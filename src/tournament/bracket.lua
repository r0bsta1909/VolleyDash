-- ============================================================================
-- src/tournament/bracket.lua -- Auslosung, Paarungen, Tabellen
--                              (M4-02, M4-02b, M4-03, M4-04)
--
-- `05_TOURNAMENT` §3, §6 und §9. Reine Funktionen ueber reine Daten: rein
-- gehen Teilnehmerlisten und Ergebnisse, raus gehen Paarungen und Tabellen.
-- Kein Zustand, keine Zeit, kein `love`.
--
-- ---------------------------------------------------------------------------
-- Der eigene Zufallsgenerator (und warum `math.random` hier nicht geht)
-- ---------------------------------------------------------------------------
--
-- `05_TOURNAMENT` §9 verlangt eine Auslosung aus einem SICHTBAREN Seed -- dann
-- kann niemand behaupten, das Bracket sei manipuliert. Diese Zusage ist nur
-- etwas wert, wenn derselbe Seed ueberall dasselbe Bracket ergibt.
--
-- `math.random` leistet das nicht. Die Zahlenfolge haengt von der
-- Lua-Implementierung ab, und auf Apple Silicon laeuft der Interpreter statt
-- des JIT (`04_NETCODE` §1). Ein sichtbarer Seed, der auf dem Rechner des
-- Turnierleiters ein anderes Bracket erzeugt als auf dem Beamer-Rechner, ist
-- schlimmer als gar keiner -- er belegt die Manipulation, die er ausschliessen
-- soll.
--
-- Also derselbe Weg wie beim Ruleset-Hash (`CLAUDE.md` §7): selbst gerechnet,
-- klein, nachpruefbar. Ein linearer Kongruenzgenerator mit den Konstanten aus
-- Numerical Recipes. Die Multiplikation bleibt exakt in einem double:
-- 1664525 * (2^32 - 1) + 1013904223 liegt bei 7,15e15 und damit unter 2^53.
-- Reine Arithmetik, keine Bit-Bibliothek.
--
-- Das ist ausdruecklich KEIN Verstoss gegen die Anti-Zufalls-Doktrin
-- (`CLAUDE.md` §3.2). Verboten ist Varianz, die niemand nachvollziehen kann.
-- Eine Auslosung aus einem angeschriebenen Seed ist das Gegenteil davon: Sie
-- ist auf jedem Rechner nachrechenbar.
-- ============================================================================

local Bracket = {}

Bracket.TIEBREAK_TARGET = 7   -- E-11: Stichsatz auf 7 Punkte

-- ---------------------------------------------------------------------------
-- Zufall
-- ---------------------------------------------------------------------------

-- Aus einem sichtbaren Seed-Text eine Zahl machen. djb2, wie in `Ruleset.hash`
-- -- ein Verfahren im Projekt, nicht zwei.
function Bracket.seedNumber(text)
    if type(text) == "number" then return math.floor(text) % 4294967296 end
    local h = 5381
    for i = 1, #tostring(text) do
        h = (h * 33 + tostring(text):byte(i)) % 4294967296
    end
    return h
end

local Rng = {}
Rng.__index = Rng

function Bracket.rng(seed)
    return setmetatable({ state = Bracket.seedNumber(seed) }, Rng)
end

-- Gleitkommazahl in [0, 1). Es werden die HOHEN Bits benutzt -- die niedrigen
-- eines LCG sind schwach periodisch.
function Rng:next()
    self.state = (1664525 * self.state + 1013904223) % 4294967296
    return math.floor(self.state / 4096) / 1048576
end

-- Ganzzahl in 1..n.
function Rng:int(n)
    if n <= 1 then return 1 end
    local v = math.floor(self:next() * n) + 1
    return v > n and n or v
end

-- Fisher-Yates, an Ort und Stelle. Gibt die Liste zurueck.
function Rng:shuffle(list)
    for i = #list, 2, -1 do
        local j = self:int(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

-- ---------------------------------------------------------------------------
-- Kleinkram
-- ---------------------------------------------------------------------------

local function copyList(list)
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    return out
end

local function nextPow2(n)
    local p = 1
    while p < n do p = p * 2 end
    return p
end

-- Fortlaufende Match-Kennungen. Bewusst ein Objekt und keine globale Zaehlung:
-- Die K.o.-Phase wird spaeter ausgelost als die Gruppenphase, und die Kennungen
-- muessen ueber beide Stufen hinweg eindeutig bleiben.
function Bracket.newIdGen(start)
    local n = start or 100
    return function()
        n = n + 1
        return string.format("m_%d", n)
    end
end

-- Slot-Referenzen. Ein Slot ist entweder ein Teilnehmer, das Ergebnis eines
-- anderen Matches oder ein Freilos.
Bracket.BYE = "bye"

function Bracket.winnerOf(matchId) return "winner_of:" .. matchId end
function Bracket.loserOf(matchId)  return "loser_of:"  .. matchId end

function Bracket.refKind(ref)
    if ref == nil then return "empty" end
    if ref == Bracket.BYE then return "bye" end
    local id = ref:match("^winner_of:(.+)$")
    if id then return "winner_of", id end
    id = ref:match("^loser_of:(.+)$")
    if id then return "loser_of", id end
    return "participant", ref
end

-- ---------------------------------------------------------------------------
-- Setzung (§9)
-- ---------------------------------------------------------------------------

Bracket.SEED_MODES = { manual = true, random = true, by_rating = true }

-- Gibt die Teilnehmerkennungen in Setzreihenfolge zurueck: Index = Setznummer.
--
--   manual      Reihenfolge wie uebergeben (der Turnierleiter hat sortiert)
--   random      deterministisch aus `seedValue`
--   by_rating   nach `ranking[id]` absteigend, Gleichstand nach Eingangsfolge.
--               `ranking` sind Vorergebnisse DESSELBEN Abends (Scope-Out:
--               alles darueber ist M6)
function Bracket.assignSeeds(participantIds, mode, seedValue, ranking)
    local ids = copyList(participantIds)

    if mode == "random" then
        Bracket.rng(seedValue or 0):shuffle(ids)
    elseif mode == "by_rating" then
        local order = {}
        for i, id in ipairs(ids) do order[id] = i end
        table.sort(ids, function(a, b)
            local ra, rb = (ranking and ranking[a]) or 0, (ranking and ranking[b]) or 0
            if ra ~= rb then return ra > rb end
            return order[a] < order[b]
        end)
    end

    return ids
end

-- ---------------------------------------------------------------------------
-- Gruppenaufteilung (§3, M4-02b)
--
-- Ziel 4-5 je Gruppe. Gewaehlt wird die Gruppenzahl, deren Groessen am
-- wenigsten von 4,5 abweichen; bei Gleichstand die groessere Gruppenzahl,
-- weil mehr Gruppen mehr parallel spielbare Matches bedeuten (ADR-013).
-- Zulaessig sind nur Aufteilungen, in denen JEDE Gruppe zwischen 3 und 6
-- Mitgliedern hat.
--
-- Ergibt fuer die beiden Faelle aus §3 genau das Geforderte:
--   20 Teilnehmer -> 4 x 5
--   18 Teilnehmer -> 5, 5, 4, 4
-- ---------------------------------------------------------------------------

Bracket.GROUP_MIN, Bracket.GROUP_MAX = 3, 6
local GROUP_IDEAL = 4.5

local function sizesFor(n, groupCount)
    local base = math.floor(n / groupCount)
    local rest = n - base * groupCount
    local sizes = {}
    for i = 1, groupCount do
        sizes[i] = base + (i <= rest and 1 or 0)   -- Rest auf die vorderen Gruppen
    end
    return sizes
end

function Bracket.groupSplit(n)
    if n < Bracket.GROUP_MIN then return { n } end

    local best, bestCost
    for groupCount = 1, math.floor(n / Bracket.GROUP_MIN) do
        local sizes = sizesFor(n, groupCount)
        local ok, cost = true, 0
        for _, size in ipairs(sizes) do
            if size < Bracket.GROUP_MIN or size > Bracket.GROUP_MAX then ok = false break end
            cost = cost + math.abs(size - GROUP_IDEAL)
        end
        -- `<=` statt `<`: bei gleicher Abweichung gewinnt die spaetere, also
        -- groessere Gruppenzahl.
        if ok and (bestCost == nil or cost <= bestCost) then best, bestCost = sizes, cost end
    end

    return best or { n }
end

-- Schlangenlinie ueber die Setzliste: 1 -> G1, 2 -> G2, 3 -> G3, 4 -> G4,
-- 5 -> G4, 6 -> G3, ... Damit sind die Gruppen gleich stark besetzt, ohne dass
-- irgendwo gewuerfelt wird.
function Bracket.buildGroups(seededIds, sizes)
    local groups, remaining = {}, {}
    for i = 1, #sizes do groups[i], remaining[i] = {}, sizes[i] end

    local index, forward = 1, true
    for _, id in ipairs(seededIds) do
        -- Die naechste Gruppe suchen, die noch Platz hat.
        local guard = 0
        while remaining[index] == 0 do
            index = index + (forward and 1 or -1)
            if index > #sizes then index, forward = #sizes, false
            elseif index < 1 then index, forward = 1, true end
            guard = guard + 1
            if guard > 4 * #sizes then break end
        end

        local group = groups[index]
        group[#group + 1] = id
        remaining[index] = remaining[index] - 1

        if forward then
            index = index + 1
            if index > #sizes then index, forward = #sizes, false end
        else
            index = index - 1
            if index < 1 then index, forward = 1, true end
        end
    end

    return groups
end

-- ---------------------------------------------------------------------------
-- Round Robin (M4-03)
--
-- Kreismethode: eine Position bleibt stehen, der Rest rotiert. Ergebnis sind
-- Runden mit PAARWEISE DISJUNKTEN Paarungen -- niemand spielt zweimal
-- gleichzeitig. Das ist der Unterschied zwischen einer Gruppenphase, die vier
-- Matches parallel spielen kann, und einer Liste, aus der der Scheduler sich
-- muehsam nicht-kollidierende Paare heraussuchen muss.
-- ---------------------------------------------------------------------------

function Bracket.roundRobin(memberIds)
    local list = copyList(memberIds)
    if #list < 2 then return {} end
    if #list % 2 == 1 then list[#list + 1] = false end   -- Platzhalter: setzt aus

    local m = #list
    local rounds = {}

    for _ = 1, m - 1 do
        local pairs_ = {}
        for i = 1, m / 2 do
            local a, b = list[i], list[m + 1 - i]
            if a and b then pairs_[#pairs_ + 1] = { a, b } end
        end
        rounds[#rounds + 1] = pairs_

        local last = table.remove(list, m)
        table.insert(list, 2, last)
    end

    return rounds
end

-- ---------------------------------------------------------------------------
-- Tabelle und die Kriterien aus E-11 (M4-03)
--
-- Reihenfolge: Siege, dann 1) direkter Vergleich, 2) Satzdifferenz,
-- 3) Punktdifferenz, 4) erzielte Punkte. Danach `unresolved` -- KEIN Muenzwurf
-- (`CLAUDE.md` §3.2). Was mit einem echten Gleichstand passiert, entscheidet
-- der Scheduler mit einem Stichsatz, nicht diese Datei.
--
-- Der direkte Vergleich wird nur angewandt, wenn die gleichstehenden Spieler
-- ALLE gegeneinander gespielt haben. Sonst vergleicht er Spieler mit
-- unterschiedlich vielen Begegnungen und ist nicht aussagekraeftig -- das ist
-- die uebliche Auslegung und die einzige, die bei einem Abbruch mitten in der
-- Gruppenphase noch stimmt.
-- ---------------------------------------------------------------------------

local function newRow(id)
    return { id = id, played = 0, wins = 0, losses = 0,
             setsWon = 0, setsLost = 0, setDiff = 0,
             pointsFor = 0, pointsAgainst = 0, pointDiff = 0 }
end

-- `matches` sind die abgeschlossenen Matches der Gruppe: Tabellen mit
-- `slotA`, `slotB`, `winner` und optional `sets` (Liste von {a=…, b=…}).
-- Ein Walkover hat keine Saetze und zaehlt nur als Sieg und Niederlage.
function Bracket.tableRows(memberIds, matches)
    local rows, byId = {}, {}
    for _, id in ipairs(memberIds) do
        local row = newRow(id)
        rows[#rows + 1] = row
        byId[id] = row
    end

    for _, m in ipairs(matches) do
        local a, b = byId[m.slotA], byId[m.slotB]
        if a and b and m.winner then
            a.played, b.played = a.played + 1, b.played + 1
            for _, set in ipairs(m.sets or {}) do
                a.pointsFor     = a.pointsFor     + set.a
                a.pointsAgainst = a.pointsAgainst + set.b
                b.pointsFor     = b.pointsFor     + set.b
                b.pointsAgainst = b.pointsAgainst + set.a
                if set.a > set.b then a.setsWon, b.setsLost = a.setsWon + 1, b.setsLost + 1
                elseif set.b > set.a then b.setsWon, a.setsLost = b.setsWon + 1, a.setsLost + 1 end
            end
            local winner = byId[m.winner]
            local loser  = (m.winner == m.slotA) and b or a
            winner.wins, loser.losses = winner.wins + 1, loser.losses + 1
        end
    end

    for _, row in ipairs(rows) do
        row.setDiff   = row.setsWon   - row.setsLost
        row.pointDiff = row.pointsFor - row.pointsAgainst
    end

    return rows, byId
end

-- Alle Paare der Menge haben gegeneinander gespielt?
local function allPlayedEachOther(ids, matches)
    local seen = {}
    for _, m in ipairs(matches) do
        if m.winner then
            seen[m.slotA .. "|" .. m.slotB] = true
            seen[m.slotB .. "|" .. m.slotA] = true
        end
    end
    for i = 1, #ids do
        for j = i + 1, #ids do
            if not seen[ids[i] .. "|" .. ids[j]] then return false end
        end
    end
    return true
end

local function headToHeadWins(ids, matches)
    local inSet, wins = {}, {}
    for _, id in ipairs(ids) do inSet[id], wins[id] = true, 0 end
    for _, m in ipairs(matches) do
        if m.winner and inSet[m.slotA] and inSet[m.slotB] then
            wins[m.winner] = wins[m.winner] + 1
        end
    end
    return wins
end

-- Nach einem Schluessel absteigend in Bloecke zerlegen. Die Reihenfolge der
-- Bloecke ist durch den Schluessel bestimmt, die Reihenfolge innerhalb eines
-- Blocks bleibt wie sie war -- damit ist das Ergebnis bei gleicher Eingabe
-- immer dasselbe, auch ohne stabiles `table.sort`.
local function splitBy(ids, keyOf)
    local values, seen = {}, {}
    for _, id in ipairs(ids) do
        local v = keyOf(id)
        if not seen[v] then seen[v] = true values[#values + 1] = v end
    end
    table.sort(values, function(a, b) return a > b end)

    local blocks = {}
    for _, v in ipairs(values) do
        local block = {}
        for _, id in ipairs(ids) do
            if keyOf(id) == v then block[#block + 1] = id end
        end
        blocks[#blocks + 1] = block
    end
    return blocks
end

local CRITERIA = { "head_to_head", "setDiff", "pointDiff", "pointsFor" }

local function resolveBlock(ids, level, ctx, out)
    if #ids == 1 then out[#out + 1] = ids[1] return end

    if level > #CRITERIA then
        -- Echter Gleichstand. Reihenfolge bleibt, wie sie hereinkam, und der
        -- Block wird gemeldet.
        ctx.unresolved[#ctx.unresolved + 1] = { first = #out + 1, ids = copyList(ids) }
        for _, id in ipairs(ids) do out[#out + 1] = id end
        return
    end

    local criterion = CRITERIA[level]
    local blocks

    if criterion == "head_to_head" then
        if not allPlayedEachOther(ids, ctx.matches) then
            return resolveBlock(ids, level + 1, ctx, out)
        end
        local wins = headToHeadWins(ids, ctx.matches)
        blocks = splitBy(ids, function(id) return wins[id] end)
    else
        blocks = splitBy(ids, function(id) return ctx.byId[id][criterion] end)
    end

    if #blocks == 1 then
        return resolveBlock(ids, level + 1, ctx, out)
    end

    -- Echte Teilmengen: wieder von vorn. Das terminiert, weil entweder die
    -- Stufe steigt oder die Menge kleiner wird.
    for _, block in ipairs(blocks) do
        resolveBlock(block, 1, ctx, out)
    end
end

-- Gibt `{ rows = <geordnete Zeilen>, unresolved = { {first=…, ids={…}}, … } }`.
-- `first` ist die Tabellenposition, an der der ungeloeste Block beginnt.
function Bracket.standings(memberIds, matches)
    local rows, byId = Bracket.tableRows(memberIds, matches)

    local ids = {}
    for _, row in ipairs(rows) do ids[#ids + 1] = row.id end

    local ctx = { byId = byId, matches = matches, unresolved = {} }
    local ordered = {}

    -- Siege sind das Hauptkriterium; E-11 nennt die Kriterien FUER den
    -- Gleichstand, also fuer alles darunter.
    for _, block in ipairs(splitBy(ids, function(id) return byId[id].wins end)) do
        resolveBlock(block, 1, ctx, ordered)
    end

    local result = { rows = {}, unresolved = ctx.unresolved }
    for i, id in ipairs(ordered) do
        byId[id].rank = i
        result.rows[i] = byId[id]
    end
    return result
end

-- Wer kommt weiter? Gibt die Kennungen zurueck -- oder nil plus den Block, der
-- im Weg steht.
--
-- Wichtig: Ein Gleichstand INTERHALB des Feldes interessiert nicht. Stehen in
-- einer Fuenfergruppe die Plaetze 3 und 4 gleich und kommen zwei weiter, ist
-- das kein Stichsatz wert. Gemeldet wird nur ein Block, der die Trennlinie
-- ueberschreitet.
function Bracket.qualifiers(standings, count)
    if count >= #standings.rows then
        local all = {}
        for _, row in ipairs(standings.rows) do all[#all + 1] = row.id end
        return all
    end

    for _, block in ipairs(standings.unresolved) do
        local last = block.first + #block.ids - 1
        if block.first <= count and last > count then
            return nil, block
        end
    end

    local out = {}
    for i = 1, count do out[i] = standings.rows[i].id end
    return out
end

-- ---------------------------------------------------------------------------
-- Single Elimination (M4-02)
--
-- Klassische Setzreihenfolge: 1 gegen n, 2 gegen n-1 usw., rekursiv
-- aufgebaut. Fuer acht Plaetze ergibt das 1-8, 4-5, 2-7, 3-6.
--
-- Freilose entstehen dadurch von selbst an der richtigen Stelle (E-01): Das
-- Bracket wird auf die naechste Zweierpotenz aufgefuellt, die aufgefuellten
-- Positionen tragen die hoechsten Setznummern, und die stehen den
-- niedrigsten -- also den hoechstgesetzten Spielern -- gegenueber.
-- ---------------------------------------------------------------------------

local function seedOrder(size)
    local order = { 1, 2 }
    local n = 2
    while n < size do
        local grown = {}
        for i = 1, n do
            grown[#grown + 1] = order[i]
            grown[#grown + 1] = 2 * n + 1 - order[i]
        end
        order, n = grown, n * 2
    end
    return order
end

Bracket.seedOrder = seedOrder   -- fuer den Test

local function roundLabel(round, total)
    if round == total     then return "Finale" end
    if round == total - 1 then return "Halbfinale" end
    if round == total - 2 then return "Viertelfinale" end
    if round == total - 3 then return "Achtelfinale" end
    return "Runde " .. round
end

-- Best-of ab dem Halbfinale (05_TOURNAMENT §2, berichtigt 2026-08-13).
local function bestOfFor(round, total, config)
    if round >= total - 1 then return config.bestOfFinals or 1 end
    return config.bestOfDefault or 1
end

-- `entrants` ist die Setzliste: Index = Setznummer.
-- Gibt `rounds, matches` zurueck. `matches` ist eine Liste in Erzeugungsfolge.
function Bracket.singleElim(entrants, config, idGen, opts)
    opts = opts or {}
    local n = #entrants
    local rounds, matches = {}, {}
    if n < 2 then return rounds, matches end

    local size   = nextPow2(n)
    local order  = seedOrder(size)
    local total  = 0
    do local s = size while s > 1 do total = total + 1 s = s / 2 end end

    local roundOffset = opts.roundOffset or 0
    local previous    = nil

    for round = 1, total do
        local count = size / (2 ^ round)
        local ids, entry = {}, {}

        for i = 1, count do
            local refA, refB
            if round == 1 then
                local seatA, seatB = order[2 * i - 1], order[2 * i]
                refA = entrants[seatA] or Bracket.BYE
                refB = entrants[seatB] or Bracket.BYE
                -- Bei korrekter Setzreihenfolge kann nie ein Paar aus zwei
                -- Freilosen entstehen; wenn doch, ist die Reihenfolge kaputt
                -- und das faellt hier auf statt am Partyabend.
                if refA == Bracket.BYE and refB == Bracket.BYE then
                    error("zwei Freilose in einer Paarung -- Setzreihenfolge kaputt", 0)
                end
            else
                refA = Bracket.winnerOf(previous[2 * i - 1])
                refB = Bracket.winnerOf(previous[2 * i])
            end

            local id = idGen()
            ids[#ids + 1] = id
            entry[#entry + 1] = id
            matches[#matches + 1] = {
                id          = id,
                round       = roundOffset + round,
                stage       = opts.stage or "elim",
                group       = nil,
                slotARef    = refA,
                slotBRef    = refB,
                bestOf      = bestOfFor(round, total, config),
                targetScore = config.targetScore,
            }
        end

        rounds[#rounds + 1] = {
            index   = roundOffset + round,
            label   = roundLabel(round, total),
            stage   = opts.stage or "elim",
            matches = entry,
        }
        previous = ids
    end

    -- Spiel um Platz 3: die beiden Halbfinalverlierer. Steht in derselben
    -- Runde wie das Finale, weil es zeitgleich gespielt wird.
    if config.thirdPlaceMatch and total >= 2 then
        local semi = rounds[total - 1].matches
        local id = idGen()
        matches[#matches + 1] = {
            id          = id,
            round       = roundOffset + total,
            stage       = opts.stage or "elim",
            slotARef    = Bracket.loserOf(semi[1]),
            slotBRef    = Bracket.loserOf(semi[2]),
            bestOf      = config.bestOfFinals or 1,
            targetScore = config.targetScore,
            thirdPlace  = true,
        }
        local final = rounds[total].matches
        final[#final + 1] = id
    end

    return rounds, matches
end

-- ---------------------------------------------------------------------------
-- Gruppen -> K.o. (M4-04)
--
-- Die Gruppenersten bekommen die Setznummern 1..g, die Zweiten g+1..2g. Damit
-- greift die klassische Setzung von oben: Gruppenerster gegen Gruppenzweiten
-- der anderen Seite, Freilose an die besten Gruppenersten.
--
-- Danach ein Reparaturgang: Zwei Spieler aus derselben Gruppe duerfen in der
-- ersten K.o.-Runde nicht aufeinandertreffen. Sie haben gerade gegeneinander
-- gespielt; ein sofortiges Wiedersehen entwertet die Gruppenphase.
-- ---------------------------------------------------------------------------

local function betterRow(a, b)
    if a.wins      ~= b.wins      then return a.wins      > b.wins      end
    if a.setDiff   ~= b.setDiff   then return a.setDiff   > b.setDiff   end
    if a.pointDiff ~= b.pointDiff then return a.pointDiff > b.pointDiff end
    if a.pointsFor ~= b.pointsFor then return a.pointsFor > b.pointsFor end
    return a.groupIndex < b.groupIndex   -- deterministischer Schlussanker
end

-- `qualifiedPerGroup[i]` ist die geordnete Liste der Weitergekommenen aus
-- Gruppe i, `standingsPerGroup[i]` die zugehoerige Tabelle.
function Bracket.elimFromGroups(qualifiedPerGroup, standingsPerGroup, config, idGen, opts)
    local advance = (config.advancePerGroup or 2)
    local groupOf, byPlace = {}, {}

    for gi, qualified in ipairs(qualifiedPerGroup) do
        for place, id in ipairs(qualified) do
            groupOf[id] = gi
            local row
            for _, r in ipairs(standingsPerGroup[gi].rows) do
                if r.id == id then row = r break end
            end
            local entry = {
                id = id, groupIndex = gi, place = place,
                wins = row and row.wins or 0, setDiff = row and row.setDiff or 0,
                pointDiff = row and row.pointDiff or 0, pointsFor = row and row.pointsFor or 0,
            }
            byPlace[place] = byPlace[place] or {}
            table.insert(byPlace[place], entry)
        end
    end

    -- Setzliste: erst alle Gruppenersten nach Staerke, dann alle Zweiten, usw.
    local entrants = {}
    for place = 1, advance do
        local list = byPlace[place] or {}
        table.sort(list, betterRow)
        for _, entry in ipairs(list) do entrants[#entrants + 1] = entry.id end
    end

    local rounds, matches = Bracket.singleElim(entrants, config, idGen, opts)

    -- Reparaturgang.
    local firstRoundIndex = (opts and opts.roundOffset or 0) + 1
    local first = {}
    for _, m in ipairs(matches) do
        if m.round == firstRoundIndex
           and select(1, Bracket.refKind(m.slotARef)) == "participant"
           and select(1, Bracket.refKind(m.slotBRef)) == "participant" then
            first[#first + 1] = m
        end
    end

    for i, m in ipairs(first) do
        if groupOf[m.slotARef] == groupOf[m.slotBRef] then
            for j, other in ipairs(first) do
                if j ~= i
                   and groupOf[other.slotBRef] ~= groupOf[m.slotARef]
                   and groupOf[m.slotBRef]     ~= groupOf[other.slotARef] then
                    m.slotBRef, other.slotBRef = other.slotBRef, m.slotBRef
                    break
                end
            end
        end
    end

    return rounds, matches, entrants
end

-- ---------------------------------------------------------------------------
-- Stichsatz (E-11)
--
-- Aus einem ungeloesten Block wird eine Mini-Rundenrunde auf 7 Punkte. Bei
-- zwei Gleichstehenden ist das ein Match, bei dreien sind es drei. Was
-- passiert, wenn auch die wieder gleich ausgehen, entscheidet ADR-021 und
-- nicht diese Datei: dann zaehlt die Setznummer.
-- ---------------------------------------------------------------------------

function Bracket.tiebreakMatches(tiedIds, config, idGen, roundIndex, groupIndex)
    local matches = {}
    for i = 1, #tiedIds do
        for j = i + 1, #tiedIds do
            matches[#matches + 1] = {
                id          = idGen(),
                round       = roundIndex,
                stage       = "tiebreak",
                group       = groupIndex,
                slotARef    = tiedIds[i],
                slotBRef    = tiedIds[j],
                bestOf      = 1,
                targetScore = Bracket.TIEBREAK_TARGET,
                tiebreak    = true,
            }
        end
    end
    return matches
end

-- ---------------------------------------------------------------------------
-- Die vollstaendige Auslosung
--
-- Gibt eine Tabelle zurueck, die genau so in das Log-Ereignis `bracket_drawn`
-- wandert. Sie beschreibt die Auslosung vollstaendig -- das Log traegt damit
-- die Paarungen selbst und nicht nur den Seed. Der Unterschied faellt beim
-- Wiederherstellen auf: Ein Log, das nur den Seed traegt, ist auf den
-- Auslosungsalgorithmus von heute angewiesen.
-- ---------------------------------------------------------------------------

function Bracket.draw(participantIds, config, opts)
    opts = opts or {}
    local format   = config.format or "groups_then_elim"
    local seedMode = opts.seedMode or "random"
    local seedValue = opts.seedValue

    local seeded = Bracket.assignSeeds(participantIds, seedMode, seedValue, opts.ranking)
    local seeds = {}
    for i, id in ipairs(seeded) do seeds[id] = i end

    local idGen = Bracket.newIdGen(opts.idStart or 100)
    local draw = {
        seedMode  = seedMode,
        seedValue = seedValue,
        seeds     = seeds,
        order     = seeded,
        format    = format,
        groups    = {},
        rounds    = {},
        matches   = {},
    }

    if format == "single_elim" then
        draw.rounds, draw.matches = Bracket.singleElim(seeded, config, idGen)
        draw.stage = "elim"
        return draw
    end

    -- round_robin ist eine einzige Gruppe; groups_then_elim teilt auf.
    local sizes = (format == "round_robin") and { #seeded } or Bracket.groupSplit(#seeded)
    draw.groups = Bracket.buildGroups(seeded, sizes)
    draw.stage  = "groups"

    -- Alle Gruppen spielen ihre Runden gleichzeitig: Runde r enthaelt die
    -- r-te Runde jeder Gruppe.
    local perGroup, maxRounds = {}, 0
    for gi, members in ipairs(draw.groups) do
        perGroup[gi] = Bracket.roundRobin(members)
        if #perGroup[gi] > maxRounds then maxRounds = #perGroup[gi] end
    end

    for r = 1, maxRounds do
        local entry = {}
        for gi = 1, #draw.groups do
            for _, pair in ipairs(perGroup[gi][r] or {}) do
                local id = idGen()
                entry[#entry + 1] = id
                draw.matches[#draw.matches + 1] = {
                    id          = id,
                    round       = r,
                    stage       = "group",
                    group       = gi,
                    slotARef    = pair[1],
                    slotBRef    = pair[2],
                    bestOf      = config.bestOfDefault or 1,
                    targetScore = config.targetScore,
                }
            end
        end
        draw.rounds[#draw.rounds + 1] = {
            index   = r,
            label   = string.format("Gruppenphase %d/%d", r, maxRounds),
            stage   = "group",
            matches = entry,
        }
    end

    draw.groupRounds = maxRounds
    return draw
end

return Bracket
