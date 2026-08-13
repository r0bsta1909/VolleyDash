-- ============================================================================
-- tests/tournament_run_test.lua -- Ebene B: der Durchlauf (M4-01 … M4-06)
--
-- Das ist die Abnahme der Stufe A aus Handoff CC-05:
--
--   "Nach Stufe A muss ein vollstaendiges 20er-Turnier headless durchlaufen --
--    angelegt, ausgelost, alle 48 Matches gespielt, Sieger, Neustart
--    mittendrin. Ohne Netzwerk, ohne Bild, im Testrunner."
--
-- Dazu die Abnahmekriterien 1 bis 4 aus `05_TOURNAMENT` §13. Punkt 5 (Export)
-- gehoert zu M4-10 und steht hier noch nicht.
--
-- Der Neustart ist der Fall, der das Modul traegt. Er wird deshalb nicht
-- nachgestellt, sondern durchgefuehrt: Das Turnierobjekt wird WEGGEWORFEN und
-- ausschliesslich aus der Datei neu aufgebaut. Was danach noch stimmt, stimmt
-- wirklich.
--
-- love-frei.
-- ============================================================================

local Model       = require("src.tournament.model")
local Scheduler   = require("src.tournament.scheduler")
local Persistence = require("src.tournament.persistence")
local H           = require("tests.tournament_helper")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local assertEq, assertTrue = H.assertEq, H.assertTrue

local CONFIG = {
    parallelMatches = 4,     -- ADR-013: bei 20 Teilnehmern nicht optional
    noShowTimeout   = 180,
    bestOfDefault   = 1,
    bestOfFinals    = 3,
    targetScore     = 15,
    thirdPlaceMatch = true,
    advancePerGroup = 2,
}

local SEED = "LAN-2026"

-- ---------------------------------------------------------------------------
-- Antrieb
--
-- Eigene Schleife statt `H.play`, weil hier nach JEDEM Schritt Zusicherungen
-- gelten -- nicht nur am Ende.
-- ---------------------------------------------------------------------------

local function newRun(persistence)
    local t = H.newTournament(20, CONFIG, { id = "t_1754900000", name = "Sommer-LAN 2026" })
    if persistence then persistence:attach(t) end
    H.draw(t, { seedMode = "random", seedValue = SEED })
    local sched = Scheduler.new(t)
    H.allOnline(t, sched)
    return t, sched
end

-- `opts.stopAt(t, now)` bricht ab und gibt die Kontrolle zurueck.
local function drive(t, sched, opts)
    opts = opts or {}
    local now   = opts.start or 0
    local guard = 0
    local maxActive = opts.maxActive or 0

    while t.status == Model.TOURNAMENT_STATUS.RUNNING do
        guard = guard + 1
        if guard > 2000 then error("Turnier haengt: " .. H.describeOpen(t), 2) end

        sched:update(now)

        local active = t:activeMatches()
        if active > maxActive then maxActive = active end
        if active > t.config.parallelMatches then
            error(string.format("%d Matches gleichzeitig, erlaubt sind %d",
                active, t.config.parallelMatches), 2)
        end

        if opts.stopAt and opts.stopAt(t, now) then return now, maxActive, true end

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
            if m.status == Model.STATUS.LIVE then
                sched:reportResult(id, H.setsFor(m, H.seedWins(t, m)), now)
            end
        end

        now = now + 10
    end

    return now, maxActive, false
end

-- Wer hat welches Match gewonnen? Der Vergleichsmassstab zwischen zwei Laeufen.
local function results(t)
    local out = {}
    for _, id in ipairs(t.matchOrder) do
        out[id] = t.matches[id].winner
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Der Durchlauf
-- ---------------------------------------------------------------------------

case("ein vollstaendiges 20er-Turnier laeuft headless durch", function()
    local t, sched = newRun()
    assertEq(#t.groups, 4, "vier Gruppen")
    assertEq(#t.matchOrder, 40, "40 Gruppenmatches ausgelost")

    local _, maxActive = drive(t, sched)

    assertEq(t.status, Model.TOURNAMENT_STATUS.FINISHED, "es endet")
    assertTrue(t.winner ~= nil, "mit einem Sieger")
    assertEq(t.participants[t.winner].status, "winner", "der auch so heisst")
    assertEq(maxActive, 4, "vier Matches liefen gleichzeitig -- die Parallelitaet greift")
end)

case("es sind genau 48 Matches -- 40 in den Gruppen, 8 im K.o.", function()
    local t, sched = newRun()
    drive(t, sched)

    local byStage = { group = 0, elim = 0, tiebreak = 0 }
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        byStage[m.stage] = (byStage[m.stage] or 0) + 1
    end
    assertEq(byStage.group, 40, "Gruppenphase")
    assertEq(byStage.elim, 8, "Viertelfinale, Halbfinale, Finale, Spiel um Platz 3")
    assertEq(byStage.tiebreak, 0, "kein Stichsatz noetig")
    assertEq(#t.matchOrder, 48, "insgesamt -- die Zahl aus 05_TOURNAMENT §2")
end)

case("alle 48 Matches sind gespielt, keins haengt", function()
    local t, sched = newRun()
    drive(t, sched)

    local counts = H.countByStatus(t)
    assertEq(counts.finished, 48, "alle abgeschlossen")
    assertEq(counts.pending, nil, "nichts offen")
    assertEq(counts.ready, nil, "nichts aufgerufen")
    assertEq(counts.live, nil, "nichts laufend")
    assertEq(counts.walkover, nil, "kein Walkover -- alle waren da")
end)

case("kein Match wird zweimal live", function()
    local t, sched = newRun()
    drive(t, sched)
    local counts = H.liveCounts(t)
    local n = 0
    for id, count in pairs(counts) do
        assertEq(count, 1, id .. " ist mehrfach gestartet")
        n = n + 1
    end
    assertEq(n, 48, "und jedes genau einmal")
end)

case("jeder Teilnehmer bekommt seine vier Gruppenmatches", function()
    -- Das ist der Grund fuer die Gruppenphase (§3): Bei reinem Single Elim
    -- haetten zehn Leute nach vier Minuten nichts mehr zu tun.
    local t, sched = newRun()
    drive(t, sched)

    for _, pid in ipairs(t.participantOrder) do
        local groupMatches = 0
        for _, id in ipairs(t.matchOrder) do
            local m = t.matches[id]
            if m.stage == "group" and (m.slotA == pid or m.slotB == pid) then
                groupMatches = groupMatches + 1
            end
        end
        assertEq(groupMatches, 4, pid .. " spielt vier Gruppenmatches")
    end
end)

case("ins K.o. kommen acht, zwei je Gruppe", function()
    local t, sched = newRun()
    drive(t, sched)

    local firstElimRound
    for _, r in ipairs(t.rounds) do
        if r.stage == "elim" and (not firstElimRound or r.index < firstElimRound) then
            firstElimRound = r.index
        end
    end

    local groupOf, seen = {}, {}
    for gi, members in ipairs(t.groups) do
        for _, id in ipairs(members) do groupOf[id] = gi end
    end
    local perGroup = {}

    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.stage == "elim" and m.round == firstElimRound then
            for _, pid in ipairs({ m.slotA, m.slotB }) do
                assertTrue(not seen[pid], pid .. " steht zweimal im Viertelfinale")
                seen[pid] = true
                perGroup[groupOf[pid]] = (perGroup[groupOf[pid]] or 0) + 1
            end
            assertTrue(groupOf[m.slotA] ~= groupOf[m.slotB],
                "Gruppengegner treffen sofort wieder aufeinander: " .. id)
        end
    end
    for gi = 1, 4 do assertEq(perGroup[gi], 2, "zwei aus Gruppe " .. gi) end
end)

case("das Finale ist Best-of-3, die Gruppenphase Best-of-1", function()
    local t, sched = newRun()
    drive(t, sched)

    local final = t:finalMatch()
    assertEq(final.bestOf, 3, "Finale")
    assertEq(#final.sets, 2, "zwei Saetze gespielt")

    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.stage == "group" then assertEq(m.bestOf, 1, "Gruppenmatch " .. id) end
    end
end)

case("die Setzung aus einem sichtbaren Seed ist reproduzierbar", function()
    local a = select(1, newRun())
    local b = select(1, newRun())
    for _, pid in ipairs(a.participantOrder) do
        assertEq(b.participants[pid].seed, a.participants[pid].seed,
            "Setznummer von " .. pid)
    end
    assertEq(a.seedValue, SEED, "der Seed steht im Zustand und ist anzeigbar")
end)

-- ---------------------------------------------------------------------------
-- 05_TOURNAMENT §13.2: der harte Neustart in Runde 2
-- ---------------------------------------------------------------------------

case("Neustart mitten in Runde 2 -- durchgefuehrt, nicht nachgestellt", function()
    -- Massstab: derselbe Ablauf ohne Stoerung.
    local refT, refSched = newRun()
    drive(refT, refSched)
    local reference = results(refT)

    -- Lauf B mit Persistenz.
    local persistence, fs = (function()
        local p = Persistence.new(H.fakeFs())
        return p, p.fs
    end)()
    local t, sched = newRun(persistence)

    -- Bis mitten in Runde 2 spielen: Runde 2 hat angefangen, ist aber offen.
    local stopped
    local now
    now, _, stopped = drive(t, sched, {
        stopAt = function(cur)
            local done, open = 0, 0
            for _, id in ipairs(cur.matchOrder) do
                local m = cur.matches[id]
                if m.round == 2 and m.stage == "group" then
                    if Model.TERMINAL[m.status] then done = done + 1 else open = open + 1 end
                end
            end
            return done >= 2 and open >= 2
        end,
    })
    assertTrue(stopped, "der Abbruchpunkt wurde erreicht")
    assertEq(Persistence.currentRound(t), 2, "wir stehen in Runde 2")

    local logBefore = #t.log
    local liveBefore = t:activeMatches()

    -- Der harte Abbruch: Prozess weg. Alles, was bleibt, ist die Datei.
    t, sched = nil, nil

    local open = persistence:running()
    assertEq(#open, 1, "der Dialog aus §7 findet genau ein laufendes Turnier")
    assertEq(open[1].name, "Sommer-LAN 2026", "mit Namen")
    assertEq(open[1].round, 2, "und Rundenangabe fuer den Dialogtext")

    local restored, source = persistence:load(open[1].id)
    assertTrue(restored ~= nil, "wiederhergestellt")
    assertEq(source, "json", "aus der regulaeren Datei")
    assertEq(#restored.log, logBefore, "vollstaendig bis zum letzten Ereignis")

    persistence:attach(restored)
    local reopened = Persistence.resume(restored, now)
    assertEq(#reopened, liveBefore, "die unterbrochenen Matches werden neu angesetzt")

    local sched2 = Scheduler.new(restored)
    H.allOnline(restored, sched2)
    drive(restored, sched2, { start = now + 10 })

    assertEq(restored.status, Model.TOURNAMENT_STATUS.FINISHED, "es laeuft zu Ende")
    assertEq(restored.winner, refT.winner, "derselbe Sieger wie ohne Stoerung")

    local after = results(restored)
    for id, winner in pairs(reference) do
        assertEq(after[id], winner, "Ergebnis von " .. id)
    end
    assertEq(#restored.matchOrder, 48, "und immer noch 48 Matches")

    -- Die Neuansetzung steht im Log -- nachvollziehbar, nicht stillschweigend.
    local restarts = 0
    for _, ev in ipairs(restored.log) do
        if ev.event == "match_aborted" and ev.reason == "host_restart" then
            restarts = restarts + 1
        end
    end
    assertEq(restarts, liveBefore, "je unterbrochenem Match ein Eintrag")
    local _ = fs
end)

case("nach dem Neustart ist das Log immer noch die Wahrheit", function()
    local persistence = Persistence.new(H.fakeFs())
    local t, sched = newRun(persistence)
    drive(t, sched, {
        stopAt = function(cur)
            local done = 0
            for _, id in ipairs(cur.matchOrder) do
                if cur.matches[id].round == 2 and Model.TERMINAL[cur.matches[id].status] then
                    done = done + 1
                end
            end
            return done >= 3
        end,
    })

    local restored = persistence:load("t_1754900000")
    persistence:attach(restored)
    Persistence.resume(restored, 1000)
    local sched2 = Scheduler.new(restored)
    H.allOnline(restored, sched2)
    drive(restored, sched2, { start = 1010 })

    local rebuilt = Model.replay(restored.log)
    local same, differences = Model.diff(restored, rebuilt)
    assertTrue(same, "identisch: " .. table.concat(differences, "\n  "))
end)

-- ---------------------------------------------------------------------------
-- 05_TOURNAMENT §13: die uebrigen Abnahmekriterien
-- ---------------------------------------------------------------------------

case("§13.1: ein 8er Single Elim laeuft ohne einen einzigen Eingriff durch", function()
    local t = H.newTournament(8, { format = "single_elim", parallelMatches = 2 })
    H.draw(t, { seedMode = "random", seedValue = SEED })
    local sched = Scheduler.new(t)
    H.allOnline(t, sched)

    drive(t, sched)
    assertEq(t.status, Model.TOURNAMENT_STATUS.FINISHED, "durchgelaufen")
    assertEq(H.playedCount(t), 8, "sieben Baummatches plus Spiel um Platz 3")
end)

case("§13.3: ein No-Show schreibt das Bracket korrekt fort", function()
    local t = H.newTournament(8, { format = "single_elim", parallelMatches = 4,
                                   noShowTimeout = 180 })
    H.draw(t)
    local sched = Scheduler.new(t)
    H.allOnline(t, sched)

    -- p_08 ist online, meldet aber nie bereit -- er sitzt nicht am Rechner.
    local absent = { p_08 = true }
    local now, guard = 0, 0
    while t.status == Model.TOURNAMENT_STATUS.RUNNING and guard < 500 do
        guard = guard + 1
        sched:update(now)
        for _, id in ipairs(t.matchOrder) do
            local m = t.matches[id]
            if m.status == Model.STATUS.READY then
                if not absent[m.slotA] then sched:confirmReady(id, m.slotA, now) end
                if not absent[m.slotB] then sched:confirmReady(id, m.slotB, now) end
            end
        end
        sched:update(now)
        for _, id in ipairs(t.matchOrder) do
            local m = t.matches[id]
            if m.status == Model.STATUS.LIVE then
                sched:reportResult(id, H.setsFor(m, H.seedWins(t, m)), now)
            end
        end
        now = now + 60
    end

    assertEq(t.status, Model.TOURNAMENT_STATUS.FINISHED, "es endet trotzdem")
    local walkovers = 0
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.status == Model.STATUS.WALKOVER then
            walkovers = walkovers + 1
            assertEq(m.reason, "no_show", "als No-Show protokolliert")
            assertTrue(m.winner ~= "p_08", "und gegen den Abwesenden entschieden")
        end
    end
    assertEq(walkovers, 1, "genau ein Walkover -- danach ist p_08 raus")
    assertEq(t.participants["p_08"].status, "eliminated", "ausgeschieden")
end)

case("§13.4: Round Robin mit fuenf Spielern und Gleichstand auf Platz 1", function()
    local t = H.newTournament(5, { format = "round_robin", parallelMatches = 2 })
    H.draw(t)
    local sched = Scheduler.new(t)
    H.allOnline(t, sched)

    -- Zwei Ausrutscher, sonst gewinnt der hoeher Gesetzte: p_02 schlaegt p_01,
    -- p_05 schlaegt p_02. Damit stehen p_01 und p_02 beide bei drei Siegen und
    -- der direkte Vergleich muss entscheiden.
    local UPSETS = { ["p_01|p_02"] = "p_02", ["p_02|p_05"] = "p_05" }
    local function winnerOf(_, m)
        local a, b = m.slotA, m.slotB
        local key = (a < b) and (a .. "|" .. b) or (b .. "|" .. a)
        return UPSETS[key] or H.seedWins(t, m)
    end

    H.play(t, sched, { winnerOf = winnerOf, limit = 400 })

    assertEq(t.status, Model.TOURNAMENT_STATUS.FINISHED, "durchgelaufen")
    local table1 = t.standings[1]
    assertEq(table1.rows[1].wins, 3, "der Erste hat drei Siege")
    assertEq(table1.rows[2].wins, 3, "der Zweite auch")
    assertEq(table1.rows[1].id, "p_02", "der direkte Vergleich entscheidet (E-11)")
    assertEq(t.winner, "p_02", "und damit das Turnier")
    for _, id in ipairs(t.matchOrder) do
        assertTrue(t.matches[id].stage ~= "tiebreak",
            "kein Stichsatz -- der direkte Vergleich hat gereicht")
    end
end)

return T
