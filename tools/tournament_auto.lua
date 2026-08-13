-- ============================================================================
-- tools/tournament_auto.lua -- ein Turnier ueber vier Prozesse (M4-09)
--
--   love . --tournament-auto=host             der Turnierleiter
--   love . --tournament-auto=client --client-id=2   ein Teilnehmer
--
-- Der Selbsttest (`--tournament-selftest`) prueft Protokoll, Ports und
-- Bracket in EINEM Prozess. Was er nicht anfasst, ist die Szene: Zuweisung
-- entgegennehmen, Match-Wirt oeffnen, in `net_game` wechseln, Ergebnis melden,
-- zurueckkehren. Genau dort lagen in Stufe B beide echten Fehler (F-T-10).
--
-- Hier laeuft das mit Bild, aber ohne Hand: Die Simulation braucht keine
-- Eingabe, um zu einem Ergebnis zu kommen -- der Ball faellt, es gibt Punkte,
-- irgendwann steht ein Satz. Ein Turnier, das ohne einen einzigen Tastendruck
-- bis zum Sieger durchlaeuft, ist genau die Frage aus `05_TOURNAMENT` §13.1.
--
-- Temporaeres Werkzeug wie `tools/net_selftest.lua`: haengt sich von aussen
-- an, wird nicht ausgeliefert.
-- ============================================================================

local Protocol  = require("src.net.protocol")
local Discovery = require("src.net.discovery")
local Model     = require("src.tournament.model")
local Frame     = require("src.input.frame")

local M = {}

-- Wie viele Teilnehmer der Leiter abwartet, bevor er auslost.
M.EXPECT = 4

function M.install(App, role)
    local Scene = require("src.app.scene")
    local baseUpdate = love.update
    local frames = 0
    local drawn, browser, joined = false, nil, false
    local lastLine = ""

    -- Vier Prozesse schreiben gleichzeitig; umgeleitet puffert LOEVE die
    -- Ausgabe und das Protokoll erscheint erst am Ende -- oder gar nicht, wenn
    -- der Lauf haengt. Genau dann will man es lesen.
    pcall(function() io.stdout:setvbuf("no") end)

    print("[tauto] Rolle " .. tostring(role))

    if role == "host" then
        App.openTournament()
    else
        browser = Discovery.newBrowser({})
        if browser then browser:probe() end
        App.openServerList()
    end

    local function say(text)
        if text ~= lastLine then
            print("[tauto] " .. text)
            lastLine = text
        end
    end

    love.update = function(dt)
        baseUpdate(dt)
        frames = frames + 1

        -- Der Teilnehmer sucht sich sein Turnier selbst. Das ist der Weg des
        -- Abends: Bake -> Serverliste -> ENTER, ohne IP-Eingabe.
        if role == "client" and not joined then
            if browser then
                browser:update()
                if frames % 120 == 0 then browser:probe() end
                for _, e in ipairs(browser:list()) do
                    if e.mode == "tournament" then
                        say("Turnier gefunden: " .. tostring(e.lobbyName)
                            .. " @ " .. tostring(e.address) .. ":" .. tostring(e.port))
                        joined = true
                        browser:close()
                        browser = nil
                        App.joinTournament(e.address, e.port)
                        break
                    end
                end
            end
            return
        end

        local top = Scene.top()
        if not top then return end

        if top.name == "tournament" then
            -- Liegt ein Turnier von einem frueheren Lauf in der Datei, kommt
            -- die Frage nach der Fortsetzung ZUERST (§7). Der Autopilot legt
            -- ein neues an -- er soll den Weg des ersten Abends fahren, nicht
            -- den der Wiederaufnahme.
            if top.ui and top.ui.mode == "resume" then
                for i, item in ipairs(top.ui:resumeItems()) do
                    if item.kind == "new" then top.ui.sel = i end
                end
                say("laufendes Turnier gefunden -- lege ein neues an")
                top:keypressed("return")
                return
            end

            local s = top.session
            if not s then return end

            if role == "host" and not drawn then
                if s:count() >= M.EXPECT then
                    if s:drawBracket(love.timer.getTime()) then
                        drawn = true
                        say(string.format("ausgelost, %d Teilnehmer, Seed %s",
                            s:count(), tostring(s:seedNumber())))
                    end
                elseif frames % 180 == 0 then
                    say(string.format("warte auf Teilnehmer: %d von %d",
                        s:count(), M.EXPECT))
                end
            end

            if frames % 180 == 0 then
                local live, done, open = 0, 0, 0
                for _, id in ipairs(s.t.matchOrder) do
                    local m = s.t.matches[id]
                    if m.status == Model.STATUS.LIVE then live = live + 1
                    elseif Model.TERMINAL[m.status] then done = done + 1
                    else open = open + 1 end
                end
                say(string.format("Matches: %d fertig, %d laufen, %d offen",
                    done, live, open))
            end

            -- Nach dem Sieger noch zwei Sekunden weiterlaufen: Der Leiter
            -- ist der Letzte, der das Ergebnis verteilt, und wer im selben
            -- Bild aussteigt, nimmt den Teilnehmern den Schlussstand weg.
            if s:isFinished() and not top.finishedAt then
                top.finishedAt = love.timer.getTime()
            end

            if s:isFinished() and love.timer.getTime() - top.finishedAt > 2 then
                print("[tauto] SIEGER: " .. tostring(s:winnerName()))
                for _, pid in ipairs(s.t.participantOrder) do
                    local p = s.t.participants[pid]
                    print(string.format("[tauto]   %-12s %d/%d  Rallye %.1fs  Ball %.0f",
                        p.name, p.stats.wins, p.stats.matches,
                        p.stats.longestRally, p.stats.fastestBall))
                end
                love.event.quit(0)
            end

        elseif top.name == "net_game" then
            -- Ohne Hand am Rechner passiert im Match NICHTS: Der Aufschlag
            -- braucht eine Beruehrung, sonst haengt die Phase auf `serve`
            -- (`src/sim/physics.lua`). Also spielt hier eine vierte Quelle
            -- (ADR-014) -- eine bewusst dumme: zum Ball laufen und springen.
            --
            -- ABSICHTLICH NICHT `src/input/bot_source.lua`: Dessen
            -- Aufschlagzweig fragt `servingPlayer == 2` ab und ist damit auf
            -- Slot 2 festgelegt. Im Turnier sitzt man in beiden Slots, und ein
            -- Bot, der als Slot 1 nie aufschlaegt, wuerde hier einen Fehler in
            -- der Turnierschicht vortaeuschen, den es nicht gibt.
            if not top.autoSource then
                local slot = top.slot or 1
                top.autoSource = {
                    poll = function()
                        local st = top.state
                        local blob, ball = st.blobs[slot], st.ball
                        local left  = ball.x < blob.x - 6
                        local right = ball.x > blob.x + 6
                        local near  = math.abs(ball.x - blob.x) < 90
                        return Frame.encode({
                            left = left, right = right,
                            jump = near and ball.y > 200,
                        })
                    end,
                }
                top.source = top.autoSource
                say("Automatik uebernimmt Slot " .. slot)
            end

            -- Zwei gleich dumme Automatiken halten den Ball beliebig lange in
            -- der Luft -- gemessen: 3000 Ticks ohne einen einzigen Punkt. Ein
            -- Turnierlauf soll aber die TURNIERSCHICHT zeigen und nicht die
            -- Ausdauer zweier Schleifen, also pfeift der Wirt nach 600 Ticks
            -- ab. Denselben Griff macht der Netz-Autopilot fuer die Revanche.
            -- Nach einem Satzende zaehlt der Wirt seine Ticks neu (Best-of-3,
            -- `resetMatch`). Dann darf auch wieder abgepfiffen werden.
            if (top.simTick or 0) < 60 then top.forced = false end

            if top.role == "host" and (top.simTick or 0) > 600 and not top.forced then
                top.forced = true
                top.state.match.score[1] = top.ruleset.targetScore
                top.state.match.score[2] = 9
                top.state.match.phase = "gameover"
                say("Abpfiff erzwungen: " .. top.ruleset.targetScore .. ":9")
            end

            if frames % 180 == 0 then
                say(string.format("Match %s: %d:%d Phase %s Tick %d Ball %.0f/%.0f",
                    top.role, top.state.match.score[1], top.state.match.score[2],
                    tostring(top.state.match.phase), top.simTick or 0,
                    top.state.ball.x, top.state.ball.y))
            end
        end

        -- Notbremse: Ein Lauf, der nach zehn Minuten nicht fertig ist, hat ein
        -- Problem, das man ohnehin am Protokoll sieht.
        if frames > 60 * 600 then
            print("[tauto] ABBRUCH -- zu lang")
            love.event.quit(1)
        end
    end
end

return M
