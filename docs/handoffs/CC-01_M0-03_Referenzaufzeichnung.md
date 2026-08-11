# Handoff CC-01 — Repo-Bootstrap und Referenzaufzeichnung

**Meilenstein:** M0 · **Aufgaben:** M0-03 (erweitert), Vorzug aus M1-08/M1-09/M1-12
**Geschätzter Aufwand:** 5–6 h · **Blockiert:** M0-04 und alles Weitere
**Erstellt:** 2026-08-11 · **Status:** freigegeben zur Ausführung

---

## 0. Lies zuerst

`CLAUDE.md` im Repo-Wurzelverzeichnis, dann diese Datei vollständig, dann
`docs/02_CODE_AUDIT_PROTOTYP.md` und `docs/07_TEST_PLAN.md` §2.

Erst danach fasst du eine Datei an.

---

## 1. Warum diese Session zuerst kommt

Das größte Risiko des Projekts ist R-04: beim Refactoring das Spielgefühl zerstören. Die
Gegenmaßnahme aus `07_TEST_PLAN` §2 sind aufgezeichnete Referenz-Rallyes, gegen die die neue
Simulation nach dem Umbau verglichen wird.

Diese Aufzeichnung ist **nur jetzt möglich**. M0-04 fixiert die Weltgeometrie, M0-05 den
Timestep. Danach existiert das Verhalten, das abgesichert werden soll, nicht mehr.
`08_ROADMAP` §3 listet M0-03 nicht unter „Wochenende 1" — das ist ein Fehler in der Roadmap
und wird mit dieser Session korrigiert.

Zweiter Grund: Sobald `git init` läuft und der Prototyp committet wird, sind die vorhandenen
Assets in der Historie. R-05 und ADR-011 machen unklare Assetherkunft blockierend. Der erste
Commit muss also sauber sein, nicht der zwanzigste.

---

## 2. Ausgangslage

- Windows 11, Git Bash als Shell. **Kein Mac verfügbar.**
- LÖVE 11.5 installiert.
- Prototyp liegt als lose Dateien im Wurzelverzeichnis: `main.lua` (1182 Zeilen),
  `bot.lua` (~130 Zeilen), dazu zehn Asset-Dateien **ohne Unterordner**.
- **Kein Git, kein GitHub-Repo.**
- `CLAUDE.md`, `.claude/settings.json`, die 13 Spezifikationsdokumente unter `docs/` und
  dieses Handoff sind bereits abgelegt.

---

## 2b. Vorbefunde

Diese Punkte sind bereits im Code geprüft. Du musst sie nicht suchen, aber im Bericht
**bestätigen oder widerlegen** — falls einer davon falsch ist, ändert das die Planung.

**`math.random` — elf Fundstellen, davon genau eine simulationsrelevant:**

| Ort | Zweck | Simulationsrelevant |
|---|---|---|
| `main.lua:461` | `serveDelay = 1.0 + math.random() * 0.5` | **ja** — Patch nach AP-4 |
| `main.lua:295`, `bot.lua:44` | Bot-Jitter auf den Zielpunkt | nein, siehe unten |
| `main.lua:74–77` | Seed + zufällige Spielernamen | nein |
| `main.lua:96–102` | Partikelstreuung | nein |
| `main.lua:943` | Kamera-Shake im Draw | nein |

Der Bot-Jitter ist der interessante Fall: Er verändert das Bot-Verhalten, also den
`InputFrame`, den der Bot erzeugt. Weil die Aufzeichnung genau diesen `InputFrame` festhält
und die Wiedergabe ihn einspielt statt den Bot neu zu simulieren, ist die Zufälligkeit
eingefroren und unschädlich. **Voraussetzung ist, dass in AP-5 tatsächlich der Bot-Output
aufgezeichnet wird und nicht der Bot-Zustand.**

Nebenbei bestätigt: `main.lua:295` und `bot.lua:44` sind die zwei Kopien aus **B-07**.
Beide bleiben in dieser Session unangetastet.

**Der prozedurale Fallback existiert bereits.** `loadImage` und `loadSound`
(`main.lua:390–410`) geben `nil` zurück, wenn eine Datei fehlt, und jede Zeichen- und
Abspielstelle prüft darauf (`947`, `1013`, `1148`, `playSound` in `375`). `main.lua:421`
setzt sogar eine Ersatzfarbe für den Ball. Konsequenz: Die Assets aus dem Repo herauszuhalten
macht das Spiel **nicht unspielbar**. Das entschärft R-05 erheblich und ist die
Hauptbegründung dafür, dass sie in AP-1 ignoriert werden statt zu blockieren.

**`bg.jpg` ist 4,9 MB groß.** Das ist der mit Abstand größte Verdachtsfall im Inventar —
ein Foto oder Stock-Bild dieser Größe stammt selten aus eigener Produktion. Behandle es in
AP-2 vorrangig. Nebenbei: 4,9 MB in einem Projekt mit Startzeitziel < 3 s auf
2015er-Hardware ist auch technisch fragwürdig.

**Die Fensterbehandlung ist schlimmer als im Audit beschrieben.** `main.lua:386–388` setzt
800×600 resizable und ruft direkt danach `love.window.maximize()` auf. In Kombination mit
B-01 heißt das: Die Feldbreite hängt an der Bildschirmauflösung des jeweiligen Rechners.
Für die Aufzeichnung ist das Falle 6 in Abschnitt 5 — nimm sie ernst.

---

## 3. Auftrag

Sechs Arbeitspakete, strikt in dieser Reihenfolge. AP-2 und AP-3 enthalten je einen Punkt,
an dem du **anhalten und fragen** musst.

### AP-1 — Repo-Bootstrap

1. `git init`, Default-Branch `main`.
2. `.gitattributes`:
   ```
   * text=auto eol=lf
   *.png binary
   *.ogg binary
   *.wav binary
   *.ttf binary
   ```
3. `.gitignore` für LÖVE + Windows: `build/`, `dist/`, `*.love`, `*.exe`, `*.zip`,
   `Thumbs.db`, `desktop.ini`, `.DS_Store`, `.vscode/`, `tests/replays/tmp/`,
   `desync.log`, `.claude/settings.local.json`.
   Zusätzlich die Assets. Sie liegen im **Wurzelverzeichnis**, nicht in einem `assets/`-Ordner,
   deshalb wurzelgebundene Muster verwenden, damit ein späterer `assets/`-Ordner nicht
   miterfasst wird:
   ```
   # TEMPORÄR bis M1-09: Assetherkunft ungeklärt (R-05, ADR-011).
   # Der Prototyp hat bereits vollständige nil-Guards (main.lua 391-401, 947, 1013, 1148,
   # playSound 375). Ohne diese Dateien startet das Spiel und ist spielbar --
   # der prozedurale Fallback aus 10_LEGAL §4 existiert de facto schon.
   /*.png
   /*.jpg
   /*.ogg
   /*.wav
   ```
4. `LICENSE` mit zlib-Lizenztext, Copyright „Roberto".
5. **Halt. Noch kein Commit.** Der erste Commit erfolgt in AP-1b, nachdem die
   Namensbereinigung durch ist. Führe bis dahin kein `git add` aus.

**Abnahme:** `git status` zeigt die Assets als ignoriert, alles andere als untracked.

### AP-1b — Namensbereinigung vor dem ersten Commit

Der Prototyp heißt an neun Stellen noch „Blobby LAN". ADR-010 hat den Namen **Volley Dash**
entschieden. Diese Bereinigung muss **vor** dem ersten Commit passieren, sonst steht „Blobby"
dauerhaft in der Historie eines öffentlichen Repositorys, dessen erklärter Zweck die
Abgrenzung vom Original ist (ADR-011, `10_LEGAL`).

Sie ist zugleich risikofrei: keine der Stellen berührt die Physik.

| Zeile | Ist | Soll |
|---|---|---|
| `main.lua:2` | Kopfkommentar „BLOBBY LAN – TWEAKED EFFECTS…" | `-- VOLLEY DASH — prototype baseline` |
| `main.lua:43` | `love.filesystem.setIdentity("BlobbyLAN")` | `love.filesystem.setIdentity("volleydash")` |
| `main.lua:50` | `love.filesystem.write("blobby_config.sav", …)` | `"volleydash_prefs.sav"` |
| `main.lua:54–55` | `getInfo`/`lines` auf `blobby_config.sav` | dito |
| `main.lua:70` | Namenspool enthält `"Blobby"` | Eintrag ersetzen, z. B. `"Blobber"` |
| `main.lua:145` | Menütitel `"BLOBBY LAN"` | `"VOLLEY DASH"` |
| `main.lua:386` | `love.window.setTitle("Blobby LAN – …")` | `love.window.setTitle("Volley Dash")` |

**Nebenwirkung, die du erwähnen musst:** Durch die neue Identity und den neuen Dateinamen
findet der Prototyp die bisherige gespeicherte Konfiguration nicht mehr und startet mit
`defaults`. Das ist für die Aufzeichnung erwünscht — die Referenz soll auf Defaults laufen,
nicht auf Robertos privaten Tweaks. Weise vor dem ersten Start darauf hin.

Danach:

1. Erster Commit: `chore: initial commit of prototype and specification set`.
   Enthält `main.lua`, `bot.lua`, `docs/`, `CLAUDE.md`, `.claude/settings.json`, `LICENSE`,
   die Git-Konfigdateien. **Enthält keine Assets.**
2. Zweiter Commit: `chore: rename prototype identifiers to Volley Dash (ADR-010)`.
   Getrennt, damit im Diff sichtbar bleibt, was am Prototyp geändert wurde.
3. Tag `prototype-baseline` auf den **zweiten** Commit. Das ist der Referenzpunkt, gegen den
   D1 später blind getestet wird.
4. **Kein `git remote add`, kein Push.** GitHub kommt in M1.

**Abnahme:** `git log --stat` zeigt zwei Commits ohne Assetdateien. `grep -ri blobby
main.lua bot.lua` liefert keinen Treffer. `git tag` zeigt `prototype-baseline`.

### AP-2 — Asset-Inventar

Es sind zehn Dateien, alle im Wurzelverzeichnis: `bg.jpg`, `blob.png`, `ball.png` sowie
`jump.wav`, `dash.wav`, `hit_blob.wav`, `hit_sand.wav`, `hit_net.wav`, `hit_wall.wav`,
`whistle.wav`, `whistle_end.wav`.

Erzeuge `docs/ASSET_INVENTORY.md`: eine Tabelle über jede dieser Dateien mit Pfad, Typ,
Größe, SHA-256, Verwendungsstelle im Code (Zeilennummer) und einer Spalte „Herkunft"
sowie „Entscheidung".

**Die Spalte Herkunft füllst du nicht.** Du weißt nicht, woher diese Dateien stammen, und
eine geratene Lizenzangabe ist schlimmer als eine leere. Trage `UNBEKANNT — von Roberto zu
klären` ein.

Ergänze eine Liste: welche Assets sind für den Spielbetrieb **funktional notwendig**, welche
sind rein dekorativ. Das ist die Grundlage für die Entscheidung über den prozeduralen
Fallback in M1-09.

> **Anhalten und fragen:** Wenn Assets gefunden werden, die erkennbar aus Blobby Volley oder
> Blobby Volley 2 stammen (GPLv2), meldest du das sofort und arbeitest nicht weiter am
> Inventar, bevor Roberto entschieden hat. Das ist der einzige Fund, der die
> Projektlizenzierung berührt.

**Abnahme:** Jede Datei in `assets/` steht in der Tabelle. Keine erfundene Herkunftsangabe.

### AP-3 — `InputFrame`-Format festschreiben

Vor der Aufzeichnung, nicht danach. Grund: Die Wiedergabe fährt die Aufzeichnung später durch
`sim.step()`, und `sim.step()` kennt laut B-03 ausschließlich `InputFrame`. Wenn die
Aufzeichnung Rohtasten enthält, testet der Regressionstest die Physik gegen eine ungetestete
Übersetzungsschicht Tastatur→InputFrame statt gegen die Physik.

Schreibe `docs/13_INPUTFRAME_FORMAT.md` mit:

- Kanonische Bitmaske, 8 Bit, ein Byte pro Spieler pro Tick:

  | Bit | Wert | Bedeutung |
  |---|---|---|
  | 0 | 1 | left |
  | 1 | 2 | right |
  | 2 | 4 | jump |
  | 3 | 8 | smash |
  | 4 | 16 | dash |
  | 5–7 | — | reserviert, muss 0 sein |

- Festlegung: **Der Dash-Bit ist ein abgeleitetes Signal, kein Tastendruck.** Die
  Doppeltipp-Erkennung sitzt in der Eingabequelle, nicht in der Simulation. Konsequenz für den
  Test: Der Regressionstest der Ebene A prüft die Physik, nicht die Doppeltipp-Erkennung.
  Die braucht einen eigenen Unit-Test in M0-06. Schreibe das ausdrücklich hinein.
- Die vier zulässigen Quellen (`local_keyboard`, `local_gamepad`, `bot`, `network`) und die
  Regel, dass pro Tick genau eine Quelle pro Spieler aktiv ist.
- Verhalten bei gleichzeitig `left` und `right`: **beide gesetzt ergibt Stillstand**
  (`vx = 0`). Prüfe im Prototyp nach, wie es dort tatsächlich ist, und dokumentiere das
  gemessene Verhalten, nicht das gewünschte.

> **Anhalten und fragen:** Falls der Prototyp bei gleichzeitig `a` und `d` ein anderes
> Verhalten zeigt als „Stillstand" (etwa „letzte Taste gewinnt"), ist das Spielinhalt und
> muss erhalten bleiben. Melde den Befund und warte auf die Entscheidung, bevor du das
> Format festschreibst.

Ergänze `docs/09_DECISION_LOG_ADR.md` um **ADR-014 — Kanonisches InputFrame-Format** nach der
Vorlage am Ende der Datei. Kennzeichne die Ergänzung im Commit als Spec-Änderung.

**Abnahme:** Dokument existiert, ADR-014 steht im Decision Log, `08_ROADMAP` M0-06 verweist
darauf.

### AP-4 — Temporärer Determinismus-Schalter im Prototyp

Der Testplan verlangt jede Rallye in zwei Ausführungen: einmal mit dem variablen Timestep des
Prototyps, einmal mit konstant 1/60 s. Der Prototyp braucht dafür einen Schalter.

Implementiere in `main.lua`, deutlich als temporär markiert:

```lua
-- TEMPORARY RECORDING SHIM (M0-03) -- remove after reference replays are captured.
-- This is NOT the B-02 fixed-timestep implementation. Do not build on it.
```

- Schalter über Kommandozeilenargument `--fixed-dt`, gelesen aus dem globalen `arg`.
- Im Modus `fixed60`: Akkumulator, der die bestehende Update-Logik mit exakt `1/60`
  aufruft und den Rest bis zum nächsten Frame stehen lässt. Echtzeitbezug bleibt damit
  erhalten. **Kein Umbau der Update-Funktion selbst.**
- Im Normalmodus verhält sich das Spiel unverändert.

Zusätzlich zwei Zufallsquellen stilllegen, weil sie die Aufzeichnung unreproduzierbar machen:

- `gameState.serveDelay = 1.0 + math.random() * 0.5` → während der Aufzeichnung fix `1.0`.
  Das ist ohnehin der Zielwert aus B-06 und GDD P4. Vermerke im Aufzeichnungs-Header, dass
  dieser Patch aktiv war.
- `math.randomseed(os.time())` auf Modulebene → während der Aufzeichnung fester Seed `1`.
  Betrifft nur Kosmetik, aber der Header soll ehrlich sein.

Sonstige Zufallsquellen suchst du systematisch: `grep -rn "math.random" .`. Jede Fundstelle
kommt in den Rückmeldebericht mit der Bewertung „simulationsrelevant ja/nein".

**Abnahme:** `love . --fixed-dt` startet im fixen Modus, sichtbar an einer Anzeige oben links.
Ohne Argument verhält sich das Spiel exakt wie vorher.

### AP-5 — `tools/record_replay.lua`

Ein Aufzeichnungswerkzeug, das Roberto bedienen kann, während er spielt. Es wird per
`require` aus `main.lua` eingebunden und ist im Release-Build abschaltbar.

**Bedienung im Spiel:**

| Taste | Wirkung |
|---|---|
| `F9` | Aufzeichnung starten / stoppen |
| `F10` | nächste Rallye-ID aus der Liste wählen |
| `F11` | Aufzeichnung verwerfen und neu beginnen |

Overlay oben rechts zeigt dauerhaft: aktuelle Rallye-ID, Modus (`variable` / `fixed60`),
Tickzahl, roter `REC`-Punkt, und ob für diese ID in diesem Modus bereits eine Datei existiert.

**Was pro Tick erfasst wird:**

- Tickindex und `dt`
- `InputFrame` beider Spieler als Zahl (Format aus AP-3)
- Ball: `x`, `y`, `vx`, `vy`
- Blob P1 und P2: je `x`, `y`, `vx`, `vy`
- Berührungszähler beider Seiten, Punktestand, aktueller Aufschläger, Spielphase

**Dateiformat** — JSON nach `tests/replays/<mode>/<rally_id>.json`:

```json
{
  "format_version": 1,
  "rally_id": "R-04",
  "description": "Ball auf Netzoberkante",
  "mode": "fixed60",
  "recorded_at": "2026-08-11T20:14:03Z",
  "prototype_commit": "a1b2c3d",
  "love_version": "11.5",
  "platform": "windows-x64",
  "patches_active": ["serveDelay=1.0", "randomseed=1"],
  "p2_source": "bot:hard",
  "ruleset_snapshot": { "gravity": "...", "ballRadius": "...", "netHeight": "..." },
  "tick_count": 412,
  "frames": [
    { "t": 0, "dt": "0.01666666666666667", "in": [5, 0],
      "ball": ["400.0", "200.0", "0.0", "0.0"],
      "p1": ["200.0", "500.0", "0.0", "0.0"],
      "p2": ["600.0", "500.0", "0.0", "0.0"],
      "touch": [0, 0], "score": [0, 0], "server": 1, "phase": "serve" }
  ]
}
```

**Zwei Formatregeln, die nicht verhandelbar sind:**

1. **Alle Fließkommazahlen werden als String mit `string.format("%.17g", v)` geschrieben.**
   Eine Toleranz von 0,5 px ist bedeutungslos, wenn die Referenz beim Serialisieren
   Nachkommastellen verliert. Der Vergleichs-Test parst sie mit `tonumber` zurück.
2. **`ruleset_snapshot` enthält die vollständige `defaults`-Tabelle** zum Zeitpunkt der
   Aufnahme, ebenfalls als `%.17g`-Strings. Ohne sie weiß die spätere Wiedergabe nicht,
   mit welchem Ruleset sie rechnen muss.

Kein externes JSON-Modul. Schreibe einen minimalen Serializer (~40 Zeilen), der genau dieses
Format erzeugt. Er muss nur schreiben können, nicht lesen — das Lesen macht später der
Testrunner in reinem Lua.

Zusätzlich `tests/replays/manifest.json`: Liste aller 12 Rallye-IDs mit Beschreibung und
Status pro Modus (`missing` / `recorded`), damit auf einen Blick sichtbar ist, was fehlt.
Das Werkzeug aktualisiert die Datei nach jeder Aufzeichnung.

**Abnahme:** Eine Probeaufzeichnung erzeugt eine wohlgeformte Datei, die sich mit
`python -m json.tool` fehlerfrei parsen lässt, und der Manifest-Eintrag springt auf
`recorded`.

### AP-6 — Aufzeichnungsanleitung

Roberto zeichnet selbst auf — das kann niemand automatisieren, es sind gespielte Rallyes.
Schreibe `docs/handoffs/CC-01_AUFZEICHNUNGSANLEITUNG.md`:

- Die 11 aufzunehmenden Rallyes R-01 bis R-11 aus `07_TEST_PLAN` §2, je mit einer
  konkreten Anweisung, wie die Situation herbeigeführt wird. Nicht „Ball auf Netzoberkante",
  sondern: welcher Aufschlag, welche Position, worauf zu achten ist, woran man erkennt,
  dass die Aufnahme brauchbar ist.
- **R-12 (Deuce 14:14 → 16:14) wird nicht aufgezeichnet.** Der Prototyp beendet den Satz bei
  15 (Blocker B-05), es gibt kein Referenzverhalten. Vermerke das ausdrücklich, damit die
  Lücke später nicht als vergessen gilt.
- Hinweis, dass P2 der Bot sein darf. Der Bot-Output wird als `InputFrame` mit aufgezeichnet
  und bei der Wiedergabe eingespielt, nicht neu simuliert — seine Zufallsanteile sind damit
  eingefroren und unschädlich.
- Reihenfolge: erst alle 11 im Normalmodus, dann alle 11 mit `--fixed-dt`.
- Geschätzter Zeitbedarf.

**Abnahme:** Ein Dritter könnte die Aufzeichnung nach dieser Anleitung durchführen.

---

## 4. Was du in dieser Session nicht tust

- **Kein Refactoring.** Nicht B-01, nicht B-02, nicht B-03, nicht die Modulaufteilung.
  Jede Änderung an der Physik macht die Aufzeichnung wertlos, die du gerade erstellst.
- Keine Regelkorrekturen (B-05 Zwei-Punkte-Vorsprung, B-06 Aufschlagverzögerung dauerhaft).
  Die Aufzeichnung soll das **jetzige** Verhalten festhalten, nicht das gewünschte.
  Ausnahme ist der befristete Aufzeichnungspatch aus AP-4.
- Kein `conf.lua`, keine Font-Vorladung, kein Sound-Pool. Das ist M0-01 und M0-02.
- Kein GitHub-Remote, kein Push, keine GitHub Actions.
- Keine Assets löschen, umbenennen oder ersetzen. Nur inventarisieren.
- Keine neuen Abhängigkeiten.

---

## 5. Bekannte Fallen

| # | Falle | Umgang |
|---|---|---|
| 1 | Fließkomma-Präzision beim JSON-Schreiben | `%.17g` als String, siehe AP-5 |
| 2 | `math.random` in der Aufschlagverzögerung | Patch auf 1.0, im Header vermerkt |
| 3 | Aufzeichnung im Rohtastenformat | `InputFrame`-Bitmaske, AP-3 vor AP-5 |
| 4 | Assets landen im ersten Commit | `.gitignore` vor `git add`, AP-1 vor allem anderen |
| 5 | Der `--fixed-dt`-Shim wird zur B-02-Implementierung ausgebaut | Kommentarblock, eigener Commit, Entfernung in M0-05 |
| 6 | `WORLD.width` hängt an der Fenstergröße (B-01) | Die Fenstergröße bei der Aufzeichnung ist Teil des Zustands. **Trage Fensterbreite und -höhe in den Datei-Header ein** und zeichne alle Rallyes bei identischer Fenstergröße auf. Sonst sind die Referenzen untereinander nicht vergleichbar. |

Falle 6 ist die unangenehmste und steht so nicht im Testplan: Solange B-01 nicht behoben ist,
ist die Feldbreite ein verstecktes Eingabeparameter der Aufzeichnung. Ergänze den Header um
`"window": [breite, hoehe]` und `"world": [breite, hoehe]`, und lass das Werkzeug eine Warnung
anzeigen, wenn die aktuelle Fenstergröße von der der letzten Aufnahme abweicht.

---

## 6. Abnahme der Session

1. `git log` zeigt saubere, thematisch getrennte Commits mit Aufgaben-IDs.
2. Tag `prototype-baseline` existiert.
3. `docs/ASSET_INVENTORY.md`, `docs/13_INPUTFRAME_FORMAT.md`, ADR-014 im Decision Log,
   `docs/handoffs/CC-01_AUFZEICHNUNGSANLEITUNG.md` existieren.
4. `love .` startet unverändert; `love . --fixed-dt` startet im fixen Modus.
5. Eine Probeaufzeichnung liegt als valides JSON vor.
6. Abschnitt 12 „Kommandos" in `CLAUDE.md` ist um den Aufzeichnungsbefehl ergänzt.

---

## 7. Rückmeldung

Schreibe am Ende `docs/handoffs/CC-01_REPORT.md` mit genau diesen Abschnitten:

```markdown
# CC-01 — Bericht

## Erledigt
[Arbeitspaket → Ergebnis, je eine Zeile]

## Nicht erledigt und warum
[leer, falls nichts]

## Befunde am Prototyp
[Was du im Code gefunden hast, das im Audit 02 fehlt oder dort falsch beschrieben ist.
 Insbesondere: alle math.random-Fundstellen mit Bewertung simulationsrelevant ja/nein.]

## Verhalten bei gleichzeitig links+rechts
[Gemessenes Verhalten des Prototyps]

## Asset-Lage
[Anzahl Dateien, davon funktional notwendig, Verdachtsfälle]

## Spec-Änderungen
[Welches Dokument, welcher Abschnitt, warum]

## Entscheidungen, die Roberto treffen muss
[Nummerierte Liste, je mit Optionen und deiner Empfehlung]

## Nächster sinnvoller Schritt
[Ein Satz]
```

Dieser Bericht ist die Grundlage für das nächste Handoff. Ohne ihn kann die Orchestrierung
nicht weiterlaufen.
