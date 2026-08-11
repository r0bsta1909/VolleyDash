# M0 — Abnahmeanleitung

**Stand:** 2026-08-11 · **Gilt für:** Ende M0 (alle neun Blocker, alle zehn Befunde erledigt)
**Zweck:** Du startest, spielst, meldest zurück. Diese Datei sagt dir, was du startest,
was sich absichtlich geändert hat, und was ich von dir brauche.

---

## 1. Starten

Zuerst ins Repo wechseln — beide Shells:

```powershell
cd C:\dev\volley-dash
```

**PowerShell** (Backslashes, voller Laufwerksbuchstabe):

| Was | Befehl |
|---|---|
| **Spielen** | `D:\love2d\LOVE\love.exe .` |
| Tests (83 Fälle, ~1 s) | `D:\love2d\LOVE\lovec.exe . --test` |
| Tests ohne LÖVE-Bibliothek | `D:\love2d\LOVE\lovec.exe . --test-no-love` |
| Referenzen prüfen | `python tools\verify_replays.py` |
| Neue Rallye aufzeichnen | `D:\love2d\LOVE\lovec.exe . --record` (F9/F10/F11) |
| Alter Stand für den Blindtest | `D:\love2d\LOVE\love.exe C:\dev\volley-dash-baseline` |

**Git Bash** (Schrägstriche, `/d/` statt `D:\`):

| Was | Befehl |
|---|---|
| **Spielen** | `/d/love2d/LOVE/love.exe .` |
| Tests | `/d/love2d/LOVE/love.exe . --test` |
| Referenzen prüfen | `python tools/verify_replays.py` |
| Alter Stand | `/d/love2d/LOVE/love.exe /c/dev/volley-dash-baseline` |

`lovec.exe` ist dieselbe Engine mit Konsolenausgabe — nimm die überall dort, wo du Text
sehen willst (Tests, Aufzeichnung). Zum reinen Spielen ist `love.exe` richtig.

**`fixed60`-Satz neu erzeugen** (nur nötig, wenn du am Werkzeug etwas änderst):

```powershell
D:\love2d\LOVE\lovec.exe . --replay-all
D:\love2d\LOVE\lovec.exe . --scene=R-01
D:\love2d\LOVE\lovec.exe . --scene=R-06
D:\love2d\LOVE\lovec.exe . --scene=R-08
D:\love2d\LOVE\lovec.exe . --scene=R-11
```

**Steuerung:** P1 `A`/`D` laufen, `W` springen, `S` Smash, Doppeltipp `A`/`D` = Dash.
P2 `H`/`K`, `U`, `J`. `ESC` Menü/Pause, `TAB` Live-Tweaker, `F11` Vollbild,
`R` nach Satzende neu.

---

## 2. Das musst du vorher wissen, sonst meldest du Absicht als Fehler

### Das Spiel startet ohne Dash und ohne Smash

Voreinstellung ist das Preset **`classic`** — das verbindliche Vanilla-Regelwerk aus
`01_GDD` §3: kein Dash, kein Smash, kein Speed-Scaling (ADR-006). Wenn du den Prototyp
mit Dash und Smash haben willst:

> `Local Match → Ruleset: < prototype >` — wirkt beim nächsten Matchstart.

**Für den Blindtest in §3 musst du `prototype` wählen.** Sonst vergleichst du zwei
verschiedene Regelwerke statt den Umbau.

### Weitere gewollte Änderungen

| Was | Warum |
|---|---|
| Fenster 1280 × 960, kein Maximieren mehr | 4:3 wie das Feld; breitere Fenster bekommen schwarze Balken statt eines breiteren Feldes (B-01, ADR-004) |
| Satz endet bei 15 **und** zwei Punkten Vorsprung, Deckel 21 | B-05, nur im Preset `classic` |
| Ballwechsel über 30 s → Aufschlagwechsel | GDD P5, nur `classic` |
| Aufschlagverzögerung immer 1,0 s | B-06, war vorher zufällig 1,0–1,5 s |
| Menü liegt über dem Spiel, Feld bleibt sichtbar | Szenenstapel; ESC pausiert wirklich |
| Dash-Doppeltipp zählt in Ticks statt Sekunden | hing vorher an der Bildwiederholrate (B-03) |
| Doppeltipp auf Sprung **mit** gehaltener Richtung = Seitwärts-Dash | Die Richtung kommt aus den Richtungsbits (ADR-014). Vorher immer Aufwärts-Dash |
| Der Bot ist beim Absprung minimal langsamer | Er bekam volle Bodengeschwindigkeit, die ein Mensch nie hatte. Siehe §4 |

---

## 3. Der Blindtest D1 — die eigentliche Abnahme

`07_TEST_PLAN` §6: **Drei Personen, die den Prototyp kennen, spielen je 3 Sätze mit alter
und neuer Version im Blindwechsel.** Frage: „Welche Version war Nummer 1?"
Erkennen mehr als eine Person die neue Version korrekt **und** bewerten die Änderung
negativ, ist M0 nicht abgenommen.

### Der alte Stand steht schon bereit

Ich habe ihn als zweiten Arbeitsordner ausgecheckt und die Assets hineinkopiert
(sie liegen im Tag noch nicht im Git):

```
C:\dev\volley-dash-baseline     ← Prototyp, Tag prototype-baseline
```

Starten:

```powershell
D:\love2d\LOVE\love.exe C:\dev\volley-dash-baseline
```

Wieder loswerden, wenn du ihn nicht mehr brauchst — aus `C:\dev\volley-dash` heraus:

```powershell
git worktree remove ..\volley-dash-baseline --force
```

### Ablauf

1. Neue Version starten, `Local Match → Ruleset: prototype`, `Play: VS Bot`, Bot-Level 3.
2. Alte Version starten (dort ist Dash/Smash ohnehin an).
3. Drei Sätze hier, drei Sätze dort — am besten von einer dritten Person in zufälliger
   Reihenfolge gestartet, damit der Spieler nicht weiß, was läuft.
4. Notieren: **Welche war Nummer 1?** Und falls erkannt: **woran?**

**Ein Unterschied, den du siehst und der nichts mit dem Spielgefühl zu tun hat:** Die alte
Version maximiert das Fenster und rechnet dann mit einem breiteren Feld. Für einen fairen
Vergleich zieh das alte Fenster auf 4:3 oder ignoriere die Feldbreite bewusst.

**Nebenwirkung:** Beide Fassungen benutzen dieselbe Einstellungsdatei. Startest du die alte,
schreibt sie ihr altes Format zurück, und die neue fällt danach einmalig auf ihre
Voreinstellungen zurück (Lautstärke, Belegung). Kein Fehler, nur lästig.

---

## 4. Gezielte Verdachtsstellen

Darauf schaue ich besonders — hier ist am ehesten etwas kaputt oder anders:

1. **Bot-Absprung.** Er legt im Absprungtick 5 statt 10 px zurück, weil jetzt für ihn
   dieselbe Luftsteuerung gilt wie für dich. Fühlt sich der Bot dadurch schwächer an?
   Zwei der elf Referenz-Rallyes ändern sich dadurch, beide mit unverändertem Ausgang.
2. **Dash-Timing.** Das Fenster sind jetzt 12 Ticks statt 0,20 s Echtzeit. Auf 60 Hz ist
   das dasselbe. Geht der Dash noch so leicht von der Hand wie vorher?
3. **Ballgefühl am Netz und an der Wand.** Die Physik ist nachweislich unverändert
   (bitgleiche Referenzen), aber genau da fällt eine Abweichung zuerst auf.
4. **Render-Interpolation.** Das Bild wird jetzt zwischen zwei Simulationsschritten
   interpoliert. Wirkt der Ball flüssiger, gleich, oder „schwimmt" er?
5. **Pause.** ESC mitten in der Rallye, zurück mit ESC: steht der Ball exakt dort weiter,
   wo er war?

---

## 5. Musik ausprobieren

Es liegt **keine Musikdatei im Repo**. Zum Ausprobieren:

```bash
mkdir -p music/menu music/match
# ein paar .ogg hineinkopieren
```

Dann: Menü spielt `music/menu/`, ein Match spielt `music/match/`, ESC pausiert.
Lautstärke und `Nächster Titel` stehen unter `Settings`. Ohne Dateien zeigt
`Settings → Music Volume` schlicht „keine Titel".

**Bevor ein Titel in den Commit wandert:** Herkunft klären. Eine gelöschte Datei bleibt in
der Historie eines öffentlichen Repos stehen. Details in `music/README.md`.

---

## 6. So brauche ich die Rückmeldung

Am hilfreichsten in dieser Form:

```
Was ich getan habe:   Ruleset prototype, VS Bot Level 3, drei Sätze
Was ich erwartet habe: Dash rettet den Ball wie früher
Was passiert ist:      Dash zündet erst beim dritten Versuch
```

Für den Blindtest zusätzlich: **welche Version war Nummer 1**, und ob die Änderung
positiv, neutral oder negativ war. Das ist das Abnahmekriterium, nicht mein Eindruck.

Wenn etwas abstürzt: die Fehlermeldung aus dem LÖVE-Fenster abtippen oder abfotografieren —
die Stelle steht in den ersten drei Zeilen.

---

## 7. Bekannte Lücken — die musst du nicht melden

| Lücke | Wann |
|---|---|
| Gamepad ist gebaut, aber ungetestet (kein Gerät hier) | sobald ein Controller da ist |
| `Display [WIP]` im Menü ohne Funktion | M5 (Vollbild, Beamer) |
| `Network Match [WIP]` ohne Funktion | M2 |
| Kein `.exe`-Build, nur Start über LÖVE | M1 |
| `variable/R-11` erreicht den Geschwindigkeitsdeckel nie | dokumentiert, Referenz dafür ist die Szene in `fixed60` |
| `R-02` ist „viele Ballwechsel", nicht „ein langer" | vor D1 ggf. neu aufzeichnen, siehe CC-01-Bericht |
