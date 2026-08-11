# VOLLEY DASH — Projekt-Dokumentation

**Stand:** 2026-08-11 · **Doc-Set-Version:** 1.0
**Ausgangslage:** LÖVE2D-Prototyp (`main.lua`, `bot.lua`), lokal 1v1 + Bot lauffähig.
**Zielbild:** Standalone-Builds für Windows & macOS, zuverlässiger LAN-Betrieb, integrierter Turniermodus.

---

## Wie dieses Doc-Set zu benutzen ist

Dieses Set ist so geschnitten, dass es **direkt als Wissensbasis eines Claude Projects bzw. Cowork-Projekts** hochgeladen werden kann. Die Reihenfolge ist Lesereihenfolge.

| # | Datei | Zweck | Wer liest es |
|---|-------|-------|--------------|
| — | `README.md` | Index, Setup-Anleitung Projekt | alle |
| — | `CLAUDE_PROJECT_INSTRUCTIONS.md` | **In das Feld „Projektanweisungen" kopieren** | Claude |
| 00 | `00_PROJECT_CHARTER.md` | Scope, Nicht-Ziele, Erfolgskriterien, Risiken | Entscheidung |
| 01 | `01_GDD_v1.0.md` | Game Design Document, Regelwerk, Modi, Mutatoren | Design |
| 02 | `02_CODE_AUDIT_PROTOTYP.md` | Ist-Analyse des Prototyps, Blocker-Liste | Umsetzung |
| 03 | `03_TECH_ARCHITECTURE.md` | Zielarchitektur, Modulschnitt, Refactoring-Plan | Umsetzung |
| 04 | `04_NETCODE_SPEC.md` | LAN-Architektur, Protokoll, Discovery, Wire-Format | Umsetzung |
| 05 | `05_TOURNAMENT_SPEC.md` | Turniermodus, Datenmodell, Zustandsautomat, Edge Cases | Umsetzung |
| 06 | `06_BUILD_RELEASE_PIPELINE.md` | Win/macOS-Builds, Signatur, CI, Versionierung | Release |
| 07 | `07_TEST_PLAN.md` | Testfälle, Desync-Detektion, LAN-Abnahme | QA |
| 08 | `08_ROADMAP_BACKLOG.md` | Meilensteine M0–M6, Backlog mit IDs | Steuerung |
| 09 | `09_DECISION_LOG_ADR.md` | Architekturentscheidungen mit Begründung | alle |
| 10 | `10_LEGAL_ASSETS_NAMING.md` | Lizenzen, GPL-Abgrenzung, Naming, Assets | Entscheidung |
| 11 | `11_OPS_RUNBOOK_LANPARTY.md` | Event-Runbook: Netzwerk, Firewall, Beamer, Reset | Betrieb |
| 12 | `12_OPENSOURCE_REPO_SETUP.md` | GitHub-Repo, Lizenzdateien, CI, Release-Prozess | Release |

---

## Setup: Claude Project vs. Cowork

**Empfehlung: beides, mit klarer Rollentrennung.**

### Claude Project „Volley Dash — Design & Specs"
- **Projektwissen:** dieses komplette Doc-Set (14 Dateien).
- **Projektanweisungen:** Inhalt von `CLAUDE_PROJECT_INSTRUCTIONS.md`.
- **Nutzung:** Regeldesign, Netcode-Sparring, Turnierformat-Fragen, Spec-Updates, ADR-Pflege.
- **Nicht dafür:** Code schreiben. Chat-Fenster sind der falsche Ort für ein wachsendes Lua-Repo.

### Claude Code (Repo-lokal)
- Repo enthält `CLAUDE.md` (= verkürzte Fassung von `CLAUDE_PROJECT_INSTRUCTIONS.md` + Modulschnitt aus `03`).
- Docs liegen unter `docs/` im Repo mit, damit Claude Code sie referenzieren kann.
- **Nutzung:** Refactoring M0, Netcode-Implementierung, Build-Skripte.

### Cowork
- Nur für die Phasen mit vielen parallelen Datei-Operationen: **M0 Refactoring** (Zerlegung der 1182-Zeilen-`main.lua`) und **M1 Build-Pipeline** (Skripte + CI-Workflow + Signatur-Doku in einem Rutsch).

**Warum getrennt:** Das GDD ändert sich langsam, der Code schnell. Wenn beides im selben Kontext liegt, driften Spec und Implementierung unbemerkt auseinander — genau der Fehler, der bei vorherigen Projekten einen kompletten Downstream-Audit erzwungen hat.

---

## Die vier Entscheidungen, die dieses Doc-Set gegenüber dem Ausgangs-GDD ändert

1. **Lockstep ist gestrichen.** Ersetzt durch host-autoritative Snapshots. Begründung: ADR-002.
2. **Das logische Spielfeld wird fixiert (800×600).** Der Prototyp skaliert die Feldbreite mit dem Fenster — das bricht sowohl Vanilla-Treue als auch jedes Netzwerkspiel. Begründung: ADR-004, Blocker B-01.
3. **„Vanilla" wird hart definiert** — inkl. Zwei-Punkte-Vorsprung, ohne Dash, ohne Smash. Der Prototyp ist derzeit **kein** Vanilla-Blobby. Siehe `01_GDD` §3 und Blocker B-05.
4. **Beamer-Auto-Regie fliegt aus dem MVP.** Scope-Begründung in `00_PROJECT_CHARTER` §4.

---

## Getroffene Grundsatzentscheidungen

| ID | Frage | **Entscheidung (2026-08-11)** | Wo dokumentiert |
|----|-------|-------------------------------|-----------------|
| Q-01 | Projektname | **Volley Dash** | ADR-010, `10_LEGAL` §3 |
| Q-02 | Apple Developer Program | **Nein.** Unsigniert + Ad-hoc-Signatur | ADR-012, `06_BUILD` §4 |
| Q-03 | Zielgröße Turnier | **Variabel, Auslegungspunkt 20 Teilnehmer** | ADR-013, `05_TOURNAMENT` §2 |
| Q-04 | Veröffentlichung | **Open Source auf GitHub, zlib-Lizenz** | ADR-011, `12_OPENSOURCE_REPO` |

### Was diese vier Entscheidungen nachgezogen haben

- **Ad-hoc-Signatur ist keine Option, sondern Pflicht.** Das Ändern der `Info.plist` in `love.app` zerstört deren vorhandene Signatur. Auf Apple Silicon startet eine ARM-Binary mit kaputter Signatur gar nicht — nicht nur Gatekeeper-Warnung, sondern Absturz. `codesign --force --deep --sign -` ist kostenlos und behebt das. Details in `06_BUILD` §4.
- **20 Teilnehmer sprengen den seriellen Turnierbetrieb.** Bei einem Match nach dem anderen dauert ein 20er-Turnier über drei Stunden. Parallele Matches (M4-09) rücken damit von „nice to have" auf den kritischen Pfad. Siehe ADR-013.
- **Open Source macht die Asset-Herkunft blockierend.** Unklar lizenzierte Grafiken/Sounds im Repo sind privat egal, öffentlich nicht. Empfehlung: prozeduraler Fallback wird Standard. `10_LEGAL` §4.
- **Neues Dokument `12_OPENSOURCE_REPO_SETUP.md`** für Repo-Struktur, Lizenzdateien, CI und Release-Prozess.

### Ein Einwand zum Namen

„Volley Dash" ist gut merkbar und kollidiert nach Recherche mit keinem bekannten Spieletitel. Aber: Der Dash ist laut ADR-006 ein **Mutator, der im Vanilla-Preset ausgeschaltet ist.** Das Spiel heißt damit nach einer Funktion, die beim ersten Start nicht aktiv ist. Drei Auswege, meine Empfehlung an dritter Stelle:

1. Dash ins Standard-Preset holen — verletzt die Vanilla-Doktrin, nicht empfohlen.
2. Umbenennen — unnötig, der Name ist gut.
3. **Zweites Preset `Volley Dash` (Dash an, Smash an) als gleichwertige Startoption neben `Classic` anbieten.** Der Name wird dadurch eingelöst, ohne dass Vanilla verwässert. Umgesetzt in `01_GDD` §5.
