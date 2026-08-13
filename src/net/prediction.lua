-- ============================================================================
-- src/net/prediction.lua -- der Gast bewegt seinen eigenen Blob sofort (M3-01)
--
-- `04_NETCODE_SPEC` §8, ADR-017. Vorhergesagt wird AUSSCHLIESSLICH der eigene
-- Blob. Ball, Gegner und Punktestand kommen weiter allein vom Host (ADR-002).
--
-- Drei Punkte, die diese Datei ausmachen -- alle drei kosten nichts, wenn man
-- sie von Anfang an richtig macht, und sind hinterher nicht mehr einzubauen:
--
--   AUFRUFEN, NICHT NACHBAUEN. Die Bewegung kommt aus `Step.applyImpulses`,
--   `Step.updateBlobTimers` und `Physics.updateBlob`. Nachgebaut waere sie
--   eine zweite Wahrheit ueber die Zahlen aus `02_CODE_AUDIT` §4.
--
--   ZEITRICHTIG VERGLEICHEN. Ein Snapshot beschreibt die Vergangenheit. Er
--   traegt `ackInputTick` -- den Eingabetick, den der Host darin verarbeitet
--   hat. Verglichen wird die Vorhersage zu genau diesem Tick, nicht die
--   aktuelle. Sonst findet man bei jedem Lauf 30 px Abweichung, obwohl nichts
--   falsch ist, und der Blob gummibandelt.
--
--   ALS SICHTVERSATZ KORRIGIEREN. Die Abweichung geht sofort in die
--   Simulationsposition; gezeichnet wird sie plus einem Versatz, der in vier
--   Ticks auf null laeuft. Damit rechnen die folgenden Ticks mit der Wahrheit
--   des Hosts, und das Bild springt trotzdem nicht.
--
-- love-frei und ohne Netz testbar (`tests/prediction_test.lua`): das ist der
-- Grund, warum das hier steht und nicht in `client.lua`.
-- ============================================================================

local World   = require("src.sim.world")
local State   = require("src.sim.state")
local Step    = require("src.sim.step")
local Physics = require("src.sim.physics")

local Prediction = {}
Prediction.__index = Prediction

-- `04_NETCODE_SPEC` §8, beide Zahlen woertlich.
Prediction.THRESHOLD     = 2     -- px, darunter wird nicht korrigiert
Prediction.CORRECT_TICKS = 4     -- ueber so viele Ticks laeuft der Versatz aus

-- Gut eine Sekunde Vorhersage. Wer laenger als das auf eine Bestaetigung
-- wartet, hat kein Vorhersageproblem, sondern kein Netz.
Prediction.HISTORY = 64

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

-- `slot` ist der eigene Platz (1 oder 2) und entscheidet ueber die Waende:
-- Spieler 1 spielt zwischen linker Wand und Netz, Spieler 2 zwischen Netz und
-- rechter Wand -- dieselbe Aufteilung wie in `Step.tick`.
function Prediction.new(slot, ruleset)
    local self = setmetatable({
        slot    = slot,
        ruleset = ruleset,

        -- Ein Blob in der Form, die `src/sim/state.lua` festlegt. Aus der
        -- Simulation geholt statt hier beschrieben: ein Feld, das dort
        -- dazukommt, fehlt sonst genau hier und nirgends sonst.
        blob    = State.new(ruleset).blobs[slot],

        -- `applyImpulses` erwartet einen Zustand mit `blobs`. Mehr liest es
        -- nicht -- die Vorhersage braucht deshalb keinen ganzen Zustand.
        mini    = nil,

        prevMask = 0,
        events   = {},        -- wird verworfen, siehe unten

        history  = {},        -- Eingabetick -> { x, y }
        lastAck  = -1,

        offsetX  = 0,         -- Sichtversatz, laeuft in CORRECT_TICKS aus
        offsetY  = 0,
        corrLeft = 0,

        corrections = 0,      -- Zaehler fuer das F3-Overlay
        takeovers   = 0,      -- harte Uebernahmen (Aufschlag), kein Fehler
        compared    = 0,
        skipped     = 0,      -- Snapshots ohne verwertbaren Ack
    }, Prediction)

    self.mini = { blobs = { self.blob } }
    return self
end

function Prediction:groundY()
    return self.ruleset.blobGroundY or 500
end

-- Dieselben Grenzen, die `Step.tick` an `Physics.updateBlob` uebergibt.
function Prediction:walls()
    local netX = World.NET_X
    if self.slot == 1 then return 0, netX end
    return netX + World.NET_WIDTH, World.WIDTH
end

-- ---------------------------------------------------------------------------
-- Ein Tick
--
-- `phase` und `tick` kommen von aussen: die Phase aus dem zuletzt angewandten
-- Snapshot, der Tick aus dem Eingabezaehler des Clients. Beide gehoeren nicht
-- hierher -- die Vorhersage weiss nichts vom Netz.
-- ---------------------------------------------------------------------------

function Prediction:advance(mask, phase, tick)
    -- `Step.tick` kehrt in `menu` und `gameover` sofort zurueck, ohne einen
    -- Blob zu bewegen. Wer das hier nicht nachvollzieht, laeuft im Abpfiff-
    -- Bild langsam vom Host weg.
    local moving = (phase == "serve" or phase == "play")

    if moving then
        local dt = World.TICK_DT
        local blob = self.blob
        local left, right = self:walls()

        -- Die Ereignisse der Vorhersage werden VERWORFEN. Kosmetik hat genau
        -- eine Quelle, und das ist der Snapshot-Vergleich aus M3-02. Zwei
        -- Quellen hiessen: der eigene Sprung staubt zweimal, und beim ersten
        -- Paketverlust staubt er einmal, ohne dass jemand gesprungen ist.
        local events = self.events
        for i = #events, 1, -1 do events[i] = nil end

        Step.applyImpulses(self.mini, 1, mask, self.prevMask, self.ruleset, events)
        Step.updateBlobTimers(blob, dt, mask, self.ruleset)
        Physics.updateBlob(blob, self.slot, dt, left, right, self.ruleset,
            self:groundY(), events)
    end

    self.prevMask = mask

    -- Der Sichtversatz laeuft linear aus, unabhaengig von der Phase: sonst
    -- bliebe er im Abpfiff-Bild stehen.
    if self.corrLeft > 0 then
        local factor = (self.corrLeft - 1) / self.corrLeft
        self.offsetX = self.offsetX * factor
        self.offsetY = self.offsetY * factor
        self.corrLeft = self.corrLeft - 1
        if self.corrLeft == 0 then self.offsetX, self.offsetY = 0, 0 end
    end

    self:remember(tick)
end

-- Der Eintrag wird ueberschrieben, nicht neu angelegt: 60 Tabellen je Sekunde
-- sind auf der Zielhardware (`CLAUDE.md` §7) unnoetiger Allokationsdruck.
function Prediction:remember(tick)
    if type(tick) ~= "number" then return end
    local index = tick % Prediction.HISTORY
    local entry = self.history[index]
    if entry then
        entry.tick, entry.x, entry.y = tick, self.blob.x, self.blob.y
    else
        self.history[index] = { tick = tick, x = self.blob.x, y = self.blob.y }
    end
end

function Prediction:predictedAt(tick)
    local entry = self.history[tick % Prediction.HISTORY]
    if entry and entry.tick == tick then return entry end
    return nil
end

-- ---------------------------------------------------------------------------
-- Abgleich mit dem Host
--
-- `hard` heisst: der Host hat den Blob versetzt, nicht bewegt (Aufschlag nach
-- einem Punkt, `Rules.resetBall`). Das ist keine falsche Vorhersage, sondern
-- eine Ansage -- sie wird sofort uebernommen und zaehlt nicht als Korrektur.
-- ---------------------------------------------------------------------------

function Prediction:reconcile(snap, hard)
    local hostX = (self.slot == 1) and snap.blob1X or snap.blob2X
    local hostY = (self.slot == 1) and snap.blob1Y or snap.blob2Y
    local hostVY = (self.slot == 1) and snap.blob1VY or snap.blob2VY

    if hard then
        self.takeovers = self.takeovers + 1
        self:takeOver(hostX, hostY, hostVY)
        return true
    end

    local ack = snap.ackInputTick
    if type(ack) ~= "number" or ack < 0 or ack <= self.lastAck then
        -- Kein Fortschritt: der Host hat die letzte Maske wiederholt (§7).
        -- Ein Vergleich gegen einen Tick, den er mit fremder Eingabe gerechnet
        -- hat, meldet einen Fehler, den niemand gemacht hat.
        self.skipped = self.skipped + 1
        return false
    end

    local mine = self:predictedAt(ack)
    if not mine then
        -- Aelter als der Ringpuffer, oder der Tick lag vor dem Matchstart.
        self.lastAck = ack
        self.skipped = self.skipped + 1
        return false
    end

    self.lastAck = ack
    self.compared = self.compared + 1

    local dx = hostX - mine.x
    local dy = hostY - mine.y
    if (dx * dx + dy * dy) <= (Prediction.THRESHOLD * Prediction.THRESHOLD) then
        return false
    end

    self.corrections = self.corrections + 1
    -- Fuer das Protokoll (`07_TEST_PLAN` §5): welcher Eingabetick, wie weit
    -- daneben. Ohne diese zwei Zahlen ist ein steigender Zaehler im WLAN
    -- nicht von einem Anzeigefehler zu unterscheiden.
    self.lastErrorTick = ack
    self.lastErrorX, self.lastErrorY = dx, dy
    self:applyError(dx, dy)
    return true
end

-- Die Abweichung sofort in die Simulationsposition, sichtbar aber erst ueber
-- vier Ticks. Der Versatz zeigt dabei genau in die Gegenrichtung, damit das
-- gezeichnete Bild in diesem Frame unveraendert bleibt.
function Prediction:applyError(dx, dy)
    self.blob.x = self.blob.x + dx
    self.blob.y = self.blob.y + dy
    self.offsetX = self.offsetX - dx
    self.offsetY = self.offsetY - dy
    self.corrLeft = Prediction.CORRECT_TICKS

    -- Der Ringpuffer wird mitgezogen: die gespeicherten Positionen sind ab
    -- jetzt in der Rechnung des Hosts. Ohne das faende der naechste Snapshot
    -- dieselbe Abweichung noch einmal.
    for _, entry in pairs(self.history) do
        entry.x = entry.x + dx
        entry.y = entry.y + dy
    end
end

-- Harte Uebernahme: Position, Fallgeschwindigkeit, kein Versatz. Der Blob
-- SOLL hier springen -- der Host hat ihn auf die Aufschlagposition gesetzt.
function Prediction:takeOver(hostX, hostY, hostVY)
    self.blob.x, self.blob.y = hostX, hostY
    self.blob.vy = hostVY or 0
    self.blob.tiltAngle = 0
    self.offsetX, self.offsetY, self.corrLeft = 0, 0, 0
    self.history = {}
    self.lastAck = -1
end

-- Beim Matchstart und beim Wiedereinstieg: alles auf Anfang, Zaehler bleiben.
function Prediction:reset(blob)
    if blob then
        for k, v in pairs(blob) do self.blob[k] = v end
    end
    self.prevMask = 0
    self.history = {}
    self.lastAck = -1
    self.offsetX, self.offsetY, self.corrLeft = 0, 0, 0
end

-- ---------------------------------------------------------------------------
-- Ergebnis
--
-- Schreibt die vorhergesagte Lage in den Blob des angezeigten Zustands. Die
-- Renderschicht und das HUD lesen ausschliesslich dort -- die Vorhersage
-- kennt weder das eine noch das andere.
-- ---------------------------------------------------------------------------

function Prediction:writeInto(target)
    for k, v in pairs(self.blob) do target[k] = v end
    target.x = self.blob.x + self.offsetX
    target.y = self.blob.y + self.offsetY
end

return Prediction
