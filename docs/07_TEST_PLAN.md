# 07 — Testplan & QA

**Version:** 1.0 · **Stand:** 2026-08-11

---

## 1. Teststrategie

Vier Ebenen, absteigend nach Automatisierbarkeit:

| Ebene | Was | Automatisiert | Wann |
|-------|-----|---------------|------|
| **A — Simulations-Regression** | Physik reproduziert Referenz-Rallyes | ✅ vollständig | bei jeder Änderung an `src/sim/` |
| **B — Regel-Unit-Tests** | Punktevergabe, Fehler, Satzende, Deuce | ✅ vollständig | bei jeder Änderung an `rules.lua` |
| **C — Netzwerk-Integration** | Zwei Prozesse, echtes ENet | ⚙️ teilweise (Skript startet 2 Instanzen) | vor jedem Release |
| **D — Manuelle Abnahme** | Spielgefühl, LAN-Party-Simulation, Turnier | ❌ manuell | vor jedem Meilenstein |

Die Simulation ist `love`-frei (Architekturregel `03_TECH` §3), deshalb laufen A und B **headless** unter reinem Lua/LuaJIT ohne Fenster — auch in CI.

## 2. Ebene A — Physik-Regression (die M0-Absicherung)

Das größte Risiko des Projekts ist, beim Refactoring das Spielgefühl zu verlieren (R-04). Absicherung:

### Aufzeichnung (vor dem Refactoring, mit dem aktuellen Prototyp)

`tools/record_replay.lua` protokolliert pro Frame: `dt`, Tastenzustände beider Spieler, sowie Position und Geschwindigkeit von Ball und beiden Blobs. Ausgabe als JSON nach `tests/replays/`.

**Aufzunehmende Referenz-Rallyes (mindestens 10):**

| ID | Inhalt | Prüft |
|----|--------|-------|
| R-01 | Aufschlag P1, direkter Punkt | Aufschlagphysik, Serve-Boost |
| R-02 | Lange Rallye ≥ 15 Ballwechsel | Akkumulierte Abweichung |
| R-03 | Wandabpraller links und rechts | `wallBounce` |
| R-04 | Ball auf Netzoberkante | Netzkollision, kritischster Fall |
| R-05 | Ball an Netzseite | Seitliche Netzkollision |
| R-06 | Blob-Ball-Kontakt aktiv (bewegter Blob) | `activeTransfer` |
| R-07 | Blob-Ball-Kontakt passiv (stehender Blob) | `passiveBounce` |
| R-08 | Smash aus dem Sprung | `activeSpike` |
| R-09 | Dash mit Rettung | Dash-Fenster, `dashGrace` |
| R-10 | Drei Berührungen bis zum Fehler | Berührungszähler |
| R-11 | Ballgeschwindigkeit am Maximum | `maxBallSpeed`-Deckel, Tunneling |
| R-12 | Deuce-Situation 14:14 → 16:14 | Regelkorrektur B-05 (**neu**, kein Referenzwert im Prototyp) |

### Wiedergabe (nach dem Refactoring)

Die aufgezeichneten Eingaben werden durch die neue `sim.step()` gefahren. Für jeden Tick wird die Ballposition mit dem Referenzwert verglichen.

| Toleranz | Bewertung |
|----------|-----------|
| ≤ 0,5 px über die gesamte Rallye | ✅ bestanden |
| 0,5 – 3 px, aber Rallye-Ausgang identisch | ⚠️ Analyse erforderlich, meist Folge des Timestep-Wechsels |
| Abweichender Rallye-Ausgang | ❌ nicht bestanden, Refactoring wird nicht fortgesetzt |

**Wichtige Einschränkung, die ehrlich dokumentiert gehört:** Der Wechsel von variablem auf festen Timestep (B-02) verändert die Physik **zwangsläufig**. Der Test kann in dieser Phase nicht auf 0,5 px bestehen. Verfahren, umgesetzt in M0-03 (ADR-015):

1. Der gespielte Durchgang liegt unter `tests/replays/variable/`. Median-`dt` 0,01670 s, sd 0,0005 — faktisch schon 1/60 mit VSync-Jitter.
2. Der `fixed60`-Satz entsteht daraus durch **Wiedergabe derselben `InputFrames` mit konstant 1/60** (`--replay-all`), nicht durch erneutes Spielen. Er ist die Referenz für die Zeit nach M0-05.
3. Wo die Wiedergabe das geprüfte Phänomen verliert, tritt eine Skriptszene an ihre Stelle (R-01, R-06, R-08, R-11). `tools/verify_replays.py` prüft für jede Rallye, dass sie ihr Phänomen tatsächlich enthält.

**Gemessen, nicht geschätzt:** Bei identischen Eingaben und identischem Startzustand liegen variabler und fixer Schritt schon nach 40 bis 190 Ticks über 0,5 px auseinander, in langen Ballwechseln bis zu 730 px. Zwei der elf Rallyes enden sogar anders aus (R-01 verliert den Aufschlag statt zu punkten, R-06 verfehlt den Aktivkontakt).

**Konsequenz für M0-05:** Ein Vergleich `variable` ↔ `fixed60` ist als Abnahmekriterium wertlos — die Ordnung der Abweichung liegt drei Größenordnungen über der Toleranz. Verglichen wird ausschließlich `fixed60` (Prototyp) ↔ `fixed60` (neue Simulation). Der variable Satz bleibt als Beleg dafür, wie sich der Prototyp tatsächlich verhalten hat, und für den Blindtest D1.

### Regressionslauf nach jedem Umbauschritt

**Seit M0-13 ist das ein Test, keine Handarbeit:**

```bash
lua tests/run_headless.lua      # Ebene A und B, ohne LÖVE
love . --test                   # dasselbe aus dem Spiel heraus
love . --test-no-love           # zusätzlich: beweist die love-Freiheit
```

`tests/replay_test.lua` fährt die aufgezeichneten `InputFrames` durch
`Step.tick` und vergleicht Tick für Tick gegen die Referenz — Ball auf 0,5 px,
Phase, Punktestand und Berührungszähler exakt. Belegt: eine Änderung der
Schwerkraft um 0,01 % lässt fünf der elf Rallyes durchfallen.

Der frühere Weg (Referenzen neu erzeugen und die Dateien vergleichen) bleibt
für Änderungen am Werkzeug selbst nützlich:

```bash
love . --replay-all && for s in R-01 R-06 R-08 R-11; do love . --scene=$s; done
python tools/verify_replays.py            # prüft, dass jede Rallye ihr Phänomen enthält
```

Der Aufzeichnungsmodus fährt ein festes 800 × 600-Fenster, in dem `scale == 1` gilt. Solange nur Geometrie und Struktur umgebaut werden und nicht die Arithmetik, darf sich **kein einziger Wert** ändern. **M0-04 und M0-05 wurden so abgenommen.**

Dass auch M0-05 bitgleich bleibt, ist kein Zufall und kein Widerspruch zur Warnung oben: Der `fixed60`-Satz wurde von vornherein mit exakt 1/60 s aufgezeichnet. Der Wechsel auf den echten Akkumulator ändert daran nichts — dieselbe Rechnung mit demselben Schritt. Die Toleranztabelle wird erst dort gebraucht, wo sich die **Arithmetik** ändert: bei der Extraktion nach `src/sim/` (M0-08) und bei den Regelkorrekturen (M0-10).

### Protokoll der akzeptierten Referenzabweichungen

Die `fixed60`-Referenzen werden nach jedem Umbauschritt neu erzeugt und müssen bitgleich
bleiben. Wo sie das **nicht** sind, steht hier warum. Die Liste ist vollständig; alles, was
nicht hier steht, ist ein Fehler.

| Schritt | Betroffen | Ursache | Ausgang |
|---|---|---|---|
| M0-07 | R-02 (ab Tick 1831, max 460 px), R-03 (ab Tick 779, Ball 0 px) | Der Bot bekam im Absprungtick volle Bodengeschwindigkeit statt `airControl`, weil sein Sprung nach der Geschwindigkeitsberechnung lag. P1 hatte diesen Vorteil nie. Der gemeinsame Verbrauchspfad aus B-07 beseitigt die Asymmetrie. | unverändert (0:1 bzw. 0:6) |

Der gespielte `variable`-Satz bleibt davon unberührt — er ist der eingefrorene Prototyp und
wird nie neu erzeugt.

**M0-08 steht bewusst nicht in dieser Tabelle.** Die vollständige Extraktion der Simulation
nach `src/sim/` — Zustand, Physik, Regeln, Schritt — lief bitgleich durch, alle elf Rallyes,
jeder Wert. Das ist der Punkt der ganzen Übung: Wenn ein Umbau dieser Größe keine einzige
Stelle bewegt, ist er nachweislich eine Umsortierung und keine Änderung.

**Was die Abweichung nicht bedeutet:** Sie sagt nichts über die Wahl von 1/60 aus. Ein chaotisches System driftet bei jeder Störung; entscheidend ist, ob sich das Ergebnis im Blindtest D1 anders **anfühlt**. Erst wenn D1 kippt, wird 1/120 mit doppelter Tickrate geprüft.

## 3. Ebene B — Regel-Unit-Tests

| ID | Fall | Erwartung |
|----|------|-----------|
| T-R-01 | Aufschläger gewinnt Ballwechsel | +1 Punkt, behält Aufschlag — **umgesetzt M0-13** |
| T-R-02 | Nicht-Aufschläger gewinnt Ballwechsel | 0 Punkte, Aufschlagwechsel — **umgesetzt M0-13** |
| T-R-03 | Ball berührt eigenen Boden | Fehler, Punkt/Aufschlag an Gegner — **umgesetzt M0-13** |
| T-R-04 | 4. Berührung in Folge | Fehler — **umgesetzt M0-13** |
| T-R-05 | 3. Berührung ist gültig | kein Fehler — **umgesetzt M0-13** |
| T-R-06 | Ball wechselt Seite | Zähler auf 0 — **umgesetzt M0-13** |
| T-R-07 | Wandberührung | zählt **nicht** als Berührung — **umgesetzt M0-13** |
| T-R-08 | Netzberührung | zählt **nicht** als Berührung (GDD P1) — **umgesetzt M0-13** |
| T-R-09 | 15:13 | Satz beendet — **umgesetzt M0-10** |
| T-R-10 | 15:14 | Satz **nicht** beendet (Blocker B-05) — **umgesetzt M0-10** |
| T-R-11 | 16:14 | Satz beendet — **umgesetzt M0-10** |
| T-R-12 | 20:20 → 21:20 bei `deuceCap=21` | Satz beendet (E-09) — **umgesetzt M0-10** |
| T-R-13 | Rallye 30 s ohne Punkt | Punkt an Nicht-Aufschläger (GDD P5) — **umgesetzt M0-10** |
| T-R-14 | Ruleset-Hash bei identischem Ruleset, andere Schlüsselreihenfolge | identischer Hash (kanonische Serialisierung) — **umgesetzt M0-09**, `tests/ruleset_test.lua` |
| T-R-15 | Ruleset mit `ballRadius=80`, `netHeight=350` | Validierung lehnt ab (F-10) — **umgesetzt M0-09** |

## 4. Ebene C — Netzwerk-Integration

`tests/net_integration.sh` startet zwei LÖVE-Instanzen lokal (Host + Client auf `127.0.0.1`) mit einem Skript-Treiber, der Eingaben injiziert.

| ID | Fall | Erwartung |
|----|------|-----------|
| T-N-01 | Client verbindet sich, spielt 1 Satz | Endstand auf beiden Seiten identisch |
| T-N-02 | 5 % Paketverlust auf Kanal 2 (Input) | Keine sichtbaren Aussetzer (Redundanz greift, `04_NETCODE` §7). **Seit ADR-019 keine Abnahmebedingung mehr** — über Kabel ist Verlust ein Defekt, kein Normalfall. Die Logik ist in Ebene B abgesichert (`input_queue_test.lua`, T-N-13) |
| T-N-03 | 20 % Paketverlust auf Kanal 1 (Snapshot) | Bild ruckelt, Endstand bleibt identisch. Wie T-N-02: offen, nicht mehr blockierend |
| T-N-04 | Client-Prozess während des Satzes killen | Host pausiert, nach 30 s Walkover |
| T-N-05 | Client killen + neu starten in 10 s | Reconnect, steigt in laufenden Satz ein |
| T-N-06 | Host mit abweichendem `rulesetHash` | Match startet nicht, Klartextmeldung |
| T-N-07 | `love.data.pack("<f", …)` auf Win und macOS | Bitidentisches Ergebnis (offener Punkt N-03) |
| T-N-08 | 200 Snapshots in einem Frame in die Queue drücken | Event-Loop leert vollständig, kein Aufstau |
| T-N-09 | Discovery mit 3 gleichzeitigen Hosts | Alle 3 in der Liste, korrekt unterscheidbar. **Gehört seit 2026-08-13 zur Abnahme von M4-09**: bei parallelen Matches (ADR-013) sind mehrere gleichzeitige Lobbys der Normalfall. Bis dahin offen |
| T-N-10 | Host beendet Lobby, Client noch verbunden | Client kehrt sauber ins Menü zurück |
| T-N-11 | 4 parallele Matches mit verteilten Match-Hosts, gleichzeitiger Ergebnisversand | Alle 4 Ergebnisse korrekt im Bracket, keine Race Condition |
| T-N-12 | Gast spielt mit Vorhersage, kein Paketverlust (M3-01) | Korrekturzähler bleibt bei 0; der eigene Blob steht an derselben Stelle wie beim Host |
| T-N-13 | Gast spielt mit Vorhersage, 20 % Eingabeverlust | Korrekturzähler steigt, der Blob wird binnen 4 Ticks wieder eingeholt, kein sichtbarer Sprung |
| T-N-14 | Prüfsumme bei gleichem Build (M3-03) | `desync` bleibt 0 bei mehr als 0 Vergleichen — beide Zahlen zusammen, eine allein sagt nichts |
| T-N-15 | Prüfsumme bei absichtlich falschem Wert, beide Reihenfolgen | Wird erkannt, egal ob Snapshot oder Prüfsumme zuerst ankommt (sie laufen über verschiedene Kanäle) |
| T-N-16 | Gast sieht Staub und hört Klänge (M3-02) | Wandtreffer, Netztreffer, Blobtreffer, Landung, Aufschlag und Punkt kommen beim Gast an |
| T-B-01 | `codesign --verify` auf der gebauten `.app` | „valid on disk"; Build bricht sonst ab (ADR-012) |
| T-B-02 | `.app` auf einem **fremden** Apple-Silicon-Mac starten | Startet nach Rechtsklick → „Öffnen"; kein Sofortabbruch |

**Paketverlust simulieren:** macOS `dnctl`/`pfctl`, Linux `tc netem`. Auf Windows via `clumsy`. Der Verlust-Test ist der wichtigste — auf WLAN-Partys ist er der Normalfall, nicht der Sonderfall.

## 5. Desync- und Vorhersagefehler-Überwachung

**Zwei Fehlerklassen, zwei Zahlen** (ADR-018). Ein gemeinsamer Wert sagt im Fehlerfall nicht, welche von beiden schuld ist — und das ist die Frage, die abends gestellt wird.

| Klasse | Woher | Erwartung |
|---|---|---|
| `CORRECTION` | Vorhersage des eigenen Blobs lag > 2 px daneben (`04_NETCODE` §8) | Im LAN 0. Bei Eingabeverlust normal — die **Rate** ist die Aussage, nicht die einzelne Zeile |
| `DESYNC` | Prüfsumme über die gepackten Snapshot-Bytes passt nicht (`04_NETCODE` §9) | Immer 0. Eine einzige Zeile ist ein Befund und heißt in der Regel: verschiedene Builds |

- **Entwicklungs-Build** (`version == "dev"`): beide Klassen mit Tick und Werten nach `desync.log` im Save-Ordner, höchstens 200 Zeilen je Sitzung. Ohne Deckel füllt ein Fehler, der sich wiederholt, die Platte.
- **Release-Build:** nur die Zähler im F3-Overlay. Kein Log.
- **Messmitschnitt:** `F4` im Netzspiel schreibt einmal je Sekunde eine Zeile nach `netlog.csv` — dieselben Werte, die F3 zeigt. Das ist das Instrument für D2 und für die WLAN-Messung aus M3-04; ein abfotografiertes Overlay ist eine Momentaufnahme, eine Zeile je Sekunde ist eine Messreihe.
- **Abnahme:** ein Satz über echtes WLAN mit offenem Mitschnitt. Ziel: `DESYNC` = 0, Korrekturrate unter 1 je Sekunde, und der Gast kann nicht sagen, ob er Host oder Gast ist.

**Die alte Fassung dieses Abschnitts verlangte etwas anderes** — eine Prüfsumme über den Simulationszustand und ein Log „mit den letzten 30 Input-Frames". Beides ist mit M3-03 fallengelassen: Der Client kennt den Zustand des Hosts nicht (ADR-002), und 30 mitgeschriebene Eingaben beantworten keine Frage, die Tick und Abweichung nicht schon beantworten. Begründung vollständig in ADR-018.

## 6. Ebene D — Manuelle Abnahme

### D1 — Spielgefühl (nach M0, blockierend)

Drei Personen, die den Prototyp kennen, spielen je 3 Sätze mit alter und neuer Version im Blindwechsel. **Frage: „Welche Version war Nummer 1?"** Wenn mehr als eine Person die neue Version korrekt als „anders" identifiziert und die Änderung negativ bewertet, ist M0 nicht abgenommen.

> **Abnahmevermerk 2026-08-12 — erteilt als Product-Owner-Abnahme.**
> r0btoshi hat beide Fassungen selbst gespielt (neue Fassung gegen den Baseline-Arbeitsordner
> `C:\dev\volley-dash-baseline`) und das Spielgefühl als unverändert bewertet.
> **Das oben beschriebene Verfahren wurde nicht durchlaufen:** es fehlen die zweite und die
> dritte Person und der Blindwechsel. Die Abnahme beruht auf **einer** Person und ist damit
> nicht gegen die eigene Erwartungshaltung abgesichert — genau das sollte das Blindverfahren
> leisten.
>
> Die Entscheidung ist bewusst so getroffen und gilt. Sie stützt sich darauf, dass die
> Ebene-A-Regression den Hauptteil der Last trägt: elf von dreizehn Umbauschritten liefen
> bitgleich durch, und die zwei gewollten Abweichungen sind in §2 einzeln protokolliert.
> M0 ist abgenommen, M1 nicht mehr blockiert.

### D2 — LAN-Party-Simulation (nach M2, blockierend)

Mindestaufbau: 1× Windows-Laptop, 1× MacBook, 1 Switch oder AP.

| # | Schritt | Erfolg wenn |
|---|---------|-------------|
| 1 | Beide Rechner frisch, nur die ZIP vorhanden | — |
| 2 | Entpacken und starten | < 90 s bis Hauptmenü, ohne Hilfe |
| 3 | Host erstellt Lobby | Lobby erscheint auf dem anderen Rechner ≤ 3 s |
| 4 | Client tritt bei, 3 Sätze | Kein Desync, keine Aussetzer |
| 5 | WLAN statt Kabel wiederholen | Spielbar oder dokumentiert als „Kabel empfohlen" |
| 6 | Discovery durch Firewall-Blockade sabotieren | Manuelle IP-Eingabe funktioniert und ist auffindbar |

### D3 — Turnier-Abnahme (nach M4, blockierend)

Siehe Abnahmekriterien in `05_TOURNAMENT_SPEC` §12. Zusätzlich der Härtetest:

**Das Chaos-Szenario.** 20 Spieler (davon dürfen 12 simulierte Clients sein), Gruppen + Single Elim, 4 parallele Matches. Während des Turniers werden bewusst ausgelöst: ein No-Show, ein Client-Absturz mitten im Satz, ein Turnier-Host-Absturz zwischen zwei Runden, und ein Spieler, der auf einen anderen Rechner wechselt. Zusätzlich: ein Match-Host (nicht der Turnier-Host) stürzt ab, während zwei andere Matches parallel laufen. **Erfolg:** Das Turnier wird zu Ende gespielt, das Endergebnis ist korrekt, und der Turnierleiter musste höchstens zweimal eingreifen.

### D4 — Build-Abnahme (nach M1)

Siehe `06_BUILD` §8.

## 7. Testdaten und Werkzeuge

| Werkzeug | Zweck |
|----------|-------|
| `tools/record_replay.lua` | Referenz-Rallyes aufzeichnen (temporär, M0-03) |
| `tools/replay_source.lua` | Aufgezeichnete `InputFrames` zurückspielen, Skriptszenen (temporär, M0-03) |
| `tools/verify_replays.py` | Prüft je Rallye, dass sie ihr Phänomen enthält |
| `tests/run_headless.lua` | Ebene A + B ohne Fenster |
| `tests/net_integration.sh` | Zwei Instanzen + Eingabe-Injektion |
| `tools/fake_clients.lua` | N virtuelle Clients für Lasttest der Lobby |
| F3-Overlay im Spiel | Tick, RTT, Paketverlust, Snapshot-Rate, Korrekturzähler, Ruleset-Hash |

Das F3-Overlay ist kein Debug-Luxus, sondern das einzige Diagnosewerkzeug, das am Partyabend verfügbar ist. Es muss in Release-Builds enthalten bleiben.

## 8. Definition of Done pro Meilenstein

Ein Meilenstein gilt als fertig, wenn:
1. alle zugehörigen automatisierten Tests grün sind,
2. die zugehörige manuelle Abnahme (D1–D4) bestanden ist,
3. ein Build für beide Plattformen existiert und startet,
4. die betroffenen Spezifikationsdokumente aktualisiert sind (kein Drift zwischen Spec und Code),
5. neue Architekturentscheidungen als ADR in `09_DECISION_LOG_ADR.md` stehen.

Punkt 4 ist der, der in der Praxis übersprungen wird und dessen Übergehen später den teuersten Audit erzwingt.
