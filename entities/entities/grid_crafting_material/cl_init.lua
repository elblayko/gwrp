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

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local myPos = self:GetPos()
    local distSqr = ply:EyePos():DistToSqr(myPos)
    if distSqr > (220 * 220) then return end

    -- Raycast check to ensure player is looking towards the item
    local aim = ply:GetAimVector()
    local dir = (myPos - ply:EyePos()):GetNormalized()
    if aim:Dot(dir) < 0.65 then return end

    local matId = self:GetMaterialID()
    if not matId or matId == "" then matId = "crafting_ingot_zinc" end

    local def = GRID.Crafting and GRID.Crafting.Materials and GRID.Crafting.Materials[matId]
    local itemName = def and def.name or matId
    local itemAmount = self:GetAmount() or 1
    local qColor = (GRID.Inventory and GRID.Inventory.GetQualityColor and GRID.Inventory.GetQualityColor(def and def.quality or 1)) or
    Color(248, 250, 252)

    local ang = ply:EyeAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    local drawPos = myPos + Vector(0, 0, 14)

    cam.Start3D2D(drawPos, Angle(0, ang.y, 90), 0.08)
    local w, h = 180, 50
    local x, y = -w / 2, -h / 2

    -- Glassmorphic container
    draw.RoundedBox(6, x, y, w, h, Color(11, 15, 25, 230))
    surface.SetDrawColor(30, 41, 59, 220)
    surface.DrawOutlinedRect(x, y, w, h, 1)

    -- Top accent glow matching quality
    draw.RoundedBox(2, x + 4, y + 3, w - 8, 2, qColor)

    -- Title & count
    draw.SimpleText(string.format("%dx %s", itemAmount, itemName), "GRID_UI_BodyBold", 0, y + 16, qColor,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Interaction prompt
    draw.SimpleText("[E] Collect into Bag", "GRID_UI_Badge", 0, y + 36, Color(148, 163, 184), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
