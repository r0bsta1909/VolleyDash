# Changelog

Alle nennenswerten Änderungen an Volley Dash. Format nach
[Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionierung nach
[Semantic Versioning](https://semver.org/lang/de/).

Bis 0.1.0 ist das Spiel nicht öffentlich verteilt worden — der erste Eintrag umfasst
deshalb die gesamte bisherige Arbeit, nicht nur die Änderungen eines Zyklus.

## [Unreleased]

Turniermodus (M4), **Stufe A bis C**: das Turnier, seine Bedienung und das Netz. Menü →
NETWORK MATCH → „Turnier" richtet aus; wer beitreten will, findet das Turnier in der
Serverliste wie eine Lobby. Gespielt wird **im** Turnier: Der Turnier-Host ruft auf, einer der
beiden Spieler hostet das Match, das Ergebnis geht von dort zurück ins Bracket. Offen bleibt
der Export (M4-10, Stufe D).

### Hinzugefügt (Stufe C — verteilte Match-Hosts, M4-09)

- **Anmeldung über das Netz.** Ein Turnier sendet jetzt eine Bake und steht in der Serverliste
  (`mode = "tournament"`); ENTER führt dort nicht in eine Match-Lobby, sondern ins Turnier.
  Wer abstürzt, kommt mit derselben Kennung zurück; wer den Rechner wechselt, über seinen
  Namen (E-05, E-14).
- **Bis zu vier Matches gleichzeitig, gehostet von den Spielern selbst** (ADR-013). Der
  Turnier-Host sagt beiden, wer hostet; der Wirt öffnet einen Port, den ihm das Betriebssystem
  gibt, und der Gegner bekommt die Adresse. **Ein fester zweiter Port wäre hier gescheitert:**
  Ein Prozess kann denselben ENet-Port nicht zweimal binden, und der Turnier-Host spielt mit.
- **ADR-022 — wer hostet.** Median der gemessenen RTT über 5 s, entschieden erst ab 5 ms
  Unterschied, sonst die kleinere Setznummer. Über Kabel ist der Gleichstand der Normalfall;
  das ist Absicht, denn 1–2 ms Unterschied sind Rauschen und kein Maß. Grund und beide
  Messwerte stehen im Log — „warum hostet der?" ist aus der Datei zu beantworten.
- **ADR-023 — der Turnierstand geht als Log-Ereignisse über die Leitung**, nicht als fertiger
  Zustand. Jeder Empfänger rechnet mit derselben Funktion wie die Absturz-Recovery, eine Lücke
  erkennt er an seinem eigenen Wasserstand, und die Nachricht bleibt bei rund 100 Byte je
  Ereignis statt 30 KB je Zustand.
- **Längste Rallye und schnellster Ball** (`05_TOURNAMENT` §11) fallen in der Simulation an und
  kommen jetzt mit dem Ergebnis des Match-Hosts mit. Gemessen wird außerhalb von `src/sim/`,
  von einem Beobachter, der liest und nichts zurückschreibt — die Simulation bleibt unberührt.
- **`--tournament-selftest`**: vier parallele Matches mit gleichzeitigem Ergebnisversand
  (T-N-11) und drei gleichzeitige Turniere im selben Netz (T-N-09), alles in einem Prozess und
  damit CI-tauglich. **T-N-09 stand seit M2 als Restschuld herum.**
- **Beide Selbsttests laufen jetzt in der CI**, auf `windows-latest` und `macos-latest`. Bis
  dahin prüfte sie nur, was ohne Leitung entscheidbar ist — bei einem Turnier mit verteilten
  Match-Hosts ist das die kleinere Hälfte. N-04 und N-05 beantwortet das ausdrücklich nicht:
  Ein Läufer hat keine Firewall und keine zweite Maschine.

### Behoben (Stufe C)

- **Die Turnierverbindung starb während des Matches.** Nur die oberste Szene bekommt `update`,
  und während eines Matches liegt der Turniermodus darunter — sein ENet-Wirt wurde vier Minuten
  lang nicht bedient. Nach 5 s Peer-Timeout galt jeder Teilnehmer als offline, der No-Show-Timer
  lief gegen Leute, die gerade spielten, und das Ergebnis fand am Ende niemanden mehr. Die
  Verbindung wandert jetzt mit ins Match, genauso wie die Bake seit M2.

### Hinzugefügt (Stufe B — die Bedienung)

- **Turnier-Lobby.** Teilnehmer werden am Turnier-Host eingetragen; nach ENTER steht der Cursor
  wieder im leeren Feld, weil zwanzig Namen sonst niemand tippt. Doppelte Namen werden
  abgewandelt statt abgelehnt (E-14), Streichen geht mit ENTF, und der Name ist danach wieder
  frei. Format, Parallelität und Setzung stehen daneben.
- **Der Seed ist sichtbar und nachrechenbar** (`05_TOURNAMENT` §9). Das Feld nimmt Text
  („sommerlan") wie Zahlen; angezeigt werden beide. Wer die angeschriebene Zahl abliest und
  wieder eintippt, bekommt dasselbe Bracket — sonst wäre ein sichtbarer Seed wertlos.
- **Zwei Ansichten, F2 schaltet um** (§10). Kompakt für den Spieler: die eigene Linie, groß
  „Nächster Gegner" und die Restzeit des No-Show-Timers. Voll für den Beamer: Gruppentabellen
  bzw. der K.o.-Baum, laufende Matches hervorgehoben, fertige ausgegraut, aufgerufene blinkend
  mit Countdown.
- **Die drei Klänge spielen.** `tournament_call` beim Aufruf des eigenen Matches,
  `tournament_warn` 30 s vor Ablauf des No-Show-Timers, `tournament_done` beim Sieger. Ohne den
  Aufruf verliert ein Match, wer nichts gehört hat — der Timer läuft seit Stufe A wirklich.
- **Bedienung des Turnierleiters (M4-11 vollständig):** Ergebnis eintragen (`15:12`, Best-of-3
  nimmt mehrere Sätze), Ergebnis korrigieren mit Pflicht-Begründung (E-12, im Bracket markiert),
  No-Show-Timer anhalten (E-02), Match abbrechen und neu ansetzen (E-06), Teilnehmer austragen
  (E-04). In der kompakten Ansicht ist davon nichts erreichbar: Ein Spieler soll sein eigenes
  Ergebnis nicht eintragen können.
- **Der Dialog „Laufendes Turnier gefunden"** (§7). Er kommt vor allem anderen — wer die Frage
  übergeht, legt ein zweites Turnier an. Unterbrochene Matches werden neu angesetzt, nicht
  gewertet.
- **`src/tournament/session.lua`** hält Modell, Scheduler und Persistenz zusammen und liefert
  der Anzeige alles Gerechnete: Restzeit, eigene Linie, Bedienliste. Die Anzeige liest, sie
  rechnet nicht — sonst gäbe es für die Restzeit zwei Rechnungen.
- **60 neue Testfälle**, alle `love`-frei, darunter ein 8er-Turnier, das ausschließlich über die
  Tastatur bis zum Sieger durchläuft.

### Hinzugefügt (Stufe A — das Turnier)

- **`src/tournament/` — Datenmodell, Auslosung, Zustandsautomat, Persistenz.** Alle vier
  Dateien sind `love`-frei und laufen im Headless-Testrunner; nur `persistence.lua` fasst
  Dateien an, und auch dort ist der Zugriff austauschbar.
- **Das Log ist die Wahrheit.** Der gesamte abgeleitete Zustand — Paarungen, Tabellen,
  Statistiken — wird nach jedem Ereignis aus dem append-only Log neu gerechnet (ADR-007).
  Damit ist die Absturz-Recovery kein eigener Codepfad, sondern derselbe Ablauf, nur schneller.
- **Formate:** Single Elimination mit Freilosen an die Höchstgesetzten, Round Robin, und
  Gruppen → K.o. als Standardformat. Die Gruppenaufteilung findet der Scheduler selbst:
  20 Teilnehmer werden 4×5, 18 werden 2×5 + 2×4, und keine Gruppe hat je weniger als 3 oder
  mehr als 6 Mitglieder — geprüft für jede Teilnehmerzahl von 4 bis 32.
- **Eigener deterministischer Zufallsgenerator für die Auslosung.** `math.random` liefert je
  nach Lua-Fassung verschiedene Folgen; ein sichtbarer Seed, der auf zwei Rechnern zwei
  Brackets erzeugt, wäre schlimmer als gar keiner (`05_TOURNAMENT` §9).
- **Atomares Speichern nach jedem Log-Ereignis** in vier Schritten (`tmp` → `bak` → rename),
  als JSON (ADR-020). Eine halb geschriebene Datei kostet höchstens das letzte Ereignis, nie
  das Turnier — der Fall steht als Test drin.
- **135 neue Testfälle**, davon ein vollständiger 20er-Durchlauf mit hartem Neustart mitten in
  Runde 2: Das Turnierobjekt wird weggeworfen und ausschließlich aus der Datei neu aufgebaut.
- **Drei Klänge für den Turniermodus** (`tournament_call`, `tournament_warn`,
  `tournament_done`, zusammen rund 1,1 MB). Sie werden noch nicht abgespielt — das kommt mit
  der Anzeige. Der Aufruf-Ton ist keine Zierde: `05_TOURNAMENT` §5 schreibt ihn vor, weil auf
  einer Party niemand auf sein Menü starrt, und seit der No-Show-Timer wirklich läuft,
  verliert ein Match, wer nichts hört.

### Behoben

- **Ein Freilos machte seinen Sieger zu seinem eigenen Verlierer.** Der Verlierer wurde mit
  einem `and/or`-Ausdruck bestimmt, der bei leerem Gegnerslot auf den Sieger durchfällt. Folge:
  eine Niederlage in der Statistik, die niemand erlitten hat — bei 20 Teilnehmern in einem
  32er-Bracket zwölf Mal. Aufgefallen an der Teilnehmerliste am Beamer, die die Zahlen zum
  ersten Mal zeigt (B-T-03).
- `assets/CREDITS.md` gab die Klänge als **44,1 kHz** an. Sie liegen sämtlich in **48 kHz**
  vor, und zwar seit jeher — nachgemessen aus den RIFF-Kopfdaten. Am Verhalten ändert das
  nichts, LÖVE liest beide Raten; falsch war nur die Zahl, nach der sich künftige Beiträge
  gerichtet hätten.

### Geändert

- `05_TOURNAMENT` §2 sagte „Best-of-3 ab Viertelfinale", §4 „ab Halbfinale". Verbindlich ist
  jetzt **ab Halbfinale**; §2 ist berichtigt. Die Grenze bleibt Konfiguration (`bestOfFinals`).
- `05_TOURNAMENT` §6 hat drei Fälle mehr: **E-15** (beide Spieler erscheinen nicht),
  **E-16** (ein Teilnehmer ist offline) und **E-17** (der Gleichstand überlebt den Stichsatz).
  Alle drei sind Stellen, an denen der Zustandsautomat ohne Regel entweder würfeln oder
  stehenbleiben müsste; beides schließt die Doktrin aus (ADR-021).

## [0.3.0] — 2026-08-13

Netzwerk-Politur (M3). Der Gast war bisher Zuschauer seines eigenen Blobs: Er drückte eine
Taste und sah die Wirkung zwei Ticks später, und sein Bild blieb still — kein Staub, kein
Klang. Beides ist behoben.

**Diese Fassung spielt mit 0.2.x zusammen.** Protokollfassung, Snapshot-Format und
Nachrichtentypen sind unverändert; wer noch 0.2.2 hat, kann mitspielen und sieht lediglich die
gewohnte Build-Warnung in der Lobby. Nur die Neuerungen unten fehlen ihm dann — der ältere
Stand sagt nichts vorher und schickt keine Prüfsummen.

### Hinzugefügt

- **Der Gast bewegt seinen eigenen Blob sofort.** Er rechnet ihn lokal mit **derselben
  Physik** wie der Host (`src/net/prediction.lua` ruft `src/sim/` auf, statt es nachzubauen).
  Ball, Gegner und Punktestand kommen unverändert allein vom Host — die Simulation bleibt
  host-autoritativ (ADR-002). Weicht die Vorhersage um mehr als 2 px ab, wird das über vier
  Ticks ausgeglichen, ohne dass das Bild springt. Verglichen wird dabei zeitrichtig: gegen den
  Eingabetick, den der Host im Snapshot bestätigt — sonst meldete jede Laufbewegung einen
  Fehler, den niemand gemacht hat (ADR-017).
- **Der Gast sieht Staub und hört Klänge.** Wandtreffer, Netztreffer, Blobtreffer, Sprung,
  Landung, Dash, Aufschlag, Fehlerwurf und Punkt werden aus dem Unterschied zweier Snapshots
  abgeleitet (`src/render/snapshot_events.lua`). Kein zusätzliches Byte auf der Leitung.
- **Desync-Detektor.** Der Host schickt zweimal je Sekunde eine Prüfsumme über die gepackten
  Snapshot-Bytes; der Gast packt den gelesenen Snapshot erneut und vergleicht. Das findet den
  Fall, den der Build-Hash bisher nur **warnte**: zwei Rechner mit verschiedenen Ständen, bei
  denen der Gast still etwas Falsches anzeigt (ADR-018).
- **F4 im Netzspiel schreibt einen Messmitschnitt** nach `netlog.csv` — einmal je Sekunde die
  Werte aus dem F3-Overlay. Für die WLAN-Messung: eine Messreihe statt eines abfotografierten
  Overlays.
- Das F3-Overlay füllt das Feld **KORREKTUR** und zeigt zusätzlich **DESYNC**. Zwei
  Fehlerklassen, zwei Zahlen — ein gemeinsamer Wert sagt im Fehlerfall nicht, welche schuld ist.

### Geändert

- Der Gast greift das Bild jetzt in **jedem** Tick zur Interpolation ab, nicht nur beim
  Eintreffen eines Snapshots. Bleibt ein Snapshot aus, steht der Ball damit still, statt
  zwischen zwei alten Ständen hin und her zu gleiten.

### Offen

- Ob die Vorhersage über **WLAN** bei 20–40 ms reicht oder ob der Ball zusätzlich
  extrapoliert werden muss, ist eine Messfrage und braucht zwei Geräte
  (`docs/handoffs/CC-04_WLAN_MESSANLEITUNG.md`).

## [0.2.2] — 2026-08-12

**Erste öffentlich veröffentlichte Fassung.** Zweite Nachbesserung aus dem LAN-Test. Die Discovery-Fehler aus 0.2.1 sind bestätigt behoben —
Suche und Wiedereinstieg laufen jetzt in beiden Richtungen ohne IP-Eingabe.

### Behoben

- **`R` im Abpfiff-Bild war im Netzspiel ohne Wirkung**, auf beiden Seiten. Der Text versprach
  eine Revanche, die es nicht gab: die Taste war nur im lokalen Spiel belegt. Jetzt pfeift der
  **Host** mit `R` ein neues Match an; der Gast setzt automatisch mit zurück. Beim **Gast**
  meldet `R` den Revanchewunsch an — er kann kein Match starten, es gibt nur eine Wahrheit
  (ADR-002), und beide Seiten sehen jetzt, worauf sie warten.
- Beim Verlassen des Matches gab die Spielszene die Rückrufe der Netzschicht nicht an die
  Lobby zurück. Wer nach dem Abpfiff zur Lobby ging, hätte dort einen Abbruch oder einen
  neuen Anpfiff verschluckt.

## [0.2.1] — 2026-08-12

Nachbesserung aus dem ersten LAN-Test mit zwei Rechnern (Windows gegen macOS).
Das Netzspiel lief; gefunden wurden zwei Fehler in der Discovery.

### Behoben

- **Die Bake schwieg, sobald das Match lief.** Nur die oberste Szene bekommt einen Takt, und
  während des Matches liegt die Lobby darunter — mitsamt der Discovery. Wem mitten im Satz
  die Verbindung abriss, der fand den Host nicht mehr in der Serverliste und musste die IP
  abtippen. Ausgerechnet beim Wiedereinstieg war die Suche also blind.
- **Der Suchende hörte nur auf einem Ohr.** Er lauschte allein auf seinem flüchtigen Port und
  war damit auf die Unicast-Antwort angewiesen. Jetzt hört er zusätzlich auf Port 21213 und
  bekommt die Ankündigung mit, die der Host ohnehin jede Sekunde sendet. Das war der Grund,
  warum ein Mac als Host von einem Windows-Rechner nicht gefunden wurde.
- Jeder Rundruf geht zusätzlich an die Rundrufadresse des eigenen Netzes
  (`192.168.1.155` → `192.168.1.255`). `255.255.255.255` ist an keine Schnittstelle gebunden
  und verlässt auf Rechnern mit VPN, Hyper-V oder WSL gern die falsche.

### Hinzugefügt

- Serverliste und Host-Lobby zeigen unten klein die eigene Adresse und die Zähler der
  Discovery. Bleibt die Liste leer, sagt der Zähler beim Host, ob die Anfrage überhaupt
  ankommt — das trennt den Hinweg vom Rückweg, statt beides zu raten.

## [0.2.0] — 2026-08-12

LAN-Spiel. Zwei Rechner finden sich im Netz und spielen ein Match 1v1 —
ohne IP-Eingabe, wenn das Netz mitspielt, und mit IP-Eingabe, wenn nicht.

### Hinzugefügt — M2 (LAN 1v1)

- **Netzwerkspiel 1v1 über LAN.** Host-autoritative Snapshots mit 60 Hz (ADR-002): der Host
  simuliert und spielt mit, der Gast schickt seine Eingaben und zeigt an, was zurückkommt.
- **Zero-Config-Discovery** über UDP-Broadcast auf Port 21213. Lobbys erscheinen von selbst
  in der Serverliste; die **manuelle IP-Eingabe steht als letzter Listeneintrag** und ist
  Pflichtfeature, nicht Notlösung — der Host zeigt seine LAN-Adresse groß in der Lobby an.
- Lobby mit Slots und Bereit-Status, Regelwerk vom Host verteilt (ADR-005). Drei Prüfungen mit
  drei Konsequenzen: abweichende Protokollfassung wird beim Beitritt abgelehnt, ein
  abweichendes Regelwerk verhindert den Start, ein abweichender Build **warnt nur**.
- Trennung und Wiedereinstieg: das Match pausiert 30 s und zeigt einen Zähler; wer mit
  derselben Kennung zurückkommt, steigt in den laufenden Satz ein. Danach Walkover.
- **Nickname**, gespeichert und über das Menü unter „Network Match" änderbar. Anders als die
  Zufallsnamen des lokalen Spiels überlebt er den Neustart — im Turnier steht er im Bracket.
  Beim ersten Start wird einer vorbelegt, damit niemand vor dem ersten Match ein Formular
  ausfüllt. Ist der Name in einer Lobby schon vergeben, hängt der Host eine Zahl an und sagt
  es dem Gast, statt ihn abzuweisen.
- **F3-Overlay** mit RTT, Paketverlust, Tick, Puffertiefe und wiederholten Eingaben.
- `tools/net_test.sh` fährt den Netzcode als ein oder zwei Prozesse gegen sich selbst,
  gespeist aus den aufgezeichneten Referenz-Rallyes.

### Geändert — M2

- `love . --test` läuft ohne Fenster, Grafik und Ton. Damit laufen die Protokolltests jetzt
  auch auf den CI-Läufern für Windows und macOS — und beantworten dort die Frage, ob beide
  Plattformen dieselben Bytes schreiben (offener Punkt N-03).
- `04_NETCODE_SPEC` auf 1.1 korrigiert: Ruleset-Hash ist djb2 mit acht Hexstellen statt MD5,
  `RULESET_FULL` überträgt binär statt JSON (ADR-016), und die Snapshot-Feldliste ist gegen
  `src/sim/state.lua` erhoben statt entworfen — zwei der fünf spezifizierten Phasen gab es
  nicht, drei sichtbare Werte fehlten.
- Die Zuordnung von Simulationsereignissen zu Staub, Klang und Wackeln liegt jetzt in
  `src/render/fx_events.lua`; lokales Spiel und Netzspiel benutzen dieselbe.

### Behoben — M2

- Discovery erzeugte ihre Sockets mit `socket.udp()` und bekam unter LuaSocket 3.0 einen
  IPv6-Socket, auf dem jeder IPv4-Broadcast scheitert. Jetzt `socket.udp4()`.
- Ein Host auf demselben Rechner stand doppelt in der Serverliste, einmal über die
  Loopback- und einmal über die LAN-Adresse.
- Zwei Instanzen auf einem Rechner teilen sich die Einstellungsdatei und damit die
  Spielerkennung; der Gast wurde dadurch als Rückkehrer auf den Platz des Hosts gesetzt.
- Das Vorzeichen der Null entsteht auf Windows und macOS unterschiedlich (auf Apple Silicon
  läuft der Interpreter statt des JIT). Sichtbar wurde das erst im CI-Lauf auf beiden
  Plattformen. Snapshots begradigen die Null jetzt vor dem Senden — sonst meldete die
  Prüfsumme aus M3-03 später in jedem stillen Tick einen Unterschied, den es nicht gibt.

## [0.1.0] — 2026-08-12

Erste verteilbare Fassung. Lokales Spiel gegen einen zweiten Spieler an derselben Tastatur
oder gegen den Bot. **Kein Netzwerk** — LAN kommt mit M2.

### Hinzugefügt — M1 (Build und Repo)

- `tools/build.sh` erzeugt aus dem Repo die `.love` und daraus die Pakete für Windows und
  macOS. Ausschlusslisten halten `docs/`, `tests/` und `tools/` aus der Auslieferung.
- `src/build_info.lua` wird beim Build erzeugt und trägt Version und Build-Hash. Beide
  stehen im Menü — die Bug-Vorlage fragt genau diese Zeichenkette ab.
- macOS-Paket mit verpflichtender Ad-hoc-Signatur (ADR-012); `codesign --verify` bricht den
  Build ab, wenn die Signatur nicht hält.
- `LIESMICH.txt` für beide Plattformen mit dem SmartScreen- und dem Gatekeeper-Weg.
- Öffentliches `README.md`, `CONTRIBUTING.md`, Issue-Vorlagen, GitHub-Actions-Workflow.
- `LICENSE-THIRD-PARTY.md`, `assets/CREDITS.md`, `docs/references.md`.

### Geändert — M1

- Bilder und Klänge liegen jetzt unter `assets/` statt im Wurzelverzeichnis.
- Der Hintergrund ist von 2752 × 1536 auf 1600 × 1200 verkleinert und heißt jetzt
  `assets/bg.png` statt `bg.jpg` — die Datei war nie ein JPEG. Spart 3,4 MB im Paket und
  senkt den Texturspeicher von rund 16 MB auf 7,7 MB.
- `main.lua` lädt das Aufzeichnungswerkzeug nur noch, wenn es da ist. Ohne diese Änderung
  wäre jede gebaute `.love` beim Start gescheitert, weil `tools/` nicht ausgeliefert wird.

### Hinzugefügt — M0 (Fundament)

- Fixer Simulationsschritt 1/60 s mit Akkumulator, davon entkoppeltes und interpoliertes
  Rendering (B-02).
- Logisches Spielfeld fix 800 × 600, Fensteranpassung als Letterbox/Pillarbox (B-01,
  ADR-004).
- `InputFrame` als einzige Eingabequelle der Simulation; Tastatur, Gamepad und Bot liefern
  denselben Datentyp (B-03, ADR-014).
- `src/sim/` ist nachweislich frei von `love` und von Zufall — belegt durch
  `--test-no-love`.
- `Ruleset` und `Prefs` getrennt, Presets `classic` und `prototype`, kanonischer
  Ruleset-Hash (B-04, ADR-005).
- Zwei-Punkte-Vorsprung, Deuce-Deckel und Rallye-Timeout (B-05).
- Konfigurierbare und persistente Tastenbelegung, Gamepad-Slots.
- Sound-Pool mit vier Stimmen je Klang, Hintergrundmusik mit Shuffle-Playlist.
- Headless-Testrunner mit 83 Fällen und elf aufgezeichneten Referenz-Rallyes.

### Geändert — M0

Zwei gewollte Verhaltensänderungen, alles andere ist bitgleich nachgewiesen:

- Der Bot bekommt im Absprungtick nicht mehr die volle Bodengeschwindigkeit; `airControl`
  gilt jetzt für beide Seiten gleich (M0-07).
- Ein Aufwärts-Dash mit gehaltener Richtungstaste wird zum Seitwärts-Dash, weil die Richtung
  aus den Richtungsbits kommt (M0-06, ADR-014).

### Abnahme

- **D1 (Spielgefühl) am 2026-08-12 als Product-Owner-Abnahme erteilt.** r0btoshi hat alte und
  neue Fassung selbst gespielt. Das vorgesehene Verfahren aus `07_TEST_PLAN` §6 — drei
  Personen im Blindwechsel — wurde **nicht** durchlaufen; die Abnahme beruht auf einer
  Person. Das ist eine Entscheidung, keine Lücke, und steht deshalb hier.
