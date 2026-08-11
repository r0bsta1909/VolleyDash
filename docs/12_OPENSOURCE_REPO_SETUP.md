# 12 — Open-Source-Repo-Setup

**Version:** 1.0 · **Stand:** 2026-08-11 · **Bezug:** ADR-011 · **Meilenstein:** M1

---

## 1. Grundhaltung

Das Repo ist **offen, nicht betreut**. Der Code steht unter zlib zur freien Nutzung, aber es gibt keine Zusage auf Issue-Bearbeitung, keine öffentliche Roadmap-Verpflichtung und keinen Support. Diese Erwartungshaltung muss im öffentlichen README stehen, und zwar an prominenter Stelle — sonst entsteht eine Verpflichtung, die neben einer Vollzeitstelle und zwei kleinen Kindern nicht einlösbar ist und das Projekt in ein schlechtes Gewissen verwandelt.

Formulierungsvorschlag fürs README:

> **Zum Stand des Projekts:** Volley Dash entsteht nebenberuflich für konkrete LAN-Abende. Der Code ist frei nutzbar und Pull Requests sind willkommen, aber es gibt keine Zusage auf zeitnahe Bearbeitung von Issues oder PRs. Wenn du das Spiel für deine Zwecke brauchst: forke es.

## 2. Repository-Struktur

```
volley-dash/
├── README.md                 # ÖFFENTLICH — nicht der interne Doc-Index
├── LICENSE                   # zlib, dein Copyright
├── LICENSE-THIRD-PARTY.md    # LÖVE, ENet, LuaSocket, LuaJIT, json.lua
├── CHANGELOG.md              # Keep-a-Changelog-Format
├── CONTRIBUTING.md           # kurz: Scope, Codestil, Tests
├── CLAUDE.md                 # Anweisungen für Claude Code
├── .gitignore
├── .github/
│   ├── workflows/build.yml   # CI, siehe §5
│   └── ISSUE_TEMPLATE/
│       ├── bug.md            # mit Pflichtfeldern OS, Version, F3-Overlay-Werte
│       └── feature.md        # mit Hinweis auf docs/00_PROJECT_CHARTER.md §4
├── conf.lua
├── main.lua
├── src/                      # siehe 03_TECH_ARCHITECTURE §2
├── assets/
│   └── CREDITS.md            # Pflicht: Herkunft und Lizenz je Asset
├── tests/
├── tools/
├── dist/                     # LIESMICH-Vorlagen, Icons
└── docs/                     # dieses Doc-Set (00–12) + references.md
```

**Die Docs kommen mit ins öffentliche Repo.** Sie sind auf Deutsch, was die Reichweite einschränkt, aber sie sind der eigentliche Mehrwert für Nachnutzer — insbesondere `04_NETCODE_SPEC` und `05_TOURNAMENT_SPEC`. Ein englischsprachiges Kurz-Abstract der Netcode-Architektur im README fängt internationale Leser ab; eine vollständige Übersetzung lohnt nicht.

## 3. Lizenzdateien

### `LICENSE` — zlib

Standardtext der zlib-Lizenz mit `Copyright (c) 2026 Roberto Versino`. Begründung der Wahl in ADR-011.

### `LICENSE-THIRD-PARTY.md`

Tabelle aller mitgelieferten Komponenten mit Lizenz und Fundstelle:

| Komponente | Lizenz | Anmerkung |
|------------|--------|-----------|
| LÖVE 11.5 | zlib | Wird nicht im Repo mitgeliefert, nur in den Release-Artefakten. `license.txt` liegt jedem Build bei |
| ENet, LuaSocket, LuaJIT, SDL2, OpenAL, mpg123 | MIT / zlib / LGPL | Teil der LÖVE-Distribution, abgedeckt durch deren `license.txt` |
| `src/lib/json.lua` | MIT | Header-Kommentar unverändert lassen |
| Assets | siehe `assets/CREDITS.md` | **Kein Asset ohne Nachweis** |

### `docs/references.md` — die GPL-Abgrenzung

Dokumentiert, welche Erkenntnis über Original-Spielverhalten woher stammt. Zweck: belegen, dass Verhalten **nachvollzogen** und kein GPLv2-Code aus Blobby Volley 2 übernommen wurde (`10_LEGAL` §2). Bei einem öffentlichen Repo, das sich erkennbar an Blobby Volley orientiert, ist das die naheliegendste Rückfrage — sie sollte beantwortet sein, bevor sie gestellt wird.

## 4. Was vor dem ersten öffentlichen Push erledigt sein muss

Die Reihenfolge ist wichtig: Ein einmal gepushtes Asset mit unklarer Lizenz bleibt in der Git-Historie, auch wenn du es später löschst.

- [ ] **`assets/CREDITS.md` vollständig.** Jede `.png`, `.jpg`, `.wav`, `.ogg` mit Herkunft und Lizenz. Fehlt ein Nachweis → Asset **vor** dem ersten Push entfernen oder ersetzen
- [ ] **Prozeduraler Fallback als Standard** (`10_LEGAL` §4): Der Prototyp zeichnet Blob und Ball bereits ohne Bilddateien. Das ist lizenzfrei, charakteristisch und beseitigt die Restunsicherheit vollständig
- [ ] `LICENSE` und `LICENSE-THIRD-PARTY.md` liegen vor
- [ ] `docs/references.md` angelegt
- [ ] Keine Klarnamen Dritter, keine IP-Adressen, keine privaten Netzwerknamen in Code, Docs oder Testdaten
- [ ] `.gitignore` deckt `build/`, `tools/prebuilt/`, `*.love`, `.DS_Store` ab
- [ ] Öffentliches README geschrieben (§6)

**Zu `tools/prebuilt/`:** Die entpackten LÖVE-Distributionen (~40 MB) gehören **nicht** ins Repo. Das CI-Skript lädt sie beim Build von der offiziellen Quelle. Lokal liegen sie ungetrackt.

## 5. GitHub Actions

Für ein Open-Source-Projekt reicht „läuft auf meinem Mac" nicht. Der Build muss reproduzierbar sein.

**Workflow `build.yml`:**

| Auslöser | Aktion |
|----------|--------|
| Push auf `main`, Pull Request | Headless-Tests (`tests/run_headless.lua`) unter LuaJIT. Schnell, kein LÖVE nötig |
| Tag `v*` | Vollbuild Windows + macOS, Artefakte an GitHub Release anhängen |

**Job Windows:** Läuft auf `ubuntu-latest`. Offizielle LÖVE-Win64-ZIP laden, `cat love.exe game.love > VolleyDash.exe`, DLLs und `license.txt` beipacken, zippen. Kein Windows-Runner nötig — <cite index="38-1">der Windows-Build lässt sich von Linux oder macOS aus mit `cat love.exe SuperGame.love > SuperGame.exe` erzeugen.</cite>

**Job macOS:** Läuft auf `macos-latest` (Pflicht, weil `codesign` gebraucht wird). LÖVE-macOS-ZIP laden, `.app` umbenennen, `.love` einlegen, Plist patchen, **ad-hoc signieren** (ADR-012), mit `zip -y` packen.

**Wichtig für die CI-Variante der Ad-hoc-Signatur:** Sie funktioniert ohne Secrets und ohne Apple-Konto. Der `codesign --verify`-Schritt gehört als Build-Abbruchbedingung in den Workflow — ein Release mit kaputter Signatur startet auf keinem Apple-Silicon-Mac, und das würde erst der erste Nutzer merken.

**Alternative:** <cite index="30-1">LÖVE Actions baut und veröffentlicht Pakete für die meisten Plattformen per GitHub Actions (Android, iOS, Linux, macOS, Windows; kein HTML5/WASM).</cite> Als Abkürzung brauchbar. Empfehlung bleibt der eigene Workflow (ADR-009), weil die Build-Hash-Injektion und der Signatur-Verify projektspezifisch sind — die Schritte aus LÖVE Actions lassen sich aber als Vorlage lesen.

## 6. Öffentliches README — Aufbau

Das ist ein anderes Dokument als der interne Index. Reihenfolge nach dem, was ein Fremder in dieser Reihenfolge wissen will:

1. **Ein Satz, was es ist**, plus GIF vom Gameplay. Ohne Bewegtbild klickt niemand weiter
2. **Download** — Link auf Releases, direkt darunter der macOS-Rechtsklick-Hinweis (ADR-012) und der Windows-Hinweis „ZIP erst entpacken"
3. **Steuerung** — vier Zeilen
4. **LAN spielen** — drei Sätze plus der Firewall-Hinweis aus `11_OPS` §3
5. **Turniermodus** — was er kann, ein Screenshot vom Bracket
6. **Warum das existiert** — kurzer Absatz: Neuimplementierung, kein Fork, kein Code aus Blobby Volley 2
7. **Technisches Kurz-Abstract auf Englisch** — LÖVE 11.5, host-authoritative snapshots, UDP broadcast discovery, integrated tournament system. Verweis auf `docs/`
8. **Stand des Projekts** — der Erwartungsabsatz aus §1
9. **Lizenz und Credits** — zlib, Nennung von Skoraszewsky/Mummert als Inspirationsquelle

**Was nicht ins README gehört:** Roadmap, Meilensteinplan, offene Punkte. Das steht in `docs/` und ist dort für Interessierte auffindbar. Im README erzeugt es eine Erwartung von Verbindlichkeit.

## 7. Release-Prozess

```
1. CHANGELOG.md ergänzen (Keep-a-Changelog)
2. VERSION aktualisieren
3. git tag -a v1.0.0 -m "Volley Dash 1.0.0"
4. git push --tags
5. CI baut, hängt VolleyDash-1.0.0-win64.zip und -macos.zip an den Release
6. Release-Notes: Änderungen + die zwei Startanleitungen (Win entpacken, Mac Rechtsklick)
7. Lokal gegenprüfen: beide Artefakte auf einem FREMDEN Rechner starten
```

Schritt 7 ist nicht optional. Ein CI-Build, der grün ist, hat noch nichts über Gatekeeper und SmartScreen bewiesen.

## 8. Issue-Vorlagen

Die Bug-Vorlage fragt vier Dinge ab, die sonst in jeder Rückfrage nachgeholt werden müssen:

- Betriebssystem und Architektur (bei macOS: Intel oder Apple Silicon)
- Version aus dem Titelbildschirm
- Bei Netzwerkproblemen: die Werte aus dem F3-Overlay (RTT, Paketverlust, Ruleset-Hash)
- Kabel oder WLAN

Die Feature-Vorlage beginnt mit dem Hinweis auf `docs/00_PROJECT_CHARTER.md` §4 („Scope — Out") und der Bitte, vorher zu prüfen, ob der Wunsch dort bereits mit Begründung ausgeschlossen ist. Das erspart auf beiden Seiten Arbeit.

## 9. Zusätzliche Aufgaben für M1

Diese kommen durch ADR-011 zum Meilenstein M1 hinzu:

| ID | Aufgabe | h |
|----|---------|---|
| M1-08 | `LICENSE`, `LICENSE-THIRD-PARTY.md`, `docs/references.md` | 1 |
| M1-09 | `assets/CREDITS.md` + Umstellung auf prozeduralen Fallback als Standard | 2 |
| M1-10 | Öffentliches README inkl. Gameplay-GIF | 2 |
| M1-11 | GitHub Actions Workflow (Tests + Tag-Build beide Plattformen) | 3 |
| M1-12 | Issue-Vorlagen, `CONTRIBUTING.md`, `.gitignore` | 1 |

**Neuer Aufwand M1: 8–12 h → 17–21 h.** Der Meilensteinplan in `08_ROADMAP` verschiebt sich entsprechend um etwa ein Wochenende.
