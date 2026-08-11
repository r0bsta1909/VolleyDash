# 04 — Netcode-Spezifikation

**Version:** 1.0 · **Stand:** 2026-08-11 · **Bezug:** ADR-002, ADR-003

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
| Client → Host: InputFrame | 8 B (Header 7 + Maske 1) | 60/s | 0,5 KB/s |
| Host → Client: Snapshot | 48 B + ENet-Overhead ≈ 76 B | 60/s | 4,6 KB/s |
| Host → Spectator | wie Client | 30/s | 2,3 KB/s |

Bei 4 parallelen Matches plus 8 Zuschauern liegt die Gesamtlast im zweistelligen KB/s-Bereich. Auf 100-MBit-LAN irrelevant, auf WLAN unkritisch.

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

### Nachrichtentypen

| ID | Name | Richtung | Kanal | Nutzlast |
|----|------|----------|-------|----------|
| 0x01 | `HELLO` | C→H | 0 | buildHash(16), playerName(≤24), clientId(4) |
| 0x02 | `WELCOME` | H→C | 0 | slot(1), lobbyState, rulesetHash(16) |
| 0x03 | `REJECT` | H→C | 0 | reasonCode(1), text(≤64) |
| 0x10 | `LOBBY_STATE` | H→C | 0 | slots[], readyFlags, hostSettings |
| 0x11 | `SET_READY` | C→H | 0 | ready(1) |
| 0x12 | `RULESET_FULL` | H→C | 0 | vollständiges Ruleset als JSON |
| 0x20 | `MATCH_START` | H→C | 0 | matchId(4), startTick(4), rulesetHash(16), seed(4), slotsAssignment |
| 0x21 | `INPUT` | C→H | 2 | tick(4), masks(3) — siehe §7 |
| 0x22 | `SNAPSHOT` | H→C | 1 | siehe §6 |
| 0x23 | `MATCH_END` | H→C | 0 | matchId(4), scoreA(1), scoreB(1), reason(1) |
| 0x30 | `SPECTATE_REQ` | C→H | 0 | matchId(4) |
| 0x40 | `TOURNAMENT_STATE` | H→C | 0 | JSON, siehe `05_TOURNAMENT` |
| 0x50 | `PING` / 0x51 `PONG` | beidseitig | 0 | timestamp(4) |
| 0x60 | `CHECKSUM` | H→C | 0 | tick(4), hash(4) — Desync-Detektor, §9 |

### Discovery-Nachrichten (UDP-Broadcast, separat)

| Typ | Richtung | Inhalt |
|-----|----------|--------|
| `PROBE` | Client → 255.255.255.255:21213 | magic „VLYD", protoVersion |
| `ANNOUNCE` | Host → Broadcast, alle 1 s | magic, protoVersion, hostName, lobbyName, players/maxPlayers, mode (`free`/`tournament`), buildHash, enetPort |

## 6. Snapshot-Format (48 Byte)

```
Feld              Typ     Bytes   Anmerkung
─────────────────────────────────────────────────────────────
tick              i4        4     Simulationstick des Hosts
ballX, ballY      f,f       8
ballVX, ballVY    f,f       8
ballRot           f         4
blob1X, blob1Y    f,f       8
blob2X, blob2Y    f,f       8
blob1VY,blob2VY   f,f       8     für Render-Interpolation nötig
scoreA, scoreB    u1,u1     2
setsA, setsB      u1,u1     2
phase             u1        1     0 serve, 1 play, 2 fault, 3 setover, 4 matchover
servingPlayer     u1        1
touchCount        u1        1
lastTouchPlayer   u1        1
flags             u1        1     bit0 blob1Grounded, bit1 blob2Grounded,
                                  bit2 blob1Dashing,  bit3 blob2Dashing
ackInputTick      i4        4     zuletzt vom Host verarbeiteter Input-Tick des Empfängers
─────────────────────────────────────────────────────────────
                            61 B  (+3 B Header = 64 B, ENet-Overhead separat)
```

Die Zahl korrigiert die Überschlagsrechnung nach oben auf 64 B — an der Bandbreitenaussage ändert das nichts.

**Kosmetische Ereignisse werden nicht übertragen.** Der Client leitet Partikel, Kamera-Shake und Sounds aus Zustandsübergängen zwischen zwei Snapshots ab (Ball war rechts von der Wand, jetzt links + VX-Vorzeichenwechsel → Wandtreffer). Das spart Bandbreite und ist robust gegen Paketverlust. Auslöserkennung gehört in `render/fx.lua`, nicht in die Simulation.

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

Das erkennt nicht Desync im Lockstep-Sinne (den es nicht geben kann), sondern **Vorhersagefehler und Protokollfehler**: falsch interpretierte Snapshots, Endianness-Probleme, Ruleset-Abweichungen. In der Entwicklungsphase wird jede Abweichung geloggt; in Release-Builds erscheint sie als stiller Zähler im Debug-Overlay (F3).

## 10. Ruleset-Abgleich

Beim `MATCH_START` sendet der Host `rulesetHash` (MD5 über das kanonisch serialisierte Ruleset). Der Client vergleicht mit dem Hash des Rulesets, das er per `RULESET_FULL` empfangen hat. Bei Abweichung: Match wird nicht gestartet, Klartextfehler.

**Kanonische Serialisierung** heißt: Schlüssel alphabetisch sortiert, Zahlen mit `%.6f` formatiert. Ohne diese Festlegung liefert `pairs()` je nach Lua-Instanz unterschiedliche Reihenfolgen und damit unterschiedliche Hashes für identische Rulesets — ein Fehler, der sich erst am Partyabend zeigt.

Zusätzlich wird `buildHash` (Hash über alle `.lua`-Dateien, zur Buildzeit erzeugt) verglichen. Bei Abweichung nur **Warnung**, kein Abbruch — sonst blockiert ein kosmetischer Patch das ganze Turnier.

## 11. Zero-Config Discovery

```
Client:  UDP-Socket auf 21213 binden, setoption("broadcast", true)
         PROBE an 255.255.255.255:21213 senden, alle 2 s wiederholen
         Antworten sammeln, Liste nach Ablauf von 5 s ohne ANNOUNCE bereinigen

Host:    UDP-Socket auf 21213
         ANNOUNCE an 255.255.255.255:21213 alle 1 s
         auf PROBE sofort mit ANNOUNCE antworten (schnellere Ersterkennung)
```

Beides mit `settimeout(0)`, gepollt in `love.update`. Kein Thread nötig — die Datenmengen sind winzig.

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
| N-03 | Ob `love.data.pack` mit `f` (float32) auf beiden Plattformen bitidentisch schreibt/liest — praktisch sicher, aber vor M2 einmal explizit verifizieren | M2, Testfall T-N-07 |
| N-04 | Ob ENet auf macOS ohne zusätzliche Firewall-Freigabe funktioniert (ausgehende Verbindungen ja, eingehende als Host?) | M2, Test auf frischem Mac |
