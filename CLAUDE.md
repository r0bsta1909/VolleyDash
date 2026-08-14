# CLAUDE.md — Volley Dash

Diese Datei wird bei jedem Start geladen. Sie ist die Verfassung des Projekts, kein Notizzettel.
Änderungen an dieser Datei sind Projektentscheidungen und werden begründet.

---

## 1. Was das ist

**Volley Dash** — ein LÖVE2D-Arcade-Volleyball für den LAN-Party-Einsatz. Zwei Blobs, ein Ball,
ein Netz. Ausgangspunkt ist ein funktionierender lokaler Prototyp (1v1 und gegen Bot).
Zielbild v1.0: Standalone-Builds für Windows und macOS, LAN-Spiel ohne IP-Eingabe,
integrierter Turniermodus für 20 Teilnehmer.

**Der Wert des Projekts liegt nicht im Gameplay.** Das ist 25 Jahre alt und kostenlos verfügbar.
Der Wert liegt darin, dass 12 Leute in 90 Sekunden spielen. Jede Funktion, die eine Erklärung
braucht, steht unter Verdacht.

Lizenz: zlib. Öffentliches Repository. Bundle-Identifier `games.4brain.volleydash`,
Discovery-Magic `VLYD`.

---

## 2. Die Spezifikation ist die Wahrheit

Unter `docs/` liegen 13 Spezifikationsdokumente. **Sie gelten, nicht dein Trainingswissen über
Blobby Volley, LÖVE oder Netcode-Architektur allgemein.** Bevor du an einem Bereich arbeitest,
liest du das zugehörige Dokument.

| Datei | Zuständig für |
|---|---|
| `00_PROJECT_CHARTER.md` | Scope In/Out, Erfolgskriterien, Risiken. **§4 Scope-Out ist bindend.** |
| `01_GDD_v1.0.md` | Spielregeln. **§3 ist das verbindliche Vanilla-Regelwerk.** |
| `02_CODE_AUDIT_PROTOTYP.md` | Blocker B-01…B-09, Befunde F-01…F-10. **§4 ist unantastbar.** |
| `03_TECH_ARCHITECTURE.md` | Modulschnitt, Reinheitsregeln der Simulation |
| `04_NETCODE_SPEC.md` | Host-autoritative Snapshots, Protokoll |
| `05_TOURNAMENT_SPEC.md` | Turniermodell, Scheduler, Recovery |
| `06_BUILD_RELEASE_PIPELINE.md` | Build-Skripte, Signatur, Abnahme |
| `07_TEST_PLAN.md` | Ebenen A–D, Referenz-Rallyes, Abnahmekriterien |
| `08_ROADMAP_BACKLOG.md` | Meilensteine M0–M6, Aufgaben-IDs |
| `09_DECISION_LOG_ADR.md` | Getroffene Entscheidungen mit Begründung |
| `10_LEGAL_ASSETS_NAMING.md` | Assetherkunft, Namensrecht |
| `11_OPS_RUNBOOK_LANPARTY.md` | Betrieb am Partyabend |
| `12_OPENSOURCE_REPO_SETUP.md` | Repo-Struktur, CI, öffentliche Dokumente |

**Regel bei Abweichung:** Erst die Spec ändern, dann den Code. Nie umgekehrt. Wenn dir im Code
etwas begegnet, das der Spec widerspricht, meldest du das, statt es still anzupassen.

---

## 3. Doktrin

1. **Vanilla ist heilig.** Jede Abweichung vom Originalverhalten braucht eine explizite
   Entscheidung, keine stillschweigende Verbesserung. Du „verbesserst" keine Spielmechanik,
   die im GDD steht.
2. **Anti-Zufall.** Keine zufälligen Timingfenster, keine Münzwürfe bei Gleichstand, keine
   Streuung in der Physik. `math.random` hat in `src/sim/` nichts zu suchen. Turnierbetrieb
   verträgt keine unbegründete Varianz.
3. **Betriebstauglichkeit vor Feature.** Frage bei jedem Vorschlag: Was passiert, wenn jemand
   den Stecker zieht? Eine Funktion, die einen Absturz oder einen No-Show nicht übersteht,
   ist nicht fertig.
4. **Testbarkeit.** Jeder Mechanikvorschlag benennt das erwartete Verhalten und wie ein Test
   ihn widerlegen würde.
5. **Reibungsfreiheit ist das Produkt.** Time-to-First-Match ≤ 90 s ab ZIP-Download.

---

## 4. Harte Invarianten

Verstöße hiergegen sind Fehler, keine Geschmacksfragen.

- **Logisches Spielfeld ist konstant 800 × 600.** Fensteranpassung ausschließlich als
  Render-Transformation mit Letterbox/Pillarbox. (ADR-004, B-01)
- **Fixer Simulationsschritt 1/60 s** mit Akkumulator. Rendering entkoppelt und interpoliert.
  Kein `dt` aus `love.update` in der Physik. (B-02)
- **Die Simulation liest niemals Hardware.** Ein `InputFrame` pro Spieler pro Tick, erzeugt
  von genau einer von vier Quellen: lokale Tastatur, Gamepad, Bot, Netzwerk. (B-03)
- **`src/sim/` ist `love`-frei.** Kein `love.*` irgendwo unterhalb von `sim/`. Sonst laufen
  die Tests der Ebenen A und B nicht headless.
- **`Ruleset` und `Prefs` sind getrennt.** `Ruleset` ist simulationsrelevant, vom Host
  verteilt, kanonisch gehasht, während des Matches unveränderlich. `Prefs` ist rein lokal.
  (ADR-005, B-04)
- **Numerisch unveränderlich** (`02_CODE_AUDIT` §4): sämtliche Werte in `defaults`, die
  Kollisionsauflösung Blob↔Ball inkl. `activeTransfer`/`passiveBounce`, das Wandabprall-
  Verhalten mit `wallBounce = 0.70`, das `dashWindow`/`dashGrace`-Fenster, Kamera-Shake,
  Partikel-Timing, Blob-Neigung. Das ist das Spielgefühl. Wenn du einen dieser Werte anfassen
  willst, fragst du vorher.

---

## 5. Geschlossene Entscheidungen

Diese werden **nicht erneut vorgeschlagen**, es sei denn, es gibt einen neuen Sachgrund —
und dann sagst du das ausdrücklich, bevor du etwas baust.

| ADR | Entscheidung |
|---|---|
| 001 | Engine bleibt LÖVE 11.5, gepinnt. Kein Godot, kein Raylib, kein 12.0-Nightly. |
| 002 | Host-autoritative Snapshots. **Lockstep und Rollback/GGPO sind verworfen.** |
| 003 | ENet für Spiel/Lobby/Turnier, LuaSocket-UDP nur für Broadcast-Discovery. |
| 004 | Logisches Feld fix 800 × 600. |
| 005 | Trennung `Ruleset` / `Prefs`. |
| 006 | Preset `classic` hat Dash und Smash **aus**. Start-Voreinstellung ist `classic`. |
| 007 | Turnierzustand ist append-only Log, atomar geschrieben (tmp → bak → rename). |
| 008 | Keine automatische Beamer-Regie in v1.0. |
| 009 | Eigene Build-Skripte statt makelove/boon/love-export. |
| 010 | Der Name ist „Volley Dash". |
| 011 | Open Source auf GitHub unter zlib. Repo ist offen, **nicht betreut**. |
| 012 | Kein Apple Developer Program, aber **verpflichtende Ad-hoc-Signatur** im macOS-Build. |
| 013 | Turnier-Auslegungspunkt 20 Teilnehmer, parallele Matches auf dem kritischen Pfad. |
| 024 | Das Menü liegt über dem Netzspiel, **ohne es anzuhalten**. Szenen mit Sockets oder autoritativer Simulation melden sich mit `alwaysUpdate` an. |

Neue Architekturentscheidungen werden als ADR in `09_DECISION_LOG_ADR.md` protokolliert,
**bevor** sie implementiert werden. Vorlage steht am Ende der Datei.

---

## 6. Scope-Wachhund

Der Product Owner neigt zur Feature-Erweiterung. Wenn eine Anforderung über
`00_PROJECT_CHARTER` §4 hinausgeht, sagst du das **bevor** du sie ausarbeitest — mit der
konkreten Auswirkung auf den Meilensteinplan aus `08_ROADMAP`.

**Kein Feature aus M6 wird vor Abschluss von M5 begonnen.** Das betrifft insbesondere:
2v2, King of the Hill, Mutatoren (Multi-Ball, Gravity Shift), Double Elimination,
Schweizer System, Zeitlupen-Replay, automatische Beamer-Regie, Spielerprofile.

Ebenfalls nicht: Internet-Multiplayer, NAT-Traversal, Mobile-Ports, Anti-Cheat,
Progression, Unlocks, Cosmetics, Accounts.

---

## 7. Technische Randbedingungen

- **Lua 5.1 / LuaJIT.** Kein `string.pack`, kein Integer-Typ, kein `//`-Operator,
  kein `goto` in älteren Pfaden. API-Auswahl entsprechend.
- **Serialisierung:** `love.data.pack` / `love.data.unpack`. Prüfsummen über `love.data.hash`.
  **Ausnahme (M0-09):** Der Ruleset-Hash wird in `src/sim/ruleset.lua` selbst gerechnet
  (djb2 über die kanonische Form). `src/sim/` muss `love`-frei bleiben, sonst laufen die
  Tests der Ebenen A und B nicht headless. Der Hash erkennt abweichende Rulesets, er
  sichert nichts ab — dafür reicht das.
- **Netzwerk:** `lua-enet` und `luasocket` sind in LÖVE enthalten. Keine externen Abhängigkeiten
  für den Netcode. LuaSocket **immer** mit `settimeout(0)`, gepollt in `love.update`.
  Blockierende Aufrufe halten die gesamte Hauptschleife an.
- **Zielhardware:** acht Jahre alte Laptops mit iGPU. RAM < 150 MB, Start < 3 s.
- **Keine Fremdbibliotheken** ohne ADR. Jede Abhängigkeit erscheint in
  `LICENSE-THIRD-PARTY.md`.

## 8. Entwicklungsumgebung

- Hauptentwicklung läuft unter **Windows**. Shell ist **Git Bash**; r0btoshi startet in der
  Praxis auch aus **PowerShell**. Beide Formen gehören in Anleitungen — die Git-Bash-Pfade
  (`/d/love2d/...`) sind in PowerShell schlicht ungültig.
- LÖVE 11.5 liegt unter `D:\love2d\LOVE\love.exe`. Start aus dem Repo-Wurzelverzeichnis:
  `/d/love2d/LOVE/love.exe .` (Git Bash) bzw. `D:\love2d\LOVE\love.exe .` (PowerShell).
  Der Pfad ist maschinenspezifisch und gehört **nicht** hartcodiert in Skripte —
  Build- und Testskripte lesen ihn aus der Umgebungsvariablen `LOVE_BIN` mit Fallback
  auf `love` im PATH.
- **Es gibt lokal keinen Mac.** `codesign`, `hdiutil` und der `.app`-Build laufen ausschließlich
  auf einem macOS-Runner in GitHub Actions. Schreibe keine Build-Schritte, die lokal einen Mac
  voraussetzen, ohne das als Blocker zu kennzeichnen.
- Zeilenenden: LF im Repo (`.gitattributes` mit `* text=auto eol=lf`).

---

## 9. Arbeitsweise

- **Kein Vorwort, keine Wiederholung der Frage, keine Zusammenfassung am Ende.**
- Bei komplexen oder mehrdeutigen Aufgaben: alle Rückfragen in **einem** Schritt (max. 3–4),
  dann eine Umsetzungsspezifikation in 2–3 Sätzen, dann auf Freigabe warten.
- Bei einfachen Aufgaben: direkt und vollständig ausführen.
- Annahmen, die du zum Schließen von Lücken triffst, explizit auflisten.
- Nie mit „es kommt darauf an" enden. Konkrete Empfehlung mit Trade-offs.
- Widerspruch ist erwünscht, wenn er begründet ist. Höflicher Konsens verdeckt Designfehler.
- Bei faktischen, rechtlichen oder API-bezogenen Aussagen: recherchieren, nicht raten.
  LÖVE-APIs und Plattformverhalten ändern sich. Wenn du es nicht verifizieren kannst,
  sag „ich weiß es nicht".
- **Sprache: Deutsch.** Code, Bezeichner, Kommentare im Code, Commit-Messages und
  Protokollnamen bleiben Englisch.

## 10. Aufträge

Größere Arbeitspakete kommen als Handoff-Dokument unter `docs/handoffs/CC-XX_*.md` herein.
Wenn eine Aufgabe auf ein Handoff verweist, liest du zuerst das Handoff vollständig,
bevor du irgendetwas anfasst. Am Ende der Session schreibst du den Rückmeldeblock aus dem
Handoff nach `docs/handoffs/CC-XX_REPORT.md`.

## 11. Commit-Konventionen

- Conventional Commits, englisch: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`,
  `build:`.
- Jeder Commit referenziert die Aufgaben-ID aus `08_ROADMAP`, z. B.
  `feat(tools): add replay recorder (M0-03)`.
- **Niemals `git push --force` auf `main`.** Niemals `git commit --amend` auf bereits
  gepushten Commits.
- Vor dem ersten Push an GitHub: Assetherkunft geklärt (`10_LEGAL` §4). Unklar lizenzierte
  Dateien dürfen nicht in die Historie geraten.

### CI — eigenständig, nicht auf Zuruf

`gh` ist installiert (`C:\Program Files\GitHub CLI`, nicht immer im PATH — dann
`export PATH="$PATH:/c/Program Files/GitHub CLI"`) und mit dem Konto `r0bsta1909` angemeldet.
**Der Stand der CI wird selbst nachgesehen, nicht erfragt.** Nach jedem Push, der Code oder
Workflow anfasst, gehört der Lauf geprüft — und ein roter Lauf gehört gelesen, bevor jemand
gefragt wird.

| Zweck | Befehl |
|---|---|
| Läufe auflisten | `gh run list --workflow=build.yml --limit 5` |
| Auf einen Lauf warten | `gh run watch <id> --exit-status --interval 15` |
| **Warum rot** | `gh run view <id> --log-failed` — das ist der Grund für `gh`: vorher gab es nur Annotationen, und zwei Läufe gingen allein dafür drauf, überhaupt an die Ausgabe zu kommen |
| Pakete bauen ohne Release | `gh workflow run build.yml --ref main` (siehe `12_OPENSOURCE` §5) |
| Artefakte holen | `gh run download <id> --dir <ziel>` |

**Nicht eigenständig:** ein Tag setzen oder ein Release veröffentlichen. Das ist eine
öffentliche Zusage und folgt `12_OPENSOURCE` §7 — vorher CHANGELOG, VERSION und eine Freigabe.

**Artefakte und Token gehören nie ins Repo.** Heruntergeladene Pakete landen außerhalb von
`C:\devolley-dash`; ein `git add -A` erwischt sonst, was dort liegt (einmal passiert,
2026-08-13, mit den Protokollen der Selbsttests).

## 12. Kommandos

<!-- Wird gefüllt, sobald die Skripte existieren. -->

| Zweck | Befehl |
|---|---|
| Spiel starten | `/d/love2d/LOVE/love.exe .` |
| Headless-Tests (Ebene A + B) | `lua tests/run_headless.lua` (ohne LÖVE) oder `/d/love2d/LOVE/love.exe . --test` |
| Reinheit der Tests belegen | `/d/love2d/LOVE/love.exe . --test-no-love` |
| Referenz-Rallye aufzeichnen | `/d/love2d/LOVE/love.exe . --record` (F9/F10/F11, Anleitung: `docs/handoffs/CC-01_AUFZEICHNUNGSANLEITUNG.md`) |
| `fixed60`-Satz erzeugen | `/d/love2d/LOVE/love.exe . --replay-all`, danach `--scene=R-01`, `--scene=R-06`, `--scene=R-08`, `--scene=R-11` |
| Referenzen prüfen | `python tools/verify_replays.py` (muss „OK" melden) |
| Szenenparameter messen | `/d/love2d/LOVE/love.exe . --scene-probe=R-11` |
| Aufzeichnung selbst testen | `/d/love2d/LOVE/love.exe . --record-selftest` |
| Bild verkleinern | `/d/love2d/LOVE/lovec.exe . --resize=assets/bg.png:1600x1200` (überschreibt die Quelle) |
| Netz-Selbsttest (ein Prozess) | `/d/love2d/LOVE/lovec.exe . --net-selftest` |
| Netztest, zwei Prozesse | `LOVE_BIN=/d/love2d/LOVE/lovec.exe ./tools/net_test.sh loopback` |
| Netztest mit Bild und Screenshots | `LOVE_BIN=/d/love2d/LOVE/lovec.exe ./tools/net_test.sh auto` |
| Build (alles, was die Maschine kann) | `LOVE_WIN=/d/love2d/LOVE ./tools/build.sh` |
| Nur die `.love` | `./tools/build.sh love` |
| Gebautes Paket testen | `/d/love2d/LOVE/love.exe build/VolleyDash.love` — **nie den Quellordner**, und **nicht aus dem Repo-Wurzelverzeichnis** (siehe unten) |

**Das gebaute Paket wird aus einem fremden Verzeichnis gestartet, nicht aus dem Repo.**
`tests/` und `tools/` liegen bewusst nicht in der `.love` — Lua findet sie über den normalen
Suchpfad aber trotzdem, wenn das Arbeitsverzeichnis das Repo ist. Ein Lauf aus dem
Wurzelverzeichnis mischt dann Archiv und Arbeitskopie und meldet grün, ohne das Paket geprüft
zu haben (gemessen 2026-08-13). Aus dem Paket heraus gibt es folgerichtig **keine Testflags**:
`--test` und `--net-selftest` gehören zum Quellordner, das Paket wird gespielt.

`tools/build.sh` braucht Info-ZIP im PATH. Git Bash bringt kein `zip` mit:
`winget install --id GnuWin32.Zip --exact --source winget`, danach
`export PATH="$PATH:/c/Program Files (x86)/GnuWin32/bin"` (oder `ZIP_BIN` setzen).
Der macOS-Zweig läuft nur auf einem macOS-Runner — `codesign` gibt es lokal nicht.

Im Netzspiel zeigt **F3** RTT, Verlust, Tick, Puffer und seit M3 die beiden Fehlerzähler
KORREKTUR (Vorhersage, §8) und DESYNC (Protokoll, §9) — genau die Werte, nach denen die
Fehlervorlage fragt. **F4** schreibt dieselben Werte einmal je Sekunde nach `netlog.csv` in den
Save-Ordner; das ist das Messinstrument für die WLAN-Abnahme
(`docs/handoffs/CC-04_WLAN_MESSANLEITUNG.md`). Aus dem Quellordner gestartet landet jede
Abweichung zusätzlich in `desync.log` — in einem gebauten Paket nicht, dort zählt nur das
Overlay (`07_TEST_PLAN` §5).

Der Turniermodus liegt im Menü unter **NETWORK MATCH → Turnier** (M4-07). **F2** schaltet
zwischen der kompakten Spieleransicht (eigene Linie, nächster Gegner, Restzeit) und der vollen
Beamer-Ansicht um; bedient wird nur in der vollen — TAB wechselt zwischen Matches und
Teilnehmern, ENTER tut, was in der Fußzeile steht, `E` trägt ein Ergebnis ein, `K` korrigiert
eines, `P` hält den No-Show-Timer an, `A` bricht ein Match ab, `W` trägt jemanden aus. Der
Turnierstand liegt als JSON unter `tournaments/` im Save-Ordner und wird nach jedem Ereignis
geschrieben (ADR-007, ADR-020) — ein laufendes Turnier wird beim nächsten Betreten des
Turniermodus zur Wiederaufnahme angeboten. Der Bildschirm **„Gespeicherte Turniere"**
(aus Anmeldung und Wiederaufnahme erreichbar) listet alle Stände mit Status und Datum und
löscht sie mit Sicherheitsabfrage (`J` bestätigt); das geöffnete Turnier ist ausgenommen.

**Seit M4-09 läuft das Turnier über das Netz.** Der Turnierleiter öffnet den Modus wie bisher;
sein Rechner sendet dann eine Bake und steht bei allen anderen in der **Serverliste**
(`mode = "tournament"`) — ENTER dort führt ins Turnier statt in eine Match-Lobby. Teilnehmer
sehen dieselbe Anzeige, dürfen aber nichts eintragen. Gespielt wird **im** Turnier: Der
Turnier-Host ruft auf, einer der beiden Spieler hostet (**ADR-022**: RTT-Median über 5 s, ab
5 ms Unterschied, sonst die kleinere Setznummer), und das Ergebnis geht von dort zurück ins
Bracket. Der Turnier-Host bindet **21212**, ein Match-Wirt einen **ephemeren** Port — ein
Prozess kann denselben ENet-Port nicht zweimal binden, und der Turnier-Host spielt mit
(`05_TOURNAMENT` §8.2). Der Turnierstand geht als **Log-Ereignisse** hinaus, nicht als fertiger
Zustand (**ADR-023**).

Turnier-Abnahmen:

| Zweck | Befehl |
|---|---|
| Vier parallele Matches, drei Turniere im Netz (T-N-11, T-N-09) | `/d/love2d/LOVE/lovec.exe . --tournament-selftest` |
| Vier echte Prozesse, ein 4er-Turnier ohne Tastendruck | `--tournament-auto=host --client-id=1`, dazu dreimal `--tournament-auto=client --client-id=N` |
| Dazu der Aussteiger-Fall (AP-3, C-T-20): einer verlässt sein Match und muss zurückfinden, sonst Exit 1 | einer der drei Teilnehmer als `--tournament-auto=escaper --client-id=N` |

Zwei Instanzen auf **einem** Rechner teilen sich die Prefs-Datei und damit die Spielerkennung;
die Testflags nehmen deshalb `--client-id=N`. Paketverlust wird unter Windows mit `clumsy`
erzeugt, Filter und Begründung stehen im Kopf von `tools/net_test.sh`.

Alle Aufzeichnungs- und Wiedergabe-Flags sind **temporär** und gehen mit M0-13 im
Headless-Testrunner auf. `--fixed-dt` gibt es seit M0-05 nicht mehr — der feste Schritt
gilt jetzt für alle. Der `fixed60`-Satz wird erzeugt, nicht gespielt (ADR-015).
Sie alle müssen aus dem Repo-Wurzelverzeichnis gestartet werden, sonst findet das Werkzeug
`tests/replays/` nicht.
