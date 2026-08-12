# M0 — Abschlussbericht

**Stand:** 2026-08-12 · **Meilenstein:** M0 Refactoring-Fundament
**Status:** abgeschlossen und abgenommen (D1 als PO-Abnahme, siehe §4)

---

## 1. Was erledigt ist

Alle **neun Blocker** und alle **zehn Befunde** aus `02_CODE_AUDIT_PROTOTYP.md`.

| Aufgabe | Ergebnis |
|---|---|
| M0-01 | `conf.lua`: Version gepinnt, Identity, Fenster 1280 × 960, fünf Module aus (F-07, F-08) |
| M0-02 | Sound-Pool mit vier Stimmen (F-04) + Hintergrundmusik mit Shuffle (Zusatz, GDD §9.1) |
| M0-03 | Referenz-Rallyes, Aufzeichnungs- und Wiedergabewerkzeug, ADR-014/015 |
| M0-04 | Welt fix 800 × 600, `viewport.lua` mit Letterbox (B-01) |
| M0-05 | Fixer Schritt 1/60 mit Akkumulator, Render-Interpolation (B-02) |
| M0-06 | `InputFrame`, `local_source`, Doppeltipp in Ticks (B-03) |
| M0-07 | Bot nach `bot_source.lua`, Instanzierung, ein Verbrauchspfad (B-07, B-09) |
| M0-08 | `src/sim/` extrahiert, nachweislich rein (kein love, kein Zufall) |
| M0-09 | `Ruleset`/`Prefs` getrennt, Presets, kanonischer Hash (B-04, F-01, F-02, F-10) |
| M0-10 | Zwei-Punkte-Vorsprung, Deuce-Deckel, Rallye-Timeout (B-05, GDD P5) |
| M0-11 | Tastenbelegung konfigurierbar und persistent, Gamepad-Slots (GDD §7) |
| M0-12 | Szenenstapel, UI und Render getrennt, `main.lua` 63 Zeilen (F-05, F-06, B-08, F-09) |
| M0-13 | Headless-Runner, Ebene A automatisiert, Regel-Unit-Tests (Testplan §3) |

**Zahlen:** 83 Tests, elf Referenz-Rallyes, `main.lua` von 1404 auf 63 Zeilen.

## 2. Das Sicherungsnetz

Die Absicherung gegen R-04 (Spielgefühl beim Refactoring verlieren) steht und hat
gearbeitet:

```powershell
D:\love2d\LOVE\lovec.exe . --test        # Ebene A + B, 83 Fälle, ~1 s
D:\love2d\LOVE\lovec.exe . --test-no-love # zusätzlich: beweist die love-Freiheit
python tools\verify_replays.py            # prüft, dass jede Rallye ihr Phänomen enthält
```

`tests/replay_test.lua` fährt die aufgezeichneten `InputFrames` durch `Step.tick` und
vergleicht Tick für Tick. **Elf von dreizehn Umbauschritten liefen bitgleich durch** —
inklusive der vollständigen Extraktion der Simulation.

## 3. Die zwei einzigen gewollten Verhaltensänderungen

Vollständig; alles andere ist nachweislich unverändert.

1. **M0-07, Bot-Absprung.** Der Bot bekam im Absprungtick volle Bodengeschwindigkeit,
   weil sein Sprung nach der Geschwindigkeitsberechnung lag. P1 hatte das nie. Jetzt gilt
   für beide `airControl`. Betrifft R-02 und R-03, beide mit unverändertem Ausgang.
   Protokolliert in `07_TEST_PLAN` §2.
2. **M0-06, Aufwärts-Dash mit gehaltener Richtung** wird zum Seitwärts-Dash, weil die
   Richtung aus den Richtungsbits kommt (ADR-014).

## 4. Abnahme D1 — entschieden am 2026-08-12

> **Nachtrag (2026-08-12, Beginn CC-02):** r0btoshi hat den zweiten Weg gewählt — **D1 ist als
> Product-Owner-Abnahme erteilt**, auf Basis einer Person, ohne Blindverfahren. Der Vermerk
> steht in `07_TEST_PLAN` §6 und im `CHANGELOG.md`. **M0 ist damit abgenommen.** Der
> Abschnitt unten bleibt als Begründungslage stehen.

### Ausgangslage der Entscheidung

`07_TEST_PLAN` §6 verlangt: **drei Personen, je drei Sätze, alte gegen neue Fassung im
Blindwechsel**, Frage „Welche war Nummer 1?".

**Stand 2026-08-12:** r0btoshi hat beide Fassungen selbst gespielt und meldet
„fühlt sich soweit alles gut an", Musik läuft. Das ist ein **positiver Rauchtest, kein
bestandenes D1** — es fehlen die zweite und dritte Person und das Blindverfahren.

Zwei Wege, beide legitim:

- **D1 nachholen** am nächsten Abend mit zwei weiteren Personen
  (Anleitung: `docs/handoffs/M0_ABNAHME.md` §3). Der Baseline-Arbeitsordner
  `C:\dev\volley-dash-baseline` steht bereit.
- **D1 als Product Owner abnehmen** und im Änderungslog vermerken. Dann steht im Protokoll,
  dass die Abnahme auf einer Person beruht — das ist eine Entscheidung, keine Lücke, solange
  sie so dasteht.

~~Bis das entschieden ist, gilt M0 als **inhaltlich fertig, formal nicht abgenommen**.~~
**Entschieden: PO-Abnahme, siehe Nachtrag oben.**

## 5. Was aus M0 bewusst offen bleibt

| Punkt | Wohin |
|---|---|
| Gamepad gebaut, aber ungetestet (kein Gerät) | sobald ein Controller da ist |
| `Display [WIP]` (Vollbild, Beamer-Lautstärke) | M5 |
| Zweite lokale Belegung im LAN abschalten (GDD §7) | M2 |
| `variable/R-11` erreicht den Deckel nie | dokumentiert, Referenz ist die Szene in `fixed60` |
| `R-02` ist „viele Ballwechsel", nicht „ein langer" | vor einem echten D1 ggf. neu aufzeichnen |
| Musik: keine Dateien im Repo, Herkunft und Downloadgröße offen | vor dem ersten Titel, `music/README.md` |
| Temporäres Werkzeug `tools/reference_mode.lua` | geht mit dem Headless-Runner auf, wenn M1-11 die CI hat |

## 6. Nächster Schritt

**M1 — Build-Pipeline und Open-Source-Repo.** Auftrag liegt als
`docs/handoffs/CC-02_M1_BUILD.md` bereit.
