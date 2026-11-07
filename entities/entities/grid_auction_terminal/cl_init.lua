--[[
    entities/entities/grid_auction_terminal/cl_init.lua
    Client 3D2D Display for Auction Terminal (Surface-Mounted Console Display)
    Author: Juicebox & Antigravity
--]]

include("shared.lua")

function ENT:Draw()
    self:DrawModel()

    local ply = LocalPlayer()
    local maxDist = (GRID.Config and GRID.Config.EntityHUDViewDistance) or 320
    if not IsValid(ply) or ply:GetPos():DistToSqr(self:GetPos()) > (maxDist * maxDist) then return end

    -- Angle and position directly on the Combine Interface monitor screen
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 45)

    local pos = self:GetPos() + self:GetUp() * 45 + self:GetForward() * 2

    cam.Start3D2D(pos, ang, 0.055)
    -- Terminal Screen Housing Plate
    draw.RoundedBox(6, -120, -55, 240, 110, Color(11, 15, 25, 245))
    surface.SetDrawColor(30, 41, 59, 220)
    surface.DrawOutlinedRect(-120, -55, 240, 110, 1)

    -- Top Cyan Line
    surface.SetDrawColor(6, 182, 212, 220)
    surface.DrawLine(-120, -54, 120, -54)

    -- Brand & Subtitle
    draw.SimpleText("GRID AUCTION", "GRID_UI_Header", 0, -32, Color(248, 250, 252), TEXT_ALIGN_CENTER)
    draw.SimpleText("MARKETPLACE TERMINAL", "GRID_UI_Caption", 0, -10, Color(34, 211, 238), TEXT_ALIGN_CENTER)

    -- Action Badge
    draw.RoundedBox(4, -85, 12, 170, 28, Color(16, 185, 129, 45))
    surface.SetDrawColor(16, 185, 129, 140)
    surface.DrawOutlinedRect(-85, 12, 170, 28, 1)
    draw.SimpleText("[ PRESS E TO OPEN ]", "GRID_UI_Badge", 0, 26, Color(74, 222, 128), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
