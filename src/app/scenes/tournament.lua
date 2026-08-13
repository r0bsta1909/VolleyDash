-- ============================================================================
-- src/app/scenes/tournament.lua -- der Turniermodus als Szene (M4-07, M4-08)
--
-- Die Szene besitzt drei Dinge und sonst nichts: die Session
-- (`src/tournament/session.lua`), die Bedienung (`src/ui/tournament_lobby.lua`)
-- und die Uhr. Entschieden wird in der Session, getippt in der Bedienung,
-- gezeichnet in `src/render/bracket_view.lua`.
--
-- ---------------------------------------------------------------------------
-- Was hier NICHT passiert
-- ---------------------------------------------------------------------------
--
-- Kein Netzwerk. Ein Turnier mit 20 Teilnehmern braucht einen zweiten
-- Wirt-Typ: `src/net/lobby.lua` hat zwei Plaetze und startet genau ein Match,
-- und das Format von `TOURNAMENT_STATE` (0x40) ist ein offener ADR
-- (ADR-016, ADR-020). Beides gehoert zu Stufe C / M4-09. Angemeldet wird
-- deshalb am Turnier-Host: Die Naht ist `Session:addParticipant`, und die
-- fuellt spaeter das Netz statt der Tastatur.
--
-- Auch kein Matchstart aus dem Turnier heraus. Gespielt wird in Stufe B
-- daneben, das Ergebnis traegt der Turnierleiter ein (M4-11) -- derselbe Weg,
-- den `11_OPS` als Notbetrieb vorsieht, wenn die Automatik ausfaellt.
-- ============================================================================

local Session     = require("src.tournament.session")
local Persistence = require("src.tournament.persistence")
local Ruleset     = require("src.sim.ruleset")
local TL          = require("src.ui.tournament_lobby")
local BracketView = require("src.render.bracket_view")
local Assets      = require("src.app.assets")
local Music       = require("src.app.music")

local TournamentScene = {}
TournamentScene.__index = TournamentScene

local function now()
    return love.timer.getTime()
end

function TournamentScene.new(app)
    local self = setmetatable({
        name = "tournament",
        app  = app,
    }, TournamentScene)

    -- Ohne Dateizugriff laeuft das Turnier trotzdem -- nur uebersteht es dann
    -- keinen Absturz. Das ist eine Meldung wert und kein Abbruch.
    self.persistence = Persistence.new()

    local running = {}
    if self.persistence then
        local ok, list = pcall(function() return self.persistence:running() end)
        if ok then running = list end
    end

    self.ui = TL.new({
        session    = nil,
        running    = running,
        now        = now,
        playerName = function() return app.playerName() end,
        onCreate   = function() self:createSession() end,
        onResume   = function(id) return self:resumeSession(id) end,
        onLeave    = function() app.leaveTournament() end,
    })

    if #running == 0 then self:createSession() end
    return self
end

-- ---------------------------------------------------------------------------
-- Turnier anlegen und wiederaufnehmen
-- ---------------------------------------------------------------------------

function TournamentScene:createSession()
    local app = self.app
    -- Das Ruleset wird beim Anlegen eingefroren (Datenmodell §4) -- dasselbe
    -- Verfahren wie in der Match-Lobby (ADR-005).
    app.applyPreset(app.prefs.preset)

    local stamp = os.time()
    local session = Session.new({
        id          = "t_" .. tostring(stamp),
        name        = app.playerName() .. "s Turnier",
        createdAt   = stamp,
        ruleset     = app.ruleset,
        rulesetHash = Ruleset.hash(app.ruleset),
        persistence = self.persistence,
        presence    = "local",
        selfName    = app.playerName(),
        seedMode    = "random",
        -- Der Seed ist von Anfang an sichtbar und aenderbar. Die Uhrzeit ist
        -- eine Vorgabe, kein Geheimnis: Wer will, tippt "sommerlan" darueber.
        seedValue   = os.date("%H%M%S", stamp),
    })

    self.session = session
    self.ui.ctx.session = session

    -- Der Mensch am Rechner steht als Erster im Feld. Wer nur ausrichtet,
    -- streicht sich mit ENTF wieder heraus.
    session:addParticipant(app.playerName(), stamp)
    return session
end

function TournamentScene:resumeSession(id)
    if not self.persistence then return false, "Kein Dateizugriff" end

    local tournament, source, err = self.persistence:load(id)
    if not tournament then return false, tostring(err) end

    local session = Session.resume(tournament, {
        persistence = self.persistence,
        presence    = "local",
        selfName    = self.app.playerName(),
    }, now())

    self.session = session
    self.ui.ctx.session = session

    if source == "bak" then
        self.ui:say("Aus der Sicherungsdatei geladen -- das letzte Ereignis kann fehlen")
    elseif #(session.reopened or {}) > 0 then
        self.ui:say(string.format("%d unterbrochene Matches neu angesetzt (E-06)",
            #session.reopened))
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Szene
-- ---------------------------------------------------------------------------

function TournamentScene:enter()
    Music.play("menu")
end

function TournamentScene:update()
    local session = self.session
    if not session then return end

    -- Der Takt des Turniers. Er laeuft auch, wenn niemand eine Taste drueckt --
    -- der No-Show-Timer ist genau der Fall, in dem niemand etwas tut.
    local events = session:tick(now())
    for _, name in ipairs(self.ui:soundsFor(events)) do
        -- Der Aufruf muss ueber die Menuemusik durchkommen (Klangliste §2);
        -- die Vorgabe des Pools ist 0.25.
        Assets.play(name, name == "tournament_call" and 0.5 or 0.35)
    end

    -- Der Aufruf ist auch eine Einblendung, nicht nur ein Ton (§5).
    for _, ev in ipairs(events) do
        if ev.event == "match_called" then
            local m = session.t.matches[ev.matchId]
            local me = session:selfId()
            if m and me and session:involves(m, me) then
                local opponent = m.slotB
                if m.slotB == me then opponent = m.slotA end
                self.ui:say("DU BIST DRAN -- gegen " .. tostring(session:nameOf(opponent)))
            end
        elseif ev.event == "tournament_finished" then
            self.ui:say("Turnier beendet -- Sieger: " .. tostring(session:winnerName()))
        end
    end
end

function TournamentScene:draw()
    BracketView.draw(self.ui, now())
end

function TournamentScene:keypressed(key)
    self.ui:keypressed(key)
end

function TournamentScene:textinput(text)
    self.ui:textinput(text)
end

return TournamentScene
