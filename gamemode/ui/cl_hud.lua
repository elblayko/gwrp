--[[
    cl_hud.lua - Classic DarkRP / GridRP Bottom-Left HUD, Ammo Display & Hitmarkers
    Author: Toxic & Antigravity
--]]

GRID = GRID or {}
GRID.UI = GRID.UI or {}

-- Text Fitting Helper (Word/Length truncation protection)
GRID.UI.FitText = GRID.UI.FitText or function(text, font, maxW)
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

function GRID.UI.CreateFonts()
    local fontConfigs = {
        -- Legacy / In-Game HUD Fonts (Crisp & Readable)
        Small = { font = "Roboto", size = 17, weight = 700, antialias = true, extended = true },
        Medium = { font = "Roboto", size = 22, weight = 700, antialias = true, extended = true },
        Large = { font = "Roboto", size = 30, weight = 800, antialias = true, extended = true },
        Ammo = { font = "Trebuchet MS", size = 42, weight = 900, antialias = true, extended = true },
        HUD_Small = { font = "Roboto", size = 17, weight = 700, antialias = true, extended = true },
        HUD_Med = { font = "Roboto", size = 22, weight = 700, antialias = true, extended = true },
        HUD_Large = { font = "Roboto", size = 30, weight = 800, antialias = true, extended = true },

        -- High-Legibility Scaled Typography for Modern Menus & F4 Dashboard
        UI_Title = { font = "Roboto", size = 34, weight = 800, antialias = true, extended = true },
        UI_Header = { font = "Roboto", size = 25, weight = 700, antialias = true, extended = true },
        UI_Sub = { font = "Roboto", size = 21, weight = 600, antialias = true, extended = true },
        UI_Price = { font = "Roboto", size = 30, weight = 800, antialias = true, extended = true },
        UI_Btn = { font = "Roboto", size = 20, weight = 700, antialias = true, extended = true },
        UI_Body = { font = "Roboto", size = 19, weight = 500, antialias = true, extended = true },
        UI_BodyBold = { font = "Roboto", size = 19, weight = 700, antialias = true, extended = true },
        UI_Badge = { font = "Roboto", size = 16, weight = 700, antialias = true, extended = true },
        UI_Caption = { font = "Roboto", size = 17, weight = 500, antialias = true, extended = true }
    }

    surface.CreateFont("GRID_FontSmall", fontConfigs.Small)
    surface.CreateFont("GRID_FontMedium", fontConfigs.Medium)
    surface.CreateFont("GRID_FontLarge", fontConfigs.Large)
    surface.CreateFont("GRID_FontAmmo", fontConfigs.Ammo)
    surface.CreateFont("GRID_HUD_Small", fontConfigs.HUD_Small)
    surface.CreateFont("GRID_HUD_Med", fontConfigs.HUD_Med)
    surface.CreateFont("GRID_HUD_Large", fontConfigs.HUD_Large)
    surface.CreateFont("GRID_UI_Title", fontConfigs.UI_Title)
    surface.CreateFont("GRID_UI_Header", fontConfigs.UI_Header)
    surface.CreateFont("GRID_UI_Sub", fontConfigs.UI_Sub)
    surface.CreateFont("GRID_UI_Price", fontConfigs.UI_Price)
    surface.CreateFont("GRID_UI_Btn", fontConfigs.UI_Btn)
    surface.CreateFont("GRID_UI_Body", fontConfigs.UI_Body)
    surface.CreateFont("GRID_UI_BodyBold", fontConfigs.UI_BodyBold)
    surface.CreateFont("GRID_UI_Badge", fontConfigs.UI_Badge)
    surface.CreateFont("GRID_UI_Caption", fontConfigs.UI_Caption)
end

-- Call immediately upon script inclusion so fonts exist regardless of engine hook timings
GRID.UI.CreateFonts()

-- Disable default HL2 HUD elements
hook.Add("HUDShouldDraw", "GRID_HideDefaultHUD", function(name)
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

local function HandleXPGained()
    local amount = net.ReadInt(32)
    local reason = net.ReadString()
    table.insert(xpPopups, {
        text = string.format("+%d XP (%s)", amount, reason),
        startTime = CurTime(),
        duration = 2.75
    })
end

net.Receive("GRID_XPGained", HandleXPGained)

local function HandleLevelUp()
    local newLvl = net.ReadInt(16)
    local rewardCash = net.ReadInt(32)
    surface.PlaySound("garrysmod/save_load1.wav")
    levelUpBanner = {
        level = newLvl,
        reward = rewardCash,
        startTime = CurTime(),
        duration = 5.0
    }
end

net.Receive("GRID_LevelUp", HandleLevelUp)

-- Main Paint Hook
hook.Add("HUDPaint", "GRID_DrawMainHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then
        smoothHP = nil
        smoothArmor = nil
        smoothXP = nil
        return
    end

    -- 1. Draw Top Turf Domination Bar
    local turf = GRID.Turf
    if turf and turf.DrawHUD then
        turf.DrawHUD()
    end

    -- 2. Modern Unified Bottom-Left HUD (Obsidian Theme with Level & XP)
    local hudW, hudH = 346, 168
    local hudX, hudY = 24, ScrH() - hudH - 24

    -- Gang & Job Metadata
    local jobData = ply:GetJobData() or {}
    local jobName = jobData.name or "Citizen"
    local gangName = ply:GetGang()
    local isGang = (gangName ~= "")
    local getGangCol = GRID.GetGangColor
    local badgeCol = isGang and (getGangCol and getGangCol(gangName) or Color(168, 85, 247)) or
        (jobData.faction and jobData.faction.color or Color(56, 189, 248))
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
    surface.SetFont("GRID_UI_Badge")
    local maxBadgeW = math.floor(hudW * 0.48)
    local fitBadge = (GRID.UI.FitText and GRID.UI.FitText(badgeText, "GRID_UI_Badge", maxBadgeW - 16)) or badgeText
    local bTextW = surface.GetTextSize(fitBadge)
    local badgeW = bTextW + 16
    local badgeX = hudX + hudW - badgeW - 14

    -- Job / Gang Capsule Pill
    draw.RoundedBox(4, badgeX, headerY, badgeW, 22, Color(badgeCol.r, badgeCol.g, badgeCol.b, 35))
    surface.SetDrawColor(badgeCol.r, badgeCol.g, badgeCol.b, 160)
    surface.DrawOutlinedRect(badgeX, headerY, badgeW, 22, 1)
    draw.SimpleText(fitBadge, "GRID_UI_Badge", badgeX + badgeW / 2, headerY + 11, badgeCol, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)

    -- Player Level Capsule Pill
    local curLevel = ply.GetLevel and ply:GetLevel() or 1
    local lvlBadgeText = "LVL " .. curLevel
    surface.SetFont("GRID_UI_Badge")
    local lvlBadgeW = surface.GetTextSize(lvlBadgeText) + 14
    local lvlBadgeX = hudX + 14

    draw.RoundedBox(4, lvlBadgeX, headerY, lvlBadgeW, 22, Color(245, 158, 11, 40))
    surface.SetDrawColor(245, 158, 11, 180)
    surface.DrawOutlinedRect(lvlBadgeX, headerY, lvlBadgeW, 22, 1)
    draw.SimpleText(lvlBadgeText, "GRID_UI_Badge", lvlBadgeX + lvlBadgeW / 2, headerY + 11, Color(251, 191, 36),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Player Nickname (Properly truncated to prevent clipping into pills)
    local nickX = lvlBadgeX + lvlBadgeW + 10
    local maxNickW = badgeX - nickX - 8
    local fitNick = (GRID.UI.FitText and GRID.UI.FitText(ply:Nick(), "GRID_UI_Sub", maxNickW)) or ply:Nick()
    draw.SimpleText(fitNick, "GRID_UI_Sub", nickX, headerY + 11, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Interpolated Bars: Health, Armor & XP
    local curHP = math.max(ply:Health(), 0)
    local maxHP = math.max(ply:GetMaxHealth(), 100)
    local curArmor = math.max(ply:Armor(), 0)
    local maxArmor = math.max(ply:GetMaxArmor() or 100, 100)
    if maxArmor <= 0 then maxArmor = 100 end

    local curXP = ply.GetXP and ply:GetXP() or 0
    local maxXP = ply.GetNextLevelXP and ply:GetNextLevelXP() or 1000
    if maxXP <= 0 then maxXP = 1000 end
    local maxLvl = (GRID.Config and GRID.Config.Level and GRID.Config.Level.MaxLevel) or 50

    smoothHP = Lerp(FrameTime() * 10, smoothHP or curHP, curHP)
    smoothArmor = Lerp(FrameTime() * 10, smoothArmor or curArmor, curArmor)
    smoothXP = Lerp(FrameTime() * 10, smoothXP or curXP, curXP)

    local barH = 14
    local barPad = 7
    local trackX = hudX + 14 + 32
    local trackW = hudW - 28 - 32

    -- Row 1: Health Bar (Vibrant Crimson)
    local hpY = hudY + 40
    local hpFrac = math.Clamp(smoothHP / maxHP, 0, 1)

    draw.RoundedBox(4, hudX + 14, hpY, 26, barH, Color(239, 68, 68, 40))
    draw.SimpleText("HP", "GRID_UI_Badge", hudX + 14 + 13, hpY + barH / 2, Color(248, 113, 113), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)

    draw.RoundedBox(4, trackX, hpY, trackW, barH, Color(17, 24, 39, 200))
    surface.SetDrawColor(30, 41, 59, 180)
    surface.DrawOutlinedRect(trackX, hpY, trackW, barH, 1)

    if hpFrac > 0 then
        local fillW = math.max(math.floor(trackW * hpFrac), 4)
        draw.RoundedBox(4, trackX, hpY, fillW, barH, Color(239, 68, 68, 225))
    end
    local hpStr = string.format("%d / %d", math.ceil(curHP), maxHP)
    draw.SimpleText(hpStr, "GRID_UI_Badge", trackX + trackW - 7, hpY + barH / 2 + 1, Color(0, 0, 0, 180), TEXT_ALIGN_RIGHT,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(hpStr, "GRID_UI_Badge", trackX + trackW - 8, hpY + barH / 2, Color(255, 255, 255, 240),
        TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

    -- Row 2: Armor Bar (Cyan)
    local armorY = hpY + barH + barPad
    local armorFrac = math.Clamp(smoothArmor / maxArmor, 0, 1)

    draw.RoundedBox(4, hudX + 14, armorY, 26, barH, Color(6, 182, 212, 40))
    draw.SimpleText("AP", "GRID_UI_Badge", hudX + 14 + 13, armorY + barH / 2, Color(34, 211, 238), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)

    draw.RoundedBox(4, trackX, armorY, trackW, barH, Color(17, 24, 39, 200))
    surface.SetDrawColor(30, 41, 59, 180)
    surface.DrawOutlinedRect(trackX, armorY, trackW, barH, 1)

    if armorFrac > 0 then
        local fillW = math.max(math.floor(trackW * armorFrac), 4)
        draw.RoundedBox(4, trackX, armorY, fillW, barH, Color(6, 182, 212, 225))
    end
    local armorStr = string.format("%d / %d", math.ceil(curArmor), maxArmor)
    draw.SimpleText(armorStr, "GRID_UI_Badge", trackX + trackW - 7, armorY + barH / 2 + 1, Color(0, 0, 0, 180),
        TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(armorStr, "GRID_UI_Badge", trackX + trackW - 8, armorY + barH / 2, Color(255, 255, 255, 240),
        TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

    -- Row 3: XP Progress Bar (Amber / Gold)
    local xpY = armorY + barH + barPad
    local xpFrac = (curLevel >= maxLvl) and 1.0 or math.Clamp(smoothXP / maxXP, 0, 1)

    draw.RoundedBox(4, hudX + 14, xpY, 26, barH, Color(245, 158, 11, 40))
    draw.SimpleText("XP", "GRID_UI_Badge", hudX + 14 + 13, xpY + barH / 2, Color(251, 191, 36), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)

    draw.RoundedBox(4, trackX, xpY, trackW, barH, Color(17, 24, 39, 200))
    surface.SetDrawColor(30, 41, 59, 180)
    surface.DrawOutlinedRect(trackX, xpY, trackW, barH, 1)

    if xpFrac > 0 then
        local fillW = math.max(math.floor(trackW * xpFrac), 4)
        draw.RoundedBox(4, trackX, xpY, fillW, barH, Color(245, 158, 11, 225))
    end
    local xpStr = (curLevel >= maxLvl) and "MAX LEVEL" or string.format("%d / %d XP", math.ceil(curXP), maxXP)
    draw.SimpleText(xpStr, "GRID_UI_Badge", trackX + trackW - 7, xpY + barH / 2 + 1, Color(0, 0, 0, 180), TEXT_ALIGN_RIGHT,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(xpStr, "GRID_UI_Badge", trackX + trackW - 8, xpY + barH / 2, Color(255, 255, 255, 240),
        TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

    -- Row 4: Economy Status Bar (Wallet Balance + Salary Counter)
    local econY = xpY + barH + 11
    surface.SetDrawColor(30, 41, 59, 180)
    surface.DrawLine(hudX + 14, econY - 3, hudX + hudW - 14, econY - 3)

    -- Wallet Pill
    draw.RoundedBox(4, hudX + 14, econY, 24, 24, Color(16, 185, 129, 35))
    surface.SetDrawColor(16, 185, 129, 140)
    surface.DrawOutlinedRect(hudX + 14, econY, 24, 24, 1)
    draw.SimpleText("$", "GRID_UI_Badge", hudX + 14 + 12, econY + 12, Color(52, 211, 153), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)

    local formatMoney = GRID.FormatMoney
    local moneyStr = formatMoney and formatMoney(ply:GetMoney()) or ("$" .. string.Comma(ply:GetMoney()))
    draw.SimpleText(moneyStr, "GRID_UI_Sub", hudX + 44, econY + 12, Color(52, 211, 153), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Salary Pill (Right Aligned)
    local sal = jobData.salary or 0
    local payInterval = (GRID.Config and GRID.Config.PaydayInterval) or 90
    local salaryStr = string.format("+$%s / %ds", string.Comma(sal), payInterval)
    surface.SetFont("GRID_UI_Badge")
    local salPillW = surface.GetTextSize(salaryStr) + 16
    local salPillX = hudX + hudW - salPillW - 14

    draw.RoundedBox(4, salPillX, econY, salPillW, 24, Color(56, 189, 248, 25))
    surface.SetDrawColor(56, 189, 248, 120)
    surface.DrawOutlinedRect(salPillX, econY, salPillW, 24, 1)
    draw.SimpleText(salaryStr, "GRID_UI_Badge", salPillX + salPillW / 2, econY + 12, Color(56, 189, 248), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)

    -- Draw Floating XP Gain Popups (Cascading upward above the HUD)
    local popupBaseY = hudY - 14
    local curT = CurTime()
    for i = #xpPopups, 1, -1 do
        local p = xpPopups[i]
        local elapsed = curT - p.startTime
        if elapsed > p.duration then
            table.remove(xpPopups, i)
        else
            local alpha = math.Clamp(1 - (elapsed / p.duration), 0, 1) * 255
            local yOffset = elapsed * 32
            local currentY = popupBaseY - yOffset - ((#xpPopups - i) * 26)

            surface.SetFont("GRID_UI_Header")
            local pw = surface.GetTextSize(p.text) + 20
            local px = hudX

            draw.RoundedBox(6, px, currentY, pw, 24, Color(11, 15, 25, alpha * 0.9))
            surface.SetDrawColor(245, 158, 11, alpha * 0.8)
            surface.DrawOutlinedRect(px, currentY, pw, 24, 1)

            draw.SimpleText(p.text, "GRID_UI_Header", px + pw / 2, currentY + 12, Color(251, 191, 36, alpha),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    -- Draw Grand Level-Up Banner (Centered upper viewport)
    if levelUpBanner then
        local elapsed = curT - levelUpBanner.startTime
        if elapsed > levelUpBanner.duration then
            levelUpBanner = nil
        else
            local alpha = math.Clamp(math.sin((elapsed / levelUpBanner.duration) * math.pi) * 1.5, 0, 1) * 255
            local bW, bH = 460, 84
            local bX, bY = ScrW() / 2 - bW / 2, ScrH() * 0.22

            draw.RoundedBox(10, bX, bY, bW, bH, Color(11, 15, 25, alpha * 0.95))
            surface.SetDrawColor(245, 158, 11, alpha)
            surface.DrawOutlinedRect(bX, bY, bW, bH, 2)

            draw.SimpleText("★ LEVEL UP! ★", "GRID_UI_Title", bX + bW / 2, bY + 24, Color(251, 191, 36, alpha),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            local sub = string.format("You reached Level %d!  •  Bonus: +$%s", levelUpBanner.level,
                string.Comma(levelUpBanner.reward))
            draw.SimpleText(sub, "GRID_UI_Sub", bX + bW / 2, bY + 56, Color(248, 250, 252, alpha), TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
    end

    -- 3. Ammo & Firearm HUD (Bottom-Right Obsidian Module)
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep:GetClass() ~= "weapon_grid_keys" and wep:GetClass() ~= "fists" and wep:GetClass() ~= "weapon_fists" then
        local clip = wep:Clip1()
        local ammoType = wep:GetPrimaryAmmoType()
        local reserve = ply:GetAmmoCount(ammoType)

        if clip >= 0 or reserve > 0 then
            local ammoW, ammoH = 196, 76
            local ammoX, ammoY = ScrW() - ammoW - 24, ScrH() - ammoH - 24

            draw.RoundedBox(8, ammoX, ammoY, ammoW, ammoH, Color(11, 15, 25, 246))
            surface.SetDrawColor(30, 41, 59, 220)
            surface.DrawOutlinedRect(ammoX, ammoY, ammoW, ammoH, 1)

            -- Accent Right Border
            draw.RoundedBoxEx(8, ammoX + ammoW - 4, ammoY, 4, ammoH, Color(245, 158, 11), false, true, false, true)

            -- Weapon Name Pill
            local wepName = wep:GetPrintName() or wep:GetClass()
            local fitName = (GRID.UI.FitText and GRID.UI.FitText(string.upper(wepName), "GRID_UI_Badge", ammoW - 28)) or string.upper(wepName)
            draw.SimpleText(fitName, "GRID_UI_Badge", ammoX + 14, ammoY + 16, Color(148, 163, 184), TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)

            if clip >= 0 then
                draw.SimpleText(tostring(clip), "GRID_FontAmmo", ammoX + ammoW - 14 - 55, ammoY + 52, Color(245, 158, 11),
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                draw.SimpleText("/ " .. reserve, "GRID_UI_Sub", ammoX + ammoW - 14, ammoY + 55, Color(203, 213, 225),
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(tostring(reserve), "GRID_FontAmmo", ammoX + ammoW - 14, ammoY + 52, Color(245, 158, 11),
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
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

            local owner = ent:GetNWEntity("GRID_DoorOwner")
            local gangName = ent:GetNWString("GRID_DoorFaction", "")

            local isOwned = IsValid(owner)
            local isOwner = isOwned and (owner == ply)

            -- Do not display purchase HUD on unpurchasable map doors
            if not isOwned and ent:GetClass() == "func_door" then return end

            local canAccess = ent.CanAccessDoor and ent:CanAccessDoor(ply)
            local cost = (GRID.Config and GRID.Config.DoorCost) or 15

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
                local gangStr = (gangName ~= "" and gangName ~= "neutral") and ("Faction: " .. string.upper(gangName)) or
                    "Private Residence"
                subText = gangStr
                subCol = Color(148, 163, 184)
                promptText = "[F2] Manage / Sell Property"
                promptCol = Color(74, 222, 128)
            elseif isOwned then
                local gangCol = (gangName ~= "" and gangName ~= "neutral" and getGangCol) and getGangCol(gangName) or nil
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
                    local gangStr = (gangName ~= "" and gangName ~= "neutral") and
                        ("Faction: " .. string.upper(gangName)) or "Private Residence"
                    subText = gangStr
                    subCol = Color(148, 163, 184)
                    promptText = "Restricted Access  •  Trespassers Beware"
                    promptCol = Color(239, 68, 68)
                end
            end

            -- Measure Badge Width
            surface.SetFont("GRID_UI_Badge")
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
            draw.SimpleText(badgeText, "GRID_UI_Badge", cardX + 8 + badgeW / 2, tagY + 18, accentCol, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)

            local maxTitleW = cardW - badgeW - 24
            local fitTitle = (GRID.UI.FitText and GRID.UI.FitText(titleText, "GRID_UI_Badge", maxTitleW)) or titleText
            draw.SimpleText(fitTitle, "GRID_UI_Badge", cardX + badgeW + 16, tagY + 18, Color(248, 250, 252),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Row 2: Subtitle Info
            draw.SimpleText(subText, "GRID_FontSmall", cardX + 12, tagY + 44, subCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Row 3: Prompt Action
            draw.SimpleText(promptText, "GRID_UI_Caption", cardX + 12, tagY + 68, promptCol, TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)
        elseif distSqr <= (160 * 160) and ent:GetClass() == "grid_clinic_pod" then
            local tagX = ScrW() / 2
            local tagY = ScrH() / 2 + 36

            surface.SetFont("GRID_UI_Badge")
            local podTitle = "Clinical Triage Pod"
            local titleW = surface.GetTextSize(podTitle)
            local totalW = titleW + 28
            local totalH = 30

            draw.RoundedBox(6, tagX - totalW / 2, tagY, totalW, totalH, Color(11, 15, 25, 240))
            surface.SetDrawColor(52, 211, 153, 200)
            surface.DrawOutlinedRect(tagX - totalW / 2, tagY, totalW, totalH, 1)

            draw.SimpleText(podTitle, "GRID_UI_Badge", tagX, tagY + 15, Color(248, 250, 252), TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        elseif distSqr <= (160 * 160) and ent.HasItemQuality and ent:HasItemQuality() then
            local qData = ent:GetItemQualityData()
            if qData then
                local entName = ent.PrintName or ent:GetClass()
                local qName = qData.name
                local qCol = qData.color

                local tagX = ScrW() / 2
                local tagY = ScrH() / 2 + 36

                surface.SetFont("GRID_UI_Badge")
                local nameW = surface.GetTextSize(entName)
                local badgeW = surface.GetTextSize(qName) + 16

                -- Up-Close Raycast UI: Layer-3 Network Switch (Modular 4-Port / 7-Port+)
                if ent.IsNetworkSwitch or ent:GetClass() == "grid_network_switch" or string.StartWith(ent:GetClass(), "grid_network_switch") then
                    local defs = ent.GetPortDefinitions and ent:GetPortDefinitions()
                    if not defs or #defs == 0 then
                        defs = {
                            { id = 1, type = "copper", name = "Port 1" },
                            { id = 2, type = "copper", name = "Port 2" },
                            { id = 3, type = "combo",  name = "Port 3" },
                            { id = 4, type = "sfp",    name = "Port 4" }
                        }
                    end

                    local numPorts = #defs
                    local isMultiRow = numPorts > 4
                    local cardW = isMultiRow and 470 or 380
                    local cardH = isMultiRow and 124 or 96
                    local cardX = tagX - cardW / 2

                    draw.RoundedBox(8, cardX, tagY, cardW, cardH, Color(11, 15, 25, 245))
                    surface.SetDrawColor(qCol.r, qCol.g, qCol.b, 200)
                    surface.DrawOutlinedRect(cardX, tagY, cardW, cardH, 1)

                    -- Header: Quality Pill + Switch Title
                    draw.RoundedBox(4, cardX + 8, tagY + 6, badgeW, 20, Color(qCol.r, qCol.g, qCol.b, 40))
                    draw.SimpleText(qName, "GRID_UI_Badge", cardX + 8 + badgeW / 2, tagY + 16, qCol, TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                    draw.SimpleText(entName, "GRID_UI_Badge", cardX + badgeW + 16, tagY + 16, Color(248, 250, 252),
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                    -- Dynamic Port Status Grid
                    local activeCount = 0
                    if not isMultiRow then
                        -- Single row layout (<= 4 ports)
                        local portW = math.floor((cardW - 20 - (numPorts - 1) * 6) / numPorts)
                        local portH = 24
                        local portY = tagY + 34

                        for idx, def in ipairs(defs) do
                            local ptId = def.id or idx
                            local active = ent.IsPortActive and ent:IsPortActive(ptId)
                            local is10G = ent.IsPort10G and ent:IsPort10G(ptId)
                            if active then activeCount = activeCount + 1 end

                            local ptX = cardX + 10 + (idx - 1) * (portW + 6)
                            local bg, col, txt

                            if def.type == "combo" then
                                if active then
                                    bg = is10G and Color(6, 182, 212, 35) or Color(16, 185, 129, 35)
                                    col = is10G and Color(56, 189, 248) or Color(52, 211, 153)
                                    txt = is10G and string.format("P%d: 10G", ptId) or string.format("P%d: 1G Cu", ptId)
                                else
                                    bg = Color(30, 41, 59, 140)
                                    col = Color(100, 116, 139)
                                    txt = string.format("P%d: COMBO", ptId)
                                end
                            elseif def.type == "sfp" then
                                bg = active and Color(6, 182, 212, 35) or Color(30, 41, 59, 140)
                                col = active and Color(56, 189, 248) or Color(100, 116, 139)
                                txt = active and string.format("P%d: 10G", ptId) or string.format("P%d: SFP", ptId)
                            else
                                bg = active and Color(16, 185, 129, 35) or Color(30, 41, 59, 140)
                                col = active and Color(52, 211, 153) or Color(148, 163, 184)
                                txt = active and string.format("P%d: LINK", ptId) or string.format("P%d: OPEN", ptId)
                            end

                            draw.RoundedBox(4, ptX, portY, portW, portH, bg)
                            surface.SetDrawColor(col.r, col.g, col.b, 160)
                            surface.DrawOutlinedRect(ptX, portY, portW, portH, 1)
                            draw.SimpleText(txt, "GRID_UI_Caption", ptX + portW / 2, portY + 12, col, TEXT_ALIGN_CENTER,
                                TEXT_ALIGN_CENTER)
                        end
                    else
                        -- Multi-row layout (5+ ports, e.g. 7-port switch)
                        local cols = math.ceil(numPorts / 2)
                        local portW = math.floor((cardW - 24 - (cols - 1) * 6) / cols)
                        local portH = 22

                        for idx, def in ipairs(defs) do
                            local ptId = def.id or idx
                            local active = ent.IsPortActive and ent:IsPortActive(ptId)
                            local is10G = ent.IsPort10G and ent:IsPort10G(ptId)
                            if active then activeCount = activeCount + 1 end

                            local row = (idx <= cols) and 0 or 1
                            local colIdx = (idx <= cols) and (idx - 1) or (idx - cols - 1)
                            local ptX = cardX + 12 + colIdx * (portW + 6)
                            local ptY = tagY + 32 + row * (portH + 5)

                            local bg, col, txt
                            if def.type == "combo" then
                                if active then
                                    bg = is10G and Color(6, 182, 212, 35) or Color(16, 185, 129, 35)
                                    col = is10G and Color(56, 189, 248) or Color(52, 211, 153)
                                    txt = is10G and string.format("P%d: 10G", ptId) or string.format("P%d: 1G Cu", ptId)
                                else
                                    bg = Color(30, 41, 59, 140)
                                    col = Color(100, 116, 139)
                                    txt = string.format("P%d: COMBO", ptId)
                                end
                            elseif def.type == "sfp" then
                                bg = active and Color(6, 182, 212, 35) or Color(30, 41, 59, 140)
                                col = active and Color(56, 189, 248) or Color(100, 116, 139)
                                txt = active and string.format("P%d: 10G", ptId) or string.format("P%d: SFP", ptId)
                            else
                                bg = active and Color(16, 185, 129, 35) or Color(30, 41, 59, 140)
                                col = active and Color(52, 211, 153) or Color(148, 163, 184)
                                txt = active and string.format("P%d: LINK", ptId) or string.format("P%d: OPEN", ptId)
                            end

                            draw.RoundedBox(4, ptX, ptY, portW, portH, bg)
                            surface.SetDrawColor(col.r, col.g, col.b, 160)
                            surface.DrawOutlinedRect(ptX, ptY, portW, portH, 1)
                            draw.SimpleText(txt, "GRID_UI_Caption", ptX + portW / 2, ptY + 11, col, TEXT_ALIGN_CENTER,
                                TEXT_ALIGN_CENTER)
                        end
                    end

                    -- Bottom Status Summary Row
                    local subnet = ent.GetSubnetID and ent:GetSubnetID() or 1
                    local summaryY = isMultiRow and (tagY + 104) or (tagY + 75)
                    local linksTxt = string.format("%d/%d Ports Active  •  Subnet: 192.168.%d.0/24  •  Gateway: 192.168.%d.1",
                        activeCount, numPorts, subnet, subnet)

                    draw.SimpleText(linksTxt, "GRID_UI_Caption", cardX + cardW / 2, summaryY, Color(203, 213, 225),
                        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

                -- Up-Close Raycast UI: Satellite WAN Uplink Gateway
                elseif ent:GetClass() == "grid_wan_uplink" then
                    local cardW = 360
                    local cardH = 92
                    local cardX = tagX - cardW / 2

                    draw.RoundedBox(8, cardX, tagY, cardW, cardH, Color(11, 15, 25, 245))
                    surface.SetDrawColor(qCol.r, qCol.g, qCol.b, 200)
                    surface.DrawOutlinedRect(cardX, tagY, cardW, cardH, 1)

                    -- Header: Quality Pill + Name
                    draw.RoundedBox(4, cardX + 8, tagY + 6, badgeW, 20, Color(qCol.r, qCol.g, qCol.b, 40))
                    draw.SimpleText(qName, "GRID_UI_Badge", cardX + 8 + badgeW / 2, tagY + 16, qCol, TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                    draw.SimpleText(entName, "GRID_UI_Badge", cardX + badgeW + 16, tagY + 16, Color(248, 250, 252),
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                    -- Key and Mesh Status Row
                    local key = ent.GetEncryptionKey and ent:GetEncryptionKey() or "NONE"
                    local isOnline = ent.GetIsOnline and ent:GetIsOnline()
                    local peers = ent.GetLinkedPeerCount and ent:GetLinkedPeerCount() or 0
                    local statusCol = isOnline and Color(52, 211, 153) or Color(245, 158, 11)
                    local statusTxt = isOnline and string.format("ONLINE (%d PEER%s)", peers, peers == 1 and "" or "S") or
                        "SEARCHING"

                    draw.SimpleText(string.format("Encryption Key: %s", key), "GRID_UI_BodyBold", cardX + 12, tagY + 40,
                        Color(56, 189, 248), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(statusTxt, "GRID_UI_Badge", cardX + cardW - 12, tagY + 40, statusCol, TEXT_ALIGN_RIGHT,
                        TEXT_ALIGN_CENTER)

                    -- Attachment and Hint Row
                    local sw = ent.GetConnectedSwitch and ent:GetConnectedSwitch()
                    local swTxt = IsValid(sw) and
                        string.format("Connected: L3 Switch Port %d (Active L3 Route)", ent:GetAssignedPort() or 0) or
                        "Unlinked: Connect to L3 Switch via Wire Tool"
                    draw.SimpleText(swTxt, "GRID_UI_Caption", cardX + 12, tagY + 68, Color(148, 163, 184), TEXT_ALIGN_LEFT,
                        TEXT_ALIGN_CENTER)

                -- Up-Close Raycast UI: Contraband Money Printers
                elseif ent.PrintAmount ~= nil or ent:GetClass():find("grid_printer_") then
                    local cardW = 340
                    local cardH = 102
                    local cardX = tagX - cardW / 2

                    draw.RoundedBox(8, cardX, tagY, cardW, cardH, Color(11, 15, 25, 245))
                    surface.SetDrawColor(qCol.r, qCol.g, qCol.b, 200)
                    surface.DrawOutlinedRect(cardX, tagY, cardW, cardH, 1)

                    -- Header: Quality Pill + Printer Name
                    draw.RoundedBox(4, cardX + 8, tagY + 6, badgeW, 20, Color(qCol.r, qCol.g, qCol.b, 40))
                    draw.SimpleText(qName, "GRID_UI_Badge", cardX + 8 + badgeW / 2, tagY + 16, qCol, TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                    draw.SimpleText(entName, "GRID_UI_Badge", cardX + badgeW + 16, tagY + 16, Color(248, 250, 252),
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                    -- Stored Cash Row
                    local cash = ent.GetStoredCash and ent:GetStoredCash() or 0
                    local moneyCol = (GRID.Colors and GRID.Colors.MoneyGreen) or Color(52, 211, 153)
                    draw.SimpleText(string.format("Stored Cash: +$%d", cash), "GRID_FontSmall", cardX + 12, tagY + 39,
                        moneyCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                    -- Temperature Row
                    local temp = ent.GetTemperature and ent:GetTemperature() or 20
                    local isUv = ent.GetHasUndervolt and ent:GetHasUndervolt()
                    local healthRed = (GRID.Colors and GRID.Colors.HealthRed) or Color(239, 68, 68)
                    local tempCol = temp > 75 and healthRed or
                        (isUv and Color(56, 189, 248) or Color(203, 213, 225))
                    local tempTxt = isUv and string.format("Temp: %d°C / 100°C (Undervolted)", temp) or
                        string.format("Temp: %d°C / 100°C", temp)
                    draw.SimpleText(tempTxt, "GRID_UI_Caption", cardX + 12, tagY + 61, tempCol, TEXT_ALIGN_LEFT,
                        TEXT_ALIGN_CENTER)

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

                    draw.SimpleText(effTxt, "GRID_UI_Caption", cardX + 12, tagY + 83, effCol, TEXT_ALIGN_LEFT,
                        TEXT_ALIGN_CENTER)

                -- Standard Raycast Badge for Other In-World Entities
                else
                    local totalW = nameW + badgeW + 24
                    draw.RoundedBox(6, tagX - totalW / 2, tagY, totalW, 30, Color(11, 15, 25, 240))
                    surface.SetDrawColor(qCol.r, qCol.g, qCol.b, 200)
                    surface.DrawOutlinedRect(tagX - totalW / 2, tagY, totalW, 30, 1)

                    -- Quality Pill Badge
                    draw.RoundedBox(4, tagX - totalW / 2 + 6, tagY + 4, badgeW, 22, Color(qCol.r, qCol.g, qCol.b, 40))
                    draw.SimpleText(qName, "GRID_UI_Badge", tagX - totalW / 2 + 6 + badgeW / 2, tagY + 15, qCol,
                        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

                    -- Entity Name
                    draw.SimpleText(entName, "GRID_UI_Badge", tagX - totalW / 2 + badgeW + 14, tagY + 15,
                        Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            end
        end
    end
end)
