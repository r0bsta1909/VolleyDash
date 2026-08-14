-- ============================================================================
-- src/app/scene.lua -- Szenen-Stack (M0-12)
--
-- Nur die oberste Szene bekommt `keypressed`. Gezeichnet werden alle von unten
-- nach oben, solange die obere durchscheinen laesst -- so liegt das Menue ueber
-- dem pausierten lokalen Spiel, ohne dass die Simulation weiterlaeuft.
--
-- Damit fallen zwei Dinge weg, die der Prototyp brauchte: die Phase "menu"
-- im Spielzustand und die fruehen `return`s aus love.update.
--
-- ---------------------------------------------------------------------------
-- `alwaysUpdate` (ADR-024)
-- ---------------------------------------------------------------------------
--
-- `update` bekam bis M4-09 ebenfalls nur die oberste Szene, und fuer das
-- lokale Spiel ist das genau richtig: Nicht aktualisiert zu werden IST die
-- Pause. Eine Szene, die Sockets haelt oder autoritativ simuliert, darf so
-- aber nicht stehenbleiben -- gemessen zweimal:
--
--   * Der Turniermodus lag waehrend eines Matches darunter und wurde
--     minutenlang nicht bedient. Nach 5 s Peer-Timeout galt jeder Teilnehmer
--     als offline (C-T-01).
--   * Ein Menue ueber dem Netzspiel haette dasselbe getan, weshalb es dort gar
--     keines gab: ESC beendete die Sitzung.
--
-- Eine Szene meldet sich deshalb mit `alwaysUpdate = true` an. Das ist eine
-- Zusage ueber sich selbst und keine globale Umschaltung -- `local_game` setzt
-- sie nicht, dort bleibt die Pause.
-- ============================================================================

local Scene = {}

local stack = {}

function Scene.push(scene)
    stack[#stack + 1] = scene
    if scene.enter then scene:enter() end
    return scene
end

function Scene.pop()
    local scene = table.remove(stack)
    if scene and scene.leave then scene:leave() end
    return scene
end

function Scene.top()
    return stack[#stack]
end

-- Von unten nach oben, damit die oberste Szene den zuletzt gueltigen Zustand
-- sieht. Die oberste laeuft immer, alles darunter nur auf eigenen Wunsch.
function Scene.update(dt)
    local top = #stack
    for i = 1, top do
        local scene = stack[i]
        if scene.update and (i == top or scene.alwaysUpdate) then
            scene:update(dt)
        end
    end
end

-- Die Szene direkt unter dieser. Das Menue braucht sie, um zu wissen, worueber
-- es liegt -- ueber dem pausierten lokalen Spiel oder ueber einem laufenden
-- Netzmatch (ADR-024).
function Scene.below(scene)
    for i = #stack, 2, -1 do
        if stack[i] == scene then return stack[i - 1] end
    end
    return nil
end

-- Liegt etwas ueber dieser Szene? Eine Szene mit `alwaysUpdate` laeuft weiter,
-- bekommt aber keine Tasten mehr -- und muss das wissen koennen (ADR-024).
function Scene.isTop(scene)
    return stack[#stack] == scene
end

function Scene.draw()
    -- Die unterste sichtbare Szene finden: alles darunter waere verdeckt.
    local first = 1
    for i = #stack, 1, -1 do
        if not stack[i].transparent then first = i break end
    end
    for i = first, #stack do
        if stack[i].draw then stack[i]:draw() end
    end
end

function Scene.keypressed(key)
    local top = stack[#stack]
    if top and top.keypressed then top:keypressed(key) end
end

-- Getippter Text (M2-05). Nur die manuelle IP-Eingabe braucht das; `keypressed`
-- allein wuerde Tastaturbelegungen ausserhalb von US-QWERTY falsch abbilden.
function Scene.textinput(text)
    local top = stack[#stack]
    if top and top.textinput then top:textinput(text) end
end

-- Alle Szenen abraeumen, auf die `predicate` zutrifft. Wird beim Verlassen
-- eines Netzspiels gebraucht: dort liegen bis zu drei Szenen uebereinander
-- (Serverliste, Lobby, Match), und jede von ihnen haelt Sockets, die in
-- `leave` zugehen muessen.
function Scene.popWhile(predicate)
    local removed = 0
    while stack[#stack] and predicate(stack[#stack]) do
        Scene.pop()
        removed = removed + 1
    end
    return removed
end

return Scene
