-- ============================================================================
-- src/tournament/export.lua -- der Ausdruck als Versicherung (M4-10)
--
-- `05_TOURNAMENT` §7: "Falls die Software komplett versagt, kann man mit dem
-- Ausdruck weitermachen." Dieser Satz ist die ganze Anforderung, und er
-- bestimmt jede Zeile hier:
--
--   * Der Leser hat KEINE Software mehr. Also stehen hier Namen und keine
--     Kennungen, und ein unentschiedener Platz heisst "Sieger aus Match 7"
--     statt "winner_of:m_7" -- die Herkunft ist genau das, was man braucht,
--     um mit dem Zettel weiterzuspielen.
--   * Die Frage des Abends ist "wer spielt als Naechstes gegen wen?". Sie
--     steht deshalb GANZ OBEN, vor allen Tabellen.
--   * Ein korrigiertes Ergebnis traegt seine Begruendung (E-12). Ein Ausdruck,
--     der die Korrektur verschweigt, ist geschoenter als die Datei -- und beim
--     ersten Streit am Beamer fliegt das auf.
--
-- Hier wird nur Text gebaut, keine Datei geschrieben -- das tut
-- `persistence.lua`, die einzige Datei des Moduls mit Dateizugriff. love-frei,
-- damit der Inhalt headless pruefbar ist.
-- ============================================================================

local Model   = require("src.tournament.model")
local Bracket = require("src.tournament.bracket")

local Export = {}

-- ---------------------------------------------------------------------------
-- Bausteine
-- ---------------------------------------------------------------------------

-- "m_7" -> "Match 7". Die Nummer ist die Sprache des Ausdrucks: Jedes Match
-- steht unter seiner Nummer in der Rundenliste, und "Sieger aus Match 7" ist
-- damit nachschlagbar.
local function matchNumber(id)
    local n = tostring(id or ""):match("^m_(%d+)$")
    return n and ("Match " .. n) or tostring(id)
end

-- Ein Platz in einer Paarung: der Name, wenn er feststeht, sonst die
-- Herkunft. Kein `a and b or c` -- ein leerer Slot ist nil (B-T-04).
local function slotText(s, m, side)
    local pid = m["slot" .. side]
    if pid then return s:nameOf(pid) end

    local kind, target = Bracket.refKind(m["slot" .. side .. "Ref"])
    if kind == "bye" then return "Freilos" end
    if kind == "winner_of" then return "Sieger aus " .. matchNumber(target) end
    if kind == "loser_of" then return "Verlierer aus " .. matchNumber(target) end
    return "offen"
end

local STATUS_TEXT = {
    [Model.STATUS.PENDING] = "wartet",
    [Model.STATUS.READY]   = "aufgerufen",
    [Model.STATUS.LIVE]    = "laeuft",
    [Model.STATUS.ABORTED] = "abgebrochen, wird neu angesetzt",
}

-- Eine Matchzeile: Nummer, Paarung, Ergebnis oder Lage -- und die Korrektur,
-- wenn es eine gab.
local function matchLine(s, m)
    local parts = { string.format("%s: %s gegen %s",
        matchNumber(m.id), slotText(s, m, "A"), slotText(s, m, "B")) }

    if Model.TERMINAL[m.status] then
        local score = s:scoreText(m)
        if score ~= "" then parts[#parts + 1] = score end
        if m.winner then parts[#parts + 1] = "Sieger: " .. s:nameOf(m.winner) end
    else
        parts[#parts + 1] = STATUS_TEXT[m.status] or m.status
    end

    local line = "- " .. table.concat(parts, " -- ")
    if m.overridden then
        line = line .. string.format("  **[korrigiert: %s]**",
            m.overrideReason or "ohne Begruendung")
    end
    return line
end

-- 0 heisst "noch keins gemessen" (Modell) und liest sich als Strich, nicht
-- als Ergebnis.
local function rallyText(v)
    if not v or v == 0 then return "--" end
    return string.format("%.1f s", v)
end

local function ballText(v)
    if not v or v == 0 then return "--" end
    return string.format("%d px/s", math.floor(v + 0.5))
end

-- ---------------------------------------------------------------------------
-- Markdown -- das Blatt fuer den Beamer-Ersatz
-- ---------------------------------------------------------------------------

-- `stamp` ist der Zeitpunkt des Exports als fertiger Text. Er kommt von
-- aussen, damit der Inhalt im Test reproduzierbar ist -- dieselbe Regel wie
-- bei `tick(now)`.
function Export.markdown(s, stamp)
    local t = s.t
    local out = {}
    local function add(fmt, ...)
        out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    end

    add("# %s", t.name)
    add("")

    local head = {}
    if stamp then head[#head + 1] = "Stand: " .. stamp end
    head[#head + 1] = "Format: "
        .. ((s.FORMAT_LABEL and s.FORMAT_LABEL[t.format]) or t.format)
    if t.seedValue and t.seedValue ~= "" then
        head[#head + 1] = string.format("Seed: %s (Zahl %d)",
            t.seedValue, Bracket.seedNumber(t.seedValue))
    end
    add(table.concat(head, " -- "))

    if t.status == Model.TOURNAMENT_STATUS.FINISHED and t.winner then
        add("")
        add("**Sieger: %s**", s:nameOf(t.winner))
    elseif t.status == Model.TOURNAMENT_STATUS.ABORTED then
        add("")
        add("**Turnier abgebrochen%s**",
            t.abortReason and (": " .. t.abortReason) or "")
    end

    -- Als Naechstes: erst was laeuft, dann was aufgerufen ist, dann was
    -- ansteht -- dieselbe Ordnung wie die Bedienliste am Beamer.
    add("")
    add("## Als Naechstes")
    add("")
    local open = 0
    for _, m in ipairs(s:operationList()) do
        if not Model.TERMINAL[m.status] then
            add("%s  (%s)", matchLine(s, m), s:roundLabel(m))
            open = open + 1
        end
    end
    if open == 0 then add("Keine offenen Matches.") end

    -- Gruppentabellen in Beamer-Sortierung (E-11). Der Rang kommt aus
    -- `standingsOf`, nicht aus einer zweiten Rechnung (F-T-09).
    for gi, members in ipairs(t.groups or {}) do
        add("")
        add("## Gruppe %d", gi)
        add("")
        add("| Platz | Name | Siege | Niederl. | Saetze | Punkte |")
        add("|---|---|---|---|---|---|")
        local standings = s:standingsOf(gi)
        for _, row in ipairs((standings and standings.rows) or {}) do
            add("| %d | %s | %d | %d | %d:%d | %d:%d |",
                row.rank, s:nameOf(row.id), row.wins, row.losses,
                row.setsWon, row.setsLost, row.pointsFor, row.pointsAgainst)
        end
        if #members == 0 then add("| | leer | | | | |") end
        if s:tiebreakPending(gi) then
            add("")
            add("Gleichstand auf der Trennlinie -- Stichsatz noetig (E-11).")
        end
    end

    -- Alle Runden mit allen Matches. Das ist der Teil, mit dem man
    -- weiterspielt: Jede Nummer, auf die "Sieger aus Match N" zeigt, steht
    -- hier mit ihrer Paarung.
    for _, r in ipairs(t.rounds or {}) do
        add("")
        add("## %s", r.label or ("Runde " .. r.index))
        add("")
        for _, id in ipairs(r.matches) do
            local m = t.matches[id]
            if m then
                add("%s%s", matchLine(s, m),
                    m.thirdPlace and "  (Spiel um Platz 3)" or "")
            end
        end
    end

    -- Die fuenf Statistiken je Spieler (§11) -- fuer die Siegerehrung, auch
    -- wenn der Rechner sie nicht mehr erlebt.
    add("")
    add("## Statistiken")
    add("")
    add("| Name | Matches (S/N) | Saetze (G/V) | Punkte (fuer:gegen) | Laengste Rallye | Schnellster Ball |")
    add("|---|---|---|---|---|---|")
    for _, pid in ipairs(t.participantOrder) do
        local p = t.participants[pid]
        local st = p.stats
        add("| %s%s | %d (%d/%d) | %d/%d | %d:%d | %s | %s |",
            p.name,
            p.status == Model.PARTICIPANT_STATUS.WITHDRAWN and " (ausgetreten)" or "",
            st.matches, st.wins, st.losses,
            st.setsWon, st.setsLost,
            st.pointsFor, st.pointsAgainst,
            rallyText(st.longestRally), ballText(st.fastestBall))
    end

    add("")
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- CSV -- die Statistiken fuer die Tabellenkalkulation
-- ---------------------------------------------------------------------------

-- Namen sind Benutzereingabe und duerfen Kommas und Anfuehrungszeichen
-- enthalten; alle anderen Felder sind Zahlen aus dem Modell.
local function csvField(v)
    local text = tostring(v)
    if text:find('[",\n]') then
        return '"' .. text:gsub('"', '""') .. '"'
    end
    return text
end

function Export.csv(s)
    local t = s.t
    local out = { "Name,Status,Matches,Siege,Niederlagen,Saetze gewonnen,"
               .. "Saetze verloren,Punkte fuer,Punkte gegen,"
               .. "Laengste Rallye (s),Schnellster Ball (px/s)" }

    for _, pid in ipairs(t.participantOrder) do
        local p = t.participants[pid]
        local st = p.stats
        out[#out + 1] = table.concat({
            csvField(p.name), p.status,
            st.matches, st.wins, st.losses,
            st.setsWon, st.setsLost, st.pointsFor, st.pointsAgainst,
            -- Leer statt 0: "noch keins gemessen" ist kein Messwert.
            st.longestRally ~= 0 and string.format("%.2f", st.longestRally) or "",
            st.fastestBall ~= 0 and string.format("%d", st.fastestBall) or "",
        }, ",")
    end

    out[#out + 1] = ""
    return table.concat(out, "\n")
end

return Export
