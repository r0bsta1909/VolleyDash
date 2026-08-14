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

## ADR-015 — Der `fixed60`-Referenzsatz entsteht durch Wiedergabe, nicht durch erneutes Spielen

**Status:** angenommen · 2026-08-11 · **erweitert ADR-014**

**Kontext:** `07_TEST_PLAN` §2 verlangt jede Referenz-Rallye zweimal: einmal mit dem variablen Schritt des Prototyps, einmal mit konstant 1/60 s. Der erste Durchgang ist von Hand gespielt und liegt vor. Der zweite von Hand nachzuspielen kostet erneut zwei Stunden, liefert aber zwangsläufig **andere** Ballwechsel — zwei Sätze, die weder untereinander noch gegen die spätere Simulation vergleichbar sind.

**Entscheidung:** Der `fixed60`-Satz entsteht, indem die aufgezeichneten `InputFrames` des gespielten Durchgangs mit festem Schritt erneut durch den Prototyp gefahren und mitgeschnitten werden (`tools/replay_source.lua`, `--replay-all`). Wo die Wiedergabe das geprüfte Phänomen verfehlt, tritt eine **Skriptszene** an ihre Stelle: synthetischer Startzustand, fester Eingabeplan, Parameter gemessen statt geraten (`--scene-probe`).

**Begründung:**
- Die Wiedergabe ist genau die Quelle, die B-03 und ADR-014 vorsehen. Sie ändert **nichts** an der Physik: im Shim werden `love.keyboard.isDown` und `Bot.updateAI` umgelenkt, sonst nichts. Der Beweis dafür ist maschinell — die `in`-Spalte der erzeugten Datei ist Tick für Tick identisch mit der Quelle.
- Der gespielte Durchgang lief bei einem Median-`dt` von 0,01670 s, also faktisch schon 1/60 mit VSync-Jitter. Dieselben Eingaben bei exakt 1/60 erzeugen daher überwiegend denselben Ballwechsel.
- Eine Referenz ist erst dann eine Referenz, wenn sie das Phänomen enthält, das sie absichert. Das ist prüfbar (`tools/verify_replays.py`) und wurde geprüft: 11 von 11.
- Vier Rallyes brauchten eine Szene, weil die Abweichung zwischen den Schrittweiten die Situation zerstört, für die sie existieren. Eine Szene ist weiterhin ein echter Lauf der Prototyp-Physik; nur der Anfangszustand wird gesetzt statt gespielt. Für R-11 gibt es gar keine Alternative: der Deckel `maxBallSpeed` wurde auch im gespielten Lauf nie erreicht.

**Konsequenzen:**
- Der Header jeder Aufzeichnung führt `driver` (`human`, `replay:…`, `scripted:…`). Das Manifest spiegelt das. Niemand muss raten, wie eine Referenz entstanden ist.
- Der `fixed60`-Satz ist reproduzierbar: `--replay-all`, dann die vier Szenen. Der gespielte Satz ist es nicht — er bleibt deshalb im Repo (Entscheidung r0btoshi, 2026-08-11).
- Wiedergegebene Rallyes laufen nach dem Ende der aufgezeichneten Eingaben mit Nulleingabe weiter, bis der Ballwechsel entschieden ist. Ohne Ausgang lässt sich die Bewertungstabelle aus `07_TEST_PLAN` §2 nicht anwenden.
- `tools/replay_source.lua` und `tools/verify_replays.py` sind Vorarbeit für M0-13: die Wiedergabe wird dort zum Testtreiber gegen `sim.step()`.

**Verworfen:**
- *Elf Rallyes ein zweites Mal spielen:* teuer, nicht reproduzierbar, und die beiden Sätze wären inhaltlich verschieden.
- *Nur Skriptszenen:* würde das gespielte Material wegwerfen. Sieben der elf Rallyes überstehen die Wiedergabe unverändert.
- *Den variablen Satz zur alleinigen Referenz erklären:* verschiebt das Problem nur; nach M0-05 rechnet die Simulation mit festem Schritt und braucht eine Referenz mit festem Schritt.

**Revisionsauslöser:** Wenn nach M0-08 mehr als zwei Rallyes nur noch über Szenen zu halten sind, ist nicht die Methode falsch, sondern die Rallye-Auswahl aus `07_TEST_PLAN` §2 zu eng an einzelnen Spielsituationen gebaut.

---

## ADR-016 — Das Protokoll überträgt den vorhandenen djb2-Hash und das Ruleset binär, kein MD5 und kein JSON

**Status:** angenommen · 2026-08-12 · **Bezug:** ADR-003, ADR-005, M0-09, M2-01

**Kontext:** `04_NETCODE_SPEC` 1.0 wurde geschrieben, bevor `src/sim/ruleset.lua` existierte. Sie verlangte an zwei Stellen etwas, das der gebaute Code nicht liefert und nach den Invarianten aus `CLAUDE.md` §4 auch nicht liefern kann:

1. §5 und §10 forderten `rulesetHash` als **MD5 über die kanonische Form**, 16 Byte. Gebaut ist djb2 mit acht Hexstellen (`Ruleset.hash`). Das ist kein Versehen: `love.data.hash` hätte `love` unterhalb von `src/sim/` gebracht, und damit wären die Testebenen A und B nicht mehr headless lauffähig — die in `CLAUDE.md` §7 ausdrücklich protokollierte Ausnahme aus M0-09.
2. §5 übertrug `RULESET_FULL` (0x12) als **JSON**. `12_OPENSOURCE` §3 führte dafür `src/lib/json.lua` (MIT) als Fremdkomponente. Diese Datei existiert nicht, und seit M1-08 hält `LICENSE-THIRD-PARTY.md` fest, dass das Projekt ohne Fremdbibliothek auskommt.

**Entscheidung:** Das Protokoll überträgt `rulesetHash` als **acht ASCII-Hexstellen** aus `Ruleset.hash` und das vollständige Ruleset als **selbstbeschreibende Schlüssel-Wert-Folge** über `love.data.pack` (`s1` Name, `u1` Typkennung, `d` bzw. `u1` Wert). Kein MD5, kein JSON, keine Fremdbibliothek.

**Begründung:**
- Der Hash hat genau eine Aufgabe: **abweichende Rulesets erkennen**. Er sichert nichts ab — im LAN gibt es kein Angreifermodell, das er abwehren könnte, und wer die `.love` verändern kann, verändert auch den Vergleich. Für die Erkennung reicht djb2. Die `love`-Freiheit der Simulation ist die deutlich teurere Eigenschaft.
- Zwei Hashes über dieselbe Sache wären der schlechteste Ausgang: `Ruleset.hash` würde für die Tests bleiben und MD5 für das Netz dazukommen. Beim ersten Auseinanderlaufen wäre nicht mehr entscheidbar, welcher recht hat.
- Das Ruleset ist eine **flache Tabelle aus 24 Zahlen und 4 Wahrheitswerten**. JSON löst hier ein Problem, das es nicht gibt, und kostet die erste Fremdabhängigkeit des Projekts.
- **Zahlen gehen als `d` (float64), nicht als `f`.** Die kanonische Form formatiert mit `%.17g`; ein Umweg über float32 würde die Zahl verändern und damit den Hash der empfangenen Kopie vom gesendeten Hash abweichen lassen. Der Abgleich aus §10 schlüge dann grundlos fehl.
- **Selbstbeschreibend statt festes Layout:** Ein festes Feldlayout müsste bei jeder Ruleset-Änderung in `protocol.lua` mitgezogen werden — und ein vergessener Nachzug fällt erst am Partyabend auf, als stiller Zahlendreher. Die Namen kosten rund 200 Byte, einmal je Match, auf dem zuverlässigen Kanal 0. Unbekannte Schlüssel werden verworfen; die Abweichung erscheint dann als Hash-Fehler mit Klartext, nicht als Absturz.

**Konsequenzen:**
- `04_NETCODE_SPEC` §5 führt `rulesetHash(8)`, §10 nennt djb2 statt MD5. Beide Stellen sind mit M2-01 berichtigt.
- Das Nachrichtenfeld ist eine Zeichenkette, kein Zahlenwert. Wer es vergleicht, vergleicht Zeichenketten.
- `12_OPENSOURCE` §3 verliert den Eintrag `src/lib/json.lua`. Das Projekt bleibt fremdbibliotheksfrei.
- **Für M4 offen:** `TOURNAMENT_STATE` (0x40) ist in `05_TOURNAMENT` als JSON spezifiziert und trägt verschachtelte Daten. Dieser ADR entscheidet darüber **nicht**. Wenn M4 JSON braucht, ist das eine eigene Entscheidung mit eigenem ADR — und dann für genau diese eine Nachricht.
- Der Desync-Detektor (§9) rechnet weiter mit `love.data.hash("md5", …)`. Er sitzt in `src/net/`, nicht in `src/sim/`, und darf `love` benutzen.

**Verworfen:**
- *`love.data.hash` in `src/sim/ruleset.lua`:* bricht die `love`-Freiheit der Simulation und damit die Testebenen A und B. Der teuerste denkbare Weg für den geringsten Gewinn.
- *MD5 zusätzlich im Netzcode über dieselbe kanonische Form:* zwei Wahrheiten für eine Frage.
- *`json.lua` aufnehmen:* braucht ADR, Eintrag in `LICENSE-THIRD-PARTY.md` und Pflege — für eine flache Tabelle aus 28 Werten.
- *Festes Feldlayout ohne Namen:* spart 200 Byte einmal je Match und erkauft das mit einer Datei, die bei jeder Ruleset-Änderung stillschweigend falsch wird.

**Revisionsauslöser:** Wenn zwei verschiedene Rulesets denselben djb2-Hash liefern (Kollision im echten Betrieb) oder wenn `Ruleset` verschachtelte Werte bekommt — dann ist nicht die Serialisierung falsch, sondern die Annahme „flache Tabelle".

---

## ADR-017 — Die Vorhersage ruft die Simulation auf und gleicht gegen `ackInputTick` ab, nicht gegen die Gegenwart

**Status:** angenommen · 2026-08-12 · **Bezug:** ADR-002, ADR-014, M3-01, `04_NETCODE_SPEC` §8

**Kontext:** Der Gast soll seinen eigenen Blob sofort bewegen sehen. `04_NETCODE_SPEC` §8 legt fest, *was* vorhergesagt wird (nur der eigene Blob) und *wie* korrigiert wird (> 2 px über vier Ticks). Offen war, *wo* das rechnet und *womit* verglichen wird. Beim Bauen zeigten sich drei Fragen, die die Spec nicht beantwortet:

1. Die beiden Schritte, die den Blob bewegen — `updateBlobTimers` und `applyImpulses` — sind in `src/sim/step.lua` **lokal**. Aufrufbar sind sie nicht. Handoff CC-04 verlangt aber ausdrücklich, sie aufzurufen statt sie zu kopieren.
2. Der Snapshot, gegen den verglichen wird, beschreibt einen Zustand aus der **Vergangenheit** (RTT/2 plus zwei Ticks Puffer). Ein Vergleich mit der aktuellen Vorhersage findet bei jedem Lauf einen Fehler von rund 30 px, obwohl nichts falsch ist — die Korrektur liefe dauernd und der Blob gummibandelte.
3. Eine Korrektur, die die Simulationsposition langsam verschiebt, verfälscht die Grundlage der nächsten vier Ticks.

**Entscheidung:** Die Vorhersage liegt in `src/net/prediction.lua`, ist `love`-frei und ruft `Step.applyImpulses`, `Step.updateBlobTimers` und `Physics.updateBlob` auf. `src/sim/step.lua` macht die beiden lokalen Funktionen dafür sichtbar — zwei Zuweisungen, keine Zeile Logik. Verglichen wird die **gespeicherte Vorhersage zum Eingabetick `ackInputTick`** aus dem Snapshot, nicht die aktuelle. Die Abweichung wird sofort auf die Simulationsposition addiert und als **Sichtversatz** über vier Ticks abgebaut.

**Begründung:**
- **Aufrufen statt kopieren:** Sechs Zeilen Blob-Bewegung in `prediction.lua` wären eine zweite Wahrheit über das Spielgefühl. Sie würde beim ersten Eingriff in `02_CODE_AUDIT` §4 auseinanderlaufen, und zwar still — die Vorhersage driftet dann systematisch gegen den Host, und das sieht aus wie ein Netzproblem. Die zwei Exportzeilen ändern kein Verhalten und keinen Zahlenwert; sie machen sichtbar, was ohnehin schon da ist.
- **`ackInputTick` ist genau dafür im Snapshot** (§6): Er sagt, welchen Eingabetick des Gastes der Host in diesem Snapshot verarbeitet hat. Damit ist der Vergleich zeitrichtig, und die gemessene Abweichung ist ein echter Vorhersagefehler statt Laufzeit.
- **Steht `ackInputTick` still** — der Host hat die letzte Maske wiederholt, weil ein Paket fehlte (§7) —, wird gar nicht verglichen. Ein Vergleich gegen einen Tick, den der Host mit fremder Eingabe gerechnet hat, meldet einen Fehler, den niemand gemacht hat.
- **Sichtversatz statt schleichender Position:** Die Simulationsposition springt sofort auf die Wahrheit des Hosts, gezeichnet wird sie plus einem Versatz, der in vier Ticks auf null geht. Damit ist die Grundlage der nächsten Ticks jederzeit korrekt und das Bild trotzdem sprungfrei. Der umgekehrte Weg — die Position langsam verschieben — rechnet vier Ticks lang mit einer Zahl, von der man bereits weiß, dass sie falsch ist.
- **Kein Rollback.** Es wird nichts neu simuliert, nichts zurückgespult und kein alter Zustand gehalten. Die Blob-Bewegung ist positionslinear: ein Positionsfehler ändert die künftige Geschwindigkeit nicht. ADR-002 bleibt unberührt.
- **Ein Punktgewinn ist keine Vorhersagefehler.** `Rules.resetBall` setzt beide Blobs auf die Aufschlagposition — ein Sprung, den der Gast nicht vorhersagen kann und nicht weich nachfahren soll. Solche Übernahmen sind hart und zählen nicht in den Korrekturzähler, sonst zeigte das F3-Overlay nach zehn Punkten zehn „Fehler", die keine sind.

**Konsequenzen:**
- `src/sim/step.lua` bekommt zwei Exportzeilen. Das ist die einzige Änderung unterhalb von `src/sim/` in M3 und ändert kein Verhalten.
- Die Vorhersage läuft **nur beim Gast**. Der Host simuliert autoritativ; für ihn ist das Modul tot.
- `prediction.lua` hält einen Ringpuffer von 64 vorhergesagten Positionen (gut eine Sekunde). Reicht der nicht mehr, ist die Verbindung ohnehin unspielbar.
- Der Korrekturzähler im F3-Overlay misst ab jetzt **echte** Vorhersagefehler: verlorene Eingabepakete und den einen Tick, in dem ein abgelaufener Fehlerwurf die Blob-Bewegung überspringt.

**Verworfen:**
- *Blob-Bewegung in `prediction.lua` nachbauen:* zweite Wahrheit über die Zahlen aus `02_CODE_AUDIT` §4.
- *`Step.tick` für den eigenen Blob mitlaufen lassen:* rechnet Ball, Netz und Gegner mit, die der Gast nicht kennt — und wäre damit die Ball-Vorhersage durch die Hintertür, vor der Handoff CC-04 §4 warnt.
- *Vergleich gegen die aktuelle Vorhersage:* meldet Laufzeit als Fehler und korrigiert dauerhaft gegen eine Vergangenheit.
- *Harter Sprung auf die Host-Position:* genau das, was §8 ausschließt.

**Revisionsauslöser:** Wenn der Korrekturzähler im LAN über null bleibt, obwohl kein Paket verloren geht. Dann stimmt entweder die Zuordnung über `ackInputTick` nicht oder die Vorhersage rechnet doch nicht dieselbe Physik.

---

## ADR-018 — Der Desync-Detektor prüft die gepackten Snapshot-Bytes mit djb2, nicht den Zustand mit MD5

**Status:** angenommen · 2026-08-12 · **ändert eine Konsequenz von ADR-016** · **Bezug:** M3-03, B-N-07, `04_NETCODE_SPEC` §9

**Kontext:** §9 verlangt eine Prüfsumme alle 30 Ticks über den Simulationszustand, `love.data.hash("md5", packedState)`, erste 4 Byte — und dass der Client sie „mit seiner vorhergesagten eigenen Blob-Position vergleicht". Das ist so nicht ausführbar: Der Client kennt den Simulationszustand des Hosts nicht, er kennt nur den Snapshot. Und eine Prüfsumme über Werte, die der Client selbst gar nicht bilden kann, meldet entweder immer oder nie einen Fehler.

Dazu kommt ein gemessener Fallstrick aus M2: Der Host hält seine Zahlen als float64, über die Leitung gehen float32 (§6). Eine Prüfsumme über die **Zahlen** vergleicht damit zwei verschiedene Werte und schlägt in jedem Tick an, in dem irgendetwas in Bewegung ist. Dasselbe gilt für jede Formatierung mit fester Stellenzahl: `%.3f` kippt, sobald der float32-Rundungsfehler eine Rundungsgrenze überschreitet — selten genug, um im Test nicht aufzufallen, und häufig genug, um am Partyabend alle halbe Stunde einen Fehlalarm zu erzeugen.

**Entscheidung:** Der Host rechnet **djb2 über die gepackten Bytes des Snapshots**, den er diesem Gast gerade geschickt hat. Der Client packt den empfangenen Snapshot mit seinem eigenen Code erneut und rechnet dieselbe Prüfsumme. Vorhersagefehler misst der Detektor **nicht** — dafür gibt es den Korrekturzähler aus ADR-017.

**Begründung:**
- **Fehlalarme sind bauartbedingt ausgeschlossen.** Der Weg float32 → double → float32 ist verlustfrei; dieselben Felder ergeben dieselben Bytes. Kein Rundungsfenster, keine Rundungsgrenze, kein Vorzeichen der Null (B-N-07, §6) — die Begradigung ist bereits vor dem Packen passiert. Ein Detektor, der zweimal grundlos anschlägt, wird ab dem dritten Mal ignoriert, und dann ist er schlechter als keiner.
- **Was er findet, ist genau das, was §9 aufzählt:** falsch interpretierte Snapshots, Endianness, abweichende Feldlisten. Der praktische Fall ist der aus §10, den der Build-Hash nur **warnt**: zwei Rechner mit verschiedenen `.love`-Ständen, in denen `Snapshot.FIELDS` nicht mehr übereinstimmt. Heute zeigt der Gast dann still etwas Falsches an. Mit dem erneuten Packen fällt es binnen einer halben Sekunde auf.
- **djb2 statt MD5** hält es bei einem Hash im Projekt (ADR-016: „zwei Wahrheiten für eine Frage"), ist `love`-frei und damit headless prüfbar, und liefert dieselben 32 Bit wie die ersten vier Byte eines MD5. Gegen Manipulation sichert auch MD5 hier nichts ab — es gibt kein Angreifermodell im LAN.
- **Zwei Fehlerklassen, zwei Zähler.** Ein gemeinsamer Wert sagt im Fehlerfall nicht, ob die Vorhersage oder das Protokoll schuld ist. Getrennt beantwortet das F3-Overlay genau die Frage, die man abends stellt.
- **Ein fehlender Snapshot ist kein Desync.** Kommt die Prüfsumme zu einem Tick, dessen Snapshot verloren ging (Kanal 1 ist unzuverlässig, §4), zählt das als *fehlend*, nicht als Abweichung.

**Konsequenzen:**
- Die Konsequenzzeile aus ADR-016 („Der Desync-Detektor rechnet weiter mit `love.data.hash`") gilt nicht mehr. `love.data.hash` wird im Projekt derzeit nirgends benutzt.
- `src/net/checksum.lua` ist `love`-frei und läuft im Headless-Runner mit. Das Packen selbst braucht `love.data` und bleibt in `protocol.lua`.
- Der Detektor prüft **eine Aussage weniger**, als §9 1.1 versprochen hat: Er bestätigt nicht, dass Host und Client denselben Simulationszustand haben. Das kann er nicht, und ADR-002 macht die Frage gegenstandslos — es gibt genau einen Zustand.
- Kosten: zwei zusätzliche Nachrichten je Sekunde und Gast (8 Byte Nutzlast), ein zweites Packen alle 30 Ticks auf jeder Seite.

**Verworfen:**
- *MD5 über den gepackten Zustand:* zweiter Hash im Projekt, nicht headless prüfbar, kein Gewinn an Aussage.
- *Prüfsumme über die Zahlen mit fester Formatierung:* erzeugt seltene, unerklärliche Fehlalarme — der teuerste Fehlertyp, weil er das Vertrauen in den Detektor zerstört, bevor er einmal recht hat.
- *Prüfsumme nur über die eigene Blob-Position:* misst dasselbe wie der Korrekturzähler, nur gröber und alle 30 Ticks statt jeden Tick.
- *Hash über die empfangenen Rohbytes:* wäre eine Tautologie — ENet liefert die Bytes, die es bekommen hat. Erst das erneute Packen aus der **gelesenen** Tabelle prüft das Lesen.

**Revisionsauslöser:** Wenn der Detektor bei gleichem Build anschlägt. Dann ist entweder `Snapshot.apply` nicht mehr verlustfrei umkehrbar oder ein Feld wird beim Lesen verändert — beides ist ein echter Befund, kein Grund, den Detektor zu entschärfen.

---

## ADR-019 — Gespielt wird über Kabel; die WLAN-Frage N-01 wird zurückgestellt

**Status:** angenommen · 2026-08-13 · **Entscheidung r0btoshi** · **Bezug:** ADR-017, `11_OPS` §2, `04_NETCODE_SPEC` §13

**Kontext:** M3 hat die Vorhersage des eigenen Blobs gebaut. Der offene Punkt N-01 fragt, ob sie bei WLAN-Latenz von 20–40 ms ausreicht oder ob der Client zusätzlich den Ball extrapolieren muss. Diese Frage ist nur an zwei Geräten in einem WLAN zu beantworten, mit zwei Menschen, die sagen können, ob es sich falsch anfühlt — Aufwand rund eine halbe Stunde plus Terminfindung.

`11_OPS` §2 empfiehlt seit dem ersten Entwurf **Kabel vor WLAN**, mit Zahlen: RTT unter 1 ms gegen 5–30 ms mit Jitter, kein Paketverlust, keine Broadcast-Probleme, kein Roaming mitten im Satz.

**Entscheidung:** Der Partyabend läuft über einen Gigabit-Switch, alle Teilnehmer per Kabel. N-01 bleibt **offen und zurückgestellt**, nicht beantwortet und nicht gestrichen. M3 ist damit abgeschlossen.

**Begründung:**
- **Die Messung beantwortet eine Frage, die im geplanten Betrieb nicht gestellt wird.** Über Kabel liegt die RTT bei 1–2 ms. Dort war das Spiel schon in M2 **ohne jede** Vorhersage spielbar; mit ihr ist die Restlatenz des eigenen Blobs null. Der Ball ist dann 1–2 ms alt, und das ist unterhalb eines Einzelbildes.
- **Der Aufwand fällt an der falschen Stelle an.** Eine halbe Stunde plus Termin für eine Zahl, die keine Entscheidung mehr auslöst — während M4 (Turnier) 36–48 h braucht und der eigentliche Zweck des Projekts ist.
- **Zurückstellen ist nicht dasselbe wie Streichen.** Steckt am Abend jemand doch im WLAN — ein Laptop ohne Ethernet-Buchse, ein Gast mit Adapterproblem —, ist die Frage sofort wieder da. Deshalb bleiben Messanleitung und Werkzeug (F4-Mitschnitt) unverändert im Repo, und N-01 bleibt in `04_NETCODE_SPEC` §13 stehen.
- **Die Vorhersage bleibt trotzdem drin.** Sie ist gebaut, getestet und kostet über Kabel nichts. Sie wieder auszubauen wäre Arbeit, um etwas zu verlieren.

**Konsequenzen:**
- **Betrieblich:** Ein Switch mit genug Ports und Kabel für alle gehören auf die Packliste. Das ist neue Hardware-Voraussetzung, die vorher eine Empfehlung war. `11_OPS` §1 und §2 sind entsprechend nachgezogen.
- Annahme **A1** im Charter verengt sich von „ein Switch bzw. ein WLAN-AP" auf **einen Switch**. Das macht die Discovery-Lage einfacher, nicht schwerer.
- **T-N-02 und T-N-03** (5 % und 20 % Paketverlust) verlieren an Dringlichkeit: Über Kabel ist Paketverlust kein Normalfall, sondern ein Defekt. Sie bleiben offen und werden nicht mehr als Abnahmebedingung geführt.
- **T-N-09 dagegen wird wichtiger, nicht unwichtiger** — drei gleichzeitige Lobbys im selben Netz sind im Turnierbetrieb mit parallelen Matches (ADR-013) der Normalfall, nicht der Sonderfall. Der Fall wandert damit von der M2-Restschuld in die Abnahme von **M4-09**.
- Wer den Abend anders aufbaut, liest §5 der Messanleitung: Dort steht die Entscheidungsregel, mit der die Frage zu beantworten ist — vorab festgelegt, damit sie nicht zur Beobachtung passend gemacht wird.

**Verworfen:**
- *N-01 als beantwortet schließen:* Sie ist nicht beantwortet. Eine geschlossene Frage ohne Messung ist eine Behauptung mit Aktenzeichen.
- *Die Vorhersage zurückbauen, weil sie über Kabel keinen messbaren Nutzen bringt:* Sie ist fertig und schadet nicht. Und sie ist genau das, was den Fall rettet, in dem doch jemand im WLAN sitzt.
- *WLAN als zweite unterstützte Betriebsart zusagen:* Das hieße, T-N-02 und T-N-03 zur Abnahmebedingung zu machen und die Messung doch zu fahren. Wer über WLAN spielt, spielt auf eigenes Risiko — das steht so im Runbook.

**Revisionsauslöser:** Wenn am Abend mehr als ein Gerät ohne Kabel dasteht. Dann ist WLAN kein Sonderfall mehr, und N-01 ist vor dem nächsten Turnier zu messen.

---

## ADR-020 — Der Turnierstand wird als JSON persistiert, mit einem eigenen Encoder

**Status:** angenommen · 2026-08-13 · **Bezug:** ADR-007, ADR-016, M4-06, `05_TOURNAMENT` §7

**Kontext:** ADR-007 legt fest, dass der Turnierzustand ein append-only Log ist, atomar geschrieben. Offen war das **Format** der Datei. `05_TOURNAMENT` §7 nennt den Dateinamen `tournaments/{id}.json`, ADR-016 hat JSON für das Ruleset ausdrücklich verworfen und diese eine Frage ebenso ausdrücklich offen gelassen: „Wenn M4 JSON braucht, ist das eine eigene Entscheidung mit eigenem ADR."

Der Unterschied zum Ruleset ist real und nicht formal. Das Ruleset ist eine flache Tabelle aus 28 Werten. Der Turnierstand ist verschachtelt (Teilnehmer, Runden, Matches mit Satzlisten, Tabellen, Log), wächst über den Abend und wird nach **jedem** Log-Ereignis vollständig neu geschrieben.

Drei Kandidaten standen zur Wahl: ein Lua-Tabellenliteral mit `loadstring` zurückgelesen, eine Schlüssel-Wert-Textdatei wie `prefs.sav`, oder JSON mit eigenem Encoder und Decoder.

**Entscheidung:** Der Turnierstand wird als **JSON** geschrieben und gelesen, mit einem eigenen, `love`-freien Encoder/Decoder in `src/tournament/json.lua`. Keine Fremdbibliothek. Der Encoder sortiert Objektschlüssel, damit derselbe Zustand dieselben Bytes ergibt.

**Begründung:**
- **Die Datei ist ein Betriebsmittel, kein Zwischenformat.** `05_TOURNAMENT` §7 begründet die Persistenz mit „ein Zettel stürzt nicht ab". Der Fall, für den sie da ist, ist der, in dem die Software nicht mehr tut, was sie soll. Genau dann muss ein Mensch die Datei mit einem Texteditor öffnen, lesen und notfalls von Hand flicken können. Ein Format, das nur die Software versteht, verfehlt den Zweck der Maßnahme.
- **`loadstring` auf einer beschädigten Datei ist der schlechtere Fehlerfall.** Der Absturzfall aus §7 hinterlässt mit einiger Wahrscheinlichkeit eine halb geschriebene Datei. Ein JSON-Decoder meldet dann „unerwartetes Ende in Zeile 412" und der Lader greift zur `.bak`. `loadstring` auf einem abgeschnittenen Tabellenliteral meldet einen Syntaxfehler oder — schlimmer — lädt eine syntaktisch vollständige, inhaltlich halbe Tabelle. Nebenbei: eine Save-Datei durch den Lua-Übersetzer zu schicken ist ein Mechanismus, den man auch ohne Angreifermodell nicht bauen muss, wenn er nichts spart.
- **Das Flachformat aus `prefs.sav` trägt die Struktur nicht.** Es kennt keine Listen und keine Verschachtelung. Man müsste Pfade wie `matches.m_101.sets.1.a=15` erfinden — also JSON nachbauen, nur unlesbarer und ohne Grammatik.
- **Die Kosten sind bekannt und einmalig.** Encoder und Decoder zusammen rund 180 Zeilen für die Teilmenge, die hier vorkommt: Objekte, Listen, Zeichenketten, Zahlen, Wahrheitswerte, `null`. Kein Unicode-Escaping über den ASCII-Bereich hinaus, keine Streaming-Schnittstelle, keine Kommentare. Das ist kein Bibliotheksersatz und will keiner sein.
- **Zahlen gehen mit `%.17g` heraus**, aus demselben Grund wie in `Ruleset.canonical`: Der Wert, der zurückkommt, muss bitgleich der Wert sein, der hineinging. Punktestände sind ganzzahlig, aber `createdAt` und die Zeitstempel sind es nicht zwingend.
- **Sortierte Schlüssel** kosten nichts und machen zwei Dinge möglich: Dateien zweier Läufe lassen sich mit `diff` vergleichen, und ein Test kann auf Bytegleichheit prüfen statt auf Strukturgleichheit.

**Konsequenzen:**
- `src/tournament/json.lua` ist **kein** allgemeiner JSON-Ersatz und wird auch nicht dazu ausgebaut. Er deckt genau das ab, was `persistence.lua` schreibt. Wer ihn woanders benutzen will, prüft vorher, ob er es kann.
- Das Projekt bleibt fremdbibliotheksfrei. `LICENSE-THIRD-PARTY.md` bekommt keinen Eintrag.
- **Über die Leitung entscheidet dieser ADR nichts.** `TOURNAMENT_STATE` (0x40) ist eine andere Frage mit anderen Kräften — dort zählt Bytezahl und nicht Lesbarkeit, und dort gibt es mit `love.data.pack` bereits ein eingeführtes Verfahren. Die Entscheidung fällt in M4-09, wie ADR-016 es vorsieht.
- Die geschriebene Datei enthält neben `header` und `log` auch den **abgeleiteten** Zustand. Der Lader **ignoriert ihn** und rekonstruiert ausschließlich aus dem Log; der abgeleitete Teil steht für den Menschen darin, der die Datei um zwei Uhr nachts aufmacht. Der Test vergleicht beide Fassungen Feld für Feld — damit ist die Redundanz nicht Ballast, sondern die laufende Prüfung der Aussage „das Log ist die Wahrheit".

**Verworfen:**
- *Lua-Tabellenliteral mit `loadstring`:* spart rund 150 Zeilen und kostet die Lesbarkeit im einzigen Fall, für den die Datei existiert.
- *Format wie `prefs.sav`:* trägt keine Verschachtelung.
- *`love.data.pack` wie beim Snapshot:* binär, nicht lesbar, und ohne festes Feldlayout nicht sinnvoll — der Turnierstand ist im Gegensatz zum Snapshot kein festes Layout.
- *Eine JSON-Bibliothek aufnehmen:* braucht ADR, Lizenzeintrag und Pflege für eine Teilmenge, die in 180 Zeilen passt. ADR-016 hat dieselbe Frage schon einmal so beantwortet.

**Revisionsauslöser:** Wenn die Datei bei 32 Teilnehmern über 500 KB wächst oder das Schreiben nach einem Log-Ereignis messbar länger als 20 ms dauert. Dann ist nicht das Format falsch, sondern die Entscheidung, nach **jedem** Ereignis den ganzen Zustand zu schreiben.

---

## ADR-021 — Der Scheduler kennt weder Münzwurf noch Stillstand: drei Sackgassen bekommen eine deterministische Regel

**Status:** angenommen · 2026-08-13 · **Bezug:** ADR-013, `CLAUDE.md` §3.2 und §3.3, `05_TOURNAMENT` §5, §6, M4-05

**Kontext:** Beim Bauen des Zustandsautomaten aus `05_TOURNAMENT` §5 sind drei Lagen aufgetreten, die die Spec nicht abdeckt. Alle drei haben dieselbe Form: Der Automat kommt an eine Stelle, an der er ohne zusätzliche Regel entweder würfeln oder stehenbleiben müsste. Die Anti-Zufalls-Doktrin schließt das eine aus, die Betriebstauglichkeits-Doktrin das andere.

1. **Beide Spieler erscheinen nicht.** E-02 regelt den No-Show für *einen* Spieler: Timer läuft, Walkover für den anderen. Erscheint keiner, gibt es keinen anderen.
2. **Ein Teilnehmer ist gar nicht verbunden.** §5 verlangt für `pending → ready` ausdrücklich, dass **beide Spieler online** sind. Der No-Show-Timer läuft aber erst ab dem `calling`, also ab `ready`. Ein Spieler, dessen Rechner aus ist, hält sein Match damit für immer in `pending` — der Timer, der den Fall lösen soll, startet nie. Bei einem K.o.-Baum steht danach das halbe Turnier.
3. **Ein Gleichstand überlebt den Stichsatz.** E-11 endet nach vier Kriterien mit „Stichsatz auf 7 Punkte. **Kein Münzwurf**". Bei einem Dreifach-Gleichstand ist der Stichsatz ein Mini-Turnier aus drei Sätzen, und das kann wieder 1–1–1 ausgehen.

**Entscheidung:** Drei Regeln, alle deterministisch, alle im Log nachvollziehbar:

1. **Beidseitiger No-Show** → Walkover für den **höher gesetzten** Spieler (kleinere Setznummer), protokolliert mit `reason = "no_show_both"`.
2. **Offline-Blockade** → Ein Match, das ausschließlich daran scheitert, dass ein Teilnehmer offline ist, bekommt einen eigenen Timer über dieselbe `noShowTimeout`-Dauer. Läuft er ab, gilt der Offline-Spieler als No-Show; ist der Gegner online, gewinnt er per Walkover. Der Timer beginnt, sobald das Match ansonsten spielbar wäre — nicht früher.
3. **Gleichstand nach dem Stichsatz** → Nach **genau einer** Stichsatzrunde entscheidet die Setznummer. Eine zweite Runde wird nicht angesetzt.

**Begründung:**
- **Die Setznummer ist die einzige Ordnung, die vor dem Turnier feststeht.** Sie ist sichtbar, sie ist aus dem Seed reproduzierbar (`05_TOURNAMENT` §9), und sie ist nicht das Ergebnis der Lage, die gerade entschieden werden soll. Damit ist sie das genaue Gegenteil eines Münzwurfs: Wer sie anzweifelt, kann den Seed nachrechnen.
- **Zu Regel 1:** Die Alternative wäre, das Match neu anzusetzen. Das verschiebt das Problem und hält bei zwei dauerhaft abwesenden Spielern eine Bracket-Linie offen, an der später eine ganze Runde hängt. Ein Walkover schreibt das Bracket fort, und der Turnierleiter kann ihn per `manual_override` (E-12) korrigieren, wenn beide doch noch auftauchen. Der umgekehrte Weg — ein hängendes Match nachträglich zu entwerten — ist im Log deutlich unangenehmer.
- **Zu Regel 2:** Ohne sie ist §5 in sich widersprüchlich. Sie ist keine Erweiterung von E-02, sondern die Bedingung dafür, dass E-02 überhaupt greifen kann. Der Timer startet bewusst erst, wenn das Match sonst spielbar wäre: Ein Spieler, der in Runde 3 noch gar nicht dran ist, darf nicht dafür bestraft werden, dass er zwischendurch den Laptop zuklappt.
- **Zu Regel 3:** Eine Abbruchbedingung ist Pflicht, sonst ist die Terminierung des Turniers nicht bewiesen. Eine Runde Stichsatz gibt der sportlichen Entscheidung ihre Chance; danach ist die Wahrscheinlichkeit eines erneuten Dreifach-Gleichstands klein genug, dass die Setznummer der billigere Ausgang ist. „Kein Münzwurf" aus E-11 bleibt gewahrt — es wird nichts gelost.
- **Alle drei Regeln erzeugen einen Log-Eintrag mit Begründungstext.** Ein Ergebnis, das niemand erklären kann, ist am Partyabend teurer als ein Ergebnis, das jemandem nicht gefällt.

**Konsequenzen:**
- `05_TOURNAMENT` §6 bekommt drei neue Zeilen: **E-15** (beidseitiger No-Show), **E-16** (Teilnehmer offline), **E-17** (Gleichstand überlebt den Stichsatz).
- Der Scheduler braucht neben `calledAt` einen zweiten Zeitstempel je Match (`blockedSince`). Er ist **Laufzeitzustand und steht nicht im Log**: Er beschreibt die Verbindungslage, nicht das Turnier. Nach einem Neustart beginnt er neu — das ist richtig so, denn nach einem Neustart des Turnier-Hosts sind ohnehin alle Clients getrennt.
- Der Verbindungsstatus (`online`) ist aus demselben Grund kein Log-Ereignis. Was im Log steht, muss die Rekonstruktion aus §7 überstehen; eine Verbindung tut das nicht.
- Damit ist die Terminierung zusicherbar: Jedes Match erreicht in endlicher Zeit einen Endzustand, auch wenn niemand mehr spielt. Der Testlauf über ein 20er-Turnier prüft genau das.

**Verworfen:**
- *Münzwurf oder `math.random` bei Gleichstand:* `CLAUDE.md` §3.2. Im Turnierbetrieb ist das die Regel, an die sich am nächsten Tag alle erinnern.
- *Beidseitigen No-Show neu ansetzen:* hält eine Bracket-Linie offen, an der eine ganze Runde hängt.
- *Offline-Spieler sofort als Walkover werten:* bestraft einen Neustart. Deshalb dieselbe Frist wie beim No-Show — sie ist mit 180 s dafür bemessen.
- *Stichsätze wiederholen, bis eine Entscheidung fällt:* keine obere Schranke, und bei drei gleich starken Spielern ist der zweite Durchgang nicht aussagekräftiger als der erste.
- *Den Turnierleiter entscheiden lassen:* `05_TOURNAMENT` §1 nennt null manuelle Eingriffe als Zielverhalten. Eine Regel, die im Zweifel den Menschen ruft, ist genau der Eingriff, den §1 ausschließt.

**Revisionsauslöser:** Wenn bei einem echten Turnier die Setznummer mehr als einmal ein Ergebnis entscheidet. Dann ist nicht die Regel falsch, sondern das Format zu grob — bei häufigen Gleichständen gehört die Gruppengröße auf den Prüfstand, nicht der Tiebreaker.

---

## ADR-022 — Wer ein Match hostet: RTT-Median über 5 s, ab 5 ms Unterschied; sonst die Setznummer

**Status:** angenommen · 2026-08-13 · **Bezug:** ADR-013, ADR-021, `05_TOURNAMENT` §8 und §12 (T-01), M4-09

**Kontext:** `05_TOURNAMENT` §8 sagt, ein Match werde von „dem mit der besseren Verbindung zum Turnier-Host" gehostet. T-01 hält seit dem 2026-08-12 fest, dass das eine Absichtserklärung ist: Es fehlt das Maß (RTT woraus, über welchen Zeitraum) und es fehlt das Verhalten bei Gleichstand. Ein Gleichstand ohne Regel ist ein Münzwurf, und den schließt `CLAUDE.md` §3.2 aus.

Beim Bauen kommt eine Größe dazu, die T-01 nicht kannte: **Seit ADR-019 wird über Kabel gespielt.** Dort liegt die RTT bei 1–2 ms, und der Unterschied zwischen zwei Teilnehmern liegt im Rauschen. Ein Maß, das auf Rauschen entscheidet, ist kein Maß, sondern ein Münzwurf mit Messgerät. Die Frage ist damit nicht in erster Linie „wie messen wir", sondern „ab wann darf die Messung überhaupt entscheiden".

**Entscheidung:** Der Turnier-Host wählt den Match-Host in drei Schritten:

1. **Maß:** der **Median** der über PING/PONG (`04_NETCODE` §5, 0x50/0x51) gemessenen Anwendungs-RTT der letzten **5 s**. Bei `Host.PING_INTERVAL = 0.5` sind das bis zu zehn Proben.
2. **Schwelle:** Der Median entscheidet nur, wenn er sich um **mehr als 5 ms** unterscheidet. Der Schnellere hostet.
3. **Gleichstand** (Unterschied ≤ 5 ms, oder eine Seite hat keine Proben): Es hostet der Spieler mit der **kleineren Setznummer**.

Die getroffene Wahl steht mit beiden Messwerten und dem Grund (`"rtt"` oder `"seed"`) im Ereignis `match_started`.

**Begründung:**
- **Median statt Mittel.** Eine GC-Pause oder ein verlorenes PONG erzeugt genau einen Ausreißer unter zehn Proben. Der Mittelwert nimmt ihn mit und kann daran die Wahl kippen; der Median nicht. Das kostet nichts — die Proben liegen ohnehin vor.
- **Die Schwelle ist der eigentliche Inhalt dieses ADR.** 5 ms sind weniger als ein Drittel eines Simulationsschritts (1/60 s ≈ 16,7 ms). Ein Unterschied unterhalb dieser Grenze kann am Match nichts ändern; ihn entscheiden zu lassen hieße, dem Zufall eine Zahl vorzuspannen. Über Kabel ist der Gleichstandsfall damit **der Normalfall** — die Setznummer ist in der Praxis die Regel und die RTT die Ausnahme für den Fall, dass am Abend doch jemand im WLAN sitzt (N-01).
- **Die Setznummer und nicht die `participantId`.** T-01 schlug die `participantId` vor. ADR-021 hat für drei andere Sackgassen bereits die Setznummer zum Schlussanker gemacht, mit einer Begründung, die hier unverändert gilt: Sie steht vor dem Turnier fest, ist aus dem sichtbaren Seed nachrechenbar und ist nicht das Ergebnis der Lage, die sie entscheidet. Zwei verschiedene Anker für zwei verwandte Gleichstandsfragen wären zwei Wahrheiten — und am Abend erinnert sich niemand daran, welche wo gilt. Freigabe r0btoshi vor der Umsetzung; `05_TOURNAMENT` §12 ist entsprechend berichtigt.
- **Der Turnier-Host hostet sein eigenes Match immer.** Seine RTT zu sich selbst ist null, also gewinnt er die Messung. Das ist keine Ausnahmeregel, sondern das Maß, das seine Arbeit tut: null Netzsprünge ist die beste Verbindung, die es gibt. Eine Ausnahme („die Autorität bleibt frei") wäre ein Sonderfall im Code für einen Lastunterschied von einem Match, das der Prozess ohnehin mitspielt. Freigabe r0btoshi.
- **Der Host-Vorteil ist benannt und klein.** Wer hostet, sieht seine Eingabe ohne Netzweg. Der Gast sagt seinen eigenen Blob seit ADR-017 vorher, der Ball wird nicht vorhergesagt (ADR-002) — über Kabel bleibt davon etwa ein Frame. Er ist damit kleiner als der Unterschied, den die Schwelle ausschließt. Wäre er größer, wäre nicht die Wahlregel falsch, sondern die Architektur.

**Konsequenzen:**
- `Scheduler.new(t, { chooseHost = … })` bekommt endlich seine Antwort; die Platzhalterregel „der höher Gesetzte" aus Stufe A ist damit **zufällig der Gleichstandsfall** dieser Regel und bleibt in genau dieser Rolle stehen. Ohne Netz (Stufe B, Testrunner) ist sie weiterhin die vollständige Regel — es gibt dann keine Proben.
- `match_started` trägt drei Felder mehr: `rttA`, `rttB`, `hostReason`. Sie stehen im Log und überstehen die Rekonstruktion aus §7. Das ist Absicht: „Warum hostet der?" ist die Frage, die am Abend gestellt wird, und sie muss aus der Datei zu beantworten sein.
- Die **Proben** selbst stehen nicht im Log. Sie beschreiben die Verbindungslage, nicht das Turnier — dieselbe Grenze wie bei `online` und `blockedSince` in ADR-021.
- Der Turnier-Host misst die RTT ohnehin für die Anzeige; die Wahl kostet keine zusätzliche Nachricht.

**Verworfen:**
- *RTT zwischen den beiden Spielern messen:* wäre das sachlich richtige Maß, setzt aber eine Verbindung voraus, die es vor der Host-Wahl noch nicht gibt. Sie erst aufzubauen, um dann zu entscheiden, wer sie behält, kostet einen Rundlauf für eine Zahl, die über Kabel bei 1–2 ms liegt.
- *Mittelwert statt Median:* nimmt den einen Ausreißer mit, den es zu ignorieren gilt.
- *Keine Schwelle, jeder Unterschied entscheidet:* macht die Wahl von Messrauschen abhängig und damit unreproduzierbar — ein Münzwurf, den man nicht mehr als solchen erkennt.
- *`participantId` als Anker (T-01):* zweiter Anker neben ADR-021 für dieselbe Art Frage.
- *Der Turnier-Host hostet nie:* Sonderfall im Code für einen Lastunterschied von einem Match.
- *Der Turnierleiter wählt:* `05_TOURNAMENT` §1 nennt null manuelle Eingriffe als Zielverhalten.

**Revisionsauslöser:** Wenn am Abend jemand im WLAN sitzt und die 5-ms-Schwelle regelmäßig überschritten wird — dann entscheidet plötzlich die RTT statt der Setznummer, und ob das Ergebnis noch als fair empfunden wird, ist eine Beobachtung und keine Rechnung. Ebenso, wenn der Host-Vorteil in einem echten Match sichtbar wird: dann ist ADR-002 an der Reihe, nicht dieser ADR.

---

## ADR-023 — `TOURNAMENT_STATE` (0x40) überträgt Log-Ereignisse als JSON, nicht den abgeleiteten Zustand

**Status:** angenommen · 2026-08-13 · **Bezug:** ADR-007, ADR-016, ADR-020, `04_NETCODE` §5, `05_TOURNAMENT` §8, M4-09

**Kontext:** `TOURNAMENT_STATE` (0x40) ist seit `04_NETCODE` 1.0 als Nachrichtentyp reserviert und war bis heute **ohne Format**. ADR-016 hat JSON für das Ruleset verworfen und diese eine Nachricht ausdrücklich offengelassen: „Wenn M4 JSON braucht, ist das eine eigene Entscheidung mit eigenem ADR." ADR-020 hat JSON für die **Datei** gewählt und über die Leitung ebenso ausdrücklich nichts entschieden — mit dem Hinweis, dort zähle „Bytezahl und nicht Lesbarkeit".

Dieser Hinweis stimmt, aber er ruht auf einer Annahme, die niemand geprüft hatte: **dass der abgeleitete Zustand über die Leitung geht.** Er muss nicht. Der Turnierzustand ist seit ADR-007 ein append-only Log, aus dem alles andere gerechnet wird. Ein Log wächst nur hinten — die Differenz zwischen zwei Ständen ist damit immer ein Suffix, und ein Suffix braucht keine Invalidierung, keine Sequenznummern über die reine Position hinaus und keinen Weg, auf dem ein Empfänger „veraltet" wird.

Die Größenordnungen: der abgeleitete Zustand eines 20er-Turniers ist rund 30 KB, ein einzelnes Log-Ereignis rund 100 Byte. Bei ~150 Ereignissen über den Abend und 20 Empfängern ist das der Unterschied zwischen 90 MB und 300 KB — und das, ohne einen Delta-Mechanismus erfinden zu müssen.

**Entscheidung:** `TOURNAMENT_STATE` (0x40) überträgt **Log-Ereignisse**, nicht den abgeleiteten Zustand. Die Nutzlast ist `fromIndex(u4)`, `count(u2)` und die Ereignisse als **JSON-Array** in einer `s4`-Zeichenkette, kodiert mit dem vorhandenen `src/tournament/json.lua`. Der Empfänger reicht jedes Ereignis an dasselbe `Model.applyEvent`, das die Recovery und der Turnier-Host benutzen.

**Begründung:**
- **Kein zweiter Ableitungspfad.** Das ist der Hauptgrund, nicht die Bytezahl. `CC-05_REPORT` §1a nennt „nichts außerhalb von `applyEvent` fasst den abgeleiteten Zustand an" die eine Entscheidung, die alles andere trägt — die Recovery aus §7 ist deshalb kein eigener Code. Würde die Leitung den fertigen Zustand tragen, gäbe es einen zweiten Weg, auf dem ein Turnierstand entsteht: einen, der beim Beamer und bei jedem Spieler läuft und der beim ersten Auseinanderlaufen mit dem Host nicht mehr entscheidbar wäre. Ereignisse zu übertragen heißt, dass Host, Datei und jeder Empfänger denselben Zustand aus derselben Funktion in derselben Reihenfolge rechnen.
- **Die Lückenerkennung ist geschenkt.** Der Empfänger kennt seinen Wasserstand. `fromIndex` größer als erwartet heißt „mir fehlt etwas" und wird mit einer Nachforderung ab dem eigenen Stand beantwortet. Kein Zustandsvergleich, keine Prüfsumme, kein Resync-Pfad, der bis zum Partyabend nie läuft.
- **Binär bräuchte fünfzehn Codecs.** Das Log kennt fünfzehn Ereignisarten mit verschiedenen Feldern. Ein festes Feldlayout je Art müsste bei jeder Modelländerung mitgezogen werden, und ein vergessener Nachzug fällt als stiller Zahlendreher am Abend auf — genau der Grund, aus dem ADR-016 das Ruleset selbstbeschreibend überträgt. JSON ist hier die selbstbeschreibende Form.
- **`json.lua` kann es, und das ist geprüft und nicht angenommen.** ADR-020 verlangt ausdrücklich: „Wer ihn woanders benutzen will, prüft vorher, ob er es kann." Er deckt genau das ab, was `persistence.lua` schreibt — und was `persistence.lua` schreibt, ist unter anderem dieses Log, Ereignis für Ereignis. Es sind dieselben Tabellen mit denselben Werttypen. Der Encoder wird für diese Entscheidung **nicht erweitert**.
- **Eine Darstellung für Datei und Leitung.** Ein Fehler im Encoder zeigt sich damit an beiden Stellen statt an einer, und die Stelle, an der er auffällt, ist die Datei — die ein Mensch aufmachen kann.
- **Die Bytezahl-Erwägung aus ADR-020 bleibt gültig, sie trifft nur nicht mehr zu.** Wer den Zustand überträgt, sollte ihn binär übertragen. Wir übertragen ihn nicht.

**Konsequenzen:**
- `04_NETCODE` §5 bekommt die **`s4`-Ausnahme** für 0x40, mit Begründung und ausdrücklich auf diese eine Nachricht begrenzt. Ein Block aus Ereignissen überschreitet 255 Byte, und ein Feldmaß zum Kürzen gibt es hier nicht.
- Ein Empfänger, der mitten im Turnier dazukommt, bekommt das Log ab Index 0 — bei 150 Ereignissen rund 15 KB, einmal, auf dem zuverlässigen Kanal 0. Gesendet wird in Blöcken zu 32 Ereignissen, damit eine einzelne Nachricht nicht beliebig groß wird.
- Der Empfänger hält ein **echtes `Model`** und eine echte `Session`. `bracket_view.lua` liest unverändert aus `Session` — die Quelle des Modells ändert sich, die Anzeige nicht (`CC-05_REPORT` §7).
- **Der Empfänger schreibt nichts ins Log.** Sein `Session` ist lesend; jede Bedienung geht als eigene Nachricht an den Turnier-Host, der das Ereignis anhängt und zurückverteilt. Sonst gäbe es zwei Schreiber auf einem append-only Log, und die Reihenfolge wäre nicht mehr die eine Wahrheit aus ADR-007.
- Ein Ereignis, dessen Art der Empfänger nicht kennt (ältere ZIP), wird verworfen und gezählt, nicht angewandt. Ein halb angewandtes Log wäre schlimmer als ein sichtbar veralteter Stand.
- `src/tournament/json.lua` bleibt trotzdem kein allgemeiner JSON-Ersatz. Diese Nutzung ist die geprüfte Ausnahme, die ADR-020 vorgesehen hat, keine Öffnung.

**Verworfen:**
- *Den abgeleiteten Zustand übertragen, binär:* fünfzehn bis zwanzig Feldlayouts, ein zweiter Ableitungspfad, und der Zwang, entweder 30 KB je Ereignis zu senden oder einen Delta-Mechanismus mit Invalidierung zu erfinden.
- *Den abgeleiteten Zustand übertragen, als JSON:* dieselbe Doppelableitung, dazu 30 KB je Ereignis. Das ist der Fall, gegen den ADR-020 zu Recht gewarnt hat.
- *Log-Ereignisse binär, ein Codec je Ereignisart:* spart rund 60 % einer ohnehin kleinen Nachricht und erkauft es mit fünfzehn Dateien voller Feldlisten, die stillschweigend falsch werden.
- *Die Zustandsdatei selbst verschicken:* enthält den abgeleiteten Teil doppelt (ADR-020) und wächst mit dem Abend.
- *Eine JSON-Bibliothek aufnehmen:* dieselbe Antwort wie in ADR-016 und ADR-020.

**Revisionsauslöser:** Wenn das Log über einen Abend so groß wird, dass die Erstübertragung an einen dazukommenden Empfänger spürbar dauert (Größenordnung: über 500 KB, dieselbe Schwelle wie in ADR-020). Dann ist nicht das Format falsch, sondern die Annahme, dass ein Empfänger das ganze Log braucht — dann bekäme er einen Zustandsabzug plus das Suffix danach.

---

## ADR-024 — Das Menü liegt über dem Netzspiel, ohne es anzuhalten

**Status:** angenommen · 2026-08-14 · **Bezug:** ADR-002, M0-12, M4-09, `04_NETCODE` §12

**Kontext:** `src/app/scene.lua` treibt seit M0-12 **nur die oberste Szene**. Gezeichnet wird von der untersten sichtbaren aufwärts, aktualisiert wird allein oben. Für das lokale Spiel ist das genau richtig: Das Menü liegt darüber, bekommt kein `update` weitergereicht, und damit **ist** das Nichtaktualisieren die Pause. Eine Phase „menu" im Spielzustand entfällt.

Im Netzspiel trägt das nicht. `src/app/scenes/net_game.lua` hält deshalb seit M2 gar kein Menü: ESC beendet dort die ganze Sitzung. Die Begründung im Kopf der Datei lautete, eine Pause beim Host sei „eine Pause, die der Gast nicht mitbekommt — das Bild steht, das Netz läuft weiter".

**Das Problem war richtig erkannt, die Konsequenz war die falsche: abgeschafft wurde das Menü, nicht die Pause.** Zwei Folgen, beide gemessen:

1. Wer im Spiel die Einstellungen sehen will, verliert das Spiel. Im Turnier war es schlimmer — ESC warf bis M4-09 aus dem gesamten Turnier, ohne Weg zurück (C-T-13).
2. Dieselbe Regel hat den Turniermodus getroffen, sobald er Sockets hielt: Während eines Matches lag er unter der Matchszene, bekam kein `update`, und sein ENet-Wirt wurde minutenlang nicht bedient. Nach 5 s Peer-Timeout galt jeder Teilnehmer als offline (C-T-01). Geflickt wurde das, indem die Turnierverbindung **in die Matchszene durchgereicht** wird — ein Sonderfall, der bei der nächsten Szene mit Socket wieder gebaut werden müsste.

**Entscheidung:** `Scene.update` treibt die oberste Szene **und** jede darunter, die sich mit `alwaysUpdate = true` dafür meldet. Das Menü ist damit auch aus dem Netzspiel erreichbar und hält es nicht an.

Es melden sich an: `net_game` (hält Sockets und simuliert beim Host autoritativ) und `tournament` (hält Sockets). `local_game` **nicht** — dort bleibt das Nichtaktualisieren die Pause.

Zwei Festlegungen gehören dazu:

- **Die eigene Eingabe ist neutral, solange etwas über der Matchszene liegt.** Nicht „letzte Maske wiederholen" wie bei fehlendem Netz-Input (§7): Das ist hier keine Lücke, sondern eine Absicht.
- **Das Verlassen wandert ins Menü.** Wenn ESC nicht mehr beendet, braucht es einen benannten Weg hinaus.

**Begründung:**
- **`Scene.draw` macht es längst so.** Es läuft von der untersten sichtbaren Szene aufwärts. Dass `update` das nicht kann, war eine Vereinfachung und keine Entscheidung — sie stammt aus einer Zeit, in der keine Szene etwas besaß, das weiterlaufen muss.
- **Eine Regel statt zweier Sonderfälle.** Der Durchreich-Umweg aus C-T-01 fällt weg. Was eine Szene besitzt, bedient sie selbst — sonst muss jede künftige Szene mit Socket ihre Verbindung durch alles hindurchreichen, was sich über sie legt.
- **Die Pause bleibt dort, wo sie hingehört.** Das lokale Spiel ändert sich nicht: keine Marke, kein `update`, Pause wie bisher. Die Marke ist eine Zusage der Szene über sich selbst und keine globale Umschaltung.
- **Neutrale Eingabe statt Tastendurchgriff.** `net_game` liest die Tastatur je Tick direkt und nicht über die Szene. Ohne diese Festlegung würde man im Menü navigieren **und** gleichzeitig seinen Blob bewegen. Ein stehender Blob ist vorhersagbar; wer im Ballwechsel ins Menü geht, verliert den Punkt, und das ist in Ordnung — es ist seine Entscheidung.
- **Der Gegner merkt nichts.** Das ist der eigentliche Gewinn gegenüber einer Pause: Es gibt keinen Zustand, den die eine Seite kennt und die andere nicht. Simulation und Snapshots laufen unverändert weiter, `MATCH_PAUSE` (0x24) bleibt dem Verbindungsverlust vorbehalten, für den es gedacht ist (§12).

**Konsequenzen:**
- `Scene.update` bekommt eine Schleife statt einer Zeile; die Reihenfolge ist von unten nach oben, damit die oberste Szene den zuletzt gültigen Zustand sieht.
- `net_game.lua` verliert `opts.tournament` samt dem Aufruf in `update`. Bliebe beides, würde die Turnierverbindung **zweimal je Bild** bedient — doppelte PINGs und ein doppelt laufender Automat.
- Das Hauptmenü bekommt einen Eintrag zum Verlassen des Netzspiels. `App.openMenu` gilt nicht mehr nur für die lokale Spielszene.
- Wer ESC im Turniermatch drückt, bleibt im Match. Der Aussteigeweg aus C-T-13 bleibt trotzdem gebaut — er greift weiterhin bei einem Absturz oder wenn jemand das Match über das Menü verlässt.
- **Eine Szene mit `alwaysUpdate` muss damit rechnen, dass sie ohne Tastatur läuft.** `keypressed` bekommt weiterhin nur die oberste.

**Verworfen:**
- *Alles immer aktualisieren:* nimmt dem lokalen Spiel die Pause, und die ist seit M0-12 der Grund, warum es keine Phase „menu" im Spielzustand gibt.
- *Das Match beim Öffnen des Menüs pausieren:* genau der Fehler, den der Kopf von `net_game.lua` beschreibt. Eine Pause, die nur eine Seite kennt, ist ein Desync mit Ansage.
- *Die Verbindung weiter durchreichen:* funktioniert für zwei Szenen und bricht bei der dritten. Es ist außerdem die falsche Richtung — die Matchszene weiß dann Dinge über das Turnier, die sie nichts angehen.
- *Die Tastatur ins Menü durchreichen und den Blob mitlaufen lassen:* „seines Glückes Schmied" gilt für die Entscheidung, das Menü zu öffnen — nicht dafür, dass die Navigation im Menü den Blob springen lässt.

**Revisionsauslöser:** Wenn eine Szene mit `alwaysUpdate` einmal erkennbar Rechenzeit kostet, während etwas darüber liegt — dann ist nicht die Regel falsch, sondern diese Szene tut im Hintergrund mehr, als sie muss.

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
