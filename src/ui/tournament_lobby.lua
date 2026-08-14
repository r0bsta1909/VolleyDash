-- ============================================================================
-- src/ui/tournament_lobby.lua -- Bedienung des Turniermodus (M4-07, M4-11)
--
-- `05_TOURNAMENT` §9, §10. Zustandsmaschine, kein Bild -- love-frei und
-- headless pruefbar, genau wie `src/ui/menu.lua`. Gezeichnet wird das Ergebnis
-- in `src/render/bracket_view.lua`.
--
-- Drei Bildschirme, weil es drei Lagen gibt:
--
--   resume   Beim Betreten liegt ein laufendes Turnier in der Datei (§7).
--            Diese Frage kommt VOR allem anderen -- wer sie uebergeht, legt
--            versehentlich ein zweites Turnier an und hat den Abend verloren.
--   setup    Anmeldung, Format, Setzung. Endet mit der Auslosung.
--   run      Das laufende Turnier. Zwei Ansichten (F2): kompakt fuer den
--            Spieler, voll fuer den Beamer (§10).
--   manage   Die gespeicherten Turniere (AP-1, CC-06). Jedes angelegte
--            Turnier liegt als Datei im Save-Ordner -- auch nie ausgeloste
--            und laengst abgeschlossene. Hier werden sie geloescht, mit
--            Sicherheitsabfrage (`J` bestaetigt) und bewusst NICHT auf
--            demselben Tastenweg wie "Teilnehmer streichen" (ENTF ohne
--            Rueckfrage): Die Datei ist die Versicherung aus §7, und ein
--            Loeschweg, den man versehentlich trifft, ist schlimmer als
--            eine volle Platte.
--
-- ---------------------------------------------------------------------------
-- Warum die Bedienung in der VOLLEN Ansicht sitzt
-- ---------------------------------------------------------------------------
--
-- Die kompakte Ansicht ist der Bildschirm eines Spielers: eigene Linie,
-- naechster Gegner, Restzeit. Ein Spieler soll dort kein Ergebnis eintragen
-- koennen -- das Ergebnis kommt vom Match-Host aus dem Simulationszustand
-- (E-08), und solange es das in Stufe B noch nicht gibt, kommt es vom
-- Turnierleiter. Der sitzt an der vollen Ansicht.
-- ============================================================================

local Model   = require("src.tournament.model")
local Session = require("src.tournament.session")

local TL = {}
TL.__index = TL

TL.MESSAGE_SECONDS = 4

-- Wie lange eine Meldung stehen bleibt, bevor sie verschwindet: lange genug
-- zum Lesen, kurz genug, um nicht ueber dem naechsten Aufruf zu haengen.

function TL.new(ctx)
    local self = setmetatable({
        ctx     = ctx,
        mode    = "setup",
        view    = "compact",
        panel   = "matches",
        sel     = 1,
        editing = nil,
        dialog  = nil,
        message = nil,
        messageUntil = 0,
    }, TL)

    local running = ctx.running or {}
    if ctx.readOnly then
        -- Ein Teilnehmer richtet nichts ein. Bis der Turnierstand da ist, hat
        -- er nichts anzuzeigen -- und die Einrichtungsseite waere nicht nur
        -- falsch, sondern unbedienbar: Sie liest eine Konfiguration, die es
        -- vor dem ersten Log-Ereignis noch gar nicht gibt (M4-09).
        self.mode = "wait"
    elseif #running > 0 then
        self.mode = "resume"
        self.running = running
    elseif ctx.session and not ctx.session:isSetup() then
        self:enterRun()
    end
    -- Der Cursor stand hier bis M4-09 sofort im Namensfeld -- der erste
    -- Handgriff eines Turniers war ja das Tippen von zwanzig Namen. Seit die
    -- Teilnehmer sich ueber das Netz anmelden, ist das falsch: Man landet in
    -- einer Eingabe, die man nicht braucht, und kommt an die Einstellungen
    -- erst ueber ESC. Der Cursor steht jetzt auf der ersten Einstellung.
    return self
end

function TL:now()
    return self.ctx.now and self.ctx.now() or 0
end

function TL:say(text)
    self.message = text
    self.messageUntil = self:now() + TL.MESSAGE_SECONDS
end

function TL:currentMessage()
    if self.message and self:now() < self.messageUntil then return self.message end
    return nil
end

function TL:session()
    return self.ctx.session
end

-- ---------------------------------------------------------------------------
-- Bildschirm 1: Wiederaufnahme (§7)
-- ---------------------------------------------------------------------------

function TL:resumeItems()
    local items = {}
    for _, entry in ipairs(self.running or {}) do
        items[#items + 1] = {
            kind  = "resume",
            id    = entry.id,
            label = string.format("%s fortsetzen  (Runde %s von %s)",
                entry.name or entry.id, tostring(entry.round), tostring(entry.rounds)),
            note  = entry.source == "bak"
                    and "aus der Sicherungsdatei -- das letzte Ereignis kann fehlen" or nil,
        }
    end
    items[#items + 1] = { kind = "new",  label = "Neues Turnier anlegen" }
    if self.ctx.savedList then
        items[#items + 1] = { kind = "manage", label = "Gespeicherte Turniere verwalten" }
    end
    items[#items + 1] = { kind = "back", label = "Zurueck" }
    return items
end

-- ---------------------------------------------------------------------------
-- Bildschirm 4: gespeicherte Turniere (AP-1, CC-06)
-- ---------------------------------------------------------------------------

-- Was der Mensch statt der rohen Statuskennung liest.
TL.SAVED_STATUS = {
    setup    = "nie gestartet",
    running  = "laeuft",
    finished = "abgeschlossen",
    aborted  = "abgebrochen",
}

function TL:manageItems()
    local items = {}
    for _, e in ipairs(self.ctx.savedList and self.ctx.savedList() or {}) do
        local status = TL.SAVED_STATUS[e.status] or tostring(e.status)
        if e.status == Model.TOURNAMENT_STATUS.RUNNING and e.round then
            status = string.format("laeuft, Runde %s von %s",
                tostring(e.round), tostring(e.rounds))
        end
        items[#items + 1] = {
            kind   = "saved",
            id     = e.id,
            label  = e.name or e.id,
            status = status,
            -- Das Datum gehoert zur Liste (CC-06 §2): Nach drei LAN-Abenden
            -- heissen alle Turniere gleich, und die Uhrzeit ist dann das
            -- einzige Merkmal, an dem man das richtige erkennt.
            when   = (e.createdAt and e.createdAt > 0)
                     and os.date("%d.%m.%Y %H:%M", e.createdAt) or "",
            loaded = e.loaded or false,
        }
    end
    items[#items + 1] = { kind = "back", label = "Zurueck" }
    return items
end

function TL:enterManage()
    self.manageFrom, self.manageSel = self.mode, self.sel
    self.mode, self.sel = "manage", 1
end

function TL:leaveManage()
    self.mode = self.manageFrom or "setup"
    self.sel  = self.manageSel or 1
    self.manageFrom, self.manageSel = nil, nil
end

function TL:manageKey(key)
    local items = self:manageItems()
    if key == "up"     then self:move(items, -1) return true end
    if key == "down"   then self:move(items, 1)  return true end
    if key == "escape" then self:leaveManage()   return true end
    if key ~= "return" and key ~= "kpenter" and key ~= "delete" then return true end

    local item = items[self.sel]
    if not item then return true end
    if item.kind == "back" then self:leaveManage() return true end

    if item.loaded then
        -- Das geoeffnete Turnier schreibt sich nach jedem Ereignis selbst
        -- wieder auf die Platte (§7) -- eine geloeschte Datei stuende nach
        -- dem naechsten Ereignis wieder da und haette nur die Sicherung
        -- gekostet. Also gar nicht erst anbieten.
        self:say("Dieses Turnier ist gerade geoeffnet")
        return true
    end

    self.dialog = { kind = "delete", id = item.id,
                    label = item.label, status = item.status, when = item.when }
    return true
end

-- ---------------------------------------------------------------------------
-- Bildschirm 2: Anmeldung und Setzung (§9)
-- ---------------------------------------------------------------------------

local function cycle(list, current, direction)
    local index = 1
    for i, name in ipairs(list) do if name == current then index = i end end
    return list[((index - 1 + direction) % #list) + 1]
end

-- Reihenfolge: erst die Einstellungen, dann der Start, dann die Teilnehmer.
--
-- Bis M4-09 stand die Anmeldung oben, weil der Turnierleiter zwanzig Namen
-- tippen musste. Seit die Teilnehmer sich ueber das Netz anmelden, ist das
-- Tippen der Notbetrieb -- und die Einstellungen lagen damit hinter der
-- gesamten Namensliste. Am Abend des 2026-08-13 gemeldet: "erst ESC druecken
-- und mit der Pfeiltaste durch alle Namen nach unten" (C-T-15). Jetzt sind
-- Format, Setzung und Start in fuenf Tastendruecken erreichbar, egal wie viele
-- schon dabei sind.
function TL:setupItems()
    local s = self:session()
    local items = {}

    items[#items + 1] = {
        kind  = "format",
        label = "Format",
        cycle = true,
        value = Session.FORMAT_LABEL[s.t.config.format] or s.t.config.format,
    }
    items[#items + 1] = {
        kind  = "parallel",
        label = "Parallele Matches",
        cycle = true,
        value = tostring(s.t.config.parallelMatches),
    }
    items[#items + 1] = {
        kind  = "seedmode",
        label = "Setzung",
        cycle = true,
        value = Session.SEED_LABEL[s.seedMode] or s.seedMode,
    }
    if s.seedMode == "random" then
        -- Die Zahl steht nur daneben, wenn sie nicht ohnehin schon der Text
        -- ist: "113355 (113355)" beantwortet keine Frage.
        local shown = tostring(s.seedValue)
        local number = s:seedNumber()
        if shown ~= tostring(number) then
            shown = string.format("%s   (%d)", shown, number)
        end
        items[#items + 1] = {
            kind  = "seed",
            label = "Seed",
            edit  = "seed",
            value = shown,
        }
    end

    local ok, why = s:canDraw()
    items[#items + 1] = {
        kind    = "draw",
        label   = "Auslosen und starten",
        blocked = not ok,
        note    = why,
    }

    -- Darunter die Anmeldung. Der Zusatz "von Hand" ist kein Schmuck: Wer
    -- ueber das Netz beitritt, taucht hier von allein auf, und ohne den Zusatz
    -- sieht das Feld nach dem Weg aus, den alle gehen muessten.
    items[#items + 1] = { kind = "add", label = "Teilnehmer von Hand eintragen",
                          edit = "add" }

    for _, pid in ipairs(s:activeIds()) do
        local p = s.t.participants[pid]
        items[#items + 1] = { kind = "participant", pid = pid, label = p.name }
    end

    if self.ctx.savedList then
        items[#items + 1] = { kind = "manage", label = "Gespeicherte Turniere" }
    end
    items[#items + 1] = { kind = "back", label = "Zurueck ins Menue" }
    return items
end

-- ---------------------------------------------------------------------------
-- Bildschirm 3: das laufende Turnier
-- ---------------------------------------------------------------------------

function TL:list()
    local s = self:session()
    if self.panel == "participants" then
        local out = {}
        for _, pid in ipairs(s.t.participantOrder) do
            out[#out + 1] = s.t.participants[pid]
        end
        -- Nach Setznummer, nicht nach Anmeldereihenfolge: Am Beamer sucht man
        -- jemanden in einer Liste von zwanzig, und die Setznummer steht
        -- daneben. Vor der Auslosung gibt es keine -- dann bleibt es die
        -- Reihenfolge der Anmeldung.
        table.sort(out, function(a, b)
            local sa, sb = a.seed or math.huge, b.seed or math.huge
            if sa ~= sb then return sa < sb end
            return a.id < b.id
        end)
        return out
    end
    return s:operationList()
end

function TL:selected()
    local list = self:list()
    if #list == 0 then return nil end
    if self.sel > #list then self.sel = #list end
    if self.sel < 1 then self.sel = 1 end
    return list[self.sel]
end

-- Was ENTER auf der Auswahl tut. Steht als Text in der Fusszeile: Eine
-- Bedienung, die man raten muss, ist am Partyabend keine.
function TL:primaryAction()
    if self.panel == "participants" then return nil end
    local m = self:selected()
    if not m then return nil end
    if m.status == Model.STATUS.READY then return "start",  "Match laeuft" end
    if m.status == Model.STATUS.LIVE  then return "result", "Ergebnis eintragen" end
    if Model.TERMINAL[m.status]       then return "override", "Ergebnis korrigieren" end
    return nil
end

-- ---------------------------------------------------------------------------
-- Ergebnis- und Korrektureingabe (M4-11, E-12)
--
-- Ein Satz je Zeile, "15:12". Sobald die Saetze einen Sieger ergeben, ist die
-- Eingabe fertig -- bei Best-of-1 nach einer Zeile, bei Best-of-3 nach zwei
-- oder drei. Die Korrektur verlangt danach eine Begruendung; ohne sie nimmt
-- der Scheduler sie nicht an.
-- ---------------------------------------------------------------------------

local function parseSet(text)
    local a, b = tostring(text):match("^%s*(%d+)%s*[:%-]%s*(%d+)%s*$")
    if not a then return nil end
    return { a = tonumber(a), b = tonumber(b) }
end

TL.parseSet = parseSet

local function decide(sets)
    local a, b = 0, 0
    for _, set in ipairs(sets) do
        if set.a > set.b then a = a + 1 elseif set.b > set.a then b = b + 1 end
    end
    return a, b
end

function TL:openDialog(kind, m)
    self.dialog = { kind = kind, matchId = m.id, sets = {}, phase = "score",
                    buffer = "", reason = "" }
end

function TL:commitDialog()
    local d, s = self.dialog, self:session()
    local m = s.t.matches[d.matchId]
    local a, b = decide(d.sets)
    local winner = m.slotB
    if a > b then winner = m.slotA end

    local ok, err
    if d.kind == "override" then
        ok, err = s:override(d.matchId, d.sets, winner, d.reason,
                             self.ctx.playerName and self.ctx.playerName() or "host", self:now())
    else
        ok, err = s:enterResult(d.matchId, d.sets, self:now())
    end

    if ok then
        self.dialog = nil
        self:say(string.format("%s gewinnt", s:nameOf(winner)))
    else
        self:say(tostring(err))
    end
end

function TL:dialogKey(key)
    local d = self.dialog

    if key == "escape" then
        self.dialog = nil
        return true
    end

    -- Die Sicherheitsabfrage des Loeschens (AP-1). `J` bestaetigt -- bewusst
    -- NICHT ENTER: ENTER hat den Dialog geoeffnet, und wer zweimal schnell
    -- drueckt, haette sonst geloescht statt gefragt.
    if d.kind == "delete" then
        if key == "j" then
            local ok, err
            if self.ctx.onDelete then ok, err = self.ctx.onDelete(d.id)
            else ok, err = false, "Loeschen ist hier nicht moeglich" end
            self.dialog = nil
            if ok then
                -- Die Wiederaufnahme-Liste zieht nach: Ein geloeschtes
                -- Turnier darf beim naechsten Betreten nicht mehr angeboten
                -- werden -- das war die Haelfte der Meldung aus CC-06.
                for i = #(self.running or {}), 1, -1 do
                    if self.running[i].id == d.id then table.remove(self.running, i) end
                end
                self:say("Geloescht -- Datei und Sicherung sind weg")
            else
                self:say(tostring(err))
            end
        elseif key == "return" or key == "kpenter" then
            self:say("J loescht endgueltig -- ESC bricht ab")
        end
        return true
    end

    if key == "backspace" then
        if d.phase == "reason" then
            d.reason = d.reason:sub(1, -2)
        elseif d.buffer ~= "" then
            d.buffer = d.buffer:sub(1, -2)
        elseif #d.sets > 0 then
            table.remove(d.sets)
        end
        return true
    end

    if key ~= "return" and key ~= "kpenter" then return true end

    if d.phase == "reason" then
        if d.reason == "" then
            self:say("Eine Korrektur ohne Begruendung nimmt das Log nicht an (E-12)")
        else
            self:commitDialog()
        end
        return true
    end

    local set = parseSet(d.buffer)
    if not set then
        self:say("Satz eingeben als 15:12")
        return true
    end
    if set.a == set.b then
        self:say("Ein Satz endet nicht unentschieden")
        return true
    end

    d.sets[#d.sets + 1] = set
    d.buffer = ""

    local s = self:session()
    local m = s.t.matches[d.matchId]
    local bestOf = m.bestOf or 1
    local needed = math.floor(bestOf / 2) + 1
    local a, b = decide(d.sets)

    if a >= needed or b >= needed then
        if d.kind == "override" then
            d.phase = "reason"
        else
            self:commitDialog()
        end
    elseif #d.sets >= bestOf then
        self:say("Die Saetze ergeben keinen Sieger")
        table.remove(d.sets)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Texteingabe
-- ---------------------------------------------------------------------------

function TL:textinput(text)
    if self.dialog then
        local d = self.dialog
        if d.phase == "reason" then
            if #d.reason < 60 then d.reason = d.reason .. text end
        elseif text:match("^[%d:%-]$") and #d.buffer < 8 then
            d.buffer = d.buffer .. text
        end
        return
    end

    if self.editing then
        if #self.editing.buffer < Session.NAME_MAX then
            self.editing.buffer = self.editing.buffer .. text
        end
    end
end

function TL:beginEdit(field, initial)
    self.editing = { field = field, buffer = initial or "" }
end

function TL:commitEdit()
    local edit = self.editing
    self.editing = nil
    if not edit then return end

    local s = self:session()
    if edit.field == "add" then
        local pid, err = s:addParticipant(edit.buffer, self:now())
        if not pid then self:say(tostring(err)) end
    elseif edit.field == "seed" then
        if edit.buffer ~= "" then s:setSeed(nil, edit.buffer) end
    end
end

-- ---------------------------------------------------------------------------
-- Tasten
-- ---------------------------------------------------------------------------

function TL:keypressed(key)
    if self.dialog then return self:dialogKey(key) end

    if self.editing then
        if key == "escape" then
            self.editing = nil
        elseif key == "backspace" then
            self.editing.buffer = self.editing.buffer:sub(1, -2)
        elseif key == "return" or key == "kpenter" then
            local field = self.editing.field
            self:commitEdit()
            -- Zwanzig Namen hintereinander: Nach ENTER steht der Cursor wieder
            -- im leeren Feld. Wer dafuer jedes Mal neu ENTER druecken muss,
            -- tippt sie nicht ein, sondern schreibt sie auf einen Zettel.
            if field == "add" then self:beginEdit("add", "") end
        end
        return true
    end

    if self.mode == "wait" then
        -- Warten auf den Turnierstand. ESC ist die einzige sinnvolle Taste.
        if key == "escape" then self.ctx.onLeave() end
        return true
    end
    if self.mode == "resume" then return self:resumeKey(key) end
    if self.mode == "manage" then return self:manageKey(key) end
    if self.mode == "setup"  then return self:setupKey(key) end
    return self:runKey(key)
end

function TL:move(items, direction)
    self.sel = self.sel + direction
    if self.sel < 1 then self.sel = 1 end
    if self.sel > #items then self.sel = #items end
end

function TL:resumeKey(key)
    local items = self:resumeItems()
    if key == "up" then self:move(items, -1) return true end
    if key == "down" then self:move(items, 1) return true end
    if key == "escape" then self.ctx.onLeave() return true end
    if key ~= "return" and key ~= "kpenter" then return true end

    local item = items[self.sel]
    if not item then return true end
    if item.kind == "resume" then
        local ok, err = self.ctx.onResume(item.id)
        if ok then self:enterRun() else self:say(tostring(err)) end
    elseif item.kind == "new" then
        self.ctx.onCreate()
        self.mode, self.sel = "setup", 1
        self:beginEdit("add", "")
    elseif item.kind == "manage" then
        self:enterManage()
    else
        self.ctx.onLeave()
    end
    return true
end

function TL:enterRun()
    self.mode, self.sel, self.panel = "run", 1, "matches"
    -- Wer ausrichtet, sieht den ganzen Baum; wer mitspielt, seine eigene Linie
    -- (§10). Die Unterscheidung trifft der Name: Steht er nicht im Feld, ist
    -- der Mensch am Rechner der Turnierleiter.
    self.view = self:session():selfId() and "compact" or "full"
end

function TL:setupKey(key)
    local items = self:setupItems()
    local item = items[self.sel] or items[1]
    local s = self:session()

    if key == "escape" then self.ctx.onLeave() return true end
    if key == "up"   then self:move(items, -1) return true end
    if key == "down" then self:move(items, 1)  return true end

    if key == "left" or key == "right" then
        local dir = (key == "right") and 1 or -1
        if item.kind == "format" then
            s:setConfig({ format = cycle(Session.FORMATS, s.t.config.format, dir) })
        elseif item.kind == "parallel" then
            local n = (s.t.config.parallelMatches or 2) + dir
            if n < 1 then n = 1 end
            if n > 8 then n = 8 end
            s:setConfig({ parallelMatches = n })
        elseif item.kind == "seedmode" then
            s:setSeed(cycle(Session.SEED_MODES, s.seedMode, dir), nil)
        end
        return true
    end

    if key == "delete" or key == "backspace" then
        if item.kind == "participant" then
            s:removeParticipant(item.pid, self:now())
            local shrunk = self:setupItems()
            if self.sel > #shrunk then self.sel = #shrunk end
        end
        return true
    end

    if key ~= "return" and key ~= "kpenter" then return true end

    if item.edit then
        self:beginEdit(item.edit, item.kind == "seed" and s.seedValue or "")
    elseif item.kind == "draw" then
        local ok, err = s:drawBracket(self:now())
        if ok then self:enterRun() else self:say(tostring(err)) end
    elseif item.kind == "participant" then
        self:say("ENTF streicht den Eintrag")
    elseif item.kind == "manage" then
        self:enterManage()
    elseif item.kind == "back" then
        self.ctx.onLeave()
    end
    return true
end

function TL:runKey(key)
    local s = self:session()

    if key == "escape" then self.ctx.onLeave() return true end
    if key == "f2" then
        self.view = (self.view == "full") and "compact" or "full"
        return true
    end

    -- Bedient wird an der vollen Ansicht (siehe Kopf). Die kompakte kennt nur
    -- F2 und ESC.
    if self.view ~= "full" then return true end

    -- Export (M4-10). VOR der readOnly-Schranke: X ist rein lesend und darf
    -- jedem offenstehen -- auch dem Teilnehmer. Die Versicherung aus §7 ist
    -- mehr wert, wenn sie auf jedem Rechner liegt, und eine angeschriebene
    -- Taste, die nichts tut, laedt zum Probieren ein (C-T-14).
    if key == "x" then
        if self.ctx.onExport then self:say(tostring(self.ctx.onExport())) end
        return true
    end

    -- Ein TEILNEHMER sieht das Turnier, er fuehrt es nicht (M4-09). Er darf
    -- die volle Ansicht aufmachen -- wer neben dem Beamer sitzt, will den
    -- ganzen Baum sehen -- aber eintragen darf er nichts: Das Ergebnis kommt
    -- vom Match-Wirt (E-08), und das Log hat genau einen Schreiber (ADR-023).
    if self.ctx.readOnly then return true end

    if key == "tab" then
        self.panel = (self.panel == "matches") and "participants" or "matches"
        self.sel = 1
        return true
    end

    local items = self:list()
    if key == "up"   then self:move(items, -1) return true end
    if key == "down" then self:move(items, 1)  return true end

    local entry = self:selected()
    if not entry then return true end

    if self.panel == "participants" then
        if key == "w" then
            if entry.status == Model.PARTICIPANT_STATUS.WITHDRAWN then
                self:say(entry.name .. " ist schon ausgetragen")
            else
                s:withdraw(entry.id, self:now())
                self:say(entry.name .. " ist ausgetragen -- offene Matches gehen an den Gegner (E-04)")
            end
        end
        return true
    end

    local m = entry

    if key == "p" then
        if m.status ~= Model.STATUS.READY then
            self:say("Nur ein aufgerufenes Match hat einen Timer")
        else
            local paused = s:togglePause(m.id, self:now())
            self:say(paused and "Timer angehalten" or "Timer laeuft weiter")
        end
        return true
    end

    if key == "a" then
        if s:abortMatch(m.id, self:now()) then
            self:say("Match abgebrochen und neu angesetzt (E-06)")
        else
            self:say("Dieses Match laesst sich nicht abbrechen")
        end
        return true
    end

    if key == "e" then
        if Model.TERMINAL[m.status] then
            self:say("Fertiges Match: K korrigiert es")
        elseif not (m.slotA and m.slotB) then
            self:say("Die Paarung steht noch nicht fest")
        else
            self:openDialog("result", m)
        end
        return true
    end

    if key == "k" then
        if not Model.TERMINAL[m.status] then
            self:say("Korrigieren laesst sich nur ein fertiges Match")
        else
            self:openDialog("override", m)
        end
        return true
    end

    if key == "return" or key == "kpenter" then
        local action = self:primaryAction()
        if action == "start" then
            s:startMatch(m.id, self:now())
        elseif action == "result" then
            self:openDialog("result", m)
        elseif action == "override" then
            self:openDialog("override", m)
        end
        return true
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Klaenge (Klangliste §1)
--
-- Der Ereignisstrom der Session kommt herein, heraus geht der Name des Klangs
-- oder nichts. Getrennt von `keypressed`, weil hier nicht die Bedienung
-- entscheidet, sondern das Turnier -- und getrennt vom Abspielen, weil `love`
-- in dieser Datei nichts zu suchen hat.
--
-- Der Aufruf gilt DIR: Er spielt, wenn dein eigenes Match aufgerufen wird. Wer
-- ausrichtet und nicht mitspielt, hoert ihn fuer jedes Match -- sonst wuesste
-- er nicht, dass die Anzeige sich geaendert hat.
-- ---------------------------------------------------------------------------

function TL:soundsFor(events)
    local s = self:session()
    local out = {}
    if not s then return out end

    local me = s:selfId()
    for _, ev in ipairs(events) do
        if ev.event == "match_called" then
            local m = s.t.matches[ev.matchId]
            if m and (not me or s:involves(m, me)) then out[#out + 1] = "tournament_call" end
        elseif ev.event == "no_show_warning" then
            local m = s.t.matches[ev.matchId]
            if m and (not me or s:involves(m, me)) then out[#out + 1] = "tournament_warn" end
        elseif ev.event == "tournament_finished" then
            out[#out + 1] = "tournament_done"
        end
    end
    return out
end

return TL
