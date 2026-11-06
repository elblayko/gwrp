--[[
    cl_deathscreen.lua - High-Legibility Death Screen & Respawn Countdown
    Author: Juicebox & Antigravity
--]]

local IsDead = false
local KillerName = "Unknown"
local RespawnTime = 0

local function HandlePlayerDied()
    KillerName = net.ReadString()
    if not KillerName or KillerName == "" then
        KillerName = "Unknown"
    end
    local dur = net.ReadUInt(8) or 30
    RespawnTime = CurTime() + dur
    IsDead = true

    -- Close F4 menu or dialogs if open
    local ui = GRID and GRID.UI
    if ui and IsValid(ui.F4Frame) then
        ui.F4Frame:Close()
        ui.F4Frame = nil
    end
end

net.Receive("GRID_PlayerDied", HandlePlayerDied)

hook.Add("HUDPaint", "GRID_DrawDeathScreen", function()
    local cur = CurTime()

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- Once player has respawned and is alive again after timer, reset state
    if cur >= RespawnTime and ply:Alive() then
        IsDead = false
        return
    end

    if not IsDead then return end

    -- Smoothly fade out over the final 2 seconds before respawn
    local remaining = RespawnTime - cur
    local fadeWindow = 2.0
    local alphaMult = 1.0

    if remaining <= 0 then
        alphaMult = 0.0
    elseif remaining <= fadeWindow then
        alphaMult = math.Clamp(remaining / fadeWindow, 0, 1)
    end

    if alphaMult <= 0 then return end

    local ui = GRID and GRID.UI
    if ui and ui.CreateFonts then
        ui.CreateFonts()
    end

    local scrW, scrH = ScrW(), ScrH()

    -- Fullscreen Vignette Overlay (Dark Crimson / Obsidian with smooth fade)
    draw.RoundedBox(0, 0, 0, scrW, scrH, Color(11, 15, 25, 235 * alphaMult))

    -- Center Glowing Accent Card (Width: 620, Height: 170)
    local cardW, cardH = math.min(scrW - 40, 620), 170
    local cardX, cardY = (scrW - cardW) / 2, (scrH - cardH) / 2

    draw.RoundedBox(10, cardX, cardY, cardW, cardH, Color(17, 24, 39, 250 * alphaMult))
    draw.RoundedBoxEx(10, cardX, cardY, cardW, 4, Color(239, 68, 68, 255 * alphaMult), true, true, false, false)
    surface.SetDrawColor(239, 68, 68, 90 * alphaMult)
    surface.DrawOutlinedRect(cardX, cardY, cardW, cardH, 1)

    -- "YOU DIED" Title
    draw.SimpleText("YOU DIED", "GRID_UI_Title", scrW / 2, cardY + 32, Color(248, 113, 113, 255 * alphaMult),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Cause of Death / Killer Nickname
    local killerDisplay = (KillerName == "Suicide") and "Cause of Death: Suicide" or ("Eliminated by: " .. KillerName)
    draw.SimpleText(killerDisplay, "GRID_UI_Header", scrW / 2, cardY + 76, Color(248, 250, 252, 255 * alphaMult),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Respawn Status & Countdown
    local secRemaining = math.max(0, math.ceil(remaining))
    local secText = string.format("Respawning in %d second%s...", secRemaining, secRemaining == 1 and "" or "s")
    draw.SimpleText(secText, "GRID_UI_Sub", scrW / 2, cardY + 126, Color(251, 191, 36, 255 * alphaMult),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
