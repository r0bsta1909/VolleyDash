-- ============================================================================
-- src/sim/rules.lua -- Beruehrungszaehler, Fehler, Punkte, Satzende (M0-08)
--
-- Alles, was den Ballwechsel bewertet. Kein Zeichnen, kein Ton, kein Zufall.
-- Kosmetik entsteht ausschliesslich ueber `events`; die Renderschicht
-- uebersetzt sie in Staub, Wackeln und Klang.
--
-- B-05 (Zwei-Punkte-Vorsprung) und P5 (Rallye-Timeout) sind mit M0-10
-- korrigiert. Beide haengen am Ruleset: `classic` spielt nach dem GDD,
-- `prototype` bildet weiter den Prototyp ab, damit die Referenz-Rallyes
-- reproduzierbar bleiben.
-- ============================================================================

local World = require("src.sim.world")

local Rules = {}

local function emit(events, event)
    events[#events + 1] = event
end

-- Eine gezaehlte Ballberuehrung. Der Cooldown verhindert, dass derselbe
-- Kontakt ueber mehrere Ticks mehrfach zaehlt.
function Rules.registerTouch(state, playerNum, blob, events)
    if blob.touchCooldown > 0 then return false end

    blob.touchCooldown = 0.20
    if state.rally.lastTouchPlayer == playerNum then
        state.rally.touchCount = state.rally.touchCount + 1
    else
        state.rally.lastTouchPlayer = playerNum
        state.rally.touchCount = 1
    end
    emit(events, { type = "blob_hit", player = playerNum })

    -- Dash-Save: wer in den letzten 0,5 s gedasht hat, bekommt beim Kontakt
    -- ein Wackeln. Nur einmal je Dash.
    if blob.dashGrace > 0 then
        blob.dashGrace = 0
        emit(events, { type = "dash_save", player = playerNum })
    end
    return true
end

-- Vierte Beruehrung in Folge: Fehler mit Verzoegerung, damit man ihn sieht.
function Rules.startFault(state, playerNum, events)
    state.rally.faultTimer = 0.75
    state.rally.faultPlayer = playerNum
    emit(events, { type = "fault", player = playerNum })
end

-- Ballwechsel neu aufsetzen. Der Aufschlaeger wechselt hier, nicht beim
-- Punkten -- Seitenaus (side-out) wie im Original.
function Rules.resetBall(state, ruleset, server, events)
    local groundY = ruleset.blobGroundY or 500

    state.match.servingPlayer = server
    state.match.phase = "serve"

    state.rally.faultTimer = 0
    state.rally.serveTimer = 0
    -- Feste Aufschlagverzoegerung (GDD P4). Der Prototyp wuerfelte hier
    -- 1,0 bis 1,5 s aus (B-06) -- das war die einzige simulationsrelevante
    -- Zufallsquelle und stand der Reinheit im Weg. Alle Referenzaufnahmen
    -- liefen bereits mit dieser Konstante.
    state.rally.serveDelay = 1.0

    state.ball.x = World.SERVE_X[server]
    state.ball.y = groundY - ruleset.serveHeight
    state.ball.vx = 0
    state.ball.vy = 0
    state.ball.rotation = 0

    state.rally.rallies = 0
    state.rally.timer = 0
    state.rally.lastTouchPlayer = 0
    state.rally.touchCount = 0
    state.rally.ballSide = server

    for i = 1, 2 do
        local blob = state.blobs[i]
        blob.tiltAngle = 0
        blob.touchCooldown = 0
        blob.dashGrace = 0
        blob.x = World.SERVE_X[i]
    end

    -- Sprungstelle fuer die Render-Interpolation: der Ball steht ohne
    -- Bewegung woanders (M0-05).
    emit(events, { type = "rally_reset", server = server })
end

-- Ist der Satz gewonnen? Getrennt, damit der Test die Regel direkt pruefen
-- kann (T-R-09 bis T-R-12).
function Rules.isSetWon(ruleset, mine, theirs)
    local target = ruleset.targetScore or 15
    if not ruleset.twoPointLead then
        -- Verhalten des Prototyps: 15 reichen, egal wie knapp (B-05).
        return mine >= target
    end
    -- 01_GDD §3.1: 15 Punkte UND zwei Punkte Vorsprung. Der Deckel beendet
    -- ein Endlos-Deuce, damit ein Bracket nicht an einem 28:26 kippt (E-09).
    if mine >= target and (mine - theirs) >= 2 then return true end
    local cap = ruleset.deuceCap or 0
    return cap > 0 and mine >= cap
end

-- Punkt oder Aufschlagwechsel. Nur der Aufschlaeger punktet.
function Rules.awardPointTo(state, ruleset, winningPlayer, events)
    if state.match.servingPlayer == winningPlayer then
        state.match.score[winningPlayer] = state.match.score[winningPlayer] + 1

        local other = winningPlayer == 1 and 2 or 1
        if Rules.isSetWon(ruleset, state.match.score[winningPlayer], state.match.score[other]) then
            state.match.phase = "gameover"
            emit(events, { type = "match_over", winner = winningPlayer })
            return
        end
        emit(events, { type = "point", to = winningPlayer })
    else
        emit(events, { type = "side_out", to = winningPlayer })
    end
    Rules.resetBall(state, ruleset, winningPlayer, events)
end

-- Seitenwechsel des Balls setzt die Beruehrungen zurueck.
function Rules.updateBallSide(state)
    local side = (state.ball.x < World.WIDTH / 2) and 1 or 2
    if state.rally.ballSide == side then return end

    state.rally.ballSide = side
    state.rally.touchCount = 0
    state.rally.lastTouchPlayer = 0
    state.blobs[1].touchCooldown = 0
    state.blobs[2].touchCooldown = 0
end

-- Endlos-Rallye: nach `rallyTimeout` Sekunden im Spiel bekommt der
-- Nicht-Aufschlaeger den Ballwechsel, also den Aufschlag (GDD P5). Verhindert,
-- dass zwei defensive Spieler den Zeitplan sprengen. 0 schaltet die Regel ab.
function Rules.checkRallyTimeout(state, ruleset, events)
    local limit = ruleset.rallyTimeout or 0
    if limit <= 0 or state.match.phase ~= "play" then return end
    if state.rally.timer < limit then return end

    local receiver = state.match.servingPlayer == 1 and 2 or 1
    emit(events, { type = "rally_timeout", to = receiver })
    Rules.awardPointTo(state, ruleset, receiver, events)
end

-- Ball im Sand: Punkt fuer die Gegenseite.
function Rules.checkGround(state, ruleset, events)
    local groundY = ruleset.ballGroundY or 520
    if state.match.phase ~= "play" then return end
    if state.rally.faultTimer > 0 then return end
    if state.ball.y + state.ball.radius < groundY then return end

    emit(events, { type = "ground_hit", x = state.ball.x, y = groundY })
    if state.ball.x < World.WIDTH / 2 then
        Rules.awardPointTo(state, ruleset, 2, events)
    else
        Rules.awardPointTo(state, ruleset, 1, events)
    end
end

return Rules
