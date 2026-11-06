--[[
    entities/entities/grid_network_switch_4p/shared.lua
    GridRP 4-Port Layer-3 Network Switch (2 Copper + 1 SFP Combo 10G/1G + 1 SFP 10G Uplink)
    Author: Juicebox
--]]

ENT.Type = "anim"
ENT.Base = "grid_network_switch_base"
ENT.PrintName = "L3 Network Switch (2-Cu + 2-SFP)"
ENT.Author = "Juicebox"
ENT.Spawnable = true

-- Central Item Quality
ENT.ItemQuality = "uncommon"
ENT.SwitchColor = Color(30, 144, 255) -- Vivid Network Blue

-- Port Layout:
-- Ports [1..2]: Dedicated Copper Ethernet (Printers, Computers, Devices)
-- Port [3]: SFP Combo Port (10G for Switches / WAN Uplink, or 1G Copper SFP for Printers)
-- Port [4]: Dedicated SFP 10G Optical Transceiver (Switch-to-Switch Interconnect Only)
ENT.PortDefinitions = {
    { id = 1, type = "copper", speed = "1G",  name = "Port 1", allowSwitch = false, allowDevice = true,  allowWAN = true },
    { id = 2, type = "copper", speed = "1G",  name = "Port 2", allowSwitch = false, allowDevice = true,  allowWAN = true },
    { id = 3, type = "combo",  speed = "10G", name = "Port 3", allowSwitch = true,  allowDevice = true,  allowWAN = true },
    { id = 4, type = "sfp",    speed = "10G", name = "Port 4", allowSwitch = true,  allowDevice = false, allowWAN = false },
}
