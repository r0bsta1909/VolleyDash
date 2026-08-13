-- ============================================================================
-- src/net/protocol.lua -- Nachrichtenformat (M2-01, 04_NETCODE_SPEC §5)
--
--     Protocol.encode(msgType, payload)  -> Zeichenkette
--     Protocol.decode(data)              -> msgType, payload  |  nil, Grund
--
-- Drei Byte Kopf, danach die Nutzlast. Serialisiert wird mit `love.data.pack`
-- und durchgehend LITTLE-ENDIAN mit ausdruecklich dimensionierten Typen
-- (`<i4`, `<f`). Ohne das Praefix richtet sich die Bytereihenfolge nach der
-- Maschine, und Windows-x86-64 und macOS-ARM64 lesen dieselben Bytes
-- verschieden. Das ist kein theoretischer Fall -- es sind die beiden
-- Zielplattformen (`06_BUILD` §1).
--
-- Diese Datei ist love-abhaengig und liegt deshalb NICHT unter src/sim/.
-- Sie ist trotzdem ohne Netz testbar: pack -> unpack -> Vergleich.
--
-- WARUM DIE TESTS NUR UNTER LOEVE LAUFEN (Entscheidung M2-01):
-- Der Headless-Runner laeuft in der CI unter reinem LuaJIT ohne `love`. Die
-- naheliegende Alternative -- `love.data` hinter eine schmale Schicht kapseln
-- und im Test durch eine Lua-Implementierung ersetzen -- waere hier die
-- falsche: Sie wuerde eine ZWEITE Pack-Implementierung einfuehren und im Test
-- genau die Schicht pruefen, die im Betrieb nicht laeuft. Der Fehler, den
-- T-N-07 finden soll (unterschiedliche Bytes auf Win und macOS), waere damit
-- systematisch unsichtbar.
--
-- Stattdessen: die Protokolltests laufen unter `love . --test` und damit auf
-- beiden CI-Laeufern (seit M1-11 gibt es einen macOS-Runner). Der reine
-- LuaJIT-Lauf ueberspringt sie mit Meldung. Alles, was ENTSCHEIDET statt zu
-- transportieren, liegt in `snapshot.lua`, `input_queue.lua` und `lobby.lua`
-- -- die sind love-frei und laufen ueberall.
-- ============================================================================

local Snapshot = require("src.net.snapshot")
local Ruleset  = require("src.sim.ruleset")
-- ADR-023: dieselbe Darstellung wie die Zustandsdatei. `json.lua` ist
-- love-frei und deckt genau die Ereignisse ab, die `persistence.lua`
-- schreibt -- die Pruefung, die ADR-020 vor einer Zweitnutzung verlangt.
local Json     = require("src.tournament.json")

local Protocol = {}

Protocol.VERSION     = 1
Protocol.HEADER      = "<BBB"
Protocol.HEADER_SIZE = 3

-- Discovery laeuft ueber einen fremden Port, auf dem alles Moegliche liegen
-- kann. Die Magic steht deshalb VOR dem Kopf (CLAUDE.md §1).
Protocol.MAGIC = "VLYD"

Protocol.PORT_ENET      = 21212
Protocol.PORT_DISCOVERY = 21213

Protocol.MSG = {
    HELLO            = 0x01,
    WELCOME          = 0x02,
    REJECT           = 0x03,
    LOBBY_STATE      = 0x10,
    SET_READY        = 0x11,
    RULESET_FULL     = 0x12,
    MATCH_START      = 0x20,
    INPUT            = 0x21,
    SNAPSHOT         = 0x22,
    MATCH_END        = 0x23,
    MATCH_PAUSE      = 0x24,
    SPECTATE_REQ     = 0x30,
    -- Turnier (M4-09). 0x40 traegt Log-Ereignisse, nicht den abgeleiteten
    -- Zustand -- ADR-023. Der Anmelde-Handschlag ist HELLO/REJECT aus der
    -- Lobby; neu ist nur die Antwort (0x46), weil ein Turnier keine Slots hat.
    TOURNAMENT_STATE = 0x40,
    TOURNAMENT_ASSIGN = 0x41,
    MATCH_ACCEPT     = 0x42,
    MATCH_REPORT     = 0x43,
    RESULT_QUERY     = 0x44,
    STATE_REQUEST    = 0x45,
    TOURNAMENT_WELCOME = 0x46,
    PING             = 0x50,
    PONG             = 0x51,
    CHECKSUM         = 0x60,
    PROBE            = 0x70,
    ANNOUNCE         = 0x71,
}

Protocol.NAME = {}
for name, id in pairs(Protocol.MSG) do Protocol.NAME[id] = name end

-- ENet-Kanaele nach `04_NETCODE_SPEC` §4. Was hier nicht steht, geht
-- zuverlaessig ueber Kanal 0.
Protocol.CHANNELS = 3
Protocol.CHANNEL = {
    [Protocol.MSG.SNAPSHOT] = 1,   -- unreliable: ein veralteter Snapshot ist wertlos
    [Protocol.MSG.INPUT]    = 2,   -- unreliable: Verlust faengt die Redundanz ab (§7)
}

Protocol.UNRELIABLE = {
    [Protocol.MSG.SNAPSHOT] = true,
    [Protocol.MSG.INPUT]    = true,
}

-- Ablehnungsgruende (`04_NETCODE_SPEC` §5, Nachricht 0x03). Der Text kommt
-- immer mit -- der Code ist fuer den Empfaenger, der Text fuer den Menschen.
Protocol.REJECT = {
    VERSION   = 1,
    FULL      = 2,
    RUNNING   = 3,
    DUPLICATE = 4,
    CLOSED    = 5,
}

-- Grund eines Matchendes (0x23).
Protocol.END = {
    NORMAL     = 0,
    DISCONNECT = 1,
    HOST_ABORT = 2,
}

-- Typkennungen in RULESET_FULL (ADR-016).
Protocol.RS_NUMBER  = 1
Protocol.RS_BOOLEAN = 2

Protocol.MAX = {
    name      = 24,
    lobby     = 32,
    buildHash = 16,
    text      = 64,
    key       = 32,
    matchId   = 16,   -- "m_101" -- Bracket.newIdGen
    pid       = 8,    -- "p_01"
    address   = 48,   -- "255.255.255.255:65535" mit Luft
}

-- Rolle in einem Turniermatch (0x41). Wer hostet, entscheidet der Turnier-Host
-- nach ADR-022 -- der Empfaenger fuehrt aus, er waehlt nicht.
Protocol.ROLE = {
    GUEST = 0,
    HOST  = 1,
}

-- Ein Block aus Log-Ereignissen (0x40). Groesser waere eine Nachricht, deren
-- Groesse vom Turnierverlauf abhaengt; 32 Ereignisse sind rund 3 KB.
Protocol.STATE_CHUNK = 32

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------

-- `dpack`/`dunpack` sind love.data.pack/unpack. Die Namen sind absichtlich
-- nicht `pack`/`unpack`: `unpack` ist in Lua 5.1 die eingebaute Listenfunktion,
-- die hier ebenfalls gebraucht wird, und zwei Bedeutungen fuer einen Namen in
-- einer Datei sind eine Fehlerquelle ohne Gegenwert.
local dpack, dunpack
local listUnpack = _G.unpack or table.unpack

local function bind()
    if not (love and love.data) then
        error("src/net/protocol.lua braucht love.data -- diese Datei laeuft "
              .. "nicht im reinen LuaJIT-Lauf (siehe Kopf)", 3)
    end
    dpack, dunpack = love.data.pack, love.data.unpack
end

-- `s1` traegt ein Laengenbyte. Laenger als 255 geht nicht, laenger als das
-- Feldmass soll nicht -- gekuerzt wird beim Sender, nicht beim Empfaenger.
local function clip(text, max)
    text = tostring(text or "")
    if #text > max then return text:sub(1, max) end
    return text
end

local function u8(value)
    value = math.floor(tonumber(value) or 0)
    if value < 0 then return 0 end
    if value > 255 then return 255 end
    return value
end

-- ---------------------------------------------------------------------------
-- Snapshot: Format aus der Feldliste
--
-- Gebaut, nicht abgeschrieben. Eine Formatzeichenkette fuer pack und unpack,
-- damit ein neues Feld in `snapshot.lua` nicht an zwei Stellen nachgezogen
-- werden muss -- und beim Vergessen sofort auffaellt statt still zu
-- verschieben.
-- ---------------------------------------------------------------------------
local SNAP_FORMAT
do
    local parts = { "<" }
    for _, field in ipairs(Snapshot.FIELDS) do parts[#parts + 1] = field[2] end
    SNAP_FORMAT = table.concat(parts)
end
Protocol.SNAP_FORMAT = SNAP_FORMAT

-- ---------------------------------------------------------------------------
-- Codecs
--
-- Je Nachrichtentyp ein Paar. `pack` bekommt die Nutzlasttabelle und liefert
-- Bytes ohne Kopf, `unpack` bekommt die Bytes ab Position 4 und liefert die
-- Tabelle zurueck. Was hier keinen Eintrag hat, laesst sich nicht senden --
-- absichtlich: eine Nachricht ohne Codec ist eine Nachricht ohne Format.
-- ---------------------------------------------------------------------------
local CODEC = {}

CODEC[Protocol.MSG.HELLO] = {
    pack = function(t)
        return dpack("string", "<I4s1s1", t.clientId or 0,
            clip(t.buildHash, Protocol.MAX.buildHash), clip(t.name, Protocol.MAX.name))
    end,
    unpack = function(data, pos)
        local clientId, buildHash, name = dunpack("<I4s1s1", data, pos)
        return { clientId = clientId, buildHash = buildHash, name = name }
    end,
}

CODEC[Protocol.MSG.WELCOME] = {
    pack = function(t)
        return dpack("string", "<BI4s1s1s1", u8(t.slot), t.clientId or 0,
            clip(t.rulesetHash, 8), clip(t.hostName, Protocol.MAX.name),
            clip(t.lobbyName, Protocol.MAX.lobby))
    end,
    unpack = function(data, pos)
        local slot, clientId, rulesetHash, hostName, lobbyName =
            dunpack("<BI4s1s1s1", data, pos)
        return { slot = slot, clientId = clientId, rulesetHash = rulesetHash,
                 hostName = hostName, lobbyName = lobbyName }
    end,
}

CODEC[Protocol.MSG.REJECT] = {
    pack = function(t)
        return dpack("string", "<Bs1", u8(t.reason), clip(t.text, Protocol.MAX.text))
    end,
    unpack = function(data, pos)
        local reason, text = dunpack("<Bs1", data, pos)
        return { reason = reason, text = text }
    end,
}

CODEC[Protocol.MSG.LOBBY_STATE] = {
    pack = function(t)
        local out = { dpack("string", "<B", #t.slots) }
        for _, slot in ipairs(t.slots) do
            out[#out + 1] = dpack("string", "<BBBs1s1",
                slot.occupied and 1 or 0, slot.ready and 1 or 0, slot.isHost and 1 or 0,
                clip(slot.name, Protocol.MAX.name),
                clip(slot.buildHash, Protocol.MAX.buildHash))
        end
        return table.concat(out)
    end,
    unpack = function(data, pos)
        local count
        count, pos = dunpack("<B", data, pos)
        local slots = {}
        for i = 1, count do
            local occupied, ready, isHost, name, buildHash
            occupied, ready, isHost, name, buildHash, pos = dunpack("<BBBs1s1", data, pos)
            slots[i] = { occupied = occupied == 1, ready = ready == 1,
                         isHost = isHost == 1, name = name, buildHash = buildHash }
        end
        return { slots = slots }
    end,
}

CODEC[Protocol.MSG.SET_READY] = {
    pack = function(t) return dpack("string", "<B", t.ready and 1 or 0) end,
    unpack = function(data, pos)
        local ready = dunpack("<B", data, pos)
        return { ready = ready == 1 }
    end,
}

-- ADR-016: selbstbeschreibende Schluessel-Wert-Folge statt JSON. Zahlen gehen
-- als `d` (float64), NICHT als `f`. Die kanonische Form fuer den Hash
-- formatiert mit `%.17g`; ein Umweg ueber float32 wuerde die Zahl aendern und
-- der Abgleich aus §10 schluege grundlos fehl.
CODEC[Protocol.MSG.RULESET_FULL] = {
    pack = function(t)
        local keys = {}
        for key in pairs(t.ruleset) do
            if Ruleset.FIELDS[key] ~= nil then keys[#keys + 1] = key end
        end
        table.sort(keys)

        local out = { dpack("string", "<B", #keys) }
        for _, key in ipairs(keys) do
            local value = t.ruleset[key]
            if type(value) == "boolean" then
                out[#out + 1] = dpack("string", "<s1BB", clip(key, Protocol.MAX.key),
                    Protocol.RS_BOOLEAN, value and 1 or 0)
            else
                out[#out + 1] = dpack("string", "<s1Bd", clip(key, Protocol.MAX.key),
                    Protocol.RS_NUMBER, value)
            end
        end
        return table.concat(out)
    end,
    unpack = function(data, pos)
        local count
        count, pos = dunpack("<B", data, pos)
        local rs = {}
        for _ = 1, count do
            local key, kind
            key, kind, pos = dunpack("<s1B", data, pos)
            local value
            if kind == Protocol.RS_BOOLEAN then
                value, pos = dunpack("<B", data, pos)
                value = value == 1
            elseif kind == Protocol.RS_NUMBER then
                value, pos = dunpack("<d", data, pos)
            else
                return nil, "unbekannte Feldkennung " .. tostring(kind)
            end
            -- Unbekannte Schluessel werden verworfen. Sie kaemen aus einer
            -- anderen Fassung; die Abweichung meldet danach der Hashvergleich
            -- im Klartext, statt hier als Absturz aufzutreten (ADR-016).
            if Ruleset.FIELDS[key] ~= nil then rs[key] = value end
        end
        return { ruleset = rs }
    end,
}

CODEC[Protocol.MSG.MATCH_START] = {
    pack = function(t)
        return dpack("string", "<I4i4s1B", t.matchId or 0, t.startTick or 0,
            clip(t.rulesetHash, 8), u8(t.slot))
    end,
    unpack = function(data, pos)
        local matchId, startTick, rulesetHash, slot = dunpack("<I4i4s1B", data, pos)
        return { matchId = matchId, startTick = startTick,
                 rulesetHash = rulesetHash, slot = slot }
    end,
}

-- Drei Masken je Paket: die des Ticks und die der beiden davor (§7). Kostet
-- zwei Byte und macht Einzelpaketverluste unsichtbar (T-N-02).
CODEC[Protocol.MSG.INPUT] = {
    pack = function(t)
        return dpack("string", "<i4BBB", t.tick,
            u8(t.masks[1]), u8(t.masks[2]), u8(t.masks[3]))
    end,
    unpack = function(data, pos)
        local tick, m0, m1, m2 = dunpack("<i4BBB", data, pos)
        return { tick = tick, masks = { m0, m1, m2 } }
    end,
}

CODEC[Protocol.MSG.SNAPSHOT] = {
    pack = function(t)
        local values = {}
        for i, field in ipairs(Snapshot.FIELDS) do values[i] = t[field[1]] end
        return dpack("string", SNAP_FORMAT, listUnpack(values, 1, #Snapshot.FIELDS))
    end,
    unpack = function(data, pos)
        local out = {}
        local results = { dunpack(SNAP_FORMAT, data, pos) }
        for i, field in ipairs(Snapshot.FIELDS) do out[field[1]] = results[i] end
        return out
    end,
}

CODEC[Protocol.MSG.MATCH_END] = {
    pack = function(t)
        return dpack("string", "<I4BBB", t.matchId or 0,
            u8(t.scoreA), u8(t.scoreB), u8(t.reason))
    end,
    unpack = function(data, pos)
        local matchId, scoreA, scoreB, reason = dunpack("<I4BBB", data, pos)
        return { matchId = matchId, scoreA = scoreA, scoreB = scoreB, reason = reason }
    end,
}

CODEC[Protocol.MSG.MATCH_PAUSE] = {
    pack = function(t)
        return dpack("string", "<BBs1", t.paused and 1 or 0, u8(t.secondsLeft),
            clip(t.text, Protocol.MAX.text))
    end,
    unpack = function(data, pos)
        local paused, secondsLeft, text = dunpack("<BBs1", data, pos)
        return { paused = paused == 1, secondsLeft = secondsLeft, text = text }
    end,
}

CODEC[Protocol.MSG.SPECTATE_REQ] = {
    pack = function(t) return dpack("string", "<I4", t.matchId or 0) end,
    unpack = function(data, pos)
        local matchId = dunpack("<I4", data, pos)
        return { matchId = matchId }
    end,
}

local timestampCodec = {
    pack = function(t) return dpack("string", "<I4", t.timestamp or 0) end,
    unpack = function(data, pos)
        local timestamp = dunpack("<I4", data, pos)
        return { timestamp = timestamp }
    end,
}
CODEC[Protocol.MSG.PING] = timestampCodec
CODEC[Protocol.MSG.PONG] = timestampCodec

CODEC[Protocol.MSG.CHECKSUM] = {
    pack = function(t) return dpack("string", "<i4I4", t.tick or 0, t.hash or 0) end,
    unpack = function(data, pos)
        local tick, hash = dunpack("<i4I4", data, pos)
        return { tick = tick, hash = hash }
    end,
}

-- ---------------------------------------------------------------------------
-- Turnier (M4-09)
--
-- 0x40 traegt LOG-EREIGNISSE, nicht den abgeleiteten Zustand (ADR-023). Damit
-- ist die Differenz zweier Staende immer ein Suffix, der Empfaenger leitet mit
-- demselben `Model.applyEvent` ab wie die Recovery, und die Nachricht bleibt
-- bei rund 100 Byte je Ereignis statt bei 30 KB je Zustand.
--
-- Das `s4` ist die einzige im Protokoll (`04_NETCODE` §5): Ein Block aus
-- Ereignissen ueberschreitet 255 Byte, und ein Feldmass, auf das der Sender
-- kuerzen koennte, gibt es hier nicht. Das Laengenpraefix bleibt -- eine
-- fremde Fassung verschiebt den Rest der Nachricht nicht, sie liefert eine
-- Laenge, die nicht aufgeht.
-- ---------------------------------------------------------------------------

CODEC[Protocol.MSG.TOURNAMENT_STATE] = {
    pack = function(t)
        local text = Json.encode(t.events or {}, false)
        return dpack("string", "<I4I2s4", t.fromIndex or 0,
            math.min(65535, #(t.events or {})), text)
    end,
    unpack = function(data, pos)
        local fromIndex, count, text = dunpack("<I4I2s4", data, pos)
        -- Ein kaputter Block wird verworfen und gezaehlt, nicht halb
        -- angewandt: ein halb angewandtes Log ist schlimmer als ein sichtbar
        -- veralteter Stand (ADR-023).
        local events, err = Json.decode(text)
        if type(events) ~= "table" then
            return { fromIndex = fromIndex, count = count, events = nil,
                     error = err or "kein JSON-Array" }
        end
        return { fromIndex = fromIndex, count = count, events = events }
    end,
}

CODEC[Protocol.MSG.TOURNAMENT_ASSIGN] = {
    pack = function(t)
        return dpack("string", "<s1Bs1s1B",
            clip(t.matchId, Protocol.MAX.matchId), u8(t.role),
            clip(t.opponent, Protocol.MAX.name),
            clip(t.address, Protocol.MAX.address), u8(t.bestOf))
    end,
    unpack = function(data, pos)
        local matchId, role, opponent, address, bestOf = dunpack("<s1Bs1s1B", data, pos)
        return { matchId = matchId, role = role, opponent = opponent,
                 address = address, bestOf = bestOf }
    end,
}

-- Der Match-Host meldet den Port, den ihm das Betriebssystem gegeben hat
-- (`05_TOURNAMENT` §8.2). Der Gast schickt dieselbe Nachricht mit Port 0 --
-- fuer ihn ist sie nur die Bereitmeldung, auf die der Scheduler wartet.
CODEC[Protocol.MSG.MATCH_ACCEPT] = {
    pack = function(t)
        return dpack("string", "<s1BI2", clip(t.matchId, Protocol.MAX.matchId),
            t.ready and 1 or 0, math.min(65535, math.floor(t.enetPort or 0)))
    end,
    unpack = function(data, pos)
        local matchId, ready, enetPort = dunpack("<s1BI2", data, pos)
        return { matchId = matchId, ready = ready == 1, enetPort = enetPort }
    end,
}

-- Der Ergebnisbericht des Match-Hosts (E-08). Er traegt die Saetze UND die
-- zwei Statistiken, die in der Simulation anfallen (`05_TOURNAMENT` §11) --
-- ohne sie fehlen sie bei der Siegerehrung, und ein zweiter Weg fuer zwei
-- Zahlen waere teurer als diese beiden Felder.
CODEC[Protocol.MSG.MATCH_REPORT] = {
    pack = function(t)
        local sets = t.sets or {}
        local parts = { dpack("string", "<s1B",
            clip(t.matchId, Protocol.MAX.matchId), u8(#sets)) }
        for _, s in ipairs(sets) do
            parts[#parts + 1] = dpack("string", "<BB", u8(s.a), u8(s.b))
        end
        parts[#parts + 1] = dpack("string", "<ffBB",
            t.longestRally or 0, t.fastestBall or 0,
            u8(t.fastestBy), u8(t.reason))
        return table.concat(parts)
    end,
    unpack = function(data, pos)
        local matchId, count
        matchId, count, pos = dunpack("<s1B", data, pos)
        local sets = {}
        for i = 1, count do
            local a, b
            a, b, pos = dunpack("<BB", data, pos)
            sets[i] = { a = a, b = b }
        end
        local longestRally, fastestBall, fastestBy, reason =
            dunpack("<ffBB", data, pos)
        return { matchId = matchId, sets = sets, longestRally = longestRally,
                 fastestBall = fastestBall, fastestBy = fastestBy, reason = reason }
    end,
}

local matchIdCodec = {
    pack = function(t)
        return dpack("string", "<s1", clip(t.matchId, Protocol.MAX.matchId))
    end,
    unpack = function(data, pos)
        local matchId = dunpack("<s1", data, pos)
        return { matchId = matchId }
    end,
}
CODEC[Protocol.MSG.RESULT_QUERY] = matchIdCodec

CODEC[Protocol.MSG.STATE_REQUEST] = {
    pack = function(t) return dpack("string", "<I4", t.fromIndex or 0) end,
    unpack = function(data, pos)
        local fromIndex = dunpack("<I4", data, pos)
        return { fromIndex = fromIndex }
    end,
}

-- Ein Turnier hat keine Slots und kein Ruleset zu verhandeln -- es hat eine
-- Teilnehmerkennung und einen Namen, der wegen der Eindeutigkeitsregel (§5)
-- ein anderer sein kann als der gewuenschte. Deshalb eine eigene Antwort
-- statt WELCOME.
CODEC[Protocol.MSG.TOURNAMENT_WELCOME] = {
    pack = function(t)
        return dpack("string", "<s1s1s1I4",
            clip(t.participantId, Protocol.MAX.pid),
            clip(t.name, Protocol.MAX.name),
            clip(t.tournamentName, Protocol.MAX.lobby),
            math.floor(t.logCount or 0))
    end,
    unpack = function(data, pos)
        local participantId, name, tournamentName, logCount =
            dunpack("<s1s1s1I4", data, pos)
        return { participantId = participantId, name = name,
                 tournamentName = tournamentName, logCount = logCount }
    end,
}

-- Discovery (§11). `PROBE` traegt ausser Magic und Kopf nichts -- die
-- Absenderadresse steht im UDP-Paket.
CODEC[Protocol.MSG.PROBE] = {
    pack = function() return "" end,
    unpack = function() return {} end,
}

-- `hostId` ist die Kennung der Lobby, nicht der Maschine. Sie loest ein
-- gemessenes Problem: ein Host auf demselben Rechner antwortet zweimal --
-- einmal ueber 127.0.0.1, einmal ueber die LAN-Adresse -- und stuende sonst
-- zweimal in der Liste.
CODEC[Protocol.MSG.ANNOUNCE] = {
    pack = function(t)
        return dpack("string", "<I4s1s1s1BBBI2",
            t.hostId or 0,
            clip(t.hostName, Protocol.MAX.name),
            clip(t.lobbyName, Protocol.MAX.lobby),
            clip(t.buildHash, Protocol.MAX.buildHash),
            u8(t.players), u8(t.maxPlayers),
            t.mode == "tournament" and 1 or 0,
            t.enetPort or Protocol.PORT_ENET)
    end,
    unpack = function(data, pos)
        local hostId, hostName, lobbyName, buildHash, players, maxPlayers, mode, enetPort =
            dunpack("<I4s1s1s1BBBI2", data, pos)
        return { hostId = hostId, hostName = hostName, lobbyName = lobbyName,
                 buildHash = buildHash, players = players, maxPlayers = maxPlayers,
                 mode = mode == 1 and "tournament" or "free", enetPort = enetPort }
    end,
}

Protocol.CODEC = CODEC

-- ---------------------------------------------------------------------------
-- Kopf, kodieren, dekodieren
-- ---------------------------------------------------------------------------

function Protocol.encode(msgType, payload)
    bind()
    local codec = CODEC[msgType]
    if not codec then
        error("Protocol: kein Codec fuer Nachricht "
              .. string.format("0x%02x", msgType or 0), 2)
    end
    return dpack("string", Protocol.HEADER, Protocol.VERSION, msgType, 0)
           .. codec.pack(payload or {})
end

-- Erstes Byte ohne vollstaendige Pruefung. Der Host braucht die Fassung eines
-- Pakets, das er gerade NICHT lesen kann -- sonst kann er die Ablehnung aus
-- §5 nicht im Klartext begruenden und der Gast sieht nur einen Timeout.
function Protocol.peekVersion(data)
    if type(data) ~= "string" or #data < 1 then return nil end
    return data:byte(1)
end

function Protocol.decode(data)
    bind()
    if type(data) ~= "string" or #data < Protocol.HEADER_SIZE then
        return nil, "zu kurz"
    end

    local version, msgType = data:byte(1), data:byte(2)
    if version ~= Protocol.VERSION then
        return nil, "protoVersion " .. tostring(version)
    end

    local codec = CODEC[msgType]
    if not codec then
        return nil, "unbekannte Nachricht " .. string.format("0x%02x", msgType)
    end

    -- Ein zu kurzes oder verstuemmeltes Paket bringt `love.data.unpack` zum
    -- Werfen. Auf dem Netz ist das der Normalfall, nicht die Ausnahme.
    local ok, payload, err = pcall(codec.unpack, data, Protocol.HEADER_SIZE + 1)
    if not ok then return nil, "unlesbar: " .. tostring(payload) end
    if payload == nil then return nil, tostring(err) end
    return msgType, payload
end

-- Discovery-Pakete tragen die Magic davor.
function Protocol.encodeDiscovery(msgType, payload)
    return Protocol.MAGIC .. Protocol.encode(msgType, payload)
end

function Protocol.decodeDiscovery(data)
    if type(data) ~= "string" or #data < #Protocol.MAGIC then return nil, "zu kurz" end
    if data:sub(1, #Protocol.MAGIC) ~= Protocol.MAGIC then return nil, "fremde Magic" end
    return Protocol.decode(data:sub(#Protocol.MAGIC + 1))
end

function Protocol.channelOf(msgType)
    return Protocol.CHANNEL[msgType] or 0
end

function Protocol.flagOf(msgType)
    return Protocol.UNRELIABLE[msgType] and "unreliable" or "reliable"
end

return Protocol
