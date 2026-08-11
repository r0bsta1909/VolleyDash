-- ============================================================================
-- src/sim/ruleset.lua -- alles, was die Simulation beeinflusst (M0-09, B-04)
--
-- Trennung nach ADR-005:
--   Ruleset  simulationsrelevant, vom Host verteilt, kanonisch gehasht,
--            waehrend eines Matches unveraendert
--   Prefs    rein lokal (src/app/prefs.lua): Lautstaerke, Bot-Stufe, Anzeige
--
-- Ohne diese Trennung koennte im Netzwerkspiel jeder Client seine eigene
-- Physik einstellen, und der Abgleich beim Match-Start waere nicht definierbar.
--
-- love-frei: keine Datei-, keine Hash-Bibliothek von aussen. Der Hash ist
-- bewusst selbst gerechnet, siehe unten.
-- ============================================================================

local Ruleset = {}

-- ---------------------------------------------------------------------------
-- Felddefinition
--
-- Die Grenzen sind die des Live-Tweakers; sie stehen jetzt hier, damit es
-- nur eine Wahrheit gibt (F-10). `step` ist die Schrittweite des Tweakers.
-- ---------------------------------------------------------------------------
Ruleset.FIELDS = {
    blobGroundY    = { type = "number", min = 400,   max = 560,  step = 5 },
    ballGroundY    = { type = "number", min = 480,   max = 560,  step = 5 },
    activeTransfer = { type = "number", min = 0.0,   max = 1.5,  step = 0.05 },
    passiveBounce  = { type = "number", min = 0.1,   max = 1.5,  step = 0.05 },
    airControl     = { type = "number", min = 0.05,  max = 1.0,  step = 0.05 },
    gravity        = { type = "number", min = 100,   max = 3000, step = 50 },
    blobGravity    = { type = "number", min = 500,   max = 4000, step = 50 },
    ballBaseSpeed  = { type = "number", min = 100,   max = 1200, step = 25 },
    maxBallSpeed   = { type = "number", min = 500,   max = 3000, step = 50 },
    ballRadius     = { type = "number", min = 8,     max = 80,   step = 2 },
    jumpForce      = { type = "number", min = -1500, max = -200, step = 20 },
    moveSpeed      = { type = "number", min = 100,   max = 1000, step = 20 },
    blobRadius     = { type = "number", min = 20,    max = 100,  step = 2 },
    netHeight      = { type = "number", min = 40,    max = 350,  step = 10 },
    serveHeight    = { type = "number", min = 50,    max = 400,  step = 10 },
    serveBoost     = { type = "number", min = 0.1,   max = 3.0,  step = 0.05 },
    wallBounce     = { type = "number", min = 0.5,   max = 2.0,  step = 0.05 },
    dashCooldown   = { type = "number", min = 0.1,   max = 5.0,  step = 0.1 },
    dashSide       = { type = "number", min = 1.0,   max = 5.0,  step = 0.1 },
    dashUp         = { type = "number", min = 1.0,   max = 3.0,  step = 0.05 },
    dashWindow     = { type = "number", min = 0.05,  max = 0.50, step = 0.02 },
    targetScore    = { type = "number", min = 5,     max = 25,   step = 1 },
    deuceCap       = { type = "number", min = 5,     max = 40,   step = 1 },
    rallyTimeout   = { type = "number", min = 0,     max = 120,  step = 5 },
    speedScaling   = { type = "boolean" },
    activeSpike    = { type = "boolean" },
    allowDash      = { type = "boolean" },
    twoPointLead   = { type = "boolean" },
}

-- ---------------------------------------------------------------------------
-- Presets
--
-- `prototype` haelt die Zahlen des Prototyps fest -- Stand Tag `prototype-baseline`
-- und damit die Grundlage aller Referenz-Rallyes. `02_CODE_AUDIT` §4: kein
-- Wert darf sich aendern.
--
-- `classic` ist das verbindliche Vanilla-Regelwerk aus `01_GDD` §3: dieselbe
-- Physik, aber ohne Dash, ohne Smash, ohne Speed-Scaling. Es ist die
-- Start-Voreinstellung (ADR-006).
-- ---------------------------------------------------------------------------
local PROTOTYPE = {
    blobGroundY    = 500,
    ballGroundY    = 520,
    activeTransfer = 0.40,
    passiveBounce  = 0.75,
    airControl     = 0.50,
    gravity        = 1000,
    blobGravity    = 1600,
    ballBaseSpeed  = 500,
    maxBallSpeed   = 1400,
    ballRadius     = 30,
    jumpForce      = -750,
    moveSpeed      = 600,
    blobRadius     = 54,
    netHeight      = 160,
    serveHeight    = 140,
    serveBoost     = 0.50,
    wallBounce     = 0.70,
    dashCooldown   = 1.5,
    dashSide       = 2.5,
    dashUp         = 1.3,
    dashWindow     = 0.20,
    targetScore    = 15,
    -- Der Prototyp kannte weder Zwei-Punkte-Vorsprung noch Rallye-Timeout.
    -- Das Preset bildet ihn ab, damit die Referenzen reproduzierbar bleiben
    -- (B-05, GDD P5 -- korrigiert wird das im Preset `classic`).
    deuceCap       = 21,
    rallyTimeout   = 0,
    speedScaling   = false,
    activeSpike    = true,
    allowDash      = true,
    twoPointLead   = false,
}

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

Ruleset.PRESETS = {
    prototype = copy(PROTOTYPE),
    classic   = nil,   -- gleich unten aus PROTOTYPE abgeleitet
}

do
    local classic = copy(PROTOTYPE)
    classic.allowDash    = false   -- 01_GDD §3.1: nicht im Original
    classic.activeSpike  = false   -- dito
    classic.speedScaling = false
    classic.twoPointLead = true    -- 01_GDD §3.1: 15 Punkte UND 2 Vorsprung (B-05)
    classic.deuceCap     = 21      -- Hard-Cap gegen Endlos-Deuce (E-09)
    classic.rallyTimeout = 30      -- 01_GDD P5, Sekunden
    Ruleset.PRESETS.classic = classic
end

Ruleset.DEFAULT_PRESET = "classic"   -- ADR-006

-- ---------------------------------------------------------------------------
-- Erzeugen
-- ---------------------------------------------------------------------------

function Ruleset.new(presetName, overrides)
    local preset = Ruleset.PRESETS[presetName or Ruleset.DEFAULT_PRESET]
    if not preset then
        error("unbekanntes Preset: " .. tostring(presetName))
    end
    local rs = copy(preset)
    if overrides then
        for k, v in pairs(overrides) do
            if Ruleset.FIELDS[k] ~= nil then rs[k] = v end
        end
    end
    return rs
end

-- Aus dem ruleset_snapshot einer Aufzeichnung. Der Sockel ist `prototype`:
-- die Referenzen entstanden vor `allowDash`, und ein fehlender Schluessel darf
-- nicht stillschweigend die heutige Voreinstellung erben.
function Ruleset.fromSnapshot(snapshot)
    return Ruleset.new("prototype", snapshot)
end

function Ruleset.clamp(key, value)
    local field = Ruleset.FIELDS[key]
    if not field or field.type ~= "number" then return value end
    return math.max(field.min, math.min(field.max, value))
end

-- ---------------------------------------------------------------------------
-- Validierung (F-10, T-R-15)
-- ---------------------------------------------------------------------------

-- Sprunghoehe des Blobs aus Sprungkraft und Schwerkraft.
local function jumpApex(rs)
    return (rs.jumpForce * rs.jumpForce) / (2 * rs.blobGravity)
end

-- Gibt ok, errors zurueck. errors ist eine Liste von Klartextzeilen.
function Ruleset.validate(rs)
    local errors = {}

    for key, field in pairs(Ruleset.FIELDS) do
        local v = rs[key]
        if v == nil then
            errors[#errors + 1] = key .. " fehlt"
        elseif type(v) ~= field.type then
            errors[#errors + 1] = key .. " hat den falschen Typ"
        elseif field.type == "number" and (v < field.min or v > field.max) then
            errors[#errors + 1] = string.format("%s = %s liegt ausserhalb von %s..%s",
                key, tostring(v), tostring(field.min), tostring(field.max))
        end
    end
    if #errors > 0 then return false, errors end

    -- Spielbarkeit: Der Blob muss den Ball ueber der Netzkante ueberhaupt
    -- erreichen koennen, sonst ist kein legales Spiel moeglich (F-10).
    local reach = jumpApex(rs) + rs.blobRadius + rs.ballRadius
    if rs.netHeight >= reach then
        errors[#errors + 1] = string.format(
            "netHeight = %s ist unerreichbar: Sprung + Radien reichen nur %.1f px hoch",
            tostring(rs.netHeight), reach)
    end

    if rs.twoPointLead and rs.deuceCap < rs.targetScore then
        errors[#errors + 1] = string.format(
            "deuceCap = %s liegt unter targetScore = %s",
            tostring(rs.deuceCap), tostring(rs.targetScore))
    end

    -- Der Ball muss zwischen Netzkante und Boden passen, sonst klemmt er
    -- dauerhaft im Netz.
    if rs.ballRadius * 2 >= rs.netHeight then
        errors[#errors + 1] = string.format(
            "ballRadius = %s ist zu gross fuer netHeight = %s",
            tostring(rs.ballRadius), tostring(rs.netHeight))
    end

    return #errors == 0, errors
end

-- ---------------------------------------------------------------------------
-- Kanonische Form und Hash (ADR-005, T-R-14)
-- ---------------------------------------------------------------------------

local function sortedKeys(rs)
    local keys = {}
    for k in pairs(rs) do
        if Ruleset.FIELDS[k] ~= nil then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

-- Schluessel sortiert, Zahlen mit fester Formatierung. Zwei gleiche Rulesets
-- ergeben dieselbe Zeichenkette, egal in welcher Reihenfolge sie entstanden
-- sind -- `pairs` ist in Lua nicht geordnet.
function Ruleset.canonical(rs)
    local parts = {}
    for _, k in ipairs(sortedKeys(rs)) do
        local v = rs[k]
        if type(v) == "number" then
            parts[#parts + 1] = k .. "=" .. string.format("%.17g", v)
        else
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
    end
    return table.concat(parts, ";")
end

-- djb2 ueber die kanonische Form, modulo 2^32, als acht Hexstellen.
--
-- Bewusst nicht `love.data.hash` (CLAUDE.md §7): diese Datei liegt unter
-- src/sim/ und muss love-frei bleiben, sonst laufen die Tests der Ebenen A
-- und B nicht headless. Der Hash erkennt abweichende Rulesets, er sichert
-- nichts ab -- dafuer reicht das. Reine Arithmetik, keine Bit-Bibliothek:
-- 2^32 * 33 bleibt exakt in einem double.
function Ruleset.hash(rs)
    local text = Ruleset.canonical(rs)
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + text:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

return Ruleset
