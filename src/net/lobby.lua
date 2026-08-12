-- ============================================================================
-- src/net/lobby.lua -- Slots, Ready-Status, Abgleich (M2-06, M2-07)
--
-- Reine Daten und reine Entscheidungen, kein Transport. Der Host haelt genau
-- eine Lobby; `host.lua` uebersetzt sie in `LOBBY_STATE`-Nachrichten.
--
-- Der wichtigste Teil dieser Datei ist `Lobby.compare`: DREI Pruefungen mit
-- DREI unterschiedlichen Konsequenzen (`04_NETCODE_SPEC` §5, §10). Die
-- Trennung ist kein Formalismus -- sie ist der Grund, warum am Partyabend
-- niemand raetselt:
--
--   protoVersion   harte Ablehnung schon beim Join. Eine fremde Fassung kann
--                  das Protokoll nicht lesen; alles andere waere ein Timeout
--                  ohne Erklaerung.
--   rulesetHash    das Match startet nicht. Zwei verschiedene Physiken sind
--                  kein Match, sondern zwei Spiele nebeneinander.
--   buildHash      nur Warnung. Ein kosmetischer Patch darf kein Turnier
--                  blockieren -- das waere die teuerste Sorte Korrektheit.
--
-- love-frei und headless testbar.
-- ============================================================================

local Lobby = {}
Lobby.__index = Lobby

Lobby.MAX_SLOTS = 2         -- 1v1. 2v2 ist M6 und ausdruecklich Scope-Out.
Lobby.HOST_SLOT = 1

Lobby.SEVERITY = {
    REJECT = "reject",      -- Join wird abgelehnt
    BLOCK  = "block",       -- Join geht, Match startet nicht
    WARN   = "warn",        -- nur Anzeige
}

function Lobby.new(opts)
    opts = opts or {}
    local self = setmetatable({
        lobbyName = opts.lobbyName or "Volley Dash",
        hostName  = opts.hostName or "Host",
        mode      = opts.mode or "free",
        slots     = {},
        running   = false,
    }, Lobby)

    for i = 1, Lobby.MAX_SLOTS do
        self.slots[i] = { occupied = false, ready = false, isHost = false,
                          name = "", buildHash = "", clientId = nil }
    end

    -- Der Host spielt mit (`04_NETCODE_SPEC` §2). Kein dedizierter Server.
    local host = self.slots[Lobby.HOST_SLOT]
    host.occupied  = true
    host.isHost    = true
    host.ready     = true
    host.name      = self.hostName
    host.buildHash = opts.buildHash or ""
    host.clientId  = opts.clientId

    return self
end

-- ---------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------

-- Sucht den Slot zu einer Kennung -- den HOST-Slot ausdruecklich nicht.
--
-- Gemessener Fall aus M2-10: Zwei Instanzen auf demselben Rechner teilen sich
-- die Prefs-Datei und damit die `clientId`. Der Gast wurde dadurch als
-- Rueckkehrer auf Platz 1 erkannt und uebernahm den Platz des Hosts -- die
-- Lobby zeigte danach den Namen des Gastes als Host an und blieb fuer immer
-- "nicht startbereit".
--
-- Der Host ist strukturell kein Rueckkehrer: er ist der Prozess, in dem diese
-- Lobby lebt. Verliert er die Verbindung, gibt es keine Lobby mehr (§12).
function Lobby:slotOf(clientId)
    for i, slot in ipairs(self.slots) do
        if slot.occupied and not slot.isHost and slot.clientId == clientId then
            return i
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Eindeutige Namen
--
-- Im Turnier steht der Name im Bracket, auf dem Beamer und im Ergebnis. Zwei
-- Spieler mit demselben Namen sind dort kein Schoenheitsfehler, sondern eine
-- Frage, die niemand beantworten kann: wer hat gewonnen?
--
-- Aufloesung durch Anhaengen, nicht durch Ablehnen. Ein Gast, der beim Beitritt
-- wegen seines Namens abgewiesen wird, muss zurueck ins Menue, tippen, neu
-- verbinden -- drei Schritte gegen die 90-Sekunden-Vorgabe (CLAUDE.md §3.5).
-- Der Host benennt ihn stattdessen um und sagt es ihm: der Gast sieht seinen
-- tatsaechlichen Namen in der Lobby stehen.
-- ---------------------------------------------------------------------------
function Lobby:uniqueName(wanted, exceptSlot)
    wanted = tostring(wanted or "")
    if wanted == "" then wanted = "Gast" end

    local taken = {}
    for i, slot in ipairs(self.slots) do
        if slot.occupied and i ~= exceptSlot then
            taken[slot.name:lower()] = true
        end
    end

    if not taken[wanted:lower()] then return wanted end

    -- " 2", " 3", ... Mehr als MAX_SLOTS Versuche kann es nicht geben.
    for suffix = 2, Lobby.MAX_SLOTS + 1 do
        local candidate = wanted .. " " .. suffix
        if not taken[candidate:lower()] then return candidate end
    end
    return wanted .. " " .. (Lobby.MAX_SLOTS + 2)
end

-- Gibt Slotnummer zurueck oder nil und einen Grund. Ein bereits bekannter
-- `clientId` bekommt SEINEN Slot zurueck -- das ist der Reconnect-Fall aus
-- §12 und kein Fehler.
function Lobby:claim(clientId, name, buildHash)
    local existing = self:slotOf(clientId)
    if existing then
        if name and name ~= "" then
            self.slots[existing].name = self:uniqueName(name, existing)
        end
        return existing, "reconnect"
    end

    for i, slot in ipairs(self.slots) do
        if not slot.occupied then
            slot.occupied  = true
            slot.ready     = false
            slot.isHost    = false
            slot.name      = self:uniqueName(name, i)
            slot.buildHash = buildHash or ""
            slot.clientId  = clientId
            return i, "join"
        end
    end
    return nil, "full"
end

function Lobby:release(index)
    local slot = self.slots[index]
    if not slot or slot.isHost then return false end
    slot.occupied, slot.ready, slot.name = false, false, ""
    slot.buildHash, slot.clientId = "", nil
    return true
end

function Lobby:setReady(index, ready)
    local slot = self.slots[index]
    if not slot or not slot.occupied then return false end
    slot.ready = not not ready
    return true
end

function Lobby:occupiedCount()
    local count = 0
    for _, slot in ipairs(self.slots) do
        if slot.occupied then count = count + 1 end
    end
    return count
end

-- Startbereit ist die Lobby, wenn alle Plaetze besetzt und alle bereit sind.
-- Ein einzelner Spieler kann kein Netzmatch starten -- dafuer gibt es das
-- lokale Spiel.
function Lobby:isStartable()
    if self:occupiedCount() < Lobby.MAX_SLOTS then return false end
    for _, slot in ipairs(self.slots) do
        if not slot.ready then return false end
    end
    return true
end

-- Was ueber die Leitung geht (Nachricht 0x10).
function Lobby:toMessage()
    local slots = {}
    for i, slot in ipairs(self.slots) do
        slots[i] = { occupied = slot.occupied, ready = slot.ready, isHost = slot.isHost,
                     name = slot.name, buildHash = slot.buildHash }
    end
    return { slots = slots }
end

-- ---------------------------------------------------------------------------
-- Abgleich (M2-07)
--
-- `host` und `client` sind Tabellen mit protoVersion, rulesetHash, buildHash.
-- Zurueck kommt eine Liste von Befunden, jeder mit Schwere und Klartext.
-- Leere Liste heisst: alles gleich.
-- ---------------------------------------------------------------------------

function Lobby.compare(host, client)
    local findings = {}

    if client.protoVersion ~= host.protoVersion then
        findings[#findings + 1] = {
            kind = "protoVersion", severity = Lobby.SEVERITY.REJECT,
            text = string.format(
                "Andere Protokollfassung: Host spricht %s, du sprichst %s. "
                .. "Ihr braucht dieselbe ZIP.",
                tostring(host.protoVersion), tostring(client.protoVersion)),
        }
        -- Weiter zu pruefen ist sinnlos: wer das Protokoll nicht spricht,
        -- hat auch die anderen Felder nicht verlaesslich uebertragen.
        return findings
    end

    if client.rulesetHash ~= host.rulesetHash then
        findings[#findings + 1] = {
            kind = "rulesetHash", severity = Lobby.SEVERITY.BLOCK,
            text = string.format(
                "Regelwerk weicht ab (Host %s, du %s). Das Match startet nicht.",
                tostring(host.rulesetHash), tostring(client.rulesetHash)),
        }
    end

    if client.buildHash ~= host.buildHash then
        findings[#findings + 1] = {
            kind = "buildHash", severity = Lobby.SEVERITY.WARN,
            text = string.format(
                "Unterschiedlicher Build (Host %s, du %s). Gespielt wird trotzdem.",
                tostring(host.buildHash), tostring(client.buildHash)),
        }
    end

    return findings
end

-- Hoechste Schwere in einer Befundliste, oder nil.
function Lobby.worst(findings)
    local order = { [Lobby.SEVERITY.WARN] = 1, [Lobby.SEVERITY.BLOCK] = 2,
                    [Lobby.SEVERITY.REJECT] = 3 }
    local worst, rank = nil, 0
    for _, finding in ipairs(findings or {}) do
        local r = order[finding.severity] or 0
        if r > rank then worst, rank = finding, r end
    end
    return worst
end

function Lobby.blocks(findings)
    local worst = Lobby.worst(findings)
    return worst ~= nil and worst.severity ~= Lobby.SEVERITY.WARN
end

return Lobby
