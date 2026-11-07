--[[
    entities/entities/grid_atm/shared.lua
    GridRP Street ATM Banking Terminal - Shared
    Author: GRID Core Team & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "grid_base_interactive"
ENT.PrintName = "Street ATM"
ENT.Author = "Juicebox & Antigravity"
ENT.Category = "GridRP - World Infrastructure"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.IsPersistentMapEntity = true
ENT.TransmitAlways = true

ENT.OverheadConfig = {
    Enabled = true,
    FaceCamera = true,
    Offset = Vector(0, 0, 50),
    MaxDistance = 350,
    FadeStart = 240,
    Scale = 0.08,
    GetTitle = function(self)
        return "STREET ATM"
    end,
    GetColor = function(self)
        return Color(34, 197, 94)
    end,
    GetCustomText = function(self)
        return "Personal Banking & Wire Vault"
    end
}

ENT.InteractionConfig = {
    Enabled = true,
    MaxUseDistance = 120,
    Badge = "BANKING",
    GetBadgeColor = function(self, ply)
        return Color(34, 197, 94)
    end,
    GetTitle = function(self, ply)
        return "Street ATM Terminal"
    end,
    GetSubtext = function(self, ply)
        local bank = ply.GetBank and ply:GetBank() or 0
        return string.format("Secure Wire Network  |  Vault Balance: $%s", string.Comma(bank))
    end,
    PrimaryAction = "Access Bank",
    PrimaryKey = "E",
    ShowProgressBar = false,
    CanUse = function(self, ply)
        return true
    end
}

