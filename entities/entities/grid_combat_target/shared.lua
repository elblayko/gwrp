--[[
    entities/entities/grid_combat_target/shared.lua
    GridRP Syndicate Live-Fire Combat Drone - Shared
    Author: GRID Core Team & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.PrintName = "Syndicate Combat Drone"
ENT.Author = "GRID Core Team & Antigravity"
ENT.Category = "GridRP"

ENT.Spawnable = true
ENT.AdminOnly = true
ENT.IsCombatTarget = true

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "TargetHealth")
    self:NetworkVar("Int", 1, "MaxTargetHealth")
    self:NetworkVar("Bool", 0, "IsActive")
end

