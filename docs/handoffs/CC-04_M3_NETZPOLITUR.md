# Handoff CC-04 — Netzwerk-Politur

**Meilenstein:** M3 · **Aufgaben:** M3-01 … M3-04 aus `08_ROADMAP_BACKLOG.md`
**Geschätzter Aufwand:** 10–15 h · **Abhängig von:** M2 (abgeschlossen, `v0.2.2` veröffentlicht)
**Erstellt:** 2026-08-12 · **Status:** freigegeben zur Ausführung

---

## 0. Lies zuerst

`CLAUDE.md` im Wurzelverzeichnis, dann diese Datei, dann **`docs/04_NETCODE_SPEC.md` §6, §8
und §9** — das sind die drei Abschnitte, um die es in diesem Meilenstein geht. Dazu
`docs/handoffs/CC-03_REPORT.md`: dort steht, was M2 gebaut hat, was im LAN gemessen wurde
und welche zwei Befunde für M3 die Vorarbeit sind.

Erst danach fasst du eine Datei an.

---

## 1. Wo das Projekt steht

**M2 ist abgeschlossen und veröffentlicht.** Zwei Rechner (Windows und macOS) haben im LAN in
beiden Richtungen gespielt: Discovery ohne IP-Eingabe, Lobby, Match, Verbindungsabbruch,
Wiedereinstieg in den laufenden Satz, Revanche. `v0.2.2` liegt als öffentlicher Release mit
Paketen für beide Plattformen.

Der Netzcode liegt unter `src/net/`, aufgeteilt nach dem, was er braucht:

| Datei | Abhängig von | Wofür |
|---|---|---|
| `snapshot.lua` | nichts | Zustand ↔ Snapshot, Phasen, Flags, Quantisierung |
| `input_queue.lua` | nichts | Jitter-Puffer, Redundanz, Repeat-Last |
| `lobby.lua` | nichts | Slots, Ready, Abgleich mit drei Konsequenzen |
| `protocol.lua` | `love.data` | Bytes, alle Nachrichtentypen |
| `host.lua` | `enet` | autoritative Seite |
| `client.lua` | `enet` | empfangende Seite |
| `discovery.lua` | `socket` | UDP-Broadcast |

Die ersten drei laufen im Headless-Runner mit; die anderen vier nicht. Was **entscheidet**,
gehört nach oben in diese Tabelle — das ist die Regel, an der sich auch M3 halten sollte.

**Zwei Befunde aus M2 sind unmittelbare Vorarbeit für M3:**

- **B-N-07 (Vorzeichen der Null).** Windows und macOS erzeugen bei `-0` unterschiedliche
  Bitmuster, weil LÖVE auf Apple Silicon den Interpreter statt des JIT fährt. `snapshot.lua`
  begradigt das vor dem Senden. **M3-03 hängt daran:** eine Prüfsumme darf nur über Werte
  laufen, die auf beiden Plattformen bitgleich entstehen. Prüfe das erneut, statt es
  anzunehmen.
- **Das Feld „KORREKTUR" im F3-Overlay existiert und meldet 0.** `src/render/netstat.lua`
  zeichnet es bereits. M3-01 füllt es, statt ein neues zu erfinden.

---

## 2. Auftrag

### AP-1 — Vorhersage des eigenen Blobs (M3-01, 5 h)

`04_NETCODE_SPEC` §8. Der Client simuliert **ausschließlich seinen eigenen Blob** sofort
lokal: horizontale Geschwindigkeit aus dem Input, Schwerkraft, Boden, Netzgrenze. Ball,
Gegnerblob und Punktestand kommen weiterhin ausschließlich vom Host.

- Bei jedem Snapshot die vorhergesagte Position mit der Host-Position vergleichen.
  **Abweichung > 2 px → sanfte Korrektur über 4 Ticks**, kein harter Sprung.
- Jede Korrektur zählt in den Zähler, der im F3-Overlay steht.
- **Warum nur der eigene Blob:** Die Blob-Bewegung enthält keine Ballkollision und ist
  deshalb fehlerfrei vorhersagbar — außer im Moment eines Ballkontakts, und der verändert
  die Blob-Position nicht. Den Ball vorherzusagen bräuchte Rollback; das ist in ADR-002
  verworfen und wird nicht neu verhandelt.

**Wo das hingehört:** Die Vorhersage ist Simulation und muss dieselbe Physik benutzen wie der
Host — sonst driftet sie systematisch. `src/sim/step.lua` bewegt den Blob in
`updateBlobTimers` und `Physics.updateBlob`. Beides ist `love`-frei und aufrufbar; **ändere
es nicht**, sondern rufe es auf.

**Abnahme:** Ein Test der Ebene B, der ohne Netz auskommt: gegebene Eingabefolge, vorhergesagte
Bahn gegen die Bahn desselben Blobs aus `Step.tick` — sie müssen übereinstimmen, solange kein
Ballkontakt dazwischenliegt. Dazu ein Korrekturtest: künstlich versetzte Host-Position,
Annäherung über vier Ticks, kein Sprung.

### AP-2 — Kosmetik aus Snapshot-Deltas (M3-02, 3 h)

`04_NETCODE_SPEC` §6. Der Gast sieht bis heute keine Partikel und hört keine Klänge — er
simuliert nicht und bekommt deshalb keine Ereignisse. Die Auslöser werden aus dem Übergang
zwischen zwei Snapshots abgeleitet: Ball war rechts von der Wand, jetzt links, VX hat das
Vorzeichen gewechselt → Wandtreffer.

Die Zuordnung Ereignis → Staub, Klang, Wackeln steht bereits in
`src/render/fx_events.lua` und wird von beiden Seiten benutzt. **Neu ist nur die Erkennung**,
und die gehört in die Renderschicht, nicht in die Simulation.

Mindestens: Wandtreffer, Netztreffer, Blobtreffer, Landung, Aufschlag, Punkt.

**Abnahme:** Die Erkennung ist eine reine Funktion über zwei Snapshots und gehört damit in
den Headless-Runner. Zwei aufeinanderfolgende Snapshots hinein, erwartete Ereignisliste
heraus. Kein Bild nötig.

### AP-3 — Desync-Detektor (M3-03, 2 h)

`04_NETCODE_SPEC` §9. Der Host rechnet alle 30 Ticks eine Prüfsumme über den
Simulationszustand und sendet sie als `CHECKSUM` (0x60, Codec liegt fertig in
`protocol.lua`). Der Client vergleicht sie mit seiner Vorhersage.

Das erkennt keinen Desync im Lockstep-Sinne — den kann es nicht geben —, sondern
**Vorhersage- und Protokollfehler**. In der Entwicklung wird jede Abweichung nach
`desync.log` geschrieben, im Release ist sie ein stiller Zähler im F3-Overlay.

**Achtung, siehe §1:** Erst prüfen, worüber die Prüfsumme laufen darf. Ein Feld, das auf zwei
Plattformen unterschiedlich entsteht, erzeugt einen Fehlalarm je Tick — und ein Detektor, der
dauernd falsch anschlägt, wird nach zwei Abenden ignoriert.

### AP-4 — WLAN-Messung (M3-04, 3 h)

Offener Punkt **N-01** aus `04_NETCODE_SPEC` §13: Reicht die Vorhersage des eigenen Blobs bei
RTT 20–40 ms, oder braucht der Client zusätzlich eine Ball-Extrapolation? Das ist **keine
Entwurfs-, sondern eine Messfrage** — sie braucht ein WLAN und zwei Menschen.

Der Harness liefert die Zahlen: `tools/net_test.sh`, F3-Overlay, und unter Windows `clumsy`
für künstliche Latenz. **Ergebnis in `04_NETCODE_SPEC` §13 eintragen**, nicht nur im Report.

---

## 3. Nachlauf aus M2

Drei Abnahmefälle aus `07_TEST_PLAN` §4 sind offen. Keiner davon braucht Code, alle brauchen
eine Bedingung, die sich nicht herstellen lässt, indem man sie sich vornimmt:

| Fall | Was fehlt |
|---|---|
| T-N-02 | 5 % Paketverlust auf Kanal 2 — `clumsy` von Hand, Filter im Kopf von `tools/net_test.sh` |
| T-N-03 | 20 % Paketverlust auf Kanal 1 |
| T-N-09 | drei Lobbys gleichzeitig im selben Netz — braucht drei Rechner |

Nimm sie mit, wenn die WLAN-Messung aus AP-4 ohnehin Hardware zusammenbringt. Sie sind
**nicht** Voraussetzung für M3, sondern Restschuld aus M2.

---

## 4. Was du in dieser Session nicht tust

- **Kein Rollback, kein Lockstep.** ADR-002, vier Gründe in `04_NETCODE` §1. Nicht erneut
  vorschlagen.
- **Keine Ball-Vorhersage**, bevor AP-4 gemessen hat, dass sie nötig ist. Sie ist der Punkt,
  an dem die Komplexität explodiert.
- **Keine Änderung an `src/sim/`.** Die Vorhersage *benutzt* die Simulation, sie kopiert sie
  nicht. Die Zahlen aus `02_CODE_AUDIT` §4 bleiben unangetastet.
- **Nichts aus M4** (Turnier) oder M5 (Spectator, Beamer).
- **Kein 2v2, keine Mutatoren.** M6, und erst nach M5.

---

## 5. Abnahme

`07_TEST_PLAN` §4, soweit die Fälle M3 betreffen, plus:

```powershell
D:\love2d\LOVE\lovec.exe . --test          # muss "179 bestanden, 0 gescheitert" oder mehr melden
D:\love2d\LOVE\lovec.exe . --test-no-love  # 148 bestanden, kein love im Namensraum
D:\love2d\LOVE\lovec.exe . --net-selftest  # 37 Pruefungen, alle gruen
python tools\verify_replays.py             # muss "OK" melden
```

Die Zahlen steigen mit den neuen Tests. Was nicht steigen darf, ist die Zahl der
gescheiterten.

**Und die eigentliche Abnahme:** Ein Match über WLAN, bei dem der Gast nicht mehr sagen kann,
ob er Host oder Gast ist. Das ist das Ziel von M3 — alles andere sind Mittel.

---

## 6. Rückmeldung

Am Ende `docs/handoffs/CC-04_REPORT.md` mit denselben Abschnitten wie CC-01 bis CC-03:
Erledigt · Nicht erledigt und warum · Befunde · Spec-Änderungen · Entscheidungen für
r0btoshi · Nächster Schritt.

Stand in `08_ROADMAP` §2 nachtragen und `CHANGELOG.md` unter `[Unreleased]` ergänzen — der
Release-Prozess aus `12_OPENSOURCE` §7 setzt beides voraus, bevor ein Tag gesetzt wird.
