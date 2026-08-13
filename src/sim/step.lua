-- ============================================================================
-- src/sim/step.lua -- der einzige Ort, an dem sich der Spielzustand aendert
--
--     Step.tick(state, inputP1, inputP2, ruleset, events)
--
-- Gleiche Eingaben, gleicher Zustand, gleiches Ergebnis. Kein Zeichnen, kein
-- Ton, keine Tastatur, kein os.time, kein math.random (03_TECH §3).
--
-- Abweichung von der Signatur in `03_TECH` §3, bewusst und dokumentiert: der
-- Zustand wird **an Ort und Stelle** geaendert statt kopiert zurueckgegeben.
-- Eine Kopie je Tick waere auf der Zielhardware (acht Jahre alte Laptops)
-- unnoetiger Allokationsdruck, und ADR-002 hat Rollback verworfen -- niemand
-- braucht alte Zustaende. An der Determiniertheit aendert das nichts.
--
-- `events` ist eine vom Aufrufer gestellte Liste, die hier geleert und neu
-- gefuellt wird. Die Renderschicht uebersetzt sie in Staub, Wackeln und Klang.
-- ============================================================================

local World   = require("src.sim.world")
local Frame   = require("src.input.frame")
local Physics = require("src.sim.physics")
local Rules   = require("src.sim.rules")

local Step = {}

local function emit(events, event)
    events[#events + 1] = event
end

-- Sprung und Dash sind Ereignisse, die die Simulation aus dem InputFrame
-- ableitet (ADR-014). Die Quelle liefert Zustaende, das dash-Bit ist die
-- dokumentierte Ausnahme.
local function applyImpulses(state, index, bits, prev, ruleset, events)
    local blob = state.blobs[index]
    local dir = Frame.moveDir(bits)
    local dashed = false

    -- Der Dash ist im Vanilla-Regelwerk aus (01_GDD §3.1, ADR-006). Die
    -- Quelle meldet ihn trotzdem; die Simulation entscheidet (ADR-014).
    if Frame.has(bits, Frame.DASH) and ruleset.allowDash and blob.cooldownTimer <= 0 then
        dashed = true
        blob.cooldownTimer = ruleset.dashCooldown
        blob.dashGrace = 0.5
        if dir == 0 then
            blob.vy = ruleset.jumpForce * ruleset.dashUp
            blob.isGrounded = false
            emit(events, { type = "dash", player = index, up = true, x = blob.x, y = blob.y })
        else
            blob.dashTimer = 0.2
            blob.dashSpeed = dir * ruleset.moveSpeed * ruleset.dashSide
            emit(events, { type = "dash", player = index, up = false, x = blob.x, y = blob.y })
        end
    end

    -- Ein ausgefuehrter Aufwaerts-Dash verbraucht den Sprungtipp. Wurde der
    -- Dash dagegen vom Cooldown geschluckt, bleibt der Sprung.
    local upDashed = dashed and dir == 0
    if Frame.pressed(bits, prev, Frame.JUMP) and blob.isGrounded and not upDashed then
        blob.vy = ruleset.jumpForce
        blob.isGrounded = false
        emit(events, { type = "jump", player = index, x = blob.x, y = blob.y })
    end
end

local function updateBlobTimers(blob, dt, bits, ruleset)
    if blob.dashGrace > 0 then blob.dashGrace = blob.dashGrace - dt end
    if blob.cooldownTimer > 0 then blob.cooldownTimer = blob.cooldownTimer - dt end
    if blob.touchCooldown > 0 then blob.touchCooldown = blob.touchCooldown - dt end

    if blob.dashTimer > 0 then
        blob.dashTimer = blob.dashTimer - dt
        blob.vx = blob.dashSpeed
        blob.tiltAngle = (blob.dashSpeed > 0) and 0.6 or -0.6
    else
        blob.tiltAngle = blob.tiltAngle * 0.8
        local speed = blob.isGrounded and ruleset.moveSpeed or (ruleset.moveSpeed * ruleset.airControl)
        blob.vx = Frame.moveDir(bits) * speed
    end
end

-- Ein Simulationsschritt von World.TICK_DT. Gibt die Ereignisliste zurueck.
function Step.tick(state, in1, in2, ruleset, events)
    events = events or {}
    for i = #events, 1, -1 do events[i] = nil end

    local phase = state.match.phase
    if phase == "menu" or phase == "gameover" then return events end

    local dt = World.TICK_DT
    local groundY = ruleset.blobGroundY or 500

    applyImpulses(state, 1, in1, state.input.prev[1], ruleset, events)
    applyImpulses(state, 2, in2, state.input.prev[2], ruleset, events)
    state.input.prev[1], state.input.prev[2] = in1, in2

    state.net.y = groundY - ruleset.netHeight
    state.net.h = ruleset.netHeight
    state.ball.radius = ruleset.ballRadius

    if state.match.phase == "serve" then
        state.ball.y = groundY - ruleset.serveHeight
        state.rally.serveTimer = state.rally.serveTimer + dt
    end

    if state.rally.faultTimer > 0 then
        state.rally.faultTimer = state.rally.faultTimer - dt
        if state.rally.faultTimer <= 0 then
            local loser = state.rally.faultPlayer
            Rules.awardPointTo(state, ruleset, loser == 1 and 2 or 1, events)
            return events
        end
    end

    updateBlobTimers(state.blobs[1], dt, in1, ruleset)
    Physics.updateBlob(state.blobs[1], 1, dt, 0, state.net.x, ruleset, groundY, events)

    updateBlobTimers(state.blobs[2], dt, in2, ruleset)
    Physics.updateBlob(state.blobs[2], 2, dt, state.net.x + state.net.w, World.WIDTH,
        ruleset, groundY, events)

    if state.match.phase == "play" then
        state.rally.timer = state.rally.timer + dt
        Physics.integrateBall(state, dt, ruleset, events)
    end

    Physics.netCollision(state, events)
    Physics.blobBall(state, 1, Frame.has(in1, Frame.SMASH), ruleset, events)
    Physics.blobBall(state, 2, Frame.has(in2, Frame.SMASH), ruleset, events)

    Physics.capSpeed(state, ruleset)
    Rules.checkGround(state, ruleset, events)
    Rules.checkRallyTimeout(state, ruleset, events)

    return events
end

-- ---------------------------------------------------------------------------
-- Sichtbar fuer die Vorhersage (M3-01, ADR-017)
--
-- Genau die zwei Schritte, die `Step.tick` oben fuer einen Blob geht. Sie
-- werden hier nur sichtbar gemacht, nicht veraendert: kein Zahlenwert, keine
-- Zeile Logik, kein anderes Verhalten. `src/net/prediction.lua` ruft sie auf,
-- statt sie nachzubauen -- sechs nachgebaute Zeilen waeren eine zweite
-- Wahrheit ueber die Blob-Bewegung und wuerden beim ersten Eingriff in
-- `02_CODE_AUDIT` §4 still gegen den Host driften.
-- ---------------------------------------------------------------------------
Step.applyImpulses    = applyImpulses
Step.updateBlobTimers = updateBlobTimers

return Step
