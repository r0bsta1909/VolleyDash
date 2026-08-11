-- ============================================================================
-- src/render/hud.lua -- Punkte, Beruehrungen, Statustexte (M0-12)
--
-- Liest den Zustand, schreibt nichts. Der Match-Kontext fuer das Turnier
-- ("Halbfinale, Satz 2") kommt in M5-03 dazu.
-- ============================================================================

local World  = require("src.sim.world")
local Assets = require("src.app.assets")

local Hud = {}

local function shadowedPrint(text, x, y)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.print(text, x + 2, y + 2)
end

-- names: { "Blau", "Rot" }
function Hud.draw(state, ruleset, names, views)
    local match, rally = state.match, state.rally
    local groundY = ruleset.blobGroundY or 500

    Assets.setFont(32)
    local left  = names[1] .. ": " .. match.score[1]
    local right = names[2] .. ": " .. match.score[2]
    shadowedPrint(left, World.WIDTH * 0.15, 30)
    shadowedPrint(right, World.WIDTH * 0.65, 30)

    -- Der Aufschlaeger steht in Gelb.
    love.graphics.setColor(match.servingPlayer == 1 and { 1, 0.85, 0.2, 1 } or { 1, 1, 1, 0.9 })
    love.graphics.print(left, World.WIDTH * 0.15, 30)
    love.graphics.setColor(match.servingPlayer == 2 and { 1, 0.85, 0.2, 1 } or { 1, 1, 1, 0.9 })
    love.graphics.print(right, World.WIDTH * 0.65, 30)

    Assets.setFont(16)
    for i = 1, 2 do
        local blob = views[i]
        if blob.cooldownTimer > 0 then
            local x = World.WIDTH * (i == 1 and 0.25 or 0.75)
            love.graphics.setColor(0.9, 0.2, 0.2, 0.8)
            love.graphics.rectangle("fill", x - 30, groundY + 15,
                60 * (blob.cooldownTimer / ruleset.dashCooldown), 4)
        end
    end

    if match.phase == "serve" then
        local sideX = World.WIDTH * (match.servingPlayer == 1 and 0.25 or 0.75)
        shadowedPrint("WAITING FOR SERVE", sideX - 80, 75)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("WAITING FOR SERVE", sideX - 80, 75)
    elseif rally.faultTimer > 0 then
        local sideX = World.WIDTH * (rally.faultPlayer == 1 and 0.25 or 0.75)
        shadowedPrint("FAULT!", sideX - 30, 75)
        love.graphics.setColor(1, 0.2, 0.2, 1)
        love.graphics.print("FAULT!", sideX - 30, 75)
    elseif rally.touchCount > 0 then
        local sideX = World.WIDTH * (rally.lastTouchPlayer == 1 and 0.25 or 0.75)
        local text = "Touches: " .. rally.touchCount .. " / 3"
        shadowedPrint(text, sideX - 45, 75)
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.print(text, sideX - 45, 75)
    end
end

function Hud.drawGameOver(state, names)
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, World.WIDTH, World.HEIGHT)

    local winner = state.match.score[1] > state.match.score[2] and names[1] or names[2]
    love.graphics.setColor(1, 0.85, 0.2)
    Assets.setFont(48)
    love.graphics.printf(winner .. " WINS!", 0, World.HEIGHT / 2 - 50, World.WIDTH, "center")

    Assets.setFont(24)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Press 'R' to play again or 'ESC' for Menu",
        0, World.HEIGHT / 2 + 20, World.WIDTH, "center")
end

return Hud
