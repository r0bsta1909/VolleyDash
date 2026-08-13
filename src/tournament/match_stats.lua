-- ============================================================================
-- src/tournament/match_stats.lua -- die zwei Zahlen aus der Simulation (M4-09)
--
-- `05_TOURNAMENT` §11 verlangt fuenf Statistiken je Spieler. Drei fallen im
-- Turniermodul an (Matches, Saetze, Punkte). Die anderen beiden -- LAENGSTE
-- RALLYE und SCHNELLSTER BALL -- fallen in der Simulation an und muessen
-- deshalb mit dem Ergebnisbericht des Match-Hosts mitkommen.
--
-- ---------------------------------------------------------------------------
-- Warum das hier steht und nicht in `src/sim/`
-- ---------------------------------------------------------------------------
--
-- Die Simulation zaehlt nichts mit. Sie ist numerisch unveraenderlich
-- (`02_CODE_AUDIT` §4), und eine Statistik ist kein Spielverhalten -- sie
-- entstuende dort nur, weil die Daten gerade danebenliegen. Dieser Beobachter
-- LIEST den Zustand nach jedem Tick und schreibt nichts zurueck. Damit bleibt
-- `sim/` unberuehrt, und der Beobachter laeuft headless: er kennt nur eine
-- Tabelle mit `match.phase`, `ball` und `rally`, kein `love` und keine Szene.
--
-- ---------------------------------------------------------------------------
-- Gemessen wird nur auf dem Match-Host
-- ---------------------------------------------------------------------------
--
-- Der Match-Host ist die Autoritaet (ADR-002). Ein Gast, der dieselbe Zahl aus
-- seinem vorhergesagten Zustand rechnet, haette eine zweite Wahrheit ohne
-- Schiedsrichter -- und die Abweichung faende niemand, weil beide plausibel
-- aussehen.
-- ============================================================================

local MatchStats = {}
MatchStats.__index = MatchStats

function MatchStats.new()
    return setmetatable({
        longestRally = 0,   -- Sekunden
        fastestBall  = 0,   -- Pixel/s im logischen Feld (800x600, ADR-004)
        fastestBy    = 0,   -- Slot 1 oder 2; 0 heisst "niemand"
    }, MatchStats)
end

-- Nach jedem Simulationsschritt aufzurufen, mit dem Zustand DANACH.
--
-- Die laengste Rallye braucht keine Erkennung des Rallye-Endes: `rally.timer`
-- waechst waehrend `play` und wird beim Zuruecksetzen auf 0 gestellt. Das
-- Maximum ueber alle Ticks ist deshalb genau die laengste Rallye -- und diese
-- Rechnung uebersteht auch den Fall, dass ein Ballwechsel durch ein Satzende
-- endet und gar kein `rally_reset` mehr kommt.
function MatchStats:observe(state)
    if not state or state.match.phase ~= "play" then return end

    local rally = state.rally
    if rally.timer > self.longestRally then
        self.longestRally = rally.timer
    end

    local ball = state.ball
    local speed = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
    if speed > self.fastestBall then
        self.fastestBall = speed
        -- Zugeordnet wird dem, der ihn zuletzt beruehrt hat. Ein Ball, den
        -- niemand angefasst hat (Aufschlag im Fall, Abpraller von der Wand
        -- nach einem Seitenwechsel), gehoert niemandem -- `lastTouchPlayer`
        -- ist dann 0, und genau das wird uebernommen.
        self.fastestBy = rally.lastTouchPlayer or 0
    end
end

-- Ein abgebrochenes oder per Walkover beendetes Match liefert nichts; die
-- Zaehler beginnen mit jedem Match neu.
function MatchStats:reset()
    self.longestRally, self.fastestBall, self.fastestBy = 0, 0, 0
end

-- Die Form, die `MATCH_REPORT` (0x43) und `match_finished` tragen.
function MatchStats:toReport()
    return {
        longestRally = self.longestRally,
        fastestBall  = self.fastestBall,
        fastestBy    = self.fastestBy,
    }
end

return MatchStats
