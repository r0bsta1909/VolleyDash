-- ============================================================================
-- tests/rules_test.lua -- Ebene B: Satzende und Rallye-Timeout (M0-10)
--
-- Deckt T-R-09 bis T-R-13 aus `07_TEST_PLAN` §3 ab. Reines Lua, kein love.
-- ============================================================================

local Ruleset = require("src.sim.ruleset")
local State   = require("src.sim.state")
local Rules   = require("src.sim.rules")
local Step    = require("src.sim.step")
local World   = require("src.sim.world")

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

-- Punktestand setzen und den Aufschlaeger punkten lassen. Gibt die Phase
-- nach dem Punkt zurueck.
local function scoreAndAward(rs, mine, theirs, winner)
    local state = State.new(rs)
    winner = winner or 1
    local other = winner == 1 and 2 or 1
    state.match.score[winner] = mine
    state.match.score[other] = theirs
    state.match.servingPlayer = winner   -- nur der Aufschlaeger punktet
    state.match.phase = "play"
    Rules.awardPointTo(state, rs, winner, {})
    return state
end

-- ---------------------------------------------------------------------------
-- T-R-09 bis T-R-12: Satzende (B-05, E-09)
-- ---------------------------------------------------------------------------

case("T-R-09: 14:13 plus Punkt = 15:13, Satz beendet", function()
    local rs = Ruleset.new("classic")
    local state = scoreAndAward(rs, 14, 13)
    assertEq(state.match.score[1], 15, "Punktestand")
    assertEq(state.match.phase, "gameover", "Satz beendet")
end)

case("T-R-10: 15:14 beendet den Satz NICHT (B-05)", function()
    local rs = Ruleset.new("classic")
    local state = scoreAndAward(rs, 14, 14)
    assertEq(state.match.score[1], 15, "Punktestand")
    assertEq(state.match.phase, "serve", "Satz laeuft weiter")
end)

case("T-R-11: 16:14 beendet den Satz", function()
    local rs = Ruleset.new("classic")
    local state = scoreAndAward(rs, 15, 14)
    assertEq(state.match.score[1], 16, "Punktestand")
    assertEq(state.match.phase, "gameover", "Satz beendet")
end)

case("T-R-12: 21:20 beendet den Satz bei deuceCap = 21 (E-09)", function()
    local rs = Ruleset.new("classic")
    assertEq(rs.deuceCap, 21, "Deckel")
    local state = scoreAndAward(rs, 20, 20)
    assertEq(state.match.score[1], 21, "Punktestand")
    assertEq(state.match.phase, "gameover", "Deckel greift ohne zwei Punkte Vorsprung")
end)

case("kurz vor dem Deckel gilt weiter der Zwei-Punkte-Vorsprung", function()
    local rs = Ruleset.new("classic")
    assertEq(scoreAndAward(rs, 19, 19).match.phase, "serve", "20:19 laeuft weiter")
end)

case("isSetWon direkt: die Regelmatrix aus 01_GDD 3.1", function()
    local rs = Ruleset.new("classic")
    assertTrue(Rules.isSetWon(rs, 15, 13), "15:13")
    assertFalse(Rules.isSetWon(rs, 15, 14), "15:14")
    assertTrue(Rules.isSetWon(rs, 16, 14), "16:14")
    assertFalse(Rules.isSetWon(rs, 14, 0), "14:0")
    assertTrue(Rules.isSetWon(rs, 21, 20), "21:20 ueber den Deckel")
end)

case("das Preset prototype behaelt das alte Verhalten (B-05 unkorrigiert)", function()
    local rs = Ruleset.new("prototype")
    assertFalse(rs.twoPointLead, "kein Zwei-Punkte-Vorsprung")
    assertTrue(Rules.isSetWon(rs, 15, 14), "15:14 beendet den Satz wie im Prototyp")
end)

case("der Nicht-Aufschlaeger bekommt keinen Punkt, nur den Aufschlag", function()
    local rs = Ruleset.new("classic")
    local state = State.new(rs)
    state.match.servingPlayer = 1
    state.match.phase = "play"
    Rules.awardPointTo(state, rs, 2, {})
    assertEq(state.match.score[2], 0, "kein Punkt")
    assertEq(state.match.servingPlayer, 2, "Aufschlagwechsel")
end)

-- ---------------------------------------------------------------------------
-- T-R-13: Rallye-Timeout (GDD P5)
-- ---------------------------------------------------------------------------

local function playingState(rs)
    local state = State.new(rs)
    state.match.phase = "play"
    state.match.servingPlayer = 1
    -- Ball in der Luft ueber der eigenen Seite, damit er waehrend des Tests
    -- nicht zu Boden geht.
    state.ball.x, state.ball.y = World.SERVE_X[1], 100
    state.ball.vx, state.ball.vy = 0, 0
    return state
end

case("T-R-13: nach 30 s ohne Punkt bekommt der Nicht-Aufschlaeger den Ball", function()
    local rs = Ruleset.new("classic")
    assertEq(rs.rallyTimeout, 30, "Timeout aus dem Preset")

    -- Der Ball haelt sich keine 30 s in der Luft; die Uhr wird deshalb kurz
    -- vor den Ablauf gestellt. Geprueft wird die Regel, nicht die Flugbahn.
    local state = playingState(rs)
    state.rally.timer = rs.rallyTimeout - World.TICK_DT / 2

    local events = Step.tick(state, 0, 0, rs, {})
    local fired = false
    for _, e in ipairs(events) do
        if e.type == "rally_timeout" then fired = true end
    end

    assertTrue(fired, "Timeout ausgeloest")
    assertEq(state.match.servingPlayer, 2, "Aufschlagwechsel an den Empfaenger")
    assertEq(state.match.score[1], 0, "kein Punkt fuer den Aufschlaeger")
    assertEq(state.match.score[2], 0, "und keiner fuer den Empfaenger")
    assertEq(state.match.phase, "serve", "neuer Aufschlag")
end)

case("der Timer laeuft nur waehrend des Spiels", function()
    local rs = Ruleset.new("classic")
    local state = State.new(rs)
    state.match.phase = "serve"
    local events = {}
    for _ = 1, 120 do Step.tick(state, 0, 0, rs, events) end
    assertEq(state.rally.timer, 0, "im Aufschlag laeuft nichts")
end)

case("ein neuer Ballwechsel setzt den Timer zurueck", function()
    local rs = Ruleset.new("classic")
    local state = playingState(rs)
    local events = {}
    for _ = 1, 30 do Step.tick(state, 0, 0, rs, events) end
    assertTrue(state.rally.timer > 0.4, "Timer laeuft")
    Rules.resetBall(state, rs, 1, {})
    assertEq(state.rally.timer, 0, "zurueckgesetzt")
end)

case("rallyTimeout = 0 schaltet die Regel ab (Preset prototype)", function()
    local rs = Ruleset.new("prototype")
    assertEq(rs.rallyTimeout, 0, "aus")

    local state = playingState(rs)
    state.rally.timer = 999   -- weit ueber jedem denkbaren Limit

    local events = Step.tick(state, 0, 0, rs, {})
    for _, e in ipairs(events) do
        assertTrue(e.type ~= "rally_timeout", "kein Timeout im Prototyp-Preset")
    end
    assertEq(state.match.phase, "play", "Ballwechsel laeuft weiter")
    assertEq(state.match.servingPlayer, 1, "kein Aufschlagwechsel")
end)

-- ---------------------------------------------------------------------------
-- T-R-01 bis T-R-08: Punktevergabe und Beruehrungszaehler (M0-13)
--
-- Diese Faelle laufen durch die ganze Simulation, nicht nur durch Rules:
-- der Zaehler haengt an der Kollision, und genau dieses Zusammenspiel soll
-- geprueft werden.
-- ---------------------------------------------------------------------------

-- Ball frei in der Luft, Blobs auf ihren Aufschlagpositionen, Phase play.
local function inPlay(rs, ballX, ballY, vx, vy)
    local state = State.new(rs)
    state.match.phase = "play"
    state.match.inProgress = true
    state.ball.x, state.ball.y = ballX, ballY
    state.ball.vx, state.ball.vy = vx or 0, vy or 0
    state.rally.ballSide = (ballX < World.WIDTH / 2) and 1 or 2
    return state
end

-- Laeuft bis zu `limit` Ticks und sammelt alle Ereignisse ein.
local function run(state, rs, limit, inputs)
    local seen = {}
    local events = {}
    for _ = 1, limit do
        Step.tick(state, inputs and inputs[1] or 0, inputs and inputs[2] or 0, rs, events)
        for _, e in ipairs(events) do seen[#seen + 1] = e end
    end
    return seen
end

local function sawEvent(events, kind)
    for _, e in ipairs(events) do
        if e.type == kind then return e end
    end
    return nil
end

case("T-R-01: Aufschlaeger gewinnt den Ballwechsel -- Punkt, Aufschlag bleibt", function()
    local rs = Ruleset.new("classic")
    local state = inPlay(rs, 700, 400, 0, 200)   -- Ball faellt auf P2s Seite, neben dem Blob
    state.match.servingPlayer = 1

    local events = run(state, rs, 120)
    assertTrue(sawEvent(events, "point") ~= nil, "Punkt vergeben")
    assertEq(state.match.score[1], 1, "Punkt fuer den Aufschlaeger")
    assertEq(state.match.score[2], 0, "kein Punkt fuer den Gegner")
    assertEq(state.match.servingPlayer, 1, "Aufschlag bleibt")
end)

case("T-R-02: Nicht-Aufschlaeger gewinnt -- kein Punkt, Aufschlagwechsel", function()
    local rs = Ruleset.new("classic")
    local state = inPlay(rs, 100, 400, 0, 200)   -- Ball faellt auf P1s Seite, neben dem Blob
    state.match.servingPlayer = 1

    local events = run(state, rs, 120)
    assertTrue(sawEvent(events, "side_out") ~= nil, "Seitenaus")
    assertEq(state.match.score[1], 0, "kein Punkt")
    assertEq(state.match.score[2], 0, "auch nicht fuer den Gewinner")
    assertEq(state.match.servingPlayer, 2, "Aufschlagwechsel")
end)

case("T-R-03: Ball auf dem eigenen Boden ist ein Fehler", function()
    local rs = Ruleset.new("classic")
    local state = inPlay(rs, 100, 400, 0, 200)
    state.match.servingPlayer = 2   -- P2 schlaegt auf, P1 laesst fallen

    local events = run(state, rs, 120)
    assertTrue(sawEvent(events, "ground_hit") ~= nil, "Bodenkontakt")
    assertEq(state.match.score[2], 1, "Punkt fuer die Gegenseite")
    assertEq(state.match.servingPlayer, 2, "Aufschlaeger behaelt ihn")
end)

case("T-R-04/T-R-05: die dritte Beruehrung ist gueltig, die vierte ist ein Fehler", function()
    local rs = Ruleset.new("classic")
    -- Ball direkt ueber dem stehenden Blob: er springt auf dem Kopf und wird
    -- dabei jedes Mal neu gezaehlt.
    local state = inPlay(rs, World.SERVE_X[1], 300, 0, 0)

    local counts = {}
    local faultAt = nil
    local events = {}
    for tick = 1, 600 do
        Step.tick(state, 0, 0, rs, events)
        for _, e in ipairs(events) do
            if e.type == "blob_hit" then counts[#counts + 1] = state.rally.touchCount end
            if e.type == "fault" and not faultAt then faultAt = state.rally.touchCount end
        end
        if faultAt then break end
    end

    assertTrue(#counts >= 4, "mindestens vier Beruehrungen, waren " .. #counts)
    assertEq(counts[1], 1, "erste Beruehrung")
    assertEq(counts[3], 3, "dritte Beruehrung zaehlt weiter")
    assertTrue(faultAt ~= nil, "Fehler ausgeloest")
    assertEq(faultAt, 4, "erst die vierte Beruehrung ist der Fehler")
end)

case("T-R-06: Seitenwechsel des Balls setzt den Zaehler zurueck", function()
    local rs = Ruleset.new("classic")
    local state = inPlay(rs, 380, 200, 600, 0)
    state.rally.touchCount, state.rally.lastTouchPlayer = 2, 1
    state.rally.ballSide = 1

    run(state, rs, 5)
    assertTrue(state.ball.x > World.WIDTH / 2, "Ball hat die Mitte ueberquert")
    assertEq(state.rally.ballSide, 2, "Seite gewechselt")
    assertEq(state.rally.touchCount, 0, "Zaehler zurueckgesetzt")
    assertEq(state.rally.lastTouchPlayer, 0, "kein letzter Beruehrer mehr")
end)

case("T-R-07: eine Wandberuehrung zaehlt nicht als Beruehrung", function()
    local rs = Ruleset.new("classic")
    local state = inPlay(rs, 60, 200, -600, 0)

    local events = run(state, rs, 20)
    assertTrue(sawEvent(events, "wall_hit") ~= nil, "Wandkontakt")
    assertEq(state.rally.touchCount, 0, "Zaehler unveraendert")
    assertEq(state.rally.lastTouchPlayer, 0, "kein Beruehrer")
end)

case("T-R-08: eine Netzberuehrung zaehlt nicht als Beruehrung (GDD P1)", function()
    local rs = Ruleset.new("classic")
    -- Ball faellt genau auf die Netzkante bei (400, 345).
    local state = inPlay(rs, 400, 200, 0, 200)

    local events = run(state, rs, 60)
    assertTrue(sawEvent(events, "net_hit") ~= nil, "Netzkontakt")
    assertEq(state.rally.touchCount, 0, "Zaehler unveraendert")
end)

return T
