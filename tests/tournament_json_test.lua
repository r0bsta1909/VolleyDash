-- ============================================================================
-- tests/tournament_json_test.lua -- Ebene B: das Persistenzformat (ADR-020)
--
-- Die beiden Faelle, auf die es ankommt: Ein Wert, der herausgeht, kommt
-- bitgleich zurueck -- und eine ABGESCHNITTENE Datei wird als kaputt erkannt
-- statt halb gelesen. Der zweite Fall ist der Normalfall nach einem Absturz.
--
-- love-frei.
-- ============================================================================

local Json = require("src.tournament.json")
local H    = require("tests.tournament_helper")

local T = {}
local function case(name, fn) T[#T + 1] = { name = name, fn = fn } end

local assertEq, assertTrue = H.assertEq, H.assertTrue

local function roundtrip(value)
    local text = Json.encode(value)
    local back, err = Json.decode(text)
    if back == nil and err then error("Decode gescheitert: " .. err, 2) end
    return back, text
end

case("Grundwerte gehen unveraendert hin und zurueck", function()
    assertEq(roundtrip(true), true, "true")
    assertEq(roundtrip(false), false, "false")
    assertEq(roundtrip(0), 0, "null")
    assertEq(roundtrip(-17), -17, "negativ")
    assertEq(roundtrip(15), 15, "Punktestand")
    assertEq(roundtrip(""), "", "leere Zeichenkette")
    assertEq(roundtrip("Blob 01"), "Blob 01", "Name")
end)

case("Bruchzahlen kommen bitgleich zurueck -- dafuer steht %.17g", function()
    for _, v in ipairs({ 0.1, 1 / 3, 0.75, 1754900000.5, -0.0000001, 2 ^ 40 + 0.5 }) do
        assertEq(roundtrip(v), v, "Wert " .. tostring(v))
    end
end)

case("Sonderzeichen ueberleben", function()
    assertEq(roundtrip('Anfuehrung " und Schraegstrich \\'),
             'Anfuehrung " und Schraegstrich \\', "Escapes")
    assertEq(roundtrip("Zeile\nZeile\tTab"), "Zeile\nZeile\tTab", "Steuerzeichen")
end)

case("Listen und Objekte bleiben, was sie waren", function()
    local back = roundtrip({ 1, 2, 3 })
    assertEq(#back, 3, "Listenlaenge")
    assertEq(back[2], 2, "Element")

    back = roundtrip({ a = 1, b = "x", c = { d = true } })
    assertEq(back.a, 1, "Zahl")
    assertEq(back.b, "x", "Text")
    assertEq(back.c.d, true, "verschachtelt")
end)

case("eine leere Tabelle wird zur leeren Liste", function()
    -- Im Turnierstand ist jede potenziell leere Tabelle eine Liste: `sets`,
    -- `log`, `unresolved`. Objekte haben dort immer Felder.
    assertEq(Json.encode({}), "[]", "leer")
    assertEq(#Json.decode("[]"), 0, "zurueck")
end)

case("gleiche Daten ergeben gleiche Bytes -- die Schluessel sind sortiert", function()
    local a = Json.encode({ zebra = 1, alpha = 2, mitte = 3 })
    local b = Json.encode({ mitte = 3, alpha = 2, zebra = 1 })
    assertEq(a, b, "byteweise gleich")
    assertTrue(a:find('"alpha"') < a:find('"mitte"'), "alphabetisch")
end)

case("ein verschachtelter Turnierstand ueberlebt den Umweg", function()
    local doc = {
        version = 1,
        log = {
            { seq = 1, event = "tournament_created", t = 1754900000 },
            { seq = 2, event = "match_finished", matchId = "m_101",
              winner = "p_01", sets = { { a = 15, b = 12 }, { a = 9, b = 15 } } },
        },
    }
    local back = roundtrip(doc)
    assertEq(back.log[2].sets[2].b, 15, "tief liegender Wert")
    assertEq(back.log[2].matchId, "m_101", "Kennung")
    assertEq(#back.log, 2, "Log-Laenge")
end)

case("null wird zu nichts, nicht zu einer Zeichenkette", function()
    local back = Json.decode('{"winner": null, "id": "m_101"}')
    assertEq(back.winner, nil, "winner fehlt")
    assertEq(back.id, "m_101", "der Rest steht")
end)

-- ---------------------------------------------------------------------------
-- Der eigentliche Grund fuer diese Suite
-- ---------------------------------------------------------------------------

case("eine abgeschnittene Datei wird erkannt, nicht halb gelesen", function()
    local text = Json.encode({ log = { { seq = 1, event = "match_finished",
                                         sets = { { a = 15, b = 12 } } } } })
    for _, cut in ipairs({ 0.25, 0.5, 0.75, 0.9 }) do
        local broken = text:sub(1, math.floor(#text * cut))
        local value, err = Json.decode(broken)
        assertEq(value, nil, string.format("bei %d%% abgeschnitten", cut * 100))
        assertTrue(err ~= nil and #err > 0, "mit Meldung")
    end
end)

case("die Fehlermeldung sagt, wo es hakt", function()
    local _, err = Json.decode('{"a": 1, "b": }')
    assertTrue(err ~= nil, "es gibt eine Meldung")
    assertTrue(err:find("Zeichen") ~= nil, "mit Position: " .. tostring(err))
end)

case("Muell hinter dem Ende faellt auf", function()
    local value, err = Json.decode('{"a":1} und dann noch was')
    assertEq(value, nil, "abgelehnt")
    assertTrue(err:find("Ende") ~= nil, "Meldung nennt das Ende: " .. tostring(err))
end)

case("kein Text ist kein JSON", function()
    assertEq(Json.decode(nil), nil, "nil")
    assertEq(Json.decode(""), nil, "leer")
    assertEq(Json.decode("   "), nil, "nur Leerraum")
end)

case("Unendlich und NaN werden abgelehnt statt still verstuemmelt", function()
    assertEq(pcall(Json.encode, { x = 1 / 0 }), false, "Unendlich")
    assertEq(pcall(Json.encode, { x = 0 / 0 }), false, "NaN")
end)

case("eine Funktion im Zustand ist ein Fehler, keine stille Luecke", function()
    -- Der Fall tritt auf, wenn jemand `onAppend` mitschreiben laesst.
    assertEq(pcall(Json.encode, { fn = print }), false, "Funktion abgelehnt")
end)

return T
