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

### M2 — LAN 1v1 (25–35 h)

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

**Offen aus M2:** D2 (zwei Rechner) und die Paketverlustfälle T-N-02/T-N-03 — beides braucht
Hardware, keinen Code. Ebenso N-04 (ENet auf einem frischen Mac) und N-05 (Broadcast durch
eine Windows-Firewall im öffentlichen Profil). Einzelheiten in `docs/handoffs/CC-03_REPORT.md`.

### M3 — Netzwerk-Politur (10–15 h)

| ID | Aufgabe | h |
|----|---------|---|
| M3-01 | Client-Vorhersage des eigenen Blobs + sanfte Korrektur | 5 |
| M3-02 | Kosmetik-Ereignisse aus Snapshot-Deltas ableiten (Partikel, Sound) | 3 |
| M3-03 | Checksum-/Vorhersagefehler-Überwachung + `desync.log` | 2 |
| M3-04 | WLAN-Test bei RTT 20–40 ms, Bewertung offener Punkt N-01 | 3 |

### M4 — Turniermodus (36–48 h)

**Abnahme:** `05_TOURNAMENT` §12 + Chaos-Szenario D3.

| ID | Aufgabe | h |
|----|---------|---|
| M4-01 | `model.lua`: Datenmodell + append-only Log | 4 |
| M4-02 | `bracket.lua`: Single Elimination inkl. Freilose | 5 |
| M4-02b | Automatische Gruppenaufteilung aus beliebiger Teilnehmerzahl (Ziel 4–5/Gruppe) | 2 |
| M4-03 | `bracket.lua`: Round Robin + Tabellenkriterien E-11 | 4 |
| M4-04 | Gruppen → Elim | 3 |
| M4-05 | `scheduler.lua`: Match-Zustandsautomat, Calling, No-Show-Timer | 5 |
| M4-06 | `persistence.lua`: atomares Schreiben, Recovery-Dialog | 4 |
| M4-07 | Turnier-Lobby-UI, Setzung mit sichtbarem Seed | 4 |
| M4-08 | `bracket_view.lua`: kompakt (Spieler) + voll (Beamer) | 5 |
| M4-09 | **Verteilte Match-Hosts bei parallelen Matches — kritischer Pfad, nicht optional** (ADR-013) | 8 |
| M4-10 | Export als Markdown/CSV | 1 |
| M4-11 | Manuelle Ergebniskorrektur mit Protokollierung | 2 |

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
