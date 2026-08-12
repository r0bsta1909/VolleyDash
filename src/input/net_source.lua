-- ============================================================================
-- src/input/net_source.lua -- die vierte Eingabequelle (M2-03, ADR-014, B-03)
--
-- `13_INPUTFRAME_FORMAT` §3 kennt genau vier Quellen: Tastatur, Gamepad, Bot,
-- Netzwerk. Drei davon standen seit M0. Das hier ist die vierte -- und sie ist
-- absichtlich die duennste von allen.
--
-- Der ganze Aufwand steckt woanders: `input_queue.lua` entscheidet, WELCHE
-- Maske dieser Tick bekommt (Redundanz, Jitter, Repeat-Last). Hier wird sie
-- nur abgeholt. Genau das ist der Ertrag der Naht aus M0: die Simulation sieht
-- vom Netz nichts als ein Byte, wie von der Tastatur auch.
-- ============================================================================

local NetSource = {}
NetSource.__index = NetSource

-- `owner` ist der Host; er haelt je Slot einen Eingabepuffer.
function NetSource.new(slot, owner)
    return setmetatable({
        kind  = "network",
        slot  = slot,
        owner = owner,
    }, NetSource)
end

-- `window` ist das Doppeltipp-Fenster der lokalen Quellen. Das Netz braucht es
-- nicht: der Dash kommt als fertiges Bit ueber die Leitung, nicht als
-- Tastenfolge (13_INPUTFRAME_FORMAT §4).
function NetSource:poll()
    if not self.owner then return 0 end
    return self.owner:inputFor(self.slot)
end

return NetSource
