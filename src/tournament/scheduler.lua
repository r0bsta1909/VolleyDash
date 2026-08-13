-- ============================================================================
-- src/tournament/scheduler.lua -- Zustandsautomat und Ansetzung (M4-05)
--
-- `05_TOURNAMENT` §5, §6. love-frei.
--
--   pending --> ready --> live --> finished
--      |          |         |
--      |          |         +--> aborted --> (Neuansetzung, zurueck auf pending)
--      |          +--> walkover  (No-Show-Timer abgelaufen)
--      +--> bye                  (Freilos)
--
-- ---------------------------------------------------------------------------
-- Zwei Regeln, die diese Datei von einer Bracket-Verwaltung unterscheiden
-- ---------------------------------------------------------------------------
--
-- 1. KEINE ZEIT AUS DER UMGEBUNG. `update(now)` bekommt die Zeit uebergeben.
--    Damit ist der No-Show-Timer im Test in Millisekunden durchspielbar statt
--    in 180 Sekunden, und der ganze Automat laeuft headless.
--
-- 2. KEIN STILLSTAND UND KEIN MUENZWURF (ADR-021). Drei Sackgassen, die §5
--    offenlaesst, haben hier eine deterministische Regel:
--
--    E-15  Beide Spieler erscheinen nicht -> der hoeher Gesetzte gewinnt.
--    E-16  Ein Teilnehmer ist offline -> §5 verlangt fuer `ready` beide online,
--          der No-Show-Timer laeuft aber erst ab `ready`. Ohne eigenen Timer
--          haengt das Match fuer immer in `pending`. Also bekommt es einen --
--          er startet, sobald das Match SONST spielbar waere.
--    E-17  Der Gleichstand ueberlebt den Stichsatz -> nach genau einer Runde
--          entscheidet die Setznummer.
--
-- Was hier NICHT im Log landet: Verbindungsstatus, Bereitmeldungen, Timer.
-- Das ist Laufzeit. Was im Log steht, muss die Rekonstruktion aus §7
-- ueberstehen, und eine Verbindung tut das nicht.
-- ============================================================================

local Bracket = require("src.tournament.bracket")
local Model   = require("src.tournament.model")

local Scheduler = {}
Scheduler.__index = Scheduler

Scheduler.MAX_PASSES = 64   -- Schutz gegen eine Regel, die sich selbst ausloest

function Scheduler.new(tournament, opts)
    opts = opts or {}
    return setmetatable({
        t            = tournament,
        online       = {},    -- [pid] = true
        confirmed    = {},    -- [matchId] = { [pid] = true }
        blockedSince = {},    -- [matchId] = Zeit, seit der nur Offline blockiert (E-16)
        pausedAt     = {},    -- [matchId] = Zeit, seit der der Timer steht (E-02)
        timerOffset  = {},    -- [matchId] = aufsummierte Pausendauer
        chooseHost   = opts.chooseHost,
    }, Scheduler)
end

-- ---------------------------------------------------------------------------
-- Kleinkram
-- ---------------------------------------------------------------------------

-- Kennungen fortsetzen, ohne mit den ausgelosten zu kollidieren. Wird bei
-- jedem Bedarf neu bestimmt -- damit stimmt sie auch nach einem Neustart, bei
-- dem der Scheduler frisch aufgebaut wird.
local function idGenFor(t)
    local highest = 100
    for _, id in ipairs(t.matchOrder) do
        local n = tonumber(tostring(id):match("^m_(%d+)$") or "")
        if n and n > highest then highest = n end
    end
    return Bracket.newIdGen(highest)
end

local function isPlayable(t, pid)
    local p = t.participants[pid]
    return p ~= nil and p.status ~= Model.PARTICIPANT_STATUS.WITHDRAWN
end

-- Ist der Teilnehmer gerade in einem aufgerufenen oder laufenden Match?
local function busy(t, pid)
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if (m.status == Model.STATUS.READY or m.status == Model.STATUS.LIVE)
           and (m.slotA == pid or m.slotB == pid) then
            return true
        end
    end
    return false
end

function Scheduler:isOnline(pid)
    return pid ~= nil and self.online[pid] == true
end

function Scheduler:deadline(m)
    return (m.calledAt or 0) + self.t.config.noShowTimeout + (self.timerOffset[m.id] or 0)
end

-- ---------------------------------------------------------------------------
-- Eingaben von aussen
-- ---------------------------------------------------------------------------

function Scheduler:setOnline(pid, online)
    self.online[pid] = online and true or nil
end

-- Ein Spieler hat in der Match-Lobby "Bereit" bestaetigt (§5).
function Scheduler:confirmReady(matchId, pid, now)
    local m = self.t.matches[matchId]
    if not m or m.status ~= Model.STATUS.READY then return false end
    if pid ~= m.slotA and pid ~= m.slotB then return false end
    self.confirmed[matchId] = self.confirmed[matchId] or {}
    self.confirmed[matchId][pid] = true
    return true
end

-- E-02: der einzige vorgesehene manuelle Eingriff.
function Scheduler:pauseNoShow(matchId, paused, now)
    if paused then
        if not self.pausedAt[matchId] then self.pausedAt[matchId] = now end
    elseif self.pausedAt[matchId] then
        self.timerOffset[matchId] = (self.timerOffset[matchId] or 0)
                                    + (now - self.pausedAt[matchId])
        self.pausedAt[matchId] = nil
    end
end

-- Das Ergebnis kommt vom Match-Host aus dem Simulationszustand, nicht von
-- einem Spieler (E-08). `sets` ist eine Liste von {a=…, b=…}.
--
-- `stats` traegt die zwei Statistiken aus `05_TOURNAMENT` §11, die in der
-- SIMULATION anfallen und deshalb nur der Match-Host kennt: die laengste
-- Rallye in Sekunden und den schnellsten Ball in Pixel/s samt dem Spieler, der
-- ihn zuletzt beruehrt hat. Ohne sie fehlen bei der Siegerehrung zwei von
-- fuenf Zahlen. Die Tastatur des Turnierleiters laesst das Feld leer -- ein
-- Ergebnis ohne Statistik ist ein gueltiges Ergebnis.
function Scheduler:reportResult(matchId, sets, now, stats)
    local t = self.t
    local m = t.matches[matchId]
    if not m then return false, "unbekanntes Match" end
    if Model.TERMINAL[m.status] then return false, "Match ist schon fertig" end
    if not (m.slotA and m.slotB) then return false, "Slots nicht besetzt" end

    local a, b = 0, 0
    for _, set in ipairs(sets) do
        if set.a > set.b then a = a + 1 elseif set.b > set.a then b = b + 1 end
    end
    if a == b then return false, "kein Sieger in den Saetzen" end

    t:append({
        event = "match_finished", matchId = matchId, at = now,
        sets = sets, winner = (a > b) and m.slotA or m.slotB,
        stats = stats,
    })
    self.confirmed[matchId] = nil
    return true
end

-- E-06: Absturz des Match-Hosts. Kein Walkover -- das Match wird neu angesetzt.
function Scheduler:abortMatch(matchId, reason, now)
    local m = self.t.matches[matchId]
    if not m or Model.TERMINAL[m.status] then return false end
    self.t:append({ event = "match_aborted", matchId = matchId, at = now,
                    reason = reason or "host_lost" })
    self.confirmed[matchId] = nil
    self.blockedSince[matchId] = nil
    return true
end

-- E-04: Alle ausstehenden Matches gehen als Walkover an den Gegner; bereits
-- gespielte Ergebnisse bleiben gewertet. Das Aufloesen erledigt `update`.
function Scheduler:withdraw(pid, now)
    if not self.t.participants[pid] then return false end
    self.t:append({ event = "participant_withdrawn", participantId = pid, at = now })
    self:setOnline(pid, false)
    self:update(now)
    return true
end

-- E-12: manuelle Korrektur, nur durch den Turnier-Host, mit Begruendung.
function Scheduler:override(matchId, sets, winner, reason, by, now)
    local m = self.t.matches[matchId]
    if not m then return false, "unbekanntes Match" end
    if not reason or reason == "" then return false, "Begruendung fehlt" end
    self.t:append({ event = "manual_override", matchId = matchId, at = now,
                    sets = sets, winner = winner, reason = reason, by = by })
    return true
end

-- ---------------------------------------------------------------------------
-- Die Schritte von `update`
-- ---------------------------------------------------------------------------

-- Freilose aufloesen, sobald der besetzte Slot feststeht (E-01).
function Scheduler:stepByes(now)
    local t = self.t
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.status == Model.STATUS.PENDING and Model.hasBye(m) then
            local winner = m.slotA or m.slotB
            if winner then
                t:append({ event = "match_bye", matchId = id, at = now, winner = winner })
                return true
            end
        end
    end
    return false
end

-- Ausgestiegene Spieler (E-04) und der Fall, dass beide ausgestiegen sind.
function Scheduler:stepWithdrawals(now)
    local t = self.t
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if not Model.TERMINAL[m.status] and m.slotA and m.slotB then
            local outA = not isPlayable(t, m.slotA)
            local outB = not isPlayable(t, m.slotB)
            if outA or outB then
                local winner
                if outA and outB then
                    winner = t:higherSeed(m.slotA, m.slotB)   -- ADR-021
                else
                    winner = outA and m.slotB or m.slotA
                end
                t:append({ event = "match_walkover", matchId = id, at = now,
                           winner = winner,
                           reason = (outA and outB) and "both_withdrawn" or "withdrawn" })
                self.confirmed[id] = nil
                return true
            end
        end
    end
    return false
end

-- Aufgerufene Matches: Bereitmeldung -> live, sonst No-Show (E-02, E-15).
function Scheduler:stepCalled(now)
    local t = self.t
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.status == Model.STATUS.READY then
            local ready = self.confirmed[id] or {}
            local both  = ready[m.slotA] and ready[m.slotB]

            if both then
                -- ADR-022. `chooseHost` darf eine Begruendung mitgeben; ohne
                -- Netz gibt es keine Proben, und dann ist die Setznummer nicht
                -- die Platzhalterregel aus Stufe A, sondern der
                -- Gleichstandsfall derselben Regel.
                local host, info
                if self.chooseHost then host, info = self.chooseHost(m, t, now) end
                if host == nil then
                    host, info = t:higherSeed(m.slotA, m.slotB), { hostReason = "seed" }
                end
                info = info or {}
                t:append({ event = "match_started", matchId = id, at = now,
                           hostClient = host, hostReason = info.hostReason,
                           rttA = info.rttA, rttB = info.rttB })
                return true
            end

            if not self.pausedAt[id] and now >= self:deadline(m) then
                local winner, reason
                if ready[m.slotA] then winner, reason = m.slotA, "no_show"
                elseif ready[m.slotB] then winner, reason = m.slotB, "no_show"
                else
                    -- E-15: keiner da. Der hoeher Gesetzte kommt weiter --
                    -- deterministisch und nachrechenbar (ADR-021).
                    winner, reason = t:higherSeed(m.slotA, m.slotB), "no_show_both"
                end
                t:append({ event = "match_walkover", matchId = id, at = now,
                           winner = winner, reason = reason })
                self.confirmed[id] = nil
                return true
            end
        end
    end
    return false
end

-- Was koennte gespielt werden, wenn niemand fehlte? Liefert die Liste in
-- fester Reihenfolge: fruehe Runde zuerst, dann Auslosungsreihenfolge.
function Scheduler:candidates()
    local t = self.t
    local out = {}
    for index, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.status == Model.STATUS.PENDING and m.slotA and m.slotB
           and isPlayable(t, m.slotA) and isPlayable(t, m.slotB)
           and not busy(t, m.slotA) and not busy(t, m.slotB) then
            out[#out + 1] = { m = m, index = index }
        end
    end
    table.sort(out, function(x, y)
        if x.m.round ~= y.m.round then return x.m.round < y.m.round end
        return x.index < y.index
    end)
    return out
end

-- E-16: Der Timer fuer offline gebliebene Teilnehmer. Er laeuft ab dem
-- Moment, in dem das Match sonst spielbar waere -- nicht frueher. Wer in
-- Runde 3 noch gar nicht dran ist, darf nicht dafuer bestraft werden, dass er
-- zwischendurch den Laptop zuklappt.
function Scheduler:stepOfflineTimer(now, candidates)
    local t = self.t
    local seen = {}

    for _, entry in ipairs(candidates) do
        local m = entry.m
        seen[m.id] = true
        local onA, onB = self:isOnline(m.slotA), self:isOnline(m.slotB)
        if onA and onB then
            self.blockedSince[m.id] = nil
        else
            if not self.blockedSince[m.id] then self.blockedSince[m.id] = now end
            local due = self.blockedSince[m.id] + t.config.noShowTimeout
                        + (self.timerOffset[m.id] or 0)
            if not self.pausedAt[m.id] and now >= due then
                local winner, reason
                if onA then winner, reason = m.slotA, "offline"
                elseif onB then winner, reason = m.slotB, "offline"
                else winner, reason = t:higherSeed(m.slotA, m.slotB), "offline_both" end
                t:append({ event = "match_walkover", matchId = m.id, at = now,
                           winner = winner, reason = reason })
                self.blockedSince[m.id] = nil
                return true
            end
        end
    end

    for id in pairs(self.blockedSince) do
        if not seen[id] then self.blockedSince[id] = nil end
    end
    return false
end

-- Aufrufen (§5). `parallelMatches` ist eine Obergrenze, keine Bedingung: Sind
-- weniger Matches spielbar, werden weniger aufgerufen -- der Scheduler
-- blockiert nicht (§2, dritte Konsequenz).
function Scheduler:stepCall(now, candidates)
    local t = self.t
    local free = (t.config.parallelMatches or 2) - t:activeMatches()
    if free <= 0 then return false end

    for _, entry in ipairs(candidates) do
        local m = entry.m
        if free <= 0 then break end
        if self:isOnline(m.slotA) and self:isOnline(m.slotB) then
            t:append({ event = "match_called", matchId = m.id, at = now })
            self.confirmed[m.id]    = {}
            self.blockedSince[m.id] = nil
            return true   -- nach jeder Aenderung neu bewerten (busy/frei)
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Gruppenphase abschliessen, Stichsatz, Uebergang ins K.o.
-- ---------------------------------------------------------------------------

-- Hat diese Gruppe schon eine Stichsatzrunde hinter sich?
--
-- Bewusst AUS DEM LOG beantwortet und nicht aus einem Laufzeitmerker: Sonst
-- ginge die Antwort beim Neustart des Turnier-Hosts verloren, und das Turnier
-- setzte nach der Wiederherstellung eine zweite Runde an -- die Zusicherung
-- aus ADR-021 ("genau eine Runde") gaelte dann nur, solange niemand abstuerzt.
--
-- Gefragt wird nach der GRUPPE, nicht nach der konkreten Gleichstandsmenge:
-- Ein Stichsatz kann von drei Gleichstehenden zwei trennen und einen neuen
-- Zweiergleichstand hinterlassen. Mit der Menge als Schluessel waere das eine
-- neue Frage und der Automat koennte im Kreis laufen.
function Scheduler:hasPlayedTiebreak(groupIndex)
    for _, ev in ipairs(self.t.log) do
        if ev.event == "tiebreak_added" and ev.group == groupIndex then return true end
    end
    return false
end

-- Gibt die Weitergekommenen einer Gruppe zurueck -- oder nil und den Block,
-- der im Weg steht.
function Scheduler:qualifiersOf(groupIndex, count)
    local t = self.t
    local standings = t.standings[groupIndex]
    if not standings then return nil end

    local ids, block = Bracket.qualifiers(standings, count)
    if ids then return ids end

    -- E-17: Nach einer Stichsatzrunde entscheidet die Setznummer (ADR-021).
    if self:hasPlayedTiebreak(groupIndex) then
        local ordered = {}
        for i, id in ipairs(block.ids) do ordered[i] = id end
        table.sort(ordered, function(a, b)
            local sa, sb = t:seedOf(a), t:seedOf(b)
            if sa ~= sb then return sa < sb end
            return a < b
        end)

        local out = {}
        for i = 1, block.first - 1 do out[#out + 1] = standings.rows[i].id end
        for _, id in ipairs(ordered) do
            if #out < count then out[#out + 1] = id end
        end
        return out
    end

    return nil, block
end

function Scheduler:stepGroupStage(now)
    local t = self.t
    if t.stage ~= "groups" then return false end
    if not t:isGroupStageComplete() then return false end

    local count = (t.format == "round_robin") and 1 or (t.config.advancePerGroup or 2)
    local qualified = {}

    for gi = 1, #t.groups do
        local ids, block = self:qualifiersOf(gi, count)
        if not ids then
            -- Stichsatz ansetzen (E-11). Genau eine Runde.
            local idGen = idGenFor(t)
            local roundIndex = (t.groupRounds or #t.rounds) + 1
            local matches = Bracket.tiebreakMatches(block.ids, t.config, idGen, roundIndex, gi)
            t:append({
                event   = "tiebreak_added",
                at      = now,
                group   = gi,
                matches = matches,
                rounds  = { { index = roundIndex, label = "Stichsatz",
                              stage = "tiebreak",
                              matches = (function()
                                  local list = {}
                                  for i, m in ipairs(matches) do list[i] = m.id end
                                  return list
                              end)() } },
            })
            return true
        end
        qualified[gi] = ids
    end

    if t.format == "round_robin" then
        t:append({ event = "tournament_finished", at = now, winner = qualified[1][1] })
        return true
    end

    local idGen = idGenFor(t)
    local offset = 0
    for _, r in ipairs(t.rounds) do if r.index > offset then offset = r.index end end

    local rounds, matches = Bracket.elimFromGroups(
        qualified, t.standings, t.config, idGen, { roundOffset = offset })

    t:append({ event = "stage_advanced", at = now, stage = "elim",
               rounds = rounds, matches = matches })
    return true
end

function Scheduler:stepFinish(now)
    local t = self.t
    if t.status ~= Model.TOURNAMENT_STATUS.RUNNING then return false end
    if t.stage ~= "elim" then return false end

    local final = t:finalMatch()
    if final and Model.TERMINAL[final.status] and final.winner then
        -- Erst wenn ALLE Matches fertig sind -- das Spiel um Platz 3 laeuft
        -- parallel zum Finale und darf nicht abgeschnitten werden.
        for _, id in ipairs(t.matchOrder) do
            if not Model.TERMINAL[t.matches[id].status] then return false end
        end
        t:append({ event = "tournament_finished", at = now, winner = final.winner })
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Der Takt
-- ---------------------------------------------------------------------------

-- Ein Durchgang. Gibt zurueck, ob sich etwas geaendert hat -- dann wird neu
-- bewertet, weil eine Aenderung die naechste ausloesen kann (ein Freilos macht
-- den Slot des Folgematches konkret, ein Walkover gibt Kapazitaet frei).
--
-- Reihenfolge ist Absicht: Erst wird aufgeloest, was ohne Zutun entschieden
-- ist, dann laufen die Timer, dann wird neu aufgerufen. Wer zuerst aufruft,
-- vergibt Kapazitaet an ein Match, das gleich ohnehin per Walkover endet.
function Scheduler:tick(now)
    -- Der Riegel gehoert HIER und nicht nur in `update`: `stepGroupStage`
    -- prueft auf "Gruppenphase vollstaendig", und das bleibt nach dem Ende
    -- eines Round-Robin-Turniers fuer immer wahr. Ohne diese Zeile haengt der
    -- Automat das Ereignis `tournament_finished` in einer Endlosschleife an.
    if self.t.status ~= Model.TOURNAMENT_STATUS.RUNNING then return false end

    if self:stepByes(now)        then return true end
    if self:stepWithdrawals(now) then return true end
    if self:stepCalled(now)      then return true end

    local candidates = self:candidates()
    if self:stepOfflineTimer(now, candidates) then return true end
    if self:stepCall(now, candidates)         then return true end

    if self:stepGroupStage(now) then return true end
    if self:stepFinish(now)     then return true end
    return false
end

-- Kein `goto`: Der Headless-Runner laeuft laut `CLAUDE.md` §12 ausdruecklich
-- auch unter reinem Lua 5.1 (`lua tests/run_headless.lua`), und dort gibt es
-- die Anweisung nicht -- LuaJIT waere die Ausnahme, nicht die Regel.
function Scheduler:update(now)
    local t = self.t
    if t.status == Model.TOURNAMENT_STATUS.FINISHED
       or t.status == Model.TOURNAMENT_STATUS.ABORTED then
        return 0
    end

    local passes = 0
    while self:tick(now) do
        passes = passes + 1
        if passes > Scheduler.MAX_PASSES then
            error("Scheduler dreht sich im Kreis -- eine Regel loest sich selbst aus", 0)
        end
    end
    return passes
end

return Scheduler
