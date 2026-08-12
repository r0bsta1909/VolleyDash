# 04 — Netcode-Spezifikation

**Version:** 1.1 · **Stand:** 2026-08-12 · **Bezug:** ADR-002, ADR-003, ADR-016

**Änderungen gegenüber 1.0** (alle in M2-01, vor der ersten Zeile Netzcode; Regel aus
`CLAUDE.md` §2 — erst die Spec, dann der Code):

| § | Was | Warum |
|---|---|---|
| 5, 10 | `rulesetHash` ist djb2 mit 8 ASCII-Hexstellen, nicht MD5 mit 16 Byte | ADR-016; gebaut ist `Ruleset.hash`, und `src/sim/` muss `love`-frei bleiben |
| 5 | `RULESET_FULL` überträgt eine binäre Schlüssel-Wert-Folge, kein JSON | ADR-016; es gibt keinen JSON-Leser und soll keinen geben |
| 6 | Snapshot-Feldliste gegen `src/sim/state.lua` berichtigt: Phasen, Sätze, Neigung, Cooldown, Fehlerwurf | 1.0 kodierte zwei Phasen, die es nicht gibt, und ließ drei Werte weg, die der Client zum Zeichnen braucht |
| 11 | Der suchende Client bindet einen flüchtigen Port; der Host antwortet auf `PROBE` unicast | Zwei Instanzen auf einem Rechner können denselben Port nicht portabel binden — genau der Testaufbau aus M2-10 |
| 3 | Bandbreite auf die tatsächliche Snapshot-Größe nachgerechnet | Folge der Korrektur in §6 |

---

## 1. Warum kein Lockstep — die wichtigste Änderung am Ausgangs-GDD

Das Ausgangs-GDD forderte „deterministische 2D-Physik mit Lockstep-Architektur". Diese Anforderung wird gestrichen.

**Lockstep verlangt bitweise identische Simulation auf allen Clients.** <cite index="60-1">Die Grundvoraussetzung einer Lockstep-Architektur ist strikter bitweiser Determinismus: Da nur Eingaben synchronisiert werden, muss jede Maschine bei gleichen Eingaben pro Frame exakt identische Ergebnisse berechnen — sonst laufen die Simulationen auseinander.</cite> Das ist in diesem Projekt aus vier Gründen nicht erreichbar:

1. **Windows-x86-64 gegen macOS-ARM64.** <cite index="60-1">Bei plattformübergreifenden Spielen ist Fließkomma-Determinismus besonders schwer zu erreichen, weil Compiler unterschiedliche Befehlssätze nutzen, Befehle umordnen oder automatisch vektorisieren und weil transzendente Funktionen wie Sinus und Cosinus je System unterschiedlich implementiert sind.</cite> Genau diese beiden Architekturen sind die Zielplattformen.
2. **LuaJIT verhält sich auf Apple Silicon anders als auf Windows.** LÖVE 11.5 hat <cite index="5-1">die JIT-Kompilierung auf macOS-arm64 (Apple Silicon) standardmäßig deaktiviert, weil Performance und verfügbarer JIT-Speicher dort nicht zuverlässig sind.</cite> Auf dem Mac läuft also der Interpreter, auf Windows der JIT — zwei unterschiedliche Ausführungspfade für dieselbe Arithmetik.
3. **Der Ausweg wäre Festkomma-Arithmetik.** <cite index="60-1">Manche Entwickler implementieren ihre Simulation ausschließlich in Fixed-Point- oder softwareemulierter Fließkomma-Arithmetik, um Indeterminismus zu umgehen.</cite> Das bedeutet, die gesamte Physik in Ganzzahl-Arithmetik neu zu schreiben — in Lua 5.1, das gar keinen Integer-Typ hat. Aufwand und Risiko für das Spielgefühl stehen in keinem Verhältnis.
4. **Der Vorteil von Lockstep existiert hier nicht.** Lockstep spart Bandbreite bei sehr großem Weltzustand (RTS mit tausenden Einheiten). Der gesamte Zustand dieses Spiels passt in **48 Byte**. Es gibt schlicht nichts zu sparen.

**Konsequenz:** host-autoritative Simulation mit Zustands-Snapshots.

## 2. Architekturüberblick

```
        ┌────────────────────────── HOST (ein Spieler-Laptop) ──────────────────────────┐
        │                                                                                │
        │   Eingaben:  lokal ──┐                                                         │
        │              Client ─┼──> InputBuffer ──> sim.step() @60 Hz ──> State          │
        │              Bot ────┘                                            │            │
        │                                                                   ▼            │
        │                                          Snapshot (48 B) @60 Hz ──┴──> Clients │
        └────────────────────────────────────────────────────────────────────────────────┘
                     ▲                                              │
              InputFrame (1 B + Header) @60 Hz                Snapshot @60 Hz
                     │                                              ▼
        ┌────────────┴──────────────────── CLIENT ───────────────────────────────────────┐
        │  Tastatur ──> InputFrame ──> senden                                            │
        │                     └──────> lokale Vorhersage des eigenen Blobs (M3)          │
        │  Snapshot ──> Interpolationspuffer (2 Ticks) ──> Rendering                     │
        └────────────────────────────────────────────────────────────────────────────────┘
```

**Die Simulation läuft an genau einer Stelle.** Der Client simuliert nicht (Ausnahme: eigene Blob-Vorhersage ab M3, siehe §8). Damit ist Desync per Konstruktion ausgeschlossen — es gibt keine zweite Wahrheit, die abweichen könnte.

**Der Host spielt mit.** Kein dedizierter Server. Der Host hat dadurch 0 ms Eingabelatenz, der Client 1 RTT. Bei LAN-RTT < 2 ms ist das nicht wahrnehmbar. (Bei WLAN mit 20–40 ms RTT wird es das — siehe §8 und `11_OPS` §2.)

## 3. Bandbreitenrechnung

| Richtung | Größe | Rate | Bandbreite |
|----------|-------|------|-----------|
| Client → Host: `INPUT` | 10 B (Header 3 + Tick 4 + 3 Masken) + Overhead ≈ 38 B | 60/s | 2,3 KB/s |
| Host → Client: `SNAPSHOT` | 72 B (Header 3 + 69 B Nutzlast) + Overhead ≈ 100 B | 60/s | 6,0 KB/s |
| Host → Spectator | wie Client | 30/s | 3,0 KB/s |

Bei 4 parallelen Matches plus 8 Zuschauern liegt die Gesamtlast im zweistelligen KB/s-Bereich. Auf 100-MBit-LAN irrelevant, auf WLAN unkritisch.

Fassung 1.0 rechnete mit 48 B je Snapshot. Nach der Berichtigung der Feldliste in §6 sind es 69 B Nutzlast. An der Aussage ändert das nichts: der Unterschied zwischen 4,6 und 6,0 KB/s ist auf jedem Netz dieses Jahrtausends nicht messbar. Er ist trotzdem hier korrigiert, weil eine Zahl, die niemand nachrechnet, irgendwann als Begründung für eine Optimierung herhält.

**Snapshot-Rate 60 Hz statt 20 Hz mit Interpolation:** Bei diesen Größen ist die volle Tickrate billiger als jede Optimierung. Delta-Kompression, Snapshot-Interpolation über größere Lücken, Eingabe-Redundanz — alles nicht nötig. Das ist der eigentliche Gewinn der Snapshot-Architektur bei kleinem Zustand.

## 4. Transport

| Zweck | Technik | Port (Default) |
|-------|---------|----------------|
| Match & Lobby | ENet (lua-enet), UDP | **21212** |
| Discovery | LuaSocket UDP Broadcast | **21213** |

Beide Ports konfigurierbar. Portbereich frei gewählt, kollidiert nicht mit gängigen Spiele-/Systemdiensten.

### ENet-Kanäle

| Kanal | Modus | Inhalt |
|-------|-------|--------|
| 0 | **reliable** | Lobby, Ruleset, Match-Start/-Ende, Turnier-Nachrichten, Chat |
| 1 | **unreliable** | Snapshots (veraltete Snapshots sind wertlos, Neuübertragung schadet nur) |
| 2 | **unreliable** | InputFrames (verlorene Frames werden über Redundanz kompensiert, §7) |

Wichtig bei lua-enet: die Ereignisschleife muss **pro Frame vollständig geleert** werden, nicht nur ein Ereignis pro Durchlauf — sonst staut sich die Queue bei 60 Hz Snapshots sofort auf.

```lua
local event = host:service(0)
while event do
    handle(event)
    event = host:service(0)   -- Timeout 0, niemals blockieren
end
```

## 5. Nachrichtenformat

Alle Nachrichten beginnen mit einem 3-Byte-Header. Serialisierung via `love.data.pack` mit **Little-Endian und explizit dimensionierten Typen** (`<` Präfix, `i4`, `f`), damit Win/macOS identisch interpretieren.

```
Header:  u8 protoVersion | u8 msgType | u8 flags
```

`protoVersion` = 1. Ein Client mit abweichender Version wird beim Join abgewiesen — mit einer Klartextmeldung, nicht mit einem Timeout. (Auf einer LAN-Party hat garantiert jemand eine ältere ZIP.)

`flags` ist in v1 durchgehend 0 und reserviert. Ein Empfänger prüft es **nicht** — sonst ist das Feld für seinen Zweck (später etwas hinzufügen, ohne die Version zu heben) wertlos.

**Zeichenketten** werden mit `s1` gepackt: ein Längenbyte, dann die Bytes. Damit ist jede Zeichenkette auf 255 Byte begrenzt; die Sender kürzen vorher auf das jeweilige Feldmaß. Kein `z`, keine feste Breite — eine nicht terminierte Zeichenkette aus einer fremden Version würde sonst den Rest der Nachricht verschieben.

### Nachrichtentypen

| ID | Name | Richtung | Kanal | Nutzlast |
|----|------|----------|-------|----------|
| 0x01 | `HELLO` | C→H | 0 | clientId(4), buildHash(≤16), playerName(≤24) |
| 0x02 | `WELCOME` | H→C | 0 | slot(1), clientId(4), rulesetHash(8), hostName(≤24), lobbyName(≤32) |
| 0x03 | `REJECT` | H→C | 0 | reasonCode(1), text(≤64) |
| 0x10 | `LOBBY_STATE` | H→C | 0 | count(1), je Slot: occupied(1), ready(1), isHost(1), name(≤24), buildHash(≤16) |
| 0x11 | `SET_READY` | C→H | 0 | ready(1) |
| 0x12 | `RULESET_FULL` | H→C | 0 | count(1), je Feld: name(≤32), typ(1), wert (`d` oder `u1`) — ADR-016 |
| 0x20 | `MATCH_START` | H→C | 0 | matchId(4), startTick(4), rulesetHash(8), slot(1) |
| 0x21 | `INPUT` | C→H | 2 | tick(4), masks(3) — siehe §7 |
| 0x22 | `SNAPSHOT` | H→C | 1 | siehe §6 |
| 0x23 | `MATCH_END` | H→C | 0 | matchId(4), scoreA(1), scoreB(1), reason(1) |
| 0x24 | `MATCH_PAUSE` | H→C | 0 | paused(1), secondsLeft(1), text(≤64) — §12 |
| 0x30 | `SPECTATE_REQ` | C→H | 0 | matchId(4) |
| 0x40 | `TOURNAMENT_STATE` | H→C | 0 | JSON, siehe `05_TOURNAMENT` |
| 0x50 | `PING` / 0x51 `PONG` | beidseitig | 0 | timestamp(4) |
| 0x60 | `CHECKSUM` | H→C | 0 | tick(4), hash(4) — Desync-Detektor, §9 |

### Namen in der Lobby sind eindeutig

Der Name eines Spielers ist im Netzspiel und im Turnier seine **Kennung**: er steht in der Lobby, im HUD und später im Bracket. Zwei gleiche Namen sind dort keine Unschönheit, sondern eine Frage, die niemand beantworten kann — wer hat gewonnen?

Der Host löst das beim Beitritt auf, **durch Anhängen, nicht durch Ablehnen**: Ist der Wunschname schon vergeben (Vergleich ohne Rücksicht auf Groß- und Kleinschreibung), wird `" 2"`, `" 3"` … angehängt. Ein Gast, der wegen seines Namens abgewiesen würde, müsste zurück ins Menü, tippen und neu verbinden — drei Schritte gegen die 90-Sekunden-Vorgabe des Charters.

Der Gast erfährt seinen tatsächlichen Namen aus `LOBBY_STATE`; eine eigene Nachricht braucht es dafür nicht. Die Lobby zeigt ihm den Unterschied an, damit er sich später im Turnierbaum wiederfindet.

**`seed` ist in `MATCH_START` gestrichen.** Die Simulation ist seit M0-08 zufallsfrei (`03_TECH` §3, `CLAUDE.md` §3.2), und `src/sim/rng.lua` aus dem Modulschnitt wurde nie gebraucht. Ein Feld zu übertragen, das keine Seite benutzt, erzeugt nur die Erwartung, es gäbe Zufall in der Simulation.

**`MATCH_PAUSE` (0x24) ist neu in 1.1.** Fassung 1.0 beschrieb in §12 „Host pausiert das Match, zeigt *Warte auf {Name} … 30 s*", ohne eine Nachricht dafür vorzusehen — der verbleibende Client hätte den Grund seines Stillstands nicht erfahren.

### Discovery-Nachrichten (UDP-Broadcast, separat)

| Typ | Richtung | Inhalt |
|-----|----------|--------|
| `PROBE` (0x70) | Client → 255.255.255.255:21213 und 127.0.0.1:21213 | magic „VLYD", Kopf |
| `ANNOUNCE` (0x71) | Host → Broadcast alle 1 s, **und unicast als Antwort auf `PROBE`** | magic, Kopf, hostId(4), hostName(≤24), lobbyName(≤32), buildHash(≤16), players(1), maxPlayers(1), mode(1: `free`/`tournament`), enetPort(2) |

`hostId` ist die Kennung der **Lobby**, nicht der Maschine, und wird beim Öffnen einmal gezogen. Sie löst ein gemessenes Problem: Ein Host auf demselben Rechner antwortet zweimal — einmal über die Loopback-Adresse, einmal über die LAN-Adresse — und stünde ohne sie zweimal in der Serverliste. Der Browser führt Einträge mit gleicher `hostId` zusammen und bevorzugt dabei `127.0.0.1`: diese Adresse kann nur von einem Host auf demselben Rechner stammen und ist dann der kürzeste Weg.

## 6. Snapshot-Format (69 Byte Nutzlast)

**Diese Liste ist gegen `src/sim/state.lua` erhoben, nicht entworfen.** Fassung 1.0 kodierte fünf Phasen, von denen es zwei nicht gibt, und Satzstände, die der Zustand nicht führt. Ein Encoder, der das nicht merkt, überträgt stillschweigend Unsinn. Wer diese Liste ändert, prüft sie erneut gegen `state.lua` — der Test `tests/snapshot_test.lua` erzwingt das für die Phasen.

```
Feld                    Typ     Bytes   Quelle in state.lua
──────────────────────────────────────────────────────────────────────────
tick                    i4        4     Tickzähler des Hosts (nicht im State)
ballX, ballY            f,f       8     ball.x, ball.y
ballVX, ballVY          f,f       8     ball.vx, ball.vy      (§8, M3-02)
ballRot                 f         4     ball.rotation
blob1X, blob1Y          f,f       8     blobs[1].x, .y
blob2X, blob2Y          f,f       8     blobs[2].x, .y
blob1VY, blob2VY        f,f       8     blobs[n].vy           (M3-01)
blob1Tilt, blob2Tilt    f,f       8     blobs[n].tiltAngle
blob1Cd, blob2Cd        u1,u1     2     blobs[n].cooldownTimer, quantisiert
scoreA, scoreB          u1,u1     2     match.score[1], [2]
phase                   u1        1     match.phase, siehe Tabelle
servingPlayer           u1        1     match.servingPlayer
touchCount              u1        1     rally.touchCount
lastTouchPlayer         u1        1     rally.lastTouchPlayer
flags                   u1        1     siehe unten
ackInputTick            i4        4     zuletzt verarbeiteter Input-Tick des Empfängers
──────────────────────────────────────────────────────────────────────────
                                 69 B  (+3 B Header = 72 B, ENet-Overhead separat)
```

### Phasen

| Wert | Phase | |
|---|---|---|
| 0 | `serve` | Aufschlag steht aus |
| 1 | `play` | Ball ist im Spiel |
| 2 | `gameover` | Satz entschieden |
| 3 | `menu` | kein Match; kommt im Netzspiel nicht vor, ist aber der Anfangswert von `State.new` und deshalb kodierbar |

`fault` und `setover` aus Fassung 1.0 **gibt es nicht**. Ein Fehler ist keine Phase, sondern `rally.faultTimer > 0` während `play` (siehe `flags`). Sätze führt der Zustand nicht: `match.score` ist ein Paar, mehr nicht. Satzzählung ist **kein** Gegenstand von M2 (Entscheidung r0btoshi, 2026-08-12) — sie wäre eine Änderung an `src/sim/`, und die ist im Handoff CC-03 §4 ausgeschlossen.

### `flags`

| Bit | Wert | Bedeutung |
|---|---|---|
| 0 | 1 | `blobs[1].isGrounded` |
| 1 | 2 | `blobs[2].isGrounded` |
| 2 | 4 | `blobs[1].dashTimer > 0` |
| 3 | 8 | `blobs[2].dashTimer > 0` |
| 4–5 | 16/32 | `rally.faultPlayer`, 0 = kein Fehler, 1 = P1, 2 = P2 (`faultTimer > 0`) |
| 6–7 | 64/128 | reserviert, müssen 0 sein |

### Was **nicht** übertragen wird und warum

- **`net`**, **`ball.radius`**: leiten sich aus dem Ruleset ab, das beide Seiten haben (`Step.tick` setzt sie in jedem Tick aus demselben Ruleset).
- **`rally.timer`, `serveTimer`, `ballSide`, `touchCooldown`, `dashGrace`, `input.prev`**: reine Simulationsbuchführung. Der Client simuliert nicht und zeigt nichts davon an.
- **`blob.vx`**: die Neigung wird direkt übertragen, und für die Darstellung ist `vx` sonst ohne Wirkung.

**Die Null wird vor dem Senden begradigt.** IEEE 754 kennt +0 und −0, und die Simulation erzeugt die negative Null beiläufig (`ball.vx = -math.abs(ball.vx) * 0.8` bei `vx = 0`). Gemessen im CI-Lauf 13 (2026-08-12): Unter Windows-x86-64 liefert `-zero` eine negative Null, unter macOS-ARM64 eine **positive** — auf Apple Silicon läuft der Interpreter statt des JIT (§1), und die Arithmetik verhält sich dort anders. Für das Spiel ist das bedeutungslos; für die Prüfsumme aus §9 wäre es ein Fehlalarm in jedem Tick, in dem etwas stillsteht. `snapshot.lua` addiert deshalb einmal `+ 0.0` auf jedes Fließkommafeld. Das ist **kein** Fehler von `love.data.pack`: die Bytes eines vollständigen Snapshots sind auf beiden Plattformen identisch (T-N-07).

**Neigung, Cooldown und Fehlerwurf standen in Fassung 1.0 nicht in der Liste.** Alle drei sind sichtbar: die Neigung ist die Blob-Animation beim Seitwärts-Dash (`02_CODE_AUDIT` §4 — „Blob-Neigung" ist ausdrücklich unveränderlich), der Cooldown ist der rote Balken im HUD, der Fehlerwurf ist die Einblendung „FAULT!". Ohne sie sähe der Client ein anderes Spiel als der Host.

**`blobNCd` ist quantisiert:** `round(cooldownTimer / ruleset.dashCooldown × 255)`, ein Byte. Der HUD-Balken zeichnet genau dieses Verhältnis; ein Float dafür wäre drei Byte für nichts. Auf der Empfängerseite wird zurückgerechnet — der Wert ist Anzeige, keine Simulationsgröße.

**Kosmetische Ereignisse werden nicht übertragen.** Der Client leitet Partikel, Kamera-Shake und Sounds aus Zustandsübergängen zwischen zwei Snapshots ab (Ball war rechts von der Wand, jetzt links + VX-Vorzeichenwechsel → Wandtreffer). Das spart Bandbreite und ist robust gegen Paketverlust. Auslöserkennung gehört in `render/fx.lua`, nicht in die Simulation. **Umgesetzt wird das in M3-02**; in M2 zeigt der Client den Zustand ohne Partikel und ohne Klang.

## 7. Eingabe-Redundanz und Verzögerung

**Redundanz:** Jedes `INPUT`-Paket enthält die Masken der **letzten drei Ticks** (aktueller + 2 vorherige). Bei einem verlorenen Paket rekonstruiert der Host die Lücke aus dem nächsten. Kosten: 2 Byte. Damit sind Einzelpaketverluste vollständig unsichtbar — der übliche Fall im WLAN.

**Fehlender Input:** Kommt bis zum Tick-Zeitpunkt kein Input, wiederholt der Host die letzte bekannte Maske (Repeat-Last). Nicht Null-Input — sonst ruckelt der Blob bei jedem Paketverlust zum Stillstand.

**Input-Verzögerung:** **0 Ticks.** Der Host verarbeitet den Client-Input im nächsten Tick nach Eintreffen. Das ist bei LAN-RTT von 1–2 ms korrekt; eine künstliche Verzögerung („input delay") wäre nur bei Lockstep nötig, um alle Clients synchron zu halten.

**Jitter-Puffer:** Der Host puffert eintreffende Inputs für maximal 2 Ticks, um Reihenfolgevertauschungen aufzulösen. Länger nicht — Latenz ist hier teurer als gelegentliche Vertauschung.

## 8. Client-seitige Darstellung

### Ohne Vorhersage (M2, Baseline)

Der Client rendert den Zustand aus einem **Interpolationspuffer von 2 Ticks (≈33 ms)** in der Vergangenheit. Dadurch sind Bewegungen auch bei Paketjitter flüssig. Gesamtlatenz Tastendruck → Bild: RTT/2 + Tickzeit + 33 ms ≈ **50 ms** bei LAN.

Das ist innerhalb des Erfolgskriteriums aus dem Charter und für ein Spiel dieser Geschwindigkeit spielbar — aber der Client merkt einen Unterschied zum Host.

### Mit Vorhersage (M3)

Der Client simuliert **ausschließlich seinen eigenen Blob** lokal sofort (die Blob-Bewegung ist trivial: horizontale Geschwindigkeit aus Input, Schwerkraft, Boden, Netzgrenze — kein Ballkontakt). Ball, Gegnerblob und Punktestand kommen ausschließlich vom Host.

Bei jedem Snapshot: Position des eigenen Blobs mit der Host-Position vergleichen. Abweichung > 2 px → sanfte Korrektur über 4 Ticks (kein harter Sprung).

**Warum nur der eigene Blob:** Weil die Blob-Bewegung keine Ballkollision enthält, ist sie fehlerfrei vorhersagbar — außer im Moment eines Ballkontakts, und der verändert die Blob-Position nicht. Den Ball vorherzusagen würde Rollback erfordern; das ist der Punkt, an dem die Komplexität explodiert und der Nutzen bei LAN-Latenz gegen null geht.

**Bewusster Verzicht auf Rollback/GGPO-artige Netcode.** Begründung: Bei RTT < 5 ms ist der Vorteil nicht wahrnehmbar, der Implementierungsaufwand aber um ein Vielfaches höher, und Rollback bringt die Determinismus-Anforderung durch die Hintertür wieder herein.

## 9. Desync-Detektor (auch ohne Lockstep sinnvoll)

Der Host berechnet alle 30 Ticks eine Prüfsumme über den Simulationszustand (`love.data.hash("md5", packedState)`, erste 4 Byte) und sendet sie als `CHECKSUM`. Der Client, der eine eigene Vorhersage fährt, vergleicht sie mit seiner vorhergesagten eigenen Blob-Position.

Das erkennt nicht Desync im Lockstep-Sinne (den es nicht geben kann), sondern **Vorhersagefehler und Protokollfehler**: falsch interpretierte Snapshots, Endianness-Probleme, Ruleset-Abweichungen.

**Voraussetzung, ohne die der Detektor Unsinn meldet:** Er darf nur über Werte laufen, die auf beiden Plattformen bitgleich entstehen. Das Vorzeichen der Null gehört nicht dazu (§6) — es ist in `snapshot.lua` begradigt, bevor etwas gesendet wird. Wer den Detektor in M3-03 baut, prüft das erneut, statt es anzunehmen. In der Entwicklungsphase wird jede Abweichung geloggt; in Release-Builds erscheint sie als stiller Zähler im Debug-Overlay (F3).

## 10. Ruleset-Abgleich

Beim `MATCH_START` sendet der Host `rulesetHash` — **acht ASCII-Hexstellen aus `Ruleset.hash`, djb2 über die kanonische Form** (ADR-016, nicht MD5). Der Client rechnet den Hash über das Ruleset, das er per `RULESET_FULL` empfangen hat, und vergleicht die Zeichenketten. Bei Abweichung: Match wird nicht gestartet, Klartextfehler.

Der Hash erkennt abweichende Rulesets. Er sichert nichts ab, und er soll es nicht — im LAN gibt es kein Angreifermodell, gegen das ein stärkerer Hash in derselben `.love` helfen würde.

**Kanonische Serialisierung** heißt: Schlüssel alphabetisch sortiert, Zahlen mit `%.6f` formatiert. Ohne diese Festlegung liefert `pairs()` je nach Lua-Instanz unterschiedliche Reihenfolgen und damit unterschiedliche Hashes für identische Rulesets — ein Fehler, der sich erst am Partyabend zeigt.

Zusätzlich wird `buildHash` (Hash über alle `.lua`-Dateien, zur Buildzeit erzeugt) verglichen. Bei Abweichung nur **Warnung**, kein Abbruch — sonst blockiert ein kosmetischer Patch das ganze Turnier.

## 11. Zero-Config Discovery

```
Client:  Socket A auf einen FLUECHTIGEN Port ("*", 0)  -- fragen und Antwort empfangen
         Socket B auf 21213, falls frei                -- Ankuendigungen mithoeren
         beide mit broadcast = true, reuseaddr = true

         PROBE an ALLE Rundrufziele senden, alle 2 s wiederholen
         Antworten auf BEIDEN Sockets sammeln
         Liste nach 5 s ohne ANNOUNCE bereinigen

Host:    UDP-Socket auf 21213, setoption("reuseaddr", true)
         ANNOUNCE an ALLE Rundrufziele, alle 1 s
         auf PROBE sofort mit ANNOUNCE an die Absenderadresse antworten (unicast)

Rundrufziele (beide Rollen):
         255.255.255.255      eingeschraenkter Rundruf
         <eigenes Netz>.255   z. B. 192.168.1.255, aus der eigenen Adresse
         127.0.0.1            derselbe Rechner
```

**Der suchende Client bindet 21213 nicht.** Fassung 1.0 sah das vor; damit können Host und Client nicht auf demselben Rechner laufen — genau der Aufbau, mit dem M2-10 das Netzspiel reproduzierbar testet, und genau der Aufbau, in dem jemand am Partyabend „mal kurz schaut, ob die Liste geht". Der Host antwortet deshalb auf `PROBE` **unicast an die Absenderadresse**; die Antwort landet auf dem flüchtigen Port des Fragenden. Das periodische Broadcast-`ANNOUNCE` bleibt, es bedient passive Zuhörer und macht die Ersterkennung unabhängig vom Probe-Takt.

**Das `PROBE` geht zusätzlich an `127.0.0.1`.** Ob eine Broadcast-Nachricht auf demselben Rechner zurückkommt, hängt am Betriebssystem; das zweite Paket kostet 30 Byte und macht den lokalen Fall unabhängig davon.

### Zwei Empfangswege beim Suchenden, zwei Rundrufziele beim Sender

Beides ist aus dem D2-Lauf vom 2026-08-12 hervorgegangen. Befund: **Ein Windows-Rechner fand den Mac als Host nicht; umgekehrt klappte es sofort.** Aus denselben Messungen folgt, dass der Rundruf des Macs den Windows-Rechner sehr wohl erreicht — in der umgekehrten Rollenverteilung hat der Windows-Rechner ihn als Host beantwortet.

- **Der Suchende hört auf zwei Sockets.** Fassung 1.1 ließ ihn nur auf einem flüchtigen Port lauschen; damit war er allein auf die Unicast-Antwort angewiesen. Der zweite Socket auf 21213 nimmt die Ankündigung entgegen, die der Host ohnehin jede Sekunde in die Runde schickt. Der Bind darf scheitern (etwa, wenn auf demselben Rechner schon eine Lobby offen ist) — dann bleibt es beim flüchtigen Port.
- **Jeder Rundruf geht zusätzlich an die Rundrufadresse des eigenen Netzes.** `255.255.255.255` ist an keine Schnittstelle gebunden; die Auswahl trifft die Routentabelle. Auf einem Rechner mit VPN, Hyper-V, VirtualBox oder WSL stehen dort mehrere Kandidaten, und das Paket verlässt die falsche Schnittstelle. Die abgeleitete Adresse (`192.168.1.155` → `192.168.1.255`) ist an ein Netz gebunden und wird richtig zugeordnet. Angenommen wird ein /24-Netz; wer in einem größeren spielt, hat den eingeschränkten Rundruf und die IP-Eingabe als Rückfallebenen.

**Die Bake läuft auch während eines Matches weiter.** Fassung 1.1 sagte das nicht ausdrücklich, und die Umsetzung tat es nicht: Die Bake lag in der Lobbyszene, und die bekommt unterhalb der Spielszene keinen Takt mehr. Ein Gast, dem mitten im Satz die Verbindung abriss, fand den Host deshalb nicht mehr in der Liste und musste die IP abtippen — **genau im Wiedereinstieg nach §12 ist die Discovery am nötigsten.**

**Die Sockets werden mit `socket.udp4()` erzeugt, nicht mit `socket.udp()`.** Das ist gemessen, nicht vorsorglich: LuaSocket 3.0 — die Fassung in LÖVE 11.5 — liefert bei `socket.udp()` einen **IPv6**-Socket. Ein `sendto` an `255.255.255.255` scheitert darauf mit „Der angegebene Host ist unbekannt", und die Discovery findet schlicht nichts. IPv4-Broadcast gibt es unter IPv6 nicht; das Gegenstück wäre Multicast an `ff02::1` und damit eine andere Baustelle. Für ein LAN-Party-Segment ist IPv4 die richtige und einzige Wahl (Annahme A1 im Charter).

Beides mit `settimeout(0)`, gepollt in `love.update`. Kein Thread nötig — die Datenmengen sind winzig, und `t.modules.thread` ist in `conf.lua` ausgeschaltet.

**Format beider Nachrichten:** dieselben 3 Header-Byte wie bei ENet (`protoVersion`, `msgType`, `flags`), damit ein fremdes Paket auf demselben Port nicht als Lobby erscheint. `PROBE` = 0x70, `ANNOUNCE` = 0x71. Davor steht die Magic `VLYD` (4 Byte, `CLAUDE.md` §1). Wer eines der beiden nicht liefert, wird still verworfen.

### Bekannte Grenzen (und die Pflicht-Fallbacks)

| Problem | Wirkung | Fallback |
|---------|---------|----------|
| Windows-Firewall fragt beim ersten Start nach Freigabe; wird sie weggeklickt oder ist der Rechner in einem „öffentlichen" Netzwerkprofil, kommt kein Broadcast durch | Discovery findet nichts | **Manuelle IP-Eingabe ist Pflichtfeature, nicht optional.** Host zeigt seine LAN-IP groß in der Lobby an |
| WLAN-Access-Points mit Client-Isolation blocken Broadcast zwischen Clients | Discovery findet nichts | Kabel empfehlen; Runbook §3 |
| Mehrere Subnetze / VLANs | Broadcast überschreitet Subnetzgrenzen nicht | Manuelle IP; ein gemeinsames Segment ist Annahme A1 im Charter |
| Zwei Hosts starten gleichzeitig eine Lobby | Zwei Einträge in der Liste | Kein Fehler — Lobbyname + Hostname anzeigen, Nutzer wählt |

**Designregel:** Die IP-Eingabe darf nicht in einem Untermenü versteckt sein. Sie steht in der Serverliste als letzter Eintrag: „Direkt verbinden (IP eingeben)". Das kostet nichts und rettet den Abend.

## 12. Trennung, Reconnect, Abbruch

| Ereignis | Verhalten |
|----------|-----------|
| Client verliert Verbindung während eines Matches | Host pausiert das Match, zeigt „Warte auf {Name} … 30 s". Client kann sich mit derselben `clientId` reconnecten und steigt in den laufenden Zustand ein |
| Timeout nach 30 s | Match endet, Sieg für den verbleibenden Spieler (`reason = disconnect`). Im Turnier wird das als Walkover gewertet (`05_TOURNAMENT` §6) |
| Host verliert Verbindung / stürzt ab | Match verloren. Clients kehren in die Serverliste zurück. Im Turnier: Host-Recovery aus der Zustandsdatei, siehe `05_TOURNAMENT` §7 |
| Client verlässt die Lobby | Slot wird frei, Lobby läuft weiter |
| ENet-Peer-Timeout | Auf 5000 ms setzen (Default 30 s ist für LAN viel zu träge und lässt tote Slots stehen) |

## 13. Offene technische Punkte

| ID | Punkt | Zu klären in |
|----|-------|--------------|
| N-01 | Verhalten bei WLAN mit RTT > 30 ms: Reicht Vorhersage des eigenen Blobs, oder braucht der Client eine Ball-Extrapolation? | M3, Playtest über WLAN |
| N-02 | Spectator-Snapshot-Rate: 30 Hz mit Interpolation testen, ob am Beamer sichtbar schlechter | M5 |
| N-03 | Ob `love.data.pack` mit `f` (float32) auf beiden Plattformen bitidentisch schreibt/liest | **BEANTWORTET, M2-01.** Ja. T-N-07 vergleicht einen vollständigen 72-Byte-Snapshot gegen eine im Test stehende Referenz; der Fall läuft auf `windows-latest` und `macos-latest` durch. **Eine Ausnahme, gefunden statt vermutet:** das Vorzeichen der Null entsteht in der Lua-Arithmetik unterschiedlich (§6), nicht beim Packen. Es wird vor dem Senden begradigt |
| N-04 | Ob ENet auf macOS ohne zusätzliche Firewall-Freigabe funktioniert (ausgehende Verbindungen ja, eingehende als Host?) | M2, Test auf frischem Mac — **bleibt offen**, ein CI-Image beantwortet das nicht |
| N-05 | Ob der UDP-Broadcast auf einem Windows-Rechner mit „öffentlichem" Netzwerkprofil überhaupt hinausgeht, oder ob die Firewall ihn ohne Rückfrage verwirft | M2-04, Test auf zwei Rechnern (D2) |
