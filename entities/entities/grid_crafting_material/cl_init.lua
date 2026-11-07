--[[
    grid_crafting_material/cl_init.lua - Client Render & 3D HUD for In-World Materials
    Author: Juicebox & Antigravity
--]]

include("shared.lua")

surface.CreateFont("GRID_UI_BodyBold", {
    font = "Roboto",
    size = 19,
    weight = 700,
    antialias = true,
    extended = true
})

surface.CreateFont("GRID_UI_Badge", {
    font = "Roboto",
    size = 16,
    weight = 700,
    antialias = true,
    extended = true
})

function ENT:Initialize()
end

function ENT:Draw()
    local tintVec = self:GetTintColor()
    if tintVec and (tintVec.x ~= 1 or tintVec.y ~= 1 or tintVec.z ~= 1) then
        render.SetColorModulation(tintVec.x, tintVec.y, tintVec.z)
        self:DrawModel()
        render.SetColorModulation(1, 1, 1)
    else
        self:DrawModel()
    end

    -- 3D2D overhead billboard is handled by grid_base_interactive with ENT.OverheadConfig
    local baseDraw = self.BaseClass and self.BaseClass.Draw
    if baseDraw then
        baseDraw(self)
    end
end
