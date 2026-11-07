--[[
    entities/entities/grid_practice_stash/cl_init.lua
    GridRP Practice Stash Crate - Client 3D2D Interface
    Author: GRID Core Team & Antigravity
--]]

include("shared.lua")

local COLOR_AMBER       = Color(245, 158, 11)
local COLOR_BG_DARK     = Color(15, 23, 42, 230)
local COLOR_TEXT_WHITE  = Color(248, 250, 252)

function ENT:Draw()
    self:DrawModel()

    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    if lp:EyePos():DistToSqr(self:GetPos()) > (350 * 350) then return end

    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    local pos = self:GetPos() + self:GetUp() * 28 + self:GetForward() * 12

    cam.Start3D2D(pos, ang, 0.08)
        draw.RoundedBox(6, -110, -32, 220, 64, COLOR_BG_DARK)
        surface.SetDrawColor(COLOR_AMBER.r, COLOR_AMBER.g, COLOR_AMBER.b, 200)
        surface.DrawOutlinedRect(-110, -32, 220, 64, 2)

        draw.SimpleText("PRACTICE STASH", "GRID_UI_Header", 0, -12, COLOR_AMBER, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("[LOCKPICK] 4s BREACH TEST", "GRID_UI_Caption", 0, 14, COLOR_TEXT_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

