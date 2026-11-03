--[[
    cl_hud.lua - Classic DarkRP / GangWars Bottom-Left HUD, Ammo Display & Hitmarkers
--]]

GWRP.UI = GWRP.UI or {}

-- Text Fitting Helper (Word/Length truncation protection)
GWRP.UI.FitText = GWRP.UI.FitText or function(text, font, maxW)
    if not text or text == "" then return "" end
    surface.SetFont(font)
    local tw = surface.GetTextSize(text)
    if tw <= maxW then return text end
    local s = text
    while #s > 3 and surface.GetTextSize(s .. "...") > maxW do
        s = string.sub(s, 1, #s - 1)
    end
    return s .. "..."
end

function GWRP.UI.CreateFonts()
    -- Legacy / In-Game HUD Fonts (Crisp & Readable)
    surface.CreateFont("GWRP_FontSmall", {
        font = "Roboto",
        size = 17,
        weight = 700,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_FontMedium", {
        font = "Roboto",
        size = 22,
        weight = 700,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_FontLarge", {
        font = "Roboto",
        size = 30,
        weight = 800,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_FontAmmo", {
        font = "Trebuchet MS",
        size = 42,
        weight = 900,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_HUD_Small", {
        font = "Roboto",
        size = 17,
        weight = 700,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_HUD_Med", {
        font = "Roboto",
        size = 22,
        weight = 700,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_HUD_Large", {
        font = "Roboto",
        size = 30,
        weight = 800,
        antialias = true,
        extended = true
    })

    -- High-Legibility Scaled Typography for Modern Menus & F4 Dashboard
    surface.CreateFont("GWRP_UI_Title", {
        font = "Roboto",
        size = 34,
        weight = 800,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_UI_Header", {
        font = "Roboto",
        size = 25,
        weight = 700,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_UI_Sub", {
        font = "Roboto",
        size = 21,
        weight = 600,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_UI_Price", {
        font = "Roboto",
        size = 30,
        weight = 800,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_UI_Btn", {
        font = "Roboto",
        size = 20,
        weight = 700,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_UI_Body", {
        font = "Roboto",
        size = 19,
        weight = 500,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_UI_BodyBold", {
        font = "Roboto",
        size = 19,
        weight = 700,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_UI_Badge", {
        font = "Roboto",
        size = 16,
        weight = 700,
        antialias = true,
        extended = true
    })
    surface.CreateFont("GWRP_UI_Caption", {
        font = "Roboto",
        size = 17,
        weight = 500,
        antialias = true,
        extended = true
    })
end

-- Call immediately upon script inclusion so fonts exist regardless of engine hook timings
GWRP.UI.CreateFonts()

-- Disable default HL2 HUD elements
hook.Add("HUDShouldDraw", "GWRP_HideDefaultHUD", function(name)
    local hide = {
        ["CHudHealth"] = true,
        ["CHudBattery"] = true,
        ["CHudAmmo"] = true,
        ["CHudSecondaryAmmo"] = true
    }
    if hide[name] then return false end
    return true
end)

-- Persistent animation state for smooth HUD interpolation
local smoothHP = nil
local smoothArmor = nil
local smoothXP = nil

-- Floating XP Popup & Level-Up State
local xpPopups = {}
local levelUpBanner = nil

net.Receive("GWRP_XPGained", function()
    local amount = net.ReadInt(32)
    local reason = net.ReadString()
    table.insert(xpPopups, {
        text = string.format("+%d XP (%s)", amount, reason),
        startTime = CurTime(),
        duration = 2.75
    })
end)

net.Receive("GWRP_LevelUp", function()
    local newLvl = net.ReadInt(16)
    local rewardCash = net.ReadInt(32)
    surface.PlaySound("garrysmod/save_load1.wav")
    levelUpBanner = {
        level = newLvl,
        reward = rewardCash,
        startTime = CurTime(),
        duration = 5.0
    }
end)

-- Main Paint Hook
hook.Add("HUDPaint", "GWRP_DrawMainHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then
        smoothHP = nil
        smoothArmor = nil
        smoothXP = nil
        return
    end

    -- 1. Draw Top Turf Domination Bar
    if GWRP.Turf and GWRP.Turf.DrawHUD then
        GWRP.Turf.DrawHUD()
    end

    -- 2. Modern Unified Bottom-Left HUD (Obsidian Theme with Level & XP)
    local hudW, hudH = 346, 168
    local hudX, hudY = 24, ScrH() - hudH - 24

    -- Gang & Job Metadata
    local jobData = ply:GetJobData() or {}
    local jobName = jobData.name or "Citizen"
    local gangName = ply:GetGang()
    local isGang = (gangName ~= "")
    local badgeCol = isGang and GWRP.GetGangColor(gangName) or (jobData.faction and jobData.faction.color or Color(56, 189, 248))
    local badgeText = isGang and (gangName .. " • " .. jobName) or jobName

    -- Background Obsidian Card
    draw.RoundedBox(8, hudX, hudY, hudW, hudH, Color(11, 15, 25, 246))

    -- Outer Border Outline
    surface.SetDrawColor(30, 41, 59, 220)
    surface.DrawOutlinedRect(hudX, hudY, hudW, hudH, 1)

    -- Left Faction/Gang Identity Accent Strip
    draw.RoundedBoxEx(8, hudX, hudY, 4, hudH, badgeCol, true, false, true, false)

    -- Top Header Row: Level Badge + Player Name + Faction/Gang Capsule Badge
    local headerY = hudY + 10
    surface.SetFont("GWRP_UI_Badge")
    local maxBadgeW = math.floor(hudW * 0.48)
    local fitBadge = GWRP.UI.FitText(badgeText, "GWRP_UI_Badge", maxBadgeW - 16)
    local bTextW = surface.GetTextSize(fitBadge)
    local badgeW = bTextW + 16
    local badgeX = hudX + hudW - badgeW - 14

    -- Job / Gang Capsule Pill
    draw.RoundedBox(4, badgeX, headerY, badgeW, 22, Color(badgeCol.r, badgeCol.g, badgeCol.b, 35))
    surface.SetDrawColor(badgeCol.r, badgeCol.g, badgeCol.b, 160)
    surface.DrawOutlinedRect(badgeX, headerY, badgeW, 22, 1)
    draw.SimpleText(fitBadge, "GWRP_UI_Badge", badgeX + badgeW / 2, headerY + 11, badgeCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Player Level Capsule Pill
    local curLevel = ply.GetLevel and ply:GetLevel() or 1
    local lvlBadgeText = "LVL " .. curLevel
    surface.SetFont("GWRP_UI_Badge")
    local lvlBadgeW = surface.GetTextSize(lvlBadgeText) + 14
    local lvlBadgeX = hudX + 14

    draw.RoundedBox(4, lvlBadgeX, headerY, lvlBadgeW, 22, Color(245, 158, 11, 40))
    surface.SetDrawColor(245, 158, 11, 180)
    surface.DrawOutlinedRect(lvlBadgeX, headerY, lvlBadgeW, 22, 1)
    draw.SimpleText(lvlBadgeText, "GWRP_UI_Badge", lvlBadgeX + lvlBadgeW / 2, headerY + 11, Color(251, 191, 36), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Player Nickname (Word/length fitted to avoid badge overlap)
    local nickX = lvlBadgeX + lvlBadgeW + 8
    local maxNickW = badgeX - nickX - 8
    local fitNick = GWRP.UI.FitText(ply:Nick(), "GWRP_UI_Sub", maxNickW)
    draw.SimpleText(fitNick, "GWRP_UI_Sub", nickX, headerY + 11, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Slate Header Divider Line
    surface.SetDrawColor(30, 41, 59, 200)
    surface.DrawLine(hudX + 12, hudY + 37, hudX + hudW - 12, hudY + 37)

    -- Interpolation Delta
    local dt = FrameTime()
    local targetHP = math.max(0, ply:Health())
    local maxHP = math.max(1, ply:GetMaxHealth())
    if smoothHP == nil then smoothHP = targetHP end
    smoothHP = Lerp(math.Clamp(dt * 10, 0, 1), smoothHP, targetHP)

    local targetArmor = math.Clamp(ply:Armor(), 0, 100)
    if smoothArmor == nil then smoothArmor = targetArmor end
    smoothArmor = Lerp(math.Clamp(dt * 10, 0, 1), smoothArmor, targetArmor)

    local targetXP = ply.GetXP and ply:GetXP() or 0
    local reqXP = ply.GetRequiredXP and ply:GetRequiredXP() or 250
    local maxLvl = (GWRP.Config and GWRP.Config.Level and GWRP.Config.Level.MaxLevel) or 50
    local isMaxLvl = (curLevel >= maxLvl)
    if smoothXP == nil then smoothXP = targetXP end
    smoothXP = Lerp(math.Clamp(dt * 8, 0, 1), smoothXP, targetXP)

    -- Common Track Sizing
    local barH = 16
    local trackX = hudX + 52
    local trackW = hudW - 66

    -- Health Bar Row
    local hpY = hudY + 44
    draw.RoundedBox(4, hudX + 14, hpY, 32, barH, Color(239, 68, 68, 35))
    surface.SetDrawColor(239, 68, 68, 160)
    surface.DrawOutlinedRect(hudX + 14, hpY, 32, barH, 1)
    draw.SimpleText("HP", "GWRP_UI_Badge", hudX + 14 + 16, hpY + barH / 2, Color(248, 113, 113), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    draw.RoundedBox(4, trackX, hpY, trackW, barH, Color(17, 24, 39, 240))
    surface.SetDrawColor(30, 41, 59, 180)
    surface.DrawOutlinedRect(trackX, hpY, trackW, barH, 1)

    local hpPct = math.Clamp(smoothHP / maxHP, 0, 1)
    if hpPct > 0 then
        local fillW = math.Clamp(math.Round(trackW * hpPct), 6, trackW)
        draw.RoundedBox(4, trackX, hpY, fillW, barH, Color(239, 68, 68))
        draw.RoundedBox(2, trackX + 1, hpY + 1, math.max(4, fillW - 2), 2, Color(254, 202, 202, 70))
    end
    local hpStr = string.format("%d / %d", math.max(0, math.ceil(smoothHP)), maxHP)
    draw.SimpleText(hpStr, "GWRP_UI_Badge", trackX + trackW - 7, hpY + barH / 2 + 1, Color(0, 0, 0, 180), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(hpStr, "GWRP_UI_Badge", trackX + trackW - 8, hpY + barH / 2, Color(255, 255, 255, 240), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

    -- Armor Bar Row
    local armorY = hudY + 65
    draw.RoundedBox(4, hudX + 14, armorY, 32, barH, Color(6, 182, 212, 35))
    surface.SetDrawColor(6, 182, 212, 160)
    surface.DrawOutlinedRect(hudX + 14, armorY, 32, barH, 1)
    draw.SimpleText("AP", "GWRP_UI_Badge", hudX + 14 + 16, armorY + barH / 2, Color(34, 211, 238), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    draw.RoundedBox(4, trackX, armorY, trackW, barH, Color(17, 24, 39, 240))
    surface.SetDrawColor(30, 41, 59, 180)
    surface.DrawOutlinedRect(trackX, armorY, trackW, barH, 1)

    local armorPct = math.Clamp(smoothArmor / 100, 0, 1)
    if armorPct > 0 then
        local fillW = math.Clamp(math.Round(trackW * armorPct), 6, trackW)
        draw.RoundedBox(4, trackX, armorY, fillW, barH, Color(6, 182, 212))
        draw.RoundedBox(2, trackX + 1, armorY + 1, math.max(4, fillW - 2), 2, Color(165, 243, 252, 70))
    end
    local armorStr = string.format("%d / 100", math.max(0, math.ceil(smoothArmor)))
    draw.SimpleText(armorStr, "GWRP_UI_Badge", trackX + trackW - 7, armorY + barH / 2 + 1, Color(0, 0, 0, 180), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(armorStr, "GWRP_UI_Badge", trackX + trackW - 8, armorY + barH / 2, Color(255, 255, 255, 240), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

    -- XP Progress Bar Row
    local xpY = hudY + 86
    draw.RoundedBox(4, hudX + 14, xpY, 32, barH, Color(245, 158, 11, 35))
    surface.SetDrawColor(245, 158, 11, 160)
    surface.DrawOutlinedRect(hudX + 14, xpY, 32, barH, 1)
    draw.SimpleText("XP", "GWRP_UI_Badge", hudX + 14 + 16, xpY + barH / 2, Color(251, 191, 36), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    draw.RoundedBox(4, trackX, xpY, trackW, barH, Color(17, 24, 39, 240))
    surface.SetDrawColor(30, 41, 59, 180)
    surface.DrawOutlinedRect(trackX, xpY, trackW, barH, 1)

    local xpPct = isMaxLvl and 1 or math.Clamp(smoothXP / math.max(1, reqXP), 0, 1)
    if xpPct > 0 then
        local fillW = math.Clamp(math.Round(trackW * xpPct), 6, trackW)
        draw.RoundedBox(4, trackX, xpY, fillW, barH, Color(245, 158, 11))
        draw.RoundedBox(2, trackX + 1, xpY + 1, math.max(4, fillW - 2), 2, Color(253, 230, 138, 80))
    end
    local xpStr = isMaxLvl and "MAX LEVEL (50)" or string.format("%s / %s XP (%d%%)", string.Comma(math.ceil(smoothXP)), string.Comma(reqXP), math.floor(xpPct * 100))
    draw.SimpleText(xpStr, "GWRP_UI_Badge", trackX + trackW - 7, xpY + barH / 2 + 1, Color(0, 0, 0, 180), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(xpStr, "GWRP_UI_Badge", trackX + trackW - 8, xpY + barH / 2, Color(255, 255, 255, 240), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

    -- Slate Mid Divider Line
    surface.SetDrawColor(30, 41, 59, 200)
    surface.DrawLine(hudX + 12, hudY + 112, hudX + hudW - 12, hudY + 112)

    -- Economy Row: Wallet & Salary
    local econY = hudY + 123

    -- Currency Glyph Pill
    draw.RoundedBox(4, hudX + 14, econY, 24, 24, Color(16, 185, 129, 35))
    surface.SetDrawColor(16, 185, 129, 160)
    surface.DrawOutlinedRect(hudX + 14, econY, 24, 24, 1)
    draw.SimpleText("$", "GWRP_UI_Badge", hudX + 14 + 12, econY + 12, Color(52, 211, 153), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Cash Value
    local moneyStr = GWRP.FormatMoney(ply:GetMoney())
    draw.SimpleText(moneyStr, "GWRP_UI_Sub", hudX + 44, econY + 12, Color(52, 211, 153), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Salary Pill Capsule
    local salaryVal = jobData.salary or 45
    local payInterval = GWRP.Config and GWRP.Config.PaydayInterval or 90
    local salaryStr = "+$" .. salaryVal .. " / " .. payInterval .. "s"
    surface.SetFont("GWRP_UI_Badge")
    local salTextW = surface.GetTextSize(salaryStr)
    local salPillW = salTextW + 18
    local salPillX = hudX + hudW - salPillW - 14

    draw.RoundedBox(4, salPillX, econY, salPillW, 24, Color(24, 32, 47, 240))
    surface.SetDrawColor(30, 41, 59, 220)
    surface.DrawOutlinedRect(salPillX, econY, salPillW, 24, 1)
    draw.SimpleText(salaryStr, "GWRP_UI_Badge", salPillX + salPillW / 2, econY + 12, Color(56, 189, 248), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- 2.5 Floating Animated +XP Popups (Ascending above the HUD card)
    local now = CurTime()
    local popupBaseY = hudY - 14
    for i = #xpPopups, 1, -1 do
        local p = xpPopups[i]
        local elapsed = now - p.startTime
        if elapsed >= p.duration then
            table.remove(xpPopups, i)
        else
            local progress = elapsed / p.duration
            local alpha = math.Clamp(math.floor((1 - progress) * 255), 0, 255)
            local yOffset = progress * 40 + (i - 1) * 22
            local currentY = popupBaseY - yOffset

            surface.SetFont("GWRP_UI_Header")
            local tw, th = surface.GetTextSize(p.text)
            local pw = tw + 20
            local px = hudX + 14

            draw.RoundedBox(4, px, currentY, pw, 24, Color(11, 15, 25, math.min(alpha, 220)))
            surface.SetDrawColor(245, 158, 11, math.min(alpha, 180))
            surface.DrawOutlinedRect(px, currentY, pw, 24, 1)
            draw.SimpleText(p.text, "GWRP_UI_Header", px + pw / 2, currentY + 12, Color(251, 191, 36, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    -- 2.6 Level-Up Fanfare Celebration Banner (Top Center of Screen)
    if levelUpBanner then
        local elapsed = now - levelUpBanner.startTime
        if elapsed >= levelUpBanner.duration then
            levelUpBanner = nil
        else
            local alpha = 255
            if elapsed < 0.5 then
                alpha = math.floor((elapsed / 0.5) * 255)
            elseif elapsed > (levelUpBanner.duration - 0.75) then
                alpha = math.floor(((levelUpBanner.duration - elapsed) / 0.75) * 255)
            end

            local scrW = ScrW()
            local bW, bH = 460, 80
            local bX = (scrW - bW) / 2
            local bY = 70

            -- Banner Card
            draw.RoundedBox(8, bX, bY, bW, bH, Color(11, 15, 25, math.min(alpha, 248)))
            surface.SetDrawColor(245, 158, 11, math.min(alpha, 220))
            surface.DrawOutlinedRect(bX, bY, bW, bH, 2)

            -- Banner Content
            local titleTxt = "★ LEVEL UP! REACHED LEVEL " .. levelUpBanner.level .. " ★"
            draw.SimpleText(titleTxt, "GWRP_UI_Title", bX + bW / 2, bY + 24, Color(251, 191, 36, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            local rewardTxt = string.format("Cash Reward: +$%s  •  Health Fully Restored!", string.Comma(levelUpBanner.reward))
            draw.SimpleText(rewardTxt, "GWRP_UI_Sub", bX + bW / 2, bY + 54, Color(74, 222, 128, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    -- 3. Draw Bottom-Right Ammo Display (Unified Theme)
    local wep = ply:GetActiveWeapon()
    local nonAmmoWeps = {
        weapon_gwrp_fists = true,
        weapon_fists = true,
        fists = true,
        weapon_gwrp_keys = true,
        weapon_physgun = true,
        weapon_physcannon = true,
        gmod_tool = true,
        weapon_gwrp_remover = true
    }
    if IsValid(wep) and not nonAmmoWeps[wep:GetClass()] then
        local clip = wep:Clip1()
        local reserve = ply:GetAmmoCount(wep:GetPrimaryAmmoType())
        if clip >= 0 or reserve > 0 then
            local ammoW, ammoH = 210, 76
            local ammoX, ammoY = ScrW() - ammoW - 24, ScrH() - ammoH - 24

            draw.RoundedBox(8, ammoX, ammoY, ammoW, ammoH, Color(11, 15, 25, 246))
            surface.SetDrawColor(30, 41, 59, 220)
            surface.DrawOutlinedRect(ammoX, ammoY, ammoW, ammoH, 1)

            -- Top accent line
            draw.RoundedBoxEx(8, ammoX, ammoY, ammoW, 3, Color(245, 158, 11), true, true, false, false)

            -- Weapon Name
            local wepName = wep:GetPrintName() or "WEAPON"
            local fitName = GWRP.UI.FitText(string.upper(wepName), "GWRP_UI_Badge", ammoW - 28)
            draw.SimpleText(fitName, "GWRP_UI_Badge", ammoX + ammoW - 14, ammoY + 16, Color(148, 163, 184), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

            -- Divider
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawLine(ammoX + 12, ammoY + 28, ammoX + ammoW - 12, ammoY + 28)

            -- Ammo Numbers
            if clip >= 0 then
                draw.SimpleText(tostring(clip), "GWRP_FontAmmo", ammoX + ammoW - 14 - 55, ammoY + 52, Color(245, 158, 11), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                draw.SimpleText("/ " .. reserve, "GWRP_UI_Sub", ammoX + ammoW - 14, ammoY + 55, Color(203, 213, 225), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(tostring(reserve), "GWRP_FontAmmo", ammoX + ammoW - 14, ammoY + 52, Color(245, 158, 11), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end

    -- 4. In-World Crosshair Tag for Entities (Doors, Clinic Pod, Printers, Network Switches)
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if IsValid(ent) then
        local distSqr = tr.HitPos:DistToSqr(ply:EyePos())
        if ent.isDoor and ent:isDoor() and distSqr <= (200 * 200) then
            local tagX = ScrW() / 2
            local tagY = ScrH() / 2 + 36

            local cardW = 340
            local cardH = 92
            local cardX = tagX - cardW / 2

            local owner = ent:GetNWEntity("GWRP_DoorOwner")
            local gangName = ent:GetNWString("GWRP_DoorFaction", "")
            local isOwned = IsValid(owner)
            local isOwner = isOwned and (owner == ply)
            local canAccess = ent.CanAccessDoor and ent:CanAccessDoor(ply)
            local cost = (GWRP.Config and GWRP.Config.DoorCost) or 15

            local accentCol = Color(52, 211, 153)
            local badgeText = "VACANT"
            local titleText = "Property Available"
            local subText = string.format("Purchase Cost: $%s", string.Comma(cost))
            local subCol = Color(74, 222, 128)
            local promptText = "[F2] Purchase Door"
            local promptCol = Color(248, 250, 252)

            if isOwner then
                accentCol = Color(52, 211, 153)
                badgeText = "YOUR DOOR"
                titleText = ply:Nick()
                local gangStr = (gangName ~= "" and gangName ~= "neutral") and ("Faction: " .. string.upper(gangName)) or "Private Residence"
                subText = gangStr
                subCol = Color(148, 163, 184)
                promptText = "[F2] Manage / Sell Property"
                promptCol = Color(74, 222, 128)
            elseif isOwned then
                local gangCol = (gangName ~= "" and gangName ~= "neutral" and GWRP.GetGangColor) and GWRP.GetGangColor(gangName) or nil
                if canAccess then
                    accentCol = gangCol or Color(6, 182, 212)
                    badgeText = "GANG ACCESS"
                    titleText = owner:Nick()
                    subText = string.format("Gang: %s  •  Access Permitted", string.upper(gangName))
                    subCol = Color(52, 211, 153)
                    promptText = "[Shared Property]"
                    promptCol = Color(203, 213, 225)
                else
                    accentCol = gangCol or Color(251, 191, 36)
                    badgeText = "OCCUPIED"
                    titleText = owner:Nick()
                    local gangStr = (gangName ~= "" and gangName ~= "neutral") and ("Faction: " .. string.upper(gangName)) or "Private Residence"
                    subText = gangStr
                    subCol = Color(148, 163, 184)
                    promptText = "Restricted Access  •  Trespassers Beware"
                    promptCol = Color(239, 68, 68)
                end
            end

            -- Measure Badge Width
            surface.SetFont("GWRP_UI_Badge")
            local bTextW = surface.GetTextSize(badgeText)
            local badgeW = bTextW + 16

            -- Card Background (Deep obsidian slate)
            draw.RoundedBox(8, cardX, tagY, cardW, cardH, Color(11, 15, 25, 245))
            surface.SetDrawColor(accentCol.r, accentCol.g, accentCol.b, 200)
            surface.DrawOutlinedRect(cardX, tagY, cardW, cardH, 1)

            -- Top Accent Line
            draw.RoundedBoxEx(8, cardX, tagY, cardW, 3, accentCol, true, true, false, false)

            -- Row 1: Status Pill + Title
            draw.RoundedBox(4, cardX + 8, tagY + 8, badgeW, 20, Color(accentCol.r, accentCol.g, accentCol.b, 40))
            surface.SetDrawColor(accentCol.r, accentCol.g, accentCol.b, 160)
            surface.DrawOutlinedRect(cardX + 8, tagY + 8, badgeW, 20, 1)
            draw.SimpleText(badgeText, "GWRP_UI_Badge", cardX + 8 + badgeW / 2, tagY + 18, accentCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            local maxTitleW = cardW - badgeW - 24
            local fitTitle = GWRP.UI.FitText(titleText, "GWRP_UI_Badge", maxTitleW)
            draw.SimpleText(fitTitle, "GWRP_UI_Badge", cardX + badgeW + 16, tagY + 18, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Row 2: Subtitle Info
            draw.SimpleText(subText, "GWRP_FontSmall", cardX + 12, tagY + 44, subCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Row 3: Prompt Action
            draw.SimpleText(promptText, "GWRP_UI_Caption", cardX + 12, tagY + 68, promptCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        elseif distSqr <= (160 * 160) and ent:GetClass() == "gwrp_clinic_pod" then
            local tagX = ScrW() / 2
            local tagY = ScrH() / 2 + 36

            surface.SetFont("GWRP_UI_Badge")
            local podTitle = "Clinical Triage Pod"
            local titleW = surface.GetTextSize(podTitle)
            local totalW = titleW + 28
            local totalH = 30

            draw.RoundedBox(6, tagX - totalW / 2, tagY, totalW, totalH, Color(11, 15, 25, 240))
            surface.SetDrawColor(52, 211, 153, 200)
            surface.DrawOutlinedRect(tagX - totalW / 2, tagY, totalW, totalH, 1)

            draw.SimpleText(podTitle, "GWRP_UI_Badge", tagX, tagY + 15, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        elseif distSqr <= (160 * 160) and ent.HasItemQuality and ent:HasItemQuality() then
            local qData = ent:GetItemQualityData()
            if qData then
            local entName = ent.PrintName or ent:GetClass()
            local qName = qData.name
            local qCol = qData.color

            local tagX = ScrW() / 2
            local tagY = ScrH() / 2 + 36

            surface.SetFont("GWRP_UI_Badge")
            local nameW = surface.GetTextSize(entName)
            local badgeW = surface.GetTextSize(qName) + 16

            -- Up-Close Raycast UI: Layer-2 Network Switch
            if ent:GetClass() == "gwrp_network_switch" then
                local cardW = 340
                local cardH = 94
                local cardX = tagX - cardW / 2

                draw.RoundedBox(8, cardX, tagY, cardW, cardH, Color(11, 15, 25, 245))
                surface.SetDrawColor(qCol.r, qCol.g, qCol.b, 200)
                surface.DrawOutlinedRect(cardX, tagY, cardW, cardH, 1)

                -- Header: Quality Pill + Switch Title
                draw.RoundedBox(4, cardX + 8, tagY + 6, badgeW, 20, Color(qCol.r, qCol.g, qCol.b, 40))
                draw.SimpleText(qName, "GWRP_UI_Badge", cardX + 8 + badgeW / 2, tagY + 16, qCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(entName, "GWRP_UI_Badge", cardX + badgeW + 16, tagY + 16, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                -- 3 Ports Status Row
                local p1 = ent.GetPort1Active and ent:GetPort1Active()
                local p2 = ent.GetPort2Active and ent:GetPort2Active()
                local p3 = ent.GetPort3Active and ent:GetPort3Active()

                local portW = 100
                local portH = 24
                local portY = tagY + 34
                local ports = {
                    { name = "P1", active = p1, x = cardX + 10 },
                    { name = "P2", active = p2, x = cardX + 120 },
                    { name = "P3", active = p3, x = cardX + 230 }
                }

                for _, pt in ipairs(ports) do
                    local bg = pt.active and Color(16, 185, 129, 35) or Color(30, 41, 59, 140)
                    local col = pt.active and Color(52, 211, 153) or Color(148, 163, 184)
                    local txt = pt.active and (pt.name .. ": LINKED") or (pt.name .. ": EMPTY")
                    draw.RoundedBox(4, pt.x, portY, portW, portH, bg)
                    surface.SetDrawColor(col.r, col.g, col.b, 160)
                    surface.DrawOutlinedRect(pt.x, portY, portW, portH, 1)
                    draw.SimpleText(txt, "GWRP_UI_Caption", pt.x + portW / 2, portY + 12, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end

                -- Hardware Status Row
                local links = ent.GetConnectedCount and ent:GetConnectedCount() or 0
                local linksTxt = string.format("Active Ports: %d / 3 Connected", links)

                draw.SimpleText(linksTxt, "GWRP_UI_Caption", cardX + cardW / 2, tagY + 75, Color(203, 213, 225), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            -- Up-Close Raycast UI: Contraband Money Printers
            elseif ent.PrintAmount ~= nil or ent:GetClass():find("gwrp_printer_") then
                local cardW = 340
                local cardH = 102
                local cardX = tagX - cardW / 2

                draw.RoundedBox(8, cardX, tagY, cardW, cardH, Color(11, 15, 25, 245))
                surface.SetDrawColor(qCol.r, qCol.g, qCol.b, 200)
                surface.DrawOutlinedRect(cardX, tagY, cardW, cardH, 1)

                -- Header: Quality Pill + Printer Name
                draw.RoundedBox(4, cardX + 8, tagY + 6, badgeW, 20, Color(qCol.r, qCol.g, qCol.b, 40))
                draw.SimpleText(qName, "GWRP_UI_Badge", cardX + 8 + badgeW / 2, tagY + 16, qCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(entName, "GWRP_UI_Badge", cardX + badgeW + 16, tagY + 16, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                -- Stored Cash Row
                local cash = ent.GetStoredCash and ent:GetStoredCash() or 0
                draw.SimpleText(string.format("Stored Cash: +$%d", cash), "GWRP_FontSmall", cardX + 12, tagY + 39, GWRP.Colors.MoneyGreen, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                -- Temperature Row (Dedicated line to prevent clipping with undervolt tag)
                local temp = ent.GetTemperature and ent:GetTemperature() or 20
                local isUv = ent.GetHasUndervolt and ent:GetHasUndervolt()
                local tempCol = temp > 75 and GWRP.Colors.HealthRed or (isUv and Color(56, 189, 248) or Color(203, 213, 225))
                local tempTxt = isUv and string.format("Temp: %d°C / 100°C (Undervolted)", temp) or string.format("Temp: %d°C / 100°C", temp)
                draw.SimpleText(tempTxt, "GWRP_UI_Caption", cardX + 12, tagY + 61, tempCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                -- Efficiency Row
                local eff = ent.GetEfficiency and ent:GetEfficiency() or 60
                if not eff or eff <= 0 then eff = 60 end

                local effCol, effTxt
                if eff >= 100 then
                    effCol = Color(52, 211, 153)
                    effTxt = "Efficiency: 100%"
                elseif eff <= 60 then
                    effCol = Color(251, 191, 36)
                    effTxt = "Efficiency: 60%"
                else
                    effCol = Color(56, 189, 248)
                    effTxt = "Efficiency: 80%"
                end

                draw.SimpleText(effTxt, "GWRP_UI_Caption", cardX + 12, tagY + 83, effCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Standard Raycast Badge for Other In-World Entities
            else
                local totalW = nameW + badgeW + 24
                draw.RoundedBox(6, tagX - totalW / 2, tagY, totalW, 30, Color(11, 15, 25, 240))
                surface.SetDrawColor(qCol.r, qCol.g, qCol.b, 200)
                surface.DrawOutlinedRect(tagX - totalW / 2, tagY, totalW, 30, 1)

                -- Quality Pill Badge
                draw.RoundedBox(4, tagX - totalW / 2 + 6, tagY + 4, badgeW, 22, Color(qCol.r, qCol.g, qCol.b, 40))
                draw.SimpleText(qName, "GWRP_UI_Badge", tagX - totalW / 2 + 6 + badgeW / 2, tagY + 15, qCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

                -- Entity Name
                draw.SimpleText(entName, "GWRP_UI_Badge", tagX - totalW / 2 + badgeW + 14, tagY + 15, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end
end
end)
