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
| zwei Tipps genau am Fensterrand | noch ein `dash`-Bit |
| zwei Tipps außerhalb `dashWindow` | kein `dash`-Bit |
| drei Tipps innerhalb `dashWindow` | genau ein `dash`-Bit, kein zweiter aus Tipp 2→3 |
| vier Tipps | zwei `dash`-Bits — Paare, keine Kette |
| Doppeltipp zweier **verschiedener** Richtungen | kein `dash`-Bit |
| gehaltene Taste über viele Ticks | kein `dash`-Bit |

**Nicht Sache der Quelle:** `dashCooldown`. Fassung 1.0 dieses Dokuments führte hier den
Fall „Doppeltipp während `dashCooldown > 0` → kein `dash`-Bit". Das widerspricht ADR-014,
wonach die Quelle „Dash jetzt" meldet und die **Simulation** gegen `dashCooldown` auswertet.
Sonst bräuchte die Quelle Simulationszustand — beim Netzwerk unmöglich. Korrigiert in M0-06:
Der Fall gehört in den Simulationstest („`dash`-Bit gesetzt, aber keine Wirkung"), nicht in
den Quellentest.

**Umgesetzt in M0-06.** Die Erkennung sitzt in `src/input/local_source.lua` als reine
Zustandsmaschine (`TapDetector`) und zählt in **Ticks** (`dashWindow` × 60 = 12), nicht mehr
in Sekunden. Test: `tests/input_frame_test.lua`, Start mit `love . --test`.

**Nebenwirkung der Bitmaske, bewusst in Kauf genommen:** Ein Doppeltipp auf die Sprungtaste
bei gleichzeitig gehaltener Richtung ergibt einen **Seitwärts**-Dash, weil die Richtung aus
den Richtungsbits kommt. Der Prototyp löste dort einen Aufwärts-Dash aus. Die Alternative
wäre ein eigenes Richtungsfeld gewesen — in ADR-014 ausdrücklich verworfen.

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
das Verhalten des Prototyps und wird nicht übernommen (Entscheidung r0btoshi, 2026-08-11).
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

## 7. Abbildung im Code

Seit M0-06 erzeugt `src/input/local_source.lua` das Format; die Aufzeichnung schreibt nur
noch mit, was ohnehin durch die Simulation läuft. Vor M0-06 las der Prototyp die Hardware
mitten in der Simulation (B-03) und das Werkzeug baute das Format nachträglich nach.

| Bit | Spieler 1 | Spieler 2 (lokal) | Spieler 2 (Bot) |
|---|---|---|---|

| `left` | `isDown("a")` | `isDown("h")` | `botInputs.left` |
| `right` | `isDown("d")` | `isDown("k")` | `botInputs.right` |
| `jump` | `isDown("w")` | `isDown("u")` | `botInputs.jump` |
| `smash` | `isDown("s")` | `isDown("j")` | `botInputs.smash` |
| `dash` | `TapDetector` | `TapDetector` | `botInputs.dashDir ~= nil` |

Dazu parallel das Gamepad: linker Stick bzw. D-Pad auf `left`/`right`, Knopf A auf `jump`,
Knopf X auf `smash`, Doppeltipp auf die Richtung ergibt wie bei der Tastatur den Dash.
Achsen werden in der Quelle über eine Schwelle diskretisiert (§6).

Aufgezeichnet wird beim Bot ausdrücklich der **Output** (`botInputs`), nicht der Zustand des
Bots. Damit sind die Zufallsanteile des Bots (`main.lua:331`) in der
Aufzeichnung eingefroren und für die Wiedergabe unschädlich.

Die Quelle wird **einmal je Tick** abgefragt, nicht je Frame. Holt ein Frame zwei Ticks
nach, bekommt jeder seinen eigenen `InputFrame` — die Doppeltipp-Erkennung zählt dadurch in
echten Ticks.

**Bekannte Ungenauigkeiten**, hier festgehalten, damit eine spätere Abweichung nicht als
Physikfehler fehlgedeutet wird:

1. **Erledigt mit M0-06.** Bis dahin lösten Sprung und Dash in `love.keypressed` aus, also
   ereignisgesteuert und außerhalb des Ticks, während die Aufzeichnung `jump` als Pegel
   festhielt. Jetzt leitet die Simulation die Flanke aus dem Pegel ab. Ein Anschlag unter
   16 ms kann vom Pegel weiterhin verfehlt werden — das ist der Preis der Tickrate und gilt
   für jede Quelle gleichermaßen.
2. Der Zustand im Replay-Frame ist der Zustand **vor** dem zugehörigen Schritt und **vor**
   den Tastenereignissen dieses Frames (`"state_convention": "pre_step"`). Nur so enthält
   er den Dash-Impuls nicht doppelt, den der Prototyp bereits in `love.keypressed` anwendet.
3. **Erledigt mit M0-07.** Der Bot setzte `dashDir` unabhängig von `left`/`right`; lag sein
   Ziel innerhalb der Toleranz von 8 px, entstand ein Dash-Bit ohne Richtungsbit, das die
   Wiedergabe als Aufwärts-Dash las. `src/input/bot_source.lua` setzt das Richtungsbit jetzt
   passend zur Dash-Richtung. Die vor M0-07 aufgezeichneten Referenzen behalten den alten
   Stand; für R-09 kommt der Dash ohnehin von **Spieler 1**.

---

## 8. Stand und offene Punkte

**Erledigt in M0-06:**

1. Doppeltipp-Erkennung zählt in Ticks (§4), mit Unit-Test (`tests/input_frame_test.lua`).
2. Der `jump`-Pegel bekommt seine Flankenerkennung in der Simulation, nicht in der Quelle —
   nur die Simulation weiß, ob der Blob am Boden steht. Der Dash bleibt die dokumentierte
   Ausnahme.
3. Gamepad-Anbindung steht (linker Stick/D-Pad, A, X). **Ungetestet mangels Gerät.**

**Offen:**

1. **Erledigt M0-11:** Tastenbelegung kommt aus den Prefs (`src/input/bindings.lua`).
   Offen bleibt nur die Gamepad-Schwelle `AXIS_DEADZONE = 0.5`, die noch fest im Code steht —
   sie braucht ein Gerät zum Einstellen.
2. Gamepad an echter Hardware prüfen, sobald eines zur Hand ist. Bis dahin gilt der Pfad
   als unbelegt — er ist so gebaut, dass er ohne Gerät schlicht `0` liefert.
3. Der Bot erzeugt seinen `InputFrame` noch nicht selbst; er schreibt ihn parallel mit
   (M0-07, `src/input/bot_source.lua`).
4. Netzwerkquelle (M2-01).
