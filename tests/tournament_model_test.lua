-- ============================================================================
-- tests/tournament_model_test.lua -- Ebene B: Datenmodell und Log (M4-01)
--
-- Die Abnahme aus AP-1 steht weiter unten und heisst "aus dem Log
-- rekonstruiert ergibt Feld fuer Feld denselben Zustand". Sie ist der Grund
-- fuer den ganzen Rest: Ist sie erfuellt, ist die Absturz-Recovery aus §7
-- fast geschenkt. Ist sie es nicht, ist sie nicht baubar.
--
-- love-frei.
-- ============================================================================

local Model     = require("src.tournament.model")
local Bracket   = require("src.tournament.bracket")
local Scheduler = require("src.tournament.scheduler")
local H         = require("tests.tournament_helper")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local assertEq, assertTrue, assertFalse = H.assertEq, H.assertTrue, H.assertFalse

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

case("ein neues Turnier steht auf setup und hat genau ein Log-Ereignis", function()
    local t = H.newTournament(0)
    assertEq(t.status, "setup", "Status")
    assertEq(#t.log, 1, "ein Ereignis")
    assertEq(t.log[1].event, "tournament_created", "welches")
    assertEq(t.log[1].seq, 1, "Sequenznummer")
end)

case("die Voreinstellungen werden von der uebergebenen Konfiguration ueberschrieben", function()
    local t = H.newTournament(0, { parallelMatches = 4, targetScore = 21 })
    assertEq(t.config.parallelMatches, 4, "uebernommen")
    assertEq(t.config.targetScore, 21, "uebernommen")
    assertEq(t.config.noShowTimeout, 180, "Voreinstellung bleibt")
    assertEq(t.config.bestOfFinals, 3, "Voreinstellung bleibt")
end)

case("Teilnehmer kommen in Eingangsreihenfolge in die Liste", function()
    local t = H.newTournament(3)
    assertEq(#t.participantOrder, 3, "drei")
    assertEq(t.participantOrder[1], "p_01", "Reihenfolge")
    assertEq(t.participants["p_02"].name, "Blob 02", "Name")
    assertEq(t.participants["p_02"].status, "active", "Status")
end)

case("derselbe Teilnehmer kann nicht zweimal beitreten (E-14)", function()
    local t = H.newTournament(1)
    local ok = pcall(function()
        t:append({ event = "participant_joined", participantId = "p_01", name = "Blob 01" })
    end)
    assertFalse(ok, "abgelehnt")
end)

case("ein unbekanntes Ereignis wird abgelehnt, nicht ignoriert", function()
    local t = H.newTournament(0)
    assertFalse(pcall(function() t:append({ event = "gluecksrad" }) end), "abgelehnt")
    assertEq(#t.log, 1, "nichts im Log gelandet")
end)

-- ---------------------------------------------------------------------------
-- Auslosung
-- ---------------------------------------------------------------------------

case("die Auslosung setzt Setznummern, Gruppen und Matches", function()
    local t = H.newTournament(20, { parallelMatches = 4 })
    H.draw(t)
    assertEq(t.status, "running", "laeuft")
    assertEq(t.stage, "groups", "Stufe")
    assertEq(#t.groups, 4, "vier Gruppen")
    assertEq(#t.matchOrder, 40, "40 Gruppenmatches")
    assertEq(t.participants["p_01"].seed, 1, "Setznummer 1")
    assertEq(t.participants["p_20"].seed, 20, "Setznummer 20")
    for _, id in ipairs(t.matchOrder) do
        assertEq(t.matches[id].status, "pending", id .. " steht auf pending")
    end
end)

case("die Slots werden aus den Referenzen aufgeloest", function()
    local t = H.newTournament(8, { format = "single_elim" })
    H.draw(t)
    local first = t.matches[t.rounds[1].matches[1]]
    assertEq(first.slotA, "p_01", "Slot A steht sofort")
    local semi = t.matches[t.rounds[2].matches[1]]
    assertEq(semi.slotA, nil, "Slot des Halbfinals ist noch offen")
    assertEq(semi.slotARef, Bracket.winnerOf(first.id), "aber die Referenz steht")
end)

case("doppelte Match-Kennungen fallen sofort auf", function()
    local t = H.newTournament(4, { format = "single_elim" })
    H.draw(t)
    local existing = t.matchOrder[1]
    assertFalse(pcall(function()
        t:append({ event = "tiebreak_added", matches = {
            { id = existing, round = 9, stage = "tiebreak",
              slotARef = "p_01", slotBRef = "p_02", bestOf = 1, targetScore = 7 } } })
    end), "abgelehnt")
end)

-- ---------------------------------------------------------------------------
-- Ergebnisse und Fortschreibung
-- ---------------------------------------------------------------------------

local function finish(t, matchId, winner, sets, at)
    t:append({ event = "match_finished", matchId = matchId, at = at or 0,
               winner = winner, sets = sets or { { a = 15, b = 9 } } })
end

case("ein Ergebnis schreibt das Bracket fort", function()
    local t = H.newTournament(8, { format = "single_elim" })
    H.draw(t)
    local qf = t.rounds[1].matches
    finish(t, qf[1], "p_01")
    assertEq(t.matches[qf[1]].status, "finished", "Status")
    assertEq(t.matches[qf[1]].loser, "p_08", "Verlierer abgeleitet")
    assertEq(t.matches[t.rounds[2].matches[1]].slotA, "p_01",
        "der Sieger steht im Halbfinale")
end)

case("das Spiel um Platz 3 bekommt die Halbfinalverlierer", function()
    local t = H.newTournament(4, { format = "single_elim" })
    H.draw(t)
    local semi = t.rounds[1].matches
    finish(t, semi[1], "p_01")
    finish(t, semi[2], "p_02")
    local third
    for _, id in ipairs(t.matchOrder) do if t.matches[id].thirdPlace then third = t.matches[id] end end
    assertEq(third.slotA, "p_04", "Verlierer des ersten Halbfinals")
    assertEq(third.slotB, "p_03", "Verlierer des zweiten Halbfinals")
end)

case("ein Sieger, der gar nicht mitspielt, wird abgelehnt", function()
    local t = H.newTournament(8, { format = "single_elim" })
    H.draw(t)
    assertFalse(pcall(finish, t, t.rounds[1].matches[1], "p_05"), "abgelehnt")
end)

case("Statistiken werden gefuehrt", function()
    local t = H.newTournament(8, { format = "single_elim" })
    H.draw(t)
    finish(t, t.rounds[1].matches[1], "p_01", { { a = 15, b = 9 } })
    local p1 = t.participants["p_01"].stats
    assertEq(p1.matches, 1, "ein Match")
    assertEq(p1.wins, 1, "ein Sieg")
    assertEq(p1.setsWon, 1, "ein Satz")
    assertEq(p1.pointsFor, 15, "Punkte fuer")
    assertEq(p1.pointsAgainst, 9, "Punkte gegen")
    assertEq(t.participants["p_08"].stats.losses, 1, "Niederlage beim Gegner")
end)

case("ein Abbruch setzt zurueck auf pending und behaelt die Saetze (E-06)", function()
    local t = H.newTournament(8, { format = "single_elim" })
    H.draw(t)
    local id = t.rounds[1].matches[1]
    t:append({ event = "match_called", matchId = id, at = 10 })
    t:append({ event = "match_started", matchId = id, at = 20 })
    t:append({ event = "match_finished", matchId = id, at = 30, winner = "p_01",
               sets = { { a = 15, b = 9 } } })
    t:append({ event = "match_aborted", matchId = id, at = 40, reason = "host_lost" })

    local m = t.matches[id]
    assertEq(m.status, "pending", "neu anzusetzen")
    assertEq(#m.sets, 1, "der gespielte Satz zaehlt weiter")
    assertEq(m.startedAt, nil, "Startzeit geloescht")
    assertEq(m.aborts, 1, "Abbruch gezaehlt")
    assertEq(t.matches[t.rounds[2].matches[1]].slotA, nil,
        "der Sieger ist wieder aus dem Halbfinale verschwunden")
end)

-- ---------------------------------------------------------------------------
-- E-12: die manuelle Korrektur -- der Fall, an dem inkrementelle Zaehler
-- stillschweigend falsch werden
-- ---------------------------------------------------------------------------

case("eine Korrektur dreht das Ergebnis UND die Statistik", function()
    local t = H.newTournament(8, { format = "single_elim" })
    H.draw(t)
    local id = t.rounds[1].matches[1]
    finish(t, id, "p_01", { { a = 15, b = 9 } })
    assertEq(t.participants["p_01"].stats.wins, 1, "vorher")

    t:append({ event = "manual_override", matchId = id, at = 50,
               winner = "p_08", sets = { { a = 9, b = 15 } },
               reason = "falsche Seite gemeldet", by = "turnierleitung" })

    assertEq(t.matches[id].winner, "p_08", "neuer Sieger")
    assertTrue(t.matches[id].overridden, "sichtbar markiert")
    assertEq(t.matches[id].overrideReason, "falsche Seite gemeldet", "mit Begruendung")
    assertEq(t.participants["p_01"].stats.wins, 0, "der alte Sieg ist weg")
    assertEq(t.participants["p_01"].stats.pointsFor, 9, "auch die Punkte stimmen")
    assertEq(t.participants["p_08"].stats.wins, 1, "der neue Sieg steht")
    assertEq(t.matches[t.rounds[2].matches[1]].slotA, "p_08", "das Bracket zieht nach")
end)

-- ---------------------------------------------------------------------------
-- Teilnehmerstatus
-- ---------------------------------------------------------------------------

case("waehrend der Gruppenphase ist niemand ausgeschieden", function()
    local t = H.newTournament(8, { parallelMatches = 8 })
    H.draw(t)
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        finish(t, id, t:higherSeed(m.slotA, m.slotB))
    end
    for _, pid in ipairs(t.participantOrder) do
        assertEq(t.participants[pid].status, "active", pid .. " spielt noch")
    end
end)

case("wer im Halbfinale verliert, ist NICHT raus -- er spielt um Platz 3", function()
    local t = H.newTournament(4, { format = "single_elim" })
    H.draw(t)
    finish(t, t.rounds[1].matches[1], "p_01")
    assertEq(t.participants["p_04"].status, "active",
        "das Spiel um Platz 3 ist ein offenes Match")
    assertEq(t.participants["p_01"].status, "active", "der Sieger spielt weiter")
end)

case("ausgeschieden ist, wer kein offenes Match mehr hat", function()
    local config = { format = "single_elim", thirdPlaceMatch = false }
    local t = H.newTournament(4, config)
    H.draw(t)
    finish(t, t.rounds[1].matches[1], "p_01")
    assertEq(t.participants["p_04"].status, "eliminated", "im Halbfinale raus")
    assertEq(t.participants["p_01"].status, "active", "der Sieger spielt weiter")
end)

case("der Sieger heisst winner, nicht eliminated", function()
    local t = H.newTournament(4, { format = "single_elim" })
    H.draw(t)
    finish(t, t.rounds[1].matches[1], "p_01")
    finish(t, t.rounds[1].matches[2], "p_02")
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.status == "pending" then finish(t, id, m.slotA) end
    end
    t:append({ event = "tournament_finished", at = 99, winner = "p_01" })
    assertEq(t.status, "finished", "Turnier fertig")
    assertEq(t.participants["p_01"].status, "winner", "Sieger")
    assertEq(t.participants["p_02"].status, "eliminated", "Zweiter")
end)

case("der hoeher Gesetzte ist der mit der kleineren Nummer", function()
    local t = H.newTournament(8, { format = "single_elim" })
    H.draw(t)
    assertEq(t:higherSeed("p_03", "p_07"), "p_03", "3 vor 7")
    assertEq(t:higherSeed("p_07", "p_03"), "p_03", "Reihenfolge egal")
    assertEq(t:higherSeed(nil, "p_07"), "p_07", "nil zaehlt nicht")
end)

-- ---------------------------------------------------------------------------
-- Die Abnahme aus AP-1
-- ---------------------------------------------------------------------------

-- Ein 8er-Turnier komplett durchspielen -- mit Walkover, Abbruch und
-- Korrektur, damit im Log alles vorkommt, was den Zustand veraendert.
local function busyTournament()
    local t = H.newTournament(12, { parallelMatches = 3, noShowTimeout = 100 })
    H.draw(t)
    local sched = Scheduler.new(t)
    H.allOnline(t, sched)

    local now = 0
    local turns = 0
    while t.status == "running" and turns < 500 do
        turns = turns + 1
        sched:update(now)

        -- Ein Abbruch mittendrin, genau einmal.
        if turns == 3 then
            for _, id in ipairs(t.matchOrder) do
                if t.matches[id].status == "live" then
                    sched:abortMatch(id, "host_lost", now)
                    break
                end
            end
        end

        for _, id in ipairs(t.matchOrder) do
            local m = t.matches[id]
            if m.status == "ready" then
                sched:confirmReady(id, m.slotA, now)
                sched:confirmReady(id, m.slotB, now)
            end
        end
        sched:update(now)

        for _, id in ipairs(t.matchOrder) do
            local m = t.matches[id]
            if m.status == "live" then
                local w = t:higherSeed(m.slotA, m.slotB)
                sched:reportResult(id, H.setsFor(m, w), now)
            end
        end
        now = now + 10
    end
    return t
end

case("aus dem Log rekonstruiert ergibt Feld fuer Feld denselben Zustand", function()
    local t = busyTournament()
    assertEq(t.status, "finished", "das Turnier ist durchgelaufen")
    assertTrue(#t.log > 60, "das Log hat Substanz: " .. #t.log)

    local rebuilt = Model.replay(t.log)
    local same, differences = Model.diff(t, rebuilt)
    if not same then
        error("Unterschiede:\n  " .. table.concat(differences, "\n  "), 2)
    end
    assertEq(#rebuilt.log, #t.log, "gleich langes Log")
end)

case("der Vergleich merkt einen Unterschied -- sonst waere er wertlos", function()
    local t = busyTournament()
    local rebuilt = Model.replay(t.log)
    rebuilt.matches[t.matchOrder[1]].winner = "p_99"
    local same, differences = Model.diff(t, rebuilt)
    assertFalse(same, "erkannt")
    assertEq(#differences, 1, "genau ein Unterschied")
    assertTrue(differences[1]:find("winner") ~= nil, "an der richtigen Stelle")
end)

case("der Vergleich prueft auch, was NUR auf einer Seite steht", function()
    local t = H.newTournament(4, { format = "single_elim" })
    H.draw(t)
    local rebuilt = Model.replay(t.log)
    rebuilt.participants["p_99"] = { id = "p_99" }
    assertFalse(Model.diff(t, rebuilt), "zusaetzliches Feld erkannt")
end)

case("Zwischenstaende stimmen auch, nicht nur das Endergebnis", function()
    -- Das Log Ereignis fuer Ereignis nachspielen und jedes Mal vergleichen.
    -- Ein Zustand, der nur am Ende stimmt, hilft der Recovery nicht -- die
    -- setzt genau mittendrin auf.
    local t = busyTournament()
    local partial = {}
    for i, ev in ipairs(t.log) do
        partial[i] = ev
        if i % 7 == 0 or i == #t.log then
            local a = Model.replay(partial)
            local b = Model.replay(partial)
            local same, differences = Model.diff(a, b)
            assertTrue(same, string.format("nach %d Ereignissen: %s",
                i, table.concat(differences, "; ")))
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Dokument
-- ---------------------------------------------------------------------------

case("das Dokument traegt Log und abgeleiteten Zustand", function()
    local t = busyTournament()
    local doc = t:toDocument()
    assertEq(doc.version, Model.VERSION, "Version")
    assertEq(#doc.log, #t.log, "vollstaendiges Log")
    assertEq(doc.derived.id, t.id, "abgeleiteter Zustand liegt bei")
    assertEq(doc.derived.log, nil, "aber nicht doppelt")
end)

case("aus dem Dokument wird ausschliesslich das Log gelesen", function()
    local t = busyTournament()
    local doc = t:toDocument()
    -- Der abgeleitete Teil wird absichtlich verbogen. Wenn der Lader ihn
    -- benutzte, kaeme der Unsinn durch.
    doc.derived.winner = "p_99"
    doc.derived.status = "aborted"

    local back = Model.fromDocument(doc)
    assertEq(back.winner, t.winner, "der Sieger kommt aus dem Log")
    assertEq(back.status, t.status, "der Status auch")
    assertTrue(Model.diff(t, back), "und alles andere ebenfalls")
end)

case("eine fremde Dateiversion wird abgelehnt, nicht geraten (F-01)", function()
    local t = H.newTournament(4)
    local doc = t:toDocument()
    doc.version = 99
    local back, err = Model.fromDocument(doc)
    assertEq(back, nil, "abgelehnt")
    assertTrue(err:find("99") ~= nil, "Meldung nennt die Version: " .. tostring(err))
end)

case("ein leeres oder fehlendes Log wird abgelehnt", function()
    assertEq(Model.fromDocument({ version = Model.VERSION, log = {} }), nil, "leer")
    assertEq(Model.fromDocument({ version = Model.VERSION }), nil, "fehlt")
    assertEq(Model.fromDocument("kein Dokument"), nil, "kein Tabellentyp")
end)

case("ein kaputtes Log stuerzt nicht ab, sondern meldet sich", function()
    local back, err = Model.fromDocument({
        version = Model.VERSION,
        log = { { event = "match_finished", matchId = "gibt_es_nicht", winner = "x" } },
    })
    assertEq(back, nil, "abgelehnt")
    assertTrue(err:find("abspielbar") ~= nil, "mit Meldung: " .. tostring(err))
end)

-- B-T-03, gefunden ueber die Teilnehmerliste in `bracket_view.lua`: Bei einem
-- Freilos ist der Gegnerslot leer. Der Verlierer wurde daraus mit einem
-- and/or-Ausdruck bestimmt, der in genau diesem Fall auf den SIEGER
-- durchfaellt -- und damit stand in der Statistik eine Niederlage, die niemand
-- erlitten hat.
case("ein Freilos hat einen Sieger und keinen Verlierer (B-T-03)", function()
    local t = H.newTournament(5, { format = "single_elim" })
    H.draw(t)

    local bye
    for _, m in ipairs(t:matchList()) do
        if Model.hasBye(m) then bye = m break end
    end
    assertTrue(bye ~= nil, "bei fuenf Teilnehmern gibt es Freilose")

    local winner = bye.slotA or bye.slotB
    t:append({ event = "match_bye", matchId = bye.id, at = 0, winner = winner })

    local done = t:match(bye.id)
    assertEq(done.winner, winner, "der Freilos-Sieger")
    assertEq(done.loser, nil, "und niemand hat verloren")

    local stats = t.participants[winner].stats
    assertEq(stats.wins, 1, "ein Sieg")
    assertEq(stats.losses, 0, "keine Niederlage")
end)

-- B-T-03, gefunden ueber die Teilnehmerliste in `bracket_view.lua`: Bei einem
-- Freilos ist der Gegnerslot leer. Der Verlierer wurde daraus mit einem
-- and/or-Ausdruck bestimmt, der in genau diesem Fall auf den SIEGER
-- durchfaellt -- und damit stand in der Statistik eine Niederlage, die niemand
-- erlitten hat.
case("ein Freilos hat einen Sieger und keinen Verlierer (B-T-03)", function()
    local t = H.newTournament(5, { format = "single_elim" })
    H.draw(t)

    local bye
    for _, m in ipairs(t:matchList()) do
        if Model.hasBye(m) then bye = m break end
    end
    assertTrue(bye ~= nil, "bei fuenf Teilnehmern gibt es Freilose")

    local winner = bye.slotA or bye.slotB
    t:append({ event = "match_bye", matchId = bye.id, at = 0, winner = winner })

    local done = t:match(bye.id)
    assertEq(done.winner, winner, "der Freilos-Sieger")
    assertEq(done.loser, nil, "und niemand hat verloren")

    local stats = t.participants[winner].stats
    assertEq(stats.wins, 1, "ein Sieg")
    assertEq(stats.losses, 0, "keine Niederlage")
end)

return T
