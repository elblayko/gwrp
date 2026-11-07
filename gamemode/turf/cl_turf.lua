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

    -- Detect if player is currently inside a controlled territory
    local pos = ply:GetPos()
    local activeZone, activeId = nil, nil
    if GRID.Turf and GRID.Turf.GetZoneAtPos then
        activeZone, activeId = GRID.Turf.GetZoneAtPos(pos)
    end

    local isControlled = activeZone and activeZone.owner and activeZone.owner ~= "" and activeZone.owner ~= "neutral"

    -- Smooth animated fade in/out
    local targetAlpha = isControlled and 255 or 0
    currentAlpha = math.Approach(currentAlpha, targetAlpha, FrameTime() * 450)

    if currentAlpha > 0 and activeZone then
        local scrW = ScrW()
        local cardW = 380
        local cardH = 54
        local cardX = (scrW - cardW) / 2
        local cardY = 16

        local owner = activeZone.owner
        local ownerCol = (GRID.GetGangColor and GRID.GetGangColor(owner)) or Color(245, 158, 11)
        local taxRate = tonumber(activeZone.tax_rate) or 10

        -- Background obsidian banner card
        draw.RoundedBox(8, cardX, cardY, cardW, cardH, Color(15, 23, 42, math.floor(currentAlpha * 0.94)))
        
        -- Border with faction accent
        surface.SetDrawColor(ownerCol.r, ownerCol.g, ownerCol.b, math.floor(currentAlpha * 0.8))
        surface.DrawOutlinedRect(cardX, cardY, cardW, cardH, 2)

        -- Top glowing accent strip
        draw.RoundedBox(2, cardX, cardY, cardW, 3, Color(ownerCol.r, ownerCol.g, ownerCol.b, math.floor(currentAlpha)))

        -- Territory Name Header (e.g. "DOWNTOWN PLAZA")
        local titleText = string.upper(tostring(activeZone.name or "GANG TERRITORY"))
        draw.SimpleText(titleText, "GRID_UI_Header", cardX + (cardW / 2), cardY + 14, Color(248, 250, 252, math.floor(currentAlpha)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Controller & Extortion Tax Info Subtext
        local infoText = string.format("Controlled by %s   •   Extortion Tax: %d%%", owner, taxRate)
        draw.SimpleText(infoText, "GRID_UI_Caption", cardX + (cardW / 2), cardY + 36, Color(ownerCol.r, ownerCol.g, ownerCol.b, math.floor(currentAlpha)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
