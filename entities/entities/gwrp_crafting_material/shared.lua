--[[
    gwrp_crafting_material/shared.lua - Shared Crafting Material Entity
    Author: Toxic & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Crafting Material"
ENT.Author = "Toxic"
ENT.Category = "GangWars RP"
ENT.Spawnable = true
ENT.AdminOnly = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "MaterialID")
    self:NetworkVar("Int", 0, "Amount")
    self:NetworkVar("Vector", 0, "TintColor")
end
