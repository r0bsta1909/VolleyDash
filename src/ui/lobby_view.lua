-- ============================================================================
-- src/ui/lobby_view.lua -- Lobby-Anzeige fuer beide Rollen (M2-06, M2-07)
--
-- Zwei Dinge stehen hier gross, und beide aus einem Grund:
--
--   Die LAN-Adresse des Hosts. Wenn die Discovery nichts findet -- Firewall,
--   Client-Isolation, zwei Subnetze -- ist das die Zahl, die jemand quer durch
--   den Raum ruft (`04_NETCODE_SPEC` §11).
--
--   Der Abgleichbefund. Drei Pruefungen, drei Konsequenzen (§5, §10), und der
--   Unterschied muss ohne Nachfrage erkennbar sein: Rot heisst "startet
--   nicht", Gelb heisst "geht trotzdem".
-- ============================================================================

local World  = require("src.sim.world")
local Assets = require("src.app.assets")
local Lobby  = require("src.net.lobby")

local LobbyView = {}

local COLOR = {
    [Lobby.SEVERITY.REJECT] = { 1, 0.3, 0.3 },
    [Lobby.SEVERITY.BLOCK]  = { 1, 0.3, 0.3 },
    [Lobby.SEVERITY.WARN]   = { 1, 0.85, 0.2 },
}

function LobbyView.draw(info)
    love.graphics.setColor(0, 0, 0, 0.82)
    love.graphics.rectangle("fill", 0, 0, World.WIDTH, World.HEIGHT)

    Assets.setFont(40)
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf(info.lobbyName or "LOBBY", 0, 44, World.WIDTH, "center")

    Assets.setFont(16)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.printf(
        info.role == "host" and "Du bist Host" or ("Verbunden mit " .. (info.hostName or "?")),
        0, 95, World.WIDTH, "center")

    -- Die Adresse. Nur beim Host, und absichtlich gross.
    if info.role == "host" then
        Assets.setFont(15)
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.printf("Falls die Liste beim Gast leer bleibt:",
            0, 130, World.WIDTH, "center")
        Assets.setFont(34)
        love.graphics.setColor(0.4, 1, 0.6)
        love.graphics.printf(info.address or "?", 0, 152, World.WIDTH, "center")
    end

    -- Slots
    Assets.setFont(22)
    local top = info.role == "host" and 215 or 160
    for i, slot in ipairs(info.slots or {}) do
        local y = top + (i - 1) * 34
        local text, color

        if not slot.occupied then
            text, color = string.format("Platz %d   frei", i), { 0.5, 0.5, 0.5 }
        else
            text = string.format("Platz %d   %s%s   %s", i, slot.name or "?",
                slot.isHost and " (Host)" or "",
                slot.ready and "BEREIT" or "wartet")
            color = slot.ready and { 0.4, 1, 0.5 } or { 1, 1, 1 }
        end

        love.graphics.setColor(color)
        love.graphics.printf(text, 0, y, World.WIDTH, "center")
    end

    -- Regelwerk: es kommt vom Host und gilt fuer beide (ADR-005).
    Assets.setFont(17)
    love.graphics.setColor(1, 1, 1, 0.65)
    love.graphics.printf(string.format("Regelwerk %s   (Hash %s)",
        info.preset or "?", tostring(info.rulesetHash)),
        0, top + 90, World.WIDTH, "center")

    -- Der Host hat den Namen abgewandelt, weil er schon vergeben war. Das
    -- muss dastehen: sonst sucht jemand im Turnierbaum nach einem Namen, unter
    -- dem er nie gespielt hat.
    if info.renamed then
        Assets.setFont(17)
        love.graphics.setColor(1, 0.85, 0.2)
        love.graphics.printf("Der Name war vergeben -- du spielst als \""
            .. info.renamed .. "\"", 0, top + 112, World.WIDTH, "center")
    end

    -- Befunde des Abgleichs
    local y = top + 145
    Assets.setFont(16)
    for _, finding in ipairs(info.findings or {}) do
        love.graphics.setColor(COLOR[finding.severity] or { 1, 1, 1 })
        love.graphics.printf(finding.text, 60, y, World.WIDTH - 120, "center")
        y = y + 38
    end

    if info.error then
        love.graphics.setColor(1, 0.3, 0.3)
        Assets.setFont(18)
        love.graphics.printf(info.error, 60, y, World.WIDTH - 120, "center")
        y = y + 40
    end

    Assets.setFont(14)
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.printf(info.hint or "", 0, World.HEIGHT - 58, World.WIDTH, "center")
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.printf("ESC verlaesst die Lobby", 0, World.HEIGHT - 32, World.WIDTH, "center")
    love.graphics.setColor(1, 1, 1, 1)
end

return LobbyView
