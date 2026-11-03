--[[
    cl_deathscreen.lua - Death Screen & Respawn Countdown
--]]

local IsDead = false
local KillerName = "Unknown"
local RespawnTime = 0

net.Receive("GWRP_PlayerDied", function()
    KillerName = net.ReadString()
    local dur = net.ReadUInt(8)
    RespawnTime = CurTime() + dur
    IsDead = true
end)

hook.Add("HUDPaint", "GWRP_DrawDeathScreen", function()
    if not IsDead then return end

    if LocalPlayer():Alive() and CurTime() > RespawnTime then
        IsDead = false
        return
    end

    local scrW, scrH = ScrW(), ScrH()

    -- Dark Red Vignette
    draw.RoundedBox(0, 0, 0, scrW, scrH, Color(15, 0, 0, 215))

    draw.SimpleText("YOU DIED", "GWRP_FontLarge", scrW / 2, scrH / 2 - 40, GWRP.Colors.HealthRed, TEXT_ALIGN_CENTER)
    draw.SimpleText("Killed by: " .. KillerName, "GWRP_FontMedium", scrW / 2, scrH / 2, GWRP.Colors.White, TEXT_ALIGN_CENTER)

    local remaining = math.max(0, math.ceil(RespawnTime - CurTime()))
    draw.SimpleText("Respawning in " .. remaining .. " seconds...", "GWRP_FontSmall", scrW / 2, scrH / 2 + 35, GWRP.Colors.Muted, TEXT_ALIGN_CENTER)
end)
