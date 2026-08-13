-- ============================================================================
-- tests/tournament_lobby_test.lua -- Ebene B: die Bedienung (M4-07, M4-11)
--
-- `05_TOURNAMENT` §9, §10, E-12. love-frei: geprueft wird die
-- Zustandsmaschine, nicht das Bild.
--
-- Der Teil, der falsch sein kann, ohne dass man es sieht, ist die Eingabe:
-- Ein Satz, der als "15:15" durchgeht, macht ein Match ohne Sieger. Eine
-- Korrektur, die ohne Begruendung committet, verletzt E-12. Ein Aufrufton, der
-- beim Falschen spielt, schickt den Falschen ans Geraet.
-- ============================================================================

local Model   = require("src.tournament.model")
local Session = require("src.tournament.session")
local TL      = require("src.ui.tournament_lobby")
local H       = require("tests.tournament_helper")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local assertEq, assertTrue, assertFalse = H.assertEq, H.assertTrue, H.assertFalse

local NAMES = { "Michi", "Anna", "Basti", "Kai", "Lea", "Tom", "Nina", "Ole" }

-- Ein Kontext, wie ihn sonst `src/app/scenes/tournament.lua` stellt. Die Uhr
-- laesst sich stellen: `env.clock = 1200`.
local function newEnv(opts)
    opts = opts or {}
    local env = { clock = 0, left = 0, created = 0, resumed = nil }

    env.session = Session.new({
        id          = "t_1754900000",
        name        = "Testturnier",
        createdAt   = 1754900000,
        config      = opts.config or { format = "single_elim", parallelMatches = 2 },
        ruleset     = { targetScore = 15 },
        rulesetHash = "deadbeef",
        presence    = "local",
        selfName    = opts.selfName,
        seedMode    = opts.seedMode or "manual",
        seedValue   = opts.seedValue or "",
    })

    env.ui = TL.new({
        session    = opts.noSession and nil or env.session,
        running    = opts.running,
        now        = function() return env.clock end,
        playerName = function() return opts.selfName or "Rob" end,
        onCreate   = function() env.created = env.created + 1 end,
        onResume   = function(id) env.resumed = id return true end,
        onLeave    = function() env.left = env.left + 1 end,
    })
    return env
end

local function typeText(ui, text)
    for i = 1, #text do ui:textinput(text:sub(i, i)) end
end

local function enterName(ui, name)
    typeText(ui, name)
    ui:keypressed("return")
end

local function fill(env, n)
    for i = 1, n do enterName(env.ui, NAMES[i] or ("Blob " .. i)) end
end

-- Bis zum Eintrag mit der gesuchten Art laufen.
local function selectKind(ui, kind, items)
    items = items or ui:setupItems()
    for i, item in ipairs(items) do
        if item.kind == kind then ui.sel = i return item end
    end
    error("kein Eintrag der Art " .. kind, 2)
end

-- ---------------------------------------------------------------------------
-- Anmeldung
-- ---------------------------------------------------------------------------

case("der Cursor steht beim Betreten im Namensfeld", function()
    local env = newEnv()
    assertEq(env.ui.mode, "setup", "Anmeldebildschirm")
    assertTrue(env.ui.editing ~= nil, "Eingabe laeuft")
    assertEq(env.ui.editing.field, "add", "und zwar im Namensfeld")
end)

case("nach ENTER steht der Cursor wieder im leeren Feld -- zwanzig Namen am Stueck", function()
    local env = newEnv()
    enterName(env.ui, "Michi")
    assertEq(env.session:count(), 1, "eingetragen")
    assertTrue(env.ui.editing ~= nil, "die Eingabe laeuft weiter")
    assertEq(env.ui.editing.buffer, "", "und das Feld ist leer")

    enterName(env.ui, "Anna")
    assertEq(env.session:count(), 2, "der zweite Name ohne Umweg")
end)

case("ESC beendet die Eingabe, ohne den Bildschirm zu verlassen", function()
    local env = newEnv()
    env.ui:keypressed("escape")
    assertEq(env.ui.editing, nil, "Eingabe beendet")
    assertEq(env.left, 0, "aber die Szene bleibt stehen")

    env.ui:keypressed("escape")
    assertEq(env.left, 1, "erst der zweite Druck geht zurueck")
end)

case("ENTF streicht den ausgewaehlten Teilnehmer", function()
    local env = newEnv()
    fill(env, 3)
    env.ui:keypressed("escape")

    local items = env.ui:setupItems()
    for i, item in ipairs(items) do
        if item.kind == "participant" and item.label == "Anna" then env.ui.sel = i end
    end
    env.ui:keypressed("delete")

    assertEq(env.session:count(), 2, "einer weniger")
    for _, pid in ipairs(env.session:activeIds()) do
        assertTrue(env.session:nameOf(pid) ~= "Anna", "und zwar der ausgewaehlte")
    end
end)

case("die Auslosung ist gesperrt, solange zu wenige angemeldet sind", function()
    local env = newEnv()
    fill(env, 3)
    env.ui:keypressed("escape")

    local item = selectKind(env.ui, "draw")
    assertTrue(item.blocked, "gesperrt")
    env.ui:keypressed("return")
    assertEq(env.ui.mode, "setup", "der Bildschirm bleibt")
    assertTrue(env.ui:currentMessage() ~= nil, "mit einer Meldung, die den Grund nennt")
end)

case("ENTER auf 'Auslosen' startet das Turnier und wechselt in die Ansicht", function()
    local env = newEnv()
    fill(env, 4)
    env.ui:keypressed("escape")
    selectKind(env.ui, "draw")
    env.ui:keypressed("return")

    assertEq(env.ui.mode, "run", "das Turnier laeuft")
    assertEq(env.session.t.status, Model.TOURNAMENT_STATUS.RUNNING, "auch im Modell")
end)

-- ---------------------------------------------------------------------------
-- Format, Setzung, Seed (§9)
-- ---------------------------------------------------------------------------

case("LINKS und RECHTS schalten das Format um", function()
    local env = newEnv()
    fill(env, 6)
    env.ui:keypressed("escape")

    selectKind(env.ui, "format")
    local before = env.session.t.config.format
    env.ui:keypressed("right")
    assertTrue(env.session.t.config.format ~= before, "umgeschaltet")
    assertEq(env.session:count(), 6, "und die Anmeldeliste steht noch")
end)

case("das Seed-Feld erscheint nur bei zufaelliger Setzung", function()
    local env = newEnv({ seedMode = "random", seedValue = "sommerlan" })
    env.ui:keypressed("escape")
    assertTrue(selectKind(env.ui, "seed") ~= nil, "bei random steht es da")

    selectKind(env.ui, "seedmode")
    env.ui:keypressed("right")
    assertEq(env.session.seedMode, "manual", "auf manuell gestellt")

    local found = false
    for _, item in ipairs(env.ui:setupItems()) do
        if item.kind == "seed" then found = true end
    end
    assertFalse(found, "dann ist das Feld weg")
end)

case("der Seed laesst sich eintippen und steht mit seiner Zahl in der Anzeige", function()
    local env = newEnv({ seedMode = "random", seedValue = "alt" })
    env.ui:keypressed("escape")
    selectKind(env.ui, "seed")
    env.ui:keypressed("return")
    -- Der alte Wert steht zum Weiterschreiben im Feld -- also erst loeschen.
    assertEq(env.ui.editing.buffer, "alt", "der alte Seed steht im Feld")
    for _ = 1, 3 do env.ui:keypressed("backspace") end
    typeText(env.ui, "sommerlan")
    env.ui:keypressed("return")

    assertEq(env.session.seedValue, "sommerlan", "uebernommen")
    local item = selectKind(env.ui, "seed")
    assertTrue(item.value:match("sommerlan"), "der Text steht in der Anzeige")
    assertTrue(item.value:match("%d"), "und die Zahl daneben")
end)

-- ---------------------------------------------------------------------------
-- Ergebniseingabe (M4-11)
-- ---------------------------------------------------------------------------

-- Acht Teilnehmer, nicht vier: Bei vier ist Runde 1 schon das Halbfinale und
-- damit Best-of-3 (§2). Fuer die Ergebniseingabe ist Best-of-1 der Normalfall.
local function running(opts)
    opts = opts or {}
    local env = newEnv(opts)
    fill(env, opts.n or 8)
    env.ui:keypressed("escape")
    selectKind(env.ui, "draw")
    env.ui:keypressed("return")
    if not opts.keepView then env.ui.view = "full" end
    return env
end

-- Die Auswahl auf ein bestimmtes Match stellen.
local function select(env, matchId)
    local list = env.ui:list()
    for i, m in ipairs(list) do
        if m.id == matchId then env.ui.sel = i return m end
    end
    error("Match " .. matchId .. " steht nicht in der Liste", 2)
end

case("ENTER auf einem aufgerufenen Match setzt es auf 'laeuft'", function()
    local env = running()
    local m = env.session:callList()[1]
    select(env, m.id)

    local action, label = env.ui:primaryAction()
    assertEq(action, "start", "die Fusszeile sagt es an")
    assertTrue(label ~= nil, "mit Text")

    env.ui:keypressed("return")
    assertEq(env.session.t.matches[m.id].status, Model.STATUS.LIVE, "es laeuft")
end)

case("ein Satz wird als 15:12 eingegeben und beendet ein Best-of-1", function()
    local env = running()
    local m = env.session:callList()[1]
    local a = m.slotA
    select(env, m.id)

    env.ui:keypressed("e")
    assertTrue(env.ui.dialog ~= nil, "die Eingabe steht offen")

    typeText(env.ui, "15:12")
    env.ui:keypressed("return")

    assertEq(env.ui.dialog, nil, "und ist wieder zu")
    assertEq(env.session.t.matches[m.id].status, Model.STATUS.FINISHED, "fertig")
    assertEq(env.session.t.matches[m.id].winner, a, "der linke Slot gewinnt")
end)

case("Unsinn in der Eingabe wird gemeldet, nicht uebernommen", function()
    local env = running()
    local m = env.session:callList()[1]
    select(env, m.id)
    env.ui:keypressed("e")

    typeText(env.ui, "1512")
    env.ui:keypressed("return")
    assertTrue(env.ui.dialog ~= nil, "die Eingabe steht noch offen")
    assertTrue(env.ui:currentMessage() ~= nil, "mit einer Meldung")
    assertEq(#env.ui.dialog.sets, 0, "kein Satz uebernommen")
end)

case("ein unentschiedener Satz wird abgelehnt", function()
    local env = running()
    local m = env.session:callList()[1]
    select(env, m.id)
    env.ui:keypressed("e")

    typeText(env.ui, "15:15")
    env.ui:keypressed("return")
    assertEq(#env.ui.dialog.sets, 0, "nicht uebernommen")
    assertEq(env.session.t.matches[m.id].status, Model.STATUS.READY, "das Match laeuft weiter")
end)

case("Best-of-3 braucht zwei gewonnene Saetze", function()
    local env = running({ n = 4, config = { format = "single_elim",
                                            parallelMatches = 2,
                                            bestOfDefault = 1, bestOfFinals = 3 } })
    -- Bei vier Teilnehmern sind Runde 1 die Halbfinals, also schon Best-of-3.
    local m = env.session:callList()[1]
    assertEq(m.bestOf, 3, "Best-of-3 ab Halbfinale (§2)")
    select(env, m.id)
    env.ui:keypressed("e")

    typeText(env.ui, "15:9")
    env.ui:keypressed("return")
    assertTrue(env.ui.dialog ~= nil, "nach einem Satz noch offen")

    typeText(env.ui, "11:15")
    env.ui:keypressed("return")
    assertTrue(env.ui.dialog ~= nil, "nach dem Ausgleich auch")

    typeText(env.ui, "15:13")
    env.ui:keypressed("return")
    assertEq(env.ui.dialog, nil, "der dritte Satz entscheidet")
    assertEq(env.session.t.matches[m.id].winner, m.slotA, "und zwar fuer den linken Slot")
    assertEq(#env.session.t.matches[m.id].sets, 3, "alle drei Saetze stehen im Log")
end)

case("die RUECKTASTE nimmt einen eingetragenen Satz zurueck", function()
    local env = running({ n = 4, config = { format = "single_elim",
                                            bestOfDefault = 3, bestOfFinals = 3 } })
    local m = env.session:callList()[1]
    select(env, m.id)
    env.ui:keypressed("e")

    typeText(env.ui, "15:9")
    env.ui:keypressed("return")
    assertEq(#env.ui.dialog.sets, 1, "ein Satz")

    env.ui:keypressed("backspace")
    assertEq(#env.ui.dialog.sets, 0, "wieder weg")
end)

case("ESC bricht die Eingabe ab, ohne etwas zu schreiben", function()
    local env = running()
    local m = env.session:callList()[1]
    select(env, m.id)
    env.ui:keypressed("e")
    typeText(env.ui, "15:12")
    env.ui:keypressed("escape")

    assertEq(env.ui.dialog, nil, "zu")
    assertEq(env.session.t.matches[m.id].status, Model.STATUS.READY, "nichts passiert")
end)

-- ---------------------------------------------------------------------------
-- Korrektur (E-12)
-- ---------------------------------------------------------------------------

case("eine Korrektur ohne Begruendung committet nicht", function()
    local env = running()
    local m = env.session:callList()[1]
    select(env, m.id)
    env.ui:keypressed("e")
    typeText(env.ui, "15:12")
    env.ui:keypressed("return")

    select(env, m.id)
    env.ui:keypressed("k")
    assertTrue(env.ui.dialog ~= nil, "Korrektur offen")

    typeText(env.ui, "9:15")
    env.ui:keypressed("return")
    assertEq(env.ui.dialog.phase, "reason", "jetzt wird nach dem Grund gefragt")

    env.ui:keypressed("return")
    assertTrue(env.ui.dialog ~= nil, "ohne Grund bleibt sie offen")
    assertEq(env.session.t.matches[m.id].winner, m.slotA, "und das Ergebnis steht unveraendert")

    typeText(env.ui, "falsch getippt")
    env.ui:keypressed("return")
    assertEq(env.ui.dialog, nil, "mit Grund geht sie zu")

    local fixed = env.session.t.matches[m.id]
    assertEq(fixed.winner, m.slotB, "der andere gewinnt")
    assertTrue(fixed.overridden, "sichtbar markiert")
    assertEq(fixed.overrideReason, "falsch getippt", "mit dem Grund im Log")
end)

case("ein laufendes Match laesst sich nicht korrigieren, ein fertiges nicht eintragen", function()
    local env = running()
    local m = env.session:callList()[1]
    select(env, m.id)

    env.ui:keypressed("k")
    assertEq(env.ui.dialog, nil, "keine Korrektur auf einem offenen Match")

    env.ui:keypressed("e")
    typeText(env.ui, "15:2")
    env.ui:keypressed("return")

    select(env, m.id)
    env.ui:keypressed("e")
    assertEq(env.ui.dialog, nil, "und kein Eintragen auf einem fertigen")
end)

-- ---------------------------------------------------------------------------
-- Timer, Abbruch, Austragen
-- ---------------------------------------------------------------------------

case("P haelt den No-Show-Timer an und wieder frei (E-02)", function()
    local env = running()
    env.clock = 1000
    local m = env.session:callList()[1]
    select(env, m.id)

    env.ui:keypressed("p")
    assertTrue(env.session:isPaused(m.id), "steht")
    env.ui:keypressed("p")
    assertFalse(env.session:isPaused(m.id), "laeuft")
end)

case("A bricht ein Match ab und setzt es neu an (E-06)", function()
    local env = running()
    local m = env.session:callList()[1]
    select(env, m.id)
    env.ui:keypressed("return")   -- auf live
    env.ui:keypressed("a")

    local after = env.session.t.matches[m.id]
    assertTrue(after.status == Model.STATUS.READY or after.status == Model.STATUS.PENDING,
        "wieder in der Ansetzung")
    assertEq(after.winner, nil, "ohne Sieger (B-T-01)")
end)

case("TAB wechselt in die Teilnehmerliste, W traegt jemanden aus (E-04)", function()
    local env = running()
    env.ui:keypressed("tab")
    assertEq(env.ui.panel, "participants", "Teilnehmerliste")

    local who = env.ui:list()[1]
    env.ui:keypressed("w")
    assertEq(env.session.t.participants[who.id].status,
        Model.PARTICIPANT_STATUS.WITHDRAWN, "ausgetragen")
    assertEq(env.session:count(), 7, "einer weniger im Feld")
end)

-- ---------------------------------------------------------------------------
-- Die beiden Ansichten (§10)
-- ---------------------------------------------------------------------------

case("F2 schaltet zwischen kompakt und voll", function()
    local env = running()
    env.ui.view = "compact"
    env.ui:keypressed("f2")
    assertEq(env.ui.view, "full", "voll")
    env.ui:keypressed("f2")
    assertEq(env.ui.view, "compact", "kompakt")
end)

-- Die kompakte Ansicht ist der Bildschirm eines Spielers. Wer dort ein
-- Ergebnis eintragen koennte, koennte sein eigenes eintragen.
case("in der kompakten Ansicht ist die Bedienung stumm", function()
    local env = running()
    env.ui.view = "compact"
    env.ui:keypressed("e")
    assertEq(env.ui.dialog, nil, "kein Eingabefeld")
    env.ui:keypressed("w")
    env.ui:keypressed("a")
    assertEq(env.session:count(), 8, "und niemand ausgetragen")
end)

case("wer mitspielt, sieht seine Linie -- wer ausrichtet, den ganzen Baum", function()
    local player = running({ selfName = "Michi", keepView = true })
    assertEq(player.ui.view, "compact", "Spieler")

    local host = running({ selfName = "Rob", keepView = true })   -- nicht im Feld
    assertEq(host.ui.view, "full", "Turnierleiter")
end)

-- ---------------------------------------------------------------------------
-- Klaenge (Klangliste §1)
-- ---------------------------------------------------------------------------

case("der Aufruf klingt fuer das eigene Match", function()
    local env = newEnv({ selfName = "Michi" })
    fill(env, 4)
    env.ui:keypressed("escape")

    env.session:drawBracket(0)
    local sounds = env.ui:soundsFor(env.session:tick(0))
    local calls = 0
    for _, name in ipairs(sounds) do if name == "tournament_call" then calls = calls + 1 end end
    assertEq(calls, 1, "genau einmal -- fuer das eigene Match, nicht fuer das andere")
end)

case("wer nicht mitspielt, hoert jeden Aufruf", function()
    local env = newEnv({ selfName = "Rob" })   -- nicht im Feld
    fill(env, 4)
    env.ui:keypressed("escape")
    env.session:drawBracket(0)

    local sounds = env.ui:soundsFor(env.session:tick(0))
    local calls = 0
    for _, name in ipairs(sounds) do if name == "tournament_call" then calls = calls + 1 end end
    assertEq(calls, 2, "beide aufgerufenen Matches")
end)

case("die Vorwarnung und der Schlussklang haengen an denselben Ereignissen", function()
    local env = newEnv({ selfName = "Rob" })
    local sounds = env.ui:soundsFor({
        { event = "no_show_warning", matchId = "m_101" },
        { event = "tournament_finished", winner = "p_01" },
    })
    -- `m_101` gibt es noch nicht: ein Ereignis zu einem unbekannten Match darf
    -- die Anzeige nicht zerlegen.
    assertEq(sounds[1], "tournament_done", "der Schlussklang kommt durch")
end)

-- ---------------------------------------------------------------------------
-- Der Durchlauf (§13.1)
--
-- Ein 8er-Turnier, ausschliesslich ueber die Tastatur bedient, bis ein Sieger
-- feststeht. Aufruf, Freilose, Fortschreibung des Baums und das Ende passieren
-- dabei von allein -- eingegeben werden nur die Ergebnisse, und die kommen in
-- Stufe C vom Match-Host (E-08).
-- ---------------------------------------------------------------------------

case("ein 8er-Turnier laeuft ueber die Tastatur bis zum Sieger durch", function()
    local env = running({ n = 8 })
    local s = env.session
    local guard = 0

    while s.t.status == Model.TOURNAMENT_STATUS.RUNNING do
        guard = guard + 1
        if guard > 100 then error("Turnier haengt: " .. H.describeOpen(s.t), 2) end

        local open = s:callList()
        if #open == 0 then
            env.clock = env.clock + 1
            s:tick(env.clock)
        else
            select(env, open[1].id)
            env.ui:keypressed("e")
            -- Solange tippen, bis das Feld zugeht: Best-of-1 nimmt einen Satz,
            -- Best-of-3 ab dem Halbfinale zwei.
            local sets = 0
            while env.ui.dialog and sets < 3 do
                typeText(env.ui, "15:9")
                env.ui:keypressed("return")
                sets = sets + 1
            end
            assertEq(env.ui.dialog, nil, "das Ergebnis ist uebernommen")
        end
    end

    assertEq(s.t.status, Model.TOURNAMENT_STATUS.FINISHED, "das Turnier ist zu")
    assertTrue(s:winnerName() ~= nil, "und ein Sieger steht am Beamer")

    -- Kein Match darf offen geblieben sein -- auch nicht das Spiel um Platz 3.
    for _, m in ipairs(s.t:matchList()) do
        assertTrue(Model.TERMINAL[m.status], m.id .. " ist fertig")
    end
end)

-- ---------------------------------------------------------------------------
-- Wiederaufnahme (§7)
-- ---------------------------------------------------------------------------

case("ein laufendes Turnier wird beim Betreten zuerst angeboten", function()
    local env = newEnv({ noSession = true, running = {
        { id = "t_1", name = "Sommer-LAN", round = 2, rounds = 3, status = "running" },
    } })

    assertEq(env.ui.mode, "resume", "die Frage kommt zuerst")
    local items = env.ui:resumeItems()
    assertTrue(items[1].label:match("Sommer%-LAN"), "mit Namen")
    assertTrue(items[1].label:match("2"), "und Rundenangabe")

    env.ui.sel = 1
    env.ui:keypressed("return")
    assertEq(env.resumed, "t_1", "fortgesetzt")
end)

case("wer stattdessen neu anlegt, landet im Anmeldebildschirm", function()
    local env = newEnv({ noSession = true, running = {
        { id = "t_1", name = "Sommer-LAN", round = 2, rounds = 3, status = "running" },
    } })

    env.ui.sel = 2   -- "Neues Turnier anlegen"
    env.ui:keypressed("return")
    assertEq(env.created, 1, "angelegt")
    assertEq(env.ui.mode, "setup", "Anmeldebildschirm")
end)

return T
