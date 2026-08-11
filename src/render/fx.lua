-- ============================================================================
-- src/render/fx.lua -- Partikel, Kamera-Shake, Schatten (M0-12)
--
-- Reine Kosmetik. Nichts hier fliesst in die Simulation zurueck; die
-- Ereignisse aus `src/sim/step.lua` gehen nur in diese Richtung.
--
-- Deshalb darf hier auch `math.random` stehen: Staub, der jedes Mal gleich
-- aussieht, waere schlechter, und die Anti-Zufalls-Doktrin gilt fuer die
-- Simulation, nicht fuer die Optik (CLAUDE.md §3).
-- ============================================================================

local Fx = {}

local particles = {}
local camera = { shakeTimer = 0, shakeMag = 0 }

function Fx.reset()
    for i = #particles, 1, -1 do particles[i] = nil end
    camera.shakeTimer, camera.shakeMag = 0, 0
end

function Fx.shake(amount, duration)
    camera.shakeMag = amount
    camera.shakeTimer = duration
end

function Fx.dust(x, y, count, spread, upForce)
    for _ = 1, count do
        particles[#particles + 1] = {
            x = x + (math.random() * spread - spread / 2),
            y = y,
            vx = (math.random() * 100 - 50),
            vy = -(math.random() * upForce + 50),
            life = 0.5 + math.random() * 0.5,
            maxLife = 1.0,
            size = math.random(3, 7),
        }
    end
end

function Fx.update(dt)
    if camera.shakeTimer > 0 then camera.shakeTimer = camera.shakeTimer - dt end

    for i = #particles, 1, -1 do
        local p = particles[i]
        p.life = p.life - dt
        p.vy = p.vy + 800 * dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        if p.life <= 0 then table.remove(particles, i) end
    end
end

-- Wird innerhalb der Viewport-Transformation aufgerufen, direkt vor dem Feld.
function Fx.applyShake()
    if camera.shakeTimer <= 0 then return end
    love.graphics.translate((math.random() * 2 - 1) * camera.shakeMag,
                            (math.random() * 2 - 1) * camera.shakeMag)
end

function Fx.draw()
    for _, p in ipairs(particles) do
        local alpha = math.max(0, p.life / p.maxLife)
        love.graphics.setColor(0.85, 0.75, 0.55, alpha)
        love.graphics.circle("fill", p.x, p.y, p.size)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Fx.shadow(x, y, radius, groundY)
    local dist = groundY - y
    if dist < 0 then dist = 0 end
    local alpha = math.max(0, 0.6 - (dist / 800))
    local scale = math.max(0.4, 1 - (dist / 600))
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.ellipse("fill", x, groundY, radius * scale, (radius * 0.25) * scale)
    love.graphics.setColor(1, 1, 1, 1)
end

return Fx
