-- ============================================================================
-- src/net/client.lua -- die zuschauende Seite (M2-03)
--
-- Der Client entscheidet NICHT (ADR-002). Er sendet seine Eingaben, empfaengt
-- Snapshots und reicht den jeweils neuesten an die Vollzustands-Vorhersage
-- weiter (`src/net/prediction.lua`, ADR-025) -- angezeigt wird deren lokal
-- fortgeschriebene Welt, neu aufgesetzt mit jedem Snapshot. Jitter erzeugt
-- damit keinen Anzeigeversatz mehr: Fehlt ein Snapshot einen Frame lang,
-- traegt die lokale Simulation das Bild, und der naechste setzt neu auf.
-- ============================================================================

local Protocol = require("src.net.protocol")
local Ruleset  = require("src.sim.ruleset")
local Lobby    = require("src.net.lobby")
local Checksum = require("src.net.checksum")

local Client = {}
Client.__index = Client

-- Einen Interpolationspuffer gibt es seit ADR-025 nicht mehr. Der Gast
-- simuliert die ganze Welt lokal vor (`src/net/prediction.lua`) und setzt sie
-- je Snapshot neu auf -- angezeigt wird stets der NEUESTE. Die Vorgeschichte
-- (2 Ticks Vorrat, umschaltbar, die Ratsche aus C-T-23) steht in
-- `04_NETCODE_SPEC` §8 und im ADR; hier waere sie nur ein Nachruf.
Client.PEER_TIMEOUT_MS = 5000
Client.PING_INTERVAL = 0.5
Client.CONNECT_TIMEOUT = 5

-- Wie viele halbe Pruefsummen offen bleiben duerfen. Bei 30 Ticks Abstand
-- sind acht Eintraege vier Sekunden Vorrat -- genug, damit ein verlorener
-- Snapshot erst dann als fehlend zaehlt, wenn er sicher nicht mehr kommt.
Client.HASH_MEMORY = 8

function Client.new(opts)
    opts = opts or {}
    local enet = opts.enet or require("enet")

    local peerHost, err = enet.host_create(nil, 1, Protocol.CHANNELS)
    if not peerHost then
        return nil, "kein Netzwerk-Socket: " .. tostring(err)
    end

    local address = string.format("%s:%d", opts.address or "127.0.0.1",
        opts.port or Protocol.PORT_ENET)

    local ok, peer = pcall(function()
        return peerHost:connect(address, Protocol.CHANNELS)
    end)
    if not ok or not peer then
        pcall(function() peerHost:destroy() end)
        return nil, "Adresse unbrauchbar: " .. tostring(opts.address)
    end

    local self = setmetatable({
        enet      = enet,
        host      = peerHost,
        peer      = peer,
        address   = opts.address or "127.0.0.1",
        port      = opts.port or Protocol.PORT_ENET,
        clientId  = opts.clientId or 0,
        name      = opts.name or "Gast",
        buildHash = opts.buildHash or "",
        clock     = opts.clock or function() return love.timer.getTime() end,
        onEvent   = opts.onEvent or function() end,

        state     = "connecting",   -- connecting | lobby | playing | ended | failed
        message   = "",
        slot      = nil,
        lobbySlots = {},
        hostName  = "",
        lobbyName = "",
        ruleset   = nil,            -- kommt per RULESET_FULL vom Host
        rulesetHash = nil,
        findings  = {},

        snapshots = {},
        latest    = nil,
        tick      = 0,              -- eigene Tickzaehlung fuer INPUT
        masks     = { 0, 0, 0 },

        startedAt = nil,
        lastPingAt = 0,
        rtt       = 0,
        stats     = { received = 0, applied = 0, held = 0, dropped = 0, lastDrain = 0,
                      checked = 0, desync = 0, missing = 0 },

        -- Desync-Detektor (§9): eigener Hash je Pruefsummen-Tick, bis die
        -- Angabe des Hosts eintrifft.
        hashes    = {},
        hashOrder = {},
    }, Client)

    self.startedAt = self:now()
    return self
end

function Client:now() return self.clock() end

function Client:send(msgType, payload)
    if not self.peer then return false end
    local ok, data = pcall(Protocol.encode, msgType, payload)
    if not ok then
        print("[client] " .. tostring(data))
        return false
    end
    self.peer:send(data, Protocol.channelOf(msgType), Protocol.flagOf(msgType))
    return true
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

-- Auch hier vollstaendig leeren: bei 60 Snapshots je Sekunde staut sich die
-- Queue sonst binnen Sekunden auf (§4, T-N-08).
function Client:service()
    local count = 0
    local event = self.host:service(0)
    while event do
        self:handle(event)
        count = count + 1
        event = self.host:service(0)
    end
    self.stats.lastDrain = count
    return count
end

function Client:handle(event)
    if event.type == "connect" then
        event.peer:timeout(32, Client.PEER_TIMEOUT_MS, Client.PEER_TIMEOUT_MS)
        self:send(Protocol.MSG.HELLO, {
            clientId = self.clientId, buildHash = self.buildHash, name = self.name,
        })

    elseif event.type == "receive" then
        self:receive(event.data)

    elseif event.type == "disconnect" then
        self.peer = nil
        if self.state ~= "ended" then
            self:fail("Verbindung zum Host verloren.")
        end
    end
end

function Client:fail(text)
    self.state = "failed"
    self.message = text
    self.onEvent("failed", text)
end

function Client:receive(data)
    local msgType, payload = Protocol.decode(data)
    if not msgType then return end

    if msgType == Protocol.MSG.WELCOME then
        self.slot        = payload.slot
        self.rulesetHash = payload.rulesetHash
        self.hostName    = payload.hostName
        self.lobbyName   = payload.lobbyName
        self.state       = "lobby"
        self.onEvent("welcome", payload.slot)

    elseif msgType == Protocol.MSG.REJECT then
        self:fail(payload.text ~= "" and payload.text or "Der Host hat abgelehnt.")
        self.state = "failed"

    elseif msgType == Protocol.MSG.TOURNAMENT_WELCOME then
        -- Die Gegenstelle ist ein TURNIER-Wirt, keine Match-Lobby. Das
        -- passiert genau auf einem Weg: Die Adresse wurde von Hand getippt
        -- (`04_NETCODE` §11), und beim Tippen weiss niemand, was auf 21212
        -- antwortet -- die Bake, die es sagen wuerde, kommt ja gerade nicht
        -- durch. HELLO ist fuer beide Wirte dasselbe (F-T-08), also steht die
        -- Antwort erst jetzt fest. Die Szene wechselt daraufhin das Protokoll
        -- (AP-2, C-T-22); dieselbe `clientId` macht daraus druben einen
        -- Wiedereintritt, keinen Doppelgaenger.
        self.onEvent("tournament", payload.tournamentName)

    elseif msgType == Protocol.MSG.RULESET_FULL then
        self:acceptRuleset(payload.ruleset)

    elseif msgType == Protocol.MSG.LOBBY_STATE then
        self.lobbySlots = payload.slots
        self:compareBuild()
        self.onEvent("lobby")

    elseif msgType == Protocol.MSG.MATCH_START then
        self:onMatchStart(payload)

    elseif msgType == Protocol.MSG.SNAPSHOT then
        self.stats.received = self.stats.received + 1
        self.snapshots[#self.snapshots + 1] = payload
        self.latest = payload
        self:rememberHash(payload)

    elseif msgType == Protocol.MSG.CHECKSUM then
        self:compareChecksum(payload)

    elseif msgType == Protocol.MSG.MATCH_END then
        -- Zurueck in die Lobby, nicht "ended": die Verbindung steht weiter,
        -- und das naechste Match soll keinen neuen Handschlag kosten.
        self.state = "lobby"
        self.onEvent("end", payload.scoreA, payload.scoreB, payload.reason)

    elseif msgType == Protocol.MSG.MATCH_PAUSE then
        self.onEvent("pause", payload.paused, payload.secondsLeft, payload.text)

    elseif msgType == Protocol.MSG.PING then
        self:send(Protocol.MSG.PONG, { timestamp = payload.timestamp })

    elseif msgType == Protocol.MSG.PONG then
        self.rtt = math.max(0, self:now() * 1000 - payload.timestamp)
    end
end

-- Das Ruleset kommt vom Host und ersetzt das eigene (ADR-005). Ungueltige
-- Werte werden nicht uebernommen -- sonst rechnet der Client mit einer Physik,
-- die es nirgends gibt.
function Client:acceptRuleset(values)
    local rs = Ruleset.new("prototype", values)
    local ok, errors = Ruleset.validate(rs)
    if not ok then
        self:fail("Der Host schickt ein unbrauchbares Regelwerk: "
                  .. tostring(errors[1]))
        return
    end
    self.ruleset = rs
    self.onEvent("ruleset", rs)
end

-- Drei Pruefungen, drei Konsequenzen (M2-07). Der Build-Hash ist die einzige
-- der drei, die nur warnt.
function Client:compareBuild()
    local hostSlot = self.lobbySlots[Lobby.HOST_SLOT]
    if not hostSlot or hostSlot.buildHash == "" then return end

    self.findings = Lobby.compare(
        { protoVersion = Protocol.VERSION, rulesetHash = self.rulesetHash,
          buildHash = hostSlot.buildHash },
        { protoVersion = Protocol.VERSION, rulesetHash = self.rulesetHash,
          buildHash = self.buildHash })
end

function Client:onMatchStart(payload)
    -- Der Abgleich aus §10: der Hash des empfangenen Rulesets gegen den, den
    -- der Host beim Start nennt. Weichen sie ab, startet das Match nicht --
    -- Klartext, kein stiller Fehlstart.
    local mine = self.ruleset and Ruleset.hash(self.ruleset) or "(keins)"
    if mine ~= payload.rulesetHash then
        self:fail(string.format(
            "Regelwerk weicht ab (Host %s, hier %s). Das Match startet nicht.",
            tostring(payload.rulesetHash), tostring(mine)))
        return
    end

    self.slot = payload.slot
    self.tick = 0
    self.masks = { 0, 0, 0 }
    self.snapshots = {}
    -- Der Host faengt seine Tickzaehlung neu an; alte Pruefsummen wuerden
    -- sonst auf die Ticks des neuen Matches passen.
    self.hashes, self.hashOrder = {}, {}
    self.state = "playing"
    self.onEvent("start", payload.matchId, payload.slot)
end

-- ---------------------------------------------------------------------------
-- Desync-Detektor (M3-03, §9, ADR-018)
--
-- Der Snapshot wird aus der GELESENEN Tabelle erneut gepackt. Nur so prueft
-- der Vergleich das Lesen; die empfangenen Rohbytes waeren eine Tautologie.
-- Gerechnet wird nur auf den Ticks, auf denen auch der Host rechnet -- das
-- ist zweimal je Sekunde statt sechzigmal.
--
-- DIE PRUEFSUMME KOMMT IN DER REGEL ZUERST. Sie laeuft ueber Kanal 0
-- (zuverlaessig), der Snapshot ueber Kanal 1 (unzuverlaessig, §4) -- und
-- zwischen zwei ENet-Kanaelen gibt es keine Reihenfolge. Gemessen im
-- Loopback, wo sie AUSNAHMSLOS vorlief. Wer hier auf die eine Richtung baut,
-- bekommt einen Detektor, der nie etwas prueft und trotzdem gruen meldet.
--
-- Deshalb: beide Haelften landen im selben Eintrag, verglichen wird, sobald
-- die zweite da ist. Was beim Verdraengen nur die Pruefsumme hat, war ein
-- verlorener Snapshot -- das ist Paketverlust, kein Befund.
-- ---------------------------------------------------------------------------

function Client:hashEntry(tick)
    local entry = self.hashes[tick]
    if entry then return entry end

    entry = {}
    self.hashes[tick] = entry
    self.hashOrder[#self.hashOrder + 1] = tick

    while #self.hashOrder > Client.HASH_MEMORY do
        local oldest = table.remove(self.hashOrder, 1)
        local dropped = self.hashes[oldest]
        self.hashes[oldest] = nil
        if dropped and dropped.theirs and not dropped.mine then
            self.stats.missing = self.stats.missing + 1
        end
    end

    return entry
end

function Client:settleHash(tick, entry)
    if not (entry.mine and entry.theirs) then return end

    self.hashes[tick] = nil
    for i = #self.hashOrder, 1, -1 do
        if self.hashOrder[i] == tick then table.remove(self.hashOrder, i) end
    end

    self.stats.checked = self.stats.checked + 1
    if entry.mine ~= entry.theirs then
        self.stats.desync = self.stats.desync + 1
        self.onEvent("desync", tick, entry.mine, entry.theirs)
    end
end

function Client:rememberHash(snap)
    if not Checksum.due(snap.tick) then return end

    local ok, data = pcall(Protocol.encode, Protocol.MSG.SNAPSHOT, snap)
    if not ok then return end

    local entry = self:hashEntry(snap.tick)
    entry.mine = Checksum.ofBytes(data)
    self:settleHash(snap.tick, entry)
end

function Client:compareChecksum(payload)
    local entry = self:hashEntry(payload.tick)
    entry.theirs = payload.hash
    self:settleHash(payload.tick, entry)
end

-- ---------------------------------------------------------------------------
-- Eingaben
-- ---------------------------------------------------------------------------

-- Einmal je Simulationstick. Jedes Paket traegt die Masken der letzten drei
-- Ticks (§7); das kostet zwei Byte und macht Einzelverluste unsichtbar.
function Client:pushInput(mask)
    self.masks[3] = self.masks[2]
    self.masks[2] = self.masks[1]
    self.masks[1] = mask

    self:send(Protocol.MSG.INPUT, { tick = self.tick, masks = self.masks })
    self.tick = self.tick + 1
end

-- ---------------------------------------------------------------------------
-- Snapshots
--
-- Einer je Tick, aber erst, wenn der Puffer gefuellt ist. Kommt nichts, gibt
-- es nichts -- das Bild haelt an, statt zu springen.
-- ---------------------------------------------------------------------------

-- Der neueste vorliegende Snapshot -- alles davor ist veraltet (ADR-025).
--
-- `gehalten` zaehlt die Ticks, in denen KEIN neuer Snapshot vorlag und die
-- lokale Simulation das Bild allein getragen hat. `verworfen` zaehlt
-- uebersprungene, weil veraltete Snapshots -- im gesunden 60-Hz-Fluss sind
-- beide nahe null, und genau daran erkennt man den Fluss im F3-Overlay.
function Client:latestSnapshot()
    local queue = self.snapshots
    local count = #queue
    if count == 0 then
        self.stats.held = self.stats.held + 1
        return nil
    end

    local snap = queue[count]
    self.stats.dropped = self.stats.dropped + (count - 1)
    self.stats.applied = self.stats.applied + 1
    for i = count, 1, -1 do queue[i] = nil end
    return snap
end

function Client:bufferDepth()
    return #self.snapshots
end

-- ---------------------------------------------------------------------------
-- Takt
-- ---------------------------------------------------------------------------

function Client:update(dt)
    self:service()

    if self.state == "connecting"
       and self:now() - self.startedAt > Client.CONNECT_TIMEOUT then
        self:fail("Keine Antwort von " .. self.address .. ".")
        return
    end

    local now = self:now()
    if now - self.lastPingAt >= Client.PING_INTERVAL then
        self.lastPingAt = now
        self:send(Protocol.MSG.PING, { timestamp = math.floor(now * 1000) })
    end
end

function Client:setReady(ready)
    self:send(Protocol.MSG.SET_READY, { ready = ready })
end

function Client:peerRtt()
    if not self.peer then return nil end
    local ok, value = pcall(function() return self.peer:round_trip_time() end)
    return ok and value or nil
end

function Client:peerLoss()
    if not self.peer then return nil end
    local ok, value = pcall(function() return self.peer:packet_loss() end)
    return ok and (value / 65536) or nil
end

function Client:close()
    -- Reihenfolge wie in `host.lua`: erst hinausschieben, dann trennen.
    -- `disconnect_now` verwirft, was noch in der Warteschlange steht.
    if self.host then pcall(function() self.host:flush() end) end
    if self.peer then pcall(function() self.peer:disconnect_now(0) end) end
    if self.host then
        pcall(function() self.host:flush() end)
        pcall(function() self.host:destroy() end)
    end
    self.peer, self.host = nil, nil
end

return Client
