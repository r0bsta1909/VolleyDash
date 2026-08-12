-- ============================================================================
-- tools/net_selftest.lua -- Netzwerk-Selbsttest im Loopback (M2-10)
--
--   love . --net-selftest          Host und Client in EINEM Prozess
--   love . --net-host[=R-05]       Host, wartet auf einen Gast
--   love . --net-client[=IP]       Client, verbindet sich (Vorgabe 127.0.0.1)
--
-- Der Selbsttest ist der billige Fall: er beweist Protokoll, Handschlag,
-- Discovery, Eingabefluss und Snapshotweg, ohne dass ein zweiter Rechner
-- dafuer angefasst werden muss. Was er NICHT beweist, ist der Betrieb ueber
-- ein echtes Netz -- dafuer sind die beiden Prozessrollen da (D2,
-- `07_TEST_PLAN` §6).
--
-- Die Eingaben kommen aus den aufgezeichneten Referenz-Rallyes unter
-- tests/replays/. Damit ist der Netzwerktest wiederholbar statt handgespielt;
-- ein Endstand, der zweimal verschieden ausfaellt, ist dann ein Befund und
-- kein Zufall.
--
-- Temporaeres Werkzeug wie tools/reference_mode.lua: es haengt sich von aussen
-- an und wird nicht ausgeliefert (CC-02 §3).
-- ============================================================================

local World      = require("src.sim.world")
local State      = require("src.sim.state")
local Step       = require("src.sim.step")
local Rules      = require("src.sim.rules")
local Ruleset    = require("src.sim.ruleset")
local Protocol   = require("src.net.protocol")
local Snapshot   = require("src.net.snapshot")
local Host       = require("src.net.host")
local Client     = require("src.net.client")
local Discovery  = require("src.net.discovery")
local Lobby      = require("src.net.lobby")

local M = {}

-- Eigene Ports: der Selbsttest soll nicht mit einer laufenden Partie
-- kollidieren, wenn jemand nebenher spielt.
M.PORT_ENET      = 21292
M.PORT_DISCOVERY = 21293

local failures = 0
local function check(ok, what)
    if ok then
        print("  ok    " .. what)
    else
        failures = failures + 1
        print("  FAIL  " .. what)
    end
    return ok
end

local function now() return love.timer.getTime() end

-- Kurz warten und dabei beide Seiten bedienen. Blockierend ist hier richtig:
-- das ist ein Werkzeug, keine Spielschleife.
local function pump(seconds, ...)
    local parties = { ... }
    local until_ = now() + seconds
    while now() < until_ do
        for _, party in ipairs(parties) do party:update(0) end
        love.timer.sleep(0.001)
    end
end

local function waitFor(seconds, condition, ...)
    local parties = { ... }
    local until_ = now() + seconds
    while now() < until_ do
        for _, party in ipairs(parties) do party:update(0) end
        if condition() then return true end
        love.timer.sleep(0.001)
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Eingaben aus einer aufgezeichneten Rallye
-- ---------------------------------------------------------------------------

local function loadInputs(id)
    local Replay = require("tools.replay_source")
    local data = Replay.load("tests/replays/fixed60/" .. id .. ".json")
        or Replay.load("tests/replays/variable/" .. id .. ".json")
    if not data then return nil end
    return data
end

-- ---------------------------------------------------------------------------
-- Ein Match fahren
--
-- Der Host simuliert, der Client schickt Eingaben und zeigt Snapshots an --
-- genau die Aufgabenteilung aus `04_NETCODE_SPEC` §2. Die Szene macht spaeter
-- dasselbe, nur mit Bild.
-- ---------------------------------------------------------------------------

local function runMatch(host, client, hostState, clientState, ruleset, inputs, ticks)
    local events = {}
    local applied = 0

    for tick = 0, ticks - 1 do
        local pair = inputs and inputs[(tick % #inputs) + 1] or { 0, 0 }

        -- Client: eigene Eingabe abschicken
        client:update(0)
        client:pushInput(pair[2])

        -- Host: Ereignisse leeren, simulieren, Snapshot verteilen
        host:update(0)
        if not host.paused then
            Step.tick(hostState, pair[1], host:inputFor(2), ruleset, events)
            host:publishSnapshot(hostState, tick)
        end

        -- Client: anzeigen, was angekommen ist
        client:update(0)
        local snap = client:nextSnapshot()
        if snap then
            Snapshot.apply(snap, clientState, ruleset)
            applied = applied + 1
        end

        love.timer.sleep(0.0005)
    end

    -- Nachlauf: der Puffer des Clients haelt zwei Ticks zurueck.
    pump(0.3, host, client)
    while true do
        local snap = client:nextSnapshot()
        if not snap then break end
        Snapshot.apply(snap, clientState, ruleset)
        applied = applied + 1
    end

    return applied
end

-- ---------------------------------------------------------------------------
-- Selbsttest
-- ---------------------------------------------------------------------------

function M.selftest(App)
    print("[net] Selbsttest -- Host und Client in einem Prozess")
    print("[net] love " .. table.concat({ love.getVersion() }, ".", 1, 3))

    local ruleset = Ruleset.new("prototype")
    local hostState = State.new(ruleset)
    local clientState = State.new(ruleset)

    -- --- Host -------------------------------------------------------------
    local host, err = Host.new({
        port = M.PORT_ENET, ruleset = ruleset,
        hostName = "Wobble", lobbyName = "Selbsttest",
        buildHash = "selftest", clientId = 1,
    })
    if not check(host ~= nil, "Host bindet Port " .. M.PORT_ENET) then
        print("       " .. tostring(err))
        return failures
    end

    local beacon = Discovery.newHost({
        port = M.PORT_DISCOVERY,
        info = { hostId = 12345, hostName = "Wobble", lobbyName = "Selbsttest",
                 buildHash = "selftest", players = 1, maxPlayers = 2, mode = "free",
                 enetPort = M.PORT_ENET },
    })
    check(beacon ~= nil, "Discovery-Host bindet Port " .. M.PORT_DISCOVERY)

    -- --- Discovery --------------------------------------------------------
    local browser = Discovery.newBrowser({ port = M.PORT_DISCOVERY })
    check(browser ~= nil, "Browser bindet einen fluechtigen Port")

    browser:probe()
    local found = waitFor(3, function() return #browser:list() > 0 end, beacon, browser)
    check(found, "die Lobby erscheint in der Serverliste (T-N-09)")

    local entry = browser:list()[1]
    if entry then
        check(entry.lobbyName == "Selbsttest", "Lobbyname kommt an: "
              .. tostring(entry.lobbyName))
        check(entry.port == M.PORT_ENET, "ENet-Port kommt an: " .. tostring(entry.port))
        check(entry.players == 1 and entry.maxPlayers == 2, "Spielerzahl kommt an")
        -- Derselbe Host antwortet ueber Loopback UND ueber die LAN-Adresse.
        -- Zwei Eintraege waeren ein Bedienfehler mit Ansage.
        check(#browser:list() == 1, "eine Lobby, ein Eintrag (auch lokal): "
              .. #browser:list())
    end

    -- --- Verbinden --------------------------------------------------------
    local client, cerr = Client.new({
        address = entry and entry.address or "127.0.0.1",
        port = entry and entry.port or M.PORT_ENET,
        clientId = 4711, name = "Slime", buildHash = "selftest",
    })
    if not check(client ~= nil, "Client oeffnet einen Socket") then
        print("       " .. tostring(cerr))
        host:close()
        return failures
    end

    local joined = waitFor(5, function() return client.state == "lobby" end, host, client)
    check(joined, "Handschlag: HELLO -> WELCOME")
    check(client.slot == 2, "der Gast bekommt Slot 2, war " .. tostring(client.slot))
    check(client.ruleset ~= nil, "das Ruleset kommt vom Host (ADR-005)")
    if client.ruleset then
        check(Ruleset.hash(client.ruleset) == Ruleset.hash(ruleset),
            "der Ruleset-Hash stimmt ueberein")
    end
    check(client.rulesetHash == Ruleset.hash(ruleset),
        "WELCOME traegt denselben Hash")
    check(#client.lobbySlots == Lobby.MAX_SLOTS, "LOBBY_STATE traegt beide Slots")

    -- --- Bereit und Start -------------------------------------------------
    client:setReady(true)
    local ready = waitFor(2, function() return host.lobby:isStartable() end, host, client)
    check(ready, "SET_READY erreicht den Host")

    host:startMatch()
    local started = waitFor(2, function() return client.state == "playing" end, host, client)
    check(started, "MATCH_START erreicht den Client")

    -- --- Ein Ballwechsel --------------------------------------------------
    local replay = loadInputs("R-05")
    check(replay ~= nil, "Referenz-Rallye R-05 geladen")

    Rules.resetBall(hostState, ruleset, 1, {})
    hostState.match.inProgress = true
    hostState.rally.serveTimer = 2.0
    hostState.blobs[1].x = hostState.ball.x
    hostState.blobs[1].y = hostState.ball.y + ruleset.blobRadius

    local ticks = math.min(600, replay and replay.count or 300)
    local applied = runMatch(host, client, hostState, clientState, ruleset,
        replay and replay.inputs or nil, ticks)

    print(string.format("[net] %d Ticks gefahren, %d Snapshots angewandt, "
        .. "%d empfangen, %d gehalten", ticks, applied,
        client.stats.received, client.stats.held))

    check(applied > ticks * 0.9, "fast jeder Tick kommt als Snapshot an")
    check(client.stats.received > 0, "Snapshots kommen an")
    check(host.queues[2].received > 0, "Eingaben des Gastes kommen an")
    check(host.queues[2].invalid == 0, "keine ungueltige Maske")

    -- Der Endstand ist die eigentliche Frage (T-N-01).
    check(clientState.match.score[1] == hostState.match.score[1]
          and clientState.match.score[2] == hostState.match.score[2],
        string.format("gleicher Endstand: Host %d:%d, Client %d:%d",
            hostState.match.score[1], hostState.match.score[2],
            clientState.match.score[1], clientState.match.score[2]))
    check(clientState.match.phase == hostState.match.phase,
        "gleiche Phase: " .. tostring(hostState.match.phase))
    check(math.abs(clientState.ball.x - hostState.ball.x) < 1.0,
        string.format("Ball an derselben Stelle (Host %.2f, Client %.2f)",
            hostState.ball.x, clientState.ball.x))

    -- --- Aufstau (T-N-08) -------------------------------------------------
    for tick = 1, 200 do host:publishSnapshot(hostState, 10000 + tick) end
    pump(0.4, host)
    local drained = client:service()
    check(drained > 0, "der Client leert die Queue in einem Durchlauf ("
          .. drained .. " Ereignisse, T-N-08)")
    pump(0.2, host, client)
    check(client:service() == 0, "danach ist die Queue leer")

    -- --- Trennung (T-N-04) ------------------------------------------------
    client:close()
    local paused = waitFor(8, function() return host.paused end, host)
    check(paused, "der Host pausiert nach der Trennung (T-N-04)")
    if paused then
        check(host:secondsLeft() > 0 and host:secondsLeft() <= Host.RECONNECT_SECONDS,
            "das 30-s-Fenster laeuft: " .. host:secondsLeft() .. " s")
        check(host.lobby.slots[2].occupied,
            "der Slot bleibt belegt -- die clientId ist der Schluessel")
    end

    -- --- Wiedereinstieg (T-N-05) ------------------------------------------
    local again = Client.new({
        address = "127.0.0.1", port = M.PORT_ENET,
        clientId = 4711, name = "Slime", buildHash = "selftest",
    })
    local back = waitFor(5, function() return again and again.state == "playing" end,
        host, again)
    check(back, "derselbe clientId steigt in das laufende Match ein (T-N-05)")
    check(not host.paused, "das Match laeuft weiter")

    if again then again:close() end
    pump(0.2, host)
    beacon:close()
    browser:close()
    host:close()

    return failures
end

-- ---------------------------------------------------------------------------
-- Zwei Prozesse
-- ---------------------------------------------------------------------------

function M.runHost(replayId)
    print("[net] Host auf Port " .. Protocol.PORT_ENET .. ", warte auf einen Gast")
    local ruleset = Ruleset.new("prototype")
    local state = State.new(ruleset)

    local host, err = Host.new({
        port = Protocol.PORT_ENET, ruleset = ruleset,
        hostName = "Harness", lobbyName = "Harness", buildHash = "harness", clientId = 1,
        onEvent = function(kind, a, b) print("[host] " .. kind .. " " .. tostring(a)
            .. " " .. tostring(b)) end,
    })
    if not host then print("[net] " .. tostring(err)) return 1 end

    local beacon = Discovery.newHost({
        info = { hostName = "Harness", lobbyName = "Harness", buildHash = "harness",
                 players = 1, maxPlayers = 2, mode = "free" },
    })

    local ok = waitFor(120, function() return host.lobby:isStartable() end, host, beacon)
    if not ok then print("[net] niemand gekommen") host:close() return 1 end

    host:startMatch()
    local replay = loadInputs(replayId or "R-05")
    local inputs = replay and replay.inputs or nil

    Rules.resetBall(state, ruleset, 1, {})
    state.match.inProgress = true
    state.rally.serveTimer = 2.0
    state.blobs[1].x = state.ball.x
    state.blobs[1].y = state.ball.y + ruleset.blobRadius

    local events = {}
    local ticks = math.min(1200, replay and replay.count or 600)
    for tick = 0, ticks - 1 do
        host:update(0)
        if not host.paused then
            local pair = inputs and inputs[(tick % #inputs) + 1] or { 0, 0 }
            Step.tick(state, pair[1], host:inputFor(2), ruleset, events)
            host:publishSnapshot(state, tick)
        end
        beacon:update()
        love.timer.sleep(1 / 60)
    end

    print(string.format("[net] Host fertig: %d:%d, Phase %s",
        state.match.score[1], state.match.score[2], state.match.phase))
    host:endMatch(state.match.score[1], state.match.score[2], Protocol.END.NORMAL)
    pump(0.5, host)
    beacon:close()
    host:close()
    return 0
end

function M.runClient(address)
    address = address or "127.0.0.1"
    print("[net] Client verbindet sich mit " .. address)

    local client, err = Client.new({
        address = address, port = Protocol.PORT_ENET,
        clientId = 4711, name = "Harness-Gast", buildHash = "harness",
        onEvent = function(kind, a) print("[client] " .. kind .. " " .. tostring(a)) end,
    })
    if not client then print("[net] " .. tostring(err)) return 1 end

    if not waitFor(30, function() return client.state == "lobby" end, client) then
        print("[net] kein Handschlag")
        client:close()
        return 1
    end
    client:setReady(true)

    if not waitFor(60, function() return client.state == "playing" end, client) then
        print("[net] kein Matchstart")
        client:close()
        return 1
    end

    local ruleset = client.ruleset
    local state = State.new(ruleset)
    local applied = 0

    while client.state == "playing" do
        client:update(0)
        client:pushInput(0)
        local snap = client:nextSnapshot()
        if snap then
            Snapshot.apply(snap, state, ruleset)
            applied = applied + 1
        end
        love.timer.sleep(1 / 60)
    end

    print(string.format("[net] Client fertig: %d:%d, %d Snapshots, %d empfangen",
        state.match.score[1], state.match.score[2], applied, client.stats.received))
    client:close()
    return 0
end

return M
