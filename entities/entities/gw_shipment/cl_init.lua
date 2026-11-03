--[[
    entities/entities/gw_shipment/cl_init.lua
--]]

include("shared.lua")

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + Vector(0, 0, 15)
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)

    local dist = EyePos():DistToSqr(pos)
    if dist > 400 * 400 then return end

    local name = self:GetWeaponName() or "Weapons"
    local count = self:GetCount() or 0

    cam.Start3D2D(pos, ang, 0.08)
        draw.RoundedBox(4, -130, -60, 260, 120, Color(20, 20, 25, 230))
        surface.SetDrawColor(230, 126, 34)
        surface.DrawOutlinedRect(-130, -60, 260, 120, 2)

        draw.SimpleText("Weapon Crate", "GW_HUD_Small", 0, -45, Color(230, 126, 34), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(name, "GW_HUD_Med", 0, -10, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Remaining: " .. count, "GW_HUD_Small", 0, 25, Color(200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Press E to retrieve into bag", "GW_HUD_Small", 0, 45, Color(46, 204, 113), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
