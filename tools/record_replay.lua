-- ============================================================================
-- TEMPORARY RECORDING TOOL (M0-03) -- remove together with the recording shim
-- in main.lua after the reference replays are captured (M0-05).
--
-- Records reference rallies of the UNCHANGED prototype so the refactoring can
-- be verified against them (07_TEST_PLAN section 2, risk R-04).
--
-- This tool writes with plain io.open, not love.filesystem, because the
-- replays belong into the repository (tests/replays/) and love.filesystem
-- would put them into the save directory. Consequence: the game has to be
-- started from the repository root.
-- ============================================================================

local Recorder = {}

Recorder.FORMAT_VERSION = 1

-- Reference rallies from 07_TEST_PLAN section 2.
local RALLIES = {
    { id = "R-01", desc = "Aufschlag P1, direkter Punkt" },
    { id = "R-02", desc = "Lange Rallye >= 15 Ballwechsel" },
    { id = "R-03", desc = "Wandabpraller links und rechts" },
    { id = "R-04", desc = "Ball auf Netzoberkante" },
    { id = "R-05", desc = "Ball an Netzseite" },
    { id = "R-06", desc = "Blob-Ball-Kontakt aktiv (bewegter Blob)" },
    { id = "R-07", desc = "Blob-Ball-Kontakt passiv (stehender Blob)" },
    { id = "R-08", desc = "Smash aus dem Sprung" },
    { id = "R-09", desc = "Dash mit Rettung" },
    { id = "R-10", desc = "Drei Beruehrungen bis zum Fehler" },
    { id = "R-11", desc = "Ballgeschwindigkeit am Maximum" },
    { id = "R-12", desc = "Deuce-Situation 14:14 -> 16:14",
      blocked = "Prototyp beendet den Satz bei 15 (B-05), kein Referenzverhalten" },
    { id = "R-00", desc = "Selbsttest des Aufzeichnungswerkzeugs, kein Referenzwert" },
}

local REPLAY_DIR = "tests/replays"
local WINDOW_STAMP = REPLAY_DIR .. "/.last_window"

local S = {
    ready       = false,
    mode        = "variable",
    step        = 1 / 60,
    refs        = nil,
    index       = 1,
    recording   = false,
    frames      = {},
    tick        = 0,
    prev        = nil,   -- state snapshot taken after the previous step,
                         -- i.e. before this frame's key events
    message     = nil,
    messageTime = 0,
    windowWarn  = nil,
    header      = {},
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Every float goes to disk as a "%.17g" string. A tolerance of 0.5 px is
-- meaningless if the reference loses decimals while being serialised.
local function num(v)
    return '"' .. string.format("%.17g", v) .. '"'
end

local function esc(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return '"' .. s .. '"'
end

local function fileExists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function writeFile(path, text)
    local f, err = io.open(path, "wb")
    if not f then return false, err end
    f:write(text)
    f:close()
    return true
end

local function replayPath(id, mode)
    return REPLAY_DIR .. "/" .. mode .. "/" .. id .. ".json"
end

local function rallyByIndex(i)
    return RALLIES[i]
end

local function setMessage(text)
    S.message = text
    S.messageTime = 4.0
end

-- Short commit hash without shelling out: read .git/HEAD and follow the ref.
local function gitHead()
    local head = io.open(".git/HEAD", "r")
    if not head then return "unknown" end
    local line = head:read("*l") or ""
    head:close()
    local ref = line:match("^ref:%s*(.+)$")
    if not ref then return line:sub(1, 7) end
    local f = io.open(".git/" .. ref, "r")
    if not f then
        -- packed refs are good enough to skip; the report names the tag instead
        return "unknown"
    end
    local hash = f:read("*l") or ""
    f:close()
    return hash:sub(1, 7)
end

local function loveVersion()
    local major, minor, revision = love.getVersion()
    return major .. "." .. minor .. "." .. revision
end

local function platform()
    local os_ = (love.system and love.system.getOS() or "unknown"):lower()
    local arch = (jit and jit.arch) or "unknown"
    return os_ .. "-" .. arch
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

function Recorder.setup(opts)
    S.mode  = opts.mode or "variable"
    S.step  = opts.step or (1 / 60)
    S.header.patches = opts.patches or {}
    S.ready = false
end

-- p1, p2, ball, net, WORLD, gameState, config and defaults are locals of
-- main.lua; they are handed over once after love.load and never reassigned.
function Recorder.attach(refs)
    S.refs  = refs
    S.ready = true

    local w, h = love.graphics.getDimensions()
    local stamp = io.open(WINDOW_STAMP, "r")
    if stamp then
        local line = stamp:read("*l") or ""
        stamp:close()
        local lw, lh = line:match("^(%d+)%s+(%d+)$")
        if lw and (tonumber(lw) ~= w or tonumber(lh) ~= h) then
            -- Trap 6 from the handoff: as long as B-01 is open, the window size
            -- is a hidden input parameter of every recording.
            S.windowWarn = string.format("Fenster %dx%d, letzte Aufnahme %sx%s", w, h, lw, lh)
        end
    end
end

function Recorder.isRecording()
    return S.recording
end

function Recorder.tickCount()
    return S.tick
end

function Recorder.currentId()
    return rallyByIndex(S.index).id
end

function Recorder.selectById(id)
    for i, rally in ipairs(RALLIES) do
        if rally.id == id then
            S.index = i
            return true
        end
    end
    return false
end

-- "human", "replay:variable/R-04.json" or "scripted:R-11". Goes into the file
-- header so nobody has to guess how a reference came to be.
function Recorder.setDriver(name)
    S.header.driver = name
end

-- ---------------------------------------------------------------------------
-- Input capture
-- ---------------------------------------------------------------------------

-- Die InputFrames baut main.lua (src/input/*). Der Recorder schreibt sie nur
-- noch mit -- seit M0-06 gibt es hier keine Tastaturabfrage mehr.

-- ---------------------------------------------------------------------------
-- State snapshot
-- ---------------------------------------------------------------------------

local function snapshot()
    local r = S.refs
    return {
        ball  = { r.ball.x, r.ball.y, r.ball.vx, r.ball.vy },
        p1    = { r.p1.x, r.p1.y, r.p1.vx, r.p1.vy },
        p2    = { r.p2.x, r.p2.y, r.p2.vx, r.p2.vy },
        touch = { r.gameState.lastTouchPlayer, r.gameState.touchCount },
        score = { r.gameState.scoreP1, r.gameState.scoreP2 },
        server = r.gameState.servingPlayer,
        phase  = r.gameState.state,
    }
end

-- ---------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------

function Recorder.start()
    local rally = rallyByIndex(S.index)
    if rally.blocked then
        setMessage(rally.id .. " ist nicht aufzeichenbar: " .. rally.blocked)
        return false
    end
    S.frames    = {}
    S.tick      = 0
    S.recording = true
    S.prev      = snapshot()

    local w, h = love.graphics.getDimensions()
    S.header.window = { w, h }
    S.header.world  = { S.refs.world.width, S.refs.world.height }
    S.header.startedAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
    setMessage("REC gestartet: " .. rally.id)
    return true
end

function Recorder.discard()
    S.frames    = {}
    S.tick      = 0
    S.recording = false
    setMessage("Aufzeichnung verworfen")
end

function Recorder.nextRally()
    if S.recording then
        setMessage("Erst F9 (Stopp), dann die ID wechseln")
        return
    end
    S.index = (S.index % #RALLIES) + 1
    setMessage("Rallye: " .. rallyByIndex(S.index).id .. " -- " .. rallyByIndex(S.index).desc)
end

-- One simulation step has just run. `dt` is the step the prototype used.
function Recorder.step(dt)
    if not (S.ready and S.recording) then return end

    local phase = S.refs.gameState.state
    if phase ~= "play" and phase ~= "serve" then
        -- menu or gameover: the update returned early, nothing moved
        return
    end

    local p1Frame, p2Frame = S.refs.inputs[1], S.refs.inputs[2]

    local st = S.prev
    S.frames[#S.frames + 1] = string.format(
        '    { "t": %d, "dt": %s, "in": [%d, %d],\n' ..
        '      "ball": [%s, %s, %s, %s],\n' ..
        '      "p1": [%s, %s, %s, %s],\n' ..
        '      "p2": [%s, %s, %s, %s],\n' ..
        '      "touch": [%d, %d], "score": [%d, %d], "server": %d, "phase": %s }',
        S.tick, num(dt), p1Frame, p2Frame,
        num(st.ball[1]), num(st.ball[2]), num(st.ball[3]), num(st.ball[4]),
        num(st.p1[1]), num(st.p1[2]), num(st.p1[3]), num(st.p1[4]),
        num(st.p2[1]), num(st.p2[2]), num(st.p2[3]), num(st.p2[4]),
        st.touch[1], st.touch[2], st.score[1], st.score[2], st.server, esc(st.phase))

    S.tick = S.tick + 1
    S.prev = snapshot()
end

-- ---------------------------------------------------------------------------
-- Serialisation
-- ---------------------------------------------------------------------------

local function rulesetSnapshot(defaults)
    local keys = {}
    for k in pairs(defaults) do keys[#keys + 1] = k end
    table.sort(keys)

    local parts = {}
    for _, k in ipairs(keys) do
        local v = defaults[k]
        local out
        if type(v) == "number" then
            out = num(v)
        elseif type(v) == "boolean" then
            out = tostring(v)
        else
            out = esc(v)
        end
        parts[#parts + 1] = '    ' .. esc(k) .. ': ' .. out
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n  }"
end

local function patchList()
    local parts = {}
    for _, p in ipairs(S.header.patches) do parts[#parts + 1] = esc(p) end
    return "[" .. table.concat(parts, ", ") .. "]"
end

function Recorder.save()
    local rally = rallyByIndex(S.index)
    local path = replayPath(rally.id, S.mode)

    local p2source
    if S.refs.config.botActive then
        p2source = "bot:" .. tostring(S.refs.config.botLevel)
    else
        p2source = "local_keyboard"
    end

    local head = {}
    head[#head + 1] = '{'
    head[#head + 1] = '  "format_version": ' .. Recorder.FORMAT_VERSION .. ','
    head[#head + 1] = '  "rally_id": ' .. esc(rally.id) .. ','
    head[#head + 1] = '  "description": ' .. esc(rally.desc) .. ','
    head[#head + 1] = '  "mode": ' .. esc(S.mode) .. ','
    head[#head + 1] = '  "recorded_at": ' .. esc(S.header.startedAt) .. ','
    head[#head + 1] = '  "prototype_commit": ' .. esc(gitHead()) .. ','
    head[#head + 1] = '  "love_version": ' .. esc(loveVersion()) .. ','
    head[#head + 1] = '  "platform": ' .. esc(platform()) .. ','
    head[#head + 1] = '  "patches_active": ' .. patchList() .. ','
    head[#head + 1] = '  "p2_source": ' .. esc(p2source) .. ','
    head[#head + 1] = '  "driver": ' .. esc(S.header.driver or "human") .. ','
    -- Trap 6: as long as B-01 is open the window size is part of the input.
    head[#head + 1] = string.format('  "window": [%d, %d],', S.header.window[1], S.header.window[2])
    head[#head + 1] = '  "world": [' .. num(S.header.world[1]) .. ', ' .. num(S.header.world[2]) .. '],'
    -- Each frame holds the state BEFORE its own step together with the input
    -- applied during that step. Replay: load frame[i] state, apply frame[i].in,
    -- step once, compare against frame[i+1] state.
    head[#head + 1] = '  "state_convention": "pre_step",'
    head[#head + 1] = '  "input_format": "13_INPUTFRAME_FORMAT.md v1 (left=1 right=2 jump=4 smash=8 dash=16)",'
    head[#head + 1] = '  "ruleset_snapshot": ' .. rulesetSnapshot(S.refs.defaults) .. ','
    head[#head + 1] = '  "tick_count": ' .. S.tick .. ','
    head[#head + 1] = '  "frames": ['

    local text = table.concat(head, "\n") .. "\n" ..
                 table.concat(S.frames, ",\n") .. "\n  ]\n}\n"

    local ok, err = writeFile(path, text)
    if not ok then
        setMessage("SCHREIBFEHLER: " .. tostring(err))
        return false
    end

    writeFile(WINDOW_STAMP, S.header.window[1] .. " " .. S.header.window[2] .. "\n")
    Recorder.writeManifest()
    setMessage(string.format("%s gespeichert (%d Ticks) -> %s", rally.id, S.tick, path))
    return true
end

function Recorder.stop()
    if not S.recording then return end
    S.recording = false
    if S.tick == 0 then
        setMessage("Nichts aufgezeichnet (0 Ticks)")
        return
    end
    Recorder.save()
end

-- How a file came to be. Read straight out of the header, so the manifest
-- cannot drift away from the files.
local function driverOf(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local head = f:read(2048) or ""
    f:close()
    return head:match('"driver": "([^"]*)"') or "human"
end

-- The manifest is rebuilt from what is actually on disk, so the tool never
-- has to read JSON back.
function Recorder.writeManifest()
    local parts = {}
    for _, rally in ipairs(RALLIES) do
        if rally.id ~= "R-00" then
            local variable = fileExists(replayPath(rally.id, "variable")) and "recorded" or "missing"
            local fixed60  = fileExists(replayPath(rally.id, "fixed60")) and "recorded" or "missing"
            if rally.blocked then
                if variable == "missing" then variable = "blocked" end
                if fixed60  == "missing" then fixed60  = "blocked" end
            end
            local drivers = ""
            local dv, df = driverOf(replayPath(rally.id, "variable")),
                           driverOf(replayPath(rally.id, "fixed60"))
            if dv then drivers = drivers .. ', "variable_driver": ' .. esc(dv) end
            if df then drivers = drivers .. ', "fixed60_driver": ' .. esc(df) end
            parts[#parts + 1] = string.format(
                '    { "rally_id": %s, "description": %s, "variable": %s, "fixed60": %s%s%s }',
                esc(rally.id), esc(rally.desc), esc(variable), esc(fixed60), drivers,
                rally.blocked and (', "blocked_reason": ' .. esc(rally.blocked)) or "")
        end
    end

    local text = '{\n  "format_version": ' .. Recorder.FORMAT_VERSION .. ',\n' ..
                 '  "updated_at": ' .. esc(os.date("!%Y-%m-%dT%H:%M:%SZ")) .. ',\n' ..
                 '  "rallies": [\n' .. table.concat(parts, ",\n") .. '\n  ]\n}\n'
    writeFile(REPLAY_DIR .. "/manifest.json", text)
end

-- ---------------------------------------------------------------------------
-- Keys and overlay
-- ---------------------------------------------------------------------------

function Recorder.keypressed(key)
    if key == "f9" then
        if S.recording then Recorder.stop() else Recorder.start() end
        return true
    elseif key == "f10" then
        Recorder.nextRally()
        return true
    elseif key == "f11" then
        -- F11 is the fullscreen toggle in the prototype. While recording, the
        -- window size must not change (trap 6), so the recorder claims the key.
        Recorder.discard()
        return true
    end
    -- The live tweaker would silently invalidate ruleset_snapshot.
    if S.recording and (key == "tab" or key == "f1") then
        setMessage("Tweaker waehrend der Aufzeichnung gesperrt")
        return true
    end
    return false
end

function Recorder.update(dt)
    if S.messageTime > 0 then
        S.messageTime = S.messageTime - dt
        if S.messageTime <= 0 then S.message = nil end
    end
end

local overlayFont

function Recorder.draw()
    if not S.ready then return end
    overlayFont = overlayFont or love.graphics.newFont(13)

    local rally = rallyByIndex(S.index)
    local sw = love.graphics.getWidth()
    local x, y, w = sw - 330, 8, 322

    local exists = fileExists(replayPath(rally.id, S.mode))
    local lines = {
        rally.id .. "  " .. (S.recording and "REC" or "bereit"),
        "Modus: " .. S.mode,
        "Ticks: " .. S.tick,
        exists and "Datei vorhanden -> wird ueberschrieben" or "noch keine Datei",
        "F9 Start/Stopp  F10 ID  F11 verwerfen",
    }
    if rally.blocked then lines[#lines + 1] = "NICHT AUFZEICHENBAR (B-05)" end
    if S.windowWarn then lines[#lines + 1] = "WARNUNG: " .. S.windowWarn end
    if S.message then lines[#lines + 1] = S.message end

    love.graphics.push()
    love.graphics.origin()
    love.graphics.setFont(overlayFont)
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", x, y, w, 16 * #lines + 12, 4, 4)

    if S.recording then
        love.graphics.setColor(0.95, 0.15, 0.15, 1)
        love.graphics.circle("fill", x + w - 14, y + 12, 5)
    end

    for i, line in ipairs(lines) do
        if i == 1 then
            love.graphics.setColor(S.recording and 0.95 or 0.85, S.recording and 0.3 or 0.85, 0.2, 1)
        elseif line:find("WARNUNG") or line:find("NICHT") or line:find("FEHLER") then
            love.graphics.setColor(1, 0.5, 0.2, 1)
        else
            love.graphics.setColor(0.85, 0.85, 0.9, 1)
        end
        love.graphics.print(line, x + 8, y + 6 + (i - 1) * 16)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
end

return Recorder
