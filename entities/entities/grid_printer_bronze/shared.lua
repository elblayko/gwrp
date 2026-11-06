--[[
    entities/entities/grid_printer_bronze/shared.lua
    GridRP Bronze Money Printer (Tier 1)
--]]

ENT.Type = "anim"
ENT.Base = "grid_printer_base"
ENT.PrintName = "Money Printer"
ENT.Author = "Juicebox"
ENT.Spawnable = true

-- Configurable Item Quality
ENT.ItemQuality = "common"
ENT.PrinterTier = 1 -- Tier 1 (Bronze Standard)

ENT.PrintAmount = 4
ENT.PrintInterval = 20.0
ENT.MaxTemp = 100
ENT.PrinterColor = Color(148, 163, 184)
ENT.BountyAmount = 125
