# AP-4 — Messanleitung (ÜBERHOLT: die Puffer-Frage ist mit ADR-025 entfallen)

> **Stand 2026-08-14, später am Tag:** Die erste Messung nach dieser Anleitung (RTT ~21 ms,
> Host im WLAN) hat die Frage „Puffer 1 oder 2" **beerdigt statt beantwortet**: Der Puffer
> hielt sein Soll nicht (C-T-23), und auch ein sauberer Puffer hätte die Konsistenzfrage
> nicht gelöst. Entschieden ist **ADR-025** — der Gast simuliert die ganze Welt vor, einen
> Puffer gibt es nicht mehr. **Was am nächsten LAN-Abend stattdessen zu prüfen ist, steht
> unten in §5;** die Läufe aus §3 sind gegenstandslos.

**Anlass:** CC-06 §2 AP-4 · **Grundlage:** `04_NETCODE` §8 (Nachtrag 2026-08-14),
`CC-05_REPORT` „Der Ball-Verzug beim Gast" · **Erstellt:** 2026-08-14

---

## 1. Was gemessen wird und warum

Der Gast zeichnet seinen eigenen Blob im Jetzt (Vorhersage, ADR-017), den Ball aber
aus dem Interpolationspuffer — bei Vorgabe 2 sind das 33 ms Vergangenheit, **auch bei
RTT null**. Im Sprung sieht man diese 33 ms als Eindringtiefe: Der Ball wird mitten
im Blob getroffen statt außen.

Puffer 1 halbiert den Versatz und kostet dafür Ruckelfestigkeit. In der CI auf
`macos-latest` ist genau das gemessen durchgefallen (146 statt 203 von 206 Snapshots
angezeigt, 68 gehalten). **Ob echte Hardware am Switch das auch tut, ist die offene
Frage — und nur die.**

## 2. Aufbau

- Zwei Rechner, **Kabel am selben Switch** (der Auslegungsfall seit ADR-019).
  Wenn vorhanden: einmal Windows und einmal macOS.
- Dieselbe Build auf beiden (Build-Hash unten links im Menü notieren).
- Freies LAN-Match reicht: **NETWORK MATCH → Host** auf dem einen,
  Beitritt über die Serverliste auf dem anderen. Kein Turnier nötig.

## 3. Durchführung — vier Läufe, je zwei bis drei Minuten

Gemessen wird **immer beim Gast** (der Host hat das Problem nicht).

| Lauf | Gast-Rechner | Menü → Settings → „Netz-Puffer (Gast)" |
|---|---|---|
| 1 | Rechner A | **2** (Vorgabe) |
| 2 | Rechner A | **1** |
| 3 | Rechner B | **2** |
| 4 | Rechner B | **1** |

Je Lauf, beim **Gast**:

1. **F3** einschalten (Overlay) und **F4** einschalten (Mitschnitt): schreibt einmal
   je Sekunde nach `netlog.csv` im Save-Ordner — Pfad steht beim Einschalten in der
   Konsole. Die Spalten `puffer`, `gehalten`, `verworfen` sind die Messgrößen.
2. Zwei bis drei Minuten **normal spielen**, mit vielen Sprüngen und Schlägen am
   Ball — der Effekt zeigt sich nur bei bewegtem Blob.
3. Danach zwei Sätze notieren (subjektiv, aber notiert, nicht erinnert):
   - Wird der Ball außen am Blob getroffen oder im Blob? (Sprung!)
   - Ruckelt oder stockt der Ball? (Das wäre `GEHALTEN` > 0 in Serie.)

Nach jedem Lauf die `netlog.csv` umbenennen (`netlog_A_puffer2.csv` usw.), sonst
schreibt der nächste Lauf hinein.

## 4. Woran die Entscheidung hängt

- **`GEHALTEN` bleibt bei Puffer 1 nahe null** (vereinzelte Einsen sind in Ordnung,
  Serien nicht) **und es fühlt sich besser an** → ADR: Vorgabe über Kabel auf 1.
- **`GEHALTEN` steigt bei Puffer 1 sichtbar** (das CI-Muster) → Puffer bleibt 2,
  und der nächste Schritt ist die **Ball-Extrapolation** (N-01) — eigener ADR,
  mit dem bekannten Preis (Zappeln bei Richtungswechsel).
- In beiden Fällen: die vier CSVs und die notierten Sätze zurück in die Session —
  der ADR zitiert dann Zahlen statt Eindrücke.

**Zur Meldung „schlimmer geworden":** Das getestete Paket (`1a46e340032b7e1c`) hatte
unverändert Puffer 2. Wenn Lauf 1/3 sich schlimmer anfühlt als der erste LAN-Abend,
ist das ein eigener Befund und gehört mit aufgeschrieben — auch dann, wenn die
Zahlen gleich aussehen. *(Nachtrag: erklärt — die stehende Puffertiefe ratschte je
nach Sessionverlauf verschieden hoch, C-T-23.)*

---

## 5. Was seit ADR-025 stattdessen zu prüfen ist

> **Erste Prüfung bestanden** (r0btoshi, 2026-08-14, Build `7895f75`, Host im WLAN /
> Gast am Kabel): Ball außen am Blob, „funktioniert perfekt", keine Schnapper gemeldet.
> Die Punkte unten gelten weiter für den LAN-Abend mit mehr Rechnern und Rollentausch.

Ein Rechner hostet, der andere tritt bei — Kabel **und** einmal absichtlich WLAN.
Beim **Gast** F3 einschalten und zwei bis drei Minuten mit vielen Sprüngen spielen:

1. **Die eigentliche Frage:** Wird der Ball jetzt **außen** am Blob getroffen — auch im
   Sprung, auch beim Gast? Das war der Befund beider LAN-Abende; er muss weg sein.
2. **Der Preis:** „Schnappt" der Ball sichtbar, wenn der **Gegner** ihn berührt
   (Richtungswechsel, Rettung)? Am Kabel sollte davon nichts zu sehen sein; im WLAN
   klein. Sichtbares Schnappen ist der Revisionsauslöser aus ADR-025.
3. **F3-Werte notieren:** `REPLAY` (Soll: RTT/2 + 1, am Kabel 1–2), `Rueckstau` (Soll 0),
   `GEHALTEN` (vereinzelt in Ordnung, Serien nicht), `KORREKTUR` (klein, nicht dauernd
   steigend). F4 schreibt sie wie gehabt nach `netlog.csv`.
