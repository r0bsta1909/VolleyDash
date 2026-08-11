# 06 — Build- und Release-Pipeline

**Version:** 1.0 · **Stand:** 2026-08-11 · **Meilenstein:** M1

---

## 1. Grundprinzip

LÖVE-Distribution funktioniert über eine `.love`-Datei — <cite index="38-1">ein ZIP-Archiv des gesamten Spielverzeichnisses, bei dem `main.lua` in der Wurzel des Archivs liegen muss (nicht in einem Unterordner), anschließend von `.zip` in `.love` umbenannt.</cite> Aus dieser einen Datei entstehen alle Plattform-Artefakte.

```
Quellcode ──> game.love ──┬──> Windows: love.exe + game.love (konkateniert) + DLLs ──> ZIP
                          ├──> macOS:   love.app umbenannt, .love in Contents/Resources ──> ZIP
                          └──> Linux:   .love direkt (ungetestet, Beigabe)
```

### Fallstrick Groß-/Kleinschreibung

<cite index="38-1">Sobald das Spiel gepackt ist, wird der Dateizugriff case-sensitiv — ein häufiger Fehler sind Dateinamen, deren Schreibweise im Code von der auf der Platte abweicht; das fällt auf case-insensitiven Systemen wie Windows und macOS erst beim Test mit der erzeugten `.love`-Datei auf.</cite>

**Konsequenz für den Workflow:** Nie den Ordner testen, immer die `.love`-Datei testen. Im Prototyp lädt `loadImage("bg.jpg")` etc. — genau der Kandidat für diesen Fehler.

## 2. `conf.lua` (fehlt im Prototyp, F-07)

```lua
function love.conf(t)
    t.identity            = "VolleyDash"      -- Speicherordner
    t.version             = "11.5"           -- Pflicht: Kompatibilitätswarnung
    t.console             = false

    t.window.title        = "Volley Dash"
    t.window.width        = 1280
    t.window.height       = 960              -- 4:3 wie das logische Feld
    t.window.minwidth     = 640
    t.window.minheight    = 480
    t.window.resizable    = true
    t.window.vsync        = 1
    t.window.highdpi      = true             -- Retina-Macs

    -- Nicht benötigte Module abschalten: schnellerer Start, kleinerer Speicherbedarf
    t.modules.physics     = false            -- Box2D wird nicht verwendet
    t.modules.video       = false
    t.modules.touch       = false
    t.modules.sensor      = false
end
```

`t.version = "11.5"` ist nicht Kosmetik: LÖVE gibt bei abweichender Laufzeitversion eine Warnung aus. Ohne diesen Eintrag startet das Spiel unter einer künftigen 12.0 kommentarlos mit potenziell verändertem Verhalten.

## 3. Windows-Build

<cite index="38-1">Der Windows-Build entsteht durch Anhängen der `.love`-Datei an `love.exe`: `copy /b love.exe+SuperGame.love SuperGame.exe`; das erzeugt ein „fused game". Für die Verteilung müssen die DLLs aus demselben LÖVE-Download beiliegen (32-Bit- und 64-Bit-DLLs nicht mischen) — ohne sie bricht die EXE mit einer Fehlermeldung ab.</cite> <cite index="38-1">Auch die `license.txt` gehört zwingend in jede Weiterverteilung.</cite>

### Inhalt des Windows-ZIP

```
VolleyDash-1.0.0-win64/
├── VolleyDash.exe          ← love.exe + game.love
├── SDL2.dll
├── OpenAL32.dll
├── love.dll
├── lua51.dll
├── mpg123.dll
├── msvcp120.dll
├── msvcr120.dll
├── license.txt            ← Pflicht
└── LIESMICH.txt           ← Netzwerkhinweise, Steuerung, Firewall
```

### Build von macOS/Linux aus

<cite index="38-1">Der Windows-Build lässt sich auch von Linux oder macOS aus erzeugen: die offizielle 64-Bit-ZIP (nicht den Installer) von love2d.org laden und `cat love.exe SuperGame.love > SuperGame.exe` ausführen.</cite>

Das bedeutet: **eine Build-Maschine reicht.** Der Mac kann beide Plattformen bauen, ein Windows-Rechner kann keinen macOS-Build erzeugen. Wenn eine Maschine gewählt werden muss: Mac.

### Icon

<cite index="38-1">Ein eigenes Icon lässt sich mit Werkzeugen wie dem Freeware-Tool Resource Hacker in die EXE einsetzen.</cite> Manueller Schritt, nicht CI-tauglich — deshalb: Icon-Schritt einmalig dokumentieren und eine vorbereitete `love.exe` mit ersetztem Icon im Repo vorhalten (unter `tools/prebuilt/`).

### SmartScreen

Eine unsignierte EXE löst beim ersten Start auf fremden Rechnern die Warnung „Der Computer wurde durch Windows geschützt" aus. Ein Code-Signing-Zertifikat kostet je nach Anbieter dreistellig pro Jahr und baut erst über Zeit Reputation auf — für dieses Projekt nicht sinnvoll.

**Mitigation:** Im `LIESMICH.txt` und in der Weitergabe-Nachricht steht der Weg („Weitere Informationen" → „Trotzdem ausführen"). Zusätzlich das ZIP nicht per Chat-Anhang, sondern als Download-Link verteilen, damit die Mark-of-the-Web-Behandlung berechenbar bleibt.

## 4. macOS-Build

<cite index="38-1">Der macOS-Build entsteht durch Umbenennen von `love.app` in `SuperGame.app`, Kopieren der `.love`-Datei nach `SuperGame.app/Contents/Resources/` (was das Spiel im fused mode startet) und Anpassen von `Contents/Info.plist`.</cite> <cite index="38-1">In der `Info.plist` müssen `CFBundleIdentifier` und `CFBundleName` geändert und der Abschnitt `UTExportedTypeDeclarations` entfernt werden — letzteres verhindert, dass macOS künftig alle `.love`-Dateien mit dem eigenen Spiel verknüpft.</cite> <cite index="38-1">Beim Zippen des `.app`-Ordners muss die `-y`-Option von `zip` gesetzt werden, damit Symlinks erhalten bleiben.</cite>

**Das `-y`-Flag ist der häufigste Fehler an dieser Stelle.** Ohne es werden Symlinks in den Frameworks aufgelöst, die App verdoppelt ihre Größe und kann beim Entpacken beschädigt sein.

### Signatur und Gatekeeper — Entscheidung Q-02: **kein Apple Developer Program**

<cite index="34-1">Ein Developer-ID-Zertifikat erlaubt Gatekeeper zu erkennen, dass die App von einem vertrauenswürdigen Entwickler stammt, wenn sie außerhalb des Mac App Store geladen und geöffnet wird; zusätzliche Sicherheit entsteht durch Notarisierung, bei der Apple die signierte Software automatisch prüft und ihr ein Ticket zuweist.</cite>

Darauf wird bewusst verzichtet (ADR-012). Damit bleibt der Rechtsklick-Weg: einmalig pro Rechner Rechtsklick auf die App → „Öffnen" → Dialog bestätigen. Auf neueren macOS-Versionen zusätzlich Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen".

### ⚠️ Ad-hoc-Signatur ist trotzdem Pflicht — nicht optional

Das ist der Punkt, an dem der naive Build auf Apple Silicon **gar nicht startet**, und zwar unabhängig von Gatekeeper.

**Ursache:** Die von love2d.org geladene `love.app` ist signiert. Sobald der Build-Vorgang die `Info.plist` ändert und eine `.love`-Datei nach `Contents/Resources/` legt, ist diese Signatur ungültig. <cite index="88-1">Code, der auf Apple-Silicon-Macs nativ läuft, muss signiert sein; wer Signaturen von ARM-Binaries entfernt oder beschädigt, muss sie neu signieren — notfalls mit einem Ad-hoc-Zertifikat.</cite>

**Lösung, kostenlos und ohne Apple-Konto:** <cite index="92-1">Das absolute Minimum ist „Ad-hoc-Codesigning", im Kern nur eine Prüfsumme der ausführbaren Datei.</cite>

```bash
codesign --force --deep --sign - "$MACDIR/$NAME.app"
codesign --verify --verbose=2 "$MACDIR/$NAME.app"   # muss "valid on disk" melden
```

Dieser Schritt gehört **nach** dem Plist-Patch und **vor** dem Zippen in `build.sh`.

**Was Ad-hoc nicht leistet — ehrlich benannt:** <cite index="92-1">Ad-hoc signierter Code läuft ohne Nutzereingriff nur auf der Maschine, die ihn gebaut hat; kopiert man ihn auf einen anderen Rechner, bricht macOS den Start ab. Die App muss dort einmal per Rechtsklick im Finder geöffnet werden</cite> — dann erscheint der Dialog mit einer zusätzlichen „Öffnen"-Schaltfläche.

Der Rechtsklick-Weg bleibt also nötig. Ad-hoc verhindert nur, dass die App **überhaupt nicht** startet. Das ist der Unterschied zwischen „einmal umständlich" und „geht nicht".

**Notfall-Einzeiler für den Partyabend** (entfernt das Quarantäne-Attribut und macht den Rechtsklick-Weg überflüssig):

```
xattr -dr com.apple.quarantine /Pfad/zu/VolleyDash.app
```

Dieser Befehl gehört ins `LIESMICH.txt` — mit dem ehrlichen Hinweis, was er tut (Gatekeeper-Prüfung für genau diese App aushebeln), damit niemand ihn blind kopiert.

**Revisionsauslöser für Q-02:** Wenn nach dem ersten öffentlichen GitHub-Release mehr als eine Handvoll Rückmeldungen kommen, dass die Mac-Version „nicht startet", ist der Umweg zu hoch und die 99 USD/Jahr sind die bessere Entscheidung. Bis dahin: nein.

### Universal Binary

Der offizielle macOS-Download von love2d.org enthält seit 11.4 native arm64-Unterstützung. Die 11.5-App läuft damit auf Intel und Apple Silicon ohne Rosetta. Kein zusätzlicher Schritt nötig — aber **auf beiden Architekturen testen**, weil LuaJIT auf arm64 ohne JIT läuft und dadurch messbar langsamer ist.

## 5. Build-Skripte

### `tools/build.sh` (macOS/Linux, baut Win + Mac)

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="$(cat VERSION)"
NAME="VolleyDash"
BUILD="build"
LOVE_WIN="tools/prebuilt/love-11.5-win64"     # entpackte offizielle ZIP
LOVE_MAC="tools/prebuilt/love-11.5-macos"     # entpackte offizielle ZIP (love.app)

rm -rf "$BUILD"; mkdir -p "$BUILD"

# --- 1. Build-Hash über alle Lua-Quellen (für Netcode-Versionscheck) ---
BUILDHASH=$(find . -name '*.lua' -not -path './build/*' -not -path './tools/*' \
            | sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-16)
echo "return { version = \"$VERSION\", buildHash = \"$BUILDHASH\" }" > src/build_info.lua

# --- 2. .love erzeugen (main.lua muss in der Wurzel liegen) ---
zip -9 -r "$BUILD/$NAME.love" . \
    -x '*.git*' 'build/*' 'tools/*' 'docs/*' 'tests/*' '*.DS_Store' '*.md'

# --- 3. Windows ---
WINDIR="$BUILD/$NAME-$VERSION-win64"
mkdir -p "$WINDIR"
cat "$LOVE_WIN/love.exe" "$BUILD/$NAME.love" > "$WINDIR/$NAME.exe"
cp "$LOVE_WIN"/*.dll "$WINDIR/"
cp "$LOVE_WIN/license.txt" "$WINDIR/"
cp dist/LIESMICH_win.txt "$WINDIR/LIESMICH.txt"
( cd "$BUILD" && zip -9 -r "$NAME-$VERSION-win64.zip" "$NAME-$VERSION-win64" )

# --- 4. macOS ---
MACDIR="$BUILD/$NAME-$VERSION-macos"
mkdir -p "$MACDIR"
cp -R "$LOVE_MAC/love.app" "$MACDIR/$NAME.app"
cp "$BUILD/$NAME.love" "$MACDIR/$NAME.app/Contents/Resources/"
python3 tools/patch_plist.py "$MACDIR/$NAME.app/Contents/Info.plist" \
        --identifier "games.4brain.volleydash" \
        --name "$NAME" \
        --version "$VERSION" \
        --remove-uti

# WICHTIG: Der Plist-Patch hat die Signatur der love.app zerstört.
# Ohne erneutes Signieren startet die App auf Apple Silicon nicht.
codesign --force --deep --sign - "$MACDIR/$NAME.app"
codesign --verify --verbose=2 "$MACDIR/$NAME.app"

cp dist/LIESMICH_mac.txt "$MACDIR/LIESMICH.txt"
( cd "$MACDIR" && zip -9 -r -y "../$NAME-$VERSION-macos.zip" "$NAME.app" LIESMICH.txt )

echo "Fertig. Build-Hash: $BUILDHASH"
```

`tools/patch_plist.py` setzt `CFBundleIdentifier`, `CFBundleName`, `CFBundleShortVersionString` und entfernt `UTExportedTypeDeclarations`.

### Was bewusst nicht verwendet wird

Der LÖVE-Wiki listet Community-Werkzeuge zur Distribution, darunter <cite index="30-1">makelove (Python 3, Windows und Linux mit AppImage), boon (Windows, macOS, Linux), love-export (Kommandozeile für Windows, macOS und Linux) und love-build.</cite>

**Empfehlung: eigenes Skript.** Begründung: Der gesamte Vorgang sind 40 Zeilen Shell, es gibt einen projektspezifischen Schritt (Build-Hash-Injektion für den Netcode-Versionsabgleich), und jedes dieser Werkzeuge ist eine zusätzliche Abhängigkeit mit eigenem Wartungsrisiko. Ein 40-Zeilen-Skript, das man vollständig versteht, ist an dieser Stelle robuster als ein Werkzeug, das man einmal im Jahr benutzt.

**Ausnahme:** Falls CI gewünscht ist, ist <cite index="30-1">LÖVE Actions, das Pakete für die meisten Plattformen per GitHub Actions baut und ausliefert (Android, iOS, Linux, macOS, Windows; kein HTML5/WASM)</cite> die passende Wahl — dann als reiner CI-Wrapper, während das lokale Skript die Wahrheit bleibt.

## 6. Versionierung

**Schema: `MAJOR.MINOR.PATCH`**, zusätzlich zwei technische Kennungen:

| Kennung | Ändert sich bei | Wirkung im Netzwerk |
|---------|-----------------|---------------------|
| `version` | jedem Release | Anzeige |
| `protoVersion` | Änderung am Wire-Format | **Harte Ablehnung** beim Join |
| `buildHash` | jeder Codeänderung | **Warnung**, kein Abbruch |
| `rulesetHash` | Änderung der Simulationsparameter | **Harte Ablehnung** beim Match-Start |

Diese Trennung ist der Grund, warum am Partyabend niemand rätselt, warum eine Verbindung scheitert: Jeder Fehlerfall hat eine eigene Klartextmeldung.

## 7. Verteilung an die Gäste

| Weg | Bewertung |
|-----|-----------|
| **Lokaler HTTP-Server im LAN** (`python3 -m http.server`), QR-Code am Beamer | **Empfohlen.** Kein Internet nötig, schnellste Verteilung, funktioniert auch wenn die Party-Leitung schlecht ist |
| USB-Stick | Fallback, funktioniert immer |
| **GitHub Releases** | Öffentlicher Kanal (Q-04). Am Partyabend aber nur Fallback — hängt an der Internetleitung. Details in `12_OPENSOURCE_REPO_SETUP` |
| itch.io | Optional zusätzlich, spiegelt nur die GitHub-Releases |
| Chat-Anhang (Discord, WhatsApp) | Vermeiden: Größenlimits, Umbenennungen, zusätzliche Sicherheitswarnungen |

## 8. Abnahmekriterien M1

1. `./tools/build.sh` erzeugt beide ZIPs ohne manuelle Schritte.
2. Windows-ZIP läuft auf einem frisch aufgesetzten Windows 11 ohne Installation.
3. macOS-ZIP läuft auf Intel-Mac **und** Apple-Silicon-Mac — getestet auf einem **fremden** Mac, nicht auf der Build-Maschine (Ad-hoc-Signaturen verhalten sich dort unterschiedlich).
3b. `codesign --verify` meldet für die gebaute `.app` „valid on disk".
4. Der Gatekeeper-Weg ist im `LIESMICH.txt` beschrieben und von einer nicht-technischen Testperson ohne Rückfrage durchführbar.
5. Die `.love`-Datei (nicht der Quellordner) wurde getestet — Case-Sensitivity-Fehler ausgeschlossen.
6. `license.txt` liegt beiden Paketen bei.
7. Startzeit bis Hauptmenü < 3 s auf der ältesten verfügbaren Testmaschine.
