--[[
    entities/entities/gw_printer_bronze/shared.lua
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Money Printer"
ENT.Author = "Toxic"
ENT.Spawnable = true

-- Configurable Item Quality
ENT.ItemQuality = "common"
ENT.PrinterTier = 1 -- Tier 1 (Standard)

ENT.PrintAmount = 4
ENT.PrintInterval = 20.0
ENT.MaxTemp = 100
ENT.PrinterColor = Color(148, 163, 184)
ENT.BountyAmount = 125

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "StoredCash")
    self:NetworkVar("Int", 1, "Temperature")
    self:NetworkVar("Entity", 0, "OwnerPlayer")
    self:NetworkVar("Int", 2, "Efficiency")       -- 60, 80, 100
    self:NetworkVar("Entity", 1, "ConnectedSwitch")
    self:NetworkVar("Int", 3, "NetworkedCount")   -- Active printers on the switch
    self:NetworkVar("Int", 4, "AssignedPort")     -- 1, 2, 3 (0 if unlinked)
    self:NetworkVar("Bool", 0, "IsTuned")         -- Supercharged by Cyber Engineer (+20% yield, -25% heat)
    self:NetworkVar("Bool", 1, "HasUndervolt")    -- Undervolt hardware module installed
    self:NetworkVar("Bool", 2, "HasOverclock")    -- Overclock hardware module installed (+50% yield, +heat)
    self:NetworkVar("Bool", 3, "VentActive")      -- Active valve sweet-spot sweep in progress
    self:NetworkVar("Float", 0, "VentStartTime")  -- Timestamp when gauge sweep began
    self:NetworkVar("Float", 1, "VentDuration")   -- Duration of gauge sweep (e.g. 1.3s)
    self:NetworkVar("Float", 2, "VentSweetMin")   -- Start of green sweet spot [0.0 - 1.0]
    self:NetworkVar("Float", 3, "VentSweetMax")   -- End of green sweet spot [0.0 - 1.0]
    self:NetworkVar("Float", 4, "ValveJammedUntil")-- Cooldown after failed/spammed venting
    self:NetworkVar("Float", 5, "LowEmissionUntil")-- Stealth dampener buff after sweet-spot hit (-30% detection)
    self:NetworkVar("Float", 6, "ThermalSpikeUntil")-- Thermal spike flare after failed/whistle vent (2.5x radar spike)
    self:NetworkVar("String", 0, "IPAddress")     -- Assigned IPv4 address (e.g. 192.168.1.10)
end
