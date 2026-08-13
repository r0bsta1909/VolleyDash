-- ============================================================================
-- tests/tournament_host_choice_test.lua -- Ebene B: wer hostet (M4-09)
--
-- ADR-022, `05_TOURNAMENT` §8.1 (T-01). love-frei.
--
-- Der Schwerpunkt liegt auf der SCHWELLE, nicht auf dem Vergleich. Dass 40 ms
-- langsamer sind als 3 ms, widerlegt nichts. Was widerlegt werden kann, ist
-- die Zusicherung, dass Messrauschen die Wahl NICHT entscheidet -- und dass
-- der Gleichstandsfall auf dieselbe Regel faellt wie ADR-021.
-- ============================================================================

local Model      = require("src.tournament.model")
local Scheduler  = require("src.tournament.scheduler")
local HostChoice = require("src.tournament.host_choice")
local H          = require("tests.tournament_helper")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local assertEq, assertTrue = H.assertEq, H.assertTrue
local assertNear = H.assertNear

-- ---------------------------------------------------------------------------
-- Das Fenster
-- ---------------------------------------------------------------------------

case("der Median wirft den einen Ausreisser weg, den der Mittelwert mitnaehme", function()
    local hc = HostChoice.new()
    -- Neun ruhige Proben und ein Ruckler. Das Mittel waere 21 ms, der Median 2.
    for i = 1, 9 do hc:sample("p_01", 2, i * 0.5) end
    hc:sample("p_01", 200, 5.0)

    assertEq(hc:median("p_01", 5.0), 2, "Median bleibt bei 2 ms")
end)

case("Proben ausserhalb der letzten 5 s zaehlen nicht mehr", function()
    local hc = HostChoice.new()
    hc:sample("p_01", 40, 0)     -- alt
    hc:sample("p_01", 3, 10.0)   -- frisch
    assertEq(hc:median("p_01", 10.0), 3, "nur die frische Probe")

    -- Und wenn gar nichts mehr im Fenster liegt, gibt es keinen Messwert --
    -- nicht etwa eine Null, die "sehr schnell" hiesse.
    assertEq(hc:median("p_01", 100.0), nil, "kein Messwert statt null")
end)

case("der Median gerader Probenzahl liegt in der Mitte", function()
    local hc = HostChoice.new()
    for _, v in ipairs({ 4, 10, 2, 8 }) do hc:sample("p_01", v, 0) end
    assertEq(hc:median("p_01", 0), 6, "Mittel der beiden mittleren Proben")
end)

-- ---------------------------------------------------------------------------
-- Die Schwelle -- der eigentliche Inhalt von ADR-022
-- ---------------------------------------------------------------------------

case("ein Unterschied ueber 5 ms entscheidet, und zwar fuer den Schnelleren", function()
    local pid, reason = HostChoice.decide("p_01", "p_02", 40, 2, "p_01")
    assertEq(pid, "p_02", "der Schnellere hostet")
    assertEq(reason, "rtt", "Grund")
end)

case("Kabel-Rauschen entscheidet NICHT -- dann gilt die Setznummer", function()
    -- Der Auslegungsfall seit ADR-019: beide ueber Kabel, 1-2 ms.
    local pid, reason = HostChoice.decide("p_01", "p_02", 2.0, 1.0, "p_01")
    assertEq(pid, "p_01", "die kleinere Setznummer hostet")
    assertEq(reason, "seed", "Grund")

    -- Und der hoeher Gesetzte ist NICHT automatisch der erste Slot: Wer
    -- schneller ist, aber nur um 4 ms, gewinnt trotzdem nicht.
    local pid2, reason2 = HostChoice.decide("p_05", "p_02", 1.0, 5.0, "p_02")
    assertEq(pid2, "p_02", "Setznummer schlaegt 4 ms Vorsprung")
    assertEq(reason2, "seed", "Grund")
end)

case("genau 5 ms sind noch Gleichstand, 5,1 ms nicht mehr", function()
    local pid = HostChoice.decide("p_01", "p_02", 7.0, 2.0, "p_01")
    assertEq(pid, "p_01", "genau 5 ms Unterschied: Setznummer")

    local pid2, reason2 = HostChoice.decide("p_01", "p_02", 7.1, 2.0, "p_01")
    assertEq(pid2, "p_02", "5,1 ms: die Messung entscheidet")
    assertEq(reason2, "rtt", "Grund")
end)

case("wer keine Proben hat, faellt auf die Setznummer und nicht auf null", function()
    -- Ein gerade wieder verbundener Spieler hat noch keine Probe. Wuerde das
    -- als "0 ms" gelesen, haette ausgerechnet der gerade Abgestuerzte die
    -- beste Verbindung.
    local pid, reason = HostChoice.decide("p_01", "p_02", nil, 40, "p_02")
    assertEq(pid, "p_02", "Setznummer entscheidet")
    assertEq(reason, "seed", "Grund")
end)

case("der Turnier-Host misst sich selbst mit null und hostet damit immer", function()
    local hc = HostChoice.new()
    hc:sampleSelf("p_03", 0)
    for i = 1, 6 do hc:sample("p_07", 20, i * 0.5) end

    local pid, reason = HostChoice.decide("p_03", "p_07",
        hc:median("p_03", 3), hc:median("p_07", 3), "p_07")
    assertEq(pid, "p_03", "null Netzspruenge gewinnt die Messung")
    assertEq(reason, "rtt", "und zwar als Messung, nicht als Sonderfall")
end)

-- ---------------------------------------------------------------------------
-- Am Scheduler
-- ---------------------------------------------------------------------------

local function startedEvent(t, matchId)
    for _, ev in ipairs(t.log) do
        if ev.event == "match_started" and ev.matchId == matchId then return ev end
    end
end

case("die Wahl landet mit Grund und Messwerten im Log", function()
    local t = H.newTournament(4, { format = "single_elim" })
    H.draw(t)

    local hc = HostChoice.new()
    local sched = Scheduler.new(t, { chooseHost = hc:chooser() })
    H.allOnline(t, sched)
    sched:update(0)

    local called
    for _, id in ipairs(t.matchOrder) do
        if t.matches[id].status == Model.STATUS.READY then called = t.matches[id] break end
    end
    assertTrue(called ~= nil, "ein Match ist aufgerufen")

    -- Der eine ist deutlich langsamer.
    for i = 1, 6 do
        hc:sample(called.slotA, 30, i * 0.5)
        hc:sample(called.slotB, 2, i * 0.5)
    end
    sched:confirmReady(called.id, called.slotA, 3)
    sched:confirmReady(called.id, called.slotB, 3)
    sched:update(3)

    local ev = startedEvent(t, called.id)
    assertTrue(ev ~= nil, "match_started steht im Log")
    assertEq(ev.hostClient, called.slotB, "der Schnellere hostet")
    assertEq(ev.hostReason, "rtt", "Grund im Log")
    assertNear(ev.rttA, 30, 0.001, "Messwert A im Log")
    assertNear(ev.rttB, 2, 0.001, "Messwert B im Log")

    -- Und er ueberlebt die Rekonstruktion aus §7 -- sonst ist die Frage
    -- "warum hostet der?" nach einem Neustart nicht mehr zu beantworten.
    local rebuilt = Model.replay(t.log)
    assertEq(rebuilt.matches[called.id].hostReason, "rtt", "Grund nach dem Wiederaufbau")
end)

case("ohne Netz bleibt die Setznummer die vollstaendige Regel", function()
    local t = H.newTournament(4, { format = "single_elim" })
    H.draw(t)
    -- Ein Waehler ohne eine einzige Probe: genau die Lage im Testrunner und in
    -- Stufe B.
    local sched = Scheduler.new(t, { chooseHost = HostChoice.new():chooser() })
    H.allOnline(t, sched)
    sched:update(0)

    local called
    for _, id in ipairs(t.matchOrder) do
        if t.matches[id].status == Model.STATUS.READY then called = t.matches[id] break end
    end
    sched:confirmReady(called.id, called.slotA, 1)
    sched:confirmReady(called.id, called.slotB, 1)
    sched:update(1)

    local ev = startedEvent(t, called.id)
    assertEq(ev.hostClient, t:higherSeed(called.slotA, called.slotB), "hoeher Gesetzter")
    assertEq(ev.hostReason, "seed", "Grund")
end)

case("ohne chooseHost hostet weiterhin der hoeher Gesetzte", function()
    local t = H.newTournament(4, { format = "single_elim" })
    H.draw(t)
    local sched = Scheduler.new(t)
    H.allOnline(t, sched)
    sched:update(0)

    local called
    for _, id in ipairs(t.matchOrder) do
        if t.matches[id].status == Model.STATUS.READY then called = t.matches[id] break end
    end
    sched:confirmReady(called.id, called.slotA, 1)
    sched:confirmReady(called.id, called.slotB, 1)
    sched:update(1)

    local ev = startedEvent(t, called.id)
    assertEq(ev.hostClient, t:higherSeed(called.slotA, called.slotB), "Setznummer")
    assertEq(ev.hostReason, "seed", "und der Grund heisst auch so")
end)

return T
