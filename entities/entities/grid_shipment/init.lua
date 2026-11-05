--[[
    entities/entities/grid_shipment/init.lua
    GridRP Weapon Shipment Kiosk & Retail Vending Logic
    Author: GRID Core Team
    Namespace: GRID / grid_
]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/items/item_item_crate.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetMass(40)
    end

    if self:GetUnitPrice() <= 0 then
        self:SetUnitPrice(75)
    end
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    -- Hobo Restriction: Hobos cannot use weapon shipments
    if activator:GetJob() == "hobo" then
        GRID.Notify(activator, "Hobos cannot retrieve or purchase weapons from shipments!", NOTIFY_ERROR)
        activator:EmitSound("common/warning.wav", 65, 100)
        return
    end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[activator] or 0) > now then return end
    self.NextUsePerPlayer[activator] = now + 0.5

    local count = self:GetCount()
    if count <= 0 then
        self:Remove()
        return
    end

    local wepClass = self:GetWeaponClass()
    if not wepClass or wepClass == "" then
        self:Remove()
        return
    end

    local wepName = self:GetWeaponName() or "Weapon"
    local owner = self:GetOwnerPlayer()
    local isOwner = (activator == owner) or (activator:SteamID() == self.PurchaserSteamID)

    -- Owner Price Configuration (Hold Reload or Walk while pressing E)
    if isOwner and (activator:KeyDown(IN_RELOAD) or activator:KeyDown(IN_WALK)) then
        local currentPrice = self:GetUnitPrice()
        local wholesaleBase = self.WholesaleBase or math.floor(currentPrice * 0.7)
        local markups = { 1.2, 1.35, 1.5, 1.75, 2.0, 2.5 }
        local curMarkupIdx = self.MarkupIndex or 1
        curMarkupIdx = (curMarkupIdx % #markups) + 1
        self.MarkupIndex = curMarkupIdx

        local newPrice = math.max(10, math.floor(wholesaleBase * markups[curMarkupIdx]))
        self:SetUnitPrice(newPrice)
        activator:EmitSound("buttons/button15.wav", 65, 110)
        GRID.Notify(activator, string.format("Shipment Retail Price adjusted: $%d (+%d%% margin)", newPrice, math.Round((markups[curMarkupIdx] - 1) * 100)), NOTIFY_GENERIC)
        return
    end

    -- Self-Consumption Gate (Dealers who switched jobs cannot consume wholesale firearms)
    if isOwner then
        local currentJob = activator:GetJob()
        local affinity = self:GetJobAffinity()
        if affinity and affinity ~= "" and currentJob ~= affinity then
            GRID.Notify(activator, "You are no longer on-duty as the licensed merchant for this shipment! Wholesale self-consumption is blocked.", NOTIFY_ERROR)
            activator:EmitSound("common/warning.wav", 65, 100)
            return
        end
    end

    -- Customer Purchase Transaction (Non-owner or dealer buying at retail)
    if not isOwner then
        local retailPrice = self:GetUnitPrice()
        if not activator:CanAfford(retailPrice) then
            GRID.Notify(activator, string.format("You cannot afford this %s ($%d)!", wepName, retailPrice), NOTIFY_ERROR)
            activator:EmitSound("common/warning.wav", 65, 100)
            return
        end

        -- Deduct purchase price
        activator:AddMoney(-retailPrice)

        -- 8% Sales Tax Anti-Inflation Sink
        local taxRate = GRID.Config.VendorSalesTaxPct or 0.08
        local salesTax = math.floor(retailPrice * taxRate)
        local dealerPayout = retailPrice - salesTax

        if IsValid(owner) and owner:IsPlayer() then
            owner:AddMoney(dealerPayout)
            GRID.Notify(owner, string.format("[MERCHANT] %s bought 1x %s! +$%d (Tax: -$%d)", activator:Nick(), wepName, dealerPayout, salesTax), NOTIFY_GENERIC)
            owner:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 115)
        end

        if GRID.Telemetry and GRID.Telemetry.Log then
            GRID.Telemetry.Log("TRADE", "SHIPMENT_PURCHASE", activator:SteamID(), IsValid(owner) and owner:SteamID() or "", retailPrice, {
                weapon = wepClass,
                tax = salesTax,
                dealer_payout = dealerPayout
            })
        end
    end

    -- Calculate weapon ammo / clip metadata & full durability
    local itemData = {
        clip1 = 0,
        clip2 = 0,
        durability = 100
    }
    local wepTable = weapons.Get(wepClass)
    if wepTable and wepTable.Primary and wepTable.Primary.ClipSize and wepTable.Primary.ClipSize > 0 then
        itemData.clip1 = wepTable.Primary.ClipSize
    end

    local added = false
    if GRID.Database and GRID.Database.AddInventoryItem then
        added = GRID.Database.AddInventoryItem(activator:SteamID(), wepClass, "weapon", 1, itemData)
    end

    if added then
        if GRID.Inventory and GRID.Inventory.Sync then
            GRID.Inventory.Sync(activator)
        end
        activator:EmitSound("items/ammo_pickup.wav", 65, 100)
        local actionStr = isOwner and "Retrieved" or "Purchased"
        GRID.Notify(activator, string.format("%s 1x %s into your bag (%d remaining in crate).", actionStr, wepName, count - 1), NOTIFY_GENERIC)
    else
        -- If inventory is full, drop it on top of shipment
        local spawnedWep = ents.Create(wepClass)
        if IsValid(spawnedWep) then
            spawnedWep.GRID_Dropped = true
            spawnedWep:SetPos(self:GetPos() + Vector(0, 0, 25))
            spawnedWep:Spawn()
            spawnedWep:Activate()
            if spawnedWep.SetDurability then
                spawnedWep:SetDurability(100)
            end
            if itemData.clip1 > 0 then
                spawnedWep:SetClip1(itemData.clip1)
            end
            GRID.Notify(activator, "Your bags are full! 1x " .. wepName .. " dispensed onto shipment crate.", NOTIFY_HINT)
        end
    end

    count = count - 1
    self:SetCount(count)

    if count <= 0 then
        self:EmitSound("physics/wood/wood_crate_break1.wav", 75, 100)
        local ed = EffectData()
        ed:SetOrigin(self:GetPos())
        util.Effect("WoodPermeate", ed)
        self:Remove()
    end
end
