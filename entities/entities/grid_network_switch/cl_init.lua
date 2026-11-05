--[[
    entities/entities/grid_network_switch/cl_init.lua
    GridRP 4-Port Layer-3 Network Switch Client Logic
--]]

include("shared.lua")

function ENT:Draw()
    local col = self.SwitchColor or Color(30, 144, 255)
    render.SetColorModulation(col.r / 255, col.g / 255, col.b / 255)
    self:DrawModel()
    render.SetColorModulation(1, 1, 1)
end
