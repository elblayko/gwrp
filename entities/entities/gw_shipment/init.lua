--[[
    entities/entities/gw_shipment/init.lua
--]]

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
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

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

    -- Calculate weapon ammo / clip metadata
    local itemData = {
        clip1 = 0,
        clip2 = 0
    }
    local wepTable = weapons.Get(wepClass)
    if wepTable and wepTable.Primary and wepTable.Primary.ClipSize and wepTable.Primary.ClipSize > 0 then
        itemData.clip1 = wepTable.Primary.ClipSize
    end

    -- First try to add to player's inventory bag so the gun dealer can hold multiple weapons to sell/trade
    local added = false
    if GW.Database and GW.Database.AddInventoryItem then
        added = GW.Database.AddInventoryItem(activator:SteamID(), wepClass, "weapon", 1, itemData)
    end

    if added then
        if GW.Inventory and GW.Inventory.Sync then
            GW.Inventory.Sync(activator)
        end
        activator:EmitSound("items/ammo_pickup.wav", 65, 100)
        GW.Notify(activator, string.format("Retrieved 1x %s into your bag (%d remaining in crate).", wepName, count - 1), NOTIFY_GENERIC)
    else
        -- If inventory is full, drop it on top of shipment
        local spawnedWep = ents.Create(wepClass)
        if IsValid(spawnedWep) then
            spawnedWep.GW_Dropped = true
            spawnedWep:SetPos(self:GetPos() + Vector(0, 0, 25))
            spawnedWep:Spawn()
            spawnedWep:Activate()
            if itemData.clip1 > 0 then
                spawnedWep:SetClip1(itemData.clip1)
            end
            GW.Notify(activator, "Your bags are full! Dropped 1x " .. wepName .. " on top of shipment.", NOTIFY_ERROR)
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
