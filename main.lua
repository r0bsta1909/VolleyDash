-- ============================================================================
-- VOLLEY DASH — prototype baseline
-- Controls: P1 = WASD, P2 = HUKJ
-- ============================================================================

local World       = require("src.sim.world")
local Ruleset     = require("src.sim.ruleset")
local Prefs       = require("src.app.prefs")
local Viewport    = require("src.render.viewport")
local Frame       = require("src.input.frame")
local LocalSource = require("src.input.local_source")
local BotSource   = require("src.input.bot_source")
local State       = require("src.sim.state")
local Step        = require("src.sim.step")
local Rules       = require("src.sim.rules")

-- ============================================================================
-- RULESET UND PREFS (M0-09, B-04, ADR-005)
--
-- `ruleset` beeinflusst die Simulation, wird im Netzwerkspiel vom Host
-- verteilt und gehasht und ist waehrend eines Matches unveraenderlich.
-- `prefs` ist rein lokal und geht niemanden sonst etwas an. Der Live-Tweaker
-- fasst ausschliesslich das Ruleset an, das Menue ausschliesslich die Prefs.
--
-- Beide Tabellen werden nie ersetzt, nur befuellt: Simulation, Bot und
-- Aufzeichnung halten Referenzen darauf.
-- ============================================================================
local prefs   = Prefs.new()
local ruleset = Ruleset.new(prefs.preset)

-- Reihenfolge fuer die Auswahl im Menue. `classic` steht vorn, weil es die
-- Voreinstellung ist (ADR-006).
local PRESET_ORDER = { "classic", "prototype" }

-- ============================================================================
-- TEMPORARY REFERENCE TOOLING (M0-03) -- goes away with M0-13, when the
-- headless test runner takes over recording and playback.
--
-- The fixed-timestep shim that used to live here is gone: M0-05 made 1/60 s
-- the real loop for everyone, so --fixed-dt has no meaning any more. What is
-- left is the recorder and the replay driver, both hooked into that loop.
--
-- Everything below is inert unless one of the command line flags is given:
--   --record            recorder overlay and F9/F10/F11
--   --record-selftest   automated smoke test of the recorder, then quit
--   --replay-all        replay every recorded rally with a fixed step and
--                       record the result as the fixed60 reference pass
--   --replay=R-04       the same for a single rally
--   --scene=R-11        run the scripted scene of that rally instead
--   --scene-probe=R-11  parameter sweep for a scene, prints, records nothing
--   --test              run the headless test suites and quit
--   --screenshot        grab one frame into the save directory, then quit.
--                       Keeps the normal window, so the letterbox of M0-04 is
--                       actually visible in the picture.
-- Without a flag the game behaves exactly as it does for a player. The
-- wrappers live at the bottom of this file, the patched call sites are marked
-- with "RECORDING SHIM".
-- ============================================================================
local REC = {
    selftest    = false,
    active      = false,
    queue       = nil,   -- rally ids still to replay
    sceneId     = nil,
    probeId     = nil,
}

for _, a in ipairs(arg or {}) do
    if a == "--record" then REC.active = true end
    if a == "--record-selftest" then REC.selftest = true end
    if a == "--replay-all" then
        REC.queue = { "R-01", "R-02", "R-03", "R-04", "R-05", "R-06",
                      "R-07", "R-08", "R-09", "R-10", "R-11" }
    end
    local one = a:match("^%-%-replay=(.+)$")
    if one then REC.queue = { one } end
    local scene = a:match("^%-%-scene=(.+)$")
    if scene then REC.queue = { scene }; REC.sceneId = scene end
    local probe = a:match("^%-%-scene%-probe=(.+)$")
    if probe then REC.probeId = probe end
    if a == "--write-manifest" then REC.writeManifest = true end
    if a == "--screenshot" then REC.shot = 0 end
    if a == "--test" then REC.test = true end
end

-- Tests laufen ohne Fenster, ohne Aufzeichnung, ohne Spiel. love.load bricht
-- danach ab (M0-06; der eigenstaendige Runner kommt in M0-13).
if REC.test then
    local ok, failed = require("tests.run_headless").run()
    love.event.quit(failed > 0 and 1 or 0)
    return
end
REC.active = REC.active or REC.selftest or REC.writeManifest or REC.queue ~= nil or REC.probeId ~= nil

-- Everything that produces reference data runs in the fixed 800x600 window and
-- with the two recording patches. --screenshot deliberately does not, otherwise
-- there is nothing to look at.
REC.refMode = REC.active
if REC.shot then REC.active = true end

-- Since M0-05 there is only one timestep. Every new recording is a fixed60 one.
REC.mode = "fixed60"

local Recorder = nil
local Replay = nil
if REC.active then Recorder = require("tools.record_replay") end
if REC.queue or REC.probeId then Replay = require("tools.replay_source") end
-- ============================================================================

-- ============================================================================
-- SAVE / LOAD SYSTEM
-- ============================================================================
love.filesystem.setIdentity("volleydash")

local function saveConfig()
    Prefs.save(prefs)
end

local function loadConfig()
    local loaded = Prefs.load()
    for k, v in pairs(loaded) do prefs[k] = v end
end

-- ============================================================================
-- SPIELER PROFILE & NAMEN
-- ============================================================================
local namePool = {
    "Blobber", "Slime", "Jelly", "Gloop", "Spiker", "Bouncer", "Titan", "Rookie", 
    "GigaBlob", "Wobble", "Squish", "LanKing", "Pudding", "SmashBro", "NoobSlayer"
}

-- RECORDING SHIM (M0-03): fixed seed while recording, so the header is honest.
-- Cosmetics only -- names, particles, camera shake. See docs/handoffs/CC-01_REPORT.md.
if REC.refMode then math.randomseed(1) else math.randomseed(os.time()) end
local p1NameIdx = math.random(1, #namePool)
local p2NameIdx = math.random(1, #namePool)
local botNameIdx = math.random(1, #namePool)

if p1NameIdx == p2NameIdx then p2NameIdx = (p2NameIdx % #namePool) + 1 end
if botNameIdx == p1NameIdx or botNameIdx == p2NameIdx then botNameIdx = (botNameIdx % #namePool) + 1 end

-- ============================================================================
-- VISUELLE EFFEKTE (Partikel & Kamera)
-- ============================================================================
local camera = { x = 0, y = 0, shakeTimer = 0, shakeMag = 0 }
local particles = {}

local function addShake(amount, duration)
    camera.shakeMag = amount
    camera.shakeTimer = duration
end

local function spawnDust(x, y, count, spread, upForce)
    for i = 1, count do
        table.insert(particles, {
            x = x + (math.random() * spread - spread/2),
            y = y,
            vx = (math.random() * 100 - 50),
            vy = -(math.random() * upForce + 50),
            life = 0.5 + math.random() * 0.5,
            maxLife = 1.0,
            size = math.random(3, 7)
        })
    end
end

local function updateParticles(dt)
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.life = p.life - dt
        p.vy = p.vy + 800 * dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        if p.life <= 0 then
            table.remove(particles, i)
        end
    end
end

local function drawParticles()
    for _, p in ipairs(particles) do
        local alpha = math.max(0, p.life / p.maxLife)
        love.graphics.setColor(0.85, 0.75, 0.55, alpha) 
        love.graphics.circle("fill", p.x, p.y, p.size)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawShadow(x, y, radius, groundY)
    local dist = groundY - y
    if dist < 0 then dist = 0 end
    local alpha = math.max(0, 0.6 - (dist / 800))
    local scale = math.max(0.4, 1 - (dist / 600))
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.ellipse("fill", x, groundY, radius * scale, (radius * 0.25) * scale)
    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================================
-- MENÜ SYSTEM
-- ============================================================================
local menu = {
    current = "main",
    main = {
        title = "VOLLEY DASH",
        selection = 1,
        items = {
            { name = "Local Match", target = "start" },
            { name = "Network Match [WIP]", target = "main" }, 
            { name = "Player Profiles", target = "profiles" },
            { name = "Settings", target = "settings" },
            { name = "Quit", action = function() saveConfig(); love.event.quit() end }
        }
    },
    start = {
        title = "LOCAL MATCH",
        selection = 1,
        items = {
            { name = "Play: 1v1 Local", action = function() launchGame(false) end },
            { name = "Play: VS Bot", action = function() launchGame(true) end },
            { 
                name = "Bot Level", 
                getValue = function() return tostring(prefs.botLevel) end,
                onLeft = function() prefs.botLevel = math.max(1, prefs.botLevel - 1); saveConfig() end,
                onRight = function() prefs.botLevel = math.min(3, prefs.botLevel + 1); saveConfig() end
            },
            {
                -- Das Preset wirkt erst beim naechsten Matchstart: waehrend
                -- eines Matches ist das Ruleset unveraenderlich (ADR-005).
                name = "Ruleset",
                getValue = function() return prefs.preset end,
                onLeft = function() cyclePreset(-1) end,
                onRight = function() cyclePreset(1) end
            },
            { name = "Back", target = "main" }
        }
    },
    profiles = {
        title = "PLAYER PROFILES",
        selection = 1,
        items = {
            { 
                name = "Player 1 Name", 
                getValue = function() return namePool[p1NameIdx] end,
                onLeft = function() p1NameIdx = p1NameIdx > 1 and (p1NameIdx - 1) or #namePool end,
                onRight = function() p1NameIdx = p1NameIdx < #namePool and (p1NameIdx + 1) or 1 end
            },
            { 
                name = "Player 2 Name (Local)", 
                getValue = function() return namePool[p2NameIdx] end,
                onLeft = function() p2NameIdx = p2NameIdx > 1 and (p2NameIdx - 1) or #namePool end,
                onRight = function() p2NameIdx = p2NameIdx < #namePool and (p2NameIdx + 1) or 1 end
            },
            { 
                name = "Bot Name", 
                getValue = function() return namePool[botNameIdx] end,
                onLeft = function() botNameIdx = botNameIdx > 1 and (botNameIdx - 1) or #namePool end,
                onRight = function() botNameIdx = botNameIdx < #namePool and (botNameIdx + 1) or 1 end
            },
            { name = "Back", target = "main" }
        }
    },
    settings = {
        title = "SETTINGS",
        selection = 1,
        items = {
            { 
                name = "Master Volume", 
                getValue = function() return math.floor(prefs.volume * 100) .. "%" end,
                onLeft = function() prefs.volume = math.max(0.0, prefs.volume - 0.05); love.audio.setVolume(prefs.volume); saveConfig() end,
                onRight = function() prefs.volume = math.min(1.0, prefs.volume + 0.05); love.audio.setVolume(prefs.volume); saveConfig() end
            },
            { name = "Open Live Tweaker", action = function() toggleTweaker() end },
            { name = "Controls [WIP]", target = "settings" },
            { name = "Display [WIP]", target = "settings" },
            { name = "Back", target = "main" }
        }
    }
}

local tweakMenu = {
    active = false,
    selectedIndex = 1,
    maxVisible = 16,
    options = {
        { name = "Ball-Boden (Y)",     key = "ballGroundY",   step = 5,   min = 480,  max = 560 },
        { name = "Aktiv-Impuls",       key = "activeTransfer",step = 0.05,min = 0.0,  max = 1.5 },
        { name = "Passiv-Abprall",     key = "passiveBounce", step = 0.05,min = 0.1,  max = 1.5 },
        { name = "Luft-Steuerung",     key = "airControl",    step = 0.05,min = 0.05, max = 1.0 },
        { name = "Ball-Schwerkraft",   key = "gravity",       step = 50,  min = 100,  max = 3000 },
        { name = "Blob-Schwerkraft",   key = "blobGravity",   step = 50,  min = 500,  max = 4000 },
        { name = "Ball-Geschwindigkeit", key = "ballBaseSpeed", step = 25,  min = 100,  max = 1200 },
        { name = "Max Ball-Speed",     key = "maxBallSpeed",  step = 50,  min = 500,  max = 3000 },
        { name = "Ball-Größe",         key = "ballRadius",    step = 2,   min = 8,    max = 80 },
        { name = "Sprungkraft",        key = "jumpForce",     step = 20,  min = -1500,max = -200 },
        { name = "Lauf-Tempo Boden",   key = "moveSpeed",     step = 20,  min = 100,  max = 1000 },
        { name = "Blob-Größe",         key = "blobRadius",    step = 2,   min = 20,   max = 100 },
        { name = "Netzhöhe",           key = "netHeight",     step = 10,  min = 40,   max = 350 },
        { name = "Aufschlag-Höhe",     key = "serveHeight",   step = 10,  min = 50,   max = 400 },
        { name = "Aufschlag-Boost",    key = "serveBoost",    step = 0.05,min = 0.1,  max = 3.0 },
        { name = "Wand-Abprall",       key = "wallBounce",    step = 0.05,min = 0.5,  max = 2.0 },
        { name = "Dash-Zeitfenster (Sek)",key = "dashWindow", step = 0.02,min = 0.05, max = 0.50 },
        { name = "Dash-Cooldown (Sek)",key = "dashCooldown",  step = 0.1, min = 0.1,  max = 5.0 },
        { name = "Dash-Tempo (Seite)", key = "dashSide",      step = 0.1, min = 1.0,  max = 5.0 },
        { name = "Dash-Höhe (Hoch)",   key = "dashUp",        step = 0.05,min = 1.0,  max = 3.0 },
        { name = "Speed-Scaling",      key = "speedScaling",  type = "bool" },
        { name = "Active Spike (Smash)",key = "activeSpike",  type = "bool" }
    }
}

-- Der Spielzustand liegt seit M0-08 vollstaendig in src/sim/state.lua.
-- `match`, `rally`, `p1`, `p2`, `ball`, `net` sind nur Abkuerzungen in diese
-- eine Tabelle hinein -- keine zweite Wahrheit.
local state, match, rally
local simEvents = {}
local resetRally   -- weiter unten definiert, hier fuer launchGame vorangestellt

local WORLD = { width = World.WIDTH, height = World.HEIGHT, groundY = ruleset.blobGroundY }
local p1, p2, ball, net

-- ============================================================================
-- EINGABE (M0-06, B-03)
--
-- Die Simulation liest keine Hardware mehr. Pro Tick steht je Spieler genau
-- ein InputFrame bereit, erzeugt von genau einer Quelle (ADR-014). sources
-- wird in love.load gefuellt; das Aufzeichnungswerkzeug haengt sich dort ein,
-- indem es eine Quelle austauscht -- mehr braucht die Wiedergabe nicht.
-- ============================================================================
local sources    = { nil, nil }
local inputs     = { 0, 0 }
local prevInputs = { 0, 0 }

local function dashWindowTicks()
    return math.max(1, math.floor(ruleset.dashWindow * World.TICK_RATE + 0.5))
end

local function gatherInputs()
    local window = dashWindowTicks()
    for i = 1, 2 do
        prevInputs[i] = inputs[i]
        inputs[i] = sources[i] and sources[i]:poll(window) or 0
    end
end

-- P2 ist entweder Mensch oder Bot. Beide liefern dasselbe Byte; die
-- Simulation merkt den Unterschied nicht (ADR-014).
local function makeP2Source()
    if prefs.botActive then
        return BotSource.new(2, {
            blob = p2, ball = ball, ruleset = ruleset,
            world = WORLD, state = state, prefs = prefs,
        })
    end
    return LocalSource.new(2)
end

-- Werte uebernehmen, ohne die Tabelle zu ersetzen: BotSource, Recorder und
-- die Simulation halten Referenzen auf genau diese eine Tabelle.
function applyRuleset(values)
    for k in pairs(Ruleset.FIELDS) do ruleset[k] = nil end
    for k, v in pairs(values) do
        if Ruleset.FIELDS[k] ~= nil then ruleset[k] = v end
    end
end

-- Preset im Menue durchschalten. Wirksam wird es beim naechsten Matchstart.
function cyclePreset(direction)
    local index = 1
    for i, name in ipairs(PRESET_ORDER) do
        if name == prefs.preset then index = i end
    end
    index = ((index - 1 + direction) % #PRESET_ORDER) + 1
    prefs.preset = PRESET_ORDER[index]
    saveConfig()
end

local function resetInputSources()
    for i = 1, 2 do
        local src = sources[i]
        if src and src.reset then src:reset() end
        inputs[i], prevInputs[i] = 0, 0
    end
end

-- ============================================================================
-- RENDER-INTERPOLATION (M0-05, B-02)
--
-- Die Simulation laeuft mit festen 1/60 s, gezeichnet wird mit der Bildrate des
-- Monitors. Ohne Interpolation ruckelt jedes Bild sichtbar, das nicht exakt auf
-- 60 Hz laeuft -- auf 144 Hz wiederholen sich Frames, auf 50 Hz fallen welche
-- aus. Gezeichnet wird deshalb zwischen dem Zustand vor und nach dem letzten
-- Tick, gewichtet mit dem Rest im Akkumulator.
--
-- Interpoliert werden ausschliesslich Anzeigewerte. Die Simulation liest diese
-- Tabellen nie.
-- ============================================================================
local renderPrev = {
    p1   = { x = 0, y = 0, tilt = 0 },
    p2   = { x = 0, y = 0, tilt = 0 },
    ball = { x = 0, y = 0, rot = 0 },
}
local renderView = { p1 = {}, p2 = {}, ball = {} }
local renderAlpha = 0

-- Vor jedem Tick aufrufen. Zugleich der Weg, eine Sprungstelle zu entschaerfen:
-- nach resetBall steht der Ball an einer neuen Stelle, und ohne diesen Aufruf
-- wuerde er einen Frame lang quer durchs Bild gleiten.
local function captureRenderState()
    if not (p1 and p2 and ball) then return end
    renderPrev.p1.x, renderPrev.p1.y, renderPrev.p1.tilt = p1.x, p1.y, p1.tiltAngle
    renderPrev.p2.x, renderPrev.p2.y, renderPrev.p2.tilt = p2.x, p2.y, p2.tiltAngle
    renderPrev.ball.x, renderPrev.ball.y, renderPrev.ball.rot = ball.x, ball.y, ball.rotation
end

local function lerp(a, b, t) return a + (b - a) * t end

local function blobView(dst, src, prev)
    for k, v in pairs(src) do dst[k] = v end
    dst.x = lerp(prev.x, src.x, renderAlpha)
    dst.y = lerp(prev.y, src.y, renderAlpha)
    dst.tiltAngle = lerp(prev.tilt, src.tiltAngle, renderAlpha)
    return dst
end

local function ballView(dst, src, prev)
    for k, v in pairs(src) do dst[k] = v end
    dst.x = lerp(prev.x, src.x, renderAlpha)
    dst.y = lerp(prev.y, src.y, renderAlpha)
    dst.rotation = lerp(prev.rot, src.rotation, renderAlpha)
    return dst
end

local assets = { bg = nil, blob = nil, ball = nil }
local sounds = {}

-- Der Inline-Bot ist mit M0-07 nach src/input/bot_source.lua gewandert
-- (B-07: es gab zwei Fassungen, B-09: sein Zustand lag auf dem Modul).

-- ============================================================================
-- AUDIO & ENGINE HELPERS
-- ============================================================================
local function playSound(snd)
    if snd then
        local clone = snd:clone()
        clone:setVolume(prefs.volume or 0.25)
        clone:play()
    end
end

function love.load()
    loadConfig() 
    
    love.window.setTitle("Volley Dash")
    if REC.refMode then
        -- RECORDING SHIM (M0-03). Since M0-04 the world no longer depends on
        -- the window, so this is not load bearing any more. It stays because
        -- the reference set has to be reproducible: same window, same header,
        -- and the "window differs from the last recording" warning keeps
        -- meaning something.
        love.window.setMode(800, 600, { resizable = false })
    else
        love.window.setMode(800, 600, { resizable = true, minwidth = 640, minheight = 480 })
        love.window.maximize()
    end

    local function loadImage(name)
        if love.filesystem.getInfo(name) then return love.graphics.newImage(name) end
        return nil
    end
    assets.bg = loadImage("bg.jpg") or loadImage("bg.png")
    assets.blob = loadImage("blob.png")
    assets.ball = loadImage("ball.png")

    local function loadSound(name)
        local baseName = name:gsub("%.%w+$", "")
        if love.filesystem.getInfo(baseName .. ".wav") then return love.audio.newSource(baseName .. ".wav", "static") end
        if love.filesystem.getInfo(baseName .. ".ogg") then return love.audio.newSource(baseName .. ".ogg", "static") end
        return nil
    end
    sounds.jump = loadSound("jump")
    sounds.dash = loadSound("dash")
    sounds.hit_blob = loadSound("hit_blob")
    sounds.hit_sand = loadSound("hit_sand")
    sounds.hit_net = loadSound("hit_net")
    sounds.hit_wall = loadSound("hit_wall")
    sounds.whistle = loadSound("whistle")
    sounds.whistle_end = loadSound("whistle_end")

    WORLD.groundY = ruleset.blobGroundY or 500
    love.graphics.setBackgroundColor(0, 0, 0)   -- Letterbox-Balken (M0-04)

    -- Der gesamte Spielzustand (M0-08). Alles Weitere sind nur Abkuerzungen
    -- in diese eine Tabelle.
    state = State.new(ruleset)
    match, rally = state.match, state.rally
    p1, p2 = state.blobs[1], state.blobs[2]
    ball, net = state.ball, state.net

    -- Farben sind Anzeige, nicht Simulation. Sie haengen deshalb hier an den
    -- Blobs und nicht in src/sim/state.lua.
    p1.color = { 0.15, 0.55, 0.95 }
    p2.color = { 0.95, 0.25, 0.25 }
    ball.color = assets.ball and { 1, 1, 1 } or { 0.98, 0.85, 0.12 }

    -- Eine Quelle je Spieler (M0-06, ADR-014). Das Aufzeichnungswerkzeug
    -- tauscht sie bei Bedarf gegen eine Wiedergabe-Quelle aus.
    sources[1] = LocalSource.new(1)
    sources[2] = makeP2Source()

    love.audio.setVolume(prefs.volume)
end

-- updateWorldDimensions() ist mit M0-04 entfallen (B-01). Die Weltgroesse
-- haengt nicht mehr am Fenster; die Fensteranpassung macht
-- src/render/viewport.lua als reine Render-Transformation.

function launchGame(vsBot)
    -- Das Ruleset wird beim Matchstart festgelegt und aendert sich danach
    -- nicht mehr (ADR-005). Der Live-Tweaker ist die dokumentierte Ausnahme
    -- fuer das Offline-Spiel.
    applyRuleset(Ruleset.PRESETS[prefs.preset] or Ruleset.PRESETS.classic)
    prefs.botActive = vsBot
    sources[2] = makeP2Source()
    match.score[1] = 0
    match.score[2] = 0
    match.inProgress = true
    match.phase = "serve"
    tweakMenu.active = false
    resetRally(1)
end

function toggleTweaker()
    if match.inProgress then
        match.phase = match.previousPhase
    else
        match.phase = "serve"
    end
    tweakMenu.active = true
    menu.current = "main" 
end

-- Kosmetik aus den Ereignissen der Simulation. Die Reihenfolge der
-- Staubwolken bleibt die des Prototyps, weil die Ereignisse in der
-- Reihenfolge ihres Entstehens kommen (M0-08).
local function processEvents(events)
    for i = 1, #events do
        local e = events[i]
        local kind = e.type

        if kind == "jump" then
            spawnDust(e.x, e.y, 8, 40, 100)
            playSound(sounds.jump)
        elseif kind == "dash" then
            playSound(sounds.dash)
            if e.up then
                spawnDust(e.x, e.y, 10, 40, 100)
            else
                spawnDust(e.x, e.y, 15, 60, 150)
            end
        elseif kind == "land" then
            spawnDust(e.x, e.y, 10, 50, 80)
        elseif kind == "wall_hit" then
            playSound(sounds.hit_wall)
        elseif kind == "net_hit" then
            playSound(sounds.hit_net)
        elseif kind == "blob_hit" then
            playSound(sounds.hit_blob)
        elseif kind == "dash_save" then
            addShake(5, 0.25)
        elseif kind == "fault" then
            addShake(4, 0.2)
        elseif kind == "smash" then
            addShake(3, 0.15)
        elseif kind == "ground_hit" then
            playSound(sounds.hit_sand)
            spawnDust(e.x, e.y, 25, 80, 200)
        elseif kind == "point" or kind == "side_out" then
            playSound(sounds.whistle)
        elseif kind == "match_over" then
            playSound(sounds.whistle_end)
        elseif kind == "rally_reset" then
            -- Sprungstelle: sonst gleitet der Ball einen Frame lang von der
            -- alten zur neuen Aufschlagposition (M0-05).
            captureRenderState()
        end
    end
end

-- Ballwechsel von aussen neu aufsetzen (Menue, Neustart nach dem Satz).
resetRally = function(server)
    for i = #simEvents, 1, -1 do simEvents[i] = nil end
    Rules.resetBall(state, ruleset, server, simEvents)
    processEvents(simEvents)
end

-- ============================================================================
-- LOGIK
-- ============================================================================

-- Ein Simulationsschritt. Die Physik steckt vollstaendig in src/sim/; hier
-- bleibt nur die Uebersetzung der Ereignisse in Kosmetik. Das Argument dient
-- nur noch der Lesbarkeit an den Aufrufstellen -- die Schrittweite ist eine
-- Konstante der Simulation (M0-05).
local function simulateTick(dt)
    Step.tick(state, inputs[1], inputs[2], ruleset, simEvents)
    processEvents(simEvents)

    -- Kosmetik laeuft mit der Tickrate mit, gehoert aber nicht in die
    -- Simulation: kein Rueckfluss in die Physik.
    if camera.shakeTimer > 0 then camera.shakeTimer = camera.shakeTimer - dt end
    updateParticles(dt)
    WORLD.groundY = ruleset.blobGroundY or 500
end

-- ============================================================================
-- FIXER SIMULATIONSSCHRITT (M0-05, B-02)
--
-- love.update bekommt die reale Frame-Zeit und verteilt sie auf ganze Ticks
-- von 1/60 s. Was uebrig bleibt, steht als renderAlpha fuer die Interpolation
-- bereit. Die Physik sieht ausschliesslich World.TICK_DT.
--
-- onPostTick gehoert dem temporaeren Werkzeug am Dateiende: die Aufzeichnung
-- haengt sich dort ein, ohne dass die Schleife etwas davon wissen muss. Der
-- Haken verschwindet mit dem Werkzeug.
-- ============================================================================
local accumulator = 0
local onPostTick    -- vom Aufzeichnungswerkzeug gesetzt, sonst nil

function love.update(dt)
    accumulator = math.min(accumulator + dt, World.MAX_FRAME_DT)

    while accumulator >= World.TICK_DT do
        accumulator = accumulator - World.TICK_DT
        gatherInputs()
        captureRenderState()
        simulateTick(World.TICK_DT)
        if onPostTick then onPostTick() end
    end

    renderAlpha = accumulator / World.TICK_DT
end

-- updateBlob, checkBlobBallCollision und checkNetCollision sind mit M0-08
-- nach src/sim/physics.lua gewandert, resetBall und awardPointTo nach
-- src/sim/rules.lua. main.lua kennt die Physik nicht mehr.

-- ============================================================================
-- INPUT EVENTS (MENÜ + SPIEL)
-- ============================================================================
-- handleDoubleTap ist mit M0-06 entfallen. Die Doppeltipp-Erkennung sitzt in
-- src/input/local_source.lua, zaehlt in Ticks statt in Sekunden und liefert
-- das dash-Bit; die Wirkung steht seit M0-08 in src/sim/step.lua.

function love.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen())
    end

    if match.phase == "menu" then
        local currentObj = menu[menu.current]
        
        if key == "escape" then
            if menu.current == "main" then
                if match.inProgress then
                    match.phase = match.previousPhase
                else
                    saveConfig()
                    love.event.quit() 
                end
            else
                menu.current = "main" 
            end
            return
        elseif key == "up" then
            currentObj.selection = math.max(1, currentObj.selection - 1)
        elseif key == "down" then
            currentObj.selection = math.min(#currentObj.items, currentObj.selection + 1)
        elseif key == "left" then
            local selectedItem = currentObj.items[currentObj.selection]
            if selectedItem.onLeft then selectedItem.onLeft() end
        elseif key == "right" then
            local selectedItem = currentObj.items[currentObj.selection]
            if selectedItem.onRight then selectedItem.onRight() end
        elseif key == "return" then
            local selectedItem = currentObj.items[currentObj.selection]
            if selectedItem.action then
                selectedItem.action()
            elseif selectedItem.target then
                menu.current = selectedItem.target
                menu[menu.current].selection = 1
            end
        end
        return
    end

    if key == "escape" then
        match.previousPhase = match.phase
        match.phase = "menu"
        menu.current = "main"
        tweakMenu.active = false
        saveConfig() 
        return
    end

    if tweakMenu.active and match.phase ~= "gameover" then
        if key == "tab" or key == "f1" then tweakMenu.active = false; saveConfig(); return end
        if key == "up" then tweakMenu.selectedIndex = math.max(1, tweakMenu.selectedIndex - 1) end
        if key == "down" then tweakMenu.selectedIndex = math.min(#tweakMenu.options, tweakMenu.selectedIndex + 1) end

        local opt = tweakMenu.options[tweakMenu.selectedIndex]
        if key == "left" or key == "right" then
            if opt.type == "bool" then
                ruleset[opt.key] = not ruleset[opt.key]
            else
                local delta = (key == "right" and 1 or -1) * opt.step
                if opt.key == "jumpForce" then delta = -delta end
                -- Grenzen kommen aus src/sim/ruleset.lua, damit es nur eine
                -- Wahrheit gibt (F-10).
                ruleset[opt.key] = Ruleset.clamp(opt.key, ruleset[opt.key] + delta)
            end
        end
        return
    end

    if key == "tab" or key == "f1" then tweakMenu.active = true end
    if key == "r" and match.phase == "gameover" then resetRally(1) end

    -- Bewegung, Sprung, Smash und Dash laufen seit M0-06 nicht mehr ueber
    -- Tastenereignisse, sondern ueber den InputFrame des jeweiligen Ticks.
end

-- ============================================================================
-- RENDERING
-- ============================================================================
function love.draw()
    Viewport.apply()

    if camera.shakeTimer > 0 then
        love.graphics.translate((math.random() * 2 - 1) * camera.shakeMag, (math.random() * 2 - 1) * camera.shakeMag)
    end

    love.graphics.setColor(1, 1, 1)
    if assets.bg then
        local bgW, bgH = assets.bg:getDimensions()
        love.graphics.draw(assets.bg, 0, 0, 0, WORLD.width / bgW, WORLD.height / bgH)
    else
        love.graphics.setColor(0.08, 0.12, 0.22)
        love.graphics.rectangle("fill", 0, 0, WORLD.width, WORLD.height)
        love.graphics.setColor(0.85, 0.72, 0.45)
        love.graphics.rectangle("fill", 0, WORLD.groundY, WORLD.width, WORLD.height - WORLD.groundY)
    end

    if match.phase == "menu" then
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", 0, 0, WORLD.width, WORLD.height)
        
        local currentObj = menu[menu.current]
        love.graphics.setFont(love.graphics.newFont(48))
        love.graphics.setColor(1, 0.85, 0.2)
        love.graphics.printf(currentObj.title, 0, 80, WORLD.width, "center")

        if match.inProgress and menu.current == "main" then
            love.graphics.setFont(love.graphics.newFont(16))
            love.graphics.setColor(0.2, 0.8, 0.2)
            love.graphics.printf("Game Paused - Press ESC to resume", 0, 140, WORLD.width, "center")
        end

        love.graphics.setFont(love.graphics.newFont(24))
        for i, item in ipairs(currentObj.items) do
            local y = 200 + (i * 40)
            local displayStr = item.name
            if item.getValue then
                displayStr = displayStr .. ": < " .. item.getValue() .. " >"
            end

            if i == currentObj.selection then
                love.graphics.setColor(1, 1, 1)
                love.graphics.printf("> " .. displayStr .. " <", 0, y, WORLD.width, "center")
            else
                love.graphics.setColor(0.6, 0.6, 0.6)
                love.graphics.printf(displayStr, 0, y, WORLD.width, "center")
            end
        end
        
        love.graphics.setFont(love.graphics.newFont(14))
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.printf("Use UP/DOWN to navigate. Use LEFT/RIGHT to change settings. Enter to select.", 0, WORLD.height - 30, WORLD.width, "center")

        Viewport.release()
        return
    end

    -- Ab hier wird der interpolierte Zustand gezeichnet, nicht der simulierte
    -- (M0-05). Die Tabellen sind Kopien; nichts davon fliesst zurueck.
    local vp1  = blobView(renderView.p1, p1, renderPrev.p1)
    local vp2  = blobView(renderView.p2, p2, renderPrev.p2)
    local vball = ballView(renderView.ball, ball, renderPrev.ball)

    drawShadow(vp1.x, vp1.y, ruleset.blobRadius, WORLD.groundY)
    drawShadow(vp2.x, vp2.y, ruleset.blobRadius, WORLD.groundY)
    drawShadow(vball.x, vball.y, ruleset.ballRadius * 1.5, ruleset.ballGroundY or 520)

    drawParticles()

    love.graphics.setColor(0.55, 0.35, 0.15)
    love.graphics.rectangle("fill", net.x, net.y, net.w, net.h, 3, 3)
    love.graphics.setColor(0.40, 0.20, 0.05)
    love.graphics.rectangle("line", net.x, net.y, net.w, net.h, 3, 3)

    drawBlob(vp1, true, vball)
    drawBlob(vp2, false, vball)

    love.graphics.setColor(vball.color)
    if vball.y + vball.radius >= 0 then
        if assets.ball then
            local bw, bh = assets.ball:getDimensions()
            local bScale = (vball.radius * 2) / bw
            love.graphics.draw(assets.ball, vball.x, vball.y, vball.rotation, bScale, bScale, bw/2, bh/2)
        else
            love.graphics.push()
            love.graphics.translate(vball.x, vball.y)
            love.graphics.rotate(vball.rotation)
            love.graphics.circle("fill", 0, 0, vball.radius)
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.circle("fill", -vball.radius*0.3, -vball.radius*0.3, vball.radius * 0.4)
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.line(0, 0, vball.radius, 0)
            love.graphics.pop()
        end
    else
        local indX = math.max(15, math.min(WORLD.width - 15, vball.x))
        love.graphics.polygon("fill", indX - 10, 4, indX + 10, 4, indX, 18)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("fill", indX, 8, 3)
    end

    local p1DisplayName = namePool[p1NameIdx]
    local p2DisplayName = prefs.botActive and namePool[botNameIdx] or namePool[p2NameIdx]

    love.graphics.setFont(love.graphics.newFont(32))
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.print(p1DisplayName .. ": " .. match.score[1], WORLD.width * 0.15 + 2, 32)
    love.graphics.print(p2DisplayName .. ": " .. match.score[2], WORLD.width * 0.65 + 2, 32)
    
    if match.servingPlayer == 1 then
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.print(p1DisplayName .. ": " .. match.score[1], WORLD.width * 0.15, 30)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(p2DisplayName .. ": " .. match.score[2], WORLD.width * 0.65, 30)
    else
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(p1DisplayName .. ": " .. match.score[1], WORLD.width * 0.15, 30)
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.print(p2DisplayName .. ": " .. match.score[2], WORLD.width * 0.65, 30)
    end

    love.graphics.setFont(love.graphics.newFont(16))
    local function drawCooldown(p, x)
        if p.cooldownTimer > 0 then
            love.graphics.setColor(0.9, 0.2, 0.2, 0.8)
            love.graphics.rectangle("fill", x - 30, WORLD.groundY + 15, 60 * (p.cooldownTimer / ruleset.dashCooldown), 4)
        end
    end
    drawCooldown(vp1, WORLD.width * 0.25)
    drawCooldown(vp2, WORLD.width * 0.75)

    if match.phase == "serve" then
        love.graphics.setColor(0, 0, 0, 0.6)
        local sideX = (match.servingPlayer == 1) and (WORLD.width * 0.25) or (WORLD.width * 0.75)
        love.graphics.print("WAITING FOR SERVE", sideX - 78, 77)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("WAITING FOR SERVE", sideX - 80, 75)
    elseif rally.faultTimer > 0 then
        local sideX = (rally.faultPlayer == 1) and (WORLD.width * 0.25) or (WORLD.width * 0.75)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.print("FAULT!", sideX - 28, 77)
        love.graphics.setColor(1, 0.2, 0.2, 1)
        love.graphics.print("FAULT!", sideX - 30, 75)
    elseif rally.touchCount > 0 then
        local sideX = (rally.lastTouchPlayer == 1) and (WORLD.width * 0.25) or (WORLD.width * 0.75)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.print("Touches: " .. rally.touchCount .. " / 3", sideX - 43, 77)
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.print("Touches: " .. rally.touchCount .. " / 3", sideX - 45, 75)
    end

    if match.phase == "gameover" then
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", 0, 0, WORLD.width, WORLD.height)
        
        love.graphics.setColor(1, 0.85, 0.2)
        love.graphics.setFont(love.graphics.newFont(48))
        local winnerName = (match.score[1] >= 15) and p1DisplayName or p2DisplayName
        love.graphics.printf(winnerName .. " WINS!", 0, WORLD.height/2 - 50, WORLD.width, "center")
        
        love.graphics.setFont(love.graphics.newFont(24))
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Press 'R' to play again or 'ESC' for Menu", 0, WORLD.height/2 + 20, WORLD.width, "center")
    end

    if tweakMenu.active and match.phase ~= "gameover" then
        local maxVisible = tweakMenu.maxVisible
        local startIndex = 1
        if tweakMenu.selectedIndex > maxVisible then
            startIndex = tweakMenu.selectedIndex - maxVisible + 1
        end
        local endIndex = math.min(#tweakMenu.options, startIndex + maxVisible - 1)

        love.graphics.setColor(0.04, 0.06, 0.1, 0.85)
        local boxHeight = 40 + ((endIndex - startIndex + 1) * 22)
        love.graphics.rectangle("fill", 10, 10, 390, boxHeight, 6, 6)
        
        love.graphics.setFont(love.graphics.newFont(12))
        love.graphics.setColor(1, 0.85, 0.2)
        love.graphics.print("LIVE TWEAKER (ESC = Menu | TAB = Hide)", 20, 18)

        local yOffset = 38
        for i = startIndex, endIndex do
            local opt = tweakMenu.options[i]
            if i == tweakMenu.selectedIndex then
                love.graphics.setColor(0.2, 0.4, 0.7, 0.8)
                love.graphics.rectangle("fill", 15, yOffset - 2, 380, 20, 4, 4)
                love.graphics.setColor(1, 1, 1)
            else
                love.graphics.setColor(0.8, 0.8, 0.8)
            end
            local valStr = tostring(ruleset[opt.key])
            if type(ruleset[opt.key]) == "number" then valStr = string.format(opt.step < 1 and "%.2f" or "%.0f", ruleset[opt.key]) end
            love.graphics.print(opt.name, 25, yOffset)
            love.graphics.print("< " .. valStr .. " >", 290, yOffset)
            yOffset = yOffset + 22
        end
        
        if endIndex < #tweakMenu.options then
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.print("v Weitere Optionen v", 150, yOffset)
        end
    end

    Viewport.release()
end

-- `ballRef` ist der interpolierte Ball (M0-05); die Augen folgen ihm. Ohne den
-- Parameter griffe die Funktion auf den simulierten Ball zu und die Pupillen
-- wuerden gegenueber dem gezeichneten Ball zappeln.
function drawBlob(p, isP1, ballRef)
    ballRef = ballRef or ball
    love.graphics.push()
    love.graphics.translate(p.x, p.y)
    love.graphics.rotate(p.tiltAngle)
    love.graphics.translate(-p.x, -p.y)
    love.graphics.setColor(1, 1, 1, 1)

    if assets.blob then
        love.graphics.setColor(p.color)
        local bw, bh = assets.blob:getDimensions()
        local bScaleX = (ruleset.blobRadius * 2) / bw
        local bScaleY = bScaleX 
        if not isP1 then bScaleX = -bScaleX end
        love.graphics.draw(assets.blob, p.x, p.y, 0, bScaleX, bScaleY, bw/2, bh)
    else
        local r = ruleset.blobRadius
        love.graphics.push()
        love.graphics.rotate(-p.tiltAngle) 
        love.graphics.setColor(0, 0, 0, 0.2)
        love.graphics.ellipse("fill", p.x, WORLD.groundY + 2, r, 6)
        love.graphics.pop()
        love.graphics.setColor(p.color)
        love.graphics.arc("fill", p.x, p.y - 5, r, math.pi, 2 * math.pi)
        love.graphics.rectangle("fill", p.x - r, p.y - 5, r * 2, 5)
        love.graphics.setColor(1, 1, 1, 0.25)
        love.graphics.arc("fill", p.x, p.y - 12, r * 0.7, math.pi, 2 * math.pi)
        local dx = ballRef.x - p.x
        local dy = ballRef.y - p.y
        local angle = math.atan2(dy, dx)
        local eyeOffsetX = isP1 and 14 or -14
        local eyeOffsetY = -r * 0.45
        love.graphics.setColor(1, 1, 1)
        love.graphics.circle("fill", p.x + eyeOffsetX, p.y + eyeOffsetY, 9)
        local pupilX = p.x + eyeOffsetX + math.cos(angle) * 3.5
        local pupilY = p.y + eyeOffsetY + math.sin(angle) * 3.5
        love.graphics.setColor(0.1, 0.1, 0.18)
        love.graphics.circle("fill", pupilX, pupilY, 4.5)
        love.graphics.setColor(1, 1, 1)
        love.graphics.circle("fill", pupilX - 1.5, pupilY - 1.5, 1.5)
    end
    love.graphics.pop()
end

-- ============================================================================
-- TEMPORARY RECORDING SHIM (M0-03) -- remove after reference replays are captured.
-- This is NOT the B-02 fixed-timestep implementation. Do not build on it.
--
-- The block wraps love.load / love.update / love.draw / love.keypressed instead
-- of editing them, so the recorded behaviour is provably the behaviour of the
-- unwrapped functions. In fixed60 mode the accumulator calls the ORIGINAL
-- love.update with a constant 1/60 and leaves the remainder for the next frame,
-- so the real-time relation is kept. Nothing inside love.update is rewritten.
-- ============================================================================
if REC.active then
    -- serveDelay stand hier bis M0-07 als Patch. Seit M0-08 ist die feste
    -- Aufschlagverzoegerung Regel (B-06, GDD P4) und kein Eingriff mehr.
    local patches = { "randomseed=1", "window=800x600 fixed" }

    Recorder.setup({ mode = REC.mode, step = World.TICK_DT, patches = patches })

    local baseLoad       = love.load
    local baseUpdate     = love.update
    local baseDraw       = love.draw
    local baseKeypressed = love.keypressed

    -- Ein aufgezeichneter Frame je Simulationstick, direkt aus der Schleife
    -- von M0-05. Frueher haben Shim und Aufzeichnung sich ihren eigenen
    -- Akkumulator geteilt; das ist mit B-02 erledigt.
    onPostTick = function() Recorder.step(World.TICK_DT) end

    -- ------------------------------------------------------------------
    -- Replay driver (M0-03). Feeds recorded InputFrames back into the
    -- prototype so the fixed60 reference pass does not have to be played a
    -- second time. Only the input source changes -- love.update, the
    -- collision code and every constant stay untouched.
    -- ------------------------------------------------------------------
    -- Die Wiedergabe ist seit M0-06 eine Quelle wie jede andere: sie liefert
    -- pro Tick ein Byte. Kein Umbiegen von love.keyboard, keine
    -- nachgestellten Tastenereignisse.
    local replayBits = { 0, 0 }
    local replaySource = { poll = function() return replayBits[1] end }
    local run = nil
    local beginNext

    local function applyInit(init)
        ball.x, ball.y, ball.vx, ball.vy = init.ball[1], init.ball[2], init.ball[3], init.ball[4]
        ball.rotation, ball.radius = 0, ruleset.ballRadius
        p1.x, p1.y, p1.vx, p1.vy = init.p1[1], init.p1[2], init.p1[3], init.p1[4]
        p2.x, p2.y, p2.vx, p2.vy = init.p2[1], init.p2[2], init.p2[3], init.p2[4]
        for _, p in ipairs({ p1, p2 }) do
            p.isGrounded = p.y >= WORLD.groundY
            p.cooldownTimer, p.dashTimer, p.dashSpeed = 0, 0, 0
            p.tiltAngle, p.touchCooldown, p.dashGrace = 0, 0, 0
        end
        rally.lastTouchPlayer, rally.touchCount = init.touch[1], init.touch[2]
        match.score[1], match.score[2] = init.score[1], init.score[2]
        match.servingPlayer, match.phase = init.server, init.phase
        rally.serveTimer, rally.serveDelay = 0, 1.0
        rally.faultTimer, rally.faultPlayer = 0, 0
        rally.ballSide = (ball.x < WORLD.width / 2) and 1 or 2
        rally.rallies, match.inProgress = 0, true
        prefs.botActive = true   -- die Aufnahmen sind gegen den Bot gespielt
        resetInputSources()
        camera.shakeTimer = 0
    end

    -- Der naechste Tick bekommt diese Bytes. P1 ueber die Quelle, P2 ueber den
    -- Bot-Haken -- der Bot-Zweig verbraucht seine Tabelle noch direkt (M0-07).
    local function feed(bits1, bits2)
        replayBits[1], replayBits[2] = bits1, bits2
    end

    beginNext = function()
        local id = table.remove(REC.queue, 1)
        if not id then
            Recorder.writeManifest()
            print("[replay] fertig")
            love.event.quit()
            run = nil
            return
        end

        local data
        if REC.sceneId == id then
            local scene = Replay.scene(id)
            if not scene then
                print("[replay] keine Szene fuer " .. id)
                return beginNext()
            end
            data = { count = scene.ticks, init = scene.makeInit(scene), scene = scene }
            Recorder.setDriver("scripted:" .. id)
        else
            local loaded, err = Replay.load("tests/replays/variable/" .. id .. ".json")
            if not loaded then
                print("[replay] " .. tostring(err))
                return beginNext()
            end
            data = loaded
            if data.ruleset then
                -- Die Aufzeichnung bringt ihr Regelwerk mit. Ohne das liefe
                -- die Wiedergabe gegen die heutige Voreinstellung.
                applyRuleset(Ruleset.fromSnapshot(data.ruleset))
            end
            Recorder.setDriver("replay:variable/" .. id .. ".json")
        end

        applyInit(data.init)
        Recorder.selectById(id)
        Recorder.start()
        run = { id = id, data = data, tick = 0, tail = 0 }
        print(string.format("[replay] %s: %d Ticks", id, data.count))
    end

    local TAIL_MAX = 400

    -- Ein Tick im Werkzeugmodus. Ruft denselben Schritt wie der Akkumulator,
    -- aber ohne ihn -- der Treiber bestimmt selbst, wann ein Tick faellt.
    -- Der Nachzug von captureRenderState haelt die Anzeige bei alpha = 0
    -- deckungsgleich mit dem simulierten Zustand.
    local function toolTick()
        gatherInputs()
        simulateTick(World.TICK_DT)
        captureRenderState()
    end

    local function replayStep()
        if not run then return end

        -- Five ticks past the end of the rally, so the awarded point is inside
        -- the file. A frame holds the state BEFORE its own step, so stopping on
        -- the deciding step would cut the result off.
        local AFTER = 5
        local rallyOver = match.phase ~= "play"
        if rallyOver and run.sawPlay then run.after = (run.after or 0) + 1 end
        if match.phase == "play" then run.sawPlay = true end

        -- A scripted scene ends when its rally ends, not when the tick budget
        -- runs out. Keeps the reference short and its outcome unambiguous.
        if run.data.scene and run.sawPlay and (run.after or 0) > AFTER then
            run.tick = run.data.count
        end

        if run.tick >= run.data.count then
            -- Let a replayed rally finish. 07_TEST_PLAN section 2 grades on the
            -- outcome, so a reference that stops mid-flight cannot be graded.
            -- Zero input, at most TAIL_MAX ticks.
            if (not rallyOver or (run.after or 0) <= AFTER) and run.tail < TAIL_MAX then
                feed(0, 0)
                toolTick()
                Recorder.step(World.TICK_DT)
                run.tail = run.tail + 1
                return
            end
            Recorder.stop()
            print(string.format("[replay] %s fertig (+%d Ticks Auslauf)", run.id, run.tail))
            beginNext()
            return
        end
        local b1, b2
        if run.data.scene then
            b1, b2 = run.data.scene.inputs(run.data.scene, run.tick)
        else
            local pair = run.data.inputs[run.tick + 1]
            b1, b2 = pair[1], pair[2]
        end
        feed(b1, b2)
        toolTick()
        Recorder.step(World.TICK_DT)
        run.tick = run.tick + 1
    end

    -- Parameter sweep for a scripted scene. Runs the simulation in a tight
    -- loop without recording and prints the metrics of every candidate, so the
    -- scene parameters are measured instead of guessed.
    local function sceneProbe(id)
        local scene = Replay.scene(id)
        if not scene then print("[probe] keine Szene fuer " .. id) return end
        local sw = scene.sweep
        for candidate = sw.from, sw.to, (sw.step or 1) do
            scene[sw.field] = candidate
            applyInit(scene.makeInit(scene))

            local peak, contacts, contactVx, airSmash = 0, 0, 0, false
            local postPeak, preContact = 0, 0
            local prevTouch, prevPlayer = 0, 0
            for tick = 0, scene.ticks - 1 do
                local b1, b2 = scene.inputs(scene, tick)
                feed(b1, b2)
                local wasAir, blobVx = not p1.isGrounded, p1.vx
                local smashHeld = Frame.has(b1, Frame.SMASH)
                local before = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
                toolTick()

                local v = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
                if v > peak then peak = v end
                if rally.touchCount > 0
                   and (rally.touchCount > prevTouch or rally.lastTouchPlayer ~= prevPlayer) then
                    contacts = contacts + 1
                    if v > postPeak then postPeak = v; preContact = before end
                    if rally.lastTouchPlayer == 1 then
                        if math.abs(blobVx) > math.abs(contactVx) then contactVx = blobVx end
                        if wasAir and smashHeld then airSmash = true end
                    end
                end
                prevTouch, prevPlayer = rally.touchCount, rally.lastTouchPlayer
            end

            print(string.format(
                "[probe] %s %s=%-5s peak=%8.2f contacts=%d maxContactVx=%7.1f airSmash=%-5s "
                .. "bestContact %7.1f -> %7.1f score=%d:%d phase=%s",
                id, sw.field, tostring(candidate), peak, contacts, contactVx, tostring(airSmash),
                preContact, postPeak, match.score[1], match.score[2], match.phase))
        end
    end

    function love.load()
        baseLoad()
        Recorder.attach({
            world = WORLD, state = state, ruleset = ruleset,
            prefs = prefs, inputs = inputs,
        })
        if REC.selftest then
            -- Ohne VSync laeuft der Selbsttest mit weit ueber 60 Bildern je
            -- Sekunde. Die 300 Ticks muessen trotzdem rund 5 s dauern -- das
            -- ist der Nachweis, dass die Simulation an der Tickrate haengt und
            -- nicht an der Bildrate (B-02).
            love.window.setVSync(0)
            print("[selftest] love " .. table.concat({ love.getVersion() }, ".", 1, 3))
            print("[selftest] hasKeyRepeat = " .. tostring(love.keyboard.hasKeyRepeat()))
            print("[selftest] window " .. table.concat({ love.graphics.getDimensions() }, "x"))
            print("[selftest] WORLD " .. WORLD.width .. "x" .. WORLD.height)
            launchGame(true)
            resetRally(2)         -- let the bot serve, otherwise nothing moves
            while Recorder.currentId() ~= "R-00" do Recorder.nextRally() end
            Recorder.start()
            REC.selftestStart, REC.selftestFrames = love.timer.getTime(), 0
        end

        if REC.refMode then
            -- Referenzdaten entstehen mit dem Preset des Prototyps, nicht mit
            -- der Vanilla-Voreinstellung: die Rallyes brauchen Dash und Smash
            -- (ADR-006 gilt fuer das Spiel, nicht fuer die Beweisstuecke).
            applyRuleset(Ruleset.PRESETS.prototype)
        end

        if REC.writeManifest then
            Recorder.writeManifest()
            print("[manifest] tests/replays/manifest.json geschrieben")
            love.event.quit()
            return
        end

        if REC.queue or REC.probeId then
            -- Seit M0-07 ist die Wiedergabe vollstaendig: beide Spieler
            -- bekommen eine Quelle, die die aufgezeichneten Bytes ausgibt.
            -- Am Spiel selbst wird nichts umgebogen.
            sources[1] = replaySource
            sources[2] = { poll = function() return replayBits[2] end }
            love.window.setVSync(0)

            if REC.probeId then
                sceneProbe(REC.probeId)
                love.event.quit()
            else
                beginNext()
            end
        end
    end

    function love.update(dt)
        Recorder.update(dt)

        if REC.shot then
            -- One frame into the save directory, then out. Two spare frames so
            -- the asynchronous capture is written before the process ends.
            REC.shot = REC.shot + 1
            if REC.shot == 5 then
                launchGame(true)   -- the field is more interesting than the menu
                resetRally(2)
            elseif REC.shot == 150 then
                love.graphics.captureScreenshot("viewport.png")
                print("[shot] " .. love.filesystem.getSaveDirectory() .. "/viewport.png")
            elseif REC.shot > 152 then
                love.event.quit()
            end
            baseUpdate(dt)
            return
        end

        if REC.queue then
            replayStep()
            return
        end

        -- Normalfall: der echte Akkumulator laeuft, die Aufzeichnung haengt
        -- ueber onPostTick an jedem Tick.
        baseUpdate(dt)
        if REC.selftestFrames then REC.selftestFrames = REC.selftestFrames + 1 end

        if REC.selftest and Recorder.tickCount() >= 300 then
            Recorder.stop()
            print(string.format("[selftest] %d Ticks in %.2f s Echtzeit, %d Frames",
                Recorder.tickCount(), love.timer.getTime() - REC.selftestStart, REC.selftestFrames))
            love.event.quit()
        end
    end

    function love.draw()
        baseDraw()
        if REC.shot then return end   -- a screenshot shows the game, not the tooling

        love.graphics.push()
        love.graphics.origin()
        love.graphics.setFont(love.graphics.newFont(13))
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.print("REC MODE 1/60", 12, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.pop()

        Recorder.draw()
    end

    function love.keypressed(key)
        -- F9/F10/F11 and, while recording, TAB/F1 belong to the recorder.
        -- F11 is the prototype's fullscreen toggle; changing the window size
        -- during a recording would poison the reference (trap 6).
        if Recorder.keypressed(key) then return end
        baseKeypressed(key)
    end
end