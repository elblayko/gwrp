--[[
    gamemode/stocks/sv_stocks.lua
    GridRP Gang Stock Market - Server Engine, AMM Liquidity, Valuation & Circuit Breakers
    Author: GRID Core Team & Antigravity
    Namespace: GRID.Stocks
--]]

GRID = GRID or {}
GRID.Stocks = GRID.Stocks or {}
GRID.Stocks.Listings = GRID.Stocks.Listings or {}
GRID.Stocks.CircuitBreakers = GRID.Stocks.CircuitBreakers or {}
GRID.Stocks.RecentDeaths = GRID.Stocks.RecentDeaths or {}
GRID.Stocks.PairKills = GRID.Stocks.PairKills or {}
GRID.Stocks.PendingSnapshots = GRID.Stocks.PendingSnapshots or {}

-- --------------------------------------------------------
-- 1. In-Memory Cache Initialization & Snapshot Timer
-- --------------------------------------------------------

function GRID.Stocks.Init()
    GRID.Database.LoadAllStocks(function(rows)
        for _, r in ipairs(rows or {}) do
            local gName = r.gang_name
            GRID.Stocks.Listings[gName] = {
                gang_name = gName,
                ticker = r.ticker,
                total_shares = tonumber(r.total_shares) or 1000,
                issued_shares = tonumber(r.issued_shares) or 0,
                circulating_shares = tonumber(r.circulating_shares) or 0,
                amm_reserve = tonumber(r.amm_reserve) or 0,
                ipo_capital_raised = tonumber(r.ipo_capital_raised) or 0,
                base_price = tonumber(r.base_price) or 10,
                current_price = tonumber(r.current_price) or 10,
                price_24h_ago = tonumber(r.price_24h_ago) or 10,
                sentiment_mult = tonumber(r.sentiment_mult) or 1.0,
                dividend_rate = tonumber(r.dividend_rate) or 0.03,
                dividend_arrears = tonumber(r.dividend_arrears) or 0,
                is_defaulted = (tonumber(r.is_defaulted) == 1 or r.is_defaulted == true),
                created_at_unix = tonumber(r.created_at_unix) or os.time(),
                updated_at_unix = tonumber(r.updated_at_unix) or os.time()
            }
        end
        print(string.format("[GRID STOCKS] Loaded %d public gang stock listings from database.", table.Count(GRID.Stocks.Listings)))
    end)

    -- Periodic 5-minute history snapshot + sentiment decay timer
    timer.Create("GRID_Stocks_SnapshotTimer", (GRID.Config and GRID.Config.Stocks and GRID.Config.Stocks.HistorySnapshotInterval) or 300, 0, function()
        GRID.Stocks.ProcessSnapshotCycle()
    end)

    -- Periodic 15-minute dividend distribution & insolvency sweep
    timer.Create("GRID_Stocks_DividendTimer", (GRID.Config and GRID.Config.Stocks and GRID.Config.Stocks.DividendInterval) or 900, 0, function()
        GRID.Stocks.ProcessDividendCycle()
    end)
end

hook.Add("GRID_DatabaseConnected", "GRID_Stocks_DatabaseReady", function()
    GRID.Stocks.Init()
end)

-- --------------------------------------------------------
-- 2. Circuit Breakers & Trading Halts
-- --------------------------------------------------------

function GRID.Stocks.IsTradingHalted(gangName)
    local haltUntil = GRID.Stocks.CircuitBreakers[gangName]
    if haltUntil and haltUntil > CurTime() then
        return true, math.ceil(haltUntil - CurTime())
    end
    return false, 0
end

function GRID.Stocks.TriggerCombatHalt(gangName, duration, reason)
    if not gangName or gangName == "" then return end
    duration = duration or (GRID.Config.Stocks and GRID.Config.Stocks.CombatHaltDuration) or 90
    local curHalt = GRID.Stocks.CircuitBreakers[gangName] or 0
    local newHalt = math.max(curHalt, CurTime() + duration)
    GRID.Stocks.CircuitBreakers[gangName] = newHalt

    local stock = GRID.Stocks.Listings[gangName]
    if stock then
        GRID.Stocks.BroadcastStockUpdate(gangName)
        for _, p in ipairs(player.GetAll()) do
            if string.lower(p:GetRawGang()) == string.lower(gangName) then
                GRID.Notify(p, string.format("[CIRCUIT BREAKER] %s trading HALTED for %ds! Reason: %s", stock.ticker, duration, reason or "Combat Incursion"), NOTIFY_ERROR, 5)
            end
        end
        if GRID.Telemetry and GRID.Telemetry.Log then
            GRID.Telemetry.Log("ECONOMY", "STOCK_CIRCUIT_BREAKER", "CONSOLE", gangName, duration, { reason = reason or "combat" })
        end
    end
end

-- --------------------------------------------------------
-- 3. Valuation Engine & Fundamental Anchor
-- --------------------------------------------------------

function GRID.Stocks.RecalculateGangPrice(gangName, reason)
    local stock = GRID.Stocks.Listings[gangName]
    if not stock then return end

    local gData = GRID.Database and GRID.Database.GetGang and GRID.Database.GetGang(gangName)
    local vaultCash = gData and tonumber(gData.bank) or 0
    local ammCash = stock.amm_reserve or 0

    local turfCount = 0
    if GRID.Turf and GRID.Turf.Zones then
        for _, z in pairs(GRID.Turf.Zones) do
            if z.owner and string.lower(z.owner) == string.lower(gangName) then
                turfCount = turfCount + 1
            end
        end
    end

    local cfg = GRID.Config.Stocks or {}
    local turfValue = cfg.TurfBaseValuation or 2500
    local totalValuation = math.max(5000, vaultCash + ammCash + (turfCount * turfValue))
    local totalShares = math.max(1, stock.total_shares or 1000)

    -- Fundamental Base Price
    local basePrice = math.max(5, math.Round(totalValuation / totalShares))
    stock.base_price = basePrice

    -- Sentiment Multiplier clamped 0.35x to 2.00x
    local sentiment = math.Clamp(tonumber(stock.sentiment_mult) or 1.0, 0.35, 2.00)
    stock.sentiment_mult = sentiment

    local defaultMod = stock.is_defaulted and (cfg.DefaultMultiplier or 0.50) or 1.00
    local spotPrice = math.max(5, math.Round(basePrice * sentiment * defaultMod))
    local oldPrice = stock.current_price or spotPrice
    stock.current_price = spotPrice
    stock.updated_at_unix = os.time()

    GRID.Database.SaveStockListing(stock)
    GRID.Stocks.BroadcastStockUpdate(gangName)

    -- Check if price moved >= 3% to log a throttled snapshot
    local pctChange = math.abs((spotPrice - oldPrice) / math.max(1, oldPrice))
    if pctChange >= 0.03 then
        local lastSnap = GRID.Stocks.PendingSnapshots[gangName] or 0
        if (CurTime() - lastSnap) >= 60 then
            GRID.Stocks.PendingSnapshots[gangName] = CurTime()
            GRID.Database.LogStockHistory(gangName, spotPrice, 0)
        end
    end
end

function GRID.Stocks.AdjustSentiment(gangName, deltaPct, reason)
    local stock = GRID.Stocks.Listings[gangName]
    if not stock then return end

    local current = stock.sentiment_mult or 1.0
    stock.sentiment_mult = math.Clamp(current + deltaPct, 0.35, 2.00)
    GRID.Stocks.RecalculateGangPrice(gangName, reason)
end

function GRID.Stocks.ProcessSnapshotCycle()
    local now = os.time()
    local cfg = GRID.Config and GRID.Config.Stocks
    local decayRate = (cfg and cfg.SentimentDecayRate) or 0.10

    for gangName, stock in pairs(GRID.Stocks.Listings) do
        -- Mean reversion decay toward 1.00x fundamental sentiment baseline
        local curSent = stock.sentiment_mult or 1.0
        stock.sentiment_mult = curSent + ((1.0 - curSent) * decayRate)
        GRID.Stocks.RecalculateGangPrice(gangName, "sentiment_decay")

        -- Log historical snapshot
        GRID.Database.LogStockHistory(gangName, stock.current_price, 0)
    end
end

-- --------------------------------------------------------
-- 4. Dividend Engine, Insolvency & Auto-Garnishment
-- --------------------------------------------------------

function GRID.Stocks.ProcessDividendCycle()
    for gangName, stock in pairs(GRID.Stocks.Listings) do
        local circulating = stock.circulating_shares or 0
        if circulating > 0 then
            local spot = stock.current_price or 10
            local divRate = stock.dividend_rate or 0.03
            local divPerShare = math.max(1, math.Round(spot * divRate))

            -- Find currently online shareholders for this gang
            local onlineHolders = {}
            local totalOnlineShares = 0
            for _, ply in ipairs(player.GetAll()) do
                if ply.GRID_StockPortfolios and ply.GRID_StockPortfolios[gangName] then
                    local pData = ply.GRID_StockPortfolios[gangName]
                    local shares = tonumber(pData.shares_owned) or 0
                    if shares > 0 then
                        table.insert(onlineHolders, { ply = ply, shares = shares, port = pData })
                        totalOnlineShares = totalOnlineShares + shares
                    end
                end
            end

            local totalDivObligation = totalOnlineShares * divPerShare
            local gData = GRID.Database.GetGang(gangName)
            local currentVault = gData and tonumber(gData.bank) or 0

            if currentVault >= totalDivObligation then
                -- Solvent payout
                if totalDivObligation > 0 then
                    GRID.Database.AddGangBank(gangName, -totalDivObligation)
                    for _, h in ipairs(onlineHolders) do
                        local payout = h.shares * divPerShare
                        h.port.unclaimed_dividends = (h.port.unclaimed_dividends or 0) + payout
                        GRID.Database.SaveStockPortfolio(h.ply:SteamID(), gangName, h.shares, h.port.avg_buy_price, h.port.last_purchase_unix, h.port.unclaimed_dividends)
                        GRID.Notify(h.ply, string.format("[%s DIVIDEND] Earned +$%s in unclaimed dividends (Total Unclaimed: $%s). Claim at an ATM!", stock.ticker, string.Comma(payout), string.Comma(h.port.unclaimed_dividends)), NOTIFY_GENERIC, 6)
                    end
                end

                -- If gang was in default and has 0 arrears, clear default
                if stock.is_defaulted and (stock.dividend_arrears or 0) <= 0 then
                    stock.is_defaulted = false
                    stock.dividend_arrears = 0
                    for _, p in ipairs(player.GetAll()) do
                        if string.lower(p:GetRawGang()) == string.lower(gangName) then
                            p:RemoveBuff("syndicate_insolvency", "cleansed")
                        end
                    end
                    GRID.NotifyAll(string.format("SOLVENCY NOTICE: '%s' ($%s) has cleared all dividend arrears and exited default!", gangName, stock.ticker), NOTIFY_HINT, 6)
                    GRID.Stocks.RecalculateGangPrice(gangName, "solvency_restored")
                end
            else
                -- Insolvent: Default / Junk status
                local shortfall = totalDivObligation - currentVault
                stock.is_defaulted = true
                stock.dividend_arrears = (stock.dividend_arrears or 0) + shortfall

                -- Distribute whatever vault cash is left pro-rata
                if currentVault > 0 and totalOnlineShares > 0 then
                    GRID.Database.AddGangBank(gangName, -currentVault)
                    for _, h in ipairs(onlineHolders) do
                        local fraction = h.shares / totalOnlineShares
                        local partialPayout = math.floor(currentVault * fraction)
                        if partialPayout > 0 then
                            h.port.unclaimed_dividends = (h.port.unclaimed_dividends or 0) + partialPayout
                            GRID.Database.SaveStockPortfolio(h.ply:SteamID(), gangName, h.shares, h.port.avg_buy_price, h.port.last_purchase_unix, h.port.unclaimed_dividends)
                        end
                    end
                end

                -- Apply persistent insolvency debuff to all online gang members
                for _, p in ipairs(player.GetAll()) do
                    if string.lower(p:GetRawGang()) == string.lower(gangName) then
                        p:AddBuff("syndicate_insolvency", 0)
                    end
                end

                GRID.NotifyAll(string.format("DEFAULT ALERT: '%s' ($%s) failed to pay dividends! Stock is now in default (-50%% value).", gangName, stock.ticker), NOTIFY_ERROR, 8)
                GRID.Stocks.RecalculateGangPrice(gangName, "dividend_default")
            end
        end
    end
end

-- Garnishes turf/printer revenues for defaulted syndicates
function GRID.Stocks.GarnishRevenue(gangName, amount, sourceName)
    local stock = GRID.Stocks.Listings[gangName]
    if not stock or not stock.is_defaulted or (stock.dividend_arrears or 0) <= 0 then
        return false, amount
    end

    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return true, 0 end

    local cfg = GRID.Config.Stocks or {}
    local arrears = stock.dividend_arrears or 0
    local garnished = math.min(arrears, amount)
    stock.dividend_arrears = math.max(0, arrears - garnished)

    -- 10% late-penalty sink
    local penaltySink = math.floor(garnished * 0.10)
    local toArrears = garnished - penaltySink

    if stock.dividend_arrears <= 0 then
        stock.is_defaulted = false
        stock.dividend_arrears = 0
        for _, p in ipairs(player.GetAll()) do
            if string.lower(p:GetRawGang()) == string.lower(gangName) then
                p:RemoveBuff("syndicate_insolvency", "cleansed")
            end
        end
        GRID.NotifyAll(string.format("DEBT CLEARED: '%s' paid off all unpaid debt using %s!", gangName, sourceName or "territory revenue"), NOTIFY_HINT, 6)
        GRID.Stocks.RecalculateGangPrice(gangName, "garnished_arrears_cleared")
    else
        GRID.Database.SaveStockListing(stock)
    end

    local remainder = amount - garnished
    return true, remainder
end

-- --------------------------------------------------------
-- 5. Network Handlers & Order Execution
-- --------------------------------------------------------

function GRID.Stocks.BroadcastStockUpdate(gangName)
    local stock = GRID.Stocks.Listings[gangName]
    if not stock then return end

    local isHalted, haltSecs = GRID.Stocks.IsTradingHalted(gangName)
    net.Start("GRID_Stock_SendListings")
    net.WriteUInt(1, 16)
    net.WriteString(stock.gang_name)
    net.WriteString(stock.ticker)
    net.WriteUInt(stock.total_shares, 16)
    net.WriteUInt(stock.issued_shares, 16)
    net.WriteUInt(stock.circulating_shares, 16)
    net.WriteUInt(stock.amm_reserve, 32)
    net.WriteUInt(stock.current_price, 32)
    net.WriteUInt(stock.price_24h_ago, 32)
    net.WriteFloat(stock.dividend_rate)
    net.WriteUInt(stock.dividend_arrears, 32)
    net.WriteBool(stock.is_defaulted)
    net.WriteBool(isHalted)
    net.WriteUInt(haltSecs, 16)
    net.Broadcast()
end

function GRID.Stocks.SendFullMarket(ply)
    if not IsValid(ply) then return end
    local count = table.Count(GRID.Stocks.Listings)
    net.Start("GRID_Stock_SendListings")
    net.WriteUInt(count, 16)
    for gName, s in pairs(GRID.Stocks.Listings) do
        local isHalted, haltSecs = GRID.Stocks.IsTradingHalted(gName)
        net.WriteString(s.gang_name)
        net.WriteString(s.ticker)
        net.WriteUInt(s.total_shares or 1000, 16)
        net.WriteUInt(s.issued_shares or 0, 16)
        net.WriteUInt(s.circulating_shares or 0, 16)
        net.WriteUInt(s.amm_reserve or 0, 32)
        net.WriteUInt(s.current_price or 10, 32)
        net.WriteUInt(s.price_24h_ago or 10, 32)
        net.WriteFloat(s.dividend_rate or 0.03)
        net.WriteUInt(s.dividend_arrears or 0, 32)
        net.WriteBool(s.is_defaulted or false)
        net.WriteBool(isHalted)
        net.WriteUInt(haltSecs, 16)
    end
    net.Send(ply)
end

net.Receive("GRID_Stock_RequestListings", function(len, ply)
    if not IsValid(ply) then return end
    if not GRID.CheckRateLimit(ply, "stock_req_listings", 3) then return end
    GRID.Stocks.SendFullMarket(ply)
end)

net.Receive("GRID_Stock_RequestPortfolio", function(len, ply)
    if not IsValid(ply) then return end
    if not GRID.CheckRateLimit(ply, "stock_req_portfolio", 3) then return end

    GRID.Database.LoadStockPortfolios(ply:SteamID(), function(rows)
        if not IsValid(ply) then return end
        ply.GRID_StockPortfolios = ply.GRID_StockPortfolios or {}
        for _, r in ipairs(rows or {}) do
            ply.GRID_StockPortfolios[r.gang_name] = r
        end

        net.Start("GRID_Stock_SendPortfolio")
        net.WriteUInt(#rows, 16)
        for _, r in ipairs(rows) do
            net.WriteString(r.gang_name)
            net.WriteUInt(tonumber(r.shares_owned) or 0, 16)
            net.WriteUInt(tonumber(r.avg_buy_price) or 0, 32)
            net.WriteUInt(tonumber(r.last_purchase_unix) or 0, 32)
            net.WriteUInt(tonumber(r.unclaimed_dividends) or 0, 32)
        end
        net.Send(ply)
    end)
end)

net.Receive("GRID_Stock_RequestHistory", function(len, ply)
    if not IsValid(ply) then return end
    if not GRID.CheckRateLimit(ply, "stock_req_history", 4) then return end

    local gangName = net.ReadString()
    local timeframeHours = net.ReadUInt(16)
    local cutoff = os.time() - (timeframeHours * 3600)

    GRID.Database.LoadStockHistory(gangName, cutoff, function(rows)
        if not IsValid(ply) then return end
        net.Start("GRID_Stock_SendHistory")
        net.WriteString(gangName)
        net.WriteUInt(#rows, 16)
        for _, r in ipairs(rows) do
            net.WriteUInt(tonumber(r.timestamp_unix) or 0, 32)
            net.WriteUInt(tonumber(r.price) or 0, 32)
            net.WriteUInt(tonumber(r.volume) or 0, 16)
        end
        net.Send(ply)
    end)
end)

-- Validation helper for ATM proximity
local function ValidateATMProximity(ply)
    if not IsValid(ply) or not ply:Alive() then return false end
    local pPos = ply:EyePos()
    for _, atm in ipairs(ents.FindByClass("grid_atm")) do
        if IsValid(atm) and atm:GetPos():DistToSqr(pPos) <= (140 * 140) then
            return true, atm
        end
    end
    return false, nil
end

-- BUY SHARES HANDLER
net.Receive("GRID_Stock_Buy", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "stock_trade", 2) then return end
    if ply.GRID_StockTxPending then return end

    local nearATM = ValidateATMProximity(ply)
    if not nearATM then
        GRID.Notify(ply, "You must be at a Street ATM to execute stock trades!", NOTIFY_ERROR)
        return
    end

    local gangName = net.ReadString()
    local shareCount = net.ReadUInt(16)

    local stock = GRID.Stocks.Listings[gangName]
    if not stock then
        GRID.Notify(ply, "Invalid stock listing!", NOTIFY_ERROR)
        return
    end

    local isHalted, haltSecs = GRID.Stocks.IsTradingHalted(gangName)
    if isHalted then
        GRID.Notify(ply, string.format("Trading for %s is halted for %ds due to active combat incursion!", stock.ticker, haltSecs), NOTIFY_ERROR)
        return
    end

    -- Check available shares for sale (issued_shares - circulating_shares)
    local availableShares = math.max(0, (stock.issued_shares or 0) - (stock.circulating_shares or 0))
    if shareCount > availableShares then
        GRID.Notify(ply, string.format("Only %d shares available for purchase!", availableShares), NOTIFY_ERROR)
        return
    end

    local quote = GRID.Stocks.CalculateBuyQuote(stock, shareCount)
    local totalCost = quote.netTotalCost

    if not ply:CanAfford(totalCost) then
        local bank = ply.GetBank and ply:GetBank() or 0
        if (ply:GetMoney() + bank) < totalCost then
            GRID.Notify(ply, string.format("Insufficient funds! Total cost: $%s (including $%s broker fee).", string.Comma(totalCost), string.Comma(quote.brokerFee)), NOTIFY_ERROR)
            return
        end
    end

    ply.GRID_StockTxPending = true
    local paid, fromWallet, fromBank = GRID.Economy.DeductFeeWithBankFallback(ply, totalCost)
    if not paid then
        ply.GRID_StockTxPending = false
        GRID.Notify(ply, "Transaction declined by banking network.", NOTIFY_ERROR)
        return
    end

    -- Capital Allocation: 50% to Gang Vault, 45% to AMM Reserve, 5% burned broker fee
    local capitalToVault = math.floor(quote.grossCost * 0.50)
    local capitalToAMM = math.floor(quote.grossCost * 0.45)
    GRID.Database.AddGangBank(gangName, capitalToVault)
    stock.amm_reserve = (stock.amm_reserve or 0) + capitalToAMM
    stock.circulating_shares = (stock.circulating_shares or 0) + shareCount

    -- Update buyer portfolio
    ply.GRID_StockPortfolios = ply.GRID_StockPortfolios or {}
    local pData = ply.GRID_StockPortfolios[gangName] or { shares_owned = 0, avg_buy_price = 0, unclaimed_dividends = 0 }
    local curShares = tonumber(pData.shares_owned) or 0
    local curAvg = tonumber(pData.avg_buy_price) or quote.avgSharePrice
    local newShares = curShares + shareCount
    local newAvg = math.Round(((curShares * curAvg) + (shareCount * quote.avgSharePrice)) / newShares)

    pData.shares_owned = newShares
    pData.avg_buy_price = newAvg
    pData.last_purchase_unix = os.time()
    ply.GRID_StockPortfolios[gangName] = pData

    GRID.Database.SaveStockPortfolio(ply:SteamID(), gangName, newShares, newAvg, os.time(), pData.unclaimed_dividends or 0)
    GRID.Stocks.AdjustSentiment(gangName, 0.005 * math.min(10, shareCount), "buy_volume")

    if GRID.Telemetry and GRID.Telemetry.Log then
        GRID.Telemetry.Log("TRADE", "STOCK_BUY", ply:SteamID(), gangName, totalCost, {
            shares = shareCount,
            avg_price = quote.avgSharePrice,
            broker_fee = quote.brokerFee,
            to_vault = capitalToVault,
            to_amm = capitalToAMM
        })
    end

    ply.GRID_StockTxPending = false
    GRID.Notify(ply, string.format("Purchased %d shares of %s for $%s!", shareCount, stock.ticker, string.Comma(totalCost)), NOTIFY_GENERIC)
    ply:EmitSound("ambient/levels/labs/coinslot1.wav")
end)

-- SELL SHARES HANDLER
net.Receive("GRID_Stock_Sell", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "stock_trade", 2) then return end
    if ply.GRID_StockTxPending then return end

    local nearATM = ValidateATMProximity(ply)
    if not nearATM then
        GRID.Notify(ply, "You must be at a Street ATM to execute stock trades!", NOTIFY_ERROR)
        return
    end

    local gangName = net.ReadString()
    local shareCount = net.ReadUInt(16)

    local stock = GRID.Stocks.Listings[gangName]
    if not stock then
        GRID.Notify(ply, "Invalid stock listing!", NOTIFY_ERROR)
        return
    end

    local isHalted, haltSecs = GRID.Stocks.IsTradingHalted(gangName)
    if isHalted then
        GRID.Notify(ply, string.format("Trading for %s is halted for %ds due to active combat incursion!", stock.ticker, haltSecs), NOTIFY_ERROR)
        return
    end

    ply.GRID_StockPortfolios = ply.GRID_StockPortfolios or {}
    local pData = ply.GRID_StockPortfolios[gangName]
    local owned = pData and (tonumber(pData.shares_owned) or 0) or 0
    if shareCount > owned then
        GRID.Notify(ply, string.format("You only own %d shares of %s!", owned, stock.ticker), NOTIFY_ERROR)
        return
    end

    -- Vesting Check
    local isInsider = GRID.Stocks.IsPlayerInsider(ply, gangName)
    local vestingRemaining = GRID.Stocks.GetVestingRemaining(pData.last_purchase_unix, isInsider)
    if vestingRemaining > 0 then
        GRID.Notify(ply, string.format("Shares are locked under vesting schedule for another %d seconds!", vestingRemaining), NOTIFY_ERROR)
        return
    end

    -- Insider Lock Check if gang is near default or turf is contested
    if isInsider and (stock.is_defaulted or (stock.dividend_arrears or 0) > 0) then
        GRID.Notify(ply, "Trade Blocked: Gang members cannot sell shares while the gang has unpaid debt!", NOTIFY_ERROR)
        return
    end

    local quote = GRID.Stocks.CalculateSellQuote(stock, shareCount, isInsider)
    local netProceeds = quote.netProceeds

    -- AMM Reserve Liquidity Check
    local ammCash = stock.amm_reserve or 0
    if netProceeds > ammCash then
        -- Cap cash-out payout to available AMM liquidity
        netProceeds = ammCash
    end

    ply.GRID_StockTxPending = true
    stock.amm_reserve = math.max(0, (stock.amm_reserve or 0) - netProceeds)
    stock.circulating_shares = math.max(0, (stock.circulating_shares or 0) - shareCount)

    local newShares = owned - shareCount
    pData.shares_owned = newShares
    ply.GRID_StockPortfolios[gangName] = pData

    GRID.Database.SaveStockPortfolio(ply:SteamID(), gangName, newShares, pData.avg_buy_price, pData.last_purchase_unix, pData.unclaimed_dividends or 0)
    ply:AddMoney(netProceeds)

    GRID.Stocks.AdjustSentiment(gangName, -0.005 * math.min(10, shareCount), "sell_volume")

    if GRID.Telemetry and GRID.Telemetry.Log then
        GRID.Telemetry.Log("TRADE", "STOCK_SELL", ply:SteamID(), gangName, netProceeds, {
            shares = shareCount,
            avg_price = quote.avgSharePrice,
            broker_fee = quote.brokerFee,
            is_insider = isInsider
        })
    end

    ply.GRID_StockTxPending = false
    GRID.Notify(ply, string.format("Sold %d shares of %s for +$%s (Broker Fee: -$%s)!", shareCount, stock.ticker, string.Comma(netProceeds), string.Comma(quote.brokerFee)), NOTIFY_GENERIC)
    ply:EmitSound("ambient/levels/labs/coinslot1.wav")
end)

-- CLAIM DIVIDENDS HANDLER
net.Receive("GRID_Stock_ClaimDividends", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "stock_claim", 2) then return end

    local nearATM = ValidateATMProximity(ply)
    if not nearATM then
        GRID.Notify(ply, "You must visit a Street ATM to wire unclaimed dividends!", NOTIFY_ERROR)
        return
    end

    local gangName = net.ReadString()
    ply.GRID_StockPortfolios = ply.GRID_StockPortfolios or {}
    local pData = ply.GRID_StockPortfolios[gangName]
    local unclaimed = pData and (tonumber(pData.unclaimed_dividends) or 0) or 0

    if unclaimed <= 0 then
        GRID.Notify(ply, "You have no unclaimed dividends for this stock!", NOTIFY_ERROR)
        return
    end

    -- Wire fee sink (hybrid base + wealth %)
    local fee = GRID.Economy.CalculateDynamicFee(ply, 10, 0.0025)
    local netPayout = math.max(1, unclaimed - fee)

    pData.unclaimed_dividends = 0
    GRID.Database.SaveStockPortfolio(ply:SteamID(), gangName, pData.shares_owned, pData.avg_buy_price, pData.last_purchase_unix, 0)
    ply:AddMoney(netPayout)

    if GRID.Telemetry and GRID.Telemetry.Log then
        GRID.Telemetry.Log("ECONOMY", "STOCK_DIVIDEND_CLAIM", ply:SteamID(), gangName, netPayout, { wire_fee = fee, gross = unclaimed })
    end

    GRID.Notify(ply, string.format("Claimed +$%s in dividends from %s (Wire Fee: -$%d)!", string.Comma(netPayout), gangName, fee), NOTIFY_GENERIC)
    ply:EmitSound("ambient/levels/labs/coinslot1.wav")
end)

-- GANG LEADER IPO HANDLER
net.Receive("GRID_Stock_IPO", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "stock_ipo", 1) then return end

    local pGang = ply:GetRawGang()
    local isLeader = ply:GetNWBool("GRID_IsGangLeader", false) or (ply.GetJob and ply:GetJob() == "gang_leader") or ply:IsAdmin()
    if pGang == "" or not isLeader then
        GRID.Notify(ply, "Only active Gang Leaders can list their syndicate on the stock exchange!", NOTIFY_ERROR)
        return
    end

    if GRID.Stocks.Listings[pGang] then
        GRID.Notify(ply, "Your gang is already publicly listed on the exchange!", NOTIFY_ERROR)
        return
    end

    local ticker = GRID.Stocks.ValidateTicker(net.ReadString())
    if not ticker then
        GRID.Notify(ply, "Ticker symbol must be 3 to 5 uppercase alphanumeric letters (e.g. SYND)!", NOTIFY_ERROR)
        return
    end

    for _, s in pairs(GRID.Stocks.Listings) do
        if string.upper(s.ticker) == ticker then
            GRID.Notify(ply, "That ticker symbol is already registered by another syndicate!", NOTIFY_ERROR)
            return
        end
    end

    local sharesForSalePct = math.Clamp(net.ReadFloat(), 0.10, 0.49)
    local divRate = math.Clamp(net.ReadFloat(), 0.02, 0.05)

    local gData = GRID.Database.GetGang(pGang)
    local vaultBank = gData and tonumber(gData.bank) or 0
    local cfg = GRID.Config.Stocks or {}
    local minVault = cfg.MinVaultForIPO or 10000

    if vaultBank < minVault then
        GRID.Notify(ply, string.format("Your gang vault must contain at least $%s to qualify for an IPO!", string.Comma(minVault)), NOTIFY_ERROR)
        return
    end

    -- Eligibility: At least 1 turf OR 3+ members
    local members = GRID.Database.GetGangMembers(pGang) or {}
    local turfsOwned = 0
    if GRID.Turf and GRID.Turf.Zones then
        for _, z in pairs(GRID.Turf.Zones) do
            if z.owner and string.lower(z.owner) == string.lower(pGang) then
                turfsOwned = turfsOwned + 1
            end
        end
    end

    if turfsOwned < 1 and #members < 3 then
        GRID.Notify(ply, "IPO Requirements: Syndicate must control at least 1 Territory OR have 3+ registered members!", NOTIFY_ERROR)
        return
    end

    -- Dynamic listing fee: $1,500 + 3% of vault
    local listingFee = (cfg.IPOListingFeeFlat or 1500) + math.floor(vaultBank * (cfg.IPOListingFeeVaultPct or 0.03))
    if vaultBank < listingFee then
        GRID.Notify(ply, string.format("Gang vault cannot cover the non-refundable IPO listing fee ($%s)!", string.Comma(listingFee)), NOTIFY_ERROR)
        return
    end

    GRID.Database.AddGangBank(pGang, -listingFee)
    local issued = math.floor(1000 * sharesForSalePct)

    local newStock = {
        gang_name = pGang,
        ticker = ticker,
        total_shares = 1000,
        issued_shares = issued,
        circulating_shares = 0,
        amm_reserve = math.floor(vaultBank * 0.15), -- Seed 15% of vault as initial AMM reserve
        ipo_capital_raised = 0,
        base_price = 10,
        current_price = 10,
        price_24h_ago = 10,
        sentiment_mult = 1.0,
        dividend_rate = divRate,
        dividend_arrears = 0,
        is_defaulted = false,
        created_at_unix = os.time(),
        updated_at_unix = os.time()
    }

    GRID.Stocks.Listings[pGang] = newStock
    GRID.Stocks.RecalculateGangPrice(pGang, "initial_public_offering")
    GRID.Database.LogStockHistory(pGang, 10, 0)

    GRID.NotifyAll(string.format("EXCHANGE IPO: '%s' listed ticker [$%s] (%d Shares for Sale | Dividend: %.1f%%)!", pGang, ticker, issued, divRate * 100), NOTIFY_HINT, 10)
end)

-- GANG LEADER BUYBACK HANDLER (Retire shares using vault cash)
net.Receive("GRID_Stock_LeaderBuyback", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "stock_buyback", 2) then return end

    local pGang = ply:GetRawGang()
    local isLeader = ply:GetNWBool("GRID_IsGangLeader", false) or (ply.GetJob and ply:GetJob() == "gang_leader") or ply:IsAdmin()
    if pGang == "" or not isLeader then return end

    local stock = GRID.Stocks.Listings[pGang]
    if not stock then return end

    local sharesToBuyback = math.max(0, net.ReadUInt(16))
    if sharesToBuyback == 0 then return end

    -- Buyback retires circulating or issued shares
    local availableToRetire = stock.issued_shares or 0
    if sharesToBuyback > availableToRetire then
        GRID.Notify(ply, string.format("Cannot buy back more than the %d total issued shares!", availableToRetire), NOTIFY_ERROR)
        return
    end

    local spotPrice = stock.current_price or 10
    local totalCost = spotPrice * sharesToBuyback
    local gData = GRID.Database.GetGang(pGang)
    local vaultBank = gData and tonumber(gData.bank) or 0

    if vaultBank < totalCost then
        GRID.Notify(ply, string.format("Gang vault has insufficient funds ($%s needed)!", string.Comma(totalCost)), NOTIFY_ERROR)
        return
    end

    GRID.Database.AddGangBank(pGang, -totalCost)
    stock.issued_shares = math.max(0, stock.issued_shares - sharesToBuyback)
    stock.circulating_shares = math.max(0, stock.circulating_shares - sharesToBuyback)

    if stock.issued_shares <= 0 then
        -- 100% BUYBACK COMPLETED: Syndicate goes private and is delisted
        GRID.Stocks.Listings[pGang] = nil
        GRID.Database.DeleteStockListing(pGang)

        -- Clean up online players' cached portfolios for this gang
        for _, pl in ipairs(player.GetAll()) do
            if pl.GRID_StockPortfolios and pl.GRID_StockPortfolios[pGang] then
                pl.GRID_StockPortfolios[pGang] = nil
            end
        end

        -- Broadcast delisting to all clients
        net.Start("GRID_Stock_Delisted")
        net.WriteString(pGang)
        net.Broadcast()

        GRID.NotifyAll(string.format("EXCHANGE NOTICE: '%s' has bought back 100%% of its shares and is now a private syndicate!", pGang), NOTIFY_HINT, 10)
        GRID.Notify(ply, string.format("Syndicate '%s' is now 100%% privately owned! You can launch a new IPO anytime at the stock exchange.", pGang), NOTIFY_GENERIC, 8)
    else
        GRID.Stocks.RecalculateGangPrice(pGang, "share_buyback")
        GRID.Notify(ply, string.format("Bought back and retired %d shares of %s using $%s from gang vault!", sharesToBuyback, stock.ticker, string.Comma(totalCost)), NOTIFY_GENERIC)
    end
end)

-- CLEAR ARREARS HANDLER (Leader or member bails out defaulted syndicate)
net.Receive("GRID_Stock_ClearArrears", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "stock_clear_debt", 2) then return end

    local gangName = net.ReadString()
    local stock = GRID.Stocks.Listings[gangName]
    if not stock or not stock.is_defaulted or (stock.dividend_arrears or 0) <= 0 then
        GRID.Notify(ply, "This gang has no unpaid debt!", NOTIFY_ERROR)
        return
    end

    local amount = math.max(1, net.ReadUInt(32))
    if not ply:CanAfford(amount) then
        GRID.Notify(ply, "You cannot afford this debt repayment!", NOTIFY_ERROR)
        return
    end

    ply:AddMoney(-amount)
    GRID.Stocks.GarnishRevenue(gangName, amount, "voluntary debt payment from " .. ply:Nick())
    GRID.Notify(ply, string.format("Paid $%s toward %s's gang debt!", string.Comma(amount), stock.ticker), NOTIFY_GENERIC)
end)

