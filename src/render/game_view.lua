-- ============================================================================
-- src/render/game_view.lua -- Feld, Blobs, Ball, Schatten (M0-12)
--
-- Zeichnet den Zustand aus `src/sim/state.lua`, ohne ihn anzufassen. Hier
-- sitzt auch die Render-Interpolation (M0-05): die Simulation laeuft mit
-- festen 1/60 s, gezeichnet wird zwischen dem Zustand vor und nach dem
-- letzten Tick.
-- ============================================================================

local World  = require("src.sim.world")
local Assets = require("src.app.assets")
local Fx     = require("src.render.fx")

local GameView = {}

-- Farben sind Anzeige, nicht Simulation, und stehen deshalb hier und nicht
-- in state.lua.
GameView.COLORS = {
    { 0.15, 0.55, 0.95 },
    { 0.95, 0.25, 0.25 },
}

local prev = {
    { x = 0, y = 0, tilt = 0 },
    { x = 0, y = 0, tilt = 0 },
    ball = { x = 0, y = 0, rot = 0 },
}
local view = { {}, {}, ball = {} }
local alpha = 0

-- Vor jedem Tick aufrufen. Zugleich der Weg, eine Sprungstelle zu entschaerfen:
-- nach einem Punkt steht der Ball an einer neuen Stelle, und ohne diesen
-- Aufruf wuerde er einen Frame lang quer durchs Bild gleiten.
function GameView.capture(state)
    for i = 1, 2 do
        local blob = state.blobs[i]
        prev[i].x, prev[i].y, prev[i].tilt = blob.x, blob.y, blob.tiltAngle
    end
    prev.ball.x, prev.ball.y, prev.ball.rot = state.ball.x, state.ball.y, state.ball.rotation
end

function GameView.setAlpha(value)
    alpha = value
end

local function lerp(a, b, t) return a + (b - a) * t end

local function blobView(index, blob)
    local dst = view[index]
    for k, v in pairs(blob) do dst[k] = v end
    dst.x = lerp(prev[index].x, blob.x, alpha)
    dst.y = lerp(prev[index].y, blob.y, alpha)
    dst.tiltAngle = lerp(prev[index].tilt, blob.tiltAngle, alpha)
    dst.color = GameView.COLORS[index]
    return dst
end

local function ballView(ball)
    local dst = view.ball
    for k, v in pairs(ball) do dst[k] = v end
    dst.x = lerp(prev.ball.x, ball.x, alpha)
    dst.y = lerp(prev.ball.y, ball.y, alpha)
    dst.rotation = lerp(prev.ball.rot, ball.rotation, alpha)
    return dst
end

-- ---------------------------------------------------------------------------
-- Einzelteile
-- ---------------------------------------------------------------------------

function GameView.drawField(groundY)
    love.graphics.setColor(1, 1, 1)
    local bg = Assets.images.bg
    if bg then
        local bgW, bgH = bg:getDimensions()
        love.graphics.draw(bg, 0, 0, 0, World.WIDTH / bgW, World.HEIGHT / bgH)
    else
        love.graphics.setColor(0.08, 0.12, 0.22)
        love.graphics.rectangle("fill", 0, 0, World.WIDTH, World.HEIGHT)
        love.graphics.setColor(0.85, 0.72, 0.45)
        love.graphics.rectangle("fill", 0, groundY, World.WIDTH, World.HEIGHT - groundY)
    end
end

function GameView.drawBlob(blob, isP1, ballRef, ruleset)
    love.graphics.push()
    love.graphics.translate(blob.x, blob.y)
    love.graphics.rotate(blob.tiltAngle)
    love.graphics.translate(-blob.x, -blob.y)
    love.graphics.setColor(1, 1, 1, 1)

    local sprite = Assets.images.blob
    if sprite then
        love.graphics.setColor(blob.color)
        local bw, bh = sprite:getDimensions()
        local scaleX = (ruleset.blobRadius * 2) / bw
        local scaleY = scaleX
        if not isP1 then scaleX = -scaleX end
        love.graphics.draw(sprite, blob.x, blob.y, 0, scaleX, scaleY, bw / 2, bh)
    else
        local r = ruleset.blobRadius
        local groundY = ruleset.blobGroundY or 500
        love.graphics.push()
        love.graphics.rotate(-blob.tiltAngle)
        love.graphics.setColor(0, 0, 0, 0.2)
        love.graphics.ellipse("fill", blob.x, groundY + 2, r, 6)
        love.graphics.pop()
        love.graphics.setColor(blob.color)
        love.graphics.arc("fill", blob.x, blob.y - 5, r, math.pi, 2 * math.pi)
        love.graphics.rectangle("fill", blob.x - r, blob.y - 5, r * 2, 5)
        love.graphics.setColor(1, 1, 1, 0.25)
        love.graphics.arc("fill", blob.x, blob.y - 12, r * 0.7, math.pi, 2 * math.pi)

        -- Die Augen folgen dem gezeichneten Ball, nicht dem simulierten,
        -- sonst zappeln die Pupillen gegenueber dem Bild (M0-05).
        local dx = ballRef.x - blob.x
        local dy = ballRef.y - blob.y
        local angle = math.atan2(dy, dx)
        local eyeOffsetX = isP1 and 14 or -14
        local eyeOffsetY = -r * 0.45
        love.graphics.setColor(1, 1, 1)
        love.graphics.circle("fill", blob.x + eyeOffsetX, blob.y + eyeOffsetY, 9)
        local pupilX = blob.x + eyeOffsetX + math.cos(angle) * 3.5
        local pupilY = blob.y + eyeOffsetY + math.sin(angle) * 3.5
        love.graphics.setColor(0.1, 0.1, 0.18)
        love.graphics.circle("fill", pupilX, pupilY, 4.5)
        love.graphics.setColor(1, 1, 1)
        love.graphics.circle("fill", pupilX - 1.5, pupilY - 1.5, 1.5)
    end
    love.graphics.pop()
end

function GameView.drawBall(ball, ruleset)
    local sprite = Assets.images.ball
    love.graphics.setColor(sprite and { 1, 1, 1 } or { 0.98, 0.85, 0.12 })

    if ball.y + ball.radius < 0 then
        -- Ball ueber dem Bildrand: Zeiger am oberen Rand
        local indX = math.max(15, math.min(World.WIDTH - 15, ball.x))
        love.graphics.polygon("fill", indX - 10, 4, indX + 10, 4, indX, 18)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("fill", indX, 8, 3)
        return
    end

    if sprite then
        local bw, bh = sprite:getDimensions()
        local scale = (ball.radius * 2) / bw
        love.graphics.draw(sprite, ball.x, ball.y, ball.rotation, scale, scale, bw / 2, bh / 2)
    else
        love.graphics.push()
        love.graphics.translate(ball.x, ball.y)
        love.graphics.rotate(ball.rotation)
        love.graphics.circle("fill", 0, 0, ball.radius)
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.circle("fill", -ball.radius * 0.3, -ball.radius * 0.3, ball.radius * 0.4)
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.line(0, 0, ball.radius, 0)
        love.graphics.pop()
    end
end

function GameView.drawNet(net)
    love.graphics.setColor(0.55, 0.35, 0.15)
    love.graphics.rectangle("fill", net.x, net.y, net.w, net.h, 3, 3)
    love.graphics.setColor(0.40, 0.20, 0.05)
    love.graphics.rectangle("line", net.x, net.y, net.w, net.h, 3, 3)
end

-- ---------------------------------------------------------------------------
-- Ganzes Feld. Gibt die interpolierten Ansichten zurueck, damit das HUD
-- dieselben Werte benutzt (Cooldown-Balken).
-- ---------------------------------------------------------------------------
function GameView.draw(state, ruleset)
    local groundY = ruleset.blobGroundY or 500
    local vp1  = blobView(1, state.blobs[1])
    local vp2  = blobView(2, state.blobs[2])
    local vball = ballView(state.ball)

    Fx.shadow(vp1.x, vp1.y, ruleset.blobRadius, groundY)
    Fx.shadow(vp2.x, vp2.y, ruleset.blobRadius, groundY)
    Fx.shadow(vball.x, vball.y, ruleset.ballRadius * 1.5, ruleset.ballGroundY or 520)

    Fx.draw()
    GameView.drawNet(state.net)
    GameView.drawBlob(vp1, true, vball, ruleset)
    GameView.drawBlob(vp2, false, vball, ruleset)
    GameView.drawBall(vball, ruleset)

    return vp1, vp2, vball
end

return GameView
