# CC-03 — Rückmeldung (M2 LAN 1v1)

**Datum:** 2026-08-12 · **Auftrag:** `docs/handoffs/CC-03_M2_LAN.md`
**Ausgangsstand:** 968e35f · **Endstand:** siehe `git log` ab e69980d
**Tests:** 179 bestanden, 0 gescheitert (vorher 83) · **Netz-Selbsttest:** 37 Prüfungen, alle grün
**Referenzen:** `python tools/verify_replays.py` meldet OK
**CI:** Lauf 14 vollständig grün, einschließlich `Protokoll-Bytes (macos-latest)`

---

## 0a. D2 gelaufen — 2026-08-12, Windows gegen macOS

**Zwei echte Rechner, beide Rollen durchgespielt. Ergebnis: das Netzspiel funktioniert.**
Protokoll aus dem Feld:

| Aufbau | Ergebnis |
|---|---|
| Windows hostet, Mac tritt bei | **automatisch gefunden**, Match läuft |
| Mac hostet, Windows tritt bei | **nicht automatisch gefunden**, mit IP-Eingabe sofort verbunden |
| Windows hostet, Gast trennt mitten im Satz | Host wartet, Zähler läuft, nach 30 s Sieg. Gast findet den Host **nicht** mehr in der Liste, kommt per IP zurück, Spiel läuft weiter |
| Mac hostet, Gast trennt mitten im Satz | dasselbe |

**Damit sind abgenommen:** T-N-01 (in beiden Richtungen), T-N-04, T-N-05 und die manuelle
IP-Eingabe als Pflichtfeature — die hat den Abend zweimal gerettet und rechtfertigt jede
Zeile, die in sie geflossen ist. **M1-07** (Start auf fremden Rechnern) ist damit ebenfalls
erledigt: beide Pakete sind auf Fremdhardware gestartet.

**Zwei Fehler, beide in meinem Code, beide behoben:**

**B-N-08 — Die Bake schweigt während des Matches.** Das erklärt Zeile 3 und 4 der Tabelle
vollständig. `scene.lua` gibt nur der obersten Szene einen Takt, und während des Matches
liegt die Lobby darunter — mitsamt der Discovery-Bake. Ab dem Anpfiff war der Host
unsichtbar. Ausgerechnet im Wiedereinstieg nach einer Trennung (§12) ist die Discovery am
nötigsten, und ausgerechnet dort fehlte sie. Die Bake wandert jetzt mit ins Match.

**B-N-09 — Der Suchende hörte nur auf einem Ohr.** Zeile 2. Aus den Messungen folgt, dass
der Rundruf des Macs den Windows-Rechner erreicht — in der umgekehrten Rolle hat dieser ihn
als Host beantwortet. Der suchende Windows-Rechner lauschte aber allein auf seinem
flüchtigen Port und war damit auf die Unicast-Antwort angewiesen. Er hört jetzt zusätzlich
auf 21213 und bekommt damit die Ankündigung, die der Host ohnehin jede Sekunde sendet.
Dazu geht jeder Rundruf zusätzlich an die Rundrufadresse des eigenen Netzes — `255.255.255.255`
verlässt auf einem Rechner mit VPN, Hyper-V oder WSL gern die falsche Schnittstelle.

**Damit die nächste Runde misst statt rät:** Serverliste und Host-Lobby zeigen unten klein
die eigene Adresse und die Zähler (gesendete Anfragen, empfangene Antworten, beantwortete
Anfragen). Bleibt die Liste leer, sagt der Zähler beim Host, ob die Frage überhaupt ankommt
— das trennt den Hinweg vom Rückweg.

**Noch offen aus D2:** T-N-02 und T-N-03 (Paketverlust mit `clumsy`) und T-N-09 (drei Hosts
gleichzeitig).

---

## 0. Nachtrag nach dem Push

**Offener Punkt N-03 ist beantwortet: ja.** Der vollständige 72-Byte-Snapshot ist auf
`windows-latest` und `macos-latest` bitgleich. Dafür brauchte es drei CI-Läufe, und der
zweite hat etwas gefunden, das keine Überlegung am Schreibtisch gefunden hätte — siehe
B-N-07.

**Nachgereicht auf Ansage (r0btoshi, 2026-08-12):** ein **gespeicherter Nickname** für
Netzspiel und Turnier. Die Zufallsnamen bleiben, wo sie hingehören — im lokalen Spiel.

---

## 1. Erledigt

| AP | Aufgaben | Ergebnis |
|---|---|---|
| AP-0 | W-01…W-03 | `04_NETCODE_SPEC` auf 1.1 korrigiert, **bevor** die erste Zeile Netzcode entstand. ADR-016 |
| AP-1 | M2-01 | `protocol.lua` (alle Nachrichtentypen) plus drei `love`-freie Module: `snapshot.lua`, `input_queue.lua`, `lobby.lua` |
| AP-2 | M2-02 | `host.lua`: autoritative Simulation, Snapshot je Tick, Ereignisschleife vollständig geleert, Peer-Timeout 5000 ms |
| AP-3 | M2-03 | `client.lua` + `net_source.lua`: Eingabe mit dreifacher Redundanz, Interpolationspuffer 2 Ticks, **keine** Vorhersage |
| AP-4 | M2-04, M2-05 | `discovery.lua` auf UDP 21213, Serverliste mit der IP-Eingabe als letztem Eintrag, LAN-Adresse groß in der Lobby |
| AP-5 | M2-06, M2-07 | Lobby mit Slots und Bereit-Status, Ruleset-Verteilung, drei Prüfungen mit drei Konsequenzen |
| AP-6 | M2-08, M2-09 | Pause 30 s, Wiedereinstieg mit derselben Kennung, Walkover; F3-Overlay |
| AP-6 | M2-10 | `tools/net_selftest.lua` und `tools/net_test.sh` — ein Prozess, zwei Prozesse, zwei Fenster |

**Der Weg vom Menü bis zum fliegenden Ball steht.** Zwei echte Instanzen auf `127.0.0.1`,
beide mit Bild, beide über die reguläre Oberfläche gestartet: `docs/media/net-host.png` und
`docs/media/net-client.png`. Sie zeigen denselben Spielstand, denselben Aufschläger und
dieselbe Ballposition — der Gast zwei Ticks hinter dem Host, wie vorgesehen.

**Im Loopback mit zwei Prozessen fallen Punkte, und beide Seiten kommen auf denselben
Endstand** (`./tools/net_test.sh loopback`, zuletzt 2:0 bei 3595 übertragenen Snapshots).

### Stand der Abnahmefälle aus `07_TEST_PLAN` §4

| Fall | Stand | Beleg |
|---|---|---|
| T-N-01 Satz spielen, gleicher Endstand | **teilweise** | Loopback: 2:0 auf beiden Seiten. Ein vollständiger Satz mit zwei Menschen ist D2 |
| T-N-02 5 % Verlust auf Kanal 2 | **Logik ja, Netz nein** | Redundanz und Repeat-Last in `tests/input_queue_test.lua`; echter Verlust braucht `clumsy` |
| T-N-03 20 % Verlust auf Kanal 1 | **offen** | dito |
| T-N-04 Client killen → Pause, Walkover | **ja** | Selbsttest: Pause, 30-s-Fenster, Walkover-Meldung nach Ablauf |
| T-N-05 Killen und in 10 s zurück | **ja** | Selbsttest: derselbe `clientId` steigt in das laufende Match ein |
| T-N-06 abweichender `rulesetHash` | **ja** | Selbsttest: Start unterbleibt, Klartext nennt beide Hashes |
| T-N-07 gleiche Bytes auf Win und macOS | **ja** | CI-Lauf 14: derselbe 72-Byte-Snapshot auf beiden Läufern. N-03 geschlossen |
| T-N-08 200 Snapshots in einem Frame | **ja** | Selbsttest: 201 Ereignisse in einem Durchlauf, danach leer |
| T-N-09 drei Hosts gleichzeitig | **offen** | braucht drei Rechner; die Zusammenführung doppelter Einträge ist belegt |
| T-N-10 Host schließt die Lobby | **ja** | Selbsttest: der Gast bekommt „Verbindung zum Host verloren", die Szene räumt sich nach 6 s ab |

---

## 2. Nicht erledigt, und warum

- **D2 (zwei Rechner).** Kein zweites Gerät verfügbar; so entschieden am 2026-08-12. Alles,
  was ohne Hardware ging, ist ersatzweise im Loopback gefahren. Was der Loopback **nicht**
  zeigt: Firewall, WLAN-Latenz, Broadcast über einen Switch, zwei verschiedene Betriebssysteme.
- **T-N-02 / T-N-03 (Paketverlust).** `clumsy` hängt sich in den Windows-Netzwerkstapel und
  lässt sich aus einem Skript nicht verlässlich fernsteuern. Filter und Vorgehen stehen im
  Kopf von `tools/net_test.sh`; ein Aufruf, der es versucht und dabei still scheitert, wäre
  schlechter als diese Zeilen.
- **N-04 (ENet auf einem frischen Mac).** Unverändert offen. Ein CI-Image beantwortet die
  Frage nach der eingehenden Verbindung nicht.
- **Der macOS-Teil von T-N-07.** Der CI-Job `protocol` ist geschrieben und läuft lokal unter
  Windows; ob der macOS-Läufer LÖVE ohne Bildschirm startet, zeigt erst der erste Push.
- **Kosmetik beim Gast.** Der Client zeigt in M2 keine Partikel und keine Klänge. Das ist
  M3-02 und in `04_NETCODE_SPEC` §6 so vorgesehen — er simuliert nicht und bekommt deshalb
  keine Ereignisse.

---

## 3. Befunde

**B-N-01 — `socket.udp()` liefert unter LuaSocket 3.0 einen IPv6-Socket.**
Ein `sendto` an `255.255.255.255` scheitert darauf mit „Der angegebene Host ist unbekannt",
und die Discovery findet schlicht nichts. Gemessen, nicht vermutet. Behoben mit
`socket.udp4()`; in `04_NETCODE_SPEC` §11 festgehalten, weil es bei jeder späteren
Socket-Erzeugung wieder zuschlagen würde.

**B-N-02 — Zwei Instanzen auf einem Rechner teilen sich die Spielerkennung.**
`clientId` liegt in den Prefs, und beide Prozesse lesen dieselbe Datei. Der Gast wurde dadurch
als Rückkehrer auf **Platz 1** erkannt und übernahm den Platz des Hosts: die Lobby wurde nie
startbereit und zeigte den Namen des Gastes als Host an. `Lobby:slotOf` überspringt jetzt den
Host-Slot — der Host ist strukturell kein Rückkehrer. Mit Testfall abgesichert.

**B-N-03 — Ein Host auf demselben Rechner stand doppelt in der Serverliste.**
Er antwortet zweimal, über `127.0.0.1` und über die LAN-Adresse. `ANNOUNCE` trägt jetzt eine
`hostId`; der Browser führt die Einträge zusammen und bevorzugt die Loopback-Adresse.

**B-N-04 — Namenskollision im eigenen Code.** `net_game.lua` hielt seinen Tickzähler in
`self.tick` und verdeckte damit die gleichnamige Methode; der Gast stürzte im ersten Frame
des Matches ab. Feld heißt jetzt `simTick`.

**B-N-05 — Der Snapshot aus Fassung 1.0 hätte ein anderes Spiel gezeigt.** Neben den zwei
Phasen, die es nicht gibt, fehlten drei **sichtbare** Werte: Blob-Neigung (die Animation beim
Seitwärts-Dash), Dash-Cooldown (der rote Balken im HUD) und der Fehlerwurf (die Einblendung
„FAULT!"). Alle drei sind ergänzt; der Cooldown als Verhältnis in einem Byte.

**B-N-07 — Das Vorzeichen der Null entsteht auf beiden Plattformen unterschiedlich.**
Gefunden vom CI-Lauf 12, präzisiert von Lauf 13. Unter Windows-x86-64 ergibt `-zero` eine
negative Null (`00000080`), unter macOS-ARM64 eine **positive** (`00000000`) — auf Apple
Silicon fährt LÖVE 11.5 den Interpreter statt des JIT. Das ist **kein** Fehler von
`love.data.pack`: alles andere ist bitgleich, der ganze Snapshot inklusive.

Die Simulation erzeugt negative Nullen beiläufig (`ball.vx = -math.abs(ball.vx) * 0.8` bei
`vx = 0`, `physics.lua:124`). Fürs Spiel bedeutungslos — `-0 == 0`, und niemand sieht ein
Vorzeichen an einer stehenden Geschwindigkeit. **Für die Prüfsumme aus `04_NETCODE` §9 wäre
es ein Fehlalarm in jedem Tick, in dem etwas stillsteht**, und der hätte in M3-03 ausgesehen
wie ein echter Desync. `snapshot.lua` begradigt die Null deshalb vor dem Senden.

Das ist der Ertrag von T-N-07: Der Punkt stand seit der Spec-Fassung 1.0 als „praktisch
sicher" im Dokument. Er war es nicht ganz.

**B-N-06 — Ein Aufschlag ohne Seitwärtsbewegung fällt auf die eigene Seite.** Beim Bau des
Loopback-Tests aufgefallen: Ein Blob, der senkrecht unter dem Ball hochspringt, schlägt ihn
senkrecht hoch, der Ball landet auf der eigenen Hälfte, es gibt Seitenaus statt Punkt — und
zwar endlos. Kein Fehler, sondern die Physik; für den Test relevant, weil ein Lauf ohne
Punkte nichts prüft. Steht als Kommentar im Harness.

---

## 4. Spec-Änderungen

Alle **vor** dem Code eingetragen, nach der Regel aus `CLAUDE.md` §2.

| Datei | Änderung |
|---|---|
| `04_NETCODE_SPEC` → 1.1 | `rulesetHash(8)` statt MD5(16); `RULESET_FULL` binär statt JSON; Snapshot-Feldliste gegen `state.lua` erhoben (69 B Nutzlast, vier Phasen, Flags mit Fehlerwurf); `MATCH_PAUSE` (0x24) ergänzt; `seed` aus `MATCH_START` gestrichen; Discovery mit flüchtigem Client-Port, Unicast-Antwort, `hostId` und `udp4`; Bandbreite nachgerechnet; N-03 beantwortet, N-05 neu |
| `09_DECISION_LOG_ADR` | **ADR-016** — djb2-Hash und binäre Ruleset-Übertragung, mit den verworfenen Alternativen |
| `03_TECH_ARCHITECTURE` | `src/net/` hat sieben statt fünf Dateien; je Datei steht dabei, wovon sie abhängt. `src/lib/json.lua` gestrichen |
| `12_OPENSOURCE_REPO_SETUP` | `src/lib/json.lua` aus der Fremdkomponententabelle entfernt — das Projekt bleibt fremdbibliotheksfrei |
| `08_ROADMAP_BACKLOG` | Statusspalte bei M2 |
| `CHANGELOG.md` | Abschnitt `[Unreleased]` |
| `CLAUDE.md` | §12 um die drei Netzbefehle und den Hinweis auf `--client-id` ergänzt |

**Warum die Snapshot-Größe steigt (48 B in der Spec → 69 B tatsächlich):** Die alte Zahl war
eine Überschlagsrechnung über eine Feldliste, die drei sichtbare Werte nicht enthielt. Bei
60 Hz macht das 6,0 statt 4,6 KB/s je Gast. Auf jedem Netz dieses Jahrtausends nicht messbar
— korrigiert wurde die Zahl trotzdem, damit sie nicht irgendwann als Begründung für eine
Optimierung herhält.

---

## 5. Entscheidungen für r0btoshi

1. **Der Testlauf braucht kein Fenster mehr.** `love . --test` schaltet in `conf.lua` Fenster,
   Grafik und Ton ab. Das war nötig, damit die Protokolltests auf den CI-Läufern laufen
   können — und ohne sie bliebe N-03 („schreiben beide Plattformen dieselben Bytes?") für
   immer eine Vermutung. Nebenwirkung: der Testlauf ist schneller und blitzt nicht mehr auf.
   **Wenn dir das nicht passt, ist der Preis der Rückbau des CI-Jobs `protocol`.**

2. **Die Protokolltests laufen nicht unter reinem LuaJIT.** Bewusst so: `love.data.pack`
   hinter eine austauschbare Schicht zu legen hieße, im Test eine zweite Pack-Implementierung
   zu prüfen und genau den Plattformunterschied unsichtbar zu machen, den T-N-07 finden soll.
   Der Headless-Runner meldet die Suite als übersprungen, statt zu schweigen.

3. **Der Nickname ist gebaut und gespeichert** (`prefs.playerName`, Menü unter „Network
   Match", oberster Eintrag). Zwei Setzungen darin, beide widerrufbar:
   - **Beim ersten Start wird ein Name vorbelegt** statt ein Formular gezeigt. Wer nichts
     tut, heißt trotzdem irgendwie und kann sofort spielen.
   - **Doppelte Namen löst der Host durch Anhängen** („Squish", „Squish 2"), nicht durch
     Ablehnen. Ein abgewiesener Gast müsste zurück ins Menü, tippen, neu verbinden — drei
     Schritte gegen die 90-Sekunden-Vorgabe. Der Gast sieht seinen tatsächlichen Namen in
     der Lobby. **Wenn du im Turnier lieber eine harte Ablehnung willst, sag es vor M4** —
     dort ist die Anmeldung der richtige Ort dafür, nicht die Lobby.

4. **ESC im laufenden Satz beendet die ganze Sitzung**, nach dem Abpfiff dagegen nur das
   Match und man landet wieder in der Lobby. So kostet das nächste Match keinen neuen
   Handschlag. Das ist eine Setzung von mir, kein Spec-Punkt.

5. **`--client-id=N` gibt es nur für die Testflags**, nicht im Spiel. Zwei Instanzen auf einem
   Rechner brauchen es, echte Gäste nicht.

---

## 6. Nächster Schritt

### Der Release liegt bereit

**`v0.2.0` ist gebaut und als Entwurf angelegt**, mit dem Windows- und dem macOS-Paket daran
(CI-Lauf 17, alle Jobs grün, einschließlich `codesign --verify --deep --strict` auf dem
macOS-Läufer). Veröffentlicht wird **nicht** — Schritt 7 des Release-Prozesses aus
`12_OPENSOURCE` §7 ist der Start auf einem fremden Rechner, und genau das ist der heutige
Abend. Der Entwurf liegt unter *Releases* im Repo; die Pakete lassen sich von dort auf beide
Maschinen laden.

Der Release-Text wird von `tools/release_notes.sh` aus dem CHANGELOG und den beiden
Startanleitungen zusammengesetzt, nicht aus Commit-Titeln. Beide `LIESMICH`-Dateien und das
README behaupteten bis eben, LAN sei nicht enthalten; sie beschreiben jetzt Hosten,
Beitreten, die Firewall-Rückfrage und die IP-Eingabe.

**Ein Detail, das sonst heute Abend aufgefallen wäre:** Der Build-Hash entstand mit
`sort` ohne feste Locale und schloss `tests/` ein. Das Windows-Paket entsteht auf einem
Linux-, das macOS-Paket auf einem BSD-artigen Läufer — dieselbe Fassung hätte damit zwei
verschiedene Hashes bekommen, und die Lobby hätte zwischen zwei Paketen **desselben Tags**
einen Build-Unterschied gewarnt. Jetzt `LC_ALL=C sort` und ohne `tests/`. Ob beide Pakete
tatsächlich denselben Hash tragen, ist mit Bordmitteln nicht prüfbar (Entwurfs-Artefakte
brauchen zum Herunterladen eine Anmeldung): **Der Vergleich der beiden Zeichenketten unten
rechts im Menü ist der Test.** Stimmen sie überein, erscheint keine Warnung.

### D2 am Abend — was in welcher Reihenfolge zu prüfen ist

Die Reihenfolge ist nicht beliebig. Jeder Schritt setzt den vorigen voraus, und der erste,
der scheitert, erklärt die folgenden.

1. **Beide Rechner in dasselbe Segment**, möglichst per Kabel. WLAN-Access-Points mit
   Client-Isolation blocken den Broadcast zwischen Gästen (`04_NETCODE` §11).
2. **Nickname auf beiden Geräten setzen**, bevor irgendetwas gestartet wird. Sonst heißen
   beide gleich und der Host hängt eine „2" an — richtig, aber verwirrend beim ersten Mal.
3. **Windows hostet, Mac tritt bei.** Beim ersten Start fragt die Windows-Firewall nach
   einer Freigabe — **erlauben, nicht wegklicken**, und zwar für das Profil, in dem der
   Rechner gerade ist (N-05). Erscheint die Lobby beim Mac in der Liste? Wenn nicht: die
   IP aus der Lobby des Hosts abtippen, letzter Eintrag der Serverliste. Findet die
   Discovery nichts, die IP-Eingabe aber schon, ist es die Firewall oder das Netz — nicht
   der Netzcode.
4. **Mac hostet, Windows tritt bei.** Das ist der eigentlich offene Punkt N-04: ob ENet auf
   macOS eine **eingehende** Verbindung ohne zusätzliche Freigabe annimmt. Ausgehend
   funktioniert erfahrungsgemäß immer, eingehend ist die Frage.
5. **Ein vollständiger Satz** in beiden Richtungen (T-N-01), einmal mit F3 offen: RTT
   sollte im LAN einstellig sein, „GEHALTEN" nahe null. Steht dort etwas anderes, ist das
   die Zahl für den Fehlerbericht.
6. **Stecker ziehen** beim Gast mitten im Satz (T-N-04): Der Host muss „Warte auf …" mit
   Zähler zeigen. Innerhalb von 30 s wieder verbinden (T-N-05) — der Satz läuft weiter, der
   Stand bleibt. Danach einmal ablaufen lassen: Walkover.
7. **`clumsy` auf dem Windows-Rechner** für T-N-02 und T-N-03. Filter im Kopf von
   `tools/net_test.sh`.

**Läuft alles:** Damit ist zugleich **M1-07** erledigt (Start auf fremden Rechnern) — der
letzte offene Punkt aus M1. Dann kann `v0.2.0` von Hand veröffentlicht werden, und mit ihm
`v0.1.0` verfallen: eine Fassung ohne Netzwerk braucht niemand mehr.

**Läuft es nicht:** Das F3-Overlay und die Zeichenkette unten rechts im Menü sind die zwei
Angaben, aus denen sich der Fehler rekonstruieren lässt. Beides fotografieren.

**Zu deiner Frage: Nein, Windows↔Windows folgt nicht automatisch, aber fast.** Was der
gemischte Test zusätzlich beweist, deckt den gleichnamigen Fall mit ab — Protokoll,
Bytereihenfolge und Ablauf sind plattformunabhängig, und die harte Frage (float32 auf
ARM gegen x86-64) ist mit T-N-07 in der CI schon beantwortet. **Was er nicht beweist, ist
die Richtung:** Ob eine eingehende Verbindung ankommt, hängt an der Firewall des Rechners,
der **hostet**, nicht am Betriebssystem des Gastes. Deshalb stehen oben Punkt 3 und 4
getrennt. Ist einmal Windows als Host durchgelaufen, ist Windows↔Windows abgedeckt; ist
nur der Mac als Host gelaufen, weißt du über den Windows-Host nichts.

Der zweite Unterschied ist unspektakulär, aber real: Bei zwei gleichen Plattformen sind die
Builds identisch, also bleibt die Build-Hash-Warnung aus. Bei Mac gegen Windows erscheint
sie — **das ist richtig so und kein Fehler** (`04_NETCODE` §10: nur Warnung, kein Abbruch).
Wenn sie erscheint, ist genau das der Beleg, dass die Prüfung wirkt.

### Danach

**M3**: Vorhersage des eigenen Blobs (M3-01) und Kosmetik aus Snapshot-Deltas (M3-02). Das
Feld „KORREKTUR" im F3-Overlay steht schon da und meldet 0 — M3-01 füllt es, statt es zu
erfinden. Für M3-03 (Desync-Detektor) ist B-N-07 die Vorarbeit: Die Prüfsumme darf nur über
Werte laufen, die auf beiden Plattformen bitgleich entstehen.
