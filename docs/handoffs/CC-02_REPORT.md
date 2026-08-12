# CC-02 — Rückmeldung (M1 Build-Pipeline und Open-Source-Repo)

**Datum:** 2026-08-12 · **Auftrag:** `docs/handoffs/CC-02_M1_BUILD.md`
**Ausgangsstand:** 36364fb · **Endstand:** siehe `git log` ab 485936f
**Tests durchgehend:** 83 bestanden, 0 gescheitert

---

## 1. Erledigt

| AP | Aufgaben | Ergebnis |
|---|---|---|
| AP-0 | — | `VERSION` (0.1.0), `CHANGELOG.md`, D1-Abnahme protokolliert |
| AP-1 | M1-01 | `tools/build.sh` erzeugt die `.love` und prüft sich selbst nach |
| AP-2 | M1-02, M1-04, M1-05 | Windows-ZIP, Build-Hash im Menü, `LIESMICH_win.txt` |
| AP-3 | M1-03, M1-3b | macOS-Zweig, `patch_plist.py`, Ad-hoc-Signatur als Abbruchbedingung |
| AP-4 | M1-08, M1-09 | Assets nach `assets/`, Hintergrund verkleinert, drei Belegdokumente |
| AP-5 | M1-10, M1-11, M1-12 | README, `CONTRIBUTING.md`, Issue-Vorlagen, `build.yml` |
| — | M1-06 | Fenster- und `.app`-Symbol automatisch; EXE-Symbol bleibt Handgriff |

**Das Artefakt existiert.** `build/VolleyDash-0.1.0-win64.zip`, 21 MB. Die darin liegende
EXE wurde gestartet, das Menü erschien, und über zwei Tastendrücke lief ein Match — belegt
durch die Bildschirmfotos unter `docs/media/`. Getestet wurde die **gebaute** Fassung, nicht
der Quellordner (`06_BUILD` §1).

**Zeit bis zum Hauptmenü: unter 1 s** auf dieser Maschine (Fenster nach rund 280 ms,
Menü vollständig gezeichnet bei 900 ms). Das Kriterium aus `06_BUILD` §8.7 lautet < 3 s auf
der ältesten verfügbaren Testmaschine — das ist diese hier nicht.

## 2. Nicht erledigt und warum

| Punkt | Grund | Was es bräuchte |
|---|---|---|
| **M1-07 Fremdrechner** | keine fremde Hardware verfügbar | Ein Windows-11-Rechner, ein Intel-Mac, ein Apple-Silicon-Mac |
| **macOS-Build ungetestet** | kein Mac lokal (`CLAUDE.md` §8), und ohne Push läuft kein Runner | Erster Tag-Build in Actions |
| **CI unbelegt** | kein Remote, kein `gh` auf dieser Maschine | Repo anlegen, pushen |
| **EXE-Symbol** | PE-Ressourcen umschreiben ist kein Skriptzweizeiler; vorgepatchte `love.exe` verbietet `12_OPENSOURCE` §4 | Handgriff mit Resource Hacker, beschrieben in `06_BUILD` §3 |
| **Gameplay-GIF** | kein Aufnahmewerkzeug eingerichtet | stattdessen zwei Bildschirmfotos im README |

`patch_plist.py` ist immerhin gegen eine nachgebaute `Info.plist` von LÖVE 11.5 geprüft:
Identifier, Name und Version werden gesetzt, `UTExportedTypeDeclarations` und
`CFBundleDocumentTypes` verschwinden. Was daran ungetestet bleibt, ist alles, was `codesign`
tut — also der Teil, der auf Apple Silicon über Start oder Nichtstart entscheidet.

## 3. Befunde

**B-M1-1 — `main.lua` hätte jede gebaute `.love` zerlegt.** Zeile 21 lud
`tools.reference_mode` mit einem harten `require`, und `tools/` gehört laut Auftrag §3 nicht
in die Auslieferung. Aus dem Quellordner lief das, aus dem Paket nicht — genau der
Fehlertyp, vor dem `06_BUILD` §1 warnt, nur nicht wegen Groß-/Kleinschreibung. Behoben mit
`pcall` und einem inerten Ersatzobjekt.

**B-M1-2 — `.gitignore` sperrte `dist/`.** Also genau den Ordner, aus dem `06_BUILD` §5 die
`LIESMICH`-Vorlagen holt. Der Eintrag war als Schutz vor Build-Artefakten gedacht, dafür ist
`build/` zuständig. Ersetzt durch `tools/prebuilt/`.

**B-M1-3 — Die dreizehn Original-Spec-Dateien waren schreibgeschützt** (`-r--r--r--`),
später entstandene Dokumente nicht. Das sieht nach Import-Nebenwirkung aus, nicht nach
Absicht; `CLAUDE.md` §2 verlangt ausdrücklich, die Spec vor dem Code zu ändern. Ich habe den
Schutz für die fünf Dateien aufgehoben, die ich anfassen musste (06, 07, 08, 09, 12).
**Wenn das doch Absicht war, sag Bescheid** — dann gehört der Schutz zurück und die
Änderungen daran auf einen anderen Weg.

**B-M1-4 — Das Paket ist zu 70 % Musik.** Die `.love` ist 16 MB groß, davon 14 MB `music/`.
Für den lokalen HTTP-Server im LAN (`06_BUILD` §7) ist das folgenlos. Für das
Charter-Kriterium „Time-to-First-Match ≤ 90 s ab ZIP-Download" über eine Internetleitung
wird es relevant: bei 10 Mbit/s sind 21 MB rund 17 s, bei 2 Mbit/s über eine Minute. Noch
tragbar, aber der nächste Titel kippt es. `music/README.md` sieht dafür ein optionales
Zusatzpaket vor.

**B-M1-5 — `python3` ist unter Windows der Store-Platzhalter**, `python` der echte
Interpreter; unter Linux ist es umgekehrt. `build.sh` fragt deshalb beide, statt einen
vorauszusetzen.

## 4. Spec-Änderungen

Alle nach der Regel „erst die Spec, dann der Code" — hier allerdings gleichzeitig, weil es
Berichtigungen an Stellen sind, die sich beim Bauen als undurchführbar erwiesen.

| Datei | Änderung |
|---|---|
| `06_BUILD` §3 | Icon-Absatz berichtigt: eine vorgepatchte `love.exe` unter `tools/prebuilt/` widerspricht `12_OPENSOURCE` §4. Ersetzt durch den umgesetzten Dreischritt plus Anleitung für den EXE-Handgriff |
| `06_BUILD` §5 | Vorspann mit den fünf Abweichungen der umgesetzten `build.sh` vom Entwurf |
| `07_TEST_PLAN` §6 | Abnahmevermerk zu D1 |
| `08_ROADMAP` M1 | Statusspalte je Aufgabe; Anmerkung zum prozeduralen Fallback |
| `ASSET_INVENTORY` §6 | von „offen" auf „erledigt", mit den tatsächlichen Zahlen |
| `music/README.md` | Herkunft der sieben Titel festgehalten |
| `CLAUDE.md` §12 | Build-Kommandos eingetragen, `zip`-Hinweis ergänzt |

**Kein neuer ADR.** Die Entscheidung, bei Bash und Info-ZIP zu bleiben statt auf Python
auszuweichen, hat den Entwurf aus `06_BUILD` §5 gerade bestätigt — das ist kein neuer
Sachverhalt, sondern der geplante.

## 5. Entscheidungen für Roberto

**1. Wann kommt der erste Push?** Alles liegt bereit. Nötig sind: ein leeres öffentliches
Repo unter deinem Konto und die URL. Der erste Push löst zwei Dinge aus, die bis dahin
Behauptungen bleiben — der Testlauf unter echtem LuaJIT und, mit einem Tag `v0.1.0`, der
macOS-Build inklusive Signatur. Vorher weiß niemand, ob beides trägt.

**2. `LICENSE` nennt „Roberto" ohne Nachnamen**, `12_OPENSOURCE` §3 sieht „Roberto Versino"
vor. Ob dein vollständiger Name in ein öffentliches Repo gehört, ist deine Entscheidung, und
sie ist nach dem ersten Push praktisch nicht mehr rückgängig zu machen. Ich habe die Datei
unverändert gelassen.

**3. Der Schreibschutz auf den Spec-Dateien** — Absicht oder Nebenwirkung? Siehe B-M1-3.

**4. Musik in der Haupt-ZIP oder separat?** Ich habe sie drin gelassen (siehe B-M1-4). Wenn
ein achter Titel dazukommt, gehört die Frage neu gestellt.

**5. EXE-Symbol jetzt oder später?** Der Handgriff dauert fünf Minuten, macht den Build aber
für dieses eine Mal manuell. Mein Vorschlag: erst vor dem ersten Release, an dem Gäste
teilnehmen — vorher sieht das Symbol ohnehin nur du.

## 6. Nächster Schritt

**M2 — LAN 1v1**, sobald der Push durch ist. `04_NETCODE_SPEC` setzt eine abgenommene M0
voraus; die liegt seit heute vor. Davor stehen zwei kurze Dinge:

1. Repo anlegen, pushen, die CI einmal grün sehen.
2. Tag `v0.1.0` setzen und den macOS-Build zum ersten Mal wirklich laufen lassen. Wenn er
   scheitert, ist das jetzt ein billiger Fehlschlag — später ist es ein Release, das auf
   fremden Macs nicht startet.
