# Credits — Herkunft und Lizenz jeder Assetdatei

**Stand:** 2026-08-12 · **Bezug:** `10_LEGAL_ASSETS_NAMING.md` §4, ADR-011, M1-09
**Vollständigkeitsanspruch:** Jede `.png`, `.wav` und `.ogg` in diesem Repository steht hier.
Was hier nicht steht, gehört nicht ins Repository.

---

## Grundsatz

Alle Assets stammen von **r0btoshi** und stehen unter derselben Lizenz wie der Code
(zlib, siehe `LICENSE`). Es wurde **kein Material aus Blobby Volley oder Blobby Volley 2**
übernommen — weder Grafik noch Klang noch Code. Zur Abgrenzung siehe `docs/references.md`.

Kein Asset ist funktional notwendig. Fehlt eine Datei, zeichnet das Spiel prozedural
weiter und bleibt still, wo ein Klang fehlte (`src/app/assets.lua`, `ASSET_INVENTORY` §3).

---

## Bilder

| Datei | Größe | Maße | Verwendung |
|---|---|---|---|
| `bg.png` | 1,7 MB | 1448 × 1086 | Hintergrund, wird auf 800 × 600 gezeichnet |
| `blob.png` | 84 kB | 496 × 271 | Spielfigur, zur Laufzeit eingefärbt |
| `ball.png` | 119 kB | 304 × 310 | Ball |
| `icon.png` | 82 kB | 512 × 512 | Fenster- und Programmsymbol |

`icon.png` ist aus `blob.png` und `ball.png` zusammengesetzt und teilt deren Herkunft.
Die 256er-Fassung für das EXE-Symbol liegt als `dist/icon-256.png`.

**Zur Historie von `bg.png`:** Die Datei hieß bis M1-09 `bg.jpg`, war aber schon immer ein
PNG (`ASSET_INVENTORY` §4). Sie lag in 2752 × 1536 vor und belegte rund 16 MB
Texturspeicher; seit M1-09 wird eine verkleinerte Fassung ausgeliefert. Die aktuelle stammt
vom 2026-08-12 und belegt 6,0 MB Texturspeicher. Alle früheren Fassungen bleiben in der
Git-Historie.

## Klänge

Acht WAV-Dateien, 44,1 kHz / 16 Bit / Stereo, zuletzt mit FFmpeg geschrieben.

| Datei | Größe | Ereignis |
|---|---|---|
| `jump.wav` | 92 kB | Absprung |
| `dash.wav` | 92 kB | Dash |
| `hit_blob.wav` | 154 kB | Ball trifft Spielfigur |
| `hit_sand.wav` | 154 kB | Ball trifft Boden |
| `hit_net.wav` | 154 kB | Ball trifft Netz |
| `hit_wall.wav` | 154 kB | Ball trifft Seitenwand |
| `whistle.wav` | 154 kB | Anpfiff und Punktpfiff |
| `whistle_end.wav` | 307 kB | Satzende |

## Musik

Sieben Titel, Ogg Vorbis, zusammen rund 14 MB. Sie werden gestreamt, nicht in den Speicher
geladen. Herkunft wie oben: von r0btoshi, zlib.

| Datei | Größe | Liste |
|---|---|---|
| `music/menu/Volley-Dash.ogg` | 2,0 MB | Menü |
| `music/match/Volley-Dash-Match-Day.ogg` | 1,2 MB | Match |
| `music/match/Volley-Dash-Match-Day-2.ogg` | 2,5 MB | Match |
| `music/match/Volley-Dash-Match-Day-3.ogg` | 2,8 MB | Match |
| `music/match/Volley-Dash-Match-Day-4.ogg` | 2,1 MB | Match |
| `music/match/Volley-Dash-Match-Day-5.ogg` | 0,9 MB | Match |
| `music/match/Volley-Dash-Match-Day-6.ogg` | 2,5 MB | Match |

## Schriften

Keine. Das Spiel benutzt ausschließlich die in LÖVE eingebaute Schrift
(`love.graphics.newFont` ohne Dateiangabe, siehe `src/app/assets.lua`). Damit gibt es
keine Schriftlizenz zu klären.

## Für Nachnutzer

Die zlib-Lizenz erlaubt Weiterverwendung und Veränderung, auch kommerziell, solange die
Herkunft nicht falsch dargestellt wird. Wer diese Dateien in einem eigenen Projekt nutzt,
muss sie nicht nennen — schön wäre es trotzdem.
