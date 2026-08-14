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
    musicVolume = { type = "number", min = 0, max = 1 },
    botActive = { type = "boolean" },
    botLevel  = { type = "number",  min = 1, max = 3 },
    preset    = { type = "string" },   -- zuletzt gewaehltes Ruleset-Preset
    -- Interpolationspuffer des Gastes in Ticks (`04_NETCODE` §8). Rein lokal
    -- und deshalb hier und nicht im Ruleset (ADR-005): Er veraendert keine
    -- Simulation, und die beiden Seiten muessen sich darueber nicht einig sein.
    netBuffer = { type = "number",  min = 1, max = 4 },
    bindings  = { type = "string" },   -- "a,d,w,s|h,k,u,j", siehe src/input/bindings.lua

    -- Netzwerk (M2). Beides rein lokal und damit hier richtig aufgehoben --
    -- die Simulation sieht davon nichts (ADR-005).
    --
    -- clientId ist die Kennung fuer den Wiedereinstieg nach einer Trennung
    -- (`04_NETCODE_SPEC` §12). Sie MUSS einen Neustart ueberleben: T-N-05
    -- verlangt genau das -- Prozess abschiessen, neu starten, in den laufenden
    -- Satz zurueck.
    clientId    = { type = "number", min = 1, max = 2147483647 },
    -- Zuletzt getippte Adresse. Wer sie einmal eingegeben hat, tippt sie nach
    -- einem Absturz nicht gern noch einmal.
    lastAddress = { type = "string" },
    -- Der Nickname fuer Netzspiel und Turnier. Anders als die Zufallsnamen des
    -- lokalen Spiels muss er einen Neustart ueberleben: im Turnier steht er im
    -- Bracket, und ein Teilnehmer, der nach jedem Start anders heisst, ist kein
    -- Teilnehmer, sondern ein Rätsel (Entscheidung r0btoshi, 2026-08-12).
    playerName  = { type = "string" },
}

-- Laenge in Zeichen, nicht in Byte: ein Name aus Umlauten waere sonst nach
-- acht Buchstaben zu Ende.
Prefs.NAME_MAX = 16

Prefs.DEFAULTS = {
    volume    = 0.25,
    musicVolume = 0.4,
    botActive = true,
    botLevel  = 3,
    preset    = "classic",
    netBuffer = 2,
    bindings  = "a,d,w,s|h,k,u,j",
    clientId    = 0,     -- 0 heisst "noch keine"; App.clientId zieht dann eine
    lastAddress = "",
    playerName  = "",    -- leer heisst "noch keiner"; App.playerName zieht dann einen
}

-- ---------------------------------------------------------------------------
-- Nickname saeubern
--
-- Reine Funktion, absichtlich hier und nicht in der Oberflaeche: derselbe Name
-- geht ueber das Netz, steht im HUD und landet spaeter im Turnierbaum. Wenn
-- drei Stellen ihn unterschiedlich zurechtstutzen, heisst derselbe Mensch an
-- drei Stellen anders.
--
-- Zeilenumbrueche und Steuerzeichen fliegen raus (sie zerlegen jede Anzeige),
-- Leerraum am Rand ebenfalls, mehrfacher Leerraum in der Mitte wird zu einem.
-- Gekuerzt wird nach ZEICHEN, nicht nach Byte.
-- ---------------------------------------------------------------------------
local utf8ok, utf8lib = pcall(require, "utf8")

function Prefs.nameLength(text)
    if utf8ok and utf8lib and utf8lib.len then
        return utf8lib.len(text) or #text
    end
    return #text
end

-- Letztes Zeichen entfernen -- fuer die Ruecktaste in der Eingabe.
function Prefs.dropLastChar(text)
    if text == "" then return text end
    if utf8ok and utf8lib and utf8lib.offset then
        local offset = utf8lib.offset(text, -1)
        if offset then return text:sub(1, offset - 1) end
    end
    return text:sub(1, -2)
end

function Prefs.cleanName(raw)
    local text = tostring(raw or "")
    -- Steuerzeichen werden zu Leerraum, nicht geloescht: sonst wuerde aus
    -- einem Zeilenumbruch in einer verbogenen Prefs-Datei stillschweigend
    -- "HansMeier" statt "Hans Meier".
    text = text:gsub("[%z\1-\31\127]", " ")
    text = text:gsub("%s+", " ")             -- mehrfacher Leerraum
    text = text:gsub("^%s+", ""):gsub("%s+$", "")

    while Prefs.nameLength(text) > Prefs.NAME_MAX do
        text = Prefs.dropLastChar(text)
    end
    return text
end

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
