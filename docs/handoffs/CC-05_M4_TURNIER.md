# Handoff CC-05 — Turniermodus

**Meilenstein:** M4 · **Aufgaben:** M4-01 … M4-11 aus `08_ROADMAP_BACKLOG.md`
**Geschätzter Aufwand:** 36–48 h · **Abhängig von:** M3 (abgeschlossen, `v0.3.0` veröffentlicht)
**Erstellt:** 2026-08-13 · **Status:** freigegeben zur Ausführung

---

## 0. Lies zuerst

`CLAUDE.md` im Wurzelverzeichnis, dann diese Datei, dann **`docs/05_TOURNAMENT_SPEC.md`
vollständig** — nicht in Auszügen. Das Dokument ist kurz, und §6 (Edge Cases) ist sein
eigentlicher Inhalt: Ein Turniersystem scheitert nie an der Bracket-Logik.

Dazu `docs/handoffs/CC-04_REPORT.md` §0 und §6: dort steht, was M3 hinterlassen hat und was
noch offen ist.

**Das ist der größte Meilenstein des Projekts — drei- bis viermal so viel wie M3.** Er ist
nicht in einer Session zu erledigen, und der Versuch wäre der Fehler. §2 gibt eine Reihenfolge
vor, die nach jeder Stufe einen belegbaren Zustand hinterlässt.

Erst danach fasst du eine Datei an.

---

## 1. Wo das Projekt steht

**`v0.3.0` ist veröffentlicht.** Das Netzspiel funktioniert: Discovery ohne IP-Eingabe, Lobby
mit Ruleset-Abgleich, host-autoritatives Match, Verbindungsabbruch mit 30-s-Fenster und
Wiedereinstieg, Revanche, Vorhersage des eigenen Blobs, Desync-Erkennung. Das Windows-Paket
ist auf einem Fremdrechner gelaufen.

**Was davon M4 trägt** — das ist keine Aufzählung zum Nachschlagen, sondern die Liste dessen,
was du **nicht** neu baust:

| Baustein | Wo | Was M4 damit macht |
|---|---|---|
| Lobby mit Slots, Ready, Abgleich | `src/net/lobby.lua` | Die Match-Lobby eines Turniermatches ist dieselbe |
| Host-autoritatives Match | `src/net/host.lua`, `src/app/scenes/net_game.lua` | Ein Turniermatch **ist** ein Netzmatch. Neu ist nur, wer es anstößt und wohin das Ergebnis geht |
| Ergebnis am Satzende | `Host:endMatch(scoreA, scoreB, reason)` | Genau der Punkt, an dem das Ergebnis an den Turnier-Host geht |
| Walkover nach 30 s | `host.lua`, `RECONNECT_SECONDS` | Vorbild und Bauteil für den No-Show-Timer aus E-02 (dort 180 s) |
| Discovery | `src/net/discovery.lua` | Ein Turnier wird genauso gefunden wie eine Lobby |
| Ruleset-Verteilung und -Hash | `src/sim/ruleset.lua`, §10 im Netcode | Das Turnier friert sein Ruleset beim Start ein (Datenmodell §4) |
| Atomares Schreiben | **gibt es noch nicht** | M4-06. Vorbild ist keins — ADR-007 beschreibt das Verfahren |

**Die Regel, die sich in M2 und M3 bewährt hat und für M4 wieder gilt:** Was **entscheidet**,
ist `love`-frei und läuft im Headless-Runner. Was **transportiert** oder **zeichnet**, darf
`love` benutzen. Konkret für dieses Modul:

| Datei | Abhängig von | Warum |
|---|---|---|
| `src/tournament/model.lua` | nichts | Datenmodell und das append-only Log |
| `src/tournament/bracket.lua` | nichts | Paarungen, Freilose, Tabellenkriterien E-11 |
| `src/tournament/scheduler.lua` | nichts | Zustandsautomat §5, welches Match als Nächstes |
| `src/tournament/persistence.lua` | `love.filesystem` | tmp → bak → rename |
| `src/render/bracket_view.lua` | `love` | Darstellung |

**Die ersten drei tragen die Fehler, die am Partyabend teuer sind.** Ein Bracket, das bei 18
Teilnehmern eine Gruppe mit 2 Leuten baut, fällt nur auf, wenn ein Test es bei 4 bis 32
durchspielt — von Hand probiert das niemand.

**Betriebliche Randbedingung, neu seit ADR-019:** Der Abend läuft über Kabel. Am Turniercode
ändert das nichts, aber die Discovery-Lage ist damit berechenbar: ein Switch, ein Segment.

---

## 2. Auftrag

**Reihenfolge ist Teil des Auftrags.** Jede Stufe endet mit etwas, das man vorführen kann.
Wer mit dem Netzwerkanteil anfängt, hat nach zwei Tagen viel Code und kein Turnier.

### Stufe A — Das Turnier ohne Netzwerk und ohne Bild

#### AP-1 — Datenmodell und Log (M4-01, 4 h)

`05_TOURNAMENT` §4. `src/tournament/model.lua`, `love`-frei.

**Das `log` ist die Wahrheit, der Rest ist abgeleitet.** Das ist keine Formulierung, sondern
die Bauvorschrift: `matches` und `standings` müssen sich jederzeit vollständig aus dem Log neu
berechnen lassen. Ohne diese Eigenschaft ist die Recovery aus §7 nicht baubar, und mit ihr ist
sie fast geschenkt.

**Abnahme:** Ein Test der Ebene B, der ein Turnier aus einem Log rekonstruiert und den
abgeleiteten Zustand gegen den mitgeführten vergleicht — Feld für Feld, nicht stichprobenartig.

#### AP-2 — Bracket (M4-02, M4-02b, M4-03, M4-04, 14 h)

`05_TOURNAMENT` §3 und §6. `src/tournament/bracket.lua`, `love`-frei.

- Single Elimination mit Freilosen an die höchstgesetzten Spieler (E-01)
- Gruppenaufteilung aus beliebiger Teilnehmerzahl, Ziel 4–5 je Gruppe, Rest auf die vorderen
  Gruppen (§3). Bei 18 also 2×5 + 2×4
- Round Robin mit den Tabellenkriterien aus **E-11**, in dieser Reihenfolge: direkter
  Vergleich, Satzdifferenz, Punktdifferenz, erzielte Punkte, dann Stichsatz auf 7.
  **Kein Münzwurf** — die Anti-Zufalls-Doktrin gilt hier genauso wie in der Simulation
- Übergang Gruppen → K.o. mit den zwei Besten je Gruppe

**Abnahme:** Ein Test, der **jede** Teilnehmerzahl von 4 bis 32 durchspielt und für jede prüft:
Jeder Spieler kommt genau einmal je Runde vor, die Summe der Matches stimmt, kein Freilos
landet in Runde 2, keine Gruppe hat weniger als 3 oder mehr als 6 Mitglieder. Dazu E-11 mit
einem konstruierten Dreifach-Gleichstand.

#### AP-3 — Scheduler (M4-05, 5 h)

`05_TOURNAMENT` §5. `src/tournament/scheduler.lua`, `love`-frei.

Zustandsautomat `pending → ready → live → finished` mit den Nebenwegen `walkover`, `aborted`
und `bye`. Dazu: welche Matches sind gleichzeitig spielbar, begrenzt durch
`config.parallelMatches`.

**`ready` setzt beide Spieler online voraus** (§5). Und: **Der Scheduler muss mit weniger
parallelen Matches auskommen, als konfiguriert sind, ohne zu blockieren** — bei geteilten
Geräten ist die Parallelität durch Hardware begrenzt (§2, dritte Konsequenz).

**Abnahme:** Ein 20er-Turnier im Zeitraffer: Alle Matches werden der Reihe nach mit
erfundenen Ergebnissen abgeschlossen, bis ein Sieger feststeht. Kein Match darf zweimal
`live` werden, keines hängenbleiben. Dazu der No-Show-Fall E-02 und der Aussteiger E-04.

#### AP-4 — Persistenz und Recovery (M4-06, 4 h)

`05_TOURNAMENT` §7, ADR-007. `src/tournament/persistence.lua` — die **einzige** Datei dieses
Moduls, die `love.filesystem` anfassen darf.

Atomar: `tmp` schreiben, alte Datei nach `bak`, `tmp` nach `json` umbenennen. **Nach jedem
Log-Ereignis**, nicht nach jedem Match.

**Die Schrittfolge in §7 ist bereits berichtigt — lies sie, bevor du sie baust.** Beim
Vorbereiten dieses Auftrags gemessen: `love.filesystem` hat weder `rename` noch `move`, und
`os.rename` überschreibt unter Windows nicht (unter POSIX schon). Die drei Schritte aus der
ursprünglichen Fassung wären beim zweiten Speichern stillschweigend gescheitert — und ein
Turnier, das nicht gespeichert wird, merkt man erst beim Absturz. Die ausführbare Fassung mit
vier Schritten steht jetzt in §7, samt der Erklärung, warum `.bak` genau das Fenster abdeckt,
in dem kurz keine `.json` existiert.

**Abnahme:** Der Fall aus `05_TOURNAMENT` §13.2 — Turnier in Runde 2 hart abbrechen, aus der
Datei rekonstruieren, ab dem letzten abgeschlossenen Match weiterlaufen. Dazu der hässliche
Fall: eine **halb geschriebene** Datei. Sie darf das Turnier nicht verlieren, dafür gibt es
`bak`.

> **Nach Stufe A muss ein vollständiges 20er-Turnier headless durchlaufen** — angelegt,
> ausgelost, alle 48 Matches gespielt, Sieger, Neustart mittendrin. Ohne Netzwerk, ohne Bild,
> im Testrunner. **Das ist der Punkt, an dem M4 steht oder fällt.** Alles danach ist
> Anbindung.

### Stufe B — Sichtbar machen

#### AP-5 — Turnier-Lobby und Bracket-Anzeige (M4-07, M4-08, 9 h)

`05_TOURNAMENT` §9 und §10. Anmeldung, Setzung mit **sichtbarem** Seed, kompakte Ansicht im
Spielermenü (eigene Linie plus „Nächster Gegner"), volle Ansicht für den Beamer.

**Zum Seed, und das ist ein Fallstrick:** §9 verlangt `random` mit sichtbarem Seed, damit
niemand Manipulation behaupten kann. Das funktioniert nur, wenn derselbe Seed überall dieselbe
Auslosung ergibt. **`math.random` leistet das nicht** — die Zahlenfolge hängt von der
Lua-Implementierung ab, und auf Apple Silicon läuft der Interpreter statt des JIT
(`04_NETCODE` §1). Ein sichtbarer Seed, der auf zwei Rechnern zwei Brackets erzeugt, ist
schlimmer als gar keiner. Es braucht einen eigenen, winzigen deterministischen Generator in
`bracket.lua` — dieselbe Begründung wie beim Ruleset-Hash (`CLAUDE.md` §7).

**Der Aufruf („calling") braucht einen Ton** (§5). Ohne akustisches Signal starrt niemand auf
sein Menü, und der No-Show-Timer läuft gegen jemanden, der nur nichts gehört hat.

### Stufe C — Der kritische Pfad

#### AP-6 — Verteilte Match-Hosts (M4-09, 8 h)

**Nicht optional und keine Ausbaustufe** (ADR-013, `05_TOURNAMENT` §2). Bei 20 Teilnehmern
dauert ein serielles Turnier 3,5 Stunden; nach drei Stunden ist die Party woanders.

Ein Match wird von **einem der beiden Spieler** gehostet, nicht vom Turnier-Host. Der
Match-Host meldet das Ergebnis über den zuverlässigen Kanal; bleibt die Meldung aus, fragt der
Turnier-Host nach 60 s nach und setzt danach E-06 um (§8).

**Zwei Entscheidungen sind hier vor der ersten Zeile Code fällig:**

1. **T-01 aus `05_TOURNAMENT` §12 — wer hostet?** Die Spec sagt „der mit der besseren
   Verbindung" und nennt weder das Maß noch das Verhalten bei Gleichstand. Ein Gleichstand
   ohne Regel ist ein Münzwurf im Turnierbetrieb, und den schließt die Doktrin aus. Der
   Vorschlag steht dort: gemessene RTT über die letzten 5 s, bei Gleichstand die niedrigere
   `participantId`. **Als ADR festhalten, dann bauen.**
2. **Wie geht `TOURNAMENT_STATE` (0x40) über die Leitung?** `05_TOURNAMENT` spezifiziert JSON,
   ADR-016 hat JSON für das Ruleset verworfen und diese eine Nachricht **ausdrücklich offen
   gelassen**: „Wenn M4 JSON braucht, ist das eine eigene Entscheidung mit eigenem ADR." Sie
   trägt verschachtelte Daten, das ist der Unterschied zum flachen Ruleset. Entscheide es, mit
   Begründung, **bevor** du die Nachricht baust.

**Abnahme:** Vier parallele Matches, gleichzeitiger Ergebnisversand, alle vier korrekt im
Bracket (T-N-11). Dazu **T-N-09** — drei gleichzeitige Lobbys im selben Netz, alle
unterscheidbar. Dieser Fall stand bis 2026-08-13 als Restschuld aus M2 herum; mit parallelen
Matches ist er kein Sonderfall mehr, sondern der Normalzustand des Abends.

### Stufe D — Der Rest

#### AP-7 — Export und manuelle Korrektur (M4-10, M4-11, 3 h)

Export als Markdown/CSV per Tastendruck (§7: „die einzige echte Versicherung" — wenn die
Software versagt, macht man mit dem Ausdruck weiter). Manuelle Ergebniskorrektur nur durch den
Turnier-Host, als `manual_override` mit Begründungstext im Log und im Bracket sichtbar
markiert (E-12).

---

## 3. Was du in dieser Session nicht tust

- **Kein Double Elimination, kein Schweizer System.** M6, und erst nach M5
  (`CLAUDE.md` §6). Beides ist der häufigste Wunsch und die häufigste Fehlentscheidung.
- **Keine automatische Beamer-Regie.** ADR-008. Sie rückt mit vier parallelen Matches an ihren
  Revisionsauslöser — bewertet wird das **nach** dem ersten 20er-Turnier, aus Beobachtung, nicht
  vorher aus Vermutung.
- **Kein Spectator-Modus.** Das ist M5.
- **Keine Änderung an `src/sim/`.** Die Zahlen aus `02_CODE_AUDIT` §4 bleiben unangetastet.
  Das Turnier setzt ein Ruleset zusammen und friert es ein; es ändert keine Physik.
- **Keine Spielerprofile, keine Ratings über den Abend hinaus.** `by_rating` in §9 meint
  Vorergebnisse **desselben** Abends. Alles darüber ist M6.
- **Nicht die WLAN-Messung.** Zurückgestellt (ADR-019), gespielt wird über Kabel.

---

## 4. Abnahme

`05_TOURNAMENT` §13, alle fünf Punkte, plus:

```powershell
D:\love2d\LOVE\lovec.exe . --test          # muss "214 bestanden, 0 gescheitert" oder mehr melden
D:\love2d\LOVE\lovec.exe . --test-no-love  # 183 bestanden, kein love im Namensraum
D:\love2d\LOVE\lovec.exe . --net-selftest  # 47 Pruefungen, alle gruen
python tools\verify_replays.py             # muss "OK" melden
```

Die Zahlen steigen mit den neuen Tests. Was nicht steigen darf, ist die Zahl der gescheiterten.

**Und die eigentliche Abnahme:** Ein 8er-Turnier, das ohne einen einzigen manuellen Eingriff
durchläuft — außer bei einem No-Show. `05_TOURNAMENT` §1 nennt die Falsifikation ausdrücklich:
Wird bei einem 8er-Turnier mehr als einmal eingegriffen, ist die Automatik unzureichend.

---

## 5. Rückmeldung

Am Ende `docs/handoffs/CC-05_REPORT.md` mit denselben Abschnitten wie CC-01 bis CC-04:
Erledigt · Nicht erledigt und warum · Befunde · Spec-Änderungen · Entscheidungen für
r0btoshi · Nächster Schritt.

**Bei mehreren Sessions:** Der Bericht wird fortgeschrieben, nicht neu geschrieben. Am Kopf
steht, welche Stufen aus §2 stehen und welche nicht — das ist die Angabe, mit der die nächste
Session anfängt.

Stand in `08_ROADMAP` §2 nachtragen und `CHANGELOG.md` unter `[Unreleased]` ergänzen — der
Release-Prozess aus `12_OPENSOURCE` §7 setzt beides voraus, bevor ein Tag gesetzt wird.

---

## 6. Was noch offen herumliegt und nicht zu M4 gehört

Damit es nicht als Versäumnis dieser Session gelesen wird:

- **Das macOS-Paket ist auf keinem fremden Mac gestartet.** Gebaut und ad-hoc signiert ist es.
  Damit hängt auch **N-04** (nimmt ENet auf macOS eine eingehende Verbindung an?) am selben
  fehlenden Gerät. Stehende Abnahme aus M1/M2.
- **T-N-02 und T-N-03** (Paketverlust): offen, seit ADR-019 nicht mehr blockierend.
- **N-01** (WLAN-Vorhersage): zurückgestellt. Anleitung und Werkzeug liegen bereit, falls am
  Abend doch jemand ohne Kabel dasteht.
