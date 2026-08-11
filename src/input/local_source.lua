-- ============================================================================
-- src/input/local_source.lua -- Tastatur und Gamepad -> InputFrame (M0-06)
--
-- Eine von vier zulaessigen Quellen (ADR-014). Die Simulation fragt nie selbst
-- die Hardware; sie bekommt pro Tick ein Byte.
--
-- Hier sitzt auch die Doppeltipp-Erkennung fuer den Dash. Sie zaehlt in
-- TICKS, nicht in Sekunden -- der Prototyp mass ueber love.timer.getTime()
-- und haing damit an der Bildwiederholrate (B-02/B-03).
--
-- love.* wird ausschliesslich innerhalb der Funktionen benutzt, damit die
-- Datei auch von einem Testrunner geladen werden kann, der kein LOEVE hat.
-- ============================================================================

local Frame    = require("src.input.frame")
local Bindings = require("src.input.bindings")

local LocalSource = {}
LocalSource.__index = LocalSource

-- Analogachsen werden in der Quelle diskretisiert -- die Simulation kennt
-- keine halben Eingaben (13_INPUTFRAME_FORMAT §6).
LocalSource.AXIS_DEADZONE = 0.5

-- Ein Geraet gehoert genau einem Spieler-Slot (GDD §7). Die Zuordnung haelt
-- ueber Hotplug hinweg, weil sie an der Joystick-ID haengt und nicht an der
-- Reihenfolge in getJoysticks().
local padSlot = {}

function LocalSource.releasePads()
    padSlot = {}
end

-- ---------------------------------------------------------------------------
-- Doppeltipp-Erkennung
--
-- Reine Zustandsmaschine ohne love, ohne Zeit, ohne Zufall. Sie sieht nur
-- Richtungs- und Sprungbits und die Ticknummer. Genau deshalb ist sie
-- testbar (ADR-014 verlangt dafuer einen eigenen Unit-Test).
--
-- Die Erkennung fragt NICHT nach dashCooldown. Die Quelle meldet "Dash
-- jetzt", die Simulation entscheidet, ob er zulaessig ist (ADR-014).
-- ---------------------------------------------------------------------------
local TapDetector = {}
TapDetector.__index = TapDetector

-- Tasten, auf denen ein Doppeltipp einen Dash ausloest: die beiden Richtungen
-- und der Sprung (Aufwaerts-Dash).
local TAP_MASKS = { Frame.LEFT, Frame.RIGHT, Frame.JUMP }

function TapDetector.new()
    return setmetatable({ lastTap = {}, prev = 0, tick = 0 }, TapDetector)
end

function TapDetector:reset()
    self.lastTap = {}
    self.prev = 0
end

-- bits: Zustandsbits dieses Ticks (ohne dash). windowTicks: dashWindow in
-- Ticks. Rueckgabe: true, wenn in diesem Tick ein Doppeltipp fertig wurde.
function TapDetector:update(bits, windowTicks)
    self.tick = self.tick + 1
    local fired = false

    for _, mask in ipairs(TAP_MASKS) do
        if Frame.pressed(bits, self.prev, mask) then
            local last = self.lastTap[mask]
            if last and (self.tick - last) <= windowTicks then
                fired = true
                -- Nach dem Ausloesen zurueckgesetzt, damit aus drei Tipps
                -- nicht zwei Dashes werden.
                self.lastTap[mask] = nil
            else
                self.lastTap[mask] = self.tick
            end
        end
    end

    self.prev = bits
    return fired
end

LocalSource.TapDetector = TapDetector

-- ---------------------------------------------------------------------------
-- Quelle
-- ---------------------------------------------------------------------------

-- playerIndex waehlt Gamepad-Slot und Vorgabebelegung. `keys` ist die
-- Belegung dieses Spielers aus den Prefs (src/input/bindings.lua).
function LocalSource.new(playerIndex, keys)
    return setmetatable({
        index = playerIndex,
        keys = keys or Bindings.DEFAULTS[playerIndex],
        taps = TapDetector.new(),
    }, LocalSource)
end

-- Belegung im laufenden Betrieb austauschen (Menue).
function LocalSource:setKeys(keys)
    self.keys = keys
end

-- Das Pad dieses Slots. Ein noch nicht zugeordnetes Pad wird dem ersten
-- Slot zugeschlagen, der danach fragt -- damit wird ein waehrend des Spiels
-- eingestecktes Gamepad ohne Neustart erkannt (GDD §7, Hotplug).
local function joystickFor(slot)
    if not (love and love.joystick) then return nil end
    local sticks = love.joystick.getJoysticks()

    for _, js in ipairs(sticks) do
        if js:isGamepad() and padSlot[js:getID()] == slot then return js end
    end
    for _, js in ipairs(sticks) do
        if js:isGamepad() and padSlot[js:getID()] == nil then
            padSlot[js:getID()] = slot
            return js
        end
    end
    return nil
end

-- Gamepad-Anteil. Ungetestet mangels Geraet an dieser Maschine; die Belegung
-- folgt der SDL-Standardbelegung, die LOEVE ueber isGamepadDown liefert.
function LocalSource:gamepadBits()
    local stick = joystickFor(self.index)
    if not stick then return 0, false end

    local pad = Bindings.GAMEPAD
    local bits = 0
    local axis = stick:getGamepadAxis(pad.axis) or 0
    if axis < -LocalSource.AXIS_DEADZONE or stick:isGamepadDown(pad.left) then
        bits = bits + Frame.LEFT
    elseif axis > LocalSource.AXIS_DEADZONE or stick:isGamepadDown(pad.right) then
        bits = bits + Frame.RIGHT
    end
    if stick:isGamepadDown(pad.jump) then bits = bits + Frame.JUMP end
    if stick:isGamepadDown(pad.smash) then bits = bits + Frame.SMASH end

    -- Dash liegt auf den Schultertasten (GDD §7). Sie setzen zugleich die
    -- Richtung, damit der Frame eindeutig bleibt (13_INPUTFRAME_FORMAT §4).
    local dash = false
    if stick:isGamepadDown(pad.dashLeft) then
        dash = true
        bits = bits - (Frame.has(bits, Frame.RIGHT) and Frame.RIGHT or 0)
        if not Frame.has(bits, Frame.LEFT) then bits = bits + Frame.LEFT end
    elseif stick:isGamepadDown(pad.dashRight) then
        dash = true
        bits = bits - (Frame.has(bits, Frame.LEFT) and Frame.LEFT or 0)
        if not Frame.has(bits, Frame.RIGHT) then bits = bits + Frame.RIGHT end
    end
    return bits, dash
end

function LocalSource:keyboardBits()
    local down = love.keyboard.isDown
    local k = self.keys
    local bits = 0
    if down(k.left)  then bits = bits + Frame.LEFT  end
    if down(k.right) then bits = bits + Frame.RIGHT end
    if down(k.jump)  then bits = bits + Frame.JUMP  end
    if down(k.smash) then bits = bits + Frame.SMASH end
    return bits
end

-- Ein InputFrame fuer diesen Tick. dashWindowTicks kommt aus dem Ruleset
-- (dashWindow * TICK_RATE).
function LocalSource:poll(dashWindowTicks)
    local bits = self:keyboardBits()
    local pad, padDash = self:gamepadBits()

    -- Tastatur und Gamepad wirken parallel. Beide Richtungen gleichzeitig ist
    -- kein Sonderfall: Frame.moveDir loest das nach links auf.
    if pad ~= 0 then
        if Frame.has(pad, Frame.LEFT)  and not Frame.has(bits, Frame.LEFT)  then bits = bits + Frame.LEFT end
        if Frame.has(pad, Frame.RIGHT) and not Frame.has(bits, Frame.RIGHT) then bits = bits + Frame.RIGHT end
        if Frame.has(pad, Frame.JUMP)  and not Frame.has(bits, Frame.JUMP)  then bits = bits + Frame.JUMP end
        if Frame.has(pad, Frame.SMASH) and not Frame.has(bits, Frame.SMASH) then bits = bits + Frame.SMASH end
    end

    local doubleTap = self.taps:update(bits, dashWindowTicks)
    if doubleTap or padDash then
        bits = bits + Frame.DASH
    end
    return bits
end

-- Nach einem Punkt, einem Szenenwechsel oder einem Reconnect: die Tipphistorie
-- gehoert nicht ueber die Grenze hinweg mitgeschleppt.
function LocalSource:reset()
    self.taps:reset()
end

return LocalSource
