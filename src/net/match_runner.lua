-- ============================================================================
-- src/net/match_runner.lua -- die Netzseite EINES Turniermatches (M4-09)
--
-- `05_TOURNAMENT` §8. Ein Turniermatch IST ein Netzmatch: Es benutzt
-- `src/net/host.lua` und `src/net/client.lua` unveraendert. Neu ist nur, wer
-- es anstoesst und wohin das Ergebnis geht -- und genau das steht hier.
--
-- ---------------------------------------------------------------------------
-- Was hier NICHT passiert
-- ---------------------------------------------------------------------------
--
-- Simuliert wird nicht. Der feste Schritt gehoert zum Match und damit zu
-- `src/app/scenes/net_game.lua`, wie im freien Spiel auch. Diese Datei oeffnet
-- den Socket, haelt die Zuweisung fest und weiss, wem das Ergebnis gehoert.
--
-- ---------------------------------------------------------------------------
-- Warum nicht die Lobby-Szene aus M2
-- ---------------------------------------------------------------------------
--
-- `src/app/scenes/lobby.lua` verhandelt: freie Slots, Bereitschaftsschalter,
-- Ruleset-Abgleich. Ein Turniermatch hat daran nichts zu verhandeln -- die
-- Paarung kommt aus dem Bracket, das Ruleset ist beim Turnierstart eingefroren
-- (Datenmodell §4), und die Bereitmeldung geht an den Turnier-Wirt und nicht
-- an den Gegner. Eine zweite Instanz, die dasselbe anders entscheidet, waere
-- eine zweite Wahrheit. Wiederverwendet werden die BAUTEILE, nicht die Szene.
-- ============================================================================

local Host     = require("src.net.host")
local Client   = require("src.net.client")
local Protocol = require("src.net.protocol")

local MatchRunner = {}
MatchRunner.__index = MatchRunner

-- Der Match-Wirt. Er bindet einen EPHEMEREN Port und liest ihn zurueck --
-- der Turnier-Wirt haelt 21212, und zweimal derselbe Port geht in einem
-- Prozess nicht (`05_TOURNAMENT` §8.2).
function MatchRunner.newHost(opts)
    opts = opts or {}
    local host, err = Host.new({
        enet      = opts.enet,
        port      = 0,
        ruleset   = opts.ruleset,
        clock     = opts.clock,
        hostName  = opts.selfName,
        lobbyName = opts.matchLabel or "Turniermatch",
        buildHash = opts.buildHash,
        clientId  = opts.clientId,
        onEvent   = opts.onEvent,
    })
    if not host then return nil, err end

    return setmetatable({
        role    = "host",
        matchId = opts.matchId,
        host    = host,
        port    = host.port,
        opponent = opts.opponent,
        bestOf  = opts.bestOf or 1,
        sets    = {},
    }, MatchRunner)
end

-- Der Gast. Die Adresse kommt vom Turnier-Wirt: IP aus seiner Sicht auf den
-- Peer, Port aus der Meldung des Match-Wirts.
function MatchRunner.newGuest(opts)
    opts = opts or {}
    local ip, port = tostring(opts.address or ""):match("^(.+):(%d+)$")
    if not ip then return nil, "unbrauchbare Adresse: " .. tostring(opts.address) end

    local client, err = Client.new({
        enet      = opts.enet,
        address   = ip,
        port      = tonumber(port),
        clientId  = opts.clientId,
        name      = opts.selfName,
        buildHash = opts.buildHash,
        clock     = opts.clock,
        onEvent   = opts.onEvent,
    })
    if not client then return nil, err end

    return setmetatable({
        role     = "guest",
        matchId  = opts.matchId,
        client   = client,
        opponent = opts.opponent,
        bestOf   = opts.bestOf or 1,
        sets     = {},
    }, MatchRunner)
end

function MatchRunner:party()
    return self.host or self.client
end

function MatchRunner:update(dt)
    local party = self:party()
    if party then party:update(dt or 0) end
end

-- Ein Satz ist zu Ende. Best-of-3 sammelt, bis einer zwei hat -- gezaehlt wird
-- hier, damit der Turnier-Wirt eine fertige Satzliste bekommt und nicht drei
-- Einzelmeldungen zusammensetzen muss.
function MatchRunner:addSet(scoreA, scoreB)
    self.sets[#self.sets + 1] = { a = scoreA, b = scoreB }
    local a, b = 0, 0
    for _, s in ipairs(self.sets) do
        if s.a > s.b then a = a + 1 elseif s.b > s.a then b = b + 1 end
    end
    local need = math.floor(self.bestOf / 2) + 1
    return a >= need or b >= need
end

function MatchRunner:isHost() return self.role == "host" end

function MatchRunner:close()
    if self.host then self.host:close() end
    if self.client then self.client:close() end
    self.host, self.client = nil, nil
end

MatchRunner.END = Protocol.END

return MatchRunner
