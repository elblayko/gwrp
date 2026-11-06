--[[
    entities/entities/grid_scavenge_node_base/init.lua
    GridRP Passive Scavenging Node Abstract Base Server Logic
    Author: Juicebox & Antigravity
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model or "models/props_junk/TrashDumpster01a.mdl"
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(CONTINUOUS_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Wake()
    end

    self:SetNodeTier(self.NodeTier or "trashbin")
    self:SetCooldownExpires(0)
    self:SetIsSearching(false)
    self:SetSearchStartTime(0)
    self:SetSearchDuration(self.SearchDuration or 1.5)
    self:SetSearcher(NULL)
    self.SearchPlayer = nil
    self.ActiveUsePress = {}
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end

    -- Debounce holding [E]: only activate once per physical key press
    self.ActiveUsePress = self.ActiveUsePress or {}
    if self.ActiveUsePress[activator] then
        return
    end
    self.ActiveUsePress[activator] = true

    -- Check cooldown (only notifies once per key press, no spam if held)
    if self:IsOnCooldown() then
        local remain = self:GetCooldownRemaining()
        local mins = math.floor(remain / 60)
        local secs = remain % 60
        local timeStr = (mins > 0) and string.format("%dm %02ds", mins, secs) or string.format("%ds", secs)
        GRID.Notify(activator,
            string.format("This %s has been picked clean recently. Check back in %s.",
                string.lower(self.PrintName or "node"), timeStr), NOTIFY_HINT)
        self:EmitSound("physics/metal/metal_box_impact_soft1.wav", 55, 110, 0.4)
        return
    end

    -- Check if another player is actively searching
    if self:GetIsSearching() and IsValid(self.SearchPlayer) and self.SearchPlayer ~= activator then
        GRID.Notify(activator, "Someone is already rummaging through here!", NOTIFY_ERROR)
        self:EmitSound("physics/metal/metal_box_impact_soft1.wav", 55, 120, 0.4)
        return
    end

    -- If player is not currently searching, start new search session
    if not self:GetIsSearching() then
        local now = CurTime()
        local isHobo = (activator.GetJob and activator:GetJob() == "hobo")
        local baseDuration = isHobo and (GRID.Scavenge.Config.HoboSearchDuration or 1.2) or
        (self.SearchDuration or GRID.Scavenge.Config.SearchDuration or 1.5)

        self:SetIsSearching(true)
        self:SetSearchStartTime(now)
        self:SetSearchDuration(baseDuration)
        self:SetSearcher(activator)
        self.SearchPlayer = activator

        -- Scavenging rustle audio
        self:EmitSound("physics/cardboard/cardboard_box_scrape1.wav", 65, 105, 0.7)
    end
end

function ENT:Think()
    -- Clear held press state when players release the IN_USE key
    if self.ActiveUsePress then
        for ply, _ in pairs(self.ActiveUsePress) do
            if not IsValid(ply) or not ply:KeyDown(IN_USE) then
                self.ActiveUsePress[ply] = nil
            end
        end
    end

    if self:GetIsSearching() then
        local now = CurTime()
        local ply = self.SearchPlayer
        local maxDist = GRID.Scavenge.Config.MaxInteractDistance or 110

        -- Validate searcher status
        if not IsValid(ply) or not ply:Alive() or ply:GetPos():DistToSqr(self:GetPos()) > (maxDist * maxDist) or not ply:KeyDown(IN_USE) then
            self:CancelSearch("Search canceled (moved away or released Use).")
            self:NextThink(now + 0.1)
            return true
        end

        -- Check completion
        local startTime = self:GetSearchStartTime()
        local duration = self:GetSearchDuration()
        if now >= (startTime + duration) then
            self:FinishSearch(ply)
        end
    end

    self:NextThink(CurTime() + 0.05)
    return true
end

function ENT:CancelSearch(reason)
    if not self:GetIsSearching() then return end
    self:SetIsSearching(false)
    self:SetSearchStartTime(0)
    self:SetSearcher(NULL)
    self.SearchPlayer = nil
    self:EmitSound("physics/cardboard/cardboard_box_impact_soft2.wav", 55, 100, 0.4)
end

function ENT:FinishSearch(ply)
    self:SetIsSearching(false)
    self:SetSearchStartTime(0)
    self:SetSearcher(NULL)
    self.SearchPlayer = nil

    if not IsValid(ply) then return end

    -- Set node cooldown scaled by population balancer
    local tier = self:GetNodeTier() or "trashbin"
    local baseCooldown = self.BaseCooldown or (GRID.Scavenge.Config.Cooldowns[tier] or 180)
    local cdMult = GRID.Population and GRID.Population.GetCooldownMultiplier and GRID.Population.GetCooldownMultiplier() or
    1.0
    local finalCooldown = math.max(30, math.Round(baseCooldown * cdMult))
    self:SetCooldownExpires(CurTime() + finalCooldown)

    -- Roll loot from table
    local lootTable = GRID.Scavenge.LootTables[tier] or GRID.Scavenge.LootTables["trashbin"]
    local yieldMult = GRID.Population and GRID.Population.GetLootYieldMultiplier and
    GRID.Population.GetLootYieldMultiplier() or 1.0

    local isHobo = (ply.GetJob and ply:GetJob() == "hobo")
    if isHobo then
        local bonus = (GRID.Scavenge and GRID.Scavenge.Config and GRID.Scavenge.Config.HoboYieldBonus) or 0.15
        yieldMult = yieldMult * (1.0 + bonus)
    end

    -- 1. Loose Cash Roll
    local cashAward = 0
    if math.Rand(0, 1) <= (lootTable.cashChance or 0.5) then
        local baseCash = math.random(lootTable.minCash or 5, lootTable.maxCash or 25)
        cashAward = math.max(1, math.Round(baseCash * yieldMult))
        ply:AddMoney(cashAward)
    end

    -- 2. Material/Junk Pool Rolls
    local itemsAwarded = {}
    local numRolls = math.random(lootTable.rolls.min or 1, lootTable.rolls.max or 3)
    local pool = lootTable.pool or {}

    local totalWeight = 0
    for _, entry in ipairs(pool) do
        totalWeight = totalWeight + entry.weight
    end

    for r = 1, numRolls do
        local roll = math.Rand(0, totalWeight)
        local cumulative = 0
        for _, entry in ipairs(pool) do
            cumulative = cumulative + entry.weight
            if roll <= cumulative then
                local baseCount = math.random(entry.min or 1, entry.max or 1)
                local finalCount = math.max(1, math.Round(baseCount * yieldMult))
                local itemId = entry.item

                local added = GRID.Database.AddInventoryItem(ply:SteamID(), itemId, "junk", finalCount, {})
                if added then
                    itemsAwarded[itemId] = (itemsAwarded[itemId] or 0) + finalCount
                end
                break
            end
        end
    end

    -- Sync inventory to player
    if GRID.Inventory and GRID.Inventory.Sync then
        GRID.Inventory.Sync(ply)
    end

    -- Success Audio & Visuals
    self:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 110, 0.7)
    self:EmitSound("buttons/button9.wav", 60, 120, 0.5)

    local ed = EffectData()
    ed:SetOrigin(self:GetPos() + Vector(0, 0, 15))
    ed:SetNormal(Vector(0, 0, 1))
    ed:SetScale(0.6)
    util.Effect("WheelDust", ed)

    -- Build notification text
    local lootSummaries = {}
    if cashAward > 0 then
        table.insert(lootSummaries, string.format("+$%d cash", cashAward))
    end
    for itemId, count in pairs(itemsAwarded) do
        local def = GRID.Inventory.GetItemData(itemId)
        table.insert(lootSummaries, string.format("%dx %s", count, def and def.name or itemId))
    end

    local summaryStr = (#lootSummaries > 0) and table.concat(lootSummaries, ", ") or "Nothing useful found"
    GRID.Notify(ply, string.format("Scavenged %s: Found %s!", self.PrintName or "node", summaryStr), NOTIFY_GENERIC)

    -- Telemetry logging
    if GRID.Telemetry and GRID.Telemetry.Log then
        local totalValue = cashAward
        for itemId, count in pairs(itemsAwarded) do
            local rec = GRID.Scavenge.Recyclables[itemId]
            if rec then
                totalValue = totalValue + (rec.cash * count)
            end
        end

        GRID.Telemetry.Log("ECONOMY", "SCAVENGE_LOOT", ply:SteamID(), "", totalValue, {
            node = self:GetClass(),
            tier = tier,
            cash = cashAward,
            items = itemsAwarded
        })
    end
end
