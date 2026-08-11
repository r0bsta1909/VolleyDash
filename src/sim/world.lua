-- ============================================================================
-- src/sim/world.lua -- Weltkonstanten der Simulation (M0-04, ADR-004, B-01)
--
-- Das logische Spielfeld ist konstant 800 x 600. Es haengt NICHT von der
-- Fenstergroesse ab. Fensteranpassung passiert ausschliesslich als
-- Render-Transformation in src/render/viewport.lua.
--
-- Diese Datei liegt unter src/sim/ und ist damit love-frei: keine love.*,
-- kein os.*, kein math.random. Sonst laufen die Tests der Ebenen A und B
-- nicht headless (03_TECH section 3).
-- ============================================================================

local World = {}

-- Logisches Feld. Zwei Clients mit unterschiedlichem Fenster spielen damit
-- nachweislich dasselbe Spiel -- Wandpositionen, Aufschlagpunkte, Netzmitte
-- und Bot-Grenzen sind auf jedem Rechner gleich.
World.WIDTH  = 800
World.HEIGHT = 600

-- Netz: Breite und die daraus folgende Mitte. Die Hoehe kommt aus dem
-- Ruleset (netHeight) und gehoert deshalb nicht hierher.
World.NET_WIDTH = 10
World.NET_X     = World.WIDTH / 2 - World.NET_WIDTH / 2   -- 395

-- Aufschlagpositionen, im Prototyp als WORLD.width * 0.25 / 0.75 geschrieben.
World.SERVE_X = { World.WIDTH * 0.25, World.WIDTH * 0.75 } -- 200, 600

-- ---------------------------------------------------------------------------
-- Zeit (M0-05, B-02)
--
-- TICK_DT ist eine Konstante der Simulation, kein Parameter. Der dt aus
-- love.update erreicht die Physik nie (03_TECH section 3). Sonst verhaelt sich
-- der Ball auf 144 Hz anders als auf 60 Hz, und ein Frame-Haenger laesst ihn
-- durch das Netz tunneln.
-- ---------------------------------------------------------------------------
World.TICK_RATE = 60
World.TICK_DT   = 1 / 60

-- Spiral-of-Death-Schutz: hoechstens 15 Ticks werden in einem Frame nachgeholt.
-- Wer laenger haengt, verliert Simulationszeit statt in eine Endlosschleife zu
-- laufen.
World.MAX_FRAME_DT = 0.25

return World
