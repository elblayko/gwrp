--[[
    entities/entities/grid_network_switch_7p/shared.lua
    GridRP 7-Port Enterprise Layer-3 Network Switch (5 Copper + 1 SFP Combo 10G/1G + 1 SFP 10G Uplink)
    Author: Toxic
--]]

ENT.Type = "anim"
ENT.Base = "grid_network_switch_base"
ENT.PrintName = "L3 Network Switch (5-Cu + 1-Combo + 1-SFP)"
ENT.Author = "Toxic"
ENT.Spawnable = true

-- Central Item Quality
ENT.ItemQuality = "epic"
ENT.SwitchColor = Color(168, 85, 247) -- Epic Neon Violet

-- 7-Port Architecture:
-- Ports [1..5]: Dedicated Copper Ethernet (Printers, Computers, Fabricators, Devices)
-- Port [6]: SFP Combo Port (10G for Switches / WAN Uplink, or 1G Copper SFP for Printers)
-- Port [7]: Dedicated SFP 10G Optical Transceiver (Switch-to-Switch Interconnect Only)
ENT.PortDefinitions = {
    { id = 1, type = "copper", speed = "1G",  name = "Port 1", allowSwitch = false, allowDevice = true, allowWAN = true },
    { id = 2, type = "copper", speed = "1G",  name = "Port 2", allowSwitch = false, allowDevice = true, allowWAN = true },
    { id = 3, type = "copper", speed = "1G",  name = "Port 3", allowSwitch = false, allowDevice = true, allowWAN = true },
    { id = 4, type = "copper", speed = "1G",  name = "Port 4", allowSwitch = false, allowDevice = true, allowWAN = true },
    { id = 5, type = "copper", speed = "1G",  name = "Port 5", allowSwitch = false, allowDevice = true, allowWAN = true },
    { id = 6, type = "combo",  speed = "10G", name = "Port 6", allowSwitch = true,  allowDevice = true, allowWAN = true },
    { id = 7, type = "sfp",    speed = "10G", name = "Port 7", allowSwitch = true,  allowDevice = false, allowWAN = false },
}

