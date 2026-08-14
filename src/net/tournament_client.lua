-- ============================================================================
-- src/net/tournament_client.lua -- die Teilnehmerseite eines Turniers (M4-09)
--
-- `05_TOURNAMENT` §8, ADR-023. Gegenstueck zu `src/net/tournament_host.lua`.
--
-- ---------------------------------------------------------------------------
-- Der Client fuehrt kein Turnier, er sieht eines
-- ---------------------------------------------------------------------------
--
-- Was hereinkommt, sind LOG-EREIGNISSE. Sie gehen durch dasselbe
-- `Model.applyEvent` wie beim Turnier-Wirt und wie bei der Recovery aus §7 --
-- es gibt also keinen zweiten Weg, auf dem ein Turnierstand entsteht. Der
-- Scheduler laeuft hier nicht (`Session.observe` setzt `readOnly`); zwei
-- Schreiber auf einem append-only Log haetten keine gemeinsame Reihenfolge.
--
-- ---------------------------------------------------------------------------
-- Zwei Verbindungen, zwei Sockets
-- ---------------------------------------------------------------------------
--
-- Diese hier haelt der Teilnehmer den ganzen Abend. Waehrend eines Matches
-- kommt eine zweite dazu -- zum Match-Wirt, ueber `src/net/client.lua` bzw.
-- `src/net/host.lua`. Das sind zwei ENet-Wirte in einem Prozess; dass das
-- geht, ist gemessen (`05_TOURNAMENT` §8.2). Was NICHT geht, ist zweimal
-- derselbe Port -- deshalb bindet der Match-Wirt `*:0`.
--
-- Beide in EINEN Wirt mit zwei Peers zu legen waere moeglich und ist bewusst
-- nicht getan: `client.lua` ist ein fertiger Matchclient mit eigenem
-- Zustandsautomaten. Ihm einen zweiten, voellig unbeteiligten Peer
-- unterzuschieben verschraenkt zwei Protokolle in einer Ereignisschleife und
-- spart dafuer einen Socket.
-- ============================================================================

local Protocol = require("src.net.protocol")
local Model    = require("src.tournament.model")
local Session  = require("src.tournament.session")

local TournamentClient = {}
TournamentClient.__index = TournamentClient

TournamentClient.PEER_TIMEOUT_MS = 5000
TournamentClient.PING_INTERVAL   = 0.5
TournamentClient.CONNECT_TIMEOUT = 5

function TournamentClient.new(opts)
    opts = opts or {}
    local enet = opts.enet or require("enet")

    local peerHost, err = enet.host_create(nil, 1, Protocol.CHANNELS)
    if not peerHost then
        return nil, "kein Netzwerk-Socket: " .. tostring(err)
    end

    local address = string.format("%s:%d", opts.address or "127.0.0.1",
        opts.port or Protocol.PORT_ENET)

    local ok, peer = pcall(function()
        return peerHost:connect(address, Protocol.CHANNELS)
    end)
    if not ok or not peer then
        pcall(function() peerHost:destroy() end)
        return nil, "Adresse unbrauchbar: " .. tostring(opts.address)
    end

    local self = setmetatable({
        enet      = enet,
        host      = peerHost,
        peer      = peer,
        address   = opts.address or "127.0.0.1",
        port      = opts.port or Protocol.PORT_ENET,
        clientId  = opts.clientId or 0,
        name      = opts.name or "Gast",
        buildHash = opts.buildHash or "",
        clock     = opts.clock or function() return love.timer.getTime() end,
        onEvent   = opts.onEvent or function() end,

        state     = "connecting",  -- connecting | joined | failed
        message   = "",
        pid       = nil,
        realName  = nil,
        tournamentName = "",

        session   = Session.observe(Model.replay({})),
        assignment = nil,          -- die zuletzt erhaltene Zuweisung
        lastReport = nil,          -- fuer die Nachfrage aus §8

        lastPingAt = 0,
        rtt        = 0,
        startedAt  = 0,
        stats      = { events = 0, dropped = 0, rebuilds = 0, gaps = 0 },
    }, TournamentClient)

    self.startedAt = self:now()
    return self
end

function TournamentClient:now() return self.clock() end

-- Die Uhr, mit der die Anzeige rechnen muss: die des Turnier-Wirts. Solange
-- noch kein PING angekommen ist, gibt es keinen Versatz -- dann steht die
-- Restzeit kurz falsch, statt gar nicht dazusein.
function TournamentClient:hostNow()
    return self:now() - (self.hostOffset or 0)
end

function TournamentClient:send(msgType, payload)
    if not self.peer then return false end
    local ok, data = pcall(Protocol.encode, msgType, payload)
    if not ok then
        print("[tournament_client] " .. tostring(data))
        return false
    end
    self.peer:send(data, Protocol.channelOf(msgType), Protocol.flagOf(msgType))
    return true
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

function TournamentClient:service()
    local count = 0
    local event = self.host:service(0)
    while event do
        self:handle(event)
        count = count + 1
        event = self.host:service(0)
    end
    return count
end

function TournamentClient:handle(event)
    if event.type == "connect" then
        event.peer:timeout(32, TournamentClient.PEER_TIMEOUT_MS,
            TournamentClient.PEER_TIMEOUT_MS)
        self:send(Protocol.MSG.HELLO, {
            clientId = self.clientId, buildHash = self.buildHash, name = self.name,
        })

    elseif event.type == "receive" then
        self:receive(event.data)

    elseif event.type == "disconnect" then
        self.peer = nil
        if self.state ~= "failed" then
            self:fail("Verbindung zum Turnier verloren.")
        end
    end
end

function TournamentClient:fail(text)
    self.state = "failed"
    self.message = text
    self.onEvent("failed", text)
end

function TournamentClient:receive(data)
    local msgType, payload = Protocol.decode(data)
    if not msgType then return end

    if msgType == Protocol.MSG.TOURNAMENT_WELCOME then
        self.pid            = payload.participantId
        self.realName       = payload.name
        self.tournamentName = payload.tournamentName
        self.state          = "joined"
        -- Der eigene Name kann ein anderer sein als der gewuenschte
        -- (`04_NETCODE` §5). Wer das nicht erfaehrt, findet sich im Baum
        -- nicht wieder -- deshalb geht er nach oben.
        self.session.selfName = payload.name
        self.onEvent("welcome", payload.participantId, payload.name)

    elseif msgType == Protocol.MSG.REJECT then
        self:fail(payload.text ~= "" and payload.text or "Das Turnier hat abgelehnt.")

    elseif msgType == Protocol.MSG.TOURNAMENT_STATE then
        self:onState(payload)

    elseif msgType == Protocol.MSG.TOURNAMENT_ASSIGN then
        -- ":PORT" ohne Rechnerteil heisst "auf demselben Rechner wie der
        -- Turnier-Wirt" -- der Fall, in dem der Turnier-Wirt selbst hostet.
        -- Welche seiner Adressen er anschreiben muesste, weiss er bei mehreren
        -- Netzwerkkarten nicht; wir dagegen haben schon einen Weg zu ihm.
        if payload.address and payload.address:sub(1, 1) == ":" then
            payload.address = self.address .. payload.address
        end
        self.assignment = payload
        self.onEvent("assign", payload)

    elseif msgType == Protocol.MSG.RESULT_QUERY then
        -- §8: Der Turnier-Wirt vermisst ein Ergebnis. Haben wir eines,
        -- schicken wir es noch einmal -- die Nachricht ist idempotent, weil
        -- der Wirt ein bereits gewertetes Match ablehnt.
        if self.lastReport and self.lastReport.matchId == payload.matchId then
            self:send(Protocol.MSG.MATCH_REPORT, self.lastReport)
        end
        self.onEvent("result_query", payload.matchId)

    elseif msgType == Protocol.MSG.PING then
        -- Nebenbei die Uhr des Turnier-Wirts mitnehmen (C-T-12).
        --
        -- Das Log traegt HOST-Zeitstempel: `calledAt` ist `love.timer.getTime()`
        -- beim Wirt, also Sekunden seit DESSEN Prozessstart. Wer den
        -- No-Show-Timer daraus gegen seine EIGENE Prozesszeit rechnet, bekommt
        -- die Differenz zweier Startzeitpunkte -- am Abend des 2026-08-13 war
        -- das ein Countdown von 15 Minuten statt der eingestellten drei.
        --
        -- Der PING traegt die Host-Zeit ohnehin, zweimal je Sekunde. Der
        -- Versatz kostet damit keine eigene Nachricht; die halbe Laufzeit, die
        -- darin steckt, ist im LAN ein Bruchteil einer Millisekunde und gegen
        -- eine 180-s-Frist bedeutungslos.
        self.hostOffset = self:now() - (payload.timestamp or 0) / 1000
        self:send(Protocol.MSG.PONG, { timestamp = payload.timestamp })

    elseif msgType == Protocol.MSG.PONG then
        self.rtt = math.max(0, self:now() * 1000 - payload.timestamp)
    end
end

-- ---------------------------------------------------------------------------
-- Der Turnierstand (ADR-023)
-- ---------------------------------------------------------------------------

function TournamentClient:logCount()
    return #self.session.t.log
end

function TournamentClient:onState(payload)
    if not payload.events then
        -- Ein kaputter Block. Nicht halb anwenden, sondern noch einmal holen.
        self.stats.dropped = self.stats.dropped + 1
        self:send(Protocol.MSG.STATE_REQUEST, { fromIndex = self:logCount() })
        return
    end

    local have = self:logCount()

    if payload.fromIndex > have then
        -- Eine Luecke. Der Wasserstand ist alles, was es dafuer braucht --
        -- ein append-only Log kennt keine Invalidierung, nur ein Suffix.
        self.stats.gaps = self.stats.gaps + 1
        self:send(Protocol.MSG.STATE_REQUEST, { fromIndex = have })
        return
    end

    -- Ueberlappung ist der Normalfall nach einer Nachforderung: schon
    -- Bekanntes wird uebersprungen, nicht ein zweites Mal angewandt.
    local skip = have - payload.fromIndex

    for i = skip + 1, #payload.events do
        local ev = payload.events[i]
        local ok = self.session:applyRemote(ev)
        if ok then
            self.stats.events = self.stats.events + 1
        else
            -- Ein Ereignis, das diese Fassung nicht anwenden kann. Der Zustand
            -- koennte halb veraendert sein, also wird er aus dem Log neu
            -- gebaut, das den Fehler nicht enthaelt -- und das Ereignis
            -- gezaehlt statt verschwiegen.
            self.stats.dropped = self.stats.dropped + 1
            self:rebuild()
            self.onEvent("event_dropped", ev and ev.event)
            return
        end
    end

    self.onEvent("state", self:logCount())
end

function TournamentClient:rebuild()
    self.stats.rebuilds = self.stats.rebuilds + 1
    local model = Model.replay(self.session.t.log)
    local name  = self.session.selfName
    self.session = Session.observe(model)
    self.session.selfName = name
end

-- ---------------------------------------------------------------------------
-- Was der Teilnehmer meldet
-- ---------------------------------------------------------------------------

-- Bereitmeldung. Der Match-Wirt gibt seinen Port mit; der Gast schickt 0.
--
-- `ready = false` ist die RUECKNAHME (C-T-13): "ich bin doch nicht dabei". Sie
-- braucht keine eigene Nachricht -- das Feld sagt bereits genau das aus, und
-- ein zweiter Nachrichtentyp fuer die Verneinung eines Wahrheitswerts waere
-- Protokoll ohne Gewinn.
function TournamentClient:accept(matchId, enetPort, ready)
    if ready == nil then ready = true end
    return self:send(Protocol.MSG.MATCH_ACCEPT,
        { matchId = matchId, ready = ready, enetPort = enetPort or 0 })
end

-- Der Ergebnisbericht (E-08). Er wird gemerkt, damit die Nachfrage aus §8
-- beantwortet werden kann, ohne das Match noch einmal zu spielen.
function TournamentClient:report(matchId, sets, stats, reason)
    stats = stats or {}
    local payload = {
        matchId      = matchId,
        sets         = sets or {},
        longestRally = stats.longestRally or 0,
        fastestBall  = stats.fastestBall or 0,
        fastestBy    = stats.fastestBy or 0,
        reason       = reason or Protocol.END.NORMAL,
    }
    self.lastReport = payload
    return self:send(Protocol.MSG.MATCH_REPORT, payload)
end

-- ---------------------------------------------------------------------------
-- Takt
-- ---------------------------------------------------------------------------

function TournamentClient:update(now)
    now = now or self:now()
    self:service()

    if self.state == "connecting"
       and now - self.startedAt > TournamentClient.CONNECT_TIMEOUT then
        self:fail("Das Turnier antwortet nicht.")
    end

    if now - self.lastPingAt >= TournamentClient.PING_INTERVAL then
        self.lastPingAt = now
        self:send(Protocol.MSG.PING, { timestamp = math.floor(now * 1000) })
    end
end

-- Der Ereignisstrom fuer die Szene -- dieselbe Funktion wie beim Turnierleiter,
-- damit Klaenge und Einblendungen an einer Stelle haengen. Der Automat laeuft
-- dabei nicht (`readOnly`), gemeldet wird nur, was hereingekommen ist.
function TournamentClient:tick(now)
    return self.session:tick(now)
end

function TournamentClient:close()
    if self.peer then pcall(function() self.peer:disconnect_now(0) end) end
    self.peer = nil
    if self.host then
        pcall(function() self.host:flush() end)
        pcall(function() self.host:destroy() end)
    end
    self.host = nil
end

return TournamentClient
