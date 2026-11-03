--[[
    entities/entities/gw_computer/shared.lua
    GWRP CyberDeck Personal Computer (L3 Terminal Appliance)
    Author: Toxic
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Personal Computer"
ENT.Author = "Toxic"
ENT.Spawnable = true

-- Central Item Quality
ENT.ItemQuality = "rare"
ENT.IsComputer = true
ENT.ComputerModel = "models/props/cs_office/computer.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "IPAddress")
    self:NetworkVar("Entity", 0, "ConnectedSwitch")
    self:NetworkVar("Int", 0, "AssignedPort")
    self:NetworkVar("Entity", 1, "OwnerPlayer")
end
