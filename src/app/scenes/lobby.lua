-- ============================================================================
-- src/app/scenes/lobby.lua -- Lobby als Szene, beide Rollen (M2-06, M2-07)
--
-- Der Host besitzt hier ENet-Host UND Discovery-Bake; der Gast besitzt den
-- Client. Beide leben so lange wie diese Szene -- verlaesst man sie, gehen
-- die Sockets zu. Genau deshalb wandert das Objekt beim Matchstart NICHT in
-- die Spielszene, sondern wird ihr nur geliehen: die Lobby bleibt unter dem
-- Match im Stapel liegen und raeumt am Ende auf.
--
-- Der Abgleich (M2-07) sitzt in `src/net/lobby.lua` und wird hier nur
-- angezeigt. Drei Pruefungen, drei Konsequenzen.
-- ============================================================================

local Protocol  = require("src.net.protocol")
local Host      = require("src.net.host")
local Client    = require("src.net.client")
local Discovery = require("src.net.discovery")
local NetLobby  = require("src.net.lobby")
local Ruleset   = require("src.sim.ruleset")
local BuildInfo = require("src.app.build_info")
local LobbyView = require("src.ui.lobby_view")
local Menu      = require("src.ui.menu")
local Music     = require("src.app.music")

local LobbyScene = {}
LobbyScene.__index = LobbyScene

local function playerName(app)
    return Menu.displayNames(false)[1]
end

function LobbyScene.new(app, opts)
    local self = setmetatable({
        name    = "lobby",
        app     = app,
        role    = opts.role,
        error   = nil,
        started = false,
        ready   = false,
    }, LobbyScene)

    if self.role == "host" then
        self:startHost(opts)
    else
        self:startClient(opts)
    end
    return self
end

-- ---------------------------------------------------------------------------
-- Host
-- ---------------------------------------------------------------------------

function LobbyScene:startHost(opts)
    local app = self.app
    -- Das Ruleset wird beim Oeffnen der Lobby festgelegt und vom Host verteilt
    -- (ADR-005). Der Live-Tweaker bleibt im Netzspiel aussen vor.
    app.applyPreset(app.prefs.preset)

    self.hostName = playerName(app)
    self.lobbyName = self.hostName .. "s Lobby"
    self.address = Discovery.localAddress()

    local host, err = Host.new({
        port      = Protocol.PORT_ENET,
        ruleset   = app.ruleset,
        hostName  = self.hostName,
        lobbyName = self.lobbyName,
        buildHash = BuildInfo.buildHash,
        clientId  = app.clientId(),
        onEvent   = function(kind, a, b, c) self:onHostEvent(kind, a, b, c) end,
    })

    if not host then
        self.error = tostring(err)
        return
    end
    self.host = host

    self.beacon = Discovery.newHost({
        info = {
            hostId     = app.clientId(),
            hostName   = self.hostName,
            lobbyName  = self.lobbyName,
            buildHash  = BuildInfo.buildHash,
            players    = 1,
            maxPlayers = NetLobby.MAX_SLOTS,
            mode       = "free",
            enetPort   = Protocol.PORT_ENET,
        },
    })
end

function LobbyScene:onHostEvent(kind, a, b, c)
    if kind == "join" or kind == "left" or kind == "lobby" then
        if self.beacon then
            self.beacon.info.players = self.host.lobby:occupiedCount()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Client
-- ---------------------------------------------------------------------------

function LobbyScene:startClient(opts)
    local app = self.app

    local client, err = Client.new({
        address   = opts.address,
        port      = opts.port or Protocol.PORT_ENET,
        clientId  = app.clientId(),
        name      = playerName(app),
        buildHash = BuildInfo.buildHash,
        onEvent   = function(kind, a, b, c) self:onClientEvent(kind, a, b, c) end,
    })

    if not client then
        self.error = tostring(err)
        return
    end
    self.client = client
    self.address = opts.address
end

function LobbyScene:onClientEvent(kind, a, b, c)
    if kind == "failed" then
        self.error = a
    elseif kind == "ruleset" then
        -- Das Regelwerk des Hosts gilt (ADR-005). Es ersetzt das eigene fuer
        -- die Dauer des Matches.
        self.app.applyRuleset(a)
    elseif kind == "start" then
        self:enterMatch(b or self.client.slot)
    end
end

-- ---------------------------------------------------------------------------
-- Uebergang ins Match
-- ---------------------------------------------------------------------------

function LobbyScene:names()
    local slots = self.role == "host" and self.host.lobby:toMessage().slots
                                       or self.client.lobbySlots
    local out = {}
    for i = 1, NetLobby.MAX_SLOTS do
        local slot = slots and slots[i]
        out[i] = (slot and slot.occupied and slot.name ~= "") and slot.name
                 or ("Spieler " .. i)
    end
    return out
end

function LobbyScene:enterMatch(slot)
    if self.started then return end
    self.started = true
    self.app.enterNetMatch({
        role    = self.role,
        host    = self.host,
        client  = self.client,
        ruleset = self.role == "host" and self.app.ruleset or self.client.ruleset,
        names   = self:names(),
        slot    = slot or 1,
    })
end

-- ---------------------------------------------------------------------------
-- Szene
-- ---------------------------------------------------------------------------

function LobbyScene:enter()
    Music.play("menu")
end

function LobbyScene:update(dt)
    if self.host then
        self.host:update(dt)
        if self.beacon then self.beacon:update() end

        -- Nach einem beendeten Match steht die Lobby wieder offen: der
        -- naechste Ballwechsel kostet dann keinen Neustart (Time-to-First-
        -- Match, CLAUDE.md §3.5).
        if self.started and not self.host.running then self.started = false end
    end

    if self.client then
        self.client:update(dt)
        if self.client.state == "playing" and not self.started then
            self:enterMatch(self.client.slot)
        end
    end
end

function LobbyScene:draw()
    local app = self.app
    local info

    if self.role == "host" then
        info = {
            role        = "host",
            lobbyName   = self.lobbyName,
            hostName    = self.hostName,
            address     = self.address,
            slots       = self.host and self.host.lobby:toMessage().slots or {},
            preset      = app.prefs.preset,
            rulesetHash = self.host and self.host:rulesetHash() or "?",
            error       = self.error,
            findings    = {},
            hint        = self.host and (self.host.lobby:isStartable()
                and "ENTER startet das Match"
                or "Warte auf einen Gast ...") or "",
        }
    else
        info = {
            role        = "client",
            lobbyName   = self.client and self.client.lobbyName or "Lobby",
            hostName    = self.client and self.client.hostName or "?",
            slots       = self.client and self.client.lobbySlots or {},
            preset      = app.prefs.preset,
            rulesetHash = self.client and self.client.rulesetHash or "?",
            error       = self.error,
            findings    = self.client and self.client.findings or {},
            hint        = self.ready and "Bereit -- warte auf den Host"
                                      or "ENTER meldet dich bereit",
        }
    end

    LobbyView.draw(info)
end

function LobbyScene:keypressed(key)
    if key == "escape" then
        self.app.leaveNet()
        return
    end

    if key == "return" or key == "kpenter" then
        if self.role == "host" then
            if self.host and self.host.lobby:isStartable() then
                self.host:startMatch()
                self:enterMatch(1)
            end
        elseif self.client and self.client.state == "lobby" then
            self.ready = not self.ready
            self.client:setReady(self.ready)
        end
    end
end

function LobbyScene:leave()
    if self.beacon then self.beacon:close() self.beacon = nil end
    if self.host then self.host:close() self.host = nil end
    if self.client then self.client:close() self.client = nil end
end

return LobbyScene
