# 08 — Roadmap & Backlog

**Version:** 1.0 · **Stand:** 2026-08-11
**Kapazitätsannahme:** 4–8 h/Woche, nebenberuflich.

---

## 1. Meilensteinübersicht

| M | Titel | Aufwand | Ergebnis für dich | Abhängig von |
|---|-------|---------|-------------------|--------------|
| **M0** | Refactoring-Fundament | 20–30 h | Gleiches Spiel, tragfähige Basis | — |
| **M1** | Build-Pipeline Win + macOS + Open-Source-Repo | 17–21 h | **Erste verteilbare ZIP** | M0 |
| **M2** | LAN 1v1 | 25–35 h | **Zwei Rechner spielen gegeneinander** | M0, M1 |
| **M3** | Netzwerk-Politur | 10–15 h | Fühlt sich lokal an | M2 |
| **M4** | Turniermodus (inkl. parallele Matches) | 36–48 h | **Turnierabend ohne Zettel** | M2 |
| **M5** | Spectator + Beamer | 12–18 h | Party-Tauglichkeit | M2, M4 |
| **M6** | Modi & Mutatoren | offen | Langfrist-Wiederspielwert | M5 |

**Gesamtaufwand bis v1.0 (M0–M5): 120–170 h.** Bei 6 h/Woche sind das **5–7 Monate**.

Gegenüber Fassung 1.0 um rund 15–20 h gestiegen: Open-Source-Repo-Aufbau (ADR-011) und verpflichtende parallele Matches bei 20 Teilnehmern (ADR-013).

**Wichtigste Reihenfolgeentscheidung: M1 vor M2.** Die Build-Pipeline kommt vor dem Netzwerk, obwohl das Netzwerk das interessantere Problem ist. Grund: Nach M1 hast du ein Artefakt, das du Leuten in die Hand drücken kannst — auch wenn nur lokales 1v1 drin ist. Das erzeugt echtes Feedback, während der Netcode noch entsteht. Umgekehrt hättest du nach M2 einen tollen Netcode, den niemand starten kann.

## 2. Meilensteine im Detail

### M0 — Refactoring-Fundament (20–30 h)

**Ziel:** Der Prototyp spielt sich identisch, ist aber netzwerk- und turnierfähig gebaut.
**Abnahme:** D1 (Blindtest Spielgefühl) + Ebene A/B grün.

| ID | Aufgabe | h | Ref |
|----|---------|---|-----|
| M0-01 | `conf.lua` anlegen, Module abschalten | 1 | F-07 |
| M0-02 | Fonts vorladen, Sound-Pool | 1 | B-08, F-04 |
| M0-03 | `record_replay.lua` + 12 Referenz-Rallyes aufzeichnen | 3 | Testplan §2 |
| M0-04 | Weltgeometrie fixieren, `viewport.lua` mit Letterbox | 3 | **B-01** |
| M0-05 | Fixer Timestep 1/60 + Akkumulator + Render-Interpolation | 4 | **B-02** |
| M0-06 | `InputFrame` + `local_source` (Tastatur, Gamepad, Doppeltipp-Dash) | 4 | **B-03**, ADR-014, `13_INPUTFRAME_FORMAT` |
| M0-07 | Bot aus `main.lua` nach `bot_source.lua` heben, auf `InputFrame`, Instanzierung | 3 | B-07, B-09 |
| M0-08 | `sim/`-Extraktion: state, physics, rules, step; Reinheit herstellen | 6 | §3 `03_TECH` |
| M0-09 | `Ruleset`/`Prefs`-Trennung, Presets, kanonischer Hash | 3 | **B-04** |
| M0-10 | Regelkorrekturen: 2-Punkte-Vorsprung, fixe Aufschlagverzögerung, Rallye-Timeout | 2 | B-05, B-06, P5 |
| M0-11 | Tastenbelegung konfigurierbar + persistent | 2 | GDD §7 |
| M0-12 | Szenen-Stack, `main.lua` unter 100 Zeilen, UI nach `ui/` | 3 | — |
| M0-13 | Headless-Testrunner ohne LÖVE ausbauen + Regel-Unit-Tests | 3 | Testplan §3 |

### M1 — Build-Pipeline + Open-Source-Repo (17–21 h)

**Ziel:** Eine ZIP pro Plattform, die überall startet.
**Abnahme:** `06_BUILD` §8.

| ID | Aufgabe | h | Stand 2026-08-12 (CC-02) |
|----|---------|---|---|
| M1-01 | `build.sh`, `.love`-Erzeugung, Ausschlusslisten | 2 | ✅ `.love` gebaut und gestartet |
| M1-02 | Windows-Fusion + DLL-Bundle + `license.txt` | 2 | ✅ ZIP gebaut, EXE spielt ein Match |
| M1-03 | macOS-`.app`, `patch_plist.py`, `zip -y` | 3 | ⚠️ geschrieben, **ungetestet** (kein Mac, kein Runner) |
| M1-04 | `build_info.lua`-Injektion (Version + Build-Hash) | 1 | ✅ steht unten rechts im Menü |
| M1-05 | `LIESMICH.txt` beide Plattformen inkl. Gatekeeper-/SmartScreen-Weg | 1 | ✅ `dist/LIESMICH_{win,mac}.txt` |
| M1-06 | Icon in `love.exe`, Icon in `.app` | 1 | ◐ Fenster- und `.app`-Symbol automatisch, **EXE-Symbol bleibt Handgriff** (`06_BUILD` §3) |
| M1-07 | Test auf Fremdrechnern (Win 11, Intel-Mac, Apple Silicon) | 2 | ❌ offen, braucht fremde Hardware |
| M1-3b | **Ad-hoc-Signatur + `codesign --verify` als Abbruchbedingung** (ADR-012) | 1 | ⚠️ im Skript und im Workflow, unbelegt bis zum ersten Tag-Build |
| M1-08 | `LICENSE`, `LICENSE-THIRD-PARTY.md`, `docs/references.md` | 1 | ✅ |
| M1-09 | `assets/CREDITS.md` + prozeduraler Fallback als Standard | 2 | ✅ Assets nach `assets/`, Hintergrund verkleinert |
| M1-10 | Öffentliches README inkl. Gameplay-GIF | 2 | ◐ README steht, **statt GIF zwei Bildschirmfotos** |
| M1-11 | GitHub Actions: Tests bei Push, Vollbuild bei Tag | 3 | ⚠️ geschrieben, läuft erst mit dem ersten Push |
| M1-12 | Issue-Vorlagen, `CONTRIBUTING.md`, `.gitignore` | 1 | ✅ |

**Zum prozeduralen Fallback in M1-09:** Er ist nicht „umgestellt worden", er war schon da.
Jede Zeichenstelle hat ihren `else`-Zweig, jeder Lader gibt `nil` zurück statt zu werfen
(`ASSET_INVENTORY` §3). Da die Herkunft aller Dateien geklärt ist, bleiben die Bilder der
Normalfall und der Fallback die Absicherung — das ist die Umkehrung dessen, was
`10_LEGAL` §4 vorsah, und sie ist zulässig, weil der Grund für die Vorsicht entfallen ist.

**Was M1 nicht abschließt:** M1-07 hängt an fremder Hardware, M1-03/M1-3b/M1-11 hängen am
ersten Push. Bis dahin gilt für den macOS-Pfad: geschrieben, nicht bewiesen.

### M2 — LAN 1v1 (25–35 h) — **ABGESCHLOSSEN 2026-08-12, `v0.2.2` veröffentlicht**

**Ziel:** Zwei Rechner, ein Match, keine IP-Eingabe nötig.
**Abnahme:** T-N-01…T-N-10 + D2.

| ID | Aufgabe | h | Stand (CC-03, 2026-08-12) |
|----|---------|---|---|
| M2-01 | `protocol.lua`: Header, pack/unpack, alle Nachrichtentypen | 4 | **fertig** — dazu `snapshot.lua`, `input_queue.lua`, `lobby.lua` als `love`-freie Hälfte; 30 Protokolltests |
| M2-02 | `host.lua`: ENet-Host, Sim-Ansteuerung, Snapshot-Versand | 5 | **fertig** |
| M2-03 | `client.lua`: Input-Versand, Snapshot-Empfang, Interpolationspuffer | 5 | **fertig** — ohne Vorhersage, die ist M3-01 |
| M2-04 | `discovery.lua`: UDP-Broadcast Announce/Probe | 4 | **fertig** — im LAN erst mit D2 belegt (N-05) |
| M2-05 | Serverliste-UI + manuelle IP-Eingabe als Pflicht-Fallback | 3 | **fertig** |
| M2-06 | `lobby.lua`: Slots, Ready, Ruleset-Verteilung, Host-Einstellungen | 4 | **fertig** |
| M2-07 | Ruleset-/Proto-/Build-Hash-Abgleich mit Klartextfehlern | 2 | **fertig** — drei Konsequenzen, mit Tests |
| M2-08 | Trennung, Reconnect, Timeouts | 3 | **fertig** — Pause, 30-s-Fenster, Walkover |
| M2-09 | F3-Debug-Overlay (RTT, Verlust, Tick, Korrekturen) | 2 | **fertig** |
| M2-10 | Integrationstest-Harness (2 Prozesse), Paketverlust-Tests | 3 | **teilweise** — Harness läuft (`tools/net_test.sh`), Paketverlust braucht `clumsy` von Hand |

**D2 ist gelaufen (2026-08-12, Windows gegen macOS) und bestanden.** T-N-01 in beiden
Richtungen, T-N-04 und T-N-05 abgenommen; **N-04 damit ebenfalls beantwortet** — ENet nimmt
auf macOS eingehende Verbindungen an. Zwei Discovery-Fehler gefunden und in 0.2.1 behoben
(B-N-08, B-N-09 im Report). Die manuelle IP-Eingabe hat den Abend zweimal gerettet.
**M1-07 ist damit erledigt.**

**Gegenprobe mit 0.2.1 bestanden:** Suche und Wiedereinstieg laufen in beiden Richtungen ohne
IP-Eingabe. In 0.2.2 kam die Revanche dazu (`R` war im Netzspiel ohne Wirkung, B-N-10).

**Restschuld aus M2, ohne Codeanteil:** T-N-02 und T-N-03 (Paketverlust, braucht `clumsy` von
Hand) und T-N-09 (drei Lobbys gleichzeitig, braucht drei Rechner). Sie sind in den
M3-Auftrag `docs/handoffs/CC-04_M3_NETZPOLITUR.md` §3 übernommen, weil die WLAN-Messung aus
M3-04 ohnehin Hardware zusammenbringt.

**Geschlossen in M2:** N-03 (gleiche Bytes auf Windows und macOS) — beantwortet durch T-N-07
in der CI, mit einer gefundenen Ausnahme beim Vorzeichen der Null (`04_NETCODE` §6).

### M3 — Netzwerk-Politur (10–15 h) — **ABGESCHLOSSEN 2026-08-13, `v0.3.0` veröffentlicht**, Auftrag: `docs/handoffs/CC-04_M3_NETZPOLITUR.md`, Bericht: `docs/handoffs/CC-04_REPORT.md`

| ID | Aufgabe | h | Stand |
|----|---------|---|---|
| M3-01 | Client-Vorhersage des eigenen Blobs + sanfte Korrektur | 5 | **fertig** — `src/net/prediction.lua`, ruft die Simulation auf statt sie zu kopieren (ADR-017) |
| M3-02 | Kosmetik-Ereignisse aus Snapshot-Deltas ableiten (Partikel, Sound) | 3 | **fertig** — `src/render/snapshot_events.lua`, `love`-frei und im Headless-Runner |
| M3-03 | Checksum-/Vorhersagefehler-Überwachung + `desync.log` | 2 | **fertig** — djb2 über die gepackten Snapshot-Bytes (ADR-018), zwei getrennte Zähler |
| M3-04 | WLAN-Test bei RTT 20–40 ms, Bewertung offener Punkt N-01 | 3 | **zurückgestellt (ADR-019).** Gespielt wird über Kabel, dort wird die Frage nicht gestellt. Werkzeug und Messanleitung bleiben im Repo, falls doch jemand im WLAN sitzt |

**Tests:** 214 bestanden (vorher 179), 183 ohne `love` (vorher 148), Netz-Selbsttest 47 Prüfungen
(vorher 37), `verify_replays.py` meldet OK.

**Abnahme:** `v0.3.0` gebaut, das Windows-Paket auf einem Fremdrechner heruntergeladen,
gestartet und gespielt (r0btoshi, 2026-08-13). Damit ist auch die Lücke aus dem CC-04-Bericht
geschlossen, dass die Spielszene in der Entwicklungsumgebung nie ausgeführt wurde.
**Das macOS-Paket ist gebaut und signiert, aber noch auf keinem fremden Mac gestartet.**

**Restschuld, neu bewertet nach ADR-019:**

| Fall | Stand |
|---|---|
| T-N-02, T-N-03 (Paketverlust) | **nicht mehr Abnahmebedingung.** Über Kabel ist Paketverlust ein Defekt, kein Normalfall. Die Logik dahinter ist in Ebene B abgesichert |
| T-N-09 (drei Lobbys gleichzeitig) | **wichtiger geworden und nach M4 verschoben.** Mehrere gleichzeitige Lobbys im selben Netz sind mit parallelen Matches der Normalfall (ADR-013). Gehört in die Abnahme von **M4-09**, nicht in die Restschuld von M2 |
| N-04 (ENet eingehend auf einem frischen Mac) | unverändert offen. Hängt am selben fremden Mac wie das Paket oben |

### M4 — Turniermodus (36–48 h) — **als Nächstes**, Auftrag: `docs/handoffs/CC-05_M4_TURNIER.md`

**Abnahme:** `05_TOURNAMENT` §13 + Chaos-Szenario D3. **Zusätzlich aus M2 übernommen:** T-N-09
(drei gleichzeitige Lobbys) gehört zur Abnahme von M4-09 — bei parallelen Matches ist das der
Normalfall, nicht der Sonderfall.

**Betriebliche Randbedingung, seit ADR-019 fest:** Der Abend läuft über Kabel. Das vereinfacht
nichts am Turniercode, verengt aber die Annahme A1 auf einen Switch und macht die
Discovery-Lage berechenbar.

| ID | Aufgabe | h | Stand 2026-08-13 (CC-05, Stufe A und B) |
|----|---------|---|---|
| M4-01 | `model.lua`: Datenmodell + append-only Log | 4 | ✅ `src/tournament/model.lua`, `love`-frei. Abgeleiteter Zustand wird nach jedem Ereignis neu gerechnet |
| M4-02 | `bracket.lua`: Single Elimination inkl. Freilose | 5 | ✅ klassische Setzung, Freilose an die Höchstgesetzten (E-01), für 4–32 geprüft |
| M4-02b | Automatische Gruppenaufteilung aus beliebiger Teilnehmerzahl (Ziel 4–5/Gruppe) | 2 | ✅ 20 → 4×5, 18 → 2×5+2×4, keine Gruppe unter 3 oder über 6 |
| M4-03 | `bracket.lua`: Round Robin + Tabellenkriterien E-11 | 4 | ✅ Kreismethode (parallelisierbare Runden), E-11 vollständig, echter Gleichstand wird gemeldet statt gewürfelt |
| M4-04 | Gruppen → Elim | 3 | ✅ inkl. Reparaturgang: keine Gruppengegner in der ersten K.o.-Runde |
| M4-05 | `scheduler.lua`: Match-Zustandsautomat, Calling, No-Show-Timer | 5 | ✅ plus E-15/E-16/E-17 (ADR-021) — ohne sie terminiert der Automat nicht |
| M4-06 | `persistence.lua`: atomares Schreiben, Recovery-Dialog | 4 | ✅ vier Schritte nach §7, JSON (ADR-020). Der Dialog „Laufendes Turnier gefunden" ist mit M4-07 dazugekommen |
| M4-07 | Turnier-Lobby-UI, Setzung mit sichtbarem Seed | 4 | ✅ `src/ui/tournament_lobby.lua` + `src/tournament/session.lua`. Anmeldung **am Turnier-Host** (das Netz ist Stufe C), Seed als Text mit nachrechenbarer Zahl, Wiederaufnahme-Dialog, die drei Klänge. `by_rating` zurückgestellt (§9) |
| M4-08 | `bracket_view.lua`: kompakt (Spieler) + voll (Beamer) | 5 | ✅ eigene Linie plus „Nächster Gegner" im Spielermenü, Gruppentabellen bzw. K.o.-Baum am Beamer, aufgerufene Matches blinkend mit Countdown (F2 schaltet um) |
| M4-09 | **Verteilte Match-Hosts bei parallelen Matches — kritischer Pfad, nicht optional** (ADR-013) | 8 | ✅ `src/net/tournament_host.lua`, `tournament_client.lua`, `match_runner.lua`, `src/tournament/host_choice.lua`, `match_stats.lua`. T-01 ist **ADR-022**, das Format von `TOURNAMENT_STATE` **ADR-023**. Abnahme mit `--tournament-selftest` (T-N-11, T-N-09) und einem Vierprozesslauf |
| M4-10 | Export als Markdown/CSV | 1 | ✅ Taste **X** in der vollen Ansicht, auch für Teilnehmer. `src/tournament/export.lua` (Text, `love`-frei) + `Persistence:export` (Schreiben). Namen statt Kennungen, Herkunft offener Plätze, Korrekturen mit Begründung (E-12), die fünf Statistiken (§11) |
| M4-11 | Manuelle Ergebniskorrektur mit Protokollierung | 2 | ✅ vollständig. Bedienung mit M4-07: Ergebnis eintragen, korrigieren (Begründung ist Pflicht), No-Show-Timer anhalten, Match abbrechen, Teilnehmer austragen |

**Stufe A ist abgeschlossen** (CC-05, 2026-08-13): Ein 20er-Turnier läuft im Headless-Runner
vollständig durch — 40 Gruppenmatches, 8 K.o.-Matches, Sieger, inklusive hartem Neustart
mitten in Runde 2 aus der Datei heraus. Bericht: `docs/handoffs/CC-05_REPORT.md`.

**Stufe B ist abgeschlossen** (CC-05, 2026-08-13): Das Turnier ist bedienbar — Menü →
NETWORK MATCH → „Turnier". Anmelden, auslosen, spielen, Sieger; ein 8er-Turnier läuft
ausschließlich über die Tastatur bis zum Sieger durch und steht als Testfall drin.
**Angemeldet wird am Turnier-Host, nicht über das Netz:** Die Match-Lobby aus M2 hat zwei
Plätze (`src/net/lobby.lua`) und startet genau ein Match, und das Format von
`TOURNAMENT_STATE` ist ein offener ADR. Beides gehört zu **M4-09**.

**Stufe C ist abgeschlossen** (CC-05, 2026-08-13): Angemeldet wird über das Netz, gespielt wird
im Turnier. Ein Turnier steht als Bake in der Serverliste; bis zu vier Matches laufen
gleichzeitig, gehostet von einem der beiden Spieler nach **ADR-022**; der Turnierstand geht als
Log-Ereignisse hinaus (**ADR-023**). Der Match-Wirt bindet einen **ephemeren** Port — ein
Prozess kann denselben ENet-Port nicht zweimal binden, und der Turnier-Wirt spielt mit
(`05_TOURNAMENT` §8.2). **T-N-09 ist damit erledigt**, es steckt im Selbsttest.

**Stufe C.1 ist abgeschlossen** (2026-08-13): sechs Befunde aus dem ersten LAN-Abend, dazu
ADR-024 (das Menü hält das Netzspiel nicht mehr an).

**Stufe C.2 ist abgeschlossen** (CC-06, 2026-08-14): Turniere löschen mit
Sicherheitsabfrage (AP-1), die eigene IP im Turnier samt Protokollwechsel bei getippter
Adresse (AP-2, C-T-22), der Weg zurück in ein unterbrochenes Match (AP-3, C-T-20/21 —
Abnahme im Vierprozesslauf mit `--tournament-auto=escaper`), und **AP-4**: Die
Zweirechner-Messung fand C-T-23 (die Puffer-Ratsche) und mündete in **ADR-025** — der Gast
simuliert die ganze Welt lokal vor (BV2-Modell), der Interpolationspuffer ist entfallen,
der Ball wird beim Gast außen am Blob getroffen. Am nächsten LAN-Abend zu prüfen:
`CC-06_AP4_MESSANLEITUNG.md` §5.
Auftrag: `docs/handoffs/CC-06_C2_NACHARBEIT.md`, Bericht: `CC-05_REPORT.md` (fortgeschrieben).

**Stufe D ist abgeschlossen** (CC-05, 2026-08-14): Export als Markdown/CSV mit **X**
(`05_TOURNAMENT` §7, Nachtrag dort). **Damit sind alle Aufgaben von M4 erledigt.** Offen aus
der M4-Abnahme bleibt nur, was Hardware braucht, die es hier nicht gibt: das Chaos-Szenario D3
und die Firewall-Frage des ephemeren Match-Ports auf fremden Rechnern (`11_OPS`, N-04/N-05).

### M5 — Spectator + Beamer (12–18 h)

| ID | Aufgabe | h |
|----|---------|---|
| M5-01 | Spectator-Beitritt zu laufendem Match | 4 |
| M5-02 | Beamer-Szene: Bracket + wählbares Live-Match, `--beamer`-Flag | 5 |
| M5-03 | Match-Kontext im HUD („Halbfinale · Satz 2") | 2 |
| M5-04 | Live-Statistiken (Ballgeschwindigkeit, Rallye-Länge) | 3 |
| M5-05 | Separate Beamer-Lautstärke, Vollbild-Voreinstellung | 1 |

### M6 — Backlog (nicht terminiert)

Nach Nutzen sortiert, nicht nach Aufwand:

| Priorität | Feature | Begründung |
|-----------|---------|------------|
| 1 | **King of the Hill** | Größter Party-Nutzen pro Aufwand. Kein Bracket, kein Warten |
| 2 | Automatische Beamer-Regie | Erst sinnvoll ab 3+ parallelen Matches |
| 3 | Zeitlupen-Replay nach Satzgewinn | Hoher Show-Wert am Beamer |
| 4 | 2v2 | Verbreitertes Feld, Netcode-Erweiterung auf 4 Inputs |
| 5 | Mutator Multi-Ball | Regeldesign E-Fall geklärt (GDD §5) |
| 6 | Mutator Gravity Shift | Am einfachsten umzusetzen, geringster Neuwert |
| 7 | Double Elimination | Verdoppelt Turnierdauer |
| 8 | Schweizer System | Nur ab 20+ Teilnehmern sinnvoll |
| 9 | Bot-Redesign (Vorhersagehorizont statt Jitter) | GDD §6, offene Designfrage |
| 10 | Persistente Spielerprofile über mehrere Abende | Braucht Identität, widerspricht „kein Account" |

## 3. Erster spielbarer Zwischenstand — die drei Wochenenden

Falls die Motivation ein sichtbares Ergebnis braucht, bevor 30 h Refactoring investiert sind, ist das der Weg mit dem kürzesten Pfad zu „zwei Rechner spielen":

| Wochenende | Inhalt | Ergebnis |
|------------|--------|----------|
| 1 | **M0-03 zuerst**, dann M0-04, M0-05, M0-06, M0-08 (die vier Blocker) | Läuft wie vorher, ist aber netzwerkfähig — und der Beweis dafür liegt vor |
| 2 | M1 komplett | ZIPs für Win + Mac, verteilbar |
| 3 | M2-01 bis M2-05 | Zwei Rechner finden sich und spielen (roh, ohne Lobby-Komfort) |

**M0-03 steht bewusst vor den Blockern.** Die Referenz-Rallyes lassen sich nur gegen den unveränderten Prototyp aufzeichnen; M0-04 fixiert die Weltgeometrie, M0-05 den Timestep. Danach existiert das Verhalten, das abgesichert werden soll, nicht mehr. Fassung 1.0 dieses Dokuments hat M0-03 hier ausgelassen — das war ein Fehler und ist in CC-01 (2026-08-11) korrigiert.

Der Rest von M0 (Ruleset-Trennung, Tastenbelegung, Regelkorrekturen) lässt sich danach nachziehen — er ist wichtig, aber nicht blockierend für das erste Netzwerkspiel.

**Wichtige Einschränkung:** M0-09 (Ruleset-Trennung) **muss** vor der ersten Verteilung an Gäste fertig sein, sonst kann jeder Client die Physik seines Spiels über den Live-Tweaker verändern.

## 4. Steuerungsregeln

- **Nach jedem Meilenstein ein Build**, auch wenn niemand ihn braucht. Ein nicht gebauter Zwischenstand ist ein nicht existierender Zwischenstand.
- **Kein Feature aus M6 wird vor Abschluss von M5 begonnen.** Charter §4 ist bindend; die Mutatoren sind der wahrscheinlichste Scope-Creep-Kanal.
- **Jede Architekturentscheidung wird als ADR protokolliert**, bevor sie implementiert wird.
- **Bei jeder Spec-Abweichung im Code:** erst die Spec ändern, dann den Code. Nicht umgekehrt.
