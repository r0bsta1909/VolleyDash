-- ============================================================================
-- conf.lua -- LOEVE-Konfiguration (M0-01, F-07, ADR-001)
--
-- Laeuft vor allem anderen, noch vor main.lua. Was hier steht, kann zur
-- Laufzeit nicht mehr sauber nachgeholt werden.
-- ============================================================================

-- Ein Testlauf braucht kein Fenster (M2-01). Ohne diese Weiche startet
-- `love . --test` eine Grafikausgabe, und damit laesst sich der Lauf auf
-- einem CI-Laeufer ohne Bildschirm nicht starten -- genau das ist aber
-- noetig, um T-N-07 (gleiche Bytes auf Windows und macOS) zu beantworten.
-- Dasselbe gilt fuer den Netzwerk-Harness aus M2-10: er faehrt Simulation und
-- Transport, aber nichts, was jemand ansehen muesste.
-- `arg` steht in love.conf bereits zur Verfuegung.
--
-- WER HIER EIN FLAG VERGISST, MERKT ES ERST AUF EINEM LAEUFER OHNE BILDSCHIRM.
-- Gemessen 2026-08-13: `--tournament-selftest` fehlte in dieser Liste. Lokal
-- lief er deshalb mit Fenster durch und niemandem fiel etwas auf; in der CI
-- blieb der Schritt drei Minuten stehen, bis die Zeitschranke ihn abbrach.
-- Faustregel: Ein Flag, das `M.runTools` bedient, gehoert hierher -- die
-- Autopiloten (`--net-auto-*`, `--tournament-auto=`) ausdruecklich NICHT, die
-- fahren das echte Spiel und brauchen das Bild.
local HEADLESS = {
    "--test", "--test-no-love",
    "--net-selftest", "--net-host", "--net-client",
    "--tournament-selftest",
}

local function isTestRun()
    for _, a in ipairs(arg or {}) do
        for _, flag in ipairs(HEADLESS) do
            if a == flag or a:sub(1, #flag + 1) == flag .. "=" then return true end
        end
    end
    return false
end

function love.conf(t)
    -- Speicherordner. Kleingeschrieben und passend zum Bundle-Identifier
    -- games.4brain.volleydash (CLAUDE.md §1). `06_BUILD` §2 nennt hier noch
    -- "VolleyDash"; das stammt aus der Zeit vor ADR-010, und ein Wechsel
    -- wuerde nur die vorhandene Prefs-Datei verwaisen lassen.
    t.identity = "volleydash"

    -- Nicht Kosmetik: LOEVE warnt bei abweichender Laufzeitversion. Ohne den
    -- Eintrag startet das Spiel unter einer kuenftigen 12.0 kommentarlos mit
    -- moeglicherweise anderem Verhalten (ADR-001).
    t.version = "11.5"

    t.console = false   -- fuer eine Konsole gibt es lovec.exe

    -- Der Testlauf endet hier: kein Fenster, keine Grafik, kein Ton.
    if isTestRun() then
        t.window = false
        t.modules.window   = false
        t.modules.graphics = false
        t.modules.audio    = false
        t.modules.sound    = false
        t.modules.joystick = false
        return
    end

    t.window.title     = "Volley Dash"
    -- 4:3 wie das logische Feld (800 x 600, ADR-004), damit im Fenster keine
    -- Balken noetig sind. Andere Verhaeltnisse fangen Letterbox und Pillarbox
    -- in src/render/viewport.lua ab.
    t.window.width     = 1280
    t.window.height    = 960
    t.window.minwidth  = 640
    t.window.minheight = 480
    t.window.resizable = true
    t.window.vsync     = 1
    t.window.highdpi   = true    -- Retina-Macs

    -- Fenster- und Taskleistensymbol (M1-06). Das Symbol der EXE selbst steckt
    -- in deren Ressourcen und wird beim Build gesetzt, nicht hier -- siehe
    -- `06_BUILD` §3.
    t.window.icon      = "assets/icon.png"

    -- Nicht benutzte Module abschalten: schnellerer Start, weniger Speicher.
    -- Zielhardware sind acht Jahre alte Laptops (CLAUDE.md §7).
    t.modules.physics = false    -- Box2D; die Physik ist handgeschrieben
    t.modules.video   = false
    t.modules.touch   = false
    t.modules.mouse   = false    -- Menues und Spiel laufen ueber die Tastatur
    t.modules.thread  = false    -- Netzwerk laeuft gepollt, nicht im Thread (ADR-003)

    -- Bleibt an, auch wenn es noch ungenutzt aussieht:
    --   joystick  Gamepad-Unterstuetzung (GDD §7)
    --   system    Plattformkennung im Aufzeichnungskopf
    --   data      Serialisierung und Pruefsummen ab M2
    -- `06_BUILD` §2 nennt zusaetzlich t.modules.sensor -- den Schalter gibt es
    -- erst ab LOEVE 12.0, unter 11.5 laeuft er ins Leere.
end
