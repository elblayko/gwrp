--[[
    entities/entities/grid_flag_pole/shared.lua
--]]

ENT.Type = "anim"
ENT.Base = "grid_base_interactive"
ENT.PrintName = "Turf Flag Pole"
ENT.Author = "Juicebox"
ENT.Category = "GridRP - World Infrastructure"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.IsPersistentMapEntity = true
ENT.RenderGroup = RENDERGROUP_BOTH

-- Exempt Gameplay Objective (No Item Quality)
ENT.NoQuality = true

ENT.OverheadConfig = {
    Enabled = true,
    FaceCamera = true,
    Offset = Vector(0, 0, 115),
    MaxDistance = 950,
    FadeStart = 750,
    Scale = 0.05,
    CustomDraw = function(self, pos, ang, alpha)
        if self.DrawBillboardContents then
            self:DrawBillboardContents(pos, ang, alpha)
        end
    end
}

ENT.InteractionConfig = {
    Enabled = true,
    MaxUseDistance = 140,
    GetBadge = function(self, ply)
        local id = self:GetTurfID()
        local zone = GRID.Turf and GRID.Turf.Zones and GRID.Turf.Zones[id]
        local owner = zone and zone.owner or "neutral"
        if self:GetIsCapturing() then
            return "CONTESTED"
        end
        return (owner ~= "" and owner ~= "neutral") and "CONTROLLED" or "UNCLAIMED"
    end,
    GetBadgeColor = function(self, ply)
        local id = self:GetTurfID()
        local zone = GRID.Turf and GRID.Turf.Zones and GRID.Turf.Zones[id]
        local owner = zone and zone.owner or "neutral"
        if self:GetIsCapturing() then
            return Color(245, 158, 11)
        end
        if owner ~= "" and owner ~= "neutral" and GRID.GetGangColor then
            return GRID.GetGangColor(owner)
        end
        return Color(52, 211, 153)
    end,
    GetTitle = function(self, ply)
        local id = self:GetTurfID()
        local zone = GRID.Turf and GRID.Turf.Zones and GRID.Turf.Zones[id]
        return zone and zone.name or ("Territory #" .. id)
    end,
    GetSubtext = function(self, ply)
        local id = self:GetTurfID()
        local zone = GRID.Turf and GRID.Turf.Zones and GRID.Turf.Zones[id]
        local owner = zone and zone.owner or "neutral"
        local tax = zone and zone.tax_rate or 10
        if owner ~= "" and owner ~= "neutral" then
            return string.format("Controlled by: %s  |  Extortion Tax: %d%%", string.upper(owner), tax)
        end
        return "Unclaimed District - Ripe for Syndicate Takeover"
    end,
    PrimaryAction = "Contest Turf",
    PrimaryKey = "E",
    ShowProgressBar = true,
    GetProgress = function(self, ply)
        if self:GetIsCapturing() then
            local st = self:GetCaptureStartTime()
            local et = self:GetCaptureEndTime()
            if et > st then
                local progress = math.Clamp((CurTime() - st) / (et - st), 0, 1)
                local gang = self:GetCapturingGang() or "Syndicate"
                return progress, string.format("CONTESTING: %d%% (%s)", math.floor(progress * 100), gang)
            end
        end
        return 0, ""
    end,
    CanUse = function(self, ply)
        return true
    end
}

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "TurfID")
    self:NetworkVar("Bool", 0, "IsCapturing")
    self:NetworkVar("Float", 0, "CaptureStartTime")
    self:NetworkVar("Float", 1, "CaptureEndTime")
    self:NetworkVar("Entity", 0, "CapturingPlayer")
    self:NetworkVar("String", 0, "CapturingGang")
    self:NetworkVar("Int", 1, "CaptureRadius")
    self:NetworkVar("Int", 2, "InfluenceRadius")
end
