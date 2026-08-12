-- ============================================================================
-- src/app/scene.lua -- Szenen-Stack (M0-12)
--
-- Nur die oberste Szene bekommt update und keypressed. Gezeichnet werden alle
-- von unten nach oben, solange die obere durchscheinen laesst -- so liegt das
-- Menue ueber dem pausierten Spiel, ohne dass die Simulation weiterlaeuft.
--
-- Damit fallen zwei Dinge weg, die der Prototyp brauchte: die Phase "menu"
-- im Spielzustand und die fruehen `return`s aus love.update.
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

function Scene.update(dt)
    local top = stack[#stack]
    if top and top.update then top:update(dt) end
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
