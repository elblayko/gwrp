--[[
    entities/entities/gwrp_computer/cl_init.lua
    GWRP Personal Computer Client Logic & Hacking OS Terminal
    Author: Toxic
--]]

include("shared.lua")

-- Monospace Terminal Fonts (High contrast & crisp)
surface.CreateFont("GWRP_Terminal_Text", {
    font = "Lucida Console",
    size = 15,
    weight = 700,
    antialias = true,
    extended = true
})
surface.CreateFont("GWRP_Terminal_Bold", {
    font = "Lucida Console",
    size = 15,
    weight = 900,
    antialias = true,
    extended = true
})
surface.CreateFont("GWRP_Terminal_Header", {
    font = "Lucida Console",
    size = 16,
    weight = 700,
    antialias = true,
    extended = true
})

local ColorPalette = {
    white     = Color(240, 240, 240),
    green     = Color(74, 222, 128),
    cyan      = Color(56, 189, 248),
    yellow    = Color(250, 204, 21),
    red       = Color(248, 113, 113),
    blue      = Color(129, 140, 248),
    muted     = Color(148, 163, 184),
    dark      = Color(100, 116, 139),
    highlight = Color(251, 191, 36)
}

function ENT:Draw()
    self:DrawModel()

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local myPos = self:GetPos() + Vector(0, 0, 24)
    if myPos:DistToSqr(ply:EyePos()) > (240 * 240) then return end

    local ang = (ply:EyePos() - myPos):Angle()
    ang.p = 0
    ang.r = 0
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    cam.Start3D2D(myPos, ang, 0.08)
        local ip = self:GetIPAddress()
        local isNet = IsValid(self:GetConnectedSwitch()) and (ip and ip ~= "")
        local statusText = isNet and ("IP: " .. ip) or "OFFLINE (NO CARRIER)"
        local statusCol = isNet and Color(74, 222, 128) or Color(239, 68, 68)

        draw.RoundedBox(6, -115, -34, 230, 68, Color(15, 23, 42, 235))
        draw.RoundedBox(6, -113, -32, 226, 64, Color(30, 41, 59, 240))

        draw.SimpleText("GWRP CYBERDECK TERMINAL", "GWRP_FontSmall", 0, -24, Color(56, 189, 248), TEXT_ALIGN_CENTER)
        draw.SimpleText(statusText, "GWRP_FontSmall", 0, -5, statusCol, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] Access Shell", "GWRP_FontSmall", 0, 14, Color(148, 163, 184), TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

-- Terminal Window Singleton
local ActiveTerminal = nil

local function OpenTerminalUI(computerEnt, switchEnt, ipStr, isNet)
    if IsValid(ActiveTerminal) then
        ActiveTerminal:Remove()
    end

    local swValid = IsValid(switchEnt)
    local subnet = swValid and (switchEnt.GetSubnetID and switchEnt:GetSubnetID() or 1) or 0
    local localIP = (ipStr and ipStr ~= "") and ipStr or "127.0.0.1"
    local domainLabel = swValid and string.format("192.168.%d.0/24 (Gateway: 192.168.%d.1)", subnet, subnet) or "DISCONNECTED (No broadcast domain)"

    local frameW = math.Clamp(ScrW() * 0.65, 750, 950)
    local frameH = math.Clamp(ScrH() * 0.65, 500, 650)

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:Center()
    frame:SetTitle("")
    frame:SetVisible(true)
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:MakePopup()

    ActiveTerminal = frame
    frame.ComputerEntity = computerEnt

    -- Custom Terminal Solid CRT Background
    frame.Paint = function(s, w, h)
        -- Solid deep background
        draw.RoundedBox(8, 0, 0, w, h, Color(11, 15, 25, 255))

        -- Header Bar
        local headerCol = swValid and Color(16, 185, 129, 35) or Color(239, 68, 68, 35)
        draw.RoundedBoxEx(8, 0, 0, w, 38, Color(15, 23, 42, 255), true, true, false, false)
        surface.SetDrawColor(headerCol)
        surface.DrawRect(0, 0, w, 38)

        -- Glowing top border line
        surface.SetDrawColor(swValid and Color(34, 197, 94, 220) or Color(239, 68, 68, 220))
        surface.DrawLine(0, 37, w, 37)

        -- Frame border
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- Title text
        local title = string.format("GWRP CYBERDECK OS v2.4 -- [ Interface: eth0 | IP: %s ]", localIP)
        draw.SimpleText(title, "GWRP_Terminal_Header", 14, 10, swValid and Color(74, 222, 128) or Color(248, 113, 113), TEXT_ALIGN_LEFT)
    end

    -- Close Button
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(28, 24)
    closeBtn:SetPos(frameW - 36, 7)
    closeBtn:SetText("X")
    closeBtn:SetFont("GWRP_FontSmall")
    closeBtn:SetTextColor(Color(248, 250, 252))
    closeBtn.Paint = function(s, w, h)
        local bg = s:IsHovered() and Color(220, 38, 38, 220) or Color(71, 85, 105, 150)
        draw.RoundedBox(4, 0, 0, w, h, bg)
    end
    closeBtn.DoClick = function()
        surface.PlaySound("buttons/button15.wav")
        frame:Close()
    end

    -- Terminal Scroll Area with Solid Black Canvas
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetPos(12, 46)
    scroll:SetSize(frameW - 24, frameH - 96)
    scroll.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(6, 9, 15, 255))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local vbar = scroll:GetVBar()
    vbar:SetWide(6)
    vbar.Paint = function() end
    vbar.btnUp.Paint = function() end
    vbar.btnDown.Paint = function() end
    vbar.btnGrip.Paint = function(s, w, h)
        draw.RoundedBox(3, 0, 0, w, h, Color(56, 189, 248, 140))
    end

    local lineEntries = {}

    local function AddTerminalLine(text, colorKey)
        local line = scroll:Add("DPanel")
        line:Dock(TOP)
        line:DockMargin(8, 1, 8, 1)

        local col = ColorPalette[colorKey] or ColorPalette.white
        local str = tostring(text or "")

        line.Paint = function(s, w, h)
            draw.SimpleText(str, "GWRP_Terminal_Text", 0, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        line:SetTall(20)

        table.insert(lineEntries, line)
        scroll:InvalidateLayout(true)

        timer.Simple(0.02, function()
            if IsValid(scroll) and IsValid(vbar) then
                scroll:ScrollToChild(line)
            end
        end)
    end

    -- Welcome Banner Lines
    AddTerminalLine("================================================================================", "dark")
    AddTerminalLine("  GWRP CYBERDECK OPERATING SYSTEM - KERNEL 2.4.19 (x86_64)", "cyan")
    AddTerminalLine(string.format("  Local Host IP     : %s", localIP), "green")
    AddTerminalLine(string.format("  Broadcast Domain  : %s", domainLabel), "white")
    AddTerminalLine("  Ethernet Status   : " .. (swValid and "CONNECTED (eth0 UP, 1000BASE-T Full Duplex)" or "NO CARRIER (Cable unplugged)"), swValid and "green" or "red")
    AddTerminalLine("--------------------------------------------------------------------------------", "dark")
    AddTerminalLine("  Type 'help' to list available commands.", "white")
    AddTerminalLine("================================================================================", "dark")
    AddTerminalLine(" ", "muted")

    -- Bottom Command Input Area
    local bottomPanel = vgui.Create("DPanel", frame)
    bottomPanel:SetPos(12, frameH - 44)
    bottomPanel:SetSize(frameW - 24, 34)
    bottomPanel.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(15, 23, 42, 255))
        surface.SetDrawColor(Color(56, 189, 248, 140))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local inMSF = false
    local currentMSFMod = "cash_siphon"

    local promptLabel = vgui.Create("DLabel", bottomPanel)
    promptLabel:SetPos(10, 8)
    promptLabel:SetFont("GWRP_Terminal_Bold")
    promptLabel:SetText("root@gw-deck:~#")
    promptLabel:SetTextColor(Color(74, 222, 128))
    promptLabel:SizeToContents()

    local textEntry = vgui.Create("DTextEntry", bottomPanel)
    textEntry:SetPos(promptLabel:GetWide() + 18, 3)
    textEntry:SetSize(bottomPanel:GetWide() - promptLabel:GetWide() - 26, 28)
    textEntry:SetFont("GWRP_Terminal_Text")
    textEntry:SetTextColor(Color(248, 250, 252))
    textEntry.Paint = function(s, w, h)
        s:DrawTextEntryText(Color(248, 250, 252), Color(6, 182, 212), Color(74, 222, 128))
    end

    local function UpdatePrompt()
        if inMSF then
            local modTag = (currentMSFMod ~= "") and string.format("exploit(%s)", currentMSFMod) or ""
            promptLabel:SetText(string.format("msf6 %s> ", modTag))
            promptLabel:SetTextColor(Color(251, 191, 36))
        else
            promptLabel:SetText("root@gw-deck:~# ")
            promptLabel:SetTextColor(Color(74, 222, 128))
        end
        promptLabel:SizeToContents()
        local pw = promptLabel:GetWide()
        textEntry:SetPos(pw + 16, 3)
        textEntry:SetSize(bottomPanel:GetWide() - pw - 24, 28)
    end

    timer.Simple(0.05, function()
        if IsValid(textEntry) then
            textEntry:RequestFocus()
        end
    end)

    frame.AddTerminalLine = AddTerminalLine

    textEntry.OnEnter = function(s)
        local val = string.Trim(s:GetValue() or "")
        s:SetText("")
        s:RequestFocus()

        if val == "" then return end

        surface.PlaySound("buttons/button15.wav")
        local promptPrefix = inMSF and (promptLabel:GetText()) or "root@gw-deck:~# "
        AddTerminalLine(promptPrefix .. val, "highlight")

        local cmdLower = string.lower(val)
        local parts = string.Explode(" ", val)
        local c1 = string.lower(parts[1] or "")
        local c2 = string.lower(parts[2] or "")

        if cmdLower == "clear" then
            for _, p in ipairs(lineEntries) do
                if IsValid(p) then p:Remove() end
            end
            lineEntries = {}
            AddTerminalLine("Terminal cleared.", "muted")
            return
        end

        if not IsValid(computerEnt) then
            AddTerminalLine("Error: Terminal connection dropped.", "red")
            return
        end

        -- Handle MSF Console Mode
        if inMSF then
            if cmdLower == "exit" or cmdLower == "quit" or cmdLower == "back" then
                inMSF = false
                UpdatePrompt()
                AddTerminalLine("Exited Metasploit Framework console.", "muted")
                return
            end

            if c1 == "use" then
                if string.find(c2, "overheat") or string.find(c2, "thermal") then
                    currentMSFMod = "thermal_overheat"
                elseif string.find(c2, "siphon") or string.find(c2, "cash") then
                    currentMSFMod = "cash_siphon"
                end
                UpdatePrompt()
                net.Start("GWRP_RunComputerCommand")
                    net.WriteEntity(computerEnt)
                    net.WriteString("msf use " .. (parts[2] or ""))
                net.SendToServer()
                return
            end

            if cmdLower == "help" then
                net.Start("GWRP_RunComputerCommand")
                    net.WriteEntity(computerEnt)
                    net.WriteString("msf help")
                net.SendToServer()
                return
            end

            if cmdLower == "show modules" or cmdLower == "modules" or cmdLower == "show" then
                net.Start("GWRP_RunComputerCommand")
                    net.WriteEntity(computerEnt)
                    net.WriteString("msf modules")
                net.SendToServer()
                return
            end

            if c1 == "run" or c1 == "exploit" then
                net.Start("GWRP_RunComputerCommand")
                    net.WriteEntity(computerEnt)
                    net.WriteString("msf run " .. (parts[2] or ""))
                net.SendToServer()
                return
            end

            -- Default: forward directly to server with "msf " prefix if not already
            local forwardCmd = (string.sub(val, 1, 4) == "msf ") and val or ("msf " .. val)
            net.Start("GWRP_RunComputerCommand")
                net.WriteEntity(computerEnt)
                net.WriteString(forwardCmd)
            net.SendToServer()
            return
        else
            -- Normal bash shell
            if cmdLower == "exit" or cmdLower == "quit" then
                frame:Close()
                return
            end

            -- If user enters "msf" or "msfconsole" without arguments, enter MSF mode:
            if (cmdLower == "msf" or cmdLower == "msfconsole") and not parts[2] then
                inMSF = true
                currentMSFMod = "cash_siphon"
                UpdatePrompt()
                net.Start("GWRP_RunComputerCommand")
                    net.WriteEntity(computerEnt)
                    net.WriteString("msf")
                net.SendToServer()
                return
            end

            net.Start("GWRP_RunComputerCommand")
                net.WriteEntity(computerEnt)
                net.WriteString(val)
            net.SendToServer()
        end
    end
end

net.Receive("GWRP_OpenComputerOS", function()
    local computerEnt = net.ReadEntity()
    local switchEnt = net.ReadEntity()
    local ipStr = net.ReadString()
    local isNet = net.ReadBool()

    OpenTerminalUI(computerEnt, switchEnt, ipStr, isNet)
end)

net.Receive("GWRP_ComputerCommandResponse", function()
    local computer = net.ReadEntity()
    local rawCmd = net.ReadString()
    local lineCount = net.ReadUInt(8)

    if not IsValid(ActiveTerminal) then return end

    for i = 1, lineCount do
        local lineText = net.ReadString()
        local lineColor = net.ReadString()
        ActiveTerminal.AddTerminalLine(lineText, lineColor)
    end

    surface.PlaySound("buttons/button14.wav")
end)
