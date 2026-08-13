-- ============================================================================
-- tests/run_headless.lua -- Testrunner der Ebenen A und B (07_TEST_PLAN §7)
--
-- Zwei Wege, derselbe Lauf:
--
--     lua tests/run_headless.lua        aus dem Repo-Wurzelverzeichnis, ohne
--                                       LOEVE -- so laeuft es spaeter in CI
--     love . --test                     im Spiel, praktisch beim Entwickeln
--
-- Die Testdateien und alles, was sie laden, sind love-frei. `--test-no-love`
-- beweist das: der Lauf setzt `love` auf nil und faellt auf die Nase, sobald
-- irgendein Modul die Bibliothek doch anfasst.
-- ============================================================================

local Runner = {}

Runner.SUITES = {
    "tests.input_frame_test",
    "tests.ruleset_test",
    "tests.rules_test",
    "tests.bindings_test",
    "tests.replay_test",
    "tests.snapshot_test",
    "tests.input_queue_test",
    "tests.lobby_test",
    "tests.menu_test",
    "tests.prediction_test",
    "tests.snapshot_events_test",
    "tests.checksum_test",

    -- M4 -- Turnier (Stufe A: love-frei und headless)
    "tests.tournament_json_test",
    "tests.tournament_bracket_test",
    "tests.tournament_model_test",
    "tests.tournament_scheduler_test",
    "tests.tournament_persistence_test",
    "tests.tournament_run_test",

    -- M4 -- Turnier (Stufe B: Laufzeit und Bedienung, ebenfalls love-frei;
    -- gezeichnet wird in `src/render/bracket_view.lua`, und das wird hier
    -- nicht geprueft -- ein Bild widerlegt kein Verhalten)
    "tests.tournament_session_test",
    "tests.tournament_lobby_test",
}

-- Suiten, die LOEVE brauchen (M2-01).
--
-- `src/net/protocol.lua` serialisiert mit `love.data.pack`. Diese Suite unter
-- reinem LuaJIT lauffaehig zu machen hiesse, die Serialisierung nachzubauen
-- und dann die Nachbildung zu pruefen -- der Fehler, den T-N-07 finden soll
-- (unterschiedliche Bytes auf Windows und macOS), waere damit systematisch
-- unsichtbar. Also: hier ueberspringen, unter `love . --test` laufen lassen.
-- Die CI tut beides.
Runner.LOVE_SUITES = {
    "tests.protocol_test",
}

local function runSuites(list, printf)
    local passed, failed = 0, 0

    for _, suiteName in ipairs(list) do
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

    return passed, failed
end

-- Gibt bestandene und gescheiterte Faelle zurueck.
function Runner.run(printf)
    printf = printf or print

    local passed, failed = runSuites(Runner.SUITES, printf)

    if love and love.data then
        local p, f = runSuites(Runner.LOVE_SUITES, printf)
        passed, failed = passed + p, failed + f
    else
        printf(string.format("-- %s uebersprungen (brauchen love.data, siehe Kopf)",
            table.concat(Runner.LOVE_SUITES, ", ")))
    end

    printf(string.format("%d bestanden, %d gescheitert", passed, failed))
    return passed, failed
end

-- Derselbe Lauf, aber ohne die Bibliothek im globalen Namensraum. Unter LOEVE
-- gestartet ist das der Nachweis, dass Simulation, Eingabe und Tests wirklich
-- ohne sie auskommen (03_TECH §3).
function Runner.runWithoutLove(printf)
    local saved = _G.love
    _G.love = nil
    local ok, passed, failed = pcall(Runner.run, printf)
    _G.love = saved
    if not ok then error(passed, 0) end
    return passed, failed
end

-- Als eigenstaendiges Skript gestartet? Dann laufen und den Exitcode setzen.
-- Unter LOEVE zeigt arg[0] auf die Binary, nicht auf diese Datei.
if arg and arg[0] and tostring(arg[0]):match("run_headless%.lua$") then
    local _, failed = Runner.run()
    os.exit(failed > 0 and 1 or 0)
end

return Runner
