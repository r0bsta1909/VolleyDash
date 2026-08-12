# Musik

Hier hinein kommen die Hintergrundtitel. Das Spiel läuft auch ohne — dann ist
es schlicht still, genau wie ohne Bilder und Klänge.

## Ordner

```
music/
├── menu/     läuft im Menü, startet automatisch beim Programmstart
├── match/    läuft während eines Matches
└── *.ogg     lose Dateien hier gelten für beides
```

Erkannt werden `.ogg`, `.mp3`, `.flac` und `.wav`. **Empfohlen ist `.ogg`** —
es ist frei, LÖVE dekodiert es ohne Zusatzbibliothek, und die Dateien sind
deutlich kleiner als WAV.

## Verhalten

- **Shuffle.** Jede Liste wird gemischt; ist sie durch, wird neu gemischt. Der
  erste Titel der neuen Runde ist nie derselbe wie der letzte der alten.
- **Automatischer Wechsel**, sobald ein Titel ausläuft.
- **ESC pausiert** die Matchmusik zusammen mit dem Spiel. Zurück im Match läuft
  sie an derselben Stelle weiter.
- **Lautstärke** getrennt von den Effekten: `Settings → Music Volume`. Dort
  liegt auch `Nächster Titel` zum Überspringen.
- Titel werden **gestreamt**, nicht in den Speicher geladen (RAM-Ziel 150 MB).
- Im Aufzeichnungsmodus (`--record`, `--replay-all`, …) bleibt die Musik aus.

## Stand

Sieben Titel liegen hier: einer im Menü, sechs im Match, zusammen rund 14 MB.
**Herkunft geklärt** (r0btoshi, 2026-08-12), Lizenz zlib wie das Projekt, aufgeführt in
`assets/CREDITS.md`. Sie werden mit ausgeliefert.

## Bevor hier eine weitere Datei landet

**Herkunft klären.** Für die elf vorhandenen Assets ist das erledigt (alle von
r0btoshi, siehe `docs/ASSET_INVENTORY.md`) — für Musik gilt `10_LEGAL` §4 neu:
Ein Titel aus unklarer Quelle darf nicht in die Historie eines öffentlichen
Repositorys geraten, denn gelöschte Dateien bleiben dort trotzdem stehen.

Sichere Quellen sind eigene Produktionen oder ausdrücklich CC0-lizenziertes
Material mit dokumentiertem Nachweis in `assets/CREDITS.md` (M1-09).

**Größe im Blick behalten.** Das Erfolgskriterium aus dem Charter ist
„Time-to-First-Match ≤ 90 s ab ZIP-Download". Vier Titel zu je 3 MB verdoppeln
die Downloadgröße. Wenn es viel wird, gehört die Musik in ein optionales
Zusatzpaket statt in die Haupt-ZIP.
