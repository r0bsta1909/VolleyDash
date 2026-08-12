#!/usr/bin/env python3
"""Patcht die Info.plist der aus love.app abgeleiteten VolleyDash.app (M1-03).

Aufruf aus tools/build.sh:

    python3 tools/patch_plist.py <pfad/Info.plist> \\
            --identifier games.4brain.volleydash \\
            --name VolleyDash --version 1.0.0 --remove-uti

Drei Aenderungen, alle drei aus `docs/06_BUILD_RELEASE_PIPELINE.md` §4:

1. CFBundleIdentifier -- sonst teilt sich das Spiel Einstellungen und
   Berechtigungen mit LOEVE selbst.
2. CFBundleName / CFBundleShortVersionString / CFBundleVersion -- Anzeige im
   Finder und im Info-Fenster.
3. UTExportedTypeDeclarations entfernen -- sonst meldet sich VolleyDash als
   Standardprogramm fuer alle .love-Dateien auf dem Rechner an. Das ist
   uebergriffig gegenueber jemandem, der noch andere LOEVE-Spiele hat.

Nur Standardbibliothek: plistlib kann binaere und XML-Plists lesen und
schreibt im selben Format zurueck.

WICHTIG: Nach diesem Schritt ist die Signatur der love.app ungueltig. Ohne
erneutes Ad-hoc-Signieren startet die App auf Apple Silicon nicht (ADR-012).
Das erledigt build.sh unmittelbar danach.
"""

import argparse
import plistlib
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Info.plist fuer den macOS-Build anpassen")
    parser.add_argument("plist", type=Path, help="Pfad zu Contents/Info.plist")
    parser.add_argument("--identifier", help="CFBundleIdentifier")
    parser.add_argument("--name", help="CFBundleName und CFBundleExecutable-Anzeige")
    parser.add_argument("--version", help="CFBundleShortVersionString und CFBundleVersion")
    parser.add_argument("--remove-uti", action="store_true",
                        help="UTExportedTypeDeclarations entfernen")
    args = parser.parse_args()

    if not args.plist.is_file():
        print(f"FEHLER: {args.plist} nicht gefunden", file=sys.stderr)
        return 1

    with args.plist.open("rb") as handle:
        plist = plistlib.load(handle)

    changed = []

    if args.identifier:
        plist["CFBundleIdentifier"] = args.identifier
        changed.append(f"CFBundleIdentifier={args.identifier}")

    if args.name:
        plist["CFBundleName"] = args.name
        # CFBundleExecutable bleibt "love": so heisst die Binaerdatei in
        # Contents/MacOS, und ein Umbenennen dort braeuchte mehr als diesen
        # Patch. Der Finder zeigt CFBundleName.
        changed.append(f"CFBundleName={args.name}")

    if args.version:
        plist["CFBundleShortVersionString"] = args.version
        plist["CFBundleVersion"] = args.version
        changed.append(f"Version={args.version}")

    if args.remove_uti:
        if plist.pop("UTExportedTypeDeclarations", None) is not None:
            changed.append("UTExportedTypeDeclarations entfernt")
        # Die Dokumenttypen verknuepfen .love ebenfalls mit der App.
        if plist.pop("CFBundleDocumentTypes", None) is not None:
            changed.append("CFBundleDocumentTypes entfernt")

    with args.plist.open("wb") as handle:
        plistlib.dump(plist, handle)

    print("Info.plist gepatcht: " + ", ".join(changed) if changed else "Info.plist unveraendert")
    print("Die Signatur der App ist jetzt ungueltig -- codesign folgt in build.sh.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
