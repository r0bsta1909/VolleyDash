-- ============================================================================
-- tests/replay_file.lua -- Leser fuer die Referenzaufzeichnungen (M0-13)
--
-- Liest das Format, das tools/record_replay.lua schreibt. Kein allgemeiner
-- JSON-Parser: der Aufbau ist bekannt und fest, und ein Parser waere mehr
-- Code als die Sache wert.
--
-- Reines Lua mit io.open -- kein love. Genau deshalb kann die Ebene A des
-- Testplans ohne Fenster laufen.
-- ============================================================================

local ReplayFile = {}

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil, "nicht gefunden: " .. path end
    local text = f:read("*a")
    f:close()
    return text
end

local function numbers(chunk, key, count)
    local pattern = '"' .. key .. '": %['
    for _ = 1, count do pattern = pattern .. '"([^"]*)", ' end
    pattern = pattern:sub(1, -3) .. "%]"

    local a, b, c, d = chunk:match(pattern)
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
end

local function ints(chunk, key)
    local a, b = chunk:match('"' .. key .. '": %[(%-?%d+), (%-?%d+)%]')
    if not a then return nil end
    return { tonumber(a), tonumber(b) }
end

-- Gibt { ruleset = {...}, frames = { ... } } zurueck oder nil, Fehlertext.
function ReplayFile.read(path)
    local text, err = readAll(path)
    if not text then return nil, err end

    local head = text:match("^(.-)\n  \"frames\"")
    local body = text:match('"frames": %[(.*)$')
    if not (head and body) then return nil, "unerwarteter Aufbau: " .. path end

    -- Ruleset aus dem Kopf. Zahlen stehen als Strings, Wahrheitswerte nackt.
    local ruleset = {}
    local block = head:match('"ruleset_snapshot": {(.-)\n  }') or ""
    for key, value in block:gmatch('"([%w_]+)": "([^"]*)"') do
        ruleset[key] = tonumber(value)
    end
    for key, value in block:gmatch('"([%w_]+)": (%a+)') do
        if value == "true" then ruleset[key] = true
        elseif value == "false" then ruleset[key] = false end
    end

    local frames = {}
    for chunk in body:gmatch('{ "t":.-"phase": "[^"]*" }') do
        local a, b = chunk:match('"in": %[(%-?%d+), (%-?%d+)%]')
        frames[#frames + 1] = {
            t      = tonumber(chunk:match('"t": (%-?%d+)')),
            dt     = tonumber(chunk:match('"dt": "([^"]*)"')),
            inputs = { tonumber(a), tonumber(b) },
            ball   = numbers(chunk, "ball", 4),
            p1     = numbers(chunk, "p1", 4),
            p2     = numbers(chunk, "p2", 4),
            touch  = ints(chunk, "touch"),
            score  = ints(chunk, "score"),
            server = tonumber(chunk:match('"server": (%d+)')),
            phase  = chunk:match('"phase": "([^"]*)"'),
        }
    end

    if #frames == 0 then return nil, "keine Frames in " .. path end
    return { path = path, ruleset = ruleset, frames = frames,
             driver = text:match('"driver": "([^"]*)"') }
end

-- Zustand aus einem Frame herstellen. Verdeckter Zustand (Timer, Bodenkontakt)
-- steht nicht in der Datei; er ist am Anfang einer Aufzeichnung im Reset,
-- deshalb wird er hier gesetzt.
function ReplayFile.applyFrame(state, frame, ruleset)
    local groundY = ruleset.blobGroundY or 500
    local ball, blobs = state.ball, state.blobs

    ball.x, ball.y, ball.vx, ball.vy = frame.ball[1], frame.ball[2], frame.ball[3], frame.ball[4]
    ball.rotation, ball.radius = 0, ruleset.ballRadius

    for i, key in ipairs({ "p1", "p2" }) do
        local blob = blobs[i]
        blob.x, blob.y, blob.vx, blob.vy =
            frame[key][1], frame[key][2], frame[key][3], frame[key][4]
        blob.isGrounded = blob.y >= groundY
        blob.cooldownTimer, blob.dashTimer, blob.dashSpeed = 0, 0, 0
        blob.tiltAngle, blob.touchCooldown, blob.dashGrace = 0, 0, 0
    end

    state.rally.lastTouchPlayer, state.rally.touchCount = frame.touch[1], frame.touch[2]
    state.match.score[1], state.match.score[2] = frame.score[1], frame.score[2]
    state.match.servingPlayer, state.match.phase = frame.server, frame.phase
    state.rally.serveTimer, state.rally.serveDelay = 0, 1.0
    state.rally.faultTimer, state.rally.faultPlayer = 0, 0
    state.rally.timer, state.rally.rallies = 0, 0
    state.rally.ballSide = (ball.x < 400) and 1 or 2
    state.input.prev[1], state.input.prev[2] = 0, 0
    state.match.inProgress = true
end

return ReplayFile
