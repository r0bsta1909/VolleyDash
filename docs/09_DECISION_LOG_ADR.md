# 09 — Decision Log (ADR)

**Version:** 1.0 · **Stand:** 2026-08-11
Format: Kontext → Entscheidung → Begründung → Konsequenzen → Verworfene Alternativen.

---

## ADR-001 — Engine bleibt LÖVE 11.5

**Status:** angenommen · 2026-08-11

**Kontext:** Das Ausgangs-GDD ließ die Engine offen („Godot 2D, Raylib, LÖVE2D"). Der Prototyp existiert bereits in LÖVE.

**Entscheidung:** LÖVE 11.5, gepinnt in `conf.lua`. Kein Wechsel, kein 12.0-Nightly.

**Begründung:**
- Der Prototyp funktioniert und trifft das Spielgefühl. Ein Engine-Wechsel bedeutet vollständiges Neuschreiben der Physik — genau des Teils, der schon richtig ist.
- LÖVE bringt alles Nötige mit: <cite index="21-1">lua-enet ist mitgeliefert</cite>, <cite index="26-1">luasocket ist in der Binary enthalten</cite>, `love.data.pack` für binäre Serialisierung, `love.data.hash` für Prüfsummen. Null externe Abhängigkeiten für den gesamten Netcode.
- LÖVE 12.0 ist <cite index="13-1">offiziell nicht veröffentlicht; verfügbar sind nur Action- bzw. inoffizielle Nightly-Builds</cite>. Binaries an fremde Rechner zu verteilen, die auf einem unveröffentlichten Branch basieren, ist für ein Nebenprojekt das falsche Risiko.

**Konsequenzen:**
- Lua 5.1 / LuaJIT: kein `string.pack`, kein Integer-Typ, kein `//`-Operator. API-Auswahl entsprechend.
- Auf Apple Silicon läuft LuaJIT ohne JIT (siehe ADR-002) → Performance dort separat prüfen.
- Ein späterer Wechsel auf 12.0 ist möglich, aber nur nach Regressionstest der gesamten Ebene A.

**Verworfen:** Godot 4 (Neuschreiben), Raylib (Neuschreiben + C), Browser/HTML5 (love.js hängt bei 0.11.1 zurück und unterstützt keine Threads).

---

## ADR-002 — Host-autoritative Snapshots statt Lockstep

**Status:** angenommen · 2026-08-11 · **ersetzt eine Vorgabe des Ausgangs-GDD**

**Kontext:** Das Ausgangs-GDD forderte „deterministische 2D-Physik mit Lockstep-Architektur für minimale Latenz und Bildschirmsynchronität im LAN". Zielplattformen sind Windows-x86-64 und macOS-ARM64.

**Entscheidung:** Kein Lockstep. Der Host simuliert autoritativ und sendet 60-mal pro Sekunde einen vollständigen Zustands-Snapshot (64 Byte). Clients senden nur Eingaben.

**Begründung:**
1. <cite index="60-1">Lockstep verlangt strikten bitweisen Determinismus, weil bei identischen Eingaben jede Maschine pro Frame identische Ergebnisse berechnen muss.</cite>
2. <cite index="60-1">Plattformübergreifend ist Fließkomma-Determinismus besonders schwierig, weil Compiler verschiedene Befehlssätze verwenden, Befehle umordnen oder vektorisieren und transzendente Funktionen wie Sinus je System unterschiedlich implementiert sind.</cite>
3. LÖVE 11.5 hat <cite index="5-1">die JIT-Kompilierung auf macOS-arm64 standardmäßig abgeschaltet, weil Performance und JIT-Speicher dort nicht zuverlässig sind.</cite> Damit laufen Mac und Windows über unterschiedliche Ausführungspfade derselben Arithmetik.
4. Der einzige verlässliche Ausweg wäre Festkomma-Arithmetik — <cite index="60-1">manche Entwickler implementieren die Simulation ausschließlich in Fixed-Point- oder softwareemulierter Fließkomma-Arithmetik, um Indeterminismus zu umgehen</cite> — was in Lua 5.1 ohne Integer-Typ ein Neuschreiben der Physik bedeutet.
5. **Der Vorteil existiert hier nicht.** Lockstep spart Bandbreite bei großem Weltzustand. Dieser Zustand ist 64 Byte groß. Es gibt nichts zu sparen.

**Konsequenzen:**
- Desync im Lockstep-Sinne ist per Konstruktion unmöglich.
- Der Client hat 1 RTT Eingabelatenz. Bei LAN-RTT < 2 ms unkritisch; im WLAN wird das durch Vorhersage des eigenen Blobs kompensiert (M3).
- Der Host hat einen Vorteil (0 ms Latenz). Auf einer Freundes-LAN akzeptabel; im Turnierfinale sollte der Host neutral sein oder rotieren.
- Determinismus bleibt trotzdem Architekturziel (`03_TECH` §3) — für Replays, Tests und Vorhersage, nicht für Synchronisation.

**Verworfen:**
- *Lockstep mit Float:* Desync-Risiko, siehe oben.
- *Lockstep mit Fixed-Point:* Aufwand und Spielgefühl-Risiko unverhältnismäßig.
- *Rollback/GGPO:* Bringt die Determinismus-Anforderung durch die Hintertür zurück, Aufwand um ein Vielfaches höher, Nutzen bei LAN-Latenz nicht wahrnehmbar.
- *Dedizierter Server:* Ein Rechner mehr auf der Party, den jemand aufsetzen muss. Widerspricht Zero-Config.

---

## ADR-003 — ENet für das Spiel, LuaSocket-UDP für Discovery

**Status:** angenommen · 2026-08-11

**Kontext:** LÖVE liefert zwei Netzwerkbibliotheken mit. <cite index="23-1">LÖVE bringt luasocket und lua-enet mit; ersteres bindet OS-Sockets an, letzteres ist ein Aufsatz über UDP.</cite>

**Entscheidung:** ENet für Lobby, Match und Turnier. LuaSocket-UDP ausschließlich für Broadcast-Discovery.

**Begründung:**
- <cite index="21-1">ENet stellt optional zuverlässige, geordnete Zustellung über UDP bereit</cite> — genau die Mischung, die hier gebraucht wird: reliable für Lobby und Turnier, unreliable für Snapshots. Selbstgebaute Zuverlässigkeit auf rohem UDP wäre unnötige Eigenentwicklung.
- <cite index="21-1">ENet lässt höhere Funktionen wie Server-Discovery bewusst weg, damit die Bibliothek flexibel und portabel bleibt</cite> — Broadcast gehört nicht zum Funktionsumfang. Deshalb der zweite Socket.
- LuaSocket blockierend zu benutzen wäre fatal: <cite index="26-1">Blockierende Operationen halten die gesamte LÖVE-Hauptschleife an, was in der Regel eine schlechte Idee ist; empfohlen sind nicht-blockierende Operationen oder ein eigener Thread.</cite>

**Konsequenzen:**
- Discovery-Socket zwingend mit `settimeout(0)`, gepollt in `love.update`. Kein Thread nötig.
- ENet-Ereignisschleife muss pro Frame vollständig geleert werden.
- ENet-Peer-Timeout auf 5000 ms statt Default (LAN-tauglich).

---

## ADR-004 — Logisches Spielfeld ist fix 800×600

**Status:** angenommen · 2026-08-11 · **korrigiert Prototypverhalten**

**Kontext:** Der Prototyp berechnet `WORLD.width` aus der Fensterbreite (`winW / scale`). Feldbreite, Wandpositionen, Aufschlagpositionen und Bot-Grenzen hängen damit vom Fenster ab.

**Entscheidung:** Das logische Feld ist konstant 800×600. Fensteranpassung erfolgt ausschließlich als Render-Transformation mit Letterbox/Pillarbox.

**Begründung:**
- **Fairness:** Zwei Spieler mit unterschiedlichem Fenster spielen sonst unterschiedliche Spiele. Auf einem 21:9-Monitor ist das Feld deutlich breiter — der Ball braucht länger von Wand zu Wand, die Deckung ist schwerer.
- **Netzwerk:** Snapshot-Koordinaten wären ohne fixes Feld bedeutungslos.
- **Vanilla-Treue:** Die Seitenwände sind im Original ein taktisches Element. <cite index="53-1">Die Bildschirmränder wirken als unsichtbare Wand, deren Nutzung ausdrücklich legal ist.</cite> Ihre Position ist damit Spielinhalt und darf nicht vom Fenster abhängen.

**Konsequenzen:** Schwarze Balken auf Breitbildschirmen. Alternativ ein dekorativer Hintergrund, der über die Feldgrenze hinausreicht — die Feldgrenze bleibt aber sichtbar markiert.

---

## ADR-005 — Trennung von Ruleset und Prefs

**Status:** angenommen · 2026-08-11

**Kontext:** Der Prototyp hält Simulationsparameter und lokale Präferenzen in einer globalen, zur Laufzeit über den Live-Tweaker veränderlichen Tabelle.

**Entscheidung:** Zwei getrennte Container. `Ruleset` ist simulationsrelevant, vom Host verteilt, kanonisch gehasht und während eines Matches unveränderlich. `Prefs` ist rein lokal.

**Begründung:** Ohne die Trennung könnte jeder Client seine Physik verändern, und der Ruleset-Abgleich beim Match-Start wäre nicht definierbar. Der Live-Tweaker bleibt trotzdem erhalten — er ist ein wertvolles Balancing-Werkzeug und wirkt offline sowie host-seitig in der Lobby.

**Konsequenzen:** Kanonische Serialisierung (Schlüssel sortiert, Zahlen mit fester Formatierung) ist Pflicht, sonst liefern identische Rulesets unterschiedliche Hashes.

---

## ADR-006 — Vanilla ist ohne Dash und ohne Smash

**Status:** angenommen · 2026-08-11 · **korrigiert Prototypverhalten**

**Kontext:** Der Prototyp hat `activeSpike = true` als Voreinstellung und Dash immer aktiv. Das GDD bezeichnet beide als optionale Mutatoren.

**Entscheidung:** Preset `classic` hat Dash und Smash aus. Voreinstellung beim Start ist `classic`.

**Begründung:** Im Original steuern Spieler <cite index="42-1">ihre Blobs ausschließlich über links, rechts und springen, ohne direkte Ballmanipulation — Treffer entstehen allein aus Positionierung und Timing.</cite> Ein Spiel, das sich „Vanilla" nennt und eine vierte Angriffstaste hat, ist kein Vanilla. Dash und Smash bleiben als Mutatoren erhalten und sind im namensgebenden Preset `volley_dash` an, das gleichrangig neben `classic` zur Wahl steht (ADR-010, GDD §5.1).

**Konsequenzen:** Wer den Prototyp kennt, wird die Standardeinstellung zunächst als „kaputt" empfinden. Das Preset `volley_dash` steht in der Lobby gleichberechtigt daneben.

---

## ADR-007 — Turnierzustand ist append-only Log + abgeleiteter Zustand

**Status:** angenommen · 2026-08-11

**Kontext:** Der Turnier-Host ist ein Spieler-Laptop und kann jederzeit abstürzen (Risiko R-07).

**Entscheidung:** Wahrheit ist ein append-only Ereignis-Log. `matches` und `standings` sind daraus ableitbar. Nach jedem Ereignis wird atomar auf Platte geschrieben (tmp → bak → rename).

**Begründung:** Ein Turniersystem, das einen Absturz nicht übersteht, ist schlechter als ein Zettel. Das Log ist zusätzlich die Grundlage für Nachvollziehbarkeit bei manuellen Korrekturen und für den Export.

**Konsequenzen:** Etwas mehr Code als direkte Zustandsmutation. Dafür ist Recovery, Export und Audit nahezu kostenlos.

---

## ADR-008 — Keine automatische Beamer-Regie in v1.0

**Status:** angenommen · 2026-08-11 · **entfernt eine Vorgabe des Ausgangs-GDD**

**Kontext:** Das Ausgangs-GDD forderte, die Beamer-Regie schalte automatisch „zum spannendsten Match im Netzwerk".

**Entscheidung:** Der Beamer-Client zeigt das Bracket plus ein manuell gewähltes Match. Automatische Regie ist M6.

**Begründung:** Automatische Regie braucht paralleles Beobachten aller Matches, eine Spannungs-Heuristik und Umschaltlogik mit Hysterese. Bei bis zu 4 parallelen Matches macht ein Mensch das besser und in einer Sekunde. Der Aufwand steht in keinem Verhältnis.

**Revisionsauslöser:** Sobald regelmäßig mehr als 4 Matches parallel laufen, wird die Entscheidung neu bewertet.

---

## ADR-009 — Eigene Build-Skripte statt Community-Werkzeug

**Status:** angenommen · 2026-08-11

**Kontext:** Das LÖVE-Wiki listet mehrere Distributionswerkzeuge, u. a. <cite index="30-1">makelove, boon, love-export und love-build</cite>.

**Entscheidung:** Eigenes Shell-Skript (~40 Zeilen). Optional später LÖVE Actions als CI-Wrapper.

**Begründung:** Der Vorgang ist trivial — <cite index="38-1">unter macOS/Linux genügt `cat love.exe SuperGame.love > SuperGame.exe` für Windows</cite>, und der macOS-Build ist Kopieren plus Info.plist-Anpassung. Es gibt einen projektspezifischen Schritt (Build-Hash-Injektion für den Netzwerk-Versionsabgleich), den kein Werkzeug kennt. Ein Skript, das man vollständig versteht, ist bei jährlicher Nutzungsfrequenz robuster als eine Fremdabhängigkeit.

---

## ADR-010 — Projektname ist „Volley Dash"

**Status:** angenommen · 2026-08-11 · **löst Q-01**

**Kontext:** Arbeitstitel war „Blobby LAN". Das Original ist eine bekannte Marke; Blobby Volley 2 steht unter GPLv2. Mit der Open-Source-Veröffentlichung (ADR-011) wird ein eigener Name unumgänglich.

**Entscheidung:** Das Projekt heißt **Volley Dash**. Bundle-Identifier `games.4brain.volleydash`, Repository `volley-dash`, Discovery-Magic `VLYD`.

**Begründung:**
- Kein Bezug zu „Blobby" im Titel — die Eigenständigkeit ist damit auch nach außen sichtbar.
- Eine Recherche über die gängigen Indie-Plattformen zeigt keinen etablierten gleichnamigen Titel. Benachbarte Namen existieren („Volley Pals", „Volley Boys", „Volley Bubble"), aber keine Kollision. *Das ersetzt keine markenrechtliche Prüfung; für ein kostenloses Open-Source-Projekt ist eine anwaltliche Recherche unverhältnismäßig.*
- Kurz, aussprechbar, im Deutschen wie im Englischen tragfähig — relevant für ein öffentliches Repository.

**Konsequenz und Spannung:** Der Name verweist auf den Dash — laut ADR-006 ein Mutator, der im `classic`-Preset **aus** ist. Aufgelöst über zwei gleichwertige Start-Presets `Classic` und `Volley Dash` (GDD §5.1), statt Dash in Vanilla aufzunehmen oder den Namen zu ändern.

**Verworfen:** *NETZKANTE* (nur im deutschen Sprachraum tragfähig, für ein GitHub-Projekt hinderlich). *Dash ins Vanilla-Preset aufnehmen* (verletzt ADR-006 und die Vanilla-Doktrin).

---

## ADR-011 — Veröffentlichung als Open Source auf GitHub unter zlib

**Status:** angenommen · 2026-08-11 · **löst Q-04**

**Kontext:** Alternativen waren privat, itch.io oder kommerziell.

**Entscheidung:** Öffentliches GitHub-Repository, Lizenz **zlib**, Binaries über GitHub Releases.

**Begründung:**
- Der Wert des Projekts liegt nicht im Gameplay (25 Jahre alt, kostenlos verfügbar), sondern in Zero-Config-LAN-Discovery, host-autoritativem Netcode in LÖVE und einem absturzfesten integrierten Turniersystem. Genau das ist für andere nachnutzbar.
- zlib ist die Lizenz von LÖVE selbst — konsistent, permissiv, ohne Copyleft-Pflichten für Nutzer. Zugleich eine sichtbare Abgrenzung zur GPLv2 von Blobby Volley 2, die unterstreicht, dass von dort kein Code stammt.
- Kommerziell scheidet aus: gegen ein etabliertes kostenloses Original zu verkaufen, funktioniert nicht.

**Konsequenzen — die drei, die wirklich Arbeit machen:**
1. **Asset-Herkunft wird blockierend.** Unklar lizenzierte Grafiken und Sounds im Repo sind privat egal, öffentlich nicht. Siehe `10_LEGAL` §4; Empfehlung ist der prozedurale Fallback als Standard.
2. **Zwei README-Dateien.** Das öffentliche README ist ein anderes Dokument als der interne Index dieses Doc-Sets.
3. **Releases brauchen Reproduzierbarkeit.** Ein Build, den nur dein Mac erzeugen kann, ist für ein Open-Source-Projekt zu wenig. Deshalb GitHub Actions ab M1 (`12_OPENSOURCE_REPO_SETUP` §5).

**Bewusst nicht enthalten:** Keine Zusage auf Issue-Bearbeitung, keine Roadmap-Verpflichtung nach außen, keine Beitragspflicht. Das Repo ist offen, nicht betreut. Das steht so im öffentlichen README — sonst entsteht eine Erwartung, die nebenberuflich nicht einlösbar ist.

---

## ADR-012 — Kein Apple Developer Program, aber verpflichtende Ad-hoc-Signatur

**Status:** angenommen · 2026-08-11 · **löst Q-02**

**Kontext:** macOS ist Zielplattform. Developer ID und Notarisierung kosten 99 USD/Jahr.

**Entscheidung:** Kein Apple Developer Program. Stattdessen **verpflichtende Ad-hoc-Signatur** der gebauten `.app` im Build-Skript.

**Begründung:**
- 99 USD/Jahr für ein kostenloses Open-Source-LAN-Spiel steht in keinem Verhältnis.
- Die Ad-hoc-Signatur ist dabei keine Sparvariante, sondern technisch **notwendig**: Der Plist-Patch im Build zerstört die vorhandene Signatur der `love.app`, und <cite index="88-1">Code, der auf Apple-Silicon-Macs nativ läuft, muss signiert sein; nach dem Entfernen oder Beschädigen einer Signatur ist erneutes Signieren nötig, notfalls ad hoc.</cite> Ohne diesen Schritt startet die App auf Apple Silicon nicht — kein Warnhinweis, sondern Fehlstart.
- <cite index="92-1">Ad-hoc-Signierung ist das kostenlose Minimum</cite>, verlangt aber weiterhin, dass die App auf einem fremden Rechner einmal per Rechtsklick geöffnet wird.

**Konsequenzen:** Der Rechtsklick-Weg gehört gut sichtbar ins öffentliche README, ins `LIESMICH.txt` und auf die Beamer-Folie am Partyabend. Zusätzlich der `xattr`-Einzeiler als Notfalloption, mit Erklärung, was er tut.

**Revisionsauslöser:** Häufen sich nach dem ersten öffentlichen Release Rückmeldungen „Mac-Version startet nicht", wird neu entschieden.

---

## ADR-013 — Turnier-Auslegungspunkt 20 Teilnehmer; parallele Matches auf den kritischen Pfad

**Status:** angenommen · 2026-08-11 · **löst Q-03**

**Kontext:** Zielgröße ist variabel, zunächst relevant sind etwa 20 Teilnehmer.

**Entscheidung:** Das System unterstützt 4–32 Teilnehmer und wird gegen **20** ausgelegt und getestet. Standardformat bei 20: **4 Gruppen à 5 (Round Robin) → 8er Single Elimination.** Parallele Matches mit verteilten Match-Hosts (M4-09) rücken vom Ausbau auf den kritischen Pfad von M4.

**Begründung:**
- Ein 20er-Turnier umfasst rund 48 Matches. Seriell abgespielt sind das etwa 3,5 Stunden — deutlich mehr, als ein Partyabend trägt. Bei 4 parallelen Matches sind es rund 90 Minuten.
- Reines Single Elim mit 20 Spielern (32er-Bracket, 12 Freilose) schickt die Hälfte des Feldes nach einem einzigen Match nach Hause. Die Gruppenphase garantiert jedem vier Matches und liefert nebenbei die Setzliste fürs K.o.
- Die Gruppenaufteilung wird automatisch aus der Teilnehmerzahl abgeleitet (Ziel 4–5 pro Gruppe), weil „variabel" in der Praxis heißt: am Abend stehen 17 oder 23 Leute da, und niemand will rechnen.

**Konsequenzen:**
- M4 wird um geschätzt 4–6 h teurer, weil verteilte Match-Hosts nicht mehr entfallen können.
- Der Scheduler muss mit **weniger** parallelen Matches als konfiguriert umgehen können, ohne zu blockieren (geteilte Hardware).
- ADR-008 (keine automatische Beamer-Regie) nähert sich seinem Revisionsauslöser. Bleibt für v1.0 bestehen, wird nach dem ersten 20er-Turnier bewertet.
- Das Chaos-Szenario im Testplan (D3) wird von 8 auf 20 simulierte Teilnehmer erweitert.

---

## ADR-014 — Kanonisches `InputFrame`-Format

**Status:** angenommen · 2026-08-11 · **festgeschrieben in CC-01 (M0-03), AP-3**

**Kontext:** B-03 verlangt, dass die Simulation ausschließlich `InputFrame` konsumiert. Vor der Referenzaufzeichnung des Prototyps muss feststehen, wie dieses Format aussieht — sonst zeichnet M0-03 Rohtasten auf, und der Regressionstest der Ebene A prüft danach die Übersetzungsschicht Tastatur→InputFrame statt der Physik. Das Format wird zusätzlich von `04_NETCODE_SPEC` (Übertragung), `05_TOURNAMENT_SPEC` (Bot-Übernahme) und `07_TEST_PLAN` §2 (Wiedergabe) benutzt.

**Entscheidung:** Ein `InputFrame` ist **ein vorzeichenloses Byte pro Spieler pro Tick** mit der Bitmaske `left=1, right=2, jump=4, smash=8, dash=16`; Bits 5–7 sind reserviert und müssen 0 sein. Details in `13_INPUTFRAME_FORMAT.md`.

**Begründung:**
- Ein Byte ist die kleinste Darstellung, die alle fünf Signale trägt, ist über `love.data.pack("<B", …)` plattformunabhängig und braucht bei 60 Hz nur 120 B/s je Richtung für beide Spieler.
- Bits 0–3 sind **Zustände** (lag im Tick an), die Flankenerkennung liegt in der Simulation. Nur so kann die Simulation entscheiden, ob ein Sprung zulässig ist — die Quelle weiß nicht, ob der Blob am Boden steht.
- Bit 4 (`dash`) ist die bewusste Ausnahme: ein **abgeleiteter Impuls**. Die Doppeltipp-Erkennung sitzt in der Eingabequelle, nicht in der Simulation. Sonst müsste die Simulation Tipp-Historien pro Spieler führen, der Bot müsste Tastendrücke simulieren, und das Netzwerk müsste Tastenfolgen statt Absichten übertragen.
- Die Richtung des Dash kommt aus den gleichzeitig gesetzten Richtungsbits, nicht aus einem eigenen Feld. Das spart Zustand und macht widersprüchliche Frames unmöglich.
- **Bei gleichzeitig `left` und `right` gewinnt `left`.** Das ist das gemessene Verhalten des Prototyps (`main.lua:585` und `main.lua:635`, `and/or`-Kette mit Linksauswertung), nicht eine Setzung. Die Referenz-Rallyes halten das jetzige Verhalten fest; eine Änderung an dieser Stelle würde die Aufzeichnung entwerten.

**Konsequenzen:**
- Der Regressionstest der Ebene A prüft die Physik, **nicht** die Doppeltipp-Erkennung. Die braucht einen eigenen Unit-Test in M0-06; die Mindestfälle stehen in `13_INPUTFRAME_FORMAT.md` §4.
- Analoge Gamepad-Achsen werden in der Quelle über eine Schwelle aus `Prefs` diskretisiert. Die Simulation kennt keine halben Eingaben.
- Die Doppeltipp-Erkennung des Prototyps misst in Echtzeit (`love.timer.getTime()`), ab M0-06 zählt sie in Ticks. Das ist eine bewusste Verhaltensänderung und in M0-06 gegen R-09 zu prüfen.
- Empfänger verwerfen Frames mit gesetzten reservierten Bits, statt sie zu maskieren. Damit fällt ein Protokollversionsfehler sofort auf.

**Verworfen:**
- *Struktur mit Klarnamen statt Bitmaske:* teurer im Netzwerk und im Replay, und ohne kanonische Feldreihenfolge nicht stabil hashbar.
- *Rohtasten übertragen und die Doppeltipp-Erkennung in der Simulation:* macht den Bot zum Tastatur-Simulator und die Simulation zustandsbehaftet über Ticks hinweg.
- *Eigenes Richtungsfeld für den Dash:* erzeugt widersprüchliche Kombinationen (Dash nach links bei gedrücktem Rechts), die validiert werden müssten.
- *„Beide Richtungen ergibt Stillstand":* Vorschlag aus dem Handoff CC-01, entspricht aber nicht dem Prototyp. Abgelehnt zugunsten des gemessenen Verhaltens.
- *16-Bit-Frame mit Reserve:* verdoppelt die Netzlast für Bits, für die es keinen Anwendungsfall gibt. Drei reservierte Bits reichen bis v1.0.

**Revisionsauslöser:** Wenn ein Modus aus M6 (2v2, Mutatoren) mehr als drei zusätzliche Signale braucht, wird auf 16 Bit erweitert — dann mit Protokollversionssprung, nicht durch Umdeutung der reservierten Bits.

---

## Vorlage für neue ADRs

```markdown
## ADR-0XX — [Titel]
**Status:** vorgeschlagen | angenommen | ersetzt durch ADR-0YY · [Datum]
**Kontext:** [Was ist die Situation, welche Kräfte wirken]
**Entscheidung:** [Was wird getan — im Aktiv, ein Satz]
**Begründung:** [Warum diese und nicht die Alternative]
**Konsequenzen:** [Was wird dadurch leichter, was schwerer]
**Verworfen:** [Alternativen mit je einem Satz Ablehnungsgrund]
**Revisionsauslöser:** [Woran erkennt man, dass die Entscheidung neu bewertet gehört]
```
