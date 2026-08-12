#!/usr/bin/env bash
# =============================================================================
# tools/release_notes.sh -- Release-Text aus dem CHANGELOG (12_OPENSOURCE §7.6)
#
#     ./tools/release_notes.sh 0.2.0 > notes.md
#
# Schritt 6 des Release-Prozesses verlangt "Aenderungen + die zwei
# Startanleitungen". Beides steht schon im Repo -- im CHANGELOG und in den
# beiden LIESMICH-Dateien. Hier wird es zusammengesetzt, statt es ein zweites
# Mal von Hand zu schreiben: ein Release-Text, der von der Wahrheit abweicht,
# ist schlechter als keiner.
#
# `gh release create --generate-notes` waere die bequeme Alternative und
# liefert eine Liste von Commit-Titeln. Die sind auf Englisch, technisch und
# fuer jemanden, der nur spielen will, wertlos.
# =============================================================================
set -eu

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Aufruf: $0 <version>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Den Abschnitt dieser Fassung aus dem CHANGELOG schneiden: von der eigenen
# Ueberschrift bis zur naechsten.
section=$(awk -v want="## [$VERSION]" '
    index($0, want) == 1 { inside = 1; next }
    inside && /^## \[/   { exit }
    inside               { print }
' CHANGELOG.md)

if [ -z "$section" ]; then
    echo "FEHLER: kein CHANGELOG-Abschnitt fuer $VERSION" >&2
    exit 1
fi

cat <<EOF
## Was neu ist

$section
## So fängst du an

**Windows** — ZIP **entpacken** (nicht aus dem ZIP heraus starten, sonst sind die
Einstellungen beim nächsten Mal weg), \`VolleyDash.exe\` doppelklicken. Bei der Warnung
„Der Computer wurde durch Windows geschützt": *Weitere Informationen* → *Trotzdem
ausführen*. Das Spiel ist nicht signiert; ein Zertifikat kostet dreistellig im Jahr.

**macOS** — ZIP **mit dem Finder** entpacken (andere Programme zerstören die Symlinks im
App-Bundle). Beim ersten Start **Rechtsklick auf die App → Öffnen**, dann im Dialog
*Öffnen*. Doppelklick allein reicht nicht: die App ist ad-hoc signiert, aber nicht
notarisiert.

Alles Weitere steht in der \`LIESMICH\`-Datei, die jedem Paket beiliegt.

## Im LAN spielen

1. Beide Rechner ins selbe Netz, möglichst per Kabel.
2. *Network Match → Nickname* setzen. Der Name bleibt gespeichert und steht in der Lobby
   des anderen.
3. Einer wählt *Spiel hosten* — seine Lobby zeigt seine IP-Adresse groß an.
4. Der andere wählt *Spiel suchen*, verbindet mit \`ENTER\` und meldet sich bereit.

Beim ersten Start fragt die Firewall nach einer Freigabe — **erlauben**, sonst kann sich
niemand zu diesem Rechner verbinden. Bleibt die Serverliste leer, hilft der letzte Eintrag:
*Direkt verbinden (IP eingeben)*. Das funktioniert auch quer durch Firewalls.

\`F3\` blendet im Match Ping, Paketverlust und Puffertiefe ein.

## Bekannte Grenzen

- **Netzwerk ist 1 gegen 1.** Turniermodus, 2v2 und Zuschauer kommen später.
- Getestet wurde bisher im Loopback und in der CI auf Windows und macOS. Der Betrieb über
  ein echtes Netz zwischen zwei Rechnern steht noch aus — deshalb ist dieser Release ein
  Entwurf.
- Der Gast sieht im Netzspiel noch keine Partikel und hört keine Klänge; er zeigt den
  Zustand, den der Host schickt. Kommt mit der nächsten Fassung.
EOF
