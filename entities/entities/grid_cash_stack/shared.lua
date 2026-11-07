--[[
    entities/entities/grid_cash_stack/shared.lua
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Cash Stack ($10,000 Debug)"
ENT.Author = "Juicebox"
ENT.Category = "GridRP - Economy & Items"
ENT.Spawnable = true
ENT.AdminOnly = true

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Amount")
end
