-- ============================================================================
-- src/tournament/host_choice.lua -- wer ein Match hostet (M4-09, ADR-022)
--
-- `05_TOURNAMENT` §8 und §8.1, T-01. love-frei, damit die Regel headless
-- pruefbar ist -- sie entscheidet, also gehoert sie hierher und nicht in
-- `src/net/`.
--
-- ---------------------------------------------------------------------------
-- Die Regel in drei Zeilen
-- ---------------------------------------------------------------------------
--
--   1. Median der RTT-Proben der letzten 5 s je Spieler.
--   2. Unterschied ueber 5 ms  -> der Schnellere hostet.
--   3. Sonst (auch: keine Proben) -> die kleinere Setznummer.
--
-- ---------------------------------------------------------------------------
-- Warum eine Schwelle, und warum diese
-- ---------------------------------------------------------------------------
--
-- Seit ADR-019 wird ueber Kabel gespielt; dort liegt die RTT bei 1-2 ms und
-- der Unterschied zwischen zwei Teilnehmern im Rauschen. Ein Mass, das auf
-- Rauschen entscheidet, ist ein Muenzwurf mit Messgeraet -- und den schliesst
-- `CLAUDE.md` §3.2 aus. 5 ms sind weniger als ein Drittel eines
-- Simulationsschritts (1/60 s); darunter kann der Unterschied am Match nichts
-- aendern.
--
-- Die Folge ist Absicht und keine Panne: Ueber Kabel ist der Gleichstandsfall
-- der NORMALFALL. Die Setznummer ist damit in der Praxis die Regel, die RTT
-- die Ausnahme fuer den Fall, dass doch jemand im WLAN sitzt (N-01).
--
-- Median statt Mittel: Eine GC-Pause oder ein verlorenes PONG erzeugt genau
-- einen Ausreisser unter zehn Proben. Der Mittelwert nimmt ihn mit und kann
-- daran die Wahl kippen.
-- ============================================================================

local HostChoice = {}
HostChoice.__index = HostChoice

-- Fenster der Proben. Bei `Host.PING_INTERVAL = 0.5` sind das bis zu zehn.
HostChoice.WINDOW_SECONDS = 5.0

-- Unterhalb davon gilt Gleichstand. Siehe Kopf.
HostChoice.THRESHOLD_MS = 5.0

function HostChoice.new(opts)
    opts = opts or {}
    return setmetatable({
        window    = opts.window or HostChoice.WINDOW_SECONDS,
        threshold = opts.threshold or HostChoice.THRESHOLD_MS,
        samples   = {},   -- [pid] = { {at=, rtt=}, … }
    }, HostChoice)
end

-- Eine Probe in Millisekunden. Der Turnier-Host misst sie ohnehin ueber
-- PING/PONG fuer die Anzeige -- die Wahl kostet keine zusaetzliche Nachricht.
function HostChoice:sample(pid, rttMs, now)
    if pid == nil or rttMs == nil then return end
    local list = self.samples[pid]
    if not list then
        list = {}
        self.samples[pid] = list
    end
    list[#list + 1] = { at = now or 0, rtt = rttMs }
end

-- Der Turnier-Host misst zu sich selbst nichts -- also traegt er null ein.
-- Null Netzspruenge ist die beste Verbindung, die es gibt; dass er sein
-- eigenes Match damit immer hostet, ist das Mass und kein Sonderfall
-- (ADR-022).
function HostChoice:sampleSelf(pid, now)
    self:sample(pid, 0, now)
end

function HostChoice:forget(pid)
    self.samples[pid] = nil
end

-- Median der Proben innerhalb des Fensters, oder nil. Aeltere Proben werden
-- dabei weggeworfen: Das Fenster ist der Zweck, nicht ein Filter darueber.
function HostChoice:median(pid, now)
    local list = self.samples[pid]
    if not list then return nil end
    now = now or 0

    local keep, values = {}, {}
    for _, s in ipairs(list) do
        if now - s.at <= self.window then
            keep[#keep + 1] = s
            values[#values + 1] = s.rtt
        end
    end
    self.samples[pid] = keep

    local n = #values
    if n == 0 then return nil end
    table.sort(values)
    if n % 2 == 1 then return values[(n + 1) / 2] end
    return (values[n / 2] + values[n / 2 + 1]) / 2
end

-- ---------------------------------------------------------------------------
-- Die Entscheidung
--
-- Reine Funktion, damit sie ohne Fenster und ohne Uhr pruefbar ist. Gibt den
-- Gewinner, den Grund ("rtt" oder "seed") und die beiden Messwerte zurueck.
-- ---------------------------------------------------------------------------

function HostChoice.decide(a, b, rttA, rttB, higherSeed, threshold)
    threshold = threshold or HostChoice.THRESHOLD_MS

    if a == nil then return b, "seed", rttA, rttB end
    if b == nil then return a, "seed", rttA, rttB end

    if rttA and rttB and math.abs(rttA - rttB) > threshold then
        if rttA < rttB then return a, "rtt", rttA, rttB end
        return b, "rtt", rttA, rttB
    end

    -- Gleichstand -- oder eine Seite hat keine Proben. Beides faellt auf
    -- dieselbe Regel: die Setznummer (ADR-021, ADR-022).
    return higherSeed, "seed", rttA, rttB
end

-- ---------------------------------------------------------------------------
-- Einmal je Match, nicht einmal je Frage
--
-- Der Turnier-Host braucht die Antwort schon beim AUFRUF -- er muss dem
-- kuenftigen Match-Host sagen, dass er einen Port oeffnen soll. Der Scheduler
-- fragt sie ein zweites Mal beim START. Waeren das zwei Rechnungen, koennte
-- die RTT dazwischen wandern und der Gast verbaende sich zu einem Rechner, der
-- inzwischen gar nicht mehr hostet.
--
-- Also: Die erste Frage entscheidet, jede weitere bekommt dieselbe Antwort.
-- `forgetMatch` loescht sie -- nach E-06 wird ein neu angesetztes Match auch
-- neu gemessen, denn genau die Verbindung, an der es gescheitert ist, kann die
-- schlechtere gewesen sein.
-- ---------------------------------------------------------------------------

function HostChoice:decideFor(match, t, now)
    self.decided = self.decided or {}
    local kept = self.decided[match.id]
    if kept then return kept.pid, kept.info end

    local a, b = match.slotA, match.slotB
    local rttA = a and self:median(a, now) or nil
    local rttB = b and self:median(b, now) or nil
    local pid, reason = HostChoice.decide(a, b, rttA, rttB,
        t:higherSeed(a, b), self.threshold)
    local info = { rttA = rttA, rttB = rttB, hostReason = reason }

    self.decided[match.id] = { pid = pid, info = info }
    return pid, info
end

function HostChoice:forgetMatch(matchId)
    if self.decided then self.decided[matchId] = nil end
end

-- Der Einhaengepunkt fuer `Scheduler.new(t, { chooseHost = … })`. Gibt den
-- Gewinner plus eine Tabelle zurueck, die im Log landet -- "warum hostet der?"
-- ist die Frage, die am Abend gestellt wird, und sie muss aus der Datei zu
-- beantworten sein.
function HostChoice:chooser()
    return function(match, t, now)
        return self:decideFor(match, t, now)
    end
end

return HostChoice
