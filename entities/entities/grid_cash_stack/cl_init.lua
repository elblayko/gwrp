--[[
    entities/entities/grid_cash_stack/cl_init.lua
--]]

include("shared.lua")

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + Vector(0, 0, 8)
    local ang = EyeAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    local dist = EyePos():DistToSqr(pos)
    if dist > 350 * 350 then return end

    local amount = self:GetAmount()
    local text = "$" .. string.Comma(amount)

    cam.Start3D2D(pos, Angle(0, ang.y, 90), 0.08)
        draw.SimpleTextOutlined(text, "GRID_HUD_Small", 0, 0, Color(46, 204, 113, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
    cam.End3D2D()
end
