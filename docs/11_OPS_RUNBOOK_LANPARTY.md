# 11 — Runbook: Betrieb auf der LAN-Party

**Version:** 1.0 · **Stand:** 2026-08-11
**Zweck:** Die Software ist fertig. Dieses Dokument sorgt dafür, dass sie am Abend auch läuft.

---

## 1. Vorbereitung (Tag vorher, ~45 min)

| # | Aufgabe | Fertig |
|---|---------|--------|
| 1 | Aktuellen Build erzeugen, **beide** ZIPs auf einem Fremdrechner testen | ☐ |
| 2 | ZIPs auf USB-Stick **und** auf den Verteil-Laptop kopieren | ☐ |
| 3 | Auf dem Verteil-Laptop einen HTTP-Server vorbereiten (`python3 -m http.server 8000` im ZIP-Ordner) | ☐ |
| 4 | QR-Code auf die Download-URL erzeugen, für den Beamer als Bild ablegen | ☐ |
| 5 | Turnier-Host-Rechner festlegen (der **nicht** an der Steckdose stirbt und **kein** Gaming-Laptop mit aktivem Update ist) | ☐ |
| 5b | Bei ~20 Teilnehmern: **8 spielfähige Rechner** für 4 parallele Matches zählen. Weniger Geräte = längeres Turnier, der Scheduler blockiert nicht, aber die Rechnung in `05_TOURNAMENT` §2 verschiebt sich | ☐ |
| 6 | Auf dem Host-Rechner: Firewall-Freigabe für das Spiel **vorab** erteilen (Schritt 3 unten) | ☐ |
| 7 | Auf dem Host-Rechner: Energiesparmodus/Standby **aus**, Windows-Update pausieren | ☐ |
| 8 | Beamer-Rechner testen: Auflösung, `--beamer`-Start, Lautstärke | ☐ |
| 9 | 2 Ersatz-Gamepads und Kabel einpacken | ☐ |
| 10 | Turnier vorab anlegen (Name, Format, Preset) und einmal mit Bots durchspielen | ☐ |
| 11 | Auf jedem Mac einmal **vorab** die App per Rechtsklick öffnen — der Umweg kostet am Abend sonst pro Gerät 2 Minuten Erklärung (ADR-012) | ☐ |

## 2. Netzwerkaufbau

**Der wichtigste Satz dieses Dokuments: Kabel schlägt WLAN, immer.**

| Aufbau | Bewertung |
|--------|-----------|
| **Gigabit-Switch, alle per Kabel** | ✅ Ideal. RTT < 1 ms, kein Paketverlust, keine Broadcast-Probleme |
| Ein WLAN-AP, alle drauf, Client-Isolation aus | ⚠️ Funktioniert, RTT 5–30 ms mit Jitter. Spielbar, aber der Client merkt es |
| Mehrere APs / Mesh | ⚠️ Roaming-Aussetzer während eines Satzes. Vermeiden |
| Gäste-WLAN | ❌ Client-Isolation ist dort Standard. Discovery funktioniert nicht, direkte Verbindungen oft auch nicht |
| Mehrere Subnetze | ❌ Broadcast überschreitet Subnetzgrenzen nicht. Discovery tot |

**Mindestanforderung:** Alle Rechner in **einem** Subnetz, ein L2-Segment (Charter-Annahme A1).

**Schnelltest vor dem Abend:** Von zwei Rechnern aus je `ping <IP des anderen>`. Kommt keine Antwort, hilft auch das Spiel nicht.

## 3. Firewall (der häufigste Ausfallgrund)

### Windows

Beim ersten Start fragt Windows nach der Netzwerkfreigabe. **Wer hier auf „Abbrechen" klickt oder das Fenster wegklickt, ist für den Rest des Abends unsichtbar.**

- Bei der Abfrage **„Private Netzwerke"** ankreuzen. „Öffentliche Netzwerke" reicht meist nicht für eingehende Verbindungen.
- Prüfen, ob das aktuelle Netzwerkprofil auf „Privat" steht: Einstellungen → Netzwerk und Internet → Eigenschaften der Verbindung → Netzwerkprofiltyp: **Privat**.
- Falls die Abfrage bereits weggeklickt wurde: Windows Defender Firewall → „App durch die Firewall kommunizieren lassen" → Eintrag suchen und Haken bei „Privat" setzen. Alternativ: Eintrag löschen, Spiel neu starten, Abfrage erscheint erneut.

### macOS

- Die macOS-Firewall ist standardmäßig aus. Falls sie aktiv ist: Systemeinstellungen → Netzwerk → Firewall → Optionen → eingehende Verbindungen für die App erlauben.
- Beim ersten Start als Host erscheint eine Abfrage „möchte eingehende Netzwerkverbindungen annehmen" → **Erlauben**.

### Der Fallback, wenn Discovery trotzdem nichts findet

1. Auf dem Host: die in der Lobby groß angezeigte **LAN-IP ablesen**.
2. Auf dem Client: Serverliste → letzter Eintrag „Direkt verbinden (IP eingeben)" → IP eintippen.

Das funktioniert immer, wenn `ping` funktioniert. Deshalb ist die manuelle IP-Eingabe im Design als Pflichtfeature geführt und nicht als Notlösung versteckt.

## 4. Verteilung an die Gäste

**Ablauf am Beamer:**
```
┌─────────────────────────────────────┐
│   NETZKANTE                         │
│                                     │
│   Download:  http://192.168.1.42:8000 │
│   [QR-Code]                         │
│                                     │
│   Windows:  ZIP entpacken → EXE     │
│   Mac:      ZIP entpacken →         │
│             RECHTSKLICK auf App     │
│             → "Öffnen"              │
│             (Doppelklick geht NICHT)│
└─────────────────────────────────────┘
```

Der Rechtsklick-Hinweis für Mac gehört auf die Folie, nicht ins `LIESMICH.txt`. Niemand liest LIESMICH-Dateien auf einer Party.

**Häufigster Fehler beim Entpacken (Windows):** Die EXE wird direkt aus dem ZIP heraus gestartet, ohne zu entpacken. Dann fehlen die DLLs und es kommt eine Fehlermeldung. Auf die Folie: **„ZIP erst entpacken, dann starten."**

## 5. Ablauf des Turnierabends

| Phase | Dauer | Aktion |
|-------|-------|--------|
| **Ankommen** | 30 min | Verteilung läuft, offene Lobbys für freies Spiel. Bot-Match auf dem Beamer als Blickfang |
| **Anmeldung** | 10 min | Turnier-Lobby offen, Spieler tragen sich mit Namen ein. Beamer zeigt Teilnehmerliste live |
| **Setzung** | 3 min | Format und **Preset (`Classic` oder `Volley Dash`)** bestätigen, Seed sichtbar würfeln, Gruppen erzeugen. **Ab hier kein Nachrücken mehr** (E-03) |
| **Gruppenphase** | 40–50 min | 4 Gruppen à 5, Best-of-1, 3–4 Matches parallel. Automatisches Calling |
| **K.o.-Runden** | 25–35 min | 8er Single Elim, ab Viertelfinale Best-of-3 |
| **Zwischen den Runden** | 5 min | Pause ansagen. Ausgeschiedene gehen in offene Lobbys |
| **Finale** | 15 min | Best-of-3. Alle anderen als Zuschauer, Beamer auf Vollbild |
| **Siegerehrung** | 5 min | Statistiken einblenden, Bracket exportieren |

**Regel für den Turnierleiter:** Der No-Show-Timer läuft sichtbar. Er wird nur pausiert, wenn jemand nachweislich unterwegs ist. Sonst zieht sich der Abend, und ein Turnier, das sich zieht, verliert seine Teilnehmer.

## 6. Störungsbehebung im Betrieb

| Symptom | Wahrscheinliche Ursache | Sofortmaßnahme |
|---------|-------------------------|----------------|
| Lobby erscheint nicht in der Liste | Firewall / falsches Netzwerkprofil / WLAN-Isolation | Manuelle IP-Eingabe (§3). Parallel Firewall prüfen |
| „Version stimmt nicht überein" | Alte ZIP im Umlauf | Aktuelle ZIP neu herunterladen lassen |
| „Regelwerk stimmt nicht überein" | Client hat Live-Tweaker offline benutzt | Client: Preset `classic` neu laden, dann erneut beitreten |
| Bild ruckelt beim Client, Host flüssig | Paketverlust im WLAN | Auf Kabel wechseln. Falls nicht möglich: F3-Overlay prüfen und Verlustrate melden |
| Spieler fühlt sich „hinterher" | Er ist Client, Host hat 0 ms Latenz | Bei wichtigen Matches: Host neutral wählen oder Seiten nach jedem Satz tauschen |
| Match hängt im Zustand „Warte auf …" | Ein Client ist abgestürzt | 30 s abwarten, dann greift Walkover automatisch |
| Turnier-Host abgestürzt | siehe unten | §7 |
| Beamer zeigt veraltetes Bracket | Verbindung zum Turnier-Host verloren | Beamer-Client neu starten, verbindet sich automatisch neu |
| Gamepad reagiert nicht | Nach Spielstart eingesteckt | Hotplug sollte greifen; sonst zurück ins Menü und wieder rein |

## 7. Notfall: Turnier-Host abgestürzt

1. **Ruhe.** Der Zustand liegt auf der Platte (ADR-007).
2. Spiel auf dem Host-Rechner neu starten.
3. Dialog „Laufendes Turnier gefunden — fortsetzen?" bestätigen.
4. Spieler in die wieder offene Lobby zurückschicken (Discovery findet sie automatisch).
5. Matches, die beim Absturz live waren, werden neu angesetzt. Bereits abgeschlossene Sätze zählen.

**Wenn das nicht funktioniert:** Bracket-Export aus dem letzten Speicherstand öffnen (`tournaments/`), am Beamer anzeigen, restliche Runden manuell aufrufen und als freie Matches spielen. Das Turnier läuft dann „von Hand" weiter — deshalb ist der Export im Design.

## 8. Nach dem Abend

- [ ] Bracket-Export sichern (für die Setzung beim nächsten Mal, Modus `by_rating`)
- [ ] `desync.log` und F3-Statistiken einsammeln — echte Netzwerkdaten von echter Hardware sind wertvoller als jeder Labortest
- [ ] Beobachtungen notieren: Wo hakte es? Wer hat was nicht verstanden? Welcher Mutator wurde gewünscht?
- [ ] Erkenntnisse in `08_ROADMAP_BACKLOG.md` §M6 einsortieren

**Die drei Fragen, die nach dem Abend beantwortet sein müssen:**
1. Wie lange hat der langsamste Gast von der ZIP bis zum ersten Ballwechsel gebraucht?
2. Wie oft musste der Turnierleiter eingreifen?
3. Hat jemand nach dem Original gefragt, weil sich etwas falsch anfühlte?

Frage 3 ist die wichtigste — sie ist der einzige verlässliche Test auf Vanilla-Treue.
