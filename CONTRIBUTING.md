# Mitarbeit

Kurz vorweg, damit niemand Zeit verschwendet: **Dieses Repo ist offen, aber nicht
betreut.** Es entsteht nebenberuflich für konkrete LAN-Abende. Pull Requests sind
willkommen, eine zeitnahe Bearbeitung ist nicht zugesagt. Wenn du das Spiel für deine
Zwecke brauchst, ist ein Fork der schnellere Weg — die zlib-Lizenz erlaubt das
ausdrücklich.

## Bevor du etwas baust

Zwei Dokumente ersparen Enttäuschungen:

- [`docs/00_PROJECT_CHARTER.md`](docs/00_PROJECT_CHARTER.md) **§4 Scope — Out** listet auf,
  was bewusst *nicht* gebaut wird, mit Begründung. Internet-Multiplayer, Accounts,
  Progression, Cosmetics und Mobile-Ports stehen dort.
- [`docs/09_DECISION_LOG_ADR.md`](docs/09_DECISION_LOG_ADR.md) hält Architekturentscheidungen
  fest. Wer eine davon umdrehen will, braucht einen neuen Sachgrund — nicht bloß eine
  andere Vorliebe.

Für alles, was größer als ein Fehlerfix ist: erst ein Issue, dann Code.

## Die drei Regeln, an denen ein PR sonst scheitert

**1. `src/sim/` bleibt frei von `love` und von Zufall.**
Die Simulation liest niemals Hardware und ruft nie `math.random`. Sie bekommt pro Spieler
und Tick genau einen `InputFrame`. Nur so laufen die Tests headless, und nur so kann ein
Netzwerkspiel überhaupt synchron bleiben. `love . --test-no-love` weist das nach.

**2. Das Spielgefühl ist eingefroren.**
Die Zahlen in `src/sim/ruleset.lua`, die Kollisionsauflösung Blob↔Ball, das Wandabprall-
Verhalten und die Dash-Fenster stehen unter
[`docs/02_CODE_AUDIT_PROTOTYP.md`](docs/02_CODE_AUDIT_PROTOTYP.md) §4. Sie werden nicht
„verbessert". Eine Änderung daran ist eine Designentscheidung und braucht vorher ein Issue.

**3. Tests bleiben grün.**
```
love . --test          # 83 Fälle, Ebene A und B
love . --test-no-love  # weist die love-Freiheit nach
python tools/verify_replays.py
```
Die Referenz-Rallyes unter `tests/replays/` fahren aufgezeichnete Eingaben Tick für Tick
durch die Simulation und vergleichen das Ergebnis. Wer sie bricht, hat das Spielgefühl
verändert — auch wenn es nicht so aussah.

## Codestil

- **Lua 5.1 / LuaJIT.** Kein `goto`, kein Integer-Typ, kein `//`. LÖVE 11.5 ist gepinnt.
- Bezeichner, Kommentare und Commit-Messages auf **Englisch**; die Dokumentation unter
  `docs/` ist auf **Deutsch**.
- Kommentare erklären, **warum** etwas so ist, nicht was die Zeile tut.
- Keine neuen Abhängigkeiten ohne ADR. Was LÖVE mitbringt, reicht — auch für den Netcode.
- Vier Leerzeichen, keine Tabs. Zeilenenden LF.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/) mit der Aufgaben-ID aus
[`docs/08_ROADMAP_BACKLOG.md`](docs/08_ROADMAP_BACKLOG.md):

```
feat(input): add gamepad dead zone handling (M0-06)
fix(render): correct letterbox offset on ultrawide (B-01)
```

## Fehler melden

Bitte die Vorlage benutzen und die Version aus dem Hauptmenü (unten rechts, z. B.
`v0.1.0 (a16e7da1d86f)`) mitschicken. Ohne sie lässt sich ein Bericht selten einordnen.

## Lizenz

Mit einem Beitrag stellst du ihn unter die [zlib-Lizenz](LICENSE) dieses Projekts.
Für Assets gilt zusätzlich: **kein Beitrag ohne geklärte Herkunft.** Eine einmal gepushte
Datei bleibt in der Historie, auch wenn sie später gelöscht wird.
