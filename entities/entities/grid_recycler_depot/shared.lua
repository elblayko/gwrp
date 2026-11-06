--[[
    entities/entities/grid_recycler_depot/shared.lua
    GridRP Street Recycling Depot (Street Sink Appliance)
    Author: Juicebox & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Street Recycling Depot"
ENT.Author = "Juicebox & Antigravity"
ENT.Category = "GridRP Scavenging"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model = "models/props_wasteland/laundry_washer003.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "TotalItemsRecycled")
    self:NetworkVar("Int", 1, "TotalCashPaid")
    self:NetworkVar("Bool", 0, "IsProcessing")
end
