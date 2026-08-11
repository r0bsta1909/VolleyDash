-- ============================================================================
-- src/app/prefs.lua -- rein lokale Einstellungen (M0-09, ADR-005)
--
-- Alles, was NICHT die Simulation beeinflusst: Lautstaerke, Bot-Stufe,
-- Anzeigeoptionen. Prefs werden nie ueber das Netz verteilt und nie gehasht.
-- Wer hier etwas verstellt, veraendert sein eigenes Spielerlebnis, nicht das
-- Spiel.
--
-- Behebt nebenbei zwei Befunde des Audits:
--   F-01  Die Datei hatte kein Versionsfeld. Bei einer Formatänderung brach
--         das Laden still.
--   F-02  Geladen wurde jeder Schluessel aus der Datei. Eine manipulierte
--         Save-Datei konnte beliebige Werte setzen. Jetzt gilt eine Whitelist.
-- ============================================================================

local Prefs = {}

Prefs.VERSION = 1
Prefs.FILE = "volleydash_prefs.sav"

-- Whitelist. Was hier nicht steht, wird beim Laden verworfen (F-02).
Prefs.FIELDS = {
    volume    = { type = "number",  min = 0, max = 1 },
    botActive = { type = "boolean" },
    botLevel  = { type = "number",  min = 1, max = 3 },
    preset    = { type = "string" },   -- zuletzt gewaehltes Ruleset-Preset
    bindings  = { type = "string" },   -- "a,d,w,s|h,k,u,j", siehe src/input/bindings.lua
}

Prefs.DEFAULTS = {
    volume    = 0.25,
    botActive = true,
    botLevel  = 3,
    preset    = "classic",
    bindings  = "a,d,w,s|h,k,u,j",
}

function Prefs.new()
    local p = {}
    for k, v in pairs(Prefs.DEFAULTS) do p[k] = v end
    return p
end

local function coerce(key, raw)
    local field = Prefs.FIELDS[key]
    if not field then return nil end

    if field.type == "number" then
        local v = tonumber(raw)
        if not v then return nil end
        if field.min and v < field.min then return nil end
        if field.max and v > field.max then return nil end
        return v
    elseif field.type == "boolean" then
        if raw == "true" then return true end
        if raw == "false" then return false end
        return nil
    end
    return tostring(raw)
end

-- Schluessel sortiert, damit die Datei bei gleichem Inhalt gleich aussieht.
function Prefs.serialize(prefs)
    local keys = {}
    for k in pairs(Prefs.FIELDS) do keys[#keys + 1] = k end
    table.sort(keys)

    local lines = { "version=" .. Prefs.VERSION }
    for _, k in ipairs(keys) do
        if prefs[k] ~= nil then lines[#lines + 1] = k .. "=" .. tostring(prefs[k]) end
    end
    return table.concat(lines, "\n") .. "\n"
end

-- Aus Textzeilen. Unbekannte Schluessel, falsche Typen und Werte ausserhalb
-- der Grenzen werden verworfen, nicht uebernommen.
function Prefs.parse(text)
    local prefs = Prefs.new()
    local version = tonumber(text:match("version=(%d+)"))

    -- Kein oder fremdes Versionsfeld: Voreinstellungen, kein Ratespiel (F-01).
    if version ~= Prefs.VERSION then return prefs, false end

    for line in text:gmatch("[^\r\n]+") do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k and k ~= "version" then
            local value = coerce(k, v)
            if value ~= nil then prefs[k] = value end
        end
    end
    return prefs, true
end

-- love.filesystem steckt nur in diesen beiden Funktionen; alles darueber ist
-- reine Datenverarbeitung und damit testbar.
function Prefs.load()
    if not (love and love.filesystem) then return Prefs.new(), false end
    if not love.filesystem.getInfo(Prefs.FILE) then return Prefs.new(), false end
    local text = love.filesystem.read(Prefs.FILE)
    if not text then return Prefs.new(), false end
    return Prefs.parse(text)
end

function Prefs.save(prefs)
    if not (love and love.filesystem) then return false end
    return love.filesystem.write(Prefs.FILE, Prefs.serialize(prefs))
end

return Prefs
