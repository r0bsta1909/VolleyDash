#!/usr/bin/env python3
"""Baut aus den PNG-Vorlagen die Symbolformate der beiden Plattformen (M1-06).

    python3 tools/make_icons.py --icns build/VolleyDash.icns
    python3 tools/make_icons.py --ico  build/VolleyDash.ico

Quellen sind `assets/icon.png` (512 x 512) und `dist/icon-256.png`.

Beide Zielformate sind Behaelter, die PNG-Daten unveraendert aufnehmen --
deshalb kommt dieses Skript ohne Bildbibliothek aus. Es skaliert nichts; es
verpackt nur, was schon in der richtigen Groesse vorliegt (`CLAUDE.md` §7:
keine Fremdbibliotheken ohne ADR).

* **.icns** wird beim macOS-Build automatisch in die `.app` gelegt.
* **.ico** ist die Vorlage fuer das Symbol der Windows-EXE. Das Einsetzen
  bleibt ein Handgriff mit Resource Hacker (`06_BUILD` §3) -- eine
  PE-Ressourcentabelle umzuschreiben ist nichts, was man nebenbei richtig
  macht, und eine vorgepatchte love.exe darf laut `12_OPENSOURCE` §4 nicht ins
  Repo.
"""

import argparse
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ICNS-Typkennungen. Der Wert ist die Kantenlaenge, die das Format erwartet.
ICNS_TYPES = {
    512: b"ic09",
    256: b"ic08",
    128: b"ic07",
}


def png_size(data: bytes) -> tuple:
    """Liest Breite und Hoehe aus dem IHDR-Block. Kein Parser, nur ein Blick."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("keine PNG-Datei")
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def load(path: Path) -> bytes:
    if not path.is_file():
        raise FileNotFoundError(path)
    return path.read_bytes()


def build_icns(sources: list, out: Path) -> None:
    entries = []
    for data in sources:
        width, height = png_size(data)
        if width != height or width not in ICNS_TYPES:
            print(f"  uebersprungen: {width} x {height} ist keine ICNS-Groesse")
            continue
        entries.append(ICNS_TYPES[width] + struct.pack(">I", len(data) + 8) + data)

    if not entries:
        raise ValueError("keine verwendbare Groesse dabei")

    body = b"".join(entries)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
    print(f"Geschrieben: {out} ({len(entries)} Groessen, {out.stat().st_size} Bytes)")


def build_ico(sources: list, out: Path) -> None:
    usable = []
    for data in sources:
        width, height = png_size(data)
        # ICO fasst nur bis 256; die 0 im Kopf bedeutet genau 256.
        if width > 256 or height > 256:
            continue
        usable.append((width, height, data))

    if not usable:
        raise ValueError("keine Groesse <= 256 dabei -- dist/icon-256.png fehlt?")

    usable.sort(key=lambda item: item[0], reverse=True)

    header = struct.pack("<HHH", 0, 1, len(usable))
    offset = len(header) + 16 * len(usable)
    directory, payload = b"", b""

    for width, height, data in usable:
        directory += struct.pack(
            "<BBBBHHII",
            0 if width == 256 else width,
            0 if height == 256 else height,
            0,      # Farbtabelle: keine
            0,      # reserviert
            1,      # Farbebenen
            32,     # Bit je Pixel
            len(data),
            offset,
        )
        payload += data
        offset += len(data)

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(header + directory + payload)
    print(f"Geschrieben: {out} ({len(usable)} Groessen, {out.stat().st_size} Bytes)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Programmsymbole erzeugen")
    parser.add_argument("--icns", type=Path, help="Ziel fuer das macOS-Symbol")
    parser.add_argument("--ico", type=Path, help="Ziel fuer das Windows-Symbol")
    args = parser.parse_args()

    if not args.icns and not args.ico:
        parser.error("mindestens --icns oder --ico angeben")

    try:
        sources = []
        for candidate in (ROOT / "assets" / "icon.png", ROOT / "dist" / "icon-256.png"):
            if candidate.is_file():
                sources.append(load(candidate))
            else:
                print(f"Hinweis: {candidate} fehlt", file=sys.stderr)

        if not sources:
            print("FEHLER: keine Symbolvorlage gefunden", file=sys.stderr)
            return 1

        if args.icns:
            build_icns(sources, args.icns)
        if args.ico:
            build_ico(sources, args.ico)
    except (ValueError, FileNotFoundError) as error:
        print(f"FEHLER: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
