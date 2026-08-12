-- ============================================================================
-- src/ui/serverlist.lua -- die Liste der gefundenen Lobbys (M2-05)
--
-- Die manuelle IP-Eingabe ist PFLICHTFEATURE, nicht Notloesung
-- (`04_NETCODE_SPEC` §11). Sie steht als letzter Eintrag in dieser Liste, nicht
-- in einem Untermenue. Begruendung, damit sie niemand spaeter "aufraeumt":
-- Auf einer fremden Party ist die Firewall der Normalfall. Windows fragt beim
-- ersten Start nach der Freigabe, jemand klickt sie weg, und der Broadcast ist
-- tot -- fuer den ganzen Abend. Dieser eine Eintrag rettet ihn.
--
-- Die Liste kennt weder Discovery noch ENet. Sie bekommt Eintraege und meldet
-- eine Auswahl (`onJoin`), sonst nichts.
-- ============================================================================

local World  = require("src.sim.world")
local Assets = require("src.app.assets")

local ServerList = {}
ServerList.__index = ServerList

ServerList.MANUAL = "__manual__"

function ServerList.new(ctx)
    return setmetatable({
        ctx       = ctx,
        entries   = {},
        selection = 1,
        typing    = false,
        input     = ctx.lastAddress or "",
        status    = "Suche im LAN ...",
    }, ServerList)
end

-- Die Discovery-Liste plus der Pflichteintrag am Ende.
function ServerList:setEntries(entries)
    self.entries = entries or {}
    local count = #self.entries + 1
    if self.selection > count then self.selection = count end
    if self.selection < 1 then self.selection = 1 end
end

function ServerList:count()
    return #self.entries + 1
end

function ServerList:isManual(index)
    return index == self:count()
end

function ServerList:keypressed(key)
    if self.typing then
        if key == "escape" then
            self.typing = false
        elseif key == "backspace" then
            self.input = self.input:sub(1, -2)
        elseif key == "return" or key == "kpenter" then
            local address, port = self:parseAddress(self.input)
            if address then
                self.typing = false
                self.ctx.onJoin(address, port, self.input)
            else
                self.status = "Das ist keine Adresse: " .. self.input
            end
        end
        return true
    end

    if key == "escape" then
        self.ctx.onBack()
    elseif key == "up" then
        self.selection = math.max(1, self.selection - 1)
    elseif key == "down" then
        self.selection = math.min(self:count(), self.selection + 1)
    elseif key == "return" or key == "kpenter" then
        if self:isManual(self.selection) then
            self.typing = true
        else
            local entry = self.entries[self.selection]
            if entry then self.ctx.onJoin(entry.address, entry.port) end
        end
    elseif key == "f5" then
        self.ctx.onRefresh()
        self.status = "Suche erneut ..."
    end
    return true
end

function ServerList:textinput(text)
    if not self.typing then return end
    -- Nur, was in einer Adresse vorkommt. Sonst landen Umlaute und Leerzeichen
    -- in einem Feld, das gleich als Fehler zurueckkommt.
    if text:match("^[%d%.:a-zA-Z%-]$") and #self.input < 48 then
        self.input = self.input .. text
    end
end

-- "192.168.1.20" oder "192.168.1.20:21212". Gibt Adresse und Port zurueck.
function ServerList:parseAddress(text)
    text = (text or ""):gsub("%s", "")
    if text == "" then return nil end

    local address, port = text:match("^([^:]+):(%d+)$")
    if address then return address, tonumber(port) end

    -- Mindestanspruch: irgendetwas, das wie ein Name oder eine Zahlenfolge
    -- aussieht. Ob dahinter jemand horcht, sagt erst der Verbindungsversuch --
    -- und der meldet es im Klartext.
    if text:match("^[%w%.%-]+$") then return text end
    return nil
end

-- ---------------------------------------------------------------------------

function ServerList:draw()
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, World.WIDTH, World.HEIGHT)

    Assets.setFont(40)
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("SPIEL SUCHEN", 0, 60, World.WIDTH, "center")

    Assets.setFont(16)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.printf(self.status, 0, 115, World.WIDTH, "center")

    Assets.setFont(20)
    local top, spacing = 175, 34

    for i = 1, self:count() do
        local y = top + (i - 1) * spacing
        local selected = (i == self.selection)
        local text

        if self:isManual(i) then
            if self.typing then
                text = "Direkt verbinden: " .. self.input .. "_"
            else
                text = "Direkt verbinden (IP eingeben)"
            end
        else
            local e = self.entries[i]
            text = string.format("%s  -  %s  (%d/%d)  %s:%d",
                e.lobbyName or "?", e.hostName or "?",
                e.players or 0, e.maxPlayers or 2, e.address, e.port)
        end

        if selected then
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf("> " .. text .. " <", 0, y, World.WIDTH, "center")
        else
            love.graphics.setColor(0.6, 0.6, 0.6)
            love.graphics.printf(text, 0, y, World.WIDTH, "center")
        end
    end

    if #self.entries == 0 then
        Assets.setFont(15)
        love.graphics.setColor(1, 1, 1, 0.45)
        love.graphics.printf(
            "Nichts gefunden? Firewall, WLAN-Client-Isolation oder zwei Netze.\n"
            .. "Der Host zeigt seine IP in der Lobby an -- damit geht es immer.",
            0, World.HEIGHT - 130, World.WIDTH, "center")
    end

    -- Die Zahlen, die den Fehler eingrenzen: gesendet, aber nichts empfangen
    -- heisst, dass entweder die Frage nicht ankommt oder die Antwort nicht
    -- zurueck. Ohne sie ist die Ursache Ratesache (D2, 2026-08-12).
    if self.diagnostics then
        Assets.setFont(12)
        love.graphics.setColor(1, 1, 1, 0.3)
        love.graphics.printf(self.diagnostics, 0, World.HEIGHT - 76, World.WIDTH, "center")
    end

    Assets.setFont(14)
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.printf(
        self.typing and "Adresse tippen, ENTER verbindet, ESC bricht ab"
                     or "HOCH/RUNTER waehlen, ENTER verbinden, F5 neu suchen, ESC zurueck",
        0, World.HEIGHT - 34, World.WIDTH, "center")
    love.graphics.setColor(1, 1, 1, 1)
end

return ServerList
