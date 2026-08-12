#!/usr/bin/env bash
# =============================================================================
# tools/build.sh -- erzeugt die .love und daraus die Plattformpakete (M1-01 ff.)
#
# Vorlage: `docs/06_BUILD_RELEASE_PIPELINE.md` §5. Aufruf aus dem
# Wurzelverzeichnis des Repos:
#
#     ./tools/build.sh              # alles, was auf dieser Maschine geht
#     ./tools/build.sh love         # nur die .love
#     ./tools/build.sh win          # .love + Windows-Paket
#     ./tools/build.sh mac          # .love + macOS-Paket (nur auf macOS)
#
# Umgebungsvariablen (nichts davon ist hartcodiert, CLAUDE.md §8):
#   LOVE_WIN   entpackte offizielle LOEVE-win64-ZIP  (Vorgabe: tools/prebuilt/love-11.5-win64)
#   LOVE_MAC   entpackte offizielle LOEVE-macOS-ZIP  (Vorgabe: tools/prebuilt/love-11.5-macos)
#   ZIP_BIN    Info-ZIP, falls nicht im PATH
#   PYTHON     Python 3, falls nicht als python3 im PATH
#
# Windows/Git-Bash: `zip` ist dort nicht eingebaut. Info-ZIP 3.0 nachruesten mit
#   winget install --id GnuWin32.Zip --exact --source winget
# und den Pfad in den PATH aufnehmen (oder ZIP_BIN setzen).
# =============================================================================
set -euo pipefail

NAME="VolleyDash"
IDENTIFIER="games.4brain.volleydash"
BUILD="build"

cd "$(dirname "$0")/.."   # ab hier gilt: Arbeitsverzeichnis ist die Repo-Wurzel

[ -f VERSION ] || { echo "FEHLER: VERSION fehlt" >&2; exit 1; }
VERSION="$(tr -d ' \t\r\n' < VERSION)"

TARGET="${1:-all}"

# --- Werkzeuge finden -------------------------------------------------------
# Auf dieser Maschine ist `python3` der Store-Platzhalter und `python` der
# echte Interpreter; auf Linux und macOS ist es umgekehrt. Deshalb suchen.
find_python() {
    if [ -n "${PYTHON:-}" ]; then echo "$PYTHON"; return; fi
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1 &&
           "$candidate" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' 2>/dev/null; then
            echo "$candidate"; return
        fi
    done
    echo ""
}

find_zip() {
    if [ -n "${ZIP_BIN:-}" ]; then echo "$ZIP_BIN"; return; fi
    if command -v zip >/dev/null 2>&1; then echo "zip"; return; fi
    # Uebliche Ablage unter Windows, wenn winget GnuWin32 installiert hat
    for candidate in "/c/Program Files (x86)/GnuWin32/bin/zip.exe" "/c/Program Files/GnuWin32/bin/zip.exe"; do
        [ -x "$candidate" ] && { echo "$candidate"; return; }
    done
    echo ""
}

hash_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum
    else shasum -a 256
    fi
}

ZIP="$(find_zip)"
if [ -z "$ZIP" ]; then
    echo "FEHLER: kein zip gefunden. Unter Windows:" >&2
    echo "  winget install --id GnuWin32.Zip --exact --source winget" >&2
    echo "  export PATH=\"\$PATH:/c/Program Files (x86)/GnuWin32/bin\"" >&2
    exit 1
fi

PY="$(find_python)"

echo "Volley Dash $VERSION"
echo "  zip:    $ZIP"
echo "  python: ${PY:-(keiner gefunden)}"
echo

rm -rf "$BUILD"
mkdir -p "$BUILD"

# --- 1. Build-Hash ueber alle Lua-Quellen -----------------------------------
# Geht dem Erzeugen von build_info_gen.lua voraus, sonst haengt der Hash von
# sich selbst ab. Der Hash dient ab M2 dem Versionsabgleich im Netz
# (`06_BUILD` §6): Abweichung ist eine Warnung, kein Abbruch.
rm -f src/build_info_gen.lua
BUILDHASH=$(find . -name '*.lua' \
                -not -path './build/*' \
                -not -path './tools/*' \
                -not -path './.git/*' \
            | sort | xargs cat | hash_stdin | cut -c1-16)

cat > src/build_info_gen.lua <<EOF
-- Erzeugt von tools/build.sh -- nicht von Hand aendern, nicht committen.
return { version = "$VERSION", buildHash = "$BUILDHASH" }
EOF

echo "Build-Hash: $BUILDHASH"

# --- 2. .love erzeugen ------------------------------------------------------
# main.lua muss in der Wurzel des Archivs liegen, sonst startet LOEVE nicht.
#
# Ausschlussliste: docs/, tests/, tools/ und dist/ gehoeren nicht in die
# Auslieferung, ebensowenig die Aufzeichnungen unter tests/replays/. Die
# Markdown-Dateien bleiben draussen -- mit einer Ausnahme, assets/CREDITS.md
# und music/README.md wandern bewusst mit, damit die Herkunftsangabe auch im
# ausgelieferten Paket steht (10_LEGAL §4).
LOVEFILE="$BUILD/$NAME.love"
"$ZIP" -9 -r -q "$LOVEFILE" . \
    -x '*.git*' \
       "$BUILD/*" \
       'tools/*' \
       'docs/*' \
       'tests/*' \
       'dist/*' \
       '.claude/*' \
       '*.DS_Store' \
       'CLAUDE.md' \
       'CHANGELOG.md' \
       'README.md' \
       'CONTRIBUTING.md' \
       'LICENSE-THIRD-PARTY.md' \
       '*.love' '*.zip' '*.exe'

echo "Erzeugt: $LOVEFILE ($(du -h "$LOVEFILE" | cut -f1))"

# Selbstkontrolle. Beide Faelle sind schon vorgekommen und beide fallen sonst
# erst dem Gast am Partyabend auf.
if command -v unzip >/dev/null 2>&1; then
    contents=$(unzip -Z1 "$LOVEFILE")
    if echo "$contents" | grep -qE '^(docs|tests|tools|dist)/'; then
        echo "FEHLER: ausgeschlossene Ordner sind in der .love gelandet" >&2
        exit 1
    fi
    if ! echo "$contents" | grep -qx 'main.lua'; then
        echo "FEHLER: main.lua liegt nicht in der Wurzel der .love" >&2
        exit 1
    fi
    echo "Inhalt geprueft: $(echo "$contents" | wc -l | tr -d ' ') Eintraege, main.lua in der Wurzel"
else
    echo "Hinweis: kein unzip -- Inhalt der .love ungeprueft." >&2
fi

[ "$TARGET" = "love" ] && { echo "Fertig."; exit 0; }

# --- 3. Windows -------------------------------------------------------------
build_windows() {
    local src="${LOVE_WIN:-tools/prebuilt/love-11.5-win64}"
    if [ ! -f "$src/love.exe" ]; then
        echo "Windows uebersprungen: $src/love.exe fehlt." >&2
        echo "  Offizielle 64-Bit-ZIP von love2d.org entpacken und LOVE_WIN setzen." >&2
        return 1
    fi

    local dir="$BUILD/$NAME-$VERSION-win64"
    mkdir -p "$dir"

    # Die Fusion: love.exe + .love ergibt ein "fused game".
    cat "$src/love.exe" "$LOVEFILE" > "$dir/$NAME.exe"

    # DLLs und license.txt muessen aus DEMSELBEN Download stammen
    # (`06_BUILD` §3). license.txt ist Pflicht, nicht Hoeflichkeit.
    cp "$src"/*.dll "$dir/"
    if [ ! -f "$src/license.txt" ]; then
        echo "FEHLER: license.txt fehlt in $src -- Weiterverteilung waere unzulaessig" >&2
        return 1
    fi
    cp "$src/license.txt" "$dir/"
    cp dist/LIESMICH_win.txt "$dir/LIESMICH.txt"

    # Die .ico fuer das EXE-Symbol wird erzeugt, aber nicht eingesetzt: das
    # Umschreiben der PE-Ressourcen ist ein Handgriff mit Resource Hacker
    # (`06_BUILD` §3) und laeuft nicht in der CI.
    if [ -n "$PY" ]; then
        "$PY" tools/make_icons.py --ico "$BUILD/$NAME.ico" || true
    fi

    ( cd "$BUILD" && "$ZIP" -9 -r -q "$NAME-$VERSION-win64.zip" "$NAME-$VERSION-win64" )
    echo "Erzeugt: $BUILD/$NAME-$VERSION-win64.zip ($(du -h "$BUILD/$NAME-$VERSION-win64.zip" | cut -f1))"
}

# --- 4. macOS ---------------------------------------------------------------
# Laeuft ausschliesslich auf macOS: codesign gibt es nur dort, und ohne
# Signatur startet die App auf Apple Silicon gar nicht (ADR-012).
build_macos() {
    if [ "$(uname -s)" != "Darwin" ]; then
        echo "macOS uebersprungen: dieser Schritt braucht codesign und laeuft nur auf macOS." >&2
        echo "  Der Tag-Build in GitHub Actions erledigt ihn auf macos-latest." >&2
        return 1
    fi

    local src="${LOVE_MAC:-tools/prebuilt/love-11.5-macos}"
    [ -d "$src/love.app" ] || { echo "macOS uebersprungen: $src/love.app fehlt." >&2; return 1; }
    [ -n "$PY" ] || { echo "FEHLER: Python 3 fehlt fuer patch_plist.py" >&2; return 1; }

    local dir="$BUILD/$NAME-$VERSION-macos"
    mkdir -p "$dir"
    cp -R "$src/love.app" "$dir/$NAME.app"
    cp "$LOVEFILE" "$dir/$NAME.app/Contents/Resources/"

    "$PY" tools/patch_plist.py "$dir/$NAME.app/Contents/Info.plist" \
          --identifier "$IDENTIFIER" \
          --name "$NAME" \
          --version "$VERSION" \
          --remove-uti

    # Programmsymbol. love.app bringt mehrere .icns mit (App-Symbol und das
    # Symbol fuer .love-Dokumente); ersetzt werden alle, weil hier kein
    # LOEVE-Symbol mehr auftauchen soll.
    if "$PY" tools/make_icons.py --icns "$BUILD/$NAME.icns"; then
        for icns in "$dir/$NAME.app/Contents/Resources/"*.icns; do
            [ -f "$icns" ] && cp "$BUILD/$NAME.icns" "$icns"
        done
    else
        echo "Hinweis: Symbol konnte nicht gebaut werden, love.app behaelt ihres." >&2
    fi

    # WICHTIG: Der Plist-Patch hat die Signatur der love.app zerstoert. Ohne
    # erneutes Signieren startet die App auf Apple Silicon nicht -- das ist
    # kein Gatekeeper-Dialog, sondern ein Nichtstart (ADR-012, `06_BUILD` §4).
    codesign --force --deep --sign - "$dir/$NAME.app"
    codesign --verify --verbose=2 "$dir/$NAME.app"   # Abbruchbedingung, set -e

    cp dist/LIESMICH_mac.txt "$dir/LIESMICH.txt"
    # -y ist Pflicht: ohne das Flag loest zip die Symlinks in den Frameworks
    # auf, die App verdoppelt ihre Groesse und kann beschaedigt ankommen.
    ( cd "$dir" && "$ZIP" -9 -r -q -y "../$NAME-$VERSION-macos.zip" "$NAME.app" LIESMICH.txt )
    echo "Erzeugt: $BUILD/$NAME-$VERSION-macos.zip"
}

case "$TARGET" in
    win)  build_windows ;;
    mac)  build_macos ;;
    all)  build_windows || true; build_macos || true ;;
    *)    echo "Unbekanntes Ziel: $TARGET (love|win|mac|all)" >&2; exit 1 ;;
esac

echo
echo "Fertig. Version $VERSION, Build-Hash $BUILDHASH"
echo "Die .love testen, nicht den Quellordner (06_BUILD §1):"
echo "  \${LOVE_BIN:-love} $LOVEFILE"
