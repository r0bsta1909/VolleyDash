# CC-05 — Rückmeldung (M4 Turniermodus)

**Datum:** 2026-08-13 · **Auftrag:** `docs/handoffs/CC-05_M4_TURNIER.md`
**Ausgangsstand:** 9f40dc7 (`v0.3.0`)
**Tests:** 349 bestanden, 0 gescheitert (vorher 214) · **ohne `love`:** 318 (vorher 183)
**Netz-Selbsttest:** 47 Prüfungen, alle grün (unverändert)
**Referenzen:** `python tools/verify_replays.py` meldet OK

> **Dieser Bericht wird fortgeschrieben.** Stand der Stufen aus §2 des Handoffs:
>
> | Stufe | Inhalt | Stand |
> |---|---|---|
> | **A** | AP-1 bis AP-4 — Datenmodell, Bracket, Scheduler, Persistenz | ✅ **abgeschlossen** |
> | **B** | AP-5 — Turnier-Lobby, Setzung mit sichtbarem Seed, Bracket-Anzeige | ⬜ offen |
> | **C** | AP-6 — verteilte Match-Hosts, `TOURNAMENT_STATE` | ⬜ offen, zwei ADRs vorher fällig |
> | **D** | AP-7 — Export, manuelle Korrektur (Bedienung) | ⬜ offen |
>
> **Die nächste Session fängt bei Stufe B an.** Sie braucht nichts aus Stufe A neu zu bauen;
> die Module sind fertig, geprüft und in der CI auf allen drei Plattformen durchgelaufen.
> Was sie an Zustand vorfindet und wo es liegt, steht in **§6** — dort anfangen zu lesen.
>
> **Die Klänge liegen bereits vor** (r0btoshi, 2026-08-13): `tournament_call`,
> `tournament_warn` und `tournament_done` sind in `assets/`, in `src/app/assets.lua`
> angemeldet und in `CREDITS.md` eingetragen. Stufe B muss sie nur noch abspielen —
> Vorgaben und Anlass stehen in `docs/handoffs/CC-05_KLANGLISTE.md`.

---

## 0. Was jetzt geht

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

---

## 2. Nicht erledigt und warum

**Stufe B, C und D** — so vorgesehen. §2 des Handoffs gibt die Reihenfolge vor, und Stufe A
war ausdrücklich der Auftrag dieser Session.

Zwei Dinge, die man für Lücken halten könnte und die keine sind:

- **Kein Dialog „Laufendes Turnier gefunden — fortsetzen?"** Die Datenseite steht:
  `Persistence:running()` liefert Kennung, Name, Format und die Rundenangabe für den
  Dialogtext, `Persistence.resume()` setzt unterbrochene Matches neu an. Was fehlt, ist die
  Anzeige, und die gehört zu M4-07.
- **Kein `bracket_view.lua`.** Stufe B.

**Eine echte Lücke, die benannt gehört:** `05_TOURNAMENT` §11 verlangt fünf Statistiken je
Spieler. Vier davon (Matches, Sätze, Punkte für/gegen) fallen im Turniermodul an und werden
geführt. **Längste Rallye und schnellster Ball fallen in der Simulation an**, nicht hier — sie
müssen mit dem Ergebnis vom Match-Host mitkommen. Das Ereignis `match_finished` trägt heute
nur die Sätze. Der Platz dafür ist da (das Ereignis ist eine offene Tabelle), aber die
**Übergabe gehört zu M4-09** und ist dort mitzudenken, sonst fehlen sie bei der Siegerehrung.

---

## 3. Befunde

### Fehler im eigenen Code, von den Tests gefunden

| ID | Befund |
|----|--------|
| **B-T-01** | **Ein abgebrochenes Match behielt seinen Sieger.** `match_aborted` setzte den Status auf `pending` zurück, ließ aber `winner` und `loser` stehen. Über `winner_of:` wanderte dieser Sieger weiter ins Folgematch — das Bracket lief also mit einem Ergebnis weiter, das gerade für ungültig erklärt worden war. Gefunden vom E-06-Test. Behoben |
| **B-T-02** | **Der Scheduler drehte sich nach dem Turnierende im Kreis.** Bei reinem Round Robin bleibt „Gruppenphase vollständig" nach dem letzten Match für immer wahr; `stepGroupStage` hängte deshalb `tournament_finished` endlos an. Der Statusriegel saß nur in `update`, nicht in `tick`. Behoben — und die Schleifenbremse (`MAX_PASSES`) hat genau das getan, wofür sie da ist |

### Lücken in der Spezifikation

Alle vier sind beim Bauen aufgefallen, nicht beim Lesen. Das ist der übliche Weg: §5 liest sich
vollständig, bis man den Automaten hinschreibt und merkt, dass zwei Kanten fehlen.

| ID | Befund | Erledigt |
|----|--------|---|
| **F-T-01** | **§5 ist in sich widersprüchlich.** Für `pending → ready` verlangt er, dass **beide Spieler online** sind. Der No-Show-Timer läuft aber erst ab dem `calling`, also ab `ready`. Ein Spieler, dessen Rechner aus ist, hält sein Match damit **für immer** in `pending` — der Timer, der den Fall lösen soll, startet nie. Bei einem K.o.-Baum steht danach das halbe Turnier | **E-16** neu, ADR-021 |
| **F-T-02** | **E-02 regelt den No-Show für einen Spieler.** Erscheint keiner, gibt es keinen anderen, an den der Walkover gehen könnte | **E-15** neu, ADR-021 |
| **F-T-03** | **E-11 endet mit „Stichsatz auf 7 Punkte. Kein Münzwurf."** Bei einem Dreifach-Gleichstand ist der Stichsatz ein Mini-Turnier aus drei Sätzen — und das kann wieder 1–1–1 ausgehen. Ohne Abbruchbedingung ist die Terminierung des Turniers nicht zusicherbar | **E-17** neu, ADR-021 |
| **F-T-04** | **Widerspruch innerhalb von `05_TOURNAMENT`:** §2 sagt „Best-of-3 ab Viertelfinale", der Kommentar an `bestOfFinals` in §4 sagt „ab Halbfinale" | §2 berichtigt |

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

---

## 5. Entscheidungen für r0btoshi

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

## 6. Nächster Schritt — Stufe B (AP-5, M4-07 und M4-08)

Anmeldung, Setzung mit **sichtbarem** Seed, kompakte Ansicht im Spielermenü (eigene Linie plus
„Nächster Gegner"), volle Ansicht für den Beamer. `05_TOURNAMENT` §9 und §10.

### Was Stufe A dafür bereitgestellt hat

Nichts davon ist neu zu bauen. Die Anzeige liest, sie rechnet nicht.

| Was die Anzeige braucht | Wo es liegt |
|---|---|
| Setzliste und sichtbarer Seed | `t.participants[pid].seed`, `t.seedValue`, `t.seedMode` — reproduzierbar über `Bracket.rng`, plattformübergreifend geprüft (F-T-05) |
| Alle Matches in fester Reihenfolge | `t.matchOrder`, `t:matchList()`, `t.rounds` (mit `label` und `stage`) |
| Nächstes eigenes Match | `t:openMatches()` nach `slotA`/`slotB` filtern |
| Gruppentabellen, fertig sortiert | `t.standings[gi].rows` mit `rank`, plus `unresolved` für den Stichsatzhinweis |
| Laufender No-Show-Countdown | `m.calledAt` + `config.noShowTimeout`; die verbleibende Zeit rechnet die Anzeige, den Ablauf entscheidet der Scheduler |
| Dialog „Laufendes Turnier gefunden" | `Persistence:running()` liefert `id`, `name`, `round`, `rounds`, `status` |
| Sichtbare Markierung einer Korrektur | `m.overridden`, `m.overrideReason`, `m.overrideBy` (E-12) |

### Vier Dinge, die dabei nicht untergehen dürfen

1. **Der Aufruf braucht einen Ton** (`05_TOURNAMENT` §5). Das war bis M4-05 eine
   Vorsichtsmaßnahme und ist jetzt eine Notwendigkeit: Der No-Show-Timer ist gebaut und läuft
   wirklich. Wer nichts hört, verliert nach 180 s per Walkover. **Die drei Dateien liegen
   vor und sind geladen** — `Assets.play("tournament_call")` genügt. Dazu gehört
   `tournament_warn` bei 30 s Restzeit (der Grund steht in der Klangliste §3.1) und
   `tournament_done` in der Beamer-Ansicht.
2. **„Raus" und „hat kein offenes Match" sind zwei verschiedene Dinge** (F-T-06). Ein
   Halbfinalverlierer spielt um Platz 3. Der Teilnehmerstatus beantwortet das schon richtig —
   die Anzeige darf ihn nur nicht selbst nachrechnen.
3. **Ein 32er-Baum ist auf einem Laptop unlesbar** (§10). Im Spielermenü gehört die eigene
   Linie hin, sonst nichts. Der vollständige Baum ist die Beamer-Ansicht.
4. **Bei Round Robin ist die Darstellung eine Tabelle, kein Baum** (§10). Beide Formate
   kommen im selben Turnier vor: erst Gruppen, dann K.o.

### Was Stufe A liegen lässt und Stufe C aufsammeln muss

Die beiden Statistiken aus §11, die in der Simulation anfallen — **längste Rallye und
schnellster Ball**. Sie müssen mit dem Ergebnisbericht des Match-Hosts mitkommen;
`match_finished` trägt heute nur die Sätze. Gehört in **M4-09** mitgedacht, sonst fehlen sie
bei der Siegerehrung.

Dazu die beiden ADRs, die vor Stufe C fällig sind (§5 dieses Berichts): **T-01** — wer hostet
ein Match — und das **Format von `TOURNAMENT_STATE`**.

### Unverändert offen und nicht zu M4 gehörend

Das macOS-Paket auf fremder Hardware und **N-04** (nimmt ENet auf macOS eine eingehende
Verbindung an?). Beides hängt am selben fehlenden Gerät. T-N-02/T-N-03 und N-01 sind seit
ADR-019 zurückgestellt.
