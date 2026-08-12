# Asset-Inventar

**Version:** 1.0 · **Stand:** 2026-08-11 · **Erhoben in:** CC-01 (M0-03), AP-2
**Bezug:** `10_LEGAL_ASSETS_NAMING.md` §4, Risiko R-05, ADR-011, M1-09

---

## 1. Status

Alle Assetdateien liegen im **Wurzelverzeichnis** des Repos, nicht in einem `assets/`-Ordner.

**Herkunft geklärt (r0btoshi, 2026-08-11): alle elf Dateien stammen von ihm.** Damit ist
Risiko R-05 erledigt und die Bedingung aus `CLAUDE.md` §11 für den ersten Push erfüllt.
Die Dateien waren bis dahin über `.gitignore` ausgeschlossen; seit dieser Session sind sie
im Repo. Was bleibt, ist rein technisch (Abschnitt 5) und gehört nach M1-09.

---

## 2. Tabelle

Es sind **11 Dateien** (das Handoff CC-01 spricht von zehn, listet aber elf auf).
Größe in Bytes, Hash über den vollständigen Dateiinhalt.

| Datei | Typ (tatsächlich) | Größe | SHA-256 | Verwendung in `main.lua` | Herkunft | Entscheidung |
|---|---|---|---|---|---|---|
| `bg.jpg` | **PNG**, 2752×1536 | 5 040 745 | `93ec97833eb6170c49355d63abe23b91da8fd0fb9e6926513a510ccbd8304371` | Laden `438`, Zeichnen `996–998` | r0btoshi, bestätigt 2026-08-11 | im Repo; verkleinern und korrekt benennen in M1-09 (§5) |
| `blob.png` | PNG, 496×271 | 84 652 | `3eea4065258b7f2fd73a293dfb583733548dce1533822503bfc2eced146bc2e4` | Laden `439`, Zeichnen `1197–1203` | r0btoshi, bestätigt 2026-08-11 | im Repo |
| `ball.png` | PNG, 304×310 | 118 979 | `9ac53e09778e6f22817a47e5bfec349b6ee9775b5540994f65592fc3e91889cd` | Laden `440`, Zeichnen `1062–1065` | r0btoshi, bestätigt 2026-08-11 | im Repo |
| `jump.wav` | WAV (PCM) | 92 238 | `7f09623279477abe4e990d42b65dcc918268fa141a63b3fda92ec7910bf6e2c0` | Laden `448`, Abspielen `615`, `967`, `976` | r0btoshi, bestätigt 2026-08-11 | im Repo |
| `dash.wav` | WAV (PCM) | 92 238 | `2a87e88c216b452e731f91be20f67e04903f9d79b720ddb1c69a35233eea8c74` | Laden `449`, Abspielen `624`, `868`, `875`, `882` | r0btoshi, bestätigt 2026-08-11 | im Repo |
| `hit_blob.wav` | WAV (PCM) | 153 678 | `fe7370983260c1b1974adf7256524400336d348c04107b5b311ef893694ad58e` | Laden `450`, Abspielen `749` | r0btoshi, bestätigt 2026-08-11 | im Repo |
| `hit_sand.wav` | WAV (PCM) | 153 678 | `98ce5a300646ff451e38c5d43ab72f169bbf05127cab0b5937a94e44a0bd5244` | Laden `451`, Abspielen `681` | r0btoshi, bestätigt 2026-08-11 | im Repo |
| `hit_net.wav` | WAV (PCM) | 153 678 | `73d347a2f2391d0d5f3799e4ba35fbdae8037f364c77b86fdfb4e4d672792dbf` | Laden `452`, Abspielen `830`, `849` | r0btoshi, bestätigt 2026-08-11 | im Repo |
| `hit_wall.wav` | WAV (PCM) | 153 678 | `e332b47ba2282247a9f99269bb94a28304f895a949c967f042889e84adf3eb07` | Laden `453`, Abspielen `660`, `664` | r0btoshi, bestätigt 2026-08-11 | im Repo |
| `whistle.wav` | WAV (PCM) | 153 678 | `e237a3f0d6c4ddba1cbe8078292af124321292016a3cafc81ff0db2e1dbc89ae` | Laden `454`, Abspielen `538`, `542` | r0btoshi, bestätigt 2026-08-11 | im Repo |
| `whistle_end.wav` | WAV (PCM) | 307 278 | `f66485ccd047edce4b32353dd6020b0a89f02c1edfbbf8a9eae1fab95730fa9b` | Laden `455`, Abspielen `536` | r0btoshi, bestätigt 2026-08-11 | im Repo |

Zeilennummern beziehen sich auf `main.lua` im Stand von CC-01 (nach dem
Aufzeichnungs-Shim). Sie verschieben sich mit M0-04 ff.

---

## 3. Funktional notwendig vs. dekorativ

**Keine einzige dieser Dateien ist funktional notwendig.** Der Prototyp hat vollständige
`nil`-Absicherungen:

- `loadImage` (`main.lua:434–437`) und `loadSound` (`442–447`) geben `nil` zurück, wenn die
  Datei fehlt — sie werfen keinen Fehler.
- Jede Zeichenstelle prüft: `assets.bg` (`996`), `assets.ball` (`1062`), `assets.blob` (`1197`).
  Jede hat einen prozeduralen Zweig.
- `playSound` (`411–417`) prüft das Argument auf `nil` und tut sonst nichts.
- `main.lua:465` setzt bei fehlendem `ball.png` sogar eine Ersatzfarbe.

| Datei | Rolle | Ohne die Datei |
|---|---|---|
| `bg.jpg` | dekorativ | Blauer Hintergrund + sandfarbener Boden (`999–1003`) |
| `blob.png` | dekorativ | Prozedural gezeichneter Blob (`1197 ff.`, else-Zweig) |
| `ball.png` | dekorativ | Prozedural gezeichneter Ball in `{0.98, 0.85, 0.12}` (`465`, `1066 ff.`) |
| alle acht `.wav` | dekorativ | Stille |

**Konsequenz für M1-09:** Der prozedurale Fallback aus `10_LEGAL` §4 existiert de facto
bereits und ist getestet, sobald die Dateien fehlen. Die Assets aus dem Repo herauszuhalten
macht das Spiel nicht unspielbar. Das entschärft R-05 erheblich.

---

## 4. Befunde aus den Metadaten

Erhoben aus den Dateiköpfen, nicht aus Vermutungen.

**`bg.jpg` ist keine JPEG-Datei.** Die Magic Bytes sind `89 50 4E 47 0D 0A 1A 0A` — ein PNG
mit falscher Endung. LÖVE erkennt das Format am Inhalt, deshalb lädt die Datei trotzdem.
Für den Build ist die Endung dennoch irreführend.

**`bg.jpg` trägt ein C2PA-Manifest** (Content Credentials, signiert 2026-08-10, mit
SynthID-Vermerk). Für die Lizenzfrage ohne Belang — die Herkunft ist geklärt. Relevant
bleibt nur, dass das Manifest rund 40 kB der Datei ausmacht und beim Commit dauerhaft in
der Historie eines öffentlichen Repos landet.

**`blob.png` und `ball.png`** enthalten einen leeren XMP-Rumpf (`XMP Core 6.0.0`) und einen
80-Byte-`eXIf`-Block.

**Die acht `.wav`** enthalten einen `LIST/INFO/ISFT`-Eintrag `Lavf59.27.100` — sie wurden
mit **FFmpeg** (libavformat 59.27.100, FFmpeg 5.1.x) geschrieben. Das sagt nur, womit die
Datei zuletzt konvertiert wurde, **nichts** über die Quelle des Klangs.

**Kein Hinweis auf Blobby Volley oder Blobby Volley 2.** Keine Datei trägt einen Namen,
eine Signatur oder ein Metadatum aus diesen Projekten.

**Fünf `.wav` haben identische Dateigröße** (153 678 Bytes), sind aber **nicht** identisch —
die SHA-256 unterscheiden sich. Gleiche Länge und gleiches Format (rund 0,87 s bei
44,1 kHz/16 Bit/Stereo), unterschiedlicher Inhalt.

---

## 5. Technische Nebenbefunde

- **`bg.jpg` ist mit 4,9 MB das mit Abstand größte Artefakt des Projekts.** Bei 2752×1536
  wird es in `main.lua:998` auf 800×600 skaliert gezeichnet, also auf rund ein Achtel der
  Fläche. Es belegt beim Laden als unkomprimierte Textur etwa 2752 × 1536 × 4 B ≈ **16 MB
  VRAM**. Das Startzeitziel < 3 s und das RAM-Ziel < 150 MB auf 2015er-Hardware
  (`CLAUDE.md` §7) stehen dazu in Spannung. Unabhängig von der Lizenzfrage gehört das Bild
  auf Zielauflösung verkleinert.
- Die Endung `.jpg` bei PNG-Inhalt ist für den Build irreführend und gehört korrigiert.

---

## 6. Erledigt in M1-09 (2026-08-12)

Alle drei Punkte sind abgearbeitet:

1. **`bg.jpg` → `assets/bg.png`, 2752 × 1536 → 1600 × 1200.** Aus 5 040 745 Bytes wurden
   1 642 578 — rund 3,4 MB weniger im Paket, und der Texturspeicher fällt von etwa 16 MB
   auf 7,7 MB. 1600 × 1200 ist die doppelte Auflösung dessen, was das Spiel zeigt: der
   Hintergrund wird ohnehin auf 800 × 600 gezerrt (`src/render/game_view.lua:76`), das
   Seitenverhältnis der Quelle war nie maßgeblich.
   Verkleinert mit LÖVE selbst (Canvas → `ImageData:encode`), um keine Bildbibliothek als
   Abhängigkeit aufzunehmen. Das C2PA-Manifest der Ursprungsdatei ist damit aus der
   ausgelieferten Fassung verschwunden — **in der Git-Historie bleibt es**.
2. **`assets/CREDITS.md` angelegt.** Enthält die elf Dateien, das neue `icon.png` und die
   sieben Musiktitel. Herkunft für alle: r0btoshi, Lizenz zlib.
3. **Umzug nach `assets/` durchgeführt.** Die Ladepfade stehen jetzt an genau einer Stelle
   (`Assets.DIR` in `src/app/assets.lua`). `music/` bleibt in der Wurzel, weil
   `src/app/music.lua` die Ordner `music/menu` und `music/match` abtastet.

**Neu hinzugekommen:** `assets/icon.png` (512 × 512) als Fenstersymbol und
`dist/icon-256.png` als Vorlage für das EXE-Symbol. Beide sind aus `blob.png` und
`ball.png` zusammengesetzt und teilen deren Herkunft.

**Musik:** sieben `.ogg` unter `music/`, rund 14 MB, seit 2026-08-11 im Repo. Herkunft
bestätigt (r0btoshi, 2026-08-12), Lizenz zlib. Damit ist die Bedingung aus `music/README.md`
erfüllt und die Musik darf mit ausgeliefert werden.
