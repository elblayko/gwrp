--[[
    entities/entities/grid_cash_stack/shared.lua
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Cash Stack"
ENT.Author = "Juicebox"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Amount")
end
