-- ============================================================================
-- src/tournament/json.lua -- JSON fuer den Turnierstand (M4-06, ADR-020)
--
-- KEIN allgemeiner JSON-Ersatz. Diese Datei deckt genau die Teilmenge ab, die
-- `persistence.lua` schreibt und liest: Objekte, Listen, Zeichenketten, Zahlen,
-- Wahrheitswerte, null. Kein Streaming, keine Kommentare, kein \u ausserhalb
-- des ASCII-Bereichs. Wer sie woanders benutzen will, prueft vorher, ob sie es
-- kann.
--
-- Warum ueberhaupt JSON und nicht `loadstring` auf einem Lua-Literal: ADR-020.
-- Kurzfassung -- die Datei ist das Betriebsmittel fuer den Fall, in dem die
-- Software nicht mehr tut, was sie soll. Dann macht ein Mensch sie mit einem
-- Texteditor auf.
--
-- love-frei.
-- ============================================================================

local Json = {}

-- ---------------------------------------------------------------------------
-- Kodieren
-- ---------------------------------------------------------------------------

local ESCAPES = {
    ['"']  = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function escapeString(s)
    local out = s:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end)
    return '"' .. out .. '"'
end

-- Zahlen mit %.17g, aus demselben Grund wie in `Ruleset.canonical`: Was
-- herausgeht, muss bitgleich zurueckkommen. %g laesst ganze Zahlen ganz
-- aussehen (5 bleibt "5"), also braucht es keine Sonderbehandlung.
local function encodeNumber(v)
    if v ~= v then error("JSON kennt kein NaN", 0) end
    if v == math.huge or v == -math.huge then error("JSON kennt kein Unendlich", 0) end
    return string.format("%.17g", v)
end

-- Ist die Tabelle eine dichte Liste 1..n? Eine leere Tabelle gilt als Liste
-- und wird zu `[]` -- im Turnierstand ist jede potenziell leere Tabelle eine
-- Liste (`sets`, `log`, `unresolved`), Objekte haben immer Felder.
local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

local encodeValue

-- Schluessel sortiert: derselbe Zustand ergibt dieselben Bytes. Damit lassen
-- sich zwei Laeufe mit `diff` vergleichen und ein Test kann auf Bytegleichheit
-- pruefen statt auf Strukturgleichheit (ADR-020).
local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) ~= "string" then
            error("JSON-Objektschluessel muessen Zeichenketten sein, war " .. type(k), 0)
        end
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

local function encodeTable(t, out, indent, depth)
    if depth > 32 then error("JSON zu tief verschachtelt", 0) end

    local nl, pad, padIn = "", "", ""
    if indent then
        nl     = "\n"
        pad    = string.rep("  ", depth)
        padIn  = string.rep("  ", depth + 1)
    end

    if isArray(t) then
        if #t == 0 then out[#out + 1] = "[]" return end
        out[#out + 1] = "[" .. nl
        for i = 1, #t do
            out[#out + 1] = padIn
            encodeValue(t[i], out, indent, depth + 1)
            if i < #t then out[#out + 1] = "," end
            out[#out + 1] = nl
        end
        out[#out + 1] = pad .. "]"
    else
        local keys = sortedKeys(t)
        out[#out + 1] = "{" .. nl
        for i = 1, #keys do
            out[#out + 1] = padIn .. escapeString(keys[i]) .. (indent and ": " or ":")
            encodeValue(t[keys[i]], out, indent, depth + 1)
            if i < #keys then out[#out + 1] = "," end
            out[#out + 1] = nl
        end
        out[#out + 1] = pad .. "}"
    end
end

encodeValue = function(v, out, indent, depth)
    local kind = type(v)
    if v == nil or kind == "nil" then
        out[#out + 1] = "null"
    elseif kind == "boolean" then
        out[#out + 1] = tostring(v)
    elseif kind == "number" then
        out[#out + 1] = encodeNumber(v)
    elseif kind == "string" then
        out[#out + 1] = escapeString(v)
    elseif kind == "table" then
        encodeTable(v, out, indent, depth)
    else
        error("JSON kann " .. kind .. " nicht darstellen", 0)
    end
end

-- `pretty` (Voreinstellung: an) macht die Datei lesbar. Das ist hier kein
-- Luxus, sondern der Zweck des Formats -- siehe Kopf.
function Json.encode(value, pretty)
    if pretty == nil then pretty = true end
    local out = {}
    encodeValue(value, out, pretty, 0)
    return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Dekodieren
--
-- Gibt bei Erfolg den Wert zurueck, sonst nil plus Klartextmeldung mit
-- Zeichenposition. Die Meldung ist wichtig: Der haeufigste Fehlerfall ist eine
-- halb geschriebene Datei nach einem Absturz, und dann muss im Log stehen,
-- WO sie abbricht -- sonst raet jemand.
-- ---------------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

local UNESCAPES = {
    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
    b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
}

function Parser.new(text)
    return setmetatable({ s = text, i = 1, n = #text }, Parser)
end

function Parser:fail(msg)
    error({ json = true, msg = string.format("%s (Zeichen %d von %d)", msg, self.i, self.n) }, 0)
end

function Parser:skip()
    local _, j = self.s:find("^[ \t\r\n]*", self.i)
    self.i = j + 1
end

function Parser:peek()
    return self.s:sub(self.i, self.i)
end

function Parser:expect(c)
    if self:peek() ~= c then self:fail("erwartet: " .. c) end
    self.i = self.i + 1
end

function Parser:parseString()
    self:expect('"')
    local buf = {}
    while true do
        if self.i > self.n then self:fail("Zeichenkette nicht beendet") end
        local c = self.s:sub(self.i, self.i)
        if c == '"' then
            self.i = self.i + 1
            return table.concat(buf)
        elseif c == '\\' then
            local e = self.s:sub(self.i + 1, self.i + 1)
            if e == 'u' then
                local hex = self.s:sub(self.i + 2, self.i + 5)
                local code = tonumber(hex, 16)
                if not code or #hex < 4 then self:fail("kaputtes \\u") end
                -- Nur der Bereich, den der Encoder erzeugt: Steuerzeichen.
                if code > 255 then self:fail("\\u ueber 00ff wird nicht unterstuetzt") end
                buf[#buf + 1] = string.char(code)
                self.i = self.i + 6
            else
                local u = UNESCAPES[e]
                if not u then self:fail("unbekannte Escape-Folge \\" .. e) end
                buf[#buf + 1] = u
                self.i = self.i + 2
            end
        else
            buf[#buf + 1] = c
            self.i = self.i + 1
        end
    end
end

function Parser:parseNumber()
    local pattern = "^%-?%d+%.?%d*[eE]?[%+%-]?%d*"
    local text = self.s:match(pattern, self.i)
    local value = text and tonumber(text)
    if not value then self:fail("keine gueltige Zahl") end
    self.i = self.i + #text
    return value
end

local function parseLiteral(self, word, value)
    if self.s:sub(self.i, self.i + #word - 1) == word then
        self.i = self.i + #word
        return value, true
    end
    return nil, false
end

function Parser:parseValue(depth)
    if depth > 64 then self:fail("zu tief verschachtelt") end
    self:skip()
    local c = self:peek()

    if c == "" then self:fail("unerwartetes Ende")
    elseif c == '{' then
        self.i = self.i + 1
        local obj = {}
        self:skip()
        if self:peek() == '}' then self.i = self.i + 1 return obj end
        while true do
            self:skip()
            local key = self:parseString()
            self:skip()
            self:expect(':')
            obj[key] = self:parseValue(depth + 1)
            self:skip()
            local d = self:peek()
            if d == ',' then self.i = self.i + 1
            elseif d == '}' then self.i = self.i + 1 return obj
            else self:fail("erwartet , oder }") end
        end
    elseif c == '[' then
        self.i = self.i + 1
        local arr = {}
        self:skip()
        if self:peek() == ']' then self.i = self.i + 1 return arr end
        while true do
            arr[#arr + 1] = self:parseValue(depth + 1)
            self:skip()
            local d = self:peek()
            if d == ',' then self.i = self.i + 1
            elseif d == ']' then self.i = self.i + 1 return arr
            else self:fail("erwartet , oder ]") end
        end
    elseif c == '"' then
        return self:parseString()
    else
        local v, ok = parseLiteral(self, "true", true)
        if ok then return v end
        v, ok = parseLiteral(self, "false", false)
        if ok then return v end
        v, ok = parseLiteral(self, "null", Json.NULL)
        if ok then return v end
        return self:parseNumber()
    end
end

-- `null` wird zu nil. Im Turnierstand ist das richtig: Ein Feld, das null ist
-- (`winner`, `calledAt`), soll nach dem Lesen genauso fehlen wie vorher.
Json.NULL = nil

function Json.decode(text)
    if type(text) ~= "string" then return nil, "kein Text" end
    local parser = Parser.new(text)
    local ok, result = pcall(function()
        local v = parser:parseValue(0)
        parser:skip()
        if parser.i <= parser.n then parser:fail("Muell nach dem Ende") end
        return v
    end)
    if ok then return result end
    if type(result) == "table" and result.json then return nil, result.msg end
    return nil, tostring(result)
end

return Json
