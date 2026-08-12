# Handoff CC-03 — LAN-Spiel 1v1

**Meilenstein:** M2 · **Aufgaben:** M2-01 … M2-10 aus `08_ROADMAP_BACKLOG.md`
**Geschätzter Aufwand:** 25–35 h · **Abhängig von:** M0 (abgenommen), M1 (gebaut)
**Erstellt:** 2026-08-12 · **Status:** freigegeben zur Ausführung

---

## 0. Lies zuerst

`CLAUDE.md` im Wurzelverzeichnis, dann diese Datei, dann **`docs/04_NETCODE_SPEC.md`
vollständig** — das ist das maßgebliche Dokument dieses Meilensteins, nicht dein
Trainingswissen über Netcode. Dazu `docs/13_INPUTFRAME_FORMAT.md` und
`docs/07_TEST_PLAN.md` §4 (Ebene C, die Fälle T-N-01…T-N-11).

Für den Stand der Vorgänger: `docs/handoffs/M0_REPORT.md` und
`docs/handoffs/CC-02_REPORT.md`.

Erst danach fasst du eine Datei an.

---

## 1. Wo das Projekt steht

M0 ist abgenommen (D1 als Product-Owner-Abnahme, eine Person, im Testplan §6 so
protokolliert). M1 ist gebaut: `tools/build.sh` erzeugt beide Plattformpakete, die CI läuft,
`v0.1.0` liegt als Release-Entwurf. Offen aus M1 ist allein **M1-07**, der Start der ZIPs
auf fremden Rechnern — das braucht Hardware, keinen Code, und blockiert M2 nicht.

**Die Naht für den Netzwerkcode ist bereits gelegt.** Das ist der eigentliche Ertrag von M0
und der Grund, warum M2 kein Umbau wird:

| Was da ist | Wo | Warum es für M2 zählt |
|---|---|---|
| `InputFrame` als einzige Eingabe der Simulation | `src/input/frame.lua` | Der Host bekommt vom Netz denselben Datentyp wie von der Tastatur (ADR-014, B-03) |
| Vier austauschbare Quellen, drei davon gebaut | `src/input/{local,bot}_source.lua` | `net_source.lua` ist die vierte und fügt sich ohne Sonderweg ein |
| `sources[]` + `inputs[]` je Slot, einmal pro Tick abgefragt | `src/app/scenes/local_game.lua:147` | Genau hier hängt sich eine Netzquelle ein |
| Fixer Schritt 1/60 mit Akkumulator | dieselbe Datei | Host-Tick und Snapshot-Takt sind schon vorhanden |
| `src/sim/` ist `love`-frei und zufallsfrei | `--test-no-love` belegt es | Der Zustand ist serialisierbar, ohne Hardware anzufassen |
| `Ruleset` getrennt von `Prefs`, kanonisch gehasht | `src/sim/ruleset.lua` | Der Abgleich aus `04_NETCODE` §10 braucht nur noch den Transport |

`src/net/` existiert noch nicht. `03_TECH` §2 sieht dort fünf Dateien vor; das ist die
Zielstruktur.

---

## 2. Drei Widersprüche zwischen Spec und Code — vor dem ersten Byte klären

Alle drei sind beim Schreiben dieses Handoffs aufgefallen. Nach der Regel aus `CLAUDE.md` §2
wird **erst die Spec geändert, dann der Code** — also entscheide das zuerst und schreib es
in `04_NETCODE_SPEC`, bevor du `protocol.lua` anlegst.

### W-01 — Der Ruleset-Hash ist nicht MD5

`04_NETCODE` §10 verlangt „MD5 über das kanonisch serialisierte Ruleset", und §5 reserviert
im Nachrichtenformat `rulesetHash(16)` — sechzehn Byte.

**Gebaut ist etwas anderes:** `Ruleset.hash` rechnet djb2 über die kanonische Form und
liefert **acht Hexstellen** (`src/sim/ruleset.lua:236 ff.`). Das ist kein Versehen, sondern
die in `CLAUDE.md` §7 ausdrücklich protokollierte Ausnahme aus M0-09: `love.data.hash` hätte
`love` unter `src/sim/` gebracht und die Ebenen A und B headless unbrauchbar gemacht.

**Empfehlung: die Spec nachziehen, nicht den Code.** Das Feld wird zu `rulesetHash(8)` als
ASCII-Hex. Der Hash muss abweichende Rulesets erkennen — mehr nicht, er sichert nichts ab.
Für diesen Zweck reicht djb2, und die `love`-Freiheit der Simulation ist die teurere
Eigenschaft. Wenn du anderer Meinung bist, sag es **vorher** mit Begründung.

### W-02 — Die Phasen im Snapshot gibt es so nicht

`04_NETCODE` §6 kodiert `phase` als `0 serve, 1 play, 2 fault, 3 setover, 4 matchover`.
`src/sim/state.lua:61` kennt `menu | serve | play | gameover`.

Zwei der Spec-Phasen existieren nicht, zwei der echten fehlen. Ein Encoder, der das nicht
merkt, überträgt stillschweigend Unsinn.

**Zu tun:** Die tatsächlichen Phasen aus `state.lua` erheben, die Abbildung festlegen und
§6 entsprechend berichtigen. Prüfe bei der Gelegenheit die **gesamte** Feldliste des
Snapshots gegen `state.lua` — `setsA`/`setsB` und `lastTouchPlayer` sind die nächsten
Kandidaten. Das ist die erste Aufgabe von M2-01, nicht eine Nacharbeit.

### W-03 — `RULESET_FULL` ist als JSON spezifiziert, es gibt keinen JSON-Leser

`04_NETCODE` §5 überträgt Nachricht `0x12` als „vollständiges Ruleset als JSON".
`12_OPENSOURCE` §3 führt dazu `src/lib/json.lua` (MIT) in der Fremdkomponententabelle auf.

**Diese Datei existiert nicht**, und `LICENSE-THIRD-PARTY.md` hält seit M1-08 fest, dass das
Projekt keine Fremdbibliothek benutzt. Der Punkt trifft **M2**, nicht erst den Turniermodus:
`RULESET_FULL` gehört zu AP-5. Drei Wege:

| Weg | Kosten |
|---|---|
| `json.lua` aufnehmen | braucht **ADR**, Eintrag in `LICENSE-THIRD-PARTY.md`, erste Fremdabhängigkeit des Projekts |
| Ruleset mit `love.data.pack` als festes Feldlayout übertragen | kein neuer Code außerhalb von `protocol.lua`, dafür muss das Layout bei jeder Ruleset-Änderung mitgezogen werden |
| Eigener Kleinstserialisierer für die flache Tabelle | rund 30 Zeilen, kein ADR |

**Empfehlung: der zweite Weg.** Das Ruleset ist eine flache Tabelle aus Zahlen und
Wahrheitswerten, die kanonische Form existiert bereits für den Hash (`Ruleset.canonical`),
und `protocol.lua` packt ohnehin schon Felder. JSON löst hier ein Problem, das es nicht gibt.
Wenn M4 später wirklich strukturiertes JSON braucht (`TOURNAMENT_STATE`, 0x40), ist das eine
eigene Entscheidung mit eigenem ADR — und dann für genau diese eine Nachricht.

---

## 3. Auftrag

Reihenfolge aus `08_ROADMAP` §2. Die Abnahmefälle stehen in `07_TEST_PLAN` §4.

### AP-1 — Protokoll (M2-01, 4 h)

`src/net/protocol.lua`: 3-Byte-Header, alle Nachrichtentypen aus `04_NETCODE` §5, pack und
unpack als Paar. **Little-Endian mit explizit dimensionierten Typen** (`<i4`, `<f`) — ohne
das interpretieren Windows und macOS dieselben Bytes unterschiedlich.

Diese Datei ist `love`-abhängig (`love.data.pack`) und gehört deshalb **nicht** unter
`src/sim/`. Sie ist trotzdem für sich testbar: pack → unpack → Vergleich, ohne Netz.

**Abnahme:** Ein Unit-Test je Nachrichtentyp im Headless-Runner. Achtung — der Runner läuft
in der CI unter reinem LuaJIT ohne `love`. Entweder die Protokolltests laufen nur unter
`love . --test`, oder du kapselst `love.data` hinter einer schmalen Schicht. Entscheide das
bewusst und schreib die Begründung dazu.

### AP-2 — Host (M2-02, 5 h)

`src/net/host.lua`: ENet-Host auf Port 21212, Simulation ansteuern, Snapshot je Tick.

- **Die Ereignisschleife pro Frame vollständig leeren** (`04_NETCODE` §4). Ein Ereignis pro
  Durchlauf staut die Queue bei 60 Hz sofort auf. Testfall T-N-08 prüft genau das.
- **Peer-Timeout auf 5000 ms.** Der ENet-Default von 30 s lässt tote Slots stehen.
- Fehlender Input: **letzte bekannte Maske wiederholen**, nicht Null (`04_NETCODE` §7).
  Null-Input lässt den Blob bei jedem Paketverlust stehenbleiben.
- Der Host spielt mit. Kein dedizierter Server.

### AP-3 — Client (M2-03, 5 h)

`src/net/client.lua` und `src/input/net_source.lua`: Input senden, Snapshots empfangen,
**Interpolationspuffer von 2 Ticks**. Der Client simuliert in M2 **nicht** — die eigene
Blob-Vorhersage ist M3 und wird hier nicht vorweggenommen (`04_NETCODE` §8).

Jedes `INPUT`-Paket trägt die Masken der letzten **drei** Ticks. Das kostet 2 Byte und macht
Einzelpaketverluste unsichtbar (T-N-02).

### AP-4 — Discovery und Serverliste (M2-04, M2-05, 7 h)

`src/net/discovery.lua` auf UDP 21213, `ANNOUNCE` im Sekundentakt, sofortige Antwort auf
`PROBE`. Magic ist `VLYD`. **`settimeout(0)`, gepollt in `love.update`** — ein blockierender
Aufruf hält die gesamte Hauptschleife an (`CLAUDE.md` §7).

> **Die manuelle IP-Eingabe ist Pflichtfeature, nicht Notlösung** (`04_NETCODE` §11). Sie
> steht als letzter Eintrag in der Serverliste, nicht in einem Untermenü. Auf einer fremden
> Party ist die Firewall der Normalfall, und dieser eine Eintrag rettet den Abend. Der Host
> zeigt seine LAN-IP groß in der Lobby.

### AP-5 — Lobby und Abgleich (M2-06, M2-07, 6 h)

Slots, Ready-Status, Ruleset-Verteilung. Drei Prüfungen mit **drei unterschiedlichen
Konsequenzen** — die Trennung ist der Grund, warum am Partyabend niemand rätselt:

| Abweichung | Folge | Meldung |
|---|---|---|
| `protoVersion` | **harte Ablehnung** beim Join | Klartext, kein Timeout |
| `rulesetHash` | **Match startet nicht** | Klartext |
| `buildHash` | **nur Warnung** | Ein kosmetischer Patch darf kein Turnier blockieren |

Version und Build-Hash stehen bereits im Menü unten rechts (`src/app/build_info.lua`).

### AP-6 — Trennung, Overlay, Testharness (M2-08 … M2-10, 8 h)

Reconnect mit derselben `clientId` in den laufenden Zustand, 30-s-Fenster, danach Walkover.
F3-Overlay mit RTT, Verlust, Tick und Korrekturen — die Bug-Vorlage im Repo fragt genau
diese Werte ab.

Für den Integrationstest: zwei LÖVE-Instanzen auf `127.0.0.1`. `tools/replay_source.lua`
und die elf aufgezeichneten Rallyes unter `tests/replays/` liefern reproduzierbare Eingaben
— damit wird der Netzwerktest wiederholbar statt handgespielt. Paketverlust simulierst du
unter Windows mit `clumsy`.

---

## 4. Was du in dieser Session nicht tust

- **Keine Client-seitige Vorhersage.** Das ist M3 und ausdrücklich nach M2 terminiert.
- **Kein Rollback, kein Lockstep.** Verworfen in ADR-002, mit vier Gründen in
  `04_NETCODE` §1. Nicht erneut vorschlagen.
- **Keine Änderung an `src/sim/`.** Wenn du dort etwas anfassen musst, ist etwas anderes
  falsch. Die Zahlen aus `02_CODE_AUDIT` §4 bleiben unangetastet.
- **Nichts aus M4** (Turnier) oder M5 (Spectator, Beamer).
- **Keine externen Bibliotheken.** `lua-enet` und `luasocket` stecken in LÖVE.

---

## 5. Abnahme

`07_TEST_PLAN` §4, Fälle **T-N-01 bis T-N-10**. T-N-11 gehört zu M4 und wird hier nicht
verlangt. Zusätzlich D2 (LAN-Party-Simulation, `07_TEST_PLAN` §6) — das braucht zwei
Rechner und ist die eigentliche Abnahme des Meilensteins.

Vor jedem Commit unverändert:

```powershell
D:\love2d\LOVE\lovec.exe . --test          # muss "83 bestanden, 0 gescheitert" melden
D:\love2d\LOVE\lovec.exe . --test-no-love
python tools\verify_replays.py
```

Die Zahl 83 steigt mit den neuen Protokolltests. Was nicht steigen darf, ist die Zahl der
gescheiterten.

**Zwei Punkte, die die CI jetzt lösen kann und vorher nicht:**

- **N-03 / T-N-07** (`love.data.pack("<f", …)` bitidentisch auf Windows und macOS) galt als
  „vor M2 einmal verifizieren", war aber ohne Mac nicht prüfbar. Seit M1-11 gibt es einen
  macOS-Runner. Ein Testfall, der gepackte Bytes gegen eine eingecheckte Referenz vergleicht
  und auf beiden Läufern läuft, schließt den Punkt endgültig.
- **N-04** (ENet auf macOS ohne zusätzliche Firewall-Freigabe) bleibt offen — das braucht
  einen echten Mac im Netz, kein CI-Image.

---

## 6. Rückmeldung

Am Ende `docs/handoffs/CC-03_REPORT.md` mit denselben Abschnitten wie CC-01 und CC-02:
Erledigt · Nicht erledigt und warum · Befunde · Spec-Änderungen · Entscheidungen für
r0btoshi · Nächster Schritt.

Trag den Stand außerdem in `08_ROADMAP` §2 als Statusspalte bei M2 nach und ergänze
`CHANGELOG.md` unter `[Unreleased]` — der Release-Prozess aus `12_OPENSOURCE` §7 setzt
voraus, dass beides gepflegt ist, bevor ein Tag gesetzt wird.
