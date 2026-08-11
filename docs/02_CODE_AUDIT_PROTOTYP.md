# 02 — Code-Audit: Prototyp `main.lua` / `bot.lua`

**Version:** 1.1 · **Stand:** 2026-08-11 · **Basis:** `main.lua` (1182 Zeilen), `bot.lua` (~130 Zeilen)

> **Nachtrag CC-01 (2026-08-11):** `bot.lua` wurde nie geladen — in `main.lua` gibt es kein
> `require`. Die Datei ist in M0-03 gelöscht worden, siehe B-07. Sie bleibt über den Tag
> `prototype-baseline` in der Historie erreichbar.

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

**Erledigt in M0-04 (2026-08-11).** `src/sim/world.lua` hält die Konstanten, `src/render/viewport.lua` macht die Letterbox-Transformation, `updateWorldDimensions()` ist ersatzlos gelöscht. Übrig blieb in `love.update` nur `WORLD.groundY = config.blobGroundY`, weil das ein Config-Wert ist und kein Fensterwert (Trennung in M0-09). Nachweis: die elf `fixed60`-Referenzen wurden nach dem Umbau neu erzeugt und sind **Frame für Frame bitgleich** mit dem Satz davor.

### B-02 — Variabler Timestep · **kritisch**

```lua
function love.update(dt)
    dt = math.min(dt, 0.05)
```

Die Physik integriert mit dem realen Frame-Delta. Auf 144 Hz verhält sich der Ball anders als auf 60 Hz, und bei einem Frame-Hänger springt der Ball weiter — bei `maxBallSpeed = 1400` und `dt = 0.05` legt er 70 px in einem Schritt zurück und kann durch das 10 px breite Netz tunneln.

**Fix:** Fixer Simulationsschritt 1/60 s mit Akkumulator. Rendering bleibt entkoppelt und interpoliert. Details in `03_TECH` §3.

**Erledigt in M0-05 (2026-08-11).** `love.update` verteilt die reale Frame-Zeit auf ganze Ticks von `World.TICK_DT`; die Physik sieht ausschließlich diese Konstante. Der Rest im Akkumulator wird als `renderAlpha` an die Zeichenschicht gegeben, die zwischen dem Zustand vor und nach dem letzten Tick interpoliert. Sprungstellen (`resetBall`) setzen den Interpolationspuffer zurück.

Nachweis: der Selbsttest zeichnet **300 Ticks in 5,05 s Echtzeit auf, während 2261 Frames gerendert wurden** (rund 448 fps ohne VSync) — Tickrate und Bildrate sind entkoppelt. Die elf `fixed60`-Referenzen sind nach dem Umbau erneut Frame für Frame bitgleich, weil sie schon mit exakt 1/60 s aufgezeichnet wurden.

### B-03 — Eingabe wird mitten in der Simulation gelesen · **kritisch**

```lua
p1.vx = love.keyboard.isDown("a") and -p1Speed or (love.keyboard.isDown("d") and p1Speed or 0)
```

Die Simulation fragt direkt die Hardware. Damit kann sie nicht von einem Netzwerkpaket, einem Bot, einer Aufzeichnung oder einem Testfall gespeist werden. Netcode, Replays und automatisierte Physik-Regressionstests sind so alle drei unmöglich.

**Fix:** Input-Abstraktion. Ein `InputFrame` pro Spieler pro Tick (`{left, right, jump, smash, dash}` als Bitmaske), erzeugt von genau einer von vier Quellen: lokale Tastatur, Gamepad, Bot, Netzwerk. Die Simulation kennt nur `InputFrame`.

**Erledigt in M0-06 (2026-08-11).** `src/input/frame.lua` (Bitmaske, love-frei) und `src/input/local_source.lua` (Tastatur, Gamepad, Doppeltipp-Erkennung in Ticks). `love.keyboard` kommt in der Simulation nicht mehr vor; Sprung und Dash sind Flanken aus dem `InputFrame` statt Tastenereignisse. Der Bot schreibt seinen Output bis M0-07 zusätzlich als `InputFrame` mit. Nachweis: 17 Unit-Tests (`love . --test`) und elf `fixed60`-Referenzen weiterhin bitgleich.

### B-04 — Config ist global, veränderlich und vermischt zwei Dinge · **hoch**

`config` enthält gleichzeitig **Simulationsparameter** (`gravity`, `ballRadius`, `netHeight`, `activeSpike`) und **lokale Präferenzen** (`volume`, `botLevel`). Der Live-Tweaker ändert Simulationsparameter zur Laufzeit. Im Netzwerkspiel würde ein Spieler damit still die Physik seines Clients verändern.

**Fix:** Aufspaltung in `Ruleset` (simulationsrelevant, vom Host verteilt, gehasht, während des Matches unveränderlich) und `Prefs` (lokal: Lautstärke, Tastenbelegung, Anzeige). Live-Tweaker wirkt nur offline oder host-seitig in der Lobby.

**Erledigt in M0-09 (2026-08-11).** `src/sim/ruleset.lua` (Felder mit Grenzen, Presets `classic`/`prototype`, Validierung, kanonische Form, Hash) und `src/app/prefs.lua` (Lautstärke, Bot-Stufe, gewähltes Preset). Das Preset wird beim Matchstart festgelegt und ändert sich danach nicht mehr; der Live-Tweaker bleibt als dokumentierte Ausnahme fürs Offline-Spiel und arbeitet nur noch auf dem Ruleset. **`classic` ist die Voreinstellung** (ADR-006): kein Dash, kein Smash, kein Speed-Scaling.

### B-05 — Satzende ohne Zwei-Punkte-Vorsprung · **hoch, Regelfehler**

```lua
if gameState.scoreP1 >= 15 or gameState.scoreP2 >= 15 then
    gameState.state = "gameover"
```

Bei 15:14 ist das Spiel vorbei. Das Original verlangt 15 **und** zwei Punkte Vorsprung. Für ein Turnier ist das der Unterschied zwischen glaubwürdig und nicht.

**Fix:** `score >= targetScore and (score - other) >= 2`. Zusätzlich Deuce-Deckel (z. B. Hard-Cap bei 21) für die Turnierzeitplanung — sonst kippt ein Bracket an einem einzigen 28:26.

**Erledigt in M0-10 (2026-08-11).** `Rules.isSetWon` in `src/sim/rules.lua`, gesteuert über `twoPointLead` und `deuceCap` im Ruleset. Das Preset `classic` spielt nach dem GDD (15 und zwei Punkte Vorsprung, Deckel 21), das Preset `prototype` behält bewusst das alte Verhalten, damit die Referenz-Rallyes reproduzierbar bleiben. Tests T-R-09 bis T-R-12 in `tests/rules_test.lua`.

### B-06 — Zufällige Aufschlagverzögerung · **mittel**

```lua
gameState.serveDelay = 1.0 + math.random() * 0.5
```

Ein zufälliges Zeitfenster vor jedem Aufschlag ist im Turnier eine unnötige Varianzquelle und widerspricht dem Anti-Zufalls-Prinzip. Zudem ist `math.random` hier ungeseedet gegenüber dem Netzwerkpartner.

**Fix:** Fix 1,0 s (GDD P4).

**Erledigt in M0-08 (2026-08-11), vorgezogen aus M0-10.** Die Reinheitsregel aus `03_TECH` §3 verbietet `math.random` in `src/sim/`; damit war die zufällige Aufschlagverzögerung der einzige Blocker für die Extraktion. Die Alternative wäre ein `rng.lua` gewesen — Aufwand für einen Wert, der laut GDD P4 ohnehin konstant sein soll. `src/sim/rules.lua` setzt jetzt immer 1,0 s. **Alle Referenzaufnahmen liefen bereits mit dieser Konstante**, deshalb ändert sich an ihnen nichts. Was von M0-10 offen bleibt: Zwei-Punkte-Vorsprung (B-05) und Rallye-Timeout (P5).

### B-07 — Bot-Code doppelt vorhanden · **mittel**

`bot.lua` existierte als Modul (Schwierigkeiten als Strings `easy/medium/hard/god`), aber `main.lua` enthält eine **zweite, abweichende Kopie** (Schwierigkeiten als Zahlen `1/2/3`, zusätzliche Aufschlaglogik, andere Dash-Bedingung, Anpassung des Zielpunkts beim dritten Ballkontakt). Die inline-Version ist die aktuellere. Zwei Wahrheiten für dieselbe Sache — klassischer Drift-Kandidat.

**Befund CC-01:** `bot.lua` wurde vom Prototyp **gar nicht geladen** (kein `require` in `main.lua`). Es waren nicht zwei konkurrierende Wahrheiten, sondern eine aktive Inline-Kopie und eine verwaiste Datei. Die verwaiste Datei ist in M0-03 gelöscht.

**Fix:** M0-07 hebt die Inline-Logik nach `src/input/bot_source.lua` (`03_TECH` §2) und lässt sie gegen die Input-Abstraktion aus B-03 arbeiten. Die Inline-Kopie verschwindet dabei ersatzlos.

**Erledigt in M0-07 (2026-08-11).** Die Logik steht wortgleich in `src/input/bot_source.lua`, alle Zahlen unverändert. Der Bot ist jetzt eine Quelle wie jede andere: er liefert ein Byte je Tick, die Simulation kennt nur noch einen Verbrauchspfad für beide Spieler. `p2.botSmash` ist entfallen — der Smash kommt aus dem `InputFrame`.

**Verhaltensfolge, bewusst in Kauf genommen:** Der Bot bekam beim Absprung bisher volle Bodengeschwindigkeit, weil sein Sprung erst *nach* der Geschwindigkeitsberechnung desselben Ticks ausgelöst wurde. P1 hatte diesen Vorteil nie — dort lag der Sprung schon immer vor dem Tick. Mit dem gemeinsamen Pfad gilt für beide dasselbe: im Absprungtick greift `airControl`. Der Bot legt dadurch 5 statt 10 px in diesem einen Tick zurück. Zwei der elf Referenz-Rallyes ändern sich dadurch messbar, beide mit unverändertem Ausgang (`07_TEST_PLAN` §2).

### B-08 — `love.graphics.newFont()` im Draw-Aufruf · **mittel, Performance**

An mindestens sechs Stellen in `love.draw` wird pro Frame eine neue Font-Instanz erzeugt (`love.graphics.setFont(love.graphics.newFont(32))`). Das allokiert 60×/Sekunde, erzeugt GC-Druck und ist auf schwacher Hardware sichtbar.

**Fix:** Fonts einmalig in `love.load` in eine `assets.fonts`-Tabelle.

**Erledigt in M0-12 (2026-08-11), vorgezogen aus M0-02.** `src/app/assets.lua` lädt alle sieben benutzten Größen einmal; die Zeichenschicht ruft nur noch `Assets.setFont`. Offen aus M0-02 bleibt der Sound-Pool (F-04).

### B-09 — Bot-State ist Modul-global · **mittel**

`Bot.targetX` und `Bot.reactionTimer` liegen auf dem Modul, nicht pro Instanz. Sobald zwei Bots existieren (2v2, KotH-Füllspieler, Bot-vs-Bot-Demo am Beamer), teilen sie sich einen Zustand.

**Fix:** `Bot.new()` gibt eine Instanz mit eigenem State zurück.

**Erledigt in M0-07 (2026-08-11).** `BotSource.new(playerIndex, ctx)`; `targetX` und `reactionTimer` liegen auf der Instanz. Zwei Bots teilen sich keinen Zielpunkt mehr.

## 3. Weitere Befunde (nicht blockierend)

| ID | Befund | Bewertung |
|----|--------|-----------|
| F-01 | `saveConfig()` schreibt ein selbstgebautes `key=value`-Format ohne Versionsfeld | **Erledigt M0-09.** `Prefs.VERSION = 1` steht in der Datei; passt sie nicht, gelten die Voreinstellungen |
| F-02 | `loadConfig()` liest jeden Key aus der Datei, auch unbekannte | **Erledigt M0-09.** Whitelist `Prefs.FIELDS`; unbekannte Schlüssel, falsche Typen und Werte außerhalb der Grenzen werden verworfen |
| F-03 | `math.randomseed(os.time())` auf Modulebene | Bei zwei gleichzeitig gestarteten Clients identische Seeds. Für Kosmetik egal, für Simulation relevant → getrennte RNG-Ströme |
| F-04 | `playSound` klont bei jedem Aufruf die Source | Bei vielen Wandtreffern in Folge Allokationsdruck. Source-Pool mit fester Größe |
| F-05 | Globale Funktionen (`launchGame`, `drawBlob`, `updateBlob`, `resetBall`) | **Erledigt M0-12.** Alles liegt in Modulen; `main.lua` hat 64 Zeilen und definiert nur noch die LÖVE-Rückrufe |
| F-06 | `gameState` mischt Match-Zustand, Rundenzustand und UI-Zustand | **Erledigt M0-08/M0-12.** `state.match` und `state.rally` in `src/sim/state.lua`; der UI-Zustand liegt in den Szenen und im Menü |
| F-07 | Kein `conf.lua` erkennbar | **Erledigt M0-01.** Version gepinnt (ADR-001), Identity `volleydash`, Fenster 1280 × 960 (4:3 wie das Feld), `physics`/`video`/`touch`/`mouse`/`thread` abgeschaltet |
| F-08 | `love.window.maximize()` fest in `love.load` | **Erledigt M0-01.** Ersatzlos entfallen; die Fenstergröße kommt aus `conf.lua`. Eine Anzeigeoption in den Prefs (Vollbild, Beamer) bleibt für M5 offen |
| F-09 | Keine Trennung Update/Draw beim Menü (`gameState.state == "menu"` returned früh aus `love.update`) | Partikel und Kamera frieren im Menü ein — kosmetisch, aber Menühintergrund-Demo wird damit unmöglich |
| F-10 | Tweaker-Optionen erlauben `ballRadius` bis 80 bei `netHeight` bis 350 | **Erledigt M0-09.** `Ruleset.validate` prüft Feldgrenzen und Spielbarkeit (Sprunghöhe + Radien müssen die Netzkante erreichen). Die Grenzen des Tweakers kommen jetzt aus derselben Definition |

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
