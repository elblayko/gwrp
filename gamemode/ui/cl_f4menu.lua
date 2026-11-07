--[[
    cl_f4menu.lua - High-Legibility Scaled UI/UX F4 Dashboard with Full Word Wrap & Truncation Protection
    Author: Juicebox & Antigravity
--]]

GRID = GRID or {}
GRID.UI = GRID.UI or {}
GRID.UI.F4Frame = nil
GRID.UI.ActiveF4Tab = "jobs"
GRID.UI.ActiveJobCategory = "all"
GRID.UI.SearchQuery = ""
GRID.UI.ClientGangData = nil

-- Network Receiver for Gang Dashboard Data
local function HandleSendGangData()
    local jsonStr = net.ReadString() or "{}"
    GRID.UI.ClientGangData = util.JSONToTable(jsonStr) or {}

    if IsValid(GRID.UI.F4Frame) and GRID.UI.ActiveF4Tab == "gang" then
        if IsValid(GRID.UI.CurrentContentPanel) then
            GRID.UI.CurrentContentPanel:Clear()
            GRID.UI.RenderContentTab(GRID.UI.CurrentContentPanel, "gang", GRID.UI.F4Frame)
        end
    end
end
net.Receive("GRID_SendGangData", HandleSendGangData)

-- Text Formatting Helpers: Word Wrap & Boundary Protection
function GRID.UI.WrapText(text, font, maxW)
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

function GRID.UI.FitText(text, font, maxW)
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

function GRID.UI.ToggleF4Menu()
    if IsValid(GRID.UI.F4Frame) then
        GRID.UI.F4Frame:Close()
        GRID.UI.F4Frame = nil
        return
    end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- Ensure fonts are always initialized and scaled
    if GRID.UI.CreateFonts then
        GRID.UI.CreateFonts()
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
        GRID.UI.F4Frame = nil
    end
    GRID.UI.F4Frame = frame

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
        draw.SimpleText("GridRP", "GRID_UI_Title", 24, 20, Color(248, 250, 252), TEXT_ALIGN_LEFT)
        draw.RoundedBox(4, 240, 24, 114, 24, Color(6, 182, 212, 35))
        surface.SetDrawColor(6, 182, 212, 120)
        surface.DrawOutlinedRect(240, 24, 114, 24, 1)
        draw.SimpleText("v0.0.1", "GRID_UI_Badge", 297, 36, Color(34, 211, 238), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)

        -- Player Wallet & Gang Pill (Center Header)
        local curMoney = IsValid(ply) and ply:GetMoney() or 0
        local curGang = IsValid(ply) and ply:GetGang() or ""
        local curJob = IsValid(ply) and ply:GetJobData() or {}
        local gangCol = (curGang ~= "") and GRID.GetGangColor(curGang) or
            (curJob.faction and curJob.faction.color or GRID.Colors.White)

        local pillText = "$" .. string.Comma(curMoney) .. "   |   " .. (curJob.name or "Citizen")
        if curGang ~= "" then
            pillText = pillText .. "   |   " .. curGang
        end

        local pillX = w / 2
        draw.RoundedBox(18, pillX - 190, 14, 380, 42, Color(24, 32, 47, 240))
        surface.SetDrawColor(gangCol.r, gangCol.g, gangCol.b, 100)
        surface.DrawOutlinedRect(pillX - 190, 14, 380, 42, 1)
        draw.SimpleText(pillText, "GRID_UI_Header", pillX, 35, Color(74, 222, 128), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Close Button (Top-Right X)
    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(44, 44)
    btnClose:SetPos(frameW - 56, 13)
    btnClose:SetText("")
    btnClose.Paint = function(s, w, h)
        local bgCol = s:IsHovered() and Color(239, 68, 68, 220) or Color(30, 41, 59, 160)
        draw.RoundedBox(6, 0, 0, w, h, bgCol)
        draw.SimpleText("X", "GRID_UI_Title", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
            draw.SimpleText("Admin HUD", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        btnAdmin.DoClick = function()
            frame:Close()
            if GRID.Turf and GRID.Turf.OpenSetupMenu then
                GRID.Turf.OpenSetupMenu()
            end
        end
    end

    -- ==========================================
    -- LEFT VERTICAL SIDEBAR NAVIGATION (CATEGORIZED SECTIONS)
    -- ==========================================
    local sidebar = vgui.Create("DPanel", frame)
    sidebar:SetPos(14, 82)
    sidebar:SetSize(264, frameH - 96)
    sidebar.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- Bottom Info Card
    local botInfo = vgui.Create("DPanel", sidebar)
    botInfo:SetPos(10, frameH - 96 - 72)
    botInfo:SetSize(244, 62)
    botInfo.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 220))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("Map: " .. game.GetMap(), "GRID_UI_Caption", 12, 16, Color(148, 163, 184))
        draw.SimpleText("Online: " .. #player.GetAll() .. " players", "GRID_UI_Caption", 12, 38, Color(74, 222, 128))
    end

    local invItems = GRID.Inventory and GRID.Inventory.ClientItems or {}
    local invBadge = #invItems > 0 and tostring(#invItems) or "0"
    local rawGang = IsValid(ply) and ply:GetRawGang() or ""
    local gangBadge = (rawGang ~= "") and "Active" or "None"
    if IsValid(ply) and rawGang ~= "" and not ply:IsGangFaction() then
        gangBadge = "Suspended"
    end

    -- Categorized Sections Hierarchy
    local navSections = {
        {
            header = "ROLES & ASSETS",
            tabs = {
                { id = "jobs",      title = "Careers & Jobs", badge = table.Count(GRID.Jobs or {}) },
                { id = "inventory", title = "Inventory",      badge = invBadge },
                { id = "auction",   title = "Auction House",  badge = "AH" },
                { id = "stocks",    title = "Stock Market",   badge = "STX" }
            }
        },
        {
            header = "INFO",
            tabs = {
                { id = "rules", title = "Server Rules", badge = "Rules" },
                { id = "guide", title = "Server Guide", badge = "Guide" }
            }
        },
        {
            header = "GANG MANAGEMENT",
            tabs = {
                { id = "gang", title = "View Gang", badge = gangBadge }
            }
        },
        {
            header = "ITEM SHOP",
            tabs = {
                { id = "weapons",    title = "Ammo & Gear",      badge = "Ammo" },
                { id = "entities",   title = "Printers & Tech",  badge = "Tech" },
                { id = "shipments",  title = "Shipments",        badge = "Bulk" },
                { id = "networking", title = "Networking",       badge = "Cyber" },
                { id = "supplies",   title = "Supplies & Items", badge = "Aid" }
            }
        }
    }

    if ply:IsAdmin() or ply:IsSuperAdmin() then
        table.insert(navSections[4].tabs, { id = "debug_buffs", title = "Debug Buffs", badge = "Admin" })
    end

    if ply:IsPolice() then
        local isMayor = (ply.GetJob and ply:GetJob() == "mayor")
        table.insert(navSections[1].tabs, {
            id = "police_dispatch",
            title = isMayor and "Mayor Warrants" or "Police Dispatch",
            badge = isMayor and "Mayor" or "LSPD"
        })
    end

    -- Sidebar Scrollable Button List
    local navScroll = vgui.Create("DScrollPanel", sidebar)
    navScroll:SetPos(6, 8)
    navScroll:SetSize(252, frameH - 96 - 86)
    local navVBar = navScroll:GetVBar()
    navVBar:SetWide(4)
    navVBar.Paint = function() end
    navVBar.btnGrip.Paint = function(s, w, h) draw.RoundedBox(2, 0, 0, w, h, Color(56, 189, 248, 80)) end
    navVBar.btnUp.Paint = function() end
    navVBar.btnDown.Paint = function() end

    -- Content Body Container
    local contentPanel = vgui.Create("DPanel", frame)
    contentPanel:SetPos(292, 82)
    contentPanel:SetSize(frameW - 306, frameH - 96)
    contentPanel.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 140))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    GRID.UI.CurrentContentPanel = contentPanel

    local function SwitchTab(tabId)
        GRID.UI.ActiveF4Tab = tabId
        if tabId == "gang" then
            local now = CurTime()
            if not GRID.UI.LastGangRequest or (now - GRID.UI.LastGangRequest) > 3 then
                GRID.UI.LastGangRequest = now
                net.Start("GRID_RequestGangData")
                net.SendToServer()
            end
        end
        contentPanel:Clear()
        GRID.UI.RenderContentTab(contentPanel, tabId, frame)
    end

    -- Build Grouped Navigation Elements
    for secIdx, sec in ipairs(navSections) do
        -- Section Header
        local secHeader = navScroll:Add("DPanel")
        secHeader:Dock(TOP)
        secHeader:DockMargin(4, secIdx == 1 and 4 or 12, 4, 4)
        secHeader:SetTall(24)
        secHeader.Paint = function(s, w, h)
            draw.SimpleText(sec.header, "GRID_UI_Badge", 8, h / 2, Color(148, 163, 184), TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)
            surface.SetFont("GRID_UI_Badge")
            local tw, _ = surface.GetTextSize(sec.header)
            local lineX = 14 + tw
            if lineX < w - 8 then
                surface.SetDrawColor(51, 65, 85, 140)
                surface.DrawLine(lineX, h / 2, w - 8, h / 2)
            end
        end

        -- Sub Tabs
        for _, tab in ipairs(sec.tabs) do
            local btnTab = navScroll:Add("DButton")
            btnTab:Dock(TOP)
            btnTab:DockMargin(4, 2, 4, 2)
            btnTab:SetTall(38)
            btnTab:SetText("")

            btnTab.Paint = function(s, w, h)
                local isActive = (GRID.UI.ActiveF4Tab == tab.id)
                local isHovered = s:IsHovered()

                local bgCol = isActive and Color(30, 41, 59, 255) or
                    (isHovered and Color(24, 32, 47, 180) or Color(0, 0, 0, 0))
                draw.RoundedBox(6, 0, 0, w, h, bgCol)

                if isActive then
                    draw.RoundedBox(2, 0, 6, 4, h - 12, Color(6, 182, 212))
                end

                local textCol = isActive and Color(248, 250, 252) or
                    (isHovered and Color(226, 232, 240) or Color(148, 163, 184))
                draw.SimpleText(tab.title, "GRID_UI_Sub", 16, h / 2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                if tab.badge then
                    local badgeText = tostring(tab.badge)
                    local badgeBg = (tab.id == "gang" and badgeText == "Suspended") and Color(245, 158, 11, 40) or
                        Color(11, 15, 25, 200)
                    local badgeFg = (tab.id == "gang" and badgeText == "Suspended") and Color(251, 191, 36) or
                        Color(148, 163, 184)
                    if tab.id == "gang" and badgeText == "Active" then
                        badgeBg = Color(16, 185, 129, 40)
                        badgeFg = Color(52, 211, 153)
                    end

                    surface.SetFont("GRID_UI_Badge")
                    local bw = surface.GetTextSize(badgeText) + 16
                    draw.RoundedBox(4, w - bw - 8, (h - 22) / 2, bw, 22, badgeBg)
                    draw.SimpleText(badgeText, "GRID_UI_Badge", w - 8 - bw / 2, h / 2, badgeFg, TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                end
            end

            btnTab.DoClick = function()
                SwitchTab(tab.id)
            end
        end
    end

    -- Initial tab load
    SwitchTab(GRID.UI.ActiveF4Tab or "jobs")
end

function GRID.UI.RefreshInventoryTab()
    if not IsValid(GRID.UI.F4Frame) or GRID.UI.ActiveF4Tab ~= "inventory" then return end
    if IsValid(GRID.UI.CurrentContentPanel) then
        GRID.UI.CurrentContentPanel:Clear()
        GRID.UI.RenderContentTab(GRID.UI.CurrentContentPanel, "inventory", GRID.UI.F4Frame)
    end
end

-- ==========================================
-- TAB CONTENT RENDERER
-- ==========================================

function GRID.UI.RenderContentTab(container, tabId, mainFrame)
    local ply = LocalPlayer()
    local contW, contH = container:GetWide(), container:GetTall()

    if tabId == "auction" then
        if GRID.Auction and GRID.Auction.RenderBrowseTab then
            GRID.Auction.IsTerminalSession = false
            GRID.Auction.RequestSync()
            GRID.Auction.RenderBrowseTab(container)
        end
        return
    end

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
            rules = "City Ordinances & Server Code of Conduct",
            guide = "Citizen Handbook & Server Guide",
            gang = "Gang Management & Underworld Syndicate"
        }
        draw.SimpleText(titles[tabId] or "Catalog", "GRID_UI_Header", 0, h / 2, Color(248, 250, 252), TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
    end

    -- Search Bar Filter (Hidden on non-catalog tabs)
    if tabId ~= "rules" and tabId ~= "guide" and tabId ~= "gang" then
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
                draw.SimpleText("Open Bag (B)", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
            end
            btnBag.DoClick = function()
                mainFrame:Close()
                if GRID.UI.ToggleBag then
                    GRID.UI.ToggleBag()
                end
            end
        end

        local txtSearch = vgui.Create("DTextEntry", topBar)
        txtSearch:SetSize(280, 42)
        txtSearch:SetPos(topBar:GetWide() - 280, 4)
        txtSearch:SetPlaceholderText(tabId == "inventory" and "Search inventory..." or
            (tabId == "jobs" and "Search roles..." or "Search catalog..."))
        txtSearch:SetFont("GRID_UI_Sub")
        txtSearch.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 220))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            s:DrawTextEntryText(Color(248, 250, 252), Color(6, 182, 212), Color(248, 250, 252))
        end
        txtSearch.OnChange = function(s)
            GRID.UI.SearchQuery = string.lower(string.Trim(s:GetText()))
            local targetScroll = container:GetChildren()[2]
            if IsValid(targetScroll) then
                targetScroll:Clear()
                if tabId == "inventory" then
                    GRID.UI.PopulateInventoryGrid(targetScroll, mainFrame, GRID.UI.SearchQuery)
                else
                    GRID.UI.PopulateGrid(targetScroll, tabId, mainFrame, GRID.UI.SearchQuery)
                end
            end
        end
    end

    -- Scroll Area
    local scroll = vgui.Create("DScrollPanel", container)
    scroll:SetPos(16, 72)
    scroll:SetSize(contW - 32, contH - 86)

    local sbar = scroll:GetVBar()
    sbar:SetWide(8)
    sbar.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(11, 15, 25, 120)) end
    sbar.btnGrip.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(56, 189, 248, 140)) end
    sbar.btnUp.Paint = function() end
    sbar.btnDown.Paint = function() end

    if tabId == "rules" then
        GRID.UI.RenderRulesContent(scroll)
    elseif tabId == "guide" then
        GRID.UI.RenderGuideContent(scroll)
    elseif tabId == "gang" then
        GRID.UI.RenderGangContent(scroll, mainFrame)
    elseif tabId == "inventory" then
        GRID.UI.PopulateInventoryGrid(scroll, mainFrame, "")
    elseif tabId == "police_dispatch" then
        GRID.UI.RenderPoliceDispatchContent(scroll, mainFrame)
    elseif tabId == "stocks" then
        GRID.UI.RenderStockMarketContent(scroll, mainFrame)
    else
        GRID.UI.PopulateGrid(scroll, tabId, mainFrame, "")
    end
end

-- ==========================================
-- SERVER GUIDE CONTENT
-- ==========================================

function GRID.UI.RenderGuideContent(scroll)
    local guideSections = {
        {
            num = "01",
            title = "Getting Started & Career Advancement",
            desc =
            "Begin your life in GridRP by opening the Careers tab. Choosing a job grants regular periodic salaries, specialized equipment, and unlocks corresponding trade items. Earn Respect and XP to Level Up by surviving, completing faction activities, contesting territory, and engaging in trade.",
            accent = Color(6, 182, 212)
        },
        {
            num = "02",
            title = "Economy: Wholesale Dealers vs Retail Kiosks",
            desc =
            "Items in the public F4 Item Shop carry a 200% to 260% convenience kiosk markup. Specialized merchants (Arms Dealers, Pharmacists, Cyber Engineers, and Black Market Dealers) purchase items at direct factory wholesale cost. Save money by purchasing directly from players or start your own distribution empire!",
            accent = Color(16, 185, 129)
        },
        {
            num = "03",
            title = "Money Printers & Cooling Mechanics",
            desc =
            "Money printers produce continuous passive cash income. Internal temperatures rise during operation; interact with printers using [E] to cycle coolant and prevent explosive overheating at 100C. Warning: Police officers are authorized to raid bases and seize illegal printers for instant cash bounties.",
            accent = Color(245, 158, 11)
        },
        {
            num = "04",
            title = "Gangs, Turf Flags & Territory Taxation",
            desc =
            "Street Gangsters can organize syndicates in the Gang Management tab or via /creategang <name>. Capture city territory districts by holding the holographic flag poles [E]. Controlled turfs deposit recurring dividends into member wallets and allow the gang leader to configure district sales taxes (5% to 30%).",
            accent = Color(168, 85, 247)
        },
        {
            num = "05",
            title = "Real Estate, Keys & Base Architecture",
            desc =
            "Look at any unowned door and press [F2] to purchase real estate. Lock and unlock doors using Keys. Base defenses must feature clear, navigable entranceways and must never completely block public highways or flag pole perimeters. Hobos are restricted to building sandbox structures and cannot purchase real estate or weapons.",
            accent = Color(56, 189, 248)
        },
        {
            num = "06",
            title = "Chat Commands Reference",
            desc =
            "Quick chat commands available to all citizens:\n- /gang : View active gang status, bank balance & controlled turfs\n- /creategang <name> : Found a street gang ($500 creation fee)\n- /invitegang <player> : Invite a fellow gangster to your syndicate\n- /acceptgang : Accept a pending street gang invitation\n- /leavegang : Voluntarily leave your current gang\n- /settax <5-30> : Configure tax rate for your controlled district\n- /g <msg> : Broadcast message on encrypted private gang radio\n- /dropmoney <amount> : Drop physical cash bills from your wallet",
            accent = Color(244, 63, 94)
        }
    }

    local scrollW = scroll:GetWide() - 32
    for _, g in ipairs(guideSections) do
        local maxTextW = math.max(scrollW - 100, 400)
        local lines = GRID.UI.WrapText(g.desc, "GRID_UI_Body", maxTextW)
        local cardH = math.max(130, 68 + #lines * 22 + 16)

        local card = scroll:Add("DPanel")
        card:Dock(TOP)
        card:DockMargin(0, 0, 0, 14)
        card:SetTall(cardH)

        card.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 200))
            draw.RoundedBoxEx(8, 0, 0, 6, h, g.accent, true, false, true, false)
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            -- Number badge
            draw.RoundedBox(4, 18, 16, 44, 34, Color(g.accent.r, g.accent.g, g.accent.b, 35))
            draw.SimpleText(g.num, "GRID_UI_Header", 40, 33, g.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            -- Title
            draw.SimpleText(g.title, "GRID_UI_Header", 76, 33, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Word-Wrapped Description
            for i, line in ipairs(lines) do
                draw.SimpleText(line, "GRID_UI_Body", 76, 62 + (i - 1) * 22, Color(148, 163, 184))
            end
        end
    end
end

-- ==========================================
-- GANG STOCK MARKET OVERVIEW (F4 INTEGRATION)
-- ==========================================

function GRID.UI.RenderStockMarketContent(scroll, mainFrame)
    local scrollW = scroll:GetWide() - 24

    -- Marquee Ticker
    if GRID.Stocks and GRID.Stocks.CreateTickerBar then
        local ticker = GRID.Stocks.CreateTickerBar(scroll, scrollW, 36)
        ticker:Dock(TOP)
        ticker:DockMargin(0, 0, 0, 12)
    end

    -- Prompt card
    local notice = scroll:Add("DPanel")
    notice:Dock(TOP)
    notice:DockMargin(0, 0, 0, 12)
    notice:SetTall(48)
    notice.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(20, 29, 47, 220))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("NOTICE: To buy shares, sell shares, or claim dividends, access any Street ATM terminal in the city.", "GRID_UI_Body", 16, h / 2, Color(52, 211, 153), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Interactive Line Chart
    if GRID.Stocks and GRID.Stocks.CreateChartPanel then
        local chart = GRID.Stocks.CreateChartPanel(scroll, scrollW, 260)
        chart:Dock(TOP)
        chart:DockMargin(0, 0, 0, 14)

        local firstListing = next(GRID.Stocks.ClientListings or {})
        if firstListing then
            chart:SetGang(firstListing)
        end
    end

    -- Public listings grid
    local listings = {}
    for _, s in pairs(GRID.Stocks.ClientListings or {}) do
        table.insert(listings, s)
    end
    table.sort(listings, function(a, b) return (a.current_price or 0) > (b.current_price or 0) end)

    for _, s in ipairs(listings) do
        local card = scroll:Add("DPanel")
        card:Dock(TOP)
        card:DockMargin(0, 0, 0, 8)
        card:SetTall(60)
        card.Paint = function(pnl, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            local statusStr = "ACTIVE"
            local statusCol = Color(52, 211, 153)
            if s.is_defaulted then
                statusStr = "DEFAULTED / JUNK"
                statusCol = Color(239, 68, 68)
            elseif s.is_halted then
                statusStr = string.format("HALTED (%ds)", s.halt_secs or 0)
                statusCol = Color(245, 158, 11)
            end

            draw.SimpleText(s.ticker, "GRID_UI_Header", 16, 20, Color(248, 250, 252))
            draw.SimpleText(s.gang_name, "GRID_UI_Caption", 16, 42, Color(148, 163, 184))

            draw.SimpleText("PRICE: $" .. string.Comma(s.current_price), "GRID_UI_Header", 220, 20, Color(52, 211, 153))
            local chg = s.current_price - (s.price_24h_ago or s.current_price)
            local pct = (s.price_24h_ago and s.price_24h_ago > 0) and ((chg / s.price_24h_ago) * 100) or 0
            draw.SimpleText(string.format("24h: %s%.1f%%", chg >= 0 and "+" or "", pct), "GRID_UI_Caption", 220, 42, chg >= 0 and Color(74, 222, 128) or Color(248, 113, 113))

            draw.SimpleText(string.format("FLOAT: %d / %d", s.circulating_shares, s.issued_shares), "GRID_UI_Body", 400, 20, Color(203, 213, 225))
            draw.SimpleText(string.format("DIVIDEND: %.1f%%", (s.dividend_rate or 0.03) * 100), "GRID_UI_Caption", 400, 42, Color(148, 163, 184))

            draw.SimpleText(statusStr, "GRID_UI_Badge", w - 16, h / 2, statusCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
end

-- ==========================================
-- GANG MANAGEMENT DASHBOARD (VIEW GANG)
-- ==========================================

function GRID.UI.RenderGangContent(scroll, mainFrame)
    local ply = LocalPlayer()
    local data = GRID.UI.ClientGangData

    -- Loading Placeholder (only request if data not cached yet)
    if not data then
        local now = CurTime()
        if not GRID.UI.LastGangRequest or (now - GRID.UI.LastGangRequest) > 3 then
            GRID.UI.LastGangRequest = now
            net.Start("GRID_RequestGangData")
            net.SendToServer()
        end

        local loading = scroll:Add("DPanel")
        loading:Dock(TOP)
        loading:SetTall(160)
        loading.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 180))
            draw.SimpleText("Loading Syndicate Intelligence...", "GRID_UI_Header", w / 2, h / 2, Color(6, 182, 212),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    local scrollW = scroll:GetWide() - 20

    -- ========================================================
    -- SCENARIO A: PLAYER IS IN A GANG
    -- ========================================================
    if data.hasGang then
        -- 1. Suspension Warning Banner (if off-duty as Police or Civilian)
        if data.isSuspended then
            local susp = scroll:Add("DPanel")
            susp:Dock(TOP)
            susp:DockMargin(0, 0, 0, 14)
            susp:SetTall(64)
            susp.Paint = function(s, w, h)
                draw.RoundedBox(8, 0, 0, w, h, Color(245, 158, 11, 25))
                surface.SetDrawColor(245, 158, 11, 140)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText("[!] GANG AFFILIATION CURRENTLY SUSPENDED", "GRID_UI_Sub", 18, 18, Color(251, 191, 36))
                draw.SimpleText(
                    "You are on duty as " ..
                    data.currentJob ..
                    ". Gang territory dividends & controls are dormant until you switch to Street Gangs in Careers.",
                    "GRID_UI_Caption", 18, 40, Color(226, 232, 240))
            end
        end

        -- 2. Top Gang Header Banner
        local gangCol = GRID.GetGangColor(data.gangName)
        local topBanner = scroll:Add("DPanel")
        topBanner:Dock(TOP)
        topBanner:DockMargin(0, 0, 0, 16)
        topBanner:SetTall(84)
        topBanner.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 240))
            draw.RoundedBoxEx(8, 0, 0, 6, h, gangCol, true, false, true, false)
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            -- Gang Name
            draw.SimpleText(data.gangName, "GRID_UI_Title", 24, 26, Color(248, 250, 252))

            -- Rank Pill
            local rText = data.isLeader and "GANG LEADER" or "SYNDICATE MEMBER"
            local rCol = data.isLeader and Color(6, 182, 212) or Color(148, 163, 184)
            surface.SetFont("GRID_UI_Badge")
            local tw = surface.GetTextSize(rText) + 20
            draw.RoundedBox(4, 24, 50, tw, 22, Color(rCol.r, rCol.g, rCol.b, 35))
            draw.SimpleText(rText, "GRID_UI_Badge", 24 + tw / 2, 61, rCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            -- Right Stats
            local stat1 = "[*] Respect: " .. string.Comma(data.respect)
            local stat2 = #data.members .. " Registered Gangsters"
            draw.SimpleText(stat1, "GRID_UI_Header", w - 24, 24, Color(245, 158, 11), TEXT_ALIGN_RIGHT)
            draw.SimpleText(stat2, "GRID_UI_Sub", w - 24, 52, Color(74, 222, 128), TEXT_ALIGN_RIGHT)
        end

        -- 3. Two Column Layout Container
        local colContainer = scroll:Add("DPanel")
        colContainer:Dock(TOP)
        colContainer:DockMargin(0, 0, 0, 16)
        colContainer:SetTall(420)
        colContainer.Paint = function() end

        local colW = (scrollW - 14) / 2

        -- LEFT COLUMN: Vault & Territories
        local leftCol = vgui.Create("DPanel", colContainer)
        leftCol:SetPos(0, 0)
        leftCol:SetSize(colW, 420)
        leftCol.Paint = function() end

        -- Vault Card
        local vaultCard = vgui.Create("DPanel", leftCol)
        vaultCard:SetPos(0, 0)
        vaultCard:SetSize(colW, 230)
        vaultCard.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 200))
            draw.RoundedBoxEx(8, 0, 0, w, 4, Color(16, 185, 129), true, true, false, false)
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText("GANG VAULT & TREASURY", "GRID_UI_Sub", 18, 16, Color(16, 185, 129))
            local balText = "$" .. string.Comma(data.bank)
            draw.SimpleText(balText, "GRID_UI_Price", 18, 52, Color(74, 222, 128))
            draw.SimpleText("Territory tax earnings and dividends accumulate directly in the vault.", "GRID_UI_Caption",
                18,
                88, Color(148, 163, 184))
        end

        -- Vault Deposit Buttons
        local depAmounts = { 500, 2500, 10000 }
        local depX = 18
        for _, amt in ipairs(depAmounts) do
            local bDep = vgui.Create("DButton", vaultCard)
            bDep:SetPos(depX, 116)
            bDep:SetSize((colW - 54) / 3, 34)
            bDep:SetText("")
            bDep.Paint = function(s, w, h)
                local bg = s:IsHovered() and Color(16, 185, 129, 220) or Color(5, 150, 105, 180)
                draw.RoundedBox(6, 0, 0, w, h, bg)
                draw.SimpleText("+$" .. string.Comma(amt), "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252),
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            bDep.DoClick = function()
                net.Start("GRID_GangUIAction")
                net.WriteString("deposit")
                net.WriteString(util.TableToJSON({ amount = amt }))
                net.SendToServer()
            end
            depX = depX + (colW - 54) / 3 + 9
        end

        -- Vault Withdraw Buttons (Leader only)
        if data.isLeader then
            local withX = 18
            for _, amt in ipairs(depAmounts) do
                local bWith = vgui.Create("DButton", vaultCard)
                bWith:SetPos(withX, 160)
                bWith:SetSize((colW - 54) / 3, 34)
                bWith:SetText("")
                bWith.Paint = function(s, w, h)
                    local canWith = (data.bank >= amt)
                    local bg = not canWith and Color(51, 65, 85, 160) or
                        (s:IsHovered() and Color(239, 68, 68, 220) or Color(185, 28, 28, 180))
                    draw.RoundedBox(6, 0, 0, w, h, bg)
                    draw.SimpleText("-$" .. string.Comma(amt), "GRID_UI_Btn", w / 2, h / 2,
                        canWith and Color(248, 250, 252) or Color(156, 163, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                bWith.DoClick = function()
                    net.Start("GRID_GangUIAction")
                    net.WriteString("withdraw")
                    net.WriteString(util.TableToJSON({ amount = amt }))
                    net.SendToServer()
                end
                withX = withX + (colW - 54) / 3 + 9
            end
        else
            local lblOnlyLeader = vgui.Create("DLabel", vaultCard)
            lblOnlyLeader:SetPos(18, 166)
            lblOnlyLeader:SetSize(colW - 36, 24)
            lblOnlyLeader:SetFont("GRID_UI_Caption")
            lblOnlyLeader:SetTextColor(Color(148, 163, 184))
            lblOnlyLeader:SetText("[*] Vault withdrawals are reserved exclusively for the Gang Leader.")
        end

        -- Controlled Territories Card
        local turfCard = vgui.Create("DPanel", leftCol)
        turfCard:SetPos(0, 244)
        turfCard:SetSize(colW, 176)
        turfCard.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 200))
            draw.RoundedBoxEx(8, 0, 0, w, 4, Color(168, 85, 247), true, true, false, false)
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText("CONTROLLED TERRITORIES (" .. #data.turfs .. ")", "GRID_UI_Sub", 18, 16, Color(168, 85, 247))
        end

        local turfScroll = vgui.Create("DScrollPanel", turfCard)
        turfScroll:SetPos(14, 46)
        turfScroll:SetSize(colW - 28, 120)

        if #data.turfs == 0 then
            local noTurf = turfScroll:Add("DLabel")
            noTurf:Dock(TOP)
            noTurf:DockMargin(4, 16, 4, 4)
            noTurf:SetFont("GRID_UI_Caption")
            noTurf:SetTextColor(Color(148, 163, 184))
            noTurf:SetText(
                "No city districts currently owned. Hold holographic flag poles in contested areas to capture.")
        else
            for _, t in ipairs(data.turfs) do
                local tRow = turfScroll:Add("DPanel")
                tRow:Dock(TOP)
                tRow:DockMargin(0, 0, 0, 8)
                tRow:SetTall(38)
                tRow.Paint = function(s, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 220))
                    draw.SimpleText(t.name, "GRID_UI_Sub", 12, h / 2, Color(248, 250, 252), TEXT_ALIGN_LEFT,
                        TEXT_ALIGN_CENTER)
                    draw.SimpleText("District Tax: " .. (t.tax_rate or 10) .. "%", "GRID_UI_Caption", w - 12, h / 2,
                        Color(74, 222, 128), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end
        end

        -- RIGHT COLUMN: Member Roster & Recruitment
        local rightCol = vgui.Create("DPanel", colContainer)
        rightCol:SetPos(colW + 14, 0)
        rightCol:SetSize(colW, 420)
        rightCol.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 200))
            draw.RoundedBoxEx(8, 0, 0, w, 4, Color(6, 182, 212), true, true, false, false)
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText("SYNDICATE ROSTER & RECRUITS", "GRID_UI_Sub", 18, 16, Color(6, 182, 212))
        end

        -- Recruitment Bar (Invite Player)
        local txtInvite = vgui.Create("DTextEntry", rightCol)
        txtInvite:SetPos(18, 48)
        txtInvite:SetSize(colW - 138, 36)
        txtInvite:SetPlaceholderText("Enter player name or SteamID...")
        txtInvite:SetFont("GRID_UI_Caption")
        txtInvite.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 220))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            s:DrawTextEntryText(Color(248, 250, 252), Color(6, 182, 212), Color(248, 250, 252))
        end

        local btnInvite = vgui.Create("DButton", rightCol)
        btnInvite:SetPos(colW - 110, 48)
        btnInvite:SetSize(92, 36)
        btnInvite:SetText("")
        btnInvite.Paint = function(s, w, h)
            local bg = s:IsHovered() and Color(6, 182, 212, 240) or Color(14, 116, 144, 200)
            draw.RoundedBox(6, 0, 0, w, h, bg)
            draw.SimpleText("Invite", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        btnInvite.DoClick = function()
            local targetName = string.Trim(txtInvite:GetText())
            if targetName == "" then return end
            net.Start("GRID_GangUIAction")
            net.WriteString("invite")
            net.WriteString(util.TableToJSON({ target = targetName }))
            net.SendToServer()
            txtInvite:SetText("")
        end

        -- Members Scrollable List
        local rosterScroll = vgui.Create("DScrollPanel", rightCol)
        rosterScroll:SetPos(18, 94)
        rosterScroll:SetSize(colW - 36, 310)

        for _, m in ipairs(data.members) do
            local mRow = rosterScroll:Add("DPanel")
            mRow:Dock(TOP)
            mRow:DockMargin(0, 0, 0, 8)
            mRow:SetTall(46)
            mRow.Paint = function(s, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 220))
                surface.SetDrawColor(30, 41, 59, 160)
                surface.DrawOutlinedRect(0, 0, w, h, 1)

                -- Online Status Dot
                local dotCol = m.isOnline and Color(74, 222, 128) or Color(100, 116, 139)
                draw.RoundedBox(4, 12, h / 2 - 4, 8, 8, dotCol)

                -- Member Name & Role
                local nameCol = m.isOnline and Color(248, 250, 252) or Color(148, 163, 184)
                draw.SimpleText(m.name, "GRID_UI_Sub", 28, 14, nameCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(m.job, "GRID_UI_Caption", 28, 32, Color(100, 116, 139), TEXT_ALIGN_LEFT,
                    TEXT_ALIGN_CENTER)

                -- Rank Tag
                local rankText = m.isLeader and "Leader" or "Member"
                local rankCol = m.isLeader and Color(6, 182, 212) or Color(148, 163, 184)
                surface.SetFont("GRID_UI_Badge")
                local rtw = surface.GetTextSize(rankText) + 16
                local rX = (data.isLeader and m.steamid ~= ply:SteamID()) and (w - rtw - 74) or (w - rtw - 12)
                draw.RoundedBox(4, rX, (h - 22) / 2, rtw, 22, Color(rankCol.r, rankCol.g, rankCol.b, 35))
                draw.SimpleText(rankText, "GRID_UI_Badge", rX + rtw / 2, h / 2, rankCol, TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
            end

            -- Kick Button (Leader only, cannot kick self)
            if data.isLeader and m.steamid ~= ply:SteamID() then
                local btnKick = vgui.Create("DButton", mRow)
                btnKick:SetSize(56, 30)
                btnKick:SetPos(colW - 36 - 66, 8)
                btnKick:SetText("")
                btnKick.Paint = function(s, w, h)
                    local bg = s:IsHovered() and Color(239, 68, 68, 240) or Color(185, 28, 28, 190)
                    draw.RoundedBox(4, 0, 0, w, h, bg)
                    draw.SimpleText("Kick", "GRID_UI_Badge", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                end
                btnKick.DoClick = function()
                    Derma_Query("Kick " .. m.name .. " from the gang?", "Confirm Kick", "Kick", function()
                        net.Start("GRID_GangUIAction")
                        net.WriteString("kick")
                        net.WriteString(util.TableToJSON({ steamid = m.steamid }))
                        net.SendToServer()
                    end, "Cancel")
                end
            end
        end

        -- 4. Bottom Danger Zone Action Row
        local bottomRow = scroll:Add("DPanel")
        bottomRow:Dock(TOP)
        bottomRow:DockMargin(0, 0, 0, 16)
        bottomRow:SetTall(46)
        bottomRow.Paint = function() end

        local btnLeave = vgui.Create("DButton", bottomRow)
        btnLeave:SetPos(0, 0)
        btnLeave:SetSize(180, 46)
        btnLeave:SetText("")
        btnLeave.Paint = function(s, w, h)
            local bg = s:IsHovered() and Color(239, 68, 68, 220) or Color(185, 28, 28, 180)
            draw.RoundedBox(6, 0, 0, w, h, bg)
            draw.SimpleText("Leave Gang", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        btnLeave.DoClick = function()
            Derma_Query("Are you sure you want to leave '" .. data.gangName .. "'?", "Leave Gang", "Yes, Leave",
                function()
                    net.Start("GRID_GangUIAction")
                    net.WriteString("leave")
                    net.WriteString("{}")
                    net.SendToServer()
                end, "Cancel")
        end

        if data.isLeader then
            local btnDisband = vgui.Create("DButton", bottomRow)
            btnDisband:SetPos(194, 0)
            btnDisband:SetSize(190, 46)
            btnDisband:SetText("")
            btnDisband.Paint = function(s, w, h)
                local bg = s:IsHovered() and Color(220, 38, 38, 255) or Color(153, 27, 27, 200)
                draw.RoundedBox(6, 0, 0, w, h, bg)
                draw.SimpleText("Disband Gang", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
            end
            btnDisband.DoClick = function()
                Derma_Query(
                    "Are you sure you want to PERMANENTLY disband '" ..
                    data.gangName .. "'? All members will be removed.",
                    "Disband Gang", "Disband Gang", function()
                        net.Start("GRID_GangUIAction")
                        net.WriteString("disband")
                        net.WriteString("{}")
                        net.SendToServer()
                    end, "Cancel")
            end
        end

        -- ========================================================
        -- SCENARIO B: PLAYER IS NOT IN A GANG
        -- ========================================================
    else
        -- If on duty as Police or Civilian: Gangs are disabled
        if not data.isGangFaction then
            local restCard = scroll:Add("DPanel")
            restCard:Dock(TOP)
            restCard:DockMargin(0, 0, 0, 16)
            restCard:SetTall(160)
            restCard.Paint = function(s, w, h)
                draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 220))
                draw.RoundedBoxEx(8, 0, 0, 6, h, Color(239, 68, 68), true, false, true, false)
                surface.SetDrawColor(30, 41, 59, 180)
                surface.DrawOutlinedRect(0, 0, w, h, 1)

                draw.SimpleText("Gang Affiliantions Temporarily Disabled", "GRID_UI_Header", 24, 26, Color(248, 113, 113))
                draw.SimpleText("You are currently employed as " .. data.currentJob .. ".", "GRID_UI_Sub", 24, 58,
                    Color(248, 250, 252))
                draw.SimpleText("Law enforcement officers and neutral civilians cannot participate in street gangs.",
                    "GRID_UI_Caption", 24, 88, Color(148, 163, 184))
                draw.SimpleText("To found or join a gang, switch to any Street Gang role in the Careers tab.",
                    "GRID_UI_Caption", 24, 110, Color(74, 222, 128))
            end

            local btnGoJobs = vgui.Create("DButton", restCard)
            btnGoJobs:SetSize(210, 42)
            btnGoJobs:SetPos(scrollW - 226, 60)
            btnGoJobs:SetText("")
            btnGoJobs.Paint = function(s, w, h)
                local bg = s:IsHovered() and Color(6, 182, 212, 240) or Color(14, 116, 144, 200)
                draw.RoundedBox(6, 0, 0, w, h, bg)
                draw.SimpleText("Open Careers & Jobs", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252),
                    TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
            end
            btnGoJobs.DoClick = function()
                if IsValid(GRID.UI.CurrentContentPanel) then
                    GRID.UI.ActiveF4Tab = "jobs"
                    GRID.UI.CurrentContentPanel:Clear()
                    GRID.UI.RenderContentTab(GRID.UI.CurrentContentPanel, "jobs", mainFrame)
                end
            end
            return
        end

        -- Active Street Gangster: Can found a new gang
        local foundCard = scroll:Add("DPanel")
        foundCard:Dock(TOP)
        foundCard:DockMargin(0, 0, 0, 18)
        foundCard:SetTall(160)
        foundCard.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 220))
            draw.RoundedBoxEx(8, 0, 0, 6, h, Color(245, 158, 11), true, false, true, false)
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText("FOUND A NEW STREET GANG", "GRID_UI_Header", 24, 24, Color(245, 158, 11))
            draw.SimpleText(
                "Establish your own syndicate, conquer territory, collect district taxes, and recruit allies.",
                "GRID_UI_Caption", 24, 52, Color(148, 163, 184))
            draw.SimpleText("Founding Fee: $" .. (data.creationCost or 500) .. " (Deducted from your personal wallet)",
                "GRID_UI_Sub", 24, 118, Color(74, 222, 128))
        end

        local txtGangName = vgui.Create("DTextEntry", foundCard)
        txtGangName:SetPos(24, 76)
        txtGangName:SetSize(scrollW - 260, 38)
        txtGangName:SetPlaceholderText("Enter gang name (2 to 24 characters)...")
        txtGangName:SetFont("GRID_UI_Sub")
        txtGangName.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 220))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            s:DrawTextEntryText(Color(248, 250, 252), Color(6, 182, 212), Color(248, 250, 252))
        end

        local btnFound = vgui.Create("DButton", foundCard)
        btnFound:SetPos(scrollW - 220, 76)
        btnFound:SetSize(200, 38)
        btnFound:SetText("")
        btnFound.Paint = function(s, w, h)
            local bg = s:IsHovered() and Color(245, 158, 11, 240) or Color(217, 119, 6, 200)
            draw.RoundedBox(6, 0, 0, w, h, bg)
            draw.SimpleText("Found Gang ($500)", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        btnFound.DoClick = function()
            local gName = string.Trim(txtGangName:GetText())
            if #gName < 2 then
                GRID.Notify(ply, "Gang name must be at least 2 characters!", NOTIFY_ERROR)
                return
            end
            net.Start("GRID_GangUIAction")
            net.WriteString("create")
            net.WriteString(util.TableToJSON({ name = gName }))
            net.SendToServer()
        end

        -- Active City Gangs Directory
        local dirBanner = scroll:Add("DPanel")
        dirBanner:Dock(TOP)
        dirBanner:DockMargin(0, 0, 0, 10)
        dirBanner:SetTall(42)
        dirBanner.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 200))
            draw.SimpleText("REGISTERED CITY GANGS (" .. #data.cityGangs .. ")", "GRID_UI_Sub", 18, h / 2,
                Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Reach out to gang leaders in-game to request an invite (/invitegang).", "GRID_UI_Caption",
                w - 18, h / 2, Color(148, 163, 184), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        if #data.cityGangs == 0 then
            local noGangs = scroll:Add("DPanel")
            noGangs:Dock(TOP)
            noGangs:SetTall(100)
            noGangs.Paint = function(s, w, h)
                draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 140))
                draw.SimpleText("No gangs currently registered in the city database. Be the first to form one!",
                    "GRID_UI_Sub", w / 2, h / 2, Color(148, 163, 184), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        else
            for _, g in ipairs(data.cityGangs) do
                local gCard = scroll:Add("DPanel")
                gCard:Dock(TOP)
                gCard:DockMargin(0, 0, 0, 8)
                gCard:SetTall(52)
                gCard.Paint = function(s, w, h)
                    local gCol = GRID.GetGangColor(g.name)
                    draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
                    draw.RoundedBoxEx(6, 0, 0, 4, h, gCol, true, false, true, false)
                    surface.SetDrawColor(30, 41, 59, 160)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)

                    draw.SimpleText(g.name, "GRID_UI_Header", 18, 18, Color(248, 250, 252))
                    draw.SimpleText((g.memberCount or 1) .. " Registered Members", "GRID_UI_Caption", 18, 36,
                        Color(148, 163, 184))

                    draw.SimpleText("[*] Respect: " .. string.Comma(g.respect or 0), "GRID_UI_Sub", w - 24, 18,
                        Color(245, 158, 11), TEXT_ALIGN_RIGHT)
                    draw.SimpleText("Vault: $" .. string.Comma(g.bank or 0), "GRID_UI_Caption", w - 24, 36,
                        Color(74, 222, 128), TEXT_ALIGN_RIGHT)
                end
            end
        end
    end
end

-- ==========================================
-- INVENTORY GRID POPULATION
-- ==========================================

function GRID.UI.PopulateInventoryGrid(scroll, mainFrame, searchFilter)
    local ply = LocalPlayer()

    local rows = GRID.Inventory and GRID.Inventory.ClientItems or {}
    local filteredRows = {}

    for _, r in ipairs(rows) do
        local def = GRID.Inventory.GetItemData(r.item_id)
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
            draw.SimpleText("No stored items found.", "GRID_UI_Header", w / 2, h / 2 - 12, Color(148, 163, 184),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("Open your 16-slot Backpack with [B] or interact with items using hands (+USE).",
                "GRID_UI_Caption", w / 2, h / 2 + 16, Color(100, 116, 139), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
        local def = GRID.Inventory.GetItemData(itemId)
        local quality = def.quality or 1
        local qCol = GRID.Inventory.QualityColors and GRID.Inventory.QualityColors[quality] or Color(148, 163, 184)
        local qName = GRID.Inventory.QualityNames and GRID.Inventory.QualityNames[quality] or "Standard"

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
            local fitName = GRID.UI.FitText(def.name, "GRID_UI_Header", contentW - 80)
            draw.SimpleText(fitName, "GRID_UI_Header", contentX, 16, Color(248, 250, 252))

            -- Quality Pill
            surface.SetFont("GRID_UI_Badge")
            local qTextW = surface.GetTextSize(qName) + 16
            draw.RoundedBox(4, w - qTextW - 16, 16, qTextW, 22, Color(qCol.r, qCol.g, qCol.b, 35))
            draw.SimpleText(qName, "GRID_UI_Badge", w - 16 - qTextW / 2, 27, qCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            -- Amount / SubType
            local subInfo = string.format("Quantity: %dx  -  %s", amount, def.subType or "Asset")
            draw.SimpleText(subInfo, "GRID_UI_Sub", contentX, 48, Color(74, 222, 128))

            -- Stats / Description
            local metaStr = def.stats or def.desc or ""
            local lines = GRID.UI.WrapText(metaStr, "GRID_UI_Caption", contentW)
            for i = 1, math.min(#lines, 2) do
                draw.SimpleText(lines[i], "GRID_UI_Caption", contentX, 76 + (i - 1) * 18, Color(148, 163, 184))
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

        -- Action Buttons
        local btnY = cardH - 48

        local btnDrop = vgui.Create("DButton", card)
        btnDrop:SetSize(110, 36)
        btnDrop:SetPos(cardW - 124, btnY)
        btnDrop:SetText("")
        btnDrop.Paint = function(s, w, h)
            local bg = s:IsHovered() and Color(239, 68, 68, 240) or Color(185, 28, 28, 190)
            draw.RoundedBox(6, 0, 0, w, h, bg)
            draw.SimpleText("Drop", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        btnDrop.DoClick = function()
            GRID.Inventory.DropItem(rowId)
        end

        if itemType == "weapon" then
            local btnEquip = vgui.Create("DButton", card)
            btnEquip:SetSize(110, 36)
            btnEquip:SetPos(cardW - 242, btnY)
            btnEquip:SetText("")
            btnEquip.Paint = function(s, w, h)
                local bg = s:IsHovered() and Color(16, 185, 129, 240) or Color(5, 150, 105, 190)
                draw.RoundedBox(6, 0, 0, w, h, bg)
                draw.SimpleText("Equip", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
            end
            btnEquip.DoClick = function()
                GRID.Inventory.UseItem(rowId)
            end
        end
    end
end

-- ==========================================
-- GRID POPULATION (JOBS & STORE CATALOG)
-- ==========================================

function GRID.UI.PopulateGrid(scroll, tabId, mainFrame, searchFilter)
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
                title = "STREET GANGS",
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

        local catCounts = { neutral = 0, gang = 0, police = 0 }
        for _, job in pairs(GRID.Jobs or {}) do
            local fId = (job.faction and job.faction.id) or "neutral"
            if catCounts[fId] ~= nil then
                catCounts[fId] = catCounts[fId] + 1
            end
        end

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
            { id = "all",     label = "All Roles (" .. table.Count(GRID.Jobs or {}) .. ")", color = Color(6, 182, 212) },
            { id = "neutral", label = "Civilians (" .. catCounts.neutral .. ")",            color = Color(148, 163, 184) },
            { id = "gang",    label = "Street Gangs (" .. catCounts.gang .. ")",            color = Color(245, 158, 11) },
            { id = "police",  label = "Police (" .. catCounts.police .. ")",                color = Color(16, 185, 129) }
        }

        local btnX = 8
        for _, fBtn in ipairs(filterButtons) do
            surface.SetFont("GRID_UI_Btn")
            local tw = surface.GetTextSize(fBtn.label) + 28
            local b = vgui.Create("DButton", filterBar)
            b:SetPos(btnX, 6)
            b:SetSize(tw, 34)
            b:SetText("")

            b.Paint = function(s, bw, bh)
                local isCur = (GRID.UI.ActiveJobCategory == fBtn.id)
                local bg = isCur and Color(fBtn.color.r, fBtn.color.g, fBtn.color.b, 45) or
                    (s:IsHovered() and Color(30, 41, 59, 200) or Color(11, 15, 25, 140))
                draw.RoundedBox(6, 0, 0, bw, bh, bg)

                surface.SetDrawColor(isCur and fBtn.color.r or 51, isCur and fBtn.color.g or 65,
                    isCur and fBtn.color.b or 85, isCur and 220 or 120)
                surface.DrawOutlinedRect(0, 0, bw, bh, 1)

                local textCol = isCur and fBtn.color or (s:IsHovered() and Color(248, 250, 252) or Color(148, 163, 184))
                draw.SimpleText(fBtn.label, "GRID_UI_Btn", bw / 2, bh / 2, textCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            b.DoClick = function()
                GRID.UI.ActiveJobCategory = fBtn.id
                scroll:Clear()
                GRID.UI.PopulateGrid(scroll, "jobs", mainFrame, searchFilter)
            end

            btnX = btnX + tw + 8
        end

        local cardW = (scroll:GetWide() - 28) / 2

        for _, cat in ipairs(categories) do
            if GRID.UI.ActiveJobCategory == "all" or GRID.UI.ActiveJobCategory == cat.id then
                local catJobs = {}
                local catActivePlayers = 0

                for jobId, job in pairs(GRID.Jobs or {}) do
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

                    local banner = scroll:Add("DPanel")
                    banner:Dock(TOP)
                    banner:DockMargin(0, 0, 0, 10)
                    banner:SetTall(48)
                    banner.Paint = function(s, w, h)
                        draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 240))
                        draw.RoundedBoxEx(8, 0, 0, 4, h, cat.color, true, false, true, false)
                        surface.SetDrawColor(30, 41, 59, 180)
                        surface.DrawOutlinedRect(0, 0, w, h, 1)

                        draw.SimpleText(cat.title, "GRID_UI_Sub", 18, 14, cat.color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        draw.SimpleText(cat.desc, "GRID_UI_Caption", 18, 33, Color(148, 163, 184), TEXT_ALIGN_LEFT,
                            TEXT_ALIGN_CENTER)

                        local actText = #catJobs .. " Roles  -  " .. catActivePlayers .. " Active Players"
                        surface.SetFont("GRID_UI_Badge")
                        local tw = surface.GetTextSize(actText) + 20
                        draw.RoundedBox(4, w - tw - 16, 12, tw, 24, Color(cat.color.r, cat.color.g, cat.color.b, 35))
                        surface.SetDrawColor(cat.color.r, cat.color.g, cat.color.b, 120)
                        surface.DrawOutlinedRect(w - tw - 16, 12, tw, 24, 1)
                        draw.SimpleText(actText, "GRID_UI_Badge", w - 16 - tw / 2, 24, cat.color, TEXT_ALIGN_CENTER,
                            TEXT_ALIGN_CENTER)
                    end

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

                        local fCol = (job.faction and job.faction.color) or GRID.Colors.White
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

                            -- Faction Pill
                            local fName = job.faction and job.faction.name or "Civilian"
                            surface.SetFont("GRID_UI_Badge")
                            local badgeW = surface.GetTextSize(fName) + 20
                            draw.RoundedBox(4, 138, 14, badgeW, 22, Color(fCol.r, fCol.g, fCol.b, 35))
                            draw.SimpleText(fName, "GRID_UI_Badge", 138 + badgeW / 2, 25, fCol, TEXT_ALIGN_CENTER,
                                TEXT_ALIGN_CENTER)

                            -- Slot Availability Pill
                            surface.SetFont("GRID_UI_Badge")
                            local slotW = surface.GetTextSize(slotText) + 18
                            local slotX = cardW - 16 - slotW
                            draw.RoundedBox(4, slotX, 14, slotW, 22, Color(slotCol.r, slotCol.g, slotCol.b, 35))
                            surface.SetDrawColor(slotCol.r, slotCol.g, slotCol.b, 90)
                            surface.DrawOutlinedRect(slotX, 14, slotW, 22, 1)
                            draw.SimpleText(slotText, "GRID_UI_Badge", slotX + slotW / 2, 25, slotCol, TEXT_ALIGN_CENTER,
                                TEXT_ALIGN_CENTER)

                            -- Job Name
                            local cleanJobName = GRID.UI.FitText(job.name, "GRID_UI_Header", maxTextW)
                            draw.SimpleText(cleanJobName, "GRID_UI_Header", 138, 42, Color(248, 250, 252))

                            -- Stats Line
                            local statsText = "Salary: +$" .. (job.salary or 45) .. " / 90s"
                            if (job.armor or 0) > 0 then
                                statsText = statsText .. "   |   Armor: " .. job.armor .. "%"
                            end
                            if job.runSpeed then
                                statsText = statsText .. "   |   Sprint: " .. job.runSpeed
                            end
                            draw.SimpleText(statsText, "GRID_UI_Sub", 138, 72, Color(74, 222, 128))

                            -- Description
                            local descLines = GRID.UI.WrapText(job.desc or "", "GRID_UI_Caption", maxTextW)
                            for i = 1, math.min(#descLines, 3) do
                                draw.SimpleText(descLines[i], "GRID_UI_Caption", 138, 98 + (i - 1) * 20,
                                    Color(148, 163, 184))
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
                            local btnCol = isMyJob and Color(30, 41, 59, 200) or
                                (not hasJobLvl and Color(51, 65, 85, 180) or (isFull and Color(51, 65, 85, 180) or (s:IsHovered() and Color(6, 182, 212, 240) or Color(14, 116, 144, 200))))
                            draw.RoundedBox(6, 0, 0, w, h, btnCol)
                            local rawText = isMyJob and "Current Active Role" or
                                (not hasJobLvl and ("Requires Level " .. reqJobLvl) or (isFull and ("Role Full (" .. currentCount .. "/" .. maxSlots .. ")") or ("Enlist as " .. job.name)))
                            local fitBtnText = GRID.UI.FitText(rawText, "GRID_UI_Btn", w - 20)
                            draw.SimpleText(fitBtnText, "GRID_UI_Btn", w / 2, h / 2,
                                (not hasJobLvl or (isFull and not isMyJob)) and Color(156, 163, 175) or
                                Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                        end

                        btnEnlist.DoClick = function()
                            if isMyJob then return end
                            if not hasJobLvl then
                                GRID.Notify(ply,
                                    string.format("You must be Level %d to become a %s!", reqJobLvl, job.name),
                                    NOTIFY_ERROR)
                                surface.PlaySound("buttons/button10.wav")
                                return
                            end
                            if isFull then
                                GRID.Notify(ply, "That role is currently at capacity!", NOTIFY_ERROR)
                                surface.PlaySound("buttons/button10.wav")
                                return
                            end

                            net.Start("GRID_ChangeJob")
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
        for itemId, item in pairs(GRID.ShopItems or {}) do
            if tabId == "weapons" and (item.category == "networking" or item.category == "supplies" or (item.type ~= "weapon" and item.type ~= "ammo")) then continue end
            if tabId == "shipments" and item.type ~= "shipment" then continue end
            if tabId == "entities" and (item.category ~= "printers" or item.debug or string.StartWith(itemId, "debug_")) then continue end
            if tabId == "supplies" and (item.category ~= "supplies" and item.type ~= "armor" and item.type ~= "medkit" and item.type ~= "consumable") then continue end
            if tabId == "networking" and item.category ~= "networking" then continue end
            if (tabId == "debug_buffs" or tabId == "buffs") and not (item.debug or string.StartWith(itemId, "debug_") or item.type == "buff" or item.type == "cleanse") then continue end

            if searchFilter ~= "" and not string.find(string.lower(item.name), searchFilter, 1, true) then
                continue
            end

            local effectiveCost = GRID.GetItemCost(item, ply)
            local reqItemLevel = item.level or 1
            local canBuyLevel = (myLevel >= reqItemLevel)
            local canAfford = (myMoney >= effectiveCost)

            local hasJobReq = (item.jobs ~= nil) or (item.job ~= nil)
            local canBuyJob = true
            local reqJobName = ""
            if item.jobs then
                canBuyJob = table.HasValue(item.jobs, plyJob)
                local names = {}
                for _, jId in ipairs(item.jobs) do
                    local jData = GRID.Jobs[jId]
                    if jData then table.insert(names, jData.name) end
                end
                reqJobName = table.concat(names, " / ")
            elseif item.job then
                canBuyJob = (plyJob == item.job)
                local jData = GRID.Jobs[item.job]
                reqJobName = jData and jData.name or item.job
            end

            local isPoliceProhibited = isPolice and
                (item.category == "printers" or item.isContraband or item.type == "shipment" or (item.jobs and table.HasValue(item.jobs, "black_market_dealer")) or (item.jobs and table.HasValue(item.jobs, "thief")))
            local isHoboProhibited = isHobo

            local isLocked = (not canBuyJob) or (not canBuyLevel) or isPoliceProhibited or isHoboProhibited

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
                local cardBg = isLocked and Color(14, 18, 27, 210) or
                    (isHover and Color(24, 32, 47, 240) or Color(17, 24, 39, 200))
                draw.RoundedBox(8, 0, 0, w, h, cardBg)
                surface.SetDrawColor(isLocked and Color(51, 65, 85, 140) or Color(30, 41, 59, 180))
                surface.DrawOutlinedRect(0, 0, w, h, 1)

                -- Item Type Pill
                local isItemDebuff = (item.isDebuff or (item.buffId and GRID.Buffs and GRID.Buffs.Registry and GRID.Buffs.Registry[item.buffId] and GRID.Buffs.Registry[item.buffId].isDebuff) or string.find(string.lower(item.name), "debuff", 1, true))
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
                draw.SimpleText(pLabel, "GRID_UI_Badge", 56, 27, pCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

                -- Item Name
                local fitItemName = GRID.UI.FitText(item.name, "GRID_UI_Header", cardW - 116)
                draw.SimpleText(fitItemName, "GRID_UI_Header", 108, 14, Color(248, 250, 252))

                -- Dynamic Price Tag
                local priceStr = (effectiveCost == 0) and "FREE" or ("$" .. string.Comma(effectiveCost))
                draw.SimpleText(priceStr, "GRID_UI_Price", 18, 54, Color(74, 222, 128))

                -- Wholesale Badge vs 200%-300% Markup Pill
                local isWholesaleActive = (item.wholesaleCost and effectiveCost <= item.wholesaleCost)
                surface.SetFont("GRID_UI_Price")
                local pw, _ = surface.GetTextSize(priceStr)
                local badgeX = 18 + pw + 12
                local badgeY = 56
                local badgeH = 22

                if isWholesaleActive then
                    surface.SetFont("GRID_UI_Badge")
                    local wText = "Wholesale Direct Price"
                    local mw, _ = surface.GetTextSize(wText)
                    local badgeW = mw + 16
                    draw.RoundedBox(4, badgeX, badgeY, badgeW, badgeH, Color(16, 185, 129, 35))
                    surface.SetDrawColor(16, 185, 129, 140)
                    surface.DrawOutlinedRect(badgeX, badgeY, badgeW, badgeH, 1)
                    draw.SimpleText(wText, "GRID_UI_Badge", badgeX + badgeW / 2, badgeY + badgeH / 2, Color(52, 211, 153),
                        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                else
                    local markupPct = GRID.GetItemMarkupPercent and GRID.GetItemMarkupPercent(item, ply)
                    if markupPct and markupPct > 0 then
                        surface.SetFont("GRID_UI_Badge")
                        local markupTxt = "+" .. markupPct .. "% Shop Markup"
                        local mw, _ = surface.GetTextSize(markupTxt)
                        local badgeW = mw + 16
                        draw.RoundedBox(4, badgeX, badgeY, badgeW, badgeH, Color(245, 158, 11, 40))
                        surface.SetDrawColor(245, 158, 11, 140)
                        surface.DrawOutlinedRect(badgeX, badgeY, badgeW, badgeH, 1)
                        draw.SimpleText(markupTxt, "GRID_UI_Badge", badgeX + badgeW / 2, badgeY + badgeH / 2,
                            Color(251, 191, 36), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                end

                -- Persistent Job & Level Prerequisite Pill
                local hasLevelReq = (reqItemLevel and reqItemLevel > 1)
                if isHoboProhibited then
                    draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(239, 68, 68, 30))
                    surface.SetDrawColor(239, 68, 68, 90)
                    surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                    draw.SimpleText("Hobos Cannot Buy Items", "GRID_UI_Caption", cardW - 114, 64, Color(248, 113, 113),
                        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                elseif isPoliceProhibited then
                    draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(239, 68, 68, 30))
                    surface.SetDrawColor(239, 68, 68, 90)
                    surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                    draw.SimpleText("Prohibited for Law Enforcement", "GRID_UI_Caption", cardW - 114, 64,
                        Color(248, 113, 113), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                elseif hasJobReq then
                    if canBuyJob then
                        local checkText = (hasLevelReq and canBuyLevel) and
                            ("[OK] " .. reqJobName .. " (LVL " .. reqItemLevel .. "+)") or ("[OK] Requires: " .. reqJobName)
                        draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(16, 185, 129, 35))
                        surface.SetDrawColor(16, 185, 129, 140)
                        surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                        local fitCheck = GRID.UI.FitText(checkText, "GRID_UI_Caption", 186)
                        draw.SimpleText(fitCheck, "GRID_UI_Caption", cardW - 114, 64, Color(52, 211, 153),
                            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    else
                        local lockTag = "Requires: " .. reqJobName
                        draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(239, 68, 68, 30))
                        surface.SetDrawColor(239, 68, 68, 90)
                        surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                        local fitLock = GRID.UI.FitText(lockTag, "GRID_UI_Caption", 186)
                        draw.SimpleText(fitLock, "GRID_UI_Caption", cardW - 114, 64, Color(248, 113, 113),
                            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                elseif hasLevelReq then
                    if canBuyLevel then
                        draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(16, 185, 129, 35))
                        surface.SetDrawColor(16, 185, 129, 140)
                        surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                        draw.SimpleText("[OK] Level " .. reqItemLevel .. " Unlocked", "GRID_UI_Caption", cardW - 114, 64,
                            Color(52, 211, 153), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    else
                        draw.RoundedBox(4, cardW - 214, 52, 200, 24, Color(245, 158, 11, 40))
                        surface.SetDrawColor(245, 158, 11, 140)
                        surface.DrawOutlinedRect(cardW - 214, 52, 200, 24, 1)
                        draw.SimpleText("Requires Level " .. reqItemLevel, "GRID_UI_Caption", cardW - 114, 64,
                            Color(251, 191, 36), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                end

                -- Item Description
                local subText = item.desc or ""
                if subText ~= "" then
                    local subLines = GRID.UI.WrapText(subText, "GRID_UI_Caption", leftContentW)
                    for i = 1, math.min(#subLines, 2) do
                        draw.SimpleText(subLines[i], "GRID_UI_Caption", 18, 96 + (i - 1) * 18, Color(148, 163, 184))
                    end
                end

                -- Savings Tip for Non-Specialists
                if not isWholesaleActive and item.markupRole then
                    local tipText = "[*] Tip: Buy from a " .. item.markupRole .. " to avoid this markup!"
                    local fitTip = GRID.UI.FitText(tipText, "GRID_UI_Caption", leftContentW)
                    draw.SimpleText(fitTip, "GRID_UI_Caption", 18, 134, Color(251, 191, 36, 200))
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
                local text = (effectiveCost == 0) and "Apply (Free)" or
                    ("Purchase ($" .. string.Comma(effectiveCost) .. ")")
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
                local fitBtnText = GRID.UI.FitText(text, "GRID_UI_Btn", w - 16)
                draw.SimpleText(fitBtnText, "GRID_UI_Btn", w / 2, h / 2,
                    isLocked and Color(156, 163, 175) or Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            btnBuy.DoClick = function()
                if isHoboProhibited then
                    GRID.Notify(ply, "Hobos cannot purchase items! You can only use building tools.", NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                if isPoliceProhibited then
                    GRID.Notify(ply, "Police officers cannot purchase printers or contraband!", NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                if not canBuyLevel and not canBuyJob then
                    GRID.Notify(ply,
                        string.format("You must be Level %d and employed as %s to purchase this!", reqItemLevel,
                            reqJobName ~= "" and reqJobName or "Specialist"), NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                if not canBuyLevel then
                    GRID.Notify(ply, string.format("You must be Level %d to purchase this item!", reqItemLevel),
                        NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                if not canBuyJob then
                    GRID.Notify(ply, "Requires employment as: " .. (reqJobName ~= "" and reqJobName or "Specialist"),
                        NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end
                if not canAfford then
                    GRID.Notify(ply, "You cannot afford this item ($" .. effectiveCost .. ")!", NOTIFY_ERROR)
                    surface.PlaySound("buttons/button10.wav")
                    return
                end

                net.Start("GRID_BuyItem")
                net.WriteString(itemId)
                net.SendToServer()
            end
        end
    end
end

-- ==========================================
-- RULES TAB (SOPHISTICATED ACCORDION WITH WORD WRAP)
-- ==========================================

function GRID.UI.RenderRulesContent(scroll)
    local rules = {
        {
            num = "01",
            title = "Turf Warfare & Sovereign Territory",
            desc =
            "All city districts marked with holographic beacons are contested turf. Gang members and law enforcement may capture territory by interacting with the flag pole (E). Controlled turfs yield recurring dividends directly into active member wallets.",
            accent = Color(6, 182, 212)
        },
        {
            num = "02",
            title = "Money Printers & Police Raids",
            desc =
            "Money printers generate recurring passive cash revenue. Maintain internal temperatures below 100C using E to prevent explosions. Police officers are authorized to raid bases and seize printers for instant cash bounties.",
            accent = Color(245, 158, 11)
        },
        {
            num = "03",
            title = "Non-RDM & Rules of Engagement",
            desc =
            "Random Deathmatch (RDM) is strictly prohibited. You must have legitimate in-character hostile roleplay provocation or ongoing turf warfare combat to initiate lethal firearm violence.",
            accent = Color(239, 68, 68)
        },
        {
            num = "04",
            title = "Base Architecture & Prop Security",
            desc =
            "Base fortifications must not completely block public highways, sidewalk thoroughfares, or flag pole capture perimeters. All bases must feature clear, navigable keycard or door access points.",
            accent = Color(16, 185, 129)
        },
        {
            num = "05",
            title = "New Life Rule (NLR) & Return Limits",
            desc =
            "Upon death, you forget all immediate memories leading up to your demise. You may not return to your location of death for at least 3 minutes, nor may you seek revenge against your killer.",
            accent = Color(168, 85, 247)
        }
    }

    local scrollW = scroll:GetWide() - 32
    for _, r in ipairs(rules) do
        local maxTextW = math.max(scrollW - 100, 400)
        local lines = GRID.UI.WrapText(r.desc, "GRID_UI_Body", maxTextW)
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

            draw.RoundedBox(4, 18, 16, 44, 34, Color(r.accent.r, r.accent.g, r.accent.b, 35))
            draw.SimpleText(r.num, "GRID_UI_Header", 40, 33, r.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            draw.SimpleText(r.title, "GRID_UI_Header", 76, 33, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            for i, line in ipairs(lines) do
                draw.SimpleText(line, "GRID_UI_Body", 76, 62 + (i - 1) * 24, Color(148, 163, 184))
            end
        end
    end
end

-- ==========================================
-- POLICE DISPATCH & WARRANT MANAGEMENT TAB
-- ==========================================

function GRID.UI.RenderPoliceDispatchContent(scroll, mainFrame)
    local ply = LocalPlayer()
    local isMayor = IsValid(ply) and (ply.GetJob and ply:GetJob() == "mayor")

    local scrollW = scroll:GetWide() - 32
    local totalH = math.max(scroll:GetTall() - 20, 520)

    local container = scroll:Add("DPanel")
    container:Dock(TOP)
    container:SetTall(totalH)
    container.Paint = function() end

    -- Top Header Card
    local headerCard = vgui.Create("DPanel", container)
    headerCard:SetPos(0, 0)
    headerCard:SetSize(scrollW, 64)
    headerCard.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 230))
        local accent = isMayor and Color(245, 158, 11) or Color(6, 182, 212)
        draw.RoundedBoxEx(8, 0, 0, w, 3, accent, true, true, false, false)
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        local title = isMayor and "MAYOR EXECUTIVE WARRANT BUREAU" or "LSPD TACTICAL DISPATCH & WARRANTS"
        local sub = isMayor and "Issue immediate executive search & arrest warrants on metropolitan suspects." or
            "Submit suspect warrants for departmental majority vote or track active fugitives."
        draw.SimpleText(title, "GRID_UI_Header", 16, 14, Color(248, 250, 252))
        draw.SimpleText(sub, "GRID_UI_Caption", 16, 38, Color(148, 163, 184))
    end

    -- Citywide Lockdown Status & Control Banner
    local lockdownCard = vgui.Create("DPanel", container)
    lockdownCard:SetPos(0, 72)
    lockdownCard:SetSize(scrollW, 52)
    lockdownCard.Paint = function(s, w, h)
        local isLockdown = GRID.Turf and GRID.Turf.IsLockdownActive and GRID.Turf.IsLockdownActive()
        local bg = isLockdown and Color(35, 15, 20, 240) or Color(17, 24, 39, 230)
        local border = isLockdown and Color(239, 68, 68, 220) or Color(30, 41, 59, 180)
        draw.RoundedBox(8, 0, 0, w, h, bg)
        surface.SetDrawColor(border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        if isLockdown then
            local pulse = math.abs(math.sin(CurTime() * 4))
            local pulseCol = Color(239, 68, 68, math.floor(180 + 75 * pulse))
            draw.RoundedBoxEx(4, 0, 0, w, 3, pulseCol, true, true, false, false)
            draw.SimpleText("[!] MARTIAL LAW LOCKDOWN IN EFFECT", "GRID_UI_Header", 16, 8, pulseCol)
            draw.SimpleText("Warrantless arrests & taser compliance authorized against all non-police citizens until a zone is captured.", "GRID_UI_Caption", 16, 30, Color(248, 250, 252))
        else
            local gangCount, totalCount, allControlled = 0, 0, false
            if GRID.Turf and GRID.Turf.GetGangControlStats then
                gangCount, totalCount, allControlled = GRID.Turf.GetGangControlStats()
            end
            local statCol = allControlled and Color(52, 211, 153) or Color(245, 158, 11)
            local statusTxt = allControlled and
                string.format("Street Gang Territory Control: %d/%d (100%%) - LOCKDOWN READY", gangCount, totalCount) or
                string.format("Street Gang Territory Control: %d/%d (%d%%) - Requires 100%% gang control to declare martial law", gangCount, totalCount, totalCount > 0 and math.floor((gangCount / totalCount) * 100) or 0)

            draw.SimpleText("CITYWIDE LOCKDOWN PROTOCOL", "GRID_UI_Badge", 16, 8, statCol)
            draw.SimpleText(statusTxt, "GRID_UI_Caption", 16, 28, Color(203, 213, 225))
        end
    end

    if isMayor then
        local btnLockdown = vgui.Create("DButton", lockdownCard)
        btnLockdown:SetSize(220, 36)
        btnLockdown:SetPos(scrollW - 232, 8)
        btnLockdown:SetText("")
        btnLockdown.Paint = function(s, w, h)
            local isLockdown = GRID.Turf and GRID.Turf.IsLockdownActive and GRID.Turf.IsLockdownActive()
            local gangCount, totalCount, allControlled = 0, 0, false
            if GRID.Turf and GRID.Turf.GetGangControlStats then
                gangCount, totalCount, allControlled = GRID.Turf.GetGangControlStats()
            end

            if isLockdown then
                local bg = s:IsHovered() and Color(239, 68, 68, 240) or Color(185, 28, 28, 200)
                draw.RoundedBox(6, 0, 0, w, h, bg)
                draw.SimpleText("LIFT CITYWIDE LOCKDOWN", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            elseif allControlled then
                local bg = s:IsHovered() and Color(245, 158, 11, 240) or Color(217, 119, 6, 200)
                draw.RoundedBox(6, 0, 0, w, h, bg)
                draw.SimpleText("INITIATE LOCKDOWN", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                draw.RoundedBox(6, 0, 0, w, h, Color(30, 41, 59, 140))
                draw.SimpleText("LOCKDOWN UNAVAILABLE", "GRID_UI_Btn", w / 2, h / 2, Color(100, 116, 139), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
        btnLockdown.DoClick = function()
            local isLockdown = GRID.Turf and GRID.Turf.IsLockdownActive and GRID.Turf.IsLockdownActive()
            net.Start("GRID_TurfLockdownAction")
            net.WriteString(isLockdown and "lift" or "initiate")
            net.SendToServer()
        end
    end

    local bodyY = 132
    local bodyH = totalH - bodyY
    local leftW = math.floor(scrollW * 0.44)
    local rightW = scrollW - leftW - 16

    -- Left: Suspect List Panel
    local leftPanel = vgui.Create("DPanel", container)
    leftPanel:SetPos(0, bodyY)
    leftPanel:SetSize(leftW, bodyH)
    leftPanel.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local txtSearch = vgui.Create("DTextEntry", leftPanel)
    txtSearch:SetPos(10, 10)
    txtSearch:SetSize(leftW - 20, 32)
    txtSearch:SetPlaceholderText("Search online citizens...")
    txtSearch:SetFont("GRID_UI_Body")

    local suspectList = vgui.Create("DListView", leftPanel)
    suspectList:SetPos(10, 48)
    suspectList:SetSize(leftW - 20, bodyH - 58)
    suspectList:SetMultiSelect(false)
    suspectList:AddColumn("Citizen Name"):SetFixedWidth(math.floor((leftW - 20) * 0.48))
    suspectList:AddColumn("Occupation"):SetFixedWidth(math.floor((leftW - 20) * 0.32))
    suspectList:AddColumn("Status"):SetFixedWidth(math.floor((leftW - 20) * 0.20))

    -- Right: Details & Action Panel
    local rightPanel = vgui.Create("DPanel", container)
    rightPanel:SetPos(leftW + 16, bodyY)
    rightPanel:SetSize(rightW, bodyH)
    rightPanel.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local selectedPlayer = nil

    local function PopulateSuspects(filter)
        suspectList:Clear()
        for _, p in ipairs(player.GetAll()) do
            if not IsValid(p) or p == ply then continue end
            local nick = p:Nick()
            if filter and filter ~= "" and not string.find(string.lower(nick), string.lower(filter), 1, true) then
                continue
            end
            local job = p:GetJobData()
            local status = p:IsWanted() and "WANTED" or "Clean"
            local line = suspectList:AddLine(nick, job and job.name or "Citizen", status)
            line.Player = p
        end
    end

    local function RefreshActionPanel()
        rightPanel:Clear()

        if not IsValid(selectedPlayer) then
            local lbl = vgui.Create("DLabel", rightPanel)
            lbl:Dock(FILL)
            lbl:SetText("Select an online citizen to view profile, issue a warrant, or call a department vote.")
            lbl:SetFont("GRID_UI_Body")
            lbl:SetContentAlignment(5)
            lbl:SetTextColor(Color(148, 163, 184))
            return
        end

        local pNick = selectedPlayer:Nick()
        local pJob = selectedPlayer:GetJobData()
        local isWanted = selectedPlayer:IsWanted()

        local details = vgui.Create("DPanel", rightPanel)
        details:SetPos(16, 16)
        details:SetSize(rightW - 32, 90)
        details.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(15, 23, 42, 220))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText(pNick, "GRID_UI_Header", 16, 14, Color(248, 250, 252))
            draw.SimpleText(string.format("Role: %s  |  Level: %d", pJob and pJob.name or "Citizen", selectedPlayer:GetLevel()), "GRID_UI_Body", 16, 42, Color(148, 163, 184))

            local statText = isWanted and "[*] WANTED SUSPECT" or "Clean Record"
            local statCol = isWanted and Color(239, 68, 68) or Color(52, 211, 153)
            draw.SimpleText(statText, "GRID_UI_Badge", w - 16, 16, statCol, TEXT_ALIGN_RIGHT)
        end

        if isWanted then
            -- Revoke wanted button
            local btnRevoke = vgui.Create("DButton", rightPanel)
            btnRevoke:SetPos(16, 120)
            btnRevoke:SetSize(rightW - 32, 42)
            btnRevoke:SetText("")
            btnRevoke.Paint = function(s, w, h)
                local bg = s:IsHovered() and Color(239, 68, 68, 240) or Color(185, 28, 28, 200)
                draw.RoundedBox(6, 0, 0, w, h, bg)
                draw.SimpleText("Revoke Wanted Status", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            btnRevoke.DoClick = function()
                LocalPlayer():ConCommand("say /unwanted " .. pNick)
                timer.Simple(0.3, function()
                    PopulateSuspects(txtSearch:GetText())
                    RefreshActionPanel()
                end)
            end
        else
            -- Issue warrant form
            local lblReason = vgui.Create("DLabel", rightPanel)
            lblReason:SetPos(16, 116)
            lblReason:SetSize(rightW - 32, 22)
            lblReason:SetText("Warrant Justification / Criminal Charge:")
            lblReason:SetFont("GRID_UI_BodyBold")
            lblReason:SetTextColor(Color(248, 250, 252))

            local txtReason = vgui.Create("DTextEntry", rightPanel)
            txtReason:SetPos(16, 142)
            txtReason:SetSize(rightW - 32, 36)
            txtReason:SetFont("GRID_UI_Body")
            txtReason:SetPlaceholderText("Enter justification (e.g. Armed Robbery, Assault, Evading Police)...")

            local btnAction = vgui.Create("DButton", rightPanel)
            btnAction:SetPos(16, 190)
            btnAction:SetSize(rightW - 32, 44)
            btnAction:SetText("")
            btnAction.Paint = function(s, w, h)
                local btnCol = isMayor and (s:IsHovered() and Color(245, 158, 11, 240) or Color(217, 119, 6, 200)) or
                    (s:IsHovered() and Color(6, 182, 212, 240) or Color(14, 116, 144, 200))
                draw.RoundedBox(6, 0, 0, w, h, btnCol)
                local btnText = isMayor and "Issue Instant Executive Warrant" or "Call Department Warrant Vote"
                draw.SimpleText(btnText, "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            btnAction.DoClick = function()
                local reason = txtReason:GetText()
                if not reason or string.Trim(reason) == "" then
                    reason = "Evading Law Enforcement"
                end
                if isMayor then
                    LocalPlayer():ConCommand(string.format("say /wanted %s %s", pNick, reason))
                else
                    LocalPlayer():ConCommand(string.format("say /votewanted %s %s", pNick, reason))
                end

                timer.Simple(0.3, function()
                    PopulateSuspects(txtSearch:GetText())
                    RefreshActionPanel()
                end)
            end

            -- Instructions note
            local note = vgui.Create("DPanel", rightPanel)
            note:SetPos(16, 250)
            note:SetSize(rightW - 32, bodyH - 266)
            note.Paint = function(s, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(15, 23, 42, 200))
                surface.SetDrawColor(30, 41, 59, 180)
                surface.DrawOutlinedRect(0, 0, w, h, 1)

                draw.SimpleText("PROCEDURAL PROTOCOL", "GRID_UI_Badge", 16, 16, Color(56, 189, 248))
                local msg = isMayor and
                    "The Mayor holds executive authority to unilaterally authorize arrest warrants. Suspects become subject to immediate apprehension and tasing." or
                    "Calling a warrant vote broadcasts a 30-second notification card to all active police officers. A majority (>50%) vote confirms the warrant."
                local wrapped = GRID.UI.WrapText(msg, "GRID_UI_Caption", w - 32)
                for idx, ln in ipairs(wrapped) do
                    draw.SimpleText(ln, "GRID_UI_Caption", 16, 40 + (idx - 1) * 20, Color(203, 213, 225))
                end
            end
        end
    end

    suspectList.OnRowSelected = function(s, rowIndex, row)
        selectedPlayer = row.Player
        RefreshActionPanel()
    end

    txtSearch.OnChange = function(s)
        PopulateSuspects(s:GetText())
    end

    PopulateSuspects("")
    RefreshActionPanel()
end
