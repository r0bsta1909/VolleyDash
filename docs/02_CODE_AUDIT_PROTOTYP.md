# 02 — Code-Audit: Prototyp `main.lua` / `bot.lua`

**Version:** 1.0 · **Stand:** 2026-08-11 · **Basis:** `main.lua` (1182 Zeilen), `bot.lua` (~130 Zeilen)

---

## 1. Gesamturteil

Der Prototyp ist als Prototyp gut: Physik, Spielgefühl, Effekte und Bot sitzen, das Live-Tweaker-Menü ist ein starkes Werkzeug fürs Balancing. Als Basis für Netzwerk und Turnier ist er in der jetzigen Form **nicht tragfähig** — nicht wegen schlechter Physik, sondern wegen vier struktureller Eigenschaften: variabler Timestep, direktes Tastaturlesen mitten in der Simulation, fenstergrößenabhängige Weltgeometrie und global veränderbarer Config-State.

Alle vier sind mit überschaubarem Aufwand behebbar, **aber sie müssen vor dem ersten Netzwerk-Code behoben sein.** Netcode auf diese Basis zu setzen bedeutet, ihn danach zweimal zu schreiben.

## 2. Blocker (müssen in M0 fallen)

### B-01 — Weltbreite hängt von der Fenstergröße ab · **kritisch**

```lua
function updateWorldDimensions()
    local winW, winH = love.graphics.getDimensions()
    scale = winH / 600
    WORLD.width = winW / scale     -- ⚠️ Feldbreite = f(Fensterbreite)
```

Zwei Clients mit unterschiedlichem Seitenverhältnis spielen auf unterschiedlich breiten Feldern. Wandabpraller, Aufschlagpositionen (`WORLD.width * 0.25`), Netzposition und die Bot-Feldbegrenzung verschieben sich mit. Auch ohne Netzwerk ist das ein Fairness- und Vanilla-Problem: Wer im Vollbild auf 21:9 spielt, hat ein anderes Spiel als der Fenster-Spieler.

**Fix:** `WORLD` wird Konstante (800×600). `scale` und Offsets kommen ausschließlich in die Render-Transformation (Letterbox/Pillarbox). `updateWorldDimensions()` verschwindet aus `love.update` komplett.

### B-02 — Variabler Timestep · **kritisch**

```lua
function love.update(dt)
    dt = math.min(dt, 0.05)
```

Die Physik integriert mit dem realen Frame-Delta. Auf 144 Hz verhält sich der Ball anders als auf 60 Hz, und bei einem Frame-Hänger springt der Ball weiter — bei `maxBallSpeed = 1400` und `dt = 0.05` legt er 70 px in einem Schritt zurück und kann durch das 10 px breite Netz tunneln.

**Fix:** Fixer Simulationsschritt 1/60 s mit Akkumulator. Rendering bleibt entkoppelt und interpoliert. Details in `03_TECH` §3.

### B-03 — Eingabe wird mitten in der Simulation gelesen · **kritisch**

```lua
p1.vx = love.keyboard.isDown("a") and -p1Speed or (love.keyboard.isDown("d") and p1Speed or 0)
```

Die Simulation fragt direkt die Hardware. Damit kann sie nicht von einem Netzwerkpaket, einem Bot, einer Aufzeichnung oder einem Testfall gespeist werden. Netcode, Replays und automatisierte Physik-Regressionstests sind so alle drei unmöglich.

**Fix:** Input-Abstraktion. Ein `InputFrame` pro Spieler pro Tick (`{left, right, jump, smash, dash}` als Bitmaske), erzeugt von genau einer von vier Quellen: lokale Tastatur, Gamepad, Bot, Netzwerk. Die Simulation kennt nur `InputFrame`.

### B-04 — Config ist global, veränderlich und vermischt zwei Dinge · **hoch**

`config` enthält gleichzeitig **Simulationsparameter** (`gravity`, `ballRadius`, `netHeight`, `activeSpike`) und **lokale Präferenzen** (`volume`, `botLevel`). Der Live-Tweaker ändert Simulationsparameter zur Laufzeit. Im Netzwerkspiel würde ein Spieler damit still die Physik seines Clients verändern.

**Fix:** Aufspaltung in `Ruleset` (simulationsrelevant, vom Host verteilt, gehasht, während des Matches unveränderlich) und `Prefs` (lokal: Lautstärke, Tastenbelegung, Anzeige). Live-Tweaker wirkt nur offline oder host-seitig in der Lobby.

### B-05 — Satzende ohne Zwei-Punkte-Vorsprung · **hoch, Regelfehler**

```lua
if gameState.scoreP1 >= 15 or gameState.scoreP2 >= 15 then
    gameState.state = "gameover"
```

Bei 15:14 ist das Spiel vorbei. Das Original verlangt 15 **und** zwei Punkte Vorsprung. Für ein Turnier ist das der Unterschied zwischen glaubwürdig und nicht.

**Fix:** `score >= targetScore and (score - other) >= 2`. Zusätzlich Deuce-Deckel (z. B. Hard-Cap bei 21) für die Turnierzeitplanung — sonst kippt ein Bracket an einem einzigen 28:26.

### B-06 — Zufällige Aufschlagverzögerung · **mittel**

```lua
gameState.serveDelay = 1.0 + math.random() * 0.5
```

Ein zufälliges Zeitfenster vor jedem Aufschlag ist im Turnier eine unnötige Varianzquelle und widerspricht dem Anti-Zufalls-Prinzip. Zudem ist `math.random` hier ungeseedet gegenüber dem Netzwerkpartner.

**Fix:** Fix 1,0 s (GDD P4).

### B-07 — Bot-Code doppelt vorhanden · **mittel**

`bot.lua` existiert als Modul (Schwierigkeiten als Strings `easy/medium/hard/god`), aber `main.lua` enthält eine **zweite, abweichende Kopie** (Schwierigkeiten als Zahlen `1/2/3`, zusätzliche Aufschlaglogik, andere Dash-Bedingung, Anpassung des Zielpunkts beim dritten Ballkontakt). Die inline-Version ist die aktuellere. Zwei Wahrheiten für dieselbe Sache — klassischer Drift-Kandidat.

**Fix:** `bot.lua` wird die einzige Quelle, übernimmt die inline-Logik, arbeitet gegen die Input-Abstraktion aus B-03. Inline-Kopie ersatzlos löschen.

### B-08 — `love.graphics.newFont()` im Draw-Aufruf · **mittel, Performance**

An mindestens sechs Stellen in `love.draw` wird pro Frame eine neue Font-Instanz erzeugt (`love.graphics.setFont(love.graphics.newFont(32))`). Das allokiert 60×/Sekunde, erzeugt GC-Druck und ist auf schwacher Hardware sichtbar.

**Fix:** Fonts einmalig in `love.load` in eine `assets.fonts`-Tabelle.

### B-09 — Bot-State ist Modul-global · **mittel**

`Bot.targetX` und `Bot.reactionTimer` liegen auf dem Modul, nicht pro Instanz. Sobald zwei Bots existieren (2v2, KotH-Füllspieler, Bot-vs-Bot-Demo am Beamer), teilen sie sich einen Zustand.

**Fix:** `Bot.new()` gibt eine Instanz mit eigenem State zurück.

## 3. Weitere Befunde (nicht blockierend)

| ID | Befund | Bewertung |
|----|--------|-----------|
| F-01 | `saveConfig()` schreibt ein selbstgebautes `key=value`-Format ohne Versionsfeld | Bei Formatänderung bricht das Laden still. Versionsfeld + Fallback auf Defaults ergänzen |
| F-02 | `loadConfig()` liest jeden Key aus der Datei, auch unbekannte | Manipulierte Save-Datei kann beliebige Config-Keys setzen. Nach Whitelist aus `defaults` filtern |
| F-03 | `math.randomseed(os.time())` auf Modulebene | Bei zwei gleichzeitig gestarteten Clients identische Seeds. Für Kosmetik egal, für Simulation relevant → getrennte RNG-Ströme |
| F-04 | `playSound` klont bei jedem Aufruf die Source | Bei vielen Wandtreffern in Folge Allokationsdruck. Source-Pool mit fester Größe |
| F-05 | Globale Funktionen (`launchGame`, `drawBlob`, `updateBlob`, `resetBall`) | Verschmutzt `_G`, erschwert Modularisierung. In M0 ohnehin behoben |
| F-06 | `gameState` mischt Match-Zustand, Rundenzustand und UI-Zustand | Sauber trennen: `MatchState` (Sätze, Punkte), `RallyState` (Berührungen, Aufschläger), `UIState` (Menü, Tweaker) |
| F-07 | Kein `conf.lua` erkennbar | Pflicht für Distribution: `t.version = "11.5"`, Fenstergröße, Identity, ungenutzte Module deaktivieren |
| F-08 | `love.window.maximize()` fest in `love.load` | Für Beamer-Client unerwünscht; gehört in Prefs |
| F-09 | Keine Trennung Update/Draw beim Menü (`gameState.state == "menu"` returned früh aus `love.update`) | Partikel und Kamera frieren im Menü ein — kosmetisch, aber Menühintergrund-Demo wird damit unmöglich |
| F-10 | Tweaker-Optionen erlauben `ballRadius` bis 80 bei `netHeight` bis 350 | Konfigurationen, in denen kein legales Spiel möglich ist. Für Offline-Spielerei ok, im Ruleset validieren |

## 4. Was ausdrücklich erhalten bleiben muss

Beim Refactoring besteht das reale Risiko, das gute Spielgefühl zu zerstören. Diese Elemente sind Kernwert und dürfen sich **numerisch nicht** ändern:

- Sämtliche Werte in `defaults` (Schwerkraft, Sprungkraft, Transferkoeffizienten, Radien).
- Die Kollisionsauflösung Blob↔Ball inkl. `activeTransfer` / `passiveBounce`-Unterscheidung.
- Das Wandabprall-Verhalten mit `wallBounce = 0.70`.
- Der Dash mit `dashWindow`/`dashGrace`-Fenster (auch wenn er in Vanilla aus ist).
- Kamera-Shake, Partikel-Timing, Blob-Neigung — das ist das Feedback, das sich „saftig" anfühlt.

**Absicherung:** Vor M0 werden 10 Referenz-Rallyes als Input-Aufzeichnung + erwartete Ballpositionen exportiert. Nach dem Umbau müssen sie innerhalb einer Toleranz von 0,5 px reproduziert werden. Verfahren in `07_TEST_PLAN` §2.

## 5. Abhängigkeitsreihenfolge der Fixes

```
B-01 (Weltgeometrie fixieren)
   └─> B-02 (Fixer Timestep)
          └─> B-03 (Input-Abstraktion)
                 ├─> B-07/B-09 (Bot als Konsument der Abstraktion)
                 └─> B-04 (Ruleset/Prefs-Trennung)
                        └─> B-05, B-06 (Regelkorrekturen im Ruleset)

B-08, F-01…F-10 sind unabhängig und können jederzeit mitlaufen.
```

Erst wenn B-01 bis B-07 stehen, darf `04_NETCODE_SPEC` umgesetzt werden.
