-- ============================================================================
-- src/net/snapshot.lua -- Abbildung Spielzustand <-> Snapshot (M2-01)
--
-- Der Snapshot ist die einzige Wahrheit, die der Client zu sehen bekommt
-- (ADR-002). Diese Datei legt fest, WELCHE Felder das sind und wie sie
-- kodiert werden; `src/net/protocol.lua` legt fest, wie sie zu Bytes werden.
--
-- Bewusst getrennt und bewusst `love`-frei: die Feldliste, die Phasenkodierung
-- und die Quantisierung sind die Stellen, an denen sich ein Fehler still
-- fortpflanzt -- ein falsch kodierter Phasenwert sieht auf der Leitung aus wie
-- ein richtiger. Headless testbar ist hier mehr wert als jede Ersparnis an
-- Dateien (`03_TECH` §2, Ergaenzung M2-01).
--
-- Vollstaendige Festlegung: `04_NETCODE_SPEC` §6.
-- ============================================================================

local Snapshot = {}

-- ---------------------------------------------------------------------------
-- Feldliste
--
-- Reihenfolge und Typen in EINER Tabelle. `protocol.lua` baut daraus die
-- Formatzeichenkette fuer pack und unpack -- damit koennen die beiden Seiten
-- nicht auseinanderlaufen, wenn hier jemand ein Feld einschiebt.
-- ---------------------------------------------------------------------------
Snapshot.FIELDS = {
    { "tick",            "i4" },
    { "ballX",           "f"  },
    { "ballY",           "f"  },
    { "ballVX",          "f"  },
    { "ballVY",          "f"  },
    { "ballRot",         "f"  },
    { "blob1X",          "f"  },
    { "blob1Y",          "f"  },
    { "blob2X",          "f"  },
    { "blob2Y",          "f"  },
    { "blob1VY",         "f"  },
    { "blob2VY",         "f"  },
    { "blob1Tilt",       "f"  },
    { "blob2Tilt",       "f"  },
    { "blob1Cd",         "B"  },
    { "blob2Cd",         "B"  },
    { "scoreA",          "B"  },
    { "scoreB",          "B"  },
    { "phase",           "B"  },
    { "servingPlayer",   "B"  },
    { "touchCount",      "B"  },
    { "lastTouchPlayer", "B"  },
    { "flags",           "B"  },
    { "ackInputTick",    "i4" },
}

Snapshot.SIZE = 69   -- Nutzlast ohne die drei Header-Byte, siehe Test

-- ---------------------------------------------------------------------------
-- Phasen
--
-- `src/sim/state.lua` kennt genau vier: menu | serve | play | gameover.
-- Fassung 1.0 der Netcode-Spec kodierte `fault` und `setover`, die es nicht
-- gibt, und liess `menu` und `gameover` weg (W-02 aus Handoff CC-03).
--
-- Ein Fehler ist KEINE Phase, sondern `rally.faultTimer > 0` waehrend `play`.
-- Er steckt in den Flags.
-- ---------------------------------------------------------------------------
Snapshot.PHASE_CODE = {
    serve    = 0,
    play     = 1,
    gameover = 2,
    menu     = 3,
}

Snapshot.PHASE_NAME = {}
for name, code in pairs(Snapshot.PHASE_CODE) do Snapshot.PHASE_NAME[code] = name end

-- ---------------------------------------------------------------------------
-- Flags
-- ---------------------------------------------------------------------------
Snapshot.FLAG = {
    GROUNDED1 = 1,
    GROUNDED2 = 2,
    DASHING1  = 4,
    DASHING2  = 8,
}

Snapshot.FAULT_SHIFT = 16   -- Bit 4 und 5 tragen faultPlayer (0, 1 oder 2)

-- Ohne Bit-Operatoren, wie ueberall im Projekt: Lua 5.1 hat keine.
local function hasFlag(flags, mask)
    return math.floor(flags / mask) % 2 == 1
end

-- ---------------------------------------------------------------------------
-- Quantisierung des Dash-Cooldowns
--
-- Der Wert ist Anzeige, kein Simulationswert: das HUD zeichnet einen Balken
-- der Breite `cooldownTimer / dashCooldown`. Genau dieses Verhaeltnis geht
-- als ein Byte ueber die Leitung.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Die Null hat ein Vorzeichen -- auf jeder Plattform ein anderes
--
-- IEEE 754 kennt +0 und -0. Die Simulation erzeugt die negative Null beilaeufig:
-- `ball.vx = -math.abs(ball.vx) * 0.8` bei vx = 0 (physics.lua:124).
--
-- GEMESSEN im CI-Lauf 13 (2026-08-12): Unter Windows-x86-64 liefert `-zero`
-- eine negative Null, unter macOS-ARM64 eine positive. LOEVE 11.5 faehrt auf
-- Apple Silicon den Interpreter statt des JIT (`04_NETCODE_SPEC` §1), und die
-- Arithmetik verhaelt sich dort an dieser Stelle anders. Das ist kein Fehler
-- von `love.data.pack` -- die Bytes eines vollstaendigen Snapshots sind auf
-- beiden Plattformen identisch, geprueft in T-N-07.
--
-- Fuer das Spiel ist der Unterschied bedeutungslos: -0 == 0, und niemand sieht
-- ein Vorzeichen an einer stehenden Geschwindigkeit. Fuer die byteweise
-- Pruefsumme aus §9 (M3-03) waere er ein Fehlalarm in jedem Tick, in dem
-- irgendetwas stillsteht. Deshalb wird die Null hier einmal begradigt:
-- `v + 0.0` macht aus -0 eine +0 und laesst jeden anderen Wert unberuehrt.
local function norm(v)
    return v + 0.0
end

local function packRatio(value, span)
    if not span or span <= 0 then return 0 end
    local ratio = value / span
    if ratio <= 0 then return 0 end
    if ratio >= 1 then return 255 end
    return math.floor(ratio * 255 + 0.5)
end

-- ---------------------------------------------------------------------------
-- Zustand -> Snapshot
-- ---------------------------------------------------------------------------

function Snapshot.from(state, tick, ackInputTick, ruleset)
    local ball, blobs = state.ball, state.blobs
    local match, rally = state.match, state.rally

    local phase = Snapshot.PHASE_CODE[match.phase]
    if not phase then
        -- Absichtlich hart: eine neue Phase in `state.lua` ohne Eintrag hier
        -- wuerde sonst als `serve` ueber die Leitung gehen und der Client
        -- zeigte stumm etwas anderes an als der Host spielt.
        error("Snapshot: unbekannte Phase '" .. tostring(match.phase)
              .. "' -- 04_NETCODE_SPEC §6 nachziehen", 2)
    end

    local flags = 0
    if blobs[1].isGrounded then flags = flags + Snapshot.FLAG.GROUNDED1 end
    if blobs[2].isGrounded then flags = flags + Snapshot.FLAG.GROUNDED2 end
    if blobs[1].dashTimer > 0 then flags = flags + Snapshot.FLAG.DASHING1 end
    if blobs[2].dashTimer > 0 then flags = flags + Snapshot.FLAG.DASHING2 end

    local faultPlayer = 0
    if rally.faultTimer > 0 then faultPlayer = rally.faultPlayer end
    flags = flags + faultPlayer * Snapshot.FAULT_SHIFT

    local span = ruleset.dashCooldown

    local snap = {
        tick            = tick,
        ballX           = ball.x,
        ballY           = ball.y,
        ballVX          = ball.vx,
        ballVY          = ball.vy,
        ballRot         = ball.rotation,
        blob1X          = blobs[1].x,
        blob1Y          = blobs[1].y,
        blob2X          = blobs[2].x,
        blob2Y          = blobs[2].y,
        blob1VY         = blobs[1].vy,
        blob2VY         = blobs[2].vy,
        blob1Tilt       = blobs[1].tiltAngle,
        blob2Tilt       = blobs[2].tiltAngle,
        blob1Cd         = packRatio(blobs[1].cooldownTimer, span),
        blob2Cd         = packRatio(blobs[2].cooldownTimer, span),
        scoreA          = match.score[1],
        scoreB          = match.score[2],
        phase           = phase,
        servingPlayer   = match.servingPlayer,
        touchCount      = math.min(255, rally.touchCount),
        lastTouchPlayer = rally.lastTouchPlayer,
        flags           = flags,
        ackInputTick    = ackInputTick or -1,
    }

    -- Eine Schleife statt zwoelf Aufrufe: ein neues Fliesskommafeld in
    -- `FIELDS` ist damit von selbst mit erfasst.
    for _, field in ipairs(Snapshot.FIELDS) do
        if field[2] == "f" then snap[field[1]] = norm(snap[field[1]]) end
    end

    return snap
end

-- ---------------------------------------------------------------------------
-- Snapshot -> Zustand
--
-- Schreibt in einen vorhandenen Zustand, statt einen neuen zu bauen: der
-- Client haelt genau einen und die Renderschicht haelt Verweise darauf
-- (`GameView.capture`).
--
-- Gibt false zurueck, wenn der Snapshot unbrauchbar ist -- ein unbekannter
-- Phasenwert oder gesetzte reservierte Flags. Verworfen wird er dann ganz;
-- stilles Zurechtbiegen verdeckt Protokollfehler (13_INPUTFRAME_FORMAT §2
-- haelt dieselbe Regel fuer den InputFrame fest).
-- ---------------------------------------------------------------------------

function Snapshot.apply(snap, state, ruleset)
    local phase = Snapshot.PHASE_NAME[snap.phase]
    if not phase then return false, "unbekannte Phase " .. tostring(snap.phase) end
    if snap.flags >= 64 then return false, "reserviertes Flag-Bit gesetzt" end

    local faultPlayer = math.floor(snap.flags / Snapshot.FAULT_SHIFT) % 4
    if faultPlayer > 2 then return false, "faultPlayer " .. faultPlayer end

    local ball, blobs = state.ball, state.blobs
    local match, rally = state.match, state.rally

    ball.x, ball.y = snap.ballX, snap.ballY
    ball.vx, ball.vy = snap.ballVX, snap.ballVY
    ball.rotation = snap.ballRot
    ball.radius = ruleset.ballRadius

    blobs[1].x, blobs[1].y, blobs[1].vy = snap.blob1X, snap.blob1Y, snap.blob1VY
    blobs[2].x, blobs[2].y, blobs[2].vy = snap.blob2X, snap.blob2Y, snap.blob2VY
    blobs[1].tiltAngle, blobs[2].tiltAngle = snap.blob1Tilt, snap.blob2Tilt
    blobs[1].isGrounded = hasFlag(snap.flags, Snapshot.FLAG.GROUNDED1)
    blobs[2].isGrounded = hasFlag(snap.flags, Snapshot.FLAG.GROUNDED2)
    blobs[1].dashTimer = hasFlag(snap.flags, Snapshot.FLAG.DASHING1) and 1 or 0
    blobs[2].dashTimer = hasFlag(snap.flags, Snapshot.FLAG.DASHING2) and 1 or 0

    local span = ruleset.dashCooldown or 0
    blobs[1].cooldownTimer = snap.blob1Cd / 255 * span
    blobs[2].cooldownTimer = snap.blob2Cd / 255 * span

    match.score[1], match.score[2] = snap.scoreA, snap.scoreB
    match.phase = phase
    match.servingPlayer = snap.servingPlayer
    match.inProgress = (phase ~= "menu")

    rally.touchCount = snap.touchCount
    rally.lastTouchPlayer = snap.lastTouchPlayer
    rally.faultPlayer = faultPlayer
    -- Kein echter Timer: der Client zaehlt nichts herunter, das HUD fragt nur
    -- `faultTimer > 0` ab. Der Host schickt in jedem Tick den aktuellen Stand.
    rally.faultTimer = (faultPlayer > 0) and 1 or 0

    -- Netz und Ballradius haengen am Ruleset, nicht am Snapshot -- beide
    -- Seiten haben dasselbe Ruleset (04_NETCODE_SPEC §6).
    local groundY = ruleset.blobGroundY or 500
    state.net.y = groundY - ruleset.netHeight
    state.net.h = ruleset.netHeight

    return true
end

return Snapshot
