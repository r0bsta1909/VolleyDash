-- ============================================================================
-- src/net/discovery.lua -- Lobbys finden, ohne eine IP zu tippen (M2-04)
--
-- UDP-Broadcast auf Port 21213 (ADR-003, `04_NETCODE_SPEC` §11). Zwei Rollen
-- in einer Datei, weil sie dasselbe Format sprechen:
--
--   Host     bindet 21213, sendet jede Sekunde ANNOUNCE an den Broadcast und
--            antwortet auf PROBE sofort -- UNICAST an den Fragenden.
--   Browser  bindet einen FLUECHTIGEN Port, sendet alle 2 s PROBE, sammelt
--            ANNOUNCE ein und raeumt Eintraege nach 5 s Stille weg.
--
-- Der Browser bindet 21213 ausdruecklich NICHT. Fassung 1.0 der Spec sah das
-- vor; damit koennen Host und Client nicht auf demselben Rechner laufen -- und
-- genau so testet M2-10 das Netzspiel reproduzierbar.
--
-- `settimeout(0)` bei jedem Socket, gepollt in `love.update`. Ein blockierender
-- Aufruf haelt die gesamte Hauptschleife an (CLAUDE.md §7). Kein Thread:
-- `t.modules.thread` ist in conf.lua aus, und die Datenmengen sind winzig.
-- ============================================================================

local Protocol = require("src.net.protocol")

local Discovery = {}
Discovery.__index = Discovery

Discovery.ANNOUNCE_INTERVAL = 1.0
Discovery.PROBE_INTERVAL    = 2.0
Discovery.ENTRY_TTL         = 5.0

Discovery.BROADCAST = "255.255.255.255"

-- Das zweite Ziel ist kein Ersatz, sondern eine Ergaenzung: ob ein Broadcast
-- auf demselben Rechner zurueckkommt, haengt am Betriebssystem. 30 Byte.
Discovery.LOCAL = "127.0.0.1"

-- Wie lange die eigene Adresse gilt, bevor sie neu ermittelt wird. Sie aendert
-- sich, wenn jemand das Kabel umsteckt oder das WLAN wechselt.
Discovery.ADDRESS_TTL = 10

-- AUSDRUECKLICH udp4, nicht udp.
--
-- `socket.udp()` liefert unter LuaSocket 3.0 (das in LOEVE 11.5 steckt) einen
-- IPv6-Socket. Ein Broadcast an "255.255.255.255" scheitert darauf mit
-- "Der angegebene Host ist unbekannt" -- gemessen, nicht vermutet. IPv4-
-- Broadcast gibt es unter IPv6 nicht; das Gegenstueck waere Multicast an
-- ff02::1 und damit eine andere Baustelle. Fuer ein LAN-Party-Segment ist
-- IPv4 die richtige und einzige Wahl (Annahme A1 im Charter).
local function newSocket(socket, port)
    local udp = (socket.udp4 or socket.udp)()
    if not udp then return nil, "kein UDP-Socket" end

    udp:settimeout(0)
    -- reuseaddr vor dem Bind: sonst scheitert der zweite Host auf derselben
    -- Maschine, und der Testaufbau aus M2-10 waere nicht moeglich.
    pcall(function() udp:setoption("reuseaddr", true) end)

    local ok, err = udp:setsockname("*", port or 0)
    if not ok then return nil, "Port " .. tostring(port) .. ": " .. tostring(err) end

    -- Muss nach dem Bind kommen und darf scheitern (manche Systeme verbieten
    -- Broadcast fuer nicht privilegierte Prozesse -- dann bleibt die manuelle
    -- IP-Eingabe, und die ist ohnehin Pflichtfeature).
    pcall(function() udp:setoption("broadcast", true) end)

    return udp
end

-- ---------------------------------------------------------------------------
-- Host
-- ---------------------------------------------------------------------------

function Discovery.newHost(opts)
    opts = opts or {}
    local socket = opts.socket or require("socket")

    local udp, err = newSocket(socket, opts.port or Protocol.PORT_DISCOVERY)
    if not udp then return nil, err end

    return setmetatable({
        role       = "host",
        udp        = udp,
        socketLib  = socket,
        port       = opts.port or Protocol.PORT_DISCOVERY,
        clock      = opts.clock or function() return love.timer.getTime() end,
        info       = opts.info or {},
        lastAnnounce = 0,
        stats      = { sent = 0, probes = 0, failed = 0 },
    }, Discovery)
end

function Discovery:announcePacket()
    local info = self.info
    return Protocol.encodeDiscovery(Protocol.MSG.ANNOUNCE, {
        hostId     = info.hostId or 0,
        hostName   = info.hostName or "Host",
        lobbyName  = info.lobbyName or "Volley Dash",
        buildHash  = info.buildHash or "",
        players    = info.players or 1,
        maxPlayers = info.maxPlayers or 2,
        mode       = info.mode or "free",
        enetPort   = info.enetPort or Protocol.PORT_ENET,
    })
end

function Discovery:sendTo(data, ip, port)
    local ok = self.udp:sendto(data, ip, port)
    if ok then
        self.stats.sent = self.stats.sent + 1
    else
        self.stats.failed = self.stats.failed + 1
    end
    return ok
end

-- ---------------------------------------------------------------------------
-- Wohin ein Rundruf geht
--
-- GEMESSEN im D2-Lauf am 2026-08-12: Ein Windows-Rechner fand den Mac als Host
-- nicht, umgekehrt klappte es. Der Unterschied liegt beim SENDER, nicht beim
-- Empfaenger -- in beiden Faellen war der Mac an derselben Buchse.
--
-- Die wahrscheinliche Ursache ist der eingeschraenkte Rundruf 255.255.255.255:
-- Er ist an keine Schnittstelle gebunden, und Windows waehlt die Schnittstelle
-- nach der Routentabelle. Auf einem Rechner mit VPN, Hyper-V, VirtualBox oder
-- WSL sind das gern vier Kandidaten, und das Paket verlaesst die falsche.
--
-- Deshalb geht jeder Rundruf ZUSAETZLICH an die Rundrufadresse des eigenen
-- Netzes (192.168.1.155 -> 192.168.1.255). Die ist an ein Netz gebunden und
-- wird von der Routentabelle richtig zugeordnet. Kosten: ein Paket von 30 Byte
-- mehr je Runde.
--
-- Angenommen wird dabei ein /24-Netz. Das ist bei jedem Heimrouter und jedem
-- LAN-Party-Switch so; wer in einem /16 spielt, hat den eingeschraenkten
-- Rundruf und die IP-Eingabe als Rueckfallebenen.
local function subnetBroadcast(address)
    local a, b, c = address:match("^(%d+)%.(%d+)%.(%d+)%.%d+$")
    if not a then return nil end
    if a == "127" then return nil end
    return a .. "." .. b .. "." .. c .. ".255"
end

function Discovery:targets()
    local now = self.clock()
    if not self.targetsAt or now - self.targetsAt > Discovery.ADDRESS_TTL then
        self.targetsAt = now
        self.address = Discovery.localAddress(self.socketLib)

        local list = { Discovery.BROADCAST, Discovery.LOCAL }
        local subnet = subnetBroadcast(self.address or "")
        if subnet then table.insert(list, 2, subnet) end
        self.targetList = list
    end
    return self.targetList
end

function Discovery:sendToAll(data, port)
    local count = 0
    for _, ip in ipairs(self:targets()) do
        if self:sendTo(data, ip, port) then count = count + 1 end
    end
    return count
end

-- Kurzfassung fuer die Anzeige. Wenn die Liste leer bleibt, ist das die Zahl,
-- die den Fehler eingrenzt: gesendet, aber nichts empfangen heisst, dass die
-- Frage nicht ankommt oder die Antwort nicht zurueck.
function Discovery:diagnostics()
    if self.role == "host" then
        return string.format("%s | %d Ankuendigungen, %d Anfragen beantwortet",
            tostring(self.address or "?"), self.stats.sent, self.stats.probes)
    end
    return string.format("%s | %d Anfragen, %d Antworten, %d fremd, %d Fehler, Port %s",
        tostring(self.address or "?"), self.stats.sent, self.stats.received,
        self.stats.foreign or 0, self.stats.failed,
        self.listener and tostring(self.port) or "nur fluechtig")
end

-- ---------------------------------------------------------------------------
-- Browser
-- ---------------------------------------------------------------------------

function Discovery.newBrowser(opts)
    opts = opts or {}
    local socket = opts.socket or require("socket")

    -- Port 0: das Betriebssystem sucht einen freien aus.
    local udp, err = newSocket(socket, 0)
    if not udp then return nil, err end

    -- ZWEITER Socket auf dem Discovery-Port, nur zum Zuhoeren.
    --
    -- GEMESSEN im D2-Lauf am 2026-08-12: Windows fand den Mac als Host nicht,
    -- umgekehrt schon. Aus den Daten folgt, dass der Rundruf des Macs den
    -- Windows-Rechner sehr wohl erreicht -- in der umgekehrten Rolle hat er
    -- ihn dort als Host beantwortet. Nur HOERTE der suchende Windows-Rechner
    -- nicht hin: er lauschte allein auf seinem fluechtigen Port und war damit
    -- auf die Unicast-Antwort angewiesen.
    --
    -- Mit diesem zweiten Socket bekommt der Browser auch die Ankuendigung, die
    -- der Host ohnehin jede Sekunde in die Runde schickt. Zwei unabhaengige
    -- Wege statt einem: faellt einer aus, traegt der andere.
    --
    -- Der Bind darf scheitern -- etwa, wenn auf diesem Rechner schon eine
    -- Lobby offen ist. Dann bleibt es beim fluechtigen Port.
    local listener = newSocket(socket, opts.port or Protocol.PORT_DISCOVERY)

    return setmetatable({
        role      = "browser",
        udp       = udp,
        listener  = listener,
        socketLib = socket,
        port      = opts.port or Protocol.PORT_DISCOVERY,
        clock     = opts.clock or function() return love.timer.getTime() end,
        entries   = {},
        lastProbe = -math.huge,
        stats     = { sent = 0, received = 0, failed = 0, foreign = 0 },
    }, Discovery)
end

function Discovery:probe()
    self:sendToAll(Protocol.encodeDiscovery(Protocol.MSG.PROBE, {}), self.port)
    self.lastProbe = self.clock()
end

-- Liste fuer die Anzeige, stabil sortiert. Stabil ist wichtig: eine Liste, in
-- der die Eintraege im Sekundentakt die Plaetze tauschen, waehlt man nicht
-- an -- man verfehlt sie (`04_NETCODE_SPEC` §11).
function Discovery:list()
    local out = {}
    for key, entry in pairs(self.entries) do
        entry.key = key
        out[#out + 1] = entry
    end
    table.sort(out, function(a, b)
        if a.lobbyName ~= b.lobbyName then return a.lobbyName < b.lobbyName end
        return a.key < b.key
    end)
    return out
end

function Discovery:prune()
    local now = self.clock()
    for key, entry in pairs(self.entries) do
        if now - entry.seenAt > Discovery.ENTRY_TTL then
            self.entries[key] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Gemeinsam
-- ---------------------------------------------------------------------------

-- Alles abholen, was da ist -- nicht ein Paket je Frame. Dieselbe Regel wie
-- bei ENet (§4): eine Queue, die langsamer geleert als gefuellt wird, waechst.
function Discovery:pollSocket(udp)
    local count = 0
    while true do
        local data, ip, port = udp:receivefrom()
        if not data then break end
        count = count + 1
        self:handle(data, ip, port)
        -- Ein Absender, der schneller schickt als wir lesen, darf den Frame
        -- nicht auffressen.
        if count > 64 then break end
    end
    return count
end

function Discovery:poll()
    local count = self:pollSocket(self.udp)
    -- Der Browser hoert zusaetzlich auf dem Discovery-Port mit, falls der
    -- Bind geklappt hat.
    if self.listener then count = count + self:pollSocket(self.listener) end
    return count
end

function Discovery:handle(data, ip, port)
    local msgType, payload = Protocol.decodeDiscovery(data)
    if not msgType then
        self.stats.foreign = (self.stats.foreign or 0) + 1
        return
    end

    if self.role == "host" and msgType == Protocol.MSG.PROBE then
        -- Sofortantwort, unicast an den Fragenden. Das ist der Weg, auf dem
        -- Host und Browser auf einem Rechner zueinander finden.
        self.stats.probes = self.stats.probes + 1
        self:sendTo(self:announcePacket(), ip, port)

    elseif self.role == "browser" and msgType == Protocol.MSG.ANNOUNCE then
        self.stats.received = self.stats.received + 1
        local port_ = payload.enetPort or Protocol.PORT_ENET

        -- Eine Lobby, ein Eintrag: laeuft der Host auf DIESEM Rechner,
        -- antwortet er zweimal -- ueber 127.0.0.1 und ueber die LAN-Adresse.
        -- Ohne die hostId stuende er zweimal in der Liste, und man waehlte
        -- einen der beiden aufs Geratewohl.
        local key = (payload.hostId and payload.hostId ~= 0)
            and ("id:" .. payload.hostId)
            or string.format("%s:%d", ip, port_)

        local entry = self.entries[key]
        local address = ip
        if entry and entry.address == Discovery.LOCAL then
            -- Die Loopback-Adresse gewinnt: sie kann nur von einem Host auf
            -- diesem Rechner stammen und ist dann der kuerzeste Weg.
            address = Discovery.LOCAL
        end

        self.entries[key] = {
            address    = address,
            port       = port_,
            hostId     = payload.hostId,
            hostName   = payload.hostName,
            lobbyName  = payload.lobbyName,
            buildHash  = payload.buildHash,
            players    = payload.players,
            maxPlayers = payload.maxPlayers,
            mode       = payload.mode,
            seenAt     = self.clock(),
        }
    end
end

function Discovery:update()
    self:poll()

    local now = self.clock()
    if self.role == "host" then
        if now - self.lastAnnounce >= Discovery.ANNOUNCE_INTERVAL then
            self.lastAnnounce = now
            self:sendToAll(self:announcePacket(), self.port)
        end
    else
        if now - self.lastProbe >= Discovery.PROBE_INTERVAL then self:probe() end
        self:prune()
    end
end

function Discovery:close()
    if self.udp then pcall(function() self.udp:close() end) end
    if self.listener then pcall(function() self.listener:close() end) end
    self.udp, self.listener = nil, nil
end

-- ---------------------------------------------------------------------------
-- Die eigene LAN-Adresse
--
-- Der Host zeigt sie gross in der Lobby an (§11): wenn der Broadcast nicht
-- durchkommt -- Firewall, WLAN-Client-Isolation, zwei Subnetze -- ist die
-- manuelle Eingabe der Weg, und dafuer muss jemand die Zahl vorlesen koennen.
--
-- `setpeername` auf UDP schickt kein Paket. Es waehlt nur die Route, und
-- danach steht in `getsockname` die Adresse der Schnittstelle, die das
-- Betriebssystem dafuer nehmen wuerde. Kein DNS, kein Verkehr, kein Warten --
-- `socket.dns.gethostname` liefert auf Rechnern mit mehreren Adaptern gern
-- die falsche.
-- ---------------------------------------------------------------------------
function Discovery.localAddress(socketLib)
    local socket = socketLib or require("socket")
    local udp = (socket.udp4 or socket.udp)()
    if not udp then return "?" end

    local ip
    local ok = pcall(function() udp:setpeername("8.8.8.8", 53) end)
    if ok then ip = udp:getsockname() end
    pcall(function() udp:close() end)

    if not ip or ip == "" or ip == "0.0.0.0" then return "?" end
    return ip
end

return Discovery
