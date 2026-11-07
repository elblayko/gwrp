--[[
    entities/entities/grid_printer_base/cl_init.lua
    GridRP Contraband Money Printer Abstract Base Client Logic
    Author: Juicebox
--]]

include("shared.lua")

-- ENT:Draw is inherited from grid_base_interactive, executing the surface-mounted ENT.OverheadConfig.CustomDraw


-- Floating Crosshair Reticle (Dual Render HUD)
hook.Add("HUDPaint", "GRID_PrinterValveHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or not (ent.IsMoneyPrinter or (ent.PrintAmount ~= nil) or string.StartWith(ent:GetClass(), "grid_printer_")) then return end
    if ply:GetPos():DistToSqr(ent:GetPos()) > (120 * 120) then return end

    local now = CurTime()
    local isVenting = ent.GetVentActive and ent:GetVentActive()
    local isJammed = ent.GetValveJammedUntil and (ent:GetValveJammedUntil() > now)
    local isDamped = ent.GetLowEmissionUntil and (ent:GetLowEmissionUntil() > now)

    local cx, cy = ScrW() / 2, ScrH() / 2

    if isVenting then
        local duration = math.max(0.1, ent:GetVentDuration())
        local progress = math.Clamp((now - ent:GetVentStartTime()) / duration, 0, 1)
        local sMin = ent:GetVentSweetMin()
        local sMax = ent:GetVentSweetMax()

        local arcR = 36
        local barW = 140
        local barH = 12
        local bx = cx - (barW / 2)
        local by = cy + 28

        draw.RoundedBox(6, bx - 6, by - 6, barW + 12, barH + 12, Color(11, 15, 25, 220))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(bx - 6, by - 6, barW + 12, barH + 12, 1)

        -- Background Track
        draw.RoundedBox(3, bx, by, barW, barH, Color(15, 23, 42, 240))

        -- Sweet spot highlight
        local sx = bx + (sMin * barW)
        local sw = math.max(4, (sMax - sMin) * barW)
        draw.RoundedBox(2, sx, by + 1, sw, barH - 2, Color(16, 185, 129, 200))

        -- Moving cursor
        local nx = bx + (progress * barW)
        local inZone = (progress >= sMin and progress <= sMax)
        local needleCol = inZone and Color(52, 211, 153) or Color(245, 158, 11)
        draw.RoundedBox(2, nx - 2, by - 3, 4, barH + 6, needleCol)

        local hint = inZone and "HIT [E] NOW!" or "EXHAUST PRESSURE"
        local hintCol = inZone and Color(52, 211, 153) or Color(245, 158, 11)
        draw.SimpleText(hint, "GRID_UI_Badge", cx, by + barH + 10, hintCol, TEXT_ALIGN_CENTER)
    elseif isJammed then
        local remain = math.ceil(ent:GetValveJammedUntil() - now)
        draw.SimpleText(string.format("VALVE JAMMED (%ds)", remain), "GRID_UI_Badge", cx, cy + 24, Color(239, 68, 68),
            TEXT_ALIGN_CENTER)
    end
end)
