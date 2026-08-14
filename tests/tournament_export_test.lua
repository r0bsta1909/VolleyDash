-- ============================================================================
-- tests/tournament_export_test.lua -- der Ausdruck als Versicherung (M4-10)
--
-- `05_TOURNAMENT` §7, §11. love-frei.
--
-- Geprueft wird der INHALT der Texte, nicht ihre Form: Der Export ist fuer
-- einen Menschen ohne Software, also muss drinstehen, was der braucht --
-- Namen statt Kennungen, die Herkunft offener Plaetze ("Sieger aus Match 7"),
-- die Korrektur samt Begruendung (E-12) und die fuenf Statistiken. Ein
-- Export, der huebsch aussieht und die Korrektur verschweigt, waere geschoenter
-- als die Datei.
-- ============================================================================

local Model       = require("src.tournament.model")
local Session     = require("src.tournament.session")
local Persistence = require("src.tournament.persistence")
local Export      = require("src.tournament.export")
local H           = require("tests.tournament_helper")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local assertEq, assertTrue, assertFalse = H.assertEq, H.assertTrue, H.assertFalse

local NAMES = {
    "Michi", "Anna", "Basti", "Kai", "Lea", "Tom", "Nina", "Ole",
}

local function newSession(opts)
    opts = opts or {}
    return Session.new({
        id          = opts.id or "t_1754900000",
        name        = "Testturnier",
        createdAt   = 1754900000,
        config      = opts.config or { format = "single_elim", noShowTimeout = 180,
                                       parallelMatches = 8 },
        ruleset     = { targetScore = 15 },
        rulesetHash = "deadbeef",
        persistence = opts.persistence,
        presence    = "local",
        seedMode    = "manual",
        seedValue   = opts.seedValue or "sommerlan",
    })
end

local function fill(s, n)
    for i = 1, n do s:addParticipant(NAMES[i] or ("Blob " .. i), 0) end
    return s
end

-- Enthaelt der Text die Stelle woertlich? `find` ohne Muster, damit "(S/N)"
-- und "**" keine Magie sind.
local function has(text, needle)
    return text:find(needle, 1, true) ~= nil
end

local function assertHas(text, needle, what)
    if not has(text, needle) then
        error(string.format("%s: \"%s\" fehlt im Export", what or "Inhalt", needle), 2)
    end
end

-- Alle offenen Matches zu Ende spielen; der hoeher Gesetzte gewinnt.
local function playOut(s)
    local guard = 0
    while s.t.status == Model.TOURNAMENT_STATUS.RUNNING do
        guard = guard + 1
        if guard > 200 then error("Turnier haengt: " .. H.describeOpen(s.t), 2) end
        for _, id in ipairs(s.t.matchOrder) do
            local m = s.t.matches[id]
            if m.status == Model.STATUS.READY and m.slotA and m.slotB then
                s:enterResult(id, H.setsFor(m, s.t:higherSeed(m.slotA, m.slotB)), guard * 10)
            end
        end
        s:tick(guard * 10)
    end
end

-- ---------------------------------------------------------------------------
-- Markdown
-- ---------------------------------------------------------------------------

case("der Export traegt Namen, keine Kennungen", function()
    local s = fill(newSession(), 8)
    s:drawBracket(0)
    local md = Export.markdown(s, "2026-08-14 20:00")

    assertHas(md, "# Testturnier", "Titel")
    assertHas(md, "Stand: 2026-08-14 20:00", "Zeitpunkt")
    assertHas(md, "Michi", "erster Name")
    assertHas(md, "Ole", "letzter Name")
    assertFalse(has(md, "p_0"), "keine Teilnehmerkennung im Text")
    assertFalse(has(md, "m_1"), "keine Matchkennung im Text")
end)

case("offene Matches stehen oben, mit Paarung und Herkunft", function()
    local s = fill(newSession(), 8)
    s:drawBracket(0)
    -- Die Kennungen vergibt der Generator (ab m_101); das erste Match der
    -- Ansetzung reicht.
    local first = s.t.matchOrder[1]
    local m1 = s.t.matches[first]
    s:enterResult(first, H.setsFor(m1, m1.slotA), 10)

    local md = Export.markdown(s, nil)
    assertHas(md, "## Als Naechstes", "Abschnitt")
    -- Die drei uebrigen Erstrundenmatches sind aufgerufen, mit beiden Namen.
    assertHas(md, "gegen", "Paarungen stehen da")
    assertHas(md, "aufgerufen", "Lage steht dabei")
    -- Das Halbfinale kennt seinen zweiten Mann noch nicht: Herkunft statt "?".
    assertHas(md, "Sieger aus Match", "Herkunft eines offenen Platzes")
end)

case("eine Korrektur ist markiert und traegt ihre Begruendung (E-12)", function()
    local s = fill(newSession(), 8)
    s:drawBracket(0)
    local first = s.t.matchOrder[1]
    local m1 = s.t.matches[first]
    s:enterResult(first, H.setsFor(m1, m1.slotA), 10)
    assertTrue(s:override(first, { { a = 9, b = 15 } }, m1.slotB,
        "Zettel sagt 15:9 fuer den anderen", "Rob", 20), "Korrektur angenommen")

    local md = Export.markdown(s, nil)
    assertHas(md, "korrigiert: Zettel sagt 15:9 fuer den anderen", "Begruendung")
end)

case("ein fertiges Turnier nennt den Sieger und hat nichts Offenes", function()
    local s = fill(newSession(), 8)
    s:drawBracket(0)
    playOut(s)
    assertTrue(s:isFinished(), "Turnier ist durch")

    local md = Export.markdown(s, nil)
    assertHas(md, "**Sieger: Michi**", "Sieger")
    assertHas(md, "Keine offenen Matches.", "nichts offen")
    assertHas(md, "(Spiel um Platz 3)", "Spiel um Platz 3 ist beschriftet")
    -- Statistiken: Setznummer 1 gewinnt drei Matches ohne Niederlage.
    assertHas(md, "| Michi | 3 (3/0) |", "Statistikzeile")
    assertHas(md, "| -- | -- |", "keine gemessene Rallye heisst Strich")
end)

case("die Simulationswerte aus dem Ergebnisbericht stehen im Export (§11)", function()
    local s = fill(newSession(), 4)
    s:drawBracket(0)
    local first = s.t.matchOrder[1]
    local m1 = s.t.matches[first]
    s:enterResult(first, H.setsFor(m1, m1.slotA), 10,
        { longestRally = 6.4, fastestBall = 1066, fastestBy = 1 })

    local md = Export.markdown(s, nil)
    assertHas(md, "6.4 s", "laengste Rallye mit Einheit")
    assertHas(md, "1066 px/s", "schnellster Ball mit Einheit")

    local csv = Export.csv(s)
    assertHas(csv, "6.40", "Rallye im CSV")
    assertHas(csv, "1066", "Ball im CSV")
end)

case("Gruppentabellen stehen in Beamer-Sortierung im Export", function()
    local s = fill(newSession({ config = { format = "groups_then_elim",
        noShowTimeout = 180, parallelMatches = 8 } }), 8)
    s:drawBracket(0)
    playOut(s)

    local md = Export.markdown(s, nil)
    assertHas(md, "## Gruppe 1", "erste Gruppe")
    assertHas(md, "## Gruppe 2", "zweite Gruppe")
    assertHas(md, "| Platz | Name |", "Tabellenkopf")
    assertHas(md, "| 1 | ", "ein Erstplatzierter steht da")
end)

case("ein Freilos heisst Freilos, nicht nil", function()
    local s = fill(newSession(), 6)
    s:drawBracket(0)
    local md = Export.markdown(s, nil)
    assertHas(md, "gegen Freilos", "Freilos ausgeschrieben")
    assertFalse(has(md, "nil"), "kein nil im Text")
end)

-- ---------------------------------------------------------------------------
-- CSV
-- ---------------------------------------------------------------------------

case("das CSV traegt je Teilnehmer eine Zeile mit den fuenf Statistiken", function()
    local s = fill(newSession(), 8)
    s:drawBracket(0)
    playOut(s)

    local csv = Export.csv(s)
    local lines = {}
    for line in csv:gmatch("[^\n]+") do lines[#lines + 1] = line end

    assertEq(lines[1], "Name,Status,Matches,Siege,Niederlagen,Saetze gewonnen,"
        .. "Saetze verloren,Punkte fuer,Punkte gegen,"
        .. "Laengste Rallye (s),Schnellster Ball (px/s)", "Kopfzeile mit Einheiten")
    assertEq(#lines, 9, "acht Teilnehmer, acht Zeilen")
    assertHas(csv, "Michi,winner,3,3,0,", "die Zeile des Siegers")
    -- Ohne Messwert bleibt das Feld leer -- 0 waere ein erfundenes Ergebnis.
    assertTrue(lines[2]:find(",,", 1, true) ~= nil or lines[2]:sub(-1) == ",",
        "leere Messfelder, keine Nullen")
end)

case("ein Name mit Komma zerlegt die Zeile nicht", function()
    local s = newSession()
    s:addParticipant('Blob, der "Echte"', 0)
    for i = 2, 4 do s:addParticipant(NAMES[i], 0) end

    local csv = Export.csv(s)
    assertHas(csv, '"Blob, der ""Echte""",', "Feld ist gequotet")
end)

-- ---------------------------------------------------------------------------
-- Schreiben (Persistence:export)
-- ---------------------------------------------------------------------------

case("X schreibt beide Dateien unter festem Namen in den Speicherordner", function()
    local fs = H.fakeFs()
    local p = Persistence.new(fs)
    local s = fill(newSession({ persistence = p }), 8)
    s:drawBracket(0)

    local files, err = p:export(s, "2026-08-14 20:00")
    assertTrue(files ~= nil, "Export gelungen: " .. tostring(err))
    assertEq(files[1], "tournaments/t_1754900000_bracket.md", "Markdown-Name")
    assertEq(files[2], "tournaments/t_1754900000_statistik.csv", "CSV-Name")
    assertHas(fs.files[files[1]], "# Testturnier", "Markdown liegt da")
    assertHas(fs.files[files[2]], "Name,Status,Matches", "CSV liegt da")

    -- Fester Name: Der zweite Export ersetzt den ersten, kein Wildwuchs.
    local before = 0
    for _ in pairs(fs.files) do before = before + 1 end
    p:export(s, "2026-08-14 21:00")
    local after = 0
    for _ in pairs(fs.files) do after = after + 1 end
    assertEq(after, before, "keine neuen Dateien beim zweiten Druck")
    assertHas(fs.files[files[1]], "21:00", "aber der neue Stand")
end)

return T
