-- ============================================================================
-- src/net/host.lua -- die autoritative Seite (M2-02, M2-08)
--
-- Der Host simuliert und spielt mit. Kein dedizierter Server (ADR-002,
-- `04_NETCODE_SPEC` §2). Diese Datei besitzt den ENet-Host, die Lobby und je
-- Slot einen Eingabepuffer; die Simulation selbst treibt die Szene
-- (`src/app/scenes/net_game.lua`) -- der feste Schritt gehoert zum Match, nicht
-- zum Netz.
--
-- Drei Punkte, die `04_NETCODE_SPEC` ausdruecklich verlangt und die sich alle
-- drei nicht nachtraeglich einbauen lassen:
--
--   * Die Ereignisschleife wird JE FRAME VOLLSTAENDIG geleert. Ein Ereignis
--     pro Durchlauf staut die Queue bei 60 Hz sofort auf (§4, T-N-08).
--   * Peer-Timeout 5000 ms statt der ENet-Vorgabe von 30 s. Sonst stehen tote
--     Slots eine halbe Minute lang (§12).
--   * Fehlender Input wiederholt die letzte Maske, nie Null (§7) -- das
--     erledigt `input_queue.lua`.
-- ============================================================================

local Protocol   = require("src.net.protocol")
local Snapshot   = require("src.net.snapshot")
local Lobby      = require("src.net.lobby")
local InputQueue = require("src.net.input_queue")
local Ruleset    = require("src.sim.ruleset")

local Host = {}
Host.__index = Host

-- ENet-Vorgabe sind 30 s. Auf einem LAN ist eine tote Verbindung nach
-- 5 s tot, und der Rest des Abends haengt daran, dass das jemand merkt.
Host.PEER_TIMEOUT_MS = 5000

-- Fenster fuer den Wiedereinstieg nach einer Trennung (§12).
Host.RECONNECT_SECONDS = 30

Host.PING_INTERVAL = 0.5

function Host.new(opts)
    opts = opts or {}

    local enet = opts.enet or require("enet")
    local port = opts.port or Protocol.PORT_ENET

    -- Zwei Spieler; der zweite Platz ist der einzige, der ueber das Netz
    -- kommt. Ein Reserveplatz haelt den Fall auf, dass sich jemand verbindet,
    -- waehrend der alte Peer noch nicht abgeraeumt ist.
    local server, err = enet.host_create("*:" .. port, 8, Protocol.CHANNELS)
    if not server then
        return nil, "Port " .. port .. " laesst sich nicht binden: " .. tostring(err)
    end

    local self = setmetatable({
        enet      = enet,
        server    = server,
        port      = port,
        ruleset   = opts.ruleset,
        clock     = opts.clock or function() return love.timer.getTime() end,
        lobby     = Lobby.new({
            lobbyName = opts.lobbyName,
            hostName  = opts.hostName,
            buildHash = opts.buildHash,
            clientId  = opts.clientId,
        }),
        buildHash = opts.buildHash or "",
        peers     = {},        -- peer (leichtgewichtiges Objekt) -> Datensatz
        slotPeer  = {},        -- Slot -> peer
        queues    = {},        -- Slot -> InputQueue
        matchId   = 0,
        running   = false,
        paused    = false,
        pauseUntil = 0,
        pauseName = "",
        lastPingAt = 0,
        onEvent   = opts.onEvent or function() end,
        stats     = { events = 0, lastDrain = 0, sent = 0, received = 0 },
    }, Host)

    for slot = 1, Lobby.MAX_SLOTS do self.queues[slot] = InputQueue.new() end

    return self
end

function Host:rulesetHash()
    return Ruleset.hash(self.ruleset)
end

-- ---------------------------------------------------------------------------
-- Senden
-- ---------------------------------------------------------------------------

function Host:send(peer, msgType, payload)
    local ok, data = pcall(Protocol.encode, msgType, payload)
    if not ok then
        print("[host] " .. tostring(data))
        return false
    end
    peer:send(data, Protocol.channelOf(msgType), Protocol.flagOf(msgType))
    self.stats.sent = self.stats.sent + 1
    return true
end

function Host:broadcast(msgType, payload)
    local ok, data = pcall(Protocol.encode, msgType, payload)
    if not ok then
        print("[host] " .. tostring(data))
        return false
    end
    self.server:broadcast(data, Protocol.channelOf(msgType), Protocol.flagOf(msgType))
    self.stats.sent = self.stats.sent + 1
    return true
end

function Host:sendLobbyState()
    self:broadcast(Protocol.MSG.LOBBY_STATE, self.lobby:toMessage())
    self.onEvent("lobby")
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

-- Leert die Queue VOLLSTAENDIG und gibt zurueck, wie viele Ereignisse das
-- waren. Der Rueckgabewert ist nicht Kosmetik: T-N-08 drueckt 200 Snapshots
-- in einen Frame und prueft genau ihn.
function Host:service()
    local count = 0
    local event = self.server:service(0)
    while event do
        self:handle(event)
        count = count + 1
        event = self.server:service(0)
    end
    self.stats.events = self.stats.events + count
    self.stats.lastDrain = count
    return count
end

function Host:handle(event)
    if event.type == "connect" then
        -- Erst beim HELLO bekommt der Peer einen Slot: vorher wissen wir
        -- weder, wer er ist, noch ob er dieselbe Fassung spricht.
        event.peer:timeout(32, Host.PEER_TIMEOUT_MS, Host.PEER_TIMEOUT_MS)
        self.peers[event.peer] = { peer = event.peer, slot = nil, clientId = nil }

    elseif event.type == "receive" then
        self.stats.received = self.stats.received + 1
        self:receive(event.peer, event.data)

    elseif event.type == "disconnect" then
        self:dropPeer(event.peer)
    end
end

function Host:receive(peer, data)
    local msgType, payload = Protocol.decode(data)

    if not msgType then
        -- Eine fremde Protokollfassung bekommt Klartext, keinen Timeout (§5).
        local version = Protocol.peekVersion(data)
        if version and version ~= Protocol.VERSION then
            self:send(peer, Protocol.MSG.REJECT, {
                reason = Protocol.REJECT.VERSION,
                text = string.format(
                    "Andere Protokollfassung: Host spricht %d, du sprichst %d. "
                    .. "Ihr braucht dieselbe ZIP.", Protocol.VERSION, version),
            })
            peer:disconnect_later(0)
        end
        return
    end

    local record = self.peers[peer]
    if not record then return end

    if msgType == Protocol.MSG.HELLO then
        self:onHello(peer, record, payload)

    elseif msgType == Protocol.MSG.SET_READY then
        if record.slot then
            self.lobby:setReady(record.slot, payload.ready)
            self:sendLobbyState()
        end

    elseif msgType == Protocol.MSG.INPUT then
        if record.slot and self.queues[record.slot] then
            self.queues[record.slot]:pushPacket(payload.tick, payload.masks)
        end

    elseif msgType == Protocol.MSG.PING then
        self:send(peer, Protocol.MSG.PONG, { timestamp = payload.timestamp })

    elseif msgType == Protocol.MSG.PONG then
        record.rtt = math.max(0, self:now() * 1000 - payload.timestamp)
    end
end

function Host:now()
    return self.clock()
end

function Host:onHello(peer, record, payload)
    local wasPaused = self.paused
    local slot, how = self.lobby:claim(payload.clientId, payload.name, payload.buildHash)

    if not slot then
        self:send(peer, Protocol.MSG.REJECT, {
            reason = Protocol.REJECT.FULL,
            text = "Die Lobby ist voll.",
        })
        peer:disconnect_later(0)
        return
    end

    -- Ein laufendes Match nimmt nur den zurueck, der vorher drin war.
    if self.running and how ~= "reconnect" then
        self.lobby:release(slot)
        self:send(peer, Protocol.MSG.REJECT, {
            reason = Protocol.REJECT.RUNNING,
            text = "Es laeuft bereits ein Match.",
        })
        peer:disconnect_later(0)
        return
    end

    record.slot     = slot
    record.clientId = payload.clientId
    record.name     = payload.name
    self.slotPeer[slot] = peer

    self:send(peer, Protocol.MSG.WELCOME, {
        slot        = slot,
        clientId    = payload.clientId,
        rulesetHash = self:rulesetHash(),
        hostName    = self.lobby.hostName,
        lobbyName   = self.lobby.lobbyName,
    })
    self:send(peer, Protocol.MSG.RULESET_FULL, { ruleset = self.ruleset })
    self:sendLobbyState()

    if how == "reconnect" and wasPaused then
        -- Der Wiedereinsteiger bekommt den laufenden Zustand: dasselbe
        -- MATCH_START, danach traegt ihn der naechste Snapshot (§12).
        self.queues[slot]:reset()
        self:send(peer, Protocol.MSG.MATCH_START, {
            matchId = self.matchId, startTick = 0,
            rulesetHash = self:rulesetHash(), slot = slot,
        })
        self:resume()
    end

    self.onEvent("join", slot, payload.name, how)
end

-- Trennung waehrend der Lobby: Slot wird frei. Trennung waehrend des Matches:
-- Match pausiert, 30 s Fenster (§12).
function Host:dropPeer(peer)
    local record = self.peers[peer]
    self.peers[peer] = nil
    if not record or not record.slot then return end

    local slot = record.slot
    self.slotPeer[slot] = nil

    if self.running then
        self:pause(record.name or "Gegner")
        -- Der Slot BLEIBT belegt: die clientId ist der Schluessel fuer den
        -- Wiedereinstieg, und ein freigegebener Slot koennte in der Zwischen-
        -- zeit von jemand anderem genommen werden.
        self.onEvent("lost", slot, record.name)
    else
        self.lobby:release(slot)
        self:sendLobbyState()
        self.onEvent("left", slot, record.name)
    end
end

-- ---------------------------------------------------------------------------
-- Match
-- ---------------------------------------------------------------------------

function Host:startMatch()
    self.matchId = self.matchId + 1
    self.running = true
    self.paused  = false
    for _, queue in pairs(self.queues) do queue:reset() end

    self.lobby.running = true
    for slot, peer in pairs(self.slotPeer) do
        self:send(peer, Protocol.MSG.MATCH_START, {
            matchId = self.matchId, startTick = 0,
            rulesetHash = self:rulesetHash(), slot = slot,
        })
    end
    self.onEvent("start", self.matchId)
end

function Host:endMatch(scoreA, scoreB, reason)
    if not self.running then return end
    self.running = false
    self.paused  = false
    self.lobby.running = false

    self:broadcast(Protocol.MSG.MATCH_END, {
        matchId = self.matchId, scoreA = scoreA, scoreB = scoreB,
        reason = reason or Protocol.END.NORMAL,
    })
    self.onEvent("end", scoreA, scoreB, reason or Protocol.END.NORMAL)
end

function Host:pause(name)
    self.paused = true
    self.pauseName = name or ""
    self.pauseUntil = self:now() + Host.RECONNECT_SECONDS
    self:sendPause()
end

function Host:resume()
    self.paused = false
    self.pauseName = ""
    self:sendPause()
    self.onEvent("resume")
end

function Host:secondsLeft()
    if not self.paused then return 0 end
    return math.max(0, math.ceil(self.pauseUntil - self:now()))
end

function Host:sendPause()
    self:broadcast(Protocol.MSG.MATCH_PAUSE, {
        paused = self.paused,
        secondsLeft = math.min(255, self:secondsLeft()),
        text = self.paused and ("Warte auf " .. self.pauseName .. " ...") or "",
    })
end

-- ---------------------------------------------------------------------------
-- Eingaben
-- ---------------------------------------------------------------------------

-- Die Maske dieses Ticks fuer einen Netz-Slot. Fehlt sie, wiederholt der
-- Puffer die letzte -- nicht Null (§7).
function Host:inputFor(slot)
    local queue = self.queues[slot]
    if not queue then return 0 end
    return (queue:consume())
end

function Host:ackTick(slot)
    local queue = self.queues[slot]
    return queue and queue:ackTick() or -1
end

function Host:publishSnapshot(state, tick)
    for slot, peer in pairs(self.slotPeer) do
        local snap = Snapshot.from(state, tick, self:ackTick(slot), self.ruleset)
        self:send(peer, Protocol.MSG.SNAPSHOT, snap)
    end
end

-- ---------------------------------------------------------------------------
-- Takt
-- ---------------------------------------------------------------------------

function Host:update(dt)
    self:service()

    local now = self:now()

    if now - self.lastPingAt >= Host.PING_INTERVAL then
        self.lastPingAt = now
        self:broadcast(Protocol.MSG.PING, { timestamp = math.floor(now * 1000) })
        if self.paused then self:sendPause() end
    end

    -- Nach 30 s ohne Rueckkehr endet das Match. Im Turnier wird das als
    -- Walkover gewertet (`05_TOURNAMENT` §6, M4).
    if self.paused and now >= self.pauseUntil then
        self.onEvent("walkover")
    end
end

function Host:rttFor(slot)
    local peer = self.slotPeer[slot]
    if not peer then return nil end
    local ok, value = pcall(function() return peer:round_trip_time() end)
    return ok and value or nil
end

function Host:lossFor(slot)
    local peer = self.slotPeer[slot]
    if not peer then return nil end
    local ok, value = pcall(function() return peer:packet_loss() end)
    -- ENet zaehlt Verlust in Bruchteilen von 65536.
    return ok and (value / 65536) or nil
end

function Host:close()
    if not self.server then return end
    for peer in pairs(self.peers) do
        pcall(function() peer:disconnect_now(0) end)
    end
    pcall(function() self.server:flush() end)
    pcall(function() self.server:destroy() end)
    self.server = nil
end

return Host
