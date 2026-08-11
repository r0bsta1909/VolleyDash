-- ============================================================================
-- VOLLEY DASH -- Bootstrap
--
-- Diese Datei tut nur noch drei Dinge: Fenster aufsetzen, die App starten und
-- die LOEVE-Rueckrufe an den Szenenstapel weiterreichen. Alles andere liegt
-- unter src/ (03_TECH §2):
--
--   src/sim/     Simulation, love-frei und headless testbar
--   src/input/   InputFrame und die vier Quellen (ADR-014)
--   src/render/  Viewport, Feld, HUD, Effekte
--   src/ui/      Menue und Live-Tweaker
--   src/app/     Prefs, Assets, Szenen
--
-- tools/reference_mode.lua ist das temporaere Werkzeug fuer die
-- Referenz-Rallyes (M0-03). Ohne Kommandozeilenflag ist es vollstaendig
-- inert.
-- ============================================================================

local Scene         = require("src.app.scene")
local Viewport      = require("src.render.viewport")
local ReferenceMode = require("tools.reference_mode")

ReferenceMode.parse(arg)

love.filesystem.setIdentity("volleydash")

function love.load()
    -- Ein Testlauf braucht weder Fenster noch Spiel.
    if ReferenceMode.runTests() then return end

    love.window.setTitle("Volley Dash")
    if ReferenceMode.refMode() then
        -- Referenzdaten entstehen in einem festen Fenster. Seit M0-04 haengt
        -- die Welt nicht mehr daran, aber der Satz soll reproduzierbar bleiben
        -- und die Fensterwarnung des Recorders etwas bedeuten.
        love.window.setMode(800, 600, { resizable = false })
    else
        love.window.setMode(800, 600, { resizable = true, minwidth = 640, minheight = 480 })
        love.window.maximize()
    end
    love.graphics.setBackgroundColor(0, 0, 0)   -- Letterbox-Balken (M0-04)

    local App = require("src.app.app")
    App.boot(ReferenceMode.refMode())
    ReferenceMode.install(App)
end

function love.update(dt)
    Scene.update(dt)
end

function love.draw()
    Viewport.apply()
    Scene.draw()
    Viewport.release()
end

function love.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        love.window.setFullscreen(not love.window.getFullscreen())
        return
    end
    Scene.keypressed(key)
end
