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
-- `tournament` steht seit M4-09 mit drin: Bis Stufe B hielt der Turniermodus
-- keine Sockets, jetzt haelt er den Turnier-Wirt auf 21212 oder die
-- Verbindung dorthin.
local NET_SCENES = { serverlist = true, lobby = true, net_game = true,
                     tournament = true }

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

-- Das Menue legt sich ueber die Szene, die gerade laeuft: das lokale Spiel
-- ODER ein Netzmatch (ADR-024). Beim lokalen Spiel ist das die Pause -- es
-- bekommt kein `update` mehr. Das Netzmatch laeuft weiter; es haelt Sockets
-- und simuliert beim Host autoritativ.
local function menuBase()
    local top = Scene.top()
    if top == App.game then return top end
    if top and top.name == "net_game" then return top end
    return nil
end

function App.openMenu()
    if not menuBase() then return end
    Scene.push(MenuScene.new(App))
end

function App.closeMenu()
    -- Ohne laufendes Match bleibt das Menue stehen; sonst saehe man ein
    -- leeres Feld ohne Ausweg. Ein Netzmatch laeuft immer.
    local top = Scene.top()
    if top and top.name == "menu" then
        local below = Scene.below(top)
        if below and below.name == "net_game" then Scene.pop() return end
    end
    if not App.game.state.match.inProgress then return end
    if Scene.top() ~= App.game then Scene.pop() end
end

-- Laeuft gerade ein Netzmatch unter dem Menue? Dann heisst der Ausstieg
-- "Verbindung trennen" und nicht "Quit" -- und ESC ist keine Pause.
function App.netMatchBelowMenu()
    local top = Scene.top()
    if not (top and top.name == "menu") then return false end
    local below = Scene.below(top)
    return below ~= nil and below.name == "net_game"
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

-- Der Nickname fuer Netzspiel und Turnier. Anders als die Zufallsnamen des
-- lokalen Spiels ueberlebt er den Neustart: im Bracket muss derselbe Mensch
-- morgen noch derselbe sein (Entscheidung r0btoshi, 2026-08-12).
--
-- Beim ersten Mal wird einer aus dem Namenspool gezogen und gespeichert --
-- niemand soll vor dem ersten Match ein Formular ausfuellen. Aendern geht im
-- Menue unter "Network Match".
function App.playerName()
    local name = Prefs.cleanName(App.prefs.playerName)
    if name == "" then
        name = Menu.NAME_POOL[math.random(1, #Menu.NAME_POOL)]
        App.prefs.playerName = name
        Prefs.save(App.prefs)
    end
    return name
end

function App.setPlayerName(name)
    local clean = Prefs.cleanName(name)
    if clean == "" then return false end
    App.prefs.playerName = clean
    Prefs.save(App.prefs)
    return true
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

-- Turniermodus (M4-07, seit M4-09 mit Netz). Er haelt jetzt Sockets -- den
-- Turnier-Wirt auf 21212 samt Bake oder die Verbindung dorthin -- und gehoert
-- damit zu NET_SCENES: `leaveNet` muss ihn mit abraeumen, sonst bleibt der
-- Port belegt, wenn jemand aus einem Match ins Menue zurueckfaellt.
function App.openTournament()
    Scene.push(require("src.app.scenes.tournament").new(App, { role = "leader" }))
end

-- Als Teilnehmer beitreten. Der Weg dorthin ist die Serverliste: Ein Turnier
-- wird genauso gefunden wie eine Lobby, nur fuehrt ENTER woanders hin
-- (`mode = "tournament"` in der Bake).
function App.joinTournament(address, port)
    Scene.push(require("src.app.scenes.tournament").new(App,
        { role = "client", address = address, port = port }))
end

function App.leaveTournament()
    Scene.popWhile(function(scene) return scene.name == "tournament" end)
end

function App.enterNetMatch(opts)
    Scene.push(require("src.app.scenes.net_game").new(App, opts))
end

-- Nur das Match verlassen. Die Lobby darunter bleibt bestehen -- damit kostet
-- das naechste Match keinen neuen Handschlag (CLAUDE.md §3.5).
function App.leaveMatch()
    Scene.popWhile(function(scene) return scene.name == "net_game" end)
end

-- Nur die Lobby verlassen, die Serverliste darunter bleibt. Gebraucht fuer
-- den Protokollwechsel, wenn eine getippte Adresse einem TURNIER gehoert
-- (AP-2, C-T-22): Die Lobbyszene geht zu, die Turnierszene kommt an ihre
-- Stelle -- wie bei einem Turnierbeitritt ueber die Serverliste auch.
function App.leaveLobby()
    Scene.popWhile(function(scene) return scene.name == "lobby" end)
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
