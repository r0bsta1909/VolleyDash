# Changelog

Alle nennenswerten Änderungen an Volley Dash. Format nach
[Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionierung nach
[Semantic Versioning](https://semver.org/lang/de/).

Bis zur ersten Veröffentlichung ist das Spiel nicht öffentlich verteilt worden — alles
Bisherige steht deshalb unter `Unreleased`.

## [Unreleased] — vorgesehen als 0.1.0

Erste verteilbare Fassung. Lokales Spiel gegen einen zweiten Spieler an derselben Tastatur
oder gegen den Bot. **Kein Netzwerk** — LAN kommt mit M2.

### Hinzugefügt — M1 (Build und Repo)

- `tools/build.sh` erzeugt aus dem Repo die `.love` und daraus die Pakete für Windows und
  macOS. Ausschlusslisten halten `docs/`, `tests/` und `tools/` aus der Auslieferung.
- `src/build_info.lua` wird beim Build erzeugt und trägt Version und Build-Hash. Beide
  stehen im Menü — die Bug-Vorlage fragt genau diese Zeichenkette ab.
- macOS-Paket mit verpflichtender Ad-hoc-Signatur (ADR-012); `codesign --verify` bricht den
  Build ab, wenn die Signatur nicht hält.
- `LIESMICH.txt` für beide Plattformen mit dem SmartScreen- und dem Gatekeeper-Weg.
- Öffentliches `README.md`, `CONTRIBUTING.md`, Issue-Vorlagen, GitHub-Actions-Workflow.
- `LICENSE-THIRD-PARTY.md`, `assets/CREDITS.md`, `docs/references.md`.

### Geändert — M1

- Bilder und Klänge liegen jetzt unter `assets/` statt im Wurzelverzeichnis.
- Der Hintergrund ist von 2752 × 1536 auf 1600 × 1200 verkleinert und heißt jetzt
  `assets/bg.png` statt `bg.jpg` — die Datei war nie ein JPEG. Spart rund 4,5 MB im Paket
  und zwei Drittel des Texturspeichers auf der Zielhardware.

### Hinzugefügt — M0 (Fundament)

- Fixer Simulationsschritt 1/60 s mit Akkumulator, davon entkoppeltes und interpoliertes
  Rendering (B-02).
- Logisches Spielfeld fix 800 × 600, Fensteranpassung als Letterbox/Pillarbox (B-01,
  ADR-004).
- `InputFrame` als einzige Eingabequelle der Simulation; Tastatur, Gamepad und Bot liefern
  denselben Datentyp (B-03, ADR-014).
- `src/sim/` ist nachweislich frei von `love` und von Zufall — belegt durch
  `--test-no-love`.
- `Ruleset` und `Prefs` getrennt, Presets `classic` und `prototype`, kanonischer
  Ruleset-Hash (B-04, ADR-005).
- Zwei-Punkte-Vorsprung, Deuce-Deckel und Rallye-Timeout (B-05).
- Konfigurierbare und persistente Tastenbelegung, Gamepad-Slots.
- Sound-Pool mit vier Stimmen je Klang, Hintergrundmusik mit Shuffle-Playlist.
- Headless-Testrunner mit 83 Fällen und elf aufgezeichneten Referenz-Rallyes.

### Geändert — M0

Zwei gewollte Verhaltensänderungen, alles andere ist bitgleich nachgewiesen:

- Der Bot bekommt im Absprungtick nicht mehr die volle Bodengeschwindigkeit; `airControl`
  gilt jetzt für beide Seiten gleich (M0-07).
- Ein Aufwärts-Dash mit gehaltener Richtungstaste wird zum Seitwärts-Dash, weil die Richtung
  aus den Richtungsbits kommt (M0-06, ADR-014).

### Abnahme

- **D1 (Spielgefühl) am 2026-08-12 als Product-Owner-Abnahme erteilt.** Roberto hat alte und
  neue Fassung selbst gespielt. Das vorgesehene Verfahren aus `07_TEST_PLAN` §6 — drei
  Personen im Blindwechsel — wurde **nicht** durchlaufen; die Abnahme beruht auf einer
  Person. Das ist eine Entscheidung, keine Lücke, und steht deshalb hier.
