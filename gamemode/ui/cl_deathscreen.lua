--[[
    cl_deathscreen.lua - Death Screen & Respawn Countdown
--]]

local IsDead = false
local KillerName = "Unknown"
local RespawnTime = 0

net.Receive("GW_PlayerDied", function()
    KillerName = net.ReadString()
    local dur = net.ReadUInt(8)
    RespawnTime = CurTime() + dur
    IsDead = true
end)

hook.Add("HUDPaint", "GW_DrawDeathScreen", function()
    if not IsDead then return end

    if LocalPlayer():Alive() and CurTime() > RespawnTime then
        IsDead = false
        return
    end

    local scrW, scrH = ScrW(), ScrH()

    -- Dark Red Vignette
    draw.RoundedBox(0, 0, 0, scrW, scrH, Color(15, 0, 0, 215))

    draw.SimpleText("YOU DIED", "GW_FontLarge", scrW / 2, scrH / 2 - 40, GW.Colors.HealthRed, TEXT_ALIGN_CENTER)
    draw.SimpleText("Killed by: " .. KillerName, "GW_FontMedium", scrW / 2, scrH / 2, GW.Colors.White, TEXT_ALIGN_CENTER)

    local remaining = math.max(0, math.ceil(RespawnTime - CurTime()))
    draw.SimpleText("Respawning in " .. remaining .. " seconds...", "GW_FontSmall", scrW / 2, scrH / 2 + 35, GW.Colors.Muted, TEXT_ALIGN_CENTER)
end)
