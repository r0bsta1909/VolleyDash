-- ============================================================================
-- TEMPORARY REPLAY SOURCE (M0-03) -- remove together with the recording shim
-- in main.lua (M0-05).
--
-- Reads a recording written by tools/record_replay.lua and hands out the
-- InputFrame of each tick. Together with the glue in main.lua this is the
-- "replay" input source of ADR-014: the simulation is fed from a file instead
-- of from the keyboard, without touching a single line of physics.
--
-- Purpose: produce the fixed60 reference pass from the rallies that were
-- played by hand with the prototype's variable step, instead of playing all
-- eleven a second time.
--
-- This is NOT a JSON parser. It reads exactly the layout that
-- tools/record_replay.lua produces. The real reader is the headless test
-- runner in M0-13.
-- ============================================================================

local Replay = {}

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil, "nicht gefunden: " .. path end
    local text = f:read("*a")
    f:close()
    return text
end

local function numbers4(body, key)
    local a, b, c, d = body:match('"' .. key .. '": %["([^"]*)", "([^"]*)", "([^"]*)", "([^"]*)"%]')
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
end

local function ints2(body, key)
    local a, b = body:match('"' .. key .. '": %[(%-?%d+), (%-?%d+)%]')
    if not a then return nil end
    return { tonumber(a), tonumber(b) }
end

-- Returns { count, inputs = { {p1, p2}, ... }, init = { ... } } or nil, err.
function Replay.load(path)
    local text, err = readAll(path)
    if not text then return nil, err end

    -- Everything before "frames" is the header; it also contains quoted
    -- numbers (ruleset_snapshot, world), so cut it off first.
    local body = text:match('"frames": %[(.*)$')
    if not body then return nil, "kein frames-Block in " .. path end

    local inputs = {}
    for a, b in body:gmatch('"in": %[(%-?%d+), (%-?%d+)%]') do
        inputs[#inputs + 1] = { tonumber(a), tonumber(b) }
    end
    if #inputs == 0 then return nil, "keine InputFrames in " .. path end

    -- The first occurrence of each key inside the frames block is frame 0.
    local init = {
        ball   = numbers4(body, "ball"),
        p1     = numbers4(body, "p1"),
        p2     = numbers4(body, "p2"),
        touch  = ints2(body, "touch"),
        score  = ints2(body, "score"),
        server = tonumber(body:match('"server": (%d+)')),
        phase  = body:match('"phase": "([^"]*)"'),
    }
    if not (init.ball and init.p1 and init.p2 and init.touch and init.score
            and init.server and init.phase) then
        return nil, "Frame 0 unvollstaendig in " .. path
    end

    return { count = #inputs, inputs = inputs, init = init, path = path }
end

-- InputFrame bits, canonical per 13_INPUTFRAME_FORMAT.md / ADR-014.
Replay.LEFT, Replay.RIGHT, Replay.JUMP, Replay.SMASH, Replay.DASH = 1, 2, 4, 8, 16

function Replay.has(bits, mask)
    return math.floor(bits / mask) % 2 == 1
end

-- Bot inputs table as Bot.updateAI would return it.
function Replay.botInputs(bits)
    local left, right = Replay.has(bits, Replay.LEFT), Replay.has(bits, Replay.RIGHT)
    local dashDir = nil
    if Replay.has(bits, Replay.DASH) then
        -- Direction comes from the direction bits (13_INPUTFRAME_FORMAT section 4).
        dashDir = right and "k" or "h"
    end
    return {
        left = left, right = right,
        jump = Replay.has(bits, Replay.JUMP),
        smash = Replay.has(bits, Replay.SMASH),
        dashDir = dashDir,
    }
end

-- ---------------------------------------------------------------------------
-- Scripted scenes -- only for rallies the playback cannot satisfy.
--
-- A scene sets a synthetic start state and drives fixed inputs. That is still
-- a genuine run of the prototype's physics; only the initial condition is
-- placed instead of played. Files recorded this way carry
-- "driver": "scripted:<id>" in the header.
-- ---------------------------------------------------------------------------

Replay.SCENES = {
    -- Serve by P1 that wins the point. The replayed rally loses the serve
    -- instead: the drift between the two timesteps is enough for the return to
    -- land on P1's own side. Here P2 stays idle, so a serve that clears the net
    -- always ends as a point for the serving player.
    ["R-01"] = {
        ticks = 400,
        startX = 140,   -- gemessen mit --scene-probe=R-01, genau ein Kontakt
        makeInit = function(scene)
            return {
                ball  = { 200, 360, 0, 0 },
                p1    = { scene.startX, 500, 0, 0 },
                p2    = { 600, 500, 0, 0 },
                touch = { 0, 0 }, score = { 0, 0 }, server = 1, phase = "serve",
            }
        end,
        -- jump into the hovering ball while drifting right
        inputs = function(scene, tick) return Replay.JUMP + Replay.RIGHT, 0 end,
        sweep = { field = "startX", from = 110, to = 200, step = 2 },
    },

    -- Active transfer: the ball drops onto a blob running at full moveSpeed.
    -- The replayed rally misses this because one tick of drift is enough for
    -- the blob to be clamped against the net divider (vx = 0) at contact.
    ["R-06"] = {
        ticks = 150,
        startX = 102,   -- gemessen mit --scene-probe=R-06
        makeInit = function(scene)
            return {
                ball  = { 300, 346, 0, 0 },
                p1    = { scene.startX, 500, 0, 0 },
                p2    = { 600, 500, 0, 0 },
                touch = { 0, 0 }, score = { 0, 0 }, server = 1, phase = "play",
            }
        end,
        inputs = function(scene, tick) return Replay.RIGHT, 0 end,
        sweep = { field = "startX", from = 54, to = 320, step = 4 },
    },

    -- Spike out of a jump: the blob has to be airborne and hold smash at the
    -- moment of contact.
    --
    -- The ball is offset horizontally on purpose. Hit exactly from below, the
    -- spike drives the ball straight back into the blob, the minOutward
    -- correction cancels it and the result is the bare minimum of 200 px/s.
    -- That is prototype behaviour, but it is not what R-08 is supposed to
    -- protect.
    ["R-08"] = {
        ticks = 150,
        offsetX = 40,   -- gemessen mit --scene-probe=R-08
        makeInit = function(scene)
            return {
                ball  = { 200 + scene.offsetX, 100, 0, 300 },
                p1    = { 200, 500, 0, 0 },
                p2    = { 600, 500, 0, 0 },
                touch = { 0, 0 }, score = { 0, 0 }, server = 1, phase = "play",
            }
        end,
        -- jump and smash held from tick 0; the rising edge on tick 0 is what
        -- triggers the jump, exactly as a key press would
        inputs = function(scene, tick) return Replay.SMASH + Replay.JUMP, 0 end,
        sweep = { field = "offsetX", from = 0, to = 90, step = 5 },
    },

    -- R-11 needs the maxBallSpeed cap to actually engage. A passive bounce can
    -- never reach it (outgoing = 0.75 * incoming), so a fast falling ball meets
    -- a rising, smashing blob slightly to its side: active transfer plus the
    -- spike factor 1.4 push the result past 1400 and the cap clamps it.
    ["R-11"] = {
        ticks = 150,
        offsetX = 50,   -- gemessen mit --scene-probe=R-11
        makeInit = function(scene)
            return {
                ball  = { 200 + scene.offsetX, 60, 0, 900 },
                p1    = { 200, 500, 0, 0 },
                p2    = { 600, 500, 0, 0 },
                touch = { 0, 0 }, score = { 0, 0 }, server = 1, phase = "play",
            }
        end,
        -- jump and smash held from tick 0; the rising edge on tick 0 is what
        -- triggers the jump, exactly as a key press would
        inputs = function(scene, tick) return Replay.SMASH + Replay.JUMP, 0 end,
        sweep = { field = "offsetX", from = 0, to = 90, step = 5 },
    },
}

function Replay.scene(id)
    return Replay.SCENES[id]
end

return Replay
