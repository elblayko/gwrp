--[[
    cl_turf.lua - Client Turf Synchronization, Top Bar HUD & Tax Slider Menu
--]]

GRID = GRID or {}
GRID.Turf = GRID.Turf or {}
GRID.TurfData = GRID.TurfData or {}

local function HandleSyncTurfZones()
    local count = net.ReadUInt(8)
    GRID.Turf.Zones = {}

    for i = 1, count do
        local id = net.ReadUInt(8)
        local name = net.ReadString()
        local pos = net.ReadVector()
        local infRadius = net.ReadUInt(16)
        local owner = net.ReadString()
        local progress = net.ReadUInt(8)
        local tax_rate = net.ReadUInt(8)
        local capRadius = net.ReadUInt(16)
        if not capRadius or capRadius == 0 then capRadius = 250 end
        local capturedAt = net.ReadUInt(32)

        GRID.Turf.Zones[id] = {
            id = id,
            name = name,
            pos = pos,
            radius = infRadius,
            influence_radius = infRadius,
            capture_radius = capRadius,
            owner = owner,
            progress = progress,
            tax_rate = tax_rate,
            captured_at = capturedAt
        }

        GRID.TurfData[id] = {
            owner = owner,
            progress = progress,
            tax_rate = tax_rate,
            captured_at = capturedAt
        }
    end

    if GRID.Turf.RefreshSetupMenu then
        GRID.Turf.RefreshSetupMenu()
    end
end

net.Receive("GRID_SyncTurfZones", HandleSyncTurfZones)

-- Real-time Ownership & Capture Updates
local function HandleTurfUpdate()
    local id = net.ReadUInt(8)
    local owner = net.ReadString()
    local progress = net.ReadUInt(8)
    local tax_rate = net.ReadUInt(8)
    local capturedAt = net.ReadUInt(32)

    GRID.TurfData[id] = {
        owner = owner,
        progress = progress,
        tax_rate = tax_rate,
        captured_at = capturedAt
    }

    if GRID.Turf.Zones[id] then
        GRID.Turf.Zones[id].owner = owner
        GRID.Turf.Zones[id].progress = progress
        GRID.Turf.Zones[id].tax_rate = tax_rate
        GRID.Turf.Zones[id].captured_at = capturedAt
    end
end

net.Receive("GRID_TurfUpdate", HandleTurfUpdate)

local currentAlpha = 0
local lastTerritoryName = ""

function GRID.Turf.DrawHUD()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local pos = ply:GetPos()
    local activeZone, activeId = nil, nil
    if GRID.Turf and GRID.Turf.GetZoneAtPos then
        activeZone, activeId = GRID.Turf.GetZoneAtPos(pos)
    end

    -- Fallback: check nearby flag pole if player is near one
    if not activeZone then
        for _, pole in ipairs(ents.FindByClass("grid_flag_pole")) do
            if IsValid(pole) then
                local polePos = pole:GetPos()
                local poleRadius = pole:GetInfluenceRadius()
                if not poleRadius or poleRadius <= 0 then poleRadius = 800 end
                if pos:DistToSqr(polePos) <= (poleRadius * poleRadius) then
                    local id = pole:GetTurfID()
                    activeId = id
                    local nwName = pole:GetNWString("GRID_ZoneName", "")
                    local nwOwner = pole:GetNWString("GRID_ZoneOwner", "")
                    local nwTax = pole:GetNWInt("GRID_TaxRate", 10)
                    activeZone = (GRID.Turf.Zones and GRID.Turf.Zones[id]) or (GRID.TurfData and GRID.TurfData[id]) or {
                        id = id,
                        name = (nwName ~= "" and nwName) or ("Territory #" .. id),
                        owner = (nwOwner ~= "" and nwOwner) or "neutral",
                        progress = 100,
                        tax_rate = nwTax,
                        pos = polePos,
                        radius = poleRadius
                    }
                    break
                end
            end
        end
    end

    -- 1. Draw Top Gang Zones Overview / Domination Pills
    local zonesList = {}
    if GRID.Turf and GRID.Turf.Zones then
        for id, z in pairs(GRID.Turf.Zones) do
            table.insert(zonesList, z)
        end
    end

    -- Fallback: if client zones table has not synced yet, populate from in-world flag poles
    if #zonesList == 0 then
        for _, pole in ipairs(ents.FindByClass("grid_flag_pole")) do
            if IsValid(pole) then
                local id = pole:GetTurfID()
                if id and id > 0 then
                    local nwName = pole:GetNWString("GRID_ZoneName", "")
                    local nwOwner = pole:GetNWString("GRID_ZoneOwner", "")
                    local nwTax = pole:GetNWInt("GRID_TaxRate", 10)
                    table.insert(zonesList, {
                        id = id,
                        name = (nwName ~= "" and nwName) or ("Territory #" .. id),
                        owner = (nwOwner ~= "" and nwOwner) or "neutral",
                        tax_rate = nwTax,
                        pos = pole:GetPos()
                    })
                end
            end
        end
    end
    table.sort(zonesList, function(a, b) return (a.id or 0) < (b.id or 0) end)

    local scrW = ScrW()
    local hasZones = #zonesList > 0
    local pillY = 10
    local pillH = 24

    if hasZones then
        local maxPillsW = math.min(scrW - 48, #zonesList * 140)
        local pillW = math.Clamp(math.floor(maxPillsW / #zonesList), 100, 150)
        local totalW = #zonesList * pillW + (#zonesList - 1) * 6
        local startX = (scrW - totalW) / 2

        for idx, z in ipairs(zonesList) do
            local zId = z.id or idx
            local isCurrent = (activeId and zId == activeId)
            local owner = z.owner
            local isOwned = (owner and owner ~= "" and owner ~= "neutral")
            local gangCol = isOwned and (GRID.GetGangColor and GRID.GetGangColor(owner) or Color(168, 85, 247)) or Color(148, 163, 184)
            local pX = startX + (idx - 1) * (pillW + 6)

            -- Capsule background
            local bgCol = isCurrent and Color(24, 32, 47, 245) or Color(11, 15, 25, 220)
            draw.RoundedBox(4, pX, pillY, pillW, pillH, bgCol)

            -- Border outline (highlighted if current)
            local borderCol = isCurrent and Color(248, 250, 252, 220) or Color(gangCol.r, gangCol.g, gangCol.b, 120)
            surface.SetDrawColor(borderCol.r, borderCol.g, borderCol.b, borderCol.a)
            surface.DrawOutlinedRect(pX, pillY, pillW, pillH, isCurrent and 2 or 1)

            -- Left indicator dot
            draw.RoundedBox(2, pX + 5, pillY + 5, 6, pillH - 10, gangCol)

            -- Zone Name
            local zName = z.name or ("Zone #" .. zId)
            local fitZName = (GRID.UI.FitText and GRID.UI.FitText(zName, "GRID_UI_Badge", pillW - 20)) or zName
            local txtCol = isCurrent and Color(248, 250, 252) or Color(203, 213, 225)
            draw.SimpleText(fitZName, "GRID_UI_Badge", pX + 16, pillY + pillH / 2, txtCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    local topOffset = hasZones and (pillY + pillH + 6) or 10

    -- 2. Draw Sleek Martial Law Emergency Ticker (Dynamic stack, zero overlap)
    local isLockdown = (GRID.Turf and GRID.Turf.IsLockdownActive and GRID.Turf.IsLockdownActive()) or false
    if isLockdown then
        local pulse = math.abs(math.sin(CurTime() * 3.5))
        local borderCol = Color(239, 68, 68, math.floor(180 + (75 * pulse)))

        local bannerW = math.Clamp(scrW - 48, 380, 560)
        local bannerH = 26
        local bannerX = (scrW - bannerW) / 2
        local bannerY = topOffset

        draw.RoundedBox(4, bannerX, bannerY, bannerW, bannerH, Color(11, 15, 25, 240))
        surface.SetDrawColor(borderCol.r, borderCol.g, borderCol.b, borderCol.a)
        surface.DrawOutlinedRect(bannerX, bannerY, bannerW, bannerH, 1)

        -- Left glowing accent indicator
        draw.RoundedBoxEx(4, bannerX, bannerY, 3, bannerH, borderCol, true, false, true, false)

        -- Tag: [!] MARTIAL LAW
        surface.SetFont("GRID_UI_Badge")
        local tagText = "[!] MARTIAL LAW"
        local tagW = surface.GetTextSize(tagText)
        draw.SimpleText(tagText, "GRID_UI_Badge", bannerX + 10, bannerY + bannerH / 2, borderCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Vertical divider
        local sepX = bannerX + 10 + tagW + 8
        draw.SimpleText("|", "GRID_UI_Caption", sepX, bannerY + bannerH / 2, Color(100, 116, 139), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Subtitle: Clean single line
        local subX = sepX + 12
        local maxSubW = bannerW - (subX - bannerX) - 10
        local subText = "Curfew in effect: police authorized to arrest and tase on sight"
        local fitSub = (GRID.UI.FitText and GRID.UI.FitText(subText, "GRID_UI_Caption", maxSubW)) or subText
        draw.SimpleText(fitSub, "GRID_UI_Caption", subX, bannerY + bannerH / 2, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        topOffset = bannerY + bannerH + 6
    end

    -- 3. Draw Active Territory Banner (Smooth animated fade when inside a zone)
    local inAnyZone = (activeZone ~= nil)
    local targetAlpha = inAnyZone and 255 or 0
    currentAlpha = math.Approach(currentAlpha, targetAlpha, FrameTime() * 450)

    if currentAlpha > 0 and activeZone then
        local a = math.floor(currentAlpha)
        local cardW = 420
        local cardH = 56
        local cardX = (scrW - cardW) / 2
        local cardY = topOffset

        local owner = activeZone.owner
        local isOwned = (owner and owner ~= "" and owner ~= "neutral")
        local ownerCol = isOwned and (GRID.GetGangColor and GRID.GetGangColor(owner) or Color(168, 85, 247)) or Color(251, 191, 36)
        local taxRate = tonumber(activeZone.tax_rate) or 10

        -- Background obsidian banner card
        draw.RoundedBox(8, cardX, cardY, cardW, cardH, Color(11, 15, 25, math.floor(a * 0.95)))

        -- Border with faction accent
        surface.SetDrawColor(ownerCol.r, ownerCol.g, ownerCol.b, math.floor(a * 0.8))
        surface.DrawOutlinedRect(cardX, cardY, cardW, cardH, 1)

        -- Top glowing accent strip
        draw.RoundedBoxEx(8, cardX, cardY, cardW, 3, Color(ownerCol.r, ownerCol.g, ownerCol.b, a), true, true, false, false)

        -- Territory Name Header (e.g. "DOWNTOWN PLAZA")
        local titleText = string.upper(tostring(activeZone.name or ("TERRITORY #" .. (activeId or 1))))
        draw.SimpleText(titleText, "GRID_UI_Header", cardX + (cardW / 2), cardY + 16, Color(248, 250, 252, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Subtitle: Controlled vs Unclaimed
        if isOwned then
            if owner == "Police" then
                local policeTxt = "Secured District  -  Under Police Protection"
                draw.SimpleText(policeTxt, "GRID_UI_Caption", cardX + cardW / 2, cardY + 38, Color(56, 189, 248, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                local taxCol
                if taxRate <= 10 then
                    taxCol = Color(74, 222, 128)
                elseif taxRate <= 20 then
                    taxCol = Color(250, 204, 21)
                elseif taxRate <= 30 then
                    taxCol = Color(251, 146, 60)
                else
                    taxCol = Color(248, 113, 113)
                end

                surface.SetFont("GRID_UI_Caption")
                local prefix = string.format("Controlled by %s  -  Extortion Tax: ", string.upper(owner))
                local taxSuffix = string.format("%d%%", taxRate)
                local preW = surface.GetTextSize(prefix)
                local sufW = surface.GetTextSize(taxSuffix)
                local totalLineW = preW + sufW
                local startLineX = cardX + (cardW - totalLineW) / 2

                draw.SimpleText(prefix, "GRID_UI_Caption", startLineX, cardY + 38, Color(ownerCol.r, ownerCol.g, ownerCol.b, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(taxSuffix, "GRID_UI_Caption", startLineX + preW, cardY + 38, Color(taxCol.r, taxCol.g, taxCol.b, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        else
            local unclaimTxt = "Unclaimed Territory  -  Capture flag pole to take control"
            draw.SimpleText(unclaimTxt, "GRID_UI_Caption", cardX + cardW / 2, cardY + 38, Color(251, 191, 36, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end

-- ========================================================
-- Turf Tax & Gang Protection Slider Interface
-- ========================================================

local function HandleOpenTurfTaxMenu()
    local turfId = net.ReadUInt(8)
    local turfName = net.ReadString()
    local currentTax = net.ReadUInt(8)
    local gangBank = net.ReadUInt(32)

    if IsValid(GRID.TurfTaxFrame) then
        GRID.TurfTaxFrame:Remove()
    end

    local fW, fH = 460, 310
    local frame = vgui.Create("DFrame")
    frame:SetSize(fW, fH)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(true)
    frame:MakePopup()
    GRID.TurfTaxFrame = frame

    frame.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(15, 23, 42, 250))
        draw.RoundedBoxEx(8, 0, 0, w, 44, Color(30, 41, 59, 255), true, true, false, false)
        surface.SetDrawColor(56, 189, 248, 120)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        draw.SimpleText("TERRITORY PROTECTION & TAXES", "GRID_FontMedium", 16, 12, Color(248, 250, 252))
    end

    local pnl = vgui.Create("DPanel", frame)
    pnl:SetPos(16, 54)
    pnl:SetSize(fW - 32, 180)
    pnl.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(24, 32, 47, 200))
        draw.SimpleText("Territory: " .. turfName, "GRID_FontMedium", 12, 12, Color(248, 250, 252))
        draw.SimpleText(string.format("Gang Vault Balance: $%d", gangBank), "GRID_FontSmall", 12, 38, Color(74, 222, 128))

        draw.SimpleText("Protection Racket Policy:", "GRID_FontSmall", 12, 66, Color(148, 163, 184))
        draw.SimpleText("Civilians running printers or shops in this district automatically pay", "GRID_FontSmall", 12, 86, Color(203, 213, 225))
        draw.SimpleText("this cut to your Gang Bank in exchange for territory protection.", "GRID_FontSmall", 12, 104, Color(203, 213, 225))
    end

    local sliderTax = vgui.Create("DNumSlider", pnl)
    sliderTax:SetPos(12, 125)
    sliderTax:SetSize(pnl:GetWide() - 24, 45)
    sliderTax:SetText("Protection Tax Rate (%)")
    sliderTax:SetMin(5)
    sliderTax:SetMax(30)
    sliderTax:SetDecimals(0)
    sliderTax:SetValue(currentTax)
    sliderTax:SetDark(false)

    local btnSave = vgui.Create("DButton", frame)
    btnSave:SetPos(16, fH - 58)
    btnSave:SetSize(fW - 32, 42)
    btnSave:SetText("APPLY TAX RATE TO TERRITORY")
    btnSave:SetFont("GRID_FontMedium")
    btnSave:SetTextColor(Color(255, 255, 255))
    btnSave.Paint = function(s, w, h)
        local col = s:IsHovered() and Color(37, 99, 235) or Color(59, 130, 246)
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnSave.DoClick = function()
        local newTax = math.Clamp(math.Round(sliderTax:GetValue()), 5, 30)
        net.Start("GRID_SetTurfTax")
            net.WriteUInt(turfId, 8)
            net.WriteUInt(newTax, 8)
        net.SendToServer()
        frame:Close()
    end
end

net.Receive("GRID_OpenTurfTaxMenu", HandleOpenTurfTaxMenu)
