-- ============================================================================
-- src/net/checksum.lua -- Pruefsumme fuer den Desync-Detektor (M3-03)
--
-- `04_NETCODE_SPEC` §9, ADR-018. Der Host rechnet alle 30 Ticks djb2 ueber
-- die GEPACKTEN BYTES des Snapshots, den er gerade verschickt hat. Der Client
-- packt den Snapshot, den er gelesen hat, mit seinem eigenen Code erneut und
-- vergleicht.
--
-- Warum ueber Bytes und nicht ueber Zahlen: Der Host haelt float64, ueber die
-- Leitung gehen float32. Eine Pruefsumme ueber die Zahlen vergliche zwei
-- verschiedene Werte und schluege in jedem Tick an, in dem etwas in Bewegung
-- ist. Eine feste Formatierung verschoebe das nur auf die Rundungsgrenzen --
-- selten genug, um im Test durchzurutschen, haeufig genug, um abends
-- Fehlalarme zu erzeugen. Ueber die gepackten Bytes ist der Weg
-- float32 -> double -> float32 verlustfrei: Fehlalarme sind bauartbedingt
-- ausgeschlossen.
--
-- Und warum das erneute Packen und nicht die empfangenen Rohbytes: die waeren
-- eine Tautologie -- ENet liefert, was es bekommen hat. Erst das Packen aus
-- der GELESENEN Tabelle prueft das Lesen. Der praktische Fall ist der aus §10,
-- den der Build-Hash nur warnt: zwei Rechner mit verschiedenen Feldlisten.
--
-- Derselbe djb2 wie in `src/sim/ruleset.lua` (ADR-016: ein Hash im Projekt,
-- nicht zwei). love-frei -- das Packen selbst braucht `love.data` und bleibt
-- in `protocol.lua`.
-- ============================================================================

local Checksum = {}

-- `04_NETCODE_SPEC` §9. Bei 60 Hz zweimal je Sekunde und Gast.
Checksum.INTERVAL = 30

-- Reine Arithmetik, keine Bit-Bibliothek: Lua 5.1 hat keine, und
-- 2^32 * 33 bleibt exakt in einem double.
function Checksum.ofBytes(data)
    local h = 5381
    for i = 1, #data do
        h = (h * 33 + data:byte(i)) % 4294967296
    end
    return h
end

function Checksum.due(tick)
    return type(tick) == "number" and tick % Checksum.INTERVAL == 0
end

return Checksum
