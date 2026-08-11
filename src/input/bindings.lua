-- ============================================================================
-- src/input/bindings.lua -- Tastenbelegung, konfigurierbar und persistent
-- (M0-11, GDD §7)
--
-- Belegungen sind lokal: sie gehoeren zu den Prefs, nicht zum Ruleset
-- (ADR-005). Zwei Spieler an einer Tastatur duerfen sich keine Taste teilen,
-- und die Tasten der Oberflaeche sind gesperrt -- sonst belegt jemand ESC und
-- kommt nicht mehr ins Menue.
--
-- love-frei: reine Datenpruefung, damit sie headless testbar ist.
-- ============================================================================

local Bindings = {}

-- Der Dash steht nicht in der Liste: er ist ein abgeleitetes Signal aus dem
-- Doppeltipp der Richtungstasten (ADR-014), keine eigene Taste.
Bindings.ACTIONS = { "left", "right", "jump", "smash" }

Bindings.LABELS = {
    left  = "Links",
    right = "Rechts",
    jump  = "Springen",
    smash = "Smash",
}

-- GDD §7
Bindings.DEFAULTS = {
    { left = "a", right = "d", jump = "w", smash = "s" },
    { left = "h", right = "k", jump = "u", smash = "j" },
}

-- Gamepad. Die Belegung ist fest; ein Pad hat feste Knopfnamen, da gibt es
-- nichts zu konfigurieren, solange SDL die Zuordnung liefert.
Bindings.GAMEPAD = {
    axis       = "leftx",
    left       = "dpleft",
    right      = "dpright",
    jump       = "a",
    smash      = "x",
    dashLeft   = "leftshoulder",   -- GDD §7: Dash auf LB/RB
    dashRight  = "rightshoulder",
}

-- Tasten der Oberflaeche. Wer die belegt, sperrt sich aus.
Bindings.RESERVED = {
    escape = true, ["return"] = true, tab = true, space = true,
    up = true, down = true, left = true, right = true,
    f1 = true, f2 = true, f3 = true, f4 = true, f5 = true, f6 = true,
    f7 = true, f8 = true, f9 = true, f10 = true, f11 = true, f12 = true,
    lalt = true, ralt = true, r = true,
}

function Bindings.new()
    local b = {}
    for slot = 1, 2 do
        b[slot] = {}
        for _, action in ipairs(Bindings.ACTIONS) do
            b[slot][action] = Bindings.DEFAULTS[slot][action]
        end
    end
    return b
end

-- Gibt ok, Fehlerliste zurueck.
function Bindings.validate(b)
    local errors = {}
    local seen = {}

    for slot = 1, 2 do
        if type(b[slot]) ~= "table" then
            errors[#errors + 1] = "Belegung fuer Spieler " .. slot .. " fehlt"
        else
            for _, action in ipairs(Bindings.ACTIONS) do
                local key = b[slot][action]
                if type(key) ~= "string" or key == "" then
                    errors[#errors + 1] = string.format("P%d %s ist nicht belegt", slot, action)
                elseif Bindings.RESERVED[key] then
                    errors[#errors + 1] = string.format("P%d %s: %s ist fuer die Oberflaeche reserviert",
                        slot, action, key)
                elseif seen[key] then
                    errors[#errors + 1] = string.format("%s ist doppelt belegt (%s und P%d %s)",
                        key, seen[key], slot, action)
                else
                    seen[key] = string.format("P%d %s", slot, action)
                end
            end
        end
    end
    return #errors == 0, errors
end

-- Eine einzelne Taste setzen. Gibt ok, Fehlertext zurueck und laesst die
-- Belegung bei einem Fehler unveraendert.
function Bindings.set(b, slot, action, key)
    if Bindings.RESERVED[key] then
        return false, key .. " ist fuer die Oberflaeche reserviert"
    end

    -- Taste woanders belegt? Dann tauschen statt doppelt zu belegen.
    for otherSlot = 1, 2 do
        for _, otherAction in ipairs(Bindings.ACTIONS) do
            if b[otherSlot][otherAction] == key
               and not (otherSlot == slot and otherAction == action) then
                b[otherSlot][otherAction] = b[slot][action]
            end
        end
    end

    b[slot][action] = key
    return true
end

-- "a,d,w,s|h,k,u,j" -- kurz, sortierstabil, in einer Zeile speicherbar.
function Bindings.serialize(b)
    local slots = {}
    for slot = 1, 2 do
        local parts = {}
        for _, action in ipairs(Bindings.ACTIONS) do
            parts[#parts + 1] = b[slot][action]
        end
        slots[#slots + 1] = table.concat(parts, ",")
    end
    return table.concat(slots, "|")
end

-- Gibt nil zurueck, wenn die Zeichenkette nicht passt oder die Belegung
-- ungueltig waere. Der Aufrufer nimmt dann die Vorgabe.
function Bindings.parse(text)
    if type(text) ~= "string" then return nil end

    local b = {}
    local slot = 0
    for part in text:gmatch("[^|]+") do
        slot = slot + 1
        if slot > 2 then return nil end
        b[slot] = {}
        local i = 0
        for key in part:gmatch("[^,]+") do
            i = i + 1
            local action = Bindings.ACTIONS[i]
            if not action then return nil end
            b[slot][action] = key
        end
        if i ~= #Bindings.ACTIONS then return nil end
    end
    if slot ~= 2 then return nil end

    if not Bindings.validate(b) then return nil end
    return b
end

return Bindings
