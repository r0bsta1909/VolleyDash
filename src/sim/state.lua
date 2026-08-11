-- ============================================================================
-- src/sim/state.lua -- der gesamte Spielzustand als reine Daten (M0-08)
--
-- Serialisierbar, ohne Funktionen, ohne Verweise nach draussen. Genau das,
-- was `04_NETCODE_SPEC` als Snapshot ueber die Leitung schickt und was der
-- Testrunner aus einer Aufzeichnung wiederherstellt.
--
-- Aufteilung nach `03_TECH` §2:
--   match  -- ueberlebt den Ballwechsel: Punkte, Aufschlaeger, Phase
--   rally  -- gilt nur fuer den laufenden Ballwechsel: Beruehrungen, Timer
--   ball, blobs, net -- Koerper
--
-- love-frei.
-- ============================================================================

local World = require("src.sim.world")

local State = {}

local function newBlob(x, groundY)
    return {
        x = x, y = groundY,
        vx = 0, vy = 0,
        isGrounded = true,
        cooldownTimer = 0,   -- Dash-Cooldown
        dashTimer = 0,       -- laufender Seitwaerts-Dash
        dashSpeed = 0,
        tiltAngle = 0,
        touchCooldown = 0,   -- Sperre gegen Mehrfachzaehlung derselben Beruehrung
        dashGrace = 0,       -- Fenster fuer den Dash-Save
    }
end

function State.new(ruleset)
    local groundY = ruleset.blobGroundY or 500

    return {
        ball = {
            x = World.SERVE_X[1],
            y = groundY - ruleset.serveHeight,
            vx = 0, vy = 0,
            rotation = 0,
            radius = ruleset.ballRadius,
        },

        blobs = {
            newBlob(World.SERVE_X[1], groundY),
            newBlob(World.SERVE_X[2], groundY),
        },

        net = {
            x = World.NET_X,
            y = groundY - ruleset.netHeight,
            w = World.NET_WIDTH,
            h = ruleset.netHeight,
        },

        match = {
            score = { 0, 0 },
            servingPlayer = 1,
            phase = "menu",          -- menu | serve | play | gameover
            previousPhase = "serve", -- fuer die Rueckkehr aus dem Menue
            inProgress = false,
        },

        rally = {
            touchCount = 0,
            lastTouchPlayer = 0,
            ballSide = 1,
            rallies = 0,
            timer = 0,          -- Spielzeit dieses Ballwechsels, fuer P5
            serveTimer = 0,
            serveDelay = 1.0,
            faultTimer = 0,
            faultPlayer = 0,
        },

        -- Die Simulation merkt sich die Eingaben des vorigen Ticks selbst.
        -- Nur so kann sie Flanken ableiten, ohne dass der Aufrufer mitzaehlt
        -- (ADR-014: Sprung ist eine Flanke, Dash ein Impuls).
        input = { prev = { 0, 0 } },
    }
end

-- Der Boden haengt am Ruleset, nicht an der Welt: der Live-Tweaker darf ihn
-- verschieben. Eine Funktion statt eines Feldes, damit es keine zweite
-- Wahrheit gibt.
function State.groundY(ruleset)
    return ruleset.blobGroundY or 500
end

function State.ballGroundY(ruleset)
    return ruleset.ballGroundY or 520
end

return State
