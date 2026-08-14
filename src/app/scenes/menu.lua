-- ============================================================================
-- src/app/scenes/menu.lua -- das Menue als Szene (M0-12)
--
-- Liegt ueber dem Spiel statt es zu ersetzen: `transparent` sorgt dafuer,
-- dass die Szene darunter weiter gezeichnet wird. Sie bekommt kein `update`
-- mehr, also steht die Simulation -- das ist die Pause.
-- ============================================================================

local Menu  = require("src.ui.menu")
local Music = require("src.app.music")

local MenuScene = {}
MenuScene.__index = MenuScene

function MenuScene.new(app)
    local self = setmetatable({
        name = "menu",
        app = app,
        transparent = true,
    }, MenuScene)

    self.menu = Menu.new({
        prefs    = app.prefs,
        bindings = app.bindings,
        ruleset  = app.ruleset,
        onLaunch = function(vsBot) app.startMatch(vsBot) end,
        onHost   = function() app.hostLobby() end,
        onBrowse = function() app.openServerList() end,
        onTournament = function() app.openTournament() end,
        playerName    = function() return app.playerName() end,
        setPlayerName = function(name) app.setPlayerName(name) end,
        onTweaker = function() app.openTweaker() end,
        onClose  = function() app.closeMenu() end,
        -- Seit ADR-024 beendet ESC ein Netzmatch nicht mehr. Der benannte Weg
        -- hinaus steht im Menue und raeumt die ganze Netzsitzung ab.
        onLeaveNet = function() app.leaveNet() end,
        onBindings = function() app.refreshBindings() end,
    })
    -- Liegt unter diesem Menue ein LAUFENDES Netzmatch? Dann steht kein Spiel
    -- still, und das Menue sagt das auch (ADR-024).
    self.menu.netMatch = app.netMatchBelowMenu()
    return self
end

-- Waehrend eines Matches ist ESC eine Pause -- dann schweigt auch die Musik.
-- Ohne laufendes Match ist das Menue der Normalzustand und die Menueliste
-- laeuft weiter.
function MenuScene:enter()
    if self.app.matchRunning() then
        Music.pause()
    elseif not self.app.netMatchBelowMenu() then
        -- Ueber einem NETZMATCH bleibt die Matchmusik an: das Match laeuft
        -- unter dem Menue weiter (ADR-024), nur die Tasten gehoeren dem
        -- Menue -- ein Rueckfall auf die Menueliste waere hier ein
        -- Musikwechsel mitten im Ballwechsel.
        Music.play("menu")
    end
end

function MenuScene:leave()
    if self.app.matchRunning() then Music.resume() end
end

function MenuScene:draw()
    -- Das Feld zeichnet die Szene darunter; hier kommt nur das Menue drauf.
    self.menu:draw(self.app.matchRunning())
end

function MenuScene:keypressed(key)
    self.menu:keypressed(key)
end

-- Getippter Text fuer den Nickname (M2). Ohne diesen Weg muesste die
-- Belegung aus `keypressed` erraten werden -- auf einer deutschen Tastatur
-- kaeme dabei Unsinn heraus.
function MenuScene:textinput(text)
    self.menu:textinput(text)
end

return MenuScene
