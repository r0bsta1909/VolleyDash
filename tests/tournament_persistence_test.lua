-- ============================================================================
-- tests/tournament_persistence_test.lua -- Ebene B: atomar schreiben (M4-06)
--
-- `05_TOURNAMENT` §7, ADR-007, ADR-020.
--
-- Der Testfall, um den es geht, ist der haessliche: eine HALB GESCHRIEBENE
-- Datei. Sie darf das Turnier nicht kosten -- dafuer gibt es die `.bak`.
--
-- Der zweitwichtigste ist unauffaelliger und war der Anlass fuer die
-- Berichtigung in §7: `os.rename` ueberschreibt unter Windows nicht. Die
-- urspruengliche Dreierschrittfolge waere beim ZWEITEN Speichern still
-- gescheitert -- und ein Turnier, das nicht gespeichert wird, merkt man erst
-- beim Absturz. Die Attrappe unter `H.fakeFs` bildet genau das nach.
--
-- love-frei: der Dateizugriff ist ein austauschbarer Unterbau.
-- ============================================================================

local Model       = require("src.tournament.model")
local Persistence = require("src.tournament.persistence")
local Scheduler   = require("src.tournament.scheduler")
local Json        = require("src.tournament.json")
local H           = require("tests.tournament_helper")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local assertEq, assertTrue, assertFalse = H.assertEq, H.assertTrue, H.assertFalse

local function store()
    local fs = H.fakeFs()
    local p = Persistence.new(fs)
    return p, fs
end

local function tournament(n, config)
    local t = H.newTournament(n or 8, config or { format = "single_elim" },
                              { id = "t_1754900000" })
    return t
end

-- ---------------------------------------------------------------------------
-- Schreiben
-- ---------------------------------------------------------------------------

case("das erste Speichern legt genau eine gueltige Datei an", function()
    local p, fs = store()
    local t = tournament()
    assertTrue(p:save(t), "gespeichert")

    assertTrue(fs.files["tournaments/t_1754900000.json"] ~= nil, "die .json steht")
    assertEq(fs.files["tournaments/t_1754900000.json.tmp"], nil, "keine .tmp uebrig")
    assertEq(fs.files["tournaments/t_1754900000.json.bak"], nil, "noch keine .bak")
end)

case("das ZWEITE Speichern scheitert nicht -- das ist der Grund fuer vier Schritte", function()
    local p, fs = store()
    local t = tournament()
    p:save(t)
    local first = fs.files["tournaments/t_1754900000.json"]

    H.draw(t)
    local ok, err = p:save(t)
    assertTrue(ok, "gespeichert: " .. tostring(err))

    assertEq(fs.files["tournaments/t_1754900000.json.bak"], first,
        "der alte Stand liegt als .bak daneben")
    assertTrue(fs.files["tournaments/t_1754900000.json"] ~= first, "und die .json ist neu")
    assertEq(fs.files["tournaments/t_1754900000.json.tmp"], nil, "keine .tmp uebrig")
    assertEq(p.writes, 2, "zwei Schreibvorgaenge")
end)

case("zehnmal speichern laesst genau zwei Dateien zurueck", function()
    local p, fs = store()
    local t = tournament()
    for i = 1, 10 do
        t:append({ event = "participant_joined",
                   participantId = "x_" .. i, name = "X" .. i })
        assertTrue(p:save(t), "Durchgang " .. i)
    end
    assertEq(#fs.list("tournaments"), 2, ".json und .bak, sonst nichts")
end)

case("ein Turnier ohne Kennung wird nicht geschrieben", function()
    local p = store()
    local t = tournament()
    t.id = ""
    assertFalse(p:save(t), "abgelehnt")
end)

case("die Datei ist lesbares JSON -- der eigentliche Zweck des Formats", function()
    local p, fs = store()
    local t = tournament()
    H.draw(t)
    p:save(t)

    local text = fs.files["tournaments/t_1754900000.json"]
    assertTrue(text:find("\n") ~= nil, "mehrzeilig")
    assertTrue(text:find('"tournament_created"') ~= nil, "Ereignisnamen im Klartext")
    assertTrue(Json.decode(text) ~= nil, "und wieder lesbar")
end)

-- ---------------------------------------------------------------------------
-- Nach jedem Log-Ereignis (§7)
-- ---------------------------------------------------------------------------

case("angehaengt wird nach JEDEM Ereignis, nicht nach jedem Match", function()
    local p = store()
    local t = tournament(8)
    local before = #t.log
    p:attach(t)

    H.draw(t)
    local sched = Scheduler.new(t)
    H.allOnline(t, sched)
    H.play(t, sched, { limit = 300 })

    assertEq(t.status, "finished", "durchgelaufen")
    assertEq(p.writes, #t.log - before, "ein Schreibvorgang je neuem Ereignis")
    assertTrue(p.writes > 20, "und es waren einige: " .. p.writes)
end)

-- ---------------------------------------------------------------------------
-- Lesen
-- ---------------------------------------------------------------------------

case("was gespeichert wurde, kommt vollstaendig zurueck", function()
    local p = store()
    local t = tournament(8)
    H.draw(t)
    p:save(t)

    local back, source = p:load("t_1754900000")
    assertTrue(back ~= nil, "geladen")
    assertEq(source, "json", "aus der .json")
    local same, differences = Model.diff(t, back)
    assertTrue(same, "identisch: " .. table.concat(differences, "; "))
end)

case("eine halb geschriebene .json kostet das Turnier nicht", function()
    local p, fs = store()
    local t = tournament(8)
    p:save(t)         -- Stand 1 -> .json
    H.draw(t)
    p:save(t)         -- Stand 1 -> .bak, Stand 2 -> .json

    fs.truncate("tournaments/t_1754900000.json", 0.6)

    local back, source, warning = p:load("t_1754900000")
    assertTrue(back ~= nil, "gerettet")
    assertEq(source, "bak", "aus der Sicherung")
    assertTrue(warning ~= nil, "und mit Hinweis, was schiefging: " .. tostring(warning))
    assertEq(#back.log, 9, "der vorletzte Stand: Anlage plus acht Teilnehmer")
end)

case("der Absturz zwischen Schritt 3 und 4 laesst gar keine .json zurueck", function()
    -- Genau das Fenster, fuer das die .bak da ist.
    local p, fs = store()
    local t = tournament(8)
    p:save(t)
    H.draw(t)
    p:save(t)
    fs.files["tournaments/t_1754900000.json"] = nil

    local back, source = p:load("t_1754900000")
    assertTrue(back ~= nil, "gerettet")
    assertEq(source, "bak", "aus der Sicherung")
end)

case("sind beide Dateien hin, wird das gemeldet und nicht geraten", function()
    local p, fs = store()
    local t = tournament(8)
    p:save(t)
    H.draw(t)
    p:save(t)
    fs.truncate("tournaments/t_1754900000.json", 0.5)
    fs.truncate("tournaments/t_1754900000.json.bak", 0.5)

    local back, source, err = p:load("t_1754900000")
    assertEq(back, nil, "kein Ergebnis")
    assertEq(source, nil, "keine Quelle")
    assertTrue(err ~= nil and err:find("json") ~= nil, "mit Meldung: " .. tostring(err))
end)

case("ein Turnier, das es nicht gibt, ergibt keinen Absturz", function()
    local p = store()
    local back, _, err = p:load("t_gibtsnicht")
    assertEq(back, nil, "kein Ergebnis")
    assertTrue(err ~= nil, "mit Meldung")
end)

-- ---------------------------------------------------------------------------
-- Der Dialog aus §7
-- ---------------------------------------------------------------------------

case("laufende Turniere werden gefunden, abgeschlossene nicht", function()
    local p, fs = store()

    local running = H.newTournament(8, { format = "single_elim" }, { id = "t_laeuft" })
    H.draw(running)
    p:save(running)

    local done = H.newTournament(4, { format = "single_elim" }, { id = "t_fertig" })
    H.draw(done)
    done:append({ event = "tournament_finished", at = 1, winner = "p_01" })
    p:save(done)

    assertEq(#p:list(), 2, "beide sind da")
    local open = p:running()
    assertEq(#open, 1, "eins laeuft")
    assertEq(open[1].id, "t_laeuft", "und zwar das richtige")
    assertEq(open[1].name, "Testturnier", "mit Namen fuer den Dialog")
    local _ = fs
end)

case("die Rundenzahl fuer den Dialogtext stimmt", function()
    local t = H.newTournament(20, { parallelMatches = 4 })
    H.draw(t)
    assertEq(Persistence.currentRound(t), 1, "vor dem ersten Match")

    -- Runde 1 komplett entscheiden.
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.round == 1 then
            t:append({ event = "match_finished", matchId = id, at = 0,
                       winner = m.slotA, sets = { { a = 15, b = 5 } } })
        end
    end
    assertEq(Persistence.currentRound(t), 2, "jetzt Runde 2")
end)

-- ---------------------------------------------------------------------------
-- Wiederaufnahme (§7 Schritt 4)
-- ---------------------------------------------------------------------------

case("aufgerufene und laufende Matches werden neu angesetzt, nicht verschenkt", function()
    local t = H.newTournament(16, { format = "single_elim", parallelMatches = 4 })
    H.draw(t)
    local sched = Scheduler.new(t)
    H.allOnline(t, sched)
    sched:update(0)

    local id = t.rounds[1].matches[1]
    local m = t.matches[id]
    sched:confirmReady(id, m.slotA, 0)
    sched:confirmReady(id, m.slotB, 0)
    sched:update(1)
    assertEq(t.matches[id].status, "live", "es laeuft")

    local reopened = Persistence.resume(t, 100)
    assertTrue(#reopened >= 1, "mindestens das laufende Match")
    for _, mid in ipairs(reopened) do
        assertEq(t.matches[mid].status, "pending", mid .. " wartet wieder")
        assertEq(t.matches[mid].winner, nil, "und hat keinen Sieger geschenkt bekommen")
    end
end)

case("die Wiederaufnahme steht als Ereignis im Log", function()
    local t = H.newTournament(8, { format = "single_elim", parallelMatches = 2 })
    H.draw(t)
    local sched = Scheduler.new(t)
    H.allOnline(t, sched)
    sched:update(0)

    Persistence.resume(t, 100)
    local found = false
    for _, ev in ipairs(t.log) do
        if ev.event == "match_aborted" and ev.reason == "host_restart" then found = true end
    end
    assertTrue(found, "nachvollziehbar, warum das Match neu angesetzt wurde")
end)

case("ohne Dateizugriff gibt es kein Objekt, aber auch keinen Absturz", function()
    local p, err = Persistence.new(nil)
    if love and love.filesystem then
        assertTrue(p ~= nil, "unter LOEVE geht es")
    else
        assertEq(p, nil, "ohne LOEVE nicht")
        assertTrue(err ~= nil, "mit Meldung")
    end
end)

-- ---------------------------------------------------------------------------
-- Loeschen (AP-1, CC-06)
-- ---------------------------------------------------------------------------

case("loeschen entfernt .json UND .bak -- das andere Turnier bleibt unberuehrt", function()
    local p, fs = store()
    local a = H.newTournament(8, { format = "single_elim" }, { id = "t_a" })
    local b = H.newTournament(8, { format = "single_elim" }, { id = "t_b" })
    p:save(a) H.draw(a) p:save(a)   -- zweimal, damit die .bak existiert
    p:save(b) H.draw(b) p:save(b)

    local jsonB = fs.files["tournaments/t_b.json"]
    local bakB  = fs.files["tournaments/t_b.json.bak"]
    assertTrue(fs.files["tournaments/t_a.json.bak"] ~= nil, "die .bak von A steht")

    assertTrue(p:delete("t_a"), "geloescht")
    assertEq(fs.files["tournaments/t_a.json"], nil, "die .json ist weg")
    assertEq(fs.files["tournaments/t_a.json.bak"], nil,
        "die .bak auch -- sonst holt `load` das Turnier daraus zurueck")
    assertEq(fs.files["tournaments/t_a.json.tmp"], nil, "und keine .tmp uebrig")
    assertEq(fs.files["tournaments/t_b.json"], jsonB, "B ist unberuehrt")
    assertEq(fs.files["tournaments/t_b.json.bak"], bakB, "samt seiner Sicherung")
    assertEq(#p:list(), 1, "die Liste kennt nur noch B")
end)

case("eine fehlende Datei ist beim Loeschen kein Fehler", function()
    local p = store()
    assertTrue(p:delete("t_nie_gesehen"), "geloescht ist geloescht")
    assertFalse(p:delete(nil), "aber ohne Kennung geht nichts")
    assertFalse(p:delete(""), "auch nicht leer")
end)

case("die Liste traegt Status und Datum -- die Verwaltung braucht beide", function()
    local p = store()
    local t = H.newTournament(8, { format = "single_elim" }, { id = "t_x" })
    p:save(t)
    local entry = p:list()[1]
    assertEq(entry.status, "setup", "nie gestartet -- genau die Sorte, die liegen bleibt")
    assertTrue(entry.createdAt ~= nil, "mit Datum")
end)

case("loeschen, waehrend dasselbe Turnier geladen ist, ueberlebt das naechste Ereignis nicht", function()
    -- Die Sperre sitzt in der Bedienung (`manageKey`) und in der Szene. Auf
    -- DIESER Ebene ist das Verhalten trotzdem festgelegt und soll so bleiben:
    -- `attach` schreibt nach jedem Ereignis (§7), ein geloeschtes, aber noch
    -- geladenes Turnier taucht also von selbst wieder auf. Verloren waere nur
    -- die .bak -- genau deshalb bietet die Bedienung das gar nicht erst an.
    local p, fs = store()
    local t = H.newTournament(8, { format = "single_elim" }, { id = "t_l" })
    p:attach(t)
    H.draw(t)
    assertTrue(fs.files["tournaments/t_l.json"] ~= nil, "gespeichert")

    p:delete("t_l")
    assertEq(fs.files["tournaments/t_l.json"], nil, "weg")

    t:append({ event = "participant_joined", participantId = "x_9", name = "X9" })
    assertTrue(fs.files["tournaments/t_l.json"] ~= nil,
        "und nach dem naechsten Ereignis wieder da")
end)

return T
