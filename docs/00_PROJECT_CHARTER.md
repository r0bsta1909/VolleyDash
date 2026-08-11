# 00 — Project Charter: VOLLEY DASH

**Version:** 1.0 · **Stand:** 2026-08-11 · **Status:** Entwurf, wartet auf Freigabe

---

## 1. Problem & Anlass

Blobby Volley war und ist ein LAN-Party-Klassiker — das deutsche Wikipedia führt genau das als Nutzungsmuster: kurze Runden, Turniereinsatz, minimale Hardwareanforderungen. <cite index="52-1">Blobby Volley wurde aufgrund der relativen Kürze des Spiels oft auf LAN-Partys als Turnierspiel genutzt und in die LAN-Ligen WWCL und NGL aufgenommen.</cite>

Was auf einer heutigen LAN-Party fehlt: eine Version, die
- auf **Windows und macOS** ohne Installationsritual startet,
- sich im LAN **ohne IP-Eingabe** findet,
- und Turniere **ohne externes Bracket-Tool** (Challonge, Zettel, Whiteboard) abwickelt.

Der bestehende Prototyp löst den Kern (Physik, Spielgefühl, Bot) bereits gut. Alles Fehlende ist Infrastruktur, nicht Design.

## 2. Zielbild (Definition of Done für v1.0)

Ein Gast kommt mit Laptop auf die Party, bekommt eine ZIP, entpackt sie, startet die EXE/App, sieht ohne Konfiguration die offene Turnier-Lobby im Menü, tritt bei — und spielt. Der Host startet das Turnier, das System verteilt Paarungen, Ergebnisse landen automatisch im Bracket, der Beamer zeigt den Stand.

## 3. Scope — In

| # | Ergebnis | Messbar fertig, wenn … |
|---|----------|------------------------|
| S1 | Standalone-Build Windows (x64) | ZIP entpacken → Doppelklick → Spiel läuft auf einem frisch aufgesetzten Win-11-Rechner ohne Runtime-Installation |
| S2 | Standalone-Build macOS (Universal, Intel + Apple Silicon) | `.app` startet auf einem fremden Mac; Gatekeeper-Weg ist in max. 2 dokumentierten Schritten überwindbar |
| S3 | Deterministisch definiertes Vanilla-Regelwerk | Preset `Classic` erfüllt die Regelmatrix in `01_GDD` §3 zu 100 % |
| S4 | LAN 1v1 über Netzwerk | 2 Rechner (1× Win, 1× Mac) im selben Switch/WLAN spielen 3 Sätze ohne Desync, ohne manuelle IP-Eingabe |
| S5 | Zero-Config Discovery | Lobbys erscheinen ≤ 3 s nach Menüaufruf in der Serverliste |
| S6 | Integrierter Turniermodus | Gruppen + Single Elimination, **20 Spieler**, 3–4 parallele Matches, komplett ohne externes Tool; Absturz eines Clients kostet kein Turnier |
| S7 | Spectator (manuell) | Beliebiger Client kann laufendem Match als Zuschauer beitreten |
| S8 | Beamer-Modus (manuell) | Dedizierter Client zeigt Bracket + wählbares Live-Match im Vollbild |

## 4. Scope — Out (v1.0)

Explizit **nicht** in v1.0, mit Begründung — damit es später nicht durch die Hintertür zurückkommt:

| Ausgeschlossen | Begründung |
|----------------|------------|
| **Support-Zusage für das Open-Source-Repo** | Das Repo ist offen, nicht betreut (ADR-011). Keine Zusage auf Issue- oder PR-Bearbeitung, keine öffentliche Roadmap-Verpflichtung |
| **Automatische Beamer-Regie** („schaltet zum spannendsten Match") | Erfordert paralleles Beobachten aller Matches + Spannungs-Heuristik + Match-Priorisierung. Hoher Aufwand, geringer Nutzen bei ≤ 4 parallelen Matches, die ein Mensch selbst umschalten kann. → M6 |
| **Zeitlupen-Replay** | Braucht Ringbuffer über alle Snapshots + Scrubbing-UI. Nice-to-have. → M6 |
| **Internet-Multiplayer / NAT-Traversal** | Widerspricht dem Charter („reiner LAN-Einsatz"). Kein Server, kein Matchmaking, keine Accounts. |
| **Mobile-Ports** | Steuerung passt nicht, kein Nutzen für den Anwendungsfall. |
| **2v2 und King of the Hill** | Sind Design-Erweiterungen, keine Infrastruktur. Erst nach stabilem 1v1-Netcode sinnvoll. → M6 |
| **Schweizer System im Turnier** | Single Elim + Round Robin decken 8–32 Spieler ab. Swiss braucht Buchholz-Wertung + Paarungsalgorithmus. → M6 |
| **Anti-Cheat** | LAN mit Freunden. Bedrohungsmodell existiert nicht. |

## 5. Erfolgskriterien (harte Zahlen)

| Kriterium | Zielwert | Messmethode |
|-----------|----------|-------------|
| Time-to-First-Match für einen neuen Gast | ≤ 90 s ab ZIP-Download | Stoppuhr, 3 Probanden |
| Eingabelatenz LAN (Tastendruck → Blob bewegt sich) | ≤ 50 ms bei RTT < 5 ms | High-Speed-Kamera oder Frame-Zähler |
| Desyncs pro 100 Sätze | 0 | Checksum-Log, siehe `07_TEST_PLAN` §5 |
| Turnier 20 Spieler, Gruppen + Single Elim | ≤ 100 min bei 4 parallelen Matches, ohne Moderationsaufwand | Live-Test |
| Absturzresistenz Turnier | Host-Neustart verliert ≤ 1 Match | Absturztest `07_TEST_PLAN` §6 |
| RAM-Verbrauch | < 150 MB | Task-Manager / Activity Monitor |
| Startzeit bis Hauptmenü | < 3 s auf 2015er-Hardware | Stoppuhr |

## 6. Constraints

- **Engine ist gesetzt:** LÖVE 11.5. Kein Engine-Wechsel — der Prototyp funktioniert, das Spielgefühl sitzt. Portierung nach Godot/Raylib wäre ein Neuschreiben ohne Gegenwert. (ADR-001)
- **Nebenberuflich.** Realistische Kapazität: 4–8 h/Woche. Der Meilensteinplan in `08` ist darauf ausgelegt und liefert nach **jedem** Meilenstein ein spielbares Artefakt.
- **Zielhardware:** alles, was eine LAN-Party mitbringt, inkl. 8 Jahre alter Laptops mit iGPU.
- **Keine laufenden Kosten.** Kein Apple Developer Program (ADR-012), kein Code-Signing-Zertifikat für Windows, keine Hosting-Kosten (GitHub Releases).

## 7. Top-Risiken

| ID | Risiko | Wirkung | Gegenmaßnahme | Doc |
|----|--------|---------|---------------|-----|
| R-01 | Lockstep-Ansatz aus dem Ausgangs-GDD führt zu Desyncs zwischen Win-x64 und macOS-ARM64 | Netcode unbrauchbar, Monate verloren | Lockstep gestrichen, host-autoritative Snapshots | ADR-002 |
| R-02 | Windows-Firewall blockt UDP-Broadcast → Discovery findet nichts, ausgerechnet am Partyabend | S5 fällt aus, Fallback auf manuelle IP nötig | Manuelle IP-Eingabe als Pflicht-Fallback im UI; Firewall-Schritt im Runbook | `11_OPS` §3 |
| R-03 | macOS-App startet auf Apple Silicon gar nicht, weil der Plist-Patch die Signatur zerstört hat | S2 fällt aus, Fehlerbild sieht aus wie „Spiel kaputt" | **Ad-hoc-Signatur im Build verpflichtend** (ADR-012) + `codesign --verify` als Abbruchbedingung; dokumentierter Rechtsklick-Weg | `06_BUILD` §4 |
| R-04 | Refactoring M0 bricht das gute Spielgefühl | Kernwert des Projekts zerstört | Physik-Regressionstest gegen aufgezeichnete Referenz-Rallyes vor dem Umbau | `07_TEST_PLAN` §2 |
| R-05 | Assets mit unklarer Herkunft landen im öffentlichen Repo und bleiben in der Git-Historie | Lizenzverstoß, History-Rewrite nötig | Name entschieden (ADR-010); `assets/CREDITS.md` und prozeduraler Fallback **vor** dem ersten Push | `10_LEGAL` §4, `12_OPENSOURCE_REPO` §4 |
| R-06 | Scope Creep über Mutatoren/Modi, Netcode wird nie fertig | Projekt bleibt ewiger Prototyp | Mutatoren komplett nach M6; Charter §4 ist bindend | `08_ROADMAP` |
| R-07 | Turnier-Host stürzt mitten im Turnier ab | Abend ist tot, sozialer Schaden | Turnierzustand nach jedem Match auf Platte; Host-Recovery beim Neustart | `05_TOURNAMENT` §7 |

## 8. Nicht-Ziele im Sinne der Haltung

Das Spiel soll sich **nicht modernisieren**. Kein Progression-System, keine Unlocks, keine Cosmetics, kein Accountzwang. Der gesamte Wert liegt in: sofort spielbar, sofort verstanden, sofort wieder vergessen bis zur nächsten Party. Jede Funktion, die eine Erklärung braucht, ist im Verdacht.

## 9. Freigabe

| Rolle | Name | Freigabe |
|-------|------|----------|
| Product Owner / Design / Dev | Roberto | ☐ |

**Angenommene Annahmen (bitte prüfen):**
- A1: Die LAN-Party hat ein gemeinsames L2-Segment (ein Switch bzw. ein WLAN-AP), kein Routing zwischen Subnetzen. Broadcast-Discovery hängt daran.
- A2: Zielgröße variabel, Auslegungspunkt 20 Teilnehmer (Q-03 entschieden, ADR-013). Daraus folgt: 3–4 parallele Matches sind Pflicht, nicht Ausbau.
- A3: Es gibt keinen dedizierten Server-Rechner; der Turnier-Host ist ein Spieler-Laptop.
- A4: Linux ist nicht Zielplattform für v1.0 (fällt bei LÖVE quasi kostenlos als `.love`/AppImage ab, wird aber nicht getestet).
