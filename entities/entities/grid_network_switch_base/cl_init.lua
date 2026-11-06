--[[
    entities/entities/grid_network_switch_base/cl_init.lua
    GridRP Layer-3 Modular Network Switch Abstract Base Client Logic
    Author: Toxic
--]]

include("shared.lua")

function ENT:Draw()
    local col = self.SwitchColor or Color(30, 144, 255)
    render.SetColorModulation(col.r / 255, col.g / 255, col.b / 255)
    self:DrawModel()
    render.SetColorModulation(1, 1, 1)
end

