# Handoff CC-02 — Build-Pipeline und Open-Source-Repo

**Meilenstein:** M1 · **Aufgaben:** M1-01 … M1-12 aus `08_ROADMAP_BACKLOG.md`
**Geschätzter Aufwand:** 17–21 h · **Abhängig von:** M0 (inhaltlich fertig)
**Erstellt:** 2026-08-12 · **Status:** freigegeben zur Ausführung

---

## 0. Lies zuerst

`CLAUDE.md` im Wurzelverzeichnis, dann diese Datei, dann
`docs/06_BUILD_RELEASE_PIPELINE.md` vollständig und `docs/12_OPENSOURCE_REPO_SETUP.md`.
Für den Stand des Vorgängers: `docs/handoffs/M0_REPORT.md`.

Erst danach fasst du eine Datei an.

---

## 1. Wo das Projekt steht

M0 ist inhaltlich fertig: alle neun Blocker und zehn Befunde des Audits erledigt,
83 Tests, elf Referenz-Rallyes, `main.lua` auf 63 Zeilen. Die Simulation liegt love-frei
unter `src/sim/`, die Eingabe hinter `InputFrame` (ADR-014), das Ruleset getrennt von den
Prefs (ADR-005).

**Was du nicht anfasst:** Die Zahlen in `src/sim/ruleset.lua` (Preset `prototype`) und die
Kollisionsauflösung. `02_CODE_AUDIT` §4 gilt unverändert. Nach jeder Änderung:

```powershell
D:\love2d\LOVE\lovec.exe . --test
```

muss „83 bestanden, 0 gescheitert" melden, bevor du committest.

**Offen aus M0, bevor M1-10 das öffentliche README schreibt:** Die Abnahme D1 ist formal
nicht durch (`M0_REPORT.md` §4). Kläre mit r0btoshi, ob D1 nachgeholt oder als PO-Abnahme
protokolliert wird — ein öffentliches Repo mit „M0 abgenommen" im README wäre sonst
unbelegt.

---

## 2. Auftrag

Reihenfolge aus `08_ROADMAP` §2, mit den Punkten, die aus M0 dazugekommen sind.

### AP-1 — `.love` bauen (M1-01)

`tools/build.sh` erzeugt die `.love` aus dem Repo. **Ausschlussliste ist der Kern:**
`docs/`, `tests/`, `.git/`, `tools/` und das temporäre `reference_mode`-Werkzeug gehören
nicht in die Auslieferung. `music/` gehört nur hinein, wenn Dateien da sind und ihre
Herkunft geklärt ist.

> **Falle aus `06_BUILD` §1:** Nie den Ordner testen, immer die gebaute `.love`. Der
> Prototyp lädt `bg.jpg` über `love.filesystem` relativ zum Spielverzeichnis — im Ordner
> funktioniert das auch dann, wenn es in der `.love` bricht.

**Abnahme:** `love VolleyDash.love` startet, Menü erscheint, ein Match läuft.

### AP-2 — Windows-Fusion (M1-02, M1-04, M1-05, M1-06)

`love.exe + .love → VolleyDash.exe`, DLLs aus demselben Download daneben, `license.txt`
zwingend dabei. `build_info.lua` mit Version und Build-Hash injizieren, `LIESMICH.txt` mit
dem SmartScreen-Weg, Icon in die EXE.

**Abnahme:** ZIP auf einen frisch aufgesetzten Windows-Rechner, entpacken, Doppelklick,
Spiel läuft ohne Runtime-Installation (Charter S1).

### AP-3 — macOS (M1-03, M1-3b)

**Hier ist ein Blocker:** Es gibt lokal keinen Mac (`CLAUDE.md` §8). `codesign`, `hdiutil`
und der `.app`-Build laufen ausschließlich auf einem macOS-Runner in GitHub Actions.
Schreibe die Schritte, aber kennzeichne sie als auf dem Runner ungetestet, bis M1-11 steht.

Die Ad-hoc-Signatur ist **verpflichtend** (ADR-012): Der Plist-Patch zerstört die Signatur
der `love.app`, und ohne erneutes Signieren startet die App auf Apple Silicon gar nicht.
`codesign --verify` ist Abbruchbedingung des Builds, kein optionaler Schritt.

### AP-4 — Assets und Recht (M1-08, M1-09)

`LICENSE-THIRD-PARTY.md`, `docs/references.md`, `assets/CREDITS.md`. Für die elf
vorhandenen Dateien ist die Herkunft geklärt (r0btoshi, siehe `ASSET_INVENTORY.md`) — die
CREDITS-Datei muss das nur noch festhalten.

**Technikpunkt aus M0-02:** `bg.jpg` ist ein PNG mit falscher Endung, 2752 × 1536, 4,9 MB,
rund 16 MB VRAM. Verkleinern auf Zielauflösung und korrekt benennen. Das ist der größte
Hebel für die Downloadgröße und damit für das Charter-Kriterium „Time-to-First-Match
≤ 90 s ab ZIP".

> **Anhalten und fragen:** Wenn r0btoshi Musikdateien beisteuert, vor dem Commit Herkunft
> klären (`music/README.md`, `10_LEGAL` §4). Eine gelöschte Datei bleibt in der Historie.

### AP-5 — GitHub (M1-10, M1-11, M1-12)

Öffentliches README (nicht das interne `docs/README.md`), Issue-Vorlagen,
`CONTRIBUTING.md`. GitHub Actions: Tests bei jedem Push, Vollbuild bei Tag.

**Der CI-Lauf ist der Ort, an dem die letzte offene Behauptung aus M0-13 endlich belegt
wird:** `lua tests/run_headless.lua` auf einem Runner mit echtem Lua 5.1 oder LuaJIT.
Hier gibt es keinen Interpreter, deshalb ist der Pfad geschrieben, aber nie ausgeführt
worden. Falls er dort scheitert, ist das ein Fund, kein Beinbruch — die Testdateien sind
love-frei, das ist unter `--test-no-love` belegt.

**Vor dem ersten Push:** `12_OPENSOURCE_REPO_SETUP` §5 und ADR-011 lesen. Das Repo ist
offen, **nicht betreut** — diese Formulierung gehört ins README, sonst entsteht eine
Erwartung, die nebenberuflich nicht einlösbar ist.

---

## 3. Was du in dieser Session nicht tust

- Kein Netzwerkcode. Das ist M2, und `04_NETCODE_SPEC` setzt eine abgenommene M0 voraus.
- Keine Änderung an `src/sim/`. Wenn du dort etwas anfassen musst, ist etwas anderes falsch.
- Keine neuen Abhängigkeiten ohne ADR.
- `tools/reference_mode.lua` und die `tests/replays/` bleiben, wo sie sind. Sie gehören
  nicht in die Auslieferung, aber sehr wohl ins Repo.

---

## 4. Rückmeldung

Am Ende `docs/handoffs/CC-02_REPORT.md` mit denselben Abschnitten wie CC-01:
Erledigt · Nicht erledigt und warum · Befunde · Spec-Änderungen · Entscheidungen für
r0btoshi · Nächster Schritt.
