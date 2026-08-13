# CC-05 — Klangliste Turniermodus

**Erstellt:** 2026-08-13 · **Für:** r0btoshi · **Bezug:** `05_TOURNAMENT` §5, M4-07
**Status:** eine Datei ist Pflicht, zwei sind begründete Vorschläge

---

## 0. Kurzfassung

**Es gibt genau eine Pflichtdatei:**

```
assets/tournament_call.wav
```

Alles andere in diesem Dokument ist Vorschlag mit Begründung, und du kannst jeden davon
ablehnen, ohne dass etwas kaputtgeht. **Fehlt eine Klangdatei, bleibt das Spiel still und
läuft weiter** — kein Absturz, keine Fehlermeldung (`src/app/assets.lua`, `10_LEGAL` §4).

---

## 1. Warum überhaupt ein Ton

`05_TOURNAMENT` §5 schreibt ihn vor, und der Grund ist kein akustischer:

> **Der Aufruf („calling"):** Sobald ein Match `ready` wird, bekommen die beiden Spieler eine
> gut sichtbare Einblendung im Menü **und** ein Signalton […]. Ohne akustisches Signal
> funktioniert das auf einer Party nicht — niemand starrt auf sein Menü.

Seit dieser Session ist das keine Vorsichtsmaßnahme mehr, sondern eine Notwendigkeit: **Der
No-Show-Timer ist gebaut und läuft wirklich.** 180 Sekunden nach dem Aufruf verliert ein
Spieler sein Match per Walkover (E-02). Ohne Ton verliert es jemand, der nichts gehört hat —
und das ist die Sorte Ärger, die einen Turnierabend kippen lässt.

---

## 2. Die Pflichtdatei

| | |
|---|---|
| **Ordner** | `assets/` — direkt darin, nicht in einem Unterordner |
| **Dateiname** | `tournament_call.wav` |
| **Format** | WAV, 44,1 kHz, 16 Bit, Stereo — wie die acht vorhandenen Klänge |
| **Alternative** | `.ogg` wird auch geladen, aber `.wav` hat Vorrang. Bei einem so kurzen Klang ist WAV richtig |

**Der Name muss exakt so lauten.** Der Lader sucht `assets/tournament_call.wav` und fällt
sonst auf `assets/tournament_call.ogg` zurück; findet er beides nicht, bleibt es still. Er ist
seit dieser Session in `src/app/assets.lua` angemeldet — du kannst die Datei also einfach
hinlegen, sie wird dann geladen. Abgespielt wird sie erst, wenn M4-07 die Anzeige baut.

### Was der Klang leisten muss

Das ist wichtiger als der Geschmack, weil es an den Betriebsbedingungen hängt:

- **Kurz: 0,5 bis 1,5 Sekunden.** Er wird als `static` geladen und über einen Stimmenpool
  abgespielt (vier Stimmen, `Assets.POOL_VOICES`). Ein langer Klang mit Nachhall überlappt
  sich bei zwei kurz aufeinanderfolgenden Aufrufen unschön.
- **Er muss sich von `whistle.wav` unterscheiden.** Der Pfiff bedeutet im Spiel „Anpfiff oder
  Punkt". Wer im Menü sitzt und einen Pfiff hört, denkt an das Match nebenan. Der Aufruf ist
  eine **Aufforderung an dich persönlich** und sollte auch so klingen — eher Glocke, Gong,
  Fanfarenmotiv oder Türklingel als Trillerpfeife.
- **Er muss über die Menümusik durchkommen.** Die läuft mit Grundlautstärke 0,5, der Klang
  spielt gegen 0,25 Grundlautstärke an. Normalisiert auf −1 dBFS, mit klarem Anschlag vorn.
- **Er darf nicht wehtun.** An einem 20er-Abend feuert er rund 96-mal (48 Matches × 2 Spieler).
  Was beim dritten Mal witzig ist, ist beim dreißigsten ein Grund, den Ton auszuschalten — und
  dann ist der No-Show-Timer wieder blind.
- **Kein Sprachanteil.** Ein gesprochenes „Du bist dran" altert schlecht und lässt sich nicht
  übersetzen.

---

## 3. Zwei Vorschläge, kein Muss

Beide sind **nicht** in der Spec gefordert. Ich nenne sie, weil sie aus dem Bau des
Zustandsautomaten heraus naheliegen — nicht, weil ein Turnier ohne sie unvollständig wäre.
Wenn du sie nicht machst, ändert sich am Code nichts.

### 3.1 `tournament_warn.wav` — die zweite Chance

| | |
|---|---|
| **Ordner / Name** | `assets/tournament_warn.wav` |
| **Format** | wie oben |
| **Länge** | 0,3 bis 0,8 s, deutlich unauffälliger als der Aufruf |

**Wofür:** Ein zweiter, leiserer Ton bei etwa 30 verbleibenden Sekunden des No-Show-Timers.

**Begründung:** Der Aufruf kann untergehen — jemand ist am Kühlschrank, jemand hat gerade
sein voriges Match beendet und den Kopfhörer abgesetzt. Der Timer läuft trotzdem. Ein zweiter
Ton kurz vor Ablauf kostet nichts und verhindert genau den Fall, der am nächsten Tag als
„die Software hat mich rausgeworfen" erzählt wird. `05_TOURNAMENT` §1 setzt sich zum Ziel,
dass der Turnierleiter **null** Eingriffe machen muss; jeder verhinderte Walkover ist ein
verhinderter Eingriff.

**Warum es trotzdem nur ein Vorschlag ist:** Es ist eine Erfindung von mir, keine Anforderung.
Wer den Aufruf überhört, überhört womöglich auch die Warnung, und dann sind es zwei Töne
statt einem für dasselbe Ergebnis.

### 3.2 `tournament_done.wav` — die Siegerehrung

| | |
|---|---|
| **Ordner / Name** | `assets/tournament_done.wav` |
| **Format** | wie oben, hier darf `.ogg` sinnvoll sein, wenn er länger wird |
| **Länge** | 2 bis 5 s |

**Wofür:** Einmal am Ende des Turniers, am Beamer, wenn der Sieger feststeht.

**Begründung:** Er spielt genau **einmal pro Abend**. Das ist der Moment, in dem sich die
ganze Veranstaltung auflöst — und der einzige Klang in der Liste, bei dem Länge und Pathos
erlaubt sind, weil ihn niemand ein zweites Mal hört.

**Warum es trotzdem nur ein Vorschlag ist:** Er gehört zur Beamer-Ansicht (M4-08) und damit
frühestens in die übernächste Sitzung. Es eilt nicht.

---

## 4. Wenn du eine Datei ablegst

`assets/CREDITS.md` erhebt einen Vollständigkeitsanspruch: *„Jede `.png`, `.wav` und `.ogg` in
diesem Repository steht hier. Was hier nicht steht, gehört nicht ins Repository."*
(`10_LEGAL` §4, M1-09). Die Zeile gehört also mit dazu. Sie ist vorbereitet — Größe eintragen
und in die Tabelle unter **Klänge** hängen:

```markdown
| `tournament_call.wav` | ... kB | Turnier-Aufruf: dein Match ist dran (05_TOURNAMENT §5) |
```

Und darüber die Anzahl anpassen: aus *„Acht WAV-Dateien"* wird neun.

**Herkunft:** Es gilt der Grundsatz oben in der Datei — alles von r0btoshi, zlib, kein
Material aus Blobby Volley oder Blobby Volley 2. **Wenn du einen Klang von woanders nimmst**
(Freesound, ein Sample-Paket, ein KI-Generator), sag das bitte ausdrücklich, bevor er in die
Historie wandert: Dann braucht er eine eigene Zeile mit Quelle und Lizenz, und der Grundsatz
in `CREDITS.md` muss aufgeweicht werden. Einmal committet ist es nicht mehr ohne Weiteres
herauszuholen — `CLAUDE.md` §11 verlangt die Klärung deshalb ausdrücklich **vor** dem Push.

---

## 5. Was NICHT gebraucht wird

Damit die Liste nicht wächst, bis sie niemand mehr abarbeitet:

- **Kein eigener Klang für Walkover, Freilos oder Rundenwechsel.** Das sind Ereignisse für die
  Anzeige, nicht für die Ohren. Wer bei jedem Bracket-Fortschritt einen Ton hört, schaltet
  nach zwanzig Minuten ab.
- **Keine Menü-Klicklaute.** Das Spiel hat heute keine und braucht keine.
- **Keine zweite Musikspur für die Turnierlobby.** Die sieben Titel reichen; die Menümusik
  läuft dort weiter.
