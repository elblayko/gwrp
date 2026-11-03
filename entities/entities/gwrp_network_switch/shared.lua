--[[
    entities/entities/gwrp_network_switch/shared.lua
    GWRP 4-Port Layer-2 Network Switch (3 Copper Ports + 1 SFP Optical Uplink)
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "L2 Network Switch (3-Port + SFP)"
ENT.Author = "Toxic"
ENT.Spawnable = true

-- Central Item Quality
ENT.ItemQuality = "uncommon"
ENT.SwitchColor = Color(30, 144, 255) -- Vivid Network Blue

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "ConnectedCount")
    self:NetworkVar("Int", 1, "MaxPorts")
    self:NetworkVar("Int", 2, "Efficiency")
    self:NetworkVar("Entity", 0, "OwnerPlayer")
    self:NetworkVar("Bool", 0, "Port1Active")
    self:NetworkVar("Bool", 1, "Port2Active")
    self:NetworkVar("Bool", 2, "Port3Active")
    self:NetworkVar("Bool", 3, "Port4Active") -- Port 4: SFP Module
    self:NetworkVar("Entity", 1, "UplinkSwitch") -- Connected switch entity via SFP
    self:NetworkVar("String", 0, "IPAddress")
    self:NetworkVar("Int", 3, "SubnetID")
end
