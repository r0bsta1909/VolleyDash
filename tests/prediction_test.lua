-- ============================================================================
-- tests/prediction_test.lua -- Ebene B: Vollzustands-Vorhersage (ADR-025)
--
-- Der Kern dieser Datei ist der erste Fall: dieselbe Eingabefolge, einmal
-- durch `Step.tick` und einmal durch die Vorhersage -- und zwar fuer die
-- GANZE Welt, Ball eingeschlossen. Kommt dabei nicht dieselbe Bahn heraus,
-- ist die Vorhersage eine zweite Physik, und der Gast driftet im Betrieb
-- langsam vom Host weg, ohne dass ein Paket verloren ginge.
--
-- Der zweite Kern ist Rebase und Replay: Ein Snapshot, der nichts Neues
-- weiss, darf nichts veraendern; einer mit frischem Ack muss die Welt neu
-- aufsetzen, die eigenen Masken wieder vorspielen und dabei genau dort
-- herauskommen, wo die laufende Vorhersage schon war. Und eine Korrektur
-- kommt ohne Sprung -- ueber vier Ticks, wie §8 es festlegt.
--
-- love-frei, kein Netz.
-- ============================================================================

local Prediction = require("src.net.prediction")
local Snapshot   = require("src.net.snapshot")
local State      = require("src.sim.state")
local Step       = require("src.sim.step")
local Rules      = require("src.sim.rules")
local Ruleset    = require("src.sim.ruleset")
local Frame      = require("src.input.frame")
local World      = require("src.sim.world")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local function assertEq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: erwartet %s, war %s",
            what or "Wert", tostring(expected), tostring(actual)), 2)
    end
end
local function assertTrue(v, what) assertEq(not not v, true, what) end
local function assertNear(actual, expected, tol, what)
    if math.abs(actual - expected) > tol then
        error(string.format("%s: erwartet %s +-%s, war %s",
            what or "Wert", tostring(expected), tostring(tol), tostring(actual)), 2)
    end
end

-- Eine Eingabefolge, die alles anfasst, was den Blob bewegt: laufen, wenden,
-- springen, in der Luft die Richtung wechseln, stehenbleiben.
local function maskAt(tick)
    if tick < 20 then return Frame.RIGHT end
    if tick == 20 then return Frame.RIGHT + Frame.JUMP end
    if tick < 45 then return Frame.RIGHT + Frame.JUMP end
    if tick < 70 then return Frame.LEFT end
    if tick == 70 then return Frame.LEFT + Frame.JUMP end
    if tick < 100 then return Frame.LEFT + Frame.JUMP end
    if tick < 120 then return 0 end
    return Frame.RIGHT
end

-- Ein Spielzustand wie beim Anpfiff und die Vorhersage dazu, mit demselben
-- Ausgangsbild -- so, wie `net_game.lua` sie aufsetzt.
local function newPair(slot, preset)
    local rs = Ruleset.new(preset or "prototype")
    local state = State.new(rs)
    Rules.resetBall(state, rs, 1, {})
    state.match.phase = "play"
    local pred = Prediction.new(slot, rs)
    pred:reset(state)
    return state, rs, pred
end

-- Der Ball wird aus dem Weg geraeumt: hoch hinaus, wo ihn in den naechsten
-- Sekunden weder ein Blob noch der Boden erreicht. Fuer die Faelle, die
-- ausschliesslich die BLOB-Bewegung festnageln wollen -- ein gelandeter Ball
-- versetzt beide Blobs (`Rules.resetBall`), und dieser Sprung gehoert den
-- Uebernahme-Faellen, nicht den Bahn-Faellen.
local function parkBall(state)
    state.match.phase = "play"
    state.ball.x = World.WIDTH / 2
    state.ball.y = -5000
    state.ball.vx = 0
    state.ball.vy = 0
end

local function own(pred)
    return pred.state.blobs[pred.slot]
end

-- ---------------------------------------------------------------------------
-- Die eigentliche Absicherung: dieselbe Bahn wie die Simulation -- Welt und
-- Ball eingeschlossen
-- ---------------------------------------------------------------------------

for _, slot in ipairs({ 1, 2 }) do
    case("die Vorhersage laeuft Tick fuer Tick auf der Bahn von Step.tick (Slot "
         .. slot .. ")", function()
        local state, rs, pred = newPair(slot)
        local events = {}

        -- KEIN parkBall: Der Ball fliegt, wird geschlagen, landet, es gibt
        -- Punkte -- alles davon muss die Vorhersage identisch nachvollziehen,
        -- denn genau dafuer ist sie da (ADR-025).
        for tick = 0, 299 do
            local mask = maskAt(tick)
            local m1 = (slot == 1) and mask or 0
            local m2 = (slot == 2) and mask or 0

            Step.tick(state, m1, m2, rs, events)
            pred:advance(mask, tick)

            local blob = state.blobs[slot]
            local mine = own(pred)
            assertNear(mine.x, blob.x, 1e-9, string.format("Blob x bei Tick %d", tick))
            assertNear(mine.y, blob.y, 1e-9, string.format("Blob y bei Tick %d", tick))
            assertNear(pred.state.ball.x, state.ball.x, 1e-9,
                string.format("Ball x bei Tick %d", tick))
            assertNear(pred.state.ball.y, state.ball.y, 1e-9,
                string.format("Ball y bei Tick %d", tick))
            assertEq(pred.state.match.score[1], state.match.score[1],
                "Punkte links bei Tick " .. tick)
            assertEq(pred.state.match.score[2], state.match.score[2],
                "Punkte rechts bei Tick " .. tick)
        end
    end)
end

case("in gameover und menu bewegt sich nichts -- wie in Step.tick", function()
    local state, rs, pred = newPair(1)
    local startX = own(pred).x

    pred.state.match.phase = "gameover"
    for tick = 0, 59 do pred:advance(Frame.RIGHT, tick) end
    assertEq(own(pred).x, startX, "x im Abpfiff-Bild")

    pred.state.match.phase = "menu"
    for tick = 60, 119 do pred:advance(Frame.RIGHT, tick) end
    assertEq(own(pred).x, startX, "x im Menue")
end)

-- ---------------------------------------------------------------------------
-- Rebase und Replay
-- ---------------------------------------------------------------------------

-- Ein Snapshot aus einem Zustand -- derselbe Weg wie beim Host. Headless
-- bleibt er eine Lua-Tabelle; die f32-Rundung der Leitung gibt es hier nicht,
-- und das ist fuer diese Faelle genau richtig: sie messen die Mechanik, nicht
-- die Quantisierung.
local function snapFrom(state, tick, ack, rs)
    return Snapshot.from(state, tick, ack, rs)
end

case("ein Snapshot mit frischem Ack setzt neu auf und spielt die Masken wieder vor", function()
    local state, rs, pred = newPair(2)
    parkBall(state)
    parkBall(pred.state)
    local events = {}

    -- Host und Vorhersage laufen synchron; bei Tick 26 wird der Host-Stand
    -- als Snapshot festgehalten.
    local held
    for tick = 0, 29 do
        local mask = maskAt(tick)
        Step.tick(state, 0, mask, rs, events)
        pred:advance(mask, tick)
        if tick == 26 then held = snapFrom(state, tick, 26, rs) end
    end

    local beforeX, beforeY = own(pred).x, own(pred).y
    local corrected = pred:rebase(held, false, 30)

    assertEq(corrected, false, "nichts zu korrigieren -- die Vorhersage stimmte")
    assertEq(pred.corrections, 0, "der Zaehler bleibt bei null")
    assertEq(pred.lastReplay, 3, "drei Ticks wieder vorgespielt (27, 28, 29)")
    assertNear(own(pred).x, beforeX, 1e-6, "und der Blob steht wieder genau da")
    assertNear(own(pred).y, beforeY, 1e-6, "auch in der Hoehe")
end)

case("eine Abweichung > 2 px wird ueber vier Ticks eingeholt, ohne Sprung", function()
    local state, rs, pred = newPair(2)
    parkBall(pred.state)

    for tick = 0, 19 do pred:advance(Frame.LEFT, tick) end

    -- Der Host weiss es besser: derselbe Stand, der Blob aber 12 px daneben.
    local snap = snapFrom(pred.state, 19, 19, rs)
    snap.blob2X = snap.blob2X + 12

    local shownBefore = own(pred).x + pred.offsetX
    local corrected = pred:rebase(snap, false, 20)

    assertTrue(corrected, "die Abweichung wird erkannt")
    assertEq(pred.corrections, 1, "und einmal gezaehlt")

    -- Kein Sprung: das gezeichnete Bild steht in diesem Tick noch da, wo es
    -- vorher stand.
    assertNear(own(pred).x + pred.offsetX, shownBefore, 1e-9,
        "gezeichnete Lage sofort nach der Korrektur")

    -- Und dann in vier Schritten hinueber, monoton, ohne Ueberschwingen.
    local seen, last = {}, shownBefore
    for i = 1, 4 do
        pred:advance(0, 19 + i)
        local shown = own(pred).x + pred.offsetX
        seen[i] = shown - last
        last = shown
    end

    assertEq(pred.corrLeft, 0, "nach vier Ticks ist der Versatz aufgebraucht")
    assertNear(pred.offsetX, 0, 1e-9, "und exakt null")
    for i = 1, 4 do
        assertTrue(seen[i] > 0, "Schritt " .. i .. " geht in Richtung Host")
        assertTrue(seen[i] < 12, "Schritt " .. i .. " ist kein Sprung")
    end
end)

case("eine Abweichung <= 2 px wird still uebernommen, nicht korrigiert", function()
    local state, rs, pred = newPair(2)
    parkBall(pred.state)
    for tick = 0, 9 do pred:advance(0, tick) end

    local snap = snapFrom(pred.state, 9, 9, rs)
    snap.blob2X = snap.blob2X + 1.5

    local corrected = pred:rebase(snap, false, 10)
    assertEq(corrected, false, "1,5 px sind keine Korrektur")
    assertEq(pred.corrections, 0, "und werden nicht gezaehlt")
    assertEq(pred.offsetX, 0, "kein Versatz")
    assertNear(own(pred).x, snap.blob2X, 1e-9,
        "die Basis des Hosts gilt trotzdem -- unsichtbar uebernommen")
end)

case("ein stehender Ack laesst den eigenen Blob in Ruhe -- den Ball nicht", function()
    -- Der Host hat die letzte Maske wiederholt (§7). Sein Stand des EIGENEN
    -- Blobs beruht auf Eingaben, die es nie gab -- ihm zu folgen waere ein
    -- Fehler, den niemand gemacht hat. Ball und Stand sind trotzdem seine
    -- Wahrheit.
    local state, rs, pred = newPair(2)
    parkBall(pred.state)
    for tick = 0, 19 do pred:advance(Frame.LEFT, tick) end

    local fresh = snapFrom(pred.state, 15, 15, rs)
    pred:rebase(fresh, false, 20)
    local skippedBefore = pred.skipped
    local myX = own(pred).x

    local stale = snapFrom(pred.state, 16, 15, rs)   -- derselbe Ack noch einmal
    stale.blob2X = stale.blob2X + 50                 -- "Wahrheit", der niemand folgt
    stale.ballX  = 123.25                            -- die Wahrheit, der man folgt

    local corrected = pred:rebase(stale, false, 21)
    assertEq(corrected, false, "derselbe Ack wird nicht zweimal ausgewertet")
    assertEq(pred.skipped, skippedBefore + 1, "und als uebersprungen gezaehlt")
    assertEq(pred.corrections, 0, "kein Fehlalarm")
    assertNear(own(pred).x, myX, 1e-9, "der eigene Blob bleibt, wo er war")
    assertNear(pred.state.ball.x, 123.25, 1e-9, "der Ball kommt vom Host")
end)

case("eine Uebernahme nach dem Punkt zaehlt nicht als Korrektur", function()
    local state, rs, pred = newPair(2)
    parkBall(pred.state)
    for tick = 0, 19 do pred:advance(Frame.LEFT, tick) end

    Rules.resetBall(state, rs, 2, {})
    state.match.phase = "play"
    local snap = snapFrom(state, 19, 19, rs)

    pred:rebase(snap, true, 20)

    assertEq(pred.corrections, 0, "Korrekturzaehler bleibt bei null")
    assertEq(pred.takeovers, 1, "die Uebernahme wird getrennt gezaehlt")
    assertNear(own(pred).x, state.blobs[2].x, 1e-9, "die Position ist sofort da")
    assertEq(pred.offsetX, 0, "und wird nicht weich nachgefahren")
end)

case("nach der Korrektur findet der naechste Snapshot nichts mehr", function()
    -- Die neue Basis gilt ab sofort auch fuer die Historie: Wer dieselbe
    -- Abweichung zweimal faende, korrigierte zweimal -- und der Blob
    -- gummibandelte.
    local state, rs, pred = newPair(1)
    parkBall(pred.state)
    for tick = 0, 19 do pred:advance(Frame.RIGHT, tick) end

    local snap = snapFrom(pred.state, 19, 19, rs)
    snap.blob1X = snap.blob1X - 9
    pred:rebase(snap, false, 20)
    assertEq(pred.corrections, 1, "einmal korrigiert")

    for tick = 20, 22 do pred:advance(Frame.RIGHT, tick) end
    local honest = snapFrom(pred.state, 22, 22, rs)
    local corrected = pred:rebase(honest, false, 23)
    assertEq(corrected, false, "der naechste Vergleich ist sauber")
    assertEq(pred.corrections, 1, "kein zweites Mal")
end)

case("die Netzgrenze haelt auch in der Vorhersage", function()
    local state, rs, pred = newPair(1)
    parkBall(pred.state)
    for tick = 0, 179 do pred:advance(Frame.RIGHT, tick) end

    local maxX = World.NET_X - rs.blobRadius
    assertNear(own(pred).x, maxX, 1e-9, "Spieler 1 steht am Netz")

    local state2, rs2, pred2 = newPair(2)
    parkBall(pred2.state)
    for tick = 0, 179 do pred2:advance(Frame.LEFT, tick) end
    local minX = World.NET_X + World.NET_WIDTH + rs2.blobRadius
    assertNear(own(pred2).x, minX, 1e-9, "Spieler 2 steht am Netz")
end)

case("classic ohne Dash sagt auch ohne Dash vorher", function()
    -- ADR-006: im Vanilla-Regelwerk ist der Dash aus. Die Vorhersage darf
    -- ihn nicht trotzdem ausfuehren -- sonst rutscht der Gast bei jedem
    -- Tastendruck weg und wird zurueckgeholt.
    local state, rs, pred = newPair(1, "classic")
    parkBall(state)
    parkBall(pred.state)
    local events = {}

    for tick = 0, 59 do
        local mask = Frame.RIGHT + Frame.DASH
        Step.tick(state, mask, 0, rs, events)
        pred:advance(mask, tick)
        assertNear(own(pred).x, state.blobs[1].x, 1e-9, "x bei Tick " .. tick)
    end
    assertEq(own(pred).cooldownTimer, 0, "kein Cooldown, weil kein Dash")
end)

case("writeInto traegt den Versatz nur ins Bild, nie in die Simulation", function()
    local state, rs, pred = newPair(2)
    parkBall(pred.state)
    for tick = 0, 19 do pred:advance(Frame.LEFT, tick) end

    local snap = snapFrom(pred.state, 19, 19, rs)
    snap.blob2X = snap.blob2X + 12
    pred:rebase(snap, false, 20)

    local target = State.new(rs)
    pred:writeInto(target)

    assertNear(target.blobs[2].x, own(pred).x + pred.offsetX, 1e-9,
        "das Bild zeigt Position plus Versatz")
    assertNear(target.ball.x, pred.state.ball.x, 1e-9, "der Ball ist mitgekommen")
    assertEq(target.match.phase, pred.state.match.phase, "die Phase auch")
    -- Die Simulationsposition selbst traegt den Versatz nicht -- die
    -- naechsten Ticks rechnen mit der Wahrheit des Hosts.
    assertTrue(math.abs(pred.offsetX) > 0, "der Versatz laeuft noch")
end)

return T
