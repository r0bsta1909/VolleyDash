-- ============================================================================
-- tests/menu_test.lua -- Ebene B: die Texteingabe im Menue (M2, Nickname)
--
-- Geprueft wird die Zustandsmaschine, nicht das Bild: Eingabe beginnen,
-- tippen, Ruecktaste, uebernehmen, abbrechen, Laenge deckeln. Das ist der
-- Teil, der falsch sein kann, ohne dass man es sieht -- ein abgeschnittener
-- oder leerer Nickname faellt erst in der Lobby des Gegenuebers auf.
--
-- love-frei: `Menu.new` und `Menu:keypressed` fassen die Bibliothek nicht an,
-- gezeichnet wird hier nicht.
-- ============================================================================

local Menu  = require("src.ui.menu")
local Prefs = require("src.app.prefs")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local function assertEq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: erwartet %s, war %s",
            what or "Wert", tostring(expected), tostring(actual)), 2)
    end
end
local function assertTrue(v, what) assertEq(not not v, true, what) end
local function assertNil(v, what) assertEq(v, nil, what) end

-- Ein Menue mit dem Kontext, den die Szene sonst stellt.
local function newMenu()
    local store = { name = "Wobble", saved = 0 }
    local menu = Menu.new({
        prefs    = Prefs.new(),
        bindings = require("src.input.bindings").new(),
        ruleset  = require("src.sim.ruleset").new("classic"),
        onLaunch = function() end,
        onTweaker = function() end,
        onClose  = function() end,
        onBindings = function() end,
        onHost   = function() end,
        onBrowse = function() end,
        playerName    = function() return store.name end,
        setPlayerName = function(value) store.name = value end,
    })
    -- Speichern schreibt sonst in die echte Prefs-Datei; hier zaehlen wir nur.
    menu.save = function(self) store.saved = store.saved + 1 end
    menu:goTo("network")
    return menu, store
end

local function nicknameItem(menu)
    for _, item in ipairs(menu.pages.network.items) do
        if item.edit then return item end
    end
    return nil
end

local function type_(menu, text)
    for i = 1, #text do menu:textinput(text:sub(i, i)) end
end

-- ---------------------------------------------------------------------------

case("die Netzwerkseite hat einen Nicknamen zum Tippen", function()
    local menu = newMenu()
    local item = nicknameItem(menu)
    assertTrue(item ~= nil, "Eintrag vorhanden")
    assertEq(item.name, "Nickname", "Beschriftung")
    assertEq(menu.pages.network.items[1], item, "steht oben")
end)

case("ENTER auf dem Eintrag beginnt die Eingabe mit dem alten Namen", function()
    local menu = newMenu()
    menu.pages.network.selection = 1
    menu:keypressed("return")
    assertTrue(menu.editing ~= nil, "Eingabe laeuft")
    assertEq(menu.editing.buffer, "Wobble", "vorbelegt")
end)

case("getippte Zeichen landen im Puffer, ENTER uebernimmt", function()
    local menu, store = newMenu()
    menu.pages.network.selection = 1
    menu:keypressed("return")
    menu.editing.buffer = ""
    type_(menu, "GigaBlob")
    menu:keypressed("return")

    assertNil(menu.editing, "Eingabe beendet")
    assertEq(store.name, "GigaBlob", "uebernommen")
    assertTrue(store.saved > 0, "gespeichert")
end)

case("die Ruecktaste entfernt ein Zeichen", function()
    local menu = newMenu()
    menu.pages.network.selection = 1
    menu:keypressed("return")
    menu.editing.buffer = ""
    type_(menu, "Blob")
    menu:keypressed("backspace")
    assertEq(menu.editing.buffer, "Blo", "ein Zeichen weniger")
end)

case("ESC verwirft die Eingabe", function()
    local menu, store = newMenu()
    menu.pages.network.selection = 1
    menu:keypressed("return")
    menu.editing.buffer = ""
    type_(menu, "Unsinn")
    menu:keypressed("escape")

    assertNil(menu.editing, "Eingabe beendet")
    assertEq(store.name, "Wobble", "alter Name bleibt")
end)

case("ein leerer Name wird nicht uebernommen", function()
    local menu, store = newMenu()
    menu.pages.network.selection = 1
    menu:keypressed("return")
    menu.editing.buffer = "   "
    menu:keypressed("return")
    -- Besser der alte Name als jemand, der im Turnierbaum "" heisst.
    assertEq(store.name, "Wobble", "alter Name bleibt")
end)

case("laenger als das Hoechstmass geht nicht", function()
    local menu, store = newMenu()
    menu.pages.network.selection = 1
    menu:keypressed("return")
    menu.editing.buffer = ""
    type_(menu, string.rep("x", Prefs.NAME_MAX + 20))
    menu:keypressed("return")
    assertEq(Prefs.nameLength(store.name), Prefs.NAME_MAX, "gedeckelt")
end)

case("waehrend der Eingabe bewegt HOCH/RUNTER die Auswahl nicht", function()
    local menu = newMenu()
    menu.pages.network.selection = 1
    menu:keypressed("return")
    menu:keypressed("down")
    assertEq(menu.pages.network.selection, 1, "Auswahl steht")
    assertTrue(menu.editing ~= nil, "Eingabe laeuft weiter")
end)

case("ausserhalb der Eingabe wird getippter Text ignoriert", function()
    local menu = newMenu()
    menu:textinput("x")
    assertNil(menu.editing, "kein Zustand aus dem Nichts")
end)

return T
