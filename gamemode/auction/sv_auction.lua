--[[
    sv_auction.lua - Server-Side Auction House Engine
    Author: Juicebox & Antigravity
    Namespace: GRID / GRID.Auction
--]]

GRID = GRID or {}
GRID.Auction = GRID.Auction or {}

-- --------------------------------------------------------
-- 1. Security & Validation Helpers
-- --------------------------------------------------------

function GRID.Auction.ValidateTerminalAccess(ply)
    if not IsValid(ply) or not ply:Alive() then return false end
    local pPos = ply:EyePos()
    for _, ent in ipairs(ents.FindByClass("grid_auction_terminal")) do
        if IsValid(ent) and ent:GetPos():DistToSqr(pPos) <= (180 * 180) then
            return true
        end
    end
    return false
end

-- --------------------------------------------------------
-- 2. Periodic Expiration Sweep
-- --------------------------------------------------------

function GRID.Auction.CheckExpirations()
    if not GRID.Database or not GRID.Database.ProcessAuctionExpirations then return end
    GRID.Database.ProcessAuctionExpirations(function()
        -- Expirations handled cleanly via database procedure
    end)
end

timer.Create("GRID_Auction_ExpiryTimer", 60, 0, function()
    GRID.Auction.CheckExpirations()
end)

hook.Add("GRID_DatabaseConnected", "GRID_Auction_InitSweep", function()
    timer.Simple(5, function()
        GRID.Auction.CheckExpirations()
    end)
end)

-- --------------------------------------------------------
-- 3. Network Handlers
-- --------------------------------------------------------

function GRID.Auction.SendListings(target)
    GRID.Database.GetActiveAuctions(function(rows)
        rows = rows or {}
        if target and not IsValid(target) then return end

        net.Start("GRID_Auction_SendListings")
        net.WriteUInt(#rows, 16)
        for _, r in ipairs(rows) do
            net.WriteUInt(tonumber(r.auction_id) or 0, 32)
            net.WriteString(r.seller_steamid or "")
            net.WriteString(r.seller_name or "Anonymous")
            net.WriteString(r.item_id or "")
            net.WriteString(r.item_type or "generic")
            net.WriteUInt(tonumber(r.amount) or 1, 16)
            net.WriteString(r.item_data or "{}")
            net.WriteUInt(tonumber(r.start_bid) or 0, 32)
            net.WriteUInt(tonumber(r.current_bid) or 0, 32)
            local highName = r.high_bidder_name
            if not highName or highName == "NULL" or highName == "nil" then
                highName = ""
            end
            net.WriteString(highName)
            net.WriteUInt(tonumber(r.buyout_price) or 0, 32)
            net.WriteUInt(tonumber(r.expires_at_unix) or 0, 32)
        end

        if target then
            net.Send(target)
        else
            net.Broadcast()
        end
    end)
end

-- A. Request Active Listings
net.Receive("GRID_Auction_RequestListings", function(len, ply)
    if not IsValid(ply) then return end
    if not GRID.CheckRateLimit(ply, "auction_req_listings", 3) then return end

    GRID.Auction.SendListings(ply)
end)

-- B. Request Market Metrics
net.Receive("GRID_Auction_RequestMetrics", function(len, ply)
    if not IsValid(ply) then return end
    if not GRID.CheckRateLimit(ply, "auction_req_metrics", 2) then return end

    GRID.Database.GetAuctionMetrics(function(metrics)
        if not IsValid(ply) then return end
        local count = table.Count(metrics)
        net.Start("GRID_Auction_SendMetrics")
        net.WriteUInt(count, 16)
        for itemId, m in pairs(metrics) do
            net.WriteString(itemId)
            net.WriteUInt(m.min_buyout or 0, 32)
            net.WriteUInt(m.active_count or 0, 16)
            net.WriteUInt(m.avg_7d or 0, 32)
            net.WriteUInt(m.sold_24h or 0, 16)
        end
        net.Send(ply)
    end)
end)

-- C. Create Auction Listing
net.Receive("GRID_Auction_CreateListing", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "auction_create", 2) then return end

    if not GRID.Auction.ValidateTerminalAccess(ply) then
        GRID.Notify(ply, "You must be at an Auction Terminal to post a listing!", NOTIFY_ERROR)
        return
    end

    local bagIndex = net.ReadUInt(8)
    local slotIndex = net.ReadUInt(8)
    local startBid = net.ReadUInt(32)
    local buyoutPrice = net.ReadUInt(32)
    local durationHours = net.ReadUInt(8)

    if startBid < 10 then
        GRID.Notify(ply, "Starting bid must be at least $10!", NOTIFY_ERROR)
        return
    end

    if buyoutPrice > 0 and buyoutPrice < startBid then
        GRID.Notify(ply, "Buyout price cannot be lower than the starting bid!", NOTIFY_ERROR)
        return
    end

    if not GRID.Auction.Durations[durationHours] then
        durationHours = 24
    end

    local item = GRID.Database.GetInventorySlot(ply:SteamID(), bagIndex, slotIndex)
    if not item then
        GRID.Notify(ply, "The selected item was not found in your inventory!", NOTIFY_ERROR)
        return
    end

    -- Hook check for onboarding / soulbound items / level gate
    if hook.Run("GRID_CanCreateAuction", ply, item) == false then
        return
    end

    local deposit = GRID.Auction.CalculateDeposit(startBid, durationHours)
    if ply:GetMoney() < deposit then
        GRID.Notify(ply, string.format("Insufficient funds! Required listing deposit: $%s", string.Comma(deposit)), NOTIFY_ERROR)
        return
    end

    GRID.Database.CreateAuction(ply:SteamID(), ply:Nick(), bagIndex, slotIndex, startBid, buyoutPrice, durationHours, deposit, function(success, status, aucID)
        if not IsValid(ply) then return end
        if success then
            GRID.Notify(ply, string.format("Listing created! Deposit paid: $%s (%dh duration)", string.Comma(deposit), durationHours), NOTIFY_GENERIC)
            ply:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 100)

            -- Sync inventory to client
            if GRID.Inventory and GRID.Inventory.Sync then
                GRID.Inventory.Sync(ply)
            end

            -- Sync updated active listings
            GRID.Auction.SendListings(ply)
        else
            if status == "ERR_MAX_LISTINGS" then
                GRID.Notify(ply, "You have reached the maximum of 10 active auction listings!", NOTIFY_ERROR)
            elseif status == "ERR_INSUFFICIENT_FUNDS" then
                GRID.Notify(ply, "Insufficient funds to cover the listing deposit!", NOTIFY_ERROR)
            elseif status == "ERR_ITEM_NOT_FOUND" then
                GRID.Notify(ply, "The selected item was not found in your inventory!", NOTIFY_ERROR)
            else
                GRID.Notify(ply, "Failed to create listing: " .. tostring(status), NOTIFY_ERROR)
            end
        end
    end)
end)

-- D. Place Bid
net.Receive("GRID_Auction_PlaceBid", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "auction_bid", 2) then return end

    if not GRID.Auction.ValidateTerminalAccess(ply) then
        GRID.Notify(ply, "You must be at an Auction Terminal to place a bid!", NOTIFY_ERROR)
        return
    end

    local auctionID = net.ReadUInt(32)
    local bidAmount = net.ReadUInt(32)

    if bidAmount <= 0 then return end
    if ply:GetMoney() < bidAmount then
        GRID.Notify(ply, "You do not have enough cash to place this bid!", NOTIFY_ERROR)
        return
    end

    GRID.Database.BidAuction(auctionID, ply:SteamID(), ply:Nick(), bidAmount, function(success, status)
        if not IsValid(ply) then return end
        if success then
            GRID.Notify(ply, string.format("Bid placed: $%s on Auction #%d!", string.Comma(bidAmount), auctionID), NOTIFY_GENERIC)
            ply:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 100)
        else
            if status == "ERR_BID_TOO_LOW" then
                GRID.Notify(ply, "Your bid must be higher than the current bid!", NOTIFY_ERROR)
            elseif status == "ERR_SELF_BID" then
                GRID.Notify(ply, "You cannot bid on your own auction!", NOTIFY_ERROR)
            elseif status == "ERR_EXPIRED" then
                GRID.Notify(ply, "This auction has already expired!", NOTIFY_ERROR)
            elseif status == "ERR_INSUFFICIENT_FUNDS" then
                GRID.Notify(ply, "Insufficient funds to cover your bid!", NOTIFY_ERROR)
            else
                GRID.Notify(ply, "Bid failed: " .. tostring(status), NOTIFY_ERROR)
            end
        end
    end)
end)

-- E. Buyout
net.Receive("GRID_Auction_Buyout", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "auction_buyout", 2) then return end

    if not GRID.Auction.ValidateTerminalAccess(ply) then
        GRID.Notify(ply, "You must be at an Auction Terminal to buyout an item!", NOTIFY_ERROR)
        return
    end

    local auctionID = net.ReadUInt(32)

    GRID.Database.BuyoutAuction(auctionID, ply:SteamID(), ply:Nick(), function(success, status)
        if not IsValid(ply) then return end
        if success then
            GRID.Notify(ply, "Item purchased! It has been delivered to your Terminal Collection Box.", NOTIFY_GENERIC)
            ply:EmitSound("items/ammo_pickup.wav", 65, 100)
        else
            if status == "ERR_INSUFFICIENT_FUNDS" then
                GRID.Notify(ply, "You do not have enough funds for buyout!", NOTIFY_ERROR)
            elseif status == "ERR_SELF_BUY" then
                GRID.Notify(ply, "You cannot buyout your own listing!", NOTIFY_ERROR)
            elseif status == "ERR_EXPIRED" then
                GRID.Notify(ply, "This auction has already expired or ended!", NOTIFY_ERROR)
            else
                GRID.Notify(ply, "Buyout failed: " .. tostring(status), NOTIFY_ERROR)
            end
        end
    end)
end)

-- F. Cancel Listing
net.Receive("GRID_Auction_Cancel", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "auction_cancel", 2) then return end

    if not GRID.Auction.ValidateTerminalAccess(ply) then
        GRID.Notify(ply, "You must be at an Auction Terminal to cancel a listing!", NOTIFY_ERROR)
        return
    end

    local auctionID = net.ReadUInt(32)

    GRID.Database.CancelAuction(auctionID, ply:SteamID(), function(success, status)
        if not IsValid(ply) then return end
        if success then
            GRID.Notify(ply, "Auction cancelled. The listing deposit was forfeited, and the item was returned to your Collection Box.", NOTIFY_GENERIC)
            ply:EmitSound("buttons/button19.wav", 60, 100)
            GRID.Auction.SendListings(ply)
        else
            if status == "ERR_HAS_BIDS" then
                GRID.Notify(ply, "Cannot cancel auction: An active bid already exists on this item!", NOTIFY_ERROR)
            elseif status == "ERR_NOT_OWNER" then
                GRID.Notify(ply, "You do not own this auction!", NOTIFY_ERROR)
            else
                GRID.Notify(ply, "Cancel failed: " .. tostring(status), NOTIFY_ERROR)
            end
        end
    end)
end)

-- G. Request Player Collection
net.Receive("GRID_Auction_RequestCollection", function(len, ply)
    if not IsValid(ply) then return end
    if not GRID.CheckRateLimit(ply, "auction_req_col", 3) then return end

    GRID.Database.GetPlayerCollection(ply:SteamID(), function(rows)
        if not IsValid(ply) then return end
        net.Start("GRID_Auction_SendCollection")
        net.WriteUInt(#rows, 16)
        for _, r in ipairs(rows) do
            net.WriteUInt(tonumber(r.collection_id) or 0, 32)
            net.WriteString(r.item_id or "")
            net.WriteString(r.item_type or "generic")
            net.WriteUInt(tonumber(r.amount) or 1, 16)
            net.WriteString(r.item_data or "{}")
            net.WriteString(r.source_reason or "")
            net.WriteUInt(tonumber(r.created_at_unix) or 0, 32)
        end
        net.Send(ply)
    end)
end)

-- H. Claim Item from Collection Box
net.Receive("GRID_Auction_ClaimItem", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "auction_claim", 2) then return end

    if not GRID.Auction.ValidateTerminalAccess(ply) then
        GRID.Notify(ply, "You must be at an Auction Terminal to claim items!", NOTIFY_ERROR)
        return
    end

    local collectionID = net.ReadUInt(32)
    local freeBag, freeSlot = GRID.Database.FindOpenSlot(ply:SteamID())
    if not freeBag or not freeSlot then
        GRID.Notify(ply, "Your bags are completely full! Clear a slot before claiming.", NOTIFY_ERROR)
        return
    end

    GRID.Database.ClaimAuctionCollection(collectionID, ply:SteamID(), freeBag, freeSlot, function(success, status)
        if not IsValid(ply) then return end
        if success then
            GRID.Notify(ply, "Item claimed and placed into your bag!", NOTIFY_GENERIC)
            ply:EmitSound("items/itempickup.wav", 65, 100)
            if GRID.Inventory and GRID.Inventory.Sync then
                GRID.Inventory.Sync(ply)
            end
        else
            GRID.Notify(ply, "Failed to claim item: " .. tostring(status), NOTIFY_ERROR)
        end
    end)
end)

-- --------------------------------------------------------
-- 4. Terminal Spawner & Map Persistence
-- --------------------------------------------------------

local function GetTerminalSavePath()
    return "gridrp/terminals_" .. game.GetMap() .. ".json"
end

function GRID.Auction.SaveTerminals()
    file.CreateDir("gridrp")
    local saved = {}
    for _, ent in ipairs(ents.FindByClass("grid_auction_terminal")) do
        if IsValid(ent) then
            table.insert(saved, {
                pos = { ent:GetPos().x, ent:GetPos().y, ent:GetPos().z },
                ang = { ent:GetAngles().p, ent:GetAngles().y, ent:GetAngles().r }
            })
        end
    end
    file.Write(GetTerminalSavePath(), util.TableToJSON(saved, true))
end

function GRID.Auction.LoadTerminals()
    local path = GetTerminalSavePath()
    if not file.Exists(path, "DATA") then return end
    local data = util.JSONToTable(file.Read(path, "DATA") or "[]") or {}
    for _, item in ipairs(data) do
        if item.pos and item.ang then
            local pos = Vector(item.pos[1], item.pos[2], item.pos[3])
            local ang = Angle(item.ang[1], item.ang[2], item.ang[3])
            local ent = ents.Create("grid_auction_terminal")
            if IsValid(ent) then
                ent:SetPos(pos)
                ent:SetAngles(ang)
                ent:Spawn()
                ent:Activate()
            end
        end
    end
end

hook.Add("InitPostEntity", "GRID_Auction_LoadTerminalsOnMap", function()
    timer.Simple(2, function()
        GRID.Auction.LoadTerminals()
    end)
end)

concommand.Add("grid_spawn_auction_terminal", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        GRID.Notify(ply, "You must be a SuperAdmin to spawn an Auction Terminal.", NOTIFY_ERROR)
        return
    end

    local pos, ang
    if IsValid(ply) then
        local tr = ply:GetEyeTrace()
        pos = tr.HitPos
        ang = Angle(0, ply:EyeAngles().y + 180, 0)
    else
        pos = Vector(0, 0, 0)
        ang = Angle(0, 0, 0)
    end

    local ent = ents.Create("grid_auction_terminal")
    if IsValid(ent) then
        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:Spawn()
        ent:Activate()
        GRID.Auction.SaveTerminals()
        if IsValid(ply) then
            GRID.Notify(ply, "Spawned Auction Terminal and saved to map profile!", NOTIFY_GENERIC)
        else
            print("[GRID] Spawned Auction Terminal at " .. tostring(pos))
        end
    end
end)

concommand.Add("grid_save_auction_terminals", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    GRID.Auction.SaveTerminals()
    if IsValid(ply) then
        GRID.Notify(ply, "All Auction Terminals saved for this map!", NOTIFY_GENERIC)
    end
end)


