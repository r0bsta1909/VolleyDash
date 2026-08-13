-- ============================================================================
-- tests/tournament_session_test.lua -- Ebene B: die Laufzeit (M4-07)
--
-- `05_TOURNAMENT` §5, §7, §9, §10. love-frei.
--
-- Geprueft wird das, was Stufe B neu entscheidet und was man am Bild nicht
-- sieht: dass die Anmeldung Doppelnamen aufloest, dass derselbe sichtbare Seed
-- zweimal dasselbe Bracket ergibt, dass die Restzeit des No-Show-Timers
-- stimmt und nur EINMAL warnt, und dass ein Turnier, das mitten in der
-- Bedienung wegbricht, aus der Datei weiterlaeuft.
-- ============================================================================

local Model       = require("src.tournament.model")
local Bracket     = require("src.tournament.bracket")
local Session     = require("src.tournament.session")
local Persistence = require("src.tournament.persistence")
local H           = require("tests.tournament_helper")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local assertEq, assertTrue, assertFalse = H.assertEq, H.assertTrue, H.assertFalse

local NAMES = {
    "Michi", "Anna", "Basti", "Kai", "Lea", "Tom", "Nina", "Ole",
    "Pia", "Rik", "Sina", "Udo", "Vera", "Wim", "Xena", "Yves",
}

local function newSession(opts)
    opts = opts or {}
    return Session.new({
        id          = opts.id or "t_1754900000",
        name        = "Testturnier",
        createdAt   = 1754900000,
        config      = opts.config or { format = "single_elim", noShowTimeout = 180 },
        ruleset     = { targetScore = 15 },
        rulesetHash = "deadbeef",
        persistence = opts.persistence,
        presence    = opts.presence or "local",
        selfName    = opts.selfName,
        seedMode    = opts.seedMode or "manual",
        seedValue   = opts.seedValue or "",
    })
end

local function fill(s, n)
    for i = 1, n do s:addParticipant(NAMES[i] or ("Blob " .. i), 0) end
    return s
end

-- ---------------------------------------------------------------------------
-- Anmeldung (§9)
-- ---------------------------------------------------------------------------

case("die Anmeldung traegt Namen in der Reihenfolge der Eingabe ein", function()
    local s = fill(newSession(), 4)
    assertEq(s:count(), 4, "vier angemeldet")
    assertEq(s:nameOf("p_01"), "Michi", "erster Name")
    assertEq(s:nameOf("p_04"), "Kai", "vierter Name")
end)

case("ein doppelter Name wird abgewandelt, nicht abgelehnt (E-14)", function()
    local s = newSession()
    s:addParticipant("Anna", 0)
    local pid = s:addParticipant("anna", 0)
    assertTrue(pid ~= nil, "angenommen")
    assertEq(s:nameOf(pid), "anna 2", "abgewandelt")
    assertEq(s:count(), 2, "beide dabei")
end)

case("ein leerer Name wird nicht angenommen", function()
    local s = newSession()
    local pid, err = s:addParticipant("   ", 0)
    assertEq(pid, nil, "abgelehnt")
    assertTrue(err ~= nil, "mit Begruendung")
    assertEq(s:count(), 0, "niemand angemeldet")
end)

case("ein gestrichener Eintrag verschwindet aus der Auslosung, nicht aus dem Log", function()
    local s = fill(newSession(), 5)
    s:removeParticipant("p_02", 0)

    assertEq(s:count(), 4, "vier bleiben")
    for _, pid in ipairs(s:activeIds()) do
        assertTrue(pid ~= "p_02", "der gestrichene ist nicht dabei")
    end
    assertEq(s.t.participants["p_02"].status, Model.PARTICIPANT_STATUS.WITHDRAWN,
        "im Log steht er als zurueckgezogen")
end)

case("nach dem Streichen ist der Name wieder frei -- der Tippfehlerfall", function()
    local s = newSession()
    s:addParticipant("Basti", 0)
    s:removeParticipant("p_01", 0)
    local pid = s:addParticipant("Basti", 0)
    assertEq(s:nameOf(pid), "Basti", "kein 'Basti 2'")
end)

case("unter vier Teilnehmern wird nicht ausgelost (§2: 4 bis 32)", function()
    local s = fill(newSession(), 3)
    local ok, why = s:canDraw()
    assertFalse(ok, "gesperrt")
    assertTrue(why:match("4"), "die Zahl steht in der Meldung")
    assertFalse(s:drawBracket(0), "und die Auslosung passiert nicht")
    assertEq(s.t.status, Model.TOURNAMENT_STATUS.SETUP, "das Turnier steht noch im Aufbau")
end)

case("nach der Auslosung nimmt die Anmeldung niemanden mehr auf (E-03)", function()
    local s = fill(newSession(), 4)
    assertTrue(s:drawBracket(0), "ausgelost")
    local pid, err = s:addParticipant("Nachzuegler", 0)
    assertEq(pid, nil, "abgelehnt")
    assertTrue(err ~= nil, "mit Begruendung")
end)

-- ---------------------------------------------------------------------------
-- Setzung (§9) -- der sichtbare Seed
-- ---------------------------------------------------------------------------

local function pairing(s)
    local out = {}
    for _, id in ipairs(s.t.matchOrder) do
        local m = s.t.matches[id]
        out[#out + 1] = tostring(m.slotARef) .. "/" .. tostring(m.slotBRef)
    end
    return table.concat(out, " ")
end

case("derselbe Seed-Text ergibt zweimal dasselbe Bracket", function()
    local a = fill(newSession({ seedMode = "random", seedValue = "sommerlan" }), 12)
    local b = fill(newSession({ seedMode = "random", seedValue = "sommerlan" }), 12)
    a:drawBracket(0)
    b:drawBracket(0)
    assertEq(pairing(a), pairing(b), "identische Paarungen")
end)

case("ein anderer Seed-Text ergibt ein anderes Bracket", function()
    local a = fill(newSession({ seedMode = "random", seedValue = "sommerlan" }), 12)
    local b = fill(newSession({ seedMode = "random", seedValue = "winterlan" }), 12)
    a:drawBracket(0)
    b:drawBracket(0)
    assertTrue(pairing(a) ~= pairing(b), "unterschiedliche Paarungen")
end)

-- Der Fallstrick des sichtbaren Seeds: Angezeigt wird eine Zahl, eingegeben
-- wird Text. Wer die Zahl abliest und wieder eintippt, MUSS dasselbe Bracket
-- bekommen -- sonst ist der Seed nicht nachrechenbar und damit wertlos.
case("die angeschriebene Seed-Zahl ergibt wieder eingetippt dasselbe Bracket", function()
    local a = fill(newSession({ seedMode = "random", seedValue = "sommerlan" }), 12)
    a:drawBracket(0)

    local shown = Bracket.seedNumber(Session.seedFrom("sommerlan"))
    local b = fill(newSession({ seedMode = "random", seedValue = tostring(shown) }), 12)
    b:drawBracket(0)

    assertEq(pairing(b), pairing(a), "dieselbe Auslosung aus der abgelesenen Zahl")
end)

case("die Setznummer steht nach der Auslosung an jedem Teilnehmer", function()
    local s = fill(newSession({ seedMode = "manual" }), 8)
    s:drawBracket(0)
    assertEq(s.t.participants["p_01"].seed, 1, "Setznummer 1")
    assertEq(s.t.participants["p_08"].seed, 8, "Setznummer 8")
end)

-- ---------------------------------------------------------------------------
-- Einstellungen vor der Auslosung
-- ---------------------------------------------------------------------------

case("ein Formatwechsel legt das Turnier neu an und behaelt die Anmeldeliste", function()
    local s = fill(newSession(), 6)
    assertTrue(s:setConfig({ format = "groups_then_elim" }), "umgestellt")

    assertEq(s.t.config.format, "groups_then_elim", "neues Format")
    assertEq(s:count(), 6, "alle sechs noch da")
    assertEq(s:nameOf("p_01"), "Michi", "und in derselben Reihenfolge")

    -- Das Log muss zum Zustand passen: Es ist die Wahrheit (§4), also darf
    -- keine Konfiguration daneben stehen, die es nicht kennt.
    local rebuilt = Model.replay(s.t.log)
    assertEq(rebuilt.config.format, "groups_then_elim", "das Log traegt das Format")
    assertTrue(Model.diff(rebuilt, s.t), "Log und Zustand stimmen ueberein")
end)

case("nach der Auslosung aendert sich die Konfiguration nicht mehr", function()
    local s = fill(newSession(), 4)
    s:drawBracket(0)
    assertFalse(s:setConfig({ parallelMatches = 4 }), "gesperrt")
end)

-- ---------------------------------------------------------------------------
-- Anwesenheit und Aufruf (§5)
-- ---------------------------------------------------------------------------

case("ohne Netz gilt jeder Angemeldete als anwesend -- sonst ruft der Scheduler nie auf", function()
    local s = fill(newSession({ config = { format = "single_elim", parallelMatches = 2 } }), 4)
    s:drawBracket(100)

    local called = 0
    for _, m in ipairs(s:callList()) do
        if m.status == Model.STATUS.READY then called = called + 1 end
    end
    assertEq(called, 2, "zwei Matches aufgerufen (parallelMatches)")
end)

case("der Ereignisstrom meldet jedes Ereignis genau einmal", function()
    local s = fill(newSession(), 4)
    s:drawBracket(100)

    local seen = {}
    for _, ev in ipairs(s:tick(100)) do seen[#seen + 1] = ev.event end
    assertEq(seen[1], "participant_joined", "die Anmeldungen kommen mit")
    assertEq(seen[#seen], "match_called", "und am Ende der Aufruf")
    assertEq(#s:tick(100), 0, "der zweite Blick auf denselben Stand liefert nichts Neues")
end)

-- Die Bedienung darf den Strom NICHT selbst leeren: Wer ein Ergebnis
-- eintraegt, loest damit den Aufruf des naechsten Matches aus -- und genau
-- der braucht einen Ton.
case("ein Eingriff leert den Ereignisstrom nicht, er fuellt ihn", function()
    local s = fill(newSession(), 4)
    s:drawBracket(100)
    s:tick(100)

    local m = s:callList()[1]
    s:startMatch(m.id, 100)
    local events = s:tick(100)
    assertEq(#events, 1, "ein Ereignis")
    assertEq(events[1].event, "match_started", "der Matchstart")
    assertEq(s.t.matches[m.id].status, Model.STATUS.LIVE, "und das Match laeuft")
end)

-- ---------------------------------------------------------------------------
-- No-Show-Timer (E-02) -- die Zahl, die die Anzeige zeigt
-- ---------------------------------------------------------------------------

case("die Restzeit zaehlt vom Aufruf herunter", function()
    local s = fill(newSession(), 4)
    s:drawBracket(1000)

    local m = s:callList()[1]
    assertEq(s:remaining(m, 1000), 180, "volle Frist")
    assertEq(s:remaining(m, 1120), 60, "nach zwei Minuten")
    assertEq(s:remaining(m, 1300), 0, "nie negativ")
end)

case("ein angehaltener Timer friert die Restzeit ein (E-02)", function()
    local s = fill(newSession(), 4)
    s:drawBracket(1000)
    local m = s:callList()[1]

    s:togglePause(m.id, 1060)
    assertEq(s:remaining(m, 1200), 120, "steht bei 120, egal wie spaet es ist")
    assertTrue(s:isPaused(m.id), "und gilt als angehalten")

    s:togglePause(m.id, 1200)
    assertEq(s:remaining(m, 1200), 120, "laeuft von dort weiter")
    assertEq(s.t.matches[m.id].status, Model.STATUS.READY,
        "und in der Pause ist kein Walkover passiert")
end)

case("die Vorwarnung kommt bei 30 Sekunden und genau einmal", function()
    local s = fill(newSession(), 4)
    s:drawBracket(1000)
    local m = s:callList()[1]

    local function warnings(at)
        local n = 0
        for _, ev in ipairs(s:tick(at)) do
            if ev.event == "no_show_warning" and ev.matchId == m.id then n = n + 1 end
        end
        return n
    end

    assertEq(warnings(1100), 0, "bei 80 Sekunden Restzeit noch nicht")
    assertEq(warnings(1155), 1, "bei 25 Sekunden Restzeit")
    assertEq(warnings(1160), 0, "und danach nicht noch einmal")
end)

case("die Vorwarnung steht NICHT im Log -- sie ist ein Ton, kein Turnierzustand", function()
    local s = fill(newSession(), 4)
    s:drawBracket(1000)
    s:tick(1160)
    for _, ev in ipairs(s.t.log) do
        assertTrue(ev.event ~= "no_show_warning", "kein Eintrag im Log")
    end
end)

-- ---------------------------------------------------------------------------
-- Bedienung (M4-11, E-12)
-- ---------------------------------------------------------------------------

case("ein eingetragenes Ergebnis beendet das Match und traegt den Sieger ein", function()
    local s = fill(newSession(), 4)
    s:drawBracket(0)
    local m = s:callList()[1]
    local a = m.slotA

    s:startMatch(m.id, 0)
    assertTrue(s:enterResult(m.id, { { a = 15, b = 9 } }, 10), "angenommen")

    local done = s.t.matches[m.id]
    assertEq(done.status, Model.STATUS.FINISHED, "fertig")
    assertEq(done.winner, a, "der linke Slot gewinnt")
end)

case("ein Ergebnis laesst sich auch ohne den Umweg ueber `live` eintragen", function()
    -- Am Partyabend ist der Turnierleiter oft erst wieder da, wenn das Match
    -- schon vorbei ist. Der Weg ueber "Match laeuft" darf keine Pflicht sein.
    local s = fill(newSession(), 4)
    s:drawBracket(0)
    local m = s:callList()[1]
    assertTrue(s:enterResult(m.id, { { a = 15, b = 9 } }, 10), "angenommen")
    assertEq(s.t.matches[m.id].status, Model.STATUS.FINISHED, "fertig")
end)

case("eine Korrektur ohne Begruendung wird abgelehnt (E-12)", function()
    local s = fill(newSession(), 4)
    s:drawBracket(0)
    local m = s:callList()[1]
    s:enterResult(m.id, { { a = 15, b = 9 } }, 10)

    local ok = s:override(m.id, { { a = 9, b = 15 } }, m.slotB, "", "Rob", 20)
    assertFalse(ok, "abgelehnt")

    assertTrue(s:override(m.id, { { a = 9, b = 15 } }, m.slotB,
        "Satz vertauscht eingetippt", "Rob", 20), "mit Begruendung angenommen")

    local fixed = s.t.matches[m.id]
    assertEq(fixed.winner, m.slotB, "der andere gewinnt jetzt")
    assertTrue(fixed.overridden, "und das Match ist als korrigiert markiert")
    assertEq(fixed.overrideBy, "Rob", "mit Urheber")
end)

case("ein Aussteiger verschenkt seine offenen Matches (E-04)", function()
    local s = fill(newSession(), 4)
    s:drawBracket(0)
    local m = s:callList()[1]
    local a, b = m.slotA, m.slotB

    assertTrue(s:withdraw(a, 10), "ausgetragen")
    assertEq(s.t.matches[m.id].status, Model.STATUS.WALKOVER, "kampflos")
    assertEq(s.t.matches[m.id].winner, b, "an den Gegner")
end)

-- ---------------------------------------------------------------------------
-- Die eigene Linie (§10)
-- ---------------------------------------------------------------------------

case("die eigene Linie fuehrt gespielte und offene Matches in Ansetzungsfolge", function()
    local s = fill(newSession({ selfName = "Michi" }), 4)
    s:drawBracket(0)

    local me = s:selfId()
    assertEq(me, "p_01", "ueber den Namen gefunden")

    local line = s:playerLine(me)
    assertEq(#line.rows, 1, "ein angesetztes Match")
    assertTrue(line.next ~= nil, "und es ist das naechste")
    assertEq(line.seed, 1, "mit Setznummer")

    s:enterResult(line.next.id, { { a = 15, b = 4 } }, 10)
    local after = s:playerLine(me)
    assertEq(#after.rows, 2, "Halbfinale gespielt, Finale steht")
    assertTrue(after.rows[1].won, "das erste ist gewonnen")
end)

-- Der Gegner des naechsten Matches steht oft noch nicht fest. Dann muss dort
-- NICHTS stehen -- nicht der eigene Name.
case("solange der Gegner offen ist, ist man nicht sein eigener Gegner", function()
    local s = fill(newSession({ selfName = "Michi" }), 4)
    s:drawBracket(0)

    local me = s:selfId()
    local mine = s:playerLine(me).next
    s:enterResult(mine.id, { { a = 15, b = 4 } }, 10)

    local line = s:playerLine(me)
    local final = line.next
    assertTrue(final ~= nil, "das Finale steht an")
    assertEq(final.slotA, me, "auf der linken Seite")
    assertEq(final.slotB, nil, "rechts noch niemand")
    assertEq(line.rows[2].opponent, nil, "und in der eigenen Linie steht kein Gegner")
end)

-- F-T-06: "raus" und "hat kein offenes Match" sind zwei verschiedene Dinge.
case("ein Halbfinalverlierer ist nicht ausgeschieden -- er spielt um Platz 3", function()
    local s = fill(newSession({ config = { format = "single_elim",
                                           thirdPlaceMatch = true } }), 4)
    s:drawBracket(0)

    local semis = {}
    for _, m in ipairs(s.t:matchList()) do
        if m.round == 1 then semis[#semis + 1] = m end
    end
    assertEq(#semis, 2, "zwei Halbfinals")

    local loser = semis[1].slotB
    s:enterResult(semis[1].id, { { a = 15, b = 7 } }, 10)
    s:enterResult(semis[2].id, { { a = 15, b = 7 } }, 20)

    assertEq(s.t.participants[loser].status, Model.PARTICIPANT_STATUS.ACTIVE,
        "noch aktiv")
    local line = s:playerLine(loser)
    assertTrue(line.next ~= nil, "und hat ein offenes Match: Platz 3")
end)

-- ---------------------------------------------------------------------------
-- Persistenz und Wiederaufnahme (§7)
-- ---------------------------------------------------------------------------

case("die Datei entsteht erst mit dem ersten Teilnehmer", function()
    local fs = H.fakeFs()
    local s = newSession({ persistence = Persistence.new(fs) })
    assertEq(fs.writes, 0, "ein leeres Turnier hinterlaesst nichts")

    s:addParticipant("Michi", 0)
    assertTrue(fs.files["tournaments/t_1754900000.json"] ~= nil,
        "ab dem ersten Namen steht der Stand in der Datei")
end)

case("jede Anmeldung wird sofort gesichert -- nicht erst die Auslosung", function()
    local fs = H.fakeFs()
    local s = fill(newSession({ persistence = Persistence.new(fs) }), 4)

    local loaded = Persistence.new(fs):load("t_1754900000")
    assertTrue(loaded ~= nil, "geladen")
    assertEq(#loaded.participantOrder, 4, "alle vier stehen in der Datei")
end)

case("ein Turnier laeuft aus der Datei weiter, mitten in der Bedienung abgebrochen", function()
    local fs = H.fakeFs()
    local s = fill(newSession({ persistence = Persistence.new(fs),
                                config = { format = "single_elim",
                                           parallelMatches = 2 } }), 8)
    s:drawBracket(1000)

    -- Zwei Matches abwickeln, dann ist der Rechner weg.
    local first = s:callList()[1]
    s:startMatch(first.id, 1000)
    s:enterResult(first.id, { { a = 15, b = 3 } }, 1010)
    local played = first.id
    local winner = s.t.matches[played].winner

    -- Neu aufgebaut aus der Datei -- kein Zugriff mehr auf die alte Session.
    local reloaded = Persistence.new(fs):load("t_1754900000")
    assertTrue(reloaded ~= nil, "die Datei traegt das Turnier")

    local back = Session.resume(reloaded, {
        persistence = Persistence.new(fs), presence = "local",
    }, 2000)

    assertEq(back.t.matches[played].winner, winner, "das gespielte Ergebnis steht noch")
    assertEq(back.t.status, Model.TOURNAMENT_STATUS.RUNNING, "das Turnier laeuft")

    -- Und es laeuft zu Ende: Ergebnisse eintragen, bis ein Sieger feststeht.
    local guard = 0
    local at = 2000
    while back.t.status == Model.TOURNAMENT_STATUS.RUNNING do
        guard = guard + 1
        if guard > 200 then error("Turnier haengt: " .. H.describeOpen(back.t), 2) end
        local open = back:callList()
        if #open == 0 then
            at = at + 10
            back:tick(at)
        else
            for _, m in ipairs(open) do
                back:enterResult(m.id, H.setsFor(m, m.slotA), at)
            end
            at = at + 10
        end
    end

    assertTrue(back.t.winner ~= nil, "ein Sieger steht fest")
    assertEq(back.t.status, Model.TOURNAMENT_STATUS.FINISHED, "und das Turnier ist zu")
end)

case("beim Wiederaufnehmen gehen unterbrochene Matches zurueck in die Ansetzung (E-06)", function()
    local fs = H.fakeFs()
    local s = fill(newSession({ persistence = Persistence.new(fs) }), 4)
    s:drawBracket(1000)
    local m = s:callList()[1]
    s:startMatch(m.id, 1000)
    assertEq(s.t.matches[m.id].status, Model.STATUS.LIVE, "es laeuft")

    local reloaded = Persistence.new(fs):load("t_1754900000")
    local back = Session.resume(reloaded, { presence = "local" }, 2000)

    assertTrue(#back.reopened >= 1, "mindestens ein Match neu angesetzt")
    -- Neu angesetzt heisst: wieder aufgerufen, mit frischem Timer -- nicht
    -- verloren und nicht weitergezaehlt.
    assertEq(back.t.matches[m.id].status, Model.STATUS.READY, "wieder aufgerufen")
    assertEq(back:remaining(back.t.matches[m.id], 2000), 180, "mit voller Frist")
end)

return T
