-- ============================================================================
-- src/net/prediction.lua -- der Gast simuliert die ganze Welt vor (ADR-025)
--
-- `04_NETCODE_SPEC` §8. Bis C.2 sagte diese Datei nur den EIGENEN Blob vorher
-- (ADR-017); Ball und Gegner kamen aus einem Interpolationspuffer und damit
-- aus der Vergangenheit. Zwei Zeitbasen in einem Bild -- der Ball wurde beim
-- Gast sichtbar IM Blob getroffen statt aussen, gemeldet an beiden LAN-Abenden.
--
-- Seit ADR-025 haelt der Gast einen VOLLEN Zustand und schreitet ihn mit der
-- echten Physik fort -- Vorbild ist der Netzwerkmodus von Blobby Volley 2
-- (ganze Welt lokal, Serverzustand hart uebernehmen), dazu die zeitrichtige
-- Abgleichmechanik aus M3:
--
--   REBASE UND REPLAY. Jeder Snapshot setzt den Zustand neu auf; danach werden
--   die eigenen Masken seit dessen `ackInputTick` wieder vorgespielt. Ball,
--   Gegner und eigener Blob stammen damit aus EINEM Simulationsschritt.
--
--   AUFRUFEN, NICHT NACHBAUEN. Es rechnet `Step.tick` -- dieselbe Funktion wie
--   beim Host und im lokalen Spiel. Eine eigene Bewegung hier waere eine
--   zweite Wahrheit ueber die Zahlen aus `02_CODE_AUDIT` §4.
--
--   STEHT DER ACK, BLEIBT DER EIGENE BLOB LOKAL. Bei Eingabeverlust (§7) hat
--   der Host mit wiederholten Masken gerechnet; sein Stand des eigenen Blobs
--   ist dann keine Wahrheit, der man folgen will. Ball und Gegner werden
--   weiter neu aufgesetzt, der eigene Blob heilt sich beim Aufschliessen --
--   dieselbe Zusicherung wie unter ADR-017.
--
--   ALS SICHTVERSATZ KORRIGIEREN. Eine Abweichung des eigenen Blobs ueber
--   2 px geht sofort in die Simulationsposition; gezeichnet wird sie plus
--   einem Versatz, der in vier Ticks auf null laeuft.
--
-- Der Host bleibt die EINZIGE Autoritaet (ADR-002): Hier wird gezeichnet,
-- nicht entschieden. love-frei und ohne Netz testbar
-- (`tests/prediction_test.lua`).
-- ============================================================================

local State    = require("src.sim.state")
local Step     = require("src.sim.step")
local Snapshot = require("src.net.snapshot")

local Prediction = {}
Prediction.__index = Prediction

-- `04_NETCODE_SPEC` §8, beide Zahlen woertlich.
Prediction.THRESHOLD     = 2     -- px, darunter wird nicht korrigiert
Prediction.CORRECT_TICKS = 4     -- ueber so viele Ticks laeuft der Versatz aus

-- Gut eine Sekunde Maskenhistorie. Wer laenger als das auf eine Bestaetigung
-- wartet, hat kein Vorhersageproblem, sondern kein Netz.
Prediction.HISTORY = 64

-- Obergrenze fuer das Wiedervorspielen je Snapshot. Im gesunden Betrieb sind
-- es RTT/2 + 1 Ticks (am Kabel: einer); die Grenze schuetzt die Zielhardware,
-- wenn der Ack nach einem Verlustfenster in einem Sprung aufholt.
Prediction.MAX_REPLAY = 30

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

-- `slot` ist der eigene Platz (1 oder 2). Der Zustand kommt aus
-- `src/sim/state.lua` -- ein Feld, das dort dazukommt, ist damit von selbst
-- hier.
function Prediction.new(slot, ruleset)
    local self = setmetatable({
        slot    = slot,
        ruleset = ruleset,

        state   = State.new(ruleset),

        -- Eingabetick -> Maske. Ein Ring, ueberschrieben statt neu angelegt:
        -- 60 Tabellen je Sekunde waeren unnoetiger Allokationsdruck
        -- (CLAUDE.md §7).
        masks   = {},

        -- Die Ereignisse der Vorhersage werden VERWORFEN. Kosmetik hat genau
        -- eine Quelle, und das ist der Snapshot-Vergleich aus M3-02. Zwei
        -- Quellen hiessen: der eigene Sprung staubt zweimal, und ein lokal
        -- vorweggenommener Punkt pfiffe, bevor der Host ihn bestaetigt hat.
        scratch = {},

        lastAck  = -1,

        offsetX  = 0,         -- Sichtversatz des eigenen Blobs
        offsetY  = 0,
        corrLeft = 0,

        corrections = 0,      -- Zaehler fuer das F3-Overlay
        takeovers   = 0,      -- harte Uebernahmen (Aufschlag), kein Fehler
        compared    = 0,
        skipped     = 0,      -- Snapshots mit stehendem Ack (§7)
        lastReplay  = 0,      -- Ticks des letzten Wiedervorspielens
    }, Prediction)

    return self
end

function Prediction:opponent()
    return (self.slot == 1) and 2 or 1
end

-- ---------------------------------------------------------------------------
-- Maskenhistorie
-- ---------------------------------------------------------------------------

function Prediction:rememberMask(tick, mask)
    if type(tick) ~= "number" then return end
    local index = tick % Prediction.HISTORY
    local entry = self.masks[index]
    if entry then
        entry.tick, entry.mask = tick, mask
    else
        self.masks[index] = { tick = tick, mask = mask }
    end
end

function Prediction:maskAt(tick)
    local entry = self.masks[tick % Prediction.HISTORY]
    if entry and entry.tick == tick then return entry.mask end
    return nil
end

-- ---------------------------------------------------------------------------
-- Ein Tick
--
-- Eigene Eingabe live, Gegnereingabe neutral: Der Gast kennt sie nicht, und
-- die Snapshots korrigieren 60-mal je Sekunde. Zwischen zwei Beruehrungen ist
-- der Ballflug reine Ballistik -- dort ist die Fortschreibung exakt.
-- ---------------------------------------------------------------------------

function Prediction:advance(mask, tick)
    self:rememberMask(tick, mask)

    local in1, in2 = mask, 0
    if self.slot == 2 then in1, in2 = 0, mask end
    Step.tick(self.state, in1, in2, self.ruleset, self.scratch)

    -- Der Sichtversatz laeuft linear aus, unabhaengig von der Phase: sonst
    -- bliebe er im Abpfiff-Bild stehen.
    if self.corrLeft > 0 then
        local factor = (self.corrLeft - 1) / self.corrLeft
        self.offsetX = self.offsetX * factor
        self.offsetY = self.offsetY * factor
        self.corrLeft = self.corrLeft - 1
        if self.corrLeft == 0 then self.offsetX, self.offsetY = 0, 0 end
    end
end

-- ---------------------------------------------------------------------------
-- Rebase und Replay (ADR-025)
--
-- `currentTick` ist der Eingabetick, den `advance` in DIESEM Frame noch
-- faehrt -- wiedervorgespielt wird deshalb bis `currentTick - 1`.
--
-- `hard` heisst: der Host hat die Welt versetzt, nicht bewegt (Aufschlag nach
-- einem Punkt, `Rules.resetBall`). Das ist keine falsche Vorhersage, sondern
-- eine Ansage -- sie wird komplett uebernommen und zaehlt nicht als Korrektur.
-- ---------------------------------------------------------------------------

function Prediction:rebase(snap, hard, currentTick)
    local rs  = self.ruleset
    local own = self.state.blobs[self.slot]

    if hard then
        self.takeovers = self.takeovers + 1
        Snapshot.apply(snap, self.state, rs)
        self.state.input.prev[1], self.state.input.prev[2] = 0, 0
        self.masks = {}
        self.lastAck = -1
        self.offsetX, self.offsetY, self.corrLeft = 0, 0, 0
        self.lastReplay = 0
        return false
    end

    local ack = snap.ackInputTick
    local fresh = type(ack) == "number" and ack >= 0 and ack > self.lastAck

    if not fresh then
        -- Stehender Ack: der Host hat die letzte Maske wiederholt (§7). Sein
        -- Stand des EIGENEN Blobs beruht auf Eingaben, die es nie gab -- ihm
        -- zu folgen waere ein Fehler, den niemand gemacht hat. Ball, Gegner
        -- und Spielstand werden trotzdem neu aufgesetzt: Sie sind die
        -- Wahrheit des Hosts, ganz gleich, was er von uns wusste.
        local keepX, keepY, keepVY = own.x, own.y, own.vy
        local keepGround, keepTilt = own.isGrounded, own.tiltAngle
        Snapshot.apply(snap, self.state, rs)
        own.x, own.y, own.vy = keepX, keepY, keepVY
        own.isGrounded, own.tiltAngle = keepGround, keepTilt
        self.skipped = self.skipped + 1
        self.lastReplay = 0
        return false
    end

    self.lastAck = ack
    self.compared = self.compared + 1

    -- Die Anzeigeposition VOR dem Neuaufsetzen -- beide Seiten des Vergleichs
    -- beschreiben denselben Tick (`currentTick - 1`), einmal aus der alten
    -- Basis, einmal aus der neuen. Das ist der zeitrichtige Vergleich aus §8.
    local beforeX, beforeY = own.x, own.y

    Snapshot.apply(snap, self.state, rs)

    -- Eingabekanten (Sprung ist eine Flanke, ADR-014): `prev` ist die Maske,
    -- die der Host zuletzt verarbeitet hat.
    local opp = self:opponent()
    self.state.input.prev[self.slot] = self:maskAt(ack) or 0
    self.state.input.prev[opp] = 0

    local from = ack + 1
    local to   = currentTick - 1
    if to - from + 1 > Prediction.MAX_REPLAY then
        from = to - Prediction.MAX_REPLAY + 1
    end

    local depth = 0
    for t = from, to do
        local mask = self:maskAt(t) or 0
        local in1, in2 = mask, 0
        if self.slot == 2 then in1, in2 = 0, mask end
        Step.tick(self.state, in1, in2, self.ruleset, self.scratch)
        depth = depth + 1
    end
    self.lastReplay = depth

    local dx = own.x - beforeX
    local dy = own.y - beforeY
    if (dx * dx + dy * dy) <= (Prediction.THRESHOLD * Prediction.THRESHOLD) then
        return false
    end

    self.corrections = self.corrections + 1
    -- Fuer das Protokoll (`07_TEST_PLAN` §5): welcher Eingabetick, wie weit
    -- daneben. Ohne diese zwei Zahlen ist ein steigender Zaehler im WLAN
    -- nicht von einem Anzeigefehler zu unterscheiden.
    self.lastErrorTick = ack
    self.lastErrorX, self.lastErrorY = dx, dy

    -- Die neue Basis gilt sofort; sichtbar wird der Sprung erst ueber vier
    -- Ticks. Der Versatz zeigt in die Gegenrichtung, damit das gezeichnete
    -- Bild in diesem Frame unveraendert bleibt.
    self.offsetX = self.offsetX - dx
    self.offsetY = self.offsetY - dy
    self.corrLeft = Prediction.CORRECT_TICKS
    return true
end

-- ---------------------------------------------------------------------------
-- Beim Matchstart und beim Wiedereinstieg: den Zustand der Szene uebernehmen,
-- alles andere auf Anfang. Die Zaehler bleiben -- sie gelten fuer die Sitzung.
-- ---------------------------------------------------------------------------

function Prediction:reset(state)
    if state then
        local s = self.state
        for k, v in pairs(state.ball) do s.ball[k] = v end
        for i = 1, 2 do
            for k, v in pairs(state.blobs[i]) do s.blobs[i][k] = v end
        end
        s.match.score[1], s.match.score[2] = state.match.score[1], state.match.score[2]
        s.match.phase         = state.match.phase
        s.match.servingPlayer = state.match.servingPlayer
        s.match.inProgress    = state.match.inProgress
        for k, v in pairs(state.rally) do s.rally[k] = v end
        s.net.x, s.net.y, s.net.w, s.net.h =
            state.net.x, state.net.y, state.net.w, state.net.h
    end
    self.state.input.prev[1], self.state.input.prev[2] = 0, 0
    self.masks = {}
    self.lastAck = -1
    self.offsetX, self.offsetY, self.corrLeft = 0, 0, 0
    self.lastReplay = 0
end

-- ---------------------------------------------------------------------------
-- Ergebnis
--
-- Schreibt den vorhergesagten Zustand in den angezeigten. Die Renderschicht
-- und das HUD lesen ausschliesslich dort; nur der eigene Blob bekommt den
-- Sichtversatz obendrauf -- im Simulationszustand steht er nie.
-- ---------------------------------------------------------------------------

function Prediction:writeInto(target)
    local s = self.state

    local tb, sb = target.ball, s.ball
    tb.x, tb.y, tb.vx, tb.vy = sb.x, sb.y, sb.vx, sb.vy
    tb.rotation, tb.radius = sb.rotation, sb.radius

    for i = 1, 2 do
        local dst, src = target.blobs[i], s.blobs[i]
        for k, v in pairs(src) do dst[k] = v end
    end

    local own = target.blobs[self.slot]
    own.x = own.x + self.offsetX
    own.y = own.y + self.offsetY

    target.match.score[1], target.match.score[2] = s.match.score[1], s.match.score[2]
    target.match.phase         = s.match.phase
    target.match.servingPlayer = s.match.servingPlayer
    target.match.inProgress    = s.match.inProgress

    local tr, sr = target.rally, s.rally
    tr.touchCount, tr.lastTouchPlayer = sr.touchCount, sr.lastTouchPlayer
    tr.faultTimer, tr.faultPlayer = sr.faultTimer, sr.faultPlayer
    tr.ballSide, tr.timer = sr.ballSide, sr.timer

    target.net.y, target.net.h = s.net.y, s.net.h
end

return Prediction
