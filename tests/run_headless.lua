-- ============================================================================
-- tests/run_headless.lua -- Testrunner der Ebenen A und B (07_TEST_PLAN section 7)
--
-- Stand M0-06: erst eine Testdatei, die der Doppeltipp-Erkennung. M0-13 baut
-- ihn aus (Regel-Unit-Tests, Wiedergabe der Referenz-Rallyes gegen sim.step)
-- und laesst ihn ohne LOEVE laufen. Bis dahin startet er ueber
--
--     love . --test
--
-- Die Testdateien selbst sind love-frei und ueberstehen den Umzug.
-- ============================================================================

local Runner = {}

Runner.SUITES = {
    "tests.input_frame_test",
    "tests.ruleset_test",
}

-- Gibt bestandene und gescheiterte Faelle zurueck.
function Runner.run(printf)
    printf = printf or print
    local passed, failed = 0, 0

    for _, suiteName in ipairs(Runner.SUITES) do
        local ok, suite = pcall(require, suiteName)
        if not ok then
            printf(string.format("SUITE FEHLER  %s: %s", suiteName, tostring(suite)))
            failed = failed + 1
        else
            printf(string.format("-- %s (%d Faelle)", suiteName, #suite))
            for _, case in ipairs(suite) do
                local success, err = pcall(case.fn)
                if success then
                    passed = passed + 1
                else
                    failed = failed + 1
                    printf(string.format("  FAIL  %s\n        %s", case.name, tostring(err)))
                end
            end
        end
    end

    printf(string.format("%d bestanden, %d gescheitert", passed, failed))
    return passed, failed
end

return Runner
