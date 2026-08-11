-- ============================================================================
-- VOLLEY DASH — prototype baseline
-- Controls: P1 = WASD, P2 = HUKJ
-- ============================================================================

local defaults = {
    botActive = true,        
    botLevel = 3,            
    
    volume = 0.25,           
    blobGroundY = 500,       
    ballGroundY = 520,       
    activeTransfer = 0.40,   
    passiveBounce = 0.75,    
    airControl = 0.50,       
    gravity = 1000,          
    blobGravity = 1600,      
    ballBaseSpeed = 500,     
    maxBallSpeed = 1400,     
    ballRadius = 30,         
    jumpForce = -750,        
    moveSpeed = 600,         
    blobRadius = 54,         
    netHeight = 160,         
    serveHeight = 140,       
    serveBoost = 0.50,       
    wallBounce = 0.70,       
    
    dashCooldown = 1.5,      
    dashSide = 2.5,          
    dashUp = 1.3,            
    dashWindow = 0.20,       
    
    speedScaling = false,    
    activeSpike = true       
}

local config = {}
for k, v in pairs(defaults) do config[k] = v end

-- ============================================================================
-- SAVE / LOAD SYSTEM
-- ============================================================================
love.filesystem.setIdentity("volleydash")

local function saveConfig()
    local data = ""
    for k, v in pairs(config) do
        data = data .. tostring(k) .. "=" .. tostring(v) .. "\n"
    end
    love.filesystem.write("volleydash_prefs.sav", data)
end

local function loadConfig()
    if love.filesystem.getInfo("volleydash_prefs.sav") then
        for line in love.filesystem.lines("volleydash_prefs.sav") do
            local k, v = line:match("([^=]+)=([^=]+)")
            if k and v then
                if type(defaults[k]) == "number" then config[k] = tonumber(v)
                elseif type(defaults[k]) == "boolean" then config[k] = (v == "true")
                else config[k] = v end
            end
        end
    end
end

-- ============================================================================
-- SPIELER PROFILE & NAMEN
-- ============================================================================
local namePool = {
    "Blobber", "Slime", "Jelly", "Gloop", "Spiker", "Bouncer", "Titan", "Rookie", 
    "GigaBlob", "Wobble", "Squish", "LanKing", "Pudding", "SmashBro", "NoobSlayer"
}

math.randomseed(os.time())
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
                getValue = function() return tostring(config.botLevel) end,
                onLeft = function() config.botLevel = math.max(1, config.botLevel - 1); saveConfig() end,
                onRight = function() config.botLevel = math.min(3, config.botLevel + 1); saveConfig() end
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
                getValue = function() return math.floor(config.volume * 100) .. "%" end,
                onLeft = function() config.volume = math.max(0.0, config.volume - 0.05); love.audio.setVolume(config.volume); saveConfig() end,
                onRight = function() config.volume = math.min(1.0, config.volume + 0.05); love.audio.setVolume(config.volume); saveConfig() end
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

local gameState = { 
    state = "menu",          
    previousState = "serve", 
    gameInProgress = false,  
    scoreP1 = 0, scoreP2 = 0, rallies = 0, 
    lastTouchPlayer = 0, touchCount = 0,
    servingPlayer = 1,
    serveTimer = 0, serveDelay = 1.0,
    faultTimer = 0, faultPlayer = 0,
    ballSide = 1 
}

local WORLD = { width = 800, height = 600, groundY = config.blobGroundY }
local scale = 1
local p1, p2, ball, net

local assets = { bg = nil, blob = nil, ball = nil }
local sounds = {}
local lastTaps = {} 

-- ============================================================================
-- BOT KI MODUL
-- ============================================================================
local Bot = {
    targetX = 600,
    reactionTimer = 0,
    difficulties = {
        [1] = { reactionDelay = 0.45, jitter = 70, useDash = false, useSmash = false }, 
        [2] = { reactionDelay = 0.20, jitter = 25, useDash = false, useSmash = true  }, 
        [3] = { reactionDelay = 0.04, jitter = 4,  useDash = true,  useSmash = true  }  
    }
}

function Bot.predictLandingX(b, c, w, diffSettings)
    local simX, simY, simVx, simVy = b.x, b.y, b.vx, b.vy
    local simDt = 0.016
    local headY = w.groundY - (c.blobRadius * 1.2)

    for t = 0, 2.5, simDt do
        simVy = simVy + c.gravity * simDt
        simX = simX + simVx * simDt
        simY = simY + simVy * simDt

        if simX - c.ballRadius < 0 then
            simX = c.ballRadius
            simVx = math.abs(simVx) * c.wallBounce
        elseif simX + c.ballRadius > w.width then
            simX = w.width - c.ballRadius
            simVx = -math.abs(simVx) * c.wallBounce
        end

        if simY >= headY and simVy > 0 then
            local jitter = (math.random() * 2 - 1) * diffSettings.jitter
            local finalX = simX + jitter
            return math.max(w.width / 2 + c.blobRadius, math.min(w.width - c.blobRadius, finalX))
        end
    end
    return w.width * 0.75
end

function Bot.updateAI(bot, b, dt, c, w, state)
    local diff = Bot.difficulties[c.botLevel] or Bot.difficulties[2]
    local inputs = { left = false, right = false, jump = false, smash = false, dashDir = nil }

    if state.state == "serve" and state.servingPlayer == 2 then
        if state.serveTimer < state.serveDelay then return inputs end

        if c.botLevel == 1 then
            if bot.x < b.x + 10 then inputs.right = true else inputs.left = true; inputs.jump = true end
        elseif c.botLevel == 2 then
            if bot.x < b.x + 15 then inputs.right = true else inputs.left = true; inputs.jump = true end
        else
            if bot.x < b.x + 25 then 
                inputs.right = true 
            else 
                inputs.left = true
                if math.abs(bot.x - b.x) < 35 then inputs.jump = true end
                if b.y < w.groundY - c.serveHeight + 20 then inputs.smash = true end
            end
        end
        return inputs
    end

    Bot.reactionTimer = Bot.reactionTimer + dt
    if Bot.reactionTimer >= diff.reactionDelay then
        Bot.reactionTimer = 0
        if b.x > w.width * 0.35 or b.vx > 0 then
            Bot.targetX = Bot.predictLandingX(b, c, w, diff)
            if state.lastTouchPlayer == 2 and state.touchCount == 2 then
                Bot.targetX = Bot.targetX + 25 
            end
        else
            Bot.targetX = w.width * 0.75 
        end
    end

    local tolerance = 8
    if bot.x < Bot.targetX - tolerance then inputs.right = true
    elseif bot.x > Bot.targetX + tolerance then inputs.left = true end

    if diff.useDash and bot.cooldownTimer <= 0 then
        local distToTarget = math.abs(bot.x - Bot.targetX)
        local timeToImpact = (w.groundY - b.y) / math.max(1, b.vy)
        local timeToRun = distToTarget / c.moveSpeed
        
        if b.x > w.width / 2 and timeToImpact > 0 and timeToRun > timeToImpact then
            inputs.dashDir = (bot.x < Bot.targetX) and "k" or "h"
            if timeToImpact < 0.25 then inputs.jump = true end
        end
    end

    local distToBallX = math.abs(bot.x - b.x)
    local ballInJumpZone = b.y > (w.groundY - c.blobRadius * 3.5) and b.y < w.groundY

    if distToBallX < (c.blobRadius + c.ballRadius + 20) and ballInJumpZone then
        if bot.isGrounded then inputs.jump = true end
        
        if diff.useSmash and c.activeSpike and not bot.isGrounded then
            if b.x < w.width * 0.65 and b.y < (w.groundY - c.netHeight) then 
                inputs.smash = true 
            elseif state.lastTouchPlayer == 2 and state.touchCount == 2 and b.vy > 0 then
                inputs.smash = true
            end
        end
    end

    return inputs
end

-- ============================================================================
-- AUDIO & ENGINE HELPERS
-- ============================================================================
local function playSound(snd)
    if snd then
        local clone = snd:clone()
        clone:setVolume(config.volume or 0.25)
        clone:play()
    end
end

function love.load()
    loadConfig() 
    
    love.window.setTitle("Volley Dash")
    love.window.setMode(800, 600, { resizable = true, minwidth = 640, minheight = 480 })
    love.window.maximize()

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

    updateWorldDimensions()

    -- Blobs bekommen einen dashGrace Timer für den Dash-Save Shake!
    p1 = { x = WORLD.width * 0.25, y = WORLD.groundY, vx = 0, vy = 0, isGrounded = true, color = {0.15, 0.55, 0.95}, cooldownTimer = 0, dashTimer = 0, tiltAngle = 0, dashSpeed = 0, touchCooldown = 0, dashGrace = 0, botSmash = false }
    p2 = { x = WORLD.width * 0.75, y = WORLD.groundY, vx = 0, vy = 0, isGrounded = true, color = {0.95, 0.25, 0.25}, cooldownTimer = 0, dashTimer = 0, tiltAngle = 0, dashSpeed = 0, touchCooldown = 0, dashGrace = 0, botSmash = false }
    net = { x = WORLD.width / 2 - 5, y = WORLD.groundY - config.netHeight, w = 10, h = config.netHeight }
    ball = { x = WORLD.width * 0.25, y = WORLD.groundY - config.serveHeight, vx = 0, vy = 0, radius = config.ballRadius, rotation = 0, color = {1, 1, 1} }
    
    if not assets.ball then ball.color = {0.98, 0.85, 0.12} end 
    
    love.audio.setVolume(config.volume)
end

function updateWorldDimensions()
    local winW, winH = love.graphics.getDimensions()
    scale = winH / 600
    WORLD.width = winW / scale
    WORLD.height = 600
    WORLD.groundY = config.blobGroundY or 500
    if net then net.x = WORLD.width / 2 - 5 end
end

function launchGame(vsBot)
    config.botActive = vsBot
    gameState.scoreP1 = 0
    gameState.scoreP2 = 0
    gameState.gameInProgress = true
    gameState.state = "serve"
    tweakMenu.active = false
    resetBall(1)
end

function toggleTweaker()
    if gameState.gameInProgress then
        gameState.state = gameState.previousState
    else
        gameState.state = "serve"
    end
    tweakMenu.active = true
    menu.current = "main" 
end

function resetBall(server)
    gameState.servingPlayer = server
    gameState.state = "serve"
    gameState.faultTimer = 0
    
    gameState.serveTimer = 0
    gameState.serveDelay = 1.0 + math.random() * 0.5 
    
    ball.x = (server == 1) and (WORLD.width * 0.25) or (WORLD.width * 0.75)
    ball.y = WORLD.groundY - config.serveHeight 
    ball.vx = 0
    ball.vy = 0
    ball.rotation = 0
    
    gameState.rallies = 0
    gameState.lastTouchPlayer = 0
    gameState.touchCount = 0
    gameState.ballSide = server 
    
    if p1 then p1.tiltAngle = 0; p1.touchCooldown = 0; p1.dashGrace = 0; p1.x = WORLD.width * 0.25 end
    if p2 then p2.tiltAngle = 0; p2.touchCooldown = 0; p2.dashGrace = 0; p2.x = WORLD.width * 0.75 end
end

local function awardPointTo(winningPlayer)
    if gameState.servingPlayer == winningPlayer then
        if winningPlayer == 1 then
            gameState.scoreP1 = gameState.scoreP1 + 1
        else
            gameState.scoreP2 = gameState.scoreP2 + 1
        end
        
        if gameState.scoreP1 >= 15 or gameState.scoreP2 >= 15 then
            gameState.state = "gameover"
            playSound(sounds.whistle_end)
        else
            playSound(sounds.whistle)
            resetBall(winningPlayer)
        end
    else
        playSound(sounds.whistle)
        resetBall(winningPlayer)
    end
end

-- ============================================================================
-- LOGIK
-- ============================================================================
function love.update(dt)
    if gameState.state == "menu" or gameState.state == "gameover" then return end
    dt = math.min(dt, 0.05)
    updateWorldDimensions()

    if camera.shakeTimer > 0 then camera.shakeTimer = camera.shakeTimer - dt end
    updateParticles(dt)

    net.y = WORLD.groundY - config.netHeight
    net.h = config.netHeight
    ball.radius = config.ballRadius
    
    if gameState.state == "serve" then
        ball.y = WORLD.groundY - config.serveHeight
        gameState.serveTimer = gameState.serveTimer + dt 
    end

    if gameState.faultTimer > 0 then
        gameState.faultTimer = gameState.faultTimer - dt
        if gameState.faultTimer <= 0 then
            if gameState.faultPlayer == 1 then awardPointTo(2) else awardPointTo(1) end
            return 
        end
    end

    -- SPIELER 1 
    if p1.dashGrace > 0 then p1.dashGrace = p1.dashGrace - dt end
    if p1.cooldownTimer > 0 then p1.cooldownTimer = p1.cooldownTimer - dt end
    if p1.touchCooldown > 0 then p1.touchCooldown = p1.touchCooldown - dt end
    if p1.dashTimer > 0 then
        p1.dashTimer = p1.dashTimer - dt
        p1.vx = p1.dashSpeed
        p1.tiltAngle = (p1.dashSpeed > 0) and 0.6 or -0.6 
    else
        p1.tiltAngle = p1.tiltAngle * 0.8 
        local p1Speed = p1.isGrounded and config.moveSpeed or (config.moveSpeed * config.airControl)
        p1.vx = love.keyboard.isDown("a") and -p1Speed or (love.keyboard.isDown("d") and p1Speed or 0)
    end
    updateBlob(p1, dt, 0, net.x)

    -- SPIELER 2 
    if p2.dashGrace > 0 then p2.dashGrace = p2.dashGrace - dt end
    local p2Speed = p2.isGrounded and config.moveSpeed or (config.moveSpeed * config.airControl)
    
    if config.botActive then
        local botInputs = Bot.updateAI(p2, ball, dt, config, WORLD, gameState)
        p2.botSmash = botInputs.smash
        
        if p2.cooldownTimer > 0 then p2.cooldownTimer = p2.cooldownTimer - dt end
        if p2.touchCooldown > 0 then p2.touchCooldown = p2.touchCooldown - dt end
        
        if p2.dashTimer > 0 then
            p2.dashTimer = p2.dashTimer - dt
            p2.vx = p2.dashSpeed
            p2.tiltAngle = (p2.dashSpeed > 0) and 0.6 or -0.6
        else
            p2.tiltAngle = p2.tiltAngle * 0.8
            p2.vx = botInputs.left and -p2Speed or (botInputs.right and p2Speed or 0)
        end
        
        if botInputs.jump and p2.isGrounded then
            p2.vy = config.jumpForce
            p2.isGrounded = false
            spawnDust(p2.x, p2.y, 8, 40, 100) 
            playSound(sounds.jump)
        end
        
        if botInputs.dashDir and p2.cooldownTimer <= 0 then
            p2.dashTimer = 0.2
            p2.dashSpeed = (botInputs.dashDir == "k" and 1 or -1) * config.moveSpeed * config.dashSide
            p2.cooldownTimer = config.dashCooldown
            p2.dashGrace = 0.5 -- Bot Dash-Rettung Fenster
            spawnDust(p2.x, p2.y, 15, 60, 150) 
            playSound(sounds.dash)
        end
    else
        p2.botSmash = false
        if p2.cooldownTimer > 0 then p2.cooldownTimer = p2.cooldownTimer - dt end
        if p2.touchCooldown > 0 then p2.touchCooldown = p2.touchCooldown - dt end
        if p2.dashTimer > 0 then
            p2.dashTimer = p2.dashTimer - dt
            p2.vx = p2.dashSpeed
            p2.tiltAngle = (p2.dashSpeed > 0) and 0.6 or -0.6
        else
            p2.tiltAngle = p2.tiltAngle * 0.8
            p2.vx = love.keyboard.isDown("h") and -p2Speed or (love.keyboard.isDown("k") and p2Speed or 0)
        end
    end
    updateBlob(p2, dt, net.x + net.w, WORLD.width)

    -- BALL PHYSIK
    if gameState.state == "play" then
        ball.vy = ball.vy + config.gravity * dt
        ball.x = ball.x + ball.vx * dt
        ball.y = ball.y + ball.vy * dt
        ball.rotation = ball.rotation + (ball.vx / ball.radius) * dt

        local currentSide = (ball.x < WORLD.width / 2) and 1 or 2
        if gameState.ballSide ~= currentSide then
            gameState.ballSide = currentSide
            gameState.touchCount = 0
            gameState.lastTouchPlayer = 0
            p1.touchCooldown = 0
            p2.touchCooldown = 0
        end

        if ball.x - ball.radius < 0 then
            ball.x = ball.radius
            ball.vx = math.abs(ball.vx) * config.wallBounce
            playSound(sounds.hit_wall)
        elseif ball.x + ball.radius > WORLD.width then
            ball.x = WORLD.width - ball.radius
            ball.vx = -math.abs(ball.vx) * config.wallBounce
            playSound(sounds.hit_wall)
        end
    end

    checkNetCollision()
    checkBlobBallCollision(p1, 1)
    checkBlobBallCollision(p2, 2)

    local maxBallVel = config.maxBallSpeed
    local curBallVel = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
    if curBallVel > maxBallVel then
        ball.vx = (ball.vx / curBallVel) * maxBallVel
        ball.vy = (ball.vy / curBallVel) * maxBallVel
    end

    local targetBallGround = config.ballGroundY or 520
    if gameState.state == "play" and gameState.faultTimer <= 0 and (ball.y + ball.radius >= targetBallGround) then
        playSound(sounds.hit_sand)
        spawnDust(ball.x, targetBallGround, 25, 80, 200) 
        -- Shake hier entfernt! Nur noch Staub und Sound bei einfachem Bodenkontakt.
        if ball.x < WORLD.width / 2 then awardPointTo(2) else awardPointTo(1) end
    end
end

function updateBlob(p, dt, wallLeft, wallRight)
    local appliedGravity = config.blobGravity
    if p.vy > 0 then appliedGravity = appliedGravity * 1.5 end

    p.vy = p.vy + appliedGravity * dt
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt

    if p.y >= WORLD.groundY then 
        if not p.isGrounded then spawnDust(p.x, WORLD.groundY, 10, 50, 80) end 
        p.y = WORLD.groundY
        p.vy = 0
        p.isGrounded = true 
    end

    local minX = wallLeft + config.blobRadius
    local maxX = wallRight - config.blobRadius
    if p.x < minX then p.x = minX; p.vx = 0 end
    if p.x > maxX then p.x = maxX; p.vx = 0 end
end

-- ============================================================================
-- KOLLISION
-- ============================================================================
function checkBlobBallCollision(p, playerNum)
    local tilt = p.tiltAngle or 0
    local headOffsetX = math.sin(tilt) * (config.blobRadius * 0.4)
    local headOffsetY = -math.cos(tilt) * (config.blobRadius * 0.4) + (config.blobRadius * 0.4)

    local dx = ball.x - (p.x + headOffsetX)
    local dy = ball.y - (p.y + headOffsetY)
    local dist = math.sqrt(dx * dx + dy * dy)
    local minDist = ball.radius + config.blobRadius

    if dist < minDist then
        if dist == 0 then dist = 0.0001 end
        local nx = dx / dist
        local ny = dy / dist
        local relVx = ball.vx - p.vx
        local relVy = ball.vy - p.vy
        local relNormalVel = relVx * nx + relVy * ny

        if relNormalVel < 0 then
            local ballNormalVel = ball.vx * nx + ball.vy * ny
            
            if gameState.state == "serve" then
                gameState.state = "play"
                ballNormalVel = -config.ballBaseSpeed * config.serveBoost
            end

            ball.x = (p.x + headOffsetX) + nx * minDist
            ball.y = (p.y + headOffsetY) + ny * minDist

            if p.touchCooldown <= 0 then
                p.touchCooldown = 0.20 
                if gameState.lastTouchPlayer == playerNum then
                    gameState.touchCount = gameState.touchCount + 1
                else
                    gameState.lastTouchPlayer = playerNum
                    gameState.touchCount = 1
                end
                playSound(sounds.hit_blob)

                -- DASH SAVE SHAKE: Wenn der Spieler in den letzten 0.5s gedasht hat, wackelt das Bild!
                if p.dashGrace > 0 then
                    addShake(5, 0.25)
                    p.dashGrace = 0 -- Damit es nur einmal pro Dash wackelt
                end
            end

            if gameState.touchCount > 3 and gameState.faultTimer <= 0 then
                gameState.faultTimer = 0.75
                gameState.faultPlayer = playerNum
                ball.vx = nx * 50
                ball.vy = math.abs(ball.vy) * 0.2
                addShake(4, 0.2) -- Kleiner Shake beim 4-Touch-Fehler
            elseif gameState.touchCount <= 3 then
                local blobNormalVel = p.vx * nx + p.vy * ny
                local baseImpulse = 0
                if ballNormalVel < 0 then baseImpulse = -ballNormalVel * (1 + config.passiveBounce) end
                local addedImpulse = 0
                if blobNormalVel > 0 then addedImpulse = blobNormalVel * config.activeTransfer * (1 + config.passiveBounce) end
                
                local totalImpulse = math.max(0, baseImpulse + addedImpulse)
                ball.vx = ball.vx + totalImpulse * nx
                ball.vy = ball.vy + totalImpulse * ny

                local isSpiking = false
                if playerNum == 1 and love.keyboard.isDown("s") then isSpiking = true end
                if playerNum == 2 then
                    if config.botActive then isSpiking = p.botSmash else isSpiking = love.keyboard.isDown("j") end
                end

                if config.activeSpike and isSpiking and not p.isGrounded then
                    ball.vx = ball.vx * 1.3
                    ball.vy = math.abs(ball.vy) * 1.4
                    addShake(3, 0.15) -- Minimaler Shake bei hartem Smash
                end

                if config.speedScaling then
                    ball.vx = ball.vx * 1.05
                    ball.vy = ball.vy * 1.05
                end

                local currentOutwardVel = ball.vx * nx + ball.vy * ny
                local minOutward = config.ballBaseSpeed * 0.4
                if currentOutwardVel < minOutward then
                    ball.vx = ball.vx + nx * (minOutward - currentOutwardVel)
                    ball.vy = ball.vy + ny * (minOutward - currentOutwardVel)
                end
            end
            gameState.rallies = gameState.rallies + 1
        else
            ball.x = (p.x + headOffsetX) + nx * minDist
            ball.y = (p.y + headOffsetY) + ny * minDist
        end
    end
end

function checkNetCollision()
    local capRadius = net.w / 2
    local capX = net.x + capRadius
    local capY = net.y + capRadius

    if ball.y < capY then
        local dx = ball.x - capX
        local dy = ball.y - capY
        local dist = math.sqrt(dx * dx + dy * dy)
        local minDist = ball.radius + capRadius

        if dist < minDist then
            if dist == 0 then dist = 0.0001 end
            local nx = dx / dist
            local ny = dy / dist
            local normalVel = ball.vx * nx + ball.vy * ny

            if normalVel < 0 then
                ball.x = capX + nx * minDist
                ball.y = capY + ny * minDist
                local impulse = -normalVel * (1 + 0.8) 
                ball.vx = ball.vx + impulse * nx
                ball.vy = ball.vy + impulse * ny
                playSound(sounds.hit_net)
            else
                ball.x = capX + nx * minDist
                ball.y = capY + ny * minDist
            end
        end
    else
        if ball.x + ball.radius > net.x and ball.x - ball.radius < net.x + net.w then
            if ball.y + ball.radius > capY then
                local hitNetSide = false
                if ball.x < capX then
                    if ball.vx > 0 then hitNetSide = true end
                    ball.x = net.x - ball.radius
                    ball.vx = -math.abs(ball.vx) * 0.8
                else
                    if ball.vx < 0 then hitNetSide = true end
                    ball.x = net.x + net.w + ball.radius
                    ball.vx = math.abs(ball.vx) * 0.8
                end
                if hitNetSide then playSound(sounds.hit_net) end
            end
        end
    end
end

-- ============================================================================
-- INPUT EVENTS (MENÜ + SPIEL)
-- ============================================================================
local function handleDoubleTap(key, playerNum, p, dashDirLeft, dashDirRight, dashUp)
    local now = love.timer.getTime()
    if p.cooldownTimer <= 0 then
        if lastTaps[playerNum .. key] and (now - lastTaps[playerNum .. key]) < config.dashWindow then
            if key == dashUp then
                p.vy = config.jumpForce * config.dashUp
                p.isGrounded = false
                p.cooldownTimer = config.dashCooldown
                p.dashGrace = 0.5 -- Startet das Dash-Save Fenster
                spawnDust(p.x, p.y, 10, 40, 100)
                playSound(sounds.dash)
            elseif key == dashDirLeft then
                p.dashTimer = 0.2
                p.dashSpeed = -config.moveSpeed * config.dashSide
                p.cooldownTimer = config.dashCooldown
                p.dashGrace = 0.5 
                spawnDust(p.x, p.y, 15, 60, 150)
                playSound(sounds.dash)
            elseif key == dashDirRight then
                p.dashTimer = 0.2
                p.dashSpeed = config.moveSpeed * config.dashSide
                p.cooldownTimer = config.dashCooldown
                p.dashGrace = 0.5 
                spawnDust(p.x, p.y, 15, 60, 150)
                playSound(sounds.dash)
            end
            lastTaps[playerNum .. key] = 0 
            return true
        else
            lastTaps[playerNum .. key] = now
        end
    end
    return false
end

function love.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen())
    end

    if gameState.state == "menu" then
        local currentObj = menu[menu.current]
        
        if key == "escape" then
            if menu.current == "main" then
                if gameState.gameInProgress then
                    gameState.state = gameState.previousState
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
        gameState.previousState = gameState.state
        gameState.state = "menu"
        menu.current = "main"
        tweakMenu.active = false
        saveConfig() 
        return
    end

    if tweakMenu.active and gameState.state ~= "gameover" then
        if key == "tab" or key == "f1" then tweakMenu.active = false; saveConfig(); return end
        if key == "up" then tweakMenu.selectedIndex = math.max(1, tweakMenu.selectedIndex - 1) end
        if key == "down" then tweakMenu.selectedIndex = math.min(#tweakMenu.options, tweakMenu.selectedIndex + 1) end

        local opt = tweakMenu.options[tweakMenu.selectedIndex]
        if key == "left" or key == "right" then
            if opt.type == "bool" then
                config[opt.key] = not config[opt.key]
            else
                local delta = (key == "right" and 1 or -1) * opt.step
                if opt.key == "jumpForce" then delta = -delta end
                config[opt.key] = math.max(opt.min, math.min(opt.max, config[opt.key] + delta))
            end
        end
        return
    end

    if key == "tab" or key == "f1" then tweakMenu.active = true end
    if key == "r" and gameState.state == "gameover" then resetBall(1) end

    if key == "w" then
        if not handleDoubleTap(key, 1, p1, "a", "d", "w") and p1.isGrounded then 
            p1.vy = config.jumpForce; p1.isGrounded = false; playSound(sounds.jump)
            spawnDust(p1.x, p1.y, 8, 40, 100)
        end
    end
    if key == "a" or key == "d" then handleDoubleTap(key, 1, p1, "a", "d", "w") end

    if not config.botActive then
        if key == "u" then
            if not handleDoubleTap(key, 2, p2, "h", "k", "u") and p2.isGrounded then 
                p2.vy = config.jumpForce; p2.isGrounded = false; playSound(sounds.jump)
                spawnDust(p2.x, p2.y, 8, 40, 100)
            end
        end
        if key == "h" or key == "k" then handleDoubleTap(key, 2, p2, "h", "k", "u") end
    end
end

-- ============================================================================
-- RENDERING
-- ============================================================================
function love.draw()
    love.graphics.push()
    love.graphics.scale(scale, scale)

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

    if gameState.state == "menu" then
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", 0, 0, WORLD.width, WORLD.height)
        
        local currentObj = menu[menu.current]
        love.graphics.setFont(love.graphics.newFont(48))
        love.graphics.setColor(1, 0.85, 0.2)
        love.graphics.printf(currentObj.title, 0, 80, WORLD.width, "center")

        if gameState.gameInProgress and menu.current == "main" then
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
        
        love.graphics.pop()
        return
    end

    drawShadow(p1.x, p1.y, config.blobRadius, WORLD.groundY)
    drawShadow(p2.x, p2.y, config.blobRadius, WORLD.groundY)
    drawShadow(ball.x, ball.y, config.ballRadius * 1.5, config.ballGroundY or 520)

    drawParticles()

    love.graphics.setColor(0.55, 0.35, 0.15)
    love.graphics.rectangle("fill", net.x, net.y, net.w, net.h, 3, 3)
    love.graphics.setColor(0.40, 0.20, 0.05)
    love.graphics.rectangle("line", net.x, net.y, net.w, net.h, 3, 3)

    drawBlob(p1, true)
    drawBlob(p2, false)

    love.graphics.setColor(ball.color)
    if ball.y + ball.radius >= 0 then
        if assets.ball then
            local bw, bh = assets.ball:getDimensions()
            local bScale = (ball.radius * 2) / bw
            love.graphics.draw(assets.ball, ball.x, ball.y, ball.rotation, bScale, bScale, bw/2, bh/2)
        else
            love.graphics.push()
            love.graphics.translate(ball.x, ball.y)
            love.graphics.rotate(ball.rotation)
            love.graphics.circle("fill", 0, 0, ball.radius)
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.circle("fill", -ball.radius*0.3, -ball.radius*0.3, ball.radius * 0.4)
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.line(0, 0, ball.radius, 0)
            love.graphics.pop()
        end
    else
        local indX = math.max(15, math.min(WORLD.width - 15, ball.x))
        love.graphics.polygon("fill", indX - 10, 4, indX + 10, 4, indX, 18)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("fill", indX, 8, 3)
    end

    local p1DisplayName = namePool[p1NameIdx]
    local p2DisplayName = config.botActive and namePool[botNameIdx] or namePool[p2NameIdx]

    love.graphics.setFont(love.graphics.newFont(32))
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.print(p1DisplayName .. ": " .. gameState.scoreP1, WORLD.width * 0.15 + 2, 32)
    love.graphics.print(p2DisplayName .. ": " .. gameState.scoreP2, WORLD.width * 0.65 + 2, 32)
    
    if gameState.servingPlayer == 1 then
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.print(p1DisplayName .. ": " .. gameState.scoreP1, WORLD.width * 0.15, 30)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(p2DisplayName .. ": " .. gameState.scoreP2, WORLD.width * 0.65, 30)
    else
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(p1DisplayName .. ": " .. gameState.scoreP1, WORLD.width * 0.15, 30)
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.print(p2DisplayName .. ": " .. gameState.scoreP2, WORLD.width * 0.65, 30)
    end

    love.graphics.setFont(love.graphics.newFont(16))
    local function drawCooldown(p, x)
        if p.cooldownTimer > 0 then
            love.graphics.setColor(0.9, 0.2, 0.2, 0.8)
            love.graphics.rectangle("fill", x - 30, WORLD.groundY + 15, 60 * (p.cooldownTimer / config.dashCooldown), 4)
        end
    end
    drawCooldown(p1, WORLD.width * 0.25)
    drawCooldown(p2, WORLD.width * 0.75)

    if gameState.state == "serve" then
        love.graphics.setColor(0, 0, 0, 0.6)
        local sideX = (gameState.servingPlayer == 1) and (WORLD.width * 0.25) or (WORLD.width * 0.75)
        love.graphics.print("WAITING FOR SERVE", sideX - 78, 77)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("WAITING FOR SERVE", sideX - 80, 75)
    elseif gameState.faultTimer > 0 then
        local sideX = (gameState.faultPlayer == 1) and (WORLD.width * 0.25) or (WORLD.width * 0.75)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.print("FAULT!", sideX - 28, 77)
        love.graphics.setColor(1, 0.2, 0.2, 1)
        love.graphics.print("FAULT!", sideX - 30, 75)
    elseif gameState.touchCount > 0 then
        local sideX = (gameState.lastTouchPlayer == 1) and (WORLD.width * 0.25) or (WORLD.width * 0.75)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.print("Touches: " .. gameState.touchCount .. " / 3", sideX - 43, 77)
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.print("Touches: " .. gameState.touchCount .. " / 3", sideX - 45, 75)
    end

    if gameState.state == "gameover" then
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", 0, 0, WORLD.width, WORLD.height)
        
        love.graphics.setColor(1, 0.85, 0.2)
        love.graphics.setFont(love.graphics.newFont(48))
        local winnerName = (gameState.scoreP1 >= 15) and p1DisplayName or p2DisplayName
        love.graphics.printf(winnerName .. " WINS!", 0, WORLD.height/2 - 50, WORLD.width, "center")
        
        love.graphics.setFont(love.graphics.newFont(24))
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Press 'R' to play again or 'ESC' for Menu", 0, WORLD.height/2 + 20, WORLD.width, "center")
    end

    if tweakMenu.active and gameState.state ~= "gameover" then
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
            local valStr = tostring(config[opt.key])
            if type(config[opt.key]) == "number" then valStr = string.format(opt.step < 1 and "%.2f" or "%.0f", config[opt.key]) end
            love.graphics.print(opt.name, 25, yOffset)
            love.graphics.print("< " .. valStr .. " >", 290, yOffset)
            yOffset = yOffset + 22
        end
        
        if endIndex < #tweakMenu.options then
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.print("v Weitere Optionen v", 150, yOffset)
        end
    end

    love.graphics.pop()
end

function drawBlob(p, isP1)
    love.graphics.push()
    love.graphics.translate(p.x, p.y)
    love.graphics.rotate(p.tiltAngle)
    love.graphics.translate(-p.x, -p.y)
    love.graphics.setColor(1, 1, 1, 1)

    if assets.blob then
        love.graphics.setColor(p.color)
        local bw, bh = assets.blob:getDimensions()
        local bScaleX = (config.blobRadius * 2) / bw
        local bScaleY = bScaleX 
        if not isP1 then bScaleX = -bScaleX end
        love.graphics.draw(assets.blob, p.x, p.y, 0, bScaleX, bScaleY, bw/2, bh)
    else
        local r = config.blobRadius
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
        local dx = ball.x - p.x
        local dy = ball.y - p.y
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