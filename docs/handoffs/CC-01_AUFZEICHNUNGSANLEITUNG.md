# CC-01 — Anleitung: Referenz-Rallyes aufzeichnen

**Aufgabe:** M0-03 · **Grundlage:** `07_TEST_PLAN` §2 · **Werkzeug:** `tools/record_replay.lua`
**Zeitbedarf:** rund 45 min für den gespielten Durchgang. Der zweite Durchgang wird erzeugt,
nicht gespielt (§6, ADR-015).

Diese Aufzeichnung ist **jetzt** zu machen und nur jetzt möglich. M0-04 fixiert die
Weltgeometrie, M0-05 den Timestep — danach existiert das Verhalten, das hier abgesichert
wird, nicht mehr.

---

## 1. Vorbereitung

**Start immer aus dem Repo-Wurzelverzeichnis.** Das Werkzeug schreibt mit `io.open` relativ
zum Arbeitsverzeichnis; von woanders gestartet landen die Dateien im Nichts.

```bash
/d/love2d/LOVE/love.exe . --record      # Aufzeichnen, variabler Timestep des Prototyps
/d/love2d/LOVE/love.exe . --fixed-dt    # dasselbe mit konstant 1/60 s
```

Beide Modi öffnen ein **festes, nicht skalierbares 800 × 600-Fenster** und zeigen oben links
`REC MODE (variable dt)` bzw. `FIXED 1/60`. Ohne Flag verhält sich das Spiel unverändert und
zeichnet nichts auf.

Vor dem ersten Durchgang prüfen:

- [ ] Das Overlay oben rechts ist sichtbar und zeigt `R-01  bereit`.
- [ ] Keine Warnzeile im Overlay. Erscheint `WARNUNG: Fenster …`, wurde eine frühere Aufnahme
      bei anderer Fenstergröße gemacht — dann ist der ganze Satz zu wiederholen.
- [ ] Der Live-Tweaker (`Tab`) steht auf Standardwerten. Im Zweifel
      `%APPDATA%\LOVE\volleydash\volleydash_prefs.sav` löschen; das Spiel startet dann auf
      `defaults`. Während einer laufenden Aufzeichnung ist der Tweaker gesperrt.
- [ ] Fenster **nicht** verschieben ist egal, Fenster **nicht** vergrößern ist Pflicht.
      `F11` (Vollbild) ist im Aufzeichnungsmodus deaktiviert und mit „verwerfen" belegt.

**Nebenwirkung der Namensbereinigung:** Der Prototyp benutzt seit ADR-010 die Identity
`volleydash` und die Datei `volleydash_prefs.sav`. Eine ältere `blobby_config.sav` wird nicht
mehr gefunden — das Spiel startet auf `defaults`. Für die Aufzeichnung ist genau das gewollt.

---

## 2. Bedienung

| Taste | Wirkung |
|---|---|
| `F9` | Aufzeichnung starten / stoppen und speichern |
| `F10` | nächste Rallye-ID wählen (nur außerhalb einer Aufnahme) |
| `F11` | laufende Aufzeichnung verwerfen |

Steuerung im Spiel: **P1** `A`/`D` laufen, `W` springen, `S` Smash, Doppeltipp `A`/`D`
Seitwärts-Dash, Doppeltipp `W` Aufwärts-Dash. **P2 lokal** `H`/`K`, `U`, `J`.

**Ablauf je Rallye:**

1. Mit `F10` die richtige ID wählen (Overlay prüfen).
2. In die Ausgangslage gehen: Es muss `WAITING FOR SERVE` stehen. Notfalls die vorige Rallye
   absichtlich verlieren, bis der gewünschte Aufschläger dran ist.
3. `F9` drücken, **dann** aufschlagen.
4. Direkt nach dem entscheidenden Ereignis wieder `F9`.
5. Overlay lesen: `R-0x gespeichert (N Ticks)`. Steht dort `SCHREIBFEHLER`, wurde nicht aus
   dem Repo-Wurzelverzeichnis gestartet.

**Kurz halten.** Eine gute Aufnahme hat 100 bis 600 Ticks. Alles darüber macht die Analyse
einer Abweichung mühsam, weil unklar bleibt, welcher Ballkontakt sie verursacht hat.
Ausnahme ist R-02, das ist absichtlich lang.

Eine Aufnahme überschreibt eine vorhandene Datei derselben ID im selben Modus ohne
Rückfrage. Das Overlay warnt vorher mit `Datei vorhanden -> wird ueberschrieben`.

---

## 3. P2 darf der Bot sein

Empfohlen: **Bot-Level 3** (`Local Match → Bot Level`), außer wo unten anders angegeben.

Das ist unbedenklich, obwohl der Bot `math.random` benutzt (`main.lua:331` — Jitter auf den
Zielpunkt). Aufgezeichnet wird der **Output** des Bots als `InputFrame`, nicht sein Zustand.
Die Wiedergabe spielt diese Frames ein und simuliert den Bot nicht neu — sein Zufallsanteil
ist damit eingefroren und unschädlich.

Wo es auf präzise Eingaben ankommt (R-06, R-07, R-08, R-09), ist ein zweiter Mensch oder
Bot-Level 1 besser, weil ein Level-3-Bot die Situation zu schnell auflöst.

---

## 4. Die elf Rallyes

Bezugswerte aus `defaults`: Blob-Boden `y = 500`, Ball-Boden `y = 520`, Netzoberkante
`y = 340` bei `x = 400`, Aufschlagpositionen `x = 200` bzw. `x = 600`, Ball beim Aufschlag
`y = 360`, `wallBounce = 0.70`, `maxBallSpeed = 1400`, Aufschlagverzögerung während der
Aufnahme fix 1,0 s.

### R-01 — Aufschlag P1, direkter Punkt
**Herbeiführen:** P1 hat Aufschlag. `F9`, dann mit `D` in den Ball laufen und ihn flach über
das Netz schlagen, sodass der Bot ihn nicht erreicht. Nach dem Aufkommen im gegnerischen Feld
sofort `F9`.
**Prüft:** Aufschlagphysik, `serveBoost = 0.50`.
**Brauchbar wenn:** Der Ball berührt genau einmal einen Blob, der Punktestand springt auf 1:0,
und die Aufnahme hat unter 200 Ticks. Kein zweiter Ballwechsel in der Datei.

### R-02 — Lange Rallye, mindestens 15 Ballwechsel
**Herbeiführen:** Gegen Bot-Level 3 spielen und bewusst **nicht** angreifen: den Ball hoch und
mittig zurückspielen, keinen Smash, kein Dash. Mitzählen; ab 15 Kontakten weiterlaufen lassen,
bis der Punkt fällt.
**Prüft:** akkumulierte Abweichung über viele Kontakte — der härteste Test der ganzen Reihe.
**Brauchbar wenn:** mindestens 15 Blob-Ball-Kontakte, mehr als 900 Ticks, und die Rallye endet
mit einem Punkt (nicht mit `ESC`).

### R-03 — Wandabpraller links und rechts
**Herbeiführen:** Den Ball absichtlich flach gegen die **linke** Seitenwand spielen (mit `A`
laufend treffen), im selben Ballwechsel danach gegen die **rechte**. Zur Not zwei Anläufe,
aber beide Wandkontakte müssen in **einer** Aufnahme liegen.
**Prüft:** `wallBounce = 0.70`, Vorzeichenbehandlung in beide Richtungen.
**Brauchbar wenn:** In den Frames kehrt `ball.vx` zweimal das Vorzeichen um, ohne dass ein
Blob in der Nähe war, und `x` liegt dabei bei `30` bzw. `WORLD.width - 30` (`ballRadius`).

### R-04 — Ball auf der Netzoberkante
**Herbeiführen:** Der kritischste Fall. Den Ball in hohem Bogen so spielen, dass er die
Netzkante bei `x = 400`, `y ≈ 340` trifft. Praktisch: aus der Nähe des Netzes mit einem
stehenden Blob hochspielen (`passiveBounce`) und die Höhe variieren. Erwarte **mehrere
Fehlversuche** — mit `F11` verwerfen und neu.
**Prüft:** Kollision gegen die Netzkappe (Radius 5), der Fall mit der größten
Tunneling-Gefahr.
**Brauchbar wenn:** Der Ball springt sichtbar oben auf dem Netz auf, statt seitlich
abzuprallen, und `hit_net` ist hörbar. In den Frames wechselt `vy` des Balls das Vorzeichen,
während sein Mittelpunkt 35 px (`ballRadius + 5`) von der Netzkappe bei `(400, 345)` entfernt
ist — also `y` zwischen 310 und 345 bei `x` zwischen 365 und 435.

### R-05 — Ball an die Netzseite
**Herbeiführen:** Flach von der eigenen Seite gegen die Netzflanke spielen, deutlich unterhalb
der Oberkante (`y > 345`).
**Prüft:** seitliche Netzkollision, im Prototyp ein anderer Zweig als R-04 (Dämpfung 0,8).
**Brauchbar wenn:** Der Ball prallt zurück auf die eigene Seite und fällt dort zu Boden.
`ball.x` liegt beim Kontakt bei `395 - ballRadius` bzw. `405 + ballRadius`.

### R-06 — Blob-Ball-Kontakt aktiv (bewegter Blob)
**Herbeiführen:** Mit gedrücktem `D` (oder `A`) **in den fallenden Ball hineinlaufen**, nicht
springen. Der Blob muss im Moment der Berührung sichtbar Fahrt haben.
**Prüft:** `activeTransfer = 0.40`, den Zusatzimpuls aus der Blob-Geschwindigkeit.
**Brauchbar wenn:** Im Kontakt-Frame ist `p1.vx` = ±600 (`moveSpeed`) und die Ballgeschwindigkeit
danach deutlich höher als in R-07. Am besten direkt nach R-07 aufnehmen und vergleichen.

### R-07 — Blob-Ball-Kontakt passiv (stehender Blob)
**Herbeiführen:** Blob unter den fallenden Ball stellen, **keine Taste drücken**, Ball auf dem
Kopf abprallen lassen.
**Prüft:** `passiveBounce = 0.75` ohne Aktivanteil.
**Brauchbar wenn:** Im Kontakt-Frame ist `p1.vx = 0` und `p1.vy = 0`, der Blob steht am Boden
(`y = 500`).

### R-08 — Smash aus dem Sprung
**Herbeiführen:** Ball hoch anspielen, mit `W` springen und **`S` gedrückt halten**, während
der Blob den Ball in der Luft trifft. Der Smash wirkt nur, wenn der Blob **nicht** am Boden ist.
**Prüft:** `activeSpike`, Faktoren 1,3 waagerecht und 1,4 senkrecht.
**Brauchbar wenn:** Der Bildschirm wackelt kurz (Kamera-Shake), der Ball geht steil nach unten,
und im Kontakt-Frame ist das `smash`-Bit (8) im `InputFrame` von P1 gesetzt.

### R-09 — Dash mit Rettung
**Herbeiführen:** Den Ball weit zur Seite spielen lassen, dann **zweimal schnell** `A` bzw. `D`
tippen (innerhalb `dashWindow = 0,20 s`) und den Ball im Dash noch erwischen.
**Wichtig:** Der Dash muss von **Spieler 1** kommen, nicht vom Bot — beim Bot kann das
Richtungsbit fehlen (`13_INPUTFRAME_FORMAT` §7).
**Prüft:** Dash-Fenster, `dashSide = 2.5`, `dashGrace`-Rettungsfenster.
**Brauchbar wenn:** Der Bildschirm wackelt beim Ballkontakt (das ist der Dash-Save-Shake), im
`InputFrame` von P1 ist das `dash`-Bit (16) gesetzt, und der Ball geht zurück über das Netz.

### R-10 — Drei Berührungen bis zum Fehler
**Herbeiführen:** Den Ball auf der **eigenen** Seite viermal hintereinander selbst berühren,
ohne dass er die Seite wechselt. Am einfachsten mit kleinen Stupsern nach oben.
**Prüft:** Berührungszähler, Fehlerauslösung beim vierten Kontakt.
**Brauchbar wenn:** Die Anzeige läuft sichtbar auf `Touches: 3 / 3`, danach erscheint `FAULT!`
und der Gegner bekommt den Punkt. In den Frames steigt das zweite Element von `touch` (der
Zähler) auf 3; der Fehler löst erst beim **vierten** Kontakt aus.

### R-11 — Ballgeschwindigkeit am Maximum
**Herbeiführen:** Smash aus dem Sprung (wie R-08) auf einen bereits schnellen Ball, am besten
nach einem Dash. Ziel ist, dass der Deckel `maxBallSpeed = 1400` greift.
**Prüft:** Geschwindigkeitsdeckel und die Tunneling-Gefahr am Netz.
**Brauchbar wenn:** In mindestens einem Frame gilt `sqrt(vx² + vy²) ≈ 1400` (Prüfung im JSON,
im Spiel nicht ablesbar). Zur Not zwei Anläufe und die Datei mit dem höchsten Wert behalten.

---

## 4b. Was in der Datei steht

`tests/replays/<modus>/<id>.json`, ein Eintrag je Simulationsschritt:

| Feld | Bedeutung |
|---|---|
| `t` | Tickindex ab 0 |
| `dt` | Schrittweite dieses Ticks (im Modus `fixed60` immer `0.016666666666666666`) |
| `in` | `[InputFrame P1, InputFrame P2]` — Bitmaske `left=1 right=2 jump=4 smash=8 dash=16` |
| `ball`, `p1`, `p2` | je `[x, y, vx, vy]` |
| `touch` | `[letzter Berührer, Zähler]` |
| `score` | `[P1, P2]` |
| `server` | 1 oder 2 |
| `phase` | `serve` oder `play` |

Alle Fließkommazahlen stehen als **Strings** in der Datei (`"%.17g"`), damit beim Schreiben
keine Nachkommastelle verloren geht. Der spätere Testrunner liest sie mit `tonumber` zurück.

**Wichtig für die Auswertung:** Der Zustand in einem Frame ist der Zustand **vor** dessen
Schritt (`"state_convention": "pre_step"`). Die Wiedergabe lädt also `frames[i]`, spielt
`frames[i].in` ein, macht einen Schritt und vergleicht mit `frames[i+1]`.

Der Kopf der Datei hält außerdem `window`, `world`, `ruleset_snapshot` (die vollständige
`defaults`-Tabelle), `patches_active` und den Commit des Prototyps fest.

---

## 5. R-12 wird nicht aufgezeichnet

**R-12 (Deuce 14:14 → 16:14) hat im Prototyp kein Referenzverhalten.** `main.lua:533` beendet
den Satz bei 15 Punkten ohne Zwei-Punkte-Vorsprung — das ist Blocker **B-05**. Bei 15:14 ist
das Spiel vorbei, die Situation 16:14 kann gar nicht entstehen.

Die Lücke ist **kein Versehen**. Sie ist im Manifest als `blocked` eingetragen und bleibt
sichtbar, bis M0-10 die Regel korrigiert. Danach wird R-12 als **neuer** Testfall der Ebene B
geschrieben (T-R-10, T-R-11 in `07_TEST_PLAN` §3), nicht als Aufzeichnung — es gibt kein
Altverhalten, gegen das man vergleichen könnte.

---

## 6. Reihenfolge und Abschluss

**Von Hand wird nur der Durchgang `--record` gespielt.** Er ist am 2026-08-11 erledigt und
liegt unter `tests/replays/variable/`.

Der zweite Durchgang `fixed60` wird **nicht gespielt, sondern erzeugt** (ADR-015):

```bash
/d/love2d/LOVE/love.exe . --replay-all        # sieben Rallyes: Eingaben mit 1/60 zurueckspielen
/d/love2d/LOVE/love.exe . --scene=R-01        # vier Skriptszenen, siehe unten
/d/love2d/LOVE/love.exe . --scene=R-06
/d/love2d/LOVE/love.exe . --scene=R-08
/d/love2d/LOVE/love.exe . --scene=R-11
python tools/verify_replays.py                 # muss "OK" melden
```

Warum vier Szenen: Bei identischen Eingaben laufen variabler und fixer Schritt nach 40 bis
190 Ticks über 0,5 px auseinander. Vier Rallyes verlieren dadurch genau die Situation, für
die sie existieren — R-01 verliert den Aufschlag, R-06 steht beim Kontakt am Netzpfosten
(`vx = 0`), R-08 verpasst den Smash aus der Luft, R-11 erreichte den Geschwindigkeitsdeckel
schon im gespielten Lauf nie. Diese vier haben stattdessen einen gesetzten Startzustand und
einen festen Eingabeplan; die Physik dazwischen ist unverändert die des Prototyps.

**Wenn eine Rallye nachträglich neu gespielt werden soll** (`--record`, F9/F10/F11 wie oben),
danach `--replay-all` erneut laufen lassen — der `fixed60`-Satz wird aus dem gespielten Satz
abgeleitet und muss zu ihm passen.

Danach ist M0-04 freigegeben.
