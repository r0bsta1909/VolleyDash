-- ============================================================================
-- src/app/music.lua -- Hintergrundmusik mit Shuffle-Playlist
--
-- Zwei Listen, nach Ordnern getrennt:
--
--     music/menu/     laeuft im Menue, startet automatisch beim Programmstart
--     music/match/    laeuft waehrend eines Matches
--     music/          lose Dateien hier gelten fuer beides
--
-- Titel werden **gestreamt**, nicht in den Speicher geladen: das RAM-Ziel
-- liegt bei 150 MB (CLAUDE.md §7), ein dekodiertes Lied allein waere schon
-- die Haelfte davon.
--
-- Ohne Dateien passiert nichts. Das Spiel laeuft dann still weiter -- genau
-- wie ohne Bilder und Klaenge (ASSET_INVENTORY §3).
-- ============================================================================

local Music = {}

Music.EXTENSIONS = { ogg = true, mp3 = true, flac = true, wav = true }
Music.FOLDER = "music"

local lists = { menu = {}, match = {} }
local current = {
    list = nil,      -- Name der laufenden Liste
    order = {},      -- gemischte Reihenfolge (Indizes in lists[name])
    position = 0,
    source = nil,
    lastTrack = nil, -- verhindert Wiederholung ueber das Mischen hinweg
}
local volume = 0.5
local enabled = true

local function isMusicFile(name)
    local ext = name:match("%.(%w+)$")
    return ext ~= nil and Music.EXTENSIONS[ext:lower()] == true
end

local function collect(path, into)
    if not love.filesystem.getInfo(path, "directory") then return end
    for _, name in ipairs(love.filesystem.getDirectoryItems(path)) do
        local full = path .. "/" .. name
        local info = love.filesystem.getInfo(full)
        if info and info.type == "file" and isMusicFile(name) then
            into[#into + 1] = full
        end
    end
end

-- `silent` schaltet die Musik ganz ab. Der Aufzeichnungsmodus benutzt das:
-- die Mischreihenfolge zieht aus demselben math.random wie der Bot, und eine
-- Referenzaufnahme soll von nichts abhaengen, was mit Musik zu tun hat.
function Music.load(silent)
    enabled = not silent
    lists.menu, lists.match = {}, {}

    local common = {}
    collect(Music.FOLDER, common)
    collect(Music.FOLDER .. "/menu", lists.menu)
    collect(Music.FOLDER .. "/match", lists.match)

    for _, path in ipairs(common) do
        lists.menu[#lists.menu + 1] = path
        lists.match[#lists.match + 1] = path
    end

    -- Damit die Reihenfolge nicht vom Dateisystem abhaengt.
    table.sort(lists.menu)
    table.sort(lists.match)
end

function Music.count(listName)
    return #(lists[listName] or {})
end

function Music.setVolume(value)
    volume = math.max(0, math.min(1, value or 0))
    if current.source then current.source:setVolume(volume) end
end

local function stopSource()
    if not current.source then return end
    current.source:stop()
    if current.source.release then current.source:release() end
    current.source = nil
end

-- Fisher-Yates. Beginnt die neue Runde mit demselben Titel wie die alte
-- endete, wird der erste getauscht -- zweimal dasselbe Lied hintereinander
-- faellt sofort auf.
local function shuffle(listName)
    local list = lists[listName]
    local order = {}
    for i = 1, #list do order[i] = i end
    for i = #order, 2, -1 do
        local j = math.random(1, i)
        order[i], order[j] = order[j], order[i]
    end
    if #order > 1 and list[order[1]] == current.lastTrack then
        order[1], order[2] = order[2], order[1]
    end
    current.order = order
    current.position = 0
end

local function playNext()
    local list = lists[current.list]
    if not list or #list == 0 then return end

    current.position = current.position + 1
    if current.position > #current.order then shuffle(current.list); current.position = 1 end

    local path = list[current.order[current.position]]
    stopSource()

    local ok, source = pcall(love.audio.newSource, path, "stream")
    if not ok or not source then
        print("[music] nicht abspielbar: " .. tostring(path))
        return
    end

    current.lastTrack = path
    current.source = source
    source:setVolume(volume)
    source:setLooping(false)
    source:play()
end

-- Startet eine Liste. Laeuft sie schon, passiert nichts -- so unterbricht ein
-- Menuewechsel den laufenden Titel nicht.
function Music.play(listName)
    if not enabled then return end
    if current.list == listName and current.source and current.source:isPlaying() then return end

    current.list = listName
    if Music.count(listName) == 0 then
        stopSource()
        return
    end
    shuffle(listName)
    playNext()
end

function Music.pause()
    if current.source and current.source:isPlaying() then current.source:pause() end
end

function Music.resume()
    if not enabled then return end
    if current.source and not current.source:isPlaying() then current.source:play() end
end

function Music.stop()
    current.list = nil
    stopSource()
end

function Music.skip()
    if not enabled or not current.list then return end
    playNext()
end

-- Einmal je Frame. Laeuft der Titel aus, kommt der naechste.
function Music.update()
    if not enabled or not current.list then return end
    if current.source and not current.source:isPlaying() then
        -- Pausierte Quellen melden ebenfalls "nicht spielend"; die werden
        -- ueber Music.resume fortgesetzt und nicht hier weitergeschaltet.
        if not current.paused then playNext() end
    end
end

-- Pause merken, damit update() den Titel nicht weiterschaltet.
local basePause, baseResume = Music.pause, Music.resume
function Music.pause() current.paused = true; basePause() end
function Music.resume() current.paused = false; baseResume() end

function Music.nowPlaying()
    if not current.source then return nil end
    return current.lastTrack
end

return Music
