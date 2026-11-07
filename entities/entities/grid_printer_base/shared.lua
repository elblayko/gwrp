--[[
    entities/entities/grid_printer_base/shared.lua
    GridRP Contraband Money Printer Abstract Base
    Author: Juicebox
--]]

ENT.Type = "anim"
ENT.Base = "grid_base_interactive"
ENT.PrintName = "Base Money Printer"
ENT.Author = "Juicebox"
ENT.Spawnable = false
ENT.AdminOnly = false
ENT.IsMoneyPrinter = true

-- Default properties to be overridden by concrete printer subclasses
ENT.ItemQuality = "common"
ENT.PrinterTier = 1
ENT.PrintAmount = 4
ENT.PrintInterval = 20.0
ENT.MaxTemp = 100
ENT.PrinterColor = Color(148, 163, 184)
ENT.BountyAmount = 125

-- --------------------------------------------------------
-- Surface-Mounted 3D Plate Display Engine
-- --------------------------------------------------------
ENT.OverheadConfig = {
    Enabled = true,
    FaceCamera = false, -- Flush on the top plate of the printer model
    Offset = Vector(-3, 0, 14.5),
    AngleOffset = Angle(0, 90, 0),
    MaxDistance = 380,
    FadeStart = 260,
    Scale = 0.08,
    CustomDraw = function(self, pos, ang, alpha)
        local qData = self.GetItemQualityData and self:GetItemQualityData()
        local trimCol = qData and qData.color or (self.PrinterColor or (GRID.Colors and GRID.Colors.Border or Color(148, 163, 184)))

        local eff = self.GetEfficiency and self:GetEfficiency() or 60
        if not eff or eff <= 0 then eff = 60 end
        local effCol = (eff >= 100) and Color(52, 211, 153) or ((eff >= 80) and Color(56, 189, 248) or Color(251, 191, 36))

        local now = CurTime()
        local isVenting = self.GetVentActive and self:GetVentActive()
        local isJammed = self.GetValveJammedUntil and (self:GetValveJammedUntil() > now)

        -- Expanded 3D Plate with Generous Padding (240x114)
        draw.RoundedBox(6, -120, -57, 240, 114, Color(15, 23, 42, math.floor(alpha * 0.94)))
        surface.SetDrawColor(30, 41, 59, math.floor(alpha * 0.8))
        surface.DrawOutlinedRect(-120, -57, 240, 114, 1)

        -- Top Accent Line
        draw.RoundedBox(4, -120, -57, 240, 3, Color(trimCol.r, trimCol.g, trimCol.b, alpha))

        -- Printer Name Header
        local whiteCol = (GRID.Colors and GRID.Colors.White) or Color(248, 250, 252)
        draw.SimpleText(self.PrintName or "MONEY PRINTER", "GRID_FontMedium", 0, -36, Color(whiteCol.r, whiteCol.g, whiteCol.b, alpha), TEXT_ALIGN_CENTER)

        if isVenting then
            local duration = math.max(0.1, self:GetVentDuration())
            local progress = math.Clamp((now - self:GetVentStartTime()) / duration, 0, 1)
            local sMin = self:GetVentSweetMin()
            local sMax = self:GetVentSweetMax()
            local inZone = (progress >= sMin and progress <= sMax)

            draw.SimpleText("VENTING IN PROGRESS", "GRID_FontSmall", 0, -10, Color(251, 191, 36, alpha), TEXT_ALIGN_CENTER)

            local barW = 200
            local barH = 16
            local barX = -100
            local barY = 12
            draw.RoundedBox(4, barX, barY, barW, barH, Color(11, 15, 25, math.floor(alpha * 0.9)))
            surface.SetDrawColor(30, 41, 59, math.floor(alpha * 0.7))
            surface.DrawOutlinedRect(barX, barY, barW, barH, 1)

            -- Green Sweet-Spot Highlight
            local greenX = barX + math.floor(sMin * barW)
            local greenW = math.max(6, math.floor((sMax - sMin) * barW))
            draw.RoundedBox(2, greenX, barY + 2, greenW, barH - 4, Color(52, 211, 153, math.floor(alpha * 0.85)))

            -- Moving Cursor Needle
            local needleX = barX + math.floor(progress * barW)
            local needleCol = inZone and Color(52, 211, 153, alpha) or Color(251, 191, 36, alpha)
            draw.RoundedBox(2, needleX - 2, barY - 2, 4, barH + 4, needleCol)

            -- Cue
            local cueTxt = inZone and "HIT [E] NOW!" or "EXHAUST PRESSURE"
            local cueCol = inZone and Color(52, 211, 153, alpha) or Color(148, 163, 184, alpha)
            draw.SimpleText(cueTxt, "GRID_FontSmall", 0, 36, cueCol, TEXT_ALIGN_CENTER)
        elseif isJammed then
            local remain = math.ceil(self:GetValveJammedUntil() - now)
            local moneyCol = (GRID.Colors and GRID.Colors.MoneyGreen) or Color(52, 211, 153)
            draw.SimpleText("$" .. self:GetStoredCash(), "GRID_FontLarge", 0, -8, Color(moneyCol.r, moneyCol.g, moneyCol.b, alpha), TEXT_ALIGN_CENTER)

            draw.RoundedBox(4, -100, 18, 200, 24, Color(239, 68, 68, math.floor(alpha * 0.2)))
            surface.SetDrawColor(239, 68, 68, math.floor(alpha * 0.6))
            surface.DrawOutlinedRect(-100, 18, 200, 24, 1)
            draw.SimpleText("VALVE JAMMED (" .. remain .. "s)", "GRID_FontSmall", 0, 30, Color(248, 113, 113, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            local moneyCol = (GRID.Colors and GRID.Colors.MoneyGreen) or Color(52, 211, 153)
            draw.SimpleText("$" .. self:GetStoredCash(), "GRID_FontLarge", 0, -8, Color(moneyCol.r, moneyCol.g, moneyCol.b, alpha), TEXT_ALIGN_CENTER)

            local temp = self:GetTemperature()
            local healthRed = (GRID.Colors and GRID.Colors.HealthRed) or Color(239, 68, 68)
            local mutedCol = (GRID.Colors and GRID.Colors.Muted) or Color(148, 163, 184)
            local tempCol = temp > 75 and healthRed or mutedCol

            local isUv = self.GetHasUndervolt and self:GetHasUndervolt()
            local isOc = self.GetHasOverclock and self:GetHasOverclock()
            local isTuned = self.GetIsTuned and self:GetIsTuned()
            local tags = {}
            if isUv then table.insert(tags, "UV") end
            if isOc then table.insert(tags, "OC") end
            if isTuned then table.insert(tags, "TUNED") end
            local modTag = #tags > 0 and (" (" .. table.concat(tags, "+") .. ")") or ""
            local tempTxt = "Temp: " .. temp .. "C" .. modTag

            draw.SimpleText(tempTxt, "GRID_FontSmall", -100, 28, Color(tempCol.r, tempCol.g, tempCol.b, alpha), TEXT_ALIGN_LEFT)
            draw.SimpleText("Eff: " .. eff .. "%", "GRID_FontSmall", 100, 28, Color(effCol.r, effCol.g, effCol.b, alpha), TEXT_ALIGN_RIGHT)
        end
    end
}

-- --------------------------------------------------------
-- Look-At Raytrace HUD Card Engine
-- --------------------------------------------------------
ENT.InteractionConfig = {
    Enabled = true,
    MaxUseDistance = 120,
    GetBadge = function(self, ply)
        local now = CurTime()
        if self.GetVentActive and self:GetVentActive() then
            return "VENTING"
        elseif self.GetValveJammedUntil and (self:GetValveJammedUntil() > now) then
            return "JAMMED"
        end
        local qData = self.GetItemQualityData and self:GetItemQualityData()
        return qData and string.upper(qData.name) or "PRINTER"
    end,
    GetBadgeColor = function(self, ply)
        local now = CurTime()
        if self.GetVentActive and self:GetVentActive() then
            return Color(245, 158, 11)
        elseif self.GetValveJammedUntil and (self:GetValveJammedUntil() > now) then
            return Color(239, 68, 68)
        end
        local qData = self.GetItemQualityData and self:GetItemQualityData()
        return qData and qData.color or (self.PrinterColor or Color(52, 211, 153))
    end,
    GetTitle = function(self, ply)
        return self.PrintName or "Money Printer"
    end,
    GetSubtext = function(self, ply)
        local cash = self.GetStoredCash and self:GetStoredCash() or 0
        local temp = self.GetTemperature and self:GetTemperature() or 20
        local eff = self.GetEfficiency and self:GetEfficiency() or 60
        local isUv = self.GetHasUndervolt and self:GetHasUndervolt()
        local isOc = self.GetHasOverclock and self:GetHasOverclock()
        local isTuned = self.GetIsTuned and self:GetIsTuned()
        local tags = {}
        if isUv then table.insert(tags, "UV") end
        if isOc then table.insert(tags, "OC") end
        if isTuned then table.insert(tags, "TUNED") end
        local modTag = #tags > 0 and (" (" .. table.concat(tags, "+") .. ")") or ""
        return string.format("Stored: +$%d  |  Temp: %dC/100C%s  |  Eff: %d%%", cash, temp, modTag, eff)
    end,
    PrimaryAction = function(self, ply)
        if self.GetVentActive and self:GetVentActive() then
            return "Vent Valve"
        end
        return "Collect Cash"
    end,
    PrimaryKey = "E",
    SecondaryAction = function(self, ply)
        local now = CurTime()
        if (self.GetVentActive and self:GetVentActive()) or (self.GetValveJammedUntil and self:GetValveJammedUntil() > now) then
            return nil
        end
        return "Cycle Vent"
    end,
    SecondaryKey = function(self, ply)
        local now = CurTime()
        if (self.GetVentActive and self:GetVentActive()) or (self.GetValveJammedUntil and self:GetValveJammedUntil() > now) then
            return nil
        end
        return "CTRL+E"
    end,
    ShowProgressBar = function(self, ply)
        local now = CurTime()
        local isVenting = self.GetVentActive and self:GetVentActive()
        local isJammed = self.GetValveJammedUntil and (self:GetValveJammedUntil() > now)
        return (isVenting or isJammed) == true
    end,
    GetSweetSpot = function(self, ply)
        local now = CurTime()
        if self.GetVentActive and self:GetVentActive() then
            local duration = math.max(0.1, self:GetVentDuration())
            local progress = math.Clamp((now - self:GetVentStartTime()) / duration, 0, 1)
            local sMin = self:GetVentSweetMin()
            local sMax = self:GetVentSweetMax()
            local inZone = (progress >= sMin and progress <= sMax)
            local hint = inZone and "HIT [E] NOW!" or "TIMING WINDOW"
            return sMin, sMax, inZone, progress, hint, "EXHAUST PRESSURE"
        end
        return nil, nil, false, nil, nil
    end,
    GetProgress = function(self, ply)
        local now = CurTime()
        if (self.GetValveJammedUntil and self:GetValveJammedUntil() > now) then
            local remain = math.ceil(self:GetValveJammedUntil() - now)
            return 1, string.format("VALVE JAMMED (%ds)", remain)
        end
        return 0, ""
    end,
    CanUse = function(self, ply)
        return true
    end
}

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "StoredCash")
    self:NetworkVar("Int", 1, "Temperature")
    self:NetworkVar("Entity", 0, "OwnerPlayer")
    self:NetworkVar("Int", 2, "Efficiency")          -- 60, 80, 100
    self:NetworkVar("Entity", 1, "ConnectedSwitch")
    self:NetworkVar("Int", 3, "NetworkedCount")      -- Active printers on the switch
    self:NetworkVar("Int", 4, "AssignedPort")        -- 1..N (0 if unlinked)
    self:NetworkVar("Bool", 0, "IsTuned")            -- Supercharged by Cyber Engineer (+20% yield, -25% heat)
    self:NetworkVar("Bool", 1, "HasUndervolt")       -- Undervolt hardware module installed
    self:NetworkVar("Bool", 2, "HasOverclock")       -- Overclock hardware module installed (+50% yield, +heat)
    self:NetworkVar("Bool", 3, "VentActive")         -- Active valve sweet-spot sweep in progress
    self:NetworkVar("Float", 0, "VentStartTime")     -- Timestamp when gauge sweep began
    self:NetworkVar("Float", 1, "VentDuration")      -- Duration of gauge sweep (e.g. 1.25s)
    self:NetworkVar("Float", 2, "VentSweetMin")      -- Start of green sweet spot [0.0 - 1.0]
    self:NetworkVar("Float", 3, "VentSweetMax")      -- End of green sweet spot [0.0 - 1.0]
    self:NetworkVar("Float", 4, "ValveJammedUntil")  -- Cooldown after failed/spammed venting
    self:NetworkVar("Float", 5, "LowEmissionUntil")  -- Stealth dampener buff after sweet-spot hit (-30% detection)
    self:NetworkVar("Float", 6, "ThermalSpikeUntil") -- Thermal spike flare after failed/whistle vent (2.5x radar spike)
    self:NetworkVar("String", 0, "IPAddress")        -- Assigned IPv4 address (e.g. 192.168.1.10)
end
