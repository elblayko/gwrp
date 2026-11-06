--[[
    grid_resource_machine/cl_init.lua - Client 3D World HUD, Temperature Gauge & Venting
    Author: Juicebox & Antigravity
--]]

include("shared.lua")

surface.CreateFont("GRID_UI_BodyBold", {
    font = "Roboto",
    size = 19,
    weight = 700,
    antialias = true,
    extended = true
})

surface.CreateFont("GRID_UI_Badge", {
    font = "Roboto",
    size = 16,
    weight = 700,
    antialias = true,
    extended = true
})

function ENT:Initialize()
    self.HumSound = CreateSound(self, "ambient/levels/labs/machine_moving_loop1.wav")
    if self.HumSound then
        self.HumSound:SetSoundLevel(55)
        self.HumSound:Play()
    end
end

function ENT:OnRemove()
    if self.HumSound then
        self.HumSound:Stop()
    end
end

function ENT:Draw()
    self:DrawModel()

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local maxDist = (GRID.Config and GRID.Config.EntityHUDViewDistance) or 380
    if ply:GetPos():DistToSqr(self:GetPos()) > (maxDist * maxDist) then return end

    local ang = ply:EyeAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    local center = self:OBBCenter()
    local maxs = self:OBBMaxs()
    local drawPos = self:LocalToWorld(Vector(center.x, center.y, maxs.z + 18))

    local now = CurTime()
    local hasItem = self:GetHasReadyItem()
    local readyName = self:GetReadyItemName()
    local eff = self:GetEfficiency()
    if not eff or eff <= 0 then eff = 60 end

    local curHP = self:GetMachineHealth()
    local maxHP = self:GetMaxMachineHealth()
    if maxHP <= 0 then maxHP = 500 end

    local curTemp = self.GetTemperature and self:GetTemperature() or 20
    local isVenting = self.GetVentActive and self:GetVentActive()
    local isJammed = self.GetValveJammedUntil and (self:GetValveJammedUntil() > now)

    local start = self:GetCycleStartTime()
    local dur = self:GetCycleDuration()
    local progress = 0
    local remaining = 0
    if dur > 0 then
        local elapsed = now - start
        progress = math.Clamp(elapsed / dur, 0, 1)
        remaining = math.max(0, math.ceil(dur - elapsed))
    end

    local isNet = IsValid(self:GetConnectedSwitch())
    local ip = self:GetIPAddress()
    local port = self:GetAssignedPort()

    cam.Start3D2D(drawPos, Angle(0, ang.y, 90), 0.08)
    local w, h = 340, 195
    local x, y = -w / 2, -h / 2

    -- Obsidian Glassmorphic Background
    draw.RoundedBox(8, x, y, w, h, Color(11, 15, 25, 240))
    surface.SetDrawColor(30, 41, 59, 230)
    surface.DrawOutlinedRect(x, y, w, h, 1)

    -- Top brand header
    draw.RoundedBoxEx(8, x, y, w, 32, Color(17, 24, 39, 255), true, true, false, false)
    surface.SetDrawColor(6, 182, 212, 160)
    surface.DrawLine(x, y + 32, x + w, y + 32)

    draw.SimpleText("RESOURCE FABRICATOR", "GRID_UI_BodyBold", x + 14, y + 16, Color(248, 250, 252), TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)

    surface.SetFont("GRID_UI_Badge")
    local bText = "LEGAL TECH"
    local bTextW = surface.GetTextSize(bText)
    local badgeW = bTextW + 18
    local badgeH = 20
    local badgeX = x + w - badgeW - 12
    local badgeY = y + 6

    draw.RoundedBox(4, badgeX, badgeY, badgeW, badgeH, Color(16, 185, 129, 30))
    surface.SetDrawColor(16, 185, 129, 140)
    surface.DrawOutlinedRect(badgeX, badgeY, badgeW, badgeH, 1)
    draw.SimpleText(bText, "GRID_UI_Badge", badgeX + badgeW / 2, badgeY + badgeH / 2, Color(52, 211, 153),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- ========================================================
    -- MIDDLE SECTION: VENTING GAUGE, READY ITEM, OR SYNTHESIS
    -- ========================================================
    if isVenting then
        -- Active Sweet-Spot Pressure Gauge
        local duration = math.max(0.1, self:GetVentDuration())
        local vProgress = math.Clamp((now - self:GetVentStartTime()) / duration, 0, 1)
        local sMin = self:GetVentSweetMin()
        local sMax = self:GetVentSweetMax()

        draw.SimpleText("HIT [E] IN GREEN ZONE", "GRID_UI_Badge", 0, y + 46, Color(251, 191, 36), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)

        -- Track
        local barW = w - 28
        local barH = 16
        local barX = x + 14
        local barY = y + 58
        draw.RoundedBox(4, barX, barY, barW, barH, Color(15, 23, 42, 240))
        surface.SetDrawColor(51, 65, 85, 200)
        surface.DrawOutlinedRect(barX, barY, barW, barH, 1)

        -- Green sweet spot zone
        local greenX = barX + (sMin * barW)
        local greenW = math.max(6, (sMax - sMin) * barW)
        draw.RoundedBox(2, greenX, barY + 2, greenW, barH - 4, Color(52, 211, 153, 220))

        -- Moving Needle
        local needleX = barX + (vProgress * barW)
        draw.RoundedBox(2, needleX - 2, barY - 2, 4, barH + 4, Color(251, 191, 36, 255))
    elseif isJammed then
        -- Valve Jammed Warning Alert
        local remain = math.ceil(self:GetValveJammedUntil() - now)
        draw.RoundedBox(6, x + 12, y + 40, w - 24, 46, Color(239, 68, 68, 25))
        surface.SetDrawColor(239, 68, 68, 160)
        surface.DrawOutlinedRect(x + 12, y + 40, w - 24, 46, 1)

        draw.SimpleText("RELIEF VALVE JAMMED", "GRID_UI_Badge", 0, y + 53, Color(248, 113, 113), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("Over-pressurized for %ds", remain), "GRID_UI_BodyBold", 0, y + 71,
            Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    elseif hasItem then
        local pulse = math.abs(math.sin(now * 4))
        local pulseCol = Color(74 + math.floor(pulse * 60), 222, 128)

        draw.RoundedBox(6, x + 12, y + 40, w - 24, 46, Color(16, 185, 129, 25))
        surface.SetDrawColor(pulseCol.r, pulseCol.g, pulseCol.b, 180)
        surface.DrawOutlinedRect(x + 12, y + 40, w - 24, 46, 1)

        draw.SimpleText("★ RESOURCE READY ON TOP ★", "GRID_UI_Badge", 0, y + 53, pulseCol, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
        draw.SimpleText(readyName ~= "" and readyName or "Crafting Material", "GRID_UI_BodyBold", 0, y + 71,
            Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        -- Status label & timer header
        draw.SimpleText("SYNTHESIZING MATERIAL", "GRID_UI_Badge", x + 14, y + 46, Color(148, 163, 184), TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("%ds (%d%%)", remaining, math.floor(progress * 100)), "GRID_UI_Badge", x + w - 14,
            y + 46, Color(34, 211, 238), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        -- Progress Bar Container
        draw.RoundedBox(4, x + 12, y + 58, w - 24, 14, Color(15, 23, 42, 255))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(x + 12, y + 58, w - 24, 14, 1)

        -- Fill
        local fillW = math.floor((w - 28) * progress)
        if fillW > 0 then
            draw.RoundedBox(3, x + 14, y + 60, fillW, 10, Color(6, 182, 212, 220))
        end
    end

    -- Network line
    local netY = y + 92
    if isNet then
        local netText = string.format("L3 Linked: Port %d  |  %s  |  %d%% Speed", port,
            (ip ~= "" and ip or "192.168.1.x"), eff)
        draw.SimpleText(netText, "GRID_UI_Badge", x + 14, netY, Color(52, 211, 153), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    else
        draw.SimpleText("Standalone (60% Speed)", "GRID_UI_Badge", x + 14, netY, Color(245, 158, 11), TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
    end

    -- ========================================================
    -- TEMPERATURE & INTEGRITY SECTION
    -- ========================================================
    local tempCol = (curTemp >= 75) and Color(239, 68, 68) or
    ((curTemp >= 50) and Color(245, 158, 11) or Color(74, 222, 128))
    local hpTextY = y + 114

    draw.SimpleText(string.format("Core Temp: %d°C / 100°C", curTemp), "GRID_UI_Badge", x + 14, hpTextY, tempCol,
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(string.format("Integrity: %d / %d HP", curHP, maxHP), "GRID_UI_Badge", x + w - 14, hpTextY,
        Color(248, 250, 252), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

    local hpBarY = y + 128
    local hpFrac = math.Clamp(curHP / maxHP, 0, 1)
    draw.RoundedBox(3, x + 12, hpBarY, w - 24, 8, Color(15, 23, 42, 255))
    draw.RoundedBox(3, x + 12, hpBarY, math.floor((w - 24) * hpFrac), 8, Color(239, 68, 68, 220))

    -- Bottom prompt
    local promptY = y + h - 28
    draw.RoundedBoxEx(8, x, promptY, w, 28, Color(17, 24, 39, 220), false, false, true, true)
    surface.SetDrawColor(30, 41, 59, 180)
    surface.DrawLine(x, promptY, x + w, promptY)

    local promptText = "[E] Open Crafting Workbench / Collect"
    local promptColor = Color(248, 250, 252)

    if isVenting then
        promptText = "TIME EXHAUST: PRESS [E] IN GREEN ZONE"
        promptColor = Color(251, 191, 36)
    elseif isJammed then
        promptText = "[Shift+E] Open Crafting  (Valve Jammed)"
        promptColor = Color(248, 113, 113)
    elseif curTemp > 20 then
        promptText = "[E] Vent Pressure  |  [Shift+E] Open Crafting"
        promptColor = Color(251, 191, 36)
    end

    draw.SimpleText(promptText, "GRID_UI_Badge", 0, promptY + 14, promptColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
