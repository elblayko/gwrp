--[[
    entities/entities/grid_computer/shared.lua
    GridRP CyberDeck Personal Computer (L3 Terminal Appliance)
    Author: Juicebox
--]]

ENT.Type = "anim"
ENT.Base = "grid_base_interactive"
ENT.PrintName = "Personal Computer Terminal"
ENT.Author = "Juicebox"
ENT.Category = "GridRP - Networking & Cyber"
ENT.Spawnable = true
ENT.AdminOnly = true

-- Central Item Quality
ENT.ItemQuality = "rare"
ENT.IsComputer = true
ENT.ComputerModel = "models/props/cs_office/computer.mdl"

ENT.OverheadConfig = {
    Enabled = true,
    FaceCamera = true,
    Offset = Vector(0, 0, 24),
    MaxDistance = 260,
    FadeStart = 180,
    Scale = 0.08,
    GetTitle = function(self)
        return "CYBERDECK TERMINAL"
    end,
    GetColor = function(self)
        return Color(56, 189, 248)
    end,
    CustomDraw = function(self, pos, ang, alpha)
        local ip = self:GetIPAddress()
        local isNet = IsValid(self:GetConnectedSwitch()) and (ip and ip ~= "")
        local isBotnet = self.GetBotnetActive and self:GetBotnetActive()
        local botnetYield = self.GetBotnetYield and self:GetBotnetYield() or 0
        local statusText = isNet and ("IP: " .. ip) or "OFFLINE (NO CARRIER)"
        local statusCol = isNet and Color(74, 222, 128) or Color(239, 68, 68)

        local boxH = isBotnet and 86 or 68
        local boxY = isBotnet and -43 or -34
        draw.RoundedBox(6, -125, boxY, 250, boxH, Color(15, 23, 42, math.floor(alpha * 0.92)))
        draw.RoundedBox(6, -123, boxY + 2, 246, boxH - 4, Color(30, 41, 59, math.floor(alpha * 0.94)))

        if isBotnet then
            draw.SimpleText("CYBERDECK TERMINAL", "GRID_FontSmall", 0, -33, Color(56, 189, 248, alpha), TEXT_ALIGN_CENTER)
            draw.SimpleText(statusText, "GRID_FontSmall", 0, -15, Color(statusCol.r, statusCol.g, statusCol.b, alpha), TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("BOTNET C2: +$%d / 20s", botnetYield), "GRID_FontSmall", 0, 4, Color(250, 204, 21, alpha), TEXT_ALIGN_CENTER)
            draw.SimpleText("[E] Access Shell", "GRID_FontSmall", 0, 23, Color(148, 163, 184, alpha), TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("CYBERDECK TERMINAL", "GRID_FontSmall", 0, -24, Color(56, 189, 248, alpha), TEXT_ALIGN_CENTER)
            draw.SimpleText(statusText, "GRID_FontSmall", 0, -5, Color(statusCol.r, statusCol.g, statusCol.b, alpha), TEXT_ALIGN_CENTER)
            draw.SimpleText("[E] Access Shell", "GRID_FontSmall", 0, 14, Color(148, 163, 184, alpha), TEXT_ALIGN_CENTER)
        end
    end
}

ENT.InteractionConfig = {
    Enabled = true,
    MaxUseDistance = 120,
    GetBadge = function(self, ply)
        local isBotnet = self.GetBotnetActive and self:GetBotnetActive()
        if isBotnet then return "BOTNET C2" end
        local ip = self:GetIPAddress()
        local isNet = IsValid(self:GetConnectedSwitch()) and (ip and ip ~= "")
        return isNet and "LINKED" or "OFFLINE"
    end,
    GetBadgeColor = function(self, ply)
        local isBotnet = self.GetBotnetActive and self:GetBotnetActive()
        if isBotnet then return Color(250, 204, 21) end
        local ip = self:GetIPAddress()
        local isNet = IsValid(self:GetConnectedSwitch()) and (ip and ip ~= "")
        return isNet and Color(74, 222, 128) or Color(239, 68, 68)
    end,
    GetTitle = function(self, ply)
        return "CyberDeck Terminal"
    end,
    GetSubtext = function(self, ply)
        local ip = self:GetIPAddress()
        local isNet = IsValid(self:GetConnectedSwitch()) and (ip and ip ~= "")
        local isBotnet = self.GetBotnetActive and self:GetBotnetActive()
        if isBotnet then
            return string.format("C2 Active | Yield: +$%d/20s | IP: %s", self:GetBotnetYield() or 0, isNet and ip or "None")
        end
        return isNet and ("Ethernet Connected: " .. ip) or "Offline - Connect to Network Switch"
    end,
    PrimaryAction = "Open Terminal",
    PrimaryKey = "E",
    ShowProgressBar = false,
    CanUse = function(self, ply)
        return true
    end
}

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "IPAddress")
    self:NetworkVar("Entity", 0, "ConnectedSwitch")
    self:NetworkVar("Int", 0, "AssignedPort")
    self:NetworkVar("Entity", 1, "OwnerPlayer")
    self:NetworkVar("Bool", 0, "BotnetActive")
    self:NetworkVar("Int", 1, "BotnetYield")
    self:NetworkVar("Int", 2, "BotnetTotalEarned")
    self:NetworkVar("Entity", 2, "BotnetOperator")
end
