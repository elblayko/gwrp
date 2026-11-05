--[[
    entities/entities/gw_shipment/shared.lua
    GangWars Weapon Shipment Kiosk
    Author: GW Core Team
    Namespace: GW / gw_
]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Weapon Shipment"
ENT.Author = "GW Core Team"
ENT.Spawnable = false

-- Configurable Item Quality
ENT.ItemQuality = "rare"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "WeaponClass")
    self:NetworkVar("String", 1, "WeaponName")
    self:NetworkVar("String", 2, "JobAffinity")
    self:NetworkVar("Int", 0, "Count")
    self:NetworkVar("Int", 1, "UnitPrice")
    self:NetworkVar("Entity", 0, "OwnerPlayer")
end
