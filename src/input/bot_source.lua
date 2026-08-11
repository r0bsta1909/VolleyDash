-- ============================================================================
-- src/input/bot_source.lua -- Bot-KI -> InputFrame (M0-07, B-07, B-09)
--
-- Wortgleich aus der Inline-Kopie in main.lua gehoben. Die Zahlen sind
-- unveraendert: Reaktionsverzoegerung, Jitter, Toleranz 8 px, die
-- Aufschlaglogik je Stufe, die Dash-Bedingung, der +25-Versatz beim dritten
-- Ballkontakt. `02_CODE_AUDIT` §4 gilt auch fuer den Bot.
--
-- Zwei Blocker fallen damit:
--   B-07  Es gab zwei Bot-Fassungen. Die verwaiste bot.lua ist geloescht, die
--         aktive Inline-Kopie steht jetzt hier -- eine Wahrheit.
--   B-09  Zielpunkt und Reaktionszaehler lagen auf dem Modul. Jetzt haelt sie
--         jede Instanz selbst, sonst teilen sich zwei Bots einen Zustand
--         (2v2, KotH-Fuellspieler, Bot-gegen-Bot am Beamer).
--
-- Der Bot ist eine Quelle wie Tastatur oder Netzwerk (ADR-014): er liefert
-- ein Byte pro Tick und fasst den Spielzustand nicht an.
--
-- Bekannte Einschraenkung: predictLandingX benutzt das globale math.random.
-- Fuer die Simulation ist das unschaedlich -- der Bot steht ausserhalb von
-- src/sim/, und Aufzeichnungen halten seinen Output fest, nicht seinen
-- Zustand. Ein deterministischer Bot (rng.lua) ist Sache des Redesigns im
-- M6-Backlog.
-- ============================================================================

local Frame = require("src.input.frame")
local World = require("src.sim.world")

local BotSource = {}
BotSource.__index = BotSource

BotSource.DIFFICULTIES = {
    [1] = { reactionDelay = 0.45, jitter = 70, useDash = false, useSmash = false },
    [2] = { reactionDelay = 0.20, jitter = 25, useDash = false, useSmash = true  },
    [3] = { reactionDelay = 0.04, jitter = 4,  useDash = true,  useSmash = true  },
}

-- ctx buendelt die Tabellen, die der Bot lesen darf. Alle werden in love.load
-- einmal erzeugt und nie ersetzt.
function BotSource.new(playerIndex, ctx)
    return setmetatable({
        index         = playerIndex,
        ctx           = ctx,
        targetX       = 600,
        reactionTimer = 0,
    }, BotSource)
end

function BotSource:reset()
    self.targetX = 600
    self.reactionTimer = 0
end

-- Vorausberechnung der Ball-Landeposition. Unveraendert aus dem Prototyp.
function BotSource:predictLandingX(b, c, w, diffSettings)
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

-- Entscheidung dieses Ticks als Tabelle. Nur intern; nach aussen geht das
-- Byte aus :poll().
function BotSource:decide()
    local bot   = self.ctx.blob
    local b     = self.ctx.ball
    local c     = self.ctx.ruleset
    local w     = self.ctx.world
    local match = self.ctx.state.match
    local rally = self.ctx.state.rally

    -- Die Bot-Stufe ist eine lokale Einstellung, kein Regelwerk (ADR-005).
    local diff = BotSource.DIFFICULTIES[self.ctx.prefs.botLevel] or BotSource.DIFFICULTIES[2]
    local inputs = { left = false, right = false, jump = false, smash = false, dashDir = nil }

    if match.phase == "serve" and match.servingPlayer == 2 then
        if rally.serveTimer < rally.serveDelay then return inputs end

        local level = self.ctx.prefs.botLevel
        if level == 1 then
            if bot.x < b.x + 10 then inputs.right = true else inputs.left = true; inputs.jump = true end
        elseif level == 2 then
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

    -- Der Reaktionszaehler laeuft in Ticks. Frueher bekam er das dt aus
    -- love.update; seit M0-05 ist das ohnehin immer TICK_DT.
    self.reactionTimer = self.reactionTimer + World.TICK_DT
    if self.reactionTimer >= diff.reactionDelay then
        self.reactionTimer = 0
        if b.x > w.width * 0.35 or b.vx > 0 then
            self.targetX = self:predictLandingX(b, c, w, diff)
            if rally.lastTouchPlayer == 2 and rally.touchCount == 2 then
                self.targetX = self.targetX + 25
            end
        else
            self.targetX = w.width * 0.75
        end
    end

    local tolerance = 8
    if bot.x < self.targetX - tolerance then inputs.right = true
    elseif bot.x > self.targetX + tolerance then inputs.left = true end

    if diff.useDash and bot.cooldownTimer <= 0 then
        local distToTarget = math.abs(bot.x - self.targetX)
        local timeToImpact = (w.groundY - b.y) / math.max(1, b.vy)
        local timeToRun = distToTarget / c.moveSpeed

        if b.x > w.width / 2 and timeToImpact > 0 and timeToRun > timeToImpact then
            inputs.dashDir = (bot.x < self.targetX) and "right" or "left"
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
            elseif rally.lastTouchPlayer == 2 and rally.touchCount == 2 and b.vy > 0 then
                inputs.smash = true
            end
        end
    end

    return inputs
end

-- Signatur wie bei jeder Quelle. Das Dash-Fenster interessiert den Bot nicht:
-- er tippt nicht doppelt, er setzt das Bit direkt (ADR-014 §4).
function BotSource:poll(dashWindowTicks)
    local d = self:decide()

    -- Die Dash-Richtung steckt im Richtungsbit. Der Bot setzt sein
    -- Richtungsbit sonst aus der Zielverfolgung; beim Dash gewinnt die
    -- Dash-Richtung, sonst zeigte das Bit gelegentlich in die Gegenrichtung.
    local left, right = d.left, d.right
    if d.dashDir == "left" then
        left, right = true, false
    elseif d.dashDir == "right" then
        left, right = false, true
    end

    return Frame.encode({
        left  = left,
        right = right,
        jump  = d.jump,
        smash = d.smash,
        dash  = d.dashDir ~= nil,
    })
end

return BotSource
