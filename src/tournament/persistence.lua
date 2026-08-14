-- ============================================================================
-- src/tournament/persistence.lua -- atomares Schreiben und Recovery (M4-06)
--
-- `05_TOURNAMENT` §7, ADR-007, ADR-020. Die EINZIGE Datei dieses Moduls, die
-- Dateien anfasst.
--
-- ---------------------------------------------------------------------------
-- Warum der Dateizugriff hier ein austauschbarer Unterbau ist
-- ---------------------------------------------------------------------------
--
-- Der wichtigste Testfall dieses Moduls ist die HALB GESCHRIEBENE Datei -- der
-- Absturz zwischen zwei Schreibvorgaengen. Mit `love.filesystem` fest
-- verdrahtet waere er nur unter LOEVE pruefbar, also genau in der Umgebung,
-- die man dafuer abschiessen muesste. Mit einem austauschbaren Unterbau ist er
-- eine Zeile im Headless-Runner.
--
-- Der Voreinstellungs-Unterbau benutzt `love.filesystem` zum Lesen und
-- Schreiben und `os` zum Umbenennen. Das ist kein Stilbruch, sondern
-- unvermeidlich:
--
--   love.filesystem KANN NICHT UMBENENNEN. Die Bibliothek hat weder `rename`
--   noch `move` (LOEVE 11.5, vollstaendige Funktionsliste geprueft). Es bleibt
--   `os.rename`, und das braucht ABSOLUTE Pfade -- die liefert
--   `love.filesystem.getSaveDirectory()`.
--
--   os.rename UEBERSCHREIBT UNTER WINDOWS NICHT. Existiert das Ziel, scheitert
--   der Aufruf mit "File exists". Unter POSIX ersetzt `rename()` das Ziel
--   atomar, unter der Windows-Laufzeit nicht. Geschrieben wird deshalb fuer
--   die strengere Plattform; das laeuft auf beiden.
--
-- Daraus folgen die vier Schritte aus §7 statt der urspruenglichen drei.
-- ============================================================================

local Json   = require("src.tournament.json")
local Model  = require("src.tournament.model")
local Export = require("src.tournament.export")

local Persistence = {}
Persistence.__index = Persistence

Persistence.DIR = "tournaments"

-- ---------------------------------------------------------------------------
-- Der Unterbau
--
-- Ein Unterbau bietet: read, write, exists, remove, rename, list, mkdir.
-- `remove` und `rename` bekommen dieselben relativen Namen wie der Rest; die
-- Umrechnung auf absolute Pfade ist Sache des Unterbaus.
-- ---------------------------------------------------------------------------

function Persistence.loveBackend()
    if not (love and love.filesystem) then return nil end

    local function absolute(name)
        return love.filesystem.getSaveDirectory() .. "/" .. name
    end

    return {
        name = "love",

        mkdir = function(dir) return love.filesystem.createDirectory(dir) end,

        exists = function(name)
            return love.filesystem.getInfo(name) ~= nil
        end,

        read = function(name)
            if not love.filesystem.getInfo(name) then return nil end
            return love.filesystem.read(name)
        end,

        write = function(name, text)
            return love.filesystem.write(name, text)
        end,

        -- Fehler wird bewusst geschluckt: Die `.bak` darf fehlen.
        remove = function(name)
            os.remove(absolute(name))
            return true
        end,

        rename = function(from, to)
            return os.rename(absolute(from), absolute(to))
        end,

        list = function(dir)
            if not love.filesystem.getInfo(dir) then return {} end
            return love.filesystem.getDirectoryItems(dir)
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

function Persistence.new(backend)
    backend = backend or Persistence.loveBackend()
    if not backend then return nil, "kein Dateizugriff verfuegbar" end
    return setmetatable({ fs = backend, writes = 0, lastError = nil }, Persistence)
end

function Persistence:paths(id)
    local base = Persistence.DIR .. "/" .. id
    return base .. ".json", base .. ".json.tmp", base .. ".json.bak"
end

-- ---------------------------------------------------------------------------
-- Schreiben -- die vier Schritte aus §7
--
-- Zwischen Schritt 3 und 4 existiert kurz KEINE `.json`. Genau dafuer ist die
-- `.bak` da: Der Lader nimmt `.json`, und wenn die fehlt oder unbrauchbar ist,
-- `.bak`. Ein Absturz in diesem Fenster kostet hoechstens das letzte
-- Log-Ereignis, nie das Turnier.
-- ---------------------------------------------------------------------------

function Persistence:save(tournament)
    local id = tournament.id
    if not id or id == "" then return false, "Turnier ohne Kennung" end

    local json, tmp, bak = self:paths(id)
    local text = Json.encode(tournament:toDocument(), true)

    self.fs.mkdir(Persistence.DIR)

    -- 1. schreiben
    local ok = self.fs.write(tmp, text)
    if not ok then
        self.lastError = "konnte " .. tmp .. " nicht schreiben"
        return false, self.lastError
    end

    -- 2. alte Sicherung weg (darf fehlen)
    self.fs.remove(bak)

    -- 3. bisherigen Stand zur Sicherung machen
    if self.fs.exists(json) then
        local moved, err = self.fs.rename(json, bak)
        if not moved then
            self.lastError = "konnte " .. json .. " nicht sichern: " .. tostring(err)
            return false, self.lastError
        end
    end

    -- 4. der neue Stand wird der gueltige
    local moved, err = self.fs.rename(tmp, json)
    if not moved then
        self.lastError = "konnte " .. tmp .. " nicht aktivieren: " .. tostring(err)
        return false, self.lastError
    end

    self.writes = self.writes + 1
    self.lastError = nil
    return true
end

-- §7: nach JEDEM Log-Ereignis, nicht nach jedem Match. Die Schreibvorgaenge
-- sind klein und selten genug, dass Sparen hier nur Risiko einbringt.
function Persistence:attach(tournament)
    tournament.onAppend = function(t) self:save(t) end
    return tournament
end

-- ---------------------------------------------------------------------------
-- Lesen
-- ---------------------------------------------------------------------------

function Persistence:readFile(path)
    local text = self.fs.read(path)
    if not text then return nil, "Datei fehlt" end

    local doc, err = Json.decode(text)
    if not doc then return nil, "kaputtes JSON: " .. tostring(err) end

    local tournament, modelErr = Model.fromDocument(doc)
    if not tournament then return nil, modelErr end
    return tournament, nil, doc
end

-- Gibt `tournament, quelle` zurueck -- `quelle` ist "json" oder "bak". Wer die
-- `.bak` bekommt, hat hoechstens das letzte Log-Ereignis verloren und sollte
-- das erfahren.
function Persistence:load(id)
    local json, _, bak = self:paths(id)

    local tournament, err = self:readFile(json)
    if tournament then return tournament, "json" end

    local fallback, bakErr = self:readFile(bak)
    if fallback then return fallback, "bak", err end

    return nil, nil, string.format("%s: %s / %s: %s", json, tostring(err), bak, tostring(bakErr))
end

-- Alle Turniere im Speicherordner, jeweils mit Kennung, Name und Status.
-- Fuer den Dialog aus §7 Schritt 1 und 2.
function Persistence:list()
    local out = {}
    for _, entry in ipairs(self.fs.list(Persistence.DIR) or {}) do
        local id = entry:match("^(.+)%.json$")
        if id then
            local tournament, source = self:load(id)
            if tournament then
                out[#out + 1] = {
                    id        = tournament.id,
                    name      = tournament.name,
                    status    = tournament.status,
                    format    = tournament.format,
                    round     = Persistence.currentRound(tournament),
                    rounds    = #tournament.rounds,
                    createdAt = tournament.createdAt,
                    source    = source,
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Persistence:running()
    local out = {}
    for _, entry in ipairs(self:list()) do
        if entry.status == Model.TOURNAMENT_STATUS.RUNNING then out[#out + 1] = entry end
    end
    return out
end

-- AP-1 (CC-06): Loeschen heisst ALLE DREI Formen loeschen. Wer nur die
-- `.json` entfernt, laesst eine `.bak` zurueck -- und `load` faellt genau
-- dorthin zurueck, das Turnier stuende beim naechsten Betreten wieder da.
-- Eine Datei, die fehlt, ist kein Fehler: `remove` schluckt das (siehe
-- Unterbau), und geloescht ist geloescht.
function Persistence:delete(id)
    if not id or id == "" then return false, "Turnier ohne Kennung" end
    local json, tmp, bak = self:paths(id)
    self.fs.remove(tmp)
    self.fs.remove(bak)
    self.fs.remove(json)
    return true
end

-- ---------------------------------------------------------------------------
-- Export (M4-10)
--
-- §7 "Zusaetzliche Absicherung": das Blatt, mit dem man weiterspielt, wenn die
-- Software versagt. Der Text kommt aus `export.lua`; hier wird nur geschrieben.
--
-- DIREKT geschrieben, ohne das tmp->bak-Verfahren von `save`: Der Export wird
-- von der Software nie zurueckgelesen, ein missglueckter wird durch den
-- naechsten Tastendruck ersetzt, und die Recovery-Quelle bleibt die `.json`.
-- Ein fester Name je Turnier -- der Export ist immer der letzte Stand, die
-- Historie traegt das append-only Log.
-- ---------------------------------------------------------------------------

function Persistence:export(session, stamp)
    local id = session.t.id
    if not id or id == "" then return nil, "Turnier ohne Kennung" end

    self.fs.mkdir(Persistence.DIR)

    local base = Persistence.DIR .. "/" .. id
    local files = {
        { name = base .. "_bracket.md",    text = Export.markdown(session, stamp) },
        { name = base .. "_statistik.csv", text = Export.csv(session) },
    }
    for _, f in ipairs(files) do
        local ok = self.fs.write(f.name, f.text)
        if not ok then
            self.lastError = "konnte " .. f.name .. " nicht schreiben"
            return nil, self.lastError
        end
    end
    return { files[1].name, files[2].name }
end

-- Die niedrigste Runde, in der noch etwas offen ist -- die Zahl aus dem
-- Dialogtext "Runde 2 von 3".
function Persistence.currentRound(tournament)
    local lowest
    for _, id in ipairs(tournament.matchOrder) do
        local m = tournament.matches[id]
        if not Model.TERMINAL[m.status] and (not lowest or m.round < lowest) then
            lowest = m.round
        end
    end
    return lowest or #tournament.rounds
end

-- ---------------------------------------------------------------------------
-- Wiederaufnahme (§7 Schritt 3 und 4)
--
-- Matches im Status `live` gehen auf `aborted` und werden neu angesetzt. Der
-- Grund ist E-06: Der Absturz des Turnier-Hosts ist nicht die Schuld eines
-- Spielers, also gibt es keinen Walkover. Bereits gespielte Saetze zaehlen.
-- ---------------------------------------------------------------------------

function Persistence.resume(tournament, now)
    local reopened = {}
    for _, id in ipairs(tournament.matchOrder) do
        local m = tournament.matches[id]
        if m.status == Model.STATUS.LIVE or m.status == Model.STATUS.READY then
            reopened[#reopened + 1] = id
        end
    end
    for _, id in ipairs(reopened) do
        tournament:append({ event = "match_aborted", matchId = id, at = now,
                            reason = "host_restart" })
    end
    return reopened
end

return Persistence
