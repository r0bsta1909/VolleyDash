# 13 — Kanonisches `InputFrame`-Format

**Version:** 1.0 · **Stand:** 2026-08-11 · **Festgeschrieben in:** CC-01 (M0-03), AP-3
**Bezug:** Blocker B-03, ADR-014, `03_TECH_ARCHITECTURE` §3, `04_NETCODE_SPEC`, `07_TEST_PLAN` §2

---

## 1. Wozu dieses Dokument

`sim.step()` kennt laut B-03 ausschließlich `InputFrame`. Alles, was Eingaben erzeugt —
Tastatur, Gamepad, Bot, Netzwerk, Aufzeichnung — produziert dieses eine Format. Damit ist die
Simulation von jeder Quelle speisbar und headless testbar.

Das Format wird **vor** der Referenzaufzeichnung festgeschrieben (M0-03), nicht danach.
Grund: Eine Aufzeichnung im Rohtastenformat würde den Regressionstest der Ebene A gegen eine
ungetestete Übersetzungsschicht Tastatur→InputFrame laufen lassen statt gegen die Physik.

---

## 2. Kanonische Bitmaske

**Ein Byte pro Spieler pro Tick.** Vorzeichenlos, 8 Bit.

| Bit | Wert | Name | Art |
|---|---|---|---|
| 0 | 1 | `left` | Zustand |
| 1 | 2 | `right` | Zustand |
| 2 | 4 | `jump` | Zustand |
| 3 | 8 | `smash` | Zustand |
| 4 | 16 | `dash` | abgeleiteter Impuls |
| 5 | 32 | — | reserviert, **muss 0 sein** |
| 6 | 64 | — | reserviert, **muss 0 sein** |
| 7 | 128 | — | reserviert, **muss 0 sein** |

Beispiel: `left` + `jump` = `1 + 4` = `5`.

**Validierung:** Jeder Empfänger — Netzwerk, Wiedergabe, Testrunner — prüft
`frame < 32`. Ein Byte mit gesetztem reserviertem Bit wird verworfen und protokolliert,
nicht maskiert. Stilles Maskieren verdeckt Protokoll- und Versionsfehler.

**Zustand vs. Impuls:** Bits 0–3 beschreiben, ob die Eingabe **während dieses Ticks anlag**
(Pegel). Flankenerkennung — „Sprung nur beim Drücken, nicht beim Halten" — ist Sache der
Simulation, nicht der Quelle. Bit 4 ist die Ausnahme, siehe §4.

---

## 3. Zulässige Quellen

Genau vier, und **pro Tick genau eine je Spieler**:

| Quelle | Kennung | Erzeugt aus |
|---|---|---|
| lokale Tastatur | `local_keyboard` | Tastenbelegung aus `Prefs` |
| lokales Gamepad | `local_gamepad` | Achsen/Buttons, Deadzone in `Prefs` |
| Bot | `bot` | `bot_source.lua` (ab M0-07), aus Spielzustand und `Ruleset` |
| Netzwerk | `network` | empfangenes Input-Paket des Gegners |

Wechselt die Quelle eines Spielers (Reconnect, Bot-Übernahme bei Disconnect), geschieht das
**zwischen** zwei Ticks und wird protokolliert. Zwei Quellen dürfen im selben Tick niemals
denselben Spieler bespielen — bei Doppelbelegung gilt der Frame als fehlerhaft, nicht als
ODER-Verknüpfung.

Die Simulation liest niemals selbst Hardware. `love.keyboard.*` unterhalb von `src/sim/` ist
ein Fehler, kein Stilproblem.

---

## 4. Der `dash`-Bit ist ein abgeleitetes Signal, kein Tastendruck

Dash entsteht im Original durch **Doppeltipp** einer Richtungstaste innerhalb von
`dashWindow` (0,20 s). Diese Erkennung sitzt **in der Eingabequelle**, nicht in der
Simulation:

- Die Quelle erkennt den Doppeltipp und setzt Bit 4 für **genau einen Tick**.
- Die Simulation sieht nur „Dash jetzt" und wertet ihn gegen `dashCooldown` aus.
- Der Bot setzt Bit 4 direkt, ohne Tipp-Simulation.
- Das Netzwerk überträgt das fertige Bit, nicht die Tastenfolge.

Die Richtung des Dash ergibt sich aus den gleichzeitig gesetzten Bits `left`/`right`,
nicht aus einem eigenen Feld:

| `dash` + … | Bedeutung |
|---|---|
| `left` | Seitwärts-Dash nach links |
| `right` | Seitwärts-Dash nach rechts |
| weder noch | Aufwärts-Dash (im Prototyp der Doppeltipp auf `w` bzw. `u`) |
| beide | ungültig, gilt als Seitwärts-Dash nach links (§5) |

**Konsequenz für den Test, ausdrücklich festgehalten:** Der Regressionstest der Ebene A
(`07_TEST_PLAN` §2) prüft damit die **Physik**, nicht die Doppeltipp-Erkennung. Die
Doppeltipp-Erkennung ist außerhalb der Referenz-Rallyes und braucht einen **eigenen
Unit-Test in M0-06**. Mindestfälle:

| Fall | Erwartung |
|---|---|
| zwei Tipps innerhalb `dashWindow` | genau ein `dash`-Bit, im Tick des zweiten Tipps |
| zwei Tipps außerhalb `dashWindow` | kein `dash`-Bit |
| drei Tipps innerhalb `dashWindow` | genau ein `dash`-Bit, kein zweiter aus Tipp 2→3 |
| Doppeltipp während `dashCooldown > 0` | kein `dash`-Bit |
| Doppeltipp zweier **verschiedener** Richtungen | kein `dash`-Bit |

Im Prototyp misst `handleDoubleTap` (`main.lua:857–890`) über `love.timer.getTime()`, also
in **Echtzeit**. Ab M0-06 zählt die Erkennung in **Ticks** (`dashWindow` × 60 = 12 Ticks),
sonst hängt sie an der Bildwiederholrate. Das ist eine bewusste, in M0-06 zu prüfende
Verhaltensänderung.

---

## 5. Gemessenes Verhalten bei gleichzeitig `left` und `right`

**Festlegung: `left` gewinnt. Kein Stillstand.**

Diese Festlegung ist **gemessen, nicht gewünscht.** Der Prototyp verhält sich so:

```lua
-- main.lua:585 (Spieler 1)
p1.vx = love.keyboard.isDown("a") and -p1Speed or (love.keyboard.isDown("d") and p1Speed or 0)

-- main.lua:635 (Spieler 2, lokal)
p2.vx = love.keyboard.isDown("h") and -p2Speed or (love.keyboard.isDown("k") and p2Speed or 0)
```

Die `and/or`-Kette wertet von links aus: Ist die Linkstaste gedrückt, ist das Ergebnis
`-speed`, unabhängig von der Rechtstaste. Sind beide gedrückt, läuft der Blob **nach links**.
`vx = 0` tritt nur ein, wenn **keine** der beiden Tasten anliegt.

Das Handoff CC-01 schlug „beide gesetzt ergibt Stillstand (`vx = 0`)" vor. Das ist **nicht**
das Verhalten des Prototyps und wird nicht übernommen (Entscheidung Roberto, 2026-08-11).
Begründung: Die Referenz-Rallyes halten das jetzige Verhalten fest; eine Regeländerung an
dieser Stelle würde die Aufzeichnung gegen eine Physik prüfen, die es zum Aufnahmezeitpunkt
nicht gab.

**Verbindliche Auflösungsregel ab M0-06:**

```
if left  then vx = -speed
elseif right then vx = +speed
else vx = 0 end
```

Der Bot kann strukturell nie beide Bits setzen: `Bot.updateAI` (`main.lua:375–377`) setzt
`left` und `right` in einem `if/elseif`. Für Quellen
`bot` und `network` ist der Fall also nur über einen manipulierten Frame erreichbar; die
Regel gilt trotzdem für alle vier Quellen einheitlich.

---

## 6. Serialisierung

| Kontext | Darstellung |
|---|---|
| im Speicher | Ganzzahl 0…31, ein Wert pro Spieler |
| Replay-JSON | `"in": [<p1>, <p2>]`, Dezimalzahlen, **keine** Strings |
| Netzwerk | ein Byte, `love.data.pack("<B", frame)`, Reihenfolge nach `04_NETCODE_SPEC` |

Die Bitmaske ist bewusst so klein, dass ein Tick beider Spieler in zwei Byte passt. Bei
60 Hz sind das 120 B/s je Richtung vor Header und Redundanz.

Fließkommazahlen kommen im `InputFrame` nicht vor. Analoge Gamepad-Achsen werden **in der
Quelle** über eine Schwelle aus `Prefs` zu `left`/`right` diskretisiert — die Simulation
kennt keine halben Eingaben. Das ist der Preis dafür, dass Tastatur und Gamepad exakt
dieselbe Physik erzeugen, und es entspricht dem Original.

---

## 7. Abbildung im Prototyp (nur M0-03)

Der Prototyp **hat kein `InputFrame`** — er liest die Hardware mitten in der Simulation
(B-03). `tools/record_replay.lua` erzeugt das Format deshalb während der Aufzeichnung aus
dem, was der Prototyp tatsächlich verbraucht:

| Bit | Spieler 1 | Spieler 2 (lokal) | Spieler 2 (Bot) |
|---|---|---|---|
| `left` | `isDown("a")` | `isDown("h")` | `botInputs.left` |
| `right` | `isDown("d")` | `isDown("k")` | `botInputs.right` |
| `jump` | `isDown("w")` | `isDown("u")` | `botInputs.jump` |
| `smash` | `isDown("s")` | `isDown("j")` | `botInputs.smash` |
| `dash` | Flanke aus `handleDoubleTap` | Flanke aus `handleDoubleTap` | `botInputs.dashDir ~= nil` |

Aufgezeichnet wird beim Bot ausdrücklich der **Output** (`botInputs`), nicht der Zustand des
Bots. Damit sind die Zufallsanteile des Bots (`main.lua:331`) in der
Aufzeichnung eingefroren und für die Wiedergabe unschädlich.

Im Modus `fixed60` teilen sich mehrere Simulationsschritte eines Frames denselben
Tastaturzustand — genau wie in der Zielarchitektur, die Eingaben einmal pro Frame abholt und
mehrfach durch `sim.step()` fährt.

**Bekannte Ungenauigkeiten**, hier festgehalten, damit eine spätere Abweichung nicht als
Physikfehler fehlgedeutet wird:

1. Der Prototyp löst Sprung und Dash in `love.keypressed` aus, also ereignisgesteuert,
   während die Aufzeichnung `jump` als Pegel festhält. Ein Tastendruck, der zwischen zwei
   Ticks beginnt und endet, kann vom Pegel verfehlt werden. Er verlangt einen Anschlag
   unter 16 ms und ist damit praktisch ausgeschlossen; der `dash`-Bit umgeht das ohnehin
   über das Flankenflag. **Gemessen:** `love.keyboard.hasKeyRepeat()` ist in LÖVE 11.5.0
   `false`, eine gehaltene Sprungtaste löst also keine Wiederholung aus. Der Pegel bleibt
   damit eindeutig.
2. Der Zustand im Replay-Frame ist der Zustand **vor** dem zugehörigen Schritt und **vor**
   den Tastenereignissen dieses Frames (`"state_convention": "pre_step"`). Nur so enthält
   er den Dash-Impuls nicht doppelt, den der Prototyp bereits in `love.keypressed` anwendet.
3. Der Bot setzt `dashDir` unabhängig von `left`/`right`. Liegt sein Ziel innerhalb der
   Toleranz von 8 px, kann ein Dash-Bit ohne Richtungsbit entstehen und die Wiedergabe
   liest ihn als Aufwärts-Dash. Der Fall ist selten; für R-09 wird deshalb der Dash von
   **Spieler 1** aufgezeichnet, nicht der des Bots.

---

## 8. Offene Punkte für M0-06

1. Doppeltipp-Erkennung von Echtzeit auf Ticks umstellen (§4), mit Unit-Test.
2. Tastenbelegung aus `Prefs` statt hartcodiert (`M0-11`, GDD §7).
3. Gamepad-Schwelle festlegen und in `Prefs` aufnehmen.
4. Ob der `jump`-Pegel in der Zielarchitektur eine Flankenerkennung in der Simulation
   bekommt oder die Quelle wie beim Dash einen Impuls setzt. Empfehlung: Flanke in der
   Simulation, weil nur sie weiß, ob der Blob am Boden steht.
