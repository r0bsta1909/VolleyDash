-- ============================================================================
-- BOT KI MODUL (bot.lua)
-- ============================================================================

local Bot = {
    targetX = 600,
    reactionTimer = 0,
    
    -- Schwierigkeitsgrade: Reaktionsverzögerung (Sek), Jitter (Px), Dash/Smash Toggles
    difficulties = {
        easy   = { reactionDelay = 0.25, jitter = 35, useDash = false, useSmash = false },
        medium = { reactionDelay = 0.12, jitter = 15, useDash = false, useSmash = true  },
        hard   = { reactionDelay = 0.04, jitter = 4,  useDash = true,  useSmash = true  },
        god    = { reactionDelay = 0.00, jitter = 0,  useDash = true,  useSmash = true  }
    }
}

-- VORAUSBERECHNUNG DER BALL-LANDENPOSITION (Echtzeit-Physik-Simulation)
function Bot.predictLandingX(ball, config, world, diffSettings)
    local simX = ball.x
    local simY = ball.y
    local simVx = ball.vx
    local simVy = ball.vy
    local simDt = 0.016 -- 60 FPS Schritt
    local headY = world.groundY - (config.blobRadius * 1.2)

    -- Simuliere Flugbahn bis zur Kopfhöhe des Bots
    for t = 0, 2.5, simDt do
        simVy = simVy + config.gravity * simDt
        simX = simX + simVx * simDt
        simY = simY + simVy * simDt

        -- Wandabpraller in Simulation spiegeln
        if simX - config.ballRadius < 0 then
            simX = config.ballRadius
            simVx = math.abs(simVx) * config.wallBounce
        elseif simX + config.ballRadius > world.width then
            simX = world.width - config.ballRadius
            simVx = -math.abs(simVx) * config.wallBounce
        end

        -- Schnittpunkt mit Kopfhöhe erreicht (im Abwärtsflug)
        if simY >= headY and simVy > 0 then
            local jitter = (math.random() * 2 - 1) * diffSettings.jitter
            local finalX = simX + jitter
            -- Abfangpunkt auf Bot-Spielfeldhälfte eingrenzen
            return math.max(world.width / 2 + config.blobRadius, math.min(world.width - config.blobRadius, finalX))
        end
    end

    return world.width * 0.75 -- Standard-Abwehrposition
end

-- VIRTUELLE EINGABEN GENERIEREN
function Bot.update(bot, ball, dt, config, world, gameState, levelName)
    local diff = Bot.difficulties[levelName] or Bot.difficulties.medium
    local inputs = { left = false, right = false, jump = false, smash = false, dashDir = nil }

    -- 1. Reaktionsverzögerung aktualisieren
    Bot.reactionTimer = Bot.reactionTimer + dt
    if Bot.reactionTimer >= diff.reactionDelay then
        Bot.reactionTimer = 0

        -- Ball nur verfolgen, wenn er auf die eigene Seite fliegt oder nahe am Netz ist
        if ball.x > world.width * 0.35 or ball.vx > 0 then
            Bot.targetX = Bot.predictLandingX(ball, config, world, diff)
        else
            Bot.targetX = world.width * 0.75 -- Neutraler Rückzug
        end
    end

    -- 2. Aufschlag-Logik
    if gameState.state == "serve" and gameState.servingPlayer == 2 then
        inputs.left = true
        if math.abs(bot.x - ball.x) < 25 then
            inputs.jump = true
        end
        return inputs
    end

    -- 3. Horizontale Lauf-Steuerung
    local tolerance = 8
    if bot.x < Bot.targetX - tolerance then
        inputs.right = true
    elseif bot.x > Bot.targetX + tolerance then
        inputs.left = true
    end

    -- 4. Notfall-Dash (Hechtsprung)
    if diff.useDash and bot.cooldownTimer <= 0 then
        local distToTarget = math.abs(bot.x - Bot.targetX)
        local timeToImpact = (world.groundY - ball.y) / math.max(1, ball.vy)
        
        -- Wenn Laufzeit zu lang ist, schieße per Dash nach vorne
        if distToTarget > 120 and timeToImpact < 0.25 and ball.x > world.width / 2 then
            inputs.dashDir = (bot.x < Bot.targetX) and "k" or "h"
        end
    end

    -- 5. Absprung & Smash-Timing
    local distToBallX = math.abs(bot.x - ball.x)
    local ballInJumpZone = ball.y > (world.groundY - config.blobRadius * 3.5) and ball.y < world.groundY

    if distToBallX < (config.blobRadius + config.ballRadius) and ballInJumpZone then
        if bot.isGrounded then
            inputs.jump = true
        end

        -- Smash ausführen (wenn nahe am Netz und in der Luft)
        if diff.useSmash and config.activeSpike and not bot.isGrounded then
            if ball.x < world.width * 0.65 and ball.y < (world.groundY - config.netHeight) then
                inputs.smash = true
            end
        end
    end

    return inputs
end

return Bot