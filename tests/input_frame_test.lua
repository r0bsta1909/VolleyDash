-- ============================================================================
-- tests/input_frame_test.lua -- Ebene B: InputFrame und Doppeltipp-Erkennung
--
-- Verlangt von ADR-014: "Die Doppeltipp-Erkennung ist ausserhalb der
-- Referenz-Rallyes und braucht einen eigenen Unit-Test in M0-06."
-- Faelle nach 13_INPUTFRAME_FORMAT section 4.
--
-- Reines Lua, kein love. Laeuft ueber tests/run_headless.lua.
-- ============================================================================

local Frame       = require("src.input.frame")
local LocalSource = require("src.input.local_source")

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

-- ---------------------------------------------------------------------------
-- Bitmaske
-- ---------------------------------------------------------------------------

case("Bitwerte sind kanonisch", function()
    assertEq(Frame.LEFT, 1, "left")
    assertEq(Frame.RIGHT, 2, "right")
    assertEq(Frame.JUMP, 4, "jump")
    assertEq(Frame.SMASH, 8, "smash")
    assertEq(Frame.DASH, 16, "dash")
end)

case("encode/decode ueber alle 32 Kombinationen", function()
    for bits = 0, 31 do
        assertEq(Frame.encode(Frame.decode(bits)), bits, "Rundlauf " .. bits)
    end
end)

case("left + jump ergibt 5", function()
    assertEq(Frame.encode({ left = true, jump = true }), 5)
end)

case("reservierte Bits sind ungueltig", function()
    assertTrue(Frame.isValid(0), "0")
    assertTrue(Frame.isValid(31), "31")
    assertFalse(Frame.isValid(32), "32 = Bit 5")
    assertFalse(Frame.isValid(255), "255")
    assertFalse(Frame.isValid(-1), "negativ")
    assertFalse(Frame.isValid(1.5), "gebrochen")
end)

case("beide Richtungen ergeben links, nicht Stillstand", function()
    assertEq(Frame.moveDir(Frame.LEFT), -1, "nur links")
    assertEq(Frame.moveDir(Frame.RIGHT), 1, "nur rechts")
    assertEq(Frame.moveDir(Frame.LEFT + Frame.RIGHT), -1, "beide (ADR-014 section 5)")
    assertEq(Frame.moveDir(0), 0, "keine")
end)

case("pressed erkennt nur die steigende Flanke", function()
    assertTrue(Frame.pressed(Frame.JUMP, 0, Frame.JUMP), "0 -> 1")
    assertFalse(Frame.pressed(Frame.JUMP, Frame.JUMP, Frame.JUMP), "gehalten")
    assertFalse(Frame.pressed(0, Frame.JUMP, Frame.JUMP), "losgelassen")
end)

-- ---------------------------------------------------------------------------
-- Doppeltipp-Erkennung (13_INPUTFRAME_FORMAT section 4)
--
-- WINDOW ist dashWindow (0,20 s) * TICK_RATE (60) = 12 Ticks.
-- ---------------------------------------------------------------------------

local WINDOW = 12

-- Spielt eine Bitfolge ab und gibt die Ticks zurueck, in denen ein Dash fiel.
local function play(sequence)
    local det = LocalSource.TapDetector.new()
    local fired = {}
    for i, bits in ipairs(sequence) do
        if det:update(bits, WINDOW) then fired[#fired + 1] = i end
    end
    return fired
end

-- Baut eine Folge: tap[i] = Tick, in dem die Taste anliegt. Alle anderen leer.
local function taps(length, mask, ticks)
    local seq = {}
    for i = 1, length do seq[i] = 0 end
    for _, tick in ipairs(ticks) do seq[tick] = mask end
    return seq
end

case("zwei Tipps innerhalb des Fensters: genau ein Dash, beim zweiten Tipp", function()
    local fired = play(taps(20, Frame.LEFT, { 1, 5 }))
    assertEq(#fired, 1, "Anzahl Dashes")
    assertEq(fired[1], 5, "Tick des Dash")
end)

case("zwei Tipps am Rand des Fensters loesen noch aus", function()
    local fired = play(taps(30, Frame.RIGHT, { 1, 1 + WINDOW }))
    assertEq(#fired, 1, "genau am Fensterrand")
end)

case("zwei Tipps ausserhalb des Fensters: kein Dash", function()
    local fired = play(taps(40, Frame.LEFT, { 1, 2 + WINDOW }))
    assertEq(#fired, 0, "einen Tick zu spaet")
end)

case("drei Tipps innerhalb des Fensters: genau ein Dash", function()
    local fired = play(taps(20, Frame.LEFT, { 1, 4, 7 }))
    assertEq(#fired, 1, "kein zweiter Dash aus Tipp 2->3")
    assertEq(fired[1], 4, "Tick des Dash")
end)

case("vier Tipps ergeben zwei Dashes", function()
    local fired = play(taps(30, Frame.LEFT, { 1, 4, 7, 10 }))
    assertEq(#fired, 2, "Paare, nicht Ketten")
    assertEq(fired[1], 4)
    assertEq(fired[2], 10)
end)

case("zwei verschiedene Richtungen: kein Dash", function()
    local seq = taps(20, Frame.LEFT, { 1 })
    seq[5] = Frame.RIGHT
    assertEq(#play(seq), 0, "links dann rechts")
end)

case("gehaltene Taste ist ein Tipp, kein Doppeltipp", function()
    local seq = {}
    for i = 1, 20 do seq[i] = Frame.LEFT end
    assertEq(#play(seq), 0, "20 Ticks gehalten")
end)

case("Aufwaerts-Dash: Doppeltipp auf jump", function()
    local fired = play(taps(20, Frame.JUMP, { 2, 6 }))
    assertEq(#fired, 1, "jump zaehlt als Dash-Taste")
    assertEq(fired[1], 6)
end)

case("Richtung und Sprung stoeren sich nicht", function()
    -- links gehalten, waehrenddessen zweimal gesprungen
    local seq = {}
    for i = 1, 20 do seq[i] = Frame.LEFT end
    seq[3] = Frame.LEFT + Frame.JUMP
    seq[7] = Frame.LEFT + Frame.JUMP
    local fired = play(seq)
    assertEq(#fired, 1, "der Sprung-Doppeltipp zaehlt")
    assertEq(fired[1], 7)
end)

case("reset loescht die Tipphistorie", function()
    local det = LocalSource.TapDetector.new()
    det:update(Frame.LEFT, WINDOW)
    det:update(0, WINDOW)
    det:reset()
    assertFalse(det:update(Frame.LEFT, WINDOW), "nach reset kein Dash")
end)

case("die Erkennung fragt nicht nach dashCooldown", function()
    -- ADR-014: die Quelle meldet "Dash jetzt", die Simulation entscheidet, ob
    -- er zulaessig ist. Der Detektor kennt den Cooldown gar nicht -- er hat
    -- keinen Parameter dafuer.
    local fired = play(taps(20, Frame.LEFT, { 1, 3 }))
    assertEq(#fired, 1, "unabhaengig vom Simulationszustand")
end)

return T
