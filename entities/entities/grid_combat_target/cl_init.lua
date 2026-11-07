--[[
    entities/entities/grid_combat_target/cl_init.lua
    GridRP Syndicate Live-Fire Combat Drone - Client 3D2D Interface
    Author: GRID Core Team & Antigravity
--]]

include("shared.lua")

local COLOR_CRIMSON    = Color(239, 68, 68)
local COLOR_AMBER      = Color(245, 158, 11)
local COLOR_BG_DARK    = Color(15, 23, 42, 230)
local COLOR_BAR_BG     = Color(30, 41, 59, 240)
local COLOR_TEXT_WHITE = Color(248, 250, 252)

function ENT:Draw()
    if not self:GetIsActive() then return end

    self:DrawModel()

    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    if lp:EyePos():DistToSqr(self:GetPos()) > (450 * 450) then return end

    -- Billboard facing the player camera
    local pos = self:WorldSpaceCenter() + Vector(0, 0, 22)
    local ang = lp:EyeAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    local hp = math.max(0, self:GetTargetHealth())
    local maxHP = math.max(1, self:GetMaxTargetHealth())
    local frac = math.Clamp(hp / maxHP, 0, 1)

    cam.Start3D2D(pos, ang, 0.08)
        -- Container
        draw.RoundedBox(6, -120, -36, 240, 72, COLOR_BG_DARK)
        surface.SetDrawColor(COLOR_CRIMSON.r, COLOR_CRIMSON.g, COLOR_CRIMSON.b, 200)
        surface.DrawOutlinedRect(-120, -36, 240, 72, 2)

        -- Header
        draw.SimpleText("COMBAT DRONE", "GRID_UI_Header", 0, -18, COLOR_CRIMSON, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Health bar background
        local barW, barH = 180, 12
        local barX, barY = -barW / 2, 2
        draw.RoundedBox(3, barX, barY, barW, barH, COLOR_BAR_BG)

        -- Health bar fill
        local fillW = math.floor(barW * frac)
        if fillW > 0 then
            local barCol = (frac > 0.4) and COLOR_AMBER or COLOR_CRIMSON
            draw.RoundedBox(3, barX, barY, fillW, barH, barCol)
        end

        -- Subtitle prompt
        draw.SimpleText("PULL TRIGGER TO DESTROY", "GRID_UI_Caption", 0, 24, COLOR_TEXT_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

