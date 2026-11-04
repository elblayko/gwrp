--[[
    cl_f4menu.lua - High-Legibility Scaled UI/UX F4 Dashboard with Full Word Wrap & Truncation Protection
    Author: Toxic & Antigravity
--]]

GW.UI = GW.UI or {}
GW.UI.F4Frame = nil
GW.UI.ActiveF4Tab = "jobs"
GW.UI.ActiveJobCategory = "all"
GW.UI.SearchQuery = ""

-- Text Formatting Helpers: Word Wrap & Boundary Protection
function GW.UI.WrapText(text, font, maxW)
    if not text or text == "" then return {} end
    surface.SetFont(font)
    local words = string.Explode(" ", text)
    local lines = {}
    local curLine = ""
    for _, w in ipairs(words) do
        local test = (curLine == "") and w or (curLine .. " " .. w)
        local tw = surface.GetTextSize(test)
        if tw > maxW and curLine ~= "" then
            table.insert(lines, curLine)
            curLine = w
        else
            curLine = test
        end
    end
    if curLine ~= "" then
        table.insert(lines, curLine)
    end
    return lines
end

function GW.UI.FitText(text, font, maxW)
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

function GW.UI.ToggleF4Menu()
    if IsValid(GW.UI.F4Frame) then
        GW.UI.F4Frame:Close()
        GW.UI.F4Frame = nil
        return
    end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- Ensure fonts are always initialized and scaled
    if GW.UI.CreateFonts then
        GW.UI.CreateFonts()
    end

    local scrW, scrH = ScrW(), ScrH()
    local frameW = math.Clamp(scrW * 0.82, 1100, 1650)
    local frameH = math.Clamp(scrH * 0.84, 750, 1050)

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(true)
    frame:MakePopup()
    frame.OnClose = function()
        GW.UI.F4Frame = nil
    end
    GW.UI.F4Frame = frame

    -- Main Container Paint (Glassmorphic Obsidian Palette)
    frame.Paint = function(s, w, h)
        -- Deep obsidian background
        draw.RoundedBox(10, 0, 0, w, h, Color(11, 15, 25, 252))

        -- Top Navigation Header Bar (Height: 70px)
        draw.RoundedBoxEx(10, 0, 0, w, 70, Color(17, 24, 39, 255), true, true, false, false)
        surface.SetDrawColor(30, 41, 59, 255)
        surface.DrawLine(0, 70, w, 70)

        -- Outer border
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- Title & Brand Tag (Large, Clean Font)
        draw.SimpleText("GangWars RP", "GW_UI_Title", 24, 20, Color(248, 250, 252), TEXT_ALIGN_LEFT)
        draw.RoundedBox(4, 240, 24, 114, 24, Color(6, 182, 212, 35))
        surface.SetDrawColor(6, 182, 212, 120)
        surface.DrawOutlinedRect(240, 24, 114, 24, 1)
        draw.SimpleText("v2.0 Standalone", "GW_UI_Badge", 297, 36, Color(34, 211, 238), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Player Wallet & Gang Pill (Center Header)
        local curMoney = IsValid(ply) and ply:GetMoney() or 0
        local curGang = IsValid(ply) and ply:GetGang() or ""
        local curJob = IsValid(ply) and ply:GetJobData() or {}
        local gangCol = (curGang ~= "") and GW.GetGangColor(curGang) or (curJob.faction and curJob.faction.color or GW.Colors.White)

        local pillText = "$" .. string.Comma(curMoney) .. "   |   " .. (curJob.name or "Citizen")
        if curGang ~= "" then
            pillText = pillText .. "   |   " .. curGang
        end

        local pillX = w / 2
        draw.RoundedBox(18, pillX - 190, 14, 380, 42, Color(24, 32, 47, 240))
        surface.SetDrawColor(gangCol.r, gangCol.g, gangCol.b, 100)
        surface.DrawOutlinedRect(pillX - 190, 14, 380, 42, 1)
        draw.SimpleText(pillText, "GW_UI_Header", pillX, 35, Color(74, 222, 128), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Close Button (Top-Right X)
    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(44, 44)
    btnClose:SetPos(frameW - 56, 13)
    btnClose:SetText("")
    btnClose.Paint = function(s, w, h)
        local bgCol = s:IsHovered() and Color(239, 68, 68, 220) or Color(30, 41, 59, 160)
        draw.RoundedBox(6, 0, 0, w, h, bgCol)
        draw.SimpleText("X", "GW_UI_Title", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnClose.DoClick = function()
        frame:Close()
    end

    -- Admin HUD Shortcut Button
    if ply:IsAdmin() or ply:IsSuperAdmin() then
        local btnAdmin = vgui.Create("DButton", frame)
        btnAdmin:SetSize(140, 38)
        btnAdmin:SetPos(frameW - 206, 16)
        btnAdmin:SetText("")
        btnAdmin.Paint = function(s, w, h)
            local bg = s:IsHovered() and Color(6, 182, 212, 240) or Color(14, 116, 144, 200)
            draw.RoundedBox(6, 0, 0, w, h, bg)
            draw.SimpleText("Admin HUD", "GW_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        btnAdmin.DoClick = function()
            frame:Close()
            if GW.Turf and GW.Turf.OpenSetupMenu then
                GW.Turf.OpenSetupMenu()
            end
        end
    end

    -- ==========================================
    -- LEFT VERTICAL SIDEBAR NAVIGATION
    -- ==========================================
    local sidebar = vgui.Create("DPanel", frame)
    sidebar:SetPos(14, 82)
    sidebar:SetSize(264, frameH - 96)
    sidebar.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- Bottom Info Card
        draw.RoundedBox(6, 12, h - 80, w - 24, 68, Color(11, 15, 25, 220))
        draw.SimpleText("Map: " .. game.GetMap(), "GW_UI_Caption", 22, h - 60, Color(148, 163, 184))
        draw.SimpleText("Online: " .. #player.GetAll() .. " players", "GW_UI_Caption", 22, h - 34, Color(74, 222, 128))
    end

    local invItems = GW.Inventory and GW.Inventory.ClientItems or {}
    local invBadge = #invItems > 0 and tostring(#invItems) or "0"

    local tabs = {
        { id = "jobs", title = "Careers & Jobs", badge = table.Count(GW.Jobs or {}) },
        { id = "inventory", title = "Inventory", badge = invBadge },
        { id = "weapons", title = "Ammo & Gear", badge = "Ammo" },
        { id = "shipments", title = "Shipments", badge = "10x Bulk" },
        { id = "entities", title = "Printers & Tech", badge = "Tech" },
        { id = "supplies", title = "Supplies & Items", badge = "Aid" },
        { id = "networking", title = "Networking", badge = "Cyber" },
        { id = "debug_buffs", title = "Debug Buffs", badge = "Debug" },
        { id = "rules", title = "Server Rules", badge = "Rules" }
    }

    -- Content Body Container
    local contentPanel = vgui.Create("DPanel", frame)
    contentPanel:SetPos(292, 82)
    contentPanel:SetSize(frameW - 306, frameH - 96)
    contentPanel.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 140))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    GW.UI.CurrentContentPanel = contentPanel

    local function SwitchTab(tabId)
        GW.UI.ActiveF4Tab = tabId
        contentPanel:Clear()
        GW.UI.RenderContentTab(contentPanel, tabId, frame)
    end

    local maxNavH = (frameH - 96) - 96
    local totalTabs = #tabs
    local btnH = math.Clamp(math.floor((maxNavH - 12) / totalTabs) - 4, 38, 48)
    local btnGap = btnH + 5
    local navY = 12

    for _, tab in ipairs(tabs) do
        local btnTab = vgui.Create("DButton", sidebar)
        btnTab:SetPos(12, navY)
        btnTab:SetSize(240, btnH)
        btnTab:SetText("")

        btnTab.Paint = function(s, w, h)
            local isActive = (GW.UI.ActiveF4Tab == tab.id)
            local isHovered = s:IsHovered()

            local bgCol = isActive and Color(30, 41, 59, 255) or (isHovered and Color(24, 32, 47, 180) or Color(0, 0, 0, 0))
            draw.RoundedBox(6, 0, 0, w, h, bgCol)

            if isActive then
                -- Vertical Cyan Accent Indicator
                draw.RoundedBox(2, 0, 6, 4, h - 12, Color(6, 182, 212))
            end

            -- Clean Title in Large Readable Sub Font
            local textCol = isActive and Color(248, 250, 252) or (isHovered and Color(226, 232, 240) or Color(148, 163, 184))
            draw.SimpleText(tab.title, "GW_UI_Sub", 18, h / 2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Badge Tag
            if tab.badge then
                local badgeText = tostring(tab.badge)
                draw.RoundedBox(4, w - 66, (h - 24) / 2, 56, 24, Color(11, 15, 25, 200))
                draw.SimpleText(badgeText, "GW_UI_Badge", w - 38, h / 2, Color(148, 163, 184), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        btnTab.DoClick = function()
            SwitchTab(tab.id)
        end

        navY = navY + btnGap
    end

    -- Initial tab load
    SwitchTab(GW.UI.ActiveF4Tab or "jobs")
end

function GW.UI.RefreshInventoryTab()
    if not IsValid(GW.UI.F4Frame) or GW.UI.ActiveF4Tab ~= "inventory" then return end
    if IsValid(GW.UI.CurrentContentPanel) then
        GW.UI.CurrentContentPanel:Clear()
        GW.UI.RenderContentTab(GW.UI.CurrentContentPanel, "inventory", GW.UI.F4Frame)
    end
end

-- ==========================================
-- TAB CONTENT RENDERER
-- ==========================================

function GW.UI.RenderContentTab(container, tabId, mainFrame)
    local ply = LocalPlayer()
    local contW, contH = container:GetWide(), container:GetTall()

    -- Search Bar & Category Header (Height: 52px)
    local topBar = vgui.Create("DPanel", container)
    topBar:SetPos(16, 12)
    topBar:SetSize(contW - 32, 50)
    topBar.Paint = function(s, w, h)
        local titles = {
            jobs = "Available Careers & Roles",
            inventory = "Personal Inventory & Stored Assets",
            weapons = "Tactical Ammunition & Utility Gear",
            shipments = "Arms Dealer Wholesale Shipments (10x Crates)",
            entities = "Money Printers & Industrial Resource Extractors",
            supplies = "Medical Supplies & Tactical Consumables",
            networking = "Network Infrastructure & Cyber Equipment",
            debug_buffs = "Debug Status Effects & Tests",
            buffs = "Debug Status Effects & Tests",
            rules = "City Ordinances & Server Code of Conduct"
        }
        draw.SimpleText(titles[tabId] or "Catalog", "GW_UI_Header", 0, h / 2, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    if tabId ~= "rules" then
        if tabId == "inventory" then
            local btnBag = vgui.Create("DButton", topBar)
            btnBag:SetSize(180, 42)
            btnBag:SetPos(topBar:GetWide() - 474, 4)
            btnBag:SetText("")
            btnBag.Paint = function(s, w, h)
                local bg = s:IsHovered() and Color(180, 140, 60, 240) or Color(140, 105, 45, 200)
                draw.RoundedBox(6, 0, 0, w, h, bg)
                surface.SetDrawColor(245, 215, 130, 200)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText("Open Bag (B)", "GW_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            btnBag.DoClick = function()
                mainFrame:Close()
                if GW.UI.ToggleBag then
                    GW.UI.ToggleBag()
                end
            end
        end

        local txtSearch = vgui.Create("DTextEntry", topBar)
        txtSearch:SetSize(280, 42)
        txtSearch:SetPos(topBar:GetWide() - 280, 4)
        txtSearch:SetPlaceholderText(tabId == "inventory" and "Search inventory..." or (tabId == "jobs" and "Search roles..." or "Search catalog..."))
        txtSearch:SetFont("GW_UI_Sub")
        txtSearch.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 220))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            s:DrawTextEntryText(Color(248, 250, 252), Color(6, 182, 212), Color(248, 250, 252))
        end
        txtSearch.OnChange = function(s)
            GW.UI.SearchQuery = string.lower(string.Trim(s:GetText()))
            local targetScroll = container:GetChildren()[2]
            if IsValid(targetScroll) then
                targetScroll:Clear()
                if tabId == "inventory" then
                    GW.UI.PopulateInventoryGrid(targetScroll, mainFrame, GW.UI.SearchQuery)
                else
                    GW.UI.PopulateGrid(targetScroll, tabId, mainFrame, GW.UI.SearchQuery)
                end
            end
        end
    end

    -- Scroll Area
    local scroll = vgui.Create("DScrollPanel", container)
    scroll:SetPos(16, 72)
    scroll:SetSize(contW - 32, contH - 86)

    -- Custom modern scrollbar
    local sbar = scroll:GetVBar()
    sbar:SetWide(8)
    sbar.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(11, 15, 25, 120)) end
    sbar.btnGrip.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(56, 189, 248, 140)) end
    sbar.btnUp.Paint = function() end
    sbar.btnDown.Paint = function() end

    if tabId == "rules" then
        GW.UI.RenderRulesContent(scroll)
    elseif tabId == "inventory" then
        GW.UI.PopulateInventoryGrid(scroll, mainFrame, "")
    else
        GW.UI.PopulateGrid(scroll, tabId, mainFrame, "")
    end
end

-- ==========================================
-- INVENTORY GRID POPULATION
-- ==========================================

function GW.UI.PopulateInventoryGrid(scroll, mainFrame, searchFilter)
    local ply = LocalPlayer()
    local steamID = ply:SteamID()

    local rows = GW.Inventory and GW.Inventory.ClientItems or {}
    local filteredRows = {}

    for _, r in ipairs(rows) do
        local def = GW.Inventory.GetItemData(r.item_id)
        local name = def and def.name or r.item_id
        if searchFilter == "" or string.find(string.lower(name), searchFilter, 1, true) then
            table.insert(filteredRows, r)
        end
    end

    if #filteredRows == 0 then
        local emptyCard = scroll:Add("DPanel")
        emptyCard:Dock(TOP)
        emptyCard:SetTall(160)
        emptyCard.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 140))
            draw.SimpleText("No stored items found.", "GW_UI_Header", w / 2, h / 2 - 12, Color(148, 163, 184), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("Open your 16-slot Backpack with [B] or interact with items using hands (+USE).", "GW_UI_Caption", w / 2, h / 2 + 16, Color(100, 116, 139), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    local layout = vgui.Create("DIconLayout", scroll)
    layout:Dock(FILL)
    layout:SetSpaceX(14)
    layout:SetSpaceY(14)

    local cardW = (scroll:GetWide() - 28) / 2
    local cardH = 154

    for _, r in ipairs(filteredRows) do
        local rowId = tonumber(r.id) or 0
        local itemId = r.item_id
        local itemType = r.item_type
        local amount = tonumber(r.amount) or 1
        local def = GW.Inventory.GetItemData(itemId)
        local quality = def.quality or 1
        local qCol = GW.Inventory.QualityColors and GW.Inventory.QualityColors[quality] or Color(148, 163, 184)
        local qName = GW.Inventory.QualityNames and GW.Inventory.QualityNames[quality] or "Standard"

        local card = layout:Add("DPanel")
        card:SetSize(cardW, cardH)

        card.Paint = function(s, w, h)
            local isHover = s:IsHovered()
            draw.RoundedBox(8, 0, 0, w, h, isHover and Color(24, 32, 47, 240) or Color(17, 24, 39, 200))
            draw.RoundedBoxEx(8, 0, 0, 4, h, qCol, true, false, true, false)
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            -- Item Name
            local contentX = 140
            local contentW = w - contentX - 16
            local fitName = GW.UI.FitText(def.name, "GW_UI_Header", contentW - 80)
            draw.SimpleText(fitName, "GW_UI_Header", contentX, 16, Color(248, 250, 252))

            -- Quality Pill
            surface.SetFont("GW_UI_Badge")
            local qTextW = surface.GetTextSize(qName) + 16
            draw.RoundedBox(4, w - qTextW - 16, 16, qTextW, 22, Color(qCol.r, qCol.g, qCol.b, 35))
            draw.SimpleText(qName, "GW_UI_Badge", w - 16 - qTextW / 2, 27, qCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            -- Amount / SubType
            local subInfo = string.format("Quantity: %dx  •  %s", amount, def.subType or "Asset")
            draw.SimpleText(subInfo, "GW_UI_Sub", contentX, 48, Color(74, 222, 128))

            -- Stats / Description
            local metaStr = def.stats or def.desc or ""
            local lines = GW.UI.WrapText(metaStr, "GW_UI_Caption", contentW)
            for i = 1, math.min(#lines, 2) do
                draw.SimpleText(lines[i], "GW_UI_Caption", contentX, 76 + (i - 1) * 18, Color(148, 163, 184))
            end
        end

        -- 3D Model Preview
        local mdl = vgui.Create("DModelPanel", card)
        mdl:SetPos(12, 12)
        mdl:SetSize(116, cardH - 24)
        mdl:SetModel(def.model or "models/props_junk/cardboard_box004a.mdl")
        mdl.PaintOver = function(s, w, h)
            surface.SetDrawColor(30, 41, 59, 120)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        if IsValid(mdl.Entity) then
            local mn, mx = mdl.Entity:GetRenderBounds()
            local size = 0
            size = math.max(size, math.abs(mn.x) + math.abs(mx.x))
            size = math.max(size, math.abs(mn.y) + math.abs(mx.y))
            size = math.max(size, math.abs(mn.z) + math.abs(mx.z))
            mdl:SetFOV(45)
            mdl:SetCamPos(Vector(size * 1.3, size * 1.3, size * 0.8))
            mdl:SetLookAt((mn + mx) * 0.5)
            function mdl:LayoutEntity(ent)
                ent:SetAngles(Angle(0, RealTime() * 30 % 360, 0))
            end
        end

        -- Action Buttons (Bottom-Right / Content Area)
        local btnY = cardH - 48

        local btnDrop = vgui.Create("DButton", card)
        btnDrop:SetSize(110, 36)
        btnDrop:SetPos(cardW - 124, btnY)
        btnDrop:SetText("")
        btnDrop.Paint = function(s, w, h)
            local bg = s:IsHovered() and Color(239, 68, 68, 240) or Color(185, 28, 28, 190)
            draw.RoundedBox(6, 0, 0, w, h, bg)
            draw.SimpleText("Drop", "GW_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        btnDrop.DoClick = function()
            GW.Inventory.DropItem(rowId)
        end

        -- If item is a weapon, show Equip button
        if itemType == "weapon" then
            local btnEquip = vgui.Create("DButton", card)
            btnEquip:SetSize(110, 36)
            btnEquip:SetPos(cardW - 242, btnY)
            btnEquip:SetText("")
            btnEquip.Paint = function(s, w, h)
                local bg = s:IsHovered() and Color(16, 185, 129, 240) or Color(5, 150, 105, 190)
                draw.RoundedBox(6, 0, 0, w, h, bg)
                draw.SimpleText("Equip", "GW_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            btnEquip.DoClick = function()
                GW.Inventory.UseItem(rowId)
            end
        end
    end
end

-- ==========================================
-- GRID POPULATION (JOBS & STORE CATALOG)
-- ==========================================

function GW.UI.PopulateGrid(scroll, tabId, mainFrame, searchFilter)
    local ply = LocalPlayer()

    -- ========================================================
    -- 1. TAB: JOBS (3-CATEGORY ORGANIZATION)
    -- ========================================================
    if tabId == "jobs" then
        local myJob = IsValid(ply) and ply:GetJob() or "citizen"
        local myLvl = IsValid(ply) and ply:GetLevel() or 1
        searchFilter = searchFilter or ""

        local categories = {
            {
                id = "neutral",
                name = "Civilians",
                title = "CIVILIANS & TRADE SERVICES",
                desc = "Standard urban civilians, licensed merchants, clinical physicians, and vagrants",
                color = Color(148, 163, 184)
            },
            {
                id = "gang",
                name = "Street Gangs",
                title = "STREET GANGS & UNDERWORLD",
                desc = "Syndicate soldiers, infiltrators, contract hitmen, and black market smugglers",
                color = Color(245, 158, 11)
            },
            {
                id = "police",
                name = "Police",
                title = "LAW ENFORCEMENT & GOVERNMENT",
                desc = "Civil Protection officers, tactical SWAT units, and municipal administration",
                color = Color(16, 185, 129)
            }
        }

        -- Count total roles per category
        local catCounts = { neutral = 0, gang = 0, police = 0 }
        for _, job in pairs(GW.Jobs or {}) do
            local fId = (job.faction and job.faction.id) or "neutral"
            if catCounts[fId] ~= nil then
                catCounts[fId] = catCounts[fId] + 1
            end
        end

        -- Top Category Filter Buttons Bar
        local filterBar = scroll:Add("DPanel")
        filterBar:Dock(TOP)
        filterBar:DockMargin(0, 0, 0, 16)
        filterBar:SetTall(46)
        filterBar.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 220))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        local filterButtons = {
            { id = "all", label = "All Roles (" .. table.Count(GW.Jobs or {}) .. ")", color = Color(6, 182, 212) },
            { id = "neutral", label = "Civilians (" .. catCounts.neutral .. ")", color = Color(148, 163, 184) },
            { id = "gang", label = "Street Gangs (" .. catCounts.gang .. ")", color = Color(245, 158, 11) },
            { id = "police", label = "Police (" .. catCounts.police .. ")", color = Color(16, 185, 129) }
        }

        local btnX = 8
        for _, fBtn in ipairs(filterButtons) do
            surface.SetFont("GW_UI_Btn")
            local tw = surface.GetTextSize(fBtn.label) + 28
            local b = vgui.Create("DButton", filterBar)
            b:SetPos(btnX, 6)
            b:SetSize(tw, 34)
            b:SetText("")

            b.Paint = function(s, bw, bh)
                local isCur = (GW.UI.ActiveJobCategory == fBtn.id)
                local bg = isCur and Color(fBtn.color.r, fBtn.color.g, fBtn.color.b, 45) or (s:IsHovered() and Color(30, 41, 59, 200) or Color(11, 15, 25, 140))
                draw.RoundedBox(6, 0, 0, bw, bh, bg)

                surface.SetDrawColor(isCur and fBtn.color.r or 51, isCur and fBtn.color.g or 65, isCur and fBtn.color.b or 85, isCur and 220 or 120)
                surface.DrawOutlinedRect(0, 0, bw, bh, 1)

                local textCol = isCur and fBtn.color or (s:IsHovered() and Color(248, 250, 252) or Color(148, 163, 184))
                draw.SimpleText(fBtn.label, "GW_UI_Btn", bw / 2, bh / 2, textCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            b.DoClick = function()
                GW.UI.ActiveJobCategory = fBtn.id
                scroll:Clear()
                GW.UI.PopulateGrid(scroll, "jobs", mainFrame, searchFilter)
            end

            btnX = btnX + tw + 8
        end

        local cardW = (scroll:GetWide() - 28) / 2

        -- Render Each Category Section
        for _, cat in ipairs(categories) do
            if GW.UI.ActiveJobCategory == "all" or GW.UI.ActiveJobCategory == cat.id then
                local catJobs = {}
                local catActivePlayers = 0

                for jobId, job in pairs(GW.Jobs or {}) do
                    local fId = (job.faction and job.faction.id) or "neutral"
                    if fId == cat.id then
                        if searchFilter == "" or string.find(string.lower(job.name), searchFilter, 1, true) then
                            table.insert(catJobs, { id = jobId, data = job })
                        end

                        for _, p in ipairs(player.GetAll()) do
                            if p:GetJob() == jobId then
                                catActivePlayers = catActivePlayers + 1
                            end
                        end
                    end
                end

                if #catJobs > 0 then
                    table.sort(catJobs, function(a, b)
                        return (a.data.level or 1) < (b.data.level or 1)
                    end)

                    -- Section Banner
                    local banner = scroll:Add("DPanel")
                    banner:Dock(TOP)
                    banner:DockMargin(0, 0, 0, 10)
                    banner:SetTall(48)
                    banner.Paint = function(s, w, h)
                        draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 240))
                        draw.RoundedBoxEx(8, 0, 0, 4, h, cat.color, true, false, true, false)
                        surface.SetDrawColor(30, 41, 59, 180)
                        surface.DrawOutlinedRect(0, 0, w, h, 1)

                        -- Title & Subtitle
                        draw.SimpleText(cat.title, "GW_UI_Sub", 18, 14, cat.color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        draw.SimpleText(cat.desc, "GW_UI_Caption", 18, 33, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                        -- Right Player Activity Capsule
                        local actText = #catJobs .. " Roles  •  " .. catActivePlayers .. " Active Players"
                        surface.SetFont("GW_UI_Badge")
                        local tw = surface.GetTextSize(actText) + 20
                        draw.RoundedBox(4, w - tw - 16, 12, tw, 24, Color(cat.color.r, cat.color.g, cat.color.b, 35))
                        surface.SetDrawColor(cat.color.r, cat.color.g, cat.color.b, 120)
                        surface.DrawOutlinedRect(w - tw - 16, 12, tw, 24, 1)
                        draw.SimpleText(actText, "GW_UI_Badge", w - 16 - tw / 2, 24, cat.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end

                    -- Grid Layout for Category
                    local catLayout = scroll:Add("DIconLayout")
                    catLayout:Dock(TOP)
                    catLayout:DockMargin(0, 0, 0, 18)
                    catLayout:SetSpaceX(14)
                    catLayout:SetSpaceY(14)

                    for _, item in ipairs(catJobs) do
                        local jobId = item.id
                        local job = item.data

                        local card = catLayout:Add("DPanel")
                        card:SetSize(cardW, 220)

                        local fCol = (job.faction and job.faction.color) or GW.Colors.White
                        local isMyJob = (myJob == jobId)
                        local maxTextW = cardW - 146
                        local reqJobLvl = job.level or 1
                        local hasJobLvl = (myLvl >= reqJobLvl)

                        local currentCount = 0
                        for _, p in ipairs(player.GetAll()) do
                            if p:GetJob() == jobId then currentCount = currentCount + 1 end
                        end

                        local slotText = ""
                        local slotCol = Color(148, 163, 184)
                        local isFull = false
                        local maxSlots = job.max or 0

                        if maxSlots > 0 then
                            local available = math.max(0, maxSlots - currentCount)
                            isFull = (available <= 0)
                            if isFull then
                                slotText = "0 / " .. maxSlots .. " Available (Full)"
                                slotCol = Color(239, 68, 68)
                            elseif available == 1 then
                                slotText = "1 / " .. maxSlots .. " Slot Available"
                                slotCol = Color(245, 158, 11)
                            else
                                slotText = available .. " / " .. maxSlots .. " Slots Available"
                                slotCol = Color(52, 211, 153)
                            end
                        else
                            slotText = "Unlimited (" .. currentCount .. " Active)"
                            slotCol = Color(148, 163, 184)
                        end

                        card.Paint = function(s, w, h)
                            local isHover = s:IsHovered()
                            draw.RoundedBox(8, 0, 0, w, h, isHover and Color(24, 32, 47, 240) or Color(17, 24, 39, 200))
                            draw.RoundedBoxEx(8, 0, 0, w, 4, fCol, true, true, false, false)
                            surface.SetDrawColor(30, 41, 59, 180)
                            surface.DrawOutlinedRect(0, 0, w, h, 1)

                            -- Row 1 Left: Faction Pill
                            local fName = job.faction and job.faction.name or "Civilian"
                            surface.SetFont("GW_UI_Badge")
                            local badgeW = surface.GetTextSize(fName) + 20
                            draw.RoundedBox(4, 138, 14, badgeW, 22, Color(fCol.r, fCol.g, fCol.b, 35))
                            draw.SimpleText(fName, "GW_UI_Badge", 138 + badgeW / 2, 25, fCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

                            -- Row 1 Right: Slot Availability Pill
                            surface.SetFont("GW_UI_Badge")
                            local slotW = surface.GetTextSize(slotText) + 18
                            local slotX = cardW - 16 - slotW
                            draw.RoundedBox(4, slotX, 14, slotW, 22, Color(slotCol.r, slotCol.g, slotCol.b, 35))
                            surface.SetDrawColor(slotCol.r, slotCol.g, slotCol.b, 90)
                            surface.DrawOutlinedRect(slotX, 14, slotW, 22, 1)
                            draw.SimpleText(slotText, "GW_UI_Badge", slotX + slotW / 2, 25, slotCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

                            -- Row 2: Job Name
                            local cleanJobName = GW.UI.FitText(job.name, "GW_UI_Header", maxTextW)
                            draw.SimpleText(cleanJobName, "GW_UI_Header", 138, 42, Color(248, 250, 252))

                            -- Row 3: Stats Line
                            local statsText = "Salary: +$" .. (job.salary or 45) .. " / 90s"
                            if (job.armor or 0) > 0 then
                                statsText = statsText .. "   |   Armor: " .. job.armor .. "%"
                            end
                            if job.runSpeed then
                                statsText = statsText .. "   |   Sprint: " .. job.runSpeed
                            end
                            draw.SimpleText(statsText, "GW_UI_Sub", 138, 72, Color(74, 222, 128))

                            -- Row 4: Description
                            local descLines = GW.UI.WrapText(job.desc or "", "GW_UI_Caption", maxTextW)
                            for i = 1, math.min(#descLines, 3) do
                                draw.SimpleText(descLines[i], "GW_UI_Caption", 138, 98 + (i - 1) * 20, Color(148, 163, 184))
                            end
                        end

                        -- 3D Model Preview
                        local mdlPanel = vgui.Create("DModelPanel", card)
                        mdlPanel:SetPos(12, 12)
                        mdlPanel:SetSize(116, 196)
                        local previewModel = job.models and job.models[1] or "models/player/Group01/male_01.mdl"
                        mdlPanel:SetModel(previewModel)
                        mdlPanel:SetFOV(34)
                        mdlPanel:SetCamPos(Vector(46, 0, 48))
                        mdlPanel:SetLookAt(Vector(0, 0, 40))
                        mdlPanel.LayoutEntity = function(s, ent)
                            ent:SetAngles(Angle(0, 40 + RealTime() * 12, 0))
                        end

                        -- Enlist Button
                        local btnEnlist = vgui.Create("DButton", card)
                        btnEnlist:SetSize(maxTextW, 42)
                        btnEnlist:SetPos(138, 164)
                        btnEnlist:SetText("")
                        btnEnlist:SetEnabled((not isFull and hasJobLvl) or isMyJob)

                        btnEnlist.Paint = function(s, w, h)
                            local btnCol = isMyJob and Color(30, 41, 59, 200) or (not hasJobLvl and Color(51, 65, 85, 180) or (isFull and Color(51, 65, 85, 180) or (s:IsHovered() and Color(6, 182, 212, 240) or Color(14, 116, 144, 200))))
                            draw.RoundedBox(6, 0, 0, w, h, btnCol)
                            local rawText = isMyJob and "Current Active Role" or (not hasJobLvl and ("Requires Level " .. reqJobLvl) or (isFull and ("Role Full (" .. currentCount .. "/" .. maxSlots .. ")") or ("Enlist as " .. job.name)))
                            local fitBtnText = GW.UI.FitText(rawText, "GW_UI_Btn", w - 20)
                            draw.SimpleText(fitBtnText, "GW_UI_Btn", w / 2, h / 2, (not hasJobLvl or (isFull and not isMyJob)) and Color(156, 163, 175) or Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                        end

                        btnEnlist.DoClick = function()
                            if isMyJob then return end
                            if not hasJobLvl then
                                GW.Notify(ply, string.format("You must be Level %d to become a %s!", reqJobLvl, job.name), NOTIFY_ERROR)
                                surface.PlaySound("buttons/button10.wav")
                                return
                            end
                            if isFull then
                                GW.Notify(ply, "That role is currently at capacity!", NOTIFY_ERROR)
                                surface.PlaySound("buttons/button10.wav")
                                return
                            end

                            net.Start("GW_ChangeJob")
                                net.WriteString(jobId)
                            net.SendToServer()
                            surface.PlaySound("buttons/button14.wav")
                            mainFrame:Close()
                        end
                    end
                end
            end
        end

    -- ========================================================
    -- 2. STORE TABS (DYNAMIC WHOLESALE/MARKUP PRICING & CHECKMARKED PREREQUISITES)
    -- ========================================================
    else
        local myMoney = IsValid(ply) and ply:GetMoney() or 0
        local myLevel = IsValid(ply) and ply:GetLevel() or 1
        local plyJob = IsValid(ply) and ply:GetJob() or "citizen"
        local isHobo = (plyJob == "hobo")
        local isPolice = IsValid(ply) and ply.IsPolice and ply:IsPolice()

        local layout = vgui.Create("DIconLayout", scroll)
        layout:Dock(FILL)
        layout:SetSpaceX(14)
        layout:SetSpaceY(14)

        local itemsList = {}
        for itemId, item in pairs(GW.ShopItems or {}) do
            -- Filter by tab type
            if tabId == "weapons" and (item.category == "networking" or item.category == "supplies" or (item.type ~= "weapon" and item.type ~= "ammo")) then continue end
            if tabId == "shipments" and item.type ~= "shipment" then continue end
            if tabId == "entities" and (item.category ~= "printers" or item.debug or string.StartWith(itemId, "debug_")) then continue end
            if tabId == "supplies" and (item.category ~= "supplies" and item.type ~= "armor" and item.type ~= "medkit" and item.type ~= "consumable") then continue end
            if tabId == "networking" and item.category ~= "networking" then continue end
            if (tabId == "debug_buffs" or tabId == "buffs") and not (item.debug or string.StartWith(itemId, "debug_") or item.type == "buff" or item.type == "cleanse") then continue end

            -- Filter by search query
            if searchFilter ~= "" and not string.find(string.lower(item.name), searchFilter, 1, true) then
                continue
            end

            -- Determine effective purchase cost via dynamic wholesale/retail pricing engine
            local effectiveCost = GW.GetItemCost(item, ply)
            local reqItemLevel = item.level or 1
            local canBuyLevel = (myLevel >= reqItemLevel)
            local canAfford = (myMoney >= effectiveCost)

            -- Job Requirement Validation
            local hasJobReq = (item.jobs ~= nil) or (item.job ~= nil)
            local canBuyJob = true
            local reqJobName = ""
            if item.jobs then
                canBuyJob = table.HasValue(item.jobs, plyJob)
                local names = {}
                for _, jId in ipairs(item.jobs) do
                    local jData = GW.Jobs[jId]
                    if jData then table.insert(names, jData.name) end
                end
                reqJobName = table.concat(names, " / ")
            elseif item.job then
                canBuyJob = (plyJob == item.job)
                local jData = GW.Jobs[item.job]
                reqJobName = jData and jData.name or item.job
            end

            -- Police & Hobo Restrictions
            local isPoliceProhibited = isPolice and (item.category == "printers" or item.isContraband or item.type == "shipment" or (item.jobs and table.HasValue(item.jobs, "black_market_dealer")) or (item.jobs and table.HasValue(item.jobs, "thief")))
            local isHoboProhibited = isHobo

            local isLocked = (not canBuyJob) or (not canBuyLevel) or isPoliceProhibited or isHoboProhibited

            -- Sorting Priority
            local rank = 1
            if not isLocked and canAfford then
                rank = 1
            elseif not isLocked and not canAfford then
                rank = 2
            elseif not canBuyLevel and canBuyJob then
                rank = 3
            elseif canBuyLevel and not canBuyJob then
                rank = 4
            else
                rank = 5
            end

            table.insert(itemsList, {
                id = itemId,
                item = item,
                rank = rank,
                effectiveCost = effectiveCost,
                canBuyLevel = canBuyLevel,
                canBuyJob = canBuyJob,
                canAfford = canAfford,
                hasJobReq = hasJobReq,
                reqItemLevel = reqItemLevel,
                reqJobName = reqJobName,
                isPoliceProhibited = isPoliceProhibited,
                isHoboProhibited = isHoboProhibited,
                isLocked = isLocked
            })
        end

        table.sort(itemsList, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            if a.rank == 3 or a.rank == 5 then
                if a.reqItemLevel ~= b.reqItemLevel then return a.reqItemLevel < b.reqItemLevel end
            end
            if a.rank == 4 then
                if a.reqJobName ~= b.reqJobName then return a.reqJobName < b.reqJobName end
            end
            if a.effectiveCost ~= b.effectiveCost then return a.effectiveCost < b.effectiveCost end
            return (a.item.name or "") < (b.item.name or "")
        end)

        for _, entry in ipairs(itemsList) do
            local itemId = entry.id
            local item = entry.item
            local effectiveCost = entry.effectiveCost
            local canBuyLevel = entry.canBuyLevel
            local canBuyJob = entry.canBuyJob
            local canAfford = entry.canAfford
            local hasJobReq = entry.hasJobReq
            local reqItemLevel = entry.reqItemLevel
            local reqJobName = entry.reqJobName
            local isPoliceProhibited = entry.isPoliceProhibited
            local isHoboProhibited = entry.isHoboProhibited
            local isLocked = entry.isLocked

            local cardW = (scroll:GetWide() - 28) / 2
            local card = layout:Add("DPanel")
            card:SetSize(cardW, 154)

            local leftContentW = cardW - 224

            card.Paint = function(s, w, h)
                local isHover = s:IsHovered()
                local cardBg = isLocked and Color(14, 18, 27, 210) or (isHover and Color(24, 32, 47, 240) or Color(17, 24, 39, 200))
                draw.RoundedBox(8, 0, 0, w, h, cardBg)
                surface.SetDrawColor(isLocked and Color(51, 65, 85, 140) or Color(30, 41, 59, 180))
                surface.DrawOutlinedRect(0, 0, w, h, 1)

                -- Item Type Pill
                local isItemDebuff = (item.isDebuff or (item.buffId and GW.Buffs and GW.Buffs.Registry and GW.Buffs.Registry[item.buffId] and GW.Buffs.Registry[item.buffId].isDebuff) or string.find(string.lower(item.name), "debuff", 1, true))
                local typePillLabels = {
                    weapon = "Weapon",
                    ammo = "Ammo",
                    shipment = "Shipment",
                    entity = "Printer",
                    armor = "Kevlar",
                    medkit = "Medical",
                    buff = "Buff",
                    debuff = "Debuff",
                    consumable = "Bag Item",
                    cleanse = "Cleanse"
                }
                local typePillColors = {
                    weapon = Color(56, 189, 248),
                    ammo = Color(245, 158, 11),
                    shipment = Color(168, 85, 247),
                    entity = Color(239, 68, 68),
                    armor = Color(16, 185, 129),
                    medkit = Color(244, 63, 94),
                    buff = Color(250, 204, 21),
                    debuff = Color(239, 68, 68),
                    consumable = Color(74, 222, 128),
                    cleanse = Color(148, 163, 184)
                }
                local itemTypeKey = (item.type == "buff" and isItemDebuff) and "debuff" or item.type
                local pLabel = typePillLabels[itemTypeKey] or "Item"
                local pCol = typePillColors[itemTypeKey] or Color(148, 163, 184)
                if item.category == "networking" then
                    pLabel = "Network"
                    pCol = Color(6, 182, 212)
                end

                draw.RoundedBox(4, 16, 14, 80, 26, Color(pCol.r, pCol.g, pCol.b, 35))
                draw.SimpleText(pLabel, "GW_UI_Badge", 56, 27, pCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

                -- Item Name
                local fitItemName = GW.UI.FitText(item.name, "GW_UI_Header", cardW - 116)
                draw.SimpleText(fitItemName, "GW_UI_Header", 108, 14, Color(248, 250, 252))

                -- Dynamic Price Tag
                local priceStr = (effectiveCost == 0) and "FREE" or ("$" .. string.Comma(effectiveCost))
                draw.SimpleText(priceStr, "GW_UI_Price", 18, 54, Color(74, 222, 128))

                -- Wholesale Badge vs 200%-300% Markup Pill
                local isWholesaleActive = (item.wholesaleCost and effectiveCost <= item.wholesaleCost)
                surface.SetFont("GW_UI_Price")
                local pw, _ = surface.GetTextSize(priceStr)
                local badgeX = 18 + pw + 12
                local badgeY = 56
                local badgeH = 22

                if isWholesaleActive then
                    surface.SetFont("GW_UI_Badge")
                    local wText = "Wholesale Direct Price"
                    local mw, _ = surface.GetTextSize(wText)
                    local badgeW = mw + 16
                    draw.RoundedBox(4, badgeX, badgeY, badgeW, badgeH, Color(16, 185, 129, 35))
                    surface.SetDrawColor(16, 185, 129, 140)
                    surface.DrawOutlinedRect(badgeX, badgeY, badgeW, badgeH, 1)
                    draw.SimpleText(wText, "GW_UI_Badge", badgeX + badgeW / 2, badgeY + badgeH / 2, Color(52, 211, 153), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                else
                    local markupPct = GW.GetItemMarkupPercent and GW.GetItemMarkupPercent(item, ply)
                    if markupPct and markupPct > 0 then
                        surface.SetFont("GW_UI_Badge")
                        local markupTxt = "+" .. markupPct .. "% Shop Markup"
                        local mw, _ = surface.GetTextSize(markupTxt)
                        local badgeW = mw + 16
                        draw.RoundedBox(4, badgeX, badgeY, badgeW, badgeH, Color(245, 158, 11, 40))
                        surface.SetDrawColor(245, 158, 11, 140)
                        surface.DrawOutlinedRect(badgeX, badgeY, badgeW, badgeH, 1)
                        draw.SimpleText(markupTxt, "GW_UI_Badge", badgeX + badgeW / 2, badgeY + badgeH / 2, Color(251, 191, 36), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                end

                -- Persistent Job & Level Prerequisite Pill (Marked Green with Checkmark When Satisfied!)
                local hasLevelReq = (reqItemLevel and reqItemLevel > 1)
                if isHoboProhibited then
                    draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(239, 68, 68, 30))
                    surface.SetDrawColor(239, 68, 68, 90)
                    surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                    draw.SimpleText("Hobos Cannot Buy Items", "GW_UI_Caption", cardW - 114, 64, Color(248, 113, 113), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                elseif isPoliceProhibited then
                    draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(239, 68, 68, 30))
                    surface.SetDrawColor(239, 68, 68, 90)
                    surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                    draw.SimpleText("Prohibited for Law Enforcement", "GW_UI_Caption", cardW - 114, 64, Color(248, 113, 113), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                elseif hasJobReq then
                    if canBuyJob then
                        -- Requirement met: PERSISTENT GREEN CHECKMARK PILL
                        local checkText = (hasLevelReq and canBuyLevel) and ("✓ " .. reqJobName .. " (LVL " .. reqItemLevel .. "+)") or ("✓ Requires: " .. reqJobName)
                        draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(16, 185, 129, 35))
                        surface.SetDrawColor(16, 185, 129, 140)
                        surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                        local fitCheck = GW.UI.FitText(checkText, "GW_UI_Caption", 186)
                        draw.SimpleText(fitCheck, "GW_UI_Caption", cardW - 114, 64, Color(52, 211, 153), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    else
                        -- Requirement unmet: RED WARNING PILL
                        local lockTag = "Requires: " .. reqJobName
                        draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(239, 68, 68, 30))
                        surface.SetDrawColor(239, 68, 68, 90)
                        surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                        local fitLock = GW.UI.FitText(lockTag, "GW_UI_Caption", 186)
                        draw.SimpleText(fitLock, "GW_UI_Caption", cardW - 114, 64, Color(248, 113, 113), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                elseif hasLevelReq then
                    if canBuyLevel then
                        draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(16, 185, 129, 35))
                        surface.SetDrawColor(16, 185, 129, 140)
                        surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                        draw.SimpleText("✓ Level " .. reqItemLevel .. " Unlocked", "GW_UI_Caption", cardW - 114, 64, Color(52, 211, 153), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    else
                        draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(245, 158, 11, 40))
                        surface.SetDrawColor(245, 158, 11, 140)
                        surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                        draw.SimpleText("Requires Level " .. reqItemLevel, "GW_UI_Caption", cardW - 114, 64, Color(251, 191, 36), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                end

                -- Item Description
                local subText = item.desc or ""
                if subText ~= "" then
                    local subLines = GW.UI.WrapText(subText, "GW_UI_Caption", leftContentW)
                    for i = 1, math.min(#subLines, 2) do
                        draw.SimpleText(subLines[i], "GW_UI_Caption", 18, 96 + (i - 1) * 18, Color(148, 163, 184))
                    end
                end

                -- Savings Tip for Non-Specialists
                if not isWholesaleActive and item.markupRole then
                    local tipText = "★ Tip: Buy from a " .. item.markupRole .. " to avoid this markup!"
                    local fitTip = GW.UI.FitText(tipText, "GW_UI_Caption", leftContentW)
                    draw.SimpleText(fitTip, "GW_UI_Caption", 18, 134, Color(251, 191, 36, 200))
                end
            end

            -- Purchase Action Button
            local btnBuy = vgui.Create("DButton", card)
            btnBuy:SetSize(200, 46)
            btnBuy:SetPos(cardW - 214, 88)
            btnBuy:SetText("")
            btnBuy:SetEnabled(canAfford and not isLocked)

            btnBuy.Paint = function(s, w, h)
                local btnCol = Color(16, 185, 129, 220)
                local text = (effectiveCost == 0) and "Apply (Free)" or ("Purchase ($" .. string.Comma(effectiveCost) .. ")")
                if item.wholesaleCost and effectiveCost <= item.wholesaleCost then
                    text = "Purchase ($" .. string.Comma(effectiveCost) .. " Wholesale)"
                end

                if isHoboProhibited then
                    btnCol = Color(51, 65, 85, 180)
                    text = "Hobos Cannot Buy Items"
                elseif isPoliceProhibited then
                    btnCol = Color(51, 65, 85, 180)
                    text = (item.category == "printers" and "Printers Prohibited") or "Contraband Prohibited"
                elseif not canBuyLevel and not canBuyJob then
                    btnCol = Color(51, 65, 85, 180)
                    text = "Requires Level & Role"
                elseif not canBuyLevel then
                    btnCol = Color(51, 65, 85, 180)
                    text = "Requires Level " .. reqItemLevel
                elseif not canBuyJob then
                    btnCol = Color(51, 65, 85, 180)
                    text = "Job Restricted"
                elseif not canAfford then
                    btnCol = Color(185, 28, 28, 140)
                    text = "Cannot Afford"
                elseif s:IsHovered() then
                    btnCol = Color(5, 150, 105, 255)
                end

                draw.RoundedBox(6, 0, 0, w, h, btnCol)
                local fitBtnText = GW.UI.FitText(text, "GW_UI_Btn", w - 16)
                draw.SimpleText(fitBtnText, "GW_UI_Btn", w / 2, h / 2, isLocked and Color(156, 163, 175) or Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            btnBuy.DoClick = function()
                if isHoboProhibited then
                    GW.Notify(ply, "Hobos cannot purchase items! You can only use building tools.", NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                if isPoliceProhibited then
                    GW.Notify(ply, "Police officers cannot purchase printers or contraband!", NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                if not canBuyLevel and not canBuyJob then
                    GW.Notify(ply, string.format("You must be Level %d and employed as %s to purchase this!", reqItemLevel, reqJobName ~= "" and reqJobName or "Specialist"), NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                if not canBuyLevel then
                    GW.Notify(ply, string.format("You must be Level %d to purchase this item!", reqItemLevel), NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                if not canBuyJob then
                    GW.Notify(ply, "Requires employment as: " .. (reqJobName ~= "" and reqJobName or "Specialist"), NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                if not canAfford then
                    GW.Notify(ply, "You cannot afford this item ($" .. effectiveCost .. ")!", NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end

                net.Start("GW_BuyItem")
                    net.WriteString(itemId)
                net.SendToServer()
            end
        end
    end
end

-- ==========================================
-- RULES TAB (SOPHISTICATED ACCORDION WITH WORD WRAP)
-- ==========================================

function GW.UI.RenderRulesContent(scroll)
    local container = vgui.Create("DPanel", scroll)
    container:Dock(FILL)
    container.Paint = function() end

    local rules = {
        {
            num = "01",
            title = "Turf Warfare & Sovereign Territory",
            desc = "All city districts marked with holographic beacons are contested turf. Gang members and law enforcement may capture territory by interacting with the flag pole (E). Controlled turfs yield recurring dividends directly into active member wallets.",
            accent = Color(6, 182, 212)
        },
        {
            num = "02",
            title = "Money Printers & Police Raids",
            desc = "Money printers generate recurring passive cash revenue. Maintain internal temperatures below 100C using E to prevent explosions. Police officers are authorized to raid bases and seize printers for instant cash bounties.",
            accent = Color(245, 158, 11)
        },
        {
            num = "03",
            title = "Non-RDM & Rules of Engagement",
            desc = "Random Deathmatch (RDM) is strictly prohibited. You must have legitimate in-character hostile roleplay provocation or ongoing turf warfare combat to initiate lethal firearm violence.",
            accent = Color(239, 68, 68)
        },
        {
            num = "04",
            title = "Base Architecture & Prop Security",
            desc = "Base fortifications must not completely block public highways, sidewalk thoroughfares, or flag pole capture perimeters. All bases must feature clear, navigable keycard or door access points.",
            accent = Color(16, 185, 129)
        },
        {
            num = "05",
            title = "New Life Rule (NLR) & Return Limits",
            desc = "Upon death, you forget all immediate memories leading up to your demise. You may not return to your location of death for at least 3 minutes, nor may you seek revenge against your killer.",
            accent = Color(168, 85, 247)
        }
    }

    local scrollW = scroll:GetWide() - 32
    for _, r in ipairs(rules) do
        local maxTextW = math.max(scrollW - 100, 400)
        local lines = GW.UI.WrapText(r.desc, "GW_UI_Body", maxTextW)
        local cardH = math.max(130, 68 + #lines * 24 + 16)

        local card = scroll:Add("DPanel")
        card:Dock(TOP)
        card:DockMargin(0, 0, 0, 14)
        card:SetTall(cardH)

        card.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 200))
            draw.RoundedBoxEx(8, 0, 0, 6, h, r.accent, true, false, true, false)
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            -- Number badge
            draw.RoundedBox(4, 18, 16, 44, 34, Color(r.accent.r, r.accent.g, r.accent.b, 35))
            draw.SimpleText(r.num, "GW_UI_Header", 40, 33, r.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            -- Title
            draw.SimpleText(r.title, "GW_UI_Header", 76, 33, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Word-Wrapped Description
            for i, line in ipairs(lines) do
                draw.SimpleText(line, "GW_UI_Body", 76, 62 + (i - 1) * 24, Color(148, 163, 184))
            end
        end
    end
end
