--[[
    entities/entities/grid_atm/shared.lua
    GridRP Street ATM Banking Terminal - Shared
    Author: GRID Core Team & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "grid_base_interactive"
ENT.PrintName = "Street ATM"
ENT.Author = "Juicebox & Antigravity"
ENT.Category = "GridRP - World Infrastructure"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.IsPersistentMapEntity = true
ENT.TransmitAlways = true

ENT.OverheadConfig = {
    Enabled = true,
    FaceCamera = true,
    Offset = Vector(0, 0, 48),
    MaxDistance = 280,
    FadeStart = 180,
    Scale = 0.065,
    GetTitle = function(self)
        return "STREET ATM"
    end,
    GetColor = function(self)
        return Color(52, 211, 153)
    end,
    GetCustomText = function(self)
        if CLIENT and GRID.Stocks and GRID.Stocks.ClientListings then
            local stocks = {}
            for _, s in pairs(GRID.Stocks.ClientListings) do
                table.insert(stocks, s)
            end
            if #stocks > 0 then
                local idx = (math.floor(CurTime() / 4) % #stocks) + 1
                local item = stocks[idx]
                if item then
                    local change = item.current_price - (item.price_24h_ago or item.current_price)
                    local sign = change >= 0 and "+" or ""
                    return string.format("EXCHANGE: %s $%s (%s%d)", item.ticker, string.Comma(item.current_price), sign, change)
                end
            end
        end
        return "Personal Banking & Stock Exchange"
    end
}

ENT.InteractionConfig = {
    Enabled = true,
    MaxUseDistance = 120,
    Badge = "FINANCE",
    GetBadgeColor = function(self, ply)
        return Color(52, 211, 153)
    end,
    GetTitle = function(self, ply)
        return "Street Financial Terminal"
    end,
    GetSubtext = function(self, ply)
        local bank = ply.GetBank and ply:GetBank() or 0
        return string.format("Secure Wire & Stock Exchange  |  Bank: $%s", string.Comma(bank))
    end,
    PrimaryAction = "Access Terminal",
    PrimaryKey = "E",
    ShowProgressBar = false,
    CanUse = function(self, ply)
        return true
    end
}

