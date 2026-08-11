# Asset-Inventar

**Version:** 1.0 · **Stand:** 2026-08-11 · **Erhoben in:** CC-01 (M0-03), AP-2
**Bezug:** `10_LEGAL_ASSETS_NAMING.md` §4, Risiko R-05, ADR-011, M1-09

---

## 1. Status

Alle Assetdateien liegen im **Wurzelverzeichnis** des Repos, nicht in einem `assets/`-Ordner.
Sie sind seit dem ersten Commit über `.gitignore` ausgeschlossen (`/*.png`, `/*.jpg`,
`/*.ogg`, `/*.wav`) und stehen **nicht** in der Git-Historie. Der Ausschluss bleibt bis
M1-09 bestehen.

**Die Spalte „Herkunft" ist nicht geraten.** Wo unten `UNBEKANNT` steht, ist die Herkunft
tatsächlich ungeklärt und von Roberto zu beantworten. Wo eine Angabe steht, stammt sie aus
den Metadaten der Datei selbst und ist überprüfbar (Abschnitt 4).

---

## 2. Tabelle

Es sind **11 Dateien** (das Handoff CC-01 spricht von zehn, listet aber elf auf).
Größe in Bytes, Hash über den vollständigen Dateiinhalt.

| Datei | Typ (tatsächlich) | Größe | SHA-256 | Verwendung in `main.lua` | Herkunft | Entscheidung |
|---|---|---|---|---|---|---|
| `bg.jpg` | **PNG**, 2752×1536 | 5 040 745 | `93ec97833eb6170c49355d63abe23b91da8fd0fb9e6926513a510ccbd8304371` | Laden `395`, Zeichnen `948–950` | **Google Generative AI**, C2PA-signiert 2026-08-10, SynthID-Wasserzeichen (siehe §4) | offen — Nutzungsbedingungen des erzeugenden Dienstes klären, Datei zusätzlich technisch ungeeignet (§5) |
| `blob.png` | PNG, 496×271 | 84 652 | `3eea4065258b7f2fd73a293dfb583733548dce1533822503bfc2eced146bc2e4` | Laden `396`, Zeichnen `1149–1155` | UNBEKANNT — von Roberto zu klären | offen |
| `ball.png` | PNG, 304×310 | 118 979 | `9ac53e09778e6f22817a47e5bfec349b6ee9775b5540994f65592fc3e91889cd` | Laden `397`, Zeichnen `1014–1017` | UNBEKANNT — von Roberto zu klären | offen |
| `jump.wav` | WAV (PCM) | 92 238 | `7f09623279477abe4e990d42b65dcc918268fa141a63b3fda92ec7910bf6e2c0` | Laden `405`, Abspielen `567`, `919`, `928` | UNBEKANNT — von Roberto zu klären | offen |
| `dash.wav` | WAV (PCM) | 92 238 | `2a87e88c216b452e731f91be20f67e04903f9d79b720ddb1c69a35233eea8c74` | Laden `406`, Abspielen `576`, `820`, `827`, `834` | UNBEKANNT — von Roberto zu klären | offen |
| `hit_blob.wav` | WAV (PCM) | 153 678 | `fe7370983260c1b1974adf7256524400336d348c04107b5b311ef893694ad58e` | Laden `407`, Abspielen `701` | UNBEKANNT — von Roberto zu klären | offen |
| `hit_sand.wav` | WAV (PCM) | 153 678 | `98ce5a300646ff451e38c5d43ab72f169bbf05127cab0b5937a94e44a0bd5244` | Laden `408`, Abspielen `633` | UNBEKANNT — von Roberto zu klären | offen |
| `hit_net.wav` | WAV (PCM) | 153 678 | `73d347a2f2391d0d5f3799e4ba35fbdae8037f364c77b86fdfb4e4d672792dbf` | Laden `409`, Abspielen `782`, `801` | UNBEKANNT — von Roberto zu klären | offen |
| `hit_wall.wav` | WAV (PCM) | 153 678 | `e332b47ba2282247a9f99269bb94a28304f895a949c967f042889e84adf3eb07` | Laden `410`, Abspielen `612`, `616` | UNBEKANNT — von Roberto zu klären | offen |
| `whistle.wav` | WAV (PCM) | 153 678 | `e237a3f0d6c4ddba1cbe8078292af124321292016a3cafc81ff0db2e1dbc89ae` | Laden `411`, Abspielen `491`, `495` | UNBEKANNT — von Roberto zu klären | offen |
| `whistle_end.wav` | WAV (PCM) | 307 278 | `f66485ccd047edce4b32353dd6020b0a89f02c1edfbbf8a9eae1fab95730fa9b` | Laden `412`, Abspielen `489` | UNBEKANNT — von Roberto zu klären | offen |

Zeilennummern beziehen sich auf `main.lua` nach der Namensbereinigung (Tag
`prototype-baseline`).

---

## 3. Funktional notwendig vs. dekorativ

**Keine einzige dieser Dateien ist funktional notwendig.** Der Prototyp hat vollständige
`nil`-Absicherungen:

- `loadImage` (`main.lua:391–394`) und `loadSound` (`399–404`) geben `nil` zurück, wenn die
  Datei fehlt — sie werfen keinen Fehler.
- Jede Zeichenstelle prüft: `assets.bg` (`948`), `assets.ball` (`1014`), `assets.blob` (`1149`).
  Jede hat einen prozeduralen Zweig.
- `playSound` (`376–382`) prüft das Argument auf `nil` und tut sonst nichts.
- `main.lua:422` setzt bei fehlendem `ball.png` sogar eine Ersatzfarbe.

| Datei | Rolle | Ohne die Datei |
|---|---|---|
| `bg.jpg` | dekorativ | Blauer Hintergrund + sandfarbener Boden (`951–955`) |
| `blob.png` | dekorativ | Prozedural gezeichneter Blob (`1149 ff.`, else-Zweig) |
| `ball.png` | dekorativ | Prozedural gezeichneter Ball in `{0.98, 0.85, 0.12}` (`422`, `1018 ff.`) |
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

**`bg.jpg` trägt ein signiertes C2PA-Manifest.** Auslesbar im Klartext:

- `c2pa.actions.v2` → `c2pa.created`, Beschreibung: *„Created by Google Generative AI."*
- `digitalSourceType`: `http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia`
- zweite Aktion `c2pa.edited`: *„Applied imperceptible SynthID watermark."*
- Signaturkette: *Google C2PA Media Services 1P ICA G3* → *Google C2PA Root CA G3*,
  Zeitstempel **2026-08-10 19:54:43 UTC** (Dateidatum 2026-08-10 passt dazu).

Die Datei ist damit **KI-generiert**, nicht fotografiert und nicht aus einer Stock-Bibliothek.
Das Handoff vermutete ein Foto oder Stock-Bild — das ist widerlegt.

**`blob.png` und `ball.png`** enthalten nur einen leeren XMP-Rumpf (`XMP Core 6.0.0`) und
einen 80-Byte-`eXIf`-Block, keinen Erzeuger, keinen Urheber, kein C2PA. Herkunft bleibt
offen.

**Die acht `.wav`** enthalten einen `LIST/INFO/ISFT`-Eintrag `Lavf59.27.100` — sie wurden
mit **FFmpeg** (libavformat 59.27.100, FFmpeg 5.1.x) geschrieben. Das sagt nur, womit die
Datei zuletzt konvertiert wurde, **nichts** über die Quelle des Klangs.

**Kein Hinweis auf Blobby Volley oder Blobby Volley 2.** Keine Datei trägt einen Namen,
eine Signatur oder ein Metadatum aus diesen Projekten. Die Stop-Regel aus AP-2 des Handoffs
ist damit nicht ausgelöst; die GPLv2-Frage stellt sich nach jetzigem Stand nicht.

**Fünf `.wav` haben identische Dateigröße** (153 678 Bytes), sind aber **nicht** identisch —
die SHA-256 unterscheiden sich. Gleiche Länge und gleiches Format (rund 0,87 s bei
44,1 kHz/16 Bit/Stereo), unterschiedlicher Inhalt.

---

## 5. Technische Nebenbefunde

- **`bg.jpg` ist mit 4,9 MB das mit Abstand größte Artefakt des Projekts.** Bei 2752×1536
  wird es in `main.lua:950` auf 800×600 skaliert gezeichnet, also auf rund ein Achtel der
  Fläche. Es belegt beim Laden als unkomprimierte Textur etwa 2752 × 1536 × 4 B ≈ **16 MB
  VRAM**. Das Startzeitziel < 3 s und das RAM-Ziel < 150 MB auf 2015er-Hardware
  (`CLAUDE.md` §7) stehen dazu in Spannung. Unabhängig von der Lizenzfrage gehört das Bild
  auf Zielauflösung verkleinert.
- Das C2PA-Manifest wandert mit der Datei mit. Wird `bg.jpg` je committet, steht die
  Signaturkette samt Zeitstempel dauerhaft in der Historie eines öffentlichen Repos.

---

## 6. Was Roberto entscheiden muss

1. **Herkunft der neun Dateien mit `UNBEKANNT`** (`blob.png`, `ball.png`, acht `.wav`):
   selbst erstellt, aus einer Bibliothek, KI-generiert, oder gefunden? Ohne Antwort bleiben
   sie bis M1-09 ausgeschlossen.
2. **`bg.jpg`:** Nutzungsbedingungen des erzeugenden Google-Dienstes prüfen — insbesondere,
   ob die Ausgabe unter zlib weiterverteilt werden darf. Unabhängig davon: verkleinern und
   korrekt als `.png` benennen, oder durch den prozeduralen Hintergrund ersetzen.
3. **Grundsatz für v1.0:** prozeduraler Fallback als Standard (Empfehlung aus `10_LEGAL` §4)
   und Assets als optionales Zusatzpaket, oder geklärte Assets ins Repo. Ersteres ist
   billiger und sofort belegbar, weil der Fallback bereits funktioniert.
