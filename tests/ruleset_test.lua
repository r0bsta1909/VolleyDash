-- ============================================================================
-- tests/ruleset_test.lua -- Ebene B: Ruleset und Prefs (M0-09)
--
-- Deckt T-R-14 (kanonischer Hash) und T-R-15 (Validierung) aus
-- `07_TEST_PLAN` §3 ab, dazu die Trennung nach ADR-005 und die beiden
-- Audit-Befunde F-01 und F-02 am Prefs-Format.
-- ============================================================================

local Ruleset = require("src.sim.ruleset")
local Prefs   = require("src.app.prefs")

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
-- Presets
-- ---------------------------------------------------------------------------

case("classic hat Dash, Smash und Speed-Scaling aus (01_GDD 3.1, ADR-006)", function()
    local rs = Ruleset.new("classic")
    assertFalse(rs.allowDash, "allowDash")
    assertFalse(rs.activeSpike, "activeSpike")
    assertFalse(rs.speedScaling, "speedScaling")
end)

case("classic ist die Voreinstellung", function()
    assertEq(Ruleset.DEFAULT_PRESET, "classic")
    assertFalse(Ruleset.new().allowDash, "ohne Argument classic")
end)

case("prototype behaelt die Zahlen des Prototyps (02_CODE_AUDIT 4)", function()
    local rs = Ruleset.new("prototype")
    assertEq(rs.gravity, 1000, "gravity")
    assertEq(rs.blobGravity, 1600, "blobGravity")
    assertEq(rs.activeTransfer, 0.40, "activeTransfer")
    assertEq(rs.passiveBounce, 0.75, "passiveBounce")
    assertEq(rs.wallBounce, 0.70, "wallBounce")
    assertEq(rs.maxBallSpeed, 1400, "maxBallSpeed")
    assertEq(rs.dashWindow, 0.20, "dashWindow")
    assertEq(rs.jumpForce, -750, "jumpForce")
    assertTrue(rs.activeSpike, "activeSpike")
    assertTrue(rs.allowDash, "allowDash")
end)

case("classic und prototype unterscheiden sich nur in den Schaltern", function()
    local a, b = Ruleset.new("classic"), Ruleset.new("prototype")
    for key, field in pairs(Ruleset.FIELDS) do
        if field.type == "number" then
            assertEq(a[key], b[key], "Zahl " .. key .. " darf sich nicht unterscheiden")
        end
    end
end)

case("Presets sind gegen Aenderung von aussen geschuetzt", function()
    local rs = Ruleset.new("classic")
    rs.gravity = 42
    assertEq(Ruleset.new("classic").gravity, 1000, "Preset unveraendert")
end)

-- ---------------------------------------------------------------------------
-- T-R-14: kanonischer Hash
-- ---------------------------------------------------------------------------

case("T-R-14: gleiche Werte, andere Schluesselreihenfolge, gleicher Hash", function()
    local a = Ruleset.new("prototype")

    -- Zweites Ruleset in umgekehrter Einfuegereihenfolge aufbauen. In Lua ist
    -- die Iterationsreihenfolge von pairs nicht festgelegt -- genau davor
    -- schuetzt die kanonische Serialisierung.
    local keys = {}
    for k in pairs(a) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return x > y end)
    local b = {}
    for _, k in ipairs(keys) do b[k] = a[k] end

    assertEq(Ruleset.canonical(b), Ruleset.canonical(a), "kanonische Form")
    assertEq(Ruleset.hash(b), Ruleset.hash(a), "Hash")
end)

case("ein geaenderter Wert aendert den Hash", function()
    local a = Ruleset.new("prototype")
    local b = Ruleset.new("prototype")
    b.gravity = b.gravity + 1
    assertTrue(Ruleset.hash(a) ~= Ruleset.hash(b), "Hash muss sich unterscheiden")
end)

case("classic und prototype haben verschiedene Hashes", function()
    assertTrue(Ruleset.hash(Ruleset.new("classic")) ~= Ruleset.hash(Ruleset.new("prototype")))
end)

case("der Hash ist acht Hexstellen", function()
    local h = Ruleset.hash(Ruleset.new("classic"))
    assertEq(#h, 8, "Laenge")
    assertTrue(h:match("^%x+$") ~= nil, "nur Hexziffern")
end)

case("Prefs-Felder stehen nicht im Ruleset (ADR-005)", function()
    for _, key in ipairs({ "volume", "botLevel", "botActive" }) do
        assertEq(Ruleset.FIELDS[key], nil, key .. " gehoert in die Prefs")
    end
    -- und tauchen deshalb auch nicht im Hash auf
    local rs = Ruleset.new("classic")
    local before = Ruleset.hash(rs)
    rs.volume = 0.9
    assertEq(Ruleset.hash(rs), before, "fremde Schluessel aendern den Hash nicht")
end)

-- ---------------------------------------------------------------------------
-- T-R-15: Validierung (F-10)
-- ---------------------------------------------------------------------------

case("beide Presets sind gueltig", function()
    assertTrue(Ruleset.validate(Ruleset.new("classic")), "classic")
    assertTrue(Ruleset.validate(Ruleset.new("prototype")), "prototype")
end)

case("T-R-15: ballRadius 80 mit netHeight 350 wird abgelehnt", function()
    local rs = Ruleset.new("prototype")
    rs.ballRadius = 80
    rs.netHeight = 350
    local ok, errors = Ruleset.validate(rs)
    assertFalse(ok, "muss abgelehnt werden")
    assertTrue(#errors > 0, "mit Begruendung")
end)

case("ein unerreichbar hohes Netz wird abgelehnt", function()
    local rs = Ruleset.new("prototype")
    rs.netHeight = 350   -- Sprung + Radien reichen nur rund 260 px hoch
    assertFalse(Ruleset.validate(rs), "netHeight 350")
end)

case("Werte ausserhalb der Grenzen werden abgelehnt", function()
    local rs = Ruleset.new("prototype")
    rs.gravity = 99999
    assertFalse(Ruleset.validate(rs), "gravity")
end)

case("ein fehlendes Feld wird abgelehnt", function()
    local rs = Ruleset.new("prototype")
    rs.wallBounce = nil
    assertFalse(Ruleset.validate(rs), "wallBounce fehlt")
end)

case("clamp haelt sich an die Grenzen des Feldes", function()
    assertEq(Ruleset.clamp("ballRadius", 999), 80, "obere Grenze")
    assertEq(Ruleset.clamp("ballRadius", 0), 8, "untere Grenze")
    assertEq(Ruleset.clamp("ballRadius", 30), 30, "innerhalb")
end)

-- ---------------------------------------------------------------------------
-- Aufzeichnungen bringen ihr Regelwerk mit
-- ---------------------------------------------------------------------------

case("fromSnapshot ergaenzt fehlende Schluessel aus dem Prototyp-Preset", function()
    -- Die Referenzen entstanden, bevor es allowDash gab. Ein fehlender
    -- Schluessel darf nicht die heutige Voreinstellung erben, sonst liefe die
    -- Wiedergabe von R-09 ohne Dash.
    local rs = Ruleset.fromSnapshot({ gravity = 1000, activeSpike = true })
    assertTrue(rs.allowDash, "allowDash aus dem Prototyp-Preset")
    assertEq(rs.gravity, 1000, "uebernommener Wert")
end)

case("fromSnapshot ignoriert Schluessel, die kein Ruleset-Feld sind", function()
    local rs = Ruleset.fromSnapshot({ volume = 0.9, botLevel = 1 })
    assertEq(rs.volume, nil, "volume")
    assertEq(rs.botLevel, nil, "botLevel")
end)

-- ---------------------------------------------------------------------------
-- Prefs (F-01, F-02)
-- ---------------------------------------------------------------------------

case("Prefs-Rundlauf ueber serialize und parse", function()
    local p = Prefs.new()
    p.volume = 0.5
    p.botLevel = 2
    p.botActive = false
    local back, ok = Prefs.parse(Prefs.serialize(p))
    assertTrue(ok, "geladen")
    assertEq(back.volume, 0.5, "volume")
    assertEq(back.botLevel, 2, "botLevel")
    assertEq(back.botActive, false, "botActive")
end)

case("F-01: ohne passendes Versionsfeld gilt die Voreinstellung", function()
    local back, ok = Prefs.parse("volume=0.9\nbotLevel=1\n")
    assertFalse(ok, "nicht als geladen melden")
    assertEq(back.volume, Prefs.DEFAULTS.volume, "Voreinstellung")

    local wrong = Prefs.parse("version=99\nvolume=0.9\n")
    assertEq(wrong.volume, Prefs.DEFAULTS.volume, "fremde Version")
end)

case("F-02: unbekannte Schluessel werden verworfen", function()
    local back = Prefs.parse("version=1\ngravity=1\nevil=1\nvolume=0.5\n")
    assertEq(back.gravity, nil, "gravity gehoert nicht in die Prefs")
    assertEq(back.evil, nil, "unbekannter Schluessel")
    assertEq(back.volume, 0.5, "gueltiger Schluessel bleibt")
end)

case("F-02: Werte ausserhalb der Grenzen werden verworfen", function()
    local back = Prefs.parse("version=1\nvolume=5\nbotLevel=9\n")
    assertEq(back.volume, Prefs.DEFAULTS.volume, "volume")
    assertEq(back.botLevel, Prefs.DEFAULTS.botLevel, "botLevel")
end)

case("serialize schreibt sortiert und mit Version", function()
    local text = Prefs.serialize(Prefs.new())
    assertTrue(text:match("^version=1\n") ~= nil, "Version zuerst")
    assertTrue(text:find("botActive=") < text:find("volume="), "sortiert")
end)

return T
