# 05 — Spezifikation: Integrierter Turniermodus

**Version:** 1.0 · **Stand:** 2026-08-11 · **Meilenstein:** M4

---

## 1. Zielverhalten

Ein Turnier auf einer LAN-Party scheitert in der Praxis nie an der Bracket-Logik, sondern an vier Dingen: Jemand ist gerade auf dem Klo. Jemandes Laptop stürzt ab. Jemand kommt eine Runde zu spät dazu. Und niemand weiß, wer als nächstes dran ist.

**Diese Spezifikation ist danach ausgelegt, nicht nach Turnierformat-Vollständigkeit.** Ein Turniersystem, das Swiss mit Buchholz kann, aber bei einem Absturz das Bracket verliert, ist wertlos. Ein System, das nur Single Elimination kann, aber jede Störung übersteht, funktioniert.

**Erwartetes beobachtbares Verhalten:** Der Turnierleiter muss während des Turniers **null** manuelle Eingriffe machen — außer bei einem No-Show. Falsifikation im Playtest: Wird bei einem 8er-Turnier mehr als einmal manuell eingegriffen, ist die Automatik unzureichend.

## 2. Dimensionierung

**Entscheidung Q-03: variabel, Auslegungspunkt 20 Teilnehmer.** Das System muss 4 bis 32 abdecken, wird aber gegen 20 optimiert und getestet.

| Größe | Wert | Anmerkung |
|-------|------|-----------|
| Teilnehmer | 4 – 32, **Auslegung 20** | Bracket muss beliebige Zahlen verkraften, nicht nur Zweierpotenzen |
| Parallele Matches | **3 – 4, konfigurierbar** | Bei 20 Teilnehmern nicht optional — siehe Rechnung unten |
| Satzlänge | Best-of-1 (Gruppe und Viertelfinale) / **Best-of-3 ab Halbfinale** | Konfigurierbar über `bestOfDefault` / `bestOfFinals` |
| Erwartete Dauer bei 20 | **≈ 90 min** bei 4 parallelen Matches | Basis: Satz ≈ 4 min inkl. Wechsel |

### Warum 20 Teilnehmer die Architektur ändern

| Ablauf | Matches | Seriell (1 parallel) | Bei 4 parallel |
|--------|---------|----------------------|----------------|
| 4 Gruppen à 5, Round Robin | 40 | 160 min | **40 min** |
| Achtelfinale entfällt, 8er K.o. + Spiel um Platz 3 | 8 (teils Bo3) | 45 min | **25 min** |
| Summe inkl. Übergängen | 48 | **≈ 3,5 h** | **≈ 90 min** |

**Berichtigung 2026-08-13 (vor M4-02).** Die Zeile „Satzlänge" widersprach dem Kommentar an `bestOfFinals` im Datenmodell §4: einmal „ab Viertelfinale", einmal „ab Halbfinale". Verbindlich ist **ab Halbfinale**, §4 behält recht. Grund: Bei 20 Teilnehmern spielt das K.o. acht Matches; Best-of-3 schon im Viertelfinale legt bis zu vier zusätzliche Sätze auf den kritischen Pfad, und die 90-Minuten-Rechnung dieses Abschnitts ist ohnehin knapp kalkuliert. Ab Halbfinale betrifft Best-of-3 vier Matches (zwei Halbfinals, Finale, Spiel um Platz 3) — dort, wo die Länge sportlich etwas wert ist. Wer es anders will, stellt `bestOfFinals` um; die Grenze selbst ist Konfiguration, nicht Code.

**Konsequenz:** Bei 20 Teilnehmern ist ein serielles Turnier praktisch nicht durchführbar — nach drei Stunden ist die Party woanders. Parallele Matches mit verteilten Match-Hosts (Backlog-Punkt M4-09) rücken damit von einer Ausbaustufe auf den **kritischen Pfad von M4**. Das ist die einzige Priorisierungsänderung, die Q-03 auslöst, aber eine wesentliche.

**Zweite Konsequenz — Hardware:** 4 parallele Matches bedeuten 8 gleichzeitig spielende Rechner. Bei 20 Gästen mit eigenem Laptop unproblematisch; falls Geräte geteilt werden, ist die reale Parallelität durch Hardware und nicht durch Software begrenzt. Der Scheduler muss deshalb mit weniger parallelen Matches als konfiguriert umgehen können, ohne zu blockieren.

**Dritte Konsequenz — ADR-008 rückt an seinen Revisionsauslöser.** Bei 4 parallelen Matches am Beamer ist manuelles Umschalten noch machbar, aber grenzwertig. Die Entscheidung gegen automatische Regie bleibt für v1.0 bestehen; nach dem ersten 20er-Turnier wird sie anhand der Beobachtung neu bewertet.

## 3. Unterstützte Formate

| Format | v1.0 | Wann sinnvoll |
|--------|------|---------------|
| **Single Elimination** | ✅ | Standardfall, kürzeste Dauer, ab 8 Spielern |
| **Round Robin (Jeder gegen Jeden)** | ✅ | 4–6 Spieler, wenn jeder viel spielen soll |
| **Round Robin Gruppen → Single Elim** | ✅ | **Standardformat für 20 Teilnehmer.** 4 Gruppen à 5, je die besten 2 ins K.o. |
| Double Elimination | M6 | Verdoppelt fast die Matchzahl; auf einer Party selten gewollt |
| Schweizer System | M6 | Braucht Buchholz + Paarungsalgorithmus |

**Begründung der Auswahl:** Single Elim + RR-Gruppen decken 4 bis 32 Teilnehmer vollständig ab. Double Elim ist der häufigste Wunsch und die häufigste Fehlentscheidung — die Verliererrunde verdoppelt die Spielzeit, und auf einer Party gehen die Leute vorher nach Hause.

**Empfehlung für 20 Teilnehmer: Gruppen → Single Elim, nicht reines Single Elim.** Begründung: Bei reinem 20er-Single-Elim (32er-Bracket mit 12 Freilosen) ist die Hälfte des Feldes nach einem einzigen Match raus — 10 Leute haben 4 Minuten gespielt und dann nichts mehr zu tun. Die Gruppenphase garantiert jedem **vier Matches**, verteilt sie gleichmäßig über 40 Minuten und liefert nebenbei die Setzliste für das K.o. Das ist der Unterschied zwischen einem Turnier, bei dem alle mitmachen, und einem, bei dem 10 Leute zuschauen.

**Gruppengrößen-Automatik:** Der Scheduler wählt die Gruppenaufteilung selbst nach Teilnehmerzahl (Ziel: 4–5 pro Gruppe, gleichmäßig, Rest auf die vorderen Gruppen verteilt). Bei 18 Spielern also 2×5 + 2×4. Manuelle Übersteuerung durch den Turnierleiter bleibt möglich.

**Explizit ergänzt: „Freies Spiel neben dem Turnier".** Wer ausgeschieden ist, darf sofort wieder in eine offene 1v1-Lobby. Ein Turniersystem, das ausgeschiedene Spieler zu Zuschauern macht, verliert die halbe Party.

## 4. Datenmodell

```lua
Tournament = {
  id            = "t_1754900000",        -- Zeitstempel-basiert
  name          = "Sommer-LAN 2026",
  format        = "single_elim",          -- single_elim | round_robin | groups_then_elim
  status        = "running",              -- setup | running | finished | aborted
  createdAt     = 1754900000,
  rulesetHash   = "…",                    -- eingefroren beim Start
  ruleset       = { … },                  -- vollständig, für Recovery
  config = {
    bestOfDefault   = 1,
    bestOfFinals    = 3,                  -- ab Halbfinale
    targetScore     = 15,
    deuceCap        = 21,                 -- Hard-Cap gegen Endlos-Deuce
    thirdPlaceMatch = true,
    noShowTimeout   = 180,                -- Sekunden bis Walkover
    parallelMatches = 2,
  },
  participants = {
    { id="p_01", name="Michi", seed=1, status="active", clientId=nil, stats={…} },
    -- status: active | eliminated | withdrawn | winner
    -- clientId: aktuelle Netzwerkverbindung, nil wenn offline
  },
  rounds = {
    { index=1, label="Viertelfinale", matches={ "m_101", "m_102", … } },
  },
  matches = {
    m_101 = {
      id        = "m_101",
      round     = 1,
      slotA     = "p_01",  slotB = "p_08",
      -- bei RR: beide immer gesetzt. Bei Elim: kann "winner_of:m_0xx" sein
      status    = "pending",   -- pending | ready | live | finished | walkover | bye
      bestOf    = 1,
      sets      = { {a=15,b=12}, … },
      winner    = nil,
      hostClient= nil,          -- welcher Rechner hostet dieses Match
      startedAt = nil, endedAt = nil,
      calledAt  = nil,          -- wann zum Spielen aufgerufen (für No-Show-Timer)
    },
  },
  standings = { … },            -- nur bei RR: Siege, Satzdifferenz, Punktdifferenz
  log = {                       -- append-only, für Nachvollziehbarkeit und Recovery
    { t=…, event="match_finished", matchId="m_101", winner="p_01", score="15:12" },
  },
}
```

**`log` ist append-only und die eigentliche Wahrheit.** Der abgeleitete Zustand (`matches`, `standings`) kann daraus jederzeit neu berechnet werden. Das ist die Grundlage der Absturz-Recovery in §7.

## 5. Zustandsautomat eines Matches

```
                     ┌──────────────────────────────────────────┐
                     │                                          │
  pending ──> ready ──> live ──> finished                       │
     │           │        │                                     │
     │           │        └──> aborted ──> (Neuansetzung) ───────┘
     │           └──> walkover (No-Show-Timer abgelaufen)
     └──> bye (Freilos bei ungerader Teilnehmerzahl)
```

| Übergang | Auslöser |
|----------|----------|
| `pending → ready` | Beide Slots sind mit konkreten Teilnehmern belegt (Vorgängermatches entschieden) **und** beide Spieler sind online |
| `ready → live` | Beide Spieler haben in der Match-Lobby „Bereit" bestätigt |
| `live → finished` | Satzzahl für `bestOf` erreicht |
| `ready → walkover` | `noShowTimeout` abgelaufen, ohne dass beide bereit waren |
| `live → aborted` | Host des Matches abgestürzt bzw. beide Spieler getrennt |
| `pending → bye` | Gegner-Slot bleibt leer (ungerade Teilnehmerzahl) |

**Der Aufruf („calling"):** Sobald ein Match `ready` wird, bekommen die beiden Spieler eine gut sichtbare Einblendung im Menü **und** ein Signalton, und das Match erscheint am Beamer in der Liste „Jetzt spielen". Ohne akustisches Signal funktioniert das auf einer Party nicht — niemand starrt auf sein Menü.

## 6. Edge Cases (der eigentliche Inhalt dieser Spec)

| # | Fall | Verhalten |
|---|------|-----------|
| E-01 | **Ungerade Teilnehmerzahl** | Freilose an die höchstgesetzten Spieler in Runde 1. Bracket wird auf die nächste Zweierpotenz aufgefüllt |
| E-02 | **Spieler ist nicht am Rechner** (No-Show) | 180-s-Timer läuft sichtbar ab dem `calling`. Danach Walkover. Turnierleiter kann den Timer pausieren (einziger vorgesehener manueller Eingriff) |
| E-03 | **Spieler kommt nach Turnierstart dazu** | Nachträglicher Beitritt nur bis zum Start von Runde 1. Danach: Warteliste für das nächste Turnier + Zugang zum freien Spiel |
| E-04 | **Spieler geht mitten im Turnier** (`withdrawn`) | Alle seine ausstehenden Matches → Walkover für den Gegner. Bei RR: bereits gespielte Ergebnisse bleiben gewertet |
| E-05 | **Client stürzt während eines Matches ab** | Netcode pausiert 30 s (§12 in `04_NETCODE`). Reconnect steigt in den laufenden Satz ein. Danach Walkover |
| E-06 | **Host eines Matches stürzt ab** | Match → `aborted`, wird neu angesetzt (kein Walkover — der Absturz ist nicht die Schuld eines Spielers). Bereits gespielte Sätze zählen |
| E-07 | **Turnier-Host stürzt ab** | Siehe §7 |
| E-08 | **Beide Spieler behaupten, gewonnen zu haben** | Kann nicht auftreten: Das Ergebnis wird vom Match-Host aus dem Simulationszustand geschrieben, nicht von Spielern gemeldet |
| E-09 | **Endlos-Deuce (28:26)** | `deuceCap` (Default 21) beendet den Satz zwangsweise beim Erreichen |
| E-10 | **Rallye ohne Ende** | Time-out-Regel P5 aus dem GDD: nach 30 s Punkt an den Nicht-Aufschläger |
| E-11 | **Gleichstand in Round-Robin-Tabelle** | Kriterien in Reihenfolge: 1) direkter Vergleich, 2) Satzdifferenz, 3) Punktdifferenz, 4) erzielte Punkte. Danach: Stichsatz auf 7 Punkte. **Kein Münzwurf** |
| E-12 | **Turnierleiter will ein Ergebnis korrigieren** | Manuelle Ergebniskorrektur nur durch den Turnier-Host, wird im `log` als `manual_override` mit Begründungstext protokolliert und im Bracket markiert |
| E-13 | **Zwei Turniere gleichzeitig im LAN** | Erlaubt. Discovery zeigt beide; Teilnahme an mehreren gleichzeitig wird blockiert |
| E-14 | **Spieler wechselt den Rechner** | Wiedereintritt über den Spielernamen; `clientId` wird neu zugeordnet. Namensdopplung wird beim Beitritt abgelehnt |
| E-15 | **Beide Spieler erscheinen nicht** | Walkover für den **höher gesetzten** Spieler (kleinere Setznummer), im Log als `no_show_both`. Kein Münzwurf, keine Neuansetzung — eine offene Bracket-Linie hält eine ganze Runde auf (ADR-021) |
| E-16 | **Ein Teilnehmer ist offline** | §5 verlangt für `ready` beide Spieler online, der No-Show-Timer läuft aber erst ab `ready`. Ein Match, das **ausschließlich** an einem offline Teilnehmer scheitert, bekommt deshalb denselben Timer über `noShowTimeout`; danach Walkover für den anwesenden Gegner. Der Timer beginnt erst, wenn das Match sonst spielbar wäre (ADR-021) |
| E-17 | **Gleichstand überlebt den Stichsatz** | Nach **genau einer** Stichsatzrunde entscheidet die Setznummer. Keine zweite Runde — sonst ist die Terminierung des Turniers nicht zusicherbar (ADR-021) |

**E-15 bis E-17 sind mit M4-05 dazugekommen**, aus dem Bau des Zustandsautomaten heraus. Alle drei haben dieselbe Form: eine Stelle, an der der Automat ohne Regel entweder würfeln oder stehenbleiben müsste. Die Begründung im Einzelnen steht in ADR-021.

## 7. Absturz-Recovery des Turnier-Hosts

**Das ist das wichtigste Feature dieses Moduls.** Ohne es ist ein integriertes Turniersystem schlechter als ein Zettel — ein Zettel stürzt nicht ab.

**Persistenz:** Nach **jedem** Log-Ereignis wird die vollständige Turnierstruktur atomar geschrieben:

```
1. Schreiben nach  tournaments/{id}.json.tmp
2. Alte Datei nach tournaments/{id}.json.bak umbenennen
3. .tmp nach       tournaments/{id}.json umbenennen
```

Speicherort: `love.filesystem.getSaveDirectory()`. Die Schreibvorgänge sind < 50 KB und passieren maximal alle paar Minuten — Performance ist kein Thema.

**Berichtigung 2026-08-13, gemessen statt angenommen (vor M4-06).** Die drei Schritte oben sind so nicht ausführbar:

- **`love.filesystem` kann nicht umbenennen.** Die Bibliothek hat weder `rename` noch `move` (LÖVE 11.5, vollständige Funktionsliste geprüft). Es bleibt `os.rename` aus der Lua-Standardbibliothek, und das braucht **absolute** Pfade — die liefert `love.filesystem.getSaveDirectory()`. Gemessen: funktioniert.
- **`os.rename` überschreibt unter Windows nicht.** Existiert das Ziel, scheitert der Aufruf mit „File exists". Unter POSIX ersetzt `rename()` das Ziel atomar, unter der Windows-Laufzeit nicht. Geschrieben wird deshalb für die strengere Plattform; das läuft auf beiden.

Die ausführbare Fassung:

```
1. schreiben          tournaments/{id}.json.tmp
2. os.remove          tournaments/{id}.json.bak      (Fehler ignorieren, darf fehlen)
3. os.rename json->bak                               (nur wenn .json existiert)
4. os.rename tmp->json
```

**Zwischen Schritt 3 und 4 existiert kurz keine `.json`.** Genau dafür ist `.bak` da: Die Recovery liest `.json`, und wenn die fehlt oder unbrauchbar ist, `.bak`. Ein Absturz in diesem Fenster kostet höchstens das letzte Log-Ereignis, nie das Turnier.

An ADR-007 ändert das nichts — das Verfahren bleibt „tmp → bak → rename", es hat nur einen Schritt mehr, als beim Schreiben der Spec bekannt war.

**Recovery-Ablauf:**
1. Beim Start prüft der Client, ob unter `tournaments/` ein Turnier mit `status = "running"` liegt.
2. Falls ja: Dialog „Laufendes Turnier ‚Sommer-LAN 2026' gefunden (Runde 2 von 3). Fortsetzen?"
3. Bei Bestätigung: Turnier wird aus dem `log` rekonstruiert, Lobby geht wieder auf, Clients verbinden sich per Discovery neu.
4. Matches im Status `live` gehen auf `aborted` und werden neu angesetzt.

**Zusätzliche Absicherung: Export.** Jederzeit per Tastendruck ein Export des Brackets als Markdown/CSV in den Speicherordner. Falls die Software komplett versagt, kann man mit dem Ausdruck weitermachen. Kostet 30 Zeilen Code und ist die einzige echte Versicherung.

## 8. Rollenverteilung im Netzwerk

| Rolle | Aufgabe |
|-------|---------|
| **Turnier-Host** | Hält den Turnierzustand, verteilt Paarungen, nimmt Ergebnisse entgegen, persistiert. Kann gleichzeitig Spieler sein |
| **Match-Host** | Simuliert ein konkretes Match. Bei 1 parallelem Match = Turnier-Host. Bei mehreren: einer der beiden Spieler (der mit der besseren Verbindung zum Turnier-Host) |
| **Client** | Spieler in einem Match |
| **Beamer** | Abonniert `TOURNAMENT_STATE` und optional ein Match als Spectator |

**Bei parallelen Matches gilt:** Der Match-Host meldet das Ergebnis über den reliable-Kanal an den Turnier-Host. Bleibt die Meldung aus (Absturz), fragt der Turnier-Host nach 60 s nach; bleibt sie weiter aus → E-06.

### 8.1 Wer hostet — die Regel (Nachtrag 2026-08-13, M4-09)

T-01 ist entschieden, **ADR-022**. Kurzfassung: Median der gemessenen RTT über die letzten 5 s, entschieden nur bei einem Unterschied über **5 ms**, sonst die **kleinere Setznummer**. Über Kabel ist der Gleichstandsfall der Normalfall — die Setznummer ist damit in der Praxis die Regel und die RTT die Ausnahme, nicht umgekehrt.

Spielt der Turnier-Host selbst mit, ist seine RTT zu sich null; er hostet sein Match also immer. Das ist kein Sonderfall im Code, sondern das Maß, das seine Arbeit tut.

### 8.2 Ports (Nachtrag 2026-08-13, M4-09)

Ein Prozess kann **nicht zweimal denselben ENet-Port binden** — der zweite `host_create` scheitert mit „already listening". Das trifft genau den Auslegungsfall: Der Turnier-Host ist gleichzeitig Spieler und möglicherweise Match-Host, und ein Teilnehmer hängt gleichzeitig am Turnier-Host und an einem Match-Host. Gemessen 2026-08-13.

| Rolle | Bindung | Wie die Gegenseite sie findet |
|---|---|---|
| Turnier-Host | `*:21212` fest (`Protocol.PORT_ENET`, konfigurierbar) | Discovery-`ANNOUNCE` mit `mode = "tournament"` und `enetPort` |
| Match-Host | `*:0` — **ephemer**, vom Betriebssystem vergeben | Der Match-Host liest den tatsächlichen Port mit `host:get_socket_address()` zurück und meldet ihn in `MATCH_ACCEPT` (0x42). Der Turnier-Host setzt ihn mit der IP zusammen, die er am Peer sieht, und schickt beides in `TOURNAMENT_ASSIGN` (0x41) an den Gegner |
| Teilnehmer | zwei Verbindungen, zwei Sockets | — |

**Kein zweiter fester Port und kein Portbereich.** Ein Portbereich (21212, 21213, 21214 …) müsste bei einer Kollision ausweichen, und der Ausweich-Pfad ist der Code, der erst am Partyabend zum ersten Mal läuft. Der ephemere Port kann nicht kollidieren, weil das Betriebssystem ihn vergibt. Damit sind zugleich **drei gleichzeitige Lobbys im selben Netz** (T-N-09) kein Sonderfall mehr.

**Der Turnier-Host hostet ein eigenes Match auf demselben Weg wie jeder andere** — zweiter ENet-Wirt auf `*:0`. Ein Multiplex über 21212 spart einen Socket und erkauft ihn mit einem zweiten Codeweg für eine Rolle, die sonst überall gleich aussieht.

## 9. Setzung (Seeding)

| Modus | Verfahren |
|-------|-----------|
| `manual` | Turnierleiter ordnet in der Lobby per Drag/Pfeiltasten |
| `random` | Deterministisch aus einem angezeigten Seed. **Der Seed wird sichtbar gemacht** — dann kann niemand behaupten, das Bracket sei manipuliert |
| `by_rating` | Aus lokalen Vorergebnissen desselben Abends (Siege/Niederlagen). Nur ab dem zweiten Turnier sinnvoll |

Standard: `random` mit sichtbarem Seed. Klassische Bracket-Position: 1 gegen n, 2 gegen n-1, usw.

**Stand 2026-08-13 (M4-07).** Gebaut sind `random` (Voreinstellung) und `manual`. **`by_rating` ist zurückgestellt** — das Verfahren steht in `bracket.lua` und nimmt eine Rangliste entgegen, aber sie aus den Vorturnieren desselben Abends zusammenzurechnen ist eigene Arbeit und vor dem zweiten Turnier des Abends wirkungslos. Entscheidung r0btoshi, Begründung im `CC-05_REPORT`.

**Der sichtbare Seed ist ein Text, gerechnet wird mit einer Zahl.** Das Feld nimmt „sommerlan" genauso wie „113355": Eine reine Ziffernfolge gilt als Zahl, alles andere läuft über djb2. Angezeigt werden beide, und die angeschriebene Zahl ergibt wieder eingetippt dasselbe Bracket — sonst wäre der Seed nicht nachrechenbar und damit wertlos. Steht als Testfall in `tests/tournament_session_test.lua`.

## 10. Darstellung des Brackets

**Im Spieler-Menü:** kompakte Ansicht — nur die eigene Turnierlinie plus „Nächster Gegner: …". Ein vollständiger 32er-Baum auf einem Laptop-Bildschirm ist unlesbar.

**Am Beamer:** vollständiges Bracket, laufende Matches hervorgehoben, abgeschlossene ausgegraut, aufgerufene Matches blinkend mit Countdown.

**Bei Round Robin:** Tabelle statt Baum, sortiert nach den Kriterien aus E-11, mit noch ausstehenden Matches am Fuß.

**Stand 2026-08-13 (M4-08).** Beides gebaut, umgeschaltet wird mit **F2**. Ein Nachtrag aus der Umsetzung: Der Hinweis „Gleichstand — Stichsatz" darf nicht an einem ungelösten Tabellenblock hängen. Vor dem ersten Spieltag steht in jeder Gruppe alles gleich, und der Hinweis stand damit von Anfang an über jeder Tabelle. Angezeigt wird er unter genau der Bedingung, unter der der Scheduler den Stichsatz auch ansetzt: Gruppe durchgespielt **und** der Gleichstand liegt auf der Trennlinie zum K.o.

## 11. Statistiken (Minimalumfang v1.0)

Pro Turnier und Spieler: Matches, Sätze, Punkte für/gegen, längste Rallye, schnellster Ball. Diese fünf reichen für die Siegerehrung und kosten fast nichts, weil die Werte ohnehin in der Simulation anfallen. Alles darüber (Heatmaps, Trefferquoten) ist M6.

**Woher die letzten beiden kommen (Nachtrag 2026-08-13, M4-09).** Die ersten drei fallen im Turniermodul an. **Längste Rallye und schnellster Ball fallen in der Simulation an** und müssen deshalb mit dem Ergebnisbericht des Match-Hosts mitkommen — `match_finished` trug bis M4-06 nur die Sätze.

- Gemessen wird **außerhalb von `src/sim/`**, von einem Beobachter, der den Zustand nach jedem Tick liest: die längste Rallye aus `state.rally.timer` beim Ende eines Ballwechsels, die höchste Ballgeschwindigkeit aus dem Betrag von `(vx, vy)`. Die Simulation zählt nichts mit; sie bleibt unverändert (`02_CODE_AUDIT` §4).
- Gemessen wird **nur auf dem Match-Host**. Er ist die Autorität (ADR-002); ein Gast, der dieselbe Zahl selbst rechnet, hätte eine zweite Wahrheit ohne Schiedsrichter.
- **Zuordnung:** Die längste Rallye zählt für **beide** Spieler des Matches — sie haben sie zusammen gespielt. Der schnellste Ball zählt für den Spieler, der ihn zuletzt berührt hat (`state.rally.lastTouchPlayer` im Moment des Maximums).
- Geführt wird je Teilnehmer das **Maximum** über alle seine Matches. Ein Walkover, ein Freilos und ein abgebrochenes Match liefern keine Werte und verändern das Maximum nicht.
- Die Einheiten stehen im Ereignis fest: die Rallye in **Sekunden**, die Geschwindigkeit in **Pixeln je Sekunde** des logischen Feldes (800 × 600, ADR-004). Eine Zahl ohne Einheit ist am Beamer eine Zahl, die niemand einordnen kann.

## 12. Offene Punkte (aufgenommen 2026-08-12, vor M2)

| ID | Punkt | Zu klären in |
|----|-------|--------------|
| T-01 | **Die Match-Host-Wahl ist noch eine Absichtserklärung.** §8 sagt „der mit der besseren Verbindung zum Turnier-Host", nennt aber weder das Maß (RTT woraus? über welchen Zeitraum?) noch das Verhalten bei Gleichstand. Ein Gleichstand ohne Regel wäre ein Münzwurf im Turnierbetrieb, und den schließt die Anti-Zufalls-Doktrin aus. ~~Vorschlag: gemessene RTT über die letzten 5 s, bei Gleichstand gewinnt die niedrigere `participantId`~~ | **ERLEDIGT 2026-08-13** — **ADR-022**, Kurzfassung in §8.1. Zwei Berichtigungen gegenüber dem Vorschlag: Es entscheidet der **Median** der Proben, nicht ihr Mittel, und erst ab **5 ms** Unterschied. Bei Gleichstand entscheidet die **Setznummer**, nicht die `participantId` — ADR-021 hat die Setznummer bereits zum Schlussanker aller Gleichstände gemacht, und zwei Anker für dieselbe Art Frage sind eine Wahrheit zu viel. Freigabe r0btoshi vor der Umsetzung |
| T-02 | **Der Turnier-Host ist der einzige Punkt, an dem Stillstand entsteht.** Die Recovery in §7 ist ein Neustart, kein Failover auf einen anderen Rechner: solange das Gerät aus ist, geht nichts weiter. Für v1.0 ist das die richtige Abwägung — die Konsequenz ist aber betrieblich und gehört ins Runbook: **der Turnier-Host darf nicht der Laptop von jemandem sein, der um Mitternacht nach Hause fährt** | **ERLEDIGT 2026-08-13** — als Punkt 5 der Vorbereitungsliste in `11_OPS` §1 eingetragen. Am Entwurf ändert sich nichts: kein Failover in v1.0 |

## 13. Abnahmekriterien M4

1. 8er Single Elim vollständig ohne manuellen Eingriff durchspielbar.
2. Turnier-Host wird während Runde 2 hart beendet (Prozess-Kill) → nach Neustart läuft das Turnier ab dem letzten abgeschlossenen Match weiter.
3. Ein Spieler erscheint nicht → Walkover greift nach 180 s, Bracket schreibt korrekt fort.
4. Round Robin mit 5 Spielern inkl. Gleichstand auf Platz 1 → Tabelle wendet E-11 korrekt an.
5. Bracket-Export als Markdown ist lesbar und vollständig.
