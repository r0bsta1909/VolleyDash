-- ============================================================================
-- tests/snapshot_events_test.lua -- Ebene B: Kosmetik aus Deltas (M3-02)
--
-- Die Erkennung ist eine reine Funktion ueber zwei Snapshots
-- (`04_NETCODE_SPEC` §6). Genau deshalb steht sie hier und nicht in einem
-- Netztest: zwei Snapshots hinein, erwartete Ereignisliste heraus, kein Bild.
--
-- Die Snapshots entstehen dabei NICHT von Hand, sondern aus der laufenden
-- Simulation. Ein handgeschriebener Snapshot prueft nur, ob der Test die
-- eigene Erwartung trifft; ein gefahrener prueft, ob die Ableitung das
-- wiederfindet, was `Step.tick` tatsaechlich gemeldet hat.
--
-- love-frei.
-- ============================================================================

local SnapEvents = require("src.render.snapshot_events")
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

local function has(events, kind)
    for i = 1, #events do
        if events[i].type == kind then return events[i] end
    end
    return nil
end

local function countOf(events, kind)
    local n = 0
    for i = 1, #events do
        if events[i].type == kind then n = n + 1 end
    end
    return n
end

local function newWorld(preset)
    local rs = Ruleset.new(preset or "prototype")
    local state = State.new(rs)
    Rules.resetBall(state, rs, 1, {})
    return state, rs
end

-- Einen Tick fahren und beide Seiten zurueckgeben: was `Step.tick` gemeldet
-- hat, und was die Ableitung aus dem Snapshot-Paar herausholt.
local function stepAndDiff(state, rs, m1, m2, tick, prevSnap)
    local simEvents = {}
    Step.tick(state, m1, m2, rs, simEvents)
    local snap = Snapshot.from(state, tick, tick - 1, rs)
    local derived = SnapEvents.diff(prevSnap, snap, rs)
    return snap, simEvents, derived
end

-- ---------------------------------------------------------------------------
-- Die Grundlage: gleiche Namen wie in der Simulation
-- ---------------------------------------------------------------------------

case("die Ableitung benutzt die Ereignisnamen von Step.tick", function()
    -- Sonst uebersetzt `fx_events.lua` beim Gast ins Leere -- und zwar
    -- still, weil eine unbekannte Ereignisart dort einfach durchfaellt.
    local known = {
        wall_hit = true, net_hit = true, blob_hit = true, land = true,
        jump = true, dash = true, fault = true, point = true,
        side_out = true, match_over = true, rally_reset = true,
        ground_hit = true,
    }

    local state, rs = newWorld()
    local prev = Snapshot.from(state, 0, -1, rs)
    local seen = {}

    state.rally.serveTimer = 2.0
    for tick = 1, 900 do
        local m1 = (tick % 60 < 6) and (Frame.JUMP + Frame.RIGHT) or Frame.RIGHT
        local m2 = (tick % 80 < 8) and (Frame.JUMP + Frame.LEFT) or Frame.LEFT
        local snap, _, derived = stepAndDiff(state, rs, m1, m2, tick, prev)
        for i = 1, #derived do seen[derived[i].type] = true end
        prev = snap
    end

    for kind in pairs(seen) do
        assertTrue(known[kind], "unbekannte Ereignisart: " .. tostring(kind))
    end
    -- Ein Lauf, in dem nichts passiert, prueft nichts.
    assertTrue(seen.blob_hit, "im Lauf kam ein Blobtreffer vor")
    assertTrue(seen.land, "im Lauf kam eine Landung vor")
end)

-- ---------------------------------------------------------------------------
-- Die sechs Ausloeser aus dem Auftrag
-- ---------------------------------------------------------------------------

case("Wandtreffer: Ball am Rand, VX kehrt um", function()
    local state, rs = newWorld()
    state.match.phase = "play"
    state.ball.x = rs.ballRadius + 2
    state.ball.y = 200
    state.ball.vx = -400
    state.ball.vy = 0

    local prev = Snapshot.from(state, 10, 9, rs)
    local snap, sim, derived = stepAndDiff(state, rs, 0, 0, 11, prev)

    assertTrue(has(sim, "wall_hit"), "die Simulation meldet den Wandtreffer")
    assertTrue(has(derived, "wall_hit"), "die Ableitung findet ihn")
end)

case("Netztreffer: Ball am Netzkoerper, Richtung kehrt um", function()
    local state, rs = newWorld()
    state.match.phase = "play"
    state.ball.x = World.NET_X - rs.ballRadius + 2
    state.ball.y = (rs.blobGroundY - rs.netHeight) + 40
    state.ball.vx = 300
    state.ball.vy = 0

    local prev = Snapshot.from(state, 20, 19, rs)
    local snap, sim, derived = stepAndDiff(state, rs, 0, 0, 21, prev)

    assertTrue(has(sim, "net_hit"), "die Simulation meldet den Netztreffer")
    assertTrue(has(derived, "net_hit"), "die Ableitung findet ihn")
end)

case("Blobtreffer: touchCount steigt", function()
    local state, rs = newWorld()
    state.match.phase = "play"
    state.blobs[1].x = 200
    state.ball.x = 200
    state.ball.y = state.blobs[1].y - rs.blobRadius - rs.ballRadius + 4
    state.ball.vy = 300

    local prev = Snapshot.from(state, 30, 29, rs)
    local snap, sim, derived = stepAndDiff(state, rs, 0, 0, 31, prev)

    assertTrue(has(sim, "blob_hit"), "die Simulation meldet die Beruehrung")
    local found = has(derived, "blob_hit")
    assertTrue(found, "die Ableitung findet sie")
    assertEq(found.player, 1, "und weiss, wer angefasst hat")
end)

case("Aufschlag: der Phasenwechsel serve -> play ist ein Blobtreffer", function()
    local state, rs = newWorld()
    state.rally.serveTimer = 2.0
    state.blobs[1].x = state.ball.x
    state.blobs[1].y = state.ball.y + rs.blobRadius

    local prev = Snapshot.from(state, 40, 39, rs)
    local snap, sim, derived = stepAndDiff(state, rs, Frame.JUMP + Frame.RIGHT, 0, 41, prev)

    assertEq(Snapshot.PHASE_NAME[snap.phase], "play", "die Phase ist umgesprungen")
    assertTrue(has(derived, "blob_hit"), "der Aufschlag klingt wie ein Treffer")
end)

case("Landung: isGrounded geht von 0 auf 1", function()
    local state, rs = newWorld()
    state.match.phase = "play"
    state.blobs[2].isGrounded = false
    state.blobs[2].y = rs.blobGroundY - 3
    state.blobs[2].vy = 400

    local prev = Snapshot.from(state, 50, 49, rs)
    local snap, sim, derived = stepAndDiff(state, rs, 0, 0, 51, prev)

    assertTrue(has(sim, "land"), "die Simulation meldet die Landung")
    local found = has(derived, "land")
    assertTrue(found, "die Ableitung findet sie")
    assertEq(found.player, 2, "beim richtigen Spieler")
end)

case("Sprung: isGrounded geht von 1 auf 0", function()
    local state, rs = newWorld()
    state.match.phase = "play"

    local prev = Snapshot.from(state, 60, 59, rs)
    local snap, sim, derived = stepAndDiff(state, rs, Frame.JUMP, 0, 61, prev)

    assertTrue(has(sim, "jump"), "die Simulation meldet den Sprung")
    assertTrue(has(derived, "jump"), "die Ableitung findet ihn")
end)

case("Punkt: der Stand steigt und der Ballwechsel wird neu aufgesetzt", function()
    local state, rs = newWorld()
    state.match.phase = "play"
    state.match.servingPlayer = 1
    -- Ball faellt auf der Seite des Gegners in den Sand: Punkt fuer den
    -- Aufschlaeger. Der Gegner muss dafuer beiseite -- er steht in `State.new`
    -- genau auf der Aufschlagposition und faenge den Ball sonst ab.
    state.blobs[2].x = World.WIDTH - rs.blobRadius
    state.ball.x = World.WIDTH * 0.75
    state.ball.y = (rs.ballGroundY or 520) - rs.ballRadius - 2
    state.ball.vy = 300

    local prev = Snapshot.from(state, 70, 69, rs)
    local snap, sim, derived = stepAndDiff(state, rs, 0, 0, 71, prev)

    assertTrue(has(sim, "point"), "die Simulation vergibt den Punkt")
    assertTrue(has(derived, "point"), "die Ableitung findet ihn")
    assertTrue(has(derived, "ground_hit"),
        "und rekonstruiert den Bodentreffer, den der Snapshot nicht zeigt")
    assertTrue(has(derived, "rally_reset"), "die Sprungstelle wird gemeldet")
    assertTrue(SnapEvents.isTakeover(derived),
        "und gilt der Vorhersage als Uebernahme")
end)

case("Seitenaus: kein Punkt, aber der Aufschlaeger wechselt", function()
    local state, rs = newWorld()
    state.match.phase = "play"
    state.match.servingPlayer = 1
    -- Der Ball faellt auf der EIGENEN Seite -- der Gegner bekommt den
    -- Aufschlag, aber keinen Punkt. Der Aufschlaeger muss dafuer beiseite.
    state.blobs[1].x = rs.blobRadius
    state.ball.x = World.WIDTH * 0.25
    state.ball.y = (rs.ballGroundY or 520) - rs.ballRadius - 2
    state.ball.vy = 300

    local prev = Snapshot.from(state, 80, 79, rs)
    local snap, sim, derived = stepAndDiff(state, rs, 0, 0, 81, prev)

    assertTrue(has(sim, "side_out"), "die Simulation meldet Seitenaus")
    assertTrue(has(derived, "side_out"), "die Ableitung findet es")
    assertEq(countOf(derived, "point"), 0, "und macht keinen Punkt daraus")
end)

case("Fehlerwurf: das Flag wechselt von 0 auf einen Spieler", function()
    local state, rs = newWorld()
    state.match.phase = "play"
    state.rally.touchCount = 3
    state.rally.lastTouchPlayer = 1
    state.blobs[1].x = 200
    state.ball.x = 200
    state.ball.y = state.blobs[1].y - rs.blobRadius - rs.ballRadius + 4
    state.ball.vy = 300

    local prev = Snapshot.from(state, 90, 89, rs)
    local snap, sim, derived = stepAndDiff(state, rs, 0, 0, 91, prev)

    assertTrue(has(sim, "fault"), "die Simulation meldet den Fehler")
    assertTrue(has(derived, "fault"), "die Ableitung findet ihn")
end)

case("Dash: der Cooldown springt von null auf voll", function()
    local state, rs = newWorld()   -- prototype: allowDash = true
    state.match.phase = "play"

    local prev = Snapshot.from(state, 100, 99, rs)
    local snap, sim, derived = stepAndDiff(state, rs, Frame.RIGHT + Frame.DASH, 0, 101, prev)

    assertTrue(has(sim, "dash"), "die Simulation meldet den Dash")
    local found = has(derived, "dash")
    assertTrue(found, "die Ableitung findet ihn")
    assertEq(found.up, false, "und erkennt den Seitwaerts-Dash am Flag")
end)

-- ---------------------------------------------------------------------------
-- Was nicht passieren darf
-- ---------------------------------------------------------------------------

case("zwei gleiche Snapshots ergeben keine Ereignisse", function()
    local state, rs = newWorld()
    local snap = Snapshot.from(state, 5, 4, rs)
    local derived = SnapEvents.diff(snap, snap, rs)
    assertEq(#derived, 0, "ein stehendes Bild staubt nicht")
end)

case("ein rueckwaerts gelesenes Paar ergibt keine Ereignisse", function()
    -- Kanal 1 ist unzuverlaessig; ein vertauschtes Paar darf keinen Punkt
    -- doppelt melden.
    local state, rs = newWorld()
    local a = Snapshot.from(state, 10, 9, rs)
    state.match.score[1] = 3
    local b = Snapshot.from(state, 11, 10, rs)

    assertEq(countOf(SnapEvents.diff(a, b, rs), "point"), 1, "vorwaerts: ein Punkt")
    assertEq(#SnapEvents.diff(b, a, rs), 0, "rueckwaerts: nichts")
end)

case("ohne vorigen Snapshot passiert nichts", function()
    local state, rs = newWorld()
    local snap = Snapshot.from(state, 0, -1, rs)
    assertEq(#SnapEvents.diff(nil, snap, rs), 0, "der erste Snapshot ist stumm")
end)

case("der Seitenwechsel des Balls ist keine Beruehrung", function()
    -- `Rules.updateBallSide` setzt touchCount und lastTouchPlayer auf 0.
    -- Ein Wechsel AUF 0 darf nicht als Treffer durchgehen.
    local state, rs = newWorld()
    state.match.phase = "play"
    state.rally.touchCount = 2
    state.rally.lastTouchPlayer = 1
    local prev = Snapshot.from(state, 110, 109, rs)

    state.rally.touchCount = 0
    state.rally.lastTouchPlayer = 0
    local curr = Snapshot.from(state, 111, 110, rs)

    assertEq(countOf(SnapEvents.diff(prev, curr, rs), "blob_hit"), 0,
        "kein Treffer beim Seitenwechsel")
end)

case("ein Fehlerwurf endet ohne Bodentreffer", function()
    -- Der Ball liegt beim Fehlerwurf in der Luft. Ein Staubaufschlag im
    -- Sand waere sichtbar falsch.
    local state, rs = newWorld()
    state.match.phase = "play"
    state.match.servingPlayer = 1
    state.rally.faultTimer = 0.01
    state.rally.faultPlayer = 2
    state.ball.x = 600
    state.ball.y = 200
    local prev = Snapshot.from(state, 120, 119, rs)

    local snap, sim, derived = stepAndDiff(state, rs, 0, 0, 121, prev)

    assertTrue(has(sim, "point") or has(sim, "side_out"),
        "der Fehlerwurf laeuft ab und wird gewertet")
    assertEq(countOf(derived, "ground_hit"), 0, "aber kein Sand")
end)

return T
