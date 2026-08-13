-- ============================================================================
-- tests/tournament_helper.lua -- gemeinsames Werkzeug der M4-Suiten
--
-- Keine eigene Suite. Enthaelt die Zusicherungen und den Zeitraffer-Antrieb,
-- mit dem ein ganzes Turnier in einer Schleife durchlaeuft.
--
-- love-frei.
-- ============================================================================

local Model     = require("src.tournament.model")
local Bracket   = require("src.tournament.bracket")
local Scheduler = require("src.tournament.scheduler")

local H = {}

-- ---------------------------------------------------------------------------
-- Zusicherungen
-- ---------------------------------------------------------------------------

function H.assertEq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: erwartet %s, war %s",
            what or "Wert", tostring(expected), tostring(actual)), 2)
    end
end

function H.assertTrue(v, what)  H.assertEq(not not v, true,  what) end
function H.assertFalse(v, what) H.assertEq(not not v, false, what) end

function H.assertNear(actual, expected, tol, what)
    if math.abs(actual - expected) > (tol or 1e-9) then
        error(string.format("%s: erwartet %s +-%s, war %s",
            what or "Wert", tostring(expected), tostring(tol), tostring(actual)), 2)
    end
end

function H.assertList(actual, expected, what)
    H.assertEq(#actual, #expected, (what or "Liste") .. " Laenge")
    for i = 1, #expected do
        H.assertEq(actual[i], expected[i], string.format("%s[%d]", what or "Liste", i))
    end
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

function H.participantId(i) return string.format("p_%02d", i) end

-- Ein Turnier mit `n` Teilnehmern, noch ohne Auslosung.
function H.newTournament(n, config, opts)
    opts = opts or {}
    local t = Model.new({
        id          = opts.id or "t_test",
        name        = opts.name or "Testturnier",
        createdAt   = opts.createdAt or 1754900000,
        rulesetHash = opts.rulesetHash or "deadbeef",
        ruleset     = opts.ruleset or { targetScore = 15, netHeight = 160 },
        config      = config,
    })
    for i = 1, n do
        t:append({ event = "participant_joined", t = 0,
                   participantId = H.participantId(i),
                   name = string.format("Blob %02d", i) })
    end
    return t
end

-- Auslosen. `seedMode` steht auf `manual`, damit die Setzliste in den Tests
-- vorhersagbar ist: Teilnehmer 1 ist Setznummer 1.
function H.draw(t, opts)
    opts = opts or {}
    local ids = {}
    for i, pid in ipairs(t.participantOrder) do ids[i] = pid end

    local config = {}
    for k, v in pairs(t.config) do config[k] = v end
    config.format = t.format

    local draw = Bracket.draw(ids, config, {
        seedMode  = opts.seedMode or "manual",
        seedValue = opts.seedValue,
    })
    t:append({ event = "bracket_drawn", t = opts.at or 0, at = opts.at or 0, draw = draw })
    return draw
end

-- ---------------------------------------------------------------------------
-- Ergebnisse erfinden
-- ---------------------------------------------------------------------------

-- Saetze, mit denen `winnerId` gewinnt. Die Punktstaende sind unauffaellig
-- verschieden, damit Punktdifferenzen ueberhaupt entstehen koennen.
function H.setsFor(m, winnerId)
    local need = math.floor((m.bestOf or 1) / 2) + 1
    local target = m.targetScore or 15
    local sets = {}
    for i = 1, need do
        local loserScore = (i * 3) % (target - 2)
        if winnerId == m.slotA then sets[i] = { a = target, b = loserScore }
        else                        sets[i] = { a = loserScore, b = target } end
    end
    return sets
end

-- Standardergebnis: Der hoeher Gesetzte (kleinere Setznummer) gewinnt. Damit
-- ist der ganze Durchlauf reproduzierbar und der Sieger vorhersagbar.
function H.seedWins(t, m)
    return t:higherSeed(m.slotA, m.slotB)
end

-- ---------------------------------------------------------------------------
-- Zeitraffer
--
-- Ein Durchgang je Schleifendurchlauf: aufrufen, bestaetigen, melden. `now`
-- laeuft in festen Schritten -- die Zeit kommt aus dem Test, nie aus `os`.
-- ---------------------------------------------------------------------------

-- `opts.winnerOf(t, m)` bestimmt den Sieger, `opts.absent[pid]` haelt einen
-- Spieler offline, `opts.onTick(t, sched, now)` erlaubt Eingriffe.
function H.play(t, sched, opts)
    opts = opts or {}
    local now   = opts.start or 0
    local step  = opts.step or 10
    local limit = opts.limit or 20000
    local winnerOf = opts.winnerOf or H.seedWins
    local guard = 0

    while t.status == Model.TOURNAMENT_STATUS.RUNNING do
        guard = guard + 1
        if guard > limit then
            error("Turnier haengt: " .. H.describeOpen(t), 2)
        end

        if opts.onTick then opts.onTick(t, sched, now) end
        sched:update(now)

        for _, id in ipairs(t.matchOrder) do
            local m = t.matches[id]
            if m.status == Model.STATUS.READY then
                if not (opts.absent and opts.absent[m.slotA]) then
                    sched:confirmReady(id, m.slotA, now)
                end
                if not (opts.absent and opts.absent[m.slotB]) then
                    sched:confirmReady(id, m.slotB, now)
                end
            end
        end
        sched:update(now)

        for _, id in ipairs(t.matchOrder) do
            local m = t.matches[id]
            if m.status == Model.STATUS.LIVE then
                local winner = winnerOf(t, m)
                sched:reportResult(id, H.setsFor(m, winner), now)
            end
        end

        now = now + step
    end

    return now
end

-- Alle online melden.
function H.allOnline(t, sched, except)
    for _, pid in ipairs(t.participantOrder) do
        sched:setOnline(pid, not (except and except[pid]))
    end
end

function H.describeOpen(t)
    local parts = {}
    for _, id in ipairs(t.matchOrder) do
        local m = t.matches[id]
        if not Model.TERMINAL[m.status] then
            parts[#parts + 1] = string.format("%s(%s,R%d,%s/%s)",
                id, m.status, m.round, tostring(m.slotA), tostring(m.slotB))
        end
    end
    return table.concat(parts, " ") .. string.format(" [%d offen]", #parts)
end

-- ---------------------------------------------------------------------------
-- Auswertung
-- ---------------------------------------------------------------------------

function H.countByStatus(t)
    local counts = {}
    for _, id in ipairs(t.matchOrder) do
        local s = t.matches[id].status
        counts[s] = (counts[s] or 0) + 1
    end
    return counts
end

-- Matches, die tatsaechlich gespielt wurden -- Freilose zaehlen nicht.
function H.playedCount(t)
    local n = 0
    for _, id in ipairs(t.matchOrder) do
        if t.matches[id].status ~= Model.STATUS.BYE then n = n + 1 end
    end
    return n
end

-- Wie oft ist jedes Match `live` geworden? Aus dem Log, nicht aus dem Zustand.
function H.liveCounts(t)
    local counts = {}
    for _, ev in ipairs(t.log) do
        if ev.event == "match_started" then
            counts[ev.matchId] = (counts[ev.matchId] or 0) + 1
        end
    end
    return counts
end

function H.newScheduler(t, opts) return Scheduler.new(t, opts) end

-- ---------------------------------------------------------------------------
-- Ein Dateisystem im Speicher
--
-- Bildet die beiden Eigenschaften nach, die `05_TOURNAMENT` §7 zu vier statt
-- drei Schritten zwingen:
--   * Umbenennen ist die einzige Art, eine Datei zu verschieben
--   * `os.rename` UEBERSCHREIBT UNTER WINDOWS NICHT -- existiert das Ziel,
--     scheitert der Aufruf
--
-- Waere die Attrappe grosszuegiger als Windows, liefe der Test gruen und das
-- Turnier am Partyabend nicht.
-- ---------------------------------------------------------------------------
function H.fakeFs()
    local fs = { files = {}, dirs = {}, renames = 0, removes = 0, writes = 0 }

    fs.mkdir  = function(dir) fs.dirs[dir] = true return true end
    fs.exists = function(name) return fs.files[name] ~= nil end
    fs.read   = function(name) return fs.files[name] end

    fs.write = function(name, text)
        fs.writes = fs.writes + 1
        fs.files[name] = text
        return true
    end

    fs.remove = function(name)
        fs.removes = fs.removes + 1
        fs.files[name] = nil
        return true
    end

    fs.rename = function(from, to)
        if fs.files[from] == nil then return nil, "No such file or directory" end
        if fs.files[to]   ~= nil then return nil, "File exists" end   -- Windows
        fs.renames = fs.renames + 1
        fs.files[to], fs.files[from] = fs.files[from], nil
        return true
    end

    fs.list = function(dir)
        local out = {}
        for name in pairs(fs.files) do
            local rest = name:match("^" .. dir:gsub("%p", "%%%0") .. "/(.+)$")
            if rest then out[#out + 1] = rest end
        end
        table.sort(out)
        return out
    end

    -- Einen Absturz mitten im Schreiben nachstellen.
    fs.truncate = function(name, fraction)
        local text = fs.files[name]
        if not text then return false end
        fs.files[name] = text:sub(1, math.floor(#text * (fraction or 0.5)))
        return true
    end

    return fs
end

return H
