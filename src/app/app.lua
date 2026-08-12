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
local Music    = require("src.app.music")

local App = {}

App.prefs    = Prefs.new()
App.ruleset  = Ruleset.new(App.prefs.preset)
App.bindings = Bindings.new()

local LocalGame  -- verzoegert geladen: das Spiel kennt die App, nicht umgekehrt
local MenuScene

-- Szenen, die zu einer Netzwerksitzung gehoeren. Sie liegen uebereinander
-- (Serverliste -> Lobby -> Match) und halten jede fuer sich Sockets, die in
-- `leave` zugehen muessen.
local NET_SCENES = { serverlist = true, lobby = true, net_game = true }

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

    -- Musik laeuft nicht mit, wenn Referenzdaten entstehen: die Mischung
    -- zieht aus demselben math.random wie der Bot.
    Music.load(deterministic)
    Music.setVolume(App.prefs.musicVolume)
    Music.play("menu")

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
    Music.play("match")
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

-- ---------------------------------------------------------------------------
-- Netzwerk (M2)
-- ---------------------------------------------------------------------------

-- Kennung fuer den Wiedereinstieg nach einer Trennung (`04_NETCODE_SPEC` §12).
-- Sie liegt in den Prefs, weil sie einen Neustart ueberleben muss: T-N-05
-- schiesst den Prozess ab und startet ihn neu, und der Host erkennt den
-- Rueckkehrer ausschliesslich hieran.
function App.clientId()
    -- Zwei Instanzen auf DEMSELBEN Rechner teilen sich die Prefs-Datei und
    -- damit die Kennung. Fuer den Harness aus M2-10 laesst sie sich deshalb
    -- ueberschreiben (`--client-id=N`); im Spiel gibt es dafuer keinen Weg,
    -- weil es dort keinen Grund gibt.
    if App.clientIdOverride then return App.clientIdOverride end

    if not App.prefs.clientId or App.prefs.clientId < 1 then
        App.prefs.clientId = math.random(1, 2147483647)
        Prefs.save(App.prefs)
    end
    return App.prefs.clientId
end

function App.setClientId(id)
    App.clientIdOverride = tonumber(id)
end

function App.openServerList()
    Scene.push(require("src.app.scenes.serverlist").new(App))
end

function App.hostLobby()
    Scene.push(require("src.app.scenes.lobby").new(App, { role = "host" }))
end

function App.joinLobby(address, port)
    Scene.push(require("src.app.scenes.lobby").new(App,
        { role = "client", address = address, port = port }))
end

function App.enterNetMatch(opts)
    Scene.push(require("src.app.scenes.net_game").new(App, opts))
end

-- Nur das Match verlassen. Die Lobby darunter bleibt bestehen -- damit kostet
-- das naechste Match keinen neuen Handschlag (CLAUDE.md §3.5).
function App.leaveMatch()
    Scene.popWhile(function(scene) return scene.name == "net_game" end)
end

-- Die ganze Sitzung beenden: alle Netzszenen abraeumen, Sockets zu.
function App.leaveNet()
    Scene.popWhile(function(scene) return NET_SCENES[scene.name] == true end)
end

function App.hasMatch()
    return App.game ~= nil
end

function App.matchRunning()
    return App.game ~= nil and App.game.state.match.inProgress
end

return App
