-- ============================================================================
-- src/render/bracket_view.lua -- Turnieranzeige (M4-08)
--
-- `05_TOURNAMENT` §10. Zwei Ansichten, zwei Zwecke:
--
--   kompakt   Der Bildschirm eines Spielers: die eigene Turnierlinie und
--             "Naechster Gegner". Ein vollstaendiger 32er-Baum ist auf einem
--             Laptop unlesbar -- er steht hier nicht, weil er dort nicht
--             hingehoert.
--   voll      Der Beamer: alles. Gruppentabellen in der Gruppenphase, der Baum
--             im K.o. Laufende Matches hervorgehoben, fertige ausgegraut,
--             aufgerufene blinkend mit Countdown.
--
-- Diese Datei RECHNET NICHTS. Jede Zahl kommt aus `src/tournament/session.lua`
-- -- insbesondere die Restzeit des No-Show-Timers. Eine zweite Rechnung hier
-- waere die, die am Abend danebenliegt.
-- ============================================================================

local World   = require("src.sim.world")
local Assets  = require("src.app.assets")
local Model   = require("src.tournament.model")
local Bracket = require("src.tournament.bracket")
local Session = require("src.tournament.session")

local View = {}

local W, H = World.WIDTH, World.HEIGHT

local COLOR = {
    title    = { 1, 0.85, 0.2 },
    text     = { 1, 1, 1 },
    dim      = { 0.62, 0.62, 0.62 },
    faint    = { 0.42, 0.42, 0.42 },
    live     = { 0.4, 1, 0.5 },
    called   = { 1, 0.85, 0.2 },
    warn     = { 1, 0.45, 0.35 },
    mine     = { 0.5, 0.8, 1 },
}

local function setColor(c, alpha)
    love.graphics.setColor(c[1], c[2], c[3], alpha or 1)
end

local function clip(text, chars)
    text = tostring(text or "")
    if #text <= chars then return text end
    return text:sub(1, chars - 1) .. "."
end

-- Aufgerufene Matches blinken (§10). Eine halbe Sekunde an, eine halbe aus --
-- schnell genug, um im Augenwinkel aufzufallen, langsam genug, um nicht zu
-- flackern.
local function blink(now)
    return (now % 1) < 0.5
end

local function clock(seconds)
    if not seconds then return "" end
    local s = math.floor(seconds + 0.5)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function backdrop()
    love.graphics.setColor(0, 0, 0, 0.88)
    love.graphics.rectangle("fill", 0, 0, W, H)
end

local function statusColor(m, now)
    if m.status == Model.STATUS.LIVE then return COLOR.live end
    if m.status == Model.STATUS.READY then
        return blink(now) and COLOR.called or COLOR.dim
    end
    if Model.TERMINAL[m.status] then return COLOR.faint end
    return COLOR.dim
end

-- ---------------------------------------------------------------------------
-- Bildschirm 1: Wiederaufnahme (§7)
-- ---------------------------------------------------------------------------

local function drawResume(ui)
    backdrop()
    Assets.setFont(40)
    setColor(COLOR.title)
    love.graphics.printf("TURNIER", 0, 70, W, "center")

    Assets.setFont(17)
    setColor(COLOR.text, 0.7)
    love.graphics.printf("Es liegt ein laufendes Turnier im Speicherordner.",
        0, 130, W, "center")

    local items = ui:resumeItems()
    Assets.setFont(20)
    for i, item in ipairs(items) do
        local y = 200 + (i - 1) * 46
        if i == ui.sel then
            setColor(COLOR.text)
            love.graphics.printf("> " .. item.label .. " <", 0, y, W, "center")
        else
            setColor(COLOR.dim)
            love.graphics.printf(item.label, 0, y, W, "center")
        end
        if item.note then
            Assets.setFont(13)
            setColor(COLOR.called, 0.8)
            love.graphics.printf(item.note, 0, y + 24, W, "center")
            Assets.setFont(20)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Bildschirm 2: Anmeldung (§9)
-- ---------------------------------------------------------------------------

local function drawSetup(ui)
    local s = ui:session()
    backdrop()

    Assets.setFont(34)
    setColor(COLOR.title)
    love.graphics.printf("TURNIER ANMELDEN", 0, 24, W, "center")

    local items = ui:setupItems()
    local count = s:count()

    Assets.setFont(15)
    setColor(COLOR.text, 0.6)
    love.graphics.print(string.format("Teilnehmer %d  (%d bis %d)",
        count, Session.MIN_PARTICIPANTS, Session.MAX_PARTICIPANTS), 40, 80)

    -- Links die Liste, rechts die Einstellungen. Zwanzig Namen untereinander
    -- passen nicht auf 600 Pixel, also zwei Spalten zu je zehn.
    local nameIndex = 0
    for i, item in ipairs(items) do
        local selected = (i == ui.sel)

        if item.kind == "add" then
            Assets.setFont(18)
            local text = "+ " .. item.label
            if ui.editing and ui.editing.field == "add" then
                text = "+ " .. ui.editing.buffer .. "_"
                setColor(COLOR.live)
            elseif selected then
                setColor(COLOR.text)
            else
                setColor(COLOR.dim)
            end
            love.graphics.print(text, 40, 104)

        elseif item.kind == "participant" then
            nameIndex = nameIndex + 1
            local col = (nameIndex - 1) >= 10 and 1 or 0
            local row = (nameIndex - 1) % 10
            local x = 44 + col * 200
            local y = 140 + row * 26
            Assets.setFont(16)
            setColor(selected and COLOR.text or COLOR.dim)
            love.graphics.print(string.format("%2d  %s", nameIndex,
                clip(item.label, 18)), x, y)

        else
            -- Einstellungen, Auslosung, Zurueck
            local slot = 0
            for j = 1, i - 1 do
                local kind = items[j].kind
                if kind ~= "add" and kind ~= "participant" then slot = slot + 1 end
            end
            local y = 150 + slot * 54
            -- Nur Werteintraege bekommen eine Ueberschrift. Bei einer Aktion
            -- stuende der Text sonst zweimal untereinander.
            if item.value then
                Assets.setFont(14)
                setColor(COLOR.text, 0.5)
                love.graphics.print(item.label, 470, y)
            end

            Assets.setFont(item.kind == "draw" and 20 or 17)
            if item.kind == "draw" and item.blocked then
                setColor(COLOR.faint)
            elseif selected then
                setColor(COLOR.text)
            else
                setColor(COLOR.dim)
            end

            -- Spitze Klammern nur dort, wo LINKS/RECHTS wirklich etwas tut.
            -- Auf einem Tippfeld waeren sie ein falsches Versprechen -- dieselbe
            -- Unterscheidung wie im Hauptmenue (`src/ui/menu.lua`).
            local text = item.label
            if item.cycle then
                text = "< " .. item.value .. " >"
            elseif item.value then
                text = item.value
            end
            if item.kind == "seed" and ui.editing and ui.editing.field == "seed" then
                text = ui.editing.buffer .. "_"
                setColor(COLOR.live)
            end
            if item.kind == "draw" or item.kind == "back" then
                text = (selected and "> " or "  ") .. item.label
            end
            love.graphics.print(text, 470, y + 18)

            if item.kind == "draw" and item.note then
                Assets.setFont(12)
                setColor(COLOR.called, 0.8)
                love.graphics.printf(item.note, 470, y + 42, 300, "left")
            end
        end
    end

    Assets.setFont(13)
    setColor(COLOR.text, 0.4)
    love.graphics.printf(
        ui.editing and "Name tippen, ENTER traegt ein, ESC beendet die Eingabe"
        or "HOCH/RUNTER waehlt, LINKS/RECHTS aendert, ENTF streicht, ENTER bestaetigt",
        0, H - 34, W, "center")
end

-- ---------------------------------------------------------------------------
-- Bildschirm 3a: kompakt -- die eigene Linie (§10)
-- ---------------------------------------------------------------------------

local STATUS_TEXT = {
    pending  = "angesetzt",
    ready    = "DU BIST DRAN",
    live     = "laeuft",
    finished = "",
    walkover = "kampflos",
    bye      = "Freilos",
}

local function drawCompact(ui, now)
    local s = ui:session()
    backdrop()

    Assets.setFont(30)
    setColor(COLOR.title)
    love.graphics.printf(s.t.name or "Turnier", 0, 26, W, "center")

    local me = s:selfId()
    local line = s:playerLine(me)

    Assets.setFont(15)
    setColor(COLOR.text, 0.55)
    if me then
        love.graphics.printf(string.format("%s   Setznummer %s",
            s:nameOf(me), tostring(line.seed or "-")), 0, 66, W, "center")
    else
        love.graphics.printf("Du spielst nicht mit -- F2 zeigt das ganze Turnier",
            0, 66, W, "center")
    end

    -- Die eigene Linie
    local y = 118
    Assets.setFont(17)
    for _, row in ipairs(line.rows) do
        local m = row.match
        setColor(statusColor(m, now))
        love.graphics.print(clip(row.label, 16), 70, y)
        setColor(Model.TERMINAL[m.status] and COLOR.faint or COLOR.text)
        love.graphics.print("gegen " .. clip(row.opponent or "?", 14), 250, y)

        if Model.TERMINAL[m.status] then
            setColor(row.won and COLOR.live or COLOR.warn)
            love.graphics.print(row.won and "Sieg" or "Niederlage", 470, y)
            setColor(COLOR.faint)
            love.graphics.print(s:scoreText(m), 590, y)
        else
            setColor(statusColor(m, now))
            love.graphics.print(STATUS_TEXT[m.status] or m.status, 470, y)
        end
        y = y + 28
    end

    if #line.rows == 0 then
        setColor(COLOR.dim)
        love.graphics.printf("Noch kein Match angesetzt.", 0, y, W, "center")
    end

    -- Naechster Gegner. Das ist die Zeile, wegen der dieser Bildschirm
    -- existiert -- entsprechend gross.
    local nextMatch = line.next
    if nextMatch then
        local opponent = nextMatch.slotB
        if nextMatch.slotB == me then opponent = nextMatch.slotA end
        Assets.setFont(16)
        setColor(COLOR.text, 0.5)
        love.graphics.printf("Naechster Gegner", 0, 400, W, "center")

        Assets.setFont(38)
        setColor(nextMatch.status == Model.STATUS.READY
                 and statusColor(nextMatch, now) or COLOR.mine)
        love.graphics.printf(s:nameOf(opponent) or "steht noch nicht fest",
            0, 424, W, "center")

        local left = s:remaining(nextMatch, now)
        if left then
            Assets.setFont(22)
            setColor(left <= Session.WARN_SECONDS and COLOR.warn or COLOR.called)
            love.graphics.printf(
                s:isPaused(nextMatch.id)
                and ("Timer angehalten  " .. clock(left))
                or ("Du hast noch " .. clock(left)), 0, 472, W, "center")
        end
    elseif s:isFinished() then
        Assets.setFont(30)
        setColor(COLOR.title)
        love.graphics.printf("Sieger: " .. tostring(s:winnerName()), 0, 420, W, "center")
    elseif line.status == Model.PARTICIPANT_STATUS.ELIMINATED then
        Assets.setFont(24)
        setColor(COLOR.faint)
        love.graphics.printf("Ausgeschieden -- freies Spiel geht jederzeit",
            0, 424, W, "center")
    else
        Assets.setFont(20)
        setColor(COLOR.dim)
        love.graphics.printf("Warte auf die naechste Runde", 0, 424, W, "center")
    end
end

-- ---------------------------------------------------------------------------
-- Bildschirm 3b: voll -- der Beamer (§10)
-- ---------------------------------------------------------------------------

local function drawHeader(ui, s)
    Assets.setFont(24)
    setColor(COLOR.title)
    love.graphics.print(clip(s.t.name, 28), 20, 14)

    Assets.setFont(13)
    setColor(COLOR.text, 0.5)
    love.graphics.print(string.format("%s   %d Teilnehmer",
        Session.FORMAT_LABEL[s.t.format] or s.t.format, s:count()), 20, 44)

    -- Der sichtbare Seed (§9). Er steht hier, damit niemand behaupten kann,
    -- das Bracket sei manipuliert -- Text und Zahl, weil die Zahl reicht, um
    -- die Auslosung nachzurechnen.
    setColor(COLOR.text, 0.45)
    local seed = s.t.seedMode == "random"
        and string.format("Seed \"%s\" = %d", tostring(s.t.seedValue),
            Bracket.seedNumber(s.t.seedValue or ""))
        or "Setzung: Reihenfolge der Anmeldung"
    love.graphics.printf(seed, W - 420, 44, 400, "right")

    if s:isFinished() then
        Assets.setFont(20)
        setColor(COLOR.title)
        love.graphics.printf("SIEGER: " .. tostring(s:winnerName()), W - 420, 16, 400, "right")
    end
end

-- Gruppentabellen (§10: Tabelle statt Baum)
local function drawGroups(ui, s, now, x0, y0, width, height)
    local groups = s.t.groups
    if #groups == 0 then return end

    local cols = (#groups <= 2) and #groups or 3
    local rows = math.ceil(#groups / cols)
    local boxW = math.floor(width / cols)
    local boxH = math.floor(height / rows)

    for gi, members in ipairs(groups) do
        local cx = x0 + ((gi - 1) % cols) * boxW
        local cy = y0 + math.floor((gi - 1) / cols) * boxH

        Assets.setFont(15)
        setColor(COLOR.title)
        love.graphics.print("Gruppe " .. gi, cx, cy)

        local standings = s:standingsOf(gi)
        Assets.setFont(12)
        local y = cy + 22
        local advance = s.t.config.advancePerGroup or 2

        for rank, row in ipairs((standings and standings.rows) or {}) do
            local qualifies = rank <= advance and s.t.format ~= "round_robin"
            setColor(qualifies and COLOR.text or COLOR.dim)
            love.graphics.print(string.format("%d %s", rank, clip(s:nameOf(row.id), 14)),
                cx, y)
            setColor(COLOR.faint)
            love.graphics.print(string.format("%d-%d  %+d", row.wins, row.losses, row.pointDiff),
                cx + 130, y)
            y = y + 17
        end

        if not standings then
            setColor(COLOR.faint)
            for i, pid in ipairs(members) do
                love.graphics.print(clip(s:nameOf(pid), 14), cx, cy + 22 + (i - 1) * 17)
            end
        end

        -- Der Stichsatzhinweis (E-11). Ohne ihn steht am Beamer eine Tabelle,
        -- deren Reihenfolge gerade nicht gilt.
        if s:tiebreakPending(gi) then
            Assets.setFont(11)
            setColor(COLOR.called, 0.9)
            love.graphics.print("Gleichstand -- Stichsatz", cx, y + 2)
        end
    end
end

-- Der K.o.-Baum. Eine Spalte je Runde, die Matches gleichmaessig verteilt.
local function drawTree(ui, s, now, x0, y0, width, height)
    local cols = s:elimColumns()
    if #cols == 0 then return end

    local colW = math.floor(width / #cols)

    for ci, col in ipairs(cols) do
        local cx = x0 + (ci - 1) * colW
        Assets.setFont(12)
        setColor(COLOR.title, 0.8)
        love.graphics.print(clip(col.label, 16), cx, y0)

        local n = #col.matches
        local slotH = math.max(26, math.floor((height - 26) / math.max(n, 1)))
        Assets.setFont(n > 8 and 9 or 11)

        for mi, m in ipairs(col.matches) do
            local y = y0 + 22 + (mi - 1) * slotH
            local color = statusColor(m, now)
            local nameChars = (colW > 130) and 15 or 11

            -- Kein `ipairs({ m.slotA, m.slotB })`: Ist der erste Slot noch
            -- nicht besetzt, hat die Tabelle keinen Folgeteil und die Schleife
            -- laeuft null Mal -- eine unentschiedene Paarung waere im Baum
            -- unsichtbar statt leer. Gemessen an einem 17er-Bracket.
            for side = 1, 2 do
                -- Auch kein `(side == 1) and m.slotA or m.slotB`: Ist `slotA`
                -- nil, faellt der Ausdruck auf `slotB` durch und der Baum
                -- zeigt denselben Namen zweimal.
                local slot = m.slotB
                if side == 1 then slot = m.slotA end
                local isWinner = (m.winner ~= nil and m.winner == slot)
                setColor(isWinner and COLOR.text or color)
                love.graphics.print(clip(s:nameOf(slot) or "-", nameChars),
                    cx, y + (side - 1) * 12)
            end

            if Model.TERMINAL[m.status] then
                setColor(COLOR.faint)
                love.graphics.print(clip(s:scoreText(m), 10), cx + colW - 48, y)
            elseif m.status == Model.STATUS.READY then
                setColor(color)
                love.graphics.print(clock(s:remaining(m, now)), cx + colW - 48, y)
            end

            if m.overridden then
                setColor(COLOR.called)
                love.graphics.print("*", cx + colW - 14, y)
            end
        end
    end
end

-- Die rechte Spalte: die Liste, in der der Turnierleiter auswaehlt. Sie ist
-- zugleich die Liste "Jetzt spielen" (§5) -- laufende und aufgerufene Matches
-- stehen oben, weil `Session:operationList` sie dorthin sortiert.
local function drawSidebar(ui, s, now, x0, y0, width, height)
    love.graphics.setColor(1, 1, 1, 0.06)
    love.graphics.rectangle("fill", x0 - 8, y0 - 8, width + 16, height + 16)

    local list = ui:list()
    local perPage = math.floor(height / 22)
    local first = 1
    if ui.sel > perPage then first = ui.sel - perPage + 1 end

    Assets.setFont(13)
    setColor(COLOR.title)
    love.graphics.print(ui.panel == "participants" and "TEILNEHMER" or "MATCHES", x0, y0)

    Assets.setFont(11)
    local y = y0 + 20

    for i = first, math.min(#list, first + perPage - 1) do
        local entry = list[i]
        local selected = (i == ui.sel)

        if selected then
            love.graphics.setColor(1, 1, 1, 0.14)
            love.graphics.rectangle("fill", x0 - 4, y - 2, width + 8, 20)
        end

        if ui.panel == "participants" then
            local withdrawn = entry.status == Model.PARTICIPANT_STATUS.WITHDRAWN
            setColor(withdrawn and COLOR.faint
                     or (entry.status == Model.PARTICIPANT_STATUS.ELIMINATED
                         and COLOR.dim or COLOR.text))
            love.graphics.print(string.format("%s %s", tostring(entry.seed or "-"),
                clip(entry.name, 16)), x0, y)
            setColor(COLOR.faint)
            love.graphics.print(withdrawn and "raus" or
                string.format("%d-%d", entry.stats.wins, entry.stats.losses), x0 + 132, y)
        else
            local m = entry
            setColor(statusColor(m, now))
            love.graphics.print(clip(string.format("%s %s",
                clip(s:nameOf(m.slotA) or "?", 9), clip(s:nameOf(m.slotB) or "?", 9)), 21),
                x0, y)

            if m.status == Model.STATUS.READY then
                setColor(s:isPaused(m.id) and COLOR.dim or COLOR.warn)
                love.graphics.print(s:isPaused(m.id) and "PAUSE"
                    or clock(s:remaining(m, now)), x0 + 132, y)
            elseif m.status == Model.STATUS.LIVE then
                setColor(COLOR.live)
                love.graphics.print("laeuft", x0 + 132, y)
            elseif Model.TERMINAL[m.status] then
                setColor(COLOR.faint)
                love.graphics.print(clip(s:scoreText(m), 9), x0 + 132, y)
            end
        end
        y = y + 20
    end
end

local function drawDialog(ui, s)
    local d = ui.dialog
    local m = s.t.matches[d.matchId]

    love.graphics.setColor(0.02, 0.02, 0.02, 0.98)
    love.graphics.rectangle("fill", 120, 170, W - 240, 250)
    setColor(COLOR.title, 0.5)
    love.graphics.rectangle("line", 120, 170, W - 240, 250)

    Assets.setFont(20)
    setColor(COLOR.title)
    love.graphics.printf(d.kind == "override" and "ERGEBNIS KORRIGIEREN"
                                               or "ERGEBNIS EINTRAGEN", 0, 190, W, "center")

    Assets.setFont(22)
    setColor(COLOR.text)
    love.graphics.printf(string.format("%s  gegen  %s",
        s:nameOf(m.slotA) or "?", s:nameOf(m.slotB) or "?"), 0, 226, W, "center")

    Assets.setFont(14)
    setColor(COLOR.text, 0.5)
    love.graphics.printf(string.format("%s, Best-of-%d", s:roundLabel(m), m.bestOf or 1),
        0, 254, W, "center")

    Assets.setFont(20)
    local text = {}
    for i, set in ipairs(d.sets) do text[i] = set.a .. ":" .. set.b end
    setColor(COLOR.live)
    love.graphics.printf(table.concat(text, "   "), 0, 288, W, "center")

    if d.phase == "reason" then
        Assets.setFont(15)
        setColor(COLOR.text, 0.6)
        love.graphics.printf("Begruendung (E-12, steht im Log und im Bracket):",
            0, 322, W, "center")
        Assets.setFont(18)
        setColor(COLOR.text)
        love.graphics.printf(d.reason .. "_", 0, 344, W, "center")
    else
        Assets.setFont(26)
        setColor(COLOR.text)
        love.graphics.printf(d.buffer .. "_", 0, 322, W, "center")
        Assets.setFont(13)
        setColor(COLOR.text, 0.45)
        love.graphics.printf("Satz eingeben als 15:12, ENTER uebernimmt",
            0, 358, W, "center")
    end

    Assets.setFont(13)
    setColor(COLOR.text, 0.35)
    love.graphics.printf("ESC bricht ab, RUECKTASTE nimmt zurueck", 0, 388, W, "center")
end

local function drawFull(ui, now)
    local s = ui:session()
    backdrop()
    drawHeader(ui, s)

    local mainW = 560
    if s.t.stage == "elim" then
        drawTree(ui, s, now, 20, 80, mainW, H - 130)
    else
        drawGroups(ui, s, now, 20, 80, mainW, H - 130)
    end

    drawSidebar(ui, s, now, 610, 88, 170, H - 150)

    -- Fusszeile: was ENTER gerade tut, steht ausgeschrieben da.
    local _, actionText = ui:primaryAction()
    Assets.setFont(12)
    setColor(COLOR.text, 0.42)
    love.graphics.print(string.format(
        "TAB %s   ENTER %s   E Ergebnis   K Korrektur   P Timer   A Abbruch   W austragen   F2 Ansicht   ESC zurueck",
        ui.panel == "matches" and "Teilnehmer" or "Matches",
        actionText or "-"), 20, H - 26)
end

-- ---------------------------------------------------------------------------

function View.draw(ui, now)
    now = now or 0

    if ui.mode == "resume" then
        drawResume(ui)
    elseif ui.mode == "setup" then
        drawSetup(ui)
    elseif ui.view == "full" then
        drawFull(ui, now)
    else
        drawCompact(ui, now)
    end

    if ui.dialog then drawDialog(ui, ui:session()) end

    local message = ui:currentMessage()
    if message then
        Assets.setFont(15)
        setColor(COLOR.called)
        love.graphics.printf(message, 0, H - 54, W, "center")
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return View
