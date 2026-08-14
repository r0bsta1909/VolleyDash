-- ============================================================================
-- src/ui/menu.lua -- Menue-Zustandsmaschine (M0-12)
--
-- Aus dem Prototyp uebernommen: eine Tabelle je Seite, jeder Eintrag ist
-- entweder ein Ziel, eine Aktion oder ein Wert mit links/rechts.
--
-- Das Menue kennt das Spiel nicht. Was es ausloesen soll, bekommt es als
-- Rueckrufe im Kontext (`launch`, `resume`, `quit`, `tweaker`).
-- ============================================================================

local World     = require("src.sim.world")
local Assets    = require("src.app.assets")
local Prefs     = require("src.app.prefs")
local Bindings  = require("src.input.bindings")
local Music     = require("src.app.music")
local BuildInfo = require("src.app.build_info")

local Menu = {}
Menu.__index = Menu

Menu.NAME_POOL = {
    "Blobber", "Slime", "Jelly", "Gloop", "Spiker", "Bouncer", "Titan", "Rookie",
    "GigaBlob", "Wobble", "Squish", "LanKing", "Pudding", "SmashBro", "NoobSlayer",
}

Menu.PRESET_ORDER = { "classic", "prototype" }

-- Namen sind Anzeige, kein Spielzustand. Sie liegen hier, weil sie hier
-- bearbeitet werden; das HUD fragt sie ueber Menu.displayNames ab.
local names = { p1 = 1, p2 = 2, bot = 3 }

function Menu.rollNames()
    local pool = #Menu.NAME_POOL
    names.p1 = math.random(1, pool)
    names.p2 = math.random(1, pool)
    names.bot = math.random(1, pool)
    if names.p1 == names.p2 then names.p2 = (names.p2 % pool) + 1 end
    if names.bot == names.p1 or names.bot == names.p2 then
        names.bot = (names.bot % pool) + 1
    end
end

function Menu.displayNames(botActive)
    return {
        Menu.NAME_POOL[names.p1],
        botActive and Menu.NAME_POOL[names.bot] or Menu.NAME_POOL[names.p2],
    }
end

local function cycle(index, direction)
    local pool = #Menu.NAME_POOL
    return ((index - 1 + direction) % pool) + 1
end

-- ---------------------------------------------------------------------------

function Menu.new(ctx)
    local self = setmetatable({
        ctx = ctx,
        current = "main",
        capture = nil,   -- laufende Tastenabfrage im Steuerungsmenue
    }, Menu)
    self.pages = self:buildPages()
    return self
end

function Menu:save()
    Prefs.save(self.ctx.prefs)
end

function Menu:cyclePreset(direction)
    local prefs = self.ctx.prefs
    local index = 1
    for i, name in ipairs(Menu.PRESET_ORDER) do
        if name == prefs.preset then index = i end
    end
    prefs.preset = Menu.PRESET_ORDER[((index - 1 + direction) % #Menu.PRESET_ORDER) + 1]
    self:save()
end

function Menu:buildControls()
    local ctx = self.ctx
    local items = {}
    for slot = 1, 2 do
        for _, action in ipairs(Bindings.ACTIONS) do
            items[#items + 1] = {
                name = string.format("P%d %s", slot, Bindings.LABELS[action]),
                getValue = function()
                    if self.capture and self.capture.slot == slot
                       and self.capture.action == action then
                        return "Taste druecken..."
                    end
                    return string.upper(ctx.bindings[slot][action])
                end,
                action = function() self.capture = { slot = slot, action = action } end,
            }
        end
    end
    items[#items + 1] = {
        name = "Zuruecksetzen",
        action = function()
            local fresh = Bindings.new()
            for slot = 1, 2 do
                for _, action in ipairs(Bindings.ACTIONS) do
                    ctx.bindings[slot][action] = fresh[slot][action]
                end
            end
            ctx.onBindings()
            self:save()
        end,
    }
    items[#items + 1] = { name = "Back", target = "settings" }
    return items
end

function Menu:buildPages()
    local ctx = self.ctx
    local prefs = ctx.prefs

    return {
        main = {
            title = "VOLLEY DASH",
            selection = 1,
            items = {
                { name = "Local Match", target = "start" },
                { name = "Network Match", target = "network" },
                { name = "Player Profiles", target = "profiles" },
                { name = "Settings", target = "settings" },
                -- Nur waehrend eines Netzmatches: Seit ADR-024 beendet ESC das
                -- Spiel nicht mehr, sondern oeffnet dieses Menue. Ohne einen
                -- benannten Weg hinaus gaebe es keinen.
                { name = "Netzspiel verlassen",
                  onlyNetMatch = true,
                  action = function() ctx.onLeaveNet() end },
                { name = "Quit", action = function() self:save(); love.event.quit() end },
            },
        },

        start = {
            title = "LOCAL MATCH",
            selection = 1,
            items = {
                { name = "Play: 1v1 Local", action = function() ctx.onLaunch(false) end },
                { name = "Play: VS Bot", action = function() ctx.onLaunch(true) end },
                {
                    name = "Bot Level",
                    getValue = function() return tostring(prefs.botLevel) end,
                    onLeft = function() prefs.botLevel = math.max(1, prefs.botLevel - 1); self:save() end,
                    onRight = function() prefs.botLevel = math.min(3, prefs.botLevel + 1); self:save() end,
                },
                {
                    -- Wirkt erst beim naechsten Matchstart: waehrend eines
                    -- Matches ist das Ruleset unveraenderlich (ADR-005).
                    name = "Ruleset",
                    getValue = function() return prefs.preset end,
                    onLeft = function() self:cyclePreset(-1) end,
                    onRight = function() self:cyclePreset(1) end,
                },
                { name = "Back", target = "main" },
            },
        },

        -- LAN-Spiel (M2). Zwei Eintraege, kein drittes Untermenue: wer hostet,
        -- weiss es, und wer sucht, sucht. Alles andere braeuchte eine
        -- Erklaerung (CLAUDE.md §1).
        network = {
            title = "NETWORK MATCH",
            selection = 1,
            items = {
                {
                    -- Steht bewusst OBEN und nicht in den Einstellungen: im
                    -- Netzspiel und im Turnier ist der Name die Kennung des
                    -- Spielers, nicht Zierrat. Die Zufallsnamen des lokalen
                    -- Spiels gelten hier nicht.
                    name = "Nickname",
                    getValue = function() return ctx.playerName() end,
                    edit = {
                        get = function() return ctx.playerName() end,
                        set = function(value) ctx.setPlayerName(value) end,
                    },
                },
                { name = "Spiel hosten", action = function() ctx.onHost() end },
                { name = "Spiel suchen", action = function() ctx.onBrowse() end },
                -- Der Turniermodus steht hier und nicht im Hauptmenue: Er
                -- gehoert zum LAN-Abend, und wer allein vor dem Rechner sitzt,
                -- braucht ihn nicht (M4-07).
                --
                -- "erstellen" statt nur "Turnier": Seit M4-09 gibt es beide
                -- Rollen, und beigetreten wird ueber "Spiel suchen" -- ein
                -- Eintrag, der nur "Turnier" heisst, sieht nach dem Weg fuer
                -- beide aus. Am Abend des 2026-08-13 gemeldet.
                { name = "Turnier erstellen", action = function() ctx.onTournament() end },
                {
                    -- Der Host verteilt das Regelwerk (ADR-005); beim Gast ist
                    -- die Einstellung wirkungslos und steht deshalb hier, nicht
                    -- in der Lobby.
                    name = "Ruleset (nur als Host)",
                    getValue = function() return prefs.preset end,
                    onLeft = function() self:cyclePreset(-1) end,
                    onRight = function() self:cyclePreset(1) end,
                },
                { name = "Back", target = "main" },
            },
        },

        profiles = {
            title = "PLAYER PROFILES",
            selection = 1,
            items = {
                {
                    name = "Player 1 Name",
                    getValue = function() return Menu.NAME_POOL[names.p1] end,
                    onLeft = function() names.p1 = cycle(names.p1, -1) end,
                    onRight = function() names.p1 = cycle(names.p1, 1) end,
                },
                {
                    name = "Player 2 Name (Local)",
                    getValue = function() return Menu.NAME_POOL[names.p2] end,
                    onLeft = function() names.p2 = cycle(names.p2, -1) end,
                    onRight = function() names.p2 = cycle(names.p2, 1) end,
                },
                {
                    name = "Bot Name",
                    getValue = function() return Menu.NAME_POOL[names.bot] end,
                    onLeft = function() names.bot = cycle(names.bot, -1) end,
                    onRight = function() names.bot = cycle(names.bot, 1) end,
                },
                { name = "Back", target = "main" },
            },
        },

        controls = { title = "CONTROLS", selection = 1, items = {} },

        settings = {
            title = "SETTINGS",
            selection = 1,
            items = {
                {
                    name = "Master Volume",
                    getValue = function() return math.floor(prefs.volume * 100) .. "%" end,
                    onLeft = function()
                        prefs.volume = math.max(0.0, prefs.volume - 0.05)
                        love.audio.setVolume(prefs.volume); self:save()
                    end,
                    onRight = function()
                        prefs.volume = math.min(1.0, prefs.volume + 0.05)
                        love.audio.setVolume(prefs.volume); self:save()
                    end,
                },
                {
                    name = "Music Volume",
                    getValue = function()
                        if Music.count("menu") + Music.count("match") == 0 then
                            return "keine Titel"
                        end
                        return math.floor(prefs.musicVolume * 100) .. "%"
                    end,
                    onLeft = function()
                        prefs.musicVolume = math.max(0.0, prefs.musicVolume - 0.05)
                        Music.setVolume(prefs.musicVolume); self:save()
                    end,
                    onRight = function()
                        prefs.musicVolume = math.min(1.0, prefs.musicVolume + 0.05)
                        Music.setVolume(prefs.musicVolume); self:save()
                    end,
                },
                { name = "Naechster Titel", action = function() Music.skip() end },
                { name = "Open Live Tweaker", action = function() ctx.onTweaker() end },
                { name = "Controls", target = "controls" },
                { name = "Display [WIP]", target = "settings" },
                { name = "Back", target = "main" },
            },
        },
    }
end

-- ---------------------------------------------------------------------------

function Menu:page()
    return self.pages[self.current]
end

-- Die Eintraege, die gerade gelten.
--
-- `onlyNetMatch` blendet den Ausstieg aus dem Netzspiel aus, solange keines
-- laeuft. Ein Menuepunkt, der nichts tut, ist schlechter als keiner -- dieselbe
-- Ueberlegung wie bei der Fusszeile im Turnier (C-T-14).
function Menu:items()
    local out = {}
    for _, item in ipairs(self:page().items) do
        if not item.onlyNetMatch or self.netMatch then out[#out + 1] = item end
    end
    return out
end

function Menu:goTo(name)
    self.current = name
    if name == "controls" then
        self.pages.controls.items = self:buildControls()
    end
    self.pages[name].selection = 1
end

-- ---------------------------------------------------------------------------
-- Texteingabe (M2, Nickname)
--
-- Eigener Zustand neben `capture`: dort wird EIN Anschlag abgefangen, hier
-- eine ganze Zeile getippt. Zwei Dinge, zwei Zustaende.
-- ---------------------------------------------------------------------------

function Menu:beginEdit(item)
    self.editing = { item = item, buffer = item.edit.get() or "" }
end

function Menu:commitEdit()
    local edit = self.editing
    self.editing = nil
    if not edit then return end

    local value = Prefs.cleanName(edit.buffer)
    -- Ein leerer Name wird nicht uebernommen: dann bliebe der alte, und das
    -- ist besser als jemand, der im Bracket "" heisst.
    if value ~= "" then edit.item.edit.set(value) end
    self:save()
end

function Menu:textinput(text)
    local edit = self.editing
    if not edit then return end
    -- Steuerzeichen kommen hier gar nicht erst an; die Laenge deckelt die
    -- Anzeige und den Platz im Protokoll (`s1`, 24 Byte).
    if Prefs.nameLength(edit.buffer) >= Prefs.NAME_MAX then return end
    edit.buffer = edit.buffer .. text
end

-- Gibt true zurueck, wenn die Taste verbraucht wurde.
function Menu:keypressed(key)
    if self.editing then
        if key == "escape" then
            self.editing = nil
        elseif key == "backspace" then
            self.editing.buffer = Prefs.dropLastChar(self.editing.buffer)
        elseif key == "return" or key == "kpenter" then
            self:commitEdit()
        end
        return true
    end

    -- Laeuft eine Tastenabfrage, gehoert der naechste Anschlag ihr (M0-11).
    if self.capture then
        if key ~= "escape" then
            local ok, err = Bindings.set(self.ctx.bindings, self.capture.slot,
                self.capture.action, key)
            if ok then
                self.ctx.onBindings()
                self:save()
            else
                print("[bindings] " .. tostring(err))
            end
        end
        self.capture = nil
        return true
    end

    local page = self:page()

    if key == "escape" then
        if self.current ~= "main" then
            self:goTo("main")
        else
            self.ctx.onClose()
        end
        return true
    elseif key == "up" then
        page.selection = math.max(1, page.selection - 1)
    elseif key == "down" then
        page.selection = math.min(#self:items(), page.selection + 1)
    elseif key == "left" then
        local item = self:items()[page.selection]
        if item and item.onLeft then item.onLeft() end
    elseif key == "right" then
        local item = self:items()[page.selection]
        if item and item.onRight then item.onRight() end
    elseif key == "return" then
        local item = self:items()[page.selection]
        if not item then return true end
        if item.edit then
            self:beginEdit(item)
        elseif item.action then
            item.action()
        elseif item.target then
            self:goTo(item.target)
        end
    end
    return true
end

function Menu:draw(matchRunning)
    local page = self:page()

    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, World.WIDTH, World.HEIGHT)

    Assets.setFont(48)
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf(page.title, 0, 80, World.WIDTH, "center")

    if self.current == "main" then
        -- Zwei verschiedene Aussagen, und die Unterscheidung ist wichtig: Im
        -- lokalen Spiel steht die Simulation, solange das Menue offen ist. Im
        -- Netzspiel laeuft sie weiter (ADR-024) -- wer das fuer eine Pause
        -- haelt, kommt zurueck und hat verloren.
        Assets.setFont(16)
        if self.netMatch then
            love.graphics.setColor(0.95, 0.6, 0.2)
            love.graphics.printf("Das Match laeuft weiter - ESC zurueck ins Spiel",
                0, 140, World.WIDTH, "center")
        elseif matchRunning then
            love.graphics.setColor(0.2, 0.8, 0.2)
            love.graphics.printf("Game Paused - Press ESC to resume",
                0, 140, World.WIDTH, "center")
        end
    end

    -- Abstand und Startpunkt haengen an der Zahl der Eintraege: das
    -- Steuerungsmenue hat zehn und passte sonst nicht mehr aufs Feld (M0-11).
    Assets.setFont(24)
    local visible = self:items()
    local count = #visible
    local spacing = math.min(40, math.floor(330 / count))
    local top = 390 - (count * spacing) / 2

    for i, item in ipairs(visible) do
        local y = top + (i - 1) * spacing
        local text = item.name

        if self.editing and self.editing.item == item then
            text = text .. ": " .. self.editing.buffer .. "_"
        elseif item.edit then
            -- Ohne Pfeile: hier wird getippt, nicht durchgeschaltet. Die
            -- spitzen Klammern der Wertzeilen waeren ein falsches Versprechen.
            text = text .. ": " .. item.getValue()
        elseif item.getValue then
            text = text .. ": < " .. item.getValue() .. " >"
        end

        if i == page.selection then
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf("> " .. text .. " <", 0, y, World.WIDTH, "center")
        else
            love.graphics.setColor(0.6, 0.6, 0.6)
            love.graphics.printf(text, 0, y, World.WIDTH, "center")
        end
    end

    Assets.setFont(14)
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.printf(
        self.editing and "Namen tippen, ENTER uebernimmt, ESC bricht ab"
        or "Use UP/DOWN to navigate. Use LEFT/RIGHT to change settings. Enter to select.",
        0, World.HEIGHT - 30, World.WIDTH, "center")

    -- Version und Build-Hash (M1-04). Steht klein in der Ecke, weil die
    -- Bug-Vorlage danach fragt und niemand sonst danach sucht.
    Assets.setFont(12)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.printf(BuildInfo.label(), 0, World.HEIGHT - 48, World.WIDTH - 12, "right")
end

return Menu
