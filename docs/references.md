# Referenzen und Abgrenzung

**Stand:** 2026-08-12 · **Bezug:** `10_LEGAL_ASSETS_NAMING.md` §2, ADR-011, M1-08

Diese Datei beantwortet die Frage, die bei einem Spiel dieser Machart naheliegt, bevor sie
gestellt wird: **Woher stammt das Verhalten, und woher stammt der Code?**

---

## 1. Die kurze Antwort

**Aus Blobby Volley 2 wurde kein Code übernommen** — weder kopiert noch nach Lua übersetzt,
weder ganz noch zeilenweise. Es wurden auch keine Assets übernommen. Volley Dash ist eine
Neuimplementierung, kein Fork und keine Portierung.

Blobby Volley 2 steht unter GPLv2. Eine Übersetzung seiner Physik nach Lua wäre eine
Bearbeitung und würde das gesamte Werk unter die GPL zwingen. Volley Dash steht unter zlib
(`LICENSE`) — das geht nur, wenn die Abgrenzung sauber ist.

## 2. Was tatsächlich die Quelle war

Der Ausgangspunkt ist ein **eigener Prototyp** in LÖVE, geschrieben aus der Erinnerung an das
Spielgefühl von Blobby Volley (2000, Skoraszewsky/Mummert) — ein Freeware-Spiel ohne
offenen Quellcode. Aus ihm konnte technisch nichts übernommen werden, weil es dort nichts
zu übernehmen gibt.

Sämtliche Zahlen der Simulation stammen aus diesem Prototyp und sind durch Ausprobieren
entstanden, nicht durch Abgleich mit fremdem Code. Sie stehen offen in
`src/sim/ruleset.lua` und sind in `02_CODE_AUDIT_PROTOTYP.md` §4 als unveränderlich
festgeschrieben:

| Größe | Wert |
|---|---|
| Schwerkraft | 1000 |
| Blob-Radius | 54 |
| Wandabprall | 0,70 |
| Feldmaße | 800 × 600 |

Wer diese Werte mit Blobby Volley 2 vergleicht, wird sie dort nicht finden. Sie ergeben in
einem 800 × 600 großen Feld bei 60 Hz ein bestimmtes Gefühl, und darauf wurden sie
eingestellt.

## 3. Übernommene Regeln

Übernommen sind **Spielregeln**, und die sind Ideen, kein geschützter Ausdruck:

- Zwei armlose Blobs, ein Netz, ein Ball. Gespielt wird mit drei Tasten: links, rechts,
  springen. Keine Schlagtaste — der Ball wird über die Kollision gespielt.
- Side-out: Punkte macht nur, wer aufschlägt. Wer nicht aufschlägt, gewinnt bei einem
  Fehler des Gegners das Aufschlagrecht.
- Höchstens drei Berührungen in Folge, der Aufschlag zählt mit. Selbstzuspiel ist erlaubt.
- Die Seitenwände sind Abpraller und dürfen taktisch genutzt werden.

Das vollständige verbindliche Regelwerk steht in `01_GDD_v1.0.md` §3.

Was Volley Dash **anders** macht, steht in `01_GDD_v1.0.md` §3 und in
`09_DECISION_LOG_ADR.md` — insbesondere die Zwei-Punkte-Regelung, Dash und Smash
(im Preset `classic` abgeschaltet, ADR-006) und der Turniermodus.

## 4. Wenn doch einmal nachgeschlagen wird

Sollte während der weiteren Entwicklung eine Verhaltensfrage anhand fremder Quellen geklärt
werden — etwa „wie verhält sich der Ball an der Netzkante?" —, gehört der Vorgang in die
folgende Tabelle: **welche Frage, welche Quelle, welches Ergebnis**. Angeschaut werden darf
alles; übernommen werden darf nur die Erkenntnis, nie der Ausdruck.

| Datum | Frage | Quelle | Ergebnis im Code |
|---|---|---|---|
| — | — | — | bislang kein Eintrag |

Die Tabelle ist leer, und das ist die Aussage: Bis hierher wurde keine fremde Quelle
herangezogen.

## 5. Namensrecht

„Blobby Volley" ist nicht der Name dieses Spiels und wird nicht als Bezeichnung verwendet.
Volley Dash nennt das Vorbild als Inspiration — das ist eine Nennung, keine Anlehnung an
eine fremde Marke. Einzelheiten in `10_LEGAL_ASSETS_NAMING.md` §3.
