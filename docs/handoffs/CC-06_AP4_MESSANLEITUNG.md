# AP-4 — Messanleitung: Netz-Puffer 1 gegen 2 (Ball im Blob beim Nicht-Host)

**Anlass:** CC-06 §2 AP-4 · **Grundlage:** `04_NETCODE` §8 (Nachtrag 2026-08-14),
`CC-05_REPORT` „Der Ball-Verzug beim Gast" · **Erstellt:** 2026-08-14

**Erst messen, dann ADR, dann Code.** Diese Reihenfolge steht in CC-06 und gilt.
Die Messung braucht **zwei echte Rechner am Kabel** — der CI-Läufer hat ein anderes
Ankunftsmuster als ein Switch, seine Zahlen entscheiden hier nichts.

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
Zahlen gleich aussehen.
