--[[
    entities/entities/gwrp_printer_bronze/cl_init.lua
    GWRP Contraband Money Printer Client Logic
--]]

include("shared.lua")

function ENT:Draw()
    self:DrawModel()

    local ply = LocalPlayer()
    local maxDist = (GWRP.Config and GWRP.Config.EntityHUDViewDistance) or 380
    if not IsValid(ply) or ply:GetPos():DistToSqr(self:GetPos()) > (maxDist * maxDist) then return end

    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)

    local pos = self:GetPos() + self:GetUp() * 14.5 + self:GetForward() * -3

    local qData = self.GetItemQualityData and self:GetItemQualityData()
    local trimCol = qData and qData.color or (self.PrinterColor or GWRP.Colors.Border)

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
        draw.SimpleText(self.PrintName, "GWRP_FontMedium", 0, -32, GWRP.Colors.White, TEXT_ALIGN_CENTER)

        if isVenting then
            -- Active Sweet-Spot Pressure Gauge
            local duration = math.max(0.1, self:GetVentDuration())
            local progress = math.Clamp((now - self:GetVentStartTime()) / duration, 0, 1)
            local sMin = self:GetVentSweetMin()
            local sMax = self:GetVentSweetMax()

            draw.SimpleText("HIT [E] IN GREEN ZONE", "GWRP_FontSmall", 0, -8, Color(251, 191, 36), TEXT_ALIGN_CENTER)

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
            draw.SimpleText("$" .. self:GetStoredCash(), "GWRP_FontLarge", 0, -6, GWRP.Colors.MoneyGreen, TEXT_ALIGN_CENTER)

            draw.RoundedBox(4, -90, 18, 180, 20, Color(239, 68, 68, 35))
            surface.SetDrawColor(239, 68, 68, 140)
            surface.DrawOutlinedRect(-90, 18, 180, 20, 1)
            draw.SimpleText("VALVE JAMMED (" .. remain .. "s)", "GWRP_FontSmall", 0, 28, Color(248, 113, 113), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            -- Standard Idle State: Stored Cash & Stats
            draw.SimpleText("$" .. self:GetStoredCash(), "GWRP_FontLarge", 0, -4, GWRP.Colors.MoneyGreen, TEXT_ALIGN_CENTER)

            local temp = self:GetTemperature()
            local tempCol = temp > 75 and GWRP.Colors.HealthRed or GWRP.Colors.Muted
            local isUv = self.GetHasUndervolt and self:GetHasUndervolt()
            local isOc = self.GetHasOverclock and self:GetHasOverclock()
            local isTuned = self.GetIsTuned and self:GetIsTuned()
            local tags = {}
            if isUv then table.insert(tags, "UV") end
            if isOc then table.insert(tags, "OC") end
            if isTuned then table.insert(tags, "TUNED") end
            if isDamped then table.insert(tags, "DAMPED") end
            local modTag = #tags > 0 and (" (" .. table.concat(tags, "+") .. ")") or ""
            local tempTxt = "Temp: " .. temp .. "°C" .. modTag
            draw.SimpleText(tempTxt, "GWRP_FontSmall", -90, 24, tempCol, TEXT_ALIGN_LEFT)
            draw.SimpleText("Eff: " .. eff .. "%", "GWRP_FontSmall", 90, 24, effCol, TEXT_ALIGN_RIGHT)
        end
    cam.End3D2D()
end

-- Floating Crosshair Reticle (Dual Render HUD)
hook.Add("HUDPaint", "GWRP_PrinterValveHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) then return end

    local class = ent:GetClass()
    if not (string.StartWith(class, "gwrp_printer_") or ent.PrintAmount ~= nil or class == "gwrp_resource_machine") then return end
    if tr.HitPos:DistToSqr(ply:EyePos()) > (110 * 110) then return end

    local now = CurTime()
    local isJammed = ent.GetValveJammedUntil and (ent:GetValveJammedUntil() > now)
    local isVenting = ent.GetVentActive and ent:GetVentActive()
    if not isJammed and not isVenting then return end

    local cx, cy = ScrW() / 2, (ScrH() / 2) + 65
    local w, h = 210, 36
    local x, y = cx - (w / 2), cy - (h / 2)

    -- Obsidian Slate Container
    draw.RoundedBox(8, x, y, w, h, Color(11, 15, 25, 245))
    surface.SetDrawColor(30, 41, 59, 230)
    surface.DrawOutlinedRect(x, y, w, h, 1)

    if isJammed then
        local remain = math.ceil(ent:GetValveJammedUntil() - now)
        draw.RoundedBoxEx(8, x, y, w, 2, Color(239, 68, 68, 220), true, true, false, false)
        draw.SimpleText("VALVE OVER-PRESSURIZED", "GWRP_UI_Badge", cx, y + 11, Color(248, 113, 113), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Jammed for " .. remain .. "s", "GWRP_UI_Caption", cx, y + 25, Color(148, 163, 184), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    if isVenting then
        draw.RoundedBoxEx(8, x, y, w, 2, Color(251, 191, 36, 220), true, true, false, false)

        -- Track Bar
        local trackX, trackY = x + 10, y + 18
        local trackW, trackH = w - 20, 10
        draw.RoundedBox(4, trackX, trackY, trackW, trackH, Color(15, 23, 42, 220))
        surface.SetDrawColor(51, 65, 85, 180)
        surface.DrawOutlinedRect(trackX, trackY, trackW, trackH, 1)

        -- Sweet spot green zone
        local sMin = ent:GetVentSweetMin()
        local sMax = ent:GetVentSweetMax()
        local zX = trackX + (sMin * trackW)
        local zW = math.max(6, (sMax - sMin) * trackW)
        draw.RoundedBox(2, zX, trackY + 1, zW, trackH - 2, Color(52, 211, 153, 220))

        -- Needle
        local duration = math.max(0.1, ent:GetVentDuration())
        local progress = math.Clamp((now - ent:GetVentStartTime()) / duration, 0, 1)
        local nX = trackX + (progress * trackW)
        draw.RoundedBox(2, nX - 2, trackY - 2, 4, trackH + 4, Color(251, 191, 36, 255))

        -- Top Title
        draw.SimpleText("TIME EXHAUST: PRESS [E]", "GWRP_UI_Badge", cx, y + 9, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)
