--[[
    cl_turf_setup.lua - Comprehensive Admin & Debug Executive HUD
    Author: Toxic
--]]

GWRP.Turf = GWRP.Turf or {}
GWRP.Turf.AdminESPEnabled = false
GWRP.Turf.SetupFrame = nil
GWRP.Turf.SelectedZoneID = nil
GWRP.Turf.PreviewRadius = 450
GWRP.Turf.PreviewName = "Downtown Plaza"
GWRP.AdminActiveTab = "players"

-- ========================================================
-- 1. 3D VISUAL ADMIN ESP & PLACEMENT PREVIEW
-- ========================================================

local function DrawCircle3D(pos, radius, col, segments)
    segments = segments or 48
    local step = (math.pi * 2) / segments

    for i = 0, segments - 1 do
        local a1 = i * step
        local a2 = (i + 1) * step

        local p1 = pos + Vector(math.cos(a1) * radius, math.sin(a1) * radius, 2)
        local p2 = pos + Vector(math.cos(a2) * radius, math.sin(a2) * radius, 2)
        render.DrawLine(p1, p2, col, true)
    end
end

hook.Add("PostDrawTranslucentRenderables", "GWRP_TurfAdmin3DESP", function(bDepth, bSkybox)
    if bDepth or bSkybox then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then return end
    if not GWRP.Turf.AdminESPEnabled then return end
    if not IsValid(GWRP.Turf.SetupFrame) or GWRP.AdminActiveTab ~= "turf" then return end

    -- 1. Draw boundary circle on ground for each placed Gang Pole when in setup menu
    for id, zone in pairs(GWRP.Turf.Zones or {}) do
        local pos = zone.pos
        local radius = zone.radius or 450
        local col = GWRP.GetGangColor(zone.owner)

        DrawCircle3D(pos, radius, col, 48)
    end

    -- 2. Real-Time Holographic Placement Preview
    if IsValid(GWRP.Turf.SetupFrame) and GWRP.AdminActiveTab == "turf" then
        local tr = (ply.GetEyeTraceNoCursor and ply:GetEyeTraceNoCursor()) or ply:GetEyeTrace()
        if tr.Hit and not tr.HitSky then
            local hitPos = tr.HitPos
            local prevCol = Color(56, 189, 248, 220)

            DrawCircle3D(hitPos, GWRP.Turf.PreviewRadius, prevCol, 48)
            render.DrawLine(hitPos, hitPos + Vector(0, 0, 100), prevCol, true)

            local ang = (ply:EyePos() - hitPos):Angle()
            ang.p = 0
            ang.r = 0
            ang:RotateAroundAxis(ang:Up(), 90)
            ang:RotateAroundAxis(ang:Forward(), 90)

            cam.Start3D2D(hitPos + Vector(0, 0, 110), ang, 0.12)
                draw.RoundedBox(4, -130, -30, 260, 60, Color(15, 23, 42, 230))
                draw.RoundedBox(4, -130, -30, 260, 3, prevCol)
                draw.SimpleText("Flag Pole Placement Preview", "GWRP_FontSmall", 0, -20, GWRP.Colors.Gold, TEXT_ALIGN_CENTER)
                draw.SimpleText(string.format("%s (Radius: %d)", GWRP.Turf.PreviewName, GWRP.Turf.PreviewRadius), "GWRP_FontSmall", 0, 4, GWRP.Colors.White, TEXT_ALIGN_CENTER)
            cam.End3D2D()
        end
    end
end)

-- ========================================================
-- 2. IN-GAME ADMIN & DEBUG DASHBOARD
-- ========================================================

function GWRP.Turf.OpenSetupMenu()
    if IsValid(GWRP.Turf.SetupFrame) then
        GWRP.Turf.SetupFrame:Close()
        GWRP.Turf.SetupFrame = nil
        return
    end

    local ply = LocalPlayer()
    if not IsValid(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then
        GWRP.Notify(ply, "You must be an administrator to access the Admin HUD!", NOTIFY_ERROR)
        return
    end

    local frame = vgui.Create("DFrame")
    frame:SetSize(920, 620)
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:ShowCloseButton(true)
    GWRP.Turf.SetupFrame = frame

    frame.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(11, 15, 25, 252))
        draw.RoundedBox(8, 0, 0, w, 52, Color(17, 24, 39, 255))
        surface.SetDrawColor(30, 41, 59, 220)
        surface.DrawLine(0, 52, w, 52)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        draw.SimpleText("GWRP Admin & Debug Dashboard", "GWRP_UI_Title", 20, 12, GWRP.Colors.White)
        draw.SimpleText("SQLite Active | Map: " .. game.GetMap(), "GWRP_UI_Caption", w - 40, 20, GWRP.Colors.MoneyGreen, TEXT_ALIGN_RIGHT)
    end

    -- Tab Navigation Strip
    local tabContainer = vgui.Create("DPanel", frame)
    tabContainer:SetPos(16, 62)
    tabContainer:SetSize(888, 38)
    tabContainer.Paint = function() end

    local contentPanel = vgui.Create("DPanel", frame)
    contentPanel:SetPos(16, 108)
    contentPanel:SetSize(888, 496)
    contentPanel.Paint = function() end

    local tabs = {
        { id = "players", name = "Player Debug & Economy" },
        { id = "turf", name = "Turf & Flag Poles" },
        { id = "spawners", name = "Game Loop & Spawners" }
    }

    local function SwitchTab(tabId)
        GWRP.AdminActiveTab = tabId
        contentPanel:Clear()

        if tabId == "players" then
            GWRP.Turf.RenderPlayerDebug(contentPanel)
        elseif tabId == "turf" then
            GWRP.Turf.RenderTurfTab(contentPanel)
        elseif tabId == "spawners" then
            GWRP.Turf.RenderSpawnersTab(contentPanel)
        end
    end

    local btnX = 0
    for _, t in ipairs(tabs) do
        local btn = vgui.Create("DButton", tabContainer)
        btn:SetPos(btnX, 0)
        btn:SetSize(220, 36)
        btn:SetText("")
        btn.Paint = function(s, w, h)
            local isActive = (GWRP.AdminActiveTab == t.id)
            local bg = isActive and Color(30, 41, 59, 255) or (s:IsHovered() and Color(24, 32, 47, 180) or Color(15, 23, 42, 140))
            draw.RoundedBox(6, 0, 0, w, h, bg)
            if isActive then
                draw.RoundedBox(2, 0, h - 3, w, 3, Color(6, 182, 212))
            end
            local textCol = isActive and Color(248, 250, 252) or Color(148, 163, 184)
            draw.SimpleText(t.name, "GWRP_UI_Btn", w / 2, h / 2, textCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        btn.DoClick = function()
            SwitchTab(t.id)
        end
        btnX = btnX + 228
    end

    SwitchTab(GWRP.AdminActiveTab or "players")
end

-- ========================================================
-- TAB 1: PLAYER MANAGEMENT & ECONOMY DEBUG
-- ========================================================

function GWRP.Turf.RenderPlayerDebug(parent)
    local contW, contH = parent:GetWide(), parent:GetTall()

    -- Left: Searchable Player List
    local listPanel = vgui.Create("DPanel", parent)
    listPanel:SetPos(0, 0)
    listPanel:SetSize(420, contH)
    listPanel.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local txtSearch = vgui.Create("DTextEntry", listPanel)
    txtSearch:SetPos(10, 10)
    txtSearch:SetSize(400, 32)
    txtSearch:SetPlaceholderText("Search online players...")
    txtSearch:SetFont("GWRP_UI_Body")

    local playerList = vgui.Create("DListView", listPanel)
    playerList:SetPos(10, 48)
    playerList:SetSize(400, contH - 58)
    playerList:SetMultiSelect(false)
    playerList:AddColumn("Player Name"):SetFixedWidth(140)
    playerList:AddColumn("Role"):SetFixedWidth(110)
    playerList:AddColumn("Wallet"):SetFixedWidth(85)
    playerList:AddColumn("Health"):SetFixedWidth(60)

    -- Right: Controls / Properties Panel
    local actionPanel = vgui.Create("DPanel", parent)
    actionPanel:SetPos(436, 0)
    actionPanel:SetSize(contW - 436, contH)
    actionPanel.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local selectedPlayer = nil

    local function PopulatePlayers(filter)
        playerList:Clear()
        for _, p in ipairs(player.GetAll()) do
            local nick = p:Nick()
            if filter and filter ~= "" and not string.find(string.lower(nick), string.lower(filter), 1, true) then
                continue
            end
            local job = p:GetJobData()
            local line = playerList:AddLine(nick, job and job.name or "Citizen", "$" .. string.Comma(p:GetMoney()), p:Health() .. " HP")
            line.Player = p
        end
    end

    txtSearch.OnChange = function(s)
        PopulatePlayers(s:GetText())
    end
    PopulatePlayers("")

    local function RefreshActionPanel()
        actionPanel:Clear()

        if not IsValid(selectedPlayer) then
            local lbl = vgui.Create("DLabel", actionPanel)
            lbl:Dock(FILL)
            lbl:SetText("Select a player from the list to view and edit properties.")
            lbl:SetFont("GWRP_UI_Header")
            lbl:SetContentAlignment(5)
            lbl:SetTextColor(Color(148, 163, 184))
            return
        end

        local pNick = selectedPlayer:Nick()
        local pSteam = selectedPlayer:SteamID()
        local pMoney = selectedPlayer:GetMoney()
        local pGang = selectedPlayer:GetGang()

        local topInfo = vgui.Create("DPanel", actionPanel)
        topInfo:Dock(TOP)
        topInfo:SetTall(64)
        topInfo.Paint = function(s, w, h)
            draw.RoundedBox(6, 10, 10, w - 20, h - 14, Color(24, 32, 47, 240))
            draw.SimpleText(pNick, "GWRP_UI_Header", 20, 18, Color(248, 250, 252))
            draw.SimpleText(pSteam .. "  |  Wallet: $" .. string.Comma(pMoney) .. "  |  Gang: " .. (pGang ~= "" and pGang or "None"), "GWRP_UI_Caption", 20, 38, Color(148, 163, 184))
        end

        local scroll = vgui.Create("DScrollPanel", actionPanel)
        scroll:Dock(FILL)
        scroll:DockMargin(10, 6, 10, 10)

        -- Section 1: Money & Economy Debug
        local secMoney = scroll:Add("DPanel")
        secMoney:Dock(TOP)
        secMoney:DockMargin(0, 0, 0, 12)
        secMoney:SetTall(110)
        secMoney.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(24, 32, 47, 180))
            draw.SimpleText("Wallet & Economy Control", "GWRP_UI_Sub", 14, 10, Color(74, 222, 128))
        end

        local txtMoney = vgui.Create("DTextEntry", secMoney)
        txtMoney:SetPos(14, 34)
        txtMoney:SetSize(180, 32)
        txtMoney:SetText(tostring(pMoney))
        txtMoney:SetNumeric(true)
        txtMoney:SetFont("GWRP_UI_Body")

        local btnSetMoney = vgui.Create("DButton", secMoney)
        btnSetMoney:SetPos(202, 34)
        btnSetMoney:SetSize(120, 32)
        btnSetMoney:SetText("Set Wallet ($)")
        btnSetMoney.DoClick = function()
            local amt = tonumber(txtMoney:GetText()) or 0
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("set_money")
                net.WriteEntity(selectedPlayer)
                net.WriteInt(amt, 32)
            net.SendToServer()
            timer.Simple(0.2, function() PopulatePlayers(txtSearch:GetText()); RefreshActionPanel() end)
        end

        local btnAdd10k = vgui.Create("DButton", secMoney)
        btnAdd10k:SetPos(14, 72)
        btnAdd10k:SetSize(90, 28)
        btnAdd10k:SetText("+ $10,000")
        btnAdd10k.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("add_money")
                net.WriteEntity(selectedPlayer)
                net.WriteInt(10000, 32)
            net.SendToServer()
            timer.Simple(0.2, function() PopulatePlayers(txtSearch:GetText()); RefreshActionPanel() end)
        end

        local btnAdd100k = vgui.Create("DButton", secMoney)
        btnAdd100k:SetPos(110, 72)
        btnAdd100k:SetSize(90, 28)
        btnAdd100k:SetText("+ $100,000")
        btnAdd100k.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("add_money")
                net.WriteEntity(selectedPlayer)
                net.WriteInt(100000, 32)
            net.SendToServer()
            timer.Simple(0.2, function() PopulatePlayers(txtSearch:GetText()); RefreshActionPanel() end)
        end

        local btnResetMoney = vgui.Create("DButton", secMoney)
        btnResetMoney:SetPos(206, 72)
        btnResetMoney:SetSize(116, 28)
        btnResetMoney:SetText("Reset ($1,000)")
        btnResetMoney.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("set_money")
                net.WriteEntity(selectedPlayer)
                net.WriteInt(1000, 32)
            net.SendToServer()
            timer.Simple(0.2, function() PopulatePlayers(txtSearch:GetText()); RefreshActionPanel() end)
        end

        -- Section 2: Role & Gang Control
        local secJob = scroll:Add("DPanel")
        secJob:Dock(TOP)
        secJob:DockMargin(0, 0, 0, 12)
        secJob:SetTall(110)
        secJob.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(24, 32, 47, 180))
            draw.SimpleText("Career & Gang Assignment", "GWRP_UI_Sub", 14, 10, Color(56, 189, 248))
        end

        local comboJob = vgui.Create("DComboBox", secJob)
        comboJob:SetPos(14, 34)
        comboJob:SetSize(220, 30)
        comboJob:SetValue(selectedPlayer:GetJobData() and selectedPlayer:GetJobData().name or "Citizen")
        for jId, jData in pairs(GWRP.Jobs or {}) do
            comboJob:AddChoice(jData.name, jId)
        end

        local btnSetJob = vgui.Create("DButton", secJob)
        btnSetJob:SetPos(240, 34)
        btnSetJob:SetSize(130, 30)
        btnSetJob:SetText("Force Role")
        btnSetJob.DoClick = function()
            local _, jId = comboJob:GetSelected()
            if jId then
                net.Start("GWRP_AdminDebugAction")
                    net.WriteString("set_job")
                    net.WriteEntity(selectedPlayer)
                    net.WriteString(jId)
                net.SendToServer()
                timer.Simple(0.3, function() PopulatePlayers(txtSearch:GetText()); RefreshActionPanel() end)
            end
        end

        local txtGang = vgui.Create("DTextEntry", secJob)
        txtGang:SetPos(14, 70)
        txtGang:SetSize(160, 28)
        txtGang:SetText(pGang)
        txtGang:SetPlaceholderText("Gang Name...")

        local btnSetGang = vgui.Create("DButton", secJob)
        btnSetGang:SetPos(180, 70)
        btnSetGang:SetSize(90, 28)
        btnSetGang:SetText("Set Gang")
        btnSetGang.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("set_gang")
                net.WriteEntity(selectedPlayer)
                net.WriteString(txtGang:GetText())
            net.SendToServer()
            timer.Simple(0.3, function() PopulatePlayers(txtSearch:GetText()); RefreshActionPanel() end)
        end

        local btnClearGang = vgui.Create("DButton", secJob)
        btnClearGang:SetPos(276, 70)
        btnClearGang:SetSize(94, 28)
        btnClearGang:SetText("Clear Gang")
        btnClearGang.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("set_gang")
                net.WriteEntity(selectedPlayer)
                net.WriteString("")
            net.SendToServer()
            timer.Simple(0.3, function() PopulatePlayers(txtSearch:GetText()); RefreshActionPanel() end)
        end

        -- Section 3: Vitals & Cheats
        local secVitals = scroll:Add("DPanel")
        secVitals:Dock(TOP)
        secVitals:DockMargin(0, 0, 0, 12)
        secVitals:SetTall(100)
        secVitals.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(24, 32, 47, 180))
            draw.SimpleText("Health, Armor & Immortality", "GWRP_UI_Sub", 14, 10, Color(245, 158, 11))
        end

        local btnHeal = vgui.Create("DButton", secVitals)
        btnHeal:SetPos(14, 32)
        btnHeal:SetSize(110, 28)
        btnHeal:SetText("Heal (100 HP)")
        btnHeal.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("set_health")
                net.WriteEntity(selectedPlayer)
                net.WriteInt(100, 32)
            net.SendToServer()
        end

        local btnArmor = vgui.Create("DButton", secVitals)
        btnArmor:SetPos(130, 32)
        btnArmor:SetSize(110, 28)
        btnArmor:SetText("Set 100% Armor")
        btnArmor.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("set_armor")
                net.WriteEntity(selectedPlayer)
                net.WriteInt(100, 32)
            net.SendToServer()
        end

        local btnGod = vgui.Create("DButton", secVitals)
        btnGod:SetPos(246, 32)
        btnGod:SetSize(120, 28)
        btnGod:SetText("Toggle Godmode")
        btnGod.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("godmode")
                net.WriteEntity(selectedPlayer)
            net.SendToServer()
        end

        local btnRespawn = vgui.Create("DButton", secVitals)
        btnRespawn:SetPos(14, 64)
        btnRespawn:SetSize(140, 26)
        btnRespawn:SetText("Respawn / Revive")
        btnRespawn.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("respawn")
                net.WriteEntity(selectedPlayer)
            net.SendToServer()
        end

        -- Section 4: Teleportation
        local secTele = scroll:Add("DPanel")
        secTele:Dock(TOP)
        secTele:DockMargin(0, 0, 0, 12)
        secTele:SetTall(75)
        secTele.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(24, 32, 47, 180))
            draw.SimpleText("Spatial Teleportation", "GWRP_UI_Sub", 14, 10, Color(168, 85, 247))
        end

        local btnGoto = vgui.Create("DButton", secTele)
        btnGoto:SetPos(14, 34)
        btnGoto:SetSize(140, 28)
        btnGoto:SetText("Teleport To (Goto)")
        btnGoto.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("goto")
                net.WriteEntity(selectedPlayer)
            net.SendToServer()
        end

        local btnBring = vgui.Create("DButton", secTele)
        btnBring:SetPos(162, 34)
        btnBring:SetSize(140, 28)
        btnBring:SetText("Bring Player Here")
        btnBring.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("bring")
                net.WriteEntity(selectedPlayer)
            net.SendToServer()
        end
    end

    playerList.OnRowSelected = function(s, index, pnl)
        selectedPlayer = pnl.Player
        RefreshActionPanel()
    end

    RefreshActionPanel()
end

-- ========================================================
-- TAB 2: TURF & FLAG POLES SETUP
-- ========================================================

function GWRP.Turf.RenderTurfTab(parent)
    local contW, contH = parent:GetWide(), parent:GetTall()

    -- Top Profile Action Bar
    local topBar = vgui.Create("DPanel", parent)
    topBar:SetPos(0, 0)
    topBar:SetSize(contW, 38)
    topBar.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(17, 24, 39, 200))
    end

    local btnSave = vgui.Create("DButton", topBar)
    btnSave:SetSize(150, 28)
    btnSave:SetPos(8, 5)
    btnSave:SetText("Save to SQLite")
    btnSave.DoClick = function()
        net.Start("GWRP_AdminTurfAction")
            net.WriteString("save")
        net.SendToServer()
    end

    local btnReload = vgui.Create("DButton", topBar)
    btnReload:SetSize(150, 28)
    btnReload:SetPos(166, 5)
    btnReload:SetText("Reload from SQLite")
    btnReload.DoClick = function()
        net.Start("GWRP_AdminTurfAction")
            net.WriteString("reload")
        net.SendToServer()
    end

    local btnClear = vgui.Create("DButton", topBar)
    btnClear:SetSize(140, 28)
    btnClear:SetPos(324, 5)
    btnClear:SetText("Clear All Poles")
    btnClear.DoClick = function()
        Derma_Query("Are you sure you want to remove all gang poles from this map?", "Confirm Clear",
            "Yes, Clear All", function()
                net.Start("GWRP_AdminTurfAction")
                    net.WriteString("clear")
                net.SendToServer()
            end,
            "Cancel", function() end
        )
    end

    local chkESP = vgui.Create("DCheckBoxLabel", topBar)
    chkESP:SetPos(490, 10)
    chkESP:SetText("Enable 3D Admin ESP Rings")
    chkESP:SetValue(GWRP.Turf.AdminESPEnabled)
    chkESP:SizeToContents()
    function chkESP:OnChange(val)
        GWRP.Turf.AdminESPEnabled = val
    end

    -- Left: Placed Poles List
    local listPoles = vgui.Create("DListView", parent)
    listPoles:SetPos(0, 48)
    listPoles:SetSize(420, contH - 48)
    listPoles:SetMultiSelect(false)
    listPoles:AddColumn("ID"):SetFixedWidth(35)
    listPoles:AddColumn("Name"):SetFixedWidth(155)
    listPoles:AddColumn("Radius"):SetFixedWidth(70)
    listPoles:AddColumn("Owner"):SetFixedWidth(120)

    -- Right: Controls / Properties Panel
    local propPanel = vgui.Create("DPanel", parent)
    propPanel:SetPos(436, 48)
    propPanel:SetSize(contW - 436, contH - 48)
    propPanel.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
        draw.SimpleText("Flag Pole Placement & Settings", "GWRP_UI_Header", 16, 16, GWRP.Colors.White)
        draw.SimpleText("Territory Name:", "GWRP_UI_Caption", 16, 52, GWRP.Colors.Muted)
        draw.SimpleText("Initial Faction / Gang Owner:", "GWRP_UI_Caption", 16, 114, GWRP.Colors.Muted)
    end

    local txtName = vgui.Create("DTextEntry", propPanel)
    txtName:SetPos(16, 72)
    txtName:SetSize(360, 30)
    txtName:SetText(GWRP.Turf.PreviewName)
    txtName.OnChange = function(s)
        GWRP.Turf.PreviewName = s:GetText()
    end

    local comboOwner = vgui.Create("DComboBox", propPanel)
    comboOwner:SetPos(16, 134)
    comboOwner:SetSize(360, 30)
    comboOwner:AddChoice("Neutral (Unclaimed)", "neutral", true)
    comboOwner:AddChoice("Police / SWAT", "police")

    -- Add known gang options
    local addedGangs = {}
    for _, z in pairs(GWRP.Turf.Zones or {}) do
        if z.owner and z.owner ~= "" and z.owner ~= "neutral" and z.owner ~= "police" and not addedGangs[z.owner] then
            addedGangs[z.owner] = true
            comboOwner:AddChoice("Gang: " .. z.owner, z.owner)
        end
    end
    for _, p in ipairs(player.GetAll()) do
        local g = p.GetGang and p:GetGang()
        if g and g ~= "" and g ~= "neutral" and g ~= "police" and not addedGangs[g] then
            addedGangs[g] = true
            comboOwner:AddChoice("Gang: " .. g, g)
        end
    end

    local sliderRadius = vgui.Create("DNumSlider", propPanel)
    sliderRadius:SetPos(16, 178)
    sliderRadius:SetSize(360, 45)
    sliderRadius:SetText("Capture Radius")
    sliderRadius:SetMin(200)
    sliderRadius:SetMax(1200)
    sliderRadius:SetDecimals(0)
    sliderRadius:SetValue(GWRP.Turf.PreviewRadius)
    sliderRadius.OnValueChanged = function(s, val)
        GWRP.Turf.PreviewRadius = math.Round(val)
    end

    local function PopulatePoles()
        if not IsValid(listPoles) then return end
        listPoles:Clear()
        for id, zone in pairs(GWRP.Turf.Zones or {}) do
            listPoles:AddLine(id, zone.name, zone.radius, zone.owner or "neutral")
        end
    end
    PopulatePoles()
    GWRP.Turf.RefreshSetupMenu = PopulatePoles

    local btnCreate = vgui.Create("DButton", propPanel)
    btnCreate:SetPos(16, 236)
    btnCreate:SetSize(360, 42)
    btnCreate:SetText("Place New Gang Pole at Crosshair")
    btnCreate.DoClick = function()
        local tr = (LocalPlayer().GetEyeTraceNoCursor and LocalPlayer():GetEyeTraceNoCursor()) or LocalPlayer():GetEyeTrace()
        if not tr.Hit or tr.HitSky then
            GWRP.Notify(LocalPlayer(), "Cannot place gang pole: Crosshair is not pointing at a valid surface!", NOTIFY_ERROR)
            return
        end

        local _, ownerVal = comboOwner:GetSelected()
        ownerVal = ownerVal or comboOwner:GetText() or "neutral"
        if ownerVal == "Neutral (Unclaimed)" then ownerVal = "neutral" end
        if ownerVal == "Police / SWAT" then ownerVal = "police" end

        local poleName = txtName:GetText()
        if not poleName or string.Trim(poleName) == "" then
            poleName = "New Territory"
        end

        net.Start("GWRP_AdminTurfAction")
            net.WriteString("add")
            net.WriteString(poleName)
            net.WriteVector(tr.HitPos)
            net.WriteUInt(GWRP.Turf.PreviewRadius or 450, 16)
            net.WriteString(ownerVal)
        net.SendToServer()

        timer.Simple(0.2, function()
            if IsValid(listPoles) then PopulatePoles() end
        end)
    end

    local btnUpdate = vgui.Create("DButton", propPanel)
    btnUpdate:SetPos(16, 284)
    btnUpdate:SetSize(360, 32)
    btnUpdate:SetText("Update Selected Pole (Name, Radius, Owner)")
    btnUpdate.DoClick = function()
        if not GWRP.Turf.SelectedZoneID then
            GWRP.Notify(LocalPlayer(), "Please select a gang pole from the list first!", NOTIFY_ERROR)
            return
        end

        local _, ownerVal = comboOwner:GetSelected()
        ownerVal = ownerVal or comboOwner:GetText() or "neutral"
        if ownerVal == "Neutral (Unclaimed)" then ownerVal = "neutral" end
        if ownerVal == "Police / SWAT" then ownerVal = "police" end

        net.Start("GWRP_AdminTurfAction")
            net.WriteString("edit")
            net.WriteUInt(GWRP.Turf.SelectedZoneID, 8)
            net.WriteString(txtName:GetText())
            net.WriteVector(Vector(0, 0, 0))
            net.WriteUInt(sliderRadius:GetValue(), 16)
            net.WriteString(ownerVal)
        net.SendToServer()

        timer.Simple(0.2, function()
            if IsValid(listPoles) then PopulatePoles() end
        end)
    end

    local btnTeleport = vgui.Create("DButton", propPanel)
    btnTeleport:SetPos(16, 322)
    btnTeleport:SetSize(176, 34)
    btnTeleport:SetText("Teleport to Pole")
    btnTeleport.DoClick = function()
        if not GWRP.Turf.SelectedZoneID then
            GWRP.Notify(LocalPlayer(), "Please select a gang pole from the list first!", NOTIFY_ERROR)
            return
        end
        net.Start("GWRP_AdminTurfAction")
            net.WriteString("teleport")
            net.WriteUInt(GWRP.Turf.SelectedZoneID, 8)
        net.SendToServer()
    end

    local btnDelete = vgui.Create("DButton", propPanel)
    btnDelete:SetPos(200, 322)
    btnDelete:SetSize(176, 34)
    btnDelete:SetText("Delete Selected Pole")
    btnDelete.DoClick = function()
        if not GWRP.Turf.SelectedZoneID then
            GWRP.Notify(LocalPlayer(), "Please select a gang pole from the list first!", NOTIFY_ERROR)
            return
        end
        net.Start("GWRP_AdminTurfAction")
            net.WriteString("remove")
            net.WriteUInt(GWRP.Turf.SelectedZoneID, 8)
        net.SendToServer()

        GWRP.Turf.SelectedZoneID = nil
        timer.Simple(0.2, function()
            if IsValid(listPoles) then PopulatePoles() end
        end)
    end

    listPoles.OnRowSelected = function(s, index, pnl)
        local id = tonumber(pnl:GetColumnText(1))
        GWRP.Turf.SelectedZoneID = id
        local zone = GWRP.Turf.Zones and GWRP.Turf.Zones[id]
        if zone then
            txtName:SetText(zone.name)
            sliderRadius:SetValue(zone.radius)
            if zone.owner == "police" then
                comboOwner:SetValue("Police / SWAT")
            elseif zone.owner == "neutral" or zone.owner == "" then
                comboOwner:SetValue("Neutral (Unclaimed)")
            else
                comboOwner:SetValue("Gang: " .. zone.owner)
            end
        end
    end
end

-- ========================================================
-- TAB 3: GAME LOOP & SPAWNERS DEBUG
-- ========================================================

function GWRP.Turf.RenderSpawnersTab(parent)
    local contW, contH = parent:GetWide(), parent:GetTall()

    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)

    -- Section: Game Cycle Triggers
    local secCycle = scroll:Add("DPanel")
    secCycle:Dock(TOP)
    secCycle:DockMargin(0, 0, 0, 14)
    secCycle:SetTall(90)
    secCycle.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("Economy Cycle Triggers", "GWRP_UI_Header", 16, 12, Color(74, 222, 128))
    end

    local btnPayday = vgui.Create("DButton", secCycle)
    btnPayday:SetPos(16, 42)
    btnPayday:SetSize(220, 36)
    btnPayday:SetText("Trigger Payday Cycle Now")
    btnPayday.DoClick = function()
        net.Start("GWRP_AdminDebugAction")
            net.WriteString("trigger_payday")
        net.SendToServer()
    end

    local btnDivs = vgui.Create("DButton", secCycle)
    btnDivs:SetPos(248, 42)
    btnDivs:SetSize(230, 36)
    btnDivs:SetText("Trigger Turf Dividends Now")
    btnDivs.DoClick = function()
        net.Start("GWRP_AdminDebugAction")
            net.WriteString("trigger_dividends")
        net.SendToServer()
    end

    -- Section: Entity Spawners
    local secSpawn = scroll:Add("DPanel")
    secSpawn:Dock(TOP)
    secSpawn:DockMargin(0, 0, 0, 14)
    secSpawn:SetTall(150)
    secSpawn.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("Test Entity Spawners (Crosshair Placement)", "GWRP_UI_Header", 16, 12, Color(56, 189, 248))
    end

    local spawners = {
        { name = "Money Printer", class = "gwrp_printer_bronze" },
        { name = "Silver Money Printer", class = "gwrp_printer_silver" },
        { name = "Diamond Money Printer", class = "gwrp_printer_diamond" },
        { name = "$10,000 Cash Stack", class = "gwrp_cash_stack" }
    }

    local sx = 16
    for _, sp in ipairs(spawners) do
        local btn = vgui.Create("DButton", secSpawn)
        btn:SetPos(sx, 44)
        btn:SetSize(185, 38)
        btn:SetText(sp.name)
        btn.DoClick = function()
            net.Start("GWRP_AdminDebugAction")
                net.WriteString("spawn_entity")
                net.WriteString(sp.class)
            net.SendToServer()
        end
        sx = sx + 195
    end
end
