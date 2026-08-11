-- ============================================================================
-- src/input/frame.lua -- kanonisches InputFrame (M0-06, B-03, ADR-014)
--
-- Ein vorzeichenloses Byte je Spieler und Tick. Vollstaendige Festlegung in
-- docs/13_INPUTFRAME_FORMAT.md.
--
--   Bit 0  1  left
--   Bit 1  2  right
--   Bit 2  4  jump
--   Bit 3  8  smash
--   Bit 4 16  dash    (abgeleiteter Impuls, kein Tastendruck)
--   Bit 5-7    reserviert, muessen 0 sein
--
-- love-frei und ohne Bit-Operatoren: Lua 5.1 hat keine, und die Datei soll
-- unter jedem Lua laufen, das der Testrunner benutzt.
-- ============================================================================

local Frame = {}

Frame.LEFT  = 1
Frame.RIGHT = 2
Frame.JUMP  = 4
Frame.SMASH = 8
Frame.DASH  = 16

Frame.MAX = 32   -- alles ab hier ist reserviert

function Frame.has(bits, mask)
    return math.floor(bits / mask) % 2 == 1
end

-- Empfaenger verwerfen ungueltige Frames, statt sie zu maskieren. Stilles
-- Maskieren verdeckt Protokoll- und Versionsfehler (13_INPUTFRAME_FORMAT §2).
function Frame.isValid(bits)
    return type(bits) == "number"
        and bits >= 0
        and bits < Frame.MAX
        and math.floor(bits) == bits
end

function Frame.encode(t)
    local bits = 0
    if t.left  then bits = bits + Frame.LEFT  end
    if t.right then bits = bits + Frame.RIGHT end
    if t.jump  then bits = bits + Frame.JUMP  end
    if t.smash then bits = bits + Frame.SMASH end
    if t.dash  then bits = bits + Frame.DASH  end
    return bits
end

function Frame.decode(bits, into)
    local t = into or {}
    t.left  = Frame.has(bits, Frame.LEFT)
    t.right = Frame.has(bits, Frame.RIGHT)
    t.jump  = Frame.has(bits, Frame.JUMP)
    t.smash = Frame.has(bits, Frame.SMASH)
    t.dash  = Frame.has(bits, Frame.DASH)
    return t
end

-- Steigende Flanke: liegt im aktuellen Tick an, lag im vorigen nicht an.
-- Die Simulation leitet Sprung und andere Ereignisse hieraus ab; die Quelle
-- liefert nur Zustaende (Ausnahme: das dash-Bit, siehe ADR-014).
function Frame.pressed(bits, prev, mask)
    return Frame.has(bits, mask) and not Frame.has(prev, mask)
end

-- Bewegungsrichtung. Beide Richtungen gleichzeitig ergeben LINKS -- gemessenes
-- Verhalten des Prototyps, festgeschrieben in ADR-014 und
-- 13_INPUTFRAME_FORMAT §5. Kein Stillstand.
function Frame.moveDir(bits)
    if Frame.has(bits, Frame.LEFT) then return -1 end
    if Frame.has(bits, Frame.RIGHT) then return 1 end
    return 0
end

function Frame.describe(bits)
    return (Frame.has(bits, Frame.LEFT)  and "L" or "-")
        .. (Frame.has(bits, Frame.RIGHT) and "R" or "-")
        .. (Frame.has(bits, Frame.JUMP)  and "J" or "-")
        .. (Frame.has(bits, Frame.SMASH) and "S" or "-")
        .. (Frame.has(bits, Frame.DASH)  and "D" or "-")
end

return Frame
