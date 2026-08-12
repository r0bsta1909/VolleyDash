-- ============================================================================
-- src/app/scenes/net_game.lua -- ein Match ueber das Netz (M2-02, M2-03, M2-09)
--
-- Eine Szene, zwei Rollen. Der Unterschied ist genau einer, und er ist der
-- Kern der ganzen Architektur (ADR-002):
--
--   HOST    simuliert. Er holt sich die eigene Eingabe von der Tastatur, die
--           des Gastes aus dem Eingabepuffer, ruft `Step.tick` und schickt
--           danach den Snapshot.
--   CLIENT  simuliert NICHT. Er schickt seine Eingabe und schreibt an, was
--           der Host ihm sendet -- zwei Ticks verzoegert, damit Jitter das
--           Bild nicht ruckeln laesst (`04_NETCODE_SPEC` §8).
--
-- Warum nicht `local_game.lua` erweitert: dort oeffnet ESC das Menue und
-- pausiert die Simulation. Beim Host waere das eine Pause, die der Gast nicht
-- mitbekommt -- das Bild steht, das Netz laeuft weiter. Eine eigene Szene ist
-- billiger als diese Sonderfaelle.
--
-- Client-seitige Vorhersage ist M3 und hier ausdruecklich NICHT eingebaut.
-- ============================================================================

local World       = require("src.sim.world")
local State       = require("src.sim.state")
local Step        = require("src.sim.step")
local Rules       = require("src.sim.rules")
local LocalSource = require("src.input.local_source")
local Snapshot    = require("src.net.snapshot")
local Protocol    = require("src.net.protocol")
local Fx          = require("src.render.fx")
local FxEvents    = require("src.render.fx_events")
local GameView    = require("src.render.game_view")
local Hud         = require("src.render.hud")
local Netstat     = require("src.render.netstat")
local Assets      = require("src.app.assets")

local NetGame = {}
NetGame.__index = NetGame

function NetGame.new(app, opts)
    local self = setmetatable({
        name        = "net_game",
        app         = app,
        role        = opts.role,
        host        = opts.host,
        client      = opts.client,
        ruleset     = opts.ruleset,
        names       = opts.names or { "Host", "Gast" },
        slot        = opts.slot or 1,
        state       = State.new(opts.ruleset),
        events      = {},
        accumulator = 0,
        simTick     = 0,   -- NICHT `tick`: das ist der Name der Methode
        overlay     = false,
        paused      = false,
        pauseText   = "",
        pauseLeft   = 0,
        result      = nil,
    }, NetGame)

    -- Beide Rollen steuern ihren eigenen Blob mit derselben Belegung. Wer
    -- Slot 2 hat, spielt trotzdem mit den Tasten von Spieler 1 -- alles andere
    -- waere eine Erklaerung wert, und Erklaerungen stehen unter Verdacht
    -- (CLAUDE.md §1).
    self.source = LocalSource.new(1, app.bindings[1])

    if self.role == "host" then
        self.host.onEvent = function(kind, a, b, c) self:onHostEvent(kind, a, b, c) end
        Rules.resetBall(self.state, self.ruleset, 1, self.events)
        self.state.match.score[1], self.state.match.score[2] = 0, 0
        self.state.match.inProgress = true
    else
        self.client.onEvent = function(kind, a, b, c) self:onClientEvent(kind, a, b, c) end
        self.state.match.inProgress = true
    end

    Fx.reset()
    GameView.capture(self.state)
    return self
end

-- ---------------------------------------------------------------------------
-- Ereignisse der Netzschicht
-- ---------------------------------------------------------------------------

function NetGame:onHostEvent(kind, a, b, c)
    if kind == "lost" then
        self.paused = true
        self.pauseText = "Warte auf " .. tostring(b or "Gegner") .. " ..."

    elseif kind == "resume" then
        self.paused = false

    elseif kind == "walkover" then
        -- 30 s ohne Rueckkehr: das Match endet, der Verbleibende gewinnt (§12).
        -- Im Turnier wird das als Walkover gewertet (M4).
        local mine = self.slot == 1 and 1 or 2
        self.state.match.score[mine] = self.ruleset.targetScore
        self.host:endMatch(self.state.match.score[1], self.state.match.score[2],
            Protocol.END.DISCONNECT)
        self.result = "Der Gegner ist nicht zurueckgekommen."
        self.paused = false
        self.state.match.phase = "gameover"

    elseif kind == "end" then
        self.result = self.result or "Match beendet."
    end
end

function NetGame:onClientEvent(kind, a, b, c)
    if kind == "pause" then
        self.paused = a
        self.pauseText = c or "Warte ..."
        self.pauseLeft = b or 0

    elseif kind == "end" then
        self.state.match.phase = "gameover"
        self.result = (c == Protocol.END.DISCONNECT)
            and "Der Gegner ist weg -- Match gewertet."
            or "Match beendet."

    elseif kind == "failed" then
        self.result = a
        self.state.match.phase = "gameover"
    end
end

-- ---------------------------------------------------------------------------
-- Takt
-- ---------------------------------------------------------------------------

function NetGame:tick()
    local window = math.max(1,
        math.floor(self.ruleset.dashWindow * World.TICK_RATE + 0.5))
    local mask = self.source:poll(window)

    if self.role == "host" then
        if self.paused then return end

        GameView.capture(self.state)
        Step.tick(self.state, mask, self.host:inputFor(2), self.ruleset, self.events)
        FxEvents.apply(self.events, self.app.prefs.volume, self.state)
        Fx.update(World.TICK_DT)

        self.host:publishSnapshot(self.state, self.simTick)
        self.simTick = self.simTick + 1

        if self.state.match.phase == "gameover" and not self.result then
            self.host:endMatch(self.state.match.score[1], self.state.match.score[2],
                Protocol.END.NORMAL)
            self.result = "Match beendet."
        end
        return
    end

    -- Client
    self.client:pushInput(mask)

    local snap = self.client:nextSnapshot()
    if snap then
        -- Vor dem Anwenden abgreifen: sonst gleitet die Darstellung von der
        -- alten zur neuen Stelle statt zu interpolieren (M0-05).
        GameView.capture(self.state)
        Snapshot.apply(snap, self.state, self.ruleset)
        self.simTick = snap.tick
    end
    Fx.update(World.TICK_DT)
end

function NetGame:update(dt)
    if self.role == "host" then self.host:update(dt) else self.client:update(dt) end
    if self.role == "client" then self.pauseLeft = math.max(0, self.pauseLeft - dt) end

    self.accumulator = math.min(self.accumulator + dt, World.MAX_FRAME_DT)
    while self.accumulator >= World.TICK_DT do
        self.accumulator = self.accumulator - World.TICK_DT
        self:tick()
    end
    GameView.setAlpha(self.accumulator / World.TICK_DT)
end

-- ---------------------------------------------------------------------------
-- Bild
-- ---------------------------------------------------------------------------

function NetGame:draw()
    Fx.applyShake()
    GameView.drawField(self.ruleset.blobGroundY or 500)
    local vp1, vp2 = GameView.draw(self.state, self.ruleset)
    Hud.draw(self.state, self.ruleset, self.names, { vp1, vp2 })

    if self.paused then
        local left = self.role == "host" and self.host:secondsLeft() or self.pauseLeft
        Netstat.drawPause(self.pauseText, left)
    end

    if self.state.match.phase == "gameover" then
        Hud.drawGameOver(self.state, self.names)
        if self.result then
            Assets.setFont(18)
            love.graphics.setColor(1, 1, 1, 0.7)
            love.graphics.printf(self.result, 0, World.HEIGHT / 2 + 70,
                World.WIDTH, "center")
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    if self.overlay then Netstat.draw(self:stats()) end
end

function NetGame:stats()
    if self.role == "host" then
        local queue = self.host.queues[2]
        return {
            role = "host", slot = self.slot, tick = self.simTick,
            rtt = self.host:appRttFor(2), peerRtt = self.host:rttFor(2),
            loss = self.host:lossFor(2) or 0,
            inputs = queue.received, repeats = queue.held,
            dropped = queue.dropped, invalid = queue.invalid,
            ack = self.host:ackTick(2), corrections = 0,
        }
    end
    return {
        role = "client", slot = self.slot, tick = self.simTick,
        rtt = self.client.rtt, peerRtt = self.client:peerRtt(),
        loss = self.client:peerLoss() or 0,
        buffer = self.client:bufferDepth(),
        received = self.client.stats.received,
        held = self.client.stats.held,
        dropped = self.client.stats.dropped,
        corrections = 0,
    }
end

function NetGame:keypressed(key)
    if key == "f3" then
        self.overlay = not self.overlay

    elseif key == "escape" then
        -- Nach dem Abpfiff geht es zurueck in die Lobby: das naechste Match
        -- kostet dann keinen neuen Handschlag. Mitten im Satz ist ESC dagegen
        -- ein Abbruch der ganzen Sitzung, und der Gegner merkt es sofort.
        if self.state.match.phase == "gameover" then
            self.app.leaveMatch()
        else
            self.app.leaveNet()
        end
    end
end

function NetGame:leave()
    if self.role == "host" then self.host.onEvent = function() end end
    if self.role == "client" then self.client.onEvent = function() end end
end

return NetGame
