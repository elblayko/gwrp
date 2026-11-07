--[[
    entities/entities/grid_printer_base/cl_init.lua
    GridRP Contraband Money Printer Abstract Base Client Logic
    Author: Juicebox
--]]

include("shared.lua")

-- ENT:Draw and Look-At HUD card interactions are inherited from grid_base_interactive.
-- Surface 3D plate rendering executes via ENT.OverheadConfig.CustomDraw.
-- Redundant floating reticle gauge (GRID_PrinterValveHUD) removed in favor of the unified Look-At HUD card.
