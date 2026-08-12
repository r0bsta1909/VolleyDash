-- ============================================================================
-- src/app/assets.lua -- Bilder, Klaenge, Schriften (M0-12)
--
-- Jede Datei ist optional. Fehlt sie, gibt der Lader `nil` zurueck und die
-- Zeichenschicht nimmt ihren prozeduralen Zweig -- das Spiel bleibt spielbar
-- (`10_LEGAL` §4, `ASSET_INVENTORY` §3).
--
-- Schriften werden einmal geladen und nicht mehr pro Frame erzeugt (B-08),
-- Klaenge liegen in einem Pool fester Groesse (F-04).
-- ============================================================================

local Assets = {}

Assets.images = {}
Assets.sounds = {}
Assets.fonts = {}

-- Vier Stimmen je Klang. Der Prototyp klonte bei jedem Abspielen eine neue
-- Quelle; bei einer Folge von Wandtreffern war das messbarer Allokationsdruck
-- (F-04). Vier reichen: mehr gleichzeitige Wandtreffer gibt es nicht, und wer
-- die fuenfte ausloest, ueberschreibt die aelteste.
Assets.POOL_VOICES = 4
local pool = {}

local FONT_SIZES = { 12, 13, 14, 16, 24, 32, 48 }

-- Seit M1-09 liegen alle Dateien unter assets/ statt in der Wurzel
-- (12_OPENSOURCE §2). Der Pfad steht genau hier einmal.
Assets.DIR = "assets/"

local function loadImage(name)
    local path = Assets.DIR .. name
    if love.filesystem.getInfo(path) then return love.graphics.newImage(path) end
    return nil
end

local function loadSound(name)
    local base = Assets.DIR .. name:gsub("%.%w+$", "")
    if love.filesystem.getInfo(base .. ".wav") then
        return love.audio.newSource(base .. ".wav", "static")
    end
    if love.filesystem.getInfo(base .. ".ogg") then
        return love.audio.newSource(base .. ".ogg", "static")
    end
    return nil
end

function Assets.load()
    -- bg.jpg war nie ein JPEG, sondern ein PNG mit falscher Endung
    -- (ASSET_INVENTORY §4). Seit M1-09 heisst die Datei, was sie ist.
    Assets.images.bg   = loadImage("bg.png")
    Assets.images.blob = loadImage("blob.png")
    Assets.images.ball = loadImage("ball.png")

    for _, name in ipairs({ "jump", "dash", "hit_blob", "hit_sand",
                            "hit_net", "hit_wall", "whistle", "whistle_end" }) do
        local sound = loadSound(name)
        Assets.sounds[name] = sound
        if sound then
            local voices = { sound }
            for _ = 2, Assets.POOL_VOICES do voices[#voices + 1] = sound:clone() end
            pool[name] = { voices = voices, next = 1 }
        end
    end

    for _, size in ipairs(FONT_SIZES) do
        Assets.fonts[size] = love.graphics.newFont(size)
    end
end

function Assets.font(size)
    -- Fallback, falls jemand eine Groesse benutzt, die nicht vorgeladen ist.
    Assets.fonts[size] = Assets.fonts[size] or love.graphics.newFont(size)
    return Assets.fonts[size]
end

function Assets.setFont(size)
    love.graphics.setFont(Assets.font(size))
end

-- Reihum durch den Pool. Keine Allokation zur Laufzeit, und bis zu vier
-- Stimmen desselben Klangs koennen sich ueberlagern.
function Assets.play(name, volume)
    local entry = pool[name]
    if not entry then return end

    local source = entry.voices[entry.next]
    entry.next = (entry.next % #entry.voices) + 1

    source:stop()
    source:setVolume(volume or 0.25)
    source:play()
end

return Assets
