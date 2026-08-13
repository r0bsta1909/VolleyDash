-- ============================================================================
-- src/render/snapshot_events.lua -- Kosmetik aus Snapshot-Deltas (M3-02)
--
-- `04_NETCODE_SPEC` §6. Der Gast simuliert nicht und bekommt deshalb keine
-- Ereignisse aus `Step.tick`. Bis M2 war sein Bild still: keine Staubwolke,
-- kein Klang, kein Wackeln. Die Ausloeser stecken aber im Zustand -- man muss
-- zwei aufeinanderfolgende Snapshots nebeneinanderhalten.
--
--     SnapshotEvents.diff(prev, curr, ruleset, events) -> events
--
-- Eine REINE FUNKTION ueber zwei Snapshots. Genau deshalb liegt sie hier und
-- nicht in `fx.lua`: sie entscheidet, wann es staubt, und was entscheidet,
-- gehoert in den Headless-Runner (`07_TEST_PLAN` §7, Handoff CC-04 §1).
-- Diese Datei ist love-frei; `fx_events.lua` daneben ist es nicht.
--
-- Die Ereignistypen sind WOERTLICH die aus `Step.tick`. Damit uebersetzt
-- `src/render/fx_events.lua` beide Seiten mit demselben Code -- zwei
-- Zuordnungen waeren zwei Wahrheiten darueber, wann es staubt.
--
-- Was hier NICHT herauskommt und warum, steht in `04_NETCODE_SPEC` §6:
-- `smash` und `dash_save` haengen an einer Taste im Moment des Kontakts und
-- hinterlassen keine Spur im Zustand.
-- ============================================================================

local World    = require("src.sim.world")
local Snapshot = require("src.net.snapshot")

local SnapshotEvents = {}

-- Der Ball wird auf die Wand GESETZT (physics.lua:63), steht im Snapshot also
-- exakt auf dem Radius. Eine halbe Pixelbreite Spiel fuer float32.
SnapshotEvents.WALL_EPS = 0.5

-- Netzkoerper plus Ballradius, mit etwas Luft: der Kappenstoss versetzt den
-- Ball entlang der Normalen und nicht exakt auf die Kante.
SnapshotEvents.NET_EPS = 2.0

-- Wie hoch der Ball im vorigen Snapshot noch stehen darf, damit ein Rallye-
-- Ende als Bodentreffer durchgeht. Ein Ball mit maxBallSpeed legt in einem
-- Tick rund 23 px zurueck; 60 px sind drei Ticks Reserve und liegen weit
-- unter der Netzkante.
SnapshotEvents.GROUND_REACH = 60

local function has(flags, mask)
    return math.floor(flags / mask) % 2 == 1
end

local function faultPlayerOf(flags)
    return math.floor(flags / Snapshot.FAULT_SHIFT) % 4
end

local function emit(events, event)
    events[#events + 1] = event
end

-- Vorzeichenwechsel mit Bewegung auf beiden Seiten. `0 -> +` ist kein Abprall,
-- sondern ein Anstoss.
local function flipped(a, b)
    return (a < 0 and b > 0) or (a > 0 and b < 0)
end

local function blobOf(snap, index)
    if index == 1 then
        return snap.blob1X, snap.blob1Y, snap.blob1VY, snap.blob1Cd,
               Snapshot.FLAG.GROUNDED1, Snapshot.FLAG.DASHING1
    end
    return snap.blob2X, snap.blob2Y, snap.blob2VY, snap.blob2Cd,
           Snapshot.FLAG.GROUNDED2, Snapshot.FLAG.DASHING2
end

-- ---------------------------------------------------------------------------
-- Ball gegen Wand und Netz
-- ---------------------------------------------------------------------------

local function ballHits(prev, curr, ruleset, events)
    local radius = ruleset.ballRadius

    if flipped(prev.ballVX, curr.ballVX) then
        if curr.ballX <= radius + SnapshotEvents.WALL_EPS then
            emit(events, { type = "wall_hit", x = curr.ballX, y = curr.ballY })
        elseif curr.ballX >= World.WIDTH - radius - SnapshotEvents.WALL_EPS then
            emit(events, { type = "wall_hit", x = curr.ballX, y = curr.ballY })
        end
    end

    -- Netz: Rechteck mit Halbkreis obendrauf (physics.lua:87). Fuer die
    -- Kosmetik reicht die Umgebung des Koerpers -- getroffen wird er, wenn
    -- der Ball dort ist und eine Geschwindigkeitskomponente umschlaegt.
    local netLeft  = World.NET_X - radius - SnapshotEvents.NET_EPS
    local netRight = World.NET_X + World.NET_WIDTH + radius + SnapshotEvents.NET_EPS
    local netTop   = (ruleset.blobGroundY or 500) - ruleset.netHeight
              - radius - World.NET_WIDTH / 2 - SnapshotEvents.NET_EPS

    if curr.ballX >= netLeft and curr.ballX <= netRight and curr.ballY >= netTop then
        if flipped(prev.ballVX, curr.ballVX) or flipped(prev.ballVY, curr.ballVY) then
            emit(events, { type = "net_hit", x = curr.ballX, y = curr.ballY })
        end
    end
end

-- ---------------------------------------------------------------------------
-- Blobs: Beruehrung, Landung, Sprung, Dash
-- ---------------------------------------------------------------------------

local function blobEvents(prev, curr, ruleset, events)
    local groundY = ruleset.blobGroundY or 500

    for index = 1, 2 do
        local x, y, vy, cd, grounded, dashing = blobOf(curr, index)
        -- Die Position VOR dem Sprung ist die, an der der Staub steht.
        local px, py, _, pcd = blobOf(prev, index)

        local wasDown = has(prev.flags, grounded)
        local isDown  = has(curr.flags, grounded)

        if isDown and not wasDown then
            emit(events, { type = "land", player = index, x = x, y = groundY })
        elseif wasDown and not isDown and vy < 0 then
            emit(events, { type = "jump", player = index, x = px, y = py })
        end

        -- Der Cooldown ist quantisiert (ein Byte, §6). Ein Dash setzt ihn von
        -- ~0 auf voll; heruntergezaehlt wird er in kleinen Schritten. Der
        -- Sprung nach oben ist damit eindeutig.
        if cd > pcd + 128 then
            emit(events, {
                type = "dash", player = index, up = not has(curr.flags, dashing),
                x = x, y = y,
            })
        end
    end
end

-- ---------------------------------------------------------------------------
-- Ballwechsel: Beruehrung, Fehler, Punkt
-- ---------------------------------------------------------------------------

local function rallyEvents(prev, curr, ruleset, events)
    local prevPhase = Snapshot.PHASE_NAME[prev.phase]
    local currPhase = Snapshot.PHASE_NAME[curr.phase]

    -- Beruehrung. `touchCount` steigt, oder der Zaehler springt auf einen
    -- anderen Spieler (`Rules.registerTouch` setzt ihn dann auf 1 zurueck).
    -- Der Wechsel auf 0 ist keine Beruehrung, sondern der Seitenwechsel des
    -- Balls (`Rules.updateBallSide`).
    local touched = curr.touchCount > prev.touchCount
        or (curr.lastTouchPlayer ~= prev.lastTouchPlayer and curr.lastTouchPlayer ~= 0)

    -- Der Aufschlag ist derselbe Vorgang: `Physics.blobBall` schaltet die
    -- Phase um und zaehlt im selben Tick die Beruehrung.
    if touched or (prevPhase == "serve" and currPhase == "play") then
        emit(events, { type = "blob_hit", player = curr.lastTouchPlayer })
    end

    local prevFault = faultPlayerOf(prev.flags)
    local currFault = faultPlayerOf(curr.flags)
    if currFault ~= 0 and prevFault == 0 then
        emit(events, { type = "fault", player = currFault })
    end

    -- Ende des Ballwechsels. Nur der Aufschlaeger punktet; verliert er, gibt
    -- es Seitenaus und der Aufschlaeger wechselt (`Rules.awardPointTo`).
    local scored = (curr.scoreA > prev.scoreA) or (curr.scoreB > prev.scoreB)
    local sideOut = (not scored) and curr.servingPlayer ~= prev.servingPlayer
    local ended = scored or sideOut

    if ended then
        -- Der Bodentreffer ist im Snapshot nie zu sehen: `Rules.checkGround`
        -- setzt den Ballwechsel im SELBEN Tick zurueck, der Ball steht also
        -- schon wieder auf der Aufschlaghoehe. Rekonstruiert wird er aus der
        -- Ballhoehe im vorigen Bild -- ein Fehlerwurf und ein Rallye-Timeout
        -- enden dagegen in der Luft.
        local ballGroundY = ruleset.ballGroundY or 520
        local low = prev.ballY + ruleset.ballRadius
                    >= ballGroundY - SnapshotEvents.GROUND_REACH
        if low and prevFault == 0 and prevPhase == "play" then
            emit(events, { type = "ground_hit", x = prev.ballX, y = ballGroundY })
        end
    end

    if scored then
        local to = (curr.scoreA > prev.scoreA) and 1 or 2
        if currPhase == "gameover" then
            emit(events, { type = "match_over", winner = to })
        else
            emit(events, { type = "point", to = to })
        end
    elseif sideOut then
        emit(events, { type = "side_out", to = curr.servingPlayer })
    end

    -- Sprungstelle fuer die Render-Interpolation (M0-05): der Ball steht ohne
    -- Bewegung woanders. Das Ereignis kommt zuletzt, damit `GameView.capture`
    -- nach allem anderen laeuft.
    if currPhase == "serve" and prevPhase ~= "serve" then
        emit(events, { type = "rally_reset", server = curr.servingPlayer })
    end
end

-- ---------------------------------------------------------------------------
-- Alles zusammen
--
-- `events` darf mitgegeben werden; die Liste wird dann geleert und neu
-- gefuellt -- dieselbe Vereinbarung wie bei `Step.tick`.
-- ---------------------------------------------------------------------------

function SnapshotEvents.diff(prev, curr, ruleset, events)
    events = events or {}
    for i = #events, 1, -1 do events[i] = nil end

    if not prev or not curr then return events end

    -- Ein uebersprungener Snapshot (Kanal 1 ist unzuverlaessig) macht die
    -- Ableitung nicht falsch, nur ungenauer. Ein RUECKWAERTS gelesener macht
    -- sie falsch: doppelte Punkte, Staub aus der Vergangenheit.
    if curr.tick <= prev.tick then return events end

    ballHits(prev, curr, ruleset, events)
    blobEvents(prev, curr, ruleset, events)
    rallyEvents(prev, curr, ruleset, events)

    return events
end

-- Enthaelt die Liste ein Ereignis, nach dem der eigene Blob vom Host versetzt
-- wurde? Dann uebernimmt die Vorhersage hart, statt weich zu korrigieren
-- (ADR-017) -- `Rules.resetBall` setzt beide Blobs auf die Aufschlagposition.
function SnapshotEvents.isTakeover(events)
    for i = 1, #events do
        if events[i].type == "rally_reset" then return true end
    end
    return false
end

return SnapshotEvents
