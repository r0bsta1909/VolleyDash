-- ============================================================================
-- tests/snapshot_test.lua -- Ebene B: Zustand <-> Snapshot (M2-01)
--
-- Der Kern dieser Datei ist der Fall "Phasen vollstaendig": Fassung 1.0 der
-- Netcode-Spec kodierte zwei Phasen, die es nicht gibt, und liess zwei echte
-- weg (W-02 aus Handoff CC-03). Ein Encoder merkt so etwas nicht -- er
-- schreibt eine Null und der Client zeigt etwas anderes an als der Host
-- spielt. Der Test hier faehrt die Simulation durch alle Phasen, die sie
-- wirklich erreicht, und vergleicht die Menge mit der Kodiertabelle.
--
-- love-frei.
-- ============================================================================

local Snapshot = require("src.net.snapshot")
local State    = require("src.sim.state")
local Step     = require("src.sim.step")
local Rules    = require("src.sim.rules")
local Ruleset  = require("src.sim.ruleset")
local Frame    = require("src.input.frame")
local World    = require("src.sim.world")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local function assertEq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: erwartet %s, war %s",
            what or "Wert", tostring(expected), tostring(actual)), 2)
    end
end
local function assertTrue(v, what) assertEq(not not v, true, what) end
local function assertFalse(v, what) assertEq(not not v, false, what) end
local function assertNear(actual, expected, tol, what)
    if math.abs(actual - expected) > tol then
        error(string.format("%s: erwartet %s +-%s, war %s",
            what or "Wert", tostring(expected), tostring(tol), tostring(actual)), 2)
    end
end

local function newWorld()
    local rs = Ruleset.new("prototype")
    return State.new(rs), rs
end

-- ---------------------------------------------------------------------------
-- Phasen -- die eigentliche Absicherung gegen W-02
-- ---------------------------------------------------------------------------

case("die Kodiertabelle deckt genau die Phasen ab, die die Simulation erreicht", function()
    local state, rs = newWorld()
    local events = {}
    local seen = { [state.match.phase] = true }   -- State.new startet in "menu"

    -- serve
    Rules.resetBall(state, rs, 1, events)
    seen[state.match.phase] = true

    -- play: der Aufschlaeger schlaegt den Ball an. Die Phase wechselt beim
    -- ersten Blob-Ball-Kontakt (physics.lua:173).
    state.rally.serveTimer = 2.0
    state.blobs[1].x = state.ball.x
    state.blobs[1].y = state.ball.y + rs.blobRadius
    for _ = 1, 30 do
        Step.tick(state, Frame.JUMP, 0, rs, events)
        seen[state.match.phase] = true
        if state.match.phase == "play" then break end
    end

    -- gameover: ein Punkt bei erreichtem Satzstand
    state.match.phase = "play"
    state.match.servingPlayer = 1
    state.match.score[1] = rs.targetScore - 1
    Rules.awardPointTo(state, rs, 1, events)
    seen[state.match.phase] = true

    for phase in pairs(seen) do
        assertTrue(Snapshot.PHASE_CODE[phase] ~= nil,
            "Phase '" .. tostring(phase) .. "' hat keinen Code -- 04_NETCODE §6 nachziehen")
    end
    for phase in pairs(Snapshot.PHASE_CODE) do
        assertTrue(seen[phase] ~= nil,
            "Code fuer Phase '" .. phase .. "', die die Simulation nie erreicht")
    end
end)

case("die Phasenkodierung ist umkehrbar eindeutig", function()
    local count = 0
    for name, code in pairs(Snapshot.PHASE_CODE) do
        assertEq(Snapshot.PHASE_NAME[code], name, "Rueckabbildung von " .. name)
        count = count + 1
    end
    assertEq(count, 4, "Zahl der Phasen")
end)

case("eine unbekannte Phase bricht ab, statt still eine Null zu senden", function()
    local state, rs = newWorld()
    state.match.phase = "setover"   -- aus der alten Spec, gibt es nicht
    local ok = pcall(Snapshot.from, state, 0, -1, rs)
    assertFalse(ok, "from() muss werfen")
end)

case("ein Snapshot mit unbekanntem Phasenwert wird verworfen", function()
    local state, rs = newWorld()
    local snap = Snapshot.from(state, 0, -1, rs)
    snap.phase = 9
    local ok, err = Snapshot.apply(snap, state, rs)
    assertFalse(ok, "apply() muss ablehnen")
    assertTrue(err ~= nil, "Grund im Klartext")
end)

-- ---------------------------------------------------------------------------
-- Feldliste
-- ---------------------------------------------------------------------------

case("die Feldliste ergibt 69 Byte Nutzlast (04_NETCODE 6)", function()
    local size = { i4 = 4, f = 4, B = 1 }
    local total = 0
    for _, field in ipairs(Snapshot.FIELDS) do
        local bytes = size[field[2]]
        assertTrue(bytes ~= nil, "unbekannter Typ " .. tostring(field[2]))
        total = total + bytes
    end
    assertEq(total, Snapshot.SIZE, "Nutzlast")
    assertEq(total, 69, "Nutzlast gegen die Spec")
end)

case("jedes Feld der Liste wird von from() auch gefuellt", function()
    local state, rs = newWorld()
    local snap = Snapshot.from(state, 7, 3, rs)
    for _, field in ipairs(Snapshot.FIELDS) do
        assertTrue(snap[field[1]] ~= nil, "Feld " .. field[1] .. " fehlt")
    end
end)

-- ---------------------------------------------------------------------------
-- Hin und zurueck
-- ---------------------------------------------------------------------------

case("from/apply erhaelt alles, was der Client zeichnet", function()
    local source, rs = newWorld()
    source.ball.x, source.ball.y = 123.5, 234.25
    source.ball.vx, source.ball.vy = -50.5, 12.25
    source.ball.rotation = 1.5
    source.blobs[1].x, source.blobs[1].y, source.blobs[1].vy = 100.5, 480.25, -3.5
    source.blobs[2].x, source.blobs[2].y, source.blobs[2].vy = 700.5, 500.0, 0
    source.blobs[1].tiltAngle, source.blobs[2].tiltAngle = 0.6, -0.6
    source.match.score[1], source.match.score[2] = 7, 9
    source.match.servingPlayer = 2
    source.match.phase = "play"
    source.rally.touchCount, source.rally.lastTouchPlayer = 2, 1

    local snap = Snapshot.from(source, 42, 41, rs)
    local target = State.new(rs)
    assertTrue(Snapshot.apply(snap, target, rs), "apply")

    assertEq(target.ball.x, 123.5, "ballX")
    assertEq(target.ball.y, 234.25, "ballY")
    assertEq(target.ball.vx, -50.5, "ballVX")
    assertEq(target.ball.rotation, 1.5, "ballRot")
    assertEq(target.blobs[1].x, 100.5, "blob1X")
    assertEq(target.blobs[2].y, 500.0, "blob2Y")
    assertEq(target.blobs[1].vy, -3.5, "blob1VY")
    assertEq(target.blobs[1].tiltAngle, 0.6, "blob1Tilt")
    assertEq(target.blobs[2].tiltAngle, -0.6, "blob2Tilt")
    assertEq(target.match.score[1], 7, "scoreA")
    assertEq(target.match.score[2], 9, "scoreB")
    assertEq(target.match.servingPlayer, 2, "servingPlayer")
    assertEq(target.match.phase, "play", "phase")
    assertEq(target.rally.touchCount, 2, "touchCount")
    assertEq(target.rally.lastTouchPlayer, 1, "lastTouchPlayer")
    assertEq(snap.tick, 42, "tick")
    assertEq(snap.ackInputTick, 41, "ackInputTick")
end)

case("das Netz kommt aus dem Ruleset, nicht aus dem Snapshot", function()
    local source, rs = newWorld()
    local snap = Snapshot.from(source, 0, -1, rs)
    local target = State.new(rs)
    target.net.h = 1   -- kaputt gemacht
    Snapshot.apply(snap, target, rs)
    assertEq(target.net.h, rs.netHeight, "netHeight")
    assertEq(target.net.y, (rs.blobGroundY or 500) - rs.netHeight, "netY")
    assertEq(target.ball.radius, rs.ballRadius, "ballRadius")
end)

-- ---------------------------------------------------------------------------
-- Flags
-- ---------------------------------------------------------------------------

case("Bodenkontakt und Dash stehen in den Flags", function()
    local source, rs = newWorld()
    source.blobs[1].isGrounded, source.blobs[2].isGrounded = true, false
    source.blobs[1].dashTimer, source.blobs[2].dashTimer = 0, 0.1

    local snap = Snapshot.from(source, 0, -1, rs)
    local target = State.new(rs)
    Snapshot.apply(snap, target, rs)

    assertTrue(target.blobs[1].isGrounded, "blob1 am Boden")
    assertFalse(target.blobs[2].isGrounded, "blob2 in der Luft")
    assertEq(target.blobs[1].dashTimer, 0, "blob1 dasht nicht")
    assertTrue(target.blobs[2].dashTimer > 0, "blob2 dasht")
end)

case("der Fehlerwurf reist in den Flags mit -- er ist keine Phase", function()
    local source, rs = newWorld()
    source.match.phase = "play"
    source.rally.faultTimer, source.rally.faultPlayer = 0.75, 2

    local snap = Snapshot.from(source, 0, -1, rs)
    assertEq(snap.phase, Snapshot.PHASE_CODE.play, "Phase bleibt play")

    local target = State.new(rs)
    Snapshot.apply(snap, target, rs)
    assertEq(target.rally.faultPlayer, 2, "faultPlayer")
    assertTrue(target.rally.faultTimer > 0, "faultTimer sichtbar")
end)

case("ohne laufenden Fehler ist faultPlayer 0", function()
    local source, rs = newWorld()
    source.rally.faultTimer, source.rally.faultPlayer = 0, 2
    local snap = Snapshot.from(source, 0, -1, rs)
    local target = State.new(rs)
    Snapshot.apply(snap, target, rs)
    assertEq(target.rally.faultPlayer, 0, "faultPlayer")
    assertEq(target.rally.faultTimer, 0, "faultTimer")
end)

case("ein gesetztes reserviertes Flag-Bit macht den Snapshot ungueltig", function()
    local state, rs = newWorld()
    local snap = Snapshot.from(state, 0, -1, rs)
    snap.flags = snap.flags + 64
    local ok = Snapshot.apply(snap, state, rs)
    assertFalse(ok, "apply() muss ablehnen")
end)

case("die negative Null wird begradigt (T-N-07, CI-Lauf 13)", function()
    local source, rs = newWorld()
    -- Genau der Weg aus physics.lua:124 bei stehendem Ball.
    source.ball.vx = -math.abs(0.0) * 0.8
    source.ball.vy = -0.0
    source.blobs[1].vy = -(0.0)

    local snap = Snapshot.from(source, 0, -1, rs)

    -- Unter Windows waeren das negative Nullen, unter macOS positive. Nach der
    -- Begradigung ist es auf beiden Seiten dieselbe -- sonst meldete die
    -- Pruefsumme aus §9 in jedem stillen Tick einen Unterschied.
    assertEq(snap.ballVX, 0, "Wert")
    assertTrue(1 / snap.ballVX > 0, "positive Null bei ballVX")
    assertTrue(1 / snap.ballVY > 0, "positive Null bei ballVY")
    assertTrue(1 / snap.blob1VY > 0, "positive Null bei blob1VY")
end)

case("die Begradigung laesst alle anderen Werte unberuehrt", function()
    local source, rs = newWorld()
    source.ball.vx, source.ball.vy = -123.5, 0.25
    source.blobs[1].tiltAngle = -0.6

    local snap = Snapshot.from(source, 0, -1, rs)
    assertEq(snap.ballVX, -123.5, "negativ bleibt negativ")
    assertEq(snap.ballVY, 0.25, "positiv bleibt positiv")
    assertEq(snap.blob1Tilt, -0.6, "Neigung")
end)

-- ---------------------------------------------------------------------------
-- Quantisierung
-- ---------------------------------------------------------------------------

case("der Dash-Cooldown geht als Verhaeltnis in einem Byte", function()
    local source, rs = newWorld()
    local target = State.new(rs)

    source.blobs[1].cooldownTimer = 0
    source.blobs[2].cooldownTimer = rs.dashCooldown
    local snap = Snapshot.from(source, 0, -1, rs)
    assertEq(snap.blob1Cd, 0, "leer")
    assertEq(snap.blob2Cd, 255, "voll")
    Snapshot.apply(snap, target, rs)
    assertEq(target.blobs[1].cooldownTimer, 0, "leer zurueck")
    assertEq(target.blobs[2].cooldownTimer, rs.dashCooldown, "voll zurueck")

    source.blobs[1].cooldownTimer = rs.dashCooldown / 2
    snap = Snapshot.from(source, 0, -1, rs)
    Snapshot.apply(snap, target, rs)
    -- Ein Byte ueber die volle Spanne: der Fehler liegt unter einem 255stel.
    assertNear(target.blobs[1].cooldownTimer, rs.dashCooldown / 2,
        rs.dashCooldown / 255, "halb")
end)

case("ein ueberzogener Cooldown laeuft nicht ueber", function()
    local source, rs = newWorld()
    source.blobs[1].cooldownTimer = rs.dashCooldown * 10
    local snap = Snapshot.from(source, 0, -1, rs)
    assertEq(snap.blob1Cd, 255, "gedeckelt")
end)

-- ---------------------------------------------------------------------------
-- Ein echter Ballwechsel
-- ---------------------------------------------------------------------------

case("ein simulierter Ballwechsel ueberlebt Tick fuer Tick den Umweg", function()
    local source, rs = newWorld()
    local target = State.new(rs)
    local events = {}

    Rules.resetBall(source, rs, 1, events)
    source.rally.serveTimer = 2.0
    -- Aufschlag: den Blob an den Ball setzen, sonst bleibt der Lauf in der
    -- Aufschlagphase stehen und prueft nichts.
    source.blobs[1].x = source.ball.x
    source.blobs[1].y = source.ball.y + rs.blobRadius

    local sawPlay, sawTouch, sawFlight = false, false, false

    for tick = 1, 240 do
        -- Tick 1 ist ein Sprung: der Blob muss sich AUF den Ball zu bewegen,
        -- sonst schiebt ihn die Kollisionsaufloesung nur weg und die Phase
        -- bleibt auf "serve" (physics.lua:164).
        Step.tick(source, tick % 7 == 1 and Frame.JUMP or Frame.RIGHT,
                  tick % 5 == 0 and Frame.LEFT or 0, rs, events)
        local snap = Snapshot.from(source, tick, tick - 1, rs)
        local ok, err = Snapshot.apply(snap, target, rs)
        assertTrue(ok, "Tick " .. tick .. ": " .. tostring(err))
        assertEq(target.ball.x, source.ball.x, "ballX in Tick " .. tick)
        assertEq(target.ball.y, source.ball.y, "ballY in Tick " .. tick)
        assertEq(target.match.phase, source.match.phase, "phase in Tick " .. tick)
        assertEq(target.match.score[1], source.match.score[1], "scoreA in Tick " .. tick)
        assertEq(target.rally.touchCount, source.rally.touchCount,
            "touchCount in Tick " .. tick)

        if source.match.phase == "play" then sawPlay = true end
        if source.rally.touchCount > 0 then sawTouch = true end
        if source.ball.x ~= World.SERVE_X[1] then sawFlight = true end
    end

    -- Ein Lauf, in dem nichts geschieht, prueft nichts.
    assertTrue(sawPlay, "der Ball war nie im Spiel")
    assertTrue(sawTouch, "der Ball wurde nie beruehrt")
    assertTrue(sawFlight, "der Ball hat die Aufschlagstelle nie verlassen")
end)

return T
