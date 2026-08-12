-- ============================================================================
-- tests/lobby_test.lua -- Ebene B: Slots und Abgleich (M2-06, M2-07)
--
-- Der wichtigste Teil sind die drei Konsequenzen aus `04_NETCODE_SPEC` §5/§10.
-- Sie sind der Grund, warum am Partyabend niemand raetselt -- und der Fall,
-- der am leichtesten still verrutscht, ist der harmlose: ein abweichender
-- buildHash darf NICHT blockieren (T-N-06 prueft die Gegenrichtung).
--
-- love-frei.
-- ============================================================================

local Lobby = require("src.net.lobby")

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

local function newLobby()
    return Lobby.new({ hostName = "Wobble", lobbyName = "Kellerparty",
                       buildHash = "abc123", clientId = 1 })
end

local function finding(findings, kind)
    for _, f in ipairs(findings) do
        if f.kind == kind then return f end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------

case("der Host belegt Slot 1 und ist bereit -- er spielt mit", function()
    local lobby = newLobby()
    local host = lobby.slots[Lobby.HOST_SLOT]
    assertTrue(host.occupied, "belegt")
    assertTrue(host.isHost, "isHost")
    assertTrue(host.ready, "bereit")
    assertEq(host.name, "Wobble", "Name")
    assertEq(lobby:occupiedCount(), 1, "ein Platz belegt")
end)

case("ein Gast bekommt den freien Slot", function()
    local lobby = newLobby()
    local slot, how = lobby:claim(4711, "Slime", "abc123")
    assertEq(slot, 2, "Slot")
    assertEq(how, "join", "Art")
    assertEq(lobby:occupiedCount(), 2, "zwei Plaetze belegt")
end)

case("ist alles belegt, wird abgelehnt", function()
    local lobby = newLobby()
    lobby:claim(4711, "Slime", "abc123")
    local slot, how = lobby:claim(4712, "Gloop", "abc123")
    assertEq(slot, nil, "kein Slot")
    assertEq(how, "full", "Grund")
end)

case("dieselbe clientId bekommt ihren Slot zurueck -- das ist der Reconnect", function()
    local lobby = newLobby()
    local slot = lobby:claim(4711, "Slime", "abc123")
    lobby:setReady(slot, true)

    local again, how = lobby:claim(4711, "Slime", "abc123")
    assertEq(again, slot, "derselbe Slot")
    assertEq(how, "reconnect", "Art")
    assertEq(lobby:occupiedCount(), 2, "kein zweiter Platz verbraucht")
end)

case("der Host-Slot ist kein Rueckkehrer-Ziel (M2-10)", function()
    -- Zwei Instanzen auf einem Rechner teilen sich die Prefs-Datei und damit
    -- die clientId. Ohne diese Regel uebernimmt der Gast den Platz des Hosts,
    -- und die Lobby wird nie startbereit -- gemessen, nicht ausgedacht.
    local lobby = Lobby.new({ hostName = "Wobble", buildHash = "abc123", clientId = 1 })
    local slot, how = lobby:claim(1, "Slime", "abc123")
    assertEq(slot, 2, "der Gast bekommt Platz 2")
    assertEq(how, "join", "und zwar als Beitritt, nicht als Rueckkehr")
    assertEq(lobby.slots[1].name, "Wobble", "der Name des Hosts bleibt stehen")
    assertTrue(lobby.slots[1].isHost, "Platz 1 bleibt der Host")
end)

case("release gibt den Slot frei, den Host aber nicht", function()
    local lobby = newLobby()
    local slot = lobby:claim(4711, "Slime", "abc123")
    assertTrue(lobby:release(slot), "Gast freigegeben")
    assertEq(lobby:occupiedCount(), 1, "wieder frei")
    assertFalse(lobby:release(Lobby.HOST_SLOT), "der Host bleibt")
end)

case("startbereit ist erst, wenn alle da und alle bereit sind", function()
    local lobby = newLobby()
    assertFalse(lobby:isStartable(), "allein nicht")

    local slot = lobby:claim(4711, "Slime", "abc123")
    assertFalse(lobby:isStartable(), "Gast noch nicht bereit")

    lobby:setReady(slot, true)
    assertTrue(lobby:isStartable(), "jetzt")

    lobby:setReady(slot, false)
    assertFalse(lobby:isStartable(), "und wieder nicht")
end)

case("toMessage bildet alle Slots ab", function()
    local lobby = newLobby()
    lobby:claim(4711, "Slime", "def456")
    local msg = lobby:toMessage()
    assertEq(#msg.slots, Lobby.MAX_SLOTS, "Zahl der Slots")
    assertTrue(msg.slots[1].isHost, "Slot 1 ist der Host")
    assertEq(msg.slots[2].name, "Slime", "Name des Gastes")
    assertEq(msg.slots[2].buildHash, "def456", "Build des Gastes")
    -- Die clientId gehoert NICHT in die Nachricht: sie ist die Kennung fuer
    -- den Reconnect, keine Anzeige.
    assertEq(msg.slots[2].clientId, nil, "keine clientId auf der Leitung")
end)

-- ---------------------------------------------------------------------------
-- Abgleich: drei Pruefungen, drei Konsequenzen
-- ---------------------------------------------------------------------------

local HOST = { protoVersion = 1, rulesetHash = "1a2b3c4d", buildHash = "abc123" }

case("alles gleich ergibt keinen Befund", function()
    local findings = Lobby.compare(HOST, { protoVersion = 1,
        rulesetHash = "1a2b3c4d", buildHash = "abc123" })
    assertEq(#findings, 0, "Zahl der Befunde")
    assertEq(Lobby.worst(findings), nil, "kein schlimmster")
    assertFalse(Lobby.blocks(findings), "blockiert nicht")
end)

case("abweichende protoVersion wird hart abgelehnt", function()
    local findings = Lobby.compare(HOST, { protoVersion = 2,
        rulesetHash = "1a2b3c4d", buildHash = "abc123" })
    local f = finding(findings, "protoVersion")
    assertTrue(f ~= nil, "Befund vorhanden")
    assertEq(f.severity, Lobby.SEVERITY.REJECT, "Schwere")
    assertTrue(#f.text > 0, "Klartext, kein Timeout")
    assertTrue(Lobby.blocks(findings), "blockiert")
end)

case("bei falscher Protokollfassung wird nicht weitergeprueft", function()
    -- Die anderen Felder stammen aus einem Format, das wir nicht lesen koennen.
    -- Sie zusaetzlich zu bemaengeln waere geraten, nicht gemessen.
    local findings = Lobby.compare(HOST, { protoVersion = 2,
        rulesetHash = "ffffffff", buildHash = "zzz" })
    assertEq(#findings, 1, "genau ein Befund")
end)

case("abweichender rulesetHash blockiert den Start, aber nicht den Join", function()
    local findings = Lobby.compare(HOST, { protoVersion = 1,
        rulesetHash = "ffffffff", buildHash = "abc123" })
    local f = finding(findings, "rulesetHash")
    assertTrue(f ~= nil, "Befund vorhanden")
    assertEq(f.severity, Lobby.SEVERITY.BLOCK, "Schwere")
    assertTrue(Lobby.blocks(findings), "blockiert den Start")
    assertTrue(f.severity ~= Lobby.SEVERITY.REJECT, "aber keine Ablehnung beim Join")
end)

case("abweichender buildHash ist nur eine Warnung (T-N-06 Gegenprobe)", function()
    local findings = Lobby.compare(HOST, { protoVersion = 1,
        rulesetHash = "1a2b3c4d", buildHash = "999999" })
    local f = finding(findings, "buildHash")
    assertTrue(f ~= nil, "Befund vorhanden")
    assertEq(f.severity, Lobby.SEVERITY.WARN, "Schwere")
    -- Der Punkt der ganzen Uebung: ein kosmetischer Patch blockiert kein
    -- Turnier.
    assertFalse(Lobby.blocks(findings), "blockiert NICHT")
end)

case("mehrere Befunde: der schlimmste zaehlt", function()
    local findings = Lobby.compare(HOST, { protoVersion = 1,
        rulesetHash = "ffffffff", buildHash = "999999" })
    assertEq(#findings, 2, "zwei Befunde")
    assertEq(Lobby.worst(findings).kind, "rulesetHash", "der schlimmste")
    assertTrue(Lobby.blocks(findings), "blockiert")
end)

return T
