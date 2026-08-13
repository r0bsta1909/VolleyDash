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

## 9. Setzung (Seeding)

| Modus | Verfahren |
|-------|-----------|
| `manual` | Turnierleiter ordnet in der Lobby per Drag/Pfeiltasten |
| `random` | Deterministisch aus einem angezeigten Seed. **Der Seed wird sichtbar gemacht** — dann kann niemand behaupten, das Bracket sei manipuliert |
| `by_rating` | Aus lokalen Vorergebnissen desselben Abends (Siege/Niederlagen). Nur ab dem zweiten Turnier sinnvoll |

Standard: `random` mit sichtbarem Seed. Klassische Bracket-Position: 1 gegen n, 2 gegen n-1, usw.

## 10. Darstellung des Brackets

**Im Spieler-Menü:** kompakte Ansicht — nur die eigene Turnierlinie plus „Nächster Gegner: …". Ein vollständiger 32er-Baum auf einem Laptop-Bildschirm ist unlesbar.

**Am Beamer:** vollständiges Bracket, laufende Matches hervorgehoben, abgeschlossene ausgegraut, aufgerufene Matches blinkend mit Countdown.

**Bei Round Robin:** Tabelle statt Baum, sortiert nach den Kriterien aus E-11, mit noch ausstehenden Matches am Fuß.

## 11. Statistiken (Minimalumfang v1.0)

Pro Turnier und Spieler: Matches, Sätze, Punkte für/gegen, längste Rallye, schnellster Ball. Diese fünf reichen für die Siegerehrung und kosten fast nichts, weil die Werte ohnehin in der Simulation anfallen. Alles darüber (Heatmaps, Trefferquoten) ist M6.

## 12. Offene Punkte (aufgenommen 2026-08-12, vor M2)

| ID | Punkt | Zu klären in |
|----|-------|--------------|
| T-01 | **Die Match-Host-Wahl ist noch eine Absichtserklärung.** §8 sagt „der mit der besseren Verbindung zum Turnier-Host", nennt aber weder das Maß (RTT woraus? über welchen Zeitraum?) noch das Verhalten bei Gleichstand. Ein Gleichstand ohne Regel wäre ein Münzwurf im Turnierbetrieb, und den schließt die Anti-Zufalls-Doktrin aus. **Vorschlag: gemessene RTT über die letzten 5 s, bei Gleichstand gewinnt die niedrigere `participantId`** — deterministisch und im Log nachprüfbar | M4-09 |
| T-02 | **Der Turnier-Host ist der einzige Punkt, an dem Stillstand entsteht.** Die Recovery in §7 ist ein Neustart, kein Failover auf einen anderen Rechner: solange das Gerät aus ist, geht nichts weiter. Für v1.0 ist das die richtige Abwägung — die Konsequenz ist aber betrieblich und gehört ins Runbook: **der Turnier-Host darf nicht der Laptop von jemandem sein, der um Mitternacht nach Hause fährt** | **ERLEDIGT 2026-08-13** — als Punkt 5 der Vorbereitungsliste in `11_OPS` §1 eingetragen. Am Entwurf ändert sich nichts: kein Failover in v1.0 |

## 13. Abnahmekriterien M4

1. 8er Single Elim vollständig ohne manuellen Eingriff durchspielbar.
2. Turnier-Host wird während Runde 2 hart beendet (Prozess-Kill) → nach Neustart läuft das Turnier ab dem letzten abgeschlossenen Match weiter.
3. Ein Spieler erscheint nicht → Walkover greift nach 180 s, Bracket schreibt korrekt fort.
4. Round Robin mit 5 Spielern inkl. Gleichstand auf Platz 1 → Tabelle wendet E-11 korrekt an.
5. Bracket-Export als Markdown ist lesbar und vollständig.
