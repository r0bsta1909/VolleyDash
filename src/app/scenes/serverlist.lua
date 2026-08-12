-- ============================================================================
-- src/app/scenes/serverlist.lua -- Lobbys suchen (M2-05)
--
-- Haelt den Discovery-Browser und reicht die Liste an die Anzeige weiter. Der
-- letzte Eintrag ist immer die manuelle IP-Eingabe -- Pflichtfeature, kein
-- Untermenue (`04_NETCODE_SPEC` §11).
-- ============================================================================

local Discovery  = require("src.net.discovery")
local ServerList = require("src.ui.serverlist")
local Prefs      = require("src.app.prefs")

local ServerListScene = {}
ServerListScene.__index = ServerListScene

function ServerListScene.new(app)
    local self = setmetatable({
        name = "serverlist",
        app  = app,
    }, ServerListScene)

    self.ui = ServerList.new({
        lastAddress = app.prefs.lastAddress,
        onBack      = function() app.leaveNet() end,
        onRefresh   = function() if self.browser then self.browser:probe() end end,
        onJoin      = function(address, port, typed)
            if typed then
                -- Wer eine Adresse getippt hat, tippt sie nach einem Absturz
                -- nicht gern noch einmal.
                app.prefs.lastAddress = typed
                Prefs.save(app.prefs)
            end
            app.joinLobby(address, port)
        end,
    })

    local browser, err = Discovery.newBrowser({})
    if browser then
        self.browser = browser
        browser:probe()
    else
        self.ui.status = "Discovery nicht moeglich: " .. tostring(err)
    end

    return self
end

function ServerListScene:update(dt)
    if not self.browser then return end

    self.browser:update()
    self.ui:setEntries(self.browser:list())

    local count = #self.browser.entries
    if count == 0 then
        self.ui.status = "Suche im LAN ..."
    else
        self.ui.status = count == 1 and "1 Lobby gefunden"
                                     or (count .. " Lobbys gefunden")
    end

    self.ui.diagnostics = self.browser:diagnostics()
end

function ServerListScene:draw()
    self.ui:draw()
end

function ServerListScene:keypressed(key)
    self.ui:keypressed(key)
end

function ServerListScene:textinput(text)
    self.ui:textinput(text)
end

function ServerListScene:leave()
    if self.browser then self.browser:close() self.browser = nil end
end

return ServerListScene
