--[[
    entities/entities/grid_printer_base/cl_init.lua
    GridRP Contraband Money Printer Abstract Base Client Logic
    Author: Juicebox
--]]

include("shared.lua")

function ENT:Draw()
    self:DrawModel()

    local ply = LocalPlayer()
    local maxDist = (GRID.Config and GRID.Config.EntityHUDViewDistance) or 380
    if not IsValid(ply) or ply:GetPos():DistToSqr(self:GetPos()) > (maxDist * maxDist) then return end

    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)

    local pos = self:GetPos() + self:GetUp() * 14.5 + self:GetForward() * -3

    local qData = self.GetItemQualityData and self:GetItemQualityData()
    local trimCol = qData and qData.color or (self.PrinterColor or GRID.Colors.Border)

    local eff = self.GetEfficiency and self:GetEfficiency() or 60
    if not eff or eff <= 0 then eff = 60 end
    local effCol = (eff >= 100) and Color(52, 211, 153) or ((eff >= 80) and Color(56, 189, 248) or Color(251, 191, 36))

    local now = CurTime()
    local isVenting = self.GetVentActive and self:GetVentActive()
    local isJammed = self.GetValveJammedUntil and (self:GetValveJammedUntil() > now)
    local isDamped = self.GetLowEmissionUntil and (self:GetLowEmissionUntil() > now)

    cam.Start3D2D(pos, ang, 0.08)
    -- Compact Sleek 3D Plate
    draw.RoundedBox(6, -105, -50, 210, 100, Color(15, 23, 42, 240))
    draw.RoundedBox(6, -105, -50, 210, 3, trimCol)

    -- Printer Name
    draw.SimpleText(self.PrintName, "GRID_FontMedium", 0, -32, GRID.Colors.White, TEXT_ALIGN_CENTER)

    if isVenting then
        -- Active Sweet-Spot Pressure Gauge
        local duration = math.max(0.1, self:GetVentDuration())
        local progress = math.Clamp((now - self:GetVentStartTime()) / duration, 0, 1)
        local sMin = self:GetVentSweetMin()
        local sMax = self:GetVentSweetMax()

        draw.SimpleText("HIT [E] IN GREEN ZONE", "GRID_FontSmall", 0, -8, Color(251, 191, 36), TEXT_ALIGN_CENTER)

        -- Track
        local barW = 180
        local barH = 16
        local barX = -90
        local barY = 14
        draw.RoundedBox(4, barX, barY, barW, barH, Color(11, 15, 25, 230))

        -- Green sweet spot zone
        local greenX = barX + (sMin * barW)
        local greenW = math.max(6, (sMax - sMin) * barW)
        draw.RoundedBox(2, greenX, barY + 2, greenW, barH - 4, Color(52, 211, 153, 220))

        -- Needle
        local needleX = barX + (progress * barW)
        draw.RoundedBox(2, needleX - 2, barY - 2, 4, barH + 4, Color(251, 191, 36, 255))
    elseif isJammed then
        -- Valve Jammed Warning
        local remain = math.ceil(self:GetValveJammedUntil() - now)
        draw.SimpleText("$" .. self:GetStoredCash(), "GRID_FontLarge", 0, -6, GRID.Colors.MoneyGreen, TEXT_ALIGN_CENTER)

        draw.RoundedBox(4, -90, 18, 180, 20, Color(239, 68, 68, 35))
        surface.SetDrawColor(239, 68, 68, 140)
        surface.DrawOutlinedRect(-90, 18, 180, 20, 1)
        draw.SimpleText("VALVE JAMMED (" .. remain .. "s)", "GRID_FontSmall", 0, 28, Color(248, 113, 113),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        -- Standard Idle State: Stored Cash & Stats
        draw.SimpleText("$" .. self:GetStoredCash(), "GRID_FontLarge", 0, -4, GRID.Colors.MoneyGreen, TEXT_ALIGN_CENTER)

        local temp = self:GetTemperature()
        local tempCol = temp > 75 and GRID.Colors.HealthRed or GRID.Colors.Muted
        local isUv = self.GetHasUndervolt and self:GetHasUndervolt()
        local isOc = self.GetHasOverclock and self:GetHasOverclock()
        local isTuned = self.GetIsTuned and self:GetIsTuned()
        local tags = {}
        if isUv then table.insert(tags, "UV") end
        if isOc then table.insert(tags, "OC") end
        if isTuned then table.insert(tags, "TUNED") end
        local modTag = #tags > 0 and (" (" .. table.concat(tags, "+") .. ")") or ""
        local tempTxt = "Temp: " .. temp .. "C" .. modTag
        draw.SimpleText(tempTxt, "GRID_FontSmall", -90, 24, tempCol, TEXT_ALIGN_LEFT)
        draw.SimpleText("Eff: " .. eff .. "%", "GRID_FontSmall", 90, 24, effCol, TEXT_ALIGN_RIGHT)
    end
    cam.End3D2D()
end

-- Floating Crosshair Reticle (Dual Render HUD)
hook.Add("HUDPaint", "GRID_PrinterValveHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or not (ent.IsMoneyPrinter or (ent.PrintAmount ~= nil) or string.StartWith(ent:GetClass(), "grid_printer_")) then return end
    if ply:GetPos():DistToSqr(ent:GetPos()) > (120 * 120) then return end

    local now = CurTime()
    local isVenting = ent.GetVentActive and ent:GetVentActive()
    local isJammed = ent.GetValveJammedUntil and (ent:GetValveJammedUntil() > now)
    local isDamped = ent.GetLowEmissionUntil and (ent:GetLowEmissionUntil() > now)

    local cx, cy = ScrW() / 2, ScrH() / 2

    if isVenting then
        local duration = math.max(0.1, ent:GetVentDuration())
        local progress = math.Clamp((now - ent:GetVentStartTime()) / duration, 0, 1)
        local sMin = ent:GetVentSweetMin()
        local sMax = ent:GetVentSweetMax()

        local arcR = 36
        local barW = 140
        local barH = 12
        local bx = cx - (barW / 2)
        local by = cy + 28

        draw.RoundedBox(6, bx - 6, by - 6, barW + 12, barH + 12, Color(11, 15, 25, 220))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(bx - 6, by - 6, barW + 12, barH + 12, 1)

        -- Background Track
        draw.RoundedBox(3, bx, by, barW, barH, Color(15, 23, 42, 240))

        -- Sweet spot highlight
        local sx = bx + (sMin * barW)
        local sw = math.max(4, (sMax - sMin) * barW)
        draw.RoundedBox(2, sx, by + 1, sw, barH - 2, Color(16, 185, 129, 200))

        -- Moving cursor
        local nx = bx + (progress * barW)
        local inZone = (progress >= sMin and progress <= sMax)
        local needleCol = inZone and Color(52, 211, 153) or Color(245, 158, 11)
        draw.RoundedBox(2, nx - 2, by - 3, 4, barH + 6, needleCol)

        local hint = inZone and "HIT [E] NOW!" or "EXHAUST PRESSURE"
        local hintCol = inZone and Color(52, 211, 153) or Color(245, 158, 11)
        draw.SimpleText(hint, "GRID_UI_Badge", cx, by + barH + 10, hintCol, TEXT_ALIGN_CENTER)
    elseif isJammed then
        local remain = math.ceil(ent:GetValveJammedUntil() - now)
        draw.SimpleText(string.format("VALVE JAMMED (%ds)", remain), "GRID_UI_Badge", cx, cy + 24, Color(239, 68, 68),
            TEXT_ALIGN_CENTER)
    end
end)
