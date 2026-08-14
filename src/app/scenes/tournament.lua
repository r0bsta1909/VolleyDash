-- ============================================================================
-- src/app/scenes/tournament.lua -- der Turniermodus als Szene (M4-07 … M4-09)
--
-- Die Szene besitzt vier Dinge und sonst nichts: die Session
-- (`src/tournament/session.lua`), die Bedienung (`src/ui/tournament_lobby.lua`),
-- die Uhr und -- seit M4-09 -- die Netzverbindung. Entschieden wird in der
-- Session, getippt in der Bedienung, gezeichnet in `src/render/bracket_view.lua`.
--
-- ---------------------------------------------------------------------------
-- Zwei Rollen, ein Bildschirm
-- ---------------------------------------------------------------------------
--
--   LEITER       haelt `TournamentHost` auf 21212 und die Bake. Die Session
--                gehoert ihm, er traegt ein und korrigiert.
--   TEILNEHMER   haelt `TournamentClient`. Seine Session ist ein ABBILD, aus
--                Log-Ereignissen abgeleitet (ADR-023) und schreibgeschuetzt --
--                das Log hat genau einen Schreiber.
--
-- Beide bekommen ihre Matchzuweisung ueber DENSELBEN Rueckruf (`onAssign`).
-- Beim Leiter kommt sie ohne Umweg ueber das Netz herein, weil er nicht mit
-- sich selbst redet -- der Weg dahinter ist aber derselbe, und genau deshalb
-- gibt es hier keinen zweiten Codepfad fuer den Fall "der Wirt spielt mit".
--
-- ---------------------------------------------------------------------------
-- Warum das Match nicht durch die Lobby-Szene geht
-- ---------------------------------------------------------------------------
--
-- `src/app/scenes/lobby.lua` VERHANDELT: freie Slots, Bereitschaftsschalter,
-- Ruleset-Abgleich. Ein Turniermatch hat daran nichts zu verhandeln. Die
-- Paarung kommt aus dem Bracket, das Ruleset ist beim Turnierstart eingefroren
-- (Datenmodell §4), und die Bereitmeldung geht an den Turnier-Wirt statt an
-- den Gegner. Wiederverwendet werden die BAUTEILE (`src/net/host.lua`,
-- `src/net/client.lua`, ueber `src/net/match_runner.lua`), nicht die Szene.
-- ============================================================================

local Session          = require("src.tournament.session")
local Persistence      = require("src.tournament.persistence")
local Ruleset          = require("src.sim.ruleset")
local Protocol         = require("src.net.protocol")
local MatchRunner      = require("src.net.match_runner")
local MatchStats       = require("src.tournament.match_stats")
local HostChoice       = require("src.tournament.host_choice")
local TournamentHost   = require("src.net.tournament_host")
local TournamentClient = require("src.net.tournament_client")
local TL               = require("src.ui.tournament_lobby")
local BracketView      = require("src.render.bracket_view")
local Scene            = require("src.app.scene")
local BuildInfo        = require("src.app.build_info")
local Assets           = require("src.app.assets")
local Music            = require("src.app.music")

local TournamentScene = {}
TournamentScene.__index = TournamentScene

-- Verschnaufpause, bevor die naechste Zuweisung angenommen wird.
--
-- Die Matchszene laesst den Endstand stehen (`NetGame.TOURNAMENT_LINGER`);
-- danach steht man wieder im Bracket -- und wurde bis M4-09 im selben Moment
-- ins naechste Match gezogen. Die Zuweisung geht dabei nicht verloren: Der
-- Turnier-Wirt wiederholt sie, bis sie angenommen ist.
TournamentScene.BREATHER = 3

local function now()
    return love.timer.getTime()
end

-- Die Uhr, mit der diese Szene rechnet.
--
-- Beim Leiter ist das die eigene. Beim TEILNEHMER ist es die des Turnier-Wirts
-- (`TournamentClient:hostNow`): Das Log traegt Host-Zeitstempel, und `calledAt`
-- gegen die eigene Prozesszeit zu rechnen liefert die Differenz zweier
-- Startzeitpunkte statt einer Restzeit (C-T-12). Eine Uhr fuer die ganze
-- Szene, damit Ton, Einblendung und Countdown nicht auseinanderlaufen.
function TournamentScene:clock()
    if self.tclient then return self.tclient:hostNow() end
    return now()
end

function TournamentScene.new(app, opts)
    opts = opts or {}
    local self = setmetatable({
        name = "tournament",
        app  = app,
        role = opts.role or "leader",
        -- ADR-024: laeuft weiter, auch wenn ein Match darueber liegt. Diese
        -- Szene haelt den Turnier-Wirt bzw. die Verbindung dorthin, und ein
        -- ENet-Wirt, den minutenlang niemand bedient, hat danach keine
        -- Teilnehmer mehr (C-T-01).
        alwaysUpdate = true,
    }, TournamentScene)

    if self.role == "client" then
        self:startClient(opts)
        return self
    end

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
-- Turnier anlegen und wiederaufnehmen (Leiter)
-- ---------------------------------------------------------------------------

function TournamentScene:createSession()
    local app = self.app
    -- Das Ruleset wird beim Anlegen eingefroren (Datenmodell §4) -- dasselbe
    -- Verfahren wie in der Match-Lobby (ADR-005).
    app.applyPreset(app.prefs.preset)

    local stamp = os.time()
    self.choice = HostChoice.new()

    local session = Session.new({
        id          = "t_" .. tostring(stamp),
        name        = app.playerName() .. "s Turnier",
        createdAt   = stamp,
        ruleset     = app.ruleset,
        rulesetHash = Ruleset.hash(app.ruleset),
        persistence = self.persistence,
        -- Seit M4-09 kommt die Anwesenheit aus der Verbindung (§5). Das ist
        -- ein Schalter, kein zweiter Codeweg -- die Datei darunter ist
        -- dieselbe wie in Stufe B.
        presence    = "net",
        chooseHost  = self.choice:chooser(),
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
    self.selfPid = session:addParticipant(app.playerName(), stamp,
        app.clientId and app.clientId() or nil)
    session:setPresence(self.selfPid, true)

    self:startHost()
    return session
end

function TournamentScene:resumeSession(id)
    if not self.persistence then return false, "Kein Dateizugriff" end

    local tournament, source, err = self.persistence:load(id)
    if not tournament then return false, tostring(err) end

    self.choice = HostChoice.new()
    local session = Session.resume(tournament, {
        persistence = self.persistence,
        presence    = "net",
        chooseHost  = self.choice:chooser(),
        selfName    = self.app.playerName(),
    }, now())

    self.session = session
    self.ui.ctx.session = session
    self.selfPid = session:selfId()

    if source == "bak" then
        self.ui:say("Aus der Sicherungsdatei geladen -- das letzte Ereignis kann fehlen")
    elseif #(session.reopened or {}) > 0 then
        self.ui:say(string.format("%d unterbrochene Matches neu angesetzt (E-06)",
            #session.reopened))
    end

    self:startHost()
    return true
end

-- ---------------------------------------------------------------------------
-- Netz
-- ---------------------------------------------------------------------------

function TournamentScene:startHost()
    if self.thost then self.thost:close() end

    local app = self.app
    local thost, err = TournamentHost.new({
        session   = self.session,
        hostChoice = self.choice,
        selfPid   = self.selfPid,
        hostName  = app.playerName(),
        buildHash = BuildInfo.buildHash,
        onEvent   = function(kind, a, b, c) self:onHostEvent(kind, a, b, c) end,
    })

    if not thost then
        -- Ohne Netz bleibt das Turnier bedienbar -- angemeldet wird dann an
        -- der Tastatur wie in Stufe B. Das ist der Notbetrieb aus `11_OPS`
        -- und kein Grund, den Abend abzubrechen.
        self.ui:say("Kein Netz: " .. tostring(err) .. " -- Anmeldung nur hier")
        self.session.presence = "local"
        self.session:refreshPresence()
        return
    end

    self.thost = thost
    thost:startBeacon({ hostId = app.clientId and app.clientId() or 0 })
end

function TournamentScene:startClient(opts)
    local app = self.app
    local client, err = TournamentClient.new({
        address   = opts.address, port = opts.port,
        clientId  = app.clientId and app.clientId() or 0,
        name      = app.playerName(),
        buildHash = BuildInfo.buildHash,
        onEvent   = function(kind, a, b, c) self:onClientEvent(kind, a, b, c) end,
    })

    self.ui = TL.new({
        session    = client and client.session or nil,
        now        = function() return self:clock() end,
        readOnly   = true,
        playerName = function() return app.playerName() end,
        onCreate   = function() end,
        onResume   = function() return false end,
        onLeave    = function() app.leaveTournament() end,
    })

    if not client then
        self.ui:say("Kein Netz: " .. tostring(err))
        return
    end

    self.tclient = client
    self.session = client.session
    self.ui:say("Verbinde mit dem Turnier ...")
end

function TournamentScene:onHostEvent(kind, a, b, c)
    if kind == "join" then
        self.ui:say(tostring(b) .. " ist dabei"
            .. (c == "new" and "" or " (wieder da)"))
    elseif kind == "leave" then
        self.ui:say(tostring(b or a) .. " ist weg")
    elseif kind == "assign" then
        self:onAssign(a)
    elseif kind == "match_lost" then
        self.ui:say("Kein Ergebnis fuer " .. tostring(a) .. " -- neu angesetzt (E-06)")
    end
end

function TournamentScene:onClientEvent(kind, a, b, c)
    if kind == "welcome" then
        self.session = self.tclient.session
        self.ui.ctx.session = self.session
        self.ui:enterRun()
        self.ui:say("Angemeldet als " .. tostring(b))
    elseif kind == "state" then
        -- Die Session kann nach einem Neuaufbau eine andere Tabelle sein.
        self.session = self.tclient.session
        self.ui.ctx.session = self.session
    elseif kind == "assign" then
        self:onAssign(a)
    elseif kind == "failed" then
        self.ui:say(tostring(a))
    end
end

-- ---------------------------------------------------------------------------
-- Ein Turniermatch (§8)
--
-- Derselbe Rueckruf fuer Leiter und Teilnehmer. Wer hostet, oeffnet einen
-- ephemeren Port und meldet ihn; wer Gast ist, wartet auf die Adresse und
-- verbindet sich dann. Die Wahl trifft weder der eine noch der andere -- sie
-- steht in der Zuweisung (ADR-022).
-- ---------------------------------------------------------------------------

function TournamentScene:onAssign(payload)
    if self.runner and self.runner.matchId == payload.matchId then
        return   -- schon aufgebaut; die zweite Zuweisung traegt nur die Adresse
    end

    -- Waehrend eines laufenden Matches wird keine neue Zuweisung angefasst.
    -- Sie kann hier ankommen, seit die Turnierverbindung ins Match mitwandert
    -- -- und der alte Laeufer wuerde dann MITTEN in seiner eigenen
    -- Ereignisschleife geschlossen. Gemessen 2026-08-13: `attempt to index
    -- field 'host' (a nil value)`. Ein Teilnehmer ist ohnehin nie in zwei
    -- Matches gleichzeitig; die Zuweisung kommt nach dem Abpfiff erneut,
    -- weil der Turnier-Wirt sie je Wasserstand verschickt.
    if self.inMatch or self.closing then return end

    -- Gerade erst aus einem Match gekommen: kurz durchatmen. Der Turnier-Wirt
    -- schickt die Zuweisung in zwei Sekunden noch einmal (C-T-16).
    if now() < (self.readyAt or 0) then return end

    if self.runner then self.closing = self.runner self.runner = nil end

    local common = {
        matchId   = payload.matchId,
        ruleset   = self.session.t.ruleset,
        selfName  = self.app.playerName(),
        buildHash = BuildInfo.buildHash,
        clientId  = self.app.clientId and self.app.clientId() or 0,
        opponent  = payload.opponent,
        bestOf    = payload.bestOf,
        bufferTicks = self.app.prefs and self.app.prefs.netBuffer or nil,
    }

    if payload.role == Protocol.ROLE.HOST then
        local runner, err = MatchRunner.newHost(common)
        if not runner then
            self.ui:say("Match laesst sich nicht oeffnen: " .. tostring(err))
            return
        end
        self.runner = runner
        self.stats  = MatchStats.new()
        self:accept(payload.matchId, runner.port)
        self.ui:say("Du bist dran gegen " .. tostring(payload.opponent)
                    .. " -- warte auf den Gegner")

    elseif payload.address and payload.address ~= "" then
        common.address = payload.address
        local runner, err = MatchRunner.newGuest(common)
        if not runner then
            self.ui:say("Gegner nicht erreichbar: " .. tostring(err))
            return
        end
        self.runner = runner
        self:accept(payload.matchId, 0)
        self.ui:say("Du bist dran gegen " .. tostring(payload.opponent))
    end
end

-- Bereitmeldung und -- beim Wirt -- der Port. Der Leiter geht dabei nicht
-- ueber das Netz: Er IST der Turnier-Wirt.
function TournamentScene:accept(matchId, port)
    if self.tclient then
        self.tclient:accept(matchId, port, true)
    elseif self.thost then
        if port and port > 0 then self.thost:hostSelfMatch(matchId, port) end
        self.session:confirmReady(matchId, self.selfPid, now())
    end
end

-- Das Match kann anfangen, sobald die Gegenseite steht. Beim Wirt heisst das
-- "der zweite Platz ist belegt", beim Gast "MATCH_START ist da".
function TournamentScene:pushMatchIfReady()
    local runner = self.runner
    if not runner or self.inMatch then return end

    if runner:isHost() then
        -- Bewusst NICHT `lobby:isStartable()`: Das verlangt zusaetzlich den
        -- Bereitschaftsschalter beider Plaetze, und den gibt es im Turnier
        -- nicht. Bereit gemeldet hat sich jeder schon beim Turnier-Wirt
        -- (`MATCH_ACCEPT`) -- ein zweites Mal danach zu fragen waere eine
        -- Huerde, die niemand erklaeren kann, und der Gast haette dafuer nicht
        -- einmal einen Bildschirm.
        if runner.host.lobby:occupiedCount() < 2 then return end
        runner.host:startMatch()
        self:enterMatch(1)
    elseif runner.client.state == "playing" then
        self:enterMatch(runner.client.slot or 2)
    end
end

function TournamentScene:enterMatch(slot)
    local runner = self.runner
    self.inMatch = true
    self.wasInMatch = true

    local other = (slot == 1) and 2 or 1
    local names = {}
    names[slot]  = self.app.playerName()
    names[other] = runner.opponent or "Gegner"

    self.app.enterNetMatch({
        role    = runner:isHost() and "host" or "client",
        host    = runner.host,
        client  = runner.client,
        ruleset = runner:isHost() and self.session.t.ruleset or runner.client.ruleset,
        -- Die Namen gehoeren zu den SLOTS, nicht zu "ich und der andere".
        -- `Hud.draw` ordnet names[1] dem Slot 1 zu; wer als Gast auf Slot 2
        -- sitzt und hier stur seinen eigenen Namen zuerst schreibt,
        -- beschriftet damit den Host mit seinem Namen. Am Abend des
        -- 2026-08-13 gemessen: derselbe Stand las sich auf zwei Rechnern
        -- spiegelverkehrt (C-T-11). `LobbyScene:names()` macht es seit M2
        -- richtig, diese Szene tat es nicht.
        names   = names,
        slot    = slot,
        stats   = self.stats,
        -- Sagt der Matchszene, dass sie zu einem Turnier gehoert: Endstand
        -- stehen lassen, danach von allein zurueck, ESC beendet nichts.
        isTournament = true,
        -- Die Turnierverbindung wandert mit: Waehrend des Matches bekommt
        -- diese Szene kein `update` mehr, und ein ENet-Wirt, den vier Minuten
        -- lang niemand bedient, hat danach keine Teilnehmer mehr.
        -- Der Rueckgabewert zaehlt: `true` heisst "noch ein Satz" (Best-of-3).
        -- Ihn zu verschlucken haette dieselbe Wirkung wie ihn nie zu
        -- schicken -- beide Seiten blieben auf dem Endstand stehen.
        onFinished = function(scoreA, scoreB, reason, stats)
            return self:reportResult(runner.matchId, scoreA, scoreB, reason, stats)
        end,
    })
end

-- Das Match wurde verlassen, nicht beendet.
--
-- Was daraus folgt, entscheidet der Turnier-Wirt und nicht der, der geht:
--
--   * Als GAST nehmen wir die Bereitmeldung zurueck. Der Wirt schickt die
--     Zuweisung daraufhin erneut, und wir bauen die Verbindung neu auf --
--     laeuft das Match schon, ist das der Wiedereinstieg aus `04_NETCODE` §12
--     mit derselben `clientId`. Wer nicht binnen 30 s zurueck ist, verliert es
--     per Walkover, und auch das ist bereits gebaut (E-05).
--   * Als MATCH-WIRT ist das Match weg, sobald der Socket zugeht. Das ist
--     E-06: neu ansetzen, kein Walkover -- der Absturz ist nicht die Schuld
--     eines Spielers. Der Leiter kann das selbst; ein Teilnehmer sagt es dem
--     Wirt mit derselben Ruecknahme, und der zieht die Folge.
function TournamentScene:abandonMatch()
    local runner = self.runner
    self.inMatch = false
    self.stats   = nil

    if runner then
        self.runner = nil
        self.closing = runner
        self.closingUntil = now() + 0.5

        if self.tclient then
            self.tclient:accept(runner.matchId, 0, false)
        elseif self.thost and runner:isHost() then
            self.session:abortMatch(runner.matchId, self:clock())
        end
    end

    self.ui:say("Match verlassen -- der Turnier-Wirt setzt es neu an")
end

-- Der Ergebnisbericht (E-08). Best-of-3 sammelt Saetze, bis einer zwei hat --
-- erst dann geht die Meldung hinaus.
function TournamentScene:reportResult(matchId, scoreA, scoreB, reason, stats)
    local runner = self.runner
    if not runner or runner.matchId ~= matchId then return end

    local done = runner:addSet(scoreA, scoreB)
    if not done then
        -- Best-of-3: noch kein Ergebnis. `true` zurueck heisst fuer die
        -- Matchszene "noch ein Satz" -- ohne diese Antwort blieben beide
        -- Seiten auf dem Endstand stehen und das Turnier wartete auf ein
        -- Ergebnis, das nie kommt. Gemessen 2026-08-13 im Finale.
        self.ui:say("Satz notiert -- weiter geht es")
        return true
    end

    -- Gemeldet wird nur vom Match-Wirt (E-08). Der Gast raeumt hier bloss auf
    -- und geht zurueck ins Turnier -- wuerde er mitmelden, gaebe es zwei
    -- Absender fuer ein Ergebnis und die Zusicherung "kann nicht auftreten"
    -- waere eine Absichtserklaerung.
    if runner:isHost() then
        if self.tclient then
            self.tclient:report(matchId, runner.sets, stats, reason)
        elseif self.thost then
            self.session:enterResult(matchId, runner.sets, now(), stats)
        end
    end

    self.reportedMatch = matchId
    self.inMatch = false
    self.runner = nil
    self.stats  = nil

    -- Der Socket wird NICHT hier zugemacht. Dieser Rueckruf kommt aus der
    -- Ereignisschleife von `Client`/`Host` heraus -- die leert ihre Queue in
    -- einer Schleife, und wer ihr mittendrin den Wirt unter den Fuessen
    -- wegzieht, bekommt beim naechsten Durchlauf ein `attempt to index field
    -- 'host' (a nil value)`. Gemessen 2026-08-13 im Vierprozesslauf.
    self.closing = runner
    -- Und nicht sofort: Der Wirt hat gerade `MATCH_END` in die Warteschlange
    -- gelegt. Eine halbe Sekunde weiterbedienen kostet nichts und sorgt
    -- dafuer, dass die Nachricht auch dann ankommt, wenn ein Paket unterwegs
    -- wiederholt werden muss.
    self.closingUntil = now() + 0.5
    -- Kein `leaveMatch()` hier: Die Matchszene laesst den Endstand stehen und
    -- geht danach von allein zurueck. Zwei Wege hinaus waeren zwei Zeitpunkte.
end

-- ---------------------------------------------------------------------------
-- Szene
-- ---------------------------------------------------------------------------

function TournamentScene:enter()
    Music.play("menu")
end

function TournamentScene:update()
    -- Diese Szene laeuft seit ADR-024 auch dann, wenn ein Match darueber
    -- liegt -- die Verbindung muss bedient werden. Alles, was den MENSCHEN
    -- oder den MATCH-SOCKET angeht, haengt deshalb daran, ob sie auch obenauf
    -- ist.
    local top = Scene.isTop(self)

    -- Aufraeumen erst, wenn die Matchszene wirklich weg ist. Sie bedient
    -- denselben Wirt; ihn ihr unter den Fuessen wegzuziehen ist genau der
    -- Fehler aus C-T-05, nur eine Ebene hoeher -- und seit `alwaysUpdate`
    -- laufen beide Szenen gleichzeitig. Gemessen 2026-08-14:
    -- `attempt to index field 'server' (a nil value)`.
    if self.closing and top then
        if now() < (self.closingUntil or 0) then
            self.closing:update(0)
        else
            self.closing:close()
            self.closing = nil
        end
    end

    if top and self.wasInMatch then
        self.wasInMatch = false
        -- Wieder obenauf, `inMatch` steht noch: Das Match wurde VERLASSEN und
        -- nicht beendet (C-T-13).
        if self.inMatch then self:abandonMatch() end
        -- Die Verschnaufpause laeuft ab hier und nicht ab dem Abpfiff: Solange
        -- der Endstand steht, sieht der Mensch das Bracket noch gar nicht
        -- (C-T-16).
        self.readyAt = now() + TournamentScene.BREATHER
    end

    if self.thost then self.thost:update(now()) end
    if self.tclient then self.tclient:update(now()) end
    local clock = self:clock()
    -- Der Laeufer wird nur bedient, solange KEIN Match darueber liegt. Sobald
    -- eines laeuft, gehoert derselbe Wirt der Matchszene -- ihn hier ein
    -- zweites Mal je Bild zu bedienen, hiesse die Ereignisschleife zweimal zu
    -- leeren und Snapshots doppelt zu verschicken (ADR-024).
    if self.runner and top then
        self.runner:update(0)
        self:pushMatchIfReady()
    end

    local session = self.session
    if not session then return end

    -- Der Takt des Turniers. Er laeuft auch, wenn niemand eine Taste drueckt --
    -- der No-Show-Timer ist genau der Fall, in dem niemand etwas tut. Beim
    -- Leiter hat `TournamentHost:update` den Automaten schon laufen lassen;
    -- was hier passiert, ist ausschliesslich das EINSAMMELN des Stroms.
    -- Der Strom wird IMMER geleert, auch waehrend eines Matches -- sonst
    -- braeche beim Zurueckkommen alles auf einmal herein. Gehoert wird er nur
    -- obenauf: Wer gerade spielt, braucht den Aufrufton eines fremden Matches
    -- nicht im Ohr.
    local events = session:tick(clock)
    if top then
        for _, name in ipairs(self.ui:soundsFor(events)) do
            -- Der Aufruf muss ueber die Menuemusik durchkommen (Klangliste §2);
            -- die Vorgabe des Pools ist 0.25.
            Assets.play(name, name == "tournament_call" and 0.5 or 0.35)
        end
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
    BracketView.draw(self.ui, self:clock())
end

function TournamentScene:keypressed(key)
    self.ui:keypressed(key)
end

function TournamentScene:textinput(text)
    self.ui:textinput(text)
end

function TournamentScene:leave()
    if self.runner then self.runner:close() self.runner = nil end
    if self.thost then self.thost:close() self.thost = nil end
    if self.tclient then self.tclient:close() self.tclient = nil end
end

return TournamentScene
