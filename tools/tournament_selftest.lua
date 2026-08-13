-- ============================================================================
-- tools/tournament_selftest.lua -- Turnier-Selbsttest im Loopback (M4-09)
--
--   love . --tournament-selftest
--
-- Prueft die zwei Abnahmen aus dem Handoff, die kein Headless-Test erreicht,
-- weil sie ueber echte Sockets laufen:
--
--   T-N-11  Vier parallele Matches, GLEICHZEITIGER Ergebnisversand, alle vier
--           korrekt im Bracket.
--   T-N-09  Drei gleichzeitige Turniere im selben Netz, alle unterscheidbar.
--
-- ---------------------------------------------------------------------------
-- Warum ein Prozess reicht -- und wofuer er nicht reicht
-- ---------------------------------------------------------------------------
--
-- Mehrere ENet-Wirte in einem Prozess funktionieren; gemessen 2026-08-13, und
-- der Lauf hier ist der stehende Beleg. Was er NICHT beweist, ist die
-- Firewall-Lage auf fremden Rechnern -- das bleibt D2 aus `07_TEST_PLAN` §6.
-- Was er dafuer kann: in der CI laufen und eine Regression finden, bevor
-- jemand acht Laptops aufklappt.
--
-- Der Aufbau ist der Auslegungsfall aus `05_TOURNAMENT` §8 und nicht der
-- bequeme: Der TURNIER-WIRT SPIELT MIT. Er haelt damit gleichzeitig einen Wirt
-- auf 21212 und -- sobald er selbst hostet -- einen zweiten auf einem
-- ephemeren Port. Genau die Lage, in der ein zweiter fester Port scheitern
-- wuerde.
--
-- Temporaeres Werkzeug wie `tools/net_selftest.lua`: es haengt sich von aussen
-- an und wird nicht ausgeliefert.
-- ============================================================================

local State           = require("src.sim.state")
local Step            = require("src.sim.step")
local Ruleset         = require("src.sim.ruleset")
local Protocol        = require("src.net.protocol")
local Discovery       = require("src.net.discovery")
local MatchRunner     = require("src.net.match_runner")
local TournamentHost  = require("src.net.tournament_host")
local TournamentClient= require("src.net.tournament_client")
local Session         = require("src.tournament.session")
local Model           = require("src.tournament.model")
local HostChoice      = require("src.tournament.host_choice")
local MatchStats      = require("src.tournament.match_stats")

local M = {}

-- Eigene Ports, damit der Lauf keine laufende Partie stoert.
M.PORT_ENET      = 21294
M.PORT_DISCOVERY = 21295

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

local function pumpAll(seconds, parties)
    local until_ = now() + seconds
    while now() < until_ do
        for _, p in ipairs(parties) do p:update(0) end
        love.timer.sleep(0.001)
    end
end

local function waitFor(seconds, condition, parties)
    local until_ = now() + seconds
    while now() < until_ do
        for _, p in ipairs(parties) do p:update(0) end
        if condition() then return true end
        love.timer.sleep(0.001)
    end
    return false
end

-- ---------------------------------------------------------------------------
-- T-N-09 -- drei Turniere im selben Netz
-- ---------------------------------------------------------------------------

function M.threeLobbies()
    print("[turnier] T-N-09 -- drei gleichzeitige Turniere im selben Netz")

    -- ---------------------------------------------------------------------
    -- ACHTUNG, hier stand bis 2026-08-13 ein falscher Aufbau
    --
    -- Der erste Anlauf liess drei Baken DENSELBEN Discovery-Port binden. Unter
    -- Windows und Linux geht das mit `SO_REUSEADDR`, unter macOS nicht -- und
    -- die CI hat das zu Recht gemeldet. Der Punkt ist aber nicht die
    -- Portteilung: Am Partyabend stehen die drei Turniere auf DREI RECHNERN,
    -- und dort bindet jeder seinen Port allein. Ein Test, der drei Binds auf
    -- einem Port erzwingt, prueft eine Lage, die es nie gibt, und faellt dann
    -- auf der Plattform um, auf der er es am wenigsten soll.
    --
    -- Geprueft wird deshalb, was T-N-09 wirklich fragt: Haelt der Browser drei
    -- Turniere auseinander? Die Baken binden dafuer fluechtige Ports und
    -- schicken ihre Ankuendigung direkt an den Browser -- genau das tun sie in
    -- echt auch, wenn sie einen `PROBE` unicast beantworten (§11).
    -- ---------------------------------------------------------------------

    local browser = Discovery.newBrowser({ port = M.PORT_DISCOVERY })
    if not check(browser ~= nil, "Browser bindet einen fluechtigen Port") then
        return
    end

    local _, browserPort = browser.udp:getsockname()
    browserPort = tonumber(browserPort)
    if not check(browserPort ~= nil, "der Browserport ist ablesbar") then
        browser:close()
        return
    end

    local beacons = {}
    for i = 1, 3 do
        local b = Discovery.newHost({
            port = 0,   -- fluechtig: in echt sitzt jede Bake auf einem eigenen Rechner
            info = { hostId = 9000 + i,
                     hostName = "Leiter " .. i,
                     lobbyName = "Turnier " .. i,
                     buildHash = "selftest",
                     players = i * 2, maxPlayers = 32,
                     mode = "tournament",
                     enetPort = M.PORT_ENET + i },
        })
        if not check(b ~= nil, "Bake " .. i .. " bindet einen eigenen Port") then
            for _, x in ipairs(beacons) do x:close() end
            browser:close()
            return
        end
        beacons[i] = b
    end

    for _, b in ipairs(beacons) do
        b:sendTo(b:announcePacket(), "127.0.0.1", browserPort)
    end

    local parties = { browser }
    local found = waitFor(4, function() return #browser:list() >= 3 end, parties)
    check(found, "alle drei erscheinen in der Liste, gefunden: " .. #browser:list())

    -- Der Punkt von T-N-09 ist nicht die Zahl, sondern die
    -- UNTERSCHEIDBARKEIT: drei Eintraege, drei Namen, drei ENet-Ports.
    local names, ports, ids = {}, {}, {}
    for _, e in ipairs(browser:list()) do
        names[e.lobbyName] = true
        ports[e.port] = true
        ids[e.hostId] = true
    end
    local function count(set)
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        return n
    end
    check(count(names) == 3, "drei verschiedene Turniernamen: " .. count(names))
    check(count(ports) == 3, "drei verschiedene ENet-Ports: " .. count(ports))
    check(count(ids) == 3, "drei verschiedene hostIds: " .. count(ids))

    local tournamentOnly = true
    for _, e in ipairs(browser:list()) do
        if e.mode ~= "tournament" then tournamentOnly = false end
    end
    check(tournamentOnly, "alle drei sind als Turnier gekennzeichnet")

    -- Und der Fall, fuer den die `hostId` ueberhaupt existiert: DASSELBE
    -- Turnier antwortet zweimal -- einmal ueber die Loopback-, einmal ueber
    -- die LAN-Adresse. Ohne Zusammenfuehrung stuende es zweimal in der Liste
    -- und man waehlte blind.
    beacons[1]:sendTo(beacons[1]:announcePacket(), "127.0.0.1", browserPort)
    beacons[1]:sendTo(beacons[1]:announcePacket(), "127.0.0.1", browserPort)
    pumpAll(0.3, parties)
    check(#browser:list() == 3,
        "eine zweite Antwort desselben Turniers ergibt keinen zweiten Eintrag: "
        .. #browser:list())

    browser:close()
    for _, b in ipairs(beacons) do b:close() end
end

-- ---------------------------------------------------------------------------
-- T-N-11 -- vier parallele Matches
-- ---------------------------------------------------------------------------

-- Ein kurzer, echter Simulationslauf, damit die zwei Statistiken aus
-- `05_TOURNAMENT` §11 auf demselben Weg entstehen wie im Spiel -- und nicht
-- als erfundene Zahl in einer Nachricht.
local function playedStats(ruleset)
    local s = State.new(ruleset)
    s.match.phase = "play"
    local st = MatchStats.new()
    for _ = 1, 400 do
        Step.tick(s, 0, 0, ruleset)
        st:observe(s)
    end
    return st:toReport()
end

function M.parallelMatches()
    print("[turnier] T-N-11 -- vier parallele Matches, gleichzeitiger Versand")

    local ruleset = Ruleset.new("classic")
    local choice  = HostChoice.new()

    -- Der Turnierleiter spielt mit. Er ist p_01 und meldet sich lokal an --
    -- ueber das Netz kommen die anderen sieben.
    local session = Session.new({
        id = "t_selftest", name = "Selbsttest", createdAt = 0,
        presence = "net",
        chooseHost = choice:chooser(),
        seedMode = "manual",
        ruleset = ruleset, rulesetHash = Ruleset.hash(ruleset),
        config = { format = "single_elim", parallelMatches = 4,
                   noShowTimeout = 600, bestOfDefault = 1, bestOfFinals = 1 },
    })
    local selfPid = session:addParticipant("Leiter", 0, 1)

    local thost, err = TournamentHost.new({
        port = M.PORT_ENET, session = session, hostChoice = choice,
        buildHash = "selftest", hostName = "Leiter", selfPid = selfPid,
    })
    if not check(thost ~= nil, "Turnier-Wirt bindet Port " .. M.PORT_ENET) then
        print("       " .. tostring(err))
        return
    end

    -- Der Turnier-Wirt misst sich selbst mit null (ADR-022).
    choice:sampleSelf(selfPid, now())

    local clients, parties = {}, { thost }
    local runners = {}     -- matchId -> { host = runner, guest = runner }
    local assignedTo = {}  -- matchId -> Zahl der Zuweisungen mit Rolle
    local openHostFor      -- vorwaerts, siehe unten

    local function noteAssigned(matchId)
        assignedTo[matchId] = (assignedTo[matchId] or 0) + 1
    end

    -- Der Zuweisungsempfaenger haengt AB DER ANMELDUNG, nicht erst nach der
    -- Auslosung: `TOURNAMENT_ASSIGN` geht genau einmal hinaus, und wer beim
    -- Aufruf nicht zuhoert, wartet den ganzen No-Show-Timer ab. (Genau das
    -- ist beim ersten Anlauf dieses Werkzeugs passiert.)
    local function attach(c)
        c.onEvent = function(kind, payload)
            if kind ~= "assign" then return end
            if payload.role == Protocol.ROLE.HOST then
                noteAssigned(payload.matchId)
                local r = openHostFor(payload.matchId, c.name)
                if r then c:accept(payload.matchId, r.port) end
                c.myMatch, c.myRunner = payload.matchId, r
            elseif payload.address ~= "" then
                local g, gerr = MatchRunner.newGuest({
                    matchId = payload.matchId, address = payload.address,
                    selfName = c.name, buildHash = "selftest",
                    clientId = c.clientId,
                })
                if check(g ~= nil, "Gast verbindet sich zu " .. payload.address) then
                    noteAssigned(payload.matchId)
                    runners[payload.matchId] = runners[payload.matchId] or {}
                    runners[payload.matchId].guest = g
                    parties[#parties + 1] = g
                    c:accept(payload.matchId, 0)
                    c.myMatch, c.myRunner = payload.matchId, g
                else
                    print("       " .. tostring(gerr))
                end
            end
        end
    end

    openHostFor = function(matchId, opener)
        local r, rerr = MatchRunner.newHost({
            matchId = matchId, ruleset = ruleset,
            selfName = opener, buildHash = "selftest", clientId = 1,
        })
        if not check(r ~= nil, "Match-Wirt fuer " .. matchId
                     .. " bindet einen ephemeren Port") then
            print("       " .. tostring(rerr))
            return nil
        end
        check(r.port ~= M.PORT_ENET and r.port > 0,
            "  und zwar NICHT " .. M.PORT_ENET .. ", sondern " .. tostring(r.port))
        runners[matchId] = runners[matchId] or {}
        runners[matchId].host = r
        parties[#parties + 1] = r
        return r
    end

    for i = 2, 8 do
        local c, cerr = TournamentClient.new({
            address = "127.0.0.1", port = M.PORT_ENET,
            clientId = 1000 + i, name = "Blob " .. i, buildHash = "selftest",
        })
        if not check(c ~= nil, "Teilnehmer " .. i .. " oeffnet einen Socket") then
            print("       " .. tostring(cerr))
            thost:close()
            return
        end
        attach(c)
        clients[#clients + 1] = c
        parties[#parties + 1] = c
    end

    local allJoined = waitFor(6, function()
        for _, c in ipairs(clients) do
            if c.state ~= "joined" then return false end
        end
        return true
    end, parties)
    check(allJoined, "alle sieben melden sich ueber das Netz an")
    check(session:count() == 8, "acht Teilnehmer, war " .. session:count())

    -- Der Turnierstand kommt als Log an, nicht als Zustand (ADR-023).
    local synced = waitFor(4, function()
        for _, c in ipairs(clients) do
            if c:logCount() < #session.t.log then return false end
        end
        return true
    end, parties)
    check(synced, "der Turnierstand kommt bei allen an")

    -- --- Auslosen ---------------------------------------------------------
    local drawn = session:drawBracket(now())
    check(drawn ~= false, "ausgelost")
    pumpAll(0.5, parties)

    local drawSynced = waitFor(4, function()
        for _, c in ipairs(clients) do
            if c:logCount() < #session.t.log then return false end
        end
        return true
    end, parties)
    check(drawSynced, "die Auslosung kommt bei allen an")

    -- Und sie ist bei allen DIESELBE. Ein abgeleiteter Zustand, der auf zwei
    -- Rechnern verschieden ausfaellt, waere der teuerste Fehler des Abends.
    local sameBracket = true
    for _, c in ipairs(clients) do
        for _, id in ipairs(session.t.matchOrder) do
            local a, b = session.t.matches[id], c.session.t.matches[id]
            if not b or a.slotA ~= b.slotA or a.slotB ~= b.slotB then
                sameBracket = false
            end
        end
    end
    check(sameBracket, "alle sehen dasselbe Bracket")

    session:tick(now())
    pumpAll(0.5, parties)
    thost:update(now())

    -- `parallelMatches = 4`, acht Teilnehmer: Alle vier Erstrundenmatches sind
    -- gleichzeitig dran. Gezaehlt werden sie ueber die AUFRUFE und nicht ueber
    -- den Status -- ein Match, das inzwischen schon laeuft, ist aufgerufen
    -- WORDEN, und ein Zaehlwerk, das nur die Gegenwart sieht, misst hier die
    -- Geschwindigkeit der Schleife statt der Software.
    local called = {}
    for _, id in ipairs(session.t.matchOrder) do
        local st = session.t.matches[id].status
        if st == Model.STATUS.READY or st == Model.STATUS.LIVE then
            called[#called + 1] = id
        end
    end
    check(#called == 4, "vier Matches gleichzeitig aufgerufen, waren " .. #called)

    -- --- Rollen und Sockets ----------------------------------------------
    -- Die Zuweisung des Leiters: Er hostet, wo er dran ist (RTT null).
    local leaderMatch
    for _, id in ipairs(called) do
        local m = session.t.matches[id]
        if m.slotA == selfPid or m.slotB == selfPid then leaderMatch = id end
    end
    check(leaderMatch ~= nil, "der Leiter ist selbst in einem Match")

    local leaderRunner
    if leaderMatch then
        local pick = choice:decideFor(session.t.matches[leaderMatch], session.t, now())
        check(pick == selfPid,
            "der Turnier-Wirt hostet sein eigenes Match (ADR-022)")
        leaderRunner = openHostFor(leaderMatch, "Leiter")
        -- Der Leiter meldet seinen Port nicht ueber das Netz -- er redet nicht
        -- mit sich selbst. Ohne diesen Aufruf wartet sein Gegner den ganzen
        -- No-Show-Timer auf eine Adresse, die nie kommt.
        if leaderRunner then
            check(thost:hostSelfMatch(leaderMatch, leaderRunner.port),
                "der Leiter veroeffentlicht seinen eigenen Match-Port")
        end
        session:confirmReady(leaderMatch, selfPid, now())
    end

    -- Zwei Runden pumpen: erst die Wirte melden ihre Ports, dann verbinden
    -- sich die Gaeste.
    pumpAll(2.0, parties)

    local live = 0
    for _, id in ipairs(called) do
        if session.t.matches[id].status == Model.STATUS.LIVE then live = live + 1 end
    end
    check(live == 4, "alle vier Matches laufen, waren " .. live)

    -- Jedes Match hat GENAU EINEN Wirt, und der Gast hat sich zu genau dem
    -- verbunden. Das ist der Punkt, an dem die gemerkte Wahl (ADR-022,
    -- `HostChoice:decideFor`) sich beweisen muss: Waere sie zwischen Aufruf
    -- und Start neu gerechnet worden, koennte der Gast an einem Rechner
    -- haengen, der gar nicht mehr hostet.
    local consistent = true
    for _, id in ipairs(called) do
        local m = session.t.matches[id]
        local r = runners[id]
        if not r or not r.host then consistent = false end
        if m.hostClient == nil then consistent = false end
        -- Der Leiter hostet ohne Netzzuweisung; die anderen drei bekommen
        -- beide Seiten ueber `TOURNAMENT_ASSIGN`.
        if id ~= leaderMatch and (assignedTo[id] or 0) ~= 2 then consistent = false end
    end
    check(consistent, "jedes laufende Match hat genau einen Wirt und einen Gast")

    -- --- Gleichzeitiger Ergebnisversand -----------------------------------
    -- Das ist der Kern von T-N-11: Nicht nacheinander, sondern alle vier in
    -- derselben Runde, bevor irgendetwas gepumpt wird.
    local stats = playedStats(ruleset)
    check(stats.longestRally > 0 and stats.fastestBall > 0,
        string.format("die Simulation liefert Statistiken: %.1f s / %.0f px/s",
            stats.longestRally, stats.fastestBall))

    local expected = {}
    for _, c in ipairs(clients) do
        if c.myMatch and c.myRunner and c.myRunner:isHost() then
            local m = session.t.matches[c.myMatch]
            expected[c.myMatch] = m.slotA
            c:report(c.myMatch, { { a = 15, b = 9 } }, stats, Protocol.END.NORMAL)
        end
    end
    if leaderMatch and leaderRunner then
        local m = session.t.matches[leaderMatch]
        expected[leaderMatch] = m.slotA
        session:enterResult(leaderMatch, { { a = 15, b = 9 } }, now(), stats)
    end

    local settled = waitFor(5, function()
        for id in pairs(expected) do
            if session.t.matches[id].status ~= Model.STATUS.FINISHED then
                return false
            end
        end
        return true
    end, parties)
    check(settled, "alle vier Ergebnisse sind gewertet")

    local correct = 0
    for id, winner in pairs(expected) do
        if session.t.matches[id].winner == winner then correct = correct + 1 end
    end
    check(correct == 4, "alle vier stehen richtig im Bracket, richtig: " .. correct)

    -- Die zwei Statistiken aus §11 sind mitgekommen.
    local withStats = 0
    for id in pairs(expected) do
        local m = session.t.matches[id]
        if m.stats and m.stats.longestRally and m.stats.longestRally > 0 then
            withStats = withStats + 1
        end
    end
    check(withStats == 4, "die Simulationsstatistiken sind mitgekommen: " .. withStats)

    local anyPlayer = false
    for _, pid in ipairs(session.t.participantOrder) do
        if session.t.participants[pid].stats.longestRally > 0 then anyPlayer = true end
    end
    check(anyPlayer, "und stehen bei den Spielern (Siegerehrung)")

    -- --- Fortschreibung ---------------------------------------------------
    session:tick(now())
    pumpAll(0.5, parties)
    thost:update(now())

    local nextRound = 0
    for _, id in ipairs(session.t.matchOrder) do
        local m = session.t.matches[id]
        if m.round == 2 and (m.status == Model.STATUS.READY
                             or m.status == Model.STATUS.LIVE) then
            nextRound = nextRound + 1
        end
    end
    check(nextRound == 2, "das Halbfinale ist aufgerufen, Matches: " .. nextRound)

    local finalSync = waitFor(4, function()
        for _, c in ipairs(clients) do
            if c:logCount() < #session.t.log then return false end
        end
        return true
    end, parties)
    check(finalSync, "der neue Stand ist bei allen angekommen")

    local sameDerived = true
    for _, c in ipairs(clients) do
        for id in pairs(expected) do
            local a, b = session.t.matches[id], c.session.t.matches[id]
            if not b or a.winner ~= b.winner or a.status ~= b.status then
                sameDerived = false
            end
        end
    end
    check(sameDerived, "alle leiten denselben Zustand ab (ADR-023)")

    local noDrops = true
    for _, c in ipairs(clients) do
        if c.stats.dropped > 0 or c.stats.rebuilds > 0 then noDrops = false end
    end
    check(noDrops, "kein Ereignis ist unterwegs verlorengegangen")

    -- --- E-08: nur der Match-Wirt meldet -----------------------------------
    local victim, other
    for _, id in ipairs(session.t.matchOrder) do
        local m = session.t.matches[id]
        if m.status == Model.STATUS.READY or m.status == Model.STATUS.LIVE then
            victim = id
        end
    end
    if victim then
        for _, c in ipairs(clients) do
            local m = session.t.matches[victim]
            if c.pid ~= m.slotA and c.pid ~= m.slotB then other = c end
        end
    end
    if victim and other then
        local before = session.t.matches[victim].status
        other:report(victim, { { a = 15, b = 0 } }, stats, Protocol.END.NORMAL)
        pumpAll(0.6, parties)
        check(session.t.matches[victim].status == before,
            "ein Unbeteiligter kann kein Ergebnis melden (E-08)")
    end

    for _, r in pairs(runners) do
        if r.host then r.host:close() end
        if r.guest then r.guest:close() end
    end
    if leaderRunner then leaderRunner:close() end
    for _, c in ipairs(clients) do c:close() end
    thost:close()
end

-- ---------------------------------------------------------------------------

function M.selftest()
    -- Umgeleitet puffert LOEVE die Ausgabe. In der CI heisst das: Ein Lauf,
    -- der haengt, hinterlaesst ein LEERES Protokoll -- also genau dann nichts,
    -- wenn man es braucht. Gemessen an Lauf 34 (2026-08-13).
    pcall(function() io.stdout:setvbuf("no") end)

    print("[turnier] Selbsttest -- Turnier-Wirt, sieben Teilnehmer, ein Prozess")
    print("[turnier] love " .. table.concat({ love.getVersion() }, ".", 1, 3))

    -- Uebersetzbarkeit der Dateien, die kein Headless-Test anfasst.
    for _, path in ipairs({ "src/app/scenes/tournament.lua",
                            "src/render/bracket_view.lua",
                            "src/net/match_runner.lua" }) do
        local chunk, err = love.filesystem.load(path)
        if not check(chunk ~= nil, path .. " laesst sich uebersetzen") then
            print("       " .. tostring(err))
        end
    end

    M.threeLobbies()
    M.parallelMatches()
    return failures
end

return M
