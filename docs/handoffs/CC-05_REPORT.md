# CC-05 — Rückmeldung (M4 Turniermodus)

**Datum:** 2026-08-13 · **Auftrag:** `docs/handoffs/CC-05_M4_TURNIER.md`
**Ausgangsstand:** 9f40dc7 (`v0.3.0`) · **Stufe B ab** 72a579a
**Tests:** 411 bestanden, 0 gescheitert (Stufe A: 349, vorher 214) · **ohne `love`:** 380 (Stufe A: 318)
**Netz-Selbsttest:** 47 Prüfungen, alle grün (unverändert)
**Referenzen:** `python tools/verify_replays.py` meldet OK

> **Dieser Bericht wird fortgeschrieben.** Stand der Stufen aus §2 des Handoffs:
>
> | Stufe | Inhalt | Stand |
> |---|---|---|
> | **A** | AP-1 bis AP-4 — Datenmodell, Bracket, Scheduler, Persistenz | ✅ **abgeschlossen** |
> | **B** | AP-5 — Turnier-Lobby, Setzung mit sichtbarem Seed, Bracket-Anzeige | ✅ **abgeschlossen** (M4-07, M4-08, M4-11) |
> | **C** | AP-6 — verteilte Match-Hosts, `TOURNAMENT_STATE` | ⬜ offen, zwei ADRs vorher fällig |
> | **D** | AP-7 — Export (M4-10) | ⬜ offen |
>
> **Die nächste Session fängt bei Stufe C an** — und **zuerst mit zwei ADRs**, nicht mit Code:
> T-01 (wer hostet ein Match) und das Format von `TOURNAMENT_STATE`. Was Stufe B dafür
> vorbereitet hat und wo die Naht liegt, steht in **§7** — dort anfangen zu lesen.
>
> **Die Klänge spielen** (Stufe B): `tournament_call` beim Aufruf des eigenen Matches,
> `tournament_warn` 30 s vor Ablauf des No-Show-Timers, `tournament_done` beim Sieger.
> Vorgaben und Anlass stehen in `docs/handoffs/CC-05_KLANGLISTE.md`.

---

## 0. Was jetzt geht

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

**Gespielt wird in Stufe B neben dem Turnier**, nicht darin: freies LAN-Match oder lokal, und
das Ergebnis trägt der Turnierleiter ein. Das gehört so in `11_OPS`, sobald Stufe C entschieden
ist — bis dahin würde der Ablauf im Runbook zweimal umgeschrieben.

---

## 7. Nächster Schritt — Stufe C (AP-6, M4-09)

**Zuerst zwei ADRs, dann Code.** Beide stehen ausformuliert in §5.2 („Zwei Entscheidungen, die
vor Stufe C fällig sind"): **T-01** — wer hostet ein Match — und das **Format von
`TOURNAMENT_STATE` (0x40)**. Wer vorher anfängt, entscheidet sie nebenbei.

### Was Stufe B dafür bereitgestellt hat

| Was Stufe C braucht | Wo die Naht liegt |
|---|---|
| Anmeldung über das Netz | `Session:addParticipant(name, now, clientId)` — die Funktion nimmt schon eine `clientId`. Stufe C ruft sie aus der Anmeldenachricht statt aus dem Namensfeld |
| Anwesenheit aus der Verbindung | `Session.new{ presence = "net" }` und `Session:setPresence(pid, online)`. Damit hört die Annahme „wer angemeldet ist, ist da" auf zu gelten — mehr ist nicht zu ändern (§1a, Punkt 3) |
| Ergebnis vom Match-Host | `Session:enterResult(matchId, sets, now)` ist genau der Eingang. Heute ruft ihn die Tastatur, in Stufe C die Nachricht des Match-Hosts (E-08) |
| Wer hostet | `Scheduler.new(t, { chooseHost = … })`, von `Session` durchgereicht (`opts.chooseHost`). Die Platzhalterregel „der höher Gesetzte" ist **nicht** die Antwort auf T-01 |
| Was der Beamer anzeigen muss | Nichts Neues. `bracket_view.lua` liest ausschließlich aus `Session`; wenn der Turnierstand über das Netz kommt, ändert sich die Quelle des Modells, nicht die Anzeige |
| Turnier findbar machen | `mode = "tournament"` ist im ANNOUNCE-Nutzlastformat vorhanden (`protocol.lua`). Stufe B sendet bewusst keine Bake (§5.1) |

### Was Stufe A liegen lässt und Stufe C aufsammeln muss

Die beiden Statistiken aus §11, die in der Simulation anfallen — **längste Rallye und
schnellster Ball**. Sie müssen mit dem Ergebnisbericht des Match-Hosts mitkommen;
`match_finished` trägt heute nur die Sätze. Gehört in **M4-09** mitgedacht, sonst fehlen sie
bei der Siegerehrung.

Dazu **T-N-09** (drei gleichzeitige Lobbys im selben Netz), das laut `08_ROADMAP` zur Abnahme
von M4-09 gehört: Mit parallelen Matches ist das kein Sonderfall mehr, sondern der
Normalzustand des Abends.

### Unverändert offen und nicht zu M4 gehörend

Das macOS-Paket auf fremder Hardware und **N-04** (nimmt ENet auf macOS eine eingehende
Verbindung an?). Beides hängt am selben fehlenden Gerät. T-N-02/T-N-03 und N-01 sind seit
ADR-019 zurückgestellt.
