-- ============================================================================
-- src/net/tournament_host.lua -- der Turnier-Wirt (M4-09)
--
-- `05_TOURNAMENT` §8, `04_NETCODE` §5. Der ZWEITE Wirt-Typ des Projekts, und
-- er ist einer aus einem in F-T-08 gemessenen Grund: `src/net/host.lua` ist
-- ein MATCH-Wirt. Er hat zwei Slots, verhandelt ein Ruleset und startet genau
-- ein Match. Ein Turnier hat 20 dauerhaft verbundene Teilnehmer, keine Slots
-- und nichts zu verhandeln -- das Ruleset friert es beim Start ein.
--
-- ---------------------------------------------------------------------------
-- Was diese Datei ist und was sie nicht ist
-- ---------------------------------------------------------------------------
--
-- Sie ist der TRANSPORT. Sie entscheidet nichts: Anmeldung geht an
-- `Session:addParticipant`, Anwesenheit an `setPresence`, Bereitmeldung an
-- `confirmReady`, Ergebnis an `enterResult`. Die Regeln stehen in
-- `src/tournament/`, love-frei und headless geprueft. Wer hier eine
-- Turnierregel findet, hat einen Fehler gefunden.
--
-- ---------------------------------------------------------------------------
-- Ports (`05_TOURNAMENT` §8.2)
-- ---------------------------------------------------------------------------
--
-- Dieser Wirt bindet 21212 fest -- die Discovery kuendigt ihn dort an. Der
-- MATCH-Wirt eines Turniermatches bindet dagegen `*:0` und meldet den
-- vergebenen Port zurueck (`MATCH_ACCEPT`). Grund, gemessen 2026-08-13: Ein
-- Prozess kann denselben ENet-Port nicht zweimal binden, und der Turnier-Wirt
-- ist gleichzeitig Spieler und moeglicherweise selbst Match-Wirt.
--
-- ---------------------------------------------------------------------------
-- Der Zustand geht als LOG hinaus, nicht als Zustand (ADR-023)
-- ---------------------------------------------------------------------------
--
-- Jeder Teilnehmer haelt seinen eigenen Wasserstand. Was er noch nicht hat,
-- bekommt er als Block von Log-Ereignissen; abgeleitet wird bei ihm mit
-- demselben `Model.applyEvent`. Damit gibt es keinen zweiten Weg, auf dem ein
-- Turnierstand entsteht -- und keine Frage, welcher der richtige waere.
-- ============================================================================

local Protocol   = require("src.net.protocol")
local Discovery  = require("src.net.discovery")
local HostChoice = require("src.tournament.host_choice")
local Model      = require("src.tournament.model")

local TournamentHost = {}
TournamentHost.__index = TournamentHost

-- 32 Teilnehmer (`05_TOURNAMENT` §2) plus Luft fuer Peers, die noch nicht
-- abgeraeumt sind, waehrend ihr Nachfolger sich schon verbindet.
TournamentHost.MAX_PEERS = 40

TournamentHost.PEER_TIMEOUT_MS = 5000
TournamentHost.PING_INTERVAL   = 0.5

-- Eine Zuweisung wird wiederholt, bis sie bestaetigt ist. Sie kann verloren
-- gehen, ohne dass ein Paket verlorengeht: Wer im Moment des Aufrufs noch im
-- vorigen Match steckt, kann sie nicht annehmen. Zwei Sekunden sind kurz genug,
-- dass davon nichts am No-Show-Timer haengen bleibt.
TournamentHost.ASSIGN_RETRY_SECONDS = 2

-- `05_TOURNAMENT` §8: "Bleibt die Meldung aus (Absturz), fragt der Turnier-
-- Host nach 60 s nach; bleibt sie weiter aus -> E-06."
TournamentHost.RESULT_QUERY_SECONDS = 60
TournamentHost.RESULT_GIVEUP_SECONDS = 120

function TournamentHost.new(opts)
    opts = opts or {}

    local enet = opts.enet or require("enet")
    local port = opts.port or Protocol.PORT_ENET

    local server, err = enet.host_create("*:" .. port, TournamentHost.MAX_PEERS,
        Protocol.CHANNELS)
    if not server then
        return nil, "Port " .. port .. " laesst sich nicht binden: " .. tostring(err)
    end

    local choice = opts.hostChoice or HostChoice.new()

    local self = setmetatable({
        enet      = enet,
        server    = server,
        port      = port,
        session   = opts.session,
        choice    = choice,
        buildHash = opts.buildHash or "",
        hostName  = opts.hostName or "Turnier",
        clock     = opts.clock or function() return love.timer.getTime() end,
        onEvent   = opts.onEvent or function() end,

        peers     = {},   -- peer -> { peer, pid, clientId, name, rtt }
        peerOf    = {},   -- pid  -> peer
        sentUpTo  = {},   -- peer -> Wasserstand im Log
        assigned  = {},   -- matchId -> { host = pid, port = , address = , told = }
        lostSince = {},   -- matchId -> Zeit, seit der der Match-Wirt weg ist
        queried   = {},   -- matchId -> Nachfrage nach §8 ist raus

        lastPingAt = 0,
        discovery  = nil,
        stats      = { sent = 0, received = 0, joins = 0, rejoins = 0,
                       reports = 0, queries = 0, aborts = 0 },
    }, TournamentHost)

    -- Der Turnier-Wirt spielt mit (`05_TOURNAMENT` §8). Seine RTT zu sich
    -- selbst ist null, und damit hostet er sein eigenes Match immer -- das ist
    -- das Mass und kein Sonderfall (ADR-022).
    self.selfPid = opts.selfPid

    return self
end

function TournamentHost:now() return self.clock() end

-- ---------------------------------------------------------------------------
-- Bake
--
-- Stufe B hat bewusst keine gesendet: ein Turnier anzukuendigen, dem niemand
-- beitreten kann, ist schlechter als es nicht anzukuendigen. Jetzt kann man
-- beitreten, also geht sie hinaus.
-- ---------------------------------------------------------------------------

function TournamentHost:startBeacon(opts)
    opts = opts or {}
    local disc, err = Discovery.newHost({
        socket = opts.socket,
        port   = opts.discoveryPort,
        info   = function()
            local t = self.session and self.session.t
            return {
                hostId     = opts.hostId or 0,
                hostName   = self.hostName,
                lobbyName  = (t and t.name) or "Turnier",
                buildHash  = self.buildHash,
                players    = self.session and self.session:count() or 0,
                maxPlayers = 32,
                mode       = "tournament",
                enetPort   = self.port,
            }
        end,
    })
    self.discovery = disc
    return disc, err
end

-- ---------------------------------------------------------------------------
-- Senden
-- ---------------------------------------------------------------------------

function TournamentHost:send(peer, msgType, payload)
    local ok, data = pcall(Protocol.encode, msgType, payload)
    if not ok then
        print("[tournament_host] " .. tostring(data))
        return false
    end
    peer:send(data, Protocol.channelOf(msgType), Protocol.flagOf(msgType))
    self.stats.sent = self.stats.sent + 1
    return true
end

function TournamentHost:sendTo(pid, msgType, payload)
    local peer = self.peerOf[pid]
    if not peer then return false end
    return self:send(peer, msgType, payload)
end

-- ---------------------------------------------------------------------------
-- Der Log-Nachlauf (ADR-023)
--
-- Jeder Peer bekommt genau das, was ihm fehlt -- in Bloecken, damit eine
-- einzelne Nachricht nicht mit dem Turnier waechst.
-- ---------------------------------------------------------------------------

function TournamentHost:pushLog(peer)
    local log = self.session and self.session.t.log
    if not log then return 0 end

    local from = self.sentUpTo[peer] or 0
    local sent = 0

    while from < #log do
        local chunk, n = {}, 0
        while n < Protocol.STATE_CHUNK and from + n < #log do
            n = n + 1
            chunk[n] = log[from + n]
        end
        self:send(peer, Protocol.MSG.TOURNAMENT_STATE,
            { fromIndex = from, events = chunk })
        from = from + n
        sent = sent + n
    end

    self.sentUpTo[peer] = from
    return sent
end

function TournamentHost:pushLogToAll()
    for peer, record in pairs(self.peers) do
        if record.pid then self:pushLog(peer) end
    end
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

function TournamentHost:service()
    local count = 0
    local event = self.server:service(0)
    while event do
        self:handle(event)
        count = count + 1
        event = self.server:service(0)
    end
    self.stats.received = self.stats.received + count
    return count
end

function TournamentHost:handle(event)
    if event.type == "connect" then
        event.peer:timeout(32, TournamentHost.PEER_TIMEOUT_MS,
            TournamentHost.PEER_TIMEOUT_MS)
        self.peers[event.peer] = { peer = event.peer }

    elseif event.type == "receive" then
        self:receive(event.peer, event.data)

    elseif event.type == "disconnect" then
        self:dropPeer(event.peer)
    end
end

function TournamentHost:receive(peer, data)
    local msgType, payload = Protocol.decode(data)

    if not msgType then
        local version = Protocol.peekVersion(data)
        if version and version ~= Protocol.VERSION then
            self:send(peer, Protocol.MSG.REJECT, {
                reason = Protocol.REJECT.VERSION,
                text = string.format(
                    "Andere Protokollfassung: Turnier spricht %d, du sprichst %d. "
                    .. "Ihr braucht dieselbe ZIP.", Protocol.VERSION, version),
            })
            peer:disconnect_later(0)
        end
        return
    end

    local record = self.peers[peer]
    if not record then return end

    if msgType == Protocol.MSG.HELLO then
        self:onHello(peer, record, payload)

    elseif msgType == Protocol.MSG.STATE_REQUEST then
        -- Eine Luecke. Der Empfaenger nennt seinen Wasserstand, und ab dort
        -- geht es noch einmal hinaus -- kein Zustandsvergleich noetig.
        self.sentUpTo[peer] = math.min(payload.fromIndex or 0,
            #self.session.t.log)
        self:pushLog(peer)

    elseif msgType == Protocol.MSG.MATCH_ACCEPT then
        self:onAccept(record, payload)

    elseif msgType == Protocol.MSG.MATCH_REPORT then
        self:onReport(record, payload)

    elseif msgType == Protocol.MSG.PING then
        self:send(peer, Protocol.MSG.PONG, { timestamp = payload.timestamp })

    elseif msgType == Protocol.MSG.PONG then
        local rtt = math.max(0, self:now() * 1000 - payload.timestamp)
        record.rtt = rtt
        -- Die Probe fuer ADR-022. Sie faellt ohnehin an; die Wahl des
        -- Match-Wirts kostet keine zusaetzliche Nachricht.
        if record.pid then self.choice:sample(record.pid, rtt, self:now()) end
    end
end

-- ---------------------------------------------------------------------------
-- Anmeldung (E-03, E-05, E-14)
-- ---------------------------------------------------------------------------

function TournamentHost:onHello(peer, record, payload)
    local session = self.session
    if not session then
        self:reject(peer, Protocol.REJECT.CLOSED, "Es laeuft kein Turnier.")
        return
    end

    local now = self:now()

    -- Wiedereintritt zuerst: Wer schon dabei ist, meldet sich nicht neu an --
    -- sonst stuende er nach einem Absturz zweimal im Baum.
    local pid, how = session:findReturning(payload.name, payload.clientId)

    if pid then
        -- Ein zweiter Rechner mit derselben Kennung waehrend der erste noch
        -- haengt: Der alte Peer fliegt, der neue uebernimmt. Zwei Verbindungen
        -- auf einen Teilnehmer waeren zwei Absender fuer eine Bereitmeldung.
        local old = self.peerOf[pid]
        if old and old ~= peer then
            local oldRecord = self.peers[old]
            if oldRecord then oldRecord.pid = nil end
            pcall(function() old:disconnect_later(0) end)
        end
        self.stats.rejoins = self.stats.rejoins + 1
    else
        if not session:isSetup() then
            -- E-03: Nachtraeglicher Beitritt nur bis zum Start von Runde 1.
            self:reject(peer, Protocol.REJECT.RUNNING,
                "Das Turnier laeuft schon. Freies Spiel geht weiter -- "
                .. "beim naechsten Turnier bist du dabei.")
            return
        end
        local err
        pid, err = session:addParticipant(payload.name, now, payload.clientId)
        if not pid then
            self:reject(peer, Protocol.REJECT.FULL, err or "Anmeldung abgelehnt.")
            return
        end
        self.stats.joins = self.stats.joins + 1
    end

    record.pid      = pid
    record.clientId = payload.clientId
    record.name     = session:nameOf(pid)
    self.peerOf[pid] = peer
    self.sentUpTo[peer] = 0

    session:setPresence(pid, true)

    self:send(peer, Protocol.MSG.TOURNAMENT_WELCOME, {
        participantId  = pid,
        name           = record.name,
        tournamentName = session.t.name,
        logCount       = #session.t.log,
    })
    self:pushLog(peer)

    -- Wer mitten in ein aufgerufenes Match hineinkommt, muss sofort erfahren,
    -- dass er dran ist -- der No-Show-Timer laeuft schon.
    self:announceAssignments(now)

    self.onEvent("join", pid, record.name, how or "new")
end

function TournamentHost:reject(peer, reason, text)
    self:send(peer, Protocol.MSG.REJECT, { reason = reason, text = text })
    pcall(function() peer:disconnect_later(0) end)
end

function TournamentHost:dropPeer(peer)
    local record = self.peers[peer]
    self.peers[peer] = nil
    self.sentUpTo[peer] = nil
    if not record or not record.pid then return end

    local pid = record.pid
    if self.peerOf[pid] == peer then self.peerOf[pid] = nil end

    -- Anwesenheit ist Laufzeit, kein Log-Ereignis (ADR-021). Der Scheduler
    -- macht daraus E-16, wenn das Match sonst spielbar waere.
    if self.session then self.session:setPresence(pid, false) end
    self.choice:forget(pid)

    -- Ist das der Wirt eines laufenden Matches, laeuft ab jetzt die Frist aus
    -- §8. Vorher gibt es keinen Grund, ein Ergebnis zu vermissen.
    for matchId, a in pairs(self.assigned) do
        if a.host == pid then
            local m = self.session and self.session.t.matches[matchId]
            if m and m.status == Model.STATUS.LIVE and not self.lostSince[matchId] then
                self.lostSince[matchId] = self:now()
            end
        end
    end

    self.onEvent("leave", pid, record.name)
end

-- ---------------------------------------------------------------------------
-- Ein Match ansetzen (§8, ADR-022)
--
-- Zwei Schritte, und die Reihenfolge ist der Grund, aus dem die Wahl des
-- Match-Wirts gemerkt wird (`HostChoice:decideFor`):
--
--   1. AUFRUF. Beide erfahren ihre Rolle. Der kuenftige Wirt oeffnet daraufhin
--      einen Wirt auf `*:0` und meldet seinen Port mit `MATCH_ACCEPT`.
--   2. ADRESSE. Sobald der Port da ist, bekommt der Gast eine zweite
--      Zuweisung -- diesmal mit "wohin".
--
-- Wuerde die Wahl in Schritt 2 neu gerechnet, koennte sie inzwischen gekippt
-- sein und der Gast verbaende sich zu einem Rechner, der nicht mehr hostet.
-- ---------------------------------------------------------------------------

function TournamentHost:announceAssignments(now)
    local session = self.session
    if not session then return end
    local t = session.t

    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if m.status == Model.STATUS.READY and m.slotA and m.slotB then
            local hostPid = self.choice:decideFor(m, t, now)
            local a = self.assigned[id]
            if not a or a.host ~= hostPid then
                a = { host = hostPid, told = {}, toldAt = {}, accepted = {} }
                self.assigned[id] = a
            end

            for _, pid in ipairs({ m.slotA, m.slotB }) do
                local isHost = (pid == hostPid)
                -- Der Gast bekommt die Zuweisung zweimal: einmal ohne
                -- Adresse (damit er weiss, dass er dran ist) und einmal mit,
                -- sobald der Wirt seinen Port gemeldet hat.
                local stamp = isHost and "host" or tostring(a.address or "")
                local stale = a.told[pid] == stamp and not a.accepted[pid]
                              and (now - (a.toldAt[pid] or 0)) >= TournamentHost.ASSIGN_RETRY_SECONDS
                if a.told[pid] ~= stamp or stale then
                    local payload = {
                        matchId  = id,
                        role     = isHost and Protocol.ROLE.HOST or Protocol.ROLE.GUEST,
                        opponent = session:nameOf(pid == m.slotA and m.slotB or m.slotA),
                        address  = (not isHost) and (a.address or "") or "",
                        bestOf   = m.bestOf or 1,
                    }
                    if pid == self.selfPid then
                        -- Der Turnierleiter spielt mit. Er bekommt dieselbe
                        -- Zuweisung wie alle anderen, nur ohne den Umweg ueber
                        -- das Netz -- er redet nicht mit sich selbst. Damit
                        -- hat die Szene EINEN Weg fuer beide Rollen statt
                        -- zweier, die auseinanderlaufen koennen.
                        a.told[pid], a.toldAt[pid] = stamp, now
                        self.onEvent("assign", payload)
                    elseif self:sendTo(pid, Protocol.MSG.TOURNAMENT_ASSIGN, payload) then
                        a.told[pid], a.toldAt[pid] = stamp, now
                    end
                end
            end
        elseif self.assigned[id] and m.status ~= Model.STATUS.LIVE then
            -- Aufruf zurueckgenommen (Walkover, Abbruch): Die Zuweisung gilt
            -- nicht mehr, und die naechste wird neu gemessen.
            self.assigned[id] = nil
            self.lostSince[id] = nil
            self.queried[id] = nil
            self.choice:forgetMatch(id)
        end
    end
end

-- Der Turnier-Wirt hostet sein eigenes Match (ADR-022, RTT null). Dann kommt
-- sein Port nicht ueber `MATCH_ACCEPT` herein -- er redet nicht mit sich
-- selbst -- und muss trotzdem beim Gegner ankommen.
--
-- Angeschrieben wird er als ":PORT", ohne Rechnerteil. Das ist kein Kuerzel,
-- sondern die einzige Angabe, die hier sicher stimmt: Welche seiner eigenen
-- Adressen der Turnier-Wirt anschreiben muesste, weiss er bei mehreren
-- Netzwerkkarten nicht -- der Gast dagegen hat bereits einen funktionierenden
-- Weg zu ihm und setzt ihn davor (`tournament_client.lua`).
function TournamentHost:hostSelfMatch(matchId, port)
    local a = self.assigned[matchId]
    if not a then return false, "Match ist nicht aufgerufen" end
    if a.host ~= self.selfPid then return false, "der Wirt ist ein anderer" end
    a.address = ":" .. tostring(math.floor(port or 0))
    self:announceAssignments(self:now())
    return true
end

function TournamentHost:onAccept(record, payload)
    local session = self.session
    if not session or not record.pid then return end
    local id = payload.matchId
    local a  = self.assigned[id]
    if not a then return end

    if a.host == record.pid and payload.enetPort and payload.enetPort > 0 then
        -- Die IP kommt aus der Sicht des Turnier-Wirts auf diesen Peer, der
        -- Port aus der Meldung: Der Quellport des Peers gehoert zu SEINEM
        -- Client-Socket, nicht zu dem Wirt, den er gerade geoeffnet hat.
        local ip = tostring(record.peer):match("^([^:]+)")
        a.address = string.format("%s:%d", ip or "127.0.0.1", payload.enetPort)
    end

    if payload.ready then
        -- Angenommen heisst: nicht mehr wiederholen. Ohne diese Zeile ginge
        -- die Zuweisung alle zwei Sekunden erneut hinaus.
        a.accepted[record.pid] = true
        session:confirmReady(id, record.pid, self:now())
        return
    end

    -- RUECKNAHME (C-T-13): Jemand hat sein Match verlassen. Zwei Faelle, und
    -- der Unterschied ist der zwischen "wartet noch" und "war schon dabei".
    a.accepted[record.pid] = nil
    a.told[record.pid] = nil          -- damit die Zuweisung erneut hinausgeht

    local m = session.t.matches[id]
    if m and m.status == Model.STATUS.LIVE and a.host == record.pid then
        -- Der MATCH-WIRT ist weg, also ist das Match weg. E-06: neu ansetzen,
        -- kein Walkover -- ein Abbruch ist nicht die Schuld eines Spielers.
        self.assigned[id] = nil
        self.lostSince[id] = nil
        self.queried[id] = nil
        self.choice:forgetMatch(id)
        self.stats.aborts = self.stats.aborts + 1
        session:abortMatch(id, self:now())
        self.onEvent("match_lost", id)
        return
    end

    -- Ein GAST ist gegangen. Laeuft das Match schon, gehoert es ihm weiterhin:
    -- Der Match-Wirt pausiert und haelt ihm 30 s frei (`04_NETCODE` §12), und
    -- die erneut geschickte Zuweisung ist genau der Weg zurueck. Kommt er
    -- nicht, endet es dort per Walkover.
    self.onEvent("match_left", id, record.pid)
end

function TournamentHost:onReport(record, payload)
    local session = self.session
    if not session or not record.pid then return end

    local a = self.assigned[payload.matchId]
    -- E-08: Das Ergebnis kommt vom Match-Wirt, nicht von einem Spieler. Wer
    -- nicht der Wirt dieses Matches ist, meldet nichts -- sonst waere die
    -- Zusicherung "kann nicht auftreten" nur eine Absichtserklaerung.
    if not a or a.host ~= record.pid then
        self.onEvent("report_rejected", payload.matchId, record.pid)
        return
    end

    self.stats.reports = self.stats.reports + 1
    self.lostSince[payload.matchId] = nil
    self.queried[payload.matchId] = nil

    local stats = nil
    if payload.longestRally and payload.longestRally > 0
       or (payload.fastestBall and payload.fastestBall > 0) then
        stats = { longestRally = payload.longestRally,
                  fastestBall  = payload.fastestBall,
                  fastestBy    = payload.fastestBy }
    end

    local ok, err = session:enterResult(payload.matchId, payload.sets,
        self:now(), stats)
    if ok then
        self.assigned[payload.matchId] = nil
        self.choice:forgetMatch(payload.matchId)
    end
    self.onEvent("result", payload.matchId, ok, err)
end

-- ---------------------------------------------------------------------------
-- Takt
-- ---------------------------------------------------------------------------

function TournamentHost:update(now)
    now = now or self:now()
    self:service()
    if self.discovery then self.discovery:update() end

    if self.session then
        -- Der Turnier-Wirt spielt mit: null Netzspruenge zu sich selbst.
        if self.selfPid then self.choice:sampleSelf(self.selfPid, now) end
        -- `advance` und nicht `tick`: Der Automat soll laufen, der
        -- EREIGNISSTROM aber der Szene gehoeren. Wer ihn hier leert, nimmt
        -- dem Turnierleiter den Aufrufton -- derselbe Grund, aus dem die
        -- Trennung in Stufe B entstanden ist (CC-05_REPORT §1a, Punkt 1).
        self.session:advance(now)
        self:announceAssignments(now)
        self:checkMissingResults(now)
        self:pushLogToAll()
    end

    if now - self.lastPingAt >= TournamentHost.PING_INTERVAL then
        self.lastPingAt = now
        for peer, record in pairs(self.peers) do
            if record.pid then
                self:send(peer, Protocol.MSG.PING,
                    { timestamp = math.floor(now * 1000) })
            end
        end
    end
end

-- §8: nach 60 s nachfragen, danach E-06. Die Frist laeuft ab dem Moment, in
-- dem der Match-Wirt weg ist -- nicht ab dem Matchstart. Ein Match dauert vier
-- Minuten, und ein Timer, der waehrend des Spiels laeuft, bricht gesunde
-- Matches ab.
function TournamentHost:checkMissingResults(now)
    local session = self.session
    for matchId, since in pairs(self.lostSince) do
        local m = session.t.matches[matchId]
        if not m or m.status ~= Model.STATUS.LIVE then
            self.lostSince[matchId] = nil
            self.queried[matchId] = nil
        elseif now - since >= TournamentHost.RESULT_GIVEUP_SECONDS then
            self.lostSince[matchId] = nil
            self.queried[matchId] = nil
            self.assigned[matchId] = nil
            self.choice:forgetMatch(matchId)
            self.stats.aborts = self.stats.aborts + 1
            -- E-06: kein Walkover. Der Absturz ist nicht die Schuld eines
            -- Spielers, das Match wird neu angesetzt.
            session:abortMatch(matchId, now)
            self.onEvent("match_lost", matchId)
        elseif now - since >= TournamentHost.RESULT_QUERY_SECONDS
               and not self.queried[matchId] then
            -- Genau einmal fragen. Der Wirt ist entweder wieder da und
            -- antwortet, oder er ist es nicht -- eine Nachfrage je Sekunde
            -- aendert daran nichts und fuellt nur das Log.
            local a = self.assigned[matchId]
            if a and self:sendTo(a.host, Protocol.MSG.RESULT_QUERY,
                                 { matchId = matchId }) then
                self.queried[matchId] = true
                self.stats.queries = self.stats.queries + 1
            end
        end
    end
end

function TournamentHost:close()
    if self.discovery then pcall(function() self.discovery:close() end) end
    self.discovery = nil
    if not self.server then return end
    for peer in pairs(self.peers) do
        pcall(function() peer:disconnect_now(0) end)
    end
    pcall(function() self.server:flush() end)
    pcall(function() self.server:destroy() end)
    self.server = nil
end

return TournamentHost
