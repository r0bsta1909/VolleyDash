# CC-01 — Bericht

**Session:** 2026-08-11 · **Handoff:** `CC-01_M0-03_Referenzaufzeichnung.md` · **Aufgabe:** M0-03
**Stand am Ende:** acht thematisch getrennte Commits, Tag `prototype-baseline`, Werkzeug einsatzbereit.
Die eigentlichen elf Rallyes muss Roberto selbst spielen (AP-6).

## Erledigt

- **AP-1** — `git init -b main`, `.gitattributes` (um `*.jpg binary` ergänzt), `.gitignore` mit wurzelgebundenen Assetmustern, `LICENSE` (zlib, Copyright „Roberto"). `git status` zeigt alle elf Assets als ignoriert.
- **AP-1b** — Acht Stellen von „Blobby LAN" auf „Volley Dash" umgestellt. Zwei getrennte Commits, `prototype-baseline` auf den zweiten. `grep -ri blobby main.lua bot.lua` ist leer, keine Assetdatei in der Historie.
- **AP-2** — `docs/ASSET_INVENTORY.md` mit elf Dateien, SHA-256, Verwendungsstelle, Herkunftsstatus und der Einordnung funktional/dekorativ.
- **AP-3** — `docs/13_INPUTFRAME_FORMAT.md` geschrieben, **ADR-014** im Decision Log ergänzt, `08_ROADMAP` M0-06 verweist darauf.
- **AP-4** — Aufzeichnungs-Shim in `main.lua`: `--fixed-dt`, `--record`, `--record-selftest`, drei Aufzeichnungspatches, Modusanzeige oben links. Ohne Flag verhält sich das Spiel unverändert.
- **AP-5** — `tools/record_replay.lua` (F9/F10/F11, Overlay, `%.17g`-JSON, vollständiger `ruleset_snapshot`, Fenster-/Weltgröße im Header, Warnung bei abweichender Fenstergröße) und `tests/replays/manifest.json` mit allen zwölf IDs.
- **AP-6** — `docs/handoffs/CC-01_AUFZEICHNUNGSANLEITUNG.md` mit konkreter Herbeiführung und Gütekriterium je Rallye. `CLAUDE.md` §12 ergänzt.
- **Probeaufzeichnung** — je einmal in beiden Modi über `--record-selftest`. Beide Dateien parsen fehlerfrei mit `python -m json.tool`, das Manifest wird geschrieben.

## Nicht erledigt und warum

- **Die elf Referenz-Rallyes selbst.** Das sind gespielte Rallyes; das kann niemand automatisieren. Werkzeug, Anleitung und Verzeichnisse stehen bereit, das Manifest listet alles als `missing`.
- **R-12 dauerhaft.** Der Prototyp beendet den Satz bei 15 ohne Zwei-Punkte-Vorsprung (B-05), es gibt kein Referenzverhalten. Im Manifest als `blocked` mit Begründung eingetragen, nicht als `missing` — die Lücke gilt damit nicht als vergessen.
- **Die Probeaufzeichnung `R-00` ist nicht committet** (`.gitignore`), weil sie kein Referenzwert ist. Reproduzierbar mit `love . --record-selftest [--fixed-dt]`.

## Befunde am Prototyp

**Vollständige `math.random`-Inventur** (Zeilennummern nach dem Shim-Einbau):

| Ort | Zweck | Simulationsrelevant |
|---|---|---|
| `main.lua:508` | `serveDelay = 1.0 + math.random() * 0.5` | **ja** — einziger Fall. Während der Aufzeichnung auf 1,0 gepatcht (B-06, GDD P4) |
| `main.lua:110` | `math.randomseed(os.time())` | nein — Saat für alles Folgende. Während der Aufzeichnung fest `1` |
| `main.lua:111–113` | Zufällige Spielernamen | nein |
| `main.lua:132–138` | Partikelstreuung (fünf Aufrufe) | nein — reine Optik, kein Rückfluss in die Physik |
| `main.lua:331` | Bot-Jitter auf den Zielpunkt | nein — siehe unten |
| `main.lua:992` | Kamera-Shake, im `love.draw` | nein — verschiebt nur die Zeichentransformation |
| `bot.lua:44` | Bot-Jitter, zweite Kopie (B-07) | nein — Datei wird vom Prototyp nicht geladen |

**Die Vorbefunde aus §2b des Handoffs sind bestätigt**, mit drei Korrekturen:

1. Der Bot-Jitter ist unschädlich, **weil die Aufzeichnung den Bot-Output festhält**. Das ist umgesetzt: `Recorder.noteBotInputs` bekommt den Rückgabewert von `Bot.updateAI` und übersetzt ihn in einen `InputFrame`. Der Bot-Zustand wird nirgends gespeichert.
2. `bot.lua` wird vom Prototyp **gar nicht geladen** — es gibt kein `require("bot")` in `main.lua`. Die Datei ist toter Code, die Inline-Kopie ist die einzige aktive. Das schärft B-07: Es sind nicht zwei konkurrierende Wahrheiten, sondern eine aktive und eine verwaiste.
3. Der prozedurale Fallback existiert wie beschrieben. Die im Handoff genannten Zeilen liegen bei `loadImage` `434–437` und `loadSound` `442–447`, Zeichenstellen `996`, `1062`, `1197`, `playSound` `411`.

**Weitere Befunde, die im Audit 02 fehlen:**

- **`love.window.maximize()` ist schlimmer als beschrieben, aber jetzt eingehegt.** Mit `resizable = true` plus `maximize()` hängt `WORLD.width` an der Bildschirmauflösung. Auf einem 1920×1080-Schirm ergäbe das maximiert `scale = 1,8` und `WORLD.width ≈ 1066,67`; die Referenz wäre nach M0-04 (fixe 800×600) wertlos gewesen. Im Aufzeichnungsmodus wird `maximize()` deshalb übersprungen und das Fenster auf feste 800×600 gesetzt. Gemessen: `WORLD 800x600`, `scale = 1`.
- **`love.keyboard.hasKeyRepeat()` ist in LÖVE 11.5.0 `false`** (gemessen im Selbsttest). Der ereignisgesteuerte Sprung des Prototyps wiederholt sich beim Halten der Taste also nicht. Damit ist die Pegel-Aufzeichnung von `jump` eindeutig.
- **`handleDoubleTap` misst in Echtzeit** über `love.timer.getTime()`, nicht in Ticks. Im Modus `fixed60` bleibt die Dash-Erkennung damit an der Bildwiederholrate hängen. Für die Aufzeichnung ist das unschädlich (der Dash wird als Flanke festgehalten), für M0-06 ist es eine Aufgabe.
- **`defaults` vermischt Ruleset und Prefs** stärker als B-04 vermuten lässt: `botActive`, `botLevel` und `volume` stehen in derselben Tabelle wie `gravity` und `wallBounce`. Der `ruleset_snapshot` in den Replays enthält deshalb bewusst die **ganze** Tabelle — die Trennung ist M0-09, nicht diese Session.
- **`whistle_end`-Pfad im Satzende ist an `>= 15` gebunden** (`main.lua:533`, zusätzlich `1140` für den Gewinnernamen). Wer B-05 repariert, muss beide Stellen anfassen.

## Verhalten bei gleichzeitig links+rechts

**Gemessen: links gewinnt. Kein Stillstand.**

```lua
-- main.lua:585 (P1)
p1.vx = love.keyboard.isDown("a") and -p1Speed or (love.keyboard.isDown("d") and p1Speed or 0)
-- main.lua:635 (P2 lokal)
p2.vx = love.keyboard.isDown("h") and -p2Speed or (love.keyboard.isDown("k") and p2Speed or 0)
```

Die `and/or`-Kette wertet von links: Liegt die Linkstaste an, ist das Ergebnis `-speed`,
unabhängig von der Rechtstaste. `vx = 0` gibt es nur, wenn keine der beiden Tasten anliegt.

Das Handoff schlug „beide gesetzt ergibt Stillstand" vor. Das ist nicht das Verhalten des
Prototyps. **Entscheidung Roberto (2026-08-11): Das gemessene Verhalten wird
festgeschrieben**, `main.lua` bleibt unverändert, ADR-014 und
`13_INPUTFRAME_FORMAT.md` §5 halten es fest.

Der Bot ist von der Frage nicht betroffen: `Bot.updateAI` (`main.lua:375–377`) und
`Bot.update` (`bot.lua:82–87`) setzen `left`/`right` in einem `if/elseif`, können also nie
beide Bits setzen.

## Asset-Lage

- **Elf Dateien**, nicht zehn wie im Handoff gezählt (die Aufzählung dort enthält elf). Alle im Wurzelverzeichnis, kein `assets/`-Ordner — die Abnahmeformulierung „jede Datei in `assets/`" geht ins Leere.
- **Funktional notwendig: keine einzige.** `loadImage`, `loadSound` und `playSound` haben vollständige `nil`-Absicherungen, jede Zeichenstelle hat einen prozeduralen Zweig, `main.lua:465` setzt sogar eine Ersatzfarbe. Der Fallback aus `10_LEGAL` §4 existiert de facto bereits. R-05 ist damit deutlich entschärft.
- **Verdachtsfall aufgeklärt, aber anders als vermutet:** `bg.jpg` ist **keine JPEG-Datei**, sondern ein PNG (2752×1536) mit falscher Endung — und es trägt ein **signiertes C2PA-Manifest**: „Created by Google Generative AI", `digitalSourceType: trainedAlgorithmicMedia`, plus „Applied imperceptible SynthID watermark", Signaturkette *Google C2PA Media Services*, Zeitstempel 2026-08-10 19:54 UTC. Das Bild ist KI-generiert, nicht fotografiert und kein Stock-Material.
- **`blob.png`, `ball.png`:** nur ein leerer XMP-Rumpf, kein Urheber. Herkunft offen.
- **Acht `.wav`:** mit FFmpeg geschrieben (`Lavf59.27.100`). Das sagt nichts über die Quelle des Klangs. Fünf haben identische Bytegröße, aber unterschiedliche Hashes — keine Duplikate.
- **Kein Fund aus Blobby Volley.** Weder Namen noch Metadaten deuten darauf hin. Die Stop-Regel aus AP-2 ist nicht ausgelöst, die GPLv2-Frage stellt sich nach jetzigem Stand nicht.
- **Technisch:** 4,9 MB für ein Bild, das auf 800×600 skaliert gezeichnet wird, entspricht rund 16 MB Texturspeicher. Das steht dem Ziel „< 150 MB RAM, Start < 3 s auf 2015er-Hardware" entgegen, unabhängig von der Lizenzfrage.

## Spec-Änderungen

| Dokument | Abschnitt | Was und warum |
|---|---|---|
| `docs/13_INPUTFRAME_FORMAT.md` | neu | Kanonisches Eingabeformat. Musste vor der Aufzeichnung stehen, sonst prüft Ebene A später die Übersetzungsschicht statt der Physik (AP-3). |
| `docs/09_DECISION_LOG_ADR.md` | ADR-014 neu | Formatentscheidung mit verworfenen Alternativen, inklusive der Ablehnung der Stillstand-Regel. |
| `docs/08_ROADMAP_BACKLOG.md` | M0-06, §3 | M0-06 verweist auf ADR-014 und das Formatdokument. §3 listet M0-03 jetzt **vor** den Blockern — das Fehlen war ein Fehler der Fassung 1.0, wie im Handoff §1 festgestellt. |
| `docs/ASSET_INVENTORY.md` | neu | Grundlage für M1-09. |
| `CLAUDE.md` | §12 | Aufzeichnungs- und Fixed-Timestep-Kommandos eingetragen, mit dem Hinweis auf ihre Befristung. |

Nicht geändert: `01_GDD`, `02_CODE_AUDIT` §4, `07_TEST_PLAN`. Die Befunde oben gehören ins
Audit, sind aber Sache der nächsten Session — `02_CODE_AUDIT` §4 ist unantastbar, §2/§3 wären
zu ergänzen.

## Entscheidungen, die Roberto treffen muss

1. **Herkunft von `blob.png`, `ball.png` und den acht `.wav`.**
   Optionen: (a) selbst erstellt → in `assets/CREDITS.md` eintragen und ins Repo aufnehmen; (b) fremd/unklar → draußen lassen und in M1-09 durch prozedurale Grafik und erzeugte Sounds ersetzen.
   **Empfehlung:** (b) als Standard, unabhängig von der Antwort. Der Fallback funktioniert bereits, und das Repo bleibt sauber. Assets können später als optionales Zusatzpaket kommen.

2. **`bg.jpg` — KI-generiert, C2PA-signiert.**
   Optionen: (a) Nutzungsbedingungen des Google-Dienstes prüfen und bei Freigabe verkleinert (800×600, als `.png`) aufnehmen; (b) ersetzen; (c) prozeduraler Hintergrund.
   **Empfehlung:** (c) für v1.0. Er existiert bereits, kostet nichts, spart 4,9 MB und 16 MB VRAM und macht die Lizenzfrage gegenstandslos. Das Bild kann als optionales Paket nachgereicht werden. Zu klären ist es trotzdem, bevor es je committet wird — das Manifest wandert mit in die Historie.

3. **`bot.lua` ist toter Code.**
   Optionen: (a) bis M0-07 liegen lassen; (b) jetzt löschen; (c) jetzt als veraltet markieren.
   **Empfehlung:** (a). M0-07 macht `bot.lua` ohnehin zur einzigen Quelle. Ein Löschen jetzt würde nur den Diff von M0-07 verwirren. Die Datei bleibt im ersten Commit, damit die Historie den Ausgangszustand zeigt.

4. **Reihenfolge der Aufzeichnung gegen den Terminplan.**
   Die elf Rallyes kosten rund 1,5 bis 2 Stunden am Stück. Optionen: (a) vor M0-04 vollständig aufzeichnen; (b) zuerst die kritischen sechs (R-01, R-02, R-04, R-06, R-07, R-11) und den Rest später.
   **Empfehlung:** (a). Nach M0-04 ist keine Nachaufnahme mehr möglich; eine halbe Referenz sichert genau die Fälle nicht ab, die erfahrungsgemäß brechen.

5. **Was mit dem `variable`-Durchgang nach M0-05 geschieht.**
   Er ist nach dem Timestep-Wechsel nicht mehr als Regressionsreferenz brauchbar, nur noch als Beleg. Optionen: (a) im Repo behalten; (b) nach der D1-Abnahme löschen.
   **Empfehlung:** (a). Rund 100 KB je Datei, und es ist der einzige Beleg dafür, wie sich der Prototyp tatsächlich verhalten hat.

## Nächster sinnvoller Schritt

Elf Rallyes im Modus `--record` und danach elf im Modus `--fixed-dt` nach
`CC-01_AUFZEICHNUNGSANLEITUNG.md` aufzeichnen, committen — erst danach M0-04 beginnen.

---

# CC-01 — Nachtrag (2026-08-11, zweite Sitzung)

Roberto hat die elf Rallyes mit `--record` gespielt und entschieden: den `fixed60`-Satz
erzeuge ich selbst, die Assetherkunft ist geklärt, `bot.lua` wird gelöscht, der
`variable`-Durchgang bleibt.

## Erledigt

- **`tools/verify_replays.py`** — prüft je Rallye ein hartes Kriterium (Netzkappenkontakt,
  Wandabpraller beidseitig, Aktiv- gegen Passivkontakt, Smash aus der Luft, Dash-Rettung,
  vierte Berührung, Geschwindigkeitsdeckel), vergleicht beide Durchgänge und prüft den
  Eingabe-Rundlauf.
- **`tools/replay_source.lua` + Treiber im Shim** — die Wiedergabe-Quelle aus ADR-014.
  `--replay-all`, `--replay=<id>`, `--scene=<id>`, `--scene-probe=<id>`, `--write-manifest`.
- **`fixed60`-Satz vollständig**, elf Dateien, **11 von 11 bestehen ihr Kriterium**.
- **ADR-015** protokolliert das Verfahren; `07_TEST_PLAN` §2 ist auf den tatsächlichen
  Ablauf umgeschrieben und um die gemessenen Zahlen ergänzt.
- **Assets** im Repo, Herkunft in `ASSET_INVENTORY.md` und `10_LEGAL` §4 eingetragen.
- **`bot.lua` gelöscht**, `02_CODE_AUDIT` B-07, `08_ROADMAP` M0-07, `13_INPUTFRAME_FORMAT`
  und `docs/README.md` nachgezogen.

## Verifikation beider Sätze

| ID | variable (gespielt) | fixed60 | Treiber fixed60 |
|---|---|---|---|
| R-01 | PASS | PASS | `scripted:R-01` |
| R-02 | PASS | PASS | `replay` |
| R-03 | PASS | PASS | `replay` |
| R-04 | PASS | PASS | `replay` |
| R-05 | PASS | PASS | `replay` |
| R-06 | PASS | PASS | `scripted:R-06` |
| R-07 | PASS | PASS | `replay` |
| R-08 | PASS | PASS | `scripted:R-08` |
| R-09 | PASS | PASS | `replay` |
| R-10 | PASS | PASS | `replay` |
| R-11 | **FAIL** (max 1156 statt 1400) | PASS | `scripted:R-11` |

Der eine Ausreißer im gespielten Satz ist dokumentiert, nicht repariert: `variable/R-11`
erreicht den Deckel `maxBallSpeed` nicht. Die Datei bleibt unverändert, die Referenz für
den Deckel ist die Szene in `fixed60`. `verify_replays.py` führt das als bekannten Fall.

## Gemessen: variabler gegen fixen Schritt

Gleiche Eingaben, gleicher Startzustand, nur die Schrittweite unterscheidet sich.

| ID | Ticks | Eingabe-Rundlauf | max. Ballabweichung | ab Tick > 0,5 px |
|---|---|---|---|---|
| R-02 | 2627 | identisch | 731,4 px | 64 |
| R-03 | 1139 | identisch | 507,2 px | 194 |
| R-04 | 277 | identisch | 521,2 px | 68 |
| R-05 | 206 | identisch | 0,9 px | 126 |
| R-07 | 354 | identisch | 2,0 px | 129 |
| R-09 | 290 | identisch | 21,9 px | 85 |
| R-10 | 359 | identisch | 1,9 px | 105 |

**Der Eingabe-Rundlauf ist in allen sieben Fällen Tick für Tick identisch.** Das ist der
Beweis, dass der Treiber genau das eingespielt hat, was aufgezeichnet wurde — die
Abweichungen stammen ausschließlich aus der Schrittweite, nicht aus dem Werkzeug.

**Die Abweichung ist drei Größenordnungen größer als die Toleranz von 0,5 px.** Sie
überschreitet sie schon nach 64 bis 194 Ticks, also nach ein bis drei Sekunden. Wo nur
wenige Kontakte stattfinden (R-05, R-07, R-10), bleibt sie unter 2 px; jeder Blob-Ball-
Kontakt vervielfacht sie.

**Konsequenz für M0-05:** Ein Vergleich `variable` ↔ `fixed60` als Abnahmekriterium ist
wertlos. Verglichen wird `fixed60` (Prototyp) gegen `fixed60` (neue Simulation). Das steht
jetzt so in `07_TEST_PLAN` §2. Über die Wahl von 1/60 sagt die Zahl nichts — das entscheidet
der Blindtest D1.

## Warum vier Rallyes eine Szene brauchen

- **R-01** verliert bei fixem Schritt den Aufschlag, statt den Punkt zu machen: der Rückball
  landet auf der eigenen Seite. Der Aufschlagkontakt selbst fällt in beiden Läufen auf
  denselben Tick (75).
- **R-06** hat den Blob im Kontaktmoment am Netzpfosten stehen. `updateBlob` klemmt ihn dort
  auf `vx = 0` — der Aktivtransfer, den R-06 absichern soll, findet dann nicht statt. Ein
  Tick Versatz genügt dafür.
- **R-08** verliert den Smash aus der Luft, nachdem der Ballwechsel ab Tick 215 auseinanderläuft.
- **R-11** erreichte den Deckel in keinem der beiden Läufe.

Die Szenen setzen einen Startzustand und einen festen Eingabeplan; die Physik dazwischen ist
unverändert die des Prototyps. Die Parameter sind mit `--scene-probe` **gemessen**.

## Neuer Befund am Prototyp: der Smash kann sich selbst aufheben

Beim Bau der R-11-Szene aufgefallen und belegt: Trifft ein springender Blob den Ball **exakt
von unten**, dreht der Smash `ball.vy = math.abs(ball.vy) * 1.4` die Bewegung nach unten,
also **in den Blob hinein**. Die anschließende `minOutward`-Korrektur zieht das komplett
zurück, und der Ball verlässt den Kontakt mit exakt 200 px/s (`ballBaseSpeed * 0.4`) — aus
einem Anflug mit 1117 px/s.

Der Smash beschleunigt also nur bei seitlichem Versatz. Bei senkrechtem Treffer **bremst er
maximal**. Das erklärt auch, warum der Geschwindigkeitsdeckel im gespielten R-11 nie fiel.

Ob das Vanilla ist oder ein Fehler, ist eine Regelfrage und gehört nicht in diese Sitzung
(GDD §3, `02_CODE_AUDIT` §4 ist unantastbar). Es ist jetzt in einer Referenz festgehalten:
`fixed60/R-08` und `fixed60/R-11` fahren beide bewusst mit Versatz.

## Zweiter Befund: `maxBallSpeed` ist über einen passiven Abpraller unerreichbar

Rechnerisch: ausgehende Geschwindigkeit = `0,75 × eingehende` (`1 + passiveBounce` minus der
eingehenden Komponente). Ein passiver Kontakt kann den Deckel nur überschreiten, wenn der
Ball schon vorher schneller als 1867 px/s wäre — was der Deckel selbst verhindert. Der Deckel
greift ausschließlich über Aktivtransfer (Dash, laufender Blob) oder Smash mit Versatz.
Das gehört in die Bewertung von B-06/GDD, wenn dort je über `maxBallSpeed` diskutiert wird.

## Entscheidungen, die Roberto treffen muss

Keine. Die fünf offenen Punkte aus dem ersten Bericht sind beantwortet:
Assetherkunft geklärt (1, 2), `bot.lua` gelöscht (3), Aufzeichnung vollständig (4),
`variable`-Durchgang bleibt im Repo (5).

Ein einziger Hinweis, ohne Rückfrage: `bg.jpg` liegt mit 4,9 MB dauerhaft in der Historie.
Herausschreiben ist nur bis zum ersten Push nach GitHub billig. Verkleinern steht als
Technikpunkt in M1-09.

## Nächster sinnvoller Schritt

M0-04 (B-01, Weltgeometrie fixieren, `viewport.lua` mit Letterbox). Die Absicherung steht:
`python tools/verify_replays.py` muss danach weiterhin „OK" melden, und nach M0-05 wird
`fixed60` gegen die neue Simulation gefahren.
