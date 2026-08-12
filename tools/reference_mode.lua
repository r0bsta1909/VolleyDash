-- ============================================================================
-- tools/reference_mode.lua -- Aufzeichnung, Wiedergabe, Szenen (M0-03, M0-12)
--
-- Temporaeres Werkzeug. Es geht mit M0-13 im Headless-Testrunner auf; bis
-- dahin haengt es sich von aussen an das laufende Spiel, ohne dass Simulation,
-- Szenen oder Oberflaeche etwas davon wissen.
--
-- Ohne Flag ist das Modul vollstaendig inert: `parse` setzt dann nichts, und
-- `install` kehrt sofort zurueck.
--
--   --record            Aufzeichnung mit Overlay und F9/F10/F11
--   --record-selftest   Selbsttest, dann beenden
--   --replay-all        alle Rallyes wiedergeben und als fixed60 schreiben
--   --replay=R-04       nur diese eine
--   --scene=R-11        stattdessen die Skriptszene fahren
--   --scene-probe=R-11  Parameterlauf, druckt nur
--   --write-manifest    Manifest neu schreiben und beenden
--   --screenshot[=seite] ein Bild in den Save-Ordner, dann beenden
--   --test              Testsuiten laufen lassen und beenden
--   --test-no-love      dasselbe ohne die Bibliothek im Namensraum
--   --resize=datei:BxH  Bild verkleinern und beenden (tools/resize_image.lua)
-- ============================================================================

local World   = require("src.sim.world")
local Ruleset = require("src.sim.ruleset")
local Frame   = require("src.input.frame")

local M = {}

local flags = {}
local Recorder, Replay

function M.parse(args)
    for _, a in ipairs(args or {}) do
        if a == "--record" then flags.record = true end
        if a == "--record-selftest" then flags.selftest = true end
        if a == "--write-manifest" then flags.manifest = true end
        if a == "--test" then flags.test = true end
        if a == "--test-no-love" then flags.test, flags.testNoLove = true, true end
        if a == "--screenshot" then flags.shot = 0 end
        if a == "--replay-all" then
            flags.queue = { "R-01", "R-02", "R-03", "R-04", "R-05", "R-06",
                            "R-07", "R-08", "R-09", "R-10", "R-11" }
        end
        local one = a:match("^%-%-replay=(.+)$")
        if one then flags.queue = { one } end
        local scene = a:match("^%-%-scene=(.+)$")
        if scene then flags.queue = { scene }; flags.sceneId = scene end
        local probe = a:match("^%-%-scene%-probe=(.+)$")
        if probe then flags.probeId = probe end
        local page = a:match("^%-%-screenshot=(.+)$")
        if page then flags.shot, flags.shotPage = 0, page end
        local resize = a:match("^%-%-resize=(.+)$")
        if resize then flags.resize = resize end
    end

    -- Alles, was Referenzdaten erzeugt, laeuft im festen 800x600-Fenster und
    -- mit festem Zufallssaat. --screenshot ausdruecklich nicht, sonst gaebe
    -- es nichts zu sehen.
    flags.refMode = flags.record or flags.selftest or flags.manifest
                    or flags.queue ~= nil or flags.probeId ~= nil
    flags.active = flags.refMode or flags.shot ~= nil
    return flags
end

function M.flags() return flags end
function M.refMode() return flags.refMode == true end
function M.active() return flags.active == true end

-- Testlauf ohne Fenster und ohne Spiel. Gibt true zurueck, wenn main.lua
-- danach nichts mehr tun soll.
function M.runTests()
    if not flags.test then return false end
    local Runner = require("tests.run_headless")

    -- --test-no-love beweist die Reinheit: der Lauf sieht die Bibliothek
    -- nicht und scheitert, sobald ein Modul sie doch anfasst.
    local runner = flags.testNoLove and Runner.runWithoutLove or Runner.run
    local _, failed = runner()
    love.event.quit(failed > 0 and 1 or 0)
    return true
end

-- Alles, was statt des Spiels laeuft und danach beendet. Gibt true zurueck,
-- wenn main.lua nichts mehr zu tun hat.
function M.runTools()
    if M.runTests() then return true end

    if flags.resize then
        local ok = require("tools.resize_image").run(flags.resize)
        love.event.quit(ok and 0 or 1)
        return true
    end

    return false
end

-- ---------------------------------------------------------------------------

function M.install(App)
    if not flags.active then return end

    Recorder = require("tools.record_replay")
    Recorder.setup({
        mode = "fixed60",
        step = World.TICK_DT,
        -- serveDelay stand hier bis M0-07 als Patch. Seit M0-08 ist die feste
        -- Aufschlagverzoegerung Regel (B-06, GDD P4) und kein Eingriff mehr.
        patches = { "randomseed=1", "window=800x600 fixed" },
    })

    local game = App.game
    Recorder.attach({
        world = { width = World.WIDTH, height = World.HEIGHT },
        state = game.state, ruleset = App.ruleset,
        prefs = App.prefs, inputs = game.inputs,
    })

    -- Ein aufgezeichneter Frame je Simulationstick, direkt aus der Schleife
    -- des Spiels.
    game.onTick = function() Recorder.step(World.TICK_DT) end

    if flags.refMode then
        -- Referenzdaten entstehen mit dem Preset des Prototyps, nicht mit der
        -- Vanilla-Voreinstellung: die Rallyes brauchen Dash und Smash
        -- (ADR-006 gilt fuer das Spiel, nicht fuer die Beweisstuecke).
        App.applyPreset("prototype")
    end

    if flags.manifest then
        Recorder.writeManifest()
        print("[manifest] tests/replays/manifest.json geschrieben")
        love.event.quit()
        return
    end

    if flags.shot then M.installScreenshot(App) return end
    if flags.selftest then M.installSelftest(App) return end
    if flags.queue or flags.probeId then M.installReplay(App) return end

    -- Reiner Aufzeichnungsmodus: Overlay und Tasten.
    M.installOverlay()
end

-- ---------------------------------------------------------------------------
-- Overlay und Tasten
-- ---------------------------------------------------------------------------

function M.installOverlay()
    local baseDraw = love.draw
    local baseKeypressed = love.keypressed
    local baseUpdate = love.update

    love.update = function(dt)
        Recorder.update(dt)
        baseUpdate(dt)
    end

    love.draw = function()
        baseDraw()
        love.graphics.push()
        love.graphics.origin()
        require("src.app.assets").setFont(13)
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.print("REC MODE 1/60", 12, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.pop()
        Recorder.draw()
    end

    love.keypressed = function(key)
        -- F9/F10/F11 und, waehrend der Aufnahme, TAB/F1 gehoeren dem Recorder.
        if Recorder.keypressed(key) then return end
        baseKeypressed(key)
    end
end

-- ---------------------------------------------------------------------------
-- Screenshot
-- ---------------------------------------------------------------------------

function M.installScreenshot(App)
    local baseUpdate = love.update
    local Scene = require("src.app.scene")

    love.update = function(dt)
        flags.shot = flags.shot + 1
        local at = flags.shotPage and 20 or 150

        if flags.shot == 5 then
            if flags.shotPage then
                local top = Scene.top()
                if top.menu then top.menu:goTo(flags.shotPage) end
            else
                App.startMatch(true)
                App.game:resetRally(2)   -- der Bot schlaegt auf, sonst passiert nichts
            end
        elseif flags.shot == at then
            love.graphics.captureScreenshot("viewport.png")
            print("[shot] " .. love.filesystem.getSaveDirectory() .. "/viewport.png")
        elseif flags.shot > at + 2 then
            love.event.quit()
        end
        baseUpdate(dt)
    end
end

-- ---------------------------------------------------------------------------
-- Selbsttest
-- ---------------------------------------------------------------------------

function M.installSelftest(App)
    local baseUpdate = love.update
    local frames, startedAt = 0, 0

    -- Ohne VSync laeuft der Selbsttest mit weit ueber 60 Bildern je Sekunde.
    -- Die 300 Ticks muessen trotzdem rund 5 s dauern -- das ist der Nachweis,
    -- dass die Simulation an der Tickrate haengt und nicht an der Bildrate.
    love.window.setVSync(0)
    print("[selftest] love " .. table.concat({ love.getVersion() }, ".", 1, 3))
    print("[selftest] hasKeyRepeat = " .. tostring(love.keyboard.hasKeyRepeat()))
    print("[selftest] window " .. table.concat({ love.graphics.getDimensions() }, "x"))
    print("[selftest] WORLD " .. World.WIDTH .. "x" .. World.HEIGHT)

    App.startMatch(true)
    App.game:resetRally(2)
    while Recorder.currentId() ~= "R-00" do Recorder.nextRally() end
    Recorder.start()
    startedAt = love.timer.getTime()

    love.update = function(dt)
        Recorder.update(dt)
        baseUpdate(dt)
        frames = frames + 1

        if Recorder.tickCount() >= 300 then
            Recorder.stop()
            print(string.format("[selftest] %d Ticks in %.2f s Echtzeit, %d Frames",
                Recorder.tickCount(), love.timer.getTime() - startedAt, frames))
            love.event.quit()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Wiedergabe und Szenen
-- ---------------------------------------------------------------------------

function M.installReplay(App)
    Replay = require("tools.replay_source")

    local game = App.game
    local bits = { 0, 0 }
    local run, beginNext

    -- Seit M0-07 ist die Wiedergabe vollstaendig: beide Spieler bekommen eine
    -- Quelle, die die aufgezeichneten Bytes ausgibt. Am Spiel selbst wird
    -- nichts umgebogen.
    game.sources[1] = { poll = function() return bits[1] end }
    game.sources[2] = { poll = function() return bits[2] end }
    love.window.setVSync(0)

    local function feed(b1, b2) bits[1], bits[2] = b1, b2 end

    local function applyInit(init)
        local state = game.state
        local ball, blobs = state.ball, state.blobs
        local groundY = App.ruleset.blobGroundY or 500

        ball.x, ball.y, ball.vx, ball.vy = init.ball[1], init.ball[2], init.ball[3], init.ball[4]
        ball.rotation, ball.radius = 0, App.ruleset.ballRadius
        for i, key in ipairs({ "p1", "p2" }) do
            local blob = blobs[i]
            blob.x, blob.y, blob.vx, blob.vy = init[key][1], init[key][2], init[key][3], init[key][4]
            blob.isGrounded = blob.y >= groundY
            blob.cooldownTimer, blob.dashTimer, blob.dashSpeed = 0, 0, 0
            blob.tiltAngle, blob.touchCooldown, blob.dashGrace = 0, 0, 0
        end

        state.rally.lastTouchPlayer, state.rally.touchCount = init.touch[1], init.touch[2]
        state.match.score[1], state.match.score[2] = init.score[1], init.score[2]
        state.match.servingPlayer, state.match.phase = init.server, init.phase
        state.rally.serveTimer, state.rally.serveDelay = 0, 1.0
        state.rally.faultTimer, state.rally.faultPlayer = 0, 0
        state.rally.timer = 0
        state.rally.ballSide = (ball.x < World.WIDTH / 2) and 1 or 2
        state.rally.rallies, state.match.inProgress = 0, true
        state.input.prev[1], state.input.prev[2] = 0, 0
        App.prefs.botActive = true   -- die Aufnahmen sind gegen den Bot gespielt
        require("src.render.fx").reset()
    end

    beginNext = function()
        local id = table.remove(flags.queue, 1)
        if not id then
            Recorder.writeManifest()
            print("[replay] fertig")
            love.event.quit()
            run = nil
            return
        end

        local data
        if flags.sceneId == id then
            local scene = Replay.scene(id)
            if not scene then
                print("[replay] keine Szene fuer " .. id)
                return beginNext()
            end
            data = { count = scene.ticks, init = scene.makeInit(scene), scene = scene }
            Recorder.setDriver("scripted:" .. id)
        else
            local loaded, err = Replay.load("tests/replays/variable/" .. id .. ".json")
            if not loaded then
                print("[replay] " .. tostring(err))
                return beginNext()
            end
            data = loaded
            if data.ruleset then
                -- Die Aufzeichnung bringt ihr Regelwerk mit. Ohne das liefe die
                -- Wiedergabe gegen die heutige Voreinstellung.
                App.applyRuleset(Ruleset.fromSnapshot(data.ruleset))
            end
            Recorder.setDriver("replay:variable/" .. id .. ".json")
        end

        applyInit(data.init)
        Recorder.selectById(id)
        Recorder.start()
        run = { id = id, data = data, tick = 0, tail = 0 }
        print(string.format("[replay] %s: %d Ticks", id, data.count))
    end

    local TAIL_MAX = 400
    local AFTER = 5

    local function step()
        if not run then return end
        local match = game.state.match

        -- Fuenf Ticks ueber das Ende hinaus, damit der vergebene Punkt in der
        -- Datei steht: ein Frame haelt den Zustand VOR seinem Schritt.
        local rallyOver = match.phase ~= "play"
        if rallyOver and run.sawPlay then run.after = (run.after or 0) + 1 end
        if match.phase == "play" then run.sawPlay = true end

        if run.data.scene and run.sawPlay and (run.after or 0) > AFTER then
            run.tick = run.data.count
        end

        if run.tick >= run.data.count then
            if (not rallyOver or (run.after or 0) <= AFTER) and run.tail < TAIL_MAX then
                feed(0, 0)
                game:tick()
                run.tail = run.tail + 1
                return
            end
            Recorder.stop()
            print(string.format("[replay] %s fertig (+%d Ticks Auslauf)", run.id, run.tail))
            beginNext()
            return
        end

        local b1, b2
        if run.data.scene then
            b1, b2 = run.data.scene.inputs(run.data.scene, run.tick)
        else
            local pair = run.data.inputs[run.tick + 1]
            b1, b2 = pair[1], pair[2]
        end
        feed(b1, b2)
        game:tick()
        run.tick = run.tick + 1
    end

    -- Parameterlauf fuer eine Skriptszene: simuliert in einer engen Schleife
    -- ohne Aufzeichnung und druckt die Kennzahlen jedes Kandidaten, damit die
    -- Szenenparameter gemessen statt geraten werden.
    local function probe(id)
        local scene = Replay.scene(id)
        if not scene then print("[probe] keine Szene fuer " .. id) return end
        local sw = scene.sweep
        local state = game.state

        for candidate = sw.from, sw.to, (sw.step or 1) do
            scene[sw.field] = candidate
            applyInit(scene.makeInit(scene))

            local peak, contacts, contactVx, airSmash = 0, 0, 0, false
            local postPeak, preContact = 0, 0
            local prevTouch, prevPlayer = 0, 0

            for tick = 0, scene.ticks - 1 do
                local b1, b2 = scene.inputs(scene, tick)
                feed(b1, b2)
                local wasAir, blobVx = not state.blobs[1].isGrounded, state.blobs[1].vx
                local smashHeld = Frame.has(b1, Frame.SMASH)
                local before = math.sqrt(state.ball.vx ^ 2 + state.ball.vy ^ 2)
                game:tick()

                local v = math.sqrt(state.ball.vx ^ 2 + state.ball.vy ^ 2)
                if v > peak then peak = v end
                if state.rally.touchCount > 0
                   and (state.rally.touchCount > prevTouch
                        or state.rally.lastTouchPlayer ~= prevPlayer) then
                    contacts = contacts + 1
                    if v > postPeak then postPeak = v; preContact = before end
                    if state.rally.lastTouchPlayer == 1 then
                        if math.abs(blobVx) > math.abs(contactVx) then contactVx = blobVx end
                        if wasAir and smashHeld then airSmash = true end
                    end
                end
                prevTouch, prevPlayer = state.rally.touchCount, state.rally.lastTouchPlayer
            end

            print(string.format(
                "[probe] %s %s=%-5s peak=%8.2f contacts=%d maxContactVx=%7.1f airSmash=%-5s "
                .. "bestContact %7.1f -> %7.1f score=%d:%d phase=%s",
                id, sw.field, tostring(candidate), peak, contacts, contactVx, tostring(airSmash),
                preContact, postPeak, state.match.score[1], state.match.score[2],
                state.match.phase))
        end
    end

    if flags.probeId then
        probe(flags.probeId)
        love.event.quit()
        return
    end

    -- Genau ein Tick je Frame: der Treiber bestimmt den Takt, nicht die Uhr.
    love.update = function(dt)
        Recorder.update(dt)
        step()
    end
    beginNext()
end

return M
