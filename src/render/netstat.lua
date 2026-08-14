-- ============================================================================
-- src/render/netstat.lua -- das F3-Overlay (M2-09)
--
-- Zeigt genau die Werte, nach denen die Fehlervorlage im Repo fragt. Das ist
-- der Zweck: wenn am Partyabend jemand sagt "es ruckelt", ist die Antwort
-- entweder eine Zahl oder eine Vermutung. F3 macht daraus eine Zahl.
--
--   RTT        Hin und zurueck, gemessen ueber PING/PONG (§5) -- also inklusive
--              der Zeit, die die Gegenseite in ihrer eigenen Schleife braucht.
--              Der ENet-Wert steht daneben; weichen sie stark ab, liegt es
--              nicht am Netz.
--   Verlust    ENet-Schaetzung in Prozent
--   Replay     wie viele Ticks je Snapshot wieder vorgespielt werden
--              (ADR-025; im gesunden Betrieb RTT/2 + 1)
--   Rueckstau  was in der Queue wartete, bevor der neueste genommen wurde (Soll: 0)
--   gehalten   Ticks ohne neuen Snapshot -- die traegt die lokale Simulation
--   verworfen  uebersprungene, weil veraltete Snapshots
--   Wdh.       Ticks, in denen der Host die letzte Maske wiederholt hat (§7)
--   Korrektur  Vorhersagefehler des eigenen Blobs: Abweichung > 2 px zur
--              Host-Position beim selben Eingabetick (§8, M3-01). Im LAN
--              gehoert hier eine kleine Zahl hin, die nicht dauernd steigt.
--              Uebernahmen nach einem Punkt zaehlen NICHT mit -- sie sind
--              eine Ansage des Hosts, kein Fehler.
--   Desync     Protokollfehler: die Pruefsumme des Hosts ueber die gepackten
--              Snapshot-Bytes passt nicht zu der, die der Client aus dem
--              gelesenen Snapshot rechnet (§9, M3-03). Erwartet ist 0/N --
--              alles andere heisst, dass die beiden Rechner verschiedene
--              Fassungen sprechen. `fehlt` sind Pruefsummen ohne Snapshot;
--              die sind Paketverlust, kein Befund.
--
-- Zwei Fehlerklassen, zwei Zahlen (ADR-018): KORREKTUR ist die Vorhersage,
-- DESYNC das Protokoll. Ein gemeinsamer Wert sagte im Fehlerfall nicht,
-- welche von beiden schuld ist -- und genau das ist die Frage, die abends
-- gestellt wird.
-- ============================================================================

local World  = require("src.sim.world")
local Assets = require("src.app.assets")

local Netstat = {}

local function line(text, x, y)
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.print(text, x + 1, y + 1)
    love.graphics.setColor(0.6, 1, 0.7, 1)
    love.graphics.print(text, x, y)
end

local function ms(value)
    if not value then return "--" end
    return string.format("%.0f ms", value)
end

function Netstat.draw(info)
    local rows = {
        string.format("ROLLE     %s  Slot %s", info.role or "?", tostring(info.slot or "-")),
        string.format("TICK      %d", info.tick or 0),
        string.format("RTT       %s (ENet %s)", ms(info.rtt), ms(info.peerRtt)),
        string.format("VERLUST   %.1f %%", (info.loss or 0) * 100),
    }

    if info.role == "client" then
        -- Seit ADR-025 gibt es keinen Anzeigeversatz mehr -- die Welt wird
        -- lokal vorgerechnet und je Snapshot neu aufgesetzt. REPLAY sagt, wie
        -- viele Ticks dabei wieder vorgespielt werden (RTT/2 + 1 im gesunden
        -- Betrieb); RUECKSTAU, was in der Queue wartete (Soll: 0).
        rows[#rows + 1] = string.format("REPLAY    %d Ticks  (Rueckstau %d)",
            info.replay or 0, info.buffer or 0)
        rows[#rows + 1] = string.format("EMPFANGEN %d", info.received or 0)
        rows[#rows + 1] = string.format("GEHALTEN  %d", info.held or 0)
        rows[#rows + 1] = string.format("VERWORFEN %d", info.dropped or 0)
    else
        rows[#rows + 1] = string.format("EINGABEN  %d", info.inputs or 0)
        rows[#rows + 1] = string.format("WDH.      %d", info.repeats or 0)
        rows[#rows + 1] = string.format("VERWORFEN %d", info.dropped or 0)
        rows[#rows + 1] = string.format("UNGUELTIG %d", info.invalid or 0)
        rows[#rows + 1] = string.format("ACK-TICK  %s", tostring(info.ack or "-"))
    end

    rows[#rows + 1] = string.format("KORREKTUR %d", info.corrections or 0)

    if info.role == "client" then
        rows[#rows + 1] = string.format("DESYNC    %d/%d  (%d fehlt)",
            info.desync or 0, info.checked or 0, info.missing or 0)
    end

    -- Unterhalb der Punktanzeige (die steht bei y = 30): ein Overlay, das den
    -- Spielstand verdeckt, waere genau dann im Weg, wenn man es braucht.
    local width, lineHeight, top = 290, 16, 76
    local height = #rows * lineHeight + 14

    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 8, top, width, height, 4, 4)

    Assets.setFont(13)
    for i, text in ipairs(rows) do
        line(text, 16, top + 6 + (i - 1) * lineHeight)
    end

    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.print(info.netlog and "F4 REC" or "F3/F4",
        8 + width - 52, top + height - 18)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Meldung ueber dem Feld, wenn das Match pausiert ist (§12). Kein Overlay im
-- Debug-Sinn: das hier sieht jeder, auch ohne F3 -- ein stehendes Bild ohne
-- Erklaerung ist der Moment, in dem jemand den Stecker zieht.
function Netstat.drawPause(text, secondsLeft)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, World.HEIGHT / 2 - 60, World.WIDTH, 120)

    Assets.setFont(32)
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.printf(text or "Warte ...", 0, World.HEIGHT / 2 - 45, World.WIDTH, "center")

    Assets.setFont(20)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf(string.format("noch %d s", secondsLeft or 0),
        0, World.HEIGHT / 2 + 5, World.WIDTH, "center")
    love.graphics.setColor(1, 1, 1, 1)
end

return Netstat
