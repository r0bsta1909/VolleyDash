-- ============================================================================
-- tests/replay_test.lua -- Ebene A: Physik-Regression (M0-13, 07_TEST_PLAN §2)
--
-- Das eigentliche Sicherungsnetz aus M0-03, jetzt automatisch: Die
-- aufgezeichneten `InputFrames` werden durch `Step.tick` gefahren und Tick fuer
-- Tick mit den Referenzwerten verglichen.
--
-- Bewertung nach `07_TEST_PLAN` §2:
--   <= 0,5 px ueber die ganze Rallye   bestanden
--   abweichender Ausgang               nicht bestanden
--
-- Bis hierher war der Vergleich Handarbeit (Referenzen neu erzeugen und die
-- Dateien diffen). Ab jetzt macht ihn der Testrunner, ohne Fenster.
-- ============================================================================

local Ruleset    = require("src.sim.ruleset")
local State      = require("src.sim.state")
local Step       = require("src.sim.step")
local ReplayFile = require("tests.replay_file")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local TOLERANCE = 0.5
local RALLIES = { "R-01", "R-02", "R-03", "R-04", "R-05", "R-06",
                  "R-07", "R-08", "R-09", "R-10", "R-11" }

local function fail(fmt, ...)
    error(string.format(fmt, ...), 3)
end

-- Faehrt eine Aufzeichnung durch die Simulation und vergleicht jeden Tick.
local function replay(id)
    local path = "tests/replays/fixed60/" .. id .. ".json"
    local doc, err = ReplayFile.read(path)
    if not doc then fail("%s", tostring(err)) end

    -- Die Aufzeichnung bringt ihr Regelwerk mit; ohne das liefe der Test
    -- gegen die heutige Voreinstellung (M0-09).
    local ruleset = Ruleset.fromSnapshot(doc.ruleset)
    local state = State.new(ruleset)
    ReplayFile.applyFrame(state, doc.frames[1], ruleset)

    local events = {}
    local worst, worstTick = 0, 0

    for i = 2, #doc.frames do
        local prev = doc.frames[i - 1]
        Step.tick(state, prev.inputs[1], prev.inputs[2], ruleset, events)

        local want = doc.frames[i]
        local dx = state.ball.x - want.ball[1]
        local dy = state.ball.y - want.ball[2]
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > worst then worst, worstTick = dist, want.t end

        if dist > TOLERANCE then
            fail("%s: Ball weicht in Tick %d um %.3f px ab (erlaubt %.1f)",
                id, want.t, dist, TOLERANCE)
        end
        if state.match.phase ~= want.phase then
            fail("%s: Phase in Tick %d ist %s, erwartet %s",
                id, want.t, state.match.phase, want.phase)
        end
        if state.match.score[1] ~= want.score[1] or state.match.score[2] ~= want.score[2] then
            fail("%s: Punktestand in Tick %d ist %d:%d, erwartet %d:%d",
                id, want.t, state.match.score[1], state.match.score[2],
                want.score[1], want.score[2])
        end
        if state.rally.touchCount ~= want.touch[2] then
            fail("%s: Beruehrungszaehler in Tick %d ist %d, erwartet %d",
                id, want.t, state.rally.touchCount, want.touch[2])
        end
    end

    return worst, worstTick, #doc.frames
end

for _, id in ipairs(RALLIES) do
    case("Ebene A: " .. id .. " reproduziert die Referenz", function()
        replay(id)
    end)
end

case("die Referenzen sind vollstaendig und tragen ihr Regelwerk", function()
    for _, id in ipairs(RALLIES) do
        local doc, err = ReplayFile.read("tests/replays/fixed60/" .. id .. ".json")
        if not doc then error(tostring(err), 2) end
        if #doc.frames < 50 then
            error(id .. " hat nur " .. #doc.frames .. " Frames", 2)
        end
        if doc.ruleset.gravity == nil then
            error(id .. " hat kein ruleset_snapshot", 2)
        end
    end
end)

return T
