--[[
    gamemode/onboarding/cl_onboarding.lua
    GridRP Burner Pager HUD Tracker & 3D-to-2D Amber Waypoints (GRID.Onboarding)
    Author: GRID Core Team & Antigravity
    Namespace: GRID.Onboarding
--]]

GRID = GRID or {}
GRID.Onboarding = GRID.Onboarding or {}

-- --------------------------------------------------------
-- Visual Assets & Fonts
-- --------------------------------------------------------
surface.CreateFont("GRID_Pager_Title", {
    font = "Trebuchet MS",
    size = 18,
    weight = 800,
    antialias = true
})

surface.CreateFont("GRID_Pager_Header", {
    font = "Roboto",
    size = 16,
    weight = 700,
    antialias = true
})

surface.CreateFont("GRID_Pager_Body", {
    font = "Roboto",
    size = 14,
    weight = 500,
    antialias = true
})

surface.CreateFont("GRID_Pager_Badge", {
    font = "Roboto",
    size = 13,
    weight = 700,
    antialias = true
})

surface.CreateFont("GRID_Waypoint_Large", {
    font = "Trebuchet MS",
    size = 20,
    weight = 800,
    antialias = true
})

surface.CreateFont("GRID_Waypoint_Dist", {
    font = "Roboto",
    size = 15,
    weight = 700,
    antialias = true
})

local COLOR_AMBER       = Color(245, 158, 11)
local COLOR_AMBER_GLOW  = Color(245, 158, 11, 45)
local COLOR_BG_DARK     = Color(15, 23, 42, 240)
local COLOR_BORDER      = Color(245, 158, 11, 180)
local COLOR_TEXT_WHITE  = Color(248, 250, 252)
local COLOR_TEXT_MUTED  = Color(148, 163, 184)
local COLOR_GREEN       = Color(34, 197, 94)

local celebrationBanner = nil
local lastStage = nil
local pingPulseUntil = 0

-- --------------------------------------------------------
-- Network Receivers
-- --------------------------------------------------------
net.Receive("GRID_OnboardingSync", function()
    local stage = net.ReadUInt(4)
    surface.PlaySound("garrysmod/balloon_pop.wav")
end)

net.Receive("GRID_OnboardingCompleted", function()
    local bonus = net.ReadUInt(32)
    surface.PlaySound("garrysmod/save_load1.wav")
    celebrationBanner = {
        bonus = bonus,
        startTime = CurTime(),
        duration = 7.0
    }
end)

net.Receive("GRID_OnboardingGatedAlert", function()
    local action = net.ReadString()
    pingPulseUntil = CurTime() + 3.0
    surface.PlaySound("buttons/button10.wav")
end)

-- --------------------------------------------------------
-- Dynamic Objective Target Locator
-- --------------------------------------------------------
local function GetCurrentObjectiveTarget(stage)
    local targetClass = nil
    if stage == GRID.Onboarding.STAGE_ROOKIE then
        targetClass = "grid_deaddrop_locker"
    elseif stage == GRID.Onboarding.STAGE_DEAD_DROP then
        targetClass = "grid_practice_stash"
    elseif stage == GRID.Onboarding.STAGE_STASH then
        targetClass = "grid_atm"
    else
        return nil
    end

    local lp = LocalPlayer()
    if not IsValid(lp) then return nil end
    local myPos = lp:GetPos()

    local bestEnt = nil
    local bestDistSqr = math.huge

    for _, ent in ipairs(ents.FindByClass(targetClass)) do
        if IsValid(ent) then
            local d = myPos:DistToSqr(ent:GetPos())
            if d < bestDistSqr then
                bestDistSqr = d
                bestEnt = ent
            end
        end
    end

    return bestEnt
end

-- --------------------------------------------------------
-- Draw 3D-to-2D Amber Waypoints (HUDPaint)
-- --------------------------------------------------------
local function DrawAmberWaypoint(targetEnt, stage)
    if not IsValid(targetEnt) then return end

    local lp = LocalPlayer()
    local targetPos = targetEnt:GetPos() + Vector(0, 0, targetEnt:OBBMaxs().z + 16)
    local screenData = targetPos:ToScreen()

    local scrW, scrH = ScrW(), ScrH()
    local x, y = screenData.x, screenData.y
    local isVisible = screenData.visible

    local distUnits = lp:GetPos():Distance(targetEnt:GetPos())
    local distMeters = math.Round(distUnits / 52.49) -- Standard Source unit to meters

    -- Screen-Edge Clamping when behind or off-screen
    local margin = 48
    local clamped = false
    if not isVisible or x < margin or x > (scrW - margin) or y < margin or y > (scrH - margin) then
        clamped = true
        local center = Vector(scrW / 2, scrH / 2, 0)
        local dir = Vector(x - center.x, y - center.y, 0):GetNormalized()
        if not isVisible then
            dir = -dir -- Invert direction if behind player camera
        end
        x = math.Clamp(center.x + dir.x * (scrW / 2 - margin), margin, scrW - margin)
        y = math.Clamp(center.y + dir.y * (scrH / 2 - margin), margin, scrH - margin)
    end

    local pulse = (pingPulseUntil > CurTime()) and (1 + math.sin(CurTime() * 12) * 0.25) or (1 + math.sin(CurTime() * 4) * 0.08)
    local boxW, boxH = 170 * pulse, 46 * pulse
    local drawX, drawY = x - (boxW / 2), y - (boxH / 2)

    -- Glow halo
    draw.RoundedBox(8, drawX - 4, drawY - 4, boxW + 8, boxH + 8, COLOR_AMBER_GLOW)
    draw.RoundedBox(6, drawX, drawY, boxW, boxH, COLOR_BG_DARK)

    surface.SetDrawColor(COLOR_AMBER.r, COLOR_AMBER.g, COLOR_AMBER.b, clamped and 255 or 200)
    surface.DrawOutlinedRect(drawX, drawY, boxW, boxH, 2)

    local trans = GRID.Onboarding.Transmissions[stage]
    local markerLabel = trans and trans.markerText or "OBJECTIVE"

    draw.SimpleText("📍 " .. markerLabel, "GRID_Waypoint_Large", drawX + (boxW / 2), drawY + 12, COLOR_AMBER, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(string.format("%dm away", distMeters), "GRID_Waypoint_Dist", drawX + (boxW / 2), drawY + 30, COLOR_TEXT_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- --------------------------------------------------------
-- Draw Burner Pager HUD Widget
-- --------------------------------------------------------
local function DrawBurnerPager(stage, targetEnt)
    if stage >= GRID.Onboarding.STAGE_COMPLETED then return end

    local scrW, scrH = ScrW(), ScrH()
    local pagerW, pagerH = 340, 140
    local pagerX = scrW - pagerW - 24
    local pagerY = 24

    -- Outer Card Background
    draw.RoundedBox(8, pagerX - 2, pagerY - 2, pagerW + 4, pagerH + 4, COLOR_AMBER_GLOW)
    draw.RoundedBox(6, pagerX, pagerY, pagerW, pagerH, COLOR_BG_DARK)

    surface.SetDrawColor(COLOR_AMBER.r, COLOR_AMBER.g, COLOR_AMBER.b, 220)
    surface.DrawOutlinedRect(pagerX, pagerY, pagerW, pagerH, 2)

    -- Header bar
    draw.RoundedBoxEx(6, pagerX, pagerY, pagerW, 30, Color(245, 158, 11, 40), true, true, false, false)
    draw.SimpleText("📟 FIXER BURNER PAGER // ENCRYPTED", "GRID_Pager_Title", pagerX + 12, pagerY + 15, COLOR_AMBER, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Progress Step Badge
    local stepText = string.format("STEP %d/3", stage + 1)
    draw.RoundedBox(4, pagerX + pagerW - 74, pagerY + 6, 62, 18, COLOR_AMBER)
    draw.SimpleText(stepText, "GRID_Pager_Badge", pagerX + pagerW - 43, pagerY + 15, COLOR_BG_DARK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local trans = GRID.Onboarding.Transmissions[stage]
    if trans then
        draw.SimpleText(trans.objective, "GRID_Pager_Header", pagerX + 12, pagerY + 46, COLOR_TEXT_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Multi-line wrapped briefing
        local wrapped = GRID.UI and GRID.UI.FitText and GRID.UI.FitText(trans.body, "GRID_Pager_Body", pagerW - 24) or trans.body
        draw.SimpleText(wrapped, "GRID_Pager_Body", pagerX + 12, pagerY + 68, COLOR_TEXT_MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    -- Distance / Status line
    if IsValid(targetEnt) then
        local distMeters = math.Round(LocalPlayer():GetPos():Distance(targetEnt:GetPos()) / 52.49)
        draw.SimpleText(string.format("Waypoint: %dm | Marked on HUD", distMeters), "GRID_Pager_Badge", pagerX + 12, pagerY + pagerH - 16, COLOR_AMBER, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    else
        draw.SimpleText("Scanning for target entity on map...", "GRID_Pager_Badge", pagerX + 12, pagerY + pagerH - 16, Color(239, 68, 68), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

-- --------------------------------------------------------
-- Draw Celebration Banner
-- --------------------------------------------------------
local function DrawCelebrationBanner()
    if not celebrationBanner then return end
    local elapsed = CurTime() - celebrationBanner.startTime
    if elapsed > celebrationBanner.duration then
        celebrationBanner = nil
        return
    end

    local alpha = 255
    if elapsed > (celebrationBanner.duration - 1.0) then
        alpha = math.Clamp((celebrationBanner.duration - elapsed) * 255, 0, 255)
    elseif elapsed < 0.5 then
        alpha = math.Clamp((elapsed / 0.5) * 255, 0, 255)
    end

    local scrW = ScrW()
    local bannerW, bannerH = 680, 84
    local bannerX = (scrW - bannerW) / 2
    local bannerY = 80

    draw.RoundedBox(8, bannerX - 3, bannerY - 3, bannerW + 6, bannerH + 6, Color(34, 197, 94, math.floor(alpha * 0.3)))
    draw.RoundedBox(6, bannerX, bannerY, bannerW, bannerH, Color(15, 23, 42, math.floor(alpha * 0.95)))

    surface.SetDrawColor(34, 197, 94, alpha)
    surface.DrawOutlinedRect(bannerX, bannerY, bannerW, bannerH, 2)

    draw.SimpleText("🎉 [SYNDICATE VERIFIED - LEVEL 2]", "GRID_UI_Header", bannerX + (bannerW / 2), bannerY + 26, Color(34, 197, 94, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(string.format("+$%s Clean Bank Secured! Base Building, Careers & Auction House Unlocked!", string.Comma(celebrationBanner.bonus or 3500)), "GRID_UI_Sub", bannerX + (bannerW / 2), bannerY + 56, Color(248, 250, 252, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- --------------------------------------------------------
-- Master HUD Hook
-- --------------------------------------------------------
hook.Add("HUDPaint", "GRID_Onboarding_DrawHUD", function()
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() then return end

    local stage = lp:GetOnboardingStage()

    -- Audio chirp on stage change
    if lastStage ~= nil and lastStage ~= stage and stage < GRID.Onboarding.STAGE_COMPLETED then
        surface.PlaySound("garrysmod/balloon_pop.wav")
    end
    lastStage = stage

    DrawCelebrationBanner()

    if stage < GRID.Onboarding.STAGE_COMPLETED then
        local targetEnt = GetCurrentObjectiveTarget(stage)
        DrawBurnerPager(stage, targetEnt)
        if IsValid(targetEnt) then
            DrawAmberWaypoint(targetEnt, stage)
        end
    end
end)

