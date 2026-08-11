-- ============================================================================
-- src/app/assets.lua -- Bilder, Klaenge, Schriften (M0-12)
--
-- Jede Datei ist optional. Fehlt sie, gibt der Lader `nil` zurueck und die
-- Zeichenschicht nimmt ihren prozeduralen Zweig -- das Spiel bleibt spielbar
-- (`10_LEGAL` §4, `ASSET_INVENTORY` §3).
--
-- Schriften werden einmal geladen und nicht mehr pro Frame erzeugt (B-08).
-- Der Sound-Pool aus F-04 fehlt noch; das ist M0-02.
-- ============================================================================

local Assets = {}

Assets.images = {}
Assets.sounds = {}
Assets.fonts = {}

local FONT_SIZES = { 12, 13, 14, 16, 24, 32, 48 }

local function loadImage(name)
    if love.filesystem.getInfo(name) then return love.graphics.newImage(name) end
    return nil
end

local function loadSound(name)
    local base = name:gsub("%.%w+$", "")
    if love.filesystem.getInfo(base .. ".wav") then
        return love.audio.newSource(base .. ".wav", "static")
    end
    if love.filesystem.getInfo(base .. ".ogg") then
        return love.audio.newSource(base .. ".ogg", "static")
    end
    return nil
end

function Assets.load()
    Assets.images.bg   = loadImage("bg.jpg") or loadImage("bg.png")
    Assets.images.blob = loadImage("blob.png")
    Assets.images.ball = loadImage("ball.png")

    for _, name in ipairs({ "jump", "dash", "hit_blob", "hit_sand",
                            "hit_net", "hit_wall", "whistle", "whistle_end" }) do
        Assets.sounds[name] = loadSound(name)
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

-- Klaenge werden pro Abspielen geklont, damit sich Wandtreffer ueberlagern
-- koennen. Der Pool dagegen ist F-04 und gehoert nach M0-02.
function Assets.play(name, volume)
    local sound = Assets.sounds[name]
    if not sound then return end
    local clone = sound:clone()
    clone:setVolume(volume or 0.25)
    clone:play()
end

return Assets
