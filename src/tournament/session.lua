-- ============================================================================
-- src/tournament/session.lua -- die Laufzeit eines Turniers (M4-07)
--
-- `05_TOURNAMENT` §5, §7, §9. love-frei.
--
-- Stufe A hat entschieden (Model), gerechnet (Bracket) und angesetzt
-- (Scheduler). Was fehlte, ist der Halter: irgendjemand muss das Modell mit
-- dem Scheduler und der Persistenz zusammenspannen, die Uhr hereinreichen und
-- sagen, WAS SEIT DEM LETZTEN BLICK PASSIERT IST. Das ist diese Datei.
--
-- ---------------------------------------------------------------------------
-- Die zwei Regeln, an denen hier alles haengt
-- ---------------------------------------------------------------------------
--
-- 1. KEINE ZEIT UND KEINE HARDWARE. `tick(now)` bekommt die Zeit uebergeben,
--    genau wie der Scheduler. Damit ist der No-Show-Timer im Test in
--    Millisekunden durchspielbar, und der Aufruf-Ton haengt an einem
--    Ereignisstrom statt an einem Zeichenaufruf.
--
-- 2. DIE ANZEIGE LIEST, SIE RECHNET NICHT (CC-05_REPORT §6). Alles, was eine
--    Ansicht wissen will -- die eigene Linie, die Restzeit, wer als Naechstes
--    dran ist -- wird hier beantwortet und nicht in `bracket_view.lua`. Sonst
--    haette die Restzeit zwei Rechnungen, und die zweite waere die falsche.
--
-- ---------------------------------------------------------------------------
-- Anwesenheit
-- ---------------------------------------------------------------------------
--
-- Der Scheduler ruft ein Match erst auf, wenn BEIDE Spieler online sind (§5).
-- Woher er das weiss, ist Sache dessen, der ihn treibt:
--
--   presence = "local"   Stufe B. Es gibt kein Netz. Wer angemeldet ist, steht
--                        im Raum -- der Turnierleiter hat seinen Namen getippt.
--                        Alle Teilnehmer gelten als anwesend.
--   presence = "net"     Stufe C. Die Anwesenheit kommt aus der Verbindung;
--                        `setPresence` wird dann von aussen gerufen.
--
-- Das ist die einzige Stelle, an der Stufe B und Stufe C sich unterscheiden --
-- und sie ist ein Schalter, kein zweiter Codeweg.
-- ============================================================================

local Model       = require("src.tournament.model")
local Bracket     = require("src.tournament.bracket")
local Scheduler   = require("src.tournament.scheduler")
local Persistence = require("src.tournament.persistence")

local Session = {}
Session.__index = Session

-- `05_TOURNAMENT` §2: 4 bis 32, Auslegung 20.
Session.MIN_PARTICIPANTS = 4
Session.MAX_PARTICIPANTS = 32

-- Vorwarnung des No-Show-Timers (Klangliste §3.1). Kein Log-Ereignis: Sie
-- beschreibt keinen Turnierzustand, sondern einen Ton.
Session.WARN_SECONDS = 30

Session.NAME_MAX = 24

Session.FORMATS = { "groups_then_elim", "single_elim", "round_robin" }

Session.FORMAT_LABEL = {
    groups_then_elim = "Gruppen + K.o.",
    single_elim      = "K.o.",
    round_robin      = "Jeder gegen jeden",
}

-- `by_rating` fehlt hier mit Absicht: Der Modus steht in `bracket.lua` und
-- braucht eine Rangliste aus den Vorturnieren DESSELBEN Abends (§9). Die
-- zusammenzurechnen ist eigene Arbeit und vor dem zweiten Turnier des Abends
-- wirkungslos -- zurueckgestellt, nicht vergessen.
Session.SEED_MODES = { "random", "manual" }

Session.SEED_LABEL = {
    random = "Zufall aus sichtbarem Seed",
    manual = "Reihenfolge der Anmeldung",
}

-- ---------------------------------------------------------------------------
-- Namen
-- ---------------------------------------------------------------------------

function Session.cleanName(name)
    name = tostring(name or "")
    name = name:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #name > Session.NAME_MAX then name = name:sub(1, Session.NAME_MAX) end
    return name
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

local function wrap(t, opts)
    local self = setmetatable({
        t           = t,
        scheduler   = Scheduler.new(t, { chooseHost = opts.chooseHost }),
        persistence = opts.persistence,
        presence    = opts.presence or "local",
        selfName    = opts.selfName,
        seedMode    = t.seedMode or opts.seedMode or "random",
        seedValue   = t.seedValue or opts.seedValue or "",
        cursor      = #t.log,   -- Wasserstand des Ereignisstroms
        warned      = {},
        online      = {},
        attached    = false,
    }, Session)

    self:refreshPresence()
    return self
end

-- `opts`: id, name, createdAt, config, ruleset, rulesetHash, persistence,
--         presence, selfName, seedMode, seedValue
function Session.new(opts)
    opts = opts or {}
    local created = opts.createdAt or 0
    local t = Model.new({
        id          = opts.id or ("t_" .. tostring(math.floor(created))),
        name        = opts.name or "Turnier",
        createdAt   = created,
        config      = opts.config,
        ruleset     = opts.ruleset,
        rulesetHash = opts.rulesetHash,
    })
    return wrap(t, opts)
end

-- Ein Turnierstand, der ueber das Netz kommt (M4-09, ADR-023). Er wird
-- GELESEN, nicht gefuehrt: Der Automat laeuft beim Turnier-Wirt, die
-- Ereignisse kommen fertig herein und werden mit demselben `applyEvent`
-- abgeleitet wie bei der Recovery.
--
-- `bracket_view.lua` merkt davon nichts -- es liest aus `Session`, und was
-- sich aendert, ist die Quelle des Modells, nicht die Anzeige.
function Session.observe(t, opts)
    opts = opts or {}
    opts.presence = "net"
    local self = wrap(t, opts)
    self.readOnly = true
    self.cursor = #t.log
    return self
end

-- Ein Ereignis vom Turnier-Wirt einspielen. Gibt zurueck, ob es angewandt
-- wurde -- ein Ereignis, dessen Art diese Fassung nicht kennt (aeltere ZIP),
-- wird verworfen und gezaehlt statt halb angewandt.
function Session:applyRemote(ev)
    if not self.readOnly then return false, "kein beobachteter Stand" end
    local ok, err = pcall(function() self.t:append(ev) end)
    if not ok then return false, tostring(err) end
    return true
end

-- Wiederaufnahme aus der Datei (§7 Schritt 3 und 4). Das Turnier kommt fertig
-- rekonstruiert herein; hier wird nur wieder angespannt.
function Session.resume(t, opts, now)
    opts = opts or {}
    local self = wrap(t, opts)
    self:ensurePersistence()

    -- Matches im Status `live` oder `ready` gehen auf `pending` zurueck und
    -- werden neu angesetzt (E-06). Der Absturz ist nicht die Schuld eines
    -- Spielers.
    self.reopened = Persistence.resume(t, now or 0)
    self.cursor = #t.log
    self:advance(now or 0)
    return self
end

-- Die Datei entsteht erst, wenn es etwas zu sichern gibt. Wer das Menue nur
-- aufmacht und wieder zugeht, hinterlaesst keinen Turnierstand.
function Session:ensurePersistence()
    if self.attached or not self.persistence then return false end
    self.persistence:attach(self.t)
    self.persistence:save(self.t)
    self.attached = true
    return true
end

-- ---------------------------------------------------------------------------
-- Anwesenheit
-- ---------------------------------------------------------------------------

function Session:setPresence(pid, online)
    self.online[pid] = online and true or nil
    self.scheduler:setOnline(pid, online)
end

function Session:refreshPresence()
    if self.presence ~= "local" then return end
    for _, pid in ipairs(self.t.participantOrder) do
        local p = self.t.participants[pid]
        local here = p.status ~= Model.PARTICIPANT_STATUS.WITHDRAWN
        self:setPresence(pid, here)
    end
end

-- ---------------------------------------------------------------------------
-- Anmeldung (§9)
--
-- Der Weg nach draussen ist eine EINZIGE Funktion. In Stufe B fuellt sie die
-- Tastatur des Turnierleiters, in Stufe C das Netz -- an dieser Datei aendert
-- sich dabei nichts.
-- ---------------------------------------------------------------------------

function Session:isSetup()
    return self.t.status == Model.TOURNAMENT_STATUS.SETUP
end

function Session:activeIds()
    local out = {}
    for _, pid in ipairs(self.t.participantOrder) do
        if self.t.participants[pid].status ~= Model.PARTICIPANT_STATUS.WITHDRAWN then
            out[#out + 1] = pid
        end
    end
    return out
end

function Session:count()
    return #self:activeIds()
end

-- Zwei Spieler mit demselben Namen sind im Bracket keine Schoenheitsfrage,
-- sondern eine, die niemand beantworten kann (E-14). Aufgeloest wird durch
-- Anhaengen, nicht durch Ablehnen -- wie in der Match-Lobby (`net/lobby.lua`).
--
-- Gezaehlt werden nur die AKTIVEN Namen: Wer sich vertippt, streicht den
-- Eintrag und tippt neu -- und soll dann nicht "Anna 2" heissen, weil die
-- gestrichene Anna noch im Log steht.
function Session:uniqueName(wanted)
    wanted = Session.cleanName(wanted)
    if wanted == "" then wanted = "Gast" end

    local taken = {}
    for _, pid in ipairs(self:activeIds()) do
        taken[self.t.participants[pid].name:lower()] = true
    end
    if not taken[wanted:lower()] then return wanted end

    for suffix = 2, Session.MAX_PARTICIPANTS + 1 do
        local candidate = wanted .. " " .. suffix
        if not taken[candidate:lower()] then return candidate end
    end
    return wanted
end

-- Wiedereintritt (E-05, E-14). Zwei Wege, in dieser Reihenfolge:
--
--   1. DIESELBE `clientId` -- der Rechner ist abgestuerzt und wieder da. Der
--      sichere Fall, er braucht keine Namensregel.
--   2. DERSELBE NAME, und der Traeger ist gerade OFFLINE -- der Spieler sitzt
--      an einem anderen Rechner (E-14).
--
-- Ist der Namensvetter dagegen ONLINE, ist es kein Wiedereintritt, sondern
-- eine echte Namensgleichheit: dann haengt `uniqueName` an (`04_NETCODE` §5).
-- Das ist die einzige Lesart, unter der beide Regeln tun, wofuer sie da sind
-- -- E-14 sagt "abgelehnt", aber ein Abweisen schickt jemanden zurueck ins
-- Menue, und der Fall, den E-14 wirklich meint, ist der abwesende Namenstraeger.
function Session:findReturning(name, clientId)
    local clean = Session.cleanName(name):lower()
    for _, pid in ipairs(self:activeIds()) do
        local p = self.t.participants[pid]
        if clientId and clientId ~= 0 and p.clientId == clientId then return pid, "client" end
    end
    for _, pid in ipairs(self:activeIds()) do
        local p = self.t.participants[pid]
        if p.name:lower() == clean and not self.online[pid] then return pid, "name" end
    end
    return nil
end

function Session:addParticipant(name, now, clientId)
    if not self:isSetup() then return nil, "Das Turnier laeuft schon" end
    if self:count() >= Session.MAX_PARTICIPANTS then
        return nil, string.format("Mehr als %d Teilnehmer sind nicht vorgesehen",
            Session.MAX_PARTICIPANTS)
    end

    local clean = Session.cleanName(name)
    if clean == "" then return nil, "Leerer Name" end

    self:ensurePersistence()
    local pid = string.format("p_%02d", #self.t.participantOrder + 1)
    self.t:append({
        event = "participant_joined", at = now or 0,
        participantId = pid, name = self:uniqueName(clean), clientId = clientId,
    })
    self:setPresence(pid, true)
    return pid
end

-- Streichen vor der Auslosung. Es gibt bewusst KEIN Ereignis "wieder
-- ausgetragen": Das Log ist append-only (ADR-007), also wird der Eintrag nicht
-- entfernt, sondern zurueckgezogen -- dasselbe Ereignis wie beim Aussteiger
-- mitten im Turnier (E-04). Die Auslosung sieht ihn danach nicht mehr.
function Session:removeParticipant(pid, now)
    if not self:isSetup() then return false, "Das Turnier laeuft schon" end
    if not self.t.participants[pid] then return false, "unbekannter Teilnehmer" end
    self.t:append({ event = "participant_withdrawn", participantId = pid, at = now or 0 })
    self:setPresence(pid, false)
    return true
end

-- ---------------------------------------------------------------------------
-- Einstellungen vor der Auslosung
--
-- `config` gehoert zum Ereignis `tournament_created` und damit zum Log. Ein
-- nachtraeglich veraenderter Wert wuerde die Rekonstruktion aus §7 verfehlen:
-- Das Log saehe nach dem Neustart eine andere Konfiguration als der Lauf, der
-- es geschrieben hat. Also wird das Turnier neu angelegt und die Anmeldeliste
-- uebernommen -- solange noch nicht ausgelost ist, kostet das nichts.
-- ---------------------------------------------------------------------------

function Session:setConfig(patch)
    if not self:isSetup() then return false, "Das Turnier laeuft schon" end

    local config = {}
    for k, v in pairs(self.t.config) do config[k] = v end
    for k, v in pairs(patch) do config[k] = v end

    local names = {}
    for _, pid in ipairs(self:activeIds()) do
        names[#names + 1] = self.t.participants[pid].name
    end

    local fresh = Model.new({
        id          = self.t.id,
        name        = self.t.name,
        createdAt   = self.t.createdAt,
        config      = config,
        ruleset     = self.t.ruleset,
        rulesetHash = self.t.rulesetHash,
    })

    self.t        = fresh
    self.scheduler = Scheduler.new(fresh, { chooseHost = self.scheduler.chooseHost })
    self.cursor   = #fresh.log
    self.online   = {}
    self.attached = false

    if self.persistence then self:ensurePersistence() end
    for i, name in ipairs(names) do
        local pid = string.format("p_%02d", i)
        fresh:append({ event = "participant_joined", at = fresh.createdAt,
                       participantId = pid, name = name })
        self:setPresence(pid, true)
    end
    self.cursor = #fresh.log
    return true
end

function Session:setSeed(mode, value)
    if not self:isSetup() then return false, "Das Turnier laeuft schon" end
    if mode then self.seedMode = mode end
    if value ~= nil then self.seedValue = tostring(value) end
    return true
end

-- Ein Seed-Feld traegt Text, der Generator will eine Zahl. Beides passt nur
-- zusammen, wenn eine reine Ziffernfolge AUCH ALS ZAHL gilt: `seedNumber`
-- reicht eine Zahl unveraendert durch, ueber eine Zeichenkette laeuft dagegen
-- djb2. Ohne diese Umwandlung ergaebe die angeschriebene Zahl, wieder
-- eingetippt, ein anderes Bracket -- und ein sichtbarer Seed, der sich nicht
-- nachrechnen laesst, ist schlimmer als gar keiner (Handoff §2, F-T-05).
function Session.seedFrom(text)
    local n = tonumber(text)
    if n and n >= 0 and n == math.floor(n) then return n end
    return tostring(text or "")
end

-- Die Zahl hinter dem Seed. Sie steht in der Anzeige neben dem Text: Wer die
-- Auslosung nachrechnen will, braucht genau sie.
function Session:seedNumber()
    return Bracket.seedNumber(Session.seedFrom(self.seedValue))
end

-- ---------------------------------------------------------------------------
-- Auslosung
-- ---------------------------------------------------------------------------

function Session:canDraw()
    if not self:isSetup() then return false, "Das Turnier laeuft schon" end
    local n = self:count()
    if n < Session.MIN_PARTICIPANTS then
        return false, string.format("Mindestens %d Teilnehmer (jetzt %d)",
            Session.MIN_PARTICIPANTS, n)
    end
    if n > Session.MAX_PARTICIPANTS then
        return false, string.format("Hoechstens %d Teilnehmer (jetzt %d)",
            Session.MAX_PARTICIPANTS, n)
    end
    return true
end

function Session:drawBracket(now)
    local ok, err = self:canDraw()
    if not ok then return false, err end

    self:ensurePersistence()
    local draw = Bracket.draw(self:activeIds(), self.t.config, {
        seedMode  = self.seedMode,
        seedValue = Session.seedFrom(self.seedValue),
    })
    self.t:append({ event = "bracket_drawn", at = now or 0, draw = draw })
    self:refreshPresence()
    self:advance(now or 0)
    return true
end

-- ---------------------------------------------------------------------------
-- Bedienung (M4-11, E-02, E-04, E-06, E-12)
--
-- Alles, was der Turnierleiter tun kann, geht durch den Scheduler -- nicht am
-- Modell vorbei. Das ist keine Formsache: Nur so landet jeder Eingriff im Log
-- und damit in der Datei.
-- ---------------------------------------------------------------------------

-- Beide Spieler stehen am Rechner. In Stufe C kommt diese Bestaetigung aus der
-- Match-Lobby; hier setzt sie der Turnierleiter.
function Session:startMatch(matchId, now)
    local m = self.t.matches[matchId]
    if not m or m.status ~= Model.STATUS.READY then return false, "Match ist nicht aufgerufen" end
    self.scheduler:confirmReady(matchId, m.slotA, now)
    self.scheduler:confirmReady(matchId, m.slotB, now)
    self:advance(now)
    return true
end

-- Einzelne Bereitmeldung. In Stufe B gab es sie nicht -- der Turnierleiter
-- bestaetigte beide auf einmal. Ueber das Netz meldet sich jeder fuer sich
-- (M4-09, `MATCH_ACCEPT`), und erst wenn beide gemeldet sind, geht das Match
-- auf `live`. Das ist dieselbe Bedingung wie vorher, nur zweimal gerufen.
function Session:confirmReady(matchId, pid, now)
    local ok = self.scheduler:confirmReady(matchId, pid, now)
    if ok then self:advance(now) end
    return ok
end

-- Der Eingang fuer ein Ergebnis. In Stufe B ruft ihn die Tastatur des
-- Turnierleiters, seit M4-09 die Nachricht des Match-Hosts (E-08). `stats` ist
-- optional -- ein von Hand eingetragenes Ergebnis hat keine, und ein Ergebnis
-- ohne Statistik ist ein gueltiges Ergebnis (`05_TOURNAMENT` §11).
function Session:enterResult(matchId, sets, now, stats)
    local ok, err = self.scheduler:reportResult(matchId, sets, now, stats)
    if ok then self:advance(now) end
    return ok, err
end

function Session:override(matchId, sets, winner, reason, by, now)
    local ok, err = self.scheduler:override(matchId, sets, winner, reason, by, now)
    if ok then self:advance(now) end
    return ok, err
end

function Session:abortMatch(matchId, now)
    local ok = self.scheduler:abortMatch(matchId, "manual", now)
    if ok then self:advance(now) end
    return ok
end

function Session:withdraw(pid, now)
    if not self.t.participants[pid] then return false end
    if self:isSetup() then return self:removeParticipant(pid, now) end
    self.scheduler:withdraw(pid, now)
    self:setPresence(pid, false)
    self:advance(now)
    return true
end

function Session:isPaused(matchId)
    return self.scheduler.pausedAt[matchId] ~= nil
end

-- E-02: der einzige vorgesehene manuelle Eingriff.
function Session:togglePause(matchId, now)
    local paused = self:isPaused(matchId)
    self.scheduler:pauseNoShow(matchId, not paused, now)
    return not paused
end

-- ---------------------------------------------------------------------------
-- Der Takt
--
-- Gibt zurueck, WAS PASSIERT IST -- die neuen Log-Eintraege seit dem letzten
-- Aufruf, in ihrer Reihenfolge. Daran haengen die Klaenge und die Einblendung;
-- ohne diesen Strom muesste die Anzeige den Zustand mit ihrem eigenen Abbild
-- vergleichen und dabei denselben Fehler zweimal machen.
--
-- Eine Ausnahme ist dabei: `no_show_warning` steht NICHT im Log. Es beschreibt
-- keinen Turnierzustand, sondern einen Ton 30 s vor Ablauf des Timers -- und
-- was im Log steht, muss die Rekonstruktion ueberstehen (Kopf des Schedulers).
-- ---------------------------------------------------------------------------

-- Den Automaten laufen lassen, OHNE den Ereignisstrom zu leeren. Jeder
-- Eingriff des Turnierleiters ruft das: Wer ein Ergebnis eintraegt, loest
-- damit den Aufruf des naechsten Matches aus -- und dieser Aufruf ist genau
-- der, der einen Ton braucht. Wuerde die Bedienung den Strom selbst leeren,
-- bliebe der Ton aus, weil die Szene beim naechsten Bild nichts mehr faende.
function Session:advance(now)
    -- Ein beobachteter Turnierstand fuehrt seinen Automaten nicht (M4-09).
    -- Der laeuft beim Turnier-Wirt; hier wuerde er ein zweites Mal Ereignisse
    -- anhaengen, und ein append-only Log mit zwei Schreibern hat keine
    -- gemeinsame Reihenfolge mehr (ADR-007, ADR-023).
    if self.readOnly then return end
    self.scheduler:update(now or 0)
end

function Session:tick(now)
    now = now or 0
    if not self.readOnly then self.scheduler:update(now) end

    local events = {}
    while self.cursor < #self.t.log do
        self.cursor = self.cursor + 1
        events[#events + 1] = self.t.log[self.cursor]
    end

    for _, id in ipairs(self.t.matchOrder) do
        local m = self.t.matches[id]
        if m.status ~= Model.STATUS.READY then
            self.warned[id] = nil
        elseif not self.warned[id] and not self:isPaused(id) then
            local left = self:remaining(m, now)
            if left and left <= Session.WARN_SECONDS then
                self.warned[id] = true
                events[#events + 1] = { event = "no_show_warning", matchId = id,
                                        synthetic = true }
            end
        end
    end

    return events
end

-- ---------------------------------------------------------------------------
-- Abfragen fuer die Anzeige
-- ---------------------------------------------------------------------------

function Session:nameOf(pid)
    if not pid then return nil end
    local p = self.t.participants[pid]
    return p and p.name or pid
end

-- Verbleibende Sekunden des No-Show-Timers, oder nil. Steht der Timer, friert
-- die Restzeit auf dem Wert ein, bei dem er angehalten wurde.
function Session:remaining(m, now)
    if not m or m.status ~= Model.STATUS.READY or not m.calledAt then return nil end
    local at = self.scheduler.pausedAt[m.id] or now
    local left = self.scheduler:deadline(m) - at
    if left < 0 then left = 0 end
    return left
end

-- Die Kennung des Menschen, der an diesem Rechner sitzt -- ueber den Namen,
-- denn der ist im Turnier die Identitaet (E-14).
function Session:selfId()
    if not self.selfName or self.selfName == "" then return nil end
    local wanted = self.selfName:lower()
    for _, pid in ipairs(self.t.participantOrder) do
        if self.t.participants[pid].name:lower() == wanted then return pid end
    end
    return nil
end

function Session:involves(m, pid)
    return pid ~= nil and (m.slotA == pid or m.slotB == pid)
end

function Session:roundLabel(m)
    for _, r in ipairs(self.t.rounds) do
        if r.index == m.round and r.stage == m.stage then return r.label end
    end
    return "Runde " .. tostring(m.round)
end

function Session:scoreText(m)
    if not m.sets or #m.sets == 0 then
        if m.status == Model.STATUS.WALKOVER then return "kampflos" end
        if m.status == Model.STATUS.BYE then return "Freilos" end
        return ""
    end
    local parts = {}
    for i, set in ipairs(m.sets) do parts[i] = set.a .. ":" .. set.b end
    return table.concat(parts, "  ")
end

-- Die eigene Turnierlinie (§10): alle Matches dieses Spielers in
-- Ansetzungsfolge, dazu das naechste offene.
--
-- "Raus" und "hat kein offenes Match" sind zwei verschiedene Dinge (F-T-06):
-- Ein Halbfinalverlierer spielt um Platz 3. Beantwortet wird das ueber den
-- Teilnehmerstatus, den das Modell fuehrt -- hier wird er gelesen, nicht
-- nachgerechnet.
function Session:playerLine(pid)
    local out = { rows = {}, next = nil, status = nil, seed = nil }
    if not pid then return out end

    local p = self.t.participants[pid]
    if not p then return out end
    out.status = p.status
    out.seed   = p.seed

    for _, id in ipairs(self.t.matchOrder) do
        local m = self.t.matches[id]
        if self:involves(m, pid) then
            -- Nicht `(m.slotA == pid) and m.slotB or m.slotA`: Steht der
            -- Gegner noch nicht fest, faellt der Ausdruck durch und man ist
            -- sein eigener naechster Gegner.
            local opponent = m.slotB
            if m.slotB == pid then opponent = m.slotA end
            local row = {
                match    = m,
                label    = self:roundLabel(m),
                opponent = self:nameOf(opponent),
                score    = self:scoreText(m),
                won      = (m.winner == pid),
            }
            out.rows[#out.rows + 1] = row
            if not out.next and not Model.TERMINAL[m.status] then out.next = m end
        end
    end
    return out
end

-- Alles, was der Turnierleiter anfassen kann, in einer festen Reihenfolge:
-- erst was laeuft, dann was aufgerufen ist, dann was als Naechstes kommt, dann
-- das Erledigte. Genau diese Liste bedient die Auswahl in der vollen Ansicht.
local OPERATION_RANK = {
    live     = 1,
    ready    = 2,
    pending  = 3,
    finished = 4,
    walkover = 4,
    bye      = 5,
    aborted  = 3,
}

function Session:operationList()
    local out = {}
    for index, id in ipairs(self.t.matchOrder) do
        local m = self.t.matches[id]
        out[#out + 1] = { m = m, index = index,
                          rank = OPERATION_RANK[m.status] or 9 }
    end
    table.sort(out, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.m.round ~= b.m.round then return a.m.round < b.m.round end
        return a.index < b.index
    end)

    local list = {}
    for i, entry in ipairs(out) do list[i] = entry.m end
    return list
end

-- Die Matches, die gerade gespielt werden oder aufgerufen sind -- die Liste
-- "Jetzt spielen" am Beamer (§5).
function Session:callList()
    local out = {}
    for _, id in ipairs(self.t.matchOrder) do
        local m = self.t.matches[id]
        if m.status == Model.STATUS.READY or m.status == Model.STATUS.LIVE then
            out[#out + 1] = m
        end
    end
    return out
end

function Session:standingsOf(groupIndex)
    return self.t.standings[groupIndex]
end

-- Steht in dieser Gruppe ein Stichsatz an (E-11)?
--
-- Nicht dasselbe wie "es gibt einen Gleichstand": Vor dem ersten Spieltag
-- stehen alle gleich, und die Tabelle traegt fuer JEDE Gruppe einen
-- ungeloesten Block. Der Hinweis am Beamer darf erst erscheinen, wenn er auch
-- zutrifft -- also unter genau der Bedingung, unter der der Scheduler den
-- Stichsatz ansetzt: Gruppe durchgespielt und der Gleichstand liegt auf der
-- Trennlinie zum K.o.
function Session:tiebreakPending(groupIndex)
    local standings = self.t.standings[groupIndex]
    if not standings then return false end

    for _, id in ipairs(self.t.matchOrder) do
        local m = self.t.matches[id]
        if m.group == groupIndex and not Model.TERMINAL[m.status] then return false end
    end

    local count = (self.t.format == "round_robin") and 1
                  or (self.t.config.advancePerGroup or 2)
    return Bracket.qualifiers(standings, count) == nil
end

-- Die Runden der K.o.-Phase in Spalten, jede mit ihren Matches. Der Beamerbaum
-- zeichnet genau das ab.
function Session:elimColumns()
    local cols = {}
    for _, r in ipairs(self.t.rounds) do
        if r.stage == "elim" then
            local matches = {}
            for _, id in ipairs(r.matches) do matches[#matches + 1] = self.t.matches[id] end
            cols[#cols + 1] = { label = r.label, index = r.index, matches = matches }
        end
    end
    table.sort(cols, function(a, b) return a.index < b.index end)
    return cols
end

function Session:isFinished()
    return self.t.status == Model.TOURNAMENT_STATUS.FINISHED
end

function Session:winnerName()
    return self:nameOf(self.t.winner)
end

return Session
