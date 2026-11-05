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
        local radius = net.ReadUInt(16)
        local owner = net.ReadString()
        local progress = net.ReadUInt(8)
        local tax_rate = net.ReadUInt(8)

        GRID.Turf.Zones[id] = {
            id = id,
            name = name,
            pos = pos,
            radius = radius,
            owner = owner,
            progress = progress,
            tax_rate = tax_rate
        }

        GRID.TurfData[id] = {
            owner = owner,
            progress = progress,
            tax_rate = tax_rate
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

    GRID.TurfData[id] = {
        owner = owner,
        progress = progress,
        tax_rate = tax_rate
    }

    if GRID.Turf.Zones[id] then
        GRID.Turf.Zones[id].owner = owner
        GRID.Turf.Zones[id].progress = progress
        GRID.Turf.Zones[id].tax_rate = tax_rate
    end
end

net.Receive("GRID_TurfUpdate", HandleTurfUpdate)

function GRID.Turf.DrawHUD()
    local zoneCount = table.Count(GRID.Turf.Zones)
    if zoneCount == 0 then return end

    local scrW = ScrW()
    local startY = 16
    local totalW = zoneCount * 160 + (zoneCount - 1) * 12
    local startX = (scrW - totalW) / 2

    local idx = 0
    for id, zone in pairs(GRID.Turf.Zones) do
        local data = GRID.TurfData[id] or { owner = zone.owner, progress = 100 }
        local curX = startX + idx * 172
        idx = idx + 1

        -- Background Pill
        draw.RoundedBox(6, curX, startY, 160, 32, (GRID.Colors and GRID.Colors.Background) or Color(15, 23, 42, 230))

        -- Zone Name
        draw.SimpleText(zone.name, "GRID_FontSmall", curX + 80, startY + 4, (GRID.Colors and GRID.Colors.White) or Color(248, 250, 252), TEXT_ALIGN_CENTER)

        -- Owner String & Dynamic Color
        local ownerStr = (data.owner and data.owner ~= "" and data.owner ~= "neutral") and data.owner or "Neutral"
        local ownerCol = GRID.GetGangColor(data.owner)
        draw.SimpleText(ownerStr, "GRID_FontSmall", curX + 80, startY + 16, ownerCol, TEXT_ALIGN_CENTER)

        -- Progress bar underline
        draw.RoundedBox(2, curX + 8, startY + 28, 144, 2, Color(30, 41, 59))
        draw.RoundedBox(2, curX + 8, startY + 28, 144 * (data.progress / 100), 2, ownerCol)
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
