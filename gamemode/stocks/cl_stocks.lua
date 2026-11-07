--[[
    gamemode/stocks/cl_stocks.lua
    GridRP Gang Stock Market - Interactive Line Chart, Live Ticker Marquee & Trade Interface
    Author: GRID Core Team & Antigravity
    Namespace: GRID.Stocks
--]]

GRID = GRID or {}
GRID.Stocks = GRID.Stocks or {}
GRID.Stocks.ClientListings = GRID.Stocks.ClientListings or {}
GRID.Stocks.ClientHistory = GRID.Stocks.ClientHistory or {}
GRID.Stocks.ClientPortfolios = GRID.Stocks.ClientPortfolios or {}

-- Network Receivers
net.Receive("GRID_Stock_SendListings", function()
    local count = net.ReadUInt(16)
    for i = 1, count do
        local gName = net.ReadString()
        GRID.Stocks.ClientListings[gName] = {
            gang_name = gName,
            ticker = net.ReadString(),
            total_shares = net.ReadUInt(16),
            issued_shares = net.ReadUInt(16),
            circulating_shares = net.ReadUInt(16),
            amm_reserve = net.ReadUInt(32),
            current_price = net.ReadUInt(32),
            price_24h_ago = net.ReadUInt(32),
            dividend_rate = net.ReadFloat(),
            dividend_arrears = net.ReadUInt(32),
            is_defaulted = net.ReadBool(),
            is_halted = net.ReadBool(),
            halt_secs = net.ReadUInt(16),
            received_at = CurTime()
        }
    end

    if IsValid(GRID.Stocks.ActiveATMExchangePanel) and GRID.Stocks.ActiveATMExchangePanel.RefreshView then
        GRID.Stocks.ActiveATMExchangePanel:RefreshView()
    end
end)

net.Receive("GRID_Stock_Delisted", function()
    local gName = net.ReadString()
    GRID.Stocks.ClientListings[gName] = nil
    if GRID.Stocks.ClientPortfolios then
        GRID.Stocks.ClientPortfolios[gName] = nil
    end

    if IsValid(GRID.Stocks.ActiveATMExchangePanel) then
        if GRID.Stocks.ActiveATMExchangePanel.SelectedGang == gName then
            GRID.Stocks.ActiveATMExchangePanel.SelectedGang = ""
        end
        if GRID.Stocks.ActiveATMExchangePanel.RefreshView then
            GRID.Stocks.ActiveATMExchangePanel:RefreshView()
        end
    end
end)

net.Receive("GRID_Stock_SendPortfolio", function()
    local count = net.ReadUInt(16)
    GRID.Stocks.ClientPortfolios = {}
    for i = 1, count do
        local gName = net.ReadString()
        GRID.Stocks.ClientPortfolios[gName] = {
            gang_name = gName,
            shares_owned = net.ReadUInt(16),
            avg_buy_price = net.ReadUInt(32),
            last_purchase_unix = net.ReadUInt(32),
            unclaimed_dividends = net.ReadUInt(32)
        }
    end

    if IsValid(GRID.Stocks.ActiveATMExchangePanel) and GRID.Stocks.ActiveATMExchangePanel.RefreshView then
        GRID.Stocks.ActiveATMExchangePanel:RefreshView()
    end
end)

net.Receive("GRID_Stock_SendHistory", function()
    local gName = net.ReadString()
    local count = net.ReadUInt(16)
    local points = {}
    for i = 1, count do
        table.insert(points, {
            timestamp = net.ReadUInt(32),
            price = net.ReadUInt(32),
            volume = net.ReadUInt(16)
        })
    end
    GRID.Stocks.ClientHistory[gName] = points

    if IsValid(GRID.Stocks.ActiveChartPanel) and GRID.Stocks.ActiveChartPanel.SelectedGang == gName then
        GRID.Stocks.ActiveChartPanel:SetHistoryData(points)
    end
end)

-- --------------------------------------------------------
-- 1. Live Marquee Ticker Bar
-- --------------------------------------------------------
function GRID.Stocks.CreateTickerBar(parent, w, h)
    local ticker = vgui.Create("DPanel", parent)
    ticker:SetSize(w, h or 36)
    ticker.ScrollOffset = 0

    ticker.Paint = function(s, pw, ph)
        draw.RoundedBox(4, 0, 0, pw, ph, Color(15, 23, 42, 240))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(0, 0, pw, ph, 1)

        local listings = {}
        for _, stock in pairs(GRID.Stocks.ClientListings) do
            table.insert(listings, stock)
        end
        table.sort(listings, function(a, b) return a.ticker < b.ticker end)

        if #listings == 0 then
            draw.SimpleText("MARKET STATUS: NO ACTIVE PUBLIC LISTINGS", "GRID_UI_Badge", 16, ph / 2, Color(148, 163, 184),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            return
        end

        s.ScrollOffset = s.ScrollOffset + (FrameTime() * 45)

        surface.SetFont("GRID_UI_Badge")
        local totalSpan = 0
        local blocks = {}
        for _, stock in ipairs(listings) do
            local change = stock.current_price - (stock.price_24h_ago or stock.current_price)
            local pct = (stock.price_24h_ago and stock.price_24h_ago > 0) and ((change / stock.price_24h_ago) * 100) or 0
            local signStr = change >= 0 and string.format("+%.1f%%", pct) or string.format("%.1f%%", pct)

            local statusStr = "ACTIVE"
            local statusCol = Color(52, 211, 153)
            if stock.is_defaulted then
                statusStr = "DEFAULTED"
                statusCol = Color(239, 68, 68)
            elseif stock.is_halted then
                statusStr = string.format("HALTED (%ds)", stock.halt_secs or 0)
                statusCol = Color(245, 158, 11)
            end

            local text = string.format("[%s] %s  $%s (%s)  |  %s", stock.ticker, string.upper(stock.gang_name),
                string.Comma(stock.current_price), signStr, statusStr)
            local tw = surface.GetTextSize(text) + 40
            table.insert(blocks, { text = text, width = tw, change = change, statusCol = statusCol })
            totalSpan = totalSpan + tw
        end

        if totalSpan <= 0 then return end
        local relOffset = s.ScrollOffset % totalSpan

        local renderX = -relOffset
        while renderX < pw do
            for _, b in ipairs(blocks) do
                if (renderX + b.width) > 0 and renderX < pw then
                    local fg = b.change >= 0 and Color(74, 222, 128) or Color(248, 113, 113)
                    draw.SimpleText(b.text, "GRID_UI_Badge", renderX, ph / 2, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                renderX = renderX + b.width
            end
        end
    end

    return ticker
end

-- --------------------------------------------------------
-- 2. Interactive Historical Canvas Line Chart
-- --------------------------------------------------------
function GRID.Stocks.CreateChartPanel(parent, w, h)
    local chart = vgui.Create("DPanel", parent)
    chart:SetSize(w, h)
    chart.SelectedGang = ""
    chart.HistoryData = {}
    chart.TimeframeHours = 24
    chart.HoverIndex = nil
    GRID.Stocks.ActiveChartPanel = chart

    function chart:SetGang(gangName)
        self.SelectedGang = gangName
        net.Start("GRID_Stock_RequestHistory")
        net.WriteString(gangName)
        net.WriteUInt(self.TimeframeHours, 16)
        net.SendToServer()
    end

    function chart:SetHistoryData(data)
        self.HistoryData = data or {}
    end

    chart.Paint = function(s, pw, ph)
        -- Background & border
        draw.RoundedBox(6, 0, 0, pw, ph, Color(11, 15, 25, 240))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(0, 0, pw, ph, 1)

        -- Chart geometry boundaries
        local padL, padR, padT, padB = 60, 20, 25, 35
        local plotW = pw - padL - padR
        local plotH = ph - padT - padB

        -- Inner graph bounding box
        draw.RoundedBox(4, padL, padT, plotW, plotH, Color(15, 23, 42, 180))
        surface.SetDrawColor(30, 41, 59, 140)
        surface.DrawOutlinedRect(padL, padT, plotW, plotH, 1)

        local data = s.HistoryData
        if not data or #data < 2 then
            draw.SimpleText("AWAITING HISTORICAL PRICE DATA...", "GRID_UI_Badge", pw / 2, ph / 2, Color(148, 163, 184),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end

        -- Calculate price bounds
        local minP, maxP = math.huge, -math.huge
        local minT, maxT = data[1].timestamp, data[#data].timestamp
        for _, pt in ipairs(data) do
            if pt.price < minP then minP = pt.price end
            if pt.price > maxP then maxP = pt.price end
        end

        if minP == maxP then
            minP = math.max(1, minP - 5)
            maxP = maxP + 5
        end

        local pRange = math.max(1, maxP - minP)
        local tRange = math.max(1, maxT - minT)

        -- Horizontal Grid Lines & Y-Axis Labels
        local gridSteps = 4
        for i = 0, gridSteps do
            local frac = i / gridSteps
            local gy = padT + (plotH * (1 - frac))
            surface.SetDrawColor(30, 41, 59, 120)
            surface.DrawLine(padL, gy, padL + plotW, gy)

            local pVal = math.Round(minP + (pRange * frac))
            draw.SimpleText("$" .. string.Comma(pVal), "GRID_UI_Caption", padL - 8, gy, Color(148, 163, 184),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        -- Compute screen points
        local screenPoints = {}
        for idx, pt in ipairs(data) do
            local xFrac = (pt.timestamp - minT) / tRange
            local yFrac = (pt.price - minP) / pRange
            local sx = padL + (xFrac * plotW)
            local sy = padT + (plotH * (1 - yFrac))
            table.insert(screenPoints, { x = sx, y = sy, data = pt, index = idx })
        end

        -- Render Line Segments
        local isUp = data[#data].price >= data[1].price
        local lineCol = isUp and Color(52, 211, 153) or Color(239, 68, 68)

        surface.SetDrawColor(lineCol.r, lineCol.g, lineCol.b, 230)
        for i = 1, #screenPoints - 1 do
            local p1 = screenPoints[i]
            local p2 = screenPoints[i + 1]
            surface.DrawLine(p1.x, p1.y, p2.x, p2.y)
            surface.DrawLine(p1.x, p1.y + 1, p2.x, p2.y + 1) -- Double thickness
        end

        -- Time Labels along X-Axis
        local t1Str = os.date("%H:%M", minT)
        local t2Str = os.date("%H:%M", maxT)
        draw.SimpleText(t1Str, "GRID_UI_Caption", padL, ph - 18, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(t2Str, "GRID_UI_Caption", padL + plotW, ph - 18, Color(148, 163, 184), TEXT_ALIGN_RIGHT,
            TEXT_ALIGN_CENTER)

        -- Interactive Mouse Cursor Crosshair & Tooltip
        local mx, my = s:CursorPos()
        s.HoverIndex = nil
        if mx >= padL and mx <= (padL + plotW) and my >= padT and my <= (padT + plotH) then
            local closestPt = nil
            local closestDist = math.huge
            for _, sp in ipairs(screenPoints) do
                local dist = math.abs(sp.x - mx)
                if dist < closestDist then
                    closestDist = dist
                    closestPt = sp
                end
            end

            if closestPt then
                s.HoverIndex = closestPt.index

                -- Vertical Crosshair Line
                surface.SetDrawColor(248, 250, 252, 100)
                surface.DrawLine(closestPt.x, padT, closestPt.x, padT + plotH)

                -- Crosshair point circle
                draw.RoundedBox(4, closestPt.x - 4, closestPt.y - 4, 8, 8, lineCol)

                -- Floating Tooltip (Min 340px width per ui_ux.md)
                local tipW, tipH = 340, 68
                local tipX = math.Clamp(closestPt.x - (tipW / 2), 10, pw - tipW - 10)
                local tipY = math.Clamp(closestPt.y - tipH - 12, 10, ph - tipH - 10)

                draw.RoundedBox(6, tipX, tipY, tipW, tipH, Color(11, 15, 25, 252))
                surface.SetDrawColor(lineCol.r, lineCol.g, lineCol.b, 200)
                surface.DrawOutlinedRect(tipX, tipY, tipW, tipH, 2)
                surface.SetDrawColor(30, 41, 59, 200)
                surface.DrawOutlinedRect(tipX + 2, tipY + 2, tipW - 4, tipH - 4, 1)

                local timeFormatted = os.date("%Y-%m-%d  %H:%M:%S", closestPt.data.timestamp)
                draw.SimpleText(timeFormatted, "GRID_UI_Caption", tipX + 12, tipY + 18, Color(148, 163, 184),
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("SPOT: $" .. string.Comma(closestPt.data.price), "GRID_UI_Header", tipX + 12, tipY + 44,
                    lineCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("Vol: " .. closestPt.data.volume, "GRID_UI_Badge", tipX + tipW - 14, tipY + 44,
                    Color(203, 213, 225), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end

    -- Timeframe Toggle Buttons (1H, 24H, 7D)
    local btnContainer = vgui.Create("DPanel", chart)
    btnContainer:SetSize(190, 24)
    btnContainer:SetPos(w - 200, 6)
    btnContainer.Paint = function() end

    local timeframes = { { label = "1H", hours = 1 }, { label = "24H", hours = 24 }, { label = "7D", hours = 168 } }
    local tBtnW = 58
    for i, tf in ipairs(timeframes) do
        local b = vgui.Create("DButton", btnContainer)
        b:SetPos((i - 1) * (tBtnW + 4), 0)
        b:SetSize(tBtnW, 22)
        b:SetText(tf.label)
        b:SetFont("GRID_UI_Badge")
        b.Paint = function(s, bw, bh)
            local active = (chart.TimeframeHours == tf.hours)
            local bg = active and Color(6, 182, 212, 200) or
                (s:IsHovered() and Color(51, 65, 85, 200) or Color(30, 41, 59, 160))
            draw.RoundedBox(4, 0, 0, bw, bh, bg)
            s:SetTextColor(active and Color(248, 250, 252) or Color(148, 163, 184))
        end
        b.DoClick = function()
            chart.TimeframeHours = tf.hours
            if chart.SelectedGang ~= "" then
                chart:SetGang(chart.SelectedGang)
            end
        end
    end

    return chart
end

-- --------------------------------------------------------
-- 3. ATM Stock Exchange Hub Tab
-- --------------------------------------------------------
function GRID.Stocks.CreateExchangeTab(parent, atmEnt)
    local container = vgui.Create("DPanel", parent)
    container:Dock(FILL)
    container.SelectedGang = ""
    GRID.Stocks.ActiveATMExchangePanel = container

    container.Paint = function(s, w, h)
        draw.RoundedBox(0, 0, 0, w, h, Color(11, 15, 25, 245))
    end

    -- Top Ticker Marquee Bar
    local tickerBar = GRID.Stocks.CreateTickerBar(container, 1040, 32)
    tickerBar:Dock(TOP)
    tickerBar:DockMargin(12, 8, 12, 6)

    -- Left Pane: Public Stock Listings Selector
    local leftPane = vgui.Create("DPanel", container)
    leftPane:Dock(LEFT)
    leftPane:SetWide(300)
    leftPane:DockMargin(12, 0, 8, 12)
    leftPane.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local leftBottomArea = vgui.Create("DPanel", leftPane)
    leftBottomArea:Dock(BOTTOM)
    leftBottomArea:SetTall(54)
    leftBottomArea.Paint = function() end

    local leftScroll = vgui.Create("DScrollPanel", leftPane)
    leftScroll:Dock(FILL)
    leftScroll.Paint = function() end

    -- Right Body Container (Chart + Trade Drawer)
    local rightBody = vgui.Create("DPanel", container)
    rightBody:Dock(FILL)
    rightBody:DockMargin(0, 0, 12, 12)
    rightBody.Paint = function() end

    -- Interactive Chart Panel
    local chart = GRID.Stocks.CreateChartPanel(rightBody, 700, 280)
    chart:Dock(TOP)
    chart:DockMargin(0, 0, 0, 8)

    -- Trade Drawer & Portfolio Panel
    local tradeDrawer = vgui.Create("DPanel", rightBody)
    tradeDrawer:Dock(FILL)
    tradeDrawer.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 200))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    function container:RefreshView()
        leftScroll:Clear()
        leftBottomArea:Clear()

        local listings = {}
        for _, stock in pairs(GRID.Stocks.ClientListings) do
            table.insert(listings, stock)
        end
        table.sort(listings, function(a, b) return (a.current_price or 0) > (b.current_price or 0) end)

        if #listings == 0 then
            local emptyLabel = leftScroll:Add("DLabel")
            emptyLabel:Dock(TOP)
            emptyLabel:DockMargin(16, 24, 16, 0)
            emptyLabel:SetTall(60)
            emptyLabel:SetFont("GRID_UI_Body")
            emptyLabel:SetWrap(true)
            emptyLabel:SetAutoStretchVertical(true)
            emptyLabel:SetText("No gangs are publicly listed.\n\nGang Leaders can list their gang on the stock exchange below.")
            emptyLabel:SetTextColor(Color(148, 163, 184))
        end

        for _, stock in ipairs(listings) do
            local item = leftScroll:Add("DButton")
            item:Dock(TOP)
            item:DockMargin(6, 4, 6, 2)
            item:SetTall(64)
            item:SetText("")

            local isSelected = (container.SelectedGang == stock.gang_name)
            item.Paint = function(s, w, h)
                local bg = isSelected and Color(30, 41, 59, 255) or
                    (s:IsHovered() and Color(24, 32, 47, 200) or Color(20, 29, 47, 160))
                draw.RoundedBox(6, 0, 0, w, h, bg)

                if isSelected then
                    draw.RoundedBox(2, 0, 6, 4, h - 12, Color(6, 182, 212))
                end

                local fg = stock.is_defaulted and Color(239, 68, 68) or
                    (stock.is_halted and Color(245, 158, 11) or Color(248, 250, 252))
                draw.SimpleText(stock.ticker, "GRID_UI_Header", 16, 20, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(GRID.UI.FitText(stock.gang_name, "GRID_UI_Caption", 160), "GRID_UI_Caption", 16, 44,
                    Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                -- Price & change
                draw.SimpleText("$" .. string.Comma(stock.current_price), "GRID_UI_Header", w - 16, 20,
                    Color(52, 211, 153), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                local change = stock.current_price - (stock.price_24h_ago or stock.current_price)
                local pct = (stock.price_24h_ago and stock.price_24h_ago > 0) and ((change / stock.price_24h_ago) * 100) or
                    0
                local signCol = change >= 0 and Color(74, 222, 128) or Color(248, 113, 113)
                draw.SimpleText(string.format("%s%.1f%%", change >= 0 and "+" or "", pct), "GRID_UI_Badge", w - 16, 44,
                    signCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end

            item.DoClick = function()
                container.SelectedGang = stock.gang_name
                chart:SetGang(stock.gang_name)
                container:BuildTradeDrawer(stock)
                container:RefreshView()
            end

            if container.SelectedGang == "" and #listings > 0 then
                container.SelectedGang = listings[1].gang_name
                chart:SetGang(listings[1].gang_name)
                container:BuildTradeDrawer(listings[1])
            end
        end

        -- Gang Leader Action Button anchored at bottom of left pane (IPO if unlisted, Buyback if listed)
        local p = LocalPlayer()
        local isLdr = IsValid(p) and
            (p:GetNWBool("GRID_IsGangLeader", false) or (p.GetJob and p:GetJob() == "gang_leader") or p:IsAdmin())
        local pGang = IsValid(p) and p:GetRawGang() or ""
        if isLdr and pGang ~= "" then
            local myStock = GRID.Stocks.ClientListings[pGang]
            if not myStock then
                leftBottomArea:SetVisible(true)
                local btnIPO = leftBottomArea:Add("DButton")
                btnIPO:Dock(FILL)
                btnIPO:DockMargin(8, 6, 8, 8)
                btnIPO:SetText("LAUNCH GANG IPO")
                btnIPO:SetFont("GRID_UI_Btn")
                btnIPO:SetTextColor(Color(248, 250, 252))
                btnIPO.Paint = function(s, w, h)
                    local isHov = s:IsHovered()
                    local bg = isHov and Color(245, 158, 11, 240) or Color(217, 119, 6, 200)
                    draw.RoundedBox(6, 0, 0, w, h, bg)
                    surface.SetDrawColor(251, 191, 36, isHov and 255 or 180)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)
                end
                btnIPO.DoClick = function()
                    container:OpenIPODialog(pGang)
                end
            elseif (myStock.issued_shares or 0) > 0 then
                leftBottomArea:SetVisible(true)
                local btnBuyback = leftBottomArea:Add("DButton")
                btnBuyback:Dock(FILL)
                btnBuyback:DockMargin(8, 6, 8, 8)
                btnBuyback:SetText("BUY BACK SHARES")
                btnBuyback:SetFont("GRID_UI_Btn")
                btnBuyback:SetTextColor(Color(248, 250, 252))
                btnBuyback.Paint = function(s, w, h)
                    local isHov = s:IsHovered()
                    local bg = isHov and Color(6, 182, 212, 240) or Color(8, 145, 178, 200)
                    draw.RoundedBox(6, 0, 0, w, h, bg)
                    surface.SetDrawColor(56, 189, 248, isHov and 255 or 180)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)
                end
                btnBuyback.DoClick = function()
                    container:OpenBuybackDialog(myStock)
                end
            else
                leftBottomArea:SetVisible(false)
            end
        else
            leftBottomArea:SetVisible(false)
        end
    end

    function container:BuildTradeDrawer(stock)
        tradeDrawer:Clear()
        if not stock then return end

        local p = LocalPlayer()
        local port = GRID.Stocks.ClientPortfolios[stock.gang_name] or
            { shares_owned = 0, avg_buy_price = 0, unclaimed_dividends = 0 }
        local isInsider = GRID.Stocks.IsPlayerInsider(p, stock.gang_name)
        local vesting = GRID.Stocks.GetVestingRemaining(port.last_purchase_unix, isInsider)

        -- Top Sub-Card: Portfolio Metrics & Claim Dividends
        local portCard = vgui.Create("DPanel", tradeDrawer)
        portCard:Dock(TOP)
        portCard:DockMargin(12, 10, 12, 8)
        portCard:SetTall(66)
        portCard.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(20, 29, 47, 230))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            local shares = port.shares_owned or 0
            local curVal = shares * (stock.current_price or 10)
            local invested = shares * (port.avg_buy_price or 10)
            local pnl = curVal - invested
            local pnlPct = invested > 0 and ((pnl / invested) * 100) or 0
            local pnlCol = pnl >= 0 and Color(74, 222, 128) or Color(248, 113, 113)

            draw.SimpleText("SHARES OWNED", "GRID_UI_Caption", 16, 18, Color(148, 163, 184), TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)
            draw.SimpleText(tostring(shares), "GRID_UI_Header", 16, 42, Color(248, 250, 252), TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)

            draw.SimpleText("POSITION VALUE", "GRID_UI_Caption", 140, 18, Color(148, 163, 184), TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)
            draw.SimpleText("$" .. string.Comma(curVal), "GRID_UI_Header", 140, 42, Color(52, 211, 153), TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)

            draw.SimpleText("UNREALIZED P&L", "GRID_UI_Caption", 300, 18, Color(148, 163, 184), TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("%s$%s (%.1f%%)", pnl >= 0 and "+" or "", string.Comma(pnl), pnlPct),
                "GRID_UI_Header", 300, 42, pnlCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        -- Action Buttons inside portCard (Claim Dividends and/or Leader Share Buyback)
        local isGangLeaderOfStock = isLdr and pGang ~= "" and (string.lower(pGang) == string.lower(stock.gang_name))
        local hasBuyback = isGangLeaderOfStock and (stock.issued_shares or 0) > 0
        local hasDividends = (port.unclaimed_dividends or 0) > 0
        local btnClaim, btnLeaderBuyback

        if hasDividends then
            btnClaim = vgui.Create("DButton", portCard)
            btnClaim:SetSize(180, 42)
            btnClaim:SetText("CLAIM DIVIDENDS ($" .. string.Comma(port.unclaimed_dividends) .. ")")
            btnClaim:SetFont("GRID_UI_Badge")
            btnClaim:SetTextColor(Color(248, 250, 252))
            btnClaim.Paint = function(s, w, h)
                local isHov = s:IsHovered()
                draw.RoundedBox(4, 0, 0, w, h, isHov and Color(16, 185, 129, 240) or Color(5, 150, 105, 200))
                surface.SetDrawColor(52, 211, 153, isHov and 255 or 180)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
            end
            btnClaim.DoClick = function()
                net.Start("GRID_Stock_ClaimDividends")
                net.WriteString(stock.gang_name)
                net.SendToServer()
            end
        end

        if hasBuyback then
            btnLeaderBuyback = vgui.Create("DButton", portCard)
            btnLeaderBuyback:SetSize(160, 42)
            btnLeaderBuyback:SetText("BUY BACK SHARES")
            btnLeaderBuyback:SetFont("GRID_UI_Badge")
            btnLeaderBuyback:SetTextColor(Color(248, 250, 252))
            btnLeaderBuyback.Paint = function(s, w, h)
                local isHov = s:IsHovered()
                draw.RoundedBox(4, 0, 0, w, h, isHov and Color(6, 182, 212, 240) or Color(8, 145, 178, 200))
                surface.SetDrawColor(56, 189, 248, isHov and 255 or 180)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
            end
            btnLeaderBuyback.DoClick = function()
                container:OpenBuybackDialog(stock)
            end
        end

        if btnClaim or btnLeaderBuyback then
            portCard.PerformLayout = function(s, w, h)
                local curRight = w - 16
                if IsValid(btnClaim) then
                    curRight = curRight - btnClaim:GetWide()
                    btnClaim:SetPos(curRight, 12)
                    curRight = curRight - 8
                end
                if IsValid(btnLeaderBuyback) then
                    curRight = curRight - btnLeaderBuyback:GetWide()
                    btnLeaderBuyback:SetPos(curRight, 12)
                end
            end
        end

        -- Trade Action Slider & Execution Form
        local form = vgui.Create("DPanel", tradeDrawer)
        form:Dock(FILL)
        form:DockMargin(12, 0, 12, 10)
        form.ShareCount = 1
        form.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(20, 29, 47, 230))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        local maxBuyable = math.max(0, (stock.issued_shares or 0) - (stock.circulating_shares or 0))

        -- Header row: Order Quantity on left, Shares Available indicator on right
        local headerRow = vgui.Create("DPanel", form)
        headerRow:Dock(TOP)
        headerRow:DockMargin(14, 6, 14, 0)
        headerRow:SetTall(22)
        headerRow.Paint = function(s, w, h)
            draw.SimpleText("ORDER QUANTITY", "GRID_UI_Badge", 0, h / 2, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            local availCol = maxBuyable > 0 and Color(52, 211, 153) or Color(248, 113, 113)
            local availText = maxBuyable > 0 and string.format("Shares Available: %s", string.Comma(maxBuyable)) or "Shares Available: 0 (SOLD OUT)"
            draw.SimpleText(availText, "GRID_UI_Badge", w, h / 2, availCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        local slider = vgui.Create("DNumSlider", form)
        slider:Dock(TOP)
        slider:DockMargin(14, 0, 14, 2)
        slider:SetTall(34)
        slider:SetText(string.format("Select Quantity (%s in stock)", string.Comma(maxBuyable)))
        slider:SetMin(1)
        slider:SetMax(math.max(1, math.max(maxBuyable, port.shares_owned or 0)))
        slider:SetDecimals(0)
        slider:SetValue(1)
        slider.OnValueChanged = function(s, val)
            form.ShareCount = math.max(1, math.Round(val))
        end

        -- Ensure slider label & text area match the Obsidian UI style
        if IsValid(slider.Label) then
            slider.Label:SetFont("GRID_UI_BodyBold")
            slider.Label:SetTextStyleColor(Color(248, 250, 252))
            slider.Label:SetTextColor(Color(248, 250, 252))
            slider.Label.UpdateColours = function(s)
                s:SetTextColor(Color(248, 250, 252))
            end
        end

        if IsValid(slider.TextArea) then
            slider.TextArea:SetFont("GRID_UI_BodyBold")
            slider.TextArea:SetTextColor(Color(248, 250, 252))
            slider.TextArea:SetWide(60)
            slider.TextArea.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(11, 15, 25, 245))
                surface.SetDrawColor(30, 41, 59, 220)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                s:DrawTextEntryText(Color(248, 250, 252), Color(6, 182, 212), Color(248, 250, 252))
            end
        end

        if IsValid(slider.Slider) then
            slider.Slider.Paint = function(s, w, h)
                local cy = math.floor(h / 2)
                draw.RoundedBox(2, 0, cy - 3, w, 6, Color(11, 15, 25, 255))
                surface.SetDrawColor(30, 41, 59, 255)
                surface.DrawOutlinedRect(0, cy - 3, w, 6, 1)

                local knobX = 0
                if IsValid(s.Knob) then
                    knobX = s.Knob:GetPos() + math.floor(s.Knob:GetWide() / 2)
                end
                if knobX > 0 then
                    draw.RoundedBox(2, 0, cy - 2, math.min(w, knobX), 4, Color(6, 182, 212, 200))
                end
            end
            if IsValid(slider.Slider.Knob) then
                slider.Slider.Knob:SetSize(16, 22)
                slider.Slider.Knob.Paint = function(s, w, h)
                    local isHov = s:IsHovered() or s:IsDown() or (s:GetParent() and s:GetParent().Dragging)
                    draw.RoundedBox(4, 0, 0, w, h, isHov and Color(56, 189, 248) or Color(6, 182, 212))
                    surface.SetDrawColor(248, 250, 252, isHov and 240 or 160)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)
                end
            end
        end

        local oldSliderLayout = slider.PerformLayout
        slider.PerformLayout = function(s)
            if oldSliderLayout then oldSliderLayout(s) end
            if IsValid(s.Label) then
                s.Label:SetWide(200)
            end
            if IsValid(s.TextArea) then
                s.TextArea:SetWide(60)
            end
        end

        -- Side-by-side Dual Quote Preview Cards (Buy Left / Sell Right)
        local previewRow = vgui.Create("DPanel", form)
        previewRow:Dock(TOP)
        previewRow:DockMargin(12, 2, 12, 6)
        previewRow:SetTall(56)
        previewRow.Paint = function() end

        local buyCard = vgui.Create("DPanel", previewRow)
        buyCard.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(11, 15, 25, 245))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            if maxBuyable <= 0 then
                -- Sold out state
                draw.RoundedBox(2, 0, 0, w, 2, Color(239, 68, 68, 200))
                draw.SimpleText("BUY QUOTE", "GRID_UI_Badge", 12, 14, Color(248, 113, 113), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("SOLD OUT", "GRID_UI_Badge", w - 12, 14, Color(239, 68, 68), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                draw.SimpleText("No shares available to purchase", "GRID_UI_Caption", 12, 38, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            elseif form.ShareCount > maxBuyable then
                -- Exceeds available limit
                draw.RoundedBox(2, 0, 0, w, 2, Color(245, 158, 11, 200))
                draw.SimpleText("BUY QUOTE", "GRID_UI_Badge", 12, 14, Color(245, 158, 11), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local availStr = string.format("Only %s Available", string.Comma(maxBuyable))
                draw.SimpleText(availStr, "GRID_UI_Badge", w - 12, 14, Color(251, 191, 36), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                local warnStr = string.format("Selected %s shares exceeds %s in stock", string.Comma(form.ShareCount), string.Comma(maxBuyable))
                draw.SimpleText(warnStr, "GRID_UI_Caption", 12, 38, Color(251, 191, 36), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            else
                -- Top accent line (Success Green)
                draw.RoundedBox(2, 0, 0, w, 2, Color(52, 211, 153, 200))

                local buyQ = GRID.Stocks.CalculateBuyQuote(stock, form.ShareCount)

                -- Line 1: Header Badge + Fee
                draw.SimpleText("ESTIMATED BUY COST", "GRID_UI_Badge", 12, 14, Color(52, 211, 153), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local feeStr = string.format("Broker Fee: $%s", string.Comma(buyQ.brokerFee))
                draw.SimpleText(feeStr, "GRID_UI_Caption", w - 12, 14, Color(148, 163, 184), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

                -- Line 2: Big Total Cost + Average Price per Share
                local costStr = string.format("$%s", string.Comma(buyQ.netTotalCost))
                draw.SimpleText(costStr, "GRID_UI_Sub", 12, 38, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local avgStr = string.format("$%s / share", string.Comma(buyQ.avgSharePrice))
                draw.SimpleText(avgStr, "GRID_UI_Caption", w - 12, 38, Color(203, 213, 225), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end

        local sellCard = vgui.Create("DPanel", previewRow)
        sellCard.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(11, 15, 25, 245))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            local owned = port.shares_owned or 0
            local sellQ = GRID.Stocks.CalculateSellQuote(stock, form.ShareCount, isInsider)

            if vesting > 0 then
                -- Top accent line (Warning Amber)
                draw.RoundedBox(2, 0, 0, w, 2, Color(245, 158, 11, 220))
                draw.SimpleText("SELL ESTIMATE", "GRID_UI_Badge", 12, 14, Color(245, 158, 11), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("[!] LOCKED", "GRID_UI_Badge", w - 12, 14, Color(245, 158, 11), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                local lockStr = string.format("Vesting Lock: %ds remaining", vesting)
                draw.SimpleText(lockStr, "GRID_UI_BodyBold", 12, 38, Color(251, 191, 36), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            elseif owned < form.ShareCount then
                -- Muted state (Cannot afford or insufficient shares)
                draw.RoundedBox(2, 0, 0, w, 2, Color(71, 85, 105, 180))
                draw.SimpleText("SELL ESTIMATE", "GRID_UI_Badge", 12, 14, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local needStr = string.format("Need %s shares", string.Comma(form.ShareCount))
                draw.SimpleText(needStr, "GRID_UI_Caption", w - 12, 14, Color(148, 163, 184), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                local ownStr = string.format("Only own %s shares", string.Comma(owned))
                draw.SimpleText(ownStr, "GRID_UI_Body", 12, 38, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            else
                -- Active Sell proceeds
                draw.RoundedBox(2, 0, 0, w, 2, Color(239, 68, 68, 200))
                draw.SimpleText("ESTIMATED PROCEEDS", "GRID_UI_Badge", 12, 14, Color(248, 113, 113), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local feeStr = string.format("Fee: -$%s", string.Comma(sellQ.brokerFee))
                draw.SimpleText(feeStr, "GRID_UI_Caption", w - 12, 14, Color(148, 163, 184), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

                local proceedsStr = string.format("+$%s", string.Comma(sellQ.netProceeds))
                draw.SimpleText(proceedsStr, "GRID_UI_Sub", 12, 38, Color(74, 222, 128), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local slipStr = string.format("Impact: -%.1f%%", sellQ.priceImpactPct)
                draw.SimpleText(slipStr, "GRID_UI_Caption", w - 12, 38, Color(203, 213, 225), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end

        previewRow.PerformLayout = function(s, w, h)
            local halfW = math.floor((w - 8) / 2)
            buyCard:SetSize(halfW, h)
            buyCard:SetPos(0, 0)
            sellCard:SetSize(halfW, h)
            sellCard:SetPos(w - halfW, 0)
        end

        -- Buy & Sell Action Buttons
        local btnRow = vgui.Create("DPanel", form)
        btnRow:Dock(TOP)
        btnRow:DockMargin(12, 0, 12, 6)
        btnRow:SetTall(42)
        btnRow.Paint = function() end

        local btnBuy = vgui.Create("DButton", btnRow)
        btnBuy:SetText("BUY SHARES")
        btnBuy:SetFont("GRID_UI_Btn")
        btnBuy.Paint = function(s, w, h)
            local canBuy = maxBuyable > 0 and form.ShareCount <= maxBuyable
            local isHov = s:IsHovered() and canBuy
            local bg = not canBuy and Color(30, 41, 59, 200) or
                (isHov and Color(16, 185, 129, 240) or Color(5, 150, 105, 200))
            draw.RoundedBox(6, 0, 0, w, h, bg)

            local borderCol = not canBuy and Color(51, 65, 85, 220) or
                (isHov and Color(52, 211, 153, 255) or Color(16, 185, 129, 180))
            surface.SetDrawColor(borderCol)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            local txtCol = canBuy and Color(248, 250, 252) or Color(148, 163, 184)
            s:SetTextColor(txtCol)
        end
        btnBuy.DoClick = function()
            if maxBuyable <= 0 or form.ShareCount > maxBuyable then return end
            net.Start("GRID_Stock_Buy")
            net.WriteString(stock.gang_name)
            net.WriteUInt(form.ShareCount, 16)
            net.SendToServer()
        end

        local btnSell = vgui.Create("DButton", btnRow)
        btnSell:SetText("SELL SHARES")
        btnSell:SetFont("GRID_UI_Btn")
        btnSell.Paint = function(s, w, h)
            local owned = port.shares_owned or 0
            local canSell = owned >= form.ShareCount and vesting <= 0
            local isHov = s:IsHovered() and canSell
            local bg = not canSell and Color(30, 41, 59, 200) or
                (isHov and Color(239, 68, 68, 240) or Color(220, 38, 38, 200))
            draw.RoundedBox(6, 0, 0, w, h, bg)

            local borderCol = not canSell and Color(51, 65, 85, 220) or
                (isHov and Color(248, 113, 113, 255) or Color(239, 68, 68, 180))
            surface.SetDrawColor(borderCol)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            local txtCol = canSell and Color(248, 250, 252) or Color(148, 163, 184)
            s:SetTextColor(txtCol)
        end
        btnSell.DoClick = function()
            local owned = port.shares_owned or 0
            local canSell = owned >= form.ShareCount and vesting <= 0
            if not canSell then return end
            net.Start("GRID_Stock_Sell")
            net.WriteString(stock.gang_name)
            net.WriteUInt(form.ShareCount, 16)
            net.SendToServer()
        end

        btnRow.PerformLayout = function(s, w, h)
            local halfW = math.floor((w - 8) / 2)
            btnBuy:SetSize(halfW, h)
            btnBuy:SetPos(0, 0)
            btnSell:SetSize(halfW, h)
            btnSell:SetPos(w - halfW, 0)
        end
    end

    local function StyleExchangeSlider(s)
        if IsValid(s.Label) then
            s.Label:SetVisible(false)
            s.Label:SetWide(0)
        end
        if IsValid(s.TextArea) then
            s.TextArea:SetFont("GRID_UI_Caption")
            s.TextArea:SetTextColor(Color(248, 250, 252))
            s.TextArea:SetWide(50)
            s.TextArea.Paint = function(te, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(11, 15, 25, 245))
                surface.SetDrawColor(30, 41, 59, 220)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                te:DrawTextEntryText(Color(248, 250, 252), Color(6, 182, 212), Color(248, 250, 252))
            end
        end
        if IsValid(s.Slider) then
            s.Slider.Paint = function(sl, w, h)
                local cy = math.floor(h / 2)
                draw.RoundedBox(2, 0, cy - 3, w, 6, Color(11, 15, 25, 255))
                surface.SetDrawColor(30, 41, 59, 255)
                surface.DrawOutlinedRect(0, cy - 3, w, 6, 1)
                local knobX = 0
                if IsValid(sl.Knob) then
                    knobX = sl.Knob:GetPos() + math.floor(sl.Knob:GetWide() / 2)
                end
                if knobX > 0 then
                    draw.RoundedBox(2, 0, cy - 2, math.min(w, knobX), 4, Color(6, 182, 212, 200))
                end
            end
            if IsValid(s.Slider.Knob) then
                s.Slider.Knob:SetSize(14, 20)
                s.Slider.Knob.Paint = function(kb, w, h)
                    local isHov = kb:IsHovered() or kb:IsDown() or (kb:GetParent() and kb:GetParent().Dragging)
                    draw.RoundedBox(4, 0, 0, w, h, isHov and Color(56, 189, 248) or Color(6, 182, 212))
                    surface.SetDrawColor(248, 250, 252, isHov and 240 or 160)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)
                end
            end
        end
    end

    function container:OpenIPODialog(gangName)
        local dlg = vgui.Create("DFrame")
        dlg:SetSize(520, 510)
        dlg:Center()
        dlg:SetTitle("")
        dlg:MakePopup()
        dlg:ShowCloseButton(true)
        dlg.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(11, 15, 25, 252))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            -- Header
            draw.SimpleText("INITIAL PUBLIC OFFERING (IPO)", "GRID_UI_Header", 20, 16, Color(248, 250, 252))
            draw.SimpleText("List '" .. gangName .. "' on the public exchange", "GRID_UI_Caption", 20, 40,
                Color(148, 163, 184))

            -- Divider
            surface.SetDrawColor(30, 41, 59, 255)
            surface.DrawLine(20, 66, w - 20, 66)
        end

        -- Ticker Symbol
        local lblTicker = vgui.Create("DLabel", dlg)
        lblTicker:SetPos(20, 76)
        lblTicker:SetText("Stock Ticker Symbol (3-5 Letters):")
        lblTicker:SetFont("GRID_UI_BodyBold")
        lblTicker:SetTextColor(Color(248, 250, 252))
        lblTicker:SizeToContents()

        local teTicker = vgui.Create("DTextEntry", dlg)
        teTicker:SetPos(20, 98)
        teTicker:SetSize(480, 32)
        teTicker:SetFont("GRID_UI_Header")
        teTicker:SetText(string.upper(string.sub(gangName, 1, 4)))

        -- Shares for Sale
        local lblSharesSaleTitle = vgui.Create("DLabel", dlg)
        lblSharesSaleTitle:SetPos(20, 142)
        lblSharesSaleTitle:SetText("Shares for Sale: 30% (300 / 1,000 Shares)")
        lblSharesSaleTitle:SetFont("GRID_UI_BodyBold")
        lblSharesSaleTitle:SetTextColor(Color(248, 250, 252))
        lblSharesSaleTitle:SizeToContents()

        local lblSharesSaleDesc = vgui.Create("DLabel", dlg)
        lblSharesSaleDesc:SetPos(20, 164)
        lblSharesSaleDesc:SetSize(480, 36)
        lblSharesSaleDesc:SetWrap(true)
        lblSharesSaleDesc:SetFont("GRID_UI_Caption")
        lblSharesSaleDesc:SetTextColor(Color(148, 163, 184))
        lblSharesSaleDesc:SetText(
            "Portion of your gang sold to players. Higher % raises more upfront cash for your gang vault, but increases your ongoing dividend payout obligation.")

        local sliderSharesSale = vgui.Create("DNumSlider", dlg)
        sliderSharesSale:SetPos(20, 202)
        sliderSharesSale:SetSize(480, 32)
        sliderSharesSale:SetText("")
        sliderSharesSale:SetMin(10)
        sliderSharesSale:SetMax(49)
        sliderSharesSale:SetDecimals(0)
        sliderSharesSale:SetValue(30)
        StyleExchangeSlider(sliderSharesSale)

        local divInterval = (GRID.Config and GRID.Config.Stocks and GRID.Config.Stocks.DividendInterval) or 900
        local divMins = math.max(1, math.Round(divInterval / 60))

        -- Cycle Dividend Rate (Shareholder Payout)
        local lblDivTitle = vgui.Create("DLabel", dlg)
        lblDivTitle:SetPos(20, 244)
        lblDivTitle:SetText(string.format("Payout to Shareholders: 3.0%% every %d minutes", divMins))
        lblDivTitle:SetFont("GRID_UI_BodyBold")
        lblDivTitle:SetTextColor(Color(248, 250, 252))
        lblDivTitle:SizeToContents()

        local lblDivDesc = vgui.Create("DLabel", dlg)
        lblDivDesc:SetPos(20, 266)
        lblDivDesc:SetSize(480, 36)
        lblDivDesc:SetWrap(true)
        lblDivDesc:SetFont("GRID_UI_Caption")
        lblDivDesc:SetTextColor(Color(148, 163, 184))
        lblDivDesc:SetText(
            string.format("Percentage of share price paid to online investors from gang vault every %dm. WARNING: If vault runs dry, stock defaults!", divMins))

        local sliderDiv = vgui.Create("DNumSlider", dlg)
        sliderDiv:SetPos(20, 304)
        sliderDiv:SetSize(480, 32)
        sliderDiv:SetText("")
        sliderDiv:SetMin(2)
        sliderDiv:SetMax(5)
        sliderDiv:SetDecimals(1)
        sliderDiv:SetValue(3)
        StyleExchangeSlider(sliderDiv)

        -- Connect slider value changes to update title labels
        sliderSharesSale.OnValueChanged = function(s, val)
            local rounded = math.Round(val)
            lblSharesSaleTitle:SetText(string.format("Shares for Sale: %d%% (%d / 1,000 Shares)", rounded, rounded * 10))
            lblSharesSaleTitle:SizeToContents()
        end

        sliderDiv.OnValueChanged = function(s, val)
            lblDivTitle:SetText(string.format("Payout to Shareholders: %.1f%% every %d minutes", val, divMins))
            lblDivTitle:SizeToContents()
        end

        -- Preview Card
        local pnlPreview = vgui.Create("DPanel", dlg)
        pnlPreview:SetPos(20, 348)
        pnlPreview:SetSize(480, 68)
        pnlPreview.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(20, 29, 47, 230))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            local saleVal = sliderSharesSale:GetValue()
            local divVal = sliderDiv:GetValue()
            local shares = math.Round(saleVal * 10)
            -- Rough estimate based on base price ($100)
            local estCap = shares * 100
            local estDiv15 = math.Round(shares * (100 * (divVal / 100)))

            draw.SimpleText("Estimated Upfront Capital Raised: ~$" .. string.Comma(estCap), "GRID_UI_Caption", 12, 14,
                Color(52, 211, 153))
            draw.SimpleText(string.format("Estimated %dm Dividend Burden: ~$%s / cycle", divMins, string.Comma(estDiv15)),
                "GRID_UI_Caption", 12, 38, Color(251, 191, 36))
        end

        -- Confirm Button
        local btnConfirm = vgui.Create("DButton", dlg)
        btnConfirm:SetPos(20, 432)
        btnConfirm:SetSize(480, 48)
        btnConfirm:SetText("LAUNCH PUBLIC LISTING ($1,500 + 3% VAULT)")
        btnConfirm:SetFont("GRID_UI_Btn")
        btnConfirm:SetTextColor(Color(248, 250, 252))
        btnConfirm.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(245, 158, 11, 240) or Color(217, 119, 6, 200))
        end
        btnConfirm.DoClick = function()
            local ticker = string.upper(string.Trim(teTicker:GetValue()))
            local sharesForSalePct = sliderSharesSale:GetValue() / 100
            local divRate = sliderDiv:GetValue() / 100
            net.Start("GRID_Stock_IPO")
            net.WriteString(ticker)
            net.WriteFloat(sharesForSalePct)
            net.WriteFloat(divRate)
            net.SendToServer()
            dlg:Close()
        end
    end

    function container:OpenBuybackDialog(stock)
        if not stock then return end
        local dlg = vgui.Create("DFrame")
        dlg:SetSize(520, 440)
        dlg:Center()
        dlg:SetTitle("")
        dlg:MakePopup()
        dlg:ShowCloseButton(true)
        dlg.Paint = function(s, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(11, 15, 25, 252))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            -- Header
            draw.SimpleText("GANG SHARE BUYBACK", "GRID_UI_Header", 20, 16, Color(248, 250, 252))
            draw.SimpleText("Retire public shares of " .. tostring(stock.gang_name) .. " [" .. tostring(stock.ticker) .. "]", "GRID_UI_Caption", 20, 40, Color(148, 163, 184))

            -- Divider
            surface.SetDrawColor(30, 41, 59, 255)
            surface.DrawLine(20, 66, w - 20, 66)
        end

        local issued = stock.issued_shares or 0
        local spotPrice = stock.current_price or 10

        local divInterval = (GRID.Config and GRID.Config.Stocks and GRID.Config.Stocks.DividendInterval) or 900
        local divMins = math.max(1, math.Round(divInterval / 60))

        -- Metrics Info Card (Shares for Sale / Spot Price / Dividend Rate)
        local pnlInfo = vgui.Create("DPanel", dlg)
        pnlInfo:SetPos(20, 78)
        pnlInfo:SetSize(480, 66)
        pnlInfo.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(20, 29, 47, 230))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText("SHARES FOR SALE", "GRID_UI_Caption", 16, 18, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("%d / 1,000", issued), "GRID_UI_Header", 16, 42, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            draw.SimpleText("SPOT SHARE PRICE", "GRID_UI_Caption", 180, 18, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("$" .. string.Comma(spotPrice), "GRID_UI_Header", 180, 42, Color(52, 211, 153), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            draw.SimpleText(string.format("%dM DIVIDEND RATE", divMins), "GRID_UI_Caption", 340, 18, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("%.1f%%", (stock.dividend_rate or 0.03) * 100), "GRID_UI_Header", 340, 42, Color(251, 191, 36), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        -- Slider Title
        local initQty = math.min(10, math.max(1, issued))
        local lblQtyTitle = vgui.Create("DLabel", dlg)
        lblQtyTitle:SetPos(20, 154)
        lblQtyTitle:SetFont("GRID_UI_BodyBold")
        lblQtyTitle:SetTextColor(Color(248, 250, 252))
        lblQtyTitle:SetText(string.format("Shares to Buy Back & Retire: %d Shares", initQty))
        lblQtyTitle:SizeToContents()

        local lblQtyDesc = vgui.Create("DLabel", dlg)
        lblQtyDesc:SetPos(20, 176)
        lblQtyDesc:SetSize(480, 36)
        lblQtyDesc:SetWrap(true)
        lblQtyDesc:SetFont("GRID_UI_Caption")
        lblQtyDesc:SetTextColor(Color(148, 163, 184))
        lblQtyDesc:SetText("Bought back using gang vault funds. Retired shares reduce public ownership and permanently decrease ongoing dividend obligations.")

        local sliderBuyback = vgui.Create("DNumSlider", dlg)
        sliderBuyback:SetPos(20, 214)
        sliderBuyback:SetSize(480, 32)
        sliderBuyback:SetText("")
        sliderBuyback:SetMin(1)
        sliderBuyback:SetMax(math.max(1, issued))
        sliderBuyback:SetDecimals(0)
        sliderBuyback:SetValue(initQty)
        StyleExchangeSlider(sliderBuyback)

        sliderBuyback.OnValueChanged = function(s, val)
            local qty = math.Clamp(math.Round(val), 1, math.max(1, issued))
            lblQtyTitle:SetText(string.format("Shares to Buy Back & Retire: %d Shares", qty))
            lblQtyTitle:SizeToContents()
        end

        -- Live Preview Card
        local pnlPreview = vgui.Create("DPanel", dlg)
        pnlPreview:SetPos(20, 258)
        pnlPreview:SetSize(480, 78)
        pnlPreview.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(20, 29, 47, 230))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            local qty = math.Clamp(math.Round(sliderBuyback:GetValue()), 1, math.max(1, issued))
            local totalCost = qty * spotPrice
            local remainingIssued = math.max(0, issued - qty)
            local divSaved = math.Round(qty * (spotPrice * (stock.dividend_rate or 0.03)))

            -- Top accent strip (Cyan)
            draw.RoundedBox(2, 0, 0, w, 2, Color(6, 182, 212, 220))

            draw.SimpleText("Total Cost from Gang Vault: $" .. string.Comma(totalCost), "GRID_UI_BodyBold", 14, 18, Color(248, 250, 252))
            draw.SimpleText(string.format("Remaining Shares for Sale: %d / 1,000", remainingIssued), "GRID_UI_Caption", 14, 40, Color(203, 213, 225))
            draw.SimpleText(string.format("Estimated Dividend Savings: ~$%s saved every %dm", string.Comma(divSaved), divMins), "GRID_UI_Caption", 14, 60, Color(52, 211, 153))
        end

        -- Action Button
        local btnConfirm = vgui.Create("DButton", dlg)
        btnConfirm:SetPos(20, 350)
        btnConfirm:SetSize(480, 48)
        btnConfirm:SetText("CONFIRM SHARE BUYBACK")
        btnConfirm:SetFont("GRID_UI_Btn")
        btnConfirm:SetTextColor(Color(248, 250, 252))
        btnConfirm.Paint = function(s, w, h)
            local isHov = s:IsHovered()
            draw.RoundedBox(6, 0, 0, w, h, isHov and Color(6, 182, 212, 240) or Color(8, 145, 178, 200))
            surface.SetDrawColor(56, 189, 248, isHov and 255 or 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
        btnConfirm.DoClick = function()
            local qty = math.Clamp(math.Round(sliderBuyback:GetValue()), 1, math.max(1, issued))
            net.Start("GRID_Stock_LeaderBuyback")
            net.WriteUInt(qty, 16)
            net.SendToServer()
            dlg:Close()
        end
    end

    -- Initial load trigger
    net.Start("GRID_Stock_RequestListings")
    net.SendToServer()
    net.Start("GRID_Stock_RequestPortfolio")
    net.SendToServer()

    container:RefreshView()
    return container
end
