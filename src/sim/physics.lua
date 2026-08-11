-- ============================================================================
-- src/sim/physics.lua -- Integration und Kollisionen (M0-08)
--
-- Wortgleich aus dem Prototyp uebernommen. `02_CODE_AUDIT` §4 gilt hier
-- vollstaendig: Kollisionsaufloesung Blob-Ball mit activeTransfer und
-- passiveBounce, Wandabprall mit 0.70, die Netzkappe, der minOutward-Ausgleich
-- und der Geschwindigkeitsdeckel. Kein Wert wurde angefasst.
--
-- Kein love, kein Ton, kein Zufall. Kosmetik geht als Ereignis nach oben.
-- ============================================================================

local World = require("src.sim.world")
local Rules = require("src.sim.rules")

local Physics = {}

local function emit(events, event)
    events[#events + 1] = event
end

-- ---------------------------------------------------------------------------
-- Blobs
-- ---------------------------------------------------------------------------

function Physics.updateBlob(blob, index, dt, wallLeft, wallRight, ruleset, groundY, events)
    local appliedGravity = ruleset.blobGravity
    if blob.vy > 0 then appliedGravity = appliedGravity * 1.5 end

    blob.vy = blob.vy + appliedGravity * dt
    blob.x = blob.x + blob.vx * dt
    blob.y = blob.y + blob.vy * dt

    if blob.y >= groundY then
        if not blob.isGrounded then
            emit(events, { type = "land", player = index, x = blob.x, y = groundY })
        end
        blob.y = groundY
        blob.vy = 0
        blob.isGrounded = true
    end

    local minX = wallLeft + ruleset.blobRadius
    local maxX = wallRight - ruleset.blobRadius
    if blob.x < minX then blob.x = minX; blob.vx = 0 end
    if blob.x > maxX then blob.x = maxX; blob.vx = 0 end
end

-- ---------------------------------------------------------------------------
-- Ball
-- ---------------------------------------------------------------------------

function Physics.integrateBall(state, dt, ruleset, events)
    local ball = state.ball

    ball.vy = ball.vy + ruleset.gravity * dt
    ball.x = ball.x + ball.vx * dt
    ball.y = ball.y + ball.vy * dt
    ball.rotation = ball.rotation + (ball.vx / ball.radius) * dt

    Rules.updateBallSide(state)

    if ball.x - ball.radius < 0 then
        ball.x = ball.radius
        ball.vx = math.abs(ball.vx) * ruleset.wallBounce
        emit(events, { type = "wall_hit", x = ball.x, y = ball.y })
    elseif ball.x + ball.radius > World.WIDTH then
        ball.x = World.WIDTH - ball.radius
        ball.vx = -math.abs(ball.vx) * ruleset.wallBounce
        emit(events, { type = "wall_hit", x = ball.x, y = ball.y })
    end
end

function Physics.capSpeed(state, ruleset)
    local ball = state.ball
    local maxBallVel = ruleset.maxBallSpeed
    local curBallVel = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
    if curBallVel > maxBallVel then
        ball.vx = (ball.vx / curBallVel) * maxBallVel
        ball.vy = (ball.vy / curBallVel) * maxBallVel
    end
end

-- ---------------------------------------------------------------------------
-- Netz: Rechteck mit Halbkreis obendrauf
-- ---------------------------------------------------------------------------

function Physics.netCollision(state, events)
    local ball, net = state.ball, state.net
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
                emit(events, { type = "net_hit", x = ball.x, y = ball.y })
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
                if hitNetSide then
                    emit(events, { type = "net_hit", x = ball.x, y = ball.y })
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Blob gegen Ball -- das Herzstueck des Spielgefuehls (02_CODE_AUDIT §4)
-- ---------------------------------------------------------------------------

function Physics.blobBall(state, index, smashHeld, ruleset, events)
    local ball = state.ball
    local blob = state.blobs[index]

    local tilt = blob.tiltAngle or 0
    local headOffsetX = math.sin(tilt) * (ruleset.blobRadius * 0.4)
    local headOffsetY = -math.cos(tilt) * (ruleset.blobRadius * 0.4) + (ruleset.blobRadius * 0.4)

    local dx = ball.x - (blob.x + headOffsetX)
    local dy = ball.y - (blob.y + headOffsetY)
    local dist = math.sqrt(dx * dx + dy * dy)
    local minDist = ball.radius + ruleset.blobRadius

    if dist >= minDist then return end
    if dist == 0 then dist = 0.0001 end

    local nx = dx / dist
    local ny = dy / dist
    local relVx = ball.vx - blob.vx
    local relVy = ball.vy - blob.vy
    local relNormalVel = relVx * nx + relVy * ny

    if relNormalVel >= 0 then
        -- Der Ball entfernt sich bereits: nur aus dem Blob schieben.
        ball.x = (blob.x + headOffsetX) + nx * minDist
        ball.y = (blob.y + headOffsetY) + ny * minDist
        return
    end

    local ballNormalVel = ball.vx * nx + ball.vy * ny

    if state.match.phase == "serve" then
        state.match.phase = "play"
        ballNormalVel = -ruleset.ballBaseSpeed * ruleset.serveBoost
    end

    ball.x = (blob.x + headOffsetX) + nx * minDist
    ball.y = (blob.y + headOffsetY) + ny * minDist

    Rules.registerTouch(state, index, blob, events)

    if state.rally.touchCount > 3 and state.rally.faultTimer <= 0 then
        Rules.startFault(state, index, events)
        ball.vx = nx * 50
        ball.vy = math.abs(ball.vy) * 0.2
    elseif state.rally.touchCount <= 3 then
        local blobNormalVel = blob.vx * nx + blob.vy * ny
        local baseImpulse = 0
        if ballNormalVel < 0 then baseImpulse = -ballNormalVel * (1 + ruleset.passiveBounce) end
        local addedImpulse = 0
        if blobNormalVel > 0 then
            addedImpulse = blobNormalVel * ruleset.activeTransfer * (1 + ruleset.passiveBounce)
        end

        local totalImpulse = math.max(0, baseImpulse + addedImpulse)
        ball.vx = ball.vx + totalImpulse * nx
        ball.vy = ball.vy + totalImpulse * ny

        if ruleset.activeSpike and smashHeld and not blob.isGrounded then
            ball.vx = ball.vx * 1.3
            ball.vy = math.abs(ball.vy) * 1.4
            emit(events, { type = "smash", player = index })
        end

        if ruleset.speedScaling then
            ball.vx = ball.vx * 1.05
            ball.vy = ball.vy * 1.05
        end

        -- Mindestgeschwindigkeit nach aussen, damit der Ball nicht im Blob
        -- kleben bleibt. Hebt bei einem Smash von unten den Schlag komplett
        -- auf -- gemessen und in CC-01 dokumentiert.
        local currentOutwardVel = ball.vx * nx + ball.vy * ny
        local minOutward = ruleset.ballBaseSpeed * 0.4
        if currentOutwardVel < minOutward then
            ball.vx = ball.vx + nx * (minOutward - currentOutwardVel)
            ball.vy = ball.vy + ny * (minOutward - currentOutwardVel)
        end
    end

    state.rally.rallies = state.rally.rallies + 1
end

return Physics
