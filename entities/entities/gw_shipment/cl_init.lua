--[[
    entities/entities/gw_shipment/cl_init.lua
    GangWars Weapon Shipment Client 3D2D Display
    Author: GW Core Team
    Namespace: GW / gw_
]]

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
    local price = self:GetUnitPrice() or 0
    local owner = self:GetOwnerPlayer()
    local isOwner = IsValid(owner) and (owner == LocalPlayer())

    cam.Start3D2D(pos, ang, 0.08)
        draw.RoundedBox(4, -130, -65, 260, 130, Color(20, 20, 25, 235))
        surface.SetDrawColor(230, 126, 34)
        surface.DrawOutlinedRect(-130, -65, 260, 130, 2)

        draw.SimpleText("Weapon Shipment Kiosk", "GW_HUD_Small", 0, -48, Color(230, 126, 34), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(name, "GW_HUD_Med", 0, -18, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("Stock: %d | Unit Price: $%d", count, price), "GW_HUD_Small", 0, 15, Color(74, 222, 128), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        if isOwner then
            draw.SimpleText("Owner: Press E to Retrieve | R+E to Adjust Markup", "GW_HUD_Small", 0, 42, Color(245, 158, 11), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText(string.format("Press E to Purchase for $%d", price), "GW_HUD_Small", 0, 42, Color(56, 189, 248), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    cam.End3D2D()
end
