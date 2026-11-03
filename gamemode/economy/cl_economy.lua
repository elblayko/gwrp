--[[
    cl_economy.lua - Client Currency Formatters
--]]

GWRP.EconomyClient = GWRP.EconomyClient or {}

function GWRP.FormatMoney(amount)
    local formatted = tostring(math.floor(amount or 0))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return "$" .. formatted
end
