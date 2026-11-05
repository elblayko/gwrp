--[[
    entities/entities/grid_wan_uplink/shared.lua
    GridRP Encrypted Satellite WAN Uplink
    Author: Toxic
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Satellite WAN Uplink"
ENT.Author = "Toxic"
ENT.Spawnable = true

ENT.ItemQuality = "rare"
ENT.ItemSubType = "Wireless Gateway"
ENT.IsNetworkDevice = true
ENT.IsWANUplink = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "EncryptionKey")
    self:NetworkVar("String", 1, "IPAddress")
    self:NetworkVar("Entity", 0, "ConnectedSwitch")
    self:NetworkVar("Int", 0, "AssignedPort")
    self:NetworkVar("Int", 1, "LinkedPeerCount")
    self:NetworkVar("Bool", 0, "IsOnline")
end
