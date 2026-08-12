# CC-03 — Rückmeldung (M2 LAN 1v1)

**Datum:** 2026-08-12 · **Auftrag:** `docs/handoffs/CC-03_M2_LAN.md`
**Ausgangsstand:** 968e35f · **Endstand:** siehe `git log` ab e69980d
**Tests:** 155 bestanden, 0 gescheitert (vorher 83) · **Netz-Selbsttest:** 37 Prüfungen, alle grün
**Referenzen:** `python tools/verify_replays.py` meldet OK

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
| T-N-07 gleiche Bytes auf Win und macOS | **halb** | Windows: Referenzbytes stimmen. macOS: CI-Job steht, ist aber **noch nie gelaufen** |
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

3. **Der Spielername ist weiterhin der zufällige aus dem Namenspool** und überlebt keinen
   Neustart. Für die Lobby reicht das; ein persistenter Name wäre ein neues Prefs-Feld und
   ein Menüeintrag. **Sag Bescheid, wenn er vor der Party persistent sein soll** — am
   Partyabend erkennt man sich an Namen.

4. **ESC im laufenden Satz beendet die ganze Sitzung**, nach dem Abpfiff dagegen nur das
   Match und man landet wieder in der Lobby. So kostet das nächste Match keinen neuen
   Handschlag. Das ist eine Setzung von mir, kein Spec-Punkt.

5. **`--client-id=N` gibt es nur für die Testflags**, nicht im Spiel. Zwei Instanzen auf einem
   Rechner brauchen es, echte Gäste nicht.

---

## 6. Nächster Schritt

1. **Pushen und die CI ansehen.** Der Job `protocol` läuft auf `windows-latest` und
   `macos-latest` und beantwortet T-N-07 endgültig. Läuft der macOS-Läufer LÖVE nicht ohne
   Bildschirm, ist das dort zu sehen und nicht am Partyabend.
2. **D2 mit zwei Rechnern**, am besten einer davon der Mac: Discovery über einen echten
   Switch, Windows-Firewallabfrage abwarten statt wegklicken (N-05), ENet eingehend auf
   macOS (N-04), ein vollständiger Satz für T-N-01.
3. **`clumsy` einmal von Hand** für T-N-02 und T-N-03. Filter steht im Skriptkopf.
4. Danach ist M2 abgenommen und **M3** dran: Vorhersage des eigenen Blobs (M3-01) und
   Kosmetik aus Snapshot-Deltas (M3-02). Das Feld „KORREKTUR" im F3-Overlay steht schon da
   und meldet 0 — M3-01 füllt es, statt es zu erfinden.
