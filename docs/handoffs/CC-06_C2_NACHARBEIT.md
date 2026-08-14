# Handoff CC-06 — Stufe C.2: Nacharbeit aus dem zweiten LAN-Abend

**Meilenstein:** M4 · **Aufgabe:** Zwischenschritt vor M4-10 (Stufe D)
**Erstellt:** 2026-08-14 · **Status:** freigegeben zur Ausführung
**Vorgänger:** `CC-05_M4_TURNIER.md`, Bericht `CC-05_REPORT.md`

---

## 0. Lies zuerst

`CLAUDE.md`, dann diese Datei, dann **`CC-05_REPORT.md`** — dort besonders den Kopf, die
Befundtabellen **C-T-11 bis C-T-19** und §7. Der Bericht ist die Geschichte dieses Moduls; er
wird fortgeschrieben, nicht neu geschrieben.

**Stufe D (Export, M4-10) wird erst begonnen, wenn diese vier Punkte erledigt sind.**
Entscheidung r0btoshi, 2026-08-14.

---

## 1. Wo das Projekt steht

M4 Stufe A, B, C und C.1 sind fertig, geprüft, committet und gepusht. Ein 4er-Turnier läuft über
vier echte Prozesse ohne einen Tastendruck bis zum Sieger durch; alle vier melden denselben
Sieger und dieselben Statistiken. Die CI ist grün auf `windows-latest` und `macos-latest` und
fährt beide Socket-Selbsttests mit.

**Der zweite LAN-Abend hat vier Dinge hinterlassen.** Drei davon sind Fehler oder Lücken, der
vierte ist die bekannte offene Frage aus `04_NETCODE` §8 — und die ist damit nicht mehr
theoretisch.

---

## 2. Auftrag

### AP-1 — Turniere löschen, abgeschlossene nicht mehr anbieten

**Gemeldet:** *„es wäre gut wenn jeder host seine turniere die nicht abgeschlossen wurden oder
die abgeschlossen sind auch wieder löschen kann mit sicherheitsabfrage. abgeschlossene turniere
sollten auch eigentlich gar nicht mehr gelistet werden oder?"*

**Was der Code heute tut:**

- `Persistence:running()` filtert auf `status == RUNNING`. Der Wiederaufnahme-Dialog zeigt also
  **nur laufende** — abgeschlossene erscheinen dort korrekterweise nicht.
- **Aber es gibt keinen Weg, irgendetwas zu löschen.** Jedes angelegte Turnier hinterlässt
  `tournaments/{id}.json` und `.json.bak`, für immer. Auch jedes, das nie ausgelost wurde
  (Status `setup`) — das taucht nirgends auf und liegt trotzdem da.
- `Persistence` hat den Unterbau schon: `self.fs.remove(name)` wird in `save` benutzt.

**Zu bauen:**

1. `Persistence:delete(id)` — entfernt `.json` **und** `.json.bak`. Eine Datei, die fehlt, ist
   kein Fehler.
2. `Persistence:all()` bzw. `list()` sichtbar machen: Für die Verwaltung braucht es **alle**
   Turniere mit Status, nicht nur die laufenden.
3. Bedienung im Turnier-Bildschirm: eine Liste der gespeicherten Turniere mit Status und Datum,
   Löschen mit **Sicherheitsabfrage**. Der Dialogmechanismus steht (`TL:openDialog`,
   `TL:commitDialog`, `TL:dialogKey`) und wird für Ergebnis und Korrektur bereits benutzt.

**Zu bedenken:** Die Datei ist nach `05_TOURNAMENT` §7 die Versicherung für den Fall, dass die
Software versagt. Ein Löschweg, den man versehentlich trifft, ist schlimmer als volle Platte —
deshalb die Abfrage, und deshalb **nicht** in denselben Tastenweg legen wie „Teilnehmer
streichen" (ENTF).

**Abnahme:** Ein Testfall, der zwei Turnierstände anlegt, einen löscht und prüft, dass der
andere unberührt ist — inklusive `.bak`. Dazu der Fall „löschen, während dasselbe Turnier
geladen ist".

### AP-2 — Die eigene IP-Adresse im Turnier anzeigen

**Gemeldet:** *„wenn man ein turnier erstellt hat sollte dort auch wie beim 1gg1 im lan die ip
Adresse angezeigt werden falls es nicht automatisch gefunden wird, dann muss niemand seine ip
raussuchen."*

**Was der Code heute tut:** Die Match-Lobby macht es bereits richtig — `src/app/scenes/lobby.lua`
holt sie mit `Discovery.localAddress()` und `src/ui/lobby_view.lua` zeigt sie an. Der
Turnier-Bildschirm zeigt sie nicht.

`04_NETCODE` §11 begründet das ausdrücklich: Wenn der Broadcast nicht durchkommt — Firewall,
WLAN-Client-Isolation, zwei Subnetze —, ist die manuelle Eingabe der Weg, und dafür muss jemand
die Zahl vorlesen können.

**Zu bauen:** Adresse in der vollen Turnieransicht, groß genug zum Vorlesen. `Discovery.localAddress`
liefert sie ohne Netzverkehr (`setpeername` auf UDP wählt nur die Route).

**Zu bedenken:** Sie gehört zum **Turnier-Wirt**, nicht zum Teilnehmer — bei dem steht dort
nichts Sinnvolles. Und sie kann `"?"` sein; dann gehört das auch so hingeschrieben.

### AP-3 — Der Weg zurück in ein unterbrochenes Match (der eigentliche Fehler)

**Gemeldet:** *„das mit dem verlassen funktioniert leider nicht, ich bin dann in der Lobby aber
trete weder automatisch wieder bei noch kann ich durch komplettes verlassen des turniers wieder
in das spiel das unterbrochen wird dann beitreten."*

**Die Ursache steht fest und ist eine Zeile.** In `TournamentHost:announceAssignments`:

```lua
if m.status == Model.STATUS.READY and m.slotA and m.slotB then
```

**Eine Zuweisung wird nur für ein `READY`-Match verschickt.** Sobald es `LIVE` ist, geht keine
mehr hinaus — nie wieder. Damit läuft die gesamte Rückkehrmechanik aus C-T-13 ins Leere:

- Der Aussteiger schickt `MATCH_ACCEPT{ready=false}`, der Wirt räumt `accepted` und `told` ab
  (das passiert korrekt) — **und dann passiert nichts**, weil die Schleife `LIVE` überspringt.
- Dasselbe beim vollständigen Verlassen und Wiederbeitreten: `onHello` ruft
  `announceAssignments`, und die überspringt das laufende Match ebenfalls.

Die zweite Hälfte der Bedingung ist ebenfalls falsch herum:

```lua
elseif self.assigned[id] and m.status ~= Model.STATUS.LIVE then
    -- Zuweisung verwerfen
```

Das räumt die gemerkte Adresse für alles auf, was nicht `LIVE` ist — also auch für ein Match,
das gerade auf `pending` zurückgesetzt wurde und gleich neu aufgerufen wird.

**Zu bauen:** Ein `LIVE`-Match muss weiterhin zuweisbar sein, solange ein Teilnehmer **keinen
Läufer** hat. Der Match-Wirt hält seinen Port ohnehin offen und nimmt denselben `clientId` als
Wiedereinsteiger an (`04_NETCODE` §12, `Host:onHello` mit `how == "reconnect"`) — der Weg
existiert also, es fehlt nur die Einladung.

**Achtung, zwei Fallen:**

1. **Der Match-Wirt braucht keine neue Zuweisung, der Gast schon.** Wer selbst hostet und
   aussteigt, löst E-06 aus (Match neu ansetzen) — das ist gebaut und richtig.
2. **Die Adresse muss erhalten bleiben.** Wird `self.assigned[id]` beim Zurücksetzen gelöscht,
   weiß der Wirt den ephemeren Port des Match-Wirts nicht mehr.

**Abnahme:** Im `--tournament-auto`-Lauf einen Teilnehmer mitten im Match ESC drücken lassen und
prüfen, dass er innerhalb weniger Sekunden wieder im selben Match landet. Dazu ein Fall im
`--tournament-selftest` auf der Protokollebene: `ready=false` bei einem `LIVE`-Match ⇒ eine
erneute `TOURNAMENT_ASSIGN` mit derselben Adresse.

### AP-4 — Ball im Blob beim Nicht-Host (N-01, jetzt fällig)

**Gemeldet:** *„das nicht-host-ball im blob Problem ist weiterhin bzw. schlimmer geworden sogar
vielleicht."*

**Stand der Erkenntnis** (ausführlich in `CC-05_REPORT`, „Der Ball-Verzug beim Gast" und
`04_NETCODE` §8, Nachtrag 2026-08-14):

- Der Gast sagt **seinen eigenen Blob** vorher und zeichnet ihn im Jetzt (ADR-017). Den **Ball**
  zeigt er aus dem Interpolationspuffer, also aus der Vergangenheit. Blob bei T, Ball bei
  T − Puffer.
- **Das hängt nicht an der RTT.** Bei 2 Ticks sind es 33 ms, auch bei RTT null. Das korrigiert
  die Begründung, mit der N-01 in ADR-019 zurückgestellt wurde.
- **Der Versuch, den Puffer auf 1 zu setzen, ist gemessen durchgefallen:** In der CI auf
  `macos-latest` kamen statt 203 von 206 Snapshots nur 146 zur Anzeige, 68 wurden gehalten. Ein
  Tick Vorrat überbrückt die Ankunftsschwankungen dort nicht.
- **Deshalb steht der Puffer auf 2**, ist über `prefs.netBuffer` umschaltbar (Menü → Settings →
  „Netz-Puffer (Gast)") und der Versatz steht im **F3-Overlay**.

**Was zuerst zu tun ist: messen, nicht bauen.** Vor jeder Codeänderung mit zwei Rechnern
feststellen, wie es sich bei Puffer 1 gegen 2 anfühlt, und die Zahlen aus F3 mitschreiben. Erst
danach entscheiden:

| Weg | Preis |
|---|---|
| Ball zwei Ticks extrapolieren | genau die Frage aus N-01; zappelt bei Richtungswechsel |
| Eigenen Blob zum **Zeichnen** ebenfalls verzögern | Blob und Ball wieder konsistent, dafür Eingabeverzögerung — also das, was die Vorhersage abschaffen sollte |
| Puffer 1 als Vorgabe | halbiert den Versatz, weniger Ruckelfestigkeit — die CI sagt: nicht umsonst |

**Das ist ein ADR**, kein Bugfix. `CLAUDE.md` §5: erst protokollieren, dann bauen.

**Zur Bemerkung „schlimmer geworden":** Das getestete Paket (Build-Hash `1a46e340032b7e1c`) hatte
den Puffer unverändert auf 2 — zwischen den beiden Abenden hat sich an dieser Zahl nichts
geändert. Wenn es schlimmer wirkt, liegt das entweder an der geschärften Aufmerksamkeit oder an
etwas anderem, das noch nicht benannt ist. **Das gehört gemessen und nicht geglaubt** — auch
meiner Erklärung nicht.

---

## 3. Was du wissen musst, bevor du anfängst

### Der Vierprozesslauf ist die einzige Prüfung, die diese Fehlerklasse findet

```
love . --tournament-auto=host --client-id=1
love . --tournament-auto=client --client-id=N     (dreimal, N = 2,3,4)
```

Er braucht **vier Prozesse und einen Desktop** (ohne OpenGL-Kontext startet er nicht) und läuft
ein 4er-Turnier ohne Tastendruck bis zum Sieger. **Jeder einzelne Fehler aus C.1 und ADR-024 ist
hier aufgefallen und in keinem der 446 Testfälle** — der Selbsttest fährt die Szene nicht.

`--tournament-selftest` (59 Prüfungen, in der CI) deckt Protokoll, Ports, Bracket und vier
parallele Matches ab, aber nichts, was eine Szene tut.

### Die Fehlerfamilie, die dieses Modul erzeugt

Keiner der neunzehn Befunde war ein Fehler in einer **Turnierregel**. Alle saßen an einer Naht:

| Naht | Befunde |
|---|---|
| Zwei Prozesse, zwei Uhren | C-T-12 (Log trägt Host-Zeit, Client rechnet gegen die eigene) |
| Zwei Rollen, eine Anzeige | C-T-11 (Namen gehören zum **Slot**, nicht zu „ich und der andere"), C-T-14 |
| Zwei Szenen, ein Socket | C-T-05, C-T-17, C-T-18 (wer bedient, wer räumt auf — `Scene.isTop`) |
| Nebeneffekt als Auskunft | C-T-19 (`opts.tournament ~= nil` als Ersatz für „ist ein Turniermatch") |
| Diagnose nach dem Lauf | C-T-08 (bei Abbruch gibt es sie nicht — `tee`, nicht `>`) |
| Test prüft die Umgebung | C-T-06 (drei Binds auf einem Port), C-T-09/C-T-10 (Replay statt Vorhersage) |

**Wer hier etwas ändert, fragt zuerst: Wer besitzt das, und wer läuft gerade?**

### ADR-024 ist frisch und ändert das Verhalten von ESC

Seit ADR-024 treibt `Scene.update` die oberste Szene **und** jede darunter mit
`alwaysUpdate = true` (`net_game`, `tournament`). ESC im Netzspiel öffnet damit das Menü, statt
die Sitzung zu beenden; das Match läuft weiter, die eigene Eingabe ist neutral. `local_game`
setzt die Marke nicht — dort bleibt das Nichtaktualisieren die Pause.

**Wichtig für AP-3:** Der Aussteigeweg aus C-T-13 (`abandonMatch`, `MATCH_ACCEPT{ready=false}`,
E-06 beim Match-Wirt) ist gebaut und richtig. Es fehlt nur die Einladung zurück.

### Werkzeuge und Umgebung

- **`gh` ist installiert und angemeldet.** Der CI-Stand wird selbst nachgesehen, nicht erfragt
  (`CLAUDE.md` §11). `gh run view <id> --log-failed` zeigt, warum etwas rot ist.
- Pakete ohne Release: `gh workflow run build.yml --ref main`, danach `gh run download`.
  **Artefakte gehören nicht ins Repo.**
- Arbeitsversion ist `0.4.0-dev`. Der `-dev`-Zusatz wird von `patch_plist.py` für die
  `Info.plist` abgeschnitten — Apple lässt dort nur Zahlen zu.
- **Keine Aufwandsschätzungen in Antworten.** Umfang über Inhalt und Risiko beschreiben.

---

## 4. Abnahme

```powershell
D:\love2d\LOVE\lovec.exe . --test                  # ≥ 446 bestanden, 0 gescheitert
D:\love2d\LOVE\lovec.exe . --test-no-love          # ≥ 405, kein love im Namensraum
D:\love2d\LOVE\lovec.exe . --net-selftest          # 49 Pruefungen
D:\love2d\LOVE\lovec.exe . --tournament-selftest   # ≥ 59 Pruefungen
python tools\verify_replays.py                     # OK
```

Was nicht steigen darf, ist die Zahl der gescheiterten. Dazu:

1. **Der Vierprozesslauf** bis zum Sieger, alle vier mit demselben Ergebnis.
2. **Der Aussteiger kommt zurück** (AP-3) — im Vierprozesslauf nachgestellt.
3. **CI grün** auf beiden Plattformen. Ein Push ist erst fertig, wenn der Lauf grün ist.

---

## 5. Rückmeldung

`CC-05_REPORT.md` wird fortgeschrieben — die Befunde laufen als **C-T-20 ff.** weiter, damit die
Nummerierung eine Geschichte bleibt. Kopf und §7 nachziehen, `08_ROADMAP` §2 und `CHANGELOG.md`
ebenfalls.

**Am Ende der Session der kopierfertige Startprompt für die nächste.**
