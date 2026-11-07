--[[
    entities/entities/grid_shipment/shared.lua
    GridRP Weapon Shipment Kiosk
    Author: GRID Core Team
    Namespace: GRID / grid_
]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Weapon Shipment"
ENT.Author = "GRID Core Team"
ENT.Category = "GridRP - Economy & Items"
ENT.Spawnable = true
ENT.AdminOnly = true

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
