-- ============================================================================
-- tests/tournament_scheduler_test.lua -- Ebene B: Zustandsautomat (M4-05)
--
-- `05_TOURNAMENT` §5 und §6. Der Schwerpunkt liegt auf den Nebenwegen, nicht
-- auf dem Normalfall: Ein Turnier scheitert nie daran, dass zwei anwesende
-- Spieler ein Match zu Ende bringen.
--
-- Die drei Faelle aus ADR-021 (E-15, E-16, E-17) stehen jeweils mit eigenem
-- Fall darin -- sie sind neu und haben in der Spec vorher gefehlt.
--
-- love-frei.
-- ============================================================================

local Model     = require("src.tournament.model")
local Scheduler = require("src.tournament.scheduler")
local H         = require("tests.tournament_helper")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local assertEq, assertTrue, assertFalse = H.assertEq, H.assertTrue, H.assertFalse

local function setup(n, config, opts)
    local t = H.newTournament(n, config)
    H.draw(t, opts)
    local sched = Scheduler.new(t)
    return t, sched
end

-- ---------------------------------------------------------------------------
-- Freilose (E-01)
-- ---------------------------------------------------------------------------

case("Freilose loesen sich von selbst auf, ohne dass jemand spielt", function()
    local t, sched = setup(6, { format = "single_elim" })
    H.allOnline(t, sched)
    sched:update(0)

    local byes = 0
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.status == Model.STATUS.BYE then
            byes = byes + 1
            assertTrue(m.winner ~= nil, "das Freilos hat einen Sieger")
        end
    end
    assertEq(byes, 2, "zwei Freilose bei sechs Teilnehmern")
    assertEq(t.matches[t.rounds[2].matches[1]].slotA, "p_01",
        "der Freigeloste steht im Halbfinale")
end)

-- ---------------------------------------------------------------------------
-- Aufrufen (§5)
-- ---------------------------------------------------------------------------

case("ohne Verbindung wird nichts aufgerufen", function()
    local t, sched = setup(8, { format = "single_elim" })
    sched:update(0)
    assertEq(t:activeMatches(), 0, "niemand online, nichts aufgerufen")
end)

case("ein Match wird erst aufgerufen, wenn BEIDE online sind", function()
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 4 })
    sched:setOnline("p_01", true)
    sched:update(0)
    assertEq(t:activeMatches(), 0, "einer allein reicht nicht")

    sched:setOnline("p_08", true)
    sched:update(1)
    assertEq(t:activeMatches(), 1, "jetzt wird aufgerufen")
end)

case("parallelMatches ist die Obergrenze", function()
    local t, sched = setup(16, { format = "single_elim", parallelMatches = 3 })
    H.allOnline(t, sched)
    sched:update(0)
    assertEq(t:activeMatches(), 3, "drei gleichzeitig")
end)

case("weniger spielbare Matches als konfiguriert blockieren nicht (§2)", function()
    -- Vier parallele Matches erlaubt, aber nur zwei Spieler sind da.
    local t, sched = setup(16, { format = "single_elim", parallelMatches = 4 })
    sched:setOnline("p_01", true)
    sched:setOnline("p_16", true)
    sched:update(0)
    assertEq(t:activeMatches(), 1, "das eine spielbare Match laeuft")

    local m = t.matches[t.rounds[1].matches[1]]
    sched:confirmReady(m.id, "p_01", 0)
    sched:confirmReady(m.id, "p_16", 0)
    sched:update(1)
    assertEq(t.matches[m.id].status, Model.STATUS.LIVE, "und laeuft wirklich")
end)

case("niemand wird in zwei Matches gleichzeitig aufgerufen", function()
    -- Round Robin: p_01 kommt in jeder Paarung vor, aber nie doppelt.
    local t, sched = setup(5, { format = "round_robin", parallelMatches = 8 })
    H.allOnline(t, sched)
    sched:update(0)

    local busy = {}
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.status == Model.STATUS.READY or m.status == Model.STATUS.LIVE then
            for _, pid in ipairs({ m.slotA, m.slotB }) do
                assertFalse(busy[pid], pid .. " wurde zweimal aufgerufen")
                busy[pid] = true
            end
        end
    end
end)

case("beide bereit -- das Match geht live und bekommt einen Host", function()
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 1 })
    H.allOnline(t, sched)
    sched:update(0)

    local id = nil
    for _, mid in ipairs(t.matchOrder) do
        if t.matches[mid].status == Model.STATUS.READY then id = mid break end
    end
    assertTrue(id ~= nil, "ein Match ist aufgerufen")
    assertTrue(t.matches[id].calledAt ~= nil, "mit Aufrufzeitpunkt fuer den Timer")

    local m = t.matches[id]
    sched:confirmReady(id, m.slotA, 5)
    sched:update(5)
    assertEq(t.matches[id].status, Model.STATUS.READY, "einer allein startet nicht")

    sched:confirmReady(id, m.slotB, 6)
    sched:update(6)
    assertEq(t.matches[id].status, Model.STATUS.LIVE, "jetzt laeuft es")
    assertEq(t.matches[id].hostClient, "p_01", "der hoeher Gesetzte hostet (vorlaeufig)")
end)

case("die Host-Wahl ist austauschbar -- M4-09 haengt genau da", function()
    local t = H.newTournament(8, { format = "single_elim", parallelMatches = 1 })
    H.draw(t)
    local sched = Scheduler.new(t, { chooseHost = function(m) return m.slotB end })
    H.allOnline(t, sched)
    sched:update(0)
    local id = t.rounds[1].matches[1]
    local m = t.matches[id]
    sched:confirmReady(id, m.slotA, 0)
    sched:confirmReady(id, m.slotB, 0)
    sched:update(1)
    assertEq(t.matches[id].hostClient, m.slotB, "die uebergebene Regel gilt")
end)

-- ---------------------------------------------------------------------------
-- Ergebnisse
-- ---------------------------------------------------------------------------

case("das Ergebnis kommt aus den Saetzen, nicht aus einer Meldung (E-08)", function()
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 1 })
    H.allOnline(t, sched)
    sched:update(0)
    local id = t.rounds[1].matches[1]
    local m = t.matches[id]
    sched:confirmReady(id, m.slotA, 0)
    sched:confirmReady(id, m.slotB, 0)
    sched:update(1)

    assertTrue(sched:reportResult(id, { { a = 9, b = 15 } }, 2), "angenommen")
    assertEq(t.matches[id].winner, m.slotB, "der Satzgewinner gewinnt")
end)

case("ein Ergebnis ohne Sieger wird abgelehnt", function()
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 1 })
    H.allOnline(t, sched)
    sched:update(0)
    local id = t.rounds[1].matches[1]
    local ok, why = sched:reportResult(id, { { a = 15, b = 9 }, { a = 9, b = 15 } }, 2)
    assertFalse(ok, "abgelehnt")
    assertTrue(why:find("Sieger") ~= nil, "mit Grund: " .. tostring(why))
end)

case("ein fertiges Match nimmt kein zweites Ergebnis an", function()
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 1 })
    H.allOnline(t, sched)
    sched:update(0)
    local id = t.rounds[1].matches[1]
    sched:reportResult(id, { { a = 15, b = 9 } }, 2)
    assertFalse(sched:reportResult(id, { { a = 9, b = 15 } }, 3), "abgelehnt")
end)

-- ---------------------------------------------------------------------------
-- E-02 / E-15: No-Show
-- ---------------------------------------------------------------------------

case("E-02: wer nicht bereit meldet, verliert nach dem Timer", function()
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 1,
                                noShowTimeout = 180 })
    H.allOnline(t, sched)
    sched:update(0)
    local id = t.rounds[1].matches[1]
    local m = t.matches[id]

    sched:confirmReady(id, m.slotA, 10)
    sched:update(100)
    assertEq(t.matches[id].status, Model.STATUS.READY, "der Timer laeuft noch")

    sched:update(180)
    assertEq(t.matches[id].status, Model.STATUS.WALKOVER, "abgelaufen")
    assertEq(t.matches[id].winner, m.slotA, "der Anwesende gewinnt")
    assertEq(t.matches[id].reason, "no_show", "mit Grund im Log")
end)

case("E-15: erscheint keiner, gewinnt der hoeher Gesetzte -- kein Muenzwurf", function()
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 1,
                                noShowTimeout = 60 })
    H.allOnline(t, sched)
    sched:update(0)
    local id = t.rounds[1].matches[1]
    local m = t.matches[id]

    sched:update(60)
    assertEq(t.matches[id].status, Model.STATUS.WALKOVER, "entschieden")
    assertEq(t.matches[id].winner, t:higherSeed(m.slotA, m.slotB), "der hoeher Gesetzte")
    assertEq(t.matches[id].reason, "no_show_both", "und es steht im Log, warum")
end)

case("E-02: der Turnierleiter kann den Timer anhalten", function()
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 1,
                                noShowTimeout = 100 })
    H.allOnline(t, sched)
    sched:update(0)
    local id = t.rounds[1].matches[1]

    sched:pauseNoShow(id, true, 50)
    sched:update(500)
    assertEq(t.matches[id].status, Model.STATUS.READY, "angehalten heisst angehalten")

    sched:pauseNoShow(id, false, 500)
    sched:update(500)
    assertEq(t.matches[id].status, Model.STATUS.READY,
        "nach dem Fortsetzen laeuft der Rest der Frist")

    sched:update(600)
    assertEq(t.matches[id].status, Model.STATUS.WALKOVER, "dann greift er")
end)

-- ---------------------------------------------------------------------------
-- E-16: der offline gebliebene Teilnehmer
-- ---------------------------------------------------------------------------

case("E-16: ein Match, das nur an einem Offline-Spieler haengt, laeuft in den Timer", function()
    local t, sched = setup(4, { format = "single_elim", parallelMatches = 2,
                                noShowTimeout = 90, thirdPlaceMatch = false })
    H.allOnline(t, sched, { p_04 = true })   -- p_04 ist nicht da

    sched:update(0)
    local id
    for _, mid in ipairs(t.matchOrder) do
        local m = t.matches[mid]
        if m.slotA == "p_01" and m.slotB == "p_04" then id = mid end
    end
    assertTrue(id ~= nil, "das Match p_01 gegen p_04 existiert")
    assertEq(t.matches[id].status, Model.STATUS.PENDING, "es wird nicht aufgerufen")

    sched:update(89)
    assertEq(t.matches[id].status, Model.STATUS.PENDING, "der Timer laeuft noch")

    sched:update(90)
    assertEq(t.matches[id].status, Model.STATUS.WALKOVER, "abgelaufen")
    assertEq(t.matches[id].winner, "p_01", "der Anwesende gewinnt")
    assertEq(t.matches[id].reason, "offline", "Grund im Log")
end)

case("E-16: der Timer startet erst, wenn das Match sonst spielbar waere", function()
    -- p_04 fehlt. Das FOLGEMATCH (Finale) darf nicht mitlaufen -- dort steht
    -- noch gar nicht fest, wer spielt.
    local t, sched = setup(4, { format = "single_elim", parallelMatches = 2,
                                noShowTimeout = 90, thirdPlaceMatch = false })
    H.allOnline(t, sched, { p_04 = true })
    sched:update(0)

    local final = t.matches[t.rounds[2].matches[1]]
    assertEq(sched.blockedSince[final.id], nil, "das Finale laeuft in keinen Timer")

    local semi
    for _, mid in ipairs(t.matchOrder) do
        local m = t.matches[mid]
        if m.slotA == "p_01" and m.slotB == "p_04" then semi = m end
    end
    assertEq(sched.blockedSince[semi.id], 0, "das blockierte Halbfinale schon")
end)

case("E-16: kommt er rechtzeitig, faengt der Timer von vorne an", function()
    local t, sched = setup(4, { format = "single_elim", parallelMatches = 2,
                                noShowTimeout = 90, thirdPlaceMatch = false })
    H.allOnline(t, sched, { p_04 = true })
    sched:update(0)
    sched:update(80)

    sched:setOnline("p_04", true)
    sched:update(81)

    local id
    for _, mid in ipairs(t.matchOrder) do
        local m = t.matches[mid]
        if m.slotA == "p_01" and m.slotB == "p_04" then id = mid end
    end
    assertEq(t.matches[id].status, Model.STATUS.READY, "aufgerufen statt verloren")
    assertEq(sched.blockedSince[id], nil, "der Blockade-Timer ist weg")
end)

-- ---------------------------------------------------------------------------
-- E-04 / E-06
-- ---------------------------------------------------------------------------

case("E-04: ein Aussteiger verschenkt alle ausstehenden Matches", function()
    local t, sched = setup(5, { format = "round_robin", parallelMatches = 1 })
    H.allOnline(t, sched)
    sched:update(0)

    sched:withdraw("p_03", 10)

    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.slotARef == "p_03" or m.slotBRef == "p_03" then
            assertEq(m.status, Model.STATUS.WALKOVER, id .. " ist entschieden")
            assertTrue(m.winner ~= "p_03", "und zwar gegen den Aussteiger")
        end
    end
    assertEq(t.participants["p_03"].status, "withdrawn", "Status")
end)

case("E-04: bereits gespielte Ergebnisse des Aussteigers bleiben gewertet", function()
    local t, sched = setup(5, { format = "round_robin", parallelMatches = 4 })
    H.allOnline(t, sched)
    sched:update(0)

    local played
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if (m.slotA == "p_03" or m.slotB == "p_03")
           and m.status == Model.STATUS.READY then
            sched:confirmReady(id, m.slotA, 0)
            sched:confirmReady(id, m.slotB, 0)
            sched:update(1)
            sched:reportResult(id, H.setsFor(m, "p_03"), 2)
            played = id
            break
        end
    end
    assertTrue(played ~= nil, "ein Match ist gespielt")

    sched:withdraw("p_03", 10)
    assertEq(t.matches[played].status, Model.STATUS.FINISHED, "das Ergebnis steht noch")
    assertEq(t.matches[played].winner, "p_03", "und zwar so, wie es ausging")
end)

case("wer zuerst aussteigt, verschenkt das Match -- nicht der Zweite", function()
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 1 })
    H.allOnline(t, sched)
    sched:update(0)
    sched:withdraw("p_01", 10)
    sched:withdraw("p_08", 11)

    local id = t.rounds[1].matches[1]
    assertEq(t.matches[id].status, Model.STATUS.WALKOVER, "entschieden")
    assertEq(t.matches[id].winner, "p_08", "als p_01 ging, war p_08 noch dabei")
    assertEq(t.matches[id].reason, "withdrawn", "Grund im Log")
end)

case("steigen beide aus, bevor der Scheduler drankommt, entscheidet die Setznummer", function()
    -- Der Fall tritt auf, wenn zwei Trennungen in derselben Netzwerkabfrage
    -- ankommen: Beide Ereignisse sind im Log, bevor `update` sie sieht.
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 1 })
    H.allOnline(t, sched)
    sched:update(0)

    t:append({ event = "participant_withdrawn", participantId = "p_01", at = 10 })
    t:append({ event = "participant_withdrawn", participantId = "p_08", at = 10 })
    sched:update(11)

    local id = t.rounds[1].matches[1]
    assertEq(t.matches[id].status, Model.STATUS.WALKOVER, "entschieden")
    assertEq(t.matches[id].winner, "p_01", "der hoeher Gesetzte")
    assertEq(t.matches[id].reason, "both_withdrawn", "Grund im Log")
end)

case("E-06: ein Absturz gibt keinen Walkover, sondern eine Neuansetzung", function()
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 1 })
    H.allOnline(t, sched)
    sched:update(0)
    local id = t.rounds[1].matches[1]
    local m = t.matches[id]
    sched:confirmReady(id, m.slotA, 0)
    sched:confirmReady(id, m.slotB, 0)
    sched:update(1)
    assertEq(t.matches[id].status, Model.STATUS.LIVE, "laeuft")

    sched:abortMatch(id, "host_lost", 5)
    assertEq(t.matches[id].status, Model.STATUS.PENDING, "zurueck in die Schlange")
    assertEq(t.matches[id].winner, nil, "und ohne Sieger")

    sched:update(6)
    assertEq(t.matches[id].status, Model.STATUS.READY, "sofort neu aufgerufen")
end)

-- ---------------------------------------------------------------------------
-- E-12
-- ---------------------------------------------------------------------------

case("E-12: eine Korrektur ohne Begruendung wird abgelehnt", function()
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 1 })
    local id = t.rounds[1].matches[1]
    local ok, why = sched:override(id, { { a = 15, b = 0 } }, "p_01", nil, "leitung", 0)
    assertFalse(ok, "abgelehnt")
    assertTrue(why:find("Begruendung") ~= nil, "mit Hinweis: " .. tostring(why))

    assertTrue(sched:override(id, { { a = 15, b = 0 } }, "p_01",
                              "Ergebnis vertauscht gemeldet", "leitung", 0), "so geht es")
    assertTrue(t.matches[id].overridden, "und ist markiert")
end)

-- ---------------------------------------------------------------------------
-- E-11 / E-17: Stichsatz
-- ---------------------------------------------------------------------------

-- Drei Spieler im Kreis: p_01 schlaegt p_02, p_02 schlaegt p_03, p_03 schlaegt
-- p_01 -- und zwar jeder mit demselben Ergebnis. Damit sind alle vier
-- Kriterien aus E-11 unentschieden.
local CYCLE = { p_01 = "p_02", p_02 = "p_03", p_03 = "p_01" }
local function cyclicWinner(_, m)
    if CYCLE[m.slotA] == m.slotB then return m.slotA end
    return m.slotB
end

case("E-11: ein echter Gleichstand setzt einen Stichsatz an", function()
    local t, sched = setup(3, { format = "round_robin", parallelMatches = 3 })
    H.allOnline(t, sched)

    -- Nur die Gruppenphase spielen.
    local now = 0
    for _ = 1, 20 do
        sched:update(now)
        for _, id in ipairs(t.matchOrder) do
            local m = t.matches[id]
            if m.status == Model.STATUS.READY then
                sched:confirmReady(id, m.slotA, now)
                sched:confirmReady(id, m.slotB, now)
            end
        end
        sched:update(now)
        for _, id in ipairs(t.matchOrder) do
            local m = t.matches[id]
            if m.status == Model.STATUS.LIVE and m.stage == "group" then
                sched:reportResult(id, H.setsFor(m, cyclicWinner(t, m)), now)
            end
        end
        now = now + 10
    end

    local tiebreaks = 0
    for _, id in ipairs(t.matchOrder) do
        if t.matches[id].stage == "tiebreak" then
            tiebreaks = tiebreaks + 1
            assertEq(t.matches[id].targetScore, 7, "Stichsatz auf 7 Punkte")
            assertEq(t.matches[id].bestOf, 1, "ein Satz")
        end
    end
    assertEq(tiebreaks, 3, "drei Gleichstehende ergeben drei Stichsaetze")
    assertEq(t.status, Model.TOURNAMENT_STATUS.RUNNING, "das Turnier laeuft weiter")
end)

case("E-17: geht auch der Stichsatz im Kreis aus, entscheidet die Setznummer", function()
    local t, sched = setup(3, { format = "round_robin", parallelMatches = 3 })
    H.allOnline(t, sched)
    H.play(t, sched, { winnerOf = cyclicWinner, limit = 200 })

    assertEq(t.status, Model.TOURNAMENT_STATUS.FINISHED, "es endet -- das ist der Punkt")
    assertEq(t.winner, "p_01", "die kleinste Setznummer")

    local tiebreakRounds = 0
    for _, ev in ipairs(t.log) do
        if ev.event == "tiebreak_added" then tiebreakRounds = tiebreakRounds + 1 end
    end
    assertEq(tiebreakRounds, 1, "genau eine Stichsatzrunde, keine zweite")
end)

case("bei klarer Tabelle gibt es keinen Stichsatz", function()
    local t, sched = setup(5, { format = "round_robin", parallelMatches = 2 })
    H.allOnline(t, sched)
    H.play(t, sched, { limit = 400 })

    assertEq(t.status, Model.TOURNAMENT_STATUS.FINISHED, "durchgelaufen")
    assertEq(t.winner, "p_01", "der Hoechstgesetzte gewinnt alles")
    for _, id in ipairs(t.matchOrder) do
        assertTrue(t.matches[id].stage ~= "tiebreak", "kein Stichsatz noetig")
    end
end)

-- ---------------------------------------------------------------------------
-- Terminierung
-- ---------------------------------------------------------------------------

case("kein Match wird zweimal live", function()
    local t, sched = setup(16, { format = "single_elim", parallelMatches = 4 })
    H.allOnline(t, sched)
    H.play(t, sched, { limit = 500 })

    for id, count in pairs(H.liveCounts(t)) do
        assertEq(count, 1, id .. " ist mehrfach gestartet")
    end
    assertEq(t.status, Model.TOURNAMENT_STATUS.FINISHED, "und es endet")
end)

case("ein Turnier, bei dem NIEMAND spielt, endet trotzdem", function()
    -- Der Fall, der ohne ADR-021 ewig laufen wuerde: alle offline, keiner
    -- meldet sich bereit. Nach den Fristen ist trotzdem ein Sieger da.
    local t, sched = setup(8, { format = "single_elim", parallelMatches = 4,
                                noShowTimeout = 30 })
    -- niemand online
    local now = 0
    for _ = 1, 200 do
        if t.status ~= Model.TOURNAMENT_STATUS.RUNNING then break end
        sched:update(now)
        now = now + 10
    end
    assertEq(t.status, Model.TOURNAMENT_STATUS.FINISHED, "beendet: " .. H.describeOpen(t))
    assertEq(t.winner, "p_01", "durchgereicht an die kleinste Setznummer")
end)

return T
