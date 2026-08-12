-- ============================================================================
-- tests/input_queue_test.lua -- Ebene B: Jitter-Puffer und Repeat-Last (M2-02)
--
-- Deckt die Regeln aus `04_NETCODE_SPEC` §7 ab und damit den Kern von T-N-02
-- (5 % Paketverlust auf Kanal 2 bleibt unsichtbar). Der Verlust selbst wird
-- hier nachgestellt, indem ein Paket schlicht nicht eingespeist wird -- dafuer
-- braucht es kein Netz.
--
-- love-frei.
-- ============================================================================

local InputQueue = require("src.net.input_queue")
local Frame      = require("src.input.frame")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local function assertEq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: erwartet %s, war %s",
            what or "Wert", tostring(expected), tostring(actual)), 2)
    end
end
local function assertTrue(v, what) assertEq(not not v, true, what) end
local function assertFalse(v, what) assertEq(not not v, false, what) end

-- Ein Paket, wie es der Client baut: die Maske dieses Ticks und die zwei davor.
local function packet(queue, tick, m0, m1, m2)
    return queue:pushPacket(tick, { m0, m1 or 0, m2 or 0 })
end

-- ---------------------------------------------------------------------------

case("Masken kommen in Tickreihenfolge heraus", function()
    local q = InputQueue.new()
    q:push(0, Frame.LEFT)
    q:push(1, Frame.RIGHT)
    q:push(2, Frame.JUMP)

    local mask, fresh = q:consume()
    assertEq(mask, Frame.LEFT, "Tick 0")
    assertTrue(fresh, "frisch")
    assertEq(q:consume(), Frame.RIGHT, "Tick 1")
    assertEq(q:consume(), Frame.JUMP, "Tick 2")
end)

case("vertauschte Reihenfolge wird einsortiert", function()
    local q = InputQueue.new()
    q:push(2, Frame.JUMP)
    q:push(0, Frame.LEFT)
    q:push(1, Frame.RIGHT)

    assertEq(q:consume(), Frame.LEFT, "Tick 0")
    assertEq(q:consume(), Frame.RIGHT, "Tick 1")
    assertEq(q:consume(), Frame.JUMP, "Tick 2")
end)

case("ohne Nachschub wird die letzte Maske wiederholt, nicht Null", function()
    local q = InputQueue.new()
    q:push(0, Frame.RIGHT)
    assertEq(q:consume(), Frame.RIGHT, "Tick 0")

    local mask, fresh = q:consume()
    assertEq(mask, Frame.RIGHT, "wiederholt")
    assertFalse(fresh, "nicht frisch")
    assertEq(q.held, 1, "held gezaehlt")

    -- Null waere hier der Fehler: der Blob bliebe bei jedem Paketverlust stehen.
    assertTrue(q:consume() ~= 0, "keine Nulleingabe")
end)

case("vor der ersten Eingabe ist die wiederholte Maske 0", function()
    local q = InputQueue.new()
    local mask, fresh = q:consume()
    assertEq(mask, 0, "Anfangswert")
    assertFalse(fresh, "nicht frisch")
end)

case("ein verlorenes Paket schliesst das naechste (T-N-02)", function()
    -- Host und Client laufen im Takt: je ein Paket, je ein Tick. Alles andere
    -- waere ein Aufstau und ein anderer Fall (siehe Ueberlauf weiter unten).
    local q = InputQueue.new()
    packet(q, 0, Frame.LEFT, 0, 0)
    assertEq(q:consume(), Frame.LEFT, "Tick 0")

    packet(q, 1, Frame.RIGHT, Frame.LEFT, 0)
    assertEq(q:consume(), Frame.RIGHT, "Tick 1")

    -- Das Paket fuer Tick 2 geht verloren. Das naechste traegt 3, 2 und 1 --
    -- die Luecke ist damit geschlossen, bevor sie jemand sieht.
    packet(q, 3, Frame.SMASH, Frame.JUMP, Frame.RIGHT)

    local mask, fresh = q:consume()
    assertEq(mask, Frame.JUMP, "Tick 2 aus der Redundanz")
    assertTrue(fresh, "nicht wiederholt, sondern rekonstruiert")
    assertEq(q.held, 0, "keine Wiederholung noetig")

    assertEq(q:consume(), Frame.SMASH, "Tick 3")
end)

case("zwei Pakete in Folge verloren -- die Redundanz reicht immer noch", function()
    local q = InputQueue.new()
    packet(q, 0, Frame.LEFT, 0, 0)
    assertEq(q:consume(), Frame.LEFT, "Tick 0")

    -- Pakete 1 und 2 verloren. Paket 3 traegt 3, 2 und 1 -- also alles.
    packet(q, 3, Frame.SMASH, Frame.JUMP, Frame.RIGHT)
    assertEq(q:consume(), Frame.RIGHT, "Tick 1 aus der Redundanz")
    assertEq(q:consume(), Frame.JUMP, "Tick 2 aus der Redundanz")
    assertEq(q:consume(), Frame.SMASH, "Tick 3")
    assertEq(q.held, 0, "keine Wiederholung noetig")
end)

case("erst der dritte Verlust in Folge kostet einen Tick", function()
    local q = InputQueue.new()
    packet(q, 0, Frame.LEFT, 0, 0)
    assertEq(q:consume(), Frame.LEFT, "Tick 0")

    -- Pakete 1, 2 und 3 verloren. Paket 4 reicht nur bis Tick 2 zurueck.
    packet(q, 4, Frame.SMASH, Frame.JUMP, Frame.RIGHT)
    assertEq(q:consume(), Frame.RIGHT, "Tick 2 -- Tick 1 fehlt endgueltig")
    assertEq(q:consume(), Frame.JUMP, "Tick 3")
    assertEq(q:consume(), Frame.SMASH, "Tick 4")

    -- Und jetzt ist nichts mehr da: Repeat-Last, nicht Null.
    local mask, fresh = q:consume()
    assertEq(mask, Frame.SMASH, "wiederholt")
    assertFalse(fresh, "nicht frisch")
end)

case("bereits verbrauchte Ticks werden nicht wieder eingespeist", function()
    local q = InputQueue.new()
    q:push(0, Frame.LEFT)
    assertEq(q:consume(), Frame.LEFT, "Tick 0")

    -- Das naechste Paket traegt Tick 0 als Redundanz erneut mit.
    packet(q, 1, Frame.RIGHT, Frame.LEFT, 0)
    assertEq(q:consume(), Frame.RIGHT, "Tick 1, nicht noch einmal Tick 0")
end)

case("ein doppelt zugestelltes Paket zaehlt einmal", function()
    local q = InputQueue.new()
    assertTrue(q:push(5, Frame.LEFT), "erstes Mal")
    assertFalse(q:push(5, Frame.RIGHT), "zweites Mal")
    assertEq(q.received, 1, "received")
    assertEq(q:consume(), Frame.LEFT, "die erste Maske gilt")
end)

case("eine Maske mit reserviertem Bit wird verworfen und gezaehlt", function()
    local q = InputQueue.new()
    assertFalse(q:push(0, 32), "Bit 5 gesetzt")
    assertFalse(q:push(1, 255), "alles gesetzt")
    assertEq(q.invalid, 2, "invalid")
    assertEq(q.received, 0, "nichts angenommen")

    -- 13_INPUTFRAME_FORMAT §2: verwerfen, nicht maskieren. Waere maskiert
    -- worden, laege hier jetzt eine gueltige Maske.
    local mask, fresh = q:consume()
    assertEq(mask, 0, "nichts angekommen")
    assertFalse(fresh, "nichts angekommen")
end)

case("laeuft der Puffer ueber, gilt der neuere Stand", function()
    local q = InputQueue.new()
    for tick = 0, 9 do q:push(tick, Frame.LEFT) end

    local mask, fresh = q:consume()
    assertTrue(fresh, "frisch")
    assertTrue(q.dropped > 0, "es wurde verworfen")
    -- Hoechstens MAX_BUFFER bleiben stehen; der Vorrat ist danach abgebaut.
    assertTrue(#q.entries < InputQueue.MAX_BUFFER + 1, "Vorrat begrenzt")
    -- Von 0..9 bleiben die letzten MAX_BUFFER stehen; verbraucht wird der
    -- aelteste davon.
    assertEq(q:ackTick(), 9 - InputQueue.MAX_BUFFER + 1, "ackTick")
end)

case("ackTick meldet den zuletzt verbrauchten Tick", function()
    local q = InputQueue.new()
    assertEq(q:ackTick(), -1, "noch keiner")
    q:push(4, Frame.LEFT)
    q:consume()
    assertEq(q:ackTick(), 4, "nach dem ersten")
    q:consume()   -- Wiederholung, kein neuer Tick
    assertEq(q:ackTick(), 4, "Wiederholung zaehlt nicht")
end)

case("reset macht den Slot fuer einen Reconnect frei", function()
    local q = InputQueue.new()
    q:push(100, Frame.LEFT)
    q:consume()
    q:reset()
    assertEq(q:ackTick(), -1, "Tickzaehlung zurueckgesetzt")
    -- Der wiederverbundene Client faengt bei 0 an; ohne reset waere alles
    -- kleiner 100 als "zu alt" verworfen worden.
    assertTrue(q:push(0, Frame.RIGHT), "Tick 0 wird wieder angenommen")
end)

return T
