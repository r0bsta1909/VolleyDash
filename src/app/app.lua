-- ============================================================================
-- src/app/app.lua -- Programmzustand und Szenenwechsel (M0-12)
--
-- Haelt zusammen, was ueber ein einzelnes Match hinaus gilt: Prefs, Ruleset,
-- Tastenbelegung. Und es kennt die zwei Uebergaenge, die es im Moment gibt --
-- Menue auf, Menue zu.
--
-- Bewusste Ergaenzung zum Modulschnitt in `03_TECH` §2: Die Szenen brauchen
-- einen gemeinsamen Kontext, sonst haengt er wieder in main.lua.
-- ============================================================================

local Prefs    = require("src.app.prefs")
local Ruleset  = require("src.sim.ruleset")
local Bindings = require("src.input.bindings")
local Assets   = require("src.app.assets")
local Scene    = require("src.app.scene")
local Menu     = require("src.ui.menu")

local App = {}

App.prefs    = Prefs.new()
App.ruleset  = Ruleset.new(App.prefs.preset)
App.bindings = Bindings.new()

local LocalGame  -- verzoegert geladen: das Spiel kennt die App, nicht umgekehrt
local MenuScene

function App.boot(deterministic)
    -- Kosmetischer Zufall: Namen, Staub, Kamera. Im Aufzeichnungsmodus fest,
    -- damit der Header ehrlich ist (die Simulation selbst ist seit M0-08
    -- zufallsfrei).
    if deterministic then math.randomseed(1) else math.randomseed(os.time()) end

    local loaded = Prefs.load()
    for k, v in pairs(loaded) do App.prefs[k] = v end

    -- Eine unbrauchbare Belegung faellt still auf die Vorgabe zurueck, statt
    -- das Spiel unsteuerbar zu machen.
    local parsed = Bindings.parse(App.prefs.bindings) or Bindings.new()
    for slot = 1, 2 do
        for _, action in ipairs(Bindings.ACTIONS) do
            App.bindings[slot][action] = parsed[slot][action]
        end
    end
    App.prefs.bindings = Bindings.serialize(App.bindings)

    App.applyPreset(App.prefs.preset)
    Assets.load()
    love.audio.setVolume(App.prefs.volume)
    Menu.rollNames()

    LocalGame = require("src.app.scenes.local_game")
    MenuScene = require("src.app.scenes.menu")

    -- Das Spiel liegt immer unten im Stapel, das Menue darueber. So bleibt
    -- das Feld hinter dem Menue sichtbar und die Simulation steht, solange
    -- das Menue oben liegt.
    App.game = Scene.push(LocalGame.new(App))
    Scene.push(MenuScene.new(App))
end

-- Werte uebernehmen, ohne die Tabelle zu ersetzen: Simulation, Bot und
-- Aufzeichnung halten Referenzen auf genau diese eine Tabelle.
function App.applyRuleset(values)
    for k in pairs(Ruleset.FIELDS) do App.ruleset[k] = nil end
    for k, v in pairs(values) do
        if Ruleset.FIELDS[k] ~= nil then App.ruleset[k] = v end
    end
end

function App.applyPreset(name)
    App.applyRuleset(Ruleset.PRESETS[name] or Ruleset.PRESETS[Ruleset.DEFAULT_PRESET])
end

-- ---------------------------------------------------------------------------
-- Uebergaenge
-- ---------------------------------------------------------------------------

function App.startMatch(vsBot)
    App.game:launch(vsBot)
    App.closeMenu()
end

function App.openMenu()
    if Scene.top() ~= App.game then return end
    Scene.push(MenuScene.new(App))
end

function App.closeMenu()
    -- Ohne laufendes Match bleibt das Menue stehen; sonst saehe man ein
    -- leeres Feld ohne Ausweg.
    if not App.game.state.match.inProgress then return end
    if Scene.top() ~= App.game then Scene.pop() end
end

function App.openTweaker()
    App.closeMenu()
    App.game.tweaker.active = true
end

function App.refreshBindings()
    App.game:refreshBindings()
end

function App.hasMatch()
    return App.game ~= nil
end

function App.matchRunning()
    return App.game ~= nil and App.game.state.match.inProgress
end

return App
