-- ============================================================================
-- src/tournament/model.lua -- Datenmodell und append-only Log (M4-01)
--
-- `05_TOURNAMENT` §4. love-frei.
--
-- ---------------------------------------------------------------------------
-- Die eine Bauvorschrift
-- ---------------------------------------------------------------------------
--
-- `log` ist die Wahrheit, alles andere ist abgeleitet. Das ist keine
-- Formulierung, sondern die Bauregel dieser Datei:
--
--   NICHTS ausserhalb von `applyEvent` fasst den abgeleiteten Zustand an.
--
-- Wer das einhaelt, bekommt die Absturz-Recovery aus §7 geschenkt: Der
-- Wiederaufbau ist derselbe Code wie der Normalbetrieb, nur schneller
-- abgespielt. Wer es bricht, merkt es erst nach einem Absturz -- also genau
-- dann, wenn es niemand mehr reparieren kann.
--
-- Deshalb ist der veraenderliche Teil klein gehalten. `applyEvent` setzt nur
-- Match- und Teilnehmerstatus; Slot-Aufloesung, Statistiken und Tabellen
-- werden danach vollstaendig NEU gerechnet (`recompute`). Das ist bei 48
-- Matches nichts wert an Rechenzeit und macht eine ganze Fehlerklasse
-- unmoeglich -- insbesondere die nachtraegliche Korrektur aus E-12, die
-- inkrementell gefuehrte Zaehler stillschweigend falsch machen wuerde.
--
-- Was NICHT im Log steht: der Verbindungsstatus der Teilnehmer. Er beschreibt
-- die Leitung, nicht das Turnier, und ueberlebt einen Neustart des
-- Turnier-Hosts ohnehin nicht (ADR-021). Er liegt im Scheduler.
-- ============================================================================

local Bracket = require("src.tournament.bracket")

local Model = {}
Model.__index = Model

Model.VERSION = 1

Model.STATUS = {
    PENDING  = "pending",
    READY    = "ready",
    LIVE     = "live",
    FINISHED = "finished",
    WALKOVER = "walkover",
    ABORTED  = "aborted",
    BYE      = "bye",
}

-- Ein Match ist fertig -- es taucht in keiner Ansetzung mehr auf.
Model.TERMINAL = {
    finished = true, walkover = true, bye = true,
}

Model.PARTICIPANT_STATUS = {
    ACTIVE = "active", ELIMINATED = "eliminated",
    WITHDRAWN = "withdrawn", WINNER = "winner",
}

Model.TOURNAMENT_STATUS = {
    SETUP = "setup", RUNNING = "running", FINISHED = "finished", ABORTED = "aborted",
}

Model.DEFAULT_CONFIG = {
    format          = "groups_then_elim",
    bestOfDefault   = 1,
    bestOfFinals    = 3,    -- ab Halbfinale (§2, berichtigt 2026-08-13)
    targetScore     = 15,
    deuceCap        = 21,
    thirdPlaceMatch = true,
    noShowTimeout   = 180,
    parallelMatches = 2,
    advancePerGroup = 2,
}

-- Die Felder, die den Zustand ausmachen. Was hier nicht steht, ist Laufzeit
-- und wird weder verglichen noch geschrieben.
Model.STATE_FIELDS = {
    "id", "name", "format", "status", "createdAt", "rulesetHash", "ruleset",
    "config", "participants", "participantOrder", "groups", "rounds",
    "matches", "matchOrder", "standings", "winner", "stage", "groupRounds",
    "seedMode", "seedValue", "abortReason",
}

-- ---------------------------------------------------------------------------
-- Kleinkram
-- ---------------------------------------------------------------------------

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, item in pairs(v) do out[k] = deepCopy(item) end
    return out
end

Model.deepCopy = deepCopy

local function newStats()
    return { matches = 0, wins = 0, losses = 0,
             setsWon = 0, setsLost = 0, pointsFor = 0, pointsAgainst = 0 }
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

Model.EVENTS = {
    "tournament_created", "participant_joined", "participant_withdrawn",
    "bracket_drawn", "stage_advanced", "tiebreak_added",
    "match_called", "match_started", "match_finished", "match_walkover",
    "match_bye", "match_aborted", "manual_override",
    "tournament_finished", "tournament_aborted",
}

local KNOWN_EVENT = {}
for _, name in ipairs(Model.EVENTS) do KNOWN_EVENT[name] = true end

-- ---------------------------------------------------------------------------
-- Ableiten
-- ---------------------------------------------------------------------------

local function installMatches(self, matches)
    for _, m in ipairs(matches) do
        if self.matches[m.id] then
            error("doppelte Match-Kennung " .. m.id, 0)
        end
        local record = deepCopy(m)
        record.slotA      = nil
        record.slotB      = nil
        record.status     = Model.STATUS.PENDING
        record.sets       = record.sets or {}
        record.winner     = nil
        record.loser      = nil
        record.hostClient = nil
        record.calledAt   = nil
        record.startedAt  = nil
        record.endedAt    = nil
        self.matches[m.id] = record
        self.matchOrder[#self.matchOrder + 1] = m.id
    end
end

local function installRounds(self, rounds)
    for _, r in ipairs(rounds) do
        local existing
        for _, have in ipairs(self.rounds) do
            if have.index == r.index and have.stage == r.stage then existing = have break end
        end
        if existing then
            for _, id in ipairs(r.matches) do
                existing.matches[#existing.matches + 1] = id
            end
        else
            self.rounds[#self.rounds + 1] = deepCopy(r)
        end
    end
    table.sort(self.rounds, function(a, b) return a.index < b.index end)
end

-- Slots aus den Referenzen aufloesen. Idempotent: `slotARef` bleibt, `slotA`
-- wird jedes Mal neu bestimmt. Damit ist die Reihenfolge egal, in der die
-- Vorgaengermatches fertig werden.
local function resolveSlots(self)
    -- Zweimal durchlaufen: Ein Match kann vom Ergebnis eines Matches
    -- abhaengen, das in `matchOrder` spaeter steht (Spiel um Platz 3).
    for _ = 1, 2 do
        for _, id in ipairs(self.matchOrder) do
            local m = self.matches[id]
            for _, side in ipairs({ "A", "B" }) do
                local ref = m["slot" .. side .. "Ref"]
                local kind, target = Bracket.refKind(ref)
                if kind == "participant" then
                    m["slot" .. side] = target
                elseif kind == "bye" then
                    m["slot" .. side] = nil
                elseif kind == "winner_of" then
                    local src = self.matches[target]
                    m["slot" .. side] = src and src.winner or nil
                elseif kind == "loser_of" then
                    local src = self.matches[target]
                    m["slot" .. side] = src and src.loser or nil
                end
            end
        end
    end
end

local function hasBye(m)
    return m.slotARef == Bracket.BYE or m.slotBRef == Bracket.BYE
end

Model.hasBye = hasBye

local function recomputeStats(self)
    for _, pid in ipairs(self.participantOrder) do
        self.participants[pid].stats = newStats()
    end

    for _, id in ipairs(self.matchOrder) do
        local m = self.matches[id]
        if Model.TERMINAL[m.status] and m.winner then
            for _, side in ipairs({ "A", "B" }) do
                local pid = m["slot" .. side]
                local p = pid and self.participants[pid]
                if p then p.stats.matches = p.stats.matches + 1 end
            end
            for _, set in ipairs(m.sets or {}) do
                local a, b = self.participants[m.slotA], self.participants[m.slotB]
                if a then
                    a.stats.pointsFor     = a.stats.pointsFor     + set.a
                    a.stats.pointsAgainst = a.stats.pointsAgainst + set.b
                end
                if b then
                    b.stats.pointsFor     = b.stats.pointsFor     + set.b
                    b.stats.pointsAgainst = b.stats.pointsAgainst + set.a
                end
                if set.a > set.b then
                    if a then a.stats.setsWon  = a.stats.setsWon  + 1 end
                    if b then b.stats.setsLost = b.stats.setsLost + 1 end
                elseif set.b > set.a then
                    if b then b.stats.setsWon  = b.stats.setsWon  + 1 end
                    if a then a.stats.setsLost = a.stats.setsLost + 1 end
                end
            end
            local w = self.participants[m.winner]
            if w then w.stats.wins = w.stats.wins + 1 end
            local l = m.loser and self.participants[m.loser]
            if l then l.stats.losses = l.stats.losses + 1 end
        end
    end
end

local function recomputeStandings(self)
    self.standings = {}
    if #self.groups == 0 then return end

    for gi, members in ipairs(self.groups) do
        local played = {}
        for _, id in ipairs(self.matchOrder) do
            local m = self.matches[id]
            if m.group == gi and Model.TERMINAL[m.status] and m.winner
               and m.slotA and m.slotB then
                played[#played + 1] = m
            end
        end
        self.standings[gi] = Bracket.standings(members, played)
    end
end

-- `eliminated` ist abgeleitet, nicht gesetzt: Wer kein offenes Match mehr hat,
-- ist raus -- ABER erst, wenn feststeht, dass keins mehr dazukommt.
--
-- Waehrend der Gruppenphase hat jeder irgendwann kein offenes Match mehr und
-- ist trotzdem nicht ausgeschieden; die K.o.-Matches werden erst mit
-- `stage_advanced` ausgelost. Deshalb greift die Regel erst, wenn die
-- K.o.-Phase steht oder das Turnier vorbei ist.
local function recomputeParticipantStatus(self)
    local final = (self.stage == "elim")
                  or (self.status == Model.TOURNAMENT_STATUS.FINISHED)

    local open = {}
    for _, id in ipairs(self.matchOrder) do
        local m = self.matches[id]
        if not Model.TERMINAL[m.status] then
            -- Auch ein noch unbesetzter Slot haelt seine moeglichen Bewerber
            -- im Rennen: `winner_of` ist noch nicht entschieden.
            if m.slotA then open[m.slotA] = true end
            if m.slotB then open[m.slotB] = true end
        end
    end

    for _, pid in ipairs(self.participantOrder) do
        local p = self.participants[pid]
        if p.status ~= Model.PARTICIPANT_STATUS.WITHDRAWN then
            if pid == self.winner then
                p.status = Model.PARTICIPANT_STATUS.WINNER
            elseif final and not open[pid] then
                p.status = Model.PARTICIPANT_STATUS.ELIMINATED
            else
                p.status = Model.PARTICIPANT_STATUS.ACTIVE
            end
        end
    end
end

local function recompute(self)
    resolveSlots(self)
    recomputeStats(self)
    recomputeStandings(self)
    recomputeParticipantStatus(self)
end

Model.recompute = recompute

-- ---------------------------------------------------------------------------
-- Ereignisse anwenden -- die EINZIGE Stelle, die den Zustand veraendert
-- ---------------------------------------------------------------------------

local function requireMatch(self, id)
    local m = self.matches[id]
    if not m then error("unbekanntes Match " .. tostring(id), 0) end
    return m
end

local function finishMatch(self, m, winner, at, status)
    if winner ~= m.slotA and winner ~= m.slotB then
        error(string.format("%s ist kein Teilnehmer von %s", tostring(winner), m.id), 0)
    end
    m.status  = status
    m.winner  = winner

    -- Bewusst KEIN `(winner == m.slotA) and m.slotB or m.slotA`: Bei einem
    -- Freilos ist der Gegnerslot leer, der Ausdruck faellt auf `slotA` durch --
    -- und der Freilos-Sieger stand als sein eigener Verlierer im Bracket.
    -- Folgen: eine Niederlage in der Statistik, die niemand erlitten hat, und
    -- eine `loser_of`-Referenz, die auf den Sieger zeigt (B-T-03).
    if winner == m.slotA then m.loser = m.slotB else m.loser = m.slotA end

    m.endedAt = at
end

local APPLY = {}

APPLY.tournament_created = function(self, ev)
    local t = ev.tournament or {}
    self.id          = t.id
    self.name        = t.name or "Turnier"
    self.createdAt   = t.createdAt or 0
    self.ruleset     = deepCopy(t.ruleset or {})
    self.rulesetHash = t.rulesetHash or ""

    self.config = {}
    for k, v in pairs(Model.DEFAULT_CONFIG) do self.config[k] = v end
    for k, v in pairs(t.config or {}) do self.config[k] = v end

    self.format = self.config.format
    self.status = Model.TOURNAMENT_STATUS.SETUP
end

APPLY.participant_joined = function(self, ev)
    if self.participants[ev.participantId] then
        error("Teilnehmer " .. ev.participantId .. " ist schon dabei", 0)
    end
    self.participants[ev.participantId] = {
        id     = ev.participantId,
        name   = ev.name or ev.participantId,
        seed   = nil,
        status = Model.PARTICIPANT_STATUS.ACTIVE,
        stats  = newStats(),
    }
    self.participantOrder[#self.participantOrder + 1] = ev.participantId
end

APPLY.participant_withdrawn = function(self, ev)
    local p = self.participants[ev.participantId]
    if not p then error("unbekannter Teilnehmer " .. tostring(ev.participantId), 0) end
    p.status = Model.PARTICIPANT_STATUS.WITHDRAWN
end

APPLY.bracket_drawn = function(self, ev)
    local draw = ev.draw
    self.status      = Model.TOURNAMENT_STATUS.RUNNING
    self.stage       = draw.stage
    self.groups      = deepCopy(draw.groups or {})
    self.groupRounds = draw.groupRounds
    self.seedMode    = draw.seedMode
    self.seedValue   = draw.seedValue

    for id, seed in pairs(draw.seeds or {}) do
        if self.participants[id] then self.participants[id].seed = seed end
    end

    installMatches(self, draw.matches or {})
    installRounds(self, draw.rounds or {})
end

APPLY.stage_advanced = function(self, ev)
    self.stage = ev.stage
    installMatches(self, ev.matches or {})
    installRounds(self, ev.rounds or {})
end

APPLY.tiebreak_added = function(self, ev)
    installMatches(self, ev.matches or {})
    installRounds(self, ev.rounds or {})
end

APPLY.match_called = function(self, ev)
    local m = requireMatch(self, ev.matchId)
    m.status   = Model.STATUS.READY
    m.calledAt = ev.at
end

APPLY.match_started = function(self, ev)
    local m = requireMatch(self, ev.matchId)
    m.status     = Model.STATUS.LIVE
    m.startedAt  = ev.at
    m.hostClient = ev.hostClient
end

APPLY.match_finished = function(self, ev)
    local m = requireMatch(self, ev.matchId)
    m.sets = deepCopy(ev.sets or {})
    finishMatch(self, m, ev.winner, ev.at, Model.STATUS.FINISHED)
end

APPLY.match_walkover = function(self, ev)
    local m = requireMatch(self, ev.matchId)
    m.sets   = {}
    m.reason = ev.reason
    finishMatch(self, m, ev.winner, ev.at, Model.STATUS.WALKOVER)
end

APPLY.match_bye = function(self, ev)
    local m = requireMatch(self, ev.matchId)
    m.sets = {}
    finishMatch(self, m, ev.winner, ev.at, Model.STATUS.BYE)
end

-- E-06: Der Absturz ist nicht die Schuld eines Spielers. Das Match geht zurueck
-- auf `pending` und wird neu angesetzt; bereits gespielte Saetze zaehlen.
APPLY.match_aborted = function(self, ev)
    local m = requireMatch(self, ev.matchId)
    m.status     = Model.STATUS.PENDING
    m.calledAt   = nil
    m.startedAt  = nil
    m.endedAt    = nil
    m.hostClient = nil
    -- Sieger und Verlierer MUESSEN mit weg. Ein abgebrochenes Match, das
    -- seinen alten Sieger behaelt, schiebt ihn ueber `winner_of` weiter ins
    -- Folgematch -- das Bracket liefe dann mit einem Ergebnis weiter, das
    -- gerade fuer ungueltig erklaert wurde.
    m.winner     = nil
    m.loser      = nil
    m.aborts     = (m.aborts or 0) + 1
    m.reason     = ev.reason
end

-- E-12: nur durch den Turnier-Host, mit Begruendung, im Bracket sichtbar.
APPLY.manual_override = function(self, ev)
    local m = requireMatch(self, ev.matchId)
    m.sets           = deepCopy(ev.sets or {})
    m.overridden     = true
    m.overrideReason = ev.reason
    m.overrideBy     = ev.by
    finishMatch(self, m, ev.winner, ev.at, Model.STATUS.FINISHED)
end

APPLY.tournament_finished = function(self, ev)
    self.status = Model.TOURNAMENT_STATUS.FINISHED
    self.winner = ev.winner
    local p = ev.winner and self.participants[ev.winner]
    if p then p.status = Model.PARTICIPANT_STATUS.WINNER end
end

APPLY.tournament_aborted = function(self, ev)
    self.status = Model.TOURNAMENT_STATUS.ABORTED
    self.abortReason = ev.reason
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

local function blank()
    return setmetatable({
        id = "", name = "", format = "", status = Model.TOURNAMENT_STATUS.SETUP,
        createdAt = 0, rulesetHash = "", ruleset = {}, config = {},
        participants = {}, participantOrder = {},
        groups = {}, rounds = {}, matches = {}, matchOrder = {},
        standings = {}, log = {}, winner = nil,
    }, Model)
end

function Model.applyEvent(self, ev)
    local fn = APPLY[ev.event]
    if not fn then error("unbekanntes Ereignis " .. tostring(ev.event), 0) end
    fn(self, ev)
    recompute(self)
end

-- Ein Ereignis anhaengen. Stempelt `seq`, wendet es an und meldet es an
-- `onAppend` -- dort haengt die Persistenz (§7: nach JEDEM Log-Ereignis).
function Model:append(ev)
    if not KNOWN_EVENT[ev.event] then
        error("unbekanntes Ereignis " .. tostring(ev.event), 0)
    end
    local entry = deepCopy(ev)
    entry.seq = #self.log + 1
    entry.t   = ev.t or ev.at or 0

    Model.applyEvent(self, entry)
    self.log[#self.log + 1] = entry

    if self.onAppend then self.onAppend(self, entry) end
    return entry
end

-- `opts`: id, name, createdAt, config, ruleset, rulesetHash
function Model.new(opts)
    opts = opts or {}
    local self = blank()
    self:append({
        event = "tournament_created",
        t     = opts.createdAt or 0,
        tournament = {
            id          = opts.id or ("t_" .. tostring(opts.createdAt or 0)),
            name        = opts.name,
            createdAt   = opts.createdAt or 0,
            config      = opts.config,
            ruleset     = opts.ruleset,
            rulesetHash = opts.rulesetHash,
        },
    })
    return self
end

-- Der Wiederaufbau aus §7. Derselbe Code wie der Normalbetrieb -- deshalb gibt
-- es hier nichts zu pflegen, wenn ein Ereignis dazukommt.
function Model.replay(log)
    local self = blank()
    for _, ev in ipairs(log) do
        local entry = deepCopy(ev)
        Model.applyEvent(self, entry)
        self.log[#self.log + 1] = entry
    end
    return self
end

-- ---------------------------------------------------------------------------
-- Abfragen
-- ---------------------------------------------------------------------------

function Model:match(id) return self.matches[id] end

function Model:matchList()
    local out = {}
    for i, id in ipairs(self.matchOrder) do out[i] = self.matches[id] end
    return out
end

function Model:openMatches()
    local out = {}
    for _, id in ipairs(self.matchOrder) do
        local m = self.matches[id]
        if not Model.TERMINAL[m.status] then out[#out + 1] = m end
    end
    return out
end

function Model:activeMatches()
    local n = 0
    for _, id in ipairs(self.matchOrder) do
        local s = self.matches[id].status
        if s == Model.STATUS.READY or s == Model.STATUS.LIVE then n = n + 1 end
    end
    return n
end

function Model:seedOf(pid)
    local p = self.participants[pid]
    return p and p.seed or math.huge
end

-- Der hoeher gesetzte Spieler (kleinere Setznummer). Der deterministische
-- Schlussanker aus ADR-021 -- E-15 und E-17 rufen ihn.
function Model:higherSeed(a, b)
    if a == nil then return b end
    if b == nil then return a end
    if self:seedOf(a) <= self:seedOf(b) then return a end
    return b
end

function Model:isGroupStageComplete()
    for _, id in ipairs(self.matchOrder) do
        local m = self.matches[id]
        if (m.stage == "group" or m.stage == "tiebreak")
           and not Model.TERMINAL[m.status] then
            return false
        end
    end
    return #self.groups > 0
end

-- Das letzte Match des Turniers: das Finale. Ohne K.o.-Phase (reines Round
-- Robin) gibt es keins -- dann entscheidet die Tabelle.
function Model:finalMatch()
    local best
    for _, id in ipairs(self.matchOrder) do
        local m = self.matches[id]
        if m.stage == "elim" and not m.thirdPlace then
            if not best or m.round > best.round then best = m end
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Dokument (fuer die Persistenz, ADR-020)
--
-- `log` ist der einzige Teil, den der Lader liest. `derived` steht fuer den
-- Menschen darin, der die Datei um zwei Uhr nachts aufmacht -- und dafuer,
-- dass ein Test die Behauptung "das Log ist die Wahrheit" jedes Mal nachprueft
-- statt sie zu glauben.
-- ---------------------------------------------------------------------------

function Model:stateOnly()
    local out = {}
    for _, key in ipairs(Model.STATE_FIELDS) do
        out[key] = deepCopy(self[key])
    end
    return out
end

function Model:toDocument()
    return {
        version = Model.VERSION,
        log     = deepCopy(self.log),
        derived = self:stateOnly(),
    }
end

function Model.fromDocument(doc)
    if type(doc) ~= "table" then return nil, "kein Dokument" end
    if doc.version ~= Model.VERSION then
        return nil, string.format("Dateiversion %s, erwartet %d",
            tostring(doc.version), Model.VERSION)
    end
    if type(doc.log) ~= "table" or #doc.log == 0 then return nil, "Log fehlt oder ist leer" end

    local ok, result = pcall(Model.replay, doc.log)
    if not ok then return nil, "Log nicht abspielbar: " .. tostring(result) end
    return result
end

-- ---------------------------------------------------------------------------
-- Vergleich -- die Abnahme aus AP-1
--
-- Feld fuer Feld, nicht stichprobenartig. Gibt `ok, unterschiede` zurueck;
-- jeder Unterschied ist eine Klartextzeile mit dem vollen Pfad.
-- ---------------------------------------------------------------------------

local function diffValue(path, a, b, out, depth)
    if depth > 24 then out[#out + 1] = path .. ": zu tief" return end

    if type(a) ~= type(b) then
        out[#out + 1] = string.format("%s: Typ %s gegen %s", path, type(a), type(b))
        return
    end

    if type(a) ~= "table" then
        if a ~= b then
            out[#out + 1] = string.format("%s: %s gegen %s", path, tostring(a), tostring(b))
        end
        return
    end

    local keys, seen = {}, {}
    for k in pairs(a) do if not seen[k] then seen[k] = true keys[#keys + 1] = k end end
    for k in pairs(b) do if not seen[k] then seen[k] = true keys[#keys + 1] = k end end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)

    for _, k in ipairs(keys) do
        diffValue(string.format("%s.%s", path, tostring(k)), a[k], b[k], out, depth + 1)
    end
end

function Model.diff(a, b)
    local out = {}
    local left  = getmetatable(a) == Model and a:stateOnly() or a
    local right = getmetatable(b) == Model and b:stateOnly() or b
    diffValue("t", left, right, out, 0)
    return #out == 0, out
end

return Model
