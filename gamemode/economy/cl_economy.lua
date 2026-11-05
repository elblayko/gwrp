--[[
    cl_economy.lua - Client Currency Formatters
--]]

GRID.EconomyClient = GRID.EconomyClient or {}

function GRID.FormatMoney(amount)
    local formatted = tostring(math.floor(amount or 0))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return "$" .. formatted
end
