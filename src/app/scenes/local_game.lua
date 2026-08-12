-- ============================================================================
-- src/app/scenes/local_game.lua -- ein lokales Match (M0-12)
--
-- Besitzt Zustand, Eingabequellen und die Tickschleife. Die Physik steckt in
-- src/sim/, die Kosmetik in src/render/ -- hier laeuft nur zusammen, was
-- zusammengehoert:
--
--     Eingaben einsammeln -> Step.tick -> Ereignisse in Kosmetik uebersetzen
--
-- Der feste Zeitschritt (M0-05) liegt hier, weil er zum Match gehoert und
-- nicht zum Programmstart.
-- ============================================================================

local World       = require("src.sim.world")
local State       = require("src.sim.state")
local Step        = require("src.sim.step")
local Rules       = require("src.sim.rules")
local LocalSource = require("src.input.local_source")
local BotSource   = require("src.input.bot_source")
local Fx          = require("src.render.fx")
local FxEvents    = require("src.render.fx_events")
local GameView    = require("src.render.game_view")
local Hud         = require("src.render.hud")
local Menu        = require("src.ui.menu")
local Tweaker     = require("src.ui.tweaker")

local LocalGame = {}
LocalGame.__index = LocalGame

function LocalGame.new(app)
    local self = setmetatable({
        name        = "local_game",
        app         = app,
        state       = State.new(app.ruleset),
        events      = {},
        accumulator = 0,
        inputs      = { 0, 0 },
        sources     = { nil, nil },
        tweaker     = Tweaker.new(app.ruleset),
        -- Haken fuer das Aufzeichnungswerkzeug (tools/reference_mode.lua).
        -- Im normalen Spiel bleibt er nil.
        onTick      = nil,
    }, LocalGame)

    self.sources[1] = LocalSource.new(1, app.bindings[1])
    self.sources[2] = self:makeP2Source()

    -- Ohne einen ersten Abgriff zeichnete die Interpolation den Ball beim
    -- Programmstart bei (0, 0) statt an der Aufschlagposition.
    GameView.capture(self.state)
    return self
end

function LocalGame:makeP2Source()
    if self.app.prefs.botActive then
        return BotSource.new(2, {
            blob = self.state.blobs[2], ball = self.state.ball,
            ruleset = self.app.ruleset, world = { width = World.WIDTH,
                                                  height = World.HEIGHT,
                                                  groundY = self.app.ruleset.blobGroundY or 500 },
            state = self.state, prefs = self.app.prefs,
        })
    end
    return LocalSource.new(2, self.app.bindings[2])
end

-- Belegung im Menue geaendert.
function LocalGame:refreshBindings()
    for slot = 1, 2 do
        local src = self.sources[slot]
        if src and src.setKeys then src:setKeys(self.app.bindings[slot]) end
    end
end

function LocalGame:launch(vsBot)
    self.app.prefs.botActive = vsBot
    -- Das Ruleset wird beim Matchstart festgelegt und aendert sich danach
    -- nicht mehr (ADR-005); der Live-Tweaker ist die Ausnahme fuer offline.
    self.app.applyPreset(self.app.prefs.preset)

    self.state.match.score[1], self.state.match.score[2] = 0, 0
    self.state.match.inProgress = true
    self.sources[2] = self:makeP2Source()
    self.tweaker.active = false
    Fx.reset()
    self:resetRally(1)
end

function LocalGame:resetRally(server)
    for i = #self.events, 1, -1 do self.events[i] = nil end
    Rules.resetBall(self.state, self.app.ruleset, server, self.events)
    self:processEvents()
end

-- Kosmetik aus den Ereignissen der Simulation. Die Zuordnung liegt seit M2-06
-- in `src/render/fx_events.lua`, weil die Netzszene als Host dieselbe braucht.
function LocalGame:processEvents()
    FxEvents.apply(self.events, self.app.prefs.volume, self.state)
end

-- ---------------------------------------------------------------------------
-- Ein Simulationsschritt. `Step.tick` sieht ausschliesslich World.TICK_DT.
-- ---------------------------------------------------------------------------
function LocalGame:tick()
    local window = math.max(1, math.floor(self.app.ruleset.dashWindow * World.TICK_RATE + 0.5))
    for i = 1, 2 do
        local src = self.sources[i]
        self.inputs[i] = src and src:poll(window) or 0
    end

    GameView.capture(self.state)
    Step.tick(self.state, self.inputs[1], self.inputs[2], self.app.ruleset, self.events)
    self:processEvents()
    Fx.update(World.TICK_DT)

    if self.onTick then self:onTick() end
end

function LocalGame:update(dt)
    self.accumulator = math.min(self.accumulator + dt, World.MAX_FRAME_DT)
    while self.accumulator >= World.TICK_DT do
        self.accumulator = self.accumulator - World.TICK_DT
        self:tick()
    end
    GameView.setAlpha(self.accumulator / World.TICK_DT)
end

function LocalGame:draw()
    local ruleset = self.app.ruleset
    Fx.applyShake()
    GameView.drawField(ruleset.blobGroundY or 500)

    local vp1, vp2 = GameView.draw(self.state, ruleset)

    -- Vor dem ersten Anpfiff gibt es nichts anzuzeigen: das Feld dient dann
    -- nur als Hintergrund fuer das Menue.
    if not self.state.match.inProgress then return end

    local names = Menu.displayNames(self.app.prefs.botActive)
    Hud.draw(self.state, ruleset, names, { vp1, vp2 })

    if self.state.match.phase == "gameover" then
        Hud.drawGameOver(self.state, names)
    end
    self.tweaker:draw()
end

function LocalGame:keypressed(key)
    if self.tweaker:keypressed(key) then return end

    if key == "escape" then
        self.app.openMenu()
    elseif key == "tab" or key == "f1" then
        self.tweaker.active = true
    elseif key == "r" and self.state.match.phase == "gameover" then
        self.state.match.score[1], self.state.match.score[2] = 0, 0
        self:resetRally(1)
    end
end

return LocalGame
