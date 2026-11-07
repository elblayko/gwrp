--[[
    entities/entities/grid_recycler_depot/init.lua
    GridRP Street Recycling Depot Server Logic
    Author: Juicebox & Antigravity
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("GRID_OpenRecyclerMenu")
util.AddNetworkString("GRID_RecycleDeposit")

function ENT:Initialize()
    self:SetModel(self.Model or "models/props_wasteland/laundry_washer003.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Wake()
    end

    self:SetTotalItemsRecycled(0)
    self:SetTotalCashPaid(0)
    self:SetIsProcessing(false)
    self.NextUsePerPlayer = {}
end

--- Processes the recycling transaction for a player
-- @param ply Player executing the transaction
-- @param selectedItems Optional table of { bag, slot, amount, item_id } to recycle (nil = all recyclables)
-- @param hitSweetSpot Optional boolean if player timed the hydraulic compaction minigame
function ENT:ProcessRecycle(ply, selectedItems, hitSweetSpot)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end

    if ply:GetPos():DistToSqr(self:GetPos()) > (140 * 140) then
        GRID.Notify(ply, "You are too far from the Recycling Depot.", NOTIFY_ERROR)
        return
    end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[ply] or 0) > now then return end
    self.NextUsePerPlayer[ply] = now + 1.0

    local steamID = ply:SteamID()
    local invRows = GRID.Database.GetInventory(steamID) or {}
    local recyclables = GRID.Scavenge and GRID.Scavenge.Recyclables or {}

    local totalCount = 0
    local baseCash = 0
    local baseXP = 0
    local categoriesPresent = {}
    local itemsToRemove = {}

    if selectedItems and #selectedItems > 0 then
        -- Process specific hopper items selected by player in dialog
        for _, req in ipairs(selectedItems) do
            local bag = tonumber(req.bag) or 0
            local slot = tonumber(req.slot) or 1
            local reqAmt = math.max(1, tonumber(req.amount) or 1)

            -- Verify item exists in player's inventory slot
            local slotItem = nil
            for _, r in ipairs(invRows) do
                if (tonumber(r.bag_index) or 0) == bag and (tonumber(r.slot_index) or 1) == slot then
                    slotItem = r
                    break
                end
            end

            if slotItem and recyclables[slotItem.item_id] then
                local def = recyclables[slotItem.item_id]
                local available = tonumber(slotItem.amount) or 1
                local amt = math.min(reqAmt, available)
                local itemPrice = tonumber(def.cash or def.price) or 0
                local itemXP = tonumber(def.xp) or 0

                if amt > 0 then
                    totalCount = totalCount + amt
                    baseCash = baseCash + (itemPrice * amt)
                    baseXP = baseXP + (itemXP * amt)
                    categoriesPresent[def.category or slotItem.item_id] = true
                    table.insert(itemsToRemove, {
                        bag = bag,
                        slot = slot,
                        amount = amt,
                        item_id = slotItem.item_id
                    })
                end
            end
        end
    else
        -- Auto-process all recyclable junk in inventory
        for _, r in ipairs(invRows) do
            local def = recyclables[r.item_id]
            if def then
                local amt = tonumber(r.amount) or 1
                local itemPrice = tonumber(def.cash or def.price) or 0
                local itemXP = tonumber(def.xp) or 0

                if amt > 0 then
                    totalCount = totalCount + amt
                    baseCash = baseCash + (itemPrice * amt)
                    baseXP = baseXP + (itemXP * amt)
                    categoriesPresent[def.category or r.item_id] = true
                    table.insert(itemsToRemove, {
                        bag = tonumber(r.bag_index) or 0,
                        slot = tonumber(r.slot_index) or 1,
                        amount = amt,
                        item_id = r.item_id
                    })
                end
            end
        end
    end

    if totalCount <= 0 then
        GRID.Notify(ply, "You don't have any recyclable junk in your bags! Rummage dumpsters or trash bins first.",
            NOTIFY_HINT)
        self:EmitSound("buttons/button10.wav", 60, 100)
        return
    end

    -- Multi-item diversity bonus calculation (+5% per distinct category, capped at +25%)
    local numCategories = table.Count(categoriesPresent)
    local comboBonus = (GRID.Scavenge and GRID.Scavenge.GetDepositBonus) and GRID.Scavenge.GetDepositBonus(numCategories) or
    0

    -- Minigame Sweet Spot bonus (+25% extra efficiency if timed correctly)
    local sweetSpotBonus = (hitSweetSpot == true) and 0.25 or 0.0

    local totalMultiplier = 1.0 + comboBonus + sweetSpotBonus
    local finalCash = math.floor(baseCash * totalMultiplier)
    local finalXP = math.floor(baseXP * totalMultiplier)

    -- Remove items from inventory
    for _, item in ipairs(itemsToRemove) do
        GRID.Database.RemoveInventoryItemAtSlot(steamID, item.bag, item.slot, item.amount)
    end
    GRID.Inventory.Sync(ply)

    -- Payout Cash & XP to player
    if ply.AddMoney then
        ply:AddMoney(finalCash)
    end
    if ply.AddXP then
        ply:AddXP(finalXP)
    end

    -- Gang bank & influence synergy
    local gangName = ply.GetGang and ply:GetGang() or ""
    local gangCut = 0
    if gangName ~= "" then
        gangCut = math.max(1, math.floor(finalCash * 0.10))
        if GRID.Database and GRID.Database.AddGangBank then
            GRID.Database.AddGangBank(gangName, gangCut)
        end
    end

    -- Visual & sound effects
    self:EmitSound("ambient/machines/hydraulic_1.wav", 75, 100)
    if hitSweetSpot then
        self:EmitSound("ambient/materials/metal_groan.wav", 80, 120)
        self:EmitSound("physics/metal/metal_box_break1.wav", 75, 100)
    else
        self:EmitSound("ambient/materials/metal_groan.wav", 70, 100)
    end

    local ed = EffectData()
    ed:SetOrigin(self:GetPos() + self:GetUp() * 25 + self:GetForward() * 10)
    ed:SetNormal(Vector(0, 0, 1))
    ed:SetMagnitude(hitSweetSpot and 3 or 2)
    ed:SetScale(hitSweetSpot and 2 or 1)
    ed:SetRadius(6)
    util.Effect("Sparks", ed, true, true)

    -- DataTables & processing state
    self:SetTotalItemsRecycled((self:GetTotalItemsRecycled() or 0) + totalCount)
    self:SetTotalCashPaid((self:GetTotalCashPaid() or 0) + finalCash)
    self:SetIsProcessing(true)
    timer.Simple(1.5, function()
        if IsValid(self) then
            self:SetIsProcessing(false)
        end
    end)

    -- User Notification
    local bonusTags = {}
    if comboBonus > 0 then
        table.insert(bonusTags, string.format("+%d%% Combo", math.Round(comboBonus * 100)))
    end
    if sweetSpotBonus > 0 then
        table.insert(bonusTags, "+25% Sweet Spot")
    end
    local tagStr = #bonusTags > 0 and (" (" .. table.concat(bonusTags, ", ") .. ")") or ""

    GRID.Notify(ply,
        string.format("Recycled %d items%s for +$%s and +%d XP!", totalCount, tagStr, string.Comma(finalCash), finalXP),
        NOTIFY_GENERIC)

    -- Telemetry logging
    if GRID.Telemetry and GRID.Telemetry.Log then
        GRID.Telemetry.Log("ECONOMY", "RECYCLE_DEPOSIT", steamID, gangName, finalCash, {
            items_recycled = totalCount,
            categories = numCategories,
            combo_bonus = comboBonus * 100,
            sweet_spot = (hitSweetSpot == true),
            payout = finalCash,
            gang_cut = gangCut,
            xp = finalXP
        })
    end
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end
    if activator:GetPos():DistToSqr(self:GetPos()) > (140 * 140) then return end

    -- Open interactive dialog menu on client
    net.Start("GRID_OpenRecyclerMenu")
    net.WriteEntity(self)
    net.WriteInt(self:GetTotalItemsRecycled() or 0, 32)
    net.WriteInt(self:GetTotalCashPaid() or 0, 32)
    net.Send(activator)
end

net.Receive("GRID_RecycleDeposit", function(len, ply)
    local ent = net.ReadEntity()
    local hitSweetSpot = net.ReadBool()
    local itemCount = net.ReadUInt(16)

    local selectedItems = nil
    if itemCount > 0 then
        selectedItems = {}
        for i = 1, itemCount do
            local bag = net.ReadUInt(8)
            local slot = net.ReadUInt(8)
            local amount = net.ReadUInt(16)
            local itemId = net.ReadString()
            table.insert(selectedItems, {
                bag = bag,
                slot = slot,
                amount = amount,
                item_id = itemId
            })
        end
    end

    if IsValid(ent) and ent:GetClass() == "grid_recycler_depot" then
        ent:ProcessRecycle(ply, selectedItems, hitSweetSpot)
    end
end)
