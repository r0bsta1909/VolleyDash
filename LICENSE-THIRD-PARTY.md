# Fremdkomponenten

Volley Dash selbst steht unter der zlib-Lizenz (`LICENSE`). Diese Datei listet alles auf,
was **mitgeliefert** wird, ohne aus diesem Repository zu stammen.

**Stand:** 2026-08-12 · **Bezug:** `12_OPENSOURCE_REPO_SETUP.md` §3, `CLAUDE.md` §7

---

## Im Repository

**Keine.** Volley Dash benutzt keine Fremdbibliothek. Der gesamte Lua-Code unter `src/`,
`tests/` und `tools/` ist projekteigen; Assets siehe `assets/CREDITS.md`.

Das ist eine bewusste Festlegung (`CLAUDE.md` §7): Jede neue Abhängigkeit braucht eine
ADR-Entscheidung und einen Eintrag in dieser Datei. Netzwerk (ab M2) und Serialisierung
laufen über das, was LÖVE bereits mitbringt — `lua-enet`, `luasocket`, `love.data`.

## In den Releasepaketen

Die Pakete unter *Releases* enthalten die LÖVE-Laufzeitumgebung. Sie wird nicht in diesem
Repository mitgeliefert, sondern beim Bauen von [love2d.org](https://love2d.org)
heruntergeladen.

| Komponente | Lizenz | Anmerkung |
|---|---|---|
| LÖVE 11.5 | zlib | `license.txt` liegt jedem Paket bei — Weiterverteilung ohne diese Datei ist nicht zulässig |
| SDL2 | zlib | Teil der LÖVE-Distribution |
| LuaJIT | MIT | Teil der LÖVE-Distribution |
| OpenAL Soft | LGPL 2.1 | Teil der LÖVE-Distribution, dynamisch gelinkt (`OpenAL32.dll`) |
| mpg123 | LGPL 2.1 | Teil der LÖVE-Distribution, dynamisch gelinkt (`mpg123.dll`) |
| lua-enet / ENet | MIT | in `love.dll` enthalten, ab M2 in Gebrauch |
| LuaSocket | MIT | in `love.dll` enthalten, ab M2 in Gebrauch |
| FreeType, libogg, libvorbis, zlib, PhysicsFS u. a. | jeweils frei, siehe `license.txt` | Teil der LÖVE-Distribution |
| Microsoft Visual C++ 2013 Runtime (`msvcp120.dll`, `msvcr120.dll`) | Microsoft-Verteilungsrecht | nur im Windows-Paket, aus dem offiziellen LÖVE-Download |

**Der maßgebliche Text ist die `license.txt` aus dem jeweiligen LÖVE-Download**, die
beiden Paketen unverändert beiliegt. Sie führt die Lizenzen aller in LÖVE gebündelten
Bibliotheken im Wortlaut auf; die Tabelle hier ist eine Orientierung, kein Ersatz.

## Werkzeuge, die nur beim Bauen laufen

Diese landen in keinem Paket und werden nicht weiterverteilt.

| Werkzeug | Lizenz | Wozu |
|---|---|---|
| Info-ZIP `zip` | Info-ZIP-Lizenz (BSD-artig) | packt `.love` und die Pakete |
| Python 3 (Standardbibliothek) | PSF | `tools/patch_plist.py`, `tools/make_icons.py`, `tools/verify_replays.py` |
| Apple `codesign` | Teil von macOS | Ad-hoc-Signatur des `.app` (ADR-012) |
