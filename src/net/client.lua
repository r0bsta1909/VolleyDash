-- ============================================================================
-- src/net/client.lua -- die zuschauende Seite (M2-03)
--
-- Der Client simuliert NICHT. Er sendet seine Eingaben, empfaengt Snapshots
-- und zeigt sie mit zwei Ticks Verzoegerung an (`04_NETCODE_SPEC` §8). Die
-- Vorhersage des eigenen Blobs ist M3 und wird hier ausdruecklich nicht
-- vorweggenommen -- sie waere die halbe Wahrheit ohne die Korrekturschleife,
-- die dazugehoert.
--
-- Warum ueberhaupt ein Puffer: Snapshots kommen mit Jitter an. Ohne Vorrat
-- steht das Bild bei jeder Verzoegerung still und springt danach. Zwei Ticks
-- (33 ms) sind der Preis dafuer, dass es das nicht tut.
-- ============================================================================

local Protocol = require("src.net.protocol")
local Ruleset  = require("src.sim.ruleset")
local Lobby    = require("src.net.lobby")

local Client = {}
Client.__index = Client

Client.BUFFER_TICKS = 2      -- Interpolationspuffer (§8)
Client.MAX_BUFFER   = 8      -- darueber wird aufgeholt, statt nachzuhinken
Client.PEER_TIMEOUT_MS = 5000
Client.PING_INTERVAL = 0.5
Client.CONNECT_TIMEOUT = 5

function Client.new(opts)
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

        state     = "connecting",   -- connecting | lobby | playing | ended | failed
        message   = "",
        slot      = nil,
        lobbySlots = {},
        hostName  = "",
        lobbyName = "",
        ruleset   = nil,            -- kommt per RULESET_FULL vom Host
        rulesetHash = nil,
        findings  = {},

        snapshots = {},
        latest    = nil,
        tick      = 0,              -- eigene Tickzaehlung fuer INPUT
        masks     = { 0, 0, 0 },

        startedAt = nil,
        lastPingAt = 0,
        rtt       = 0,
        stats     = { received = 0, applied = 0, held = 0, dropped = 0, lastDrain = 0 },
    }, Client)

    self.startedAt = self:now()
    return self
end

function Client:now() return self.clock() end

function Client:send(msgType, payload)
    if not self.peer then return false end
    local ok, data = pcall(Protocol.encode, msgType, payload)
    if not ok then
        print("[client] " .. tostring(data))
        return false
    end
    self.peer:send(data, Protocol.channelOf(msgType), Protocol.flagOf(msgType))
    return true
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

-- Auch hier vollstaendig leeren: bei 60 Snapshots je Sekunde staut sich die
-- Queue sonst binnen Sekunden auf (§4, T-N-08).
function Client:service()
    local count = 0
    local event = self.host:service(0)
    while event do
        self:handle(event)
        count = count + 1
        event = self.host:service(0)
    end
    self.stats.lastDrain = count
    return count
end

function Client:handle(event)
    if event.type == "connect" then
        event.peer:timeout(32, Client.PEER_TIMEOUT_MS, Client.PEER_TIMEOUT_MS)
        self:send(Protocol.MSG.HELLO, {
            clientId = self.clientId, buildHash = self.buildHash, name = self.name,
        })

    elseif event.type == "receive" then
        self:receive(event.data)

    elseif event.type == "disconnect" then
        self.peer = nil
        if self.state ~= "ended" then
            self:fail("Verbindung zum Host verloren.")
        end
    end
end

function Client:fail(text)
    self.state = "failed"
    self.message = text
    self.onEvent("failed", text)
end

function Client:receive(data)
    local msgType, payload = Protocol.decode(data)
    if not msgType then return end

    if msgType == Protocol.MSG.WELCOME then
        self.slot        = payload.slot
        self.rulesetHash = payload.rulesetHash
        self.hostName    = payload.hostName
        self.lobbyName   = payload.lobbyName
        self.state       = "lobby"
        self.onEvent("welcome", payload.slot)

    elseif msgType == Protocol.MSG.REJECT then
        self:fail(payload.text ~= "" and payload.text or "Der Host hat abgelehnt.")
        self.state = "failed"

    elseif msgType == Protocol.MSG.RULESET_FULL then
        self:acceptRuleset(payload.ruleset)

    elseif msgType == Protocol.MSG.LOBBY_STATE then
        self.lobbySlots = payload.slots
        self:compareBuild()
        self.onEvent("lobby")

    elseif msgType == Protocol.MSG.MATCH_START then
        self:onMatchStart(payload)

    elseif msgType == Protocol.MSG.SNAPSHOT then
        self.stats.received = self.stats.received + 1
        self.snapshots[#self.snapshots + 1] = payload
        self.latest = payload

    elseif msgType == Protocol.MSG.MATCH_END then
        -- Zurueck in die Lobby, nicht "ended": die Verbindung steht weiter,
        -- und das naechste Match soll keinen neuen Handschlag kosten.
        self.state = "lobby"
        self.onEvent("end", payload.scoreA, payload.scoreB, payload.reason)

    elseif msgType == Protocol.MSG.MATCH_PAUSE then
        self.onEvent("pause", payload.paused, payload.secondsLeft, payload.text)

    elseif msgType == Protocol.MSG.PING then
        self:send(Protocol.MSG.PONG, { timestamp = payload.timestamp })

    elseif msgType == Protocol.MSG.PONG then
        self.rtt = math.max(0, self:now() * 1000 - payload.timestamp)
    end
end

-- Das Ruleset kommt vom Host und ersetzt das eigene (ADR-005). Ungueltige
-- Werte werden nicht uebernommen -- sonst rechnet der Client mit einer Physik,
-- die es nirgends gibt.
function Client:acceptRuleset(values)
    local rs = Ruleset.new("prototype", values)
    local ok, errors = Ruleset.validate(rs)
    if not ok then
        self:fail("Der Host schickt ein unbrauchbares Regelwerk: "
                  .. tostring(errors[1]))
        return
    end
    self.ruleset = rs
    self.onEvent("ruleset", rs)
end

-- Drei Pruefungen, drei Konsequenzen (M2-07). Der Build-Hash ist die einzige
-- der drei, die nur warnt.
function Client:compareBuild()
    local hostSlot = self.lobbySlots[Lobby.HOST_SLOT]
    if not hostSlot or hostSlot.buildHash == "" then return end

    self.findings = Lobby.compare(
        { protoVersion = Protocol.VERSION, rulesetHash = self.rulesetHash,
          buildHash = hostSlot.buildHash },
        { protoVersion = Protocol.VERSION, rulesetHash = self.rulesetHash,
          buildHash = self.buildHash })
end

function Client:onMatchStart(payload)
    -- Der Abgleich aus §10: der Hash des empfangenen Rulesets gegen den, den
    -- der Host beim Start nennt. Weichen sie ab, startet das Match nicht --
    -- Klartext, kein stiller Fehlstart.
    local mine = self.ruleset and Ruleset.hash(self.ruleset) or "(keins)"
    if mine ~= payload.rulesetHash then
        self:fail(string.format(
            "Regelwerk weicht ab (Host %s, hier %s). Das Match startet nicht.",
            tostring(payload.rulesetHash), tostring(mine)))
        return
    end

    self.slot = payload.slot
    self.tick = 0
    self.masks = { 0, 0, 0 }
    self.snapshots = {}
    self.state = "playing"
    self.onEvent("start", payload.matchId, payload.slot)
end

-- ---------------------------------------------------------------------------
-- Eingaben
-- ---------------------------------------------------------------------------

-- Einmal je Simulationstick. Jedes Paket traegt die Masken der letzten drei
-- Ticks (§7); das kostet zwei Byte und macht Einzelverluste unsichtbar.
function Client:pushInput(mask)
    self.masks[3] = self.masks[2]
    self.masks[2] = self.masks[1]
    self.masks[1] = mask

    self:send(Protocol.MSG.INPUT, { tick = self.tick, masks = self.masks })
    self.tick = self.tick + 1
end

-- ---------------------------------------------------------------------------
-- Snapshots
--
-- Einer je Tick, aber erst, wenn der Puffer gefuellt ist. Kommt nichts, gibt
-- es nichts -- das Bild haelt an, statt zu springen.
-- ---------------------------------------------------------------------------

function Client:nextSnapshot()
    local queue = self.snapshots

    -- Zu weit hinten: aufholen, statt eine wachsende Verzoegerung mitzuziehen.
    -- Das passiert, wenn der Client Frames verloren hat, nicht der Host.
    while #queue > Client.MAX_BUFFER do
        table.remove(queue, 1)
        self.stats.dropped = self.stats.dropped + 1
    end

    if #queue <= Client.BUFFER_TICKS then
        self.stats.held = self.stats.held + 1
        return nil
    end

    local snap = table.remove(queue, 1)
    self.stats.applied = self.stats.applied + 1
    return snap
end

function Client:bufferDepth()
    return #self.snapshots
end

-- ---------------------------------------------------------------------------
-- Takt
-- ---------------------------------------------------------------------------

function Client:update(dt)
    self:service()

    if self.state == "connecting"
       and self:now() - self.startedAt > Client.CONNECT_TIMEOUT then
        self:fail("Keine Antwort von " .. self.address .. ".")
        return
    end

    local now = self:now()
    if now - self.lastPingAt >= Client.PING_INTERVAL then
        self.lastPingAt = now
        self:send(Protocol.MSG.PING, { timestamp = math.floor(now * 1000) })
    end
end

function Client:setReady(ready)
    self:send(Protocol.MSG.SET_READY, { ready = ready })
end

function Client:peerRtt()
    if not self.peer then return nil end
    local ok, value = pcall(function() return self.peer:round_trip_time() end)
    return ok and value or nil
end

function Client:peerLoss()
    if not self.peer then return nil end
    local ok, value = pcall(function() return self.peer:packet_loss() end)
    return ok and (value / 65536) or nil
end

function Client:close()
    if self.peer then pcall(function() self.peer:disconnect_now(0) end) end
    if self.host then
        pcall(function() self.host:flush() end)
        pcall(function() self.host:destroy() end)
    end
    self.peer, self.host = nil, nil
end

return Client
