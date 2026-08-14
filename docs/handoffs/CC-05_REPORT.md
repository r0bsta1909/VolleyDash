# CC-05 — Rückmeldung (M4 Turniermodus)

**Datum:** 2026-08-13 · **Auftrag:** `docs/handoffs/CC-05_M4_TURNIER.md`
**Ausgangsstand:** 9f40dc7 (`v0.3.0`) · **Stufe B ab** 72a579a · **Stufe C ab** e7aeb2b
**Tests:** 446 bestanden, 0 gescheitert (Stufe C: 445, B: 411, A: 349, vorher 214) · **ohne `love`:** 405
**Netz-Selbsttest:** 49 Prüfungen, alle grün
**Turnier-Selbsttest:** 59 Prüfungen, alle grün (T-N-11 und T-N-09)
**Vierprozesslauf:** 4er-Turnier, zehn Matches, Sieger — auf allen vier Prozessen derselbe
**Referenzen:** `python tools/verify_replays.py` meldet OK

> **Dieser Bericht wird fortgeschrieben.** Stand der Stufen aus §2 des Handoffs:
>
> | Stufe | Inhalt | Stand |
> |---|---|---|
> | **A** | AP-1 bis AP-4 — Datenmodell, Bracket, Scheduler, Persistenz | ✅ **abgeschlossen** |
> | **B** | AP-5 — Turnier-Lobby, Setzung mit sichtbarem Seed, Bracket-Anzeige | ✅ **abgeschlossen** (M4-07, M4-08, M4-11) |
> | **C** | AP-6 — verteilte Match-Hosts, `TOURNAMENT_STATE` | ✅ **abgeschlossen** (M4-09, ADR-022, ADR-023) |
> | **C.1** | Nacharbeit aus dem ersten LAN-Abend — sechs Befunde | ✅ **abgeschlossen** (C-T-11 … C-T-16) |
> | **D** | AP-7 — Export (M4-10) | ⬜ offen |
>
> **Die nächste Session fängt bei Stufe D an** — Export als Markdown/CSV, drei Stunden. Was
> dafür schon dasteht und was dabei zu beachten ist, steht in **§7**.
>
> **Beide ADRs sind entschieden und stehen vor dem Code im Log:** **ADR-022** (wer hostet ein
> Match) und **ADR-023** (Format von `TOURNAMENT_STATE`). Begründung und Freigabe in §5.3.
>
> **Die Klänge spielen** (Stufe B): `tournament_call` beim Aufruf des eigenen Matches,
> `tournament_warn` 30 s vor Ablauf des No-Show-Timers, `tournament_done` beim Sieger.
> Vorgaben und Anlass stehen in `docs/handoffs/CC-05_KLANGLISTE.md`.

---

## 0. Was jetzt geht

### Nach Stufe C (2026-08-13, dritte Sitzung)

**Das Turnier läuft über das Netz, und gespielt wird darin.** Der Turnierleiter öffnet
NETWORK MATCH → „Turnier" wie bisher; sein Rechner sendet ab da eine Bake und steht bei allen
anderen in der **Serverliste**. Wer dort ENTER drückt, landet nicht in einer Match-Lobby,
sondern im Turnier: Name ist angemeldet, Bracket ist sichtbar, und beim Aufruf des eigenen
Matches öffnet sich das Match von allein — einer der beiden Spieler hostet, der andere
verbindet sich, und das Ergebnis geht am Ende zurück ins Bracket.

**Gemessen, nicht behauptet.** Ein 4er-Turnier über **vier echte Prozesse**, ohne einen
einzigen Tastendruck nach der Auslosung: zehn Matches inklusive Gruppenphase, Stichsatz,
Best-of-3-Finale, Sieger, Statistiken. Werkzeug: `--tournament-auto=host` plus dreimal
`--tournament-auto=client --client-id=N`.

Dazu der Selbsttest in einem Prozess (`--tournament-selftest`, 58 Prüfungen): **vier parallele
Matches mit gleichzeitigem Ergebnisversand** (T-N-11) und **drei gleichzeitige Turniere im
selben Netz** (T-N-09) — der Fall, der seit M2 als Restschuld herumstand.

**Der Turnier-Wirt spielt mit.** Das ist kein Randfall, sondern der Auslegungsfall aus
`05_TOURNAMENT` §8, und er ist der Grund für die Portregel: Ein Prozess kann denselben
ENet-Port nicht zweimal binden — gemessen, nicht angenommen. Match-Wirte binden deshalb einen
ephemeren Port und melden ihn.

### Nach Stufe B (2026-08-13, zweite Sitzung)

**Das Turnier ist bedienbar.** Menü → NETWORK MATCH → „Turnier": Namen eintragen, auslosen,
Ergebnisse eintragen, Sieger. Der Seed steht sichtbar daneben, der Aufruf klingt, der
No-Show-Timer läuft sichtbar ab, und mitten im Turnier lässt sich der Prozess abschießen —
beim nächsten Betreten fragt der Dialog, ob fortgesetzt werden soll.

Ein **8er-Turnier läuft ausschließlich über die Tastatur bis zum Sieger durch**, und das steht
als Testfall drin (`tests/tournament_lobby_test.lua`). Eingegeben werden dabei nur die
Ergebnisse; Aufruf, Freilose, Fortschreibung des Baums, Übergang ins K.o. und das Ende
passieren von allein.

**Was noch nicht geht: über das Netz anmelden und im Turnier spielen.** Gespielt wird daneben
(freies LAN-Match oder lokal), das Ergebnis trägt der Turnierleiter ein. Warum das die richtige
Grenze für Stufe B ist, steht in §5.1.

### Nach Stufe A (erste Sitzung)

Ein vollständiges 20er-Turnier läuft im Headless-Testrunner durch — angelegt, ausgelost,
40 Gruppenmatches, 8 K.o.-Matches, Sieger. Mitten in Runde 2 wird das Turnierobjekt
**weggeworfen** und ausschließlich aus der Datei neu aufgebaut; danach läuft es zu Ende und
liefert denselben Sieger und dieselben 48 Einzelergebnisse wie der ungestörte Lauf.

Das ist der Punkt, an dem M4 laut Handoff steht oder fällt. Er steht.

**Zu sehen ist davon nichts.** Wer die Version startet, sieht dasselbe Spiel wie in 0.3.0 —
keine Zeile dieses Moduls hängt an der Oberfläche oder am Netz. Das war der Auftrag, und es ist
auch die richtige Reihenfolge: Was entscheidet, ist jetzt prüfbar, bevor irgendwas es benutzt.

---

## 1. Erledigt

| AP | Aufgaben | Ergebnis |
|---|---|---|
| AP-1 | M4-01 | `src/tournament/model.lua` — Datenmodell §4, append-only Log mit 15 Ereignisarten. Der gesamte abgeleitete Zustand wird nach jedem Ereignis neu gerechnet |
| AP-2 | M4-02, M4-02b, M4-03, M4-04 | `src/tournament/bracket.lua` — eigener deterministischer Generator, Single Elim mit Freilosen, Gruppenautomatik, Round Robin, E-11, Übergang ins K.o. |
| AP-3 | M4-05 | `src/tournament/scheduler.lua` — Zustandsautomat §5 mit allen Nebenwegen, plus drei Regeln, die §5 offengelassen hat (ADR-021) |
| AP-4 | M4-06 | `src/tournament/persistence.lua` + `src/tournament/json.lua` — vier Schritte nach §7, Recovery aus `.json` mit Rückfall auf `.bak` |
| — | M4-11 | Die **Datenseite** der manuellen Korrektur ist fertig: `manual_override` verlangt eine Begründung und markiert das Match sichtbar. Die Bedienung gehört zu M4-07 |
| **AP-5** | **M4-07, M4-08, M4-11** | **Stufe B, siehe §1a** |
| **AP-6** | **M4-09** | **Stufe C, siehe §1b** |

### 1b. Stufe C im Einzelnen

| Datei | Was sie tut |
|---|---|
| `src/tournament/host_choice.lua` | **ADR-022.** Probenfenster, Median, Schwelle, Gleichstandsregel. `love`-frei — die Regel entscheidet, also gehört sie zu den entscheidenden Dateien und nicht in `src/net/` |
| `src/tournament/match_stats.lua` | Die zwei Zahlen aus §11. Ein **Beobachter**, der den Simulationszustand nach jedem Tick liest und nichts zurückschreibt. `love`-frei |
| `src/net/tournament_host.lua` | Der **zweite Wirt-Typ** (F-T-08). 40 Peers auf 21212, Anmeldung, Anwesenheit, Zuweisung, Ergebnisannahme, die 60-s-Nachfrage aus §8 |
| `src/net/tournament_client.lua` | Die Teilnehmerseite. Hält eine **lesende** Session, die aus Log-Ereignissen abgeleitet wird |
| `src/net/match_runner.lua` | Die Netzseite **eines** Turniermatches. Öffnet `Host` auf `*:0` bzw. `Client` auf die zugewiesene Adresse, zählt die Sätze |
| `src/net/protocol.lua` | 0x40 bis 0x46. `HELLO`/`REJECT` werden wiederverwendet — sie tragen schon genau das, was eine Anmeldung braucht |
| `src/app/scenes/tournament.lua` | Zwei Rollen, **ein** Zuweisungsrückruf. Der Leiter bekommt seine Zuweisung ohne Umweg über das Netz, aber über denselben Weg |
| `tools/tournament_selftest.lua` | T-N-11 und T-N-09 in einem Prozess, CI-tauglich |
| `tools/tournament_auto.lua` | Vier Prozesse, ein Turnier, kein Tastendruck — die Antwort auf F-T-10 für die Turnierszene |

**Vier Dinge, die dabei nicht offensichtlich waren:**

1. **Ein Prozess kann denselben ENet-Port nicht zweimal binden.** Gemessen: Der zweite
   `host_create("*:21212")` scheitert mit „already listening". Das trifft genau den
   Auslegungsfall, denn der Turnier-Wirt ist gleichzeitig Spieler und möglicherweise selbst
   Match-Wirt. Match-Wirte binden deshalb `*:0`, lesen den vergebenen Port mit
   `get_socket_address()` zurück und melden ihn. Ein Portbereich wäre die schlechtere Antwort:
   Er bräuchte einen Ausweichpfad, und der liefe am Partyabend zum ersten Mal.
2. **Die Wahl des Match-Wirts wird gemerkt, nicht zweimal gerechnet.** Der Turnier-Wirt
   braucht sie schon beim **Aufruf** — er muss dem künftigen Wirt sagen, dass er einen Port
   öffnen soll — und der Scheduler fragt sie beim **Start** erneut. Wären das zwei Rechnungen,
   könnte die RTT dazwischen wandern und der Gast verbände sich zu einem Rechner, der gar nicht
   mehr hostet.
3. **Der Turnier-Wirt kann seinen eigenen Match-Port nicht über das Netz melden** — er redet
   nicht mit sich selbst. Angeschrieben wird er als `":PORT"` ohne Rechnerteil; der Gast setzt
   die Adresse davor, unter der er den Turnier-Wirt ohnehin erreicht. Das ist nicht bloß
   bequem: Welche seiner eigenen Adressen der Turnier-Wirt anschreiben müsste, weiß er bei
   mehreren Netzwerkkarten nicht.
4. **Eine Zuweisung wird wiederholt, bis sie bestätigt ist.** Sie kann verlorengehen, ohne dass
   ein Paket verlorengeht: Wer im Moment des Aufrufs noch im vorigen Match steckt, kann sie
   nicht annehmen. Zwei Sekunden Wiederholung, und der No-Show-Timer merkt nichts davon.

### 1a. Stufe B im Einzelnen

| Datei | Was sie tut |
|---|---|
| `src/tournament/session.lua` | Die Laufzeit: hält Modell, Scheduler und Persistenz zusammen, nimmt die Uhr von außen und liefert **den Ereignisstrom seit dem letzten Blick**. `love`-frei |
| `src/ui/tournament_lobby.lua` | Die Bedienung als Zustandsmaschine — drei Bildschirme (Wiederaufnahme, Anmeldung, laufendes Turnier), Ergebnis- und Korrektureingabe. `love`-frei, wie `src/ui/menu.lua` |
| `src/render/bracket_view.lua` | Das Bild: kompakt und voll. Rechnet nichts |
| `src/app/scenes/tournament.lua` | Die Szene: treibt die Session mit `love.timer`, spielt die Klänge, blendet den Aufruf ein |
| `src/ui/menu.lua`, `src/app/app.lua` | Ein Menüeintrag „Turnier" unter NETWORK MATCH und zwei Übergänge |

**Drei Dinge, die dabei nicht offensichtlich waren:**

1. **Der Ereignisstrom gehört der Szene, nicht der Bedienung.** Wer ein Ergebnis einträgt, löst
   damit den Aufruf des nächsten Matches aus — und genau dieser Aufruf braucht einen Ton. Hätte
   `enterResult` den Strom selbst geleert, wäre der Ton ausgeblieben, weil die Szene beim
   nächsten Bild nichts mehr gefunden hätte. Deshalb gibt es `advance` (Automat laufen lassen)
   getrennt von `tick` (laufen lassen **und** berichten). Es gibt einen Testfall, der genau das
   festnagelt.
2. **Die Vorwarnung steht nicht im Log.** `no_show_warning` ist ein Ton, kein Turnierzustand;
   was im Log steht, muss die Rekonstruktion aus §7 überstehen. Sie kommt als synthetisches
   Ereignis aus `tick` und ist als solches markiert.
3. **Anwesenheit ist ein Schalter, kein zweiter Codeweg.** §5 verlangt für `ready` beide Spieler
   online. In Stufe B gilt: Wer angemeldet ist, steht im Raum — der Turnierleiter hat seinen
   Namen getippt. Stufe C setzt `presence = "net"` und ruft `setPresence` aus der Verbindung.
   Sonst ändert sich an der Datei nichts.

### Die eine Entscheidung, die alles andere trägt

**Nichts außerhalb von `applyEvent` fasst den abgeleiteten Zustand an.** Paarungen,
Tabellenplätze, Statistiken und die Auflösung der `winner_of`-Referenzen werden nach jedem
Ereignis **vollständig neu** gerechnet, nicht fortgeschrieben.

Das kostet bei 48 Matches nichts messbares und erledigt drei Probleme auf einmal:

1. **Die Recovery ist kein eigener Codepfad.** `Model.replay(log)` ruft denselben `applyEvent`
   in derselben Reihenfolge. Ein Wiederaufbau, der von einem zweiten Stück Code lebt, wäre
   genau der Code, der nie ausgeführt wird, bis er gebraucht wird — und dann falsch ist.
2. **E-12 wird trivial.** Eine nachträgliche Ergebniskorrektur würde inkrementell geführte
   Zähler stillschweigend falsch machen: Der alte Sieg müsste zurückgebucht, die alten Punkte
   abgezogen, die Tabelle neu sortiert werden. Es gibt einen Test dafür, und er war beim
   ersten Anlauf grün, weil es nichts zurückzubuchen gibt.
3. **Der Test der Abnahme aus AP-1 ist nicht nur eine Zusicherung, sondern eine Falle.**
   Er vergleicht Feld für Feld und wiederholt das an Zwischenständen quer durch das Log — ein
   Zustand, der nur am Ende stimmt, hilft der Recovery nicht, die setzt genau mittendrin auf.
   Wer versehentlich außerhalb von `applyEvent` etwas setzt, sieht ihn sofort rot.

### Was geprüft ist

- **Für JEDE Teilnehmerzahl von 4 bis 32:** keine Gruppe unter 3 oder über 6, jeder Spieler
  genau einmal je Runde, die Matchsumme stimmt, kein Freilos außerhalb von Runde 1, keine
  Gruppengegner in der ersten K.o.-Runde. Das ist die Sorte Fehler, die von Hand niemand
  findet — man probiert 8 und 16 und ist zufrieden.
- **Die beiden Zahlen aus der Spec stimmen genau:** 20 Teilnehmer werden 4×5, 18 werden
  2×5 + 2×4. Beide stehen als eigener Testfall drin, weil sie in `05_TOURNAMENT` §3 wörtlich
  zugesagt sind.
- **E-11 mit konstruiertem Dreifach-Gleichstand**, einmal auflösbar (direkter Vergleich, dann
  Punktdifferenz) und einmal echt unauflösbar — dann wird gemeldet statt gewürfelt.
- **Ein Turnier, bei dem NIEMAND spielt, endet trotzdem.** Acht Teilnehmer, alle offline,
  keine einzige Bereitmeldung. Nach den Fristen steht ein Sieger fest. Ohne diesen Fall wäre
  die Terminierung des Automaten nicht zugesichert, sondern gehofft.
- **Die halb geschriebene Datei** an vier Abbruchstellen, und der Absturz genau im Fenster
  zwischen Schritt 3 und 4, in dem kurz keine `.json` existiert.

### Was in Stufe C geprüft ist

34 neue Testfälle im Headless-Runner (`love`-frei) plus 58 Prüfungen im Turnier-Selbsttest.
Die, die etwas widerlegen können:

- **Rauschen entscheidet nicht.** 2,0 ms gegen 1,0 ms — die Kabellage — fällt auf die
  Setznummer. Genau 5 ms Unterschied auch, 5,1 ms nicht mehr. Ohne diesen Fall wäre ADR-022 die
  Zusicherung, die man am ehesten stillschweigend verletzt.
- **Der Median wirft den einen Ausreißer weg, den der Mittelwert mitnähme** (neun Proben zu
  2 ms, eine zu 200 ms).
- **Wer keine Proben hat, fällt auf die Setznummer und nicht auf null.** Sonst hätte
  ausgerechnet der gerade Abgestürzte die beste Verbindung.
- **Der Grund der Wahl überlebt die Rekonstruktion aus §7.** „Warum hostet der?" muss auch nach
  einem Neustart aus der Datei zu beantworten sein.
- **Die längste Rallye zählt für beide Spieler, der schnellste Ball nur für den letzten
  Berührer** — und ein Ball, den niemand angefasst hat, gehört niemandem.
- **Ein abgebrochenes Match nimmt seine Statistiken mit** (E-06). Sie gehören zu einem
  Durchgang, der nicht zählt; stehen zu lassen hieße, bei der Siegerehrung eine Rallye aus
  einem Match zu zeigen, das nie gewertet wurde.
- **Der Beobachter lässt die Simulation unberührt.** Zwei identische Zustände, 300 Ticks, einer
  beobachtet — Ball, Rallye-Uhr und Punktestand bleiben gleich.
- **Ein Block aus 32 Log-Ereignissen geht über die Leitung und kommt Feld für Feld zurück** —
  inklusive der verschachtelten Satzlisten. Er ist länger als 255 Byte, und genau das ist der
  Grund für das `s4`.
- **Ein angeschnittener Block liefert KEIN halbes Ereignis**, sondern einen Grund. Ein halb
  angewandtes Log wäre schlimmer als ein sichtbar veralteter Stand.
- **Ein Unbeteiligter kann kein Ergebnis melden** (E-08). Ohne diesen Fall wäre die Zusage
  „kann nicht auftreten" eine Absichtserklärung.
- **Vier parallele Matches, alle vier Ergebnisse in derselben Runde abgeschickt**, alle vier
  korrekt im Bracket, alle vier mit Statistik (T-N-11).
- **Drei gleichzeitige Turniere im selben Netz**: drei Namen, drei ENet-Ports, drei `hostId` —
  und **kein Turnier steht doppelt in der Liste**, obwohl jedes über Loopback und LAN-Adresse
  antwortet (T-N-09).
- **Alle Teilnehmer leiten denselben Zustand ab.** Ein Bracket, das auf zwei Rechnern
  verschieden aussieht, wäre der teuerste Fehler des Abends.

### Was in Stufe B geprüft ist

60 neue Fälle, alle `love`-frei. Die, die etwas widerlegen können:

- **Ein 8er-Turnier ausschließlich über die Tastatur bis zum Sieger** — inklusive der Zusicherung,
  dass am Ende **kein** Match offen geblieben ist, auch nicht das Spiel um Platz 3.
- **Derselbe Seed-Text ergibt zweimal dasselbe Bracket, ein anderer ein anderes** — und die
  **angeschriebene Zahl ergibt wieder eingetippt dieselbe Auslosung.** Der letzte Fall ist der
  eigentliche: Ein sichtbarer Seed, den man nicht nachrechnen kann, ist wertlos (F-T-05).
- **Die Restzeit des No-Show-Timers**: volle Frist beim Aufruf, herunterzählend, nie negativ,
  und **eingefroren, solange der Timer angehalten ist** (E-02).
- **Die Vorwarnung kommt bei 30 s und genau einmal** — und steht nicht im Log.
- **Ein Eingriff füllt den Ereignisstrom, er leert ihn nicht** (siehe §1a, Punkt 1).
- **Eine Korrektur ohne Begründung committet nicht** (E-12), und mit Begründung steht der Grund
  im Log und die Markierung am Match.
- **Ein unentschiedener Satz („15:15") wird abgelehnt**, ebenso Unsinn wie „1512". Best-of-3
  braucht zwei gewonnene Sätze.
- **Ein Turnier, das mitten in der Bedienung wegbricht**, wird ausschließlich aus der Datei neu
  aufgebaut und zu Ende gespielt; unterbrochene Matches sind wieder aufgerufen und haben die
  **volle** Frist, keine angebrochene.
- **In der kompakten Ansicht ist die Bedienung stumm** — `E`, `K`, `W`, `A` tun dort nichts.
- **Solange der Gegner offen ist, ist man nicht sein eigener Gegner.** Klingt albern, war ein
  Fehler (§3, B-T-04).

---

## 2. Nicht erledigt und warum

### Nach Stufe C

- **Stufe D (M4-10, Export)** — so vorgesehen, §2 des Handoffs gibt die Reihenfolge vor. Rund
  drei Stunden, siehe §7.
- **Kein Spectator und keine Beamer-Regie.** M5 bzw. ADR-008, beides ausdrücklich außerhalb
  dieser Session (Handoff §3).
- **Der Turnier-Host bleibt der einzige Punkt, an dem Stillstand entsteht** (T-02). Es gibt
  kein Failover auf einen anderen Rechner, und das ist für v1.0 die richtige Abwägung — die
  Konsequenz steht seit dem 2026-08-13 als Punkt 5 in der Vorbereitungsliste von `11_OPS` §1.
  Stufe C ändert daran nichts, macht es aber teurer: Jetzt hängen auch die laufenden Matches
  am Turnier-Host, nicht nur die Anzeige.
- **Der Vierprozesslauf prüft die Firewall nicht.** Er läuft über Loopback. Ob ein Match-Wirt
  auf einem **ephemeren** Port von einem fremden Rechner aus erreichbar ist, ist damit **nicht**
  beantwortet — das ist neu gegenüber M2, wo nur 21212 freizugeben war. Gehört in die
  Abnahme D2 und ins Runbook; siehe §5.3.
- **Kein Wiedereintritt in ein LAUFENDES Match nach einem Absturz des Match-Wirts.** Das Match
  geht nach E-06 auf `pending` zurück und wird neu angesetzt — bereits gespielte Sätze zählen,
  aber der angefangene Satz ist weg. So steht es in der Spec, und so ist es gebaut.

### Nach Stufe B

- **Stufe C (M4-09) und Stufe D (M4-10)** — so vorgesehen, §2 des Handoffs gibt die Reihenfolge
  vor. Vor Stufe C sind zwei ADRs fällig (§6).
- **`by_rating` als Setzungsmodus** ist zurückgestellt (Entscheidung r0btoshi, in `05_TOURNAMENT`
  §9 mit Datum eingetragen). Das Verfahren steht in `bracket.lua`; was fehlt, ist die Rangliste
  aus den Vorturnieren desselben Abends. Vor dem zweiten Turnier des Abends ist der Modus
  ohnehin wirkungslos.
- **Kein Matchstart aus dem Turnier heraus.** Gespielt wird daneben, das Ergebnis trägt der
  Turnierleiter ein. Das ist nicht bloß Verzicht: Es ist derselbe Weg, den `11_OPS` als
  Notbetrieb vorsieht, wenn die Automatik ausfällt — und er ist damit einmal wirklich gelaufen
  statt nur aufgeschrieben.
- **Kein Umbenennen eines Teilnehmers.** Es gibt kein Log-Ereignis dafür, und eines zu erfinden
  hieße, Stufe A anzufassen. Wer sich vertippt, streicht den Eintrag und tippt neu — der Name
  ist danach wieder frei, und genau das steht als Testfall drin.
- **`05_TOURNAMENT` §13.1 („8er ohne manuellen Eingriff") ist in Stufe B nur zur Hälfte
  entscheidbar.** Aufruf, Freilose, Fortschreibung, Walkover und das Ende brauchen null
  Eingriffe — das ist gemessen. Die Ergebniseingabe ist selbst ein Eingriff, aber sie ist der
  Platzhalter für den Match-Host aus E-08. Die Abnahme ist damit erst nach Stufe C vollständig
  zu beantworten, und das sollte niemand als bestanden verbuchen, bevor sie es ist.

### Nach Stufe A (unverändert gültig)

**Eine echte Lücke, die benannt gehört:** `05_TOURNAMENT` §11 verlangt fünf Statistiken je
Spieler. Vier davon (Matches, Sätze, Punkte für/gegen) fallen im Turniermodul an und werden
geführt. **Längste Rallye und schnellster Ball fallen in der Simulation an**, nicht hier — sie
müssen mit dem Ergebnis vom Match-Host mitkommen. Das Ereignis `match_finished` trägt heute
nur die Sätze. Der Platz dafür ist da (das Ereignis ist eine offene Tabelle), aber die
**Übergabe gehört zu M4-09** und ist dort mitzudenken, sonst fehlen sie bei der Siegerehrung.

---

## 3. Befunde

### Fehler im eigenen Code — die ersten zwei von den Tests, die letzten zwei vom Bild

| ID | Befund |
|----|--------|
| **B-T-01** | **Ein abgebrochenes Match behielt seinen Sieger.** `match_aborted` setzte den Status auf `pending` zurück, ließ aber `winner` und `loser` stehen. Über `winner_of:` wanderte dieser Sieger weiter ins Folgematch — das Bracket lief also mit einem Ergebnis weiter, das gerade für ungültig erklärt worden war. Gefunden vom E-06-Test. Behoben |
| **B-T-02** | **Der Scheduler drehte sich nach dem Turnierende im Kreis.** Bei reinem Round Robin bleibt „Gruppenphase vollständig" nach dem letzten Match für immer wahr; `stepGroupStage` hängte deshalb `tournament_finished` endlos an. Der Statusriegel saß nur in `update`, nicht in `tick`. Behoben — und die Schleifenbremse (`MAX_PASSES`) hat genau das getan, wofür sie da ist |
| **B-T-03** | **Ein Freilos machte seinen Sieger zu seinem eigenen Verlierer** — ein Fehler aus Stufe A, aufgefallen erst in Stufe B. `finishMatch` bestimmte den Verlierer mit `(winner == m.slotA) and m.slotB or m.slotA`. Bei einem Freilos ist der Gegnerslot **leer**, der Ausdruck fällt deshalb auf `slotA` durch — also auf den Sieger. Folgen: eine Niederlage in der Statistik, die niemand erlitten hat (bei 20 Teilnehmern zwölf Mal), und eine `loser_of`-Referenz, die auf den Sieger zeigt. **Kein Test der Stufe A hat das gesehen**, weil keiner die Statistik eines Freilos-Siegers gelesen hat; sichtbar wurde es in der Teilnehmerliste am Beamer, die die Zahlen zum ersten Mal anzeigt. Behoben, mit Regressionstest in `tournament_model_test.lua` |
| **B-T-04** | **Dieselbe Falle noch dreimal, im neuen Code.** `x and a or b` fällt auf `b` durch, sobald `a` `nil` ist — und ein unbesetzter Slot ist genau das. Im Baum blieben unentschiedene Paarungen dadurch **unsichtbar** statt leer (`ipairs{nil, nil}` läuft null Mal), und der eigene nächste Gegner war man selbst, solange der Gegner noch nicht feststand. Alle Vorkommen des Musters in den neuen Dateien durchgesehen und ersetzt; die drei Stellen tragen jetzt einen Kommentar, weil das Muster sonst beim nächsten Mal wieder hineinrutscht |

### Lücken in der Spezifikation

Alle vier sind beim Bauen aufgefallen, nicht beim Lesen. Das ist der übliche Weg: §5 liest sich
vollständig, bis man den Automaten hinschreibt und merkt, dass zwei Kanten fehlen.

| ID | Befund | Erledigt |
|----|--------|---|
| **F-T-01** | **§5 ist in sich widersprüchlich.** Für `pending → ready` verlangt er, dass **beide Spieler online** sind. Der No-Show-Timer läuft aber erst ab dem `calling`, also ab `ready`. Ein Spieler, dessen Rechner aus ist, hält sein Match damit **für immer** in `pending` — der Timer, der den Fall lösen soll, startet nie. Bei einem K.o.-Baum steht danach das halbe Turnier | **E-16** neu, ADR-021 |
| **F-T-02** | **E-02 regelt den No-Show für einen Spieler.** Erscheint keiner, gibt es keinen anderen, an den der Walkover gehen könnte | **E-15** neu, ADR-021 |
| **F-T-03** | **E-11 endet mit „Stichsatz auf 7 Punkte. Kein Münzwurf."** Bei einem Dreifach-Gleichstand ist der Stichsatz ein Mini-Turnier aus drei Sätzen — und das kann wieder 1–1–1 ausgehen. Ohne Abbruchbedingung ist die Terminierung des Turniers nicht zusicherbar | **E-17** neu, ADR-021 |
| **F-T-04** | **Widerspruch innerhalb von `05_TOURNAMENT`:** §2 sagt „Best-of-3 ab Viertelfinale", der Kommentar an `bestOfFinals` in §4 sagt „ab Halbfinale" | §2 berichtigt |

### Neu aus Stufe B

| ID | Befund | Erledigt |
|----|--------|---|
| **F-T-08** | **Die Anmeldung eines Turniers ist kein Anwendungsfall der Lobby aus M2.** `src/net/lobby.lua` hat `MAX_SLOTS = 2` und startet genau ein Match; `src/net/host.lua` erzeugt den ENet-Wirt mit acht Peers. Ein Turnier braucht 20 dauerhaft verbundene Teilnehmer, eine Anmeldenachricht mit Namen und den Rundfunk des Turnierstands — also einen **zweiten Wirt-Typ**. Genau dessen Nachricht (`TOURNAMENT_STATE`, 0x40) ist reserviert und **ohne Format**: ADR-016 hat es offengelassen, ADR-020 hat es bewusst nicht mitentschieden. Wer die Netz-Anmeldung in Stufe B baut, entscheidet diesen ADR nebenbei oder wirft den Code in Stufe C weg | Grenze gezogen, §5.1 |
| **F-T-09** | **Der Hinweis „Gleichstand — Stichsatz" hing am falschen Merkmal.** Er stand an jedem ungelösten Tabellenblock — und vor dem ersten Spieltag steht in **jeder** Gruppe alles gleich, also stand er von Anfang an über allen Tabellen. Angezeigt wird er jetzt unter genau der Bedingung, unter der der Scheduler den Stichsatz ansetzt (Gruppe durchgespielt und der Gleichstand liegt auf der Trennlinie). Der Punkt ist allgemeiner: **Eine Anzeige, die eine Bedingung selbst formuliert statt sie zu erfragen, formuliert sie irgendwann anders als der Automat** | §10 ergänzt, `Session:tiebreakPending` |
| **F-T-10** | **Die Zeichenroutinen sind von keinem Headless-Test erfasst** — und beide Fehler dieser Sitzung (B-T-03, B-T-04) waren nur im Bild zu sehen. Geprüft wurde deshalb mit einem **wegwerfbaren** Skript, das die Szene über Tastendrücke fährt und sechs Bildschirmfotos schreibt; danach ist es gelöscht. Das ist kein Ersatz für einen Test, aber es hat zwei echte Fehler gefunden, die in 412 grünen Fällen nicht auffielen. **Für M5 (Beamer-Szene) gehört das dauerhaft ins Werkzeug**, nicht wieder als Wegwerfstück | offen, Hinweis für M5 |

### Neu aus Stufe C — fünf Fehler, und keiner davon war in 445 grünen Testfällen zu sehen

Das ist der eigentliche Befund dieser Sitzung. **Alle fünf sind erst im Vierprozesslauf
aufgefallen**, keiner im Headless-Runner und keiner im Selbsttest — und drei davon hätten am
Partyabend das Turnier zum Stillstand gebracht, nicht bloß gestört.

| ID | Befund |
|----|--------|
| **C-T-01** | **Die Turnierverbindung starb während des Matches.** Nur die oberste Szene bekommt `update` (`src/app/scene.lua`), und während eines Matches liegt der Turniermodus darunter — sein ENet-Wirt wurde vier Minuten lang nicht bedient. Nach 5 s Peer-Timeout galt **jeder Teilnehmer als offline**, der No-Show-Timer lief gegen Leute, die gerade spielten, und der Ergebnisbericht fand am Ende niemanden mehr. Gemessen: Das Turnier blieb nach dem ersten Match stehen. Behoben, indem die Verbindung mit ins Match wandert — **derselbe Fehler und dieselbe Lösung wie bei der Bake in M2** (D2, 2026-08-12). Dass er ein zweites Mal auftrat, ist der eigentliche Hinweis: „Nur oben bekommt `update`" ist eine Falle, die jedes Mal zuschlägt, wenn eine Szene etwas besitzt, das weiterlaufen muss |
| **C-T-02** | **`disconnect_now` verwarf die letzte Nachricht.** Der Match-Wirt schickte `MATCH_END` und räumte im selben Atemzug auf; `Host:close` trennte die Peers **vor** dem `flush`, und ENet wirft dabei alles weg, was für diesen Peer noch in der Warteschlange steht. Beim Gast kam nichts an — er blieb auf dem Endstand stehen, und das Turnier wartete auf ihn. Behoben: erst hinausschieben, dann trennen, dazu eine halbe Sekunde Nachlauf, bevor der Socket zugeht. **Das betraf auch das freie Spiel**, nur fiel es dort nie auf, weil danach niemand auf eine Nachricht wartet |
| **C-T-03** | **Ein nil-Feld fiel über `__index` auf eine gleichnamige Methode durch.** Der Statistik-Beobachter hieß `self.stats`, und `NetGame:stats()` gibt es seit M3 für das Netz-Overlay. Beim Gast ist der Beobachter `nil` — und `self.stats` lieferte damit die **Methode**, also einen wahrheitswerten Wert, der `toReport` nicht kennt. Der Gast stürzte beim Abpfiff ab. Umbenannt in `matchStats`. Das Muster ist allgemeiner als der Fall: **In einer Klasse mit Metatabelle ist jedes optionale Feld, das so heißt wie eine Methode, eine Falle** — `x and x:f()` prüft dann nicht, ob es das Feld gibt, sondern findet immer die Methode |
| **C-T-04** | **Best-of-3 hatte keinen zweiten Satz.** Der Satzzähler stand richtig da (`MatchRunner:addSet`), aber der Rückruf, der „noch ein Satz" hätte melden sollen, gab seinen Wert nicht zurück — eine fehlende `return` in einer Closure. Folge: Im **Finale** blieben beide Seiten auf dem Endstand stehen und das Turnier wartete auf ein Ergebnis, das nie kam. Es traf ausgerechnet die vier Matches, in denen `bestOfFinals` gilt, also die, die zählen. Behoben; der Weg für den nächsten Satz ist jetzt derselbe wie die Revanche im freien Spiel |
| **C-T-05** | **Ein Socket wurde mitten in seiner eigenen Ereignisschleife geschlossen.** Der Ergebnisrückruf kommt aus `Client:service` heraus, und diese Schleife leert die Queue in einem `while` — wer ihr dabei den Wirt wegzieht, bekommt beim nächsten Durchlauf `attempt to index field 'host' (a nil value)`. Aufgeräumt wird jetzt einen Frame später, in `update`. **Das ist keine Turnierbesonderheit:** Jeder Rückruf aus einer ENet-Schleife darf den Wirt nicht anfassen, und bis Stufe C hat das nie jemand gebraucht |

**Was diese fünf gemeinsam haben:** Keiner ist ein Fehler in einer Turnierregel. Alle fünf
sitzen an der Naht zwischen zwei Dingen, die für sich genommen richtig sind — Szene und
Netzschicht, Feld und Methode, Rückruf und Schleife. Genau deshalb hat sie kein Test der
Ebenen A und B gefunden: **Die Nähte sind nicht headless prüfbar, und die Wahrheit über sie
steht in keinem der beiden Module.** Der Vierprozesslauf ist die einzige Prüfung, die sie
sieht, und er gehört deshalb dauerhaft ins Werkzeug und nicht in den Papierkorb (Fortsetzung
von F-T-10).

### Kleinere Befunde aus Stufe C

| ID | Befund | Erledigt |
|----|--------|---|
| **F-T-11** | **E-14 und `04_NETCODE` §5 widersprechen sich beim doppelten Namen.** E-14 sagt „Namensdopplung wird beim Beitritt abgelehnt", §5 sagt „durch Anhängen, nicht durch Ablehnen" — und begründet das mit den 90 Sekunden aus dem Charter. Aufgelöst nach dem, wofür die beiden Regeln da sind: Ist der Namensträger gerade **offline**, ist es ein Wiedereintritt und der Name führt zurück auf denselben Teilnehmer (das meint E-14). Ist er **online**, sind es zwei Leute mit demselben Namen und der zweite bekommt „ 2" angehängt (das meint §5). Beide Regeln tun damit ihre Arbeit, und niemand wird ins Menü zurückgeschickt | in `session.lua` umgesetzt, Begründung im Code |
| **F-T-12** | **Die Discovery-Bake trug feste Angaben.** `Discovery.newHost{ info = … }` nahm nur eine Tabelle; für eine Match-Lobby stimmt das (zwei Plätze, ein Name), für ein Turnier nicht — dessen Teilnehmerzahl ändert sich den ganzen Abend, und die Bake hätte ab dem zweiten Beitritt **still** eine falsche Zahl gesendet. `info` darf jetzt auch eine Funktion sein | `discovery.lua`, eine Zeile |
| **F-T-13** | **`lobby:isStartable()` passt nicht auf ein Turniermatch.** Es verlangt zusätzlich den Bereitschaftsschalter beider Plätze — den gibt es im Turnier nicht, weil bereit gemeldet wird beim Turnier-Wirt (`MATCH_ACCEPT`). Ein zweites Mal danach zu fragen wäre eine Hürde ohne Bildschirm, auf dem man sie erfüllen könnte. Das Turniermatch startet, sobald der zweite Platz belegt ist | `tournament.lua`, mit Begründung im Code |

### Aus dem ersten CI-Lauf mit den Selbsttests (Lauf 34)

Drei Befunde, und keiner davon ist ein Fehler im Produkt: einer sitzt im Test, einer in der
Konfiguration des Testlaufs, einer in der Diagnose. Der Reihe nach aufgetreten, weil jeder den
nächsten erst sichtbar gemacht hat.

| ID | Befund | Erledigt |
|----|--------|---|
| **C-T-06** | **T-N-09 prüfte eine Lage, die es nie gibt.** Der erste Aufbau ließ drei Baken **denselben** Discovery-Port binden. Unter Windows und Linux geht das mit `SO_REUSEADDR`, unter macOS nicht — und die CI hat es zu Recht gemeldet. Der Punkt ist aber nicht die Portteilung: Am Partyabend stehen die drei Turniere auf **drei Rechnern**, und dort bindet jeder seinen Port allein. Ein Test, der drei Binds auf einem Port erzwingt, prüft eine Lage, die nicht vorkommt, und fällt dann ausgerechnet auf der Plattform um, auf der er es am wenigsten soll. **Das Produkt war nie betroffen** — `newBrowser` verträgt einen gescheiterten Zweitbind seit M2 ausdrücklich. Neu gebaut nach dem, was T-N-09 wirklich fragt: Hält der Browser drei Turniere auseinander? Die Baken binden dafür flüchtige Ports und schicken ihre Ankündigung direkt an den Browser — genau das tun sie in echt auch, wenn sie einen `PROBE` unicast beantworten. Dazu ein Fall mehr als vorher: **dieselbe `hostId` zweimal ergibt keinen zweiten Eintrag** | behoben |
| **C-T-07** | **`--tournament-selftest` fehlte in der Headless-Liste von `conf.lua`.** Der Lauf startete damit **mit Fenster, Grafik und Audio** — auf einem Läufer ohne Bildschirm bleibt er stehen, bis die Zeitschranke ihn abbricht. Lokal fiel nichts auf, weil hier ein Desktop existiert. Behoben; `conf.lua` trägt jetzt die Faustregel dazu: Ein Flag, das `M.runTools` bedient, gehört in die Liste — die Autopiloten (`--net-auto-*`, `--tournament-auto=`) ausdrücklich nicht, die fahren das echte Spiel und brauchen das Bild |
| **C-T-08** | **Ein abgebrochener Schritt hinterließ ein leeres Protokoll — zweimal hintereinander.** Erst puffert LÖVE seine Ausgabe im Redirect (behoben mit `setvbuf`), dann brach die Zeitschranke den Schritt ab, **bevor** das nachgelagerte `cat` drankam — drei Minuten, null Zeilen. Beides ist derselbe Denkfehler: Diagnose, die erst nach dem Lauf passiert, gibt es bei einem Abbruch nicht. Die Schritte benutzen jetzt `tee`; damit steht alles im Joblog, **während** es passiert |

### Aus Lauf 37 — der einzige Fehlschlag lag in einem M3-Werkzeug

| ID | Befund | Erledigt |
|----|--------|---|
| **C-T-09** | **Der Vorhersagetest unter Eingabeverlust prüfte das Replay, nicht die Vorhersage.** Er unterschlug drei **aufeinanderfolgende** INPUT-Pakete von fünfzehn, mit der Begründung, damit sei die dreifache Redundanz aus §7 überwunden. Das rechnet sich nicht auf: Ein Paket trägt `{t, t-1, t-2}`; fallen `t`, `t+1` und `t+2` aus, bringt Paket `t+3` die Masken `t+1` und `t+2` doch wieder mit. Unwiederbringlich verloren war **genau ein Tick** — und ob ein einzelner Tick mehr als 2 px Abweichung erzeugt, hängt daran, wo im Replay er landet. Windows fiel auf die eine Seite, macOS auf die andere. Jetzt fällt die Eingabe für ein zusammenhängendes Fenster von 120 Ticks ganz aus, und die Eingabe kommt **nicht** aus dem Replay, sondern ist eine gefahrene Bewegung (links, rechts, links): Der Host wiederholt im Ausfall die letzte Maske und läuft damit zwangsläufig in die falsche Richtung. Die Abweichung ist nicht mehr wahrscheinlich, sondern zwingend | behoben |
| **C-T-10** | **Der zweite Prüfsatz desselben Blocks war nur zufällig grün.** „Der Blob steht danach wieder beim Host" vergleicht auf **3 px** genau. An einem laufenden Blob ist das nicht zu halten — allein der Anzeigepuffer von zwei Ticks (§8) sind bei Laufgeschwindigkeit rund 13 px; man misst dann den Puffer und nicht die Vorhersage. Bestanden hat er bisher, weil der Blob im getroffenen Replay-Ausschnitt praktisch stillstand. Die gefahrene Eingabe steht deshalb die letzten 60 Ticks still, und erst dann wird verglichen — die Aussage ist damit wieder die, die sie sein soll: **der Gast hat aufgeschlossen** | behoben |

**Zur Zahl der Korrekturen (2):** Das ist nicht knapp, sondern richtig. Während des Ausfalls
kommt beim Host keine Eingabe an, also steht sein `ackInputTick` still — und ADR-017 gleicht
ausdrücklich gegen den bestätigten Tick ab und nicht gegen die Gegenwart. Es gibt deshalb genau
zwei Ereignisse: das Auseinanderlaufen am Anfang und das Aufschließen am Ende. Über drei Läufe
identisch, samt Endposition auf zwei Nachkommastellen.

**Was ich von hier aus nicht belegen kann:** ob der Fall auf macOS stabil ist. Die Abweichung
ist jetzt so groß wie das halbe Feld statt zwei Pixel, damit ist die Marge um Größenordnungen
besser — aber die Aussage macht der nächste CI-Lauf, nicht ich.

### Aus dem ersten echten LAN-Abend (2026-08-13) — Stufe C.1

**Der kritische Pfad hat gehalten.** Beitreten über die Serverliste, Zuweisung, Match zwischen
zwei Nicht-Hosts, Ergebnis zurück ins Bracket, nächste Runde — über echte Rechner, Windows und
macOS gemischt. **Damit ist die Firewall-Frage für den ephemeren Match-Port beantwortet:** Er
kommt durch. Das war der Grund, warum vier Rechner nötig waren, und es hat funktioniert.

Was nicht gehalten hat, sind fünf Dinge — und alle fünf sind in Stufe C entstanden.

| ID | Befund | Erledigt |
|----|--------|---|
| **C-T-11** | **Die HUD-Namen waren beim Gast vertauscht.** Derselbe Stand las sich auf zwei Rechnern spiegelverkehrt: „Slime 0 / r0b 6" gegen „Slime 6 / r0b 0", bei identischem Bild — r0b links und blau auf beiden, der Name einmal links und einmal rechts. `Hud.draw` ordnet `names[1]` dem **Slot 1** zu; die Turnier-Szene übergab dagegen stur `{eigener, Gegner}`. Wer als Gast auf Slot 2 sitzt, beschriftete damit den Host mit seinem eigenen Namen. Die Punktzahlen waren nie falsch, nur die Beschriftung. `LobbyScene:names()` macht es seit M2 richtig — ich hatte es in der neuen Szene nachgebaut statt benutzt | behoben |
| **C-T-12** | **Der No-Show-Timer zeigte beim Teilnehmer 15 Minuten statt der eingestellten drei.** Das Log trägt **Host-Zeitstempel**: `calledAt` ist `love.timer.getTime()` beim Wirt, also Sekunden seit **dessen** Prozessstart. Der Teilnehmer rechnete `deadline − seine eigene` Prozesszeit — die Differenz zweier Startzeitpunkte. Lief der Wirt zwölf Minuten länger, kamen fünfzehn heraus. In Stufe B gab es nur einen Prozess, deshalb konnte das nie auffallen. Der Versatz kommt jetzt aus dem PING des Turnier-Wirts, den es zweimal je Sekunde ohnehin gibt; die Szene rechnet durchgehend mit **einer** Uhr | behoben |
| **C-T-13** | **ESC im Match warf einen aus dem ganzen Turnier, ohne Weg zurück.** `net_game` ruft mitten im Satz `leaveNet()`, und das räumt seit M4-09 auch den Turniermodus ab — der hält jetzt Sockets. Man kam zwar wieder herein und sah, gegen wen man dran ist, aber weder von allein noch über eine der angeschriebenen Tasten zurück ins Match: Der Turnier-Wirt führte die Zuweisung als **angenommen** und schickte sie nicht erneut. Beim *nächsten* Gegner klappte es, weil das eine neue Zuweisung ist — genau so beobachtet. Jetzt wird nur das Match verlassen, die Bereitmeldung mit `MATCH_ACCEPT{ready=false}` zurückgenommen, und der Wirt zieht die Folge: läuft das Match noch nicht, wird neu zugewiesen; war der Aussteiger der **Match-Wirt**, greift E-06 (neu ansetzen, kein Walkover); war er der Gast, hält ihm der Match-Wirt 30 s frei (`04_NETCODE` §12) — das ist der Wiedereinstieg, den es seit M2 gibt | behoben |
| **C-T-14** | **Jeder sah die Bedienhinweise, nur der Turnierleiter konnte sie ausführen.** Die Tasten waren für Teilnehmer stummgeschaltet, die Fußzeile wusste nichts davon. Angeschriebene Tasten, die nichts tun, sind schlechter als keine Fußzeile — sie laden zum Probieren ein, und genau das ist passiert | behoben |
| **C-T-15** | **Die Einstellungen lagen hinter der gesamten Namensliste.** Gemeldet als „erst ESC drücken und mit der Pfeiltaste durch alle Namen nach unten". Das Namensfeld stand seit M4-07 ganz oben und der Cursor sprang beim Betreten hinein — richtig, solange der Turnierleiter zwanzig Namen tippen musste. Seit sie sich über das Netz anmelden, ist das Tippen der **Notbetrieb** und lag trotzdem im Weg. Jetzt: Format, Parallelität, Setzung, Seed und „Auslosen und starten" zuerst, die Anmeldung („von Hand") darunter, die Liste zuletzt. Der Weg zu den Einstellungen ist damit unabhängig von der Teilnehmerzahl — es gibt einen Testfall, der genau das festnagelt | behoben |
| **C-T-16** | **Nach dem Abpfiff riss es einen sofort ins nächste Match.** „Man spielt zu Ende, sieht 1 s die Lobby und ist direkt im nächsten Spiel." Zwei Ursachen: Die Matchszene wurde im Moment des Ergebnisses abgeräumt, und die nächste Zuweisung wurde ohne Pause angenommen. Jetzt bleibt der Endstand **fünf Sekunden** stehen (ESC kürzt ab), danach folgen **drei Sekunden** im Bracket, bevor die nächste Zuweisung greift. Die geht dabei nicht verloren — der Wirt wiederholt sie alle zwei Sekunden, bis sie angenommen ist. Die Frist läuft ab dem Auftauchen der Szene und nicht ab dem Abpfiff: Während der Endstand steht, bekommt der Turniermodus kein `update`, und eine dort gestartete Frist wäre beim Auftauchen längst abgelaufen | behoben |

**Was diese sechs gemeinsam haben — wieder dasselbe wie bei C-T-01 bis C-T-05:** Keiner ist ein
Fehler in einer Turnierregel. Alle sitzen an einer Naht, und drei davon (C-T-11, C-T-12, C-T-13)
sind erst dadurch entstanden, dass es seit Stufe C **zwei Prozesse mit zwei Uhren und zwei
Rollen** gibt. Der Vierprozesslauf findet sie; der Selbsttest kann es nicht, weil er die Szene
nicht fährt.

### Der Ball-Verzug beim Gast — kein Fehler, sondern die Architektur

Gemeldet mit ungewöhnlicher Präzision: **Eingaben flüssig, aber der Ball wird nicht außen am
Blob getroffen, sondern mitten im Blob — und nur im Sprung, nicht im Stehen.** Auf jedem
Nicht-Host-Rechner, Windows wie macOS, gegen jeden Host.

Das ist die sichtbare Folge zweier Entscheidungen, die für sich richtig sind: Der Gast sagt
seinen **eigenen Blob** vorher und zeigt ihn im Jetzt (ADR-017); den **Ball** zeigt er zwei
Ticks verzögert aus dem Snapshot-Puffer (`04_NETCODE` §8). Blob bei T, Ball bei T − 33 ms. Im
Stehen bewegt sich der Blob kaum und es fällt nicht auf; im Sprung bewegt er sich schnell, und
dann sieht man die 33 ms als Eindringtiefe.

**Das korrigiert eine Annahme, die seit ADR-019 im Log steht.** N-01 wurde zurückgestellt, weil
über Kabel die RTT bei 1–2 ms liegt. Das stimmt — nur hat der Effekt **nichts mit RTT zu tun**.
Der Puffer sind 33 ms auch bei RTT null. Es ist keine Netz-, sondern eine Anzeigefrage, und sie
ist ohne WLAN und ohne Paketverlust reproduzierbar.

Drei Wege, keiner umsonst:

| Weg | Preis |
|---|---|
| Ball zwei Ticks extrapolieren | genau das, was N-01 als Frage stellt; wird bei Richtungswechsel sichtbar zappeln |
| Eigenen Blob zum **Zeichnen** ebenfalls verzögern | Blob und Ball wieder konsistent, dafür 33 ms Eingabeverzögerung — also das, was die Vorhersage abschaffen sollte |
| `Client.BUFFER_TICKS` von 2 auf 1 senken | halbiert den Effekt, kostet Ruckelfestigkeit bei Jitter; über Kabel vertretbar |

**Empfehlung: der dritte zuerst**, weil er billig und messbar ist, und die Extrapolation nur,
wenn er nicht reicht. Das ist eine ADR-Entscheidung und gehört nicht in eine Fehlerbehebung —
deshalb hier als Befund und nicht als Änderung.

### Bestätigt, nicht neu

| ID | Befund |
|----|--------|
| **F-T-05** | **`math.random` ist für die Auslosung unbrauchbar** — das Handoff hatte es angekündigt, hier ist die Bestätigung aus der Umsetzung. Der Generator in `bracket.lua` ist ein LCG mit den Konstanten aus Numerical Recipes; die Multiplikation bleibt exakt in einem double (7,15e15 < 2^53), also reine Arithmetik ohne Bit-Bibliothek. Zwei Testfälle nageln den djb2-Wert zweier Seed-Texte fest: Ändert sich das Verfahren, ergibt derselbe angeschriebene Seed ein anderes Bracket — und genau das darf nicht unbemerkt passieren. **Die Prämisse ist jetzt plattformübergreifend geprüft:** Die 36 Bracket-Fälle sind in der CI auf `ubuntu-latest`, `windows-latest` und **`macos-latest`** durchgelaufen — also auch dort, wo LuaJIT ohne JIT im Interpreter läuft (`04_NETCODE` §1). Das ist die Plattform, wegen der der eigene Generator überhaupt existiert |
| **F-T-06** | **Ein Halbfinalverlierer ist nicht ausgeschieden** — er spielt um Platz 3. Klingt selbstverständlich, ist es beim Bauen des Teilnehmerstatus nicht: Der erste Anlauf hat ihn als `eliminated` geführt. Für `bracket_view.lua` (M4-08) heißt das, dass „raus" und „hat kein offenes Match" zwei verschiedene Dinge sind |
| **F-T-07** | **`goto` gibt es in Lua 5.1 nicht.** `CLAUDE.md` §12 nennt `lua tests/run_headless.lua` **ohne** LÖVE als gleichwertigen Testweg; dort ist LuaJIT nicht garantiert. Die Schleife im Scheduler ist entsprechend ohne `goto` geschrieben. Lokal war das nicht nachweisbar — es gibt keinen eigenständigen Lua-Interpreter auf dieser Maschine. **Erledigt durch die CI** (Lauf 31681743683, 2026-08-13): `luajit tests/run_headless.lua` auf `ubuntu-latest` meldet **318 bestanden, 0 gescheitert**, ganz ohne LÖVE im Prozess. Damit ist zugleich die `love`-Freiheit des Moduls nicht mehr nur durch `--test-no-love` behauptet, sondern durch einen Interpreter belegt, der die Bibliothek gar nicht kennt |

---

## 4. Spec-Änderungen

Alle **vor** dem Code eingetragen, wie `CLAUDE.md` §2 es verlangt.

| Datei | Änderung |
|---|---|
| `05_TOURNAMENT` §2 | Berichtigung mit Datum: Best-of-3 gilt **ab Halbfinale**, §4 behält recht. Begründung steht dort — Best-of-3 schon im Viertelfinale legt bis zu vier zusätzliche Sätze auf den kritischen Pfad, und die 90-Minuten-Rechnung ist ohnehin knapp |
| `05_TOURNAMENT` §6 | **E-15, E-16, E-17** neu, mit Verweis auf ADR-021 |
| `09_DECISION_LOG` | **ADR-020** — Persistenzformat JSON mit eigenem Encoder |
| `09_DECISION_LOG` | **ADR-021** — drei Sackgassen bekommen eine deterministische Regel |
| `08_ROADMAP` §2 | Stand von M4-01 bis M4-06 und M4-11 eingetragen |
| `CHANGELOG.md` | `[Unreleased]` |

### Aus Stufe C

Alle **vor** dem Code eingetragen. Die beiden ADRs standen vor der ersten Zeile Code im Log,
wie `CLAUDE.md` §5 es verlangt, und sie wurden vorher freigegeben (§5.3).

| Datei | Änderung |
|---|---|
| `09_DECISION_LOG` | **ADR-022** — Match-Host-Wahl: RTT-Median über 5 s, Schwelle 5 ms, sonst die Setznummer |
| `09_DECISION_LOG` | **ADR-023** — `TOURNAMENT_STATE` überträgt Log-Ereignisse als JSON, nicht den abgeleiteten Zustand |
| `05_TOURNAMENT` §8 | **§8.1** (wer hostet, Kurzfassung) und **§8.2** (Ports, mit der gemessenen Begründung) neu |
| `05_TOURNAMENT` §11 | Woher längste Rallye und schnellster Ball kommen, wem sie zugerechnet werden, in welcher Einheit |
| `05_TOURNAMENT` §12 | **T-01 auf ERLEDIGT**, mit den zwei Berichtigungen gegenüber dem ursprünglichen Vorschlag (Median statt Mittel, Setznummer statt `participantId`) |
| `04_NETCODE` §5 | **0x41 bis 0x46** in der Nachrichtentabelle, die **`s4`-Ausnahme** für 0x40 mit Begründung und Begrenzung, und der Absatz, warum `HELLO`/`REJECT` wiederverwendet werden |
| `08_ROADMAP` §2 | M4-09 auf ✅, Absatz „Stufe C ist abgeschlossen", T-N-09 erledigt |
| `12_OPENSOURCE` §5 | Die beiden Selbsttests laufen in der CI, mit dem, was sie **nicht** beantworten (N-04, N-05) und dem offenen Punkt der Release-Gatterung |
| `.github/workflows/build.yml` | Job `protocol` heißt jetzt „Protokoll und Sockets", führt `--net-selftest` und `--tournament-selftest` zeitbeschränkt aus, und die Build-Jobs hängen an `[test, protocol]` |
| `CLAUDE.md` §12 | Wie der Turniermodus über das Netz läuft, die zwei neuen Abnahmebefehle |
| `CHANGELOG.md` | `[Unreleased]` um Stufe C ergänzt, C-T-01 unter „Behoben" |

**Eine Ehrlichkeit dazu:** F-T-11 bis F-T-13 sind **nach** dem Code entstanden — es sind
Befunde aus der Umsetzung. Keine Regel der Spec wurde durch Code geändert; F-T-11 löst einen
Widerspruch auf, der zwischen zwei Dokumenten schon vorher stand, und begründet die Auflösung
aus dem Zweck beider Regeln.

### Aus Stufe B

**Eine Einschränkung, die dazugehört:** Anders als in Stufe A sind diese Einträge zum Teil
**nach** dem Code entstanden — sie beschreiben Befunde aus der Umsetzung (F-T-09) und den
Zuschnitt einer freigegebenen Entscheidung (`by_rating`). **Keine Regel der Spec wurde durch
Code geändert**; es ist nichts nachträglich passend gemacht worden. Der Fall, für den
`CLAUDE.md` §2 gedacht ist — Code weicht ab, also wird die Spec hinterhergezogen — ist nicht
eingetreten.

| Datei | Änderung |
|---|---|
| `05_TOURNAMENT` §9 | Zwei Nachträge mit Datum: **`by_rating` ist zurückgestellt** (gebaut sind `random` und `manual`), und der sichtbare Seed ist ein **Text**, aus dem eine Zahl gerechnet wird — eine reine Ziffernfolge gilt als Zahl, damit der angeschriebene Wert wieder eingetippt dasselbe Bracket ergibt |
| `05_TOURNAMENT` §10 | Nachtrag mit Datum: F2 schaltet die Ansichten um, und der Stichsatzhinweis hängt an der Bedingung des Schedulers, nicht an einem ungelösten Tabellenblock (F-T-09) |
| `08_ROADMAP` §2 | M4-07, M4-08 und M4-11 auf ✅, Absatz „Stufe B ist abgeschlossen" |
| `CLAUDE.md` §12 | Wo der Turniermodus liegt, welche Tasten er hat, wo der Turnierstand liegt |
| `CHANGELOG.md` | `[Unreleased]` um Stufe B ergänzt, B-T-03 unter „Behoben" |

**Kein neuer ADR.** Stufe B hat keine Architekturentscheidung getroffen, die über die
vorhandenen hinausgeht: Die Anmeldegrenze ist eine Auftragsentscheidung (§5.1) und in
`08_ROADMAP` festgehalten, die beiden ADRs für Stufe C sind unverändert offen.

---

## 5. Entscheidungen für r0btoshi

### 5.3 Aus Stufe C — die zwei fälligen ADRs, beide vor dem Code freigegeben

1. **ADR-022 — wer hostet: Median der RTT über 5 s, erst ab 5 ms Unterschied, sonst die
   Setznummer.**

   Der Inhalt ist nicht der Vergleich, sondern die **Schwelle**. Seit ADR-019 wird über Kabel
   gespielt; dort liegt die RTT bei 1–2 ms, und der Unterschied zwischen zwei Teilnehmern ist
   Rauschen. Ein Maß, das auf Rauschen entscheidet, ist ein Münzwurf mit Messgerät — und den
   schließt §3.2 genauso aus wie den ohne. 5 ms sind weniger als ein Drittel eines
   Simulationsschritts; darunter kann der Unterschied am Match nichts ändern.

   **Die Folge ist Absicht:** Über Kabel ist der Gleichstand der Normalfall. Die Setznummer ist
   damit in der Praxis **die** Regel, die RTT die Ausnahme für den Fall, dass doch jemand im
   WLAN sitzt. Wer das umdrehen will, dreht an der Schwelle, nicht am Verfahren.

   Zwei Abweichungen vom Vorschlag in T-01, beide von dir freigegeben: **Median statt Mittel**
   (ein GC-Ruckler ist ein Ausreißer unter zehn Proben, und der Mittelwert nimmt ihn mit) und
   **Setznummer statt `participantId`** (ADR-021 hat die Setznummer schon zum Schlussanker
   gemacht; zwei Anker für dieselbe Art Frage sind eine Wahrheit zu viel). `05_TOURNAMENT` §12
   ist entsprechend berichtigt.

   **Der Turnier-Host hostet sein eigenes Match immer** — seine RTT zu sich selbst ist null.
   Das ist keine Ausnahme im Code, sondern das Maß, das seine Arbeit tut.

2. **ADR-023 — `TOURNAMENT_STATE` überträgt Log-Ereignisse, nicht den Zustand.**

   Das kippt eine Vorfestlegung aus ADR-020 („über die Leitung zählt Bytezahl und nicht
   Lesbarkeit"), und zwar an ihrer **Prämisse**, nicht an ihrem Argument: Es zählt Bytezahl,
   *wenn der ganze Zustand geht*. Muss er nicht. Das Log ist append-only, die Differenz zweier
   Stände ist damit immer ein Suffix, und ein Suffix kennt keine Invalidierung. Ein Ereignis
   sind ~100 Byte, der Zustand ~30 KB.

   Der Hauptgrund ist trotzdem nicht die Größe, sondern: **kein zweiter Ableitungspfad.** Host,
   Datei und jeder Empfänger rechnen denselben Zustand aus derselben Funktion in derselben
   Reihenfolge — genau die Eigenschaft, die §1a „die eine Entscheidung, die alles andere trägt"
   nennt. Ginge der fertige Zustand über die Leitung, gäbe es einen zweiten Weg, auf dem ein
   Turnierstand entsteht, und beim ersten Auseinanderlaufen wäre nicht entscheidbar, welcher
   recht hat.

   Binär hätte fünfzehn Codecs gebraucht, einen je Ereignisart — das feste Feldlayout, das
   ADR-016 verworfen hat. `src/tournament/json.lua` deckt genau diese Ereignisse ab; das ist
   die Prüfung, die ADR-020 vor einer Zweitnutzung ausdrücklich verlangt, und sie ist bestanden.

   **Preis, der dazugehört:** die erste `s4`-Zeichenkette im Protokoll, begrenzt auf diese eine
   Nachricht und in `04_NETCODE` §5 als Ausnahme eingetragen.

### Was du wissen solltest, ohne dass es eine Entscheidung wäre

- **Der ephemere Match-Port ist neu für die Firewall.** Bis M4 war genau ein Port freizugeben
  (21212); jetzt öffnet jeder Match-Wirt einen Port, den ihm das Betriebssystem gibt. Über
  Loopback ist das geprüft, über ein echtes Netz **nicht** — und N-05 (ob der Windows-Firewall
  bei „öffentlichem" Profil überhaupt etwas durchlässt) steht ohnehin noch offen. **Das gehört
  vor den Abend auf zwei Rechner**, und es ist die einzige Stelle, an der Stufe C betrieblich
  etwas Neues verlangt. Der Ausweg, falls es klemmt, steht schon da: `parallelMatches = 1` —
  dann hostet der Turnier-Host alle Matches, und es bleibt bei einem Port.
- **`05_TOURNAMENT` §13.1 ist jetzt vollständig beantwortet, und die Antwort ist ja.** Der
  Vorbehalt aus §5.1 („die Ergebniseingabe ist selbst ein Eingriff") ist aufgelöst: Im
  Vierprozesslauf gibt es nach der Auslosung **null** Tastendrücke, und das Turnier läuft bis
  zum Sieger durch — Gruppenphase, Stichsatz, Best-of-3-Finale, Statistiken. Das ist der
  Punkt, den ich in Stufe B ausdrücklich nicht verbuchen wollte, bevor er es ist.
- **Ein Artefakt des Werkzeugs, kein Befund:** Im Vierprozesslauf haben alle Spieler dieselbe
  längste Rallye (6,4 s) und denselben schnellsten Ball (1066 px/s). Das liegt an der
  Automatik, die in jedem Match dieselbe Physik erzeugt — mit Menschen an den Tasten stehen da
  verschiedene Zahlen.

### 5.1 Aus Stufe B — vier, davon eine, die den Zuschnitt der Stufe bestimmt

1. **Angemeldet wird am Turnier-Host, nicht über das Netz** (freigegeben vor der Umsetzung).
   Begründung in F-T-08: Die Lobby aus M2 ist eine **Match**-Lobby mit zwei Plätzen, und die
   Nachricht, die ein Turnier bräuchte, hat kein Format. Die Naht ist **eine** Funktion —
   `Session:addParticipant(name)`. In Stufe B füllt sie die Tastatur, in Stufe C das Netz; an
   der Datei ändert sich dabei nichts. Weggeworfen wird davon nichts.

   **Eine Bake sendet der Turniermodus in Stufe B bewusst nicht.** Die Discovery trägt
   `mode = "tournament"` bereits (`protocol.lua`), das kostet nichts — aber ein Turnier
   anzukündigen, dem niemand beitreten kann, ist schlechter als es nicht anzukündigen.

2. **Bedient wird nur in der vollen Ansicht.** Die kompakte ist der Bildschirm eines Spielers;
   dort ein Ergebnis eintragen zu können hieße, sein eigenes eintragen zu können. E-08 sagt
   ausdrücklich, dass das Ergebnis vom Match-Host aus dem Simulationszustand kommt und nicht von
   Spielern gemeldet wird — solange es diesen Host nicht gibt, ist der Turnierleiter sein
   Stellvertreter, und dann sitzt die Eingabe da, wo er sitzt.

3. **Ein Ergebnis lässt sich auch ohne den Umweg über „Match läuft" eintragen.** Der Weg
   `ready → live → finished` ist der saubere, aber am Abend kommt der Turnierleiter oft erst
   zurück, wenn das Match schon vorbei ist. Ein Pflichtschritt, den man nachträglich nicht
   nachholen kann, produziert Falscheingaben. Steht als Testfall drin.

4. **Streichen statt Umbenennen.** Es gibt kein Log-Ereignis für eine Umbenennung, und eines zu
   erfinden hieße, Stufe A anzufassen. Ein gestrichener Name ist sofort wieder frei — wer sich
   vertippt, tippt neu. Kostet fünf Sekunden und hält das Log ehrlich.

**Ein Vorbehalt, der dir gehört:** `05_TOURNAMENT` §13.1 fragt, ob ein 8er-Turnier **ohne
manuellen Eingriff** durchläuft. Die Automatik braucht null Eingriffe, gemessen. Die
Ergebniseingabe ist selbst einer — sie ist der Platzhalter für den Match-Host. Ich würde §13.1
deshalb **nicht** als bestanden verbuchen, bevor Stufe C läuft, auch wenn der Durchlauf steht.

### 5.2 Aus Stufe A (unverändert)

Vier getroffen, alle mit Begründung im ADR. Die ersten beiden sind Architektur, die letzten
beiden Turnierrecht — bei denen widersprich bitte, wenn dir die Regel nicht passt, **bevor**
sie am Abend zum ersten Mal greift.

1. **ADR-020 — der Turnierstand wird als JSON geschrieben, mit eigenem Encoder.**
   Nicht aus Formattreue, sondern weil §7 die Datei ausdrücklich als Versicherung für den Fall
   begründet, dass die Software versagt. Dann macht ein Mensch sie mit einem Texteditor auf.
   Ein Lua-Literal hätte ~150 Zeilen gespart und genau diesen Fall verfehlt. Über die Leitung
   (`TOURNAMENT_STATE`) entscheidet der ADR ausdrücklich **nicht**.

2. **ADR-021 — drei neue Regeln, alle deterministisch.** Beidseitiger No-Show, Offline-Timer,
   Gleichstand nach dem Stichsatz. Der Schlussanker ist überall dieselbe Größe: **die
   Setznummer.** Sie steht vor dem Turnier fest, ist aus dem sichtbaren Seed nachrechenbar und
   ist nicht das Ergebnis der Lage, die sie entscheidet — also das genaue Gegenteil eines
   Münzwurfs.

3. **Best-of-3 ab Halbfinale, nicht ab Viertelfinale.** Das war ein Widerspruch in der Spec,
   keine freie Wahl — aber welche Seite recht behält, war eine. Ab Halbfinale sind es vier
   Matches statt acht mit Best-of-3, und die liegen dort, wo die Länge sportlich etwas wert
   ist. Umzustellen ist es mit einem Wert (`bestOfFinals`), nicht mit Code.

4. **Wer zuerst aussteigt, verschenkt das Match** — auch wenn der Gegner Sekunden später
   ebenfalls aussteigt. Erst wenn **beide** Austritte im Log stehen, bevor der Scheduler das
   Match sieht (zwei Trennungen in derselben Netzwerkabfrage), greift die Setznummer. Das ist
   keine Willkür, sondern die einzige Lesart, die nicht von der Taktfrequenz des Schedulers
   abhängt.

### Zwei Entscheidungen, die vor Stufe C fällig sind — nicht jetzt, aber nicht vergessen

Beide stehen so schon im Handoff §2 unter AP-6, hier nur als Erinnerung mit dem, was Stufe A
dazu vorbereitet hat:

- **T-01: Wer hostet ein Match?** Der Einhängepunkt steht:
  `Scheduler.new(t, { chooseHost = function(match, t) … end })`. Ohne Angabe hostet zurzeit der
  höher Gesetzte — das ist eine **Platzhalterregel** und ausdrücklich nicht die Antwort auf
  T-01. Die Spec schlägt gemessene RTT über 5 s vor, bei Gleichstand die niedrigere
  `participantId`. Als ADR festhalten, dann bauen.
- **Format von `TOURNAMENT_STATE` (0x40).** ADR-016 hat das offengelassen, ADR-020 hat es
  bewusst nicht mitentschieden. `src/tournament/json.lua` existiert jetzt und wäre verfügbar —
  das ist aber **kein Argument**, ihn auch über die Leitung zu benutzen. Dort zählt Bytezahl
  und nicht Lesbarkeit.

---

## 6. Bedienung — die Kurzfassung für den Abend

Menü → **NETWORK MATCH → Turnier**. Liegt ein laufendes Turnier in der Datei, kommt die Frage
nach der Fortsetzung **zuerst** — wer sie übergeht, legt ein zweites Turnier an.

| | |
|---|---|
| Anmelden | Namen tippen, ENTER. Der Cursor bleibt im Feld; ENTF streicht einen Eintrag |
| Einstellen | Format, parallele Matches, Setzung, Seed — LINKS/RECHTS, Seed wird getippt |
| Starten | „Auslosen und starten". Ab vier Teilnehmern, höchstens 32 |
| Ansicht | **F2** — kompakt (Spieler: eigene Linie, nächster Gegner, Restzeit) / voll (Beamer) |
| Auswahl | HOCH/RUNTER, **TAB** wechselt zwischen Matches und Teilnehmern |
| Bedienen | **ENTER** tut, was in der Fußzeile steht · **E** Ergebnis · **K** Korrektur (Begründung ist Pflicht) · **P** Timer anhalten · **A** Match abbrechen · **W** Teilnehmer austragen |
| Ergebnis | `15:12`, ENTER. Best-of-3 nimmt so lange Sätze, bis einer zwei hat |

Der Turnierstand liegt als JSON unter `tournaments/` im Save-Ordner und wird nach **jedem**
Ereignis geschrieben. Wer die Software für tot erklärt, macht die Datei mit einem Texteditor auf
und spielt mit dem Ausdruck weiter — das war der Grund für ADR-020, und in Stufe D kommt der
Export dazu (M4-10).

**Seit Stufe C wird IM Turnier gespielt.** Der Turnierleiter öffnet den Modus, alle anderen
finden ihn in der **Serverliste** und drücken ENTER — von da an passiert alles von allein:
Aufruf, Matchstart, Ergebnis, nächste Runde. Der Turnierleiter greift nur noch ein, wenn etwas
schiefgeht (No-Show-Timer anhalten, Ergebnis korrigieren, Match abbrechen, Teilnehmer
austragen) — genau die fünf Tasten oben.

**Der Notbetrieb bleibt und ist der Weg aus Stufe B:** Fällt das Netz aus, wird daneben
gespielt und der Turnierleiter trägt das Ergebnis mit `E` ein. Das ist kein Rückfallcode,
sondern derselbe Eingang (`Session:enterResult`), den auch der Match-Wirt benutzt — er ist
damit den ganzen Abend über eingeübt und nicht bloß aufgeschrieben.

**Für `11_OPS` heißt das:** Der Ablauf steht jetzt fest und kann eingetragen werden. Eine
Sache gehört dazu, die neu ist — der ephemere Match-Port und die Firewall (§5.3).

---

## 7. Nächster Schritt — Stufe D (AP-7, M4-10)

**Export als Markdown/CSV per Tastendruck**, rund drei Stunden. `05_TOURNAMENT` §7 nennt ihn
„die einzige echte Versicherung": Wenn die Software versagt, macht man mit dem Ausdruck weiter.

### Was dafür schon dasteht

| Was der Export braucht | Wo es liegt |
|---|---|
| Der vollständige Turnierstand | `Session.t` — Teilnehmer, Runden, Matches, Tabellen, Statistiken, alles abgeleitet und aktuell |
| Tabellen in der richtigen Reihenfolge | `Session:standingsOf(groupIndex)` — dieselbe Sortierung, die der Beamer zeigt (E-11) |
| Der K.o.-Baum spaltenweise | `Session:elimColumns()` |
| Die Markierung korrigierter Ergebnisse | `m.overridden` und der Begründungstext im Log (E-12) — **beides gehört in den Export**, sonst ist der Ausdruck geschönter als die Datei |
| Die fünf Statistiken je Spieler | `p.stats`, seit M4-09 vollständig (§11) |
| Dateizugriff | `src/tournament/persistence.lua` ist die **einzige** Datei des Moduls, die `love.filesystem` anfassen darf — der Export gehört dorthin oder daneben, nicht in die Szene |

### Zwei Dinge, die dabei zu bedenken sind

1. **Der Export ist für einen Menschen ohne Software.** Wer ihn ausdruckt, hat gerade keinen
   funktionierenden Rechner mehr. Also gehören dort **Namen** hinein und keine Kennungen,
   **offene Matches** und nicht nur gespielte, und der Hinweis, wer als Nächstes gegen wen
   spielt — genau die Frage, die der Ausdruck beantworten muss.
2. **Ein Tastendruck, nicht ein Menü.** §7 sagt „jederzeit per Tastendruck". Frei ist in der
   vollen Ansicht noch `X`; `E`, `K`, `P`, `A`, `W` und `TAB` sind vergeben (`CLAUDE.md` §12).

### Was danach noch offen ist und nicht zu M4 gehört

- **Das macOS-Paket auf fremder Hardware** und **N-04** (nimmt ENet auf macOS eine eingehende
  Verbindung an?). Beides hängt am selben fehlenden Gerät. **Seit Stufe C wiegt N-04 schwerer:**
  Ein Mac ist jetzt nicht mehr nur potenzieller Lobby-Host, sondern potenzieller **Match-Wirt**
  auf einem ephemeren Port.
- **N-05** (kommt der UDP-Broadcast bei „öffentlichem" Netzwerkprofil überhaupt hinaus) und die
  Erreichbarkeit des **ephemeren Match-Ports** von einem fremden Rechner. Beides gehört in
  denselben Zweirechnertest, siehe §5.3.
- **T-N-02 und T-N-03** (Paketverlust): offen, seit ADR-019 nicht mehr blockierend.
- **N-01** (WLAN-Vorhersage): zurückgestellt. Anleitung und Werkzeug liegen bereit.

---

## 8. Der Startprompt für die nächste Session

```
Lies CLAUDE.md, dann docs/handoffs/CC-05_M4_TURNIER.md §2 "Stufe D" (AP-7) und §4.
Dann docs/handoffs/CC-05_REPORT.md: den Kopf, §5.3 und §7 -- dort stehen die Nähte.
Danach 05_TOURNAMENT §7 (Absatz "Zusätzliche Absicherung: Export"), §10 und §11
sowie E-12 in §6.

Stufe A (Datenmodell, Bracket, Scheduler, Persistenz), Stufe B (Lobby, Seed,
bracket_view, Bedienung) und Stufe C (verteilte Match-Hosts, ADR-022, ADR-023)
sind fertig, geprüft und committet -- davon wird nichts neu gebaut.

Nimm dir nur Stufe D vor: AP-7, also M4-10 (Export als Markdown/CSV per
Tastendruck). Kein Spectator (M5), keine Beamer-Regie (ADR-008), kein Double
Elimination (M6).

Der Export ist für einen Menschen ohne funktionierenden Rechner gedacht -- Namen
statt Kennungen, offene Matches mitsamt der nächsten Paarung, korrigierte
Ergebnisse als solche markiert (E-12). Dateizugriff ausschließlich über
persistence.lua. Ein Tastendruck, kein Menü; frei ist in der vollen Ansicht `X`.

Ausgangszahlen: lovec.exe . --test = 446 bestanden, --test-no-love = 405,
--net-selftest = 49 Prüfungen, --tournament-selftest = 59 Prüfungen,
python tools/verify_replays.py = OK. Was nicht steigen darf, ist die Zahl der
gescheiterten.

Die CI fährt seit M4-09 beide Selbsttests auf windows-latest und macos-latest,
und die Paketjobs hängen daran. Ein Push ist erst fertig, wenn der Lauf grün
ist -- nachsehen mit gh (CLAUDE.md §11), nicht nachfragen.

CC-05_REPORT.md wird fortgeschrieben, nicht neu geschrieben.

Danach dein Plan in maximal 10 Zeilen plus Rückfragen.
```
