--[[
    cl_auction.lua - High-Legibility Two-Tier Tree Auction House UI & Client Engine
    Author: Juicebox & Antigravity
    Namespace: GRID / GRID.Auction
--]]

GRID = GRID or {}
GRID.Auction = GRID.Auction or {}

GRID.Auction.Listings = {}
GRID.Auction.Metrics = {}
GRID.Auction.Collection = {}
GRID.Auction.IsTerminalSession = false
GRID.Auction.SelectedBaseItem = nil
GRID.Auction.ActiveTab = "browse" -- "browse", "create", "mylistings", "collection"
GRID.Auction.SearchQuery = ""
GRID.Auction.MainFrame = nil

-- --------------------------------------------------------
-- 1. Network Receivers
-- --------------------------------------------------------

net.Receive("GRID_Auction_OpenTerminal", function()
    GRID.Auction.IsTerminalSession = true
    GRID.Auction.OpenUI(true)
end)

net.Receive("GRID_Auction_OpenRemote", function()
    GRID.Auction.IsTerminalSession = false
    GRID.Auction.OpenUI(false)
end)

net.Receive("GRID_Auction_SendListings", function()
    local count = net.ReadUInt(16)
    local list = {}
    for i = 1, count do
        table.insert(list, {
            auction_id = net.ReadUInt(32),
            seller_steamid = net.ReadString(),
            seller_name = net.ReadString(),
            item_id = net.ReadString(),
            item_type = net.ReadString(),
            amount = net.ReadUInt(16),
            item_data = net.ReadString(),
            start_bid = net.ReadUInt(32),
            current_bid = net.ReadUInt(32),
            high_bidder_name = net.ReadString(),
            buyout_price = net.ReadUInt(32),
            expires_at_unix = net.ReadUInt(32)
        })
    end
    GRID.Auction.Listings = list

    if IsValid(GRID.Auction.MainFrame) and GRID.Auction.RefreshCurrentTab then
        GRID.Auction.RefreshCurrentTab()
    end
end)

net.Receive("GRID_Auction_SendMetrics", function()
    local count = net.ReadUInt(16)
    local metrics = {}
    for i = 1, count do
        local id = net.ReadString()
        metrics[id] = {
            min_buyout = net.ReadUInt(32),
            active_count = net.ReadUInt(16),
            avg_7d = net.ReadUInt(32),
            sold_24h = net.ReadUInt(16)
        }
    end
    GRID.Auction.Metrics = metrics

    if IsValid(GRID.Auction.MainFrame) and GRID.Auction.RefreshCurrentTab then
        GRID.Auction.RefreshCurrentTab()
    end
end)

net.Receive("GRID_Auction_SendCollection", function()
    local count = net.ReadUInt(16)
    local col = {}
    for i = 1, count do
        table.insert(col, {
            collection_id = net.ReadUInt(32),
            item_id = net.ReadString(),
            item_type = net.ReadString(),
            amount = net.ReadUInt(16),
            item_data = net.ReadString(),
            source_reason = net.ReadString(),
            created_at_unix = net.ReadUInt(32)
        })
    end
    GRID.Auction.Collection = col

    if IsValid(GRID.Auction.MainFrame) and GRID.Auction.RefreshCurrentTab then
        GRID.Auction.RefreshCurrentTab()
    end
end)

function GRID.Auction.RequestSync()
    net.Start("GRID_Auction_RequestListings")
    net.SendToServer()

    net.Start("GRID_Auction_RequestMetrics")
    net.SendToServer()

    if GRID.Auction.IsTerminalSession then
        net.Start("GRID_Auction_RequestCollection")
        net.SendToServer()
    end
end

-- --------------------------------------------------------
-- 2. Main Window Creation
-- --------------------------------------------------------

function GRID.Auction.OpenUI(isTerminal)
    GRID.Auction.IsTerminalSession = (isTerminal == true)

    if IsValid(GRID.Auction.MainFrame) then
        GRID.Auction.MainFrame:Close()
        GRID.Auction.MainFrame = nil
    end

    if GRID.UI.CreateFonts then
        GRID.UI.CreateFonts()
    end

    GRID.Auction.RequestSync()

    local scrW, scrH = ScrW(), ScrH()
    local frameW = math.Clamp(scrW * 0.85, 1140, 1680)
    local frameH = math.Clamp(scrH * 0.86, 760, 1060)

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(true)
    frame.IsTerminalSession = (isTerminal == true)
    frame:MakePopup()
    GRID.Auction.MainFrame = frame

    frame.OnClose = function()
        GRID.Auction.MainFrame = nil
    end

    -- Glassmorphic Obsidian Header & Frame Paint
    frame.Paint = function(s, w, h)
        draw.RoundedBox(10, 0, 0, w, h, Color(11, 15, 25, 252))
        draw.RoundedBoxEx(10, 0, 0, w, 70, Color(17, 24, 39, 255), true, true, false, false)
        surface.SetDrawColor(30, 41, 59, 255)
        surface.DrawLine(0, 70, w, 70)
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- Title & Dynamic Terminal Mode Badge Placement (No Overlap)
        surface.SetFont("GRID_UI_Title")
        local titleText = "GRID AUCTION HOUSE"
        local titleW, titleH = surface.GetTextSize(titleText)
        draw.SimpleText(titleText, "GRID_UI_Title", 24, 20, Color(248, 250, 252), TEXT_ALIGN_LEFT)

        local isTerminal = frame.IsTerminalSession or GRID.Auction.IsTerminalSession
        local modeText = isTerminal and "TERMINAL CONNECTED" or "REMOTE BROWSING"
        local modeCol = isTerminal and Color(74, 222, 128) or Color(251, 191, 36)
        local modeBg = isTerminal and Color(16, 185, 129, 35) or Color(245, 158, 11, 35)

        surface.SetFont("GRID_UI_Badge")
        local badgeTextW, badgeTextH = surface.GetTextSize(modeText)
        local badgeW = badgeTextW + 18
        local badgeH = 24
        local badgeX = 24 + titleW + 14
        local badgeY = 24

        draw.RoundedBox(4, badgeX, badgeY, badgeW, badgeH, modeBg)
        surface.SetDrawColor(modeCol.r, modeCol.g, modeCol.b, 120)
        surface.DrawOutlinedRect(badgeX, badgeY, badgeW, badgeH, 1)
        draw.SimpleText(modeText, "GRID_UI_Badge", badgeX + badgeW / 2, badgeY + badgeH / 2, modeCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Dynamic Pill: Wallet & Cash Sink Info
        local ply = LocalPlayer()
        local curMoney = IsValid(ply) and ply:GetMoney() or 0
        local pillText = "$" .. string.Comma(curMoney) .. "   |   Sales Tax: 7.5%   |   Max: 10 Listings"
        surface.SetFont("GRID_UI_Sub")
        local pillTextW, pillTextH = surface.GetTextSize(pillText)
        local pillW = pillTextW + 36
        local pillH = 38
        local pillY = 17

        -- Safely position pill: center if space permits, otherwise right-align before the close button
        local centerX = w / 2
        local pillX = centerX - pillW / 2
        if (pillX < (badgeX + badgeW + 18)) or (pillX + pillW > (w - 70)) then
            pillX = w - 70 - pillW
        end

        draw.RoundedBox(19, pillX, pillY, pillW, pillH, Color(24, 32, 47, 240))
        surface.SetDrawColor(30, 41, 59, 220)
        surface.DrawOutlinedRect(pillX, pillY, pillW, pillH, 1)
        draw.SimpleText(pillText, "GRID_UI_Sub", pillX + pillW / 2, pillY + pillH / 2, Color(74, 222, 128), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Close Button
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

    -- Left Navigation Sidebar
    local sidebar = vgui.Create("DPanel", frame)
    sidebar:SetPos(14, 82)
    sidebar:SetSize(250, frameH - 96)
    sidebar.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- Main Content Area
    local contentPanel = vgui.Create("DPanel", frame)
    contentPanel:SetPos(278, 82)
    contentPanel:SetSize(frameW - 292, frameH - 96)
    contentPanel.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(17, 24, 39, 140))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local function SwitchTab(tabId)
        GRID.Auction.ActiveTab = tabId
        contentPanel:Clear()
        GRID.Auction.RenderTab(contentPanel, tabId, frame)
    end

    GRID.Auction.RefreshCurrentTab = function()
        if IsValid(contentPanel) then
            contentPanel:Clear()
            GRID.Auction.RenderTab(contentPanel, GRID.Auction.ActiveTab, frame)
        end
    end

    -- Navigation Buttons
    local navTabs = {
        { id = "browse", title = "Browse Listings", badge = "Market" },
        { id = "create", title = "Post Auction", badge = "Sell" },
        { id = "mylistings", title = "My Auctions", badge = "Active" },
        { id = "collection", title = "Collection Box", badge = "Vault" }
    }

    local yOffset = 14
    for _, t in ipairs(navTabs) do
        local btn = vgui.Create("DButton", sidebar)
        btn:SetPos(8, yOffset)
        btn:SetSize(234, 42)
        btn:SetText("")

        btn.Paint = function(s, w, h)
            local isActive = (GRID.Auction.ActiveTab == t.id)
            local isHov = s:IsHovered()
            local bg = isActive and Color(30, 41, 59, 255) or (isHov and Color(24, 32, 47, 180) or Color(0, 0, 0, 0))
            draw.RoundedBox(6, 0, 0, w, h, bg)

            if isActive then
                draw.RoundedBox(2, 0, 6, 4, h - 12, Color(6, 182, 212))
            end

            local textCol = isActive and Color(248, 250, 252) or (isHov and Color(226, 232, 240) or Color(148, 163, 184))
            draw.SimpleText(t.title, "GRID_UI_Sub", 14, h / 2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Badge count
            local badgeStr = t.badge
            if t.id == "mylistings" then
                local myCount = 0
                local mySteamID = LocalPlayer():SteamID()
                for _, a in ipairs(GRID.Auction.Listings) do
                    if a.seller_steamid == mySteamID then myCount = myCount + 1 end
                end
                badgeStr = myCount .. "/10"
            elseif t.id == "collection" then
                badgeStr = #GRID.Auction.Collection > 0 and tostring(#GRID.Auction.Collection) or "0"
            end

            surface.SetFont("GRID_UI_Badge")
            local bw = surface.GetTextSize(badgeStr) + 16
            draw.RoundedBox(4, w - bw - 8, (h - 22) / 2, bw, 22, Color(11, 15, 25, 200))
            draw.SimpleText(badgeStr, "GRID_UI_Badge", w - 8 - bw / 2, h / 2, Color(148, 163, 184), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        btn.DoClick = function()
            SwitchTab(t.id)
        end

        yOffset = yOffset + 48
    end

    -- Bottom Terminal Help Note
    local botHelp = vgui.Create("DPanel", sidebar)
    botHelp:SetPos(8, frameH - 96 - 90)
    botHelp:SetSize(234, 80)
    botHelp.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 220))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        draw.SimpleText("Terminal Protocol:", "GRID_UI_Badge", 10, 10, Color(34, 211, 238))
        if GRID.Auction.IsTerminalSession then
            draw.SimpleText("Full Transaction Enabled", "GRID_UI_Caption", 10, 32, Color(74, 222, 128))
            draw.SimpleText("Post, bid & claim active", "GRID_UI_Caption", 10, 52, Color(148, 163, 184))
        else
            draw.SimpleText("Remote View Only", "GRID_UI_Caption", 10, 32, Color(251, 191, 36))
            draw.SimpleText("Visit terminal to bid/sell", "GRID_UI_Caption", 10, 52, Color(148, 163, 184))
        end
    end

    SwitchTab(GRID.Auction.ActiveTab or "browse")
end

-- --------------------------------------------------------
-- 3. Tab Render Engine
-- --------------------------------------------------------

function GRID.Auction.RenderTab(parent, tabId, frame)
    if tabId == "browse" then
        GRID.Auction.RenderBrowseTab(parent)
    elseif tabId == "create" then
        GRID.Auction.RenderCreateTab(parent)
    elseif tabId == "mylistings" then
        GRID.Auction.RenderMyListingsTab(parent)
    elseif tabId == "collection" then
        GRID.Auction.RenderCollectionTab(parent)
    end
end

-- --------------------------------------------------------
-- 4. Two-Tier Tree Browse Tab
-- --------------------------------------------------------

function GRID.Auction.RenderBrowseTab(parent)
    local pW, pH = parent:GetSize()

    -- Aggregate active auctions by base item_id
    local grouped = {}
    for _, auc in ipairs(GRID.Auction.Listings) do
        local id = auc.item_id
        if not grouped[id] then
            grouped[id] = {
                item_id = id,
                item_type = auc.item_type,
                instances = {},
                min_buyout = auc.buyout_price > 0 and auc.buyout_price or nil,
                count = 0
            }
        end
        table.insert(grouped[id].instances, auc)
        grouped[id].count = grouped[id].count + 1
        if auc.buyout_price > 0 then
            if not grouped[id].min_buyout or auc.buyout_price < grouped[id].min_buyout then
                grouped[id].min_buyout = auc.buyout_price
            end
        end
    end

    -- If no item currently selected, select the first one available
    if not GRID.Auction.SelectedBaseItem or not grouped[GRID.Auction.SelectedBaseItem] then
        for id, _ in pairs(grouped) do
            GRID.Auction.SelectedBaseItem = id
            break
        end
    end

    -- Left Pane: Base Items List (Width: 330px)
    local leftPane = vgui.Create("DPanel", parent)
    leftPane:SetPos(10, 10)
    leftPane:SetSize(330, pH - 20)
    leftPane.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 220))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- Search Entry
    local searchEntry = vgui.Create("DTextEntry", leftPane)
    searchEntry:SetPos(8, 8)
    searchEntry:SetSize(314, 34)
    searchEntry:SetFont("GRID_UI_Sub")
    searchEntry:SetPlaceholderText("Search items...")
    searchEntry:SetText(GRID.Auction.SearchQuery or "")
    searchEntry.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(17, 24, 39, 240))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        s:DrawTextEntryText(Color(248, 250, 252), Color(6, 182, 212), Color(248, 250, 252))
        if s:GetText() == "" and not s:HasFocus() then
            draw.SimpleText("Search items...", "GRID_UI_Sub", 10, h / 2, Color(100, 116, 139), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    searchEntry.OnChange = function(s)
        GRID.Auction.SearchQuery = string.lower(s:GetText())
        if IsValid(baseScroll) and IsValid(rightPane) then
            GRID.Auction.PopulateBaseItems(baseScroll, grouped, rightPane)
        end
    end

    -- Scroll Panel for Base Items
    local baseScroll = vgui.Create("DScrollPanel", leftPane)
    baseScroll:SetPos(8, 48)
    baseScroll:SetSize(314, pH - 20 - 56)
    local vbar = baseScroll:GetVBar()
    vbar:SetWide(4)
    vbar.Paint = function() end
    vbar.btnGrip.Paint = function(s, w, h) draw.RoundedBox(2, 0, 0, w, h, Color(56, 189, 248, 80)) end
    vbar.btnUp.Paint = function() end
    vbar.btnDown.Paint = function() end
    leftPane.BaseScroll = baseScroll

    -- Right Pane: Selected Base Item & Instance Breakdown (Flex)
    local rightPane = vgui.Create("DPanel", parent)
    rightPane:SetPos(350, 10)
    rightPane:SetSize(pW - 360, pH - 20)
    rightPane.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    parent.RightPane = rightPane

    -- Populate Left Base Items
    GRID.Auction.PopulateBaseItems(baseScroll, grouped, rightPane)

    -- Render Right Instances
    GRID.Auction.RenderInstancesPane(rightPane, grouped[GRID.Auction.SelectedBaseItem])
end

function GRID.Auction.PopulateBaseItems(scroll, grouped, rightPane)
    scroll:Clear()

    local sorted = {}
    for id, group in pairs(grouped) do
        local def = GRID.Inventory and GRID.Inventory.Items and GRID.Inventory.Items[id]
        local name = def and def.name or id
        if GRID.Auction.SearchQuery == "" or string.find(string.lower(name), GRID.Auction.SearchQuery, 1, true) then
            table.insert(sorted, group)
        end
    end

    table.sort(sorted, function(a, b)
        return a.count > b.count
    end)

    if #sorted == 0 then
        local emptyLbl = scroll:Add("DLabel")
        emptyLbl:Dock(TOP)
        emptyLbl:DockMargin(10, 20, 10, 0)
        emptyLbl:SetFont("GRID_UI_Sub")
        emptyLbl:SetTextColor(Color(148, 163, 184))
        emptyLbl:SetText("No active listings found.")
        emptyLbl:SetContentAlignment(5)
        return
    end

    for _, group in ipairs(sorted) do
        local def = GRID.Inventory and GRID.Inventory.Items and GRID.Inventory.Items[group.item_id]
        local itemName = def and def.name or group.item_id
        local qualCol = GRID.Inventory and GRID.Inventory.GetQualityColor and GRID.Inventory.GetQualityColor(def and def.quality or 1) or Color(248, 250, 252)

        local btn = scroll:Add("DButton")
        btn:Dock(TOP)
        btn:DockMargin(0, 0, 0, 6)
        btn:SetTall(56)
        btn:SetText("")

        btn.Paint = function(s, w, h)
            local isSel = (GRID.Auction.SelectedBaseItem == group.item_id)
            local isHov = s:IsHovered()
            local bg = isSel and Color(30, 41, 59, 255) or (isHov and Color(24, 32, 47, 200) or Color(17, 24, 39, 160))
            draw.RoundedBox(6, 0, 0, w, h, bg)

            if isSel then
                draw.RoundedBox(2, 0, 6, 4, h - 12, Color(6, 182, 212))
            end

            -- Quality Accent Dot
            draw.RoundedBox(3, 12, 14, 6, 6, qualCol)

            -- Item Title
            draw.SimpleText(itemName, "GRID_UI_Sub", 26, 16, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Price tag
            local priceStr = group.min_buyout and ("From $" .. string.Comma(group.min_buyout)) or "Bids Only"
            draw.SimpleText(priceStr, "GRID_UI_Caption", 26, 38, Color(74, 222, 128), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Count Badge
            local badgeStr = tostring(group.count) .. " listed"
            surface.SetFont("GRID_UI_Badge")
            local bw = surface.GetTextSize(badgeStr) + 14
            draw.RoundedBox(4, w - bw - 10, (h - 22) / 2, bw, 22, Color(11, 15, 25, 200))
            draw.SimpleText(badgeStr, "GRID_UI_Badge", w - 10 - bw / 2, h / 2, Color(34, 211, 238), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        btn.DoClick = function()
            GRID.Auction.SelectedBaseItem = group.item_id
            GRID.Auction.RenderInstancesPane(rightPane, group)
        end
    end
end

-- --------------------------------------------------------
-- 5. Right Instance Inspection & Streamlined Statistics
-- --------------------------------------------------------

function GRID.Auction.RenderInstancesPane(parent, group)
    parent:Clear()
    if not group then
        local noSel = vgui.Create("DLabel", parent)
        noSel:Dock(FILL)
        noSel:SetFont("GRID_UI_Header")
        noSel:SetTextColor(Color(148, 163, 184))
        noSel:SetText("Select an item on the left to inspect listings.")
        noSel:SetContentAlignment(5)
        return
    end

    local pW, pH = parent:GetSize()
    local def = GRID.Inventory and GRID.Inventory.Items and GRID.Inventory.Items[group.item_id]
    local itemName = def and def.name or group.item_id
    local qualCol = GRID.Inventory and GRID.Inventory.GetQualityColor and GRID.Inventory.GetQualityColor(def and def.quality or 1) or Color(248, 250, 252)

    -- Top Header Panel: Item Name & Quality Badge
    local topHeader = vgui.Create("DPanel", parent)
    topHeader:Dock(TOP)
    topHeader:DockMargin(12, 12, 12, 8)
    topHeader:SetTall(64)
    topHeader.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 220))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        draw.SimpleText(itemName, "GRID_UI_Header", 16, 22, qualCol, TEXT_ALIGN_LEFT)
        draw.SimpleText(def and def.desc or "Distinct item instance marketplace listing.", "GRID_UI_Caption", 16, 44, Color(148, 163, 184))

        local totalStr = string.format("%d Available Listings", group.count)
        draw.SimpleText(totalStr, "GRID_UI_Sub", w - 16, 32, Color(34, 211, 238), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    -- Market Statistics Bar (Streamlined Analytics: 7-day Avg, Current Lowest Buyout, 24h Sold)
    local statsBar = vgui.Create("DPanel", parent)
    statsBar:Dock(TOP)
    statsBar:DockMargin(12, 0, 12, 12)
    statsBar:SetTall(52)

    local metric = GRID.Auction.Metrics[group.item_id] or {}
    local avg7d = metric.avg_7d and ("$" .. string.Comma(metric.avg_7d)) or "N/A"
    local minBuyout = metric.min_buyout and metric.min_buyout > 0 and ("$" .. string.Comma(metric.min_buyout)) or (group.min_buyout and ("$" .. string.Comma(group.min_buyout)) or "N/A")
    local sold24h = metric.sold_24h and tostring(metric.sold_24h) or "0"

    statsBar.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(24, 32, 47, 220))
        surface.SetDrawColor(6, 182, 212, 100)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- 3 Columns
        local colW = w / 3

        -- Col 1: Lowest Buyout
        draw.SimpleText("Current Lowest Buyout", "GRID_UI_Caption", 16, 14, Color(148, 163, 184))
        draw.SimpleText(minBuyout, "GRID_UI_Sub", 16, 34, Color(74, 222, 128))

        -- Col 2: 7-Day Average Price
        draw.SimpleText("7-Day Market Average", "GRID_UI_Caption", colW + 16, 14, Color(148, 163, 184))
        draw.SimpleText(avg7d, "GRID_UI_Sub", colW + 16, 34, Color(34, 211, 238))

        -- Col 3: 24-Hour Units Sold
        draw.SimpleText("24-Hour Units Sold", "GRID_UI_Caption", colW * 2 + 16, 14, Color(148, 163, 184))
        draw.SimpleText(sold24h .. " units", "GRID_UI_Sub", colW * 2 + 16, 34, Color(248, 250, 252))
    end

    -- Scrollable List of Instances sorted by Lowest Buyout / Bid
    local instanceScroll = vgui.Create("DScrollPanel", parent)
    instanceScroll:Dock(FILL)
    instanceScroll:DockMargin(12, 0, 12, 12)
    local vbar = instanceScroll:GetVBar()
    vbar:SetWide(4)
    vbar.Paint = function() end
    vbar.btnGrip.Paint = function(s, w, h) draw.RoundedBox(2, 0, 0, w, h, Color(56, 189, 248, 80)) end
    vbar.btnUp.Paint = function() end
    vbar.btnDown.Paint = function() end

    -- Sort instances: Cheapest buyout first, then highest bid
    local instances = table.Copy(group.instances)
    table.sort(instances, function(a, b)
        local priceA = a.buyout_price > 0 and a.buyout_price or (a.current_bid > 0 and a.current_bid or a.start_bid)
        local priceB = b.buyout_price > 0 and b.buyout_price or (b.current_bid > 0 and b.current_bid or b.start_bid)
        return priceA < priceB
    end)

    for _, inst in ipairs(instances) do
        local card = instanceScroll:Add("DPanel")
        card:Dock(TOP)
        card:DockMargin(0, 0, 0, 8)
        card:SetTall(102)

        local badges = GRID.Auction.GetItemAttributeBadges(inst.item_data)
        local timeLeft = GRID.Auction.FormatTimeRemaining(inst.expires_at_unix)
        local curBid = inst.current_bid > 0 and inst.current_bid or inst.start_bid
        local hasBuyout = (inst.buyout_price > 0)
        local hasHighBidder = inst.high_bidder_name and inst.high_bidder_name ~= "" and inst.high_bidder_name ~= "NULL" and inst.high_bidder_name ~= "nil" and inst.current_bid > 0
        local isTerminal = GRID.Auction.IsTerminalSession

        local btnBuy = nil
        local btnBid = nil
        local noticePill = nil

        card.Paint = function(s, w, h)
            local isHov = s:IsHovered()
            draw.RoundedBox(6, 0, 0, w, h, isHov and Color(24, 32, 47, 240) or Color(17, 24, 39, 200))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            -- Left Section: Seller & Status
            local sellerStr = "Seller: " .. inst.seller_name
            draw.SimpleText(sellerStr, "GRID_UI_Sub", 14, 16, Color(248, 250, 252))

            local statusSub = "Time Left: " .. timeLeft
            if hasHighBidder then
                statusSub = statusSub .. "   •   High Bidder: " .. inst.high_bidder_name
            else
                statusSub = statusSub .. "   •   No Bids Yet"
            end
            draw.SimpleText(statusSub, "GRID_UI_Caption", 14, 38, hasHighBidder and Color(56, 189, 248) or Color(148, 163, 184))

            -- Render Attribute Badges horizontally
            local bx = 14
            local by = 64
            for _, b in ipairs(badges) do
                surface.SetFont("GRID_UI_Badge")
                local bw = surface.GetTextSize(b.text) + 14
                draw.RoundedBox(4, bx, by, bw, 22, b.bg)
                draw.SimpleText(b.text, "GRID_UI_Badge", bx + bw / 2, by + 11, b.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                bx = bx + bw + 6
            end

            -- Right Columns: Pricing Details (Centered above matching action buttons)
            local colW = 100
            local buyoutX = w - 114
            local bidX = hasBuyout and (w - 224) or (w - 114)

            -- Bid Column
            local bidLabel = (inst.current_bid > 0) and "CURRENT BID" or "STARTING BID"
            draw.SimpleText(bidLabel, "GRID_UI_Caption", bidX + colW / 2, 14, Color(148, 163, 184), TEXT_ALIGN_CENTER)
            draw.SimpleText("$" .. string.Comma(curBid), "GRID_UI_Price", bidX + colW / 2, 33, Color(248, 250, 252), TEXT_ALIGN_CENTER)

            -- Buyout Column (if available)
            if hasBuyout then
                draw.SimpleText("BUYOUT PRICE", "GRID_UI_Caption", buyoutX + colW / 2, 14, Color(148, 163, 184), TEXT_ALIGN_CENTER)
                draw.SimpleText("$" .. string.Comma(inst.buyout_price), "GRID_UI_Price", buyoutX + colW / 2, 33, Color(74, 222, 128), TEXT_ALIGN_CENTER)
            end
        end

        -- Action Buttons or Remote Browsing Notice
        if isTerminal then
            if hasBuyout then
                btnBuy = vgui.Create("DButton", card)
                btnBuy:SetSize(100, 32)
                btnBuy:SetText("")
                btnBuy.Paint = function(s, w, h)
                    local isHov = s:IsHovered()
                    draw.RoundedBox(4, 0, 0, w, h, isHov and Color(16, 185, 129, 220) or Color(16, 185, 129, 140))
                    surface.SetDrawColor(16, 185, 129, 200)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)
                    draw.SimpleText("Buyout", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                btnBuy.DoClick = function()
                    Derma_Query(
                        string.format("Buyout %s for $%s?\n\nFunds will be deducted immediately, and the item will be delivered to your Terminal Collection Box.", itemName, string.Comma(inst.buyout_price)),
                        "Confirm Instant Buyout",
                        "Confirm Buyout", function()
                            net.Start("GRID_Auction_Buyout")
                            net.WriteUInt(inst.auction_id, 32)
                            net.SendToServer()
                        end,
                        "Cancel", function() end
                    )
                end
            end

            -- Bid Button
            btnBid = vgui.Create("DButton", card)
            btnBid:SetSize(100, 32)
            btnBid:SetText("")
            btnBid.Paint = function(s, w, h)
                local isHov = s:IsHovered()
                draw.RoundedBox(4, 0, 0, w, h, isHov and Color(6, 182, 212, 220) or Color(6, 182, 212, 140))
                surface.SetDrawColor(6, 182, 212, 200)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText("Bid", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            btnBid.DoClick = function()
                local minBid = inst.current_bid > 0 and (inst.current_bid + math.max(10, math.floor(inst.current_bid * 0.05))) or inst.start_bid
                Derma_StringRequest(
                    "Place Bid",
                    string.format("Enter your bid for %s.\nMinimum required bid: $%s", itemName, string.Comma(minBid)),
                    tostring(minBid),
                    function(text)
                        local bidAmt = tonumber(text) or 0
                        if bidAmt < minBid then
                            Derma_Message("Bid must be at least $" .. string.Comma(minBid), "Bid Error", "OK")
                            return
                        end
                        net.Start("GRID_Auction_PlaceBid")
                        net.WriteUInt(inst.auction_id, 32)
                        net.WriteUInt(bidAmt, 32)
                        net.SendToServer()
                    end
                )
            end
        else
            -- Remote F4 Mode: Visual Notice Pill
            noticePill = vgui.Create("DPanel", card)
            noticePill:SetSize(hasBuyout and 210 or 100, 30)
            noticePill.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(245, 158, 11, 35))
                surface.SetDrawColor(245, 158, 11, 120)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                local noticeText = (w > 120) and "Terminal Required to Bid" or "Terminal Req."
                draw.SimpleText(noticeText, "GRID_UI_Caption", w / 2, h / 2, Color(251, 191, 36), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        card.PerformLayout = function(s, w, h)
            local colW = 100
            local buyoutX = w - 114
            local bidX = hasBuyout and (w - 224) or (w - 114)

            if IsValid(btnBuy) then
                btnBuy:SetPos(buyoutX, 58)
                btnBuy:SetSize(colW, 32)
            end
            if IsValid(btnBid) then
                btnBid:SetPos(bidX, 58)
                btnBid:SetSize(colW, 32)
            end
            if IsValid(noticePill) then
                local pW = hasBuyout and 210 or colW
                noticePill:SetPos(bidX, 59)
                noticePill:SetSize(pW, 30)
            end
        end
    end
end

-- --------------------------------------------------------
-- 6. Create Listing Tab (Seller Assistant & Quick Undercut)
-- --------------------------------------------------------

function GRID.Auction.RenderCreateTab(parent)
    local pW, pH = parent:GetSize()

    if not GRID.Auction.IsTerminalSession then
        local warn = vgui.Create("DPanel", parent)
        warn:Dock(FILL)
        warn.Paint = function(s, w, h)
            draw.SimpleText("Terminal Access Required", "GRID_UI_Title", w / 2, h / 2 - 20, Color(245, 158, 11), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("You must visit a physical Auction Terminal (Bank or Central Plaza) to post auctions.", "GRID_UI_Sub", w / 2, h / 2 + 16, Color(148, 163, 184), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    -- Left Pane: Player Bag Inventory
    local leftPane = vgui.Create("DPanel", parent)
    leftPane:SetPos(12, 12)
    leftPane:SetSize(360, pH - 24)
    leftPane.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 220))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("Select Item from Bag", "GRID_UI_Sub", 14, 16, Color(248, 250, 252))
    end

    local invScroll = vgui.Create("DScrollPanel", leftPane)
    invScroll:SetPos(8, 42)
    invScroll:SetSize(344, pH - 24 - 50)
    local vbar = invScroll:GetVBar()
    vbar:SetWide(4)
    vbar.Paint = function() end
    vbar.btnGrip.Paint = function(s, w, h) draw.RoundedBox(2, 0, 0, w, h, Color(56, 189, 248, 80)) end

    -- Right Pane: Listing Configuration & Undercut Assistant
    local rightPane = vgui.Create("DPanel", parent)
    rightPane:SetPos(384, 12)
    rightPane:SetSize(pW - 396, pH - 24)
    rightPane.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(11, 15, 25, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local selectedInvItem = nil

    local function RefreshListingForm()
        rightPane:Clear()
        if not selectedInvItem then
            local lbl = vgui.Create("DLabel", rightPane)
            lbl:Dock(FILL)
            lbl:SetFont("GRID_UI_Header")
            lbl:SetTextColor(Color(148, 163, 184))
            lbl:SetText("Select an item on the left to set up listing details.")
            lbl:SetContentAlignment(5)
            return
        end

        local def = GRID.Inventory and GRID.Inventory.Items and GRID.Inventory.Items[selectedInvItem.item_id]
        local itemName = def and def.name or selectedInvItem.item_id
        local qualCol = GRID.Inventory and GRID.Inventory.GetQualityColor and GRID.Inventory.GetQualityColor(def and def.quality or 1) or Color(248, 250, 252)

        -- Top Card: Item Name & Badges
        local topCard = vgui.Create("DPanel", rightPane)
        topCard:Dock(TOP)
        topCard:DockMargin(16, 16, 16, 12)
        topCard:SetTall(74)
        local badges = GRID.Auction.GetItemAttributeBadges(selectedInvItem.item_data)
        topCard.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 220))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            draw.SimpleText(itemName, "GRID_UI_Header", 16, 20, qualCol)

            local bx = 16
            local by = 42
            for _, b in ipairs(badges) do
                surface.SetFont("GRID_UI_Badge")
                local bw = surface.GetTextSize(b.text) + 12
                draw.RoundedBox(4, bx, by, bw, 20, b.bg)
                draw.SimpleText(b.text, "GRID_UI_Badge", bx + bw / 2, by + 10, b.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                bx = bx + bw + 6
            end
        end

        -- Undercut Assistant Card
        local metric = GRID.Auction.Metrics[selectedInvItem.item_id] or {}
        local minBuy = metric.min_buyout or 0
        local avg7d = metric.avg_7d or 0

        local assistantCard = vgui.Create("DPanel", rightPane)
        assistantCard:Dock(TOP)
        assistantCard:DockMargin(16, 0, 16, 12)
        assistantCard:SetTall(64)
        assistantCard.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(24, 32, 47, 220))
            surface.SetDrawColor(6, 182, 212, 100)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            draw.SimpleText("MARKET INTELLIGENCE", "GRID_UI_Badge", 16, 12, Color(34, 211, 238))
            local infoStr = string.format("Lowest Active Buyout: %s   |   7-Day Average: %s", minBuy > 0 and ("$" .. string.Comma(minBuy)) or "None", avg7d > 0 and ("$" .. string.Comma(avg7d)) or "None")
            draw.SimpleText(infoStr, "GRID_UI_Sub", 16, 38, Color(248, 250, 252))
        end

        -- Form Body Panel
        local formBody = vgui.Create("DPanel", rightPane)
        formBody:Dock(FILL)
        formBody:DockMargin(16, 0, 16, 16)
        formBody.Paint = function() end

        -- Duration Selector
        local curDuration = 24
        local lblDur = vgui.Create("DLabel", formBody)
        lblDur:SetPos(0, 0)
        lblDur:SetFont("GRID_UI_Sub")
        lblDur:SetTextColor(Color(226, 232, 240))
        lblDur:SetText("Listing Duration & Deposit Rate:")
        lblDur:SizeToContents()

        local durBtns = {}
        local durX = 0
        for _, d in ipairs({ 12, 24, 48 }) do
            local cfg = GRID.Auction.Durations[d]
            local b = vgui.Create("DButton", formBody)
            b:SetPos(durX, 26)
            b:SetSize(120, 36)
            b:SetText("")
            b.Paint = function(s, w, h)
                local isSel = (curDuration == d)
                local isHov = s:IsHovered()
                draw.RoundedBox(4, 0, 0, w, h, isSel and Color(6, 182, 212, 220) or (isHov and Color(30, 41, 59, 200) or Color(17, 24, 39, 200)))
                surface.SetDrawColor(30, 41, 59, 220)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText(cfg.name, "GRID_UI_Btn", w / 2, h / 2, isSel and Color(11, 15, 25) or Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            b.DoClick = function()
                curDuration = d
            end
            durBtns[d] = b
            durX = durX + 130
        end

        -- Starting Bid Input
        local lblStart = vgui.Create("DLabel", formBody)
        lblStart:SetPos(0, 74)
        lblStart:SetFont("GRID_UI_Sub")
        lblStart:SetTextColor(Color(226, 232, 240))
        lblStart:SetText("Starting Bid ($):")
        lblStart:SizeToContents()

        local inStartBid = vgui.Create("DTextEntry", formBody)
        inStartBid:SetPos(0, 100)
        inStartBid:SetSize(220, 36)
        inStartBid:SetFont("GRID_UI_Sub")
        inStartBid:SetNumeric(true)
        inStartBid:SetText(minBuy > 0 and tostring(math.floor(minBuy * 0.8)) or "500")

        -- Buyout Input
        local lblBuyout = vgui.Create("DLabel", formBody)
        lblBuyout:SetPos(240, 74)
        lblBuyout:SetFont("GRID_UI_Sub")
        lblBuyout:SetTextColor(Color(226, 232, 240))
        lblBuyout:SetText("Buyout Price ($) [Optional]:")
        lblBuyout:SizeToContents()

        local inBuyout = vgui.Create("DTextEntry", formBody)
        inBuyout:SetPos(240, 100)
        inBuyout:SetSize(220, 36)
        inBuyout:SetFont("GRID_UI_Sub")
        inBuyout:SetNumeric(true)
        inBuyout:SetText(minBuy > 0 and tostring(minBuy) or "1000")

        -- Quick Undercut Buttons
        local btnMatch = nil
        local btnUndercut1 = nil
        if minBuy > 0 then
            btnMatch = vgui.Create("DButton", formBody)
            btnMatch:SetSize(100, 30)
            btnMatch:SetText("")
            btnMatch.Paint = function(s, w, h)
                local isHov = s:IsHovered()
                draw.RoundedBox(4, 0, 0, w, h, isHov and Color(30, 41, 59, 255) or Color(17, 24, 39, 200))
                surface.SetDrawColor(30, 41, 59, 220)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText("Match Lowest", "GRID_UI_Badge", w / 2, h / 2, Color(34, 211, 238), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            btnMatch.DoClick = function()
                inBuyout:SetText(tostring(minBuy))
            end

            btnUndercut1 = vgui.Create("DButton", formBody)
            btnUndercut1:SetSize(100, 30)
            btnUndercut1:SetText("")
            btnUndercut1.Paint = function(s, w, h)
                local isHov = s:IsHovered()
                draw.RoundedBox(4, 0, 0, w, h, isHov and Color(30, 41, 59, 255) or Color(17, 24, 39, 200))
                surface.SetDrawColor(30, 41, 59, 220)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText("Undercut $1", "GRID_UI_Badge", w / 2, h / 2, Color(74, 222, 128), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            btnUndercut1.DoClick = function()
                inBuyout:SetText(tostring(math.max(1, minBuy - 1)))
            end
        end

        -- Cost Breakdown Card
        local breakdownCard = vgui.Create("DPanel", formBody)
        breakdownCard:SetPos(0, 180)
        breakdownCard:SetSize(formBody:GetWide(), 96)
        breakdownCard.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            local sBid = tonumber(inStartBid:GetText()) or 0
            local bPrice = tonumber(inBuyout:GetText()) or 0
            local dep = GRID.Auction.CalculateDeposit(sBid, curDuration)
            local tax = GRID.Auction.CalculateSalesTax(bPrice > 0 and bPrice or sBid)
            local netPayout = (bPrice > 0 and bPrice or sBid) - tax + dep

            draw.SimpleText("Required Upfront Deposit (Refunded on successful sale):", "GRID_UI_Caption", 16, 18, Color(148, 163, 184))
            draw.SimpleText("$" .. string.Comma(dep), "GRID_UI_Sub", w - 20, 18, Color(251, 191, 36), TEXT_ALIGN_RIGHT)

            draw.SimpleText("House Sales Tax (7.5% burned on sale):", "GRID_UI_Caption", 16, 42, Color(148, 163, 184))
            draw.SimpleText("$" .. string.Comma(tax), "GRID_UI_Sub", w - 20, 42, Color(239, 68, 68), TEXT_ALIGN_RIGHT)

            draw.SimpleText("Estimated Net Payout into Bank:", "GRID_UI_Sub", 16, 68, Color(248, 250, 252))
            draw.SimpleText("$" .. string.Comma(netPayout), "GRID_UI_Header", w - 20, 68, Color(74, 222, 128), TEXT_ALIGN_RIGHT)
        end

        -- Post Button
        local btnPost = vgui.Create("DButton", formBody)
        btnPost:SetPos(0, 290)
        btnPost:SetSize(220, 44)

        formBody.PerformLayout = function(s, w, h)
            local colW = math.Clamp((w - 20) / 2, 160, 260)
            inStartBid:SetSize(colW, 36)
            lblBuyout:SetPos(colW + 20, 74)
            inBuyout:SetPos(colW + 20, 100)
            inBuyout:SetSize(colW, 36)

            local nextY = 150
            if IsValid(btnMatch) and IsValid(btnUndercut1) then
                local bW = (colW - 8) / 2
                btnMatch:SetPos(colW + 20, 144)
                btnMatch:SetSize(bW, 28)
                btnUndercut1:SetPos(colW + 20 + bW + 8, 144)
                btnUndercut1:SetSize(bW, 28)
                nextY = 184
            end

            breakdownCard:SetPos(0, nextY)
            breakdownCard:SetSize(w, 96)

            btnPost:SetPos(0, nextY + 108)
            btnPost:SetSize(math.min(w, 280), 44)
        end
        btnPost:SetText("")
        btnPost.Paint = function(s, w, h)
            local isHov = s:IsHovered()
            draw.RoundedBox(6, 0, 0, w, h, isHov and Color(16, 185, 129, 240) or Color(16, 185, 129, 180))
            surface.SetDrawColor(16, 185, 129, 255)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            draw.SimpleText("POST AUCTION", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        btnPost.DoClick = function()
            local sBid = tonumber(inStartBid:GetText()) or 0
            local bPrice = tonumber(inBuyout:GetText()) or 0

            if sBid < 10 then
                Derma_Message("Starting bid must be at least $10!", "Listing Error", "OK")
                return
            end

            if bPrice > 0 and bPrice < sBid then
                Derma_Message("Buyout price cannot be lower than the starting bid!", "Listing Error", "OK")
                return
            end

            net.Start("GRID_Auction_CreateListing")
            net.WriteUInt(selectedInvItem.bag_index or 0, 8)
            net.WriteUInt(selectedInvItem.slot_index or 1, 8)
            net.WriteUInt(sBid, 32)
            net.WriteUInt(bPrice, 32)
            net.WriteUInt(curDuration, 8)
            net.SendToServer()

            selectedInvItem = nil
            RefreshListingForm()
        end
    end

    -- Populate Bag Items in Left Pane
    local playerItems = GRID.Inventory and GRID.Inventory.ClientItems or {}
    for _, item in ipairs(playerItems) do
        local def = GRID.Inventory and GRID.Inventory.Items and GRID.Inventory.Items[item.item_id]
        local itemName = def and def.name or item.item_id
        local qualCol = GRID.Inventory and GRID.Inventory.GetQualityColor and GRID.Inventory.GetQualityColor(def and def.quality or 1) or Color(248, 250, 252)

        local btn = invScroll:Add("DButton")
        btn:Dock(TOP)
        btn:DockMargin(0, 0, 0, 6)
        btn:SetTall(52)
        btn:SetText("")

        btn.Paint = function(s, w, h)
            local isSel = (selectedInvItem and selectedInvItem.bag_index == item.bag_index and selectedInvItem.slot_index == item.slot_index)
            local isHov = s:IsHovered()
            draw.RoundedBox(6, 0, 0, w, h, isSel and Color(30, 41, 59, 255) or (isHov and Color(24, 32, 47, 200) or Color(17, 24, 39, 160)))
            if isSel then
                draw.RoundedBox(2, 0, 6, 4, h - 12, Color(6, 182, 212))
            end

            draw.RoundedBox(3, 12, 14, 6, 6, qualCol)
            draw.SimpleText(itemName, "GRID_UI_Sub", 26, 16, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("Bag %d | Slot %d", item.bag_index or 0, item.slot_index or 1), "GRID_UI_Caption", 26, 36, Color(148, 163, 184))
        end

        btn.DoClick = function()
            selectedInvItem = item
            RefreshListingForm()
        end
    end

    RefreshListingForm()
end

-- --------------------------------------------------------
-- 7. My Listings Tab
-- --------------------------------------------------------

function GRID.Auction.RenderMyListingsTab(parent)
    local pW, pH = parent:GetSize()
    local mySteamID = LocalPlayer():SteamID()

    local myList = {}
    for _, a in ipairs(GRID.Auction.Listings) do
        if a.seller_steamid == mySteamID then
            table.insert(myList, a)
        end
    end

    local topInfo = vgui.Create("DPanel", parent)
    topInfo:Dock(TOP)
    topInfo:DockMargin(12, 12, 12, 12)
    topInfo:SetTall(56)
    topInfo.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 220))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        draw.SimpleText("My Active Auctions (" .. #myList .. "/10 Listings)", "GRID_UI_Header", 16, 28, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Note: Auctions with active bids cannot be cancelled.", "GRID_UI_Caption", w - 16, 28, Color(245, 158, 11), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(12, 0, 12, 12)
    local vbar = scroll:GetVBar()
    vbar:SetWide(4)
    vbar.Paint = function() end
    vbar.btnGrip.Paint = function(s, w, h) draw.RoundedBox(2, 0, 0, w, h, Color(56, 189, 248, 80)) end

    if #myList == 0 then
        local emptyLbl = scroll:Add("DLabel")
        emptyLbl:Dock(TOP)
        emptyLbl:DockMargin(10, 40, 10, 0)
        emptyLbl:SetFont("GRID_UI_Header")
        emptyLbl:SetTextColor(Color(148, 163, 184))
        emptyLbl:SetText("You have no active auction listings.")
        emptyLbl:SetContentAlignment(5)
        return
    end

    for _, inst in ipairs(myList) do
        local def = GRID.Inventory and GRID.Inventory.Items and GRID.Inventory.Items[inst.item_id]
        local itemName = def and def.name or inst.item_id
        local qualCol = GRID.Inventory and GRID.Inventory.GetQualityColor and GRID.Inventory.GetQualityColor(def and def.quality or 1) or Color(248, 250, 252)
        local badges = GRID.Auction.GetItemAttributeBadges(inst.item_data)
        local timeLeft = GRID.Auction.FormatTimeRemaining(inst.expires_at_unix)

        local card = scroll:Add("DPanel")
        card:Dock(TOP)
        card:DockMargin(0, 0, 0, 8)
        card:SetTall(84)

        card.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText(itemName, "GRID_UI_Sub", 16, 20, qualCol)
            draw.SimpleText("Time Left: " .. timeLeft, "GRID_UI_Caption", 16, 42, Color(148, 163, 184))

            local bx = 16
            local by = 56
            for _, b in ipairs(badges) do
                surface.SetFont("GRID_UI_Badge")
                local bw = surface.GetTextSize(b.text) + 10
                draw.RoundedBox(3, bx, by, bw, 18, b.bg)
                draw.SimpleText(b.text, "GRID_UI_Badge", bx + bw / 2, by + 9, b.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                bx = bx + bw + 6
            end

            local pX = w - 260
            local curB = inst.current_bid > 0 and inst.current_bid or inst.start_bid
            draw.SimpleText("Current Bid: $" .. string.Comma(curB), "GRID_UI_Sub", pX, 22, Color(248, 250, 252))
            if inst.buyout_price > 0 then
                draw.SimpleText("Buyout: $" .. string.Comma(inst.buyout_price), "GRID_UI_Sub", pX, 44, Color(74, 222, 128))
            end
        end

        if GRID.Auction.IsTerminalSession and inst.current_bid == 0 then
            local btnCancel = vgui.Create("DButton", card)
            btnCancel:SetSize(100, 34)
            btnCancel:SetPos(card:GetWide() - 114, 25)
            btnCancel:SetText("")
            card.PerformLayout = function(s, w, h)
                btnCancel:SetPos(w - 114, 25)
            end
            btnCancel.Paint = function(s, w, h)
                local isHov = s:IsHovered()
                draw.RoundedBox(4, 0, 0, w, h, isHov and Color(239, 68, 68, 220) or Color(239, 68, 68, 140))
                surface.SetDrawColor(239, 68, 68, 200)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText("Cancel", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            btnCancel.DoClick = function()
                Derma_Query(
                    "Cancel this auction?\n\nWARNING: Your listing deposit will be forfeited, and the item will be sent to your Collection Box.",
                    "Cancel Auction",
                    "Yes, Cancel Auction", function()
                        net.Start("GRID_Auction_Cancel")
                        net.WriteUInt(inst.auction_id, 32)
                        net.SendToServer()
                    end,
                    "Keep Auction", function() end
                )
            end
        end
    end
end

-- --------------------------------------------------------
-- 8. Terminal Collection Box Tab (Won, Expired & Canceled Goods)
-- --------------------------------------------------------

function GRID.Auction.RenderCollectionTab(parent)
    local pW, pH = parent:GetSize()

    if not GRID.Auction.IsTerminalSession then
        local warn = vgui.Create("DPanel", parent)
        warn:Dock(FILL)
        warn.Paint = function(s, w, h)
            draw.SimpleText("Terminal Access Required", "GRID_UI_Title", w / 2, h / 2 - 20, Color(245, 158, 11), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("You must visit a physical Auction Terminal to claim won or returned items.", "GRID_UI_Sub", w / 2, h / 2 + 16, Color(148, 163, 184), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    local topInfo = vgui.Create("DPanel", parent)
    topInfo:Dock(TOP)
    topInfo:DockMargin(12, 12, 12, 12)
    topInfo:SetTall(56)
    topInfo.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 220))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        draw.SimpleText("Terminal Collection Box (" .. #GRID.Auction.Collection .. " Items Pending)", "GRID_UI_Header", 16, 28, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Ensure you have empty inventory slots before claiming.", "GRID_UI_Caption", w - 16, 28, Color(74, 222, 128), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(12, 0, 12, 12)
    local vbar = scroll:GetVBar()
    vbar:SetWide(4)
    vbar.Paint = function() end
    vbar.btnGrip.Paint = function(s, w, h) draw.RoundedBox(2, 0, 0, w, h, Color(56, 189, 248, 80)) end

    if #GRID.Auction.Collection == 0 then
        local emptyLbl = scroll:Add("DLabel")
        emptyLbl:Dock(TOP)
        emptyLbl:DockMargin(10, 40, 10, 0)
        emptyLbl:SetFont("GRID_UI_Header")
        emptyLbl:SetTextColor(Color(148, 163, 184))
        emptyLbl:SetText("No pending items in your collection box.")
        emptyLbl:SetContentAlignment(5)
        return
    end

    for _, item in ipairs(GRID.Auction.Collection) do
        local def = GRID.Inventory and GRID.Inventory.Items and GRID.Inventory.Items[item.item_id]
        local itemName = def and def.name or item.item_id
        local qualCol = GRID.Inventory and GRID.Inventory.GetQualityColor and GRID.Inventory.GetQualityColor(def and def.quality or 1) or Color(248, 250, 252)
        local badges = GRID.Auction.GetItemAttributeBadges(item.item_data)

        local reasonTag = "WON"
        local reasonCol = Color(74, 222, 128)
        if item.source_reason == "EXPIRED_AUCTION" then
            reasonTag = "EXPIRED"
            reasonCol = Color(245, 158, 11)
        elseif item.source_reason == "CANCELLED_AUCTION" then
            reasonTag = "CANCELLED"
            reasonCol = Color(239, 68, 68)
        end

        local card = scroll:Add("DPanel")
        card:Dock(TOP)
        card:DockMargin(0, 0, 0, 8)
        card:SetTall(74)

        card.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText(itemName, "GRID_UI_Sub", 16, 20, qualCol)

            surface.SetFont("GRID_UI_Badge")
            local rw = surface.GetTextSize(reasonTag) + 12
            draw.RoundedBox(3, 16, 42, rw, 20, Color(reasonCol.r, reasonCol.g, reasonCol.b, 35))
            draw.SimpleText(reasonTag, "GRID_UI_Badge", 16 + rw / 2, 52, reasonCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            local bx = 16 + rw + 8
            local by = 42
            for _, b in ipairs(badges) do
                surface.SetFont("GRID_UI_Badge")
                local bw = surface.GetTextSize(b.text) + 10
                draw.RoundedBox(3, bx, by, bw, 20, b.bg)
                draw.SimpleText(b.text, "GRID_UI_Badge", bx + bw / 2, by + 10, b.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                bx = bx + bw + 6
            end
        end

        local btnClaim = vgui.Create("DButton", card)
        btnClaim:SetSize(110, 36)
        btnClaim:SetPos(card:GetWide() - 124, 19)
        btnClaim:SetText("")
        card.PerformLayout = function(s, w, h)
            btnClaim:SetPos(w - 124, 19)
        end
        btnClaim.Paint = function(s, w, h)
            local isHov = s:IsHovered()
            draw.RoundedBox(4, 0, 0, w, h, isHov and Color(16, 185, 129, 240) or Color(16, 185, 129, 160))
            surface.SetDrawColor(16, 185, 129, 220)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            draw.SimpleText("Claim to Bag", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        btnClaim.DoClick = function()
            net.Start("GRID_Auction_ClaimItem")
            net.WriteUInt(item.collection_id, 32)
            net.SendToServer()
        end
    end
end
