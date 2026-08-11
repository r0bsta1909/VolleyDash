# 10 — Lizenzen, Assets, Naming

**Version:** 1.0 · **Stand:** 2026-08-11

> **Hinweis:** Ich bin kein Anwalt. Dieses Dokument fasst recherchierte Fakten zu Lizenzen zusammen und leitet daraus praktische Handlungsempfehlungen ab. Für eine verbindliche Bewertung — insbesondere zu Marken- und Titelschutz — wäre eine anwaltliche Prüfung nötig, die sich erst lohnt, wenn das Spiel öffentlich verteilt wird (Q-04).

---

## 1. Lizenzlage der beteiligten Software

| Komponente | Lizenz | Pflichten für dich |
|------------|--------|--------------------|
| **LÖVE 11.5** | zlib | <cite index="38-1">Die `license.txt` aus dem LÖVE-Download muss jeder Weiterverteilung beiliegen.</cite> Sonst keine Einschränkungen — auch kommerzielle Nutzung ist erlaubt |
| ENet (über lua-enet) | MIT | Copyright-Hinweis mitliefern (steckt in LÖVEs `license.txt`) |
| LuaSocket | MIT | dito |
| LuaJIT | MIT | dito |
| SDL2, OpenAL, mpg123 | zlib / LGPL / LGPL | Bei dynamischer Verlinkung (LÖVE liefert DLLs separat) erfüllt. **Deshalb DLLs nie in die EXE einbetten** |
| `json.lua` (falls verwendet) | MIT | Header-Kommentar erhalten |

**Praktische Konsequenz:** Es reicht, `license.txt` aus dem LÖVE-Download unverändert beizulegen — was `06_BUILD` §3 ohnehin als Pflichtschritt führt.

## 2. Abgrenzung zu Blobby Volley 1 und 2 — der wichtige Teil

| Ursprung | Status | Was du tun darfst | Was nicht |
|----------|--------|-------------------|-----------|
| **Blobby Volley 1** (2000, Skoraszewsky/Mummert) | <cite index="47-1">Version 1.0 wurde im November 2000 als Freeware für Windows veröffentlicht.</cite> Freeware, kein offener Quellcode | Regeln und Spielprinzip nachbauen | Assets (Grafiken, Sounds) entnehmen |
| **Blobby Volley 2** (2007–2014) | <cite index="47-1">Seit 2007 auf SourceForge unter GPLv2, offizielle Fortsetzung, in C++ statt Delphi geschrieben, basierend auf den Original-Assets.</cite> | Quellcode **lesen und daraus lernen** | Quellcode **kopieren oder übersetzen** — auch nicht zeilenweise nach Lua. Assets verwenden |

### Warum die GPL hier praktisch relevant ist

GPLv2 ist eine Copyleft-Lizenz: Wer abgeleiteten Code verbreitet, muss das Gesamtwerk unter GPLv2 stellen und den Quellcode offenlegen. Eine Lua-Übersetzung der C++-Physik aus Blobby Volley 2 wäre eine Bearbeitung.

**Handlungsregel für das Projekt:**
- ✅ Die BV2-Quellen als **Referenz für Verhalten** ansehen („wie verhält sich der Ball an der Netzkante?") und das Verhalten selbst implementieren.
- ✅ Spielregeln übernehmen. Regeln sind Ideen, kein urheberrechtlich geschützter Ausdruck.
- ❌ Konstanten, Funktionsstrukturen oder Kollisionsroutinen aus BV2 übernehmen.
- ❌ `strand1.bmp`, Blob-Grafiken, Pfiff-Sounds oder sonstige Original-Assets.

**Der Prototyp ist hier bereits sauber:** Er hat eigene Konstanten (`gravity = 1000`, `blobRadius = 54` etc.), eigene Kollisionslogik und lädt eigene Assets. Das bleibt so.

**Falls du BV2-Quellen zur Verifikation heranziehst:** Dokumentiere im Repo, welche Erkenntnis du woher hast (`docs/references.md`) — im Zweifelsfall belegt das, dass Verhalten nachvollzogen und nicht Code übernommen wurde.

## 3. Naming — Entscheidung Q-01: **Volley Dash**

**Problem:** „Blobby Volley" ist ein etablierter Titel mit klarer Herkunft. Ein Spiel namens „Volley Dash" ist im Freundeskreis unproblematisch, bei öffentlicher Verteilung aber ein vermeidbares Risiko — und obendrein ehrlicher, wenn es einen eigenen Namen trägt, weil es eine eigenständige Neuimplementierung mit eigenem Netcode und Turniersystem ist.

### Optionen

| Name | Bewertung |
|------|-----------|
| **NETZKANTE** | Deutsch, prägnant, doppeldeutig (Volleyball + Netzwerk). Passt zum LAN-Fokus. Keine bekannte Kollision im Spielebereich |
| SPIKE LAN | Klar, international, aber generisch |
| BLOBS & BUMPS | Verspielt, aber führt „Blob" mit |
| KOPFBALL | Trifft die Mechanik (<cite index="53-1">die armlosen Blobs spielen den Ball mit dem „Kopf", vergleichbar mit einem Kopfball</cite>), kollidiert aber mit der ARD-Sendung |
| VOLLEYBLOB | Zu nah am Original, und es existiert bereits ein gleichnamiges Browserspiel |

**Entschieden: VOLLEY DASH** (ADR-010). *NETZKANTE war meine ursprüngliche Empfehlung; sie scheidet aus, weil der Name mit der Open-Source-Veröffentlichung außerhalb des deutschen Sprachraums nicht trägt.* Zur alten Begründung: Begründung: Die Doppelbedeutung trägt die gesamte Produktidee (Volleyballnetz + Computernetzwerk), der Name ist auf einer deutschen LAN-Party sofort verständlich, und er signalisiert Eigenständigkeit statt Klon.

**Was in jedem Fall gilt:**
- Die Figuren dürfen weiterhin „Blobs" heißen — das ist eine Gattungsbezeichnung, kein Titel.
- Im `LIESMICH.txt` und in einer Credits-Zeile: „Inspiriert von Blobby Volley (2000) von Daniel Skoraszewsky und Silvio Mummert." Das ist fair, kostet nichts und ordnet das Projekt korrekt ein.
- Vor öffentlicher Veröffentlichung: kostenlose Vorabrecherche im DPMA-Register (register.dpma.de) und im EUIPO-Register auf den gewählten Namen. Ersetzt keine anwaltliche Prüfung, filtert aber offensichtliche Kollisionen.

## 4. Eigene Assets

| Asset | Status im Prototyp | Anforderung |
|-------|--------------------|-------------|
| `blob.png` | vorhanden, Herkunft unklar | **Herkunft klären.** Wenn nicht selbst erstellt: neu zeichnen. Ein Blob ist ein Halbkreis mit Auge — 20 Minuten Arbeit |
| `ball.png` | vorhanden, Herkunft unklar | dito |
| `bg.jpg` / `bg.png` | vorhanden, Herkunft unklar | dito. Bei Stockfoto: Lizenz dokumentieren |
| Sounds (Sprung, Dash, Wand, Pfiff) | vorhanden, Herkunft unklar | Herkunft klären. Ersatz: freesound.org (CC0-Filter) oder selbst aufgenommen |
| Fonts | LÖVE-Standardfont | Bei eigenem Font: nur OFL-lizenzierte verwenden |

**⚠️ Blockierend vor dem ersten öffentlichen Push (ADR-011):** Eine `assets/CREDITS.md` anlegen, die für jedes Asset Herkunft und Lizenz nennt. Fehlt der Nachweis, wird das Asset ersetzt — **vor** dem Push, nicht danach. Eine gelöschte Datei bleibt in der Git-Historie; ein nachträglicher History-Rewrite auf einem geforkten Repo ist praktisch nicht durchführbar.

**Der elegante Weg:** Der Prototyp funktioniert bereits vollständig **ohne** externe Assets — der Zeichencode enthält Fallbacks für Blob und Ball (prozedurale Halbkreise, Augen mit Ballverfolgung). Der prozedurale Look ist charakteristisch und lizenzfrei. Es spricht viel dafür, ihn zum Standard zu machen und Bild-Assets nur optional zu unterstützen.

## 5. Veröffentlichungsmodell — Entscheidung Q-04

| Option | Lizenz für deinen Code | Aufwand | Wann sinnvoll |
|--------|------------------------|---------|---------------|
| **A: Privat** (nur Freundeskreis) | keine nötig | 0 | Für v1.0 ausreichend |
| **B: itch.io kostenlos** | zlib | + Store-Seite | Optional als Spiegel der GitHub-Releases, später |
| **C: Open Source auf GitHub** | MIT oder zlib | + README, + Contribution-Hinweise | Wenn du Beiträge willst oder das Projekt als Referenz zeigen möchtest |
| D: Kommerziell ❌ | proprietär | + Steuer, + Support, + Signatur | Der Markt für Blobby-Volley-Klone ist gesättigt und kostenlos bedient |

**Entschieden: C — Open Source auf GitHub, sofort** (ADR-011, Q-04). Ursprüngliche Empfehlung war A→C; die Direktentscheidung für C zieht §4 (Asset-Herkunft) von „Aufgabe für M1" auf **blockierend vor dem ersten Push** hoch. Begründung für C: Begründung: Das Interessante an diesem Projekt ist nicht das Gameplay (25 Jahre alt), sondern die LAN-Infrastruktur und das integrierte Turniersystem — genau das ist als offener Code für andere nützlich und als Referenzprojekt vorzeigbar. Option D scheidet aus: gegen ein kostenloses, seit 25 Jahren etabliertes Original zu verkaufen, funktioniert nicht.

**Lizenzempfehlung bei C: zlib.** Grund: Es ist dieselbe Lizenz wie LÖVE selbst — konsistent, permissiv, ohne Copyleft-Verpflichtungen für Nutzer.

## 6. Datenschutz

Nahezu kein Thema, was ein Vorteil des reinen LAN-Ansatzes ist:

- Keine Telemetrie, kein Crash-Reporting an externe Dienste, keine Accounts.
- Spielernamen liegen lokal und werden nur im LAN übertragen.
- Turnierergebnisse liegen lokal in `love.filesystem.getSaveDirectory()`.

**Einzige aktive Maßnahme:** Im `LIESMICH.txt` einen Zweizeiler, dass das Spiel keinerlei Daten ins Internet sendet und ausschließlich im lokalen Netzwerk kommuniziert. Auf einer LAN-Party fragt garantiert jemand — und ein Spiel, das UDP-Broadcasts verschickt, sollte diese Frage vorwegnehmen.

## 7. Checkliste vor der ersten Verteilung

- [ ] `license.txt` aus dem LÖVE-Download liegt beiden ZIPs bei
- [ ] `assets/CREDITS.md` vollständig, kein Asset ohne Herkunftsnachweis
- [ ] Kein Code aus Blobby Volley 2 übernommen (Selbstprüfung + `docs/references.md`)
- [ ] Name entschieden (Q-01), DPMA/EUIPO-Vorabrecherche erfolgt
- [ ] Credits-Zeile zur Inspirationsquelle im Spiel und im `LIESMICH.txt`
- [ ] Datenschutz-Zweizeiler im `LIESMICH.txt`
- [ ] `LICENSE` (zlib), `LICENSE-THIRD-PARTY.md`, `docs/references.md` im Repo — vollständige Liste in `12_OPENSOURCE_REPO_SETUP` §4
- [ ] Ad-hoc-Signatur im Build aktiv und per `codesign --verify` geprüft (ADR-012)
