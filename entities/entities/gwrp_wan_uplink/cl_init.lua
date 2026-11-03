--[[
    entities/entities/gwrp_wan_uplink/cl_init.lua
    GWRP Encrypted Satellite WAN Uplink Client Logic & UI
    Author: Toxic
--]]

include("shared.lua")

function ENT:Draw()
    self:DrawModel()

    -- Up-close 3D2D Status Display on the dish
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local distSqr = self:GetPos():DistToSqr(ply:GetPos())
    if distSqr > (280 * 280) then return end

    local key = self:GetEncryptionKey() or "NONE"
    local isOnline = self:GetIsOnline()
    local peers = self:GetLinkedPeerCount() or 0
    local sw = self:GetConnectedSwitch()
    local isLinkedToSwitch = IsValid(sw)

    local ang = self:GetAngles()
    local pos = self:GetPos() + ang:Up() * 45 + ang:Forward() * 5

    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    cam.Start3D2D(pos, ang, 0.08)
        local w, h = 320, 140
        local x, y = -w / 2, -h / 2

        -- Background panel
        draw.RoundedBox(8, x, y, w, h, Color(11, 15, 25, 235))
        surface.SetDrawColor(56, 189, 248, 180)
        surface.DrawOutlinedRect(x, y, w, h, 1)

        -- Header
        draw.SimpleText("SATELLITE WAN UPLINK", "GWRP_FontSmall", 0, y + 16, Color(56, 189, 248), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Key Pill
        local keyBoxW = 260
        draw.RoundedBox(4, -keyBoxW / 2, y + 36, keyBoxW, 26, Color(30, 41, 59, 220))
        surface.SetDrawColor(100, 116, 139, 120)
        surface.DrawOutlinedRect(-keyBoxW / 2, y + 36, keyBoxW, 26, 1)
        draw.SimpleText("KEY: " .. key, "GWRP_UI_BodyBold", 0, y + 49, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Status Indicator
        local statusCol = isOnline and Color(52, 211, 153) or Color(245, 158, 11)
        local statusTxt = isOnline and string.format("ONLINE (%d MESH PEER%s)", peers, peers == 1 and "" or "S") or (isLinkedToSwitch and "SEARCHING FOR PEERS..." or "NO SWITCH LINK")
        draw.SimpleText(statusTxt, "GWRP_UI_Caption", 0, y + 80, statusCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Switch link indicator
        local swText = isLinkedToSwitch and string.format("Switch Port %d | IP: %s", self:GetAssignedPort() or 0, self:GetIPAddress() ~= "" and self:GetIPAddress() or "DHCP") or "Connect to L3 Switch via Wire Tool"
        draw.SimpleText(swText, "GWRP_UI_Caption", 0, y + 104, Color(148, 163, 184), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Interaction hint
        draw.SimpleText("[E] Configure Encryption Key", "GWRP_UI_Caption", 0, y + 124, Color(203, 213, 225), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

-- Interactive Configuration Modal
local ActiveWANPanel = nil

local function OpenWANConfigUI(uplinkEnt, currentKey, isOnline, peerCount, switchEnt, subnet, ipStr)
    if IsValid(ActiveWANPanel) then
        ActiveWANPanel:Remove()
    end

    local frameW = 500
    local frameH = 360

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:Center()
    frame:SetTitle("")
    frame:SetVisible(true)
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:MakePopup()

    ActiveWANPanel = frame

    frame.Paint = function(s, w, h)
        draw.RoundedBox(10, 0, 0, w, h, Color(15, 23, 42, 250))
        surface.SetDrawColor(56, 189, 248, 140)
        surface.DrawOutlinedRect(0, 0, w, h, 2)

        -- Header Banner
        draw.RoundedBoxEx(10, 0, 0, w, 44, Color(11, 15, 25, 255), true, true, false, false)
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawLine(0, 44, w, 44)

        draw.SimpleText("SATELLITE WAN GATEWAY // CONFIGURATION", "GWRP_UI_BodyBold", 16, 22, Color(56, 189, 248), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Close Button
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(32, 28)
    closeBtn:SetPos(frameW - 40, 8)
    closeBtn:SetText("X")
    closeBtn:SetFont("GWRP_UI_BodyBold")
    closeBtn:SetTextColor(Color(148, 163, 184))
    closeBtn.Paint = function(s, w, h)
        if s:IsHovered() then
            draw.RoundedBox(4, 0, 0, w, h, Color(239, 68, 68, 80))
        end
    end
    closeBtn.DoClick = function()
        frame:Remove()
    end

    -- Status Card
    local statusCard = vgui.Create("DPanel", frame)
    statusCard:SetPos(16, 56)
    statusCard:SetSize(frameW - 32, 80)
    statusCard.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        local statusCol = isOnline and Color(52, 211, 153) or Color(245, 158, 11)
        local statusTxt = isOnline and string.format("STATUS: MESH ONLINE (%d PEER%s LINKED ACROSS MAP)", peerCount, peerCount == 1 and "" or "S") or "STATUS: STANDALONE (Searching for matching key...)"

        draw.SimpleText(statusTxt, "GWRP_UI_BodyBold", 14, 18, statusCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local swInfo = IsValid(switchEnt) and string.format("Local L3 Switch Subnet: 192.168.%d.0/24 (Gateway: 192.168.%d.1 | IP: %s)", subnet, subnet, ipStr ~= "" and ipStr or "Pending") or "Local Switch: Not Connected (Use Wire Tool to link to an L3 Switch)"
        draw.SimpleText(swInfo, "GWRP_UI_Caption", 14, 42, Color(203, 213, 225), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local routeInfo = isOnline and "Routing Engine: Active (Cross-subnet traffic forwarded over WAN tunnel)" or "Routing Engine: Idle (Requires 2+ matching uplinks)"
        draw.SimpleText(routeInfo, "GWRP_UI_Caption", 14, 62, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Encryption Key Input Section
    local keyLabel = vgui.Create("DLabel", frame)
    keyLabel:SetPos(16, 150)
    keyLabel:SetText("WIRELESS MESH ENCRYPTION KEY / CODE:")
    keyLabel:SetFont("GWRP_UI_Badge")
    keyLabel:SetTextColor(Color(248, 250, 252))
    keyLabel:SizeToContents()

    local keyDesc = vgui.Create("DLabel", frame)
    keyDesc:SetPos(16, 172)
    keyDesc:SetText("All Satellite WAN Uplinks with the same key automatically form an encrypted wireless mesh.")
    keyDesc:SetFont("GWRP_UI_Caption")
    keyDesc:SetTextColor(Color(148, 163, 184))
    keyDesc:SizeToContents()

    local keyEntry = vgui.Create("DTextEntry", frame)
    keyEntry:SetPos(16, 196)
    keyEntry:SetSize(frameW - 32, 40)
    keyEntry:SetFont("GWRP_FontSmall")
    keyEntry:SetText(currentKey or "")
    keyEntry:SetTextColor(Color(56, 189, 248))
    keyEntry.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 255))
        surface.SetDrawColor(s:IsEditing() and Color(56, 189, 248) or Color(51, 65, 85), 200)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        s:DrawTextEntryText(s:GetTextColor(), s:GetHighlightColor(), s:GetCursorColor())
    end

    -- Button Row
    local saveBtn = vgui.Create("DButton", frame)
    saveBtn:SetPos(16, 250)
    saveBtn:SetSize(225, 42)
    saveBtn:SetText("SAVE & BROADCAST KEY")
    saveBtn:SetFont("GWRP_UI_BodyBold")
    saveBtn:SetTextColor(Color(255, 255, 255))
    saveBtn.Paint = function(s, w, h)
        local bg = s:IsHovered() and Color(14, 165, 233) or Color(2, 132, 199)
        draw.RoundedBox(6, 0, 0, w, h, bg)
    end
    saveBtn.DoClick = function()
        local val = string.Trim(string.upper(keyEntry:GetValue()))
        if string.len(val) < 2 then
            surface.PlaySound("buttons/button10.wav")
            return
        end

        net.Start("GWRP_UpdateWANKey")
            net.WriteEntity(uplinkEnt)
            net.WriteString(val)
        net.SendToServer()

        surface.PlaySound("buttons/button14.wav")
        frame:Remove()
    end

    local genBtn = vgui.Create("DButton", frame)
    genBtn:SetPos(255, 250)
    genBtn:SetSize(225, 42)
    genBtn:SetText("GENERATE RANDOM KEY")
    genBtn:SetFont("GWRP_UI_BodyBold")
    genBtn:SetTextColor(Color(203, 213, 225))
    genBtn.Paint = function(s, w, h)
        local bg = s:IsHovered() and Color(51, 65, 85) or Color(30, 41, 59)
        draw.RoundedBox(6, 0, 0, w, h, bg)
    end
    genBtn.DoClick = function()
        local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        local code = ""
        for i = 1, 6 do
            local r = math.random(1, #chars)
            code = code .. string.sub(chars, r, r)
        end
        keyEntry:SetText("WAN-" .. code)
        surface.PlaySound("buttons/button15.wav")
    end

    -- Wiremod note
    local wireNote = vgui.Create("DLabel", frame)
    wireNote:SetPos(16, 308)
    wireNote:SetText("Tip: Wiremod supports dynamic key configuration via the EncryptionKey [STRING] input.")
    wireNote:SetFont("GWRP_UI_Caption")
    wireNote:SetTextColor(Color(100, 116, 139))
    wireNote:SizeToContents()
end

net.Receive("GWRP_OpenWANConfig", function()
    local uplinkEnt = net.ReadEntity()
    local currentKey = net.ReadString()
    local isOnline = net.ReadBool()
    local peerCount = net.ReadUInt(8)
    local switchEnt = net.ReadEntity()
    local subnet = net.ReadUInt(16)
    local ipStr = net.ReadString()

    OpenWANConfigUI(uplinkEnt, currentKey, isOnline, peerCount, switchEnt, subnet, ipStr)
end)
