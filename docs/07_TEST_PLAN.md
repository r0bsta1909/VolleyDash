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

Bis M0-05 den Timestep ändert, ist die Messlatte **Bitgleichheit**, nicht Toleranz:

```bash
cp -r tests/replays/fixed60 /tmp/fixed60_before
love . --replay-all && for s in R-01 R-06 R-08 R-11; do love . --scene=$s; done
python tools/verify_replays.py            # muss "OK" melden
# danach die frames-Bloecke beider Staende vergleichen -- sie muessen identisch sein
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

**Was die Abweichung nicht bedeutet:** Sie sagt nichts über die Wahl von 1/60 aus. Ein chaotisches System driftet bei jeder Störung; entscheidend ist, ob sich das Ergebnis im Blindtest D1 anders **anfühlt**. Erst wenn D1 kippt, wird 1/120 mit doppelter Tickrate geprüft.

## 3. Ebene B — Regel-Unit-Tests

| ID | Fall | Erwartung |
|----|------|-----------|
| T-R-01 | Aufschläger gewinnt Ballwechsel | +1 Punkt, behält Aufschlag |
| T-R-02 | Nicht-Aufschläger gewinnt Ballwechsel | 0 Punkte, Aufschlagwechsel |
| T-R-03 | Ball berührt eigenen Boden | Fehler, Punkt/Aufschlag an Gegner |
| T-R-04 | 4. Berührung in Folge | Fehler |
| T-R-05 | 3. Berührung ist gültig | kein Fehler |
| T-R-06 | Ball wechselt Seite | Zähler auf 0 |
| T-R-07 | Wandberührung | zählt **nicht** als Berührung |
| T-R-08 | Netzberührung | zählt **nicht** als Berührung (GDD P1) |
| T-R-09 | 15:13 | Satz beendet |
| T-R-10 | 15:14 | Satz **nicht** beendet (Blocker B-05) |
| T-R-11 | 16:14 | Satz beendet |
| T-R-12 | 20:20 → 21:20 bei `deuceCap=21` | Satz beendet (E-09) |
| T-R-13 | Rallye 30 s ohne Punkt | Punkt an Nicht-Aufschläger (GDD P5) |
| T-R-14 | Ruleset-Hash bei identischem Ruleset, andere Schlüsselreihenfolge | identischer Hash (kanonische Serialisierung) |
| T-R-15 | Ruleset mit `ballRadius=80`, `netHeight=350` | Validierung lehnt ab (F-10) |

## 4. Ebene C — Netzwerk-Integration

`tests/net_integration.sh` startet zwei LÖVE-Instanzen lokal (Host + Client auf `127.0.0.1`) mit einem Skript-Treiber, der Eingaben injiziert.

| ID | Fall | Erwartung |
|----|------|-----------|
| T-N-01 | Client verbindet sich, spielt 1 Satz | Endstand auf beiden Seiten identisch |
| T-N-02 | 5 % Paketverlust auf Kanal 2 (Input) | Keine sichtbaren Aussetzer (Redundanz greift, `04_NETCODE` §7) |
| T-N-03 | 20 % Paketverlust auf Kanal 1 (Snapshot) | Bild ruckelt, Endstand bleibt identisch |
| T-N-04 | Client-Prozess während des Satzes killen | Host pausiert, nach 30 s Walkover |
| T-N-05 | Client killen + neu starten in 10 s | Reconnect, steigt in laufenden Satz ein |
| T-N-06 | Host mit abweichendem `rulesetHash` | Match startet nicht, Klartextmeldung |
| T-N-07 | `love.data.pack("<f", …)` auf Win und macOS | Bitidentisches Ergebnis (offener Punkt N-03) |
| T-N-08 | 200 Snapshots in einem Frame in die Queue drücken | Event-Loop leert vollständig, kein Aufstau |
| T-N-09 | Discovery mit 3 gleichzeitigen Hosts | Alle 3 in der Liste, korrekt unterscheidbar |
| T-N-10 | Host beendet Lobby, Client noch verbunden | Client kehrt sauber ins Menü zurück |
| T-N-11 | 4 parallele Matches mit verteilten Match-Hosts, gleichzeitiger Ergebnisversand | Alle 4 Ergebnisse korrekt im Bracket, keine Race Condition |
| T-B-01 | `codesign --verify` auf der gebauten `.app` | „valid on disk"; Build bricht sonst ab (ADR-012) |
| T-B-02 | `.app` auf einem **fremden** Apple-Silicon-Mac starten | Startet nach Rechtsklick → „Öffnen"; kein Sofortabbruch |

**Paketverlust simulieren:** macOS `dnctl`/`pfctl`, Linux `tc netem`. Auf Windows via `clumsy`. Der Verlust-Test ist der wichtigste — auf WLAN-Partys ist er der Normalfall, nicht der Sonderfall.

## 5. Desync- und Vorhersagefehler-Überwachung

Der Checksum-Mechanismus aus `04_NETCODE` §9 wird zum Testinstrument:

- **Entwicklungs-Build:** Jede Abweichung zwischen Client-Vorhersage und Host-Zustand > 2 px wird mit Tick, Werten und den letzten 30 Input-Frames nach `desync.log` geschrieben.
- **Abnahme:** 100 Sätze über echtes LAN, Ziel 0 Einträge über der Schwelle. Einträge unter der Schwelle (normale Korrekturen) werden gezählt und als Rate protokolliert.
- **Release-Build:** Zähler im F3-Overlay, kein Log.

## 6. Ebene D — Manuelle Abnahme

### D1 — Spielgefühl (nach M0, blockierend)

Drei Personen, die den Prototyp kennen, spielen je 3 Sätze mit alter und neuer Version im Blindwechsel. **Frage: „Welche Version war Nummer 1?"** Wenn mehr als eine Person die neue Version korrekt als „anders" identifiziert und die Änderung negativ bewertet, ist M0 nicht abgenommen.

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
