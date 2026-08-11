-- ============================================================================
-- src/ui/tweaker.lua -- Live-Tweaker (M0-12)
--
-- Aendert das Ruleset zur Laufzeit. Erlaubt ist das **offline oder
-- host-seitig in der Lobby** (B-04, ADR-005) -- im laufenden Netzwerkmatch
-- ist das Ruleset unveraenderlich. Die Sperre dafuer kommt mit M2-06.
--
-- Die Grenzen kommen aus src/sim/ruleset.lua, nicht aus dieser Liste: eine
-- zweite Wahrheit ueber Wertebereiche war Befund F-10.
-- ============================================================================

local Ruleset = require("src.sim.ruleset")
local Assets  = require("src.app.assets")

local Tweaker = {}
Tweaker.__index = Tweaker

-- Reihenfolge und Beschriftung sind Oberflaeche und stehen deshalb hier.
Tweaker.OPTIONS = {
    { name = "Ball-Boden (Y)",        key = "ballGroundY" },
    { name = "Aktiv-Impuls",          key = "activeTransfer" },
    { name = "Passiv-Abprall",        key = "passiveBounce" },
    { name = "Luft-Steuerung",        key = "airControl" },
    { name = "Ball-Schwerkraft",      key = "gravity" },
    { name = "Blob-Schwerkraft",      key = "blobGravity" },
    { name = "Ball-Geschwindigkeit",  key = "ballBaseSpeed" },
    { name = "Max Ball-Speed",        key = "maxBallSpeed" },
    { name = "Ball-Groesse",          key = "ballRadius" },
    { name = "Sprungkraft",           key = "jumpForce" },
    { name = "Lauf-Tempo Boden",      key = "moveSpeed" },
    { name = "Blob-Groesse",          key = "blobRadius" },
    { name = "Netzhoehe",             key = "netHeight" },
    { name = "Aufschlag-Hoehe",       key = "serveHeight" },
    { name = "Aufschlag-Boost",       key = "serveBoost" },
    { name = "Wand-Abprall",          key = "wallBounce" },
    { name = "Dash-Zeitfenster (Sek)", key = "dashWindow" },
    { name = "Dash-Cooldown (Sek)",   key = "dashCooldown" },
    { name = "Dash-Tempo (Seite)",    key = "dashSide" },
    { name = "Dash-Hoehe (Hoch)",     key = "dashUp" },
    { name = "Satzpunkte",            key = "targetScore" },
    { name = "Deuce-Deckel",          key = "deuceCap" },
    { name = "Rallye-Timeout (Sek)",  key = "rallyTimeout" },
    { name = "Speed-Scaling",         key = "speedScaling" },
    { name = "Active Spike (Smash)",  key = "activeSpike" },
    { name = "Dash erlaubt",          key = "allowDash" },
    { name = "Zwei-Punkte-Vorsprung", key = "twoPointLead" },
}

Tweaker.MAX_VISIBLE = 16

function Tweaker.new(ruleset)
    return setmetatable({ ruleset = ruleset, active = false, index = 1 }, Tweaker)
end

function Tweaker:toggle()
    self.active = not self.active
end

local function field(key)
    return Ruleset.FIELDS[key]
end

function Tweaker:adjust(direction)
    local opt = Tweaker.OPTIONS[self.index]
    local def = field(opt.key)
    if not def then return end

    if def.type == "boolean" then
        self.ruleset[opt.key] = not self.ruleset[opt.key]
        return
    end

    local delta = direction * (def.step or 1)
    -- Die Sprungkraft ist negativ: rechts soll trotzdem "hoeher" bedeuten.
    if opt.key == "jumpForce" then delta = -delta end
    self.ruleset[opt.key] = Ruleset.clamp(opt.key, self.ruleset[opt.key] + delta)
end

-- Gibt true zurueck, wenn die Taste verbraucht wurde.
function Tweaker:keypressed(key)
    if not self.active then return false end

    if key == "tab" or key == "f1" then self.active = false return true end
    if key == "up" then self.index = math.max(1, self.index - 1) return true end
    if key == "down" then self.index = math.min(#Tweaker.OPTIONS, self.index + 1) return true end
    if key == "left" then self:adjust(-1) return true end
    if key == "right" then self:adjust(1) return true end
    return true   -- solange der Tweaker offen ist, gehoert ihm die Tastatur
end

function Tweaker:draw()
    if not self.active then return end

    local startIndex = 1
    if self.index > Tweaker.MAX_VISIBLE then
        startIndex = self.index - Tweaker.MAX_VISIBLE + 1
    end
    local endIndex = math.min(#Tweaker.OPTIONS, startIndex + Tweaker.MAX_VISIBLE - 1)

    love.graphics.setColor(0.04, 0.06, 0.1, 0.85)
    local boxHeight = 40 + ((endIndex - startIndex + 1) * 22)
    love.graphics.rectangle("fill", 10, 10, 390, boxHeight, 6, 6)

    Assets.setFont(12)
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.print("LIVE TWEAKER (ESC = Menu | TAB = Hide)", 20, 18)

    local y = 38
    for i = startIndex, endIndex do
        local opt = Tweaker.OPTIONS[i]
        if i == self.index then
            love.graphics.setColor(0.2, 0.4, 0.7, 0.8)
            love.graphics.rectangle("fill", 15, y - 2, 380, 20, 4, 4)
            love.graphics.setColor(1, 1, 1)
        else
            love.graphics.setColor(0.8, 0.8, 0.8)
        end

        local value = self.ruleset[opt.key]
        local text = tostring(value)
        if type(value) == "number" then
            local def = field(opt.key)
            text = string.format((def and def.step or 1) < 1 and "%.2f" or "%.0f", value)
        end
        love.graphics.print(opt.name, 25, y)
        love.graphics.print("< " .. text .. " >", 290, y)
        y = y + 22
    end

    if endIndex < #Tweaker.OPTIONS then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.print("v Weitere Optionen v", 150, y)
    end
end

return Tweaker
