-- ============================================================================
-- tests/bindings_test.lua -- Ebene B: Tastenbelegung (M0-11, GDD §7)
-- ============================================================================

local Bindings = require("src.input.bindings")
local Prefs    = require("src.app.prefs")

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

case("Vorgabe entspricht der Tabelle in GDD 7", function()
    local b = Bindings.new()
    assertEq(b[1].left, "a"); assertEq(b[1].right, "d")
    assertEq(b[1].jump, "w"); assertEq(b[1].smash, "s")
    assertEq(b[2].left, "h"); assertEq(b[2].right, "k")
    assertEq(b[2].jump, "u"); assertEq(b[2].smash, "j")
end)

case("die Vorgabe ist gueltig", function()
    assertTrue(Bindings.validate(Bindings.new()))
end)

case("der Dash hat keine eigene Taste", function()
    for _, action in ipairs(Bindings.ACTIONS) do
        assertTrue(action ~= "dash", "dash ist ein Doppeltipp, keine Taste")
    end
end)

case("eine doppelt belegte Taste wird erkannt", function()
    local b = Bindings.new()
    b[2].left = "a"   -- gehoert P1
    local ok, errors = Bindings.validate(b)
    assertFalse(ok, "muss auffallen")
    assertTrue(#errors > 0, "mit Begruendung")
end)

case("Tasten der Oberflaeche sind gesperrt", function()
    local b = Bindings.new()
    b[1].jump = "escape"
    assertFalse(Bindings.validate(b), "escape")

    local ok, err = Bindings.set(Bindings.new(), 1, "jump", "tab")
    assertFalse(ok, "set lehnt ab")
    assertTrue(err ~= nil, "mit Begruendung")
end)

case("set tauscht, statt doppelt zu belegen", function()
    local b = Bindings.new()
    -- P1 soll auf die Taste von P1 rechts springen: die Aktionen tauschen.
    assertTrue(Bindings.set(b, 1, "jump", "d"), "gesetzt")
    assertEq(b[1].jump, "d", "neue Taste")
    assertEq(b[1].right, "w", "alte Taste des Sprungs uebernommen")
    assertTrue(Bindings.validate(b), "bleibt gueltig")
end)

case("set tauscht auch ueber Spielergrenzen hinweg", function()
    local b = Bindings.new()
    assertTrue(Bindings.set(b, 1, "left", "h"), "gesetzt")
    assertEq(b[1].left, "h")
    assertEq(b[2].left, "a", "P2 bekommt die freigewordene Taste")
    assertTrue(Bindings.validate(b), "bleibt gueltig")
end)

case("Rundlauf ueber serialize und parse", function()
    local b = Bindings.new()
    Bindings.set(b, 1, "jump", "space2")
    local back = Bindings.parse(Bindings.serialize(b))
    assertTrue(back ~= nil, "geparst")
    for slot = 1, 2 do
        for _, action in ipairs(Bindings.ACTIONS) do
            assertEq(back[slot][action], b[slot][action], "P" .. slot .. " " .. action)
        end
    end
end)

case("serialize schreibt die dokumentierte Kurzform", function()
    assertEq(Bindings.serialize(Bindings.new()), "a,d,w,s|h,k,u,j")
end)

case("kaputte Zeichenketten ergeben nil, nicht halbe Belegungen", function()
    assertEq(Bindings.parse("a,d,w"), nil, "zu wenige Aktionen")
    assertEq(Bindings.parse("a,d,w,s"), nil, "nur ein Spieler")
    assertEq(Bindings.parse("a,d,w,s|h,k,u,j|x,y,z,q"), nil, "drei Spieler")
    assertEq(Bindings.parse("a,d,w,s|a,k,u,j"), nil, "doppelte Taste")
    assertEq(Bindings.parse(""), nil, "leer")
    assertEq(Bindings.parse(nil), nil, "nil")
end)

case("die Belegung liegt in den Prefs, nicht im Ruleset (ADR-005)", function()
    assertTrue(Prefs.FIELDS.bindings ~= nil, "Prefs-Feld vorhanden")
    assertEq(Prefs.DEFAULTS.bindings, "a,d,w,s|h,k,u,j", "Vorgabe")
    local back = Prefs.parse(Prefs.serialize(Prefs.new()))
    assertEq(back.bindings, "a,d,w,s|h,k,u,j", "ueberlebt Speichern und Laden")
end)

case("Gamepad: Dash liegt auf den Schultertasten (GDD 7)", function()
    assertEq(Bindings.GAMEPAD.dashLeft, "leftshoulder")
    assertEq(Bindings.GAMEPAD.dashRight, "rightshoulder")
    assertEq(Bindings.GAMEPAD.jump, "a")
    assertEq(Bindings.GAMEPAD.smash, "x")
end)

return T
