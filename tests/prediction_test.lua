-- ============================================================================
-- tests/prediction_test.lua -- Ebene B: Vorhersage des eigenen Blobs (M3-01)
--
-- Der Kern dieser Datei ist der erste Fall: dieselbe Eingabefolge, einmal
-- durch `Step.tick` und einmal durch die Vorhersage. Kommt dabei nicht
-- dieselbe Bahn heraus, ist die Vorhersage eine zweite Physik -- und der
-- Gast driftet im Betrieb langsam vom Host weg, ohne dass ein Paket verloren
-- ginge (`04_NETCODE_SPEC` §8, ADR-017).
--
-- Der zweite Kern ist der Korrekturtest: kein harter Sprung, sondern vier
-- Ticks. Ein Test, der nur die Endposition prueft, wuerde einen Sprung
-- durchgehen lassen -- also wird der Weg dahin geprueft.
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

local function newPair(slot, preset)
    local rs = Ruleset.new(preset or "prototype")
    local state = State.new(rs)
    Rules.resetBall(state, rs, 1, {})
    local pred = Prediction.new(slot, rs)
    pred:reset(state.blobs[slot])
    return state, rs, pred
end

-- Der Ball wird aus dem Weg geraeumt: hoch hinaus, wo ihn in den naechsten
-- Sekunden weder ein Blob noch der Boden erreicht.
--
-- Das ist kein Kunstgriff, sondern die Bedingung des Auftrags: geprueft wird
-- die Uebereinstimmung, "solange kein Ballkontakt dazwischenliegt". Ohne das
-- schlaegt der Blob den Ball im ersten Tick auf, der Ball faellt, es gibt
-- einen Punkt -- und `Rules.resetBall` VERSETZT beide Blobs auf die
-- Aufschlagposition. Dieser Sprung ist keine falsche Vorhersage, sondern die
-- Uebernahme, die ein eigener Fall weiter unten prueft.
local function parkBall(state)
    state.match.phase = "play"
    state.ball.x = World.WIDTH / 2
    state.ball.y = -5000
    state.ball.vx = 0
    state.ball.vy = 0
end

-- ---------------------------------------------------------------------------
-- Die eigentliche Absicherung: dieselbe Bahn wie die Simulation
-- ---------------------------------------------------------------------------

for _, slot in ipairs({ 1, 2 }) do
    case("die Vorhersage laeuft Tick fuer Tick auf der Bahn von Step.tick (Slot "
         .. slot .. ")", function()
        local state, rs, pred = newPair(slot)
        local events = {}
        parkBall(state)

        for tick = 0, 179 do
            local mask = maskAt(tick)
            local m1 = (slot == 1) and mask or 0
            local m2 = (slot == 2) and mask or 0

            Step.tick(state, m1, m2, rs, events)
            pred:advance(mask, state.match.phase, tick)

            local blob = state.blobs[slot]
            -- Bitgleich waere zu viel verlangt, sobald der Ball die Phase
            -- umschaltet; identisch ist die Rechnung trotzdem. Ein
            -- Zehntausendstel Pixel ist die Grenze, unter der kein
            -- Rundungsunterschied mehr ein Fehler ist.
            assertNear(pred.blob.x, blob.x, 1e-4,
                string.format("x bei Tick %d", tick))
            assertNear(pred.blob.y, blob.y, 1e-4,
                string.format("y bei Tick %d", tick))
            assertNear(pred.blob.vy, blob.vy, 1e-4,
                string.format("vy bei Tick %d", tick))
        end
    end)
end

case("ein Ballkontakt aendert die Blob-Bahn nicht", function()
    -- Der Ball wird dem Blob direkt vor den Kopf gesetzt; die Vorhersage
    -- weiss nichts davon. Genau das ist die Begruendung aus §8: die
    -- Kollision veraendert den Ball, nicht den Blob.
    local state, rs, pred = newPair(1)
    local events = {}
    parkBall(state)

    local touched = false
    for tick = 0, 119 do
        -- Ball auf den Kopf des Blobs setzen. Er wird weggeschlagen; der
        -- Blob selbst darf davon nichts merken.
        if tick == 30 then
            state.ball.x = state.blobs[1].x
            state.ball.y = state.blobs[1].y - rs.blobRadius
            state.ball.vy = 200
        end
        local mask = maskAt(tick)
        Step.tick(state, mask, 0, rs, events)
        pred:advance(mask, state.match.phase, tick)

        for i = 1, #events do
            if events[i].type == "blob_hit" then touched = true end
        end

        -- Landet der weggeschlagene Ball, versetzt `Rules.resetBall` die
        -- Blobs -- noch in DIESEM Tick. Ab da vergleicht dieser Fall nichts
        -- mehr; die Uebernahme hat einen eigenen.
        if state.match.phase ~= "play" then break end

        assertNear(pred.blob.x, state.blobs[1].x, 1e-4, "x bei Tick " .. tick)
        assertNear(pred.blob.y, state.blobs[1].y, 1e-4, "y bei Tick " .. tick)
    end

    assertTrue(touched, "der Ball wurde tatsaechlich beruehrt")
end)

case("in gameover und menu bewegt sich nichts -- wie in Step.tick", function()
    local state, rs, pred = newPair(1)
    local startX = pred.blob.x

    for tick = 0, 59 do
        pred:advance(Frame.RIGHT, "gameover", tick)
    end
    assertEq(pred.blob.x, startX, "x im Abpfiff-Bild")

    for tick = 60, 119 do
        pred:advance(Frame.RIGHT, "menu", tick)
    end
    assertEq(pred.blob.x, startX, "x im Menue")
end)

-- ---------------------------------------------------------------------------
-- Korrektur
-- ---------------------------------------------------------------------------

-- Ein Snapshot mit frei gesetzter Blob-Position. Nur die Felder, die
-- `Prediction:reconcile` liest -- der Rest gehoert dem Host.
local function snapWith(slot, x, y, ack)
    local snap = {
        tick = 0, ackInputTick = ack,
        blob1X = 0, blob1Y = 0, blob1VY = 0,
        blob2X = 0, blob2Y = 0, blob2VY = 0,
    }
    snap["blob" .. slot .. "X"] = x
    snap["blob" .. slot .. "Y"] = y
    return snap
end

case("eine Abweichung > 2 px wird ueber vier Ticks eingeholt, ohne Sprung", function()
    local state, rs, pred = newPair(2)

    -- Zwanzig Ticks laufen, damit es eine Vorgeschichte gibt.
    for tick = 0, 19 do pred:advance(Frame.LEFT, "play", tick) end

    local mine = pred:predictedAt(19)
    assertTrue(mine ~= nil, "Tick 19 steht im Ringpuffer")

    local before = pred.blob.x + pred.offsetX
    local corrected = pred:reconcile(snapWith(2, mine.x + 12, mine.y, 19), false)

    assertTrue(corrected, "die Abweichung wird erkannt")
    assertEq(pred.corrections, 1, "und einmal gezaehlt")

    -- Kein Sprung: das gezeichnete Bild steht in diesem Tick noch da, wo es
    -- vorher stand.
    assertNear(pred.blob.x + pred.offsetX, before, 1e-9, "gezeichnete Lage sofort nach der Korrektur")

    -- Und dann in vier Schritten hinueber, monoton, ohne Ueberschwingen.
    local seen, last = {}, before
    for i = 1, 4 do
        pred:advance(0, "play", 19 + i)
        local shown = pred.blob.x + pred.offsetX
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

case("eine Abweichung <= 2 px wird nicht korrigiert", function()
    local state, rs, pred = newPair(2)
    for tick = 0, 9 do pred:advance(0, "play", tick) end

    local mine = pred:predictedAt(9)
    local corrected = pred:reconcile(snapWith(2, mine.x + 1.5, mine.y, 9), false)

    assertEq(corrected, false, "1,5 px sind keine Korrektur")
    assertEq(pred.corrections, 0, "und werden nicht gezaehlt")
    assertEq(pred.offsetX, 0, "kein Versatz")
end)

case("verglichen wird gegen den Eingabetick, nicht gegen die Gegenwart", function()
    -- Der Fall, der ohne `ackInputTick` jeden Lauf als Fehler meldet: Der
    -- Gast ist zehn Ticks weiter als der Snapshot. Die Vorhersage ist
    -- richtig -- sie darf nichts korrigieren.
    -- Kurz halten: Spieler 2 steht nach rund 15 Ticks an der Netzgrenze, und
    -- ein stehender Blob driftet nicht.
    local state, rs, pred = newPair(2)
    for tick = 0, 11 do pred:advance(Frame.LEFT, "play", tick) end

    local old = pred:predictedAt(1)
    local drift = math.abs(pred.blob.x - old.x)
    assertTrue(drift > Prediction.THRESHOLD,
        "der Blob ist seit Tick 1 weitergelaufen (" .. string.format("%.1f", drift) .. " px)")

    local corrected = pred:reconcile(snapWith(2, old.x, old.y, 1), false)
    assertEq(corrected, false, "ein alter, aber richtiger Snapshot korrigiert nicht")
    assertEq(pred.corrections, 0, "und zaehlt nicht")
end)

case("ein stehender ackInputTick wird uebersprungen", function()
    -- Der Host hat die letzte Maske wiederholt (§7). Er hat mit einer
    -- Eingabe gerechnet, die der Gast nie geschickt hat -- ein Vergleich
    -- meldete einen Fehler, den niemand gemacht hat.
    local state, rs, pred = newPair(2)
    for tick = 0, 19 do pred:advance(Frame.LEFT, "play", tick) end

    local mine = pred:predictedAt(15)
    pred:reconcile(snapWith(2, mine.x, mine.y, 15), false)
    local skippedBefore = pred.skipped

    local corrected = pred:reconcile(snapWith(2, mine.x + 50, mine.y, 15), false)
    assertEq(corrected, false, "derselbe Ack wird nicht zweimal ausgewertet")
    assertEq(pred.skipped, skippedBefore + 1, "und als uebersprungen gezaehlt")
    assertEq(pred.corrections, 0, "kein Fehlalarm")
end)

case("eine Uebernahme nach dem Punkt zaehlt nicht als Korrektur", function()
    local state, rs, pred = newPair(2)
    for tick = 0, 19 do pred:advance(Frame.LEFT, "play", tick) end

    local target = World.SERVE_X[2]
    pred:reconcile(snapWith(2, target, rs.blobGroundY, 19), true)

    assertEq(pred.corrections, 0, "Korrekturzaehler bleibt bei null")
    assertEq(pred.takeovers, 1, "die Uebernahme wird getrennt gezaehlt")
    assertEq(pred.blob.x, target, "die Position ist sofort da")
    assertEq(pred.offsetX, 0, "und wird nicht weich nachgefahren")
end)

case("nach der Korrektur findet der naechste Snapshot nichts mehr", function()
    -- Ohne das Mitziehen des Ringpuffers wuerde dieselbe Abweichung ein
    -- zweites Mal gefunden und ein zweites Mal korrigiert.
    local state, rs, pred = newPair(1)
    for tick = 0, 19 do pred:advance(Frame.RIGHT, "play", tick) end

    local at15 = pred:predictedAt(15)
    pred:reconcile(snapWith(1, at15.x + 9, at15.y, 15), false)
    assertEq(pred.corrections, 1, "einmal korrigiert")

    local at18 = pred:predictedAt(18)
    local corrected = pred:reconcile(snapWith(1, at18.x, at18.y, 18), false)
    assertEq(corrected, false, "der naechste Vergleich ist sauber")
    assertEq(pred.corrections, 1, "kein zweites Mal")
end)

case("die Netzgrenze haelt auch in der Vorhersage", function()
    local state, rs, pred = newPair(1)
    for tick = 0, 179 do pred:advance(Frame.RIGHT, "play", tick) end

    local maxX = World.NET_X - rs.blobRadius
    assertNear(pred.blob.x, maxX, 1e-9, "Spieler 1 steht am Netz")

    local state2, rs2, pred2 = newPair(2)
    for tick = 0, 179 do pred2:advance(Frame.LEFT, "play", tick) end
    local minX = World.NET_X + World.NET_WIDTH + rs2.blobRadius
    assertNear(pred2.blob.x, minX, 1e-9, "Spieler 2 steht am Netz")
end)

case("classic ohne Dash sagt auch ohne Dash vorher", function()
    -- ADR-006: im Vanilla-Regelwerk ist der Dash aus. Die Vorhersage darf
    -- ihn nicht trotzdem ausfuehren -- sonst rutscht der Gast bei jedem
    -- Tastendruck weg und wird zurueckgeholt.
    local state, rs, pred = newPair(1, "classic")
    local events = {}

    for tick = 0, 59 do
        local mask = Frame.RIGHT + Frame.DASH
        Step.tick(state, mask, 0, rs, events)
        pred:advance(mask, state.match.phase, tick)
        assertNear(pred.blob.x, state.blobs[1].x, 1e-4, "x bei Tick " .. tick)
    end
    assertEq(pred.blob.cooldownTimer, 0, "kein Cooldown, weil kein Dash")
end)

return T
