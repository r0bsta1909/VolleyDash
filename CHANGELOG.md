# Changelog

Alle nennenswerten Änderungen an Volley Dash. Format nach
[Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionierung nach
[Semantic Versioning](https://semver.org/lang/de/).

Bis 0.1.0 ist das Spiel nicht öffentlich verteilt worden — der erste Eintrag umfasst
deshalb die gesamte bisherige Arbeit, nicht nur die Änderungen eines Zyklus.

## [Unreleased]

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
