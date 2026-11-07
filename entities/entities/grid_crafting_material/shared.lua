--[[
    grid_crafting_material/shared.lua - Shared Crafting Material Entity
    Author: Juicebox & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Crafting Material"
ENT.Author = "Juicebox"
ENT.Category = "GridRP - Economy & Items"
ENT.Spawnable = true
ENT.AdminOnly = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "MaterialID")
    self:NetworkVar("Int", 0, "Amount")
    self:NetworkVar("Vector", 0, "TintColor")
end
