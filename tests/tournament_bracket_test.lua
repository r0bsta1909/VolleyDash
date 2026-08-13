-- ============================================================================
-- tests/tournament_bracket_test.lua -- Ebene B: Auslosung und Tabellen
--                                     (M4-02, M4-02b, M4-03, M4-04)
--
-- Der Kern dieser Suite ist die Schleife ueber JEDE Teilnehmerzahl von 4 bis
-- 32. Ein Bracket, das bei 18 Teilnehmern eine Zweiergruppe baut, faellt von
-- Hand niemandem auf -- man probiert 8 und 16 und ist zufrieden. Genau
-- deshalb steht der Fall hier.
--
-- love-frei.
-- ============================================================================

local Bracket = require("src.tournament.bracket")
local H       = require("tests.tournament_helper")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local assertEq, assertTrue, assertList = H.assertEq, H.assertTrue, H.assertList

local CONFIG = {
    bestOfDefault = 1, bestOfFinals = 3, targetScore = 15,
    thirdPlaceMatch = true, advancePerGroup = 2,
}

local function ids(n)
    local out = {}
    for i = 1, n do out[i] = H.participantId(i) end
    return out
end

-- ---------------------------------------------------------------------------
-- Der eigene Zufallsgenerator
-- ---------------------------------------------------------------------------

case("der sichtbare Seed ergibt immer dieselbe Zahl", function()
    -- Festgenagelt, nicht nachgerechnet: Aendert sich das Verfahren, ergibt
    -- derselbe angeschriebene Seed ein anderes Bracket -- und genau das darf
    -- nicht unbemerkt passieren (§9).
    assertEq(Bracket.seedNumber("LAN-2026"), 3825522519, "djb2 von LAN-2026")
    assertEq(Bracket.seedNumber("Sommer-LAN 2026"), 684384842, "djb2 von Sommer-LAN 2026")
end)

case("derselbe Seed mischt gleich, ein anderer Seed anders", function()
    local a = Bracket.rng("LAN-2026"):shuffle(ids(20))
    local b = Bracket.rng("LAN-2026"):shuffle(ids(20))
    assertList(a, b, "zweimal derselbe Seed")

    local c = Bracket.rng("LAN-2027"):shuffle(ids(20))
    local same = true
    for i = 1, 20 do if a[i] ~= c[i] then same = false break end end
    assertTrue(not same, "anderer Seed ergibt eine andere Reihenfolge")
end)

case("der Generator bleibt in seinen Grenzen und trifft jeden Wert", function()
    local rng = Bracket.rng(1)
    local seen = {}
    for _ = 1, 4000 do
        local v = rng:int(6)
        assertTrue(v >= 1 and v <= 6, "int(6) in 1..6")
        seen[v] = true
    end
    for v = 1, 6 do assertTrue(seen[v], "Wert " .. v .. " kam vor") end
end)

case("mischen verliert und verdoppelt niemanden", function()
    local list = Bracket.rng("x"):shuffle(ids(32))
    local seen = {}
    assertEq(#list, 32, "Laenge")
    for _, id in ipairs(list) do
        assertTrue(not seen[id], "kein Doppel: " .. id)
        seen[id] = true
    end
end)

-- ---------------------------------------------------------------------------
-- Setzreihenfolge
-- ---------------------------------------------------------------------------

case("die klassische Setzreihenfolge stimmt", function()
    assertList(Bracket.seedOrder(2), { 1, 2 }, "2er")
    assertList(Bracket.seedOrder(4), { 1, 4, 2, 3 }, "4er")
    assertList(Bracket.seedOrder(8), { 1, 8, 4, 5, 2, 7, 3, 6 }, "8er")
end)

case("in der Setzreihenfolge kommt jede Nummer genau einmal vor", function()
    for _, size in ipairs({ 2, 4, 8, 16, 32 }) do
        local order, seen = Bracket.seedOrder(size), {}
        assertEq(#order, size, "Laenge " .. size)
        for _, s in ipairs(order) do
            assertTrue(not seen[s], "kein Doppel bei " .. size)
            seen[s] = true
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Gruppenaufteilung (M4-02b)
-- ---------------------------------------------------------------------------

case("die beiden Faelle aus der Spec stimmen genau", function()
    assertList(Bracket.groupSplit(20), { 5, 5, 5, 5 }, "20 Teilnehmer")
    assertList(Bracket.groupSplit(18), { 5, 5, 4, 4 }, "18 Teilnehmer")
end)

case("keine Gruppe faellt unter 3 oder ueber 6 -- fuer jede Zahl von 4 bis 32", function()
    for n = 4, 32 do
        local sizes, sum = Bracket.groupSplit(n), 0
        for _, size in ipairs(sizes) do
            assertTrue(size >= Bracket.GROUP_MIN,
                string.format("n=%d: Gruppe mit %d ist zu klein", n, size))
            assertTrue(size <= Bracket.GROUP_MAX,
                string.format("n=%d: Gruppe mit %d ist zu gross", n, size))
            sum = sum + size
        end
        assertEq(sum, n, string.format("n=%d: Summe der Gruppengroessen", n))
    end
end)

case("der Rest landet auf den vorderen Gruppen, nicht verstreut", function()
    for n = 4, 32 do
        local sizes = Bracket.groupSplit(n)
        for i = 2, #sizes do
            assertTrue(sizes[i] <= sizes[i - 1],
                string.format("n=%d: Gruppe %d ist groesser als %d", n, i, i - 1))
        end
    end
end)

case("die Schlangenlinie verteilt jeden genau einmal", function()
    for n = 4, 32 do
        local sizes  = Bracket.groupSplit(n)
        local groups = Bracket.buildGroups(ids(n), sizes)
        local seen, total = {}, 0
        assertEq(#groups, #sizes, "Gruppenzahl bei n=" .. n)
        for gi, members in ipairs(groups) do
            assertEq(#members, sizes[gi],
                string.format("n=%d: Groesse von Gruppe %d", n, gi))
            for _, id in ipairs(members) do
                assertTrue(not seen[id], string.format("n=%d: %s doppelt", n, id))
                seen[id] = true
                total = total + 1
            end
        end
        assertEq(total, n, "alle verteilt bei n=" .. n)
    end
end)

case("die Schlangenlinie legt die Topgesetzten in verschiedene Gruppen", function()
    local groups = Bracket.buildGroups(ids(20), Bracket.groupSplit(20))
    for gi = 1, 4 do
        assertEq(groups[gi][1], H.participantId(gi),
            "Setznummer " .. gi .. " fuehrt Gruppe " .. gi)
    end
end)

-- ---------------------------------------------------------------------------
-- Round Robin
-- ---------------------------------------------------------------------------

case("jeder spielt gegen jeden genau einmal", function()
    for n = 2, 8 do
        local rounds, seen, total = Bracket.roundRobin(ids(n)), {}, 0
        for _, round in ipairs(rounds) do
            for _, pair in ipairs(round) do
                local key = pair[1] < pair[2] and (pair[1] .. pair[2]) or (pair[2] .. pair[1])
                assertTrue(not seen[key], string.format("n=%d: %s doppelt", n, key))
                seen[key] = true
                total = total + 1
            end
        end
        assertEq(total, n * (n - 1) / 2, "Matchzahl bei n=" .. n)
    end
end)

case("in einer Runde spielt niemand zweimal -- das ist die Parallelitaet", function()
    for n = 2, 8 do
        for _, round in ipairs(Bracket.roundRobin(ids(n))) do
            local busy = {}
            for _, pair in ipairs(round) do
                for _, id in ipairs(pair) do
                    assertTrue(not busy[id],
                        string.format("n=%d: %s spielt zweimal in einer Runde", n, id))
                    busy[id] = true
                end
            end
        end
    end
end)

case("eine Fuenfergruppe braucht 5 Runden und 10 Matches", function()
    local rounds = Bracket.roundRobin(ids(5))
    assertEq(#rounds, 5, "Runden")
    local total = 0
    for _, round in ipairs(rounds) do
        assertEq(#round, 2, "Matches je Runde")
        total = total + #round
    end
    assertEq(total, 10, "Matches insgesamt")
end)

-- ---------------------------------------------------------------------------
-- Single Elimination (M4-02, E-01)
-- ---------------------------------------------------------------------------

local function elimOf(n, config)
    local idGen = Bracket.newIdGen(100)
    return Bracket.singleElim(ids(n), config or CONFIG, idGen)
end

case("bei acht Teilnehmern gibt es kein Freilos", function()
    local rounds, matches = elimOf(8)
    assertEq(#rounds, 3, "Runden")
    -- 7 echte Matches plus Spiel um Platz 3
    assertEq(#matches, 8, "Matches")
    for _, m in ipairs(matches) do
        assertTrue(m.slotARef ~= Bracket.BYE and m.slotBRef ~= Bracket.BYE, "kein Freilos")
    end
end)

case("die Freilose gehen an die hoechstgesetzten Spieler (E-01)", function()
    -- 12 Teilnehmer, 16er-Bracket, 4 Freilose -> Setznummern 1 bis 4.
    local _, matches = elimOf(12)
    local withBye = {}
    for _, m in ipairs(matches) do
        if m.slotARef == Bracket.BYE or m.slotBRef == Bracket.BYE then
            withBye[#withBye + 1] = (m.slotARef ~= Bracket.BYE) and m.slotARef or m.slotBRef
        end
    end
    assertEq(#withBye, 4, "vier Freilose")
    table.sort(withBye)
    assertList(withBye, { "p_01", "p_02", "p_03", "p_04" }, "Freilose")
end)

case("kein Freilos landet in Runde 2", function()
    for n = 4, 32 do
        local rounds, matches = elimOf(n)
        local firstRound = rounds[1].index
        for _, m in ipairs(matches) do
            if m.slotARef == Bracket.BYE or m.slotBRef == Bracket.BYE then
                assertEq(m.round, firstRound,
                    string.format("n=%d: Freilos in Runde %d", n, m.round))
            end
        end
    end
end)

case("jeder Teilnehmer kommt in Runde 1 genau einmal vor", function()
    for n = 4, 32 do
        local rounds, matches = elimOf(n)
        local seen, count = {}, 0
        for _, m in ipairs(matches) do
            if m.round == rounds[1].index then
                for _, ref in ipairs({ m.slotARef, m.slotBRef }) do
                    if ref ~= Bracket.BYE then
                        assertTrue(not seen[ref],
                            string.format("n=%d: %s zweimal in Runde 1", n, ref))
                        seen[ref] = true
                        count = count + 1
                    end
                end
            end
        end
        assertEq(count, n, string.format("n=%d: alle in Runde 1", n))
    end
end)

case("die Summe der Matches stimmt: n-1 echte plus Spiel um Platz 3", function()
    for n = 4, 32 do
        local _, matches = elimOf(n)
        local real = 0
        for _, m in ipairs(matches) do
            if m.slotARef ~= Bracket.BYE and m.slotBRef ~= Bracket.BYE then real = real + 1 end
        end
        -- Ein Freilosmatch entscheidet nichts, es besetzt nur einen Slot.
        assertEq(real, n - 1 + 1, string.format("n=%d: echte Matches", n))
    end
end)

case("Best-of-3 ab dem Halbfinale, nicht ab dem Viertelfinale", function()
    -- 05_TOURNAMENT §2, berichtigt 2026-08-13.
    local rounds, matches = elimOf(8)
    local byRound = {}
    for _, m in ipairs(matches) do
        byRound[m.round] = byRound[m.round] or {}
        table.insert(byRound[m.round], m)
    end
    for _, m in ipairs(byRound[1]) do assertEq(m.bestOf, 1, "Viertelfinale") end
    for _, m in ipairs(byRound[2]) do assertEq(m.bestOf, 3, "Halbfinale") end
    for _, m in ipairs(byRound[3]) do assertEq(m.bestOf, 3, "Finale") end
    assertEq(rounds[1].label, "Viertelfinale", "Beschriftung Runde 1")
    assertEq(rounds[3].label, "Finale", "Beschriftung Runde 3")
end)

case("das Spiel um Platz 3 haengt an den beiden Halbfinalverlierern", function()
    local rounds, matches = elimOf(8)
    local third
    for _, m in ipairs(matches) do if m.thirdPlace then third = m end end
    assertTrue(third ~= nil, "es gibt ein Spiel um Platz 3")
    local semi = rounds[2].matches
    assertEq(third.slotARef, Bracket.loserOf(semi[1]), "Slot A")
    assertEq(third.slotBRef, Bracket.loserOf(semi[2]), "Slot B")
end)

case("ohne Spiel um Platz 3 wird keins gebaut", function()
    local config = {}
    for k, v in pairs(CONFIG) do config[k] = v end
    config.thirdPlaceMatch = false
    local _, matches = elimOf(8, config)
    assertEq(#matches, 7, "nur die sieben Baummatches")
end)

-- ---------------------------------------------------------------------------
-- Tabelle und E-11
-- ---------------------------------------------------------------------------

local function match(a, b, sets, winner)
    return { slotA = a, slotB = b, sets = sets, winner = winner }
end

case("die Tabelle zaehlt Saetze und Punkte richtig", function()
    local rows = Bracket.tableRows({ "a", "b" }, {
        match("a", "b", { { a = 15, b = 9 } }, "a"),
    })
    assertEq(rows[1].wins, 1, "a gewinnt")
    assertEq(rows[1].pointsFor, 15, "a Punkte fuer")
    assertEq(rows[1].pointDiff, 6, "a Differenz")
    assertEq(rows[2].losses, 1, "b verliert")
    assertEq(rows[2].pointDiff, -6, "b Differenz")
end)

case("ein Walkover zaehlt als Sieg, aber ohne Punkte", function()
    local rows = Bracket.tableRows({ "a", "b" }, {
        { slotA = "a", slotB = "b", sets = {}, winner = "a" },
    })
    assertEq(rows[1].wins, 1, "Sieg gezaehlt")
    assertEq(rows[1].pointsFor, 0, "keine Punkte")
    assertEq(rows[1].setDiff, 0, "keine Saetze")
end)

case("E-11: der direkte Vergleich entscheidet vor der Satzdifferenz", function()
    -- a und b haben je einen Sieg; b hat gegen a gewonnen, a hat die bessere
    -- Punktdifferenz. Der direkte Vergleich steht vorn, also fuehrt b.
    local st = Bracket.standings({ "a", "b", "c" }, {
        match("a", "b", { { a = 5,  b = 15 } }, "b"),
        match("a", "c", { { a = 15, b = 0  } }, "a"),
        match("b", "c", { { a = 15, b = 13 } }, "b"),
    })
    assertEq(st.rows[1].id, "b", "b fuehrt mit zwei Siegen")
    assertEq(st.rows[2].id, "a", "a auf zwei")
    assertEq(st.rows[3].id, "c", "c auf drei")
    assertEq(#st.unresolved, 0, "nichts offen")
end)

case("E-11: Dreifach-Gleichstand wird der Reihe nach aufgeloest", function()
    -- a schlaegt b, b schlaegt c, c schlaegt a -- jeder ein Sieg, der direkte
    -- Vergleich trennt nicht. Also entscheidet die Satzdifferenz; die ist hier
    -- ueberall 0, dann die Punktdifferenz.
    local st = Bracket.standings({ "a", "b", "c" }, {
        match("a", "b", { { a = 15, b = 1  } }, "a"),
        match("b", "c", { { a = 15, b = 5  } }, "b"),
        match("c", "a", { { a = 15, b = 10 } }, "c"),
    })
    -- Punktdifferenzen: a 15+10-1-15 = +9, b 1+15-15-5 = -4, c 5+15-15-10 = -5
    assertEq(st.rows[1].id, "a", "a nach Punktdifferenz vorn")
    assertEq(st.rows[2].id, "b", "b auf zwei")
    assertEq(st.rows[3].id, "c", "c auf drei")
    assertEq(#st.unresolved, 0, "aufgeloest, kein Stichsatz noetig")
end)

case("E-11: ein echter Gleichstand wird gemeldet, nicht ausgewuerfelt", function()
    -- Spiegelbildliche Ergebnisse: Nach allen vier Kriterien identisch.
    local st = Bracket.standings({ "a", "b", "c" }, {
        match("a", "b", { { a = 15, b = 10 } }, "a"),
        match("b", "c", { { a = 15, b = 10 } }, "b"),
        match("c", "a", { { a = 15, b = 10 } }, "c"),
    })
    assertEq(#st.unresolved, 1, "ein offener Block")
    assertEq(#st.unresolved[1].ids, 3, "drei Gleichstehende")
    assertEq(st.unresolved[1].first, 1, "der Block beginnt auf Platz 1")
end)

case("der direkte Vergleich bleibt aussen vor, solange nicht alle gespielt haben", function()
    -- a und b haben je einen Sieg, aber nicht gegeneinander gespielt.
    local st = Bracket.standings({ "a", "b", "c", "d" }, {
        match("a", "c", { { a = 15, b = 1  } }, "a"),
        match("b", "d", { { a = 15, b = 12 } }, "b"),
    })
    -- Also entscheidet die Satzdifferenz (beide +1), dann die Punktdifferenz.
    assertEq(st.rows[1].id, "a", "a hat die bessere Punktdifferenz")
    assertEq(st.rows[2].id, "b", "b auf zwei")
end)

case("ein Gleichstand unterhalb der Trennlinie stoert nicht", function()
    -- Plaetze 3 und 4 stehen gleich, es kommen aber nur zwei weiter.
    local st = Bracket.standings({ "a", "b", "c", "d" }, {
        match("a", "b", { { a = 15, b = 5 } }, "a"),
        match("a", "c", { { a = 15, b = 5 } }, "a"),
        match("a", "d", { { a = 15, b = 5 } }, "a"),
        match("b", "c", { { a = 15, b = 5 } }, "b"),
        match("b", "d", { { a = 15, b = 5 } }, "b"),
        match("c", "d", { { a = 15, b = 5 } }, "c"),
    })
    local qualified = Bracket.qualifiers(st, 2)
    assertTrue(qualified ~= nil, "zwei kommen weiter, ohne Stichsatz")
    assertList(qualified, { "a", "b" }, "Weitergekommene")
end)

case("ein Gleichstand AUF der Trennlinie blockiert und wird gemeldet", function()
    local st = Bracket.standings({ "a", "b", "c" }, {
        match("a", "b", { { a = 15, b = 10 } }, "a"),
        match("b", "c", { { a = 15, b = 10 } }, "b"),
        match("c", "a", { { a = 15, b = 10 } }, "c"),
    })
    local qualified, block = Bracket.qualifiers(st, 2)
    assertEq(qualified, nil, "keine Entscheidung")
    assertEq(#block.ids, 3, "der Block, der im Weg steht")
end)

-- ---------------------------------------------------------------------------
-- Gruppen -> K.o. (M4-04)
-- ---------------------------------------------------------------------------

-- Baut aus n Teilnehmern eine vollstaendige, entschiedene Gruppenphase und
-- gibt Weitergekommene plus Tabellen zurueck.
local function playedGroups(n)
    local sizes  = Bracket.groupSplit(n)
    local groups = Bracket.buildGroups(ids(n), sizes)
    local qualified, standings = {}, {}

    for gi, members in ipairs(groups) do
        local played = {}
        for _, round in ipairs(Bracket.roundRobin(members)) do
            for _, pair in ipairs(round) do
                -- Der mit der kleineren Nummer gewinnt: strenge Ordnung, keine
                -- Gleichstaende.
                local winner = (pair[1] < pair[2]) and pair[1] or pair[2]
                local loser  = (winner == pair[1]) and pair[2] or pair[1]
                played[#played + 1] = {
                    slotA = pair[1], slotB = pair[2], winner = winner,
                    sets = { { a = (winner == pair[1]) and 15 or 7,
                               b = (winner == pair[1]) and 7 or 15 } },
                }
                local _ = loser
            end
        end
        standings[gi] = Bracket.standings(members, played)
        qualified[gi] = Bracket.qualifiers(standings[gi], 2)
    end
    return qualified, standings, groups
end

case("aus den Gruppen kommen genau zwei je Gruppe ins K.o.", function()
    local qualified, standings = playedGroups(20)
    assertEq(#qualified, 4, "vier Gruppen")
    local idGen = Bracket.newIdGen(500)
    local _, _, entrants = Bracket.elimFromGroups(qualified, standings, CONFIG, idGen,
                                                  { roundOffset = 5 })
    assertEq(#entrants, 8, "acht im K.o.")
end)

case("in der ersten K.o.-Runde treffen sich keine Gruppengegner -- 4 bis 32", function()
    for n = 8, 32 do
        local qualified, standings = playedGroups(n)
        if #qualified >= 2 then
            local groupOf = {}
            for gi, list in ipairs(qualified) do
                for _, id in ipairs(list) do groupOf[id] = gi end
            end

            local idGen = Bracket.newIdGen(500)
            local rounds, matches = Bracket.elimFromGroups(
                qualified, standings, CONFIG, idGen, { roundOffset = 10 })

            local firstRound = rounds[1].index
            for _, m in ipairs(matches) do
                if m.round == firstRound then
                    local kindA = Bracket.refKind(m.slotARef)
                    local kindB = Bracket.refKind(m.slotBRef)
                    if kindA == "participant" and kindB == "participant" then
                        assertTrue(groupOf[m.slotARef] ~= groupOf[m.slotBRef],
                            string.format("n=%d: %s und %s kommen beide aus Gruppe %s",
                                n, m.slotARef, m.slotBRef, tostring(groupOf[m.slotARef])))
                    end
                end
            end
        end
    end
end)

case("die Gruppenersten bekommen die vorderen Setznummern", function()
    local qualified, standings = playedGroups(20)
    local idGen = Bracket.newIdGen(500)
    local _, _, entrants = Bracket.elimFromGroups(qualified, standings, CONFIG, idGen)
    -- Die ersten vier Plaetze der Setzliste sind Gruppenerste.
    local firsts = {}
    for _, list in ipairs(qualified) do firsts[list[1]] = true end
    for i = 1, 4 do
        assertTrue(firsts[entrants[i]], "Setznummer " .. i .. " ist Gruppenerster")
    end
end)

-- ---------------------------------------------------------------------------
-- Die vollstaendige Auslosung
-- ---------------------------------------------------------------------------

case("20 Teilnehmer ergeben 4 Gruppen und 40 Gruppenmatches", function()
    local draw = Bracket.draw(ids(20),
        { format = "groups_then_elim", bestOfDefault = 1, bestOfFinals = 3,
          targetScore = 15, thirdPlaceMatch = true, advancePerGroup = 2 },
        { seedMode = "manual" })
    assertEq(#draw.groups, 4, "Gruppen")
    assertEq(#draw.matches, 40, "Gruppenmatches")
    assertEq(draw.groupRounds, 5, "Gruppenrunden")
    assertEq(#draw.rounds, 5, "Runden in der Auslosung")
    for _, round in ipairs(draw.rounds) do
        assertEq(#round.matches, 8, "acht Matches je Runde -- vier Gruppen mal zwei")
    end
end)

case("die Auslosung traegt die Setzliste, nicht nur den Seed", function()
    local draw = Bracket.draw(ids(8), { format = "single_elim", targetScore = 15 },
                              { seedMode = "random", seedValue = "LAN-2026" })
    assertEq(draw.seedValue, "LAN-2026", "der Seed steht drin")
    local seen = 0
    for _, seed in pairs(draw.seeds) do
        assertTrue(seed >= 1 and seed <= 8, "Setznummer in 1..8")
        seen = seen + 1
    end
    assertEq(seen, 8, "jeder hat eine Setznummer")
end)

case("zweimal dieselbe Auslosung ergibt dieselben Paarungen", function()
    local config = { format = "groups_then_elim", targetScore = 15, advancePerGroup = 2 }
    local a = Bracket.draw(ids(20), config, { seedMode = "random", seedValue = "LAN-2026" })
    local b = Bracket.draw(ids(20), config, { seedMode = "random", seedValue = "LAN-2026" })
    assertEq(#a.matches, #b.matches, "gleich viele Matches")
    for i = 1, #a.matches do
        assertEq(a.matches[i].slotARef, b.matches[i].slotARef, "Slot A von Match " .. i)
        assertEq(a.matches[i].slotBRef, b.matches[i].slotBRef, "Slot B von Match " .. i)
    end
end)

return T
