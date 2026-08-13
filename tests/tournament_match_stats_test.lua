-- ============================================================================
-- tests/tournament_match_stats_test.lua -- Ebene B: die zwei Zahlen aus der
-- Simulation (M4-09, `05_TOURNAMENT` §11)
--
-- Gefahren wird mit der echten Simulation, nicht mit einer erfundenen Tabelle:
-- Der Beobachter liest Felder, die es in `src/sim/state.lua` gibt, und ein
-- Test gegen eine Attrappe wuerde genau den Fall verfehlen, in dem eines davon
-- umbenannt wird.
--
-- love-frei.
-- ============================================================================

local State      = require("src.sim.state")
local Step       = require("src.sim.step")
local Ruleset    = require("src.sim.ruleset")
local MatchStats = require("src.tournament.match_stats")
local H          = require("tests.tournament_helper")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local assertEq, assertTrue = H.assertEq, H.assertTrue
local assertNear = H.assertNear

local DT = 1 / 60

local function newPlay()
    local rs = Ruleset.new("classic")
    local s = State.new(rs)
    s.match.phase = "play"
    s.match.inProgress = true
    return s, rs
end

case("ausserhalb von `play` wird nichts gemessen", function()
    local s, rs = newPlay()
    s.match.phase = "serve"
    s.ball.vx, s.ball.vy = 900, 0
    s.rally.timer = 30

    local st = MatchStats.new()
    st:observe(s)
    assertEq(st.longestRally, 0, "keine Rallye")
    assertEq(st.fastestBall, 0, "kein Ball")
end)

case("die laengste Rallye ist das Maximum ueber alle Ticks", function()
    local s = newPlay()
    local st = MatchStats.new()

    -- Ein langer Ballwechsel, dann ein Ruecksetzer, dann ein kurzer.
    for i = 1, 40 do
        s.rally.timer = i * DT
        st:observe(s)
    end
    s.rally.timer = 0
    for i = 1, 10 do
        s.rally.timer = i * DT
        st:observe(s)
    end

    assertNear(st.longestRally, 40 * DT, 1e-9, "der lange Ballwechsel zaehlt")
end)

case("der schnellste Ball gehoert dem, der ihn zuletzt beruehrt hat", function()
    local s = newPlay()
    local st = MatchStats.new()

    s.rally.lastTouchPlayer = 1
    s.ball.vx, s.ball.vy = 300, 400        -- 500
    st:observe(s)
    assertNear(st.fastestBall, 500, 1e-6, "erster Wert")
    assertEq(st.fastestBy, 1, "Spieler 1")

    s.rally.lastTouchPlayer = 2
    s.ball.vx, s.ball.vy = 600, 800        -- 1000
    st:observe(s)
    assertNear(st.fastestBall, 1000, 1e-6, "schneller")
    assertEq(st.fastestBy, 2, "Spieler 2")

    -- Langsamer aendert nichts -- auch nicht die Zuordnung.
    s.rally.lastTouchPlayer = 1
    s.ball.vx, s.ball.vy = 30, 40
    st:observe(s)
    assertNear(st.fastestBall, 1000, 1e-6, "Maximum bleibt")
    assertEq(st.fastestBy, 2, "und der Urheber auch")
end)

-- Ein Ball, den niemand angefasst hat, gehoert niemandem. Wuerde er dem
-- letzten Beruehrer des VORIGEN Ballwechsels zugeschrieben, stuende bei der
-- Siegerehrung ein Schlag, den es nicht gab.
case("ein unberuehrter Ball gehoert niemandem", function()
    local s = newPlay()
    local st = MatchStats.new()
    s.rally.lastTouchPlayer = 0
    s.ball.vx, s.ball.vy = 0, 700
    st:observe(s)

    assertNear(st.fastestBall, 700, 1e-6, "gemessen wird trotzdem")
    assertEq(st.fastestBy, 0, "aber niemandem zugeschrieben")
end)

-- Der eigentliche Punkt dieser Suite: Der Beobachter laeuft an der ECHTEN
-- Simulation und fasst sie nicht an.
case("die Simulation bleibt vom Beobachter unberuehrt", function()
    local rs = Ruleset.new("classic")
    local a, b = State.new(rs), State.new(rs)
    a.match.phase, b.match.phase = "play", "play"

    local st = MatchStats.new()
    for tick = 1, 300 do
        Step.tick(a, 0, 0, rs)
        Step.tick(b, 0, 0, rs)
        st:observe(a)
    end

    -- Feld fuer Feld waere zu viel; die Groessen, an denen sich eine
    -- Beeinflussung zeigen wuerde, reichen.
    assertEq(a.ball.x, b.ball.x, "Ball x")
    assertEq(a.ball.y, b.ball.y, "Ball y")
    assertEq(a.ball.vy, b.ball.vy, "Ball vy")
    assertEq(a.rally.timer, b.rally.timer, "Rallye-Uhr")
    assertEq(a.match.score[1], b.match.score[1], "Punktestand")
end)

case("ein echter Lauf liefert plausible Zahlen und einen Bericht", function()
    local rs = Ruleset.new("classic")
    local s = State.new(rs)
    s.match.phase = "play"

    local st = MatchStats.new()
    for tick = 1, 600 do
        Step.tick(s, 0, 0, rs)
        st:observe(s)
    end

    assertTrue(st.longestRally > 0, "es wurde gespielt")
    assertTrue(st.fastestBall > 0, "der Ball hat sich bewegt")
    -- Die Simulation deckelt bei `maxBallSpeed`; schneller kann sie nicht
    -- messen, und langsamer als null auch nicht.
    assertTrue(st.fastestBall <= rs.maxBallSpeed + 1e-6, "unter dem Deckel")

    local report = st:toReport()
    assertNear(report.longestRally, st.longestRally, 1e-9, "Bericht Rallye")
    assertNear(report.fastestBall, st.fastestBall, 1e-9, "Bericht Ball")
end)

case("reset setzt alle drei Werte zurueck", function()
    local st = MatchStats.new()
    st.longestRally, st.fastestBall, st.fastestBy = 40, 900, 2
    st:reset()
    assertEq(st.longestRally, 0, "Rallye")
    assertEq(st.fastestBall, 0, "Ball")
    assertEq(st.fastestBy, 0, "Urheber")
end)

return T
