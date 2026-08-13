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
local Checksum   = require("src.net.checksum")
local Prediction = require("src.net.prediction")
local Frame      = require("src.input.frame")
local SnapEvents = require("src.render.snapshot_events")

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

-- `pred` ist optional und faehrt die Vorhersage des Gastes mit (M3-01). Sie
-- laeuft hier genau so wie in `net_game.lua`: Snapshot anwenden, Kosmetik
-- ableiten, abgleichen, einen Tick weiterrechnen. Das ist der Punkt, an dem
-- sich zeigt, ob die Zuordnung ueber `ackInputTick` im echten
-- Nachrichtenfluss stimmt -- headless laesst sich das nicht pruefen, weil es
-- dort keinen Nachrichtenfluss gibt.
local function runMatch(host, client, hostState, clientState, ruleset, inputs, ticks, pred)
    local events = {}
    local applied = 0
    local prevSnap = nil

    for tick = 0, ticks - 1 do
        local pair = inputs and inputs[(tick % #inputs) + 1] or { 0, 0 }

        -- Client: eigene Eingabe abschicken
        client:update(0)
        local inputTick = client.tick
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

            if pred then
                local derived = SnapEvents.diff(prevSnap, snap, ruleset)
                pred:reconcile(snap, SnapEvents.isTakeover(derived))
                prevSnap = snap
            end
        end

        if pred then
            pred:advance(pair[2], clientState.match.phase, inputTick)
            pred:writeInto(clientState.blobs[2])
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
    -- Siehe `tools/tournament_selftest.lua`: ohne das hinterlaesst ein
    -- haengender CI-Lauf ein leeres Protokoll.
    pcall(function() io.stdout:setvbuf("no") end)

    print("[net] Selbsttest -- Host und Client in einem Prozess")
    print("[net] love " .. table.concat({ love.getVersion() }, ".", 1, 3))

    -- Die Spielszene laesst sich hier nicht AUSFUEHREN -- sie braucht Bild
    -- und Ton, und dieser Lauf hat beides nicht. Uebersetzen laesst sie sich
    -- trotzdem, und ein Tippfehler in der Datei, die alles zusammenhaengt,
    -- faellt sonst erst beim Anpfiff auf.
    for _, path in ipairs({ "src/app/scenes/net_game.lua",
                            "src/render/netstat.lua" }) do
        local chunk, err = love.filesystem.load(path)
        if not check(chunk ~= nil, path .. " laesst sich uebersetzen") then
            print("       " .. tostring(err))
        end
    end

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

    local pred = Prediction.new(2, ruleset)
    pred:reset(clientState.blobs[2])

    local ticks = math.min(600, replay and replay.count or 300)
    local applied = runMatch(host, client, hostState, clientState, ruleset,
        replay and replay.inputs or nil, ticks, pred)

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

    -- --- Vorhersage (M3-01) -----------------------------------------------
    --
    -- Im Loopback geht kein Paket verloren. Genau deshalb ist das hier eine
    -- harte Aussage: Bleibt die Vorhersage trotzdem stehen, stimmt die
    -- Zuordnung ueber `ackInputTick` nicht -- und im WLAN waere das nicht
    -- mehr von Jitter zu unterscheiden.
    print(string.format("[net] Vorhersage: %d verglichen, %d korrigiert, "
        .. "%d uebernommen, %d uebersprungen",
        pred.compared, pred.corrections, pred.takeovers, pred.skipped))

    check(pred.compared > ticks * 0.5,
        "die Vorhersage wird laufend abgeglichen (" .. pred.compared .. " Vergleiche)")
    check(pred.corrections <= pred.compared * 0.02,
        string.format("und korrigiert fast nie: %d von %d Vergleichen",
            pred.corrections, pred.compared))
    check(math.abs(clientState.blobs[2].x - hostState.blobs[2].x) < 3.0,
        string.format("der vorhergesagte Blob steht beim Host (Host %.2f, Gast %.2f)",
            hostState.blobs[2].x, clientState.blobs[2].x))

    -- --- Vorhersage unter Eingabeverlust ----------------------------------
    --
    -- Im sauberen Loopback bleibt der Korrekturzaehler bei null. Das ist das
    -- richtige Ergebnis und zugleich ein Problem: ein Zaehler, der nie
    -- zaehlt, koennte auch abgeklemmt sein. Also wird hier absichtlich Eingabe
    -- unterschlagen -- der Host wiederholt dann die letzte Maske (§7), und
    -- genau das ist der Vorhersagefehler, den M3-01 sichtbar machen soll.
    --
    -- BERICHTIGT 2026-08-13, nachdem der Fall in der CI auf macOS umfiel und
    -- auf Windows nicht:
    --
    -- Vorher wurden drei AUFEINANDERFOLGENDE Pakete von fuenfzehn
    -- unterschlagen, mit der Begruendung, damit sei die dreifache Redundanz
    -- ueberwunden. Das rechnet sich nicht auf. Ein Paket traegt {t, t-1, t-2};
    -- faellt t, t+1 und t+2 aus, dann bringt Paket t+3 die Masken t+1 und t+2
    -- doch wieder mit. Unwiederbringlich verloren war also GENAU EIN Tick --
    -- und ob ein einzelner Tick mehr als 2 px Abweichung erzeugt, haengt
    -- daran, wo im Replay er landet. Windows fiel auf die eine Seite, macOS
    -- auf die andere. Ein Test, der so entscheidet, prueft das Replay und
    -- nicht die Vorhersage.
    --
    -- Jetzt faellt die Eingabe fuer ein zusammenhaengendes Fenster ganz aus.
    -- Der Host wiederholt darin die letzte Maske, waehrend der Gast weiter
    -- mit seinen echten Masken vorhersagt -- die Abweichung ist damit nicht
    -- wahrscheinlich, sondern zwingend, solange der Spieler sich ueberhaupt
    -- bewegt. Danach bleiben 100 Ticks, in denen der Blob wieder aufschliesst;
    -- die Korrektur laeuft laut §8 ueber vier.
    --
    -- Unterschlagen wird im WERKZEUG, nicht im Spiel: `client.send` wird fuer
    -- die Dauer des Laufs umgehaengt. Ein Testschalter im ausgelieferten Code
    -- waere ein Schalter, den irgendwann jemand findet.
    local BLACKOUT_FROM, BLACKOUT_TO = 20, 140

    local realSend = client.send
    local sendTick = 0
    client.send = function(this, msgType, payload)
        if msgType == Protocol.MSG.INPUT then
            sendTick = sendTick + 1
            if sendTick > BLACKOUT_FROM and sendTick <= BLACKOUT_TO then
                return true
            end
        end
        return realSend(this, msgType, payload)
    end

    -- Und die Eingabe kommt fuer diesen Lauf NICHT aus dem Replay.
    --
    -- Auch das ist eine Berichtigung vom 2026-08-13: Mit den aufgezeichneten
    -- Masken haengt die Aussage daran, ob der Gast im getroffenen Ausschnitt
    -- ueberhaupt laeuft -- gemessen eine einzige Korrektur, und das ist zu
    -- nahe an der Null fuer eine Zusicherung. Gefragt ist hier nicht, was in
    -- R-05 passiert, sondern ob der Zaehler auf einen echten Eingabeverlust
    -- reagiert. Also links, rechts, links: Der Host wiederholt im Ausfall die
    -- letzte Maske und laeuft damit zwangslaeufig in die falsche Richtung,
    -- waehrend der Gast die Wende schon vorhersagt.
    --
    -- Gewendet wird alle 20 Ticks, damit der Blob nicht an der Wand parkt --
    -- dort stuende auch die wiederholte Maske still und es gaebe nichts zu
    -- korrigieren.
    --
    -- Die letzten 60 Ticks steht er still, und das ist kein Beiwerk: Der
    -- Abgleich unten vergleicht die Position des vorhergesagten Blobs mit der
    -- des Hosts auf 3 px genau. An einem LAUFENDEN Blob ist diese Aussage
    -- nicht zu halten -- allein der Anzeigepuffer von zwei Ticks (§8) sind bei
    -- Laufgeschwindigkeit rund 13 px, und man wuerde den Puffer messen statt
    -- die Vorhersage. Steht er, ist die Aussage wieder die, die sie sein soll:
    -- Der Gast hat aufgeschlossen.
    local moving = {}
    for i = 1, 240 do
        if i > 180 then
            moving[i] = { 0, 0 }
        else
            local right = (math.floor((i - 1) / 20) % 2) == 0
            moving[i] = { 0, Frame.encode({ right = right, left = not right }) }
        end
    end

    local corrBefore = pred.corrections
    runMatch(host, client, hostState, clientState, ruleset, moving, 240, pred)
    client.send = realSend

    local lossy = pred.corrections - corrBefore
    print(string.format("[net] %d Ticks ohne Eingabe: %d Korrekturen",
        BLACKOUT_TO - BLACKOUT_FROM, lossy))
    check(lossy > 0,
        "bei echtem Eingabeverlust schlaegt der Korrekturzaehler an (" .. lossy .. ")")
    check(math.abs(clientState.blobs[2].x - hostState.blobs[2].x) < 3.0,
        string.format("und der Blob steht danach wieder beim Host (%.2f gegen %.2f)",
            hostState.blobs[2].x, clientState.blobs[2].x))

    -- --- Desync-Detektor (M3-03) ------------------------------------------
    print(string.format("[net] Pruefsummen: %d geprueft, %d abweichend, %d ohne Snapshot",
        client.stats.checked, client.stats.desync, client.stats.missing))

    check(client.stats.checked > 0,
        "Pruefsummen kommen an und werden verglichen (" .. client.stats.checked .. ")")
    check(client.stats.desync == 0,
        "keine Abweichung bei gleichem Build (" .. client.stats.desync .. ")")

    -- Ein Detektor, der nie anschlaegt, koennte auch kaputt sein. Also einmal
    -- absichtlich falsch fuettern -- in beiden Reihenfolgen, denn beide
    -- kommen im Betrieb vor.
    local probe = {}
    for k, v in pairs(client.latest or {}) do probe[k] = v end
    probe.tick = Checksum.INTERVAL * 1000     -- weit weg von allem Echten

    local before = client.stats.desync
    client:rememberHash(probe)
    client:compareChecksum({ tick = probe.tick, hash = 0xDEADBEEF })
    check(client.stats.desync == before + 1,
        "eine falsche Pruefsumme wird erkannt (Snapshot zuerst)")

    probe.tick = probe.tick + Checksum.INTERVAL
    client:compareChecksum({ tick = probe.tick, hash = 0xDEADBEEF })
    client:rememberHash(probe)
    check(client.stats.desync == before + 2,
        "auch, wenn die Pruefsumme vorlaeuft")

    -- Und ein richtiger Wert darf NICHT anschlagen -- sonst prueft der Fall
    -- oben nur, dass der Zaehler zaehlt.
    probe.tick = probe.tick + Checksum.INTERVAL
    local checkedBefore = client.stats.checked
    local honest = Checksum.ofBytes(Protocol.encode(Protocol.MSG.SNAPSHOT, probe))
    client:rememberHash(probe)
    client:compareChecksum({ tick = probe.tick, hash = honest })
    check(client.stats.desync == before + 2 and client.stats.checked == checkedBefore + 1,
        "eine richtige Pruefsumme geht durch")

    client.stats.desync = before

    -- --- Aufstau (T-N-08) -------------------------------------------------
    for tick = 1, 200 do host:publishSnapshot(hostState, 10000 + tick) end
    pump(0.4, host)
    local drained = client:service()
    check(drained > 0, "der Client leert die Queue in einem Durchlauf ("
          .. drained .. " Ereignisse, T-N-08)")
    pump(0.2, host, client)
    check(client:service() == 0, "danach ist die Queue leer")

    -- --- Abweichendes Regelwerk (T-N-06) ----------------------------------
    --
    -- Der Gast hat das Regelwerk des Hosts empfangen. Wir verbiegen seine
    -- Kopie und lassen den Host das Match erneut ansagen: der Hashvergleich
    -- aus §10 muss das merken und den Start verhindern -- mit Klartext.
    local blocked, blockText = false, nil
    local savedGravity = client.ruleset.gravity
    client.ruleset.gravity = savedGravity + 1
    client.onEvent = function(kind, text)
        if kind == "failed" then blocked, blockText = true, text end
    end
    client:onMatchStart({ matchId = 99, startTick = 0,
        rulesetHash = host:rulesetHash(), slot = 2 })
    check(blocked, "abweichendes Regelwerk verhindert den Start (T-N-06)")
    check(blockText ~= nil and blockText:find("Regelwerk") ~= nil,
        "und zwar im Klartext: " .. tostring(blockText))
    client.ruleset.gravity = savedGravity
    client.onEvent = function() end
    client.state = "playing"

    -- --- Trennung (T-N-04) ------------------------------------------------
    local sawWalkover = false
    host.onEvent = function(kind) if kind == "walkover" then sawWalkover = true end end

    client:close()
    local paused = waitFor(8, function() return host.paused end, host)
    check(paused, "der Host pausiert nach der Trennung (T-N-04)")
    if paused then
        check(host:secondsLeft() > 0 and host:secondsLeft() <= Host.RECONNECT_SECONDS,
            "das 30-s-Fenster laeuft: " .. host:secondsLeft() .. " s")
        check(host.lobby.slots[2].occupied,
            "der Slot bleibt belegt -- die clientId ist der Schluessel")

        -- Das Fenster vorstellen, statt 30 s zu warten: gemessen wird, ob der
        -- Ablauf die Meldung ausloest, nicht ob die Uhr geht.
        host.pauseUntil = host:now() - 1
        pump(0.1, host)
        check(sawWalkover, "nach Ablauf des Fensters meldet der Host Walkover")
        host.pauseUntil = host:now() + Host.RECONNECT_SECONDS
        host.onEvent = function() end
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

    -- --- Der Host schliesst die Lobby (T-N-10) ----------------------------
    local lost = false
    if again then
        again.onEvent = function(kind) if kind == "failed" then lost = true end end
    end
    beacon:close()
    host:close()
    if again then
        waitFor(6, function() return lost end, again)
        check(lost, "der Gast erfaehrt das Ende der Lobby (T-N-10)")
        check(again.message ~= "", "mit Klartext: " .. tostring(again.message))
        again:close()
    end

    browser:close()

    return failures
end

-- ---------------------------------------------------------------------------
-- Autopilot: das ECHTE Spiel, beide Rollen, ohne Hand am Gerät
--
--   love . --net-auto-host
--   love . --net-auto-client[=IP]
--
-- Fuehrt Menue, Lobby und Match durch, speist beiden Seiten einen festen
-- Eingabeplan ein und legt am Ende einen Screenshot in den Save-Ordner. Damit
-- laesst sich der Weg vom Klick bis zum fliegenden Ball pruefen, ohne dass
-- jemand zwei Fenster nebeneinander bedient -- und der Beweis ist ein Bild,
-- keine Behauptung.
-- ---------------------------------------------------------------------------

local Frame = require("src.input.frame")

-- Fester Eingabeplan. Tick 1 ist ein Sprung, damit der Aufschlag zustande
-- kommt; danach laeuft der Blob hin und her, damit im Bild etwas passiert.
local function scriptedMask(slot, tick)
    if slot == 1 then
        if tick < 4 then return Frame.JUMP end
        if tick % 120 < 60 then return Frame.RIGHT end
        return Frame.LEFT
    end
    if tick % 90 < 45 then return Frame.LEFT end
    return Frame.RIGHT
end

function M.installAutopilot(App, role, address)
    local Scene = require("src.app.scene")
    local baseUpdate = love.update
    local frames, ticks, shot = 0, 0, false
    local self_probe   -- Browser, der waehrend des Matches sucht

    print("[auto] Rolle " .. role .. (address and (" -> " .. address) or ""))
    if role == "host" then
        App.hostLobby()
    else
        App.joinLobby(address or "127.0.0.1", Protocol.PORT_ENET)
    end

    love.update = function(dt)
        baseUpdate(dt)
        frames = frames + 1

        local top = Scene.top()
        if not top then return end

        if top.name == "lobby" then
            if role == "host" then
                if top.host and top.host.lobby:isStartable() then top:keypressed("return") end
            elseif top.client and top.client.state == "lobby" and not top.ready then
                top:keypressed("return")
            end

        elseif top.name == "net_game" then
            if not top.overlay then top:keypressed("f3") end

            -- Der Fall aus D2: Findet ein Suchender den Host noch, waehrend
            -- dieser spielt? Bis 2026-08-12 nicht -- die Bake lag in der
            -- Lobbyszene und die bekommt waehrend des Matches kein `update`.
            if role == "host" and not top.beaconChecked then
                top.beaconChecked = true
                print("[auto] Bake im Match: " .. (top.beacon and "ja" or "NEIN"))
            end
            -- Revanche pruefen (gemeldet aus dem LAN-Test, 0.2.2): Nach dem
            -- Abpfiff muss `R` beim Host ein neues Match anpfeifen und den
            -- Gast mitnehmen. Der Autopilot zwingt das Ende herbei, statt auf
            -- 15 Punkte zu warten.
            if not top.rematchProbe and frames > 60 * 4 then
                top.rematchProbe = true
                if role == "host" then
                    top.state.match.score[1] = 1
                    top.state.match.score[2] = 0
                    top.state.match.phase = "gameover"
                    top.host:endMatch(1, 0, 0)
                    top.result = "Match beendet."
                    print("[auto] Abpfiff erzwungen, druecke R")
                    top:keypressed("r")
                end
            end
            if top.rematchProbe and frames % 120 == 0 then
                print(string.format("[auto] nach R: Phase %s, Stand %d:%d, Tick %d",
                    top.state.match.phase, top.state.match.score[1],
                    top.state.match.score[2], top.simTick))
            end

            if role == "client" and not self_probe then
                self_probe = Discovery.newBrowser({})
                if self_probe then self_probe:probe() end
            end
            if self_probe then
                self_probe:update()
                if frames % 120 == 0 then
                    print(string.format("[auto] Suche waehrend des Matches: %d Lobbys (%s)",
                        #self_probe:list(), self_probe:diagnostics()))
                end
            end
            -- Eingabeplan statt Tastatur: die Quelle ist austauschbar, genau
            -- dafuer gibt es sie (ADR-014).
            if not top.scripted then
                top.scripted = true
                local slot = (role == "host") and 1 or 2
                top.source = { poll = function()
                    ticks = ticks + 1
                    return scriptedMask(slot, ticks)
                end }
            end
        end

        if frames == 60 * 8 and not shot then
            shot = true
            love.graphics.captureScreenshot("net-" .. role .. ".png")
            print("[auto] Screenshot: " .. love.filesystem.getSaveDirectory()
                  .. "/net-" .. role .. ".png")
            if top.name == "net_game" then
                print(string.format("[auto] Stand %d:%d, Phase %s, Tick %d",
                    top.state.match.score[1], top.state.match.score[2],
                    top.state.match.phase, top.simTick))
            else
                print("[auto] steht in Szene: " .. tostring(top.name)
                      .. " -- Fehler: " .. tostring(top.error))
            end
        end

        if frames > 60 * 9 then love.event.quit() end
    end
end

-- ---------------------------------------------------------------------------
-- Zwei Prozesse
--
-- Beide Seiten spielen die aufgezeichnete Rallye ab und schlagen selbst auf,
-- wenn sie an der Reihe sind. Ohne diesen Zusatz endet der Lauf nach dem
-- ersten Seitenaus mit 0:0 -- ein Endstand, der auf beiden Seiten gleich ist,
-- ohne dass jemals etwas passiert waere. Ein Test, der nichts geschehen
-- laesst, prueft nichts.
-- ---------------------------------------------------------------------------

-- Aufschlagen heisst springen UND sich dabei zum Netz bewegen. Die Simulation
-- leitet die Sprungflanke aus dem Pegel ab (ADR-014), also muss der Pegel
-- zwischendurch fallen. Die Richtung bleibt waehrend des Aufstiegs anliegen:
-- ohne sie geht der Ball senkrecht hoch und faellt auf die eigene Seite --
-- gemessen, das Ergebnis war ein endloser Wechsel von Seitenaus bei 0:0.
local function serveAssist(state, slot, tick, baseMask)
    if state.match.phase ~= "serve" or state.match.servingPlayer ~= slot then
        return baseMask
    end

    local toNet = (slot == 1) and Frame.RIGHT or Frame.LEFT
    local phase = tick % 40
    if phase < 2 then return Frame.JUMP + toNet end
    if phase < 14 then return toNet end
    return 0
end

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
    local ticks = 3600            -- eine Minute Spielzeit als Obergrenze
    local target = 3              -- oder drei Punkte, was zuerst kommt

    for tick = 0, ticks - 1 do
        host:update(0)
        if not host.paused then
            local pair = inputs and inputs[(tick % #inputs) + 1] or { 0, 0 }
            local mine = serveAssist(state, 1, tick, pair[1])
            Step.tick(state, mine, host:inputFor(2), ruleset, events)
            host:publishSnapshot(state, tick)
        end
        beacon:update()
        love.timer.sleep(1 / 60)

        if state.match.score[1] + state.match.score[2] >= target then break end
        if state.match.phase == "gameover" then break end
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
    local applied, tick = 0, 0

    while client.state == "playing" do
        client:update(0)
        -- Der Gast schlaegt auf, wenn er an der Reihe ist -- er sieht die
        -- Phase im Snapshot, den der Host ihm schickt.
        client:pushInput(serveAssist(state, 2, tick, 0))
        local snap = client:nextSnapshot()
        if snap then
            Snapshot.apply(snap, state, ruleset)
            applied = applied + 1
        end
        tick = tick + 1
        love.timer.sleep(1 / 60)
    end

    print(string.format("[net] Client fertig: %d:%d, %d Snapshots, %d empfangen",
        state.match.score[1], state.match.score[2], applied, client.stats.received))
    client:close()
    return 0
end

return M
