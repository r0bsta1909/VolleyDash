-- ============================================================================
-- src/render/fx_events.lua -- Ereignisse der Simulation in Kosmetik (M2-06)
--
-- Herausgeloest aus `src/app/scenes/local_game.lua`, unveraendert. Grund: die
-- Netzszene braucht dieselbe Zuordnung, sobald sie Host ist -- dort laeuft
-- dieselbe Simulation und es fallen dieselben Ereignisse an. Zwei Kopien
-- waeren zwei Wahrheiten darueber, wann es staubt.
--
-- Die Reihenfolge der Staubwolken bleibt die des Prototyps, weil die
-- Ereignisse in der Reihenfolge ihres Entstehens kommen (M0-08).
--
-- Der CLIENT ruft das hier nicht auf. Er simuliert nicht und bekommt keine
-- Ereignisse; er leitet Kosmetik ab M3-02 aus Snapshot-Uebergaengen ab
-- (`04_NETCODE_SPEC` §6). Bis dahin ist sein Bild still.
-- ============================================================================

local Assets   = require("src.app.assets")
local Fx       = require("src.render.fx")
local GameView = require("src.render.game_view")

local FxEvents = {}

function FxEvents.apply(events, volume, state)
    for i = 1, #events do
        local e = events[i]
        local kind = e.type

        if kind == "jump" then
            Fx.dust(e.x, e.y, 8, 40, 100)
            Assets.play("jump", volume)
        elseif kind == "dash" then
            Assets.play("dash", volume)
            if e.up then Fx.dust(e.x, e.y, 10, 40, 100) else Fx.dust(e.x, e.y, 15, 60, 150) end
        elseif kind == "land" then
            Fx.dust(e.x, e.y, 10, 50, 80)
        elseif kind == "wall_hit" then
            Assets.play("hit_wall", volume)
        elseif kind == "net_hit" then
            Assets.play("hit_net", volume)
        elseif kind == "blob_hit" then
            Assets.play("hit_blob", volume)
        elseif kind == "dash_save" then
            Fx.shake(5, 0.25)
        elseif kind == "fault" or kind == "rally_timeout" then
            Fx.shake(4, 0.2)
        elseif kind == "smash" then
            Fx.shake(3, 0.15)
        elseif kind == "ground_hit" then
            Assets.play("hit_sand", volume)
            Fx.dust(e.x, e.y, 25, 80, 200)
        elseif kind == "point" or kind == "side_out" then
            Assets.play("whistle", volume)
        elseif kind == "match_over" then
            Assets.play("whistle_end", volume)
        elseif kind == "rally_reset" then
            -- Sprungstelle: sonst gleitet der Ball einen Frame lang von der
            -- alten zur neuen Aufschlagposition (M0-05).
            GameView.capture(state)
        end
    end
end

return FxEvents
