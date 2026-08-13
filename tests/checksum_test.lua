-- ============================================================================
-- tests/checksum_test.lua -- Ebene B: Pruefsumme des Desync-Detektors (M3-03)
--
-- `04_NETCODE_SPEC` §9, ADR-018. Geprueft wird die Eigenschaft, an der der
-- Detektor steht oder faellt: Er darf nicht grundlos anschlagen. Ein
-- Detektor, der zweimal falsch meldet, wird ab dem dritten Mal ignoriert --
-- dann ist er schlechter als keiner.
--
-- Das Packen selbst braucht `love.data` und wird in `tests/protocol_test.lua`
-- geprueft. Hier laeuft nur, was love-frei ist.
-- ============================================================================

local Checksum = require("src.net.checksum")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local function assertEq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: erwartet %s, war %s",
            what or "Wert", tostring(expected), tostring(actual)), 2)
    end
end
local function assertTrue(v, what) assertEq(not not v, true, what) end

case("gleiche Bytes, gleicher Hash", function()
    local data = "\1\2\3VLYD\255\0\0"
    assertEq(Checksum.ofBytes(data), Checksum.ofBytes(data), "zweimal dasselbe")
end)

case("ein einziges gekipptes Bit faellt auf", function()
    -- Das ist der Fall, den der Detektor finden soll: zwei Rechner mit
    -- verschiedenen Feldlisten schreiben verschiedene Bytes.
    local a = string.rep("\0", 68) .. "\1"
    local b = string.rep("\0", 68) .. "\3"
    assertTrue(Checksum.ofBytes(a) ~= Checksum.ofBytes(b), "andere Bytes, anderer Hash")
end)

case("vertauschte Felder faellt auf", function()
    -- Zwei gleich lange Snapshots mit vertauschter Reihenfolge -- der Fall
    -- aus §10, den der Build-Hash nur warnt.
    local a = "\1\2\3\4" .. "\9\9\9\9"
    local b = "\9\9\9\9" .. "\1\2\3\4"
    assertTrue(Checksum.ofBytes(a) ~= Checksum.ofBytes(b), "Reihenfolge zaehlt")
end)

case("das Nullbyte zaehlt mit", function()
    -- Ein Hash, der bei \0 aufhoert, wuerde die halbe Nutzlast uebersehen --
    -- und der Snapshot ist voll davon.
    assertTrue(Checksum.ofBytes("\0\0\1") ~= Checksum.ofBytes("\0\0\2"),
        "hinter dem Nullbyte wird weitergerechnet")
    assertTrue(Checksum.ofBytes("\0") ~= Checksum.ofBytes("\0\0"),
        "die Laenge zaehlt mit")
end)

case("der Hash bleibt in 32 Bit", function()
    -- Sonst passt er nicht in das `I4`-Feld der Nachricht (0x60) und die
    -- Gegenseite liest etwas anderes, als gesendet wurde.
    local data = string.rep("\255", 72)
    local h = Checksum.ofBytes(data)
    assertTrue(h >= 0 and h < 4294967296, "im Wertebereich: " .. tostring(h))
    assertEq(math.floor(h), h, "ganzzahlig")
end)

case("die leere Zeichenkette ist der Startwert", function()
    assertEq(Checksum.ofBytes(""), 5381, "djb2-Startwert")
end)

case("gerechnet wird alle 30 Ticks", function()
    assertEq(Checksum.INTERVAL, 30, "§9: alle 30 Ticks")
    assertTrue(Checksum.due(0), "Tick 0")
    assertTrue(Checksum.due(30), "Tick 30")
    assertTrue(Checksum.due(600), "Tick 600")
    assertEq(Checksum.due(29), false, "Tick 29 nicht")
    assertEq(Checksum.due(31), false, "Tick 31 nicht")
    assertEq(Checksum.due(nil), false, "und nichts ist kein Tick")
end)

return T
