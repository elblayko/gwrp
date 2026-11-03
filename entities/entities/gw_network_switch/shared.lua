--[[
    entities/entities/gw_network_switch/shared.lua
    GWRP 4-Port Layer-3 Network Switch (2 Copper + 1 SFP Combo 10G/1G + 1 SFP 10G Uplink)
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "L3 Network Switch (2-Cu + 2-SFP)"
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
    self:NetworkVar("Bool", 2, "Port3Active")     -- Port 3: SFP Combo Port (10G for Switches/WAN or 1G for Printers)
    self:NetworkVar("Bool", 3, "Port4Active")     -- Port 4: Dedicated 10G SFP Module
    self:NetworkVar("Bool", 4, "Port3Is10G")      -- true: 10G SFP (Switch/WAN), false: 1G Copper (Printers/Devices)
    self:NetworkVar("Entity", 1, "UplinkSwitch")  -- Connected switch on Port 4
    self:NetworkVar("Entity", 2, "Port3Switch")   -- Connected switch on Port 3 (if linked)
    self:NetworkVar("String", 0, "IPAddress")
    self:NetworkVar("Int", 3, "SubnetID")
end
