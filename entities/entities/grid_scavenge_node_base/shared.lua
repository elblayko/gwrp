--[[
    entities/entities/grid_scavenge_node_base/shared.lua
    GridRP Passive Scavenging Node Abstract Base
    Author: Juicebox & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "grid_base_interactive"
ENT.PrintName = "Base Scavenge Node"
ENT.Author = "Juicebox & Antigravity"
ENT.Spawnable = false
ENT.AdminOnly = false
ENT.IsScavengeNode = true

-- Defaults to be overridden by subclasses
ENT.NodeTier = "trashbin"
ENT.BaseCooldown = 180
ENT.SearchDuration = 1.5

ENT.OverheadConfig = {
    Enabled = false,
}

ENT.InteractionConfig = {
    Enabled = true,
    MaxUseDistance = 160,
    GetBadge = function(self, ply)
        if self:IsOnCooldown() then
            return "PICKED CLEAN"
        elseif self:GetIsSearching() then
            return "SEARCHING"
        end
        return "SALVAGEABLE"
    end,
    GetBadgeColor = function(self, ply)
        if self:IsOnCooldown() then
            return Color(239, 68, 68)
        elseif self:GetIsSearching() then
            return Color(251, 191, 36)
        end
        return Color(52, 211, 153)
    end,
    GetTitle = function(self, ply)
        return self.PrintName or "Scavenge Node"
    end,
    GetSubtext = function(self, ply)
        local tier = self.GetNodeTier and self:GetNodeTier() or "trashbin"
        local tierSubtitles = {
            ["dumpster"] = "Industrial Refuse - High Scrap & Tech",
            ["trashbin"] = "Public Waste Bin - Recyclables & Cash",
            ["scrappile"] = "Metal Salvage Debris - Scrap & Chemicals"
        }
        return tierSubtitles[tier] or "Street Salvage Refuse"
    end,
    PrimaryAction = "Rummage",
    PrimaryKey = "E",
    ShowProgressBar = true,
    GetProgress = function(self, ply)
        if self:GetIsSearching() then
            local duration = math.max(0.1, self:GetSearchDuration() or 1.5)
            local progress = math.Clamp((CurTime() - (self:GetSearchStartTime() or CurTime())) / duration, 0, 1)
            local isMe = (self:GetSearcher() == ply)
            local text = isMe and string.format("RUMMAGING (%d%%)", math.floor(progress * 100)) or "SEARCH IN PROGRESS"
            return progress, text
        elseif self:IsOnCooldown() then
            local remain = self:GetCooldownRemaining()
            local text = string.format("COOLDOWN (%ds)", remain)
            return 0, text
        end
        return 0, ""
    end,
    CanUse = function(self, ply)
        return true
    end
}

function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "CooldownExpires")
    self:NetworkVar("Bool", 0, "IsSearching")
    self:NetworkVar("Float", 1, "SearchStartTime")
    self:NetworkVar("Float", 2, "SearchDuration")
    self:NetworkVar("Entity", 0, "Searcher")
    self:NetworkVar("String", 0, "NodeTier")
end

function ENT:IsOnCooldown()
    return (self:GetCooldownExpires() or 0) > CurTime()
end

function ENT:GetCooldownRemaining()
    return math.max(0, math.ceil((self:GetCooldownExpires() or 0) - CurTime()))
end
