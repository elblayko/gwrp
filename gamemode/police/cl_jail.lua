--[[
    gamemode/police/cl_jail.lua
    GridRP Jail, Sentence, Bail & Holding Cell System - Client HUD & ESP
    Author: GRID Core Team
--]]

include("sh_jail.lua")

GRID.Jail.ClientPoints = GRID.Jail.ClientPoints or {}
GRID.Jail.ClientReleasePoint = GRID.Jail.ClientReleasePoint or nil

net.Receive("GRID_JailSyncPoints", function()
    local count = net.ReadUInt(16)
    local pts = {}
    for i = 1, count do
        local pos = net.ReadVector()
        local ang = net.ReadAngle()
        table.insert(pts, { pos = pos, ang = ang })
    end
    local hasRelease = net.ReadBool()
    local rel = nil
    if hasRelease then
        rel = { pos = net.ReadVector(), ang = net.ReadAngle() }
    end

    GRID.Jail.ClientPoints = pts
    GRID.Jail.ClientReleasePoint = rel

    if GRID.Jail.OnPointsUpdated then
        GRID.Jail.OnPointsUpdated()
    end
end)

-- Bail Action Requester
function GRID.Jail.RequestPayBail(targetEnt)
    net.Start("GRID_JailPayBail")
    net.WriteEntity(targetEnt or LocalPlayer())
    net.SendToServer()
end

-- ========================================================
-- 1. PRISONER SENTENCE SCREEN-SPACE OVERLAY
-- ========================================================

hook.Add("HUDPaint", "GRID_JailSentenceHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or not ply:IsJailed() then return end

    local scrW, scrH = ScrW(), ScrH()
    local rem = ply:GetJailTimeRemaining()
    local bail = ply:GetJailBail()

    local cardW, cardH = 360, 110
    local cardX = (scrW - cardW) / 2
    local cardY = 32

    -- Obsidian Glassmorphic Card
    draw.RoundedBox(8, cardX, cardY, cardW, cardH, Color(11, 15, 25, 240))
    surface.SetDrawColor(30, 41, 59, 200)
    surface.DrawOutlinedRect(cardX, cardY, cardW, cardH, 1)

    -- Top Amber Warning Stripe
    draw.RoundedBoxEx(4, cardX, cardY, cardW, 3, Color(239, 68, 68), true, true, false, false)

    -- Header Badge
    draw.SimpleText("POLICE HOLDING CELL", "GRID_UI_Badge", cardX + cardW / 2, cardY + 12, Color(239, 68, 68), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    -- Sentence Timer
    local timerText = string.format("Sentence Remaining: %02d:%02d", math.floor(rem / 60), rem % 60)
    draw.SimpleText(timerText, "GRID_UI_Header", cardX + cardW / 2, cardY + 36, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    -- Bail Information & Prompt
    local bailText = string.format("Bail Bond: $%s  |  Type /paybail to post bail", string.Comma(bail))
    draw.SimpleText(bailText, "GRID_UI_Caption", cardX + cardW / 2, cardY + 74, Color(148, 163, 184), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end)

-- ========================================================
-- 2. ADMIN 3D ESP JAIL CELL RENDERING
-- ========================================================

hook.Add("PostDrawTranslucentRenderables", "GRID_JailAdmin3DESP", function(bDepth, bSkybox)
    if bDepth or bSkybox then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then return end
    if not GRID.Turf or not GRID.Turf.AdminESPEnabled then return end

    local pts = GRID.Jail.ClientPoints or {}
    for idx, pt in ipairs(pts) do
        local pos = pt.pos
        local dist = ply:EyePos():DistToSqr(pos)
        if dist > 3500 * 3500 then continue end

        local col = Color(245, 158, 11, 200)

        -- 3D cylinder/point marker
        render.DrawLine(pos, pos + Vector(0, 0, 72), col, true)

        local ang = (ply:EyePos() - pos):Angle()
        ang.p = 0
        ang.r = 0
        ang:RotateAroundAxis(ang:Up(), 90)
        ang:RotateAroundAxis(ang:Forward(), 90)

        cam.Start3D2D(pos + Vector(0, 0, 80), ang, 0.1)
            draw.RoundedBox(4, -80, -20, 160, 40, Color(15, 23, 42, 230))
            draw.RoundedBox(4, -80, -20, 160, 2, col)
            draw.SimpleText(string.format("Jail Cell #%d", idx), "GRID_FontSmall", 0, -5, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        cam.End3D2D()
    end

    if GRID.Jail.ClientReleasePoint then
        local pos = GRID.Jail.ClientReleasePoint.pos
        local col = Color(52, 211, 153, 200)
        render.DrawLine(pos, pos + Vector(0, 0, 72), col, true)

        local ang = (ply:EyePos() - pos):Angle()
        ang.p = 0
        ang.r = 0
        ang:RotateAroundAxis(ang:Up(), 90)
        ang:RotateAroundAxis(ang:Forward(), 90)

        cam.Start3D2D(pos + Vector(0, 0, 80), ang, 0.1)
            draw.RoundedBox(4, -80, -20, 160, 40, Color(15, 23, 42, 230))
            draw.RoundedBox(4, -80, -20, 160, 2, col)
            draw.SimpleText("Jail Release Point", "GRID_FontSmall", 0, -5, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        cam.End3D2D()
    end
end)

