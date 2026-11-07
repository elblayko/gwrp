--[[
    entities/entities/grid_printer_diamond/shared.lua
    GridRP Diamond Money Printer (Tier 3)
--]]

ENT.Type = "anim"
ENT.Base = "grid_printer_base"
ENT.PrintName = "Diamond Money Printer"
ENT.Author = "Juicebox"
ENT.Category = "GridRP - Contraband Printers"
ENT.Spawnable = true
ENT.AdminOnly = true

-- Configurable Item Quality
ENT.ItemQuality = "rare"
ENT.PrinterTier = 3 -- Tier 3 (Diamond)

ENT.PrintAmount = 25
ENT.PrintInterval = 20.0
ENT.MaxTemp = 100
ENT.PrinterColor = Color(56, 189, 248)
ENT.BountyAmount = 1000
