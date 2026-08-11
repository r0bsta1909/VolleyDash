-- ============================================================================
-- src/render/viewport.lua -- Letterbox/Pillarbox 800x600 -> Fenster (M0-04)
--
-- Die einzige Stelle, an der die Fenstergroesse ueberhaupt vorkommt. Die
-- Simulation rechnet immer in logischen 800 x 600 (ADR-004); hier wird das
-- Feld mittig, seitenverhaeltnistreu und mit schwarzen Balken ins Fenster
-- gelegt.
--
-- Vorher (B-01) wurde stattdessen WORLD.width aus der Fensterbreite berechnet.
-- Ein 21:9-Spieler hatte damit ein breiteres Feld als ein Fensterspieler --
-- andere Wandabpraller, andere Aufschlagpositionen, anderer Bot-Radius.
-- ============================================================================

local World = require("src.sim.world")

local Viewport = {}

-- Zuletzt berechnete Transformation. scale ist immer > 0.
local state = { scale = 1, ox = 0, oy = 0, winW = 0, winH = 0 }

-- Neu berechnen. Guenstig genug, um es pro Frame zu tun -- damit gibt es
-- keinen veralteten Zustand nach einem Resize, und love.resize wird nicht
-- gebraucht.
function Viewport.update()
    local winW, winH = love.graphics.getDimensions()
    local scale = math.min(winW / World.WIDTH, winH / World.HEIGHT)
    state.scale = scale
    state.ox = math.floor((winW - World.WIDTH * scale) / 2)
    state.oy = math.floor((winH - World.HEIGHT * scale) / 2)
    state.winW, state.winH = winW, winH
    return state
end

-- Transformation setzen. Alles danach zeichnet in logischen Koordinaten.
-- Das Scissor-Rechteck haelt Ueberzeichnungen (skalierte Hintergrundbilder,
-- Kamera-Shake) aus den Balken heraus.
function Viewport.apply()
    Viewport.update()
    love.graphics.push()
    love.graphics.setScissor(state.ox, state.oy,
        World.WIDTH * state.scale, World.HEIGHT * state.scale)
    love.graphics.translate(state.ox, state.oy)
    love.graphics.scale(state.scale, state.scale)
end

function Viewport.release()
    love.graphics.setScissor()
    love.graphics.pop()
end

-- Fensterkoordinate -> Weltkoordinate. Noch ungenutzt; die Menues laufen
-- ueber die Tastatur. Gehoert trotzdem hierher, damit spaeter niemand die
-- Umrechnung ein zweites Mal erfindet.
function Viewport.toWorld(sx, sy)
    return (sx - state.ox) / state.scale, (sy - state.oy) / state.scale
end

function Viewport.getScale()
    return state.scale
end

-- x, y, Breite, Hoehe des Feldes im Fenster -- fuer Overlays, die in
-- Bildschirmkoordinaten zeichnen.
function Viewport.getRect()
    return state.ox, state.oy, World.WIDTH * state.scale, World.HEIGHT * state.scale
end

return Viewport
