--[[
    gamemode/stocks/sh_stocks.lua
    GridRP Gang Stock Market - Shared Math, Validations & Helper Functions
    Author: GRID Core Team & Antigravity
    Namespace: GRID.Stocks
--]]

GRID = GRID or {}
GRID.Stocks = GRID.Stocks or {}
GRID.Stocks.Listings = GRID.Stocks.Listings or {}

-- Ticker symbol validation (3 to 5 uppercase alphanumeric ASCII characters)
function GRID.Stocks.ValidateTicker(ticker)
    if not ticker or not isstring(ticker) then return false end
    local clean = string.upper(string.Trim(ticker))
    if #clean < 3 or #clean > 5 then return false end
    if not string.match(clean, "^[A-Z0-9]+$") then return false end
    return clean
end

-- Checks if player is considered an insider for a given gang
function GRID.Stocks.IsPlayerInsider(ply, gangName)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    local pGang = ply.GetRawGang and ply:GetRawGang() or ply:GetGang()
    if pGang and string.lower(pGang) == string.lower(gangName or "") then
        return true
    end
    return false
end

-- Vesting lock check
function GRID.Stocks.GetVestingRemaining(lastPurchaseUnix, isInsider)
    local cfg = GRID.Config.Stocks
    local lockDuration = isInsider and (cfg.InsiderVestingSecs or 1800) or (cfg.StandardVestingSecs or 900)
    local elapsed = os.time() - (tonumber(lastPurchaseUnix) or 0)
    local remaining = lockDuration - elapsed
    return math.max(0, remaining)
end

-- Buy Quote Calculation:
-- Base Price = (Vault Cash + AMM Reserve + Turf Count * TurfValuation) / TotalShares
-- Each share purchased increases demand; marginal slippage applies per batch.
function GRID.Stocks.CalculateBuyQuote(stockData, shareCount)
    shareCount = math.max(0, math.floor(tonumber(shareCount) or 0))
    if shareCount == 0 or not stockData then
        return {
            shareCount = 0,
            spotPrice = 0,
            avgSharePrice = 0,
            grossCost = 0,
            brokerFee = 0,
            netTotalCost = 0,
            priceImpactPct = 0
        }
    end

    local cfg = GRID.Config.Stocks
    local spotPrice = math.max(5, tonumber(stockData.current_price) or 10)
    local slippageStep = 0.0015 -- +0.15% per share in batch
    local impactPct = math.min(1.5, shareCount * slippageStep)
    local avgPrice = math.max(5, math.Round(spotPrice * (1 + (impactPct / 2))))
    local grossCost = avgPrice * shareCount
    local feePct = cfg.EntryBrokerFeePct or 0.05
    local brokerFee = math.max(1, math.floor(grossCost * feePct))
    local netTotal = grossCost + brokerFee

    return {
        shareCount = shareCount,
        spotPrice = spotPrice,
        avgSharePrice = avgPrice,
        grossCost = grossCost,
        brokerFee = brokerFee,
        netTotalCost = netTotal,
        priceImpactPct = impactPct * 100
    }
end

-- Sell Quote Calculation:
-- Selling applies downward slippage and exit broker fees (higher for insiders).
function GRID.Stocks.CalculateSellQuote(stockData, shareCount, isInsider)
    shareCount = math.max(0, math.floor(tonumber(shareCount) or 0))
    if shareCount == 0 or not stockData then
        return {
            shareCount = 0,
            spotPrice = 0,
            avgSharePrice = 0,
            grossProceeds = 0,
            brokerFee = 0,
            netProceeds = 0,
            priceImpactPct = 0
        }
    end

    local cfg = GRID.Config.Stocks
    local spotPrice = math.max(5, tonumber(stockData.current_price) or 10)
    local slippageStep = 0.0015 -- -0.15% per share
    local impactPct = math.min(0.60, shareCount * slippageStep)
    local avgPrice = math.max(1, math.Round(spotPrice * (1 - (impactPct / 2))))
    local grossProceeds = avgPrice * shareCount

    local feePct = cfg.ExitBrokerFeePct or 0.075
    if isInsider then
        feePct = feePct + (cfg.InsiderExtraExitFeePct or 0.05) -- 12.5% total
    end

    local brokerFee = math.max(1, math.floor(grossProceeds * feePct))
    local netProceeds = math.max(0, grossProceeds - brokerFee)

    return {
        shareCount = shareCount,
        spotPrice = spotPrice,
        avgSharePrice = avgPrice,
        grossProceeds = grossProceeds,
        brokerFee = brokerFee,
        netProceeds = netProceeds,
        priceImpactPct = impactPct * 100
    }
end

