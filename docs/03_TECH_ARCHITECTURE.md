# 03 — Technische Architektur

**Version:** 1.0 · **Stand:** 2026-08-11

---

## 1. Technologie-Stack

| Ebene | Wahl | Begründung |
|-------|------|------------|
| Engine | **LÖVE 11.5** | Stabile Version. <cite index="13-1">LÖVE 12.0 („Bestest Friend") ist offiziell nicht veröffentlicht; verfügbar sind nur GitHub-Action- bzw. inoffizielle Nightly-Builds.</cite> Für ein Projekt, das fremden Leuten Binaries in die Hand drückt, ist ein unveröffentlichter Branch das falsche Fundament. |
| Sprache | Lua 5.1 / **LuaJIT** | Von LÖVE 11.5 mitgebracht. **Wichtig:** kein `string.pack`, kein Integer-Typ, kein `goto` in allen Formen — API-Erwartungen entsprechend setzen |
| Serialisierung | **`love.data.pack` / `love.data.unpack`** | <cite index="66-1">Verhält sich wie `string.pack` aus Lua 5.3 und folgt dessen Formatstring-Regeln.</cite> Damit ist binäres Wire-Format ohne externe Bibliothek möglich |
| Hashing | `love.data.hash` (MD5/SHA) | Für Ruleset-Hash und Desync-Checksummen |
| Transport Spiel | **lua-enet** | <cite index="21-1">lua-enet ist eine Anbindung an die ENet-Bibliothek und wird mit LÖVE mitgeliefert; ENet stellt eine dünne, robuste Netzwerkschicht über UDP bereit, deren Hauptmerkmal optional zuverlässige, geordnete Zustellung ist.</cite> |
| Transport Discovery | **LuaSocket UDP (Broadcast)** | <cite index="26-1">Das luasocket-Modul ist in der LÖVE-Binary enthalten und wird per `require("socket")` eingebunden.</cite> ENet kann keine Broadcasts — deshalb zweiter Socket. **Nur nicht-blockierend** (`settimeout(0)`), sonst friert die Hauptschleife ein |
| Persistenz | `love.filesystem` + JSON | Turnierzustand, Prefs, Profile |
| Build | Shell-/PowerShell-Skripte + GitHub Actions | Siehe `06_BUILD` |

**Keine externen Lua-Bibliotheken außer einem JSON-Encoder** (z. B. `json.lua`, MIT, eine Datei). Jede Abhängigkeit ist ein zusätzliches Lizenz- und Build-Risiko für ein Projekt dieser Größe.

## 2. Zielverzeichnisstruktur

```
volley-dash/
├── conf.lua                  # LÖVE-Konfiguration, Versions-Pin
├── main.lua                  # nur Bootstrap + love-Callbacks → Delegation
├── CLAUDE.md                 # Anweisungen für Claude Code
│
├── src/
│   ├── sim/                  # ⚠️ REINE SIMULATION — kein love.graphics, kein love.keyboard,
│   │   │                     #    kein love.audio, kein os.time, kein ungeseedetes math.random
│   │   ├── world.lua         # Weltkonstanten (800×600), Feldgeometrie
│   │   ├── ruleset.lua       # Ruleset-Definition, Presets, Validierung, Hash
│   │   ├── state.lua         # MatchState / RallyState — reine Daten, serialisierbar
│   │   ├── step.lua          # step(state, inputP1, inputP2, ruleset) → newState, events[]
│   │   ├── physics.lua       # Integration, Kollisionen Blob/Ball/Netz/Wand
│   │   ├── rules.lua         # Berührungszähler, Fehler, Punkte, Satz-/Matchende
│   │   └── rng.lua           # deterministischer PRNG (LCG), pro Match geseedet
│   │
│   ├── input/
│   │   ├── frame.lua         # InputFrame: Bitmaske ↔ Tabelle
│   │   ├── local_source.lua  # Tastatur + Gamepad → InputFrame
│   │   ├── bot_source.lua    # Bot-KI → InputFrame  (ersetzt bot.lua)
│   │   ├── net_source.lua    # Netzwerk → InputFrame
│   │   └── bindings.lua      # Tastenbelegung, persistent
│   │
│   ├── net/
│   │   ├── protocol.lua      # Nachrichtentypen, pack/unpack, Versionsfeld   [love]
│   │   ├── snapshot.lua      # State <-> flache Snapshot-Tabelle (M2-01)     [rein]
│   │   ├── input_queue.lua   # Jitter-Puffer + Repeat-Last je Slot (M2-02)   [rein]
│   │   ├── lobby.lua         # Lobby-Zustand, Slots, Ready-Status            [rein]
│   │   ├── prediction.lua    # Vorhersage des eigenen Blobs (M3-01)         [rein]
│   │   ├── checksum.lua      # djb2 fuer den Desync-Detektor (M3-03)        [rein]
│   │   ├── host.lua          # Autoritative Instanz: Sim + Snapshot-Versand  [enet]
│   │   ├── client.lua        # Input-Versand, Snapshot-Empfang, Interpolation[enet]
│   │   └── discovery.lua     # UDP-Broadcast Announce/Probe                  [socket]
│   │
│   ├── tournament/
│   │   ├── model.lua         # Datenmodell (Turnier, Runde, Match, Teilnehmer)
│   │   ├── bracket.lua       # Single Elim / Round Robin: Erzeugung, Fortschreibung
│   │   ├── scheduler.lua     # Welches Match ist als nächstes spielbar
│   │   ├── json.lua          # nur für persistence.lua (ADR-020), kein Allzweck-JSON
│   │   └── persistence.lua   # Speichern nach jedem Ereignis, Recovery   [filesystem]
│   │
│   ├── render/
│   │   ├── viewport.lua      # Letterbox-Transformation 800×600 → Fenster
│   │   ├── game_view.lua     # Blobs, Ball, Netz, Schatten
│   │   ├── fx.lua            # Partikel, Kamera-Shake
│   │   ├── fx_events.lua     # Ereignis → Staub, Klang, Wackeln (M2-06)     [love]
│   │   ├── snapshot_events.lua # Ereignisse aus zwei Snapshots (M3-02)      [rein]
│   │   ├── netstat.lua       # F3-Overlay, F4-Mitschnitt (M2-09, M3)        [love]
│   │   ├── hud.lua           # Punkte, Berührungen, Match-Kontext
│   │   └── bracket_view.lua  # Turnierbaum-Darstellung
│   │
│   ├── ui/
│   │   ├── menu.lua          # Menü-Zustandsmaschine (aus dem Prototyp übernehmbar)
│   │   ├── lobby_view.lua
│   │   ├── serverlist.lua
│   │   └── tweaker.lua       # Live-Tweaker, nur offline/host
│   │
│   ├── app/
│   │   ├── app.lua           # Programmzustand, Szenenwechsel (Ergänzung M0-12)
│   │   ├── scene.lua         # Szenen-Stack
│   │   ├── scenes/           # menu, local_game, net_game, lobby, tournament, spectator, beamer
│   │   ├── assets.lua        # Bilder, Klänge (Pool), Schriften
│   │   ├── music.lua         # Shuffle-Playlist, gestreamt (Ergänzung M0-02)
│   │   └── prefs.lua         # lokale Präferenzen, persistent
│   │
│
├── assets/                   # bg, blob, ball, sounds, fonts
├── tests/
│   ├── replays/              # aufgezeichnete Referenz-Rallyes (M0-Absicherung)
│   └── run_headless.lua      # Simulation ohne LÖVE-Fenster
├── tools/
│   ├── build_win.sh
│   ├── build_mac.sh
│   └── record_replay.lua
└── docs/                     # dieses Doc-Set
```

**Ergänzung M2-01 — warum `src/net/` sieben statt fünf Dateien hat.** Die Klammer hinter jeder Datei nennt, wovon sie abhängt. `protocol.lua` braucht `love.data.pack`, `host.lua`/`client.lua` brauchen `enet`, `discovery.lua` braucht `socket` — diese vier sind im Testrunner der Ebenen A und B nicht lauffähig. Alles, was **entscheidet** statt zu transportieren, ist deshalb herausgezogen und rein: die Abbildung Zustand ↔ Snapshot (`snapshot.lua`, dort sitzt die Phasenkodierung), der Jitter-Puffer mit Repeat-Last (`input_queue.lua`) und der Lobbyzustand (`lobby.lua`). Genau diese drei tragen die Fehler, die am Partyabend teuer sind, und genau sie laufen headless unter `luajit tests/run_headless.lua`.

**Ergänzung M3 — die Regel gilt weiter, und sie hat einen Fall über die Ordnergrenze hinweg.** `prediction.lua` und `checksum.lua` sind nach derselben Frage geschnitten: Sie entscheiden (wann korrigiert wird, ob die Bytes stimmen) und sind deshalb rein und headless prüfbar. Der Transport bleibt in `host.lua`/`client.lua`.

`snapshot_events.lua` liegt dagegen unter `render/`, weil es Kosmetik erzeugt — und ist trotzdem `love`-frei. Das ist kein Widerspruch: Der Ordner sagt, *wozu* eine Datei gehört, die Klammer sagt, *wovon sie abhängt*. Die Ableitung „Ball war rechts von der Wand, jetzt links → Wandtreffer" ist eine reine Funktion über zwei Tabellen und gehört damit in den Testrunner; `04_NETCODE_SPEC` §6 nannte bis M3 `fx.lua` als Ort, und das wäre der falsche gewesen — `fx.lua` zeichnet.

**Ausnahme, protokolliert:** `src/sim/step.lua` macht seit M3-01 zwei lokale Funktionen sichtbar (`applyImpulses`, `updateBlobTimers`), damit die Vorhersage die Simulation *aufrufen* kann, statt sie nachzubauen. Zwei Zuweisungen, keine Zeile Logik, kein Zahlenwert — Begründung in ADR-017.

`src/lib/json.lua` stand hier bis M2-01 und ist gestrichen — ADR-016.

## 3. Die zentrale Regel: `src/sim/` ist rein

**`step(state, inputP1, inputP2, ruleset) → events`**

Diese Funktion ist die einzige Stelle, an der sich der Spielzustand ändert. Gleiche Eingaben, gleicher Zustand, gleiches Ergebnis. Sie darf nicht:

- zeichnen, Sound abspielen, Tasten lesen
- `os.time`, `os.clock`, `love.timer` aufrufen
- das globale `math.random` benutzen (nur `rng.lua` mit explizitem Zustand)
- über Tabellen mit nicht-numerischen Schlüsseln iterieren, wenn die Reihenfolge das Ergebnis beeinflusst

**Warum diese Härte, obwohl kein Lockstep gefahren wird:** Auch bei host-autoritativer Simulation braucht man die Reinheit für (a) Replays, (b) automatisierte Physik-Regressionstests, (c) Client-seitige Vorhersage der eigenen Blob-Bewegung, (d) den Desync-Detektor. Die Kosten sind gering, der Nutzen steht an vier Stellen.

`events` ist eine Liste kosmetischer Auslöser (`{type="wall_hit", x=…}`, `{type="jump", player=1}`, `{type="point", to=2}`), die die Rendering-Schicht in Partikel und Sound übersetzt. So bleibt die Simulation stumm und der Client kann Effekte auch für Snapshots erzeugen, die er nicht selbst simuliert hat.

**Abweichung, entschieden in M0-08:** `step` gibt **keinen neuen Zustand** zurück, sondern ändert den übergebenen an Ort und Stelle und liefert nur die Ereignisliste. Grund: Eine Kopie des gesamten Zustands 60-mal je Sekunde ist auf acht Jahre alter Hardware unnötiger Allokationsdruck, und alte Zustände braucht niemand — ADR-002 hat Rollback verworfen, host-autoritative Snapshots kommen ohne Historie aus. An der Determiniertheit ändert das nichts: Die Funktion liest ausschließlich `state`, die beiden `InputFrames` und das `Ruleset`. Auch die Ereignisliste stellt der Aufrufer, sie wird bei jedem Aufruf geleert.

**`rng.lua` existiert noch nicht.** Seit M0-08 kommt die Simulation ohne Zufall aus (die zufällige Aufschlagverzögerung ist mit B-06 entfallen). Die Datei wird erst angelegt, wenn ein Mutator oder ein deterministischer Bot sie braucht — bis dahin ist „kein Zufall" die schärfere und billigere Regel.

### Fixer Timestep

```
TICK_RATE = 60
TICK_DT   = 1/60

accumulator = accumulator + realDt
accumulator = min(accumulator, 0.25)        -- Spiral-of-Death-Schutz: max 15 Ticks Nachholen
while accumulator >= TICK_DT do
    state = step(state, inputs, ruleset)
    accumulator = accumulator - TICK_DT
    tick = tick + 1
end
alpha = accumulator / TICK_DT                -- für Render-Interpolation
```

`TICK_DT` ist eine Konstante im Simulationscode, **nicht** ein Parameter. Der `dt`, den `love.update` liefert, erreicht `src/sim/` nie.

### Tunneling-Schutz

Bei `maxBallSpeed = 1400` und `TICK_DT = 1/60` bewegt sich der Ball maximal 23,3 px pro Tick. Netzbreite ist 10 px, Ballradius 30 px — der Ball kann das Netz nicht überspringen, solange die Kollisionsprüfung mit dem Netz als Kapsel (Rechteck + Halbkreis oben) gegen die **Bewegungsstrecke** und nicht nur gegen die Endposition arbeitet. Bei aktivem Mutator „Speed-Scaling" muss `maxBallSpeed` hart bei 1400 gedeckelt bleiben (GDD P6).

## 4. Input-Pipeline

```
┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ Tastatur/Pad │   │   Bot-KI     │   │  Netzwerk    │   │   Replay     │
└──────┬───────┘   └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
       └──────────────────┴──────────────────┴──────────────────┘
                                 │
                         ┌───────▼────────┐
                         │  InputFrame    │  1 Byte Bitmaske:
                         │  pro Tick      │  bit0 left, bit1 right, bit2 jump,
                         └───────┬────────┘  bit3 smash, bit4 dashLeft, bit5 dashRight
                                 │
                         ┌───────▼────────┐
                         │  sim.step()    │
                         └────────────────┘
```

**Dash als Bit statt als Doppeltipp-Erkennung in der Simulation:** Die Doppeltipp-Erkennung (`lastTaps` im Prototyp) ist Eingabe-Interpretation und gehört in `local_source.lua`. Die Simulation bekommt nur „Dash nach links jetzt". Sonst wandert Echtzeit-Timing in die Simulation und macht sie nicht-reproduzierbar.

## 5. Ruleset vs. Prefs

| | **Ruleset** | **Prefs** |
|---|---|---|
| Beispiele | gravity, jumpForce, blobRadius, netHeight, targetScore, activeSpike, dashEnabled, speedScaling | volume, keyBindings, fullscreen, playerName, botLevel (offline), beamerVolume |
| Wer bestimmt | Host der Lobby | jeder Client für sich |
| Wann änderbar | nur in der Lobby, nie im Match | jederzeit |
| Übertragung | vollständig beim Join + Hash bei jedem Match-Start | nie |
| Persistenz | Presets in `rulesets/*.json` | `prefs.json` |
| Live-Tweaker | nur offline oder als Host in der Lobby | — |

**Presets v1.0:** `classic` (Vanilla, GDD §3.1), `volley_dash` (Dash + Smash, namensgebende Hausvariante), `quick` (7 Punkte, kein Deuce, für KotH), `custom`. Siehe GDD §5.1.

Ruleset-Validierung beim Laden: Werte außerhalb der zulässigen Bereiche werden abgelehnt, nicht geklemmt. Ein stillschweigend geklemmter Wert erzeugt sonst unterschiedliche Rulesets bei gleichem Hash.

## 6. Szenen-Stack

```
MenuScene
 ├─ LocalGameScene      (1v1 lokal, VS Bot)
 ├─ ServerListScene ──> LobbyScene ──> NetGameScene
 ├─ TournamentHostScene ──> LobbyScene ──> NetGameScene ──> BracketScene
 ├─ SpectatorScene
 └─ BeamerScene         (eigener Einstiegspunkt, per Kommandozeilenflag --beamer)
```

Der Beamer-Client ist **dieselbe Binary** mit anderem Startflag — kein zweites Artefakt. LÖVE reicht Kommandozeilenargumente durch (`arg`), und im fusionierten Modus funktioniert das ebenfalls.

## 7. Refactoring-Reihenfolge (M0)

Jeder Schritt endet mit einem spielbaren Zustand. Nach jedem Schritt läuft die Replay-Regression.

| Schritt | Inhalt | Risiko |
|---------|--------|--------|
| M0.1 | `conf.lua` anlegen, Fonts vorladen (B-08), Referenz-Replays aufzeichnen | niedrig |
| M0.2 | Weltgeometrie fixieren, `viewport.lua` mit Letterbox (B-01) | **mittel — Spielgefühl!** |
| M0.3 | Fixer Timestep + Akkumulator, Render-Interpolation (B-02) | **hoch — Spielgefühl!** |
| M0.4 | Input-Abstraktion, `InputFrame`, lokale Quelle (B-03) | mittel |
| M0.5 | Bot auf `InputFrame` umstellen, Inline-Kopie löschen, Instanzierung (B-07, B-09) | niedrig |
| M0.6 | `sim/`-Extraktion: state, physics, rules, step — Reinheit herstellen | **hoch** |
| M0.7 | Ruleset/Prefs-Trennung, Presets, Hash (B-04) | mittel |
| M0.8 | Regelkorrekturen: Zwei-Punkte-Vorsprung, fixe Aufschlagverzögerung (B-05, B-06) | niedrig |
| M0.9 | Menü/UI in `ui/`, Szenen-Stack, `main.lua` auf < 100 Zeilen | niedrig |

**Abbruchkriterium:** Wenn nach M0.3 die Replay-Regression nicht innerhalb der Toleranz reproduziert, wird nicht weitergebaut, sondern die Abweichung analysiert. Ein „fühlt sich fast gleich an" ist an dieser Stelle die teuerste aller Antworten.

## 8. Was bewusst *nicht* gebaut wird

- **Kein ECS.** Zwei Blobs und ein Ball. Ein Entity-Component-System wäre hier reine Zeremonie.
- **Kein Physik-Framework (Box2D).** Die Kollisionen sind analytisch und handgeschrieben — genau das erzeugt das eigenwillige Spielgefühl. Box2D würde es zerstören und Determinismus verschlechtern.
- **Kein State-Management-Framework.** Ein Szenen-Stack aus 40 Zeilen reicht.
- **Keine Hot-Reload-Infrastruktur.** Der Live-Tweaker deckt den Bedarf ab.
