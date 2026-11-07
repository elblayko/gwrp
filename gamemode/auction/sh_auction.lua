--[[
    sh_auction.lua - Shared Auction House Configurations, Sinks & Item Attribute Parsers
    Author: Juicebox & Antigravity
    Namespace: GRID / GRID.Auction
--]]

GRID = GRID or {}
GRID.Auction = GRID.Auction or {}

-- Durations, Deposit Rates & Operational Sinks
GRID.Auction.MaxListingsPerPlayer = 10
GRID.Auction.SalesTaxRate = 0.075 -- 7.5% House Transaction Tax
GRID.Auction.MinDeposit = 100

-- Collection Box Retention: uncollected items expire after 24h to prevent free inventory space hoarding
GRID.Auction.CollectionRetentionHours = 24
GRID.Auction.CollectionRetentionTime = GRID.Auction.CollectionRetentionHours * 3600

GRID.Auction.Durations = {
    [12] = { name = "12 Hours", hours = 12, depositRate = 0.02 },
    [24] = { name = "24 Hours", hours = 24, depositRate = 0.04 },
    [48] = { name = "48 Hours", hours = 48, depositRate = 0.06 }
}

function GRID.Auction.CalculateDeposit(startBid, durationHours)
    local cfg = GRID.Auction.Durations[durationHours] or GRID.Auction.Durations[24]
    local rate = cfg.depositRate or 0.04
    local calculated = math.floor((tonumber(startBid) or 0) * rate)
    return math.max(GRID.Auction.MinDeposit, calculated)
end

function GRID.Auction.CalculateSalesTax(salePrice)
    return math.floor((tonumber(salePrice) or 0) * GRID.Auction.SalesTaxRate)
end

-- Distinct Item Attribute Parser & Badge Generator
function GRID.Auction.ParseItemData(data)
    if type(data) == "string" then
        if data == "" or data == "{}" then return {} end
        local parsed = util.JSONToTable(data)
        if parsed then return parsed end
        return {}
    elseif type(data) == "table" then
        return data
    end
    return {}
end

function GRID.Auction.GetItemAttributeBadges(itemData)
    local data = GRID.Auction.ParseItemData(itemData)
    local badges = {}

    -- 1. Rolled Combat Modifiers
    if data.modifiers and istable(data.modifiers) then
        if data.modifiers.damage_mult and data.modifiers.damage_mult ~= 1.0 then
            local pct = math.Round((data.modifiers.damage_mult - 1.0) * 100)
            local sign = pct > 0 and "+" or ""
            table.insert(badges, {
                text = sign .. pct .. "% Damage",
                color = pct > 0 and Color(74, 222, 128) or Color(239, 68, 68),
                bg = pct > 0 and Color(16, 185, 129, 35) or Color(239, 68, 68, 35)
            })
        end

        if data.modifiers.elemental_type and data.modifiers.elemental_type ~= "" then
            local elem = string.lower(data.modifiers.elemental_type)
            local val = data.modifiers.elemental_val or 5
            if elem == "poison" or elem == "toxic" then
                table.insert(badges, {
                    text = string.format("Poison (%d DPS)", val),
                    color = Color(52, 211, 153),
                    bg = Color(16, 185, 129, 45)
                })
            elseif elem == "fire" or elem == "incendiary" then
                table.insert(badges, {
                    text = string.format("Fire (+%d Dmg)", val),
                    color = Color(248, 113, 113),
                    bg = Color(239, 68, 68, 45)
                })
            elseif elem == "electric" or elem == "shock" then
                table.insert(badges, {
                    text = string.format("Shock (%ds Stun)", val),
                    color = Color(56, 189, 248),
                    bg = Color(6, 182, 212, 45)
                })
            else
                table.insert(badges, {
                    text = string.upper(elem),
                    color = Color(216, 180, 254),
                    bg = Color(168, 85, 247, 45)
                })
            end
        end

        if data.modifiers.fire_rate_mult and data.modifiers.fire_rate_mult ~= 1.0 then
            local pct = math.Round((data.modifiers.fire_rate_mult - 1.0) * 100)
            local sign = pct > 0 and "+" or ""
            table.insert(badges, {
                text = sign .. pct .. "% Fire Rate",
                color = Color(147, 197, 253),
                bg = Color(59, 130, 246, 35)
            })
        end
    end

    -- 2. Durability
    if data.durability ~= nil then
        local cur = 100
        local max = tonumber(data.max_durability) or tonumber(data.maxDurability) or 100
        if istable(data.durability) then
            cur = tonumber(data.durability.current) or tonumber(data.durability.cur) or 100
            max = tonumber(data.durability.max) or max
        else
            cur = tonumber(data.durability) or 100
        end
        local pct = max > 0 and (cur / max) or 1
        local col = Color(74, 222, 128)
        if pct < 0.3 then
            col = Color(239, 68, 68)
        elseif pct < 0.7 then
            col = Color(245, 158, 11)
        end
        table.insert(badges, {
            text = string.format("Durability: %d/%d", cur, max),
            color = col,
            bg = Color(col.r, col.g, col.b, 35)
        })
    end

    -- 3. Named Affixes
    if data.affixes and istable(data.affixes) then
        for _, affix in ipairs(data.affixes) do
            table.insert(badges, {
                text = tostring(affix),
                color = Color(251, 191, 36),
                bg = Color(245, 158, 11, 35)
            })
        end
    end

    -- 4. Crafter Signature
    if data.crafter then
        local crafterName = istable(data.crafter) and data.crafter.name or tostring(data.crafter)
        if crafterName and crafterName ~= "" then
            table.insert(badges, {
                text = "Crafted by " .. crafterName,
                color = Color(148, 163, 184),
                bg = Color(51, 65, 85, 45)
            })
        end
    end

    return badges
end

function GRID.Auction.FormatTimeRemaining(expiresAtUnix)
    local diff = (tonumber(expiresAtUnix) or 0) - os.time()
    if diff <= 0 then return "Expired" end
    local hours = math.floor(diff / 3600)
    local minutes = math.floor((diff % 3600) / 60)
    if hours >= 24 then
        local days = math.floor(hours / 24)
        local remHours = hours % 24
        return string.format("%dd %dh", days, remHours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", math.max(1, minutes))
    end
end

function GRID.Auction.FormatCollectionTimeRemaining(createdAtUnix)
    local retention = GRID.Auction.CollectionRetentionTime or 86400
    local expiresAt = (tonumber(createdAtUnix) or 0) + retention
    local diff = expiresAt - os.time()
    if diff <= 0 then
        return "Expired", true, 0
    end
    local hours = math.floor(diff / 3600)
    local minutes = math.floor((diff % 3600) / 60)
    local seconds = diff % 60
    if hours >= 24 then
        local days = math.floor(hours / 24)
        local remHours = hours % 24
        return string.format("%dd %dh", days, remHours), false, diff
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes), false, diff
    else
        return string.format("%dm %ds", minutes, seconds), false, diff
    end
end

