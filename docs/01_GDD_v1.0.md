# 01 — Game Design Document: VOLLEY DASH

**Version:** 1.0 (ersetzt den Ausgangsentwurf) · **Stand:** 2026-08-11

---

## 1. High Concept

Ein 2D-Arcade-Volleyball für den LAN-Abend. Zwei Blobs, ein Netz, ein Ball, drei Tasten. Das Original-Spielgefühl ist **fixierter Standard**, nicht Option. Alles Neue — Modi, Mutatoren, Smash, Dash — ist zuschaltbar und in der Voreinstellung **aus**.

Der eigentliche Produktwert liegt nicht im Gameplay (das ist 25 Jahre alt und erprobt), sondern in **Reibungsfreiheit**: von der ZIP zum laufenden Turnier in unter zwei Minuten.

## 2. Zielspieler & Nutzungskontext

| Aspekt | Beschreibung |
|--------|--------------|
| Primär | 8–16 Erwachsene auf einer privaten LAN-Party, gemischte Skill-Level, gemischte Betriebssysteme |
| Sitzung | 3–8 Minuten pro Satz, 20–40 Minuten pro Turnierteilnahme |
| Aufmerksamkeit | Geteilt. Es wird nebenher geredet, getrunken, zugeschaut |
| Vorwissen | Ein Teil kennt das Original aus der Schulzeit, ein Teil gar nicht |
| Lernkurve | Regeln müssen in ≤ 15 Sekunden Zuschauen verstanden sein |

**Konsequenz für das Design:** Jede Mechanik, die man erklären muss, gehört hinter einen Schalter. Der Standard muss beim Zuschauen selbsterklärend sein.

## 3. Vanilla-Regelwerk (Preset `Classic`) — verbindlich

Das ist die Referenz. Abweichungen sind Bugs, keine Geschmacksfragen.

### 3.1 Regelmatrix

| Regel | Wert | Quelle / Anmerkung |
|-------|------|--------------------|
| Punktesystem | Side-out (Rally-Punkt **nur** für den Aufschläger) | <cite index="53-1">Punkte können nur vom aufschlagenden Spieler erzielt werden; wer nicht aufschlägt, gewinnt bei einem Fehler des Gegners lediglich das Aufschlagrecht.</cite> |
| Satzgewinn | **15 Punkte UND 2 Punkte Vorsprung** | <cite index="53-1">Das Spiel endet, wenn ein Spieler 15 oder mehr Punkte erreicht und zusätzlich zwei Punkte Vorsprung hat.</cite> ⚠️ Prototyp verletzt das (Blocker B-05) |
| Fehler 1 | Ball berührt eigenen Boden | <cite index="53-1">Der Ball berührt den Boden im eigenen Feld.</cite> |
| Fehler 2 | Mehr als 3 Berührungen in Folge (Aufschlag zählt mit) | <cite index="53-1">Ein Spieler berührt den Ball mehr als dreimal hintereinander; der Aufschlag zählt dabei als Berührung.</cite> |
| Mehrfachberührung | **Erlaubt** bis 3 — der Blob darf sich selbst zuspielen | <cite index="53-1">Da pro Feldseite nur ein Spieler steht, darf dieser den Ball mehrfach hintereinander berühren — anders als im echten Volleyball.</cite> |
| Seitenwände | Ball prallt elastisch ab, **regelkonform und taktisch nutzbar** | <cite index="53-1">Die Bildschirmränder wirken als unsichtbare Wand, von der der Ball abprallt; das zu nutzen ist vollkommen legal.</cite> |
| Steuerung | 3 Tasten: links, rechts, springen | <cite index="42-1">Im Original steuern Spieler ihre Blobs ausschließlich über links/rechts/springen; es gibt keine direkte Ballmanipulation — Treffer entstehen allein aus Positionierung und Timing.</cite> |
| Ballkontakt | Passiv über Kollision („Kopfball"), keine Schlagtaste | <cite index="53-1">Die armlosen Blobs bewegen sich links/rechts, springen und spielen den Ball mit dem „Kopf" — vergleichbar mit einem Kopfball.</cite> |
| Netz | Undurchdringlich für Blob und Ball von der Seite; Netzkante ist Kollisionsobjekt | Original |
| Dash / Hechtsprung | **AUS** | Nicht im Original |
| Active Spike / Smash | **AUS** | Nicht im Original |
| Speed-Scaling | **AUS** | Nicht im Original |

### 3.2 Präzisierungen, die das Original offenlässt

Diese Punkte müssen einmal entschieden und dann eingefroren werden, weil sie das Spielgefühl bestimmen und über Netzwerk konsistent sein müssen:

| # | Frage | Festlegung v1.0 | Begründung |
|---|-------|-----------------|------------|
| P1 | Zählt eine Netzberührung als Berührung? | Nein | Sonst werden Netzroller zu unbeabsichtigten Fehlern |
| P2 | Wird der Berührungszähler beim Seitenwechsel des Balls zurückgesetzt? | Ja, sobald der Ballmittelpunkt die Netzachse überquert | Entspricht Prototypverhalten, ist beobachtbar |
| P3 | Was passiert bei Ball auf Netzoberkante? | Ball prallt nach der zuletzt gültigen horizontalen Richtung ab, kein Zufall | Anti-Zufalls-Doktrin: kein Coin-Flip in einer Turnier-Rallye |
| P4 | Aufschlagverzögerung | Fixe 1,0 s (nicht zufällig!) | Prototyp nutzt `1.0 + random()*0.5`. Im Turnier ist ein zufälliges Timingfenster unfair. Blocker B-06 |
| P5 | Time-out ohne Ballkontakt | Nach 30 s Rallye ohne Punkt: Punkt an den Nicht-Aufschläger (Aufschlagwechsel) | Verhindert Endlos-Rallyes zwischen zwei defensiven Spielern; Turnierzeitplanung |
| P6 | Max. Ballgeschwindigkeit | Hart gedeckelt (Prototyp: 1400 px/s) | Verhindert Tunneling durch das Netz bei fixem Timestep |

### 3.3 Feldgeometrie (fixiert, ADR-004)

Das logische Spielfeld ist **800 × 600 Einheiten**, unabhängig von der Fenstergröße. Breitere Fenster erhalten Letterboxing (Pillarbox) links/rechts, keine Feldverbreiterung.

```
0                        400                       800
├─────────────────────────┬─────────────────────────┤
│                         █                         │
│      Feld Spieler 1     █      Feld Spieler 2     │   Netz: x=400, Höhe 160
│                         █                         │
└─────────────────────────┴─────────────────────────┘  Boden Blob y=500 / Ball y=520
```

**Warum das nicht verhandelbar ist:** Im Prototyp berechnet `updateWorldDimensions()` die Feldbreite aus der Fensterbreite. Zwei Spieler mit unterschiedlichem Fenster spielen dann auf unterschiedlich breiten Feldern — die Wandabpraller liegen anderswo, der Bot rechnet mit falschen Grenzen, und jedes Netzwerkspiel divergiert sofort. Siehe Blocker B-01.

## 4. Spielmodi

| Modus | Spieler | Meilenstein | Beschreibung |
|-------|---------|-------------|--------------|
| **Local 1v1** | 2 an einem Gerät | ✅ vorhanden | WASD vs. HUKJ, oder Gamepad |
| **VS Bot** | 1 | ✅ vorhanden | 3 Stufen (siehe §6) |
| **LAN 1v1** | 2 an zwei Geräten | M2 | Kern des Projekts |
| **Turnier** | 4–32 | M4 | Siehe `05_TOURNAMENT_SPEC` |
| **Spectator** | beliebig | M5 | Beobachter ohne Eingriff |
| **Beamer** | 1 dedizierter Client | M5 | Bracket + Live-Match im Vollbild |
| King of the Hill | n | M6 | Gewinner bleibt, nächster rückt nach |
| 2v2 | 4 | M6 | Verbreitertes Feld, 2 Blobs/Seite |

### 4.1 King of the Hill — Designnotiz

KotH ist auf einer LAN-Party der ehrlich beste Modus (kein Warten, kein Bracket, jeder darf sofort), wird aber oft falsch gebaut. Zwei Fallen:

- **Der Champion ermüdet.** Nach 6 Siegen in Folge spielt er schlechter, das Ranking misst Ausdauer statt Können. → Zwangsrotation nach 5 Siegen (Champion geht ans Ende der Schlange, behält seinen Punktestand).
- **Die Schlange stirbt.** Wer als 12. ansteht, ist 20 Minuten raus. → Satzlänge in KotH auf 7 Punkte (kein 2-Punkte-Vorsprung, Sudden Death bei 7:7).

KotH ist **kein Vanilla** und läuft nur als eigenes Preset.

## 5. Mutatoren (alle standardmäßig AUS)

Aktivierbar ausschließlich in der Lobby durch den Host, **gesperrt während eines laufenden Matches**, und mit dem Ruleset-Hash mitversendet (siehe `04_NETCODE` §6).

| Mutator | Wirkung | Testbare Verhaltenserwartung | Status |
|---------|---------|------------------------------|--------|
| **Active Spike** | Vierte Taste erlaubt in der Luft einen Timing-Schmetterball | Rallye-Länge sinkt um ≥ 30 %; Anteil der Punkte durch Direktangriff steigt | ✅ im Prototyp |
| **Dash** | Hechtsprung zur Seite mit Cooldown | Anteil geretteter Bälle (die sonst aufgekommen wären) steigt messbar; Rallye-Länge steigt | ✅ im Prototyp |
| **Speed-Scaling** | Ball wird pro Ballwechsel schneller | Rallyes > 12 Ballwechsel werden seltener; Punkt fällt schneller | ⚙️ Flag vorhanden, Logik prüfen |
| **Multi-Ball** | Zweiter Ball nach 10 s Rallye | Erfordert Regelentscheidung: Punkt bei erstem Bodenkontakt beliebigen Balls? → **Ja**, Rallye endet sofort | M6 |
| **Gravity Shift** | Schwerkraft für Ball und Blob skalierbar | Sprunghöhe und Hangtime steigen; erwartet: mehr Luftduelle am Netz | M6 |

### 5.1 Presets — die Startauswahl

Das Spiel heißt nach einem Mutator, der in Vanilla aus ist. Damit der Name eingelöst wird, ohne die Vanilla-Doktrin zu verwässern, gibt es beim Start **zwei gleichwertige Presets** statt eines Standards mit Optionen darunter:

| Preset | Dash | Smash | Speed-Scaling | Satzlänge | Rolle |
|--------|------|-------|---------------|-----------|-------|
| **Classic** | – | – | – | 15 + 2 Vorsprung | Die Referenz. Original-Regelwerk, unverhandelbar |
| **Volley Dash** | ✓ | ✓ | – | 15 + 2 Vorsprung | Die Hausvariante. Namensgebend, schneller, mehr Rettungen |
| Quick | ✓ | ✓ | – | 7, kein Deuce | Für King of the Hill und Warteschlangen |
| Custom | frei | frei | frei | frei | Live-Tweaker, offline/Host |

**Beide oberen Presets sind in der Lobby erste Wahl, nebeneinander, ohne Vorbelegung eines „richtigen".** Der Turnier-Host entscheidet pro Turnier, welches gilt — und die Entscheidung steht sichtbar im Bracket, damit später niemand behauptet, unter anderen Regeln gespielt zu haben.

**Was das *nicht* aufweicht:** `Classic` bleibt bitgenau das Original. Kein Kompromiss-Preset dazwischen, keine „Classic+"-Variante. Sobald es drei Abstufungen gibt, weiß niemand mehr, was Vanilla war.

**Regel für neue Mutatoren:** Ein Mutator wird nur aufgenommen, wenn (a) die erwartete Verhaltensänderung vorab benannt ist und (b) ein Playtest sie widerlegen könnte. Ein Mutator, dessen Wirkung sich nicht in einer Zahl (Rallye-Länge, Punkte pro Minute, Anteil Netzduelle) zeigt, ist Dekoration und fliegt raus.

## 6. Bot-Design

Der Bot bleibt in v1.0 funktional wie im Prototyp, wird aber architektonisch entkoppelt (siehe `03_TECH` §4): Er erzeugt **denselben Input-Struct** wie ein Mensch oder ein Netzwerkclient und läuft ausschließlich auf dem Host.

| Stufe | Reaktionsverzögerung | Ziel-Jitter | Dash | Smash | Zielgruppe |
|-------|---------------------|-------------|------|-------|-----------|
| 1 Easy | 0,45 s | ±70 px | – | – | Erstkontakt, Kinder |
| 2 Medium | 0,20 s | ±25 px | – | ✓ | Gelegenheitsspieler |
| 3 Hard | 0,04 s | ±4 px | ✓ | ✓ | Aufwärmen vor dem Turnier |

**Offene Designfrage (nicht Blocker):** Der Bot nutzt derzeit eine exakte Flugbahnvorhersage und wird über Jitter + Reaktionszeit künstlich verschlechtert. Das erzeugt auf Stufe 1 ein „dummes, aber übermenschlich informiertes" Verhalten, das sich unnatürlich anfühlt. Alternative für M6: Vorhersagehorizont begrenzen (Bot simuliert nur 0,6 s statt 2,5 s voraus) statt Jitter aufzuaddieren. Zu prüfen im Playtest — Falsifikation: Wenn Testspieler den Unterschied blind nicht erkennen, bleibt Jitter.

## 7. Steuerung

| Aktion | P1 Tastatur | P2 Tastatur (lokal) | Gamepad |
|--------|-------------|---------------------|---------|
| Links | A | H | D-Pad / Stick links |
| Rechts | D | K | D-Pad / Stick rechts |
| Springen | W | U | A / Kreuz |
| Smash (Mutator) | S | J | X / Quadrat |
| Dash (Mutator) | Doppeltipp A/D | Doppeltipp H/K | LB/RB |

**Anforderungen ab M0:**
- Belegung frei konfigurierbar und persistent (fehlt im Prototyp: „Controls [WIP]").
- Gamepad-Hotplug: ein während des Spiels eingestecktes Pad wird erkannt.
- **Ein Gerät = ein Spieler-Slot.** Im LAN-Modus wird die zweite lokale Belegung deaktiviert, sonst kann ein Spieler beide Blobs steuern.

## 8. Präsentation

Bleibt wie im Prototyp — die visuelle Sprache (Partikel, Kamera-Shake, Blob-Neigung beim Dash, Schatten als Höhenanzeige, Ball-Indikator am oberen Bildrand) funktioniert und ist für Zuschauer am Beamer lesbar. Keine Überarbeitung in v1.0.

**Zwei Ergänzungen für den Turnierbetrieb:**
- **Spielernamen statt Slot-Nummern** überall, inkl. Bracket und Beamer. Namenspool bleibt als Fallback, freie Eingabe kommt dazu.
- **Match-Kontext im HUD:** „Viertelfinale · Satz 2 · Best-of-3". Ohne das weiß am Beamer niemand, was er sieht.

## 9. Audio

Unverändert (Sprung, Dash, Wandtreffer, Pfiff). **Ergänzung:** Der Beamer-Client braucht eine eigene Lautstärkeeinstellung, sonst übertönt der Beamer die Spieler oder umgekehrt.

## 10. Änderungshistorie

| Version | Datum | Änderung |
|---------|-------|----------|
| Entwurf | — | Ausgangs-GDD (Lockstep, variable Feldbreite, Beamer-Auto-Regie im Scope) |
| 1.0 | 2026-08-11 | Vanilla-Regelmatrix belegt und verbindlich gemacht; 2-Punkte-Vorsprung ergänzt; Feld fixiert; Lockstep gestrichen (ADR-002); Auto-Regie, Multi-Ball, Gravity Shift, 2v2, KotH nach M6; Testbarkeitskriterium für Mutatoren eingeführt; Präzisierungen P1–P6 |
