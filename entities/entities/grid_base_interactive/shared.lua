--[[
    entities/entities/grid_base_interactive/shared.lua
    GridRP Unified Interactive Base Entity - Shared Definition
    Author: GRID Core Team & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Interactive Entity"
ENT.Author = "GRID Core Team"
ENT.Spawnable = false
ENT.AdminSpawnable = false
ENT.IsGridInteractive = true

-- --------------------------------------------------------
-- Overhead 3D2D Display Configuration (Child-Overridable)
-- --------------------------------------------------------
ENT.OverheadConfig = {
    Enabled = true,
    Offset = Vector(0, 0, 48),
    AngleOffset = Angle(0, 0, 0),
    FaceCamera = true,
    MaxDistance = 450,
    FadeStart = 300,
    Scale = 0.05,
    Title = "Interactive Node",
    GetTitle = function(self)
        return self.PrintName or self.OverheadConfig.Title or "Interactive Node"
    end,
    GetColor = function(self)
        return Color(52, 211, 153)
    end,
    ShowHealthBar = false,
    ShowProgressBar = false,
    GetProgress = function(self)
        return 0
    end,
    GetCustomText = function(self)
        return nil
    end,
    CustomDraw = nil,
}

-- --------------------------------------------------------
-- Look-At Screen-Space HUD Configuration (Child-Overridable)
-- --------------------------------------------------------
ENT.InteractionConfig = {
    Enabled = true,
    MaxUseDistance = 120,
    Badge = "INTERACTIVE",
    GetBadge = function(self, ply)
        return self.InteractionConfig.Badge or "INTERACTIVE"
    end,
    GetBadgeColor = function(self, ply)
        return Color(52, 211, 153)
    end,
    Title = nil,
    GetTitle = function(self, ply)
        return self.PrintName or "Interactive Entity"
    end,
    Subtext = nil,
    GetSubtext = function(self, ply)
        return self.InteractionConfig.Subtext or ""
    end,
    PrimaryAction = "Interact",
    PrimaryKey = "E",
    SecondaryAction = nil,
    SecondaryKey = nil,
    ShowProgressBar = false,
    GetProgress = function(self, ply)
        return 0, ""
    end,
    CanUse = function(self, ply)
        return true
    end,
}

function ENT:SetupDataTables()
    -- Derived classes may call this or add their own network vars
end

