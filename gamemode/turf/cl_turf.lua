--[[
    cl_turf.lua - Client Turf Synchronization, Top Bar HUD & Tax Slider Menu
--]]

GW.Turf = GW.Turf or {}
GW.TurfData = GW.TurfData or {}

-- Full Zone Definitions Sync
net.Receive("GW_SyncTurfZones", function()
    local count = net.ReadUInt(8)
    GW.Turf.Zones = {}

    for i = 1, count do
        local id = net.ReadUInt(8)
        local name = net.ReadString()
        local pos = net.ReadVector()
        local radius = net.ReadUInt(16)
        local owner = net.ReadString()
        local progress = net.ReadUInt(8)
        local tax_rate = net.ReadUInt(8)

        GW.Turf.Zones[id] = {
            id = id,
            name = name,
            pos = pos,
            radius = radius,
            owner = owner,
            progress = progress,
            tax_rate = tax_rate
        }

        GW.TurfData[id] = {
            owner = owner,
            progress = progress,
            tax_rate = tax_rate
        }
    end

    if GW.Turf.RefreshSetupMenu then
        GW.Turf.RefreshSetupMenu()
    end
end)

-- Real-time Ownership & Capture Updates
net.Receive("GW_TurfUpdate", function()
    local id = net.ReadUInt(8)
    local owner = net.ReadString()
    local progress = net.ReadUInt(8)
    local tax_rate = net.ReadUInt(8)

    GW.TurfData[id] = {
        owner = owner,
        progress = progress,
        tax_rate = tax_rate
    }

    if GW.Turf.Zones[id] then
        GW.Turf.Zones[id].owner = owner
        GW.Turf.Zones[id].progress = progress
        GW.Turf.Zones[id].tax_rate = tax_rate
    end
end)

function GW.Turf.DrawHUD()
    local zoneCount = table.Count(GW.Turf.Zones)
    if zoneCount == 0 then return end

    local scrW = ScrW()
    local startY = 16
    local totalW = zoneCount * 160 + (zoneCount - 1) * 12
    local startX = (scrW - totalW) / 2

    local idx = 0
    for id, zone in pairs(GW.Turf.Zones) do
        local data = GW.TurfData[id] or { owner = zone.owner, progress = 100 }
        local curX = startX + idx * 172
        idx = idx + 1

        -- Background Pill
        draw.RoundedBox(6, curX, startY, 160, 32, GW.Colors.Background)

        -- Zone Name
        draw.SimpleText(zone.name, "GW_FontSmall", curX + 80, startY + 4, GW.Colors.White, TEXT_ALIGN_CENTER)

        -- Owner String & Dynamic Color
        local ownerStr = (data.owner and data.owner ~= "" and data.owner ~= "neutral") and data.owner or "Neutral"
        local ownerCol = GW.GetGangColor(data.owner)
        draw.SimpleText(ownerStr, "GW_FontSmall", curX + 80, startY + 16, ownerCol, TEXT_ALIGN_CENTER)

        -- Progress bar underline
        draw.RoundedBox(2, curX + 8, startY + 28, 144, 2, Color(30, 41, 59))
        draw.RoundedBox(2, curX + 8, startY + 28, 144 * (data.progress / 100), 2, ownerCol)
    end
end

-- ========================================================
-- Turf Tax & Gang Protection Slider Interface
-- ========================================================

net.Receive("GW_OpenTurfTaxMenu", function()
    local turfId = net.ReadUInt(8)
    local turfName = net.ReadString()
    local currentTax = net.ReadUInt(8)
    local gangBank = net.ReadUInt(32)

    if IsValid(GW.TurfTaxFrame) then
        GW.TurfTaxFrame:Remove()
    end

    local fW, fH = 460, 310
    local frame = vgui.Create("DFrame")
    frame:SetSize(fW, fH)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(true)
    frame:MakePopup()
    GW.TurfTaxFrame = frame

    frame.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(15, 23, 42, 250))
        draw.RoundedBoxEx(8, 0, 0, w, 44, Color(30, 41, 59, 255), true, true, false, false)
        surface.SetDrawColor(56, 189, 248, 120)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        draw.SimpleText("TERRITORY PROTECTION & TAXES", "GW_FontMedium", 16, 12, Color(248, 250, 252))
    end

    local pnl = vgui.Create("DPanel", frame)
    pnl:SetPos(16, 54)
    pnl:SetSize(fW - 32, 180)
    pnl.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(24, 32, 47, 200))
        draw.SimpleText("Territory: " .. turfName, "GW_FontMedium", 12, 12, Color(248, 250, 252))
        draw.SimpleText(string.format("Gang Vault Balance: $%d", gangBank), "GW_FontSmall", 12, 38, Color(74, 222, 128))

        draw.SimpleText("Protection Racket Policy:", "GW_FontSmall", 12, 66, Color(148, 163, 184))
        draw.SimpleText("Civilians running printers or shops in this district automatically pay", "GW_FontSmall", 12, 86, Color(203, 213, 225))
        draw.SimpleText("this cut to your Gang Bank in exchange for territory protection.", "GW_FontSmall", 12, 104, Color(203, 213, 225))
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
    btnSave:SetFont("GW_FontMedium")
    btnSave:SetTextColor(Color(255, 255, 255))
    btnSave.Paint = function(s, w, h)
        local col = s:IsHovered() and Color(37, 99, 235) or Color(59, 130, 246)
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnSave.DoClick = function()
        local newTax = math.Clamp(math.Round(sliderTax:GetValue()), 5, 30)
        net.Start("GW_SetTurfTax")
            net.WriteUInt(turfId, 8)
            net.WriteUInt(newTax, 8)
        net.SendToServer()
        frame:Close()
    end
end)
