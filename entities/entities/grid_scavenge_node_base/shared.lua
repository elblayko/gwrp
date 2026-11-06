--[[
    entities/entities/grid_scavenge_node_base/shared.lua
    GridRP Passive Scavenging Node Abstract Base
    Author: Juicebox & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Base Scavenge Node"
ENT.Author = "Juicebox & Antigravity"
ENT.Spawnable = false
ENT.AdminOnly = false
ENT.IsScavengeNode = true

-- Defaults to be overridden by subclasses
ENT.NodeTier = "trashbin"
ENT.BaseCooldown = 180
ENT.SearchDuration = 1.5

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
