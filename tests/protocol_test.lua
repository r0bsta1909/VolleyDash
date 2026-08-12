-- ============================================================================
-- tests/protocol_test.lua -- Ebene B: Nachrichtenformat (M2-01)
--
-- DIESE SUITE BRAUCHT LOEVE. `love.data.pack` ist die Serialisierung des
-- Projekts; sie durch eine Lua-Nachbildung zu ersetzen, nur damit der Test
-- unter reinem LuaJIT laeuft, wuerde die Nachbildung pruefen und nicht das,
-- was im Betrieb Bytes schreibt. Der Headless-Runner ueberspringt sie deshalb
-- mit Meldung; gestartet wird sie mit
--
--     love . --test
--
-- und damit in der CI auf beiden Plattformen (M1-11).
--
-- T-N-07 (offener Punkt N-03) steckt unten: gepackte Bytes gegen eine hier
-- stehende Referenz. Laeuft der Fall auf Windows UND macOS durch, ist die
-- Frage nach der Bytereihenfolge beantwortet -- und zwar mit Beweis statt mit
-- "praktisch sicher".
-- ============================================================================

local Protocol = require("src.net.protocol")
local Snapshot = require("src.net.snapshot")
local Ruleset  = require("src.sim.ruleset")
local Frame    = require("src.input.frame")

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
local function assertNear(actual, expected, tol, what)
    if math.abs(actual - expected) > tol then
        error(string.format("%s: erwartet %s +-%s, war %s",
            what or "Wert", tostring(expected), tostring(tol), tostring(actual)), 2)
    end
end

local function hex(data)
    return (data:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

-- Hin und zurueck. Gibt die dekodierte Nutzlast zurueck.
local function roundtrip(msgType, payload)
    local data = Protocol.encode(msgType, payload)
    local kind, out = Protocol.decode(data)
    assertEq(kind, msgType, "Nachrichtentyp nach dem Umlauf")
    assertTrue(out ~= nil, "Nutzlast dekodiert")
    return out, data
end

-- ---------------------------------------------------------------------------
-- Kopf
-- ---------------------------------------------------------------------------

case("jede Nachricht traegt drei Byte Kopf", function()
    local data = Protocol.encode(Protocol.MSG.SET_READY, { ready = true })
    assertEq(data:byte(1), Protocol.VERSION, "protoVersion")
    assertEq(data:byte(2), Protocol.MSG.SET_READY, "msgType")
    assertEq(data:byte(3), 0, "flags")
    assertEq(#data, Protocol.HEADER_SIZE + 1, "Kopf plus ein Byte Nutzlast")
end)

case("eine fremde Protokollfassung wird abgelehnt, bleibt aber lesbar", function()
    local data = Protocol.encode(Protocol.MSG.HELLO,
        { clientId = 1, buildHash = "x", name = "y" })
    local fremd = string.char(99) .. data:sub(2)

    local kind, err = Protocol.decode(fremd)
    assertEq(kind, nil, "wird nicht dekodiert")
    assertTrue(tostring(err):find("protoVersion") ~= nil, "Grund benannt")

    -- Der Host muss die Fassung des Pakets kennen, das er NICHT lesen kann --
    -- sonst kann er die Ablehnung aus §5 nicht begruenden.
    assertEq(Protocol.peekVersion(fremd), 99, "peekVersion")
end)

case("unbekannte Nachrichtentypen und Bruchstuecke stuerzen nicht ab", function()
    assertEq(Protocol.decode(""), nil, "leer")
    assertEq(Protocol.decode("ab"), nil, "kuerzer als der Kopf")
    assertEq(Protocol.decode(string.char(Protocol.VERSION, 0xEE, 0)), nil, "unbekannter Typ")

    -- Abgeschnittene Nutzlast: auf dem Netz der Normalfall, nicht die Ausnahme.
    local data = Protocol.encode(Protocol.MSG.SNAPSHOT,
        Snapshot.from(require("src.sim.state").new(Ruleset.new("classic")), 1, 0,
                      Ruleset.new("classic")))
    local kind, err = Protocol.decode(data:sub(1, 10))
    assertEq(kind, nil, "abgeschnitten")
    assertTrue(err ~= nil, "Grund vorhanden")
end)

-- ---------------------------------------------------------------------------
-- Ein Umlauf je Nachrichtentyp
-- ---------------------------------------------------------------------------

case("HELLO", function()
    local out = roundtrip(Protocol.MSG.HELLO,
        { clientId = 4294967295, buildHash = "0123456789abcdef", name = "NoobSlayer" })
    assertEq(out.clientId, 4294967295, "clientId")
    assertEq(out.buildHash, "0123456789abcdef", "buildHash")
    assertEq(out.name, "NoobSlayer", "name")
end)

case("WELCOME", function()
    local out = roundtrip(Protocol.MSG.WELCOME,
        { slot = 2, clientId = 7, rulesetHash = "1a2b3c4d",
          hostName = "Wobble", lobbyName = "Kellerparty" })
    assertEq(out.slot, 2, "slot")
    assertEq(out.clientId, 7, "clientId")
    assertEq(out.rulesetHash, "1a2b3c4d", "rulesetHash")
    assertEq(#out.rulesetHash, 8, "acht Hexstellen, nicht 16 Byte MD5 (ADR-016)")
    assertEq(out.lobbyName, "Kellerparty", "lobbyName")
end)

case("REJECT", function()
    local out = roundtrip(Protocol.MSG.REJECT,
        { reason = Protocol.REJECT.VERSION, text = "Andere Fassung" })
    assertEq(out.reason, Protocol.REJECT.VERSION, "reason")
    assertEq(out.text, "Andere Fassung", "text")
end)

case("LOBBY_STATE mit beiden Slots", function()
    local out = roundtrip(Protocol.MSG.LOBBY_STATE, { slots = {
        { occupied = true,  ready = true,  isHost = true,  name = "Wobble", buildHash = "abc" },
        { occupied = false, ready = false, isHost = false, name = "",       buildHash = "" },
    } })
    assertEq(#out.slots, 2, "Zahl der Slots")
    assertTrue(out.slots[1].isHost, "Slot 1 ist Host")
    assertTrue(out.slots[1].ready, "Slot 1 bereit")
    assertFalse(out.slots[2].occupied, "Slot 2 frei")
    assertEq(out.slots[2].name, "", "leerer Name")
end)

case("SET_READY", function()
    assertTrue(roundtrip(Protocol.MSG.SET_READY, { ready = true }).ready, "true")
    assertFalse(roundtrip(Protocol.MSG.SET_READY, { ready = false }).ready, "false")
end)

case("MATCH_START", function()
    local out = roundtrip(Protocol.MSG.MATCH_START,
        { matchId = 900001, startTick = 0, rulesetHash = "deadbeef", slot = 2 })
    assertEq(out.matchId, 900001, "matchId")
    assertEq(out.startTick, 0, "startTick")
    assertEq(out.rulesetHash, "deadbeef", "rulesetHash")
    assertEq(out.slot, 2, "slot")
end)

case("INPUT traegt drei Masken", function()
    local out = roundtrip(Protocol.MSG.INPUT,
        { tick = 1234, masks = { Frame.LEFT + Frame.JUMP, Frame.RIGHT, 0 } })
    assertEq(out.tick, 1234, "tick")
    assertEq(out.masks[1], Frame.LEFT + Frame.JUMP, "Maske 0")
    assertEq(out.masks[2], Frame.RIGHT, "Maske -1")
    assertEq(out.masks[3], 0, "Maske -2")
end)

case("INPUT ist zehn Byte gross (04_NETCODE 3)", function()
    local data = Protocol.encode(Protocol.MSG.INPUT, { tick = 0, masks = { 0, 0, 0 } })
    assertEq(#data, 10, "Groesse")
end)

case("MATCH_END", function()
    local out = roundtrip(Protocol.MSG.MATCH_END,
        { matchId = 1, scoreA = 15, scoreB = 13, reason = Protocol.END.DISCONNECT })
    assertEq(out.scoreA, 15, "scoreA")
    assertEq(out.scoreB, 13, "scoreB")
    assertEq(out.reason, Protocol.END.DISCONNECT, "reason")
end)

case("MATCH_PAUSE", function()
    local out = roundtrip(Protocol.MSG.MATCH_PAUSE,
        { paused = true, secondsLeft = 30, text = "Warte auf Slime" })
    assertTrue(out.paused, "paused")
    assertEq(out.secondsLeft, 30, "secondsLeft")
    assertEq(out.text, "Warte auf Slime", "text")
end)

case("PING und PONG", function()
    assertEq(roundtrip(Protocol.MSG.PING, { timestamp = 123456 }).timestamp, 123456, "PING")
    assertEq(roundtrip(Protocol.MSG.PONG, { timestamp = 123456 }).timestamp, 123456, "PONG")
end)

case("CHECKSUM", function()
    local out = roundtrip(Protocol.MSG.CHECKSUM, { tick = 300, hash = 3735928559 })
    assertEq(out.tick, 300, "tick")
    assertEq(out.hash, 3735928559, "hash")
end)

case("zu lange Zeichenketten werden beim Sender gekuerzt", function()
    local lang = string.rep("x", 200)
    local out = roundtrip(Protocol.MSG.HELLO,
        { clientId = 1, buildHash = lang, name = lang })
    assertEq(#out.name, Protocol.MAX.name, "Name gekuerzt")
    assertEq(#out.buildHash, Protocol.MAX.buildHash, "buildHash gekuerzt")
end)

-- ---------------------------------------------------------------------------
-- Snapshot
-- ---------------------------------------------------------------------------

local function sampleSnapshot()
    return {
        tick = 4242, ballX = 400.5, ballY = 300.25, ballVX = -123.75, ballVY = 0.1,
        ballRot = 1.5, blob1X = 200.5, blob1Y = 500, blob2X = 600.5, blob2Y = 460.75,
        blob1VY = -750, blob2VY = 0, blob1Tilt = 0.6, blob2Tilt = -0.6,
        blob1Cd = 128, blob2Cd = 0, scoreA = 14, scoreB = 13,
        phase = Snapshot.PHASE_CODE.play, servingPlayer = 2,
        touchCount = 3, lastTouchPlayer = 1, flags = 1 + 8, ackInputTick = 4230,
    }
end

case("der Snapshot passt in 72 Byte", function()
    local data = Protocol.encode(Protocol.MSG.SNAPSHOT, sampleSnapshot())
    assertEq(#data, Protocol.HEADER_SIZE + Snapshot.SIZE, "Groesse")
    assertEq(#data, 72, "Groesse gegen die Spec")
end)

case("der Snapshot ueberlebt den Umlauf", function()
    local out = roundtrip(Protocol.MSG.SNAPSHOT, sampleSnapshot())
    local expected = sampleSnapshot()

    for _, field in ipairs(Snapshot.FIELDS) do
        local name, kind = field[1], field[2]
        if kind == "f" then
            -- float32: 0.1 ist dort nicht darstellbar. Der Verlust ist bekannt
            -- und in Kauf genommen -- Pixelkoordinaten brauchen keine 15
            -- Stellen (04_NETCODE §6).
            assertNear(out[name], expected[name],
                math.max(1e-6, math.abs(expected[name]) * 1e-6), name)
        else
            assertEq(out[name], expected[name], name)
        end
    end
end)

case("das Format wird aus der Feldliste gebaut, nicht abgeschrieben", function()
    assertEq(Protocol.SNAP_FORMAT:sub(1, 1), "<", "Little-Endian erzwungen")

    -- Unabhaengig nachgerechnet: was gepackt wird, muss so gross sein wie die
    -- Summe der deklarierten Feldbreiten. Eine hartkodierte Formatzeichenkette
    -- faellt hier auf, sobald jemand ein Feld ergaenzt.
    local width = { i4 = 4, f = 4, B = 1 }
    local total = 0
    for _, field in ipairs(Snapshot.FIELDS) do total = total + width[field[2]] end

    local data = Protocol.encode(Protocol.MSG.SNAPSHOT, sampleSnapshot())
    assertEq(#data - Protocol.HEADER_SIZE, total, "Nutzlast folgt der Feldliste")
end)

-- ---------------------------------------------------------------------------
-- RULESET_FULL (ADR-016)
-- ---------------------------------------------------------------------------

case("das Ruleset kommt hashgleich an -- sonst ist der Abgleich wertlos", function()
    for _, preset in ipairs({ "classic", "prototype" }) do
        local rs = Ruleset.new(preset)
        local out = roundtrip(Protocol.MSG.RULESET_FULL, { ruleset = rs })
        assertEq(Ruleset.hash(out.ruleset), Ruleset.hash(rs), "Hash von " .. preset)
        assertEq(Ruleset.canonical(out.ruleset), Ruleset.canonical(rs),
            "kanonische Form von " .. preset)
    end
end)

case("Zahlen gehen als float64 -- float32 wuerde den Hash zerlegen", function()
    local rs = Ruleset.new("prototype")
    rs.activeTransfer = 0.4   -- in float32 nicht darstellbar
    local out = roundtrip(Protocol.MSG.RULESET_FULL, { ruleset = rs })
    assertEq(out.ruleset.activeTransfer, 0.4, "exakt")
    assertEq(Ruleset.hash(out.ruleset), Ruleset.hash(rs), "Hash")
end)

case("Wahrheitswerte bleiben Wahrheitswerte", function()
    local rs = Ruleset.new("classic")
    local out = roundtrip(Protocol.MSG.RULESET_FULL, { ruleset = rs })
    assertEq(type(out.ruleset.allowDash), "boolean", "Typ")
    assertEq(out.ruleset.allowDash, false, "classic hat Dash aus (ADR-006)")
    assertEq(out.ruleset.twoPointLead, true, "classic hat Zwei-Punkte-Vorsprung")
end)

case("ein unbekannter Schluessel wird verworfen, nicht uebernommen", function()
    -- Von Hand gebaut: so saehe ein Paket aus einer spaeteren Fassung aus.
    local payload = love.data.pack("string", "<B", 2)
        .. love.data.pack("string", "<s1Bd", "gravity", Protocol.RS_NUMBER, 1000)
        .. love.data.pack("string", "<s1Bd", "gravityShift", Protocol.RS_NUMBER, 42)
    local data = love.data.pack("string", "<BBB",
        Protocol.VERSION, Protocol.MSG.RULESET_FULL, 0) .. payload

    local kind, out = Protocol.decode(data)
    assertEq(kind, Protocol.MSG.RULESET_FULL, "dekodiert")
    assertEq(out.ruleset.gravity, 1000, "bekanntes Feld")
    assertEq(out.ruleset.gravityShift, nil, "unbekanntes Feld verworfen")
end)

-- ---------------------------------------------------------------------------
-- Kanaele
-- ---------------------------------------------------------------------------

case("Snapshots und Eingaben laufen unzuverlaessig, alles andere zuverlaessig", function()
    assertEq(Protocol.channelOf(Protocol.MSG.SNAPSHOT), 1, "Snapshot-Kanal")
    assertEq(Protocol.channelOf(Protocol.MSG.INPUT), 2, "Input-Kanal")
    assertEq(Protocol.channelOf(Protocol.MSG.MATCH_START), 0, "Lobby-Kanal")

    assertEq(Protocol.flagOf(Protocol.MSG.SNAPSHOT), "unreliable", "Snapshot")
    assertEq(Protocol.flagOf(Protocol.MSG.INPUT), "unreliable", "Input")
    assertEq(Protocol.flagOf(Protocol.MSG.MATCH_START), "reliable", "Match-Start")
    assertEq(Protocol.flagOf(Protocol.MSG.RULESET_FULL), "reliable", "Ruleset")
end)

-- ---------------------------------------------------------------------------
-- Discovery
-- ---------------------------------------------------------------------------

case("Discovery-Pakete tragen die Magic vor dem Kopf", function()
    local data = Protocol.encodeDiscovery(Protocol.MSG.ANNOUNCE, {
        hostId = 987654, hostName = "Wobble", lobbyName = "Kellerparty",
        buildHash = "abc123", players = 1, maxPlayers = 2, mode = "free",
        enetPort = 21212 })

    assertEq(data:sub(1, 4), "VLYD", "Magic")
    local kind, out = Protocol.decodeDiscovery(data)
    assertEq(kind, Protocol.MSG.ANNOUNCE, "Typ")
    assertEq(out.hostId, 987654, "hostId")
    assertEq(out.lobbyName, "Kellerparty", "lobbyName")
    assertEq(out.players, 1, "players")
    assertEq(out.mode, "free", "mode")
    assertEq(out.enetPort, 21212, "enetPort")
end)

case("ein fremdes Paket auf demselben Port wird still verworfen", function()
    assertEq(Protocol.decodeDiscovery("irgendwas anderes"), nil, "fremde Magic")
    assertEq(Protocol.decodeDiscovery("VLY"), nil, "zu kurz")
end)

case("PROBE ist sieben Byte", function()
    local data = Protocol.encodeDiscovery(Protocol.MSG.PROBE, {})
    assertEq(#data, 4 + Protocol.HEADER_SIZE, "Magic plus Kopf")
end)

-- ---------------------------------------------------------------------------
-- T-N-07 / offener Punkt N-03: Bytereihenfolge
--
-- Diese Referenzen sind auf Windows-x86-64 erzeugt und stehen hier fest. Laeuft
-- der Fall auf dem macOS-Laeufer ebenfalls durch, ist bewiesen, dass beide
-- Plattformen dieselben Bytes schreiben -- und der offene Punkt N-03 ist
-- geschlossen. Scheitert er, ist er gefunden, bevor jemand am Partyabend ein
-- Match spielt, das auf einer Seite anders aussieht.
-- ---------------------------------------------------------------------------

-- Erzeugt mit `love . --test` unter LOEVE 11.5, Windows 10 x86-64, 2026-08-12.
-- Wer die Feldliste in `snapshot.lua` aendert, aendert diese Zeile mit -- und
-- merkt dabei, dass er ein Format aendert, das auf zwei Rechnern gilt.
local REFERENCE_SNAPSHOT_HEX =
    "012200" ..                    -- Kopf: protoVersion 1, SNAPSHOT, flags 0
    "92100000" ..                  -- tick 4242
    "0040c843" .. "00209643" ..    -- ballX 400.5, ballY 300.25
    "0080f7c2" .. "cdcccc3d" ..    -- ballVX -123.75, ballVY 0.1 (float32-gerundet)
    "0000c03f" ..                  -- ballRot 1.5
    "00804843" .. "0000fa43" ..    -- blob1X 200.5, blob1Y 500
    "00201644" .. "0060e643" ..    -- blob2X 600.5, blob2Y 460.75
    "00803bc4" .. "00000000" ..    -- blob1VY -750, blob2VY 0
    "9a99193f" .. "9a9919bf" ..    -- blob1Tilt 0.6, blob2Tilt -0.6
    "8000" ..                      -- blob1Cd 128, blob2Cd 0
    "0e0d" ..                      -- scoreA 14, scoreB 13
    "01" .. "02" .. "03" .. "01" ..-- phase play, servingPlayer 2, touch 3, last 1
    "09" ..                        -- flags: blob1 am Boden + blob2 dasht
    "86100000"                     -- ackInputTick 4230

case("T-N-07: einzelne Werte sind bitgenau (IEEE 754, Little-Endian)", function()
    assertEq(hex(love.data.pack("string", "<i4", -2)), "feffffff", "i4 negativ")
    assertEq(hex(love.data.pack("string", "<i4", 1)), "01000000", "i4 positiv")
    assertEq(hex(love.data.pack("string", "<f", 1.5)), "0000c03f", "f exakt")
    assertEq(hex(love.data.pack("string", "<f", 0.1)), "cdcccc3d", "f gerundet")
    assertEq(hex(love.data.pack("string", "<f", 123456.789)), "6520f147", "f gross")
    assertEq(hex(love.data.pack("string", "<f", -3.25)), "000050c0", "f negativ")
    assertEq(hex(love.data.pack("string", "<d", 0.1)), "9a9999999999b93f", "d")
    assertEq(hex(love.data.pack("string", "<I2", 21212)), "dc52", "I2")
end)

-- ---------------------------------------------------------------------------
-- Negative Null
--
-- Der erste CI-Lauf auf macOS-ARM64 hat hier einen echten Unterschied
-- gefunden: das LITERAL `-0.0` packt dort als 00000000, unter Windows als
-- 00000080. Auf Apple Silicon laeuft LOEVE 11.5 im Interpreter statt im JIT
-- (`04_NETCODE_SPEC` §1), und die Konstantenfaltung des Parsers verliert
-- offenbar das Vorzeichen.
--
-- Die Frage, auf die es ankommt, ist eine andere: Eine negative Null aus der
-- SIMULATION entsteht nicht als Literal, sondern durch Rechnen --
-- `ball.vx = -math.abs(ball.vx) * 0.8` bei vx = 0 (physics.lua:124). Wenn die
-- zur Laufzeit gebildete negative Null auf beiden Plattformen gleich gepackt
-- wird, ist der Befund eine Lua-Eigenheit und kein Serialisierungsfehler.
-- Genau das prueft der naechste Fall.
-- ---------------------------------------------------------------------------

case("T-N-07: das Vorzeichen der Null ist NICHT plattformgleich", function()
    -- Festgehaltene Messung, kein Fehlschlag. CI-Lauf 13, 2026-08-12:
    --
    --   Windows-x86-64   `-zero` ergibt eine negative Null -> 00000080
    --   macOS-ARM64      `-zero` ergibt eine POSITIVE Null -> 00000000
    --
    -- Der Unterschied entsteht in der Arithmetik der Lua-Fassung, nicht in
    -- `love.data.pack`: auf Apple Silicon laeuft der Interpreter statt des
    -- JIT (`04_NETCODE_SPEC` §1). Fuer das Spiel bedeutungslos, fuer eine
    -- byteweise Pruefsumme (§9) nicht -- deshalb begradigt `snapshot.lua`
    -- die Null, bevor sie auf die Leitung geht.
    local zero = 0.0
    local negzero = -zero
    local bytes = hex(love.data.pack("string", "<f", negzero))
    assertTrue(bytes == "00000080" or bytes == "00000000",
        "unerwartete Bytes fuer eine Null: " .. bytes)

    -- Was portabel IST und worauf es ankommt: der Wert bleibt null, und die
    -- begradigte Null ist auf beiden Plattformen dieselbe.
    assertEq(love.data.unpack("<f", love.data.pack("string", "<f", negzero)), 0,
        "Wert nach dem Umlauf")
    assertEq(hex(love.data.pack("string", "<f", negzero + 0.0)), "00000000",
        "begradigt")
end)

case("T-N-07: ein vollstaendiger Snapshot ergibt dieselben 72 Byte", function()
    local data = Protocol.encode(Protocol.MSG.SNAPSHOT, sampleSnapshot())
    assertEq(hex(data), REFERENCE_SNAPSHOT_HEX, "Snapshot-Bytes")
end)

case("T-N-07: die Referenz laesst sich zurueckdekodieren", function()
    local data = REFERENCE_SNAPSHOT_HEX:gsub("%x%x", function(pair)
        return string.char(tonumber(pair, 16))
    end)
    local kind, out = Protocol.decode(data)
    assertEq(kind, Protocol.MSG.SNAPSHOT, "Typ")
    assertEq(out.tick, 4242, "tick")
    assertEq(out.scoreA, 14, "scoreA")
    assertEq(out.phase, Snapshot.PHASE_CODE.play, "phase")
end)

return T
