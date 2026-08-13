# CC-04 — Rückmeldung (M3 Netzwerk-Politur)

**Datum:** 2026-08-12 · **Auftrag:** `docs/handoffs/CC-04_M3_NETZPOLITUR.md`
**Ausgangsstand:** 4bcb582 (`v0.2.2`)
**Tests:** 214 bestanden, 0 gescheitert (vorher 179) · **ohne `love`:** 183 (vorher 148)
**Netz-Selbsttest:** 47 Prüfungen, alle grün (vorher 37)
**Referenzen:** `python tools/verify_replays.py` meldet OK

> **M3 ist abgeschlossen.** `v0.3.0` ist getaggt, die CI hat beide Pakete gebaut, und das
> Windows-Paket ist auf einem Fremdrechner heruntergeladen, gestartet und gespielt worden
> (r0btoshi, 2026-08-13). AP-4 ist per **ADR-019 zurückgestellt**: Gespielt wird über Kabel,
> dort wird die WLAN-Frage nicht gestellt. Zurückgestellt heißt nicht beantwortet — Werkzeug
> und Messanleitung bleiben im Repo. Der Nachfolgeauftrag liegt als
> `docs/handoffs/CC-05_M4_TURNIER.md` bereit.

---

## 0. Nachtrag nach dem Release — 2026-08-13

**`v0.3.0` ist draußen.** Schritte 1–4 des Release-Prozesses aus `12_OPENSOURCE` §7 sind
gelaufen, die CI hat den Entwurf mit beiden Paketen bestückt, und **Schritt 7 ist für Windows
erledigt**: heruntergeladen, gestartet, läuft.

**Damit schließt sich die Lücke aus §2:** Die Spielszene war in der Entwicklungsumgebung nie
ausgeführt worden (kein OpenGL in der Shell), nur übersetzt. Der Start auf dem Fremdrechner
war also nicht Formalie, sondern die eigentliche Abnahme des Zusammenbaus.

**Was weiterhin offen ist und keinem zugeordnet war:** Das **macOS-Paket** ist gebaut und
ad-hoc signiert, aber auf keinem fremden Mac gestartet. Damit bleibt auch **N-04** offen (nimmt
ENet auf macOS eine eingehende Verbindung ohne zusätzliche Freigabe an?). Beides hängt am
selben fehlenden Gerät und ist kein M3-Rest, sondern eine stehende Abnahme aus M1/M2.

**B-N-16 — Ein Paketlauf aus dem Repo-Verzeichnis mischt Archiv und Arbeitskopie.**
Beim Gegenprüfen des Pakets gefunden: `lovec build/VolleyDash.love --test` meldete aus dem
Repo-Wurzelverzeichnis 214 bestandene Tests und stürzte aus jedem anderen Verzeichnis beim
Start ab. `tests/` und `tools/` liegen bewusst nicht in der `.love` — Lua findet sie über den
normalen Suchpfad aber trotzdem, wenn das Arbeitsverzeichnis zufällig das Repo ist. Der Lauf
prüfte also nie das Paket. Kein neuer Fehler, sondern eine Falle seit dem ersten Build; in
`CLAUDE.md` §12 festgehalten. **Aus dem Paket heraus gibt es folgerichtig keine Testflags: das
Paket wird gespielt, nicht getestet.**

**Entscheidung r0btoshi, 2026-08-13: Der Abend läuft über Kabel** (ADR-019). Folgen, alle
eingetragen: N-01 zurückgestellt, A1 im Charter auf einen Switch verengt, Switch und Kabel auf
der Packliste in `11_OPS` §1, T-N-02/T-N-03 nicht mehr blockierend — und **T-N-09 wandert nach
M4-09**, weil mehrere gleichzeitige Lobbys mit parallelen Matches der Normalfall sind.

Nebenbei erledigt, weil ohnehin am Runbook gearbeitet wurde: **T-02** aus `05_TOURNAMENT` §12
(der Turnier-Host darf nicht der Rechner von jemandem sein, der früher geht) steht jetzt als
Punkt 5 der Vorbereitungsliste.

---

## 1. Erledigt

| AP | Aufgabe | Ergebnis |
|---|---|---|
| AP-1 | M3-01 | `src/net/prediction.lua` — `love`-frei, ruft `src/sim/` auf statt es zu kopieren. Abgleich gegen `ackInputTick`, Korrektur als Sichtversatz über 4 Ticks. ADR-017 |
| AP-2 | M3-02 | `src/render/snapshot_events.lua` — reine Funktion über zwei Snapshots, im Headless-Runner. Zehn Ereignisarten, dieselben Namen wie `Step.tick` |
| AP-3 | M3-03 | djb2 über die gepackten Snapshot-Bytes, `desync.log` mit zwei Zeilenarten, zweiter Zähler im F3-Overlay. ADR-018 |
| AP-4 | M3-04 | **Nicht durchgeführt** (§2). Vorbereitet: Messanleitung, F4-Mitschnitt, Entscheidungsregel |

### Was der Gast jetzt anders erlebt

**Sein Blob reagiert sofort.** Vorher: Taste drücken, zwei Ticks warten, Wirkung sehen. Jetzt
rechnet er ihn lokal — mit **derselben** Physik, nicht mit einer nachgebauten. Ball, Gegner
und Punktestand kommen unverändert allein vom Host (ADR-002).

**Sein Bild staubt und klingt.** Wandtreffer, Netztreffer, Blobtreffer, Sprung, Landung, Dash,
Aufschlag, Fehlerwurf, Punkt, Seitenaus und Satzende — alles aus dem Unterschied zweier
Snapshots, kein zusätzliches Byte auf der Leitung.

**Das Feld KORREKTUR im F3-Overlay meldet nicht mehr 0, weil nichts gemessen wird**, sondern
weil nichts abweicht. Daneben steht jetzt DESYNC.

### Belege

- **Ebene B, 28 neue Fälle.** Der wichtigste: dieselbe Eingabefolge einmal durch `Step.tick`
  und einmal durch die Vorhersage, Tick für Tick verglichen, für **beide** Slots, 180 Ticks,
  Toleranz 10⁻⁴ px. Läuft das auseinander, ist die Vorhersage eine zweite Physik.
- **Selbsttest im Loopback:** 198 Abgleiche, **0 Korrekturen**, der vorhergesagte Blob steht
  auf dem Pixel beim Host.
- **Selbsttest mit unterschlagenen Eingabepaketen:** Der Korrekturzähler schlägt an und der
  Blob ist danach wieder da, wo der Host ihn hat. Dazu unten mehr — das war nötig, weil ein
  Zähler, der nie zählt, auch abgeklemmt sein könnte.
- **Prüfsummen:** 15 verglichen, 0 abweichend. Dazu drei Gegenproben: ein falscher Wert wird
  erkannt, **in beiden Ankunftsreihenfolgen**, und ein richtiger geht durch.

---

## 2. Nicht erledigt, und warum

- **AP-4, die WLAN-Messung.** Sie braucht ein WLAN, zwei Geräte und zwei Menschen. Was sich
  ohne das belegen ließ, ist belegt (§1); was offen bleibt, ist die **Wahrnehmung des Balls** —
  er wird nicht vorhergesagt, und ob 20–40 ms daran auffallen, entscheidet kein Zähler.
  Ein geratenes Ergebnis in `04_NETCODE_SPEC` §13 wäre schlimmer als ein offener Punkt: Es
  stünde dort als Messung.
- **T-N-02, T-N-03, T-N-09** (Restschuld aus M2). Unverändert offen, unverändert
  Hardware-gebunden. Sie stehen als §6 in der Messanleitung, damit sie mitgenommen werden,
  wenn ohnehin Geräte zusammenstehen.
- **Der Autopilot mit Bild** (`tools/net_test.sh auto`) ließ sich hier nicht fahren: Diese
  Shell hat kein OpenGL 2.1 (`1.1.0 - GDI Generic`). Der Loopback mit **zwei Prozessen** lief
  dagegen (2:0 auf beiden Seiten, 3597 Snapshots). Die Spielszene selbst ist damit **nicht
  ausgeführt**, sondern nur übersetzt — der Selbsttest prüft das jetzt ausdrücklich, aber
  Übersetzen ist nicht Laufen. **Das ist die Lücke, die der erste Start am Gerät schließt.**

---

## 3. Befunde

**B-N-11 — Die Prüfsumme überholt den Snapshot, auf den sie sich bezieht.**
Gemessen, nicht vermutet: Im ersten Lauf standen 0 geprüfte und 7 fehlende Prüfsummen.
`CHECKSUM` läuft über Kanal 0 (zuverlässig), der Snapshot über Kanal 1 (unzuverlässig) — und
**zwischen zwei ENet-Kanälen gibt es keine Reihenfolge**. Im Loopback lief die Prüfsumme
*ausnahmslos* vor. Wer hier auf die naheliegende Reihenfolge baut, bekommt einen Detektor, der
nie etwas prüft und trotzdem grün meldet. Der Client hält jetzt beide Hälften und vergleicht,
sobald die zweite da ist. Beide Richtungen sind im Selbsttest abgesichert.

**B-N-12 — Ein Vergleich gegen die Gegenwart hätte die Vorhersage unbrauchbar gemacht.**
Kein Fehler im Code, sondern eine Lücke in der Spec, gefunden beim Bauen: Ein Snapshot
beschreibt die Vergangenheit. Ein Abgleich der aktuellen Vorhersage gegen ihn findet bei
jedem Lauf rund 30 px Abweichung, obwohl nichts falsch ist — die Korrektur liefe dauernd und
der Blob gummibandelte. `ackInputTick` steht seit M2 genau dafür im Snapshot; §8 sagte nur
nicht, dass er dafür zu benutzen ist. Steht er still, weil der Host eine Maske wiederholt hat,
wird gar nicht verglichen. Nachgetragen in §8 und ADR-017.

**B-N-13 — Der Korrekturzähler war ungeprüft, weil er richtig lag.**
Im sauberen Loopback bleibt er bei 0. Das ist das erwünschte Ergebnis und zugleich ein
Testproblem: Ein abgeklemmter Zähler sähe genauso aus. Der Selbsttest unterschlägt jetzt
absichtlich jedes fünfte Eingabepaket — drei aufeinanderfolgende, damit auch die dreifache
Redundanz aus §7 die Lücke nicht mehr schließt. Der Zähler schlägt an, der Blob wird
eingeholt. Unterschlagen wird im **Werkzeug**, nicht im Spiel: ein Testschalter im
ausgelieferten Code ist ein Schalter, den irgendwann jemand findet.

**B-N-14 — `Rules.resetBall` versetzt beide Blobs, und das ist keine falsche Vorhersage.**
Nach jedem Punkt springen beide Blobs auf die Aufschlagposition. Weich nachgefahren sähe das
falsch aus, und gezählt hätte es nach zehn Punkten zehn „Fehler" gemeldet, die keine sind.
Solche Übernahmen werden hart ausgeführt und getrennt gezählt. Erkannt wird der Fall am
abgeleiteten `rally_reset` — dasselbe Ereignis, das die Renderschicht ohnehin für die
Interpolationssprungstelle braucht.

**B-N-15 — Der Bodentreffer ist im Snapshot nie zu sehen.**
`Rules.checkGround` meldet ihn und setzt den Ballwechsel im **selben Tick** zurück; der
nächste Snapshot zeigt den Ball also schon wieder auf Aufschlaghöhe. Ohne Gegenmaßnahme fehlt
dem Gast genau der Klang, der einen Punkt hörbar macht. Rekonstruiert aus dem Rallye-Ende plus
der Ballhöhe im vorigen Bild — ein Fehlerwurf und ein Rallye-Timeout enden in der Luft und
lösen ihn deshalb nicht aus. **Das ist der einzige abgeleitete Auslöser mit einer Annahme
darin; er gehört beim ersten Spiel am Gerät angehört** (§6 der Messanleitung).

**Nicht ableitbar und bewusst weggelassen:** `smash` und `dash_save`. Beide hängen an einer
Taste im Moment des Kontakts und hinterlassen keine Spur im Zustand. Der Gast hört den
Treffer, das Wackeln entfällt. Sie zu übertragen hieße, Kosmetik ins Protokoll zu nehmen —
zwei Bit für ein Wackeln.

---

## 4. Spec-Änderungen

Alle **vor** dem Code eingetragen, nach der Regel aus `CLAUDE.md` §2.

| Datei | Änderung |
|---|---|
| `09_DECISION_LOG_ADR` | **ADR-017** — Vorhersage ruft die Simulation auf, gleicht gegen `ackInputTick` ab, korrigiert als Sichtversatz. **ADR-018** — Prüfsumme über die gepackten Bytes mit djb2 |
| `04_NETCODE_SPEC` → 1.2 | §6 Tabelle der ableitbaren Auslöser und der nicht ableitbaren; §8 Zeitrichtigkeit, Sichtversatz, harte Übernahme; §9 vollständig neu gefasst; §13 N-01 mit Zwischenstand |
| `07_TEST_PLAN` | §4 sechs neue Fälle T-N-12…T-N-16; §5 neu gefasst — zwei Fehlerklassen, zwei Zähler, F4-Mitschnitt |
| `03_TECH_ARCHITECTURE` | Drei neue Dateien im Baum; Begründung, warum eine `render/`-Datei `love`-frei ist; die Ausnahme in `step.lua` protokolliert |
| `08_ROADMAP_BACKLOG` | M3 mit Stand je Aufgabe |
| `CHANGELOG.md` | `[Unreleased]` |
| `CLAUDE.md` | §12 um F4, `netlog.csv` und `desync.log` ergänzt |

**Eine Konsequenz von ADR-016 ist damit hinfällig:** Sie schrieb fest, dass der Desync-Detektor
weiter mit `love.data.hash("md5", …)` rechnet. Das war formuliert, bevor klar war, *worüber* er
rechnet. Über die Zahlen gerechnet erzeugt jede Prüfsumme Fehlalarme (der Host hält float64,
über die Leitung gehen float32); über die gepackten Bytes gerechnet sind Fehlalarme
bauartbedingt ausgeschlossen — und dann ist djb2 der Hash, den das Projekt schon hat.
`love.data.hash` wird jetzt nirgends benutzt.

**Was §9 nicht mehr verspricht:** Der Detektor bestätigt **nicht**, dass Host und Client
denselben Simulationszustand haben. Das kann er nicht — der Client kennt den Zustand des Hosts
nicht —, und ADR-002 macht die Frage gegenstandslos: Es gibt genau einen Zustand.

---

## 5. Entscheidungen für r0btoshi

1. **Zwei Zeilen in `src/sim/step.lua`.** Der Auftrag verlangte, `updateBlobTimers` und
   `Physics.updateBlob` *aufzurufen* statt sie zu kopieren — die erste ist aber lokal und von
   außen nicht erreichbar. Ich habe sie sichtbar gemacht (`Step.updateBlobTimers`,
   `Step.applyImpulses`): zwei Zuweisungen, keine Zeile Logik, kein Zahlenwert aus
   `02_CODE_AUDIT` §4 angefasst. **Die Alternative wäre eine Kopie der Blob-Bewegung im
   Netzcode gewesen** — eine zweite Wahrheit über das Spielgefühl, die beim ersten Eingriff
   still gegen den Host driftet. Wenn du das anders willst, ist der Preis genau diese Kopie.

2. **Der Desync-Detektor misst das Protokoll, nicht die Vorhersage.** §9 verlangte beides in
   einer Zahl. Das ist nicht ausführbar (der Client kennt den Zustand des Hosts nicht) und
   wäre auch unbrauchbar: Im Fehlerfall stünde eine Zahl da, die nicht sagt, ob die Vorhersage
   oder das Protokoll schuld ist. Jetzt sind es zwei Zeilen im Overlay. **KORREKTUR darf
   steigen** (Paketverlust), **DESYNC nicht** (verschiedene Builds).

3. **F4 schreibt einen Mitschnitt.** Nicht im Auftrag, aber die WLAN-Messung ohne ihn heißt:
   jemand fotografiert ein Overlay ab. Eine Zeile je Sekunde in `netlog.csv` macht daraus eine
   Messreihe, die man am nächsten Tag noch lesen kann. **Bewusst eine Taste und kein
   Kommandozeilenflag** — gemessen wird auf den gebauten Paketen, und die startet abends
   niemand aus einer Shell. Kostet rund 40 Zeilen und ist ohne Tastendruck vollständig inert.

4. **Die Entscheidungsregel für N-01 steht vor der Messung fest**, in §5 der Messanleitung.
   Absicht: Sie soll nicht nachträglich zur Beobachtung passend gemacht werden. Kurzfassung —
   sagen beide „ich konnte nicht sagen, ob ich Host oder Gast war" und bleibt die Korrekturrate
   unter 1 je Sekunde, ist N-01 mit **nein** geschlossen und M3 fertig. Ball-Extrapolation
   wäre selbst im ungünstigen Fall ein Vorschlag für **M6**, nicht für M3.

5. **Der Gast greift das Bild jetzt in jedem Tick zur Interpolation ab**, nicht nur beim
   Eintreffen eines Snapshots. Nebenwirkung und Verbesserung zugleich: Bleibt ein Snapshot
   aus, steht der Ball still, statt zwischen zwei alten Ständen hin und her zu gleiten. Das
   war vorher ein leises Zittern bei Jitter.

---

## 6. Nächster Schritt

*Ursprünglich standen hier drei Schritte: einmal starten, WLAN messen, dann `0.3.0`. Der erste
ist erledigt, der zweite zurückgestellt (ADR-019), der dritte veröffentlicht. Der Abschnitt
gilt jetzt so:*

**M4 — der Turniermodus.** Auftrag liegt als `docs/handoffs/CC-05_M4_TURNIER.md` bereit. Das
ist der Meilenstein, der den eigentlichen Zweck des Projekts trägt: 20 Leute an einem Abend
durch ein Bracket. Alles bis hierher war Voraussetzung.

**Wenn ein fremder Mac erreichbar ist**, kosten drei Dinge zusammen zehn Minuten: das
macOS-Paket starten (Rechtsklick → Öffnen), einmal als **Host** eine Verbindung annehmen
lassen (N-04), und im Match einmal auf den Punktklang hören — der Bodentreffer ist beim Gast
rekonstruiert und der einzige abgeleitete Auslöser mit einer Annahme darin (B-N-15).

**Nicht angefasst und weiterhin offen:** N-04 und der Start des macOS-Pakets auf fremder
Hardware. Beide hängen am selben fehlenden Gerät.
