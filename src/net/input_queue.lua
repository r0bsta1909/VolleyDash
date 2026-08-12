-- ============================================================================
-- src/net/input_queue.lua -- Jitter-Puffer und Repeat-Last (M2-02)
--
-- Der Host bekommt die Eingaben des Clients ueber einen unzuverlaessigen Kanal
-- und braucht in JEDEM Tick genau eine Maske. Diese Datei entscheidet, welche.
-- Drei Regeln aus `04_NETCODE_SPEC` §7, alle drei mit Grund:
--
--   Redundanz    Jedes Paket traegt die Masken der letzten drei Ticks. Ein
--                verlorenes Paket faellt damit nicht auf (T-N-02).
--   Repeat-Last  Fehlt eine Eingabe, wird die letzte bekannte wiederholt --
--                nicht Null. Null liesse den Blob bei jedem Paketverlust
--                stehenbleiben, und genau das sieht man.
--   Jitter       Hoechstens zwei Ticks Vorrat. Laenger ist Latenz teurer als
--                eine gelegentliche Vertauschung.
--
-- love-frei und ohne Netz testbar. Das ist der Sinn der Trennung: die Regel
-- laesst sich headless pruefen, der Transport nicht.
-- ============================================================================

local Frame = require("src.input.frame")

local InputQueue = {}
InputQueue.__index = InputQueue

-- Zwei Ticks Vorrat plus der, den dieser Tick verbraucht.
InputQueue.MAX_BUFFER = 3

function InputQueue.new()
    return setmetatable({
        entries  = {},   -- aufsteigend nach tick
        last     = 0,    -- zuletzt ausgelieferte Maske (Repeat-Last)
        lastTick = -1,   -- zuletzt verbrauchter Tick; -1 heisst "noch keiner"
        received = 0,
        held     = 0,    -- Ticks, in denen wiederholt werden musste
        dropped  = 0,    -- verworfen, weil der Puffer ueberlief
        invalid  = 0,    -- Masken mit gesetztem reservierten Bit
    }, InputQueue)
end

-- Eine einzelne Maske einsortieren. Gibt true zurueck, wenn sie neu war.
function InputQueue:push(tick, mask)
    if type(tick) ~= "number" or tick <= self.lastTick then return false end

    -- 13_INPUTFRAME_FORMAT §2: verwerfen und zaehlen, nicht maskieren.
    -- Stilles Maskieren verdeckt Protokoll- und Versionsfehler.
    if not Frame.isValid(mask) then
        self.invalid = self.invalid + 1
        return false
    end

    local entries = self.entries
    for i = #entries, 1, -1 do
        if entries[i].tick == tick then return false end
        if entries[i].tick < tick then
            table.insert(entries, i + 1, { tick = tick, mask = mask })
            self.received = self.received + 1
            return true
        end
    end

    table.insert(entries, 1, { tick = tick, mask = mask })
    self.received = self.received + 1
    return true
end

-- Ein ganzes INPUT-Paket: masks[1] gehoert zu `tick`, masks[2] zu `tick-1`,
-- masks[3] zu `tick-2`. Die aelteren sind die Redundanz und schliessen die
-- Luecke eines verlorenen Pakets.
function InputQueue:pushPacket(tick, masks)
    local added = 0
    for offset = 0, 2 do
        local mask = masks[offset + 1]
        if mask ~= nil and self:push(tick - offset, mask) then added = added + 1 end
    end
    return added
end

-- Die Maske fuer diesen Tick. Zweiter Rueckgabewert sagt, ob sie frisch war --
-- der Unterschied ist die Kennzahl, die im F3-Overlay steht.
function InputQueue:consume()
    local entries = self.entries

    if #entries == 0 then
        self.held = self.held + 1
        return self.last, false
    end

    -- Ueberlauf: der Client liegt vor uns. Dann gilt der neuere Stand, die
    -- alten Masken sind bereits ueberholt.
    while #entries > InputQueue.MAX_BUFFER do
        table.remove(entries, 1)
        self.dropped = self.dropped + 1
    end

    local entry = table.remove(entries, 1)
    self.last = entry.mask
    self.lastTick = entry.tick
    return entry.mask, true
end

-- Was der Host als `ackInputTick` in den Snapshot schreibt.
function InputQueue:ackTick()
    return self.lastTick
end

-- Bei Reconnect: derselbe Slot, aber der Client faengt seine Tickzaehlung neu
-- an. Ohne das Zuruecksetzen wuerde jede Eingabe als "zu alt" verworfen.
function InputQueue:reset()
    self.entries = {}
    self.last = 0
    self.lastTick = -1
end

return InputQueue
