# Handoff CC-07 — Spectator + Beamer

**Meilenstein:** M5 · **Aufgaben:** M5-01 … M5-05 aus `08_ROADMAP_BACKLOG.md`, dazu F-T-10
aus `CC-05_REPORT` §3
**Abhängig von:** M4 (abgeschlossen, alle Stufen A–D, `CC-05_REPORT` Kopftabelle)
**Erstellt:** 2026-08-14 · **Status:** Entwurf. Stufenschnitt und die vier Zuschnittsfragen
(§1.2) sind freigegeben (r0btoshi, 2026-08-14); die Freigabe zur Ausführung erteilt r0btoshi
an dieser Statuszeile.

---

## 0. Lies zuerst

`CLAUDE.md` im Wurzelverzeichnis, dann diese Datei, dann:

- `04_NETCODE_SPEC.md` §3 (Bandbreite, Zuschauerzeile), §5 (Nachrichten), §6 (Snapshot),
  §8 letzter Abschnitt (**ADR-025** — die Vollzustands-Vorhersage ist der Bauplan des
  Zuschauers), §13 N-02
- `05_TOURNAMENT_SPEC.md` §8 (Rollen — die Beamer-Zeile), §10 (Darstellung), §11 (Statistiken)
- `CC-05_REPORT.md` §3: **F-T-10** (warum das Bildschirmfoto-Werkzeug zuerst kommt) und
  **C-T-01 bis C-T-05** (die Nahtfehler — jede Stufe dieses Handoffs baut neue Nähte
  zwischen Szene und Netzschicht, und genau dort saßen alle fünf)
- `00_PROJECT_CHARTER.md` §3 S7/S8 (was zugesagt ist) und §4 (was nicht)

Erst danach fasst du eine Datei an.

---

## 1. Wo das Projekt steht

**M4 ist fertig.** Das Turnier läuft über das Netz, gespielt wird darin, der Vierprozesslauf
mit Aussteiger läuft bis zum Sieger durch. Ausgangszahlen: `--test` 469 bestanden,
`--test-no-love` 428, `--net-selftest` 49, `--tournament-selftest` 81,
`verify_replays.py` OK.

**Was davon M5 trägt** — die Liste dessen, was du **nicht** neu baust:

| Baustein | Wo | Was M5 damit macht |
|---|---|---|
| Vollzustands-Vorhersage (ADR-025) | `src/net/prediction.lua`, `src/net/client.lua` | **Ein Zuschauer ist ein Gast ohne Eingabe.** Lokale Vollsimulation trägt das Bild, jeder Snapshot setzt neu auf; das Replay der eigenen Masken entfällt, weil es keine gibt |
| `SPECTATE_REQ` (0x30) | `src/net/protocol.lua` | Kodiert seit M2, nie behandelt. M5-01 gibt ihm einen Handler |
| Match-Wirt mit 8 Peers | `src/net/host.lua` | 2 Spieler + bis zu 6 Zuschauer, ohne das Limit anzufassen |
| Kosmetik aus Snapshot-Übergängen | `src/render/snapshot_events.lua` | Der Zuschauer bekommt Partikel und Klang auf demselben Weg wie der Gast |
| Volle Bracket-Ansicht (F2) | `src/render/bracket_view.lua`, `src/ui/tournament_lobby.lua` | Die Beamer-Szene zeigt sie unverändert; neu ist nur die Match-Auswahl daneben |
| Lesender Turnier-Client | `src/net/tournament_client.lua` | Der Beamer ist ein solcher Client ohne Teilnehmer-Anmeldung |
| Statistik-Beobachter | `src/tournament/match_stats.lua` | M5-04 auf dem Wirt. Liest nach jedem Tick, schreibt nichts zurück, `love`-frei |
| Satzzählung | `src/net/match_runner.lua` | „Satz 2" für M5-03. Sätze stehen **bewusst nicht** im Snapshot (`04_NETCODE` §6) |
| Screenshot-Code | `tools/net_selftest.lua`, `tools/reference_mode.lua` | Vorlage für das dauerhafte Werkzeug aus F-T-10 |

**Die Regel aus M2 bis M4 gilt weiter:** Was entscheidet oder ableitet, ist `love`-frei und
läuft im Headless-Runner. Was transportiert oder zeichnet, darf `love` benutzen.

**Die Lehre aus Stufe C von M4 gilt hier doppelt:** Alle fünf teuren Fehler saßen an Nähten
zwischen Szene und Netzschicht, und keiner war headless zu sehen. Der Zuschauer und der
Beamer sind neue Szenen mit eigenen Sockets — `alwaysUpdate` (ADR-024) von Anfang an
mitdenken, keinen Wirt aus seiner eigenen Ereignisschleife heraus schließen (C-T-05), und
die Mehrprozess-Abnahmen sind Teil jeder Stufe, nicht Kür am Ende.

### 1.2 Die vier Zuschnittsentscheidungen (freigegeben r0btoshi, 2026-08-14)

1. **Der Spectator gilt für freie LAN-Matches und Turniermatches.** Charter S7 sagt
   „beliebiger Client". Der Mechanismus ist derselbe; das freie Match ist der testbare
   Unterbau (Stufe B), das Turnier setzt nur die Adressbeschaffung obendrauf (Stufe C).
2. **Zuschauer bekommen 60 Hz, wie der Gast.** Die 30-Hz-Zeile in `04_NETCODE` §3 und die
   Messfrage N-02 stammen aus der Zeit vor ADR-025. Ein Codeweg statt zwei; die Bandbreite
   ist laut §3 selbst bei 4 Matches + 8 Zuschauern irrelevant. **N-02 wird per Spec-Nachtrag
   geschlossen, nicht per Messreihe** (Nachtrag gehört zu Stufe B, vor dem Code).
3. **Live-Statistiken werden beim Zuschauer lokal aus den Snapshots abgeleitet.** Kein
   Protokollzusatz. Das ist Anzeige, keine zweite Wahrheit: Die Turnierwertung kommt weiter
   allein vom Ergebnisbericht des Match-Wirts (`05_TOURNAMENT` §11).
4. **Der Beamer ist ein reines Anzeigegerät.** Match-Auswahl und Ansichtswechsel, keine
   Turnier-Bedienung. Wer bedienen will, sitzt am Rechner des Turnierleiters (F2 voll, wie
   seit M4-08). Einzige Ausnahme, wie überall: **X** exportiert — die Taste ist rein lesend.

**Annahmen dazu, festgehalten statt stillschweigend:** Der Beamer belegt keinen
Teilnehmerplatz, taucht in keiner Teilnehmerliste auf und hat keine Wirkung auf Anwesenheit
oder No-Show-Timer. Die Live-Statistik-Anzeige (M5-04) sehen **nur Zuschauer und Beamer** —
Spieler behalten ihr HUD unverändert. Widerspruch dazu bitte vor Stufe D.

---

## 2. Auftrag

**Reihenfolge ist Teil des Auftrags.** Jede Stufe endet mit etwas, das man vorführen kann.

### Stufe A — Das Werkzeug zuerst (F-T-10)

Beide Zeichenfehler aus M4 (B-T-03, B-T-04) waren nur im Bild zu sehen, und M5 ist fast
ausschließlich Zeichenarbeit. Deshalb steht das Werkzeug am Anfang, nicht am Ende.

Ein dauerhaftes Skript unter `tools/`, gestartet über ein Flag aus dem Repo-Wurzelverzeichnis
(z. B. `--shots=<szenario>`): fährt eine Szene über geskriptete Tastendrücke und schreibt
**benannte** Bildschirmfotos in den Save-Ordner. Szenarien liegen als kleine Beschreibungsdateien
unter `tools/` — das Wegwerfskript aus M4 (sechs Ansichten der Turnier-Lobby) wird als erstes
Szenario wiedergeboren. Capture-Code liegt als Vorlage in `tools/net_selftest.lua` und
`tools/reference_mode.lua`.

**Randbedingungen:** Das Flag braucht Grafik und gehört damit ausdrücklich **nicht** in die
Headless-Liste von `conf.lua` (Faustregel dort, C-T-07). Es ist ein Werkzeug, kein Test:
verglichen wird mit dem Auge, aber stabile Namen machen den Vergleich schnell. Läuft lokal;
eine CI-Einbindung ist nicht gefordert.

**Abnahme:** Die sechs M4-Ansichten entstehen reproduzierbar mit festen Dateinamen. Jede
folgende Stufe benennt ihre Soll-Bilder als Szenario.

### Stufe B — Spectator im freien Spiel (M5-01, Teil 1)

**Vorher fällig: ADR-026 (Spectator-Anschluss).** Inhalt mindestens: Zuschauer = Gast ohne
Eingabe (ADR-025-Pfad ohne Replay), 60 Hz (Entscheidung §1.2), Beitrittsweg über die
Serverliste, Antwortnachricht mit Matchkontext (unten), Kapazität aus dem vorhandenen
Peer-Limit, Verhalten bei Matchende und Revanche. Dazu die beiden Spec-Nachträge:
`04_NETCODE` §3 (Zuschauerzeile) und §13 (N-02 beantwortet).

Der Bau danach:

- **Wirt** (`src/net/host.lua`): behandelt `SPECTATE_REQ`. Zuschauer sind eine eigene
  Peer-Klasse — kein Lobby-Slot, keine Eingaben angenommen, Snapshots auf Kanal 1 und die
  Kanal-0-Nachrichten (`MATCH_END`, `MATCH_PAUSE`, …) wie an den Gast. **Die Trennung eines
  Zuschauers hat null Wirkung auf das Match** — keine Pause, kein Reconnect-Fenster. Das ist
  eine Zusicherung mit Testfall, keine Selbstverständlichkeit.
- **Antwort auf den Beitritt** (neue Nachricht, z. B. 0x31): Spielernamen, Satzstand,
  `bestOf`, im Turnierfall das Rundenlabel — alles, was der Zuschauer nicht aus dem Snapshot
  lesen kann. Wird bei Satzende erneut gesendet (zuverlässiger Kanal). Das ist zugleich die
  Datengrundlage für M5-03 in Stufe D — sie gehört zum Handschlag, nicht nachgerüstet.
- **Zuschauerseite:** der ADR-025-Pfad aus `src/net/prediction.lua` mit neutraler eigener
  Eingabe und ohne Abgleich/Korrekturzähler (es gibt keine eigene Position, die abweichen
  könnte). Kosmetik aus `snapshot_events`, HUD-Namen aus der Beitrittsantwort, ESC verlässt.
  F3 zeigt REPLAY 0 und zählt GEHALTEN, wenn Snapshots ausbleiben.
- **Serverliste:** `ANNOUNCE` trägt `players`/`maxPlayers` seit M2. Ein voller Eintrag („2/2")
  ist nicht mehr das Ende — ENTER dort tritt als Zuschauer bei. Die Fußzeile sagt das an.

**Abnahme:** Erweiterung `--net-selftest` (Wirt, Gast und Zuschauer in einem Prozess: der
Zuschauer sieht am Ende denselben Spielstand wie der Wirt; seine Trennung mitten im Satz
löst keine Pause aus; die Beitrittsantwort kommt an). Dritte Rolle in `tools/net_test.sh`.
Soll-Bilder über das Stufe-A-Werkzeug.

### Stufe C — Turnier-Anbindung und Beamer (M5-01 Teil 2, M5-02, M5-05)

**Vorher fällig: ADR-027 (Beamer-Rolle).** Zwei Fragen: Wie meldet sich ein Nicht-Teilnehmer
beim Turnier-Wirt an (das Header-`flags`-Byte scheidet aus — §5 verbietet ausdrücklich, es
auszuwerten; also eigene Anmeldenachricht oder eigenes Feld), und wie erfährt ein Zuschauer
die **ephemere** Adresse eines laufenden Match-Wirts? Die kennt nur der Turnier-Wirt — er
baut sie für `TOURNAMENT_ASSIGN` zusammen. Naheliegende Antwort: Anfrage an den Turnier-Wirt,
Antwort als `TOURNAMENT_ASSIGN` mit Zuschauer-Rolle (`role` gibt es dort schon, die Nutzlast
passt: `matchId ≤16`, `address ≤48`). Entscheide es im ADR, mit Begründung. Dazu der
Spec-Nachtrag in `05_TOURNAMENT` §8 (Beamer-Zeile konkretisieren).

Der Bau danach:

- **`--beamer`** startet in die Serverliste mit Vollbild-Voreinstellung und eigener
  Lautstärke (M5-05; beides `Prefs`, rein lokal, ADR-005). ENTER auf einem Turnier tritt als
  lesender Nicht-Teilnehmer bei: volle Bracket-Ansicht wie F2, dazu die Liste der
  `LIVE`-Matches. ENTER auf einem Match verbindet als Zuschauer (Stufe B, unverändert),
  ESC zurück zum Bracket. **Umgeschaltet wird von Hand** — keine Automatik (ADR-008).
- Der Beamer hält beide Verbindungen gleichzeitig — Turnier-Wirt und Match-Wirt — wie ein
  spielender Teilnehmer auch (zwei Sockets, `05_TOURNAMENT` §8.2). Die Turnierverbindung
  wandert mit in die Zuschauerszene (die Lehre aus C-T-01).
- **X** exportiert auch am Beamer (rein lesend, eigener Save-Ordner, wie beim Teilnehmer).
- Kein Teilnehmerplatz, keine Anwesenheitswirkung, kein Eintrag in Listen (§1.2, Annahmen).

**Abnahme:** Erweiterung `--tournament-selftest` (Nicht-Teilnehmer-Anmeldung: leitet
denselben Zustand ab, steht in keiner Teilnehmerliste, bekommt auf Anfrage die Adresse eines
`LIVE`-Matches; ein Turnier mit Beamer verhält sich für alle Teilnehmer exakt wie eines
ohne). Fünfter Prozess im Vierprozesslauf: `--tournament-auto=beamer` muss mindestens ein
Match als Zuschauer sehen und das Turnier bis zum Sieger verfolgen, sonst Exit 1.
Soll-Bilder der Beamer-Szene.

### Stufe D — Matchkontext und Live-Statistiken (M5-03, M5-04)

- **M5-03:** Kontextzeile im Match-HUD („Halbfinale · Satz 2 · Best of 3") — **nur im
  Turniermatch**, im freien Spiel gibt es keine Runden und keine Sätze. Der Zuschauer hat die
  Daten aus der Beitrittsantwort (Stufe B); der Spieler holt das Rundenlabel aus seiner
  eigenen lesenden Turnier-Session über die `matchId` — **kein** Protokollzusatz — und den
  Satzstand aus dem `MatchRunner`.
- **M5-04:** Ballgeschwindigkeit und Rallye-Länge, live, **nur für Zuschauer und Beamer**
  (§1.2, Annahmen). Auf dem Match-Wirt liefert der vorhandene Beobachter
  (`src/tournament/match_stats.lua`) die Werte; auf der Zuschauerseite leitet ein neues,
  `love`-freies Modul sie aus dem Snapshot-Strom ab (Nachbar von
  `src/render/snapshot_events.lua`: Geschwindigkeit aus |`ballVX`, `ballVY`|, Rallye-Länge
  aus den Phasenübergängen `serve → play → …`). Einheiten wie in `05_TOURNAMENT` §11:
  Sekunden, Pixel je Sekunde — eine Zahl ohne Einheit am Beamer kann niemand einordnen.

**Abnahme:** Headless-Tests für die Ableitung (ein aufgezeichneter Snapshot-Strom; das
abgeleitete Maximum stimmt mit dem des Wirt-Beobachters überein, Toleranz float32).
Soll-Bilder für Kontextzeile und Statistik-Einblendung.

---

## 3. Was du in dieser Session nicht tust

- **Keine automatische Beamer-Regie.** ADR-008, Charter §4. Sie rückt mit dem ersten
  20er-Turnier an ihren Revisionsauslöser — bewertet wird aus Beobachtung, nicht vorher.
- **Kein Zeitlupen-Replay.** M6 (Charter §4).
- **Keine Änderung an `src/sim/`.** M5 ist Netz-, UI- und Render-Arbeit. Die Zahlen aus
  `02_CODE_AUDIT` §4 bleiben unangetastet.
- **Kein neues Snapshot-Format, keine zweite Rate, kein neuer fester Port.** Der Zuschauer
  bekommt exakt die Gast-Snapshots (§1.2, Entscheidung 2); Match-Wirte binden ephemer wie
  seit M4-09.
- **Keine Turnier-Bedienung am Beamer** (§1.2, Entscheidung 4) — auch nicht „nur der
  No-Show-Timer, weil er gerade abläuft". Ausnahme bleibt X.
- **Kein Zuschauer-Chat, keine Zuschauerzähler-Anzeige für Spieler, keine Kamera-Wahl.**
  Nichts davon steht in der Roadmap.
- **Nichts aus M6** (`CLAUDE.md` §6): kein King of the Hill, kein 2v2, keine Mutatoren.
- **Nicht die AP-4-Sichtprüfung und nicht das Chaos-Szenario D3.** Beides braucht den
  LAN-Abend und macht r0btoshi (`CC-06_AP4_MESSANLEITUNG.md` §5, `07_TEST_PLAN` §6).

---

## 4. Abnahme

```powershell
D:\love2d\LOVE\lovec.exe . --test                 # Ausgang: 469 bestanden, 0 gescheitert
D:\love2d\LOVE\lovec.exe . --test-no-love         # Ausgang: 428, kein love im Namensraum
D:\love2d\LOVE\lovec.exe . --net-selftest         # Ausgang: 49 Pruefungen
D:\love2d\LOVE\lovec.exe . --tournament-selftest  # Ausgang: 81 Pruefungen
python tools\verify_replays.py                    # muss "OK" melden
```

Die Zahlen steigen mit den neuen Prüfungen. **Was nicht steigen darf, ist die Zahl der
gescheiterten.** Dazu der Fünfprozesslauf aus Stufe C, alle Exit 0.

**Und die eigentliche Abnahme, in beide Richtungen:**

- **S7/S8 aus dem Charter:** Ein beliebiger Client kann einem laufenden Match zusehen; ein
  dedizierter Rechner zeigt Bracket und wählbares Live-Match im Vollbild.
- **Die Falsifikation:** Ein Turniermatch mit Beamer-Zuschauer muss für die beiden Spieler
  **unmessbar** dasselbe sein wie eines ohne — kein Anstieg bei KORREKTUR oder DESYNC (F3),
  keine Pause, kein veränderter Ausgang. Ein Zuschauer, den die Spieler bemerken, ist ein
  Fehler, kein Feature.

---

## 5. Rückmeldung

Am Ende `docs/handoffs/CC-07_REPORT.md` mit denselben Abschnitten wie CC-01 bis CC-05:
Erledigt · Nicht erledigt und warum · Befunde · Spec-Änderungen · Entscheidungen für
r0btoshi · Nächster Schritt.

**Bei mehreren Sessions:** Der Bericht wird fortgeschrieben, nicht neu geschrieben. Am Kopf
steht, welche Stufen aus §2 stehen und welche nicht.

Stand in `08_ROADMAP` §2 nachtragen und `CHANGELOG.md` unter `[Unreleased]` ergänzen. Die
beiden ADRs (026, 027) stehen **vor** dem Code der jeweiligen Stufe im Log — Vorlage am Ende
von `09_DECISION_LOG_ADR.md`.

---

## 6. Was noch offen herumliegt und nicht zu M5 gehört

Damit es nicht als Versäumnis dieser Session gelesen wird:

- **AP-4-Sichtprüfung** (Ball-Schnapper bei Gegnerberührung, Revisionsauslöser von ADR-025)
  und **Chaos-Szenario D3** — nächster LAN-Abend, r0btoshi.
- **N-04** (nimmt ENet auf macOS eine eingehende Verbindung an?) und das macOS-Paket auf
  fremder Hardware — hängt am fehlenden Gerät. Seit M4-09 wiegt N-04 schwerer (Mac als
  Match-Wirt auf ephemerem Port); ein Beamer-Mac wäre dagegen nur ausgehend und unkritisch.
- **N-05** (UDP-Broadcast bei „öffentlichem" Netzwerkprofil) — Zweirechnertest.
- **T-N-02 und T-N-03** (Paketverlust): offen, seit ADR-019 nicht mehr blockierend.
- **Release 0.4.0** nach `12_OPENSOURCE` §7 — CHANGELOG, VERSION, Freigabe. Eigener Schritt,
  nicht Teil von M5.
