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

        -- Compact Sleek 3D Plate
        draw.RoundedBox(6, -105, -50, 210, 100, Color(15, 23, 42, math.floor(alpha * 0.94)))
        draw.RoundedBox(6, -105, -50, 210, 3, Color(trimCol.r, trimCol.g, trimCol.b, alpha))

        -- Printer Name
        local whiteCol = (GRID.Colors and GRID.Colors.White) or Color(248, 250, 252)
        draw.SimpleText(self.PrintName, "GRID_FontMedium", 0, -32, Color(whiteCol.r, whiteCol.g, whiteCol.b, alpha), TEXT_ALIGN_CENTER)

        if isVenting then
            local duration = math.max(0.1, self:GetVentDuration())
            local progress = math.Clamp((now - self:GetVentStartTime()) / duration, 0, 1)
            local sMin = self:GetVentSweetMin()
            local sMax = self:GetVentSweetMax()

            draw.SimpleText("HIT [E] IN GREEN ZONE", "GRID_FontSmall", 0, -8, Color(251, 191, 36, alpha), TEXT_ALIGN_CENTER)

            local barW = 180
            local barH = 16
            local barX = -90
            local barY = 14
            draw.RoundedBox(4, barX, barY, barW, barH, Color(11, 15, 25, math.floor(alpha * 0.9)))

            local greenX = barX + (sMin * barW)
            local greenW = math.max(6, (sMax - sMin) * barW)
            draw.RoundedBox(2, greenX, barY + 2, greenW, barH - 4, Color(52, 211, 153, math.floor(alpha * 0.85)))

            local needleX = barX + (progress * barW)
            draw.RoundedBox(2, needleX - 2, barY - 2, 4, barH + 4, Color(251, 191, 36, alpha))
        elseif isJammed then
            local remain = math.ceil(self:GetValveJammedUntil() - now)
            local moneyCol = (GRID.Colors and GRID.Colors.MoneyGreen) or Color(52, 211, 153)
            draw.SimpleText("$" .. self:GetStoredCash(), "GRID_FontLarge", 0, -6, Color(moneyCol.r, moneyCol.g, moneyCol.b, alpha), TEXT_ALIGN_CENTER)

            draw.RoundedBox(4, -90, 18, 180, 20, Color(239, 68, 68, math.floor(alpha * 0.2)))
            surface.SetDrawColor(239, 68, 68, math.floor(alpha * 0.6))
            surface.DrawOutlinedRect(-90, 18, 180, 20, 1)
            draw.SimpleText("VALVE JAMMED (" .. remain .. "s)", "GRID_FontSmall", 0, 28, Color(248, 113, 113, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            local moneyCol = (GRID.Colors and GRID.Colors.MoneyGreen) or Color(52, 211, 153)
            draw.SimpleText("$" .. self:GetStoredCash(), "GRID_FontLarge", 0, -4, Color(moneyCol.r, moneyCol.g, moneyCol.b, alpha), TEXT_ALIGN_CENTER)

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

            draw.SimpleText(tempTxt, "GRID_FontSmall", -90, 24, Color(tempCol.r, tempCol.g, tempCol.b, alpha), TEXT_ALIGN_LEFT)
            draw.SimpleText("Eff: " .. eff .. "%", "GRID_FontSmall", 90, 24, Color(effCol.r, effCol.g, effCol.b, alpha), TEXT_ALIGN_RIGHT)
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
        local qData = self.GetItemQualityData and self:GetItemQualityData()
        return qData and string.upper(qData.name) or "PRINTER"
    end,
    GetBadgeColor = function(self, ply)
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
        local uvTag = isUv and " (UV)" or ""
        return string.format("Stored: +$%d  |  Temp: %dC/100C%s  |  Eff: %d%%", cash, temp, uvTag, eff)
    end,
    PrimaryAction = "Collect Cash",
    PrimaryKey = "E",
    SecondaryAction = "Cycle Vent",
    SecondaryKey = "CTRL+E",
    ShowProgressBar = true,
    GetProgress = function(self, ply)
        local now = CurTime()
        if self:GetVentActive() then
            local duration = math.max(0.1, self:GetVentDuration())
            local progress = math.Clamp((now - self:GetVentStartTime()) / duration, 0, 1)
            local sMin = self:GetVentSweetMin()
            local sMax = self:GetVentSweetMax()
            local inZone = (progress >= sMin and progress <= sMax)
            local text = inZone and "HIT [E] NOW! (SWEET SPOT)" or "VENTING IN PROGRESS"
            return progress, text
        elseif (self:GetValveJammedUntil() or 0) > now then
            local remain = math.ceil(self:GetValveJammedUntil() - now)
            return 0, string.format("VALVE JAMMED (%ds)", remain)
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
