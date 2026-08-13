# CC-04 — WLAN-Messung (M3-04, offener Punkt N-01)

**Zweck:** `04_NETCODE_SPEC` §13, N-01 beantworten — *Reicht die Vorhersage des eigenen Blobs
bei RTT 20–40 ms, oder braucht der Client zusätzlich eine Ball-Extrapolation?*

**Das ist keine Entwurfsfrage, sondern eine Messfrage.** Sie braucht ein WLAN und zwei
Menschen. Diese Anleitung sorgt dafür, dass der Abend Zahlen hinterlässt und nicht Eindrücke.

**Dauer:** 25 Minuten, davon 10 Minuten Aufbau.

---

## 0. Was schon feststeht — und was nicht

Was **ohne** WLAN belegt ist (Selbsttest, `--net-selftest`, und die Testebene B):

- Die Vorhersage läuft Tick für Tick auf derselben Bahn wie `Step.tick` (12 Fälle, beide Slots).
- Im Loopback: 198 Abgleiche, **0 Korrekturen**. Der eigene Blob steht auf dem Pixel beim Host.
- Bei künstlich unterschlagenen Eingabepaketen schlägt der Korrekturzähler an und der Blob wird
  binnen vier Ticks wieder eingeholt.

Was das **nicht** beantwortet: wie sich das anfühlt, wenn der **Ball** 20–40 ms alt ist. Der
Ball wird nicht vorhergesagt (ADR-002), und ob das auffällt, entscheidet kein Zähler, sondern
ein Mensch mit einem Schläger in der Hand.

**Deshalb hat diese Messung zwei Teile: eine Zahl und ein Urteil.** Beide gehören ins Ergebnis.

---

## 1. Aufbau

1. **Beide Rechner ins WLAN**, nicht ans Kabel. Das ist der Punkt der Übung.
   Access Points mit Client-Isolation blocken den Broadcast zwischen Gästen
   (`04_NETCODE` §11) — findet die Suche nichts, ist die IP-Eingabe der letzte Eintrag in
   der Serverliste.
2. **Gebaute Pakete verwenden**, nicht den Quellordner. Gemessen wird, was am Partyabend läuft.
   *(Nebenwirkung: im Release schreibt `desync.log` nicht mit — nur die Zähler in F3. Für die
   Zahlen unten reicht das; wer die einzelnen Korrekturen sehen will, startet aus dem
   Quellordner.)*
3. **Nickname auf beiden Geräten setzen**, bevor irgendetwas startet.
4. **Auf beiden Seiten F3 einschalten** und **F4 drücken**. F4 schreibt einmal je Sekunde eine
   Zeile nach `netlog.csv` in den Save-Ordner:
   - Windows: `%APPDATA%\LOVE\volleydash\netlog.csv`
   - macOS: `~/Library/Application Support/LOVE/volleydash/netlog.csv`

   Unten rechts im Overlay steht dann `F4 REC`.

---

## 2. Die vier Läufe

Jeder Lauf ist **ein voller Satz**. Zwischen den Läufen F4 aus und wieder an — die Datei wächst
weiter, die Lücke im Zeitstempel trennt die Läufe.

| # | Aufbau | Wozu |
|---|---|---|
| 1 | WLAN, ohne Zutat | Der Normalfall. RTT sollte 5–30 ms sein |
| 2 | WLAN, `clumsy` mit **+30 ms** Verzögerung auf dem Host | Der Zielbereich von N-01 |
| 3 | WLAN, `clumsy` mit **5 % Verlust** auf Kanal 2 | zugleich **T-N-02** aus `07_TEST_PLAN` §4 |
| 4 | WLAN, `clumsy` mit **20 % Verlust** auf Kanal 1 | zugleich **T-N-03** |

`clumsy` läuft nur unter Windows. Filter und Begründung stehen im Kopf von `tools/net_test.sh`;
Kanal 1 sind die Snapshots (Host → Gast), Kanal 2 die Eingaben (Gast → Host).

**Beide Rollen durchspielen.** Wer nur einmal Gast war, hat die Hälfte gemessen.

---

## 3. Die Zahl

Aus `netlog.csv` des **Gastes**, je Lauf:

| Spalte | Was sie beantwortet |
|---|---|
| `rtt_ms` | Ist der Lauf überhaupt im Zielbereich? Unter 15 ms misst er nicht, was er messen soll |
| `korrektur` | Vorhersagefehler, **kumulativ**. Interessant ist der Zuwachs je Sekunde |
| `desync` | Muss **0** bleiben. Alles andere ist ein Befund, kein Messwert |
| `puffer` | Soll 2–4 sein. Dauerhaft 0 heißt: der Gast hungert, das Bild stockt |
| `gehalten` | Ticks ohne neuen Snapshot — das sieht man als Stocken |

**Auswertung:** Zuwachs von `korrektur` über den Satz, geteilt durch die Sekunden.

- **unter 1 je Sekunde** → die Vorhersage trägt.
- **1 bis 5 je Sekunde** → sie trägt, aber der Verlust ist hoch. Erst das Netz ansehen, nicht
  den Netzcode.
- **über 5 je Sekunde bei RTT unter 40 ms** → Befund. Dann stimmt etwas mit der Zuordnung über
  `ackInputTick` nicht (ADR-017), und das ist ein Fehler, kein Anlass für ein neues Feature.

---

## 4. Das Urteil

Die Zahl sagt nichts über den Ball. Deshalb dieselbe Frage an **beide** Spieler, nach Lauf 2,
getrennt und ohne Absprache:

1. **„Konntest du sagen, ob du Host oder Gast warst?"** — Das ist das Abnahmekriterium aus dem
   Handoff, wörtlich.
2. **„Kam der Ball dorthin, wo du hingeschlagen hast?"** — Wenn nein: kam er zu früh oder zu
   spät?
3. **„Hat sich dein eigener Blob verzögert angefühlt?"** — Wenn ja, ist das ein
   Vorhersagefehler und widerspricht der Zahl aus §3. Dann gilt die Wahrnehmung, und der
   Widerspruch ist der eigentliche Befund.

---

## 5. Ergebnis eintragen

**Nicht nur in den Report.** `04_NETCODE_SPEC` §13, Zeile N-01, bekommt die Antwort im selben
Format wie N-03: Was gemessen wurde, mit welchen Zahlen, und was daraus folgt.

**Die Entscheidungsregel steht vorab fest**, damit sie nicht nachträglich zur Beobachtung
passend gemacht wird:

| Beobachtung | Folge |
|---|---|
| Beide sagen „konnte ich nicht sagen", Korrekturrate < 1/s | **N-01 geschlossen: nein.** Keine Ball-Extrapolation. M3 ist fertig |
| Der Gast merkt den Ball, der eigene Blob fühlt sich richtig an | **N-01 offen.** Ball-Extrapolation wird ein Vorschlag für **M6**, nicht für M3 — sie ist der Punkt, an dem die Komplexität explodiert (Handoff CC-04 §4) |
| Der eigene Blob fühlt sich verzögert an | **Fehler in M3-01.** Zuerst `desync.log` aus einem Lauf im Quellordner, dann ADR-017 gegen den Code prüfen |

Der mittlere Fall ist der einzige, in dem über neue Funktionen zu reden ist — und auch dann
erst nach M5 (`CLAUDE.md` §6).

---

## 6. Nebenbei mitnehmen

Wenn ohnehin zwei Geräte zusammenstehen, kosten diese drei fast nichts extra:

- **T-N-09** — drei Lobbys gleichzeitig. Braucht ein drittes Gerät; ein Telefon reicht nicht,
  aber ein dritter Laptop schon. Erwartung: drei Einträge in der Liste, unterscheidbar.
- **N-04** — nimmt ein frischer Mac eine **eingehende** Verbindung ohne zusätzliche Freigabe an?
  Ausgehend funktioniert erfahrungsgemäß immer. Offen seit M2.
- **Der Bodentreffer-Klang beim Gast.** M3-02 rekonstruiert ihn aus dem Rallye-Ende, weil der
  Snapshot den Ball nie im Sand zeigt (`04_NETCODE` §6). Einmal hinhören: klingt der Punkt beim
  Gast wie beim Host? Wenn er fehlt oder doppelt kommt, steht die Rekonstruktion falsch.
