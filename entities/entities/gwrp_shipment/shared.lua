--[[
    entities/entities/gwrp_shipment/shared.lua
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Weapon Shipment"
ENT.Author = "Toxic"
ENT.Spawnable = false

-- Configurable Item Quality
ENT.ItemQuality = "rare"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "WeaponClass")
    self:NetworkVar("String", 1, "WeaponName")
    self:NetworkVar("Int", 0, "Count")
end
