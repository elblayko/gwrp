--[[
    sv_vendors.lua - F4 Menu Purchase Engine
--]]

net.Receive("GW_BuyItem", function(len, ply)
    if not GW.CheckRateLimit(ply, "buy_item", 4) then return end
    local itemId = net.ReadString()
    local item = GW.ShopItems[itemId]
    if not item then return end

    local reqLevel = item.level or 1
    if ply:GetLevel() < reqLevel then
        GW.Notify(ply, string.format("You must be Level %d to purchase this item!", reqLevel), NOTIFY_ERROR)
        return
    end

    if item.jobs then
        if not table.HasValue(item.jobs, ply:GetJob()) then
            GW.Notify(ply, "Your current job cannot purchase this item!", NOTIFY_ERROR)
            return
        end
    elseif item.job and ply:GetJob() ~= item.job then
        GW.Notify(ply, "Your current job cannot purchase this item!", NOTIFY_ERROR)
        return
    end

    if not ply:CanAfford(item.cost) then
        GW.Notify(ply, "You cannot afford this item!", NOTIFY_ERROR)
        return
    end

    if item.type == "weapon" then
        ply:AddMoney(-item.cost)
        ply:Give(item.class)
        GW.Notify(ply, "Purchased " .. item.name .. "!", NOTIFY_GENERIC)
    elseif item.type == "ammo" then
        ply:AddMoney(-item.cost)
        local mult = (itemId == "ammo_bulk_crate") and 2 or 1
        ply:GiveAmmo(90 * mult, "Pistol", true)
        ply:GiveAmmo(120 * mult, "AR2", true)
        ply:GiveAmmo(32 * mult, "Buckshot", true)
        ply:GiveAmmo(28 * mult, "357", true)
        GW.Notify(ply, (mult > 1 and "Delivered Wholesale Bulk Ammo Pack!" or "Purchased Ammo Pack!"), NOTIFY_GENERIC)
    elseif item.type == "entity" then
        if item.max then
            local count = 0
            for _, existing in ipairs(ents.FindByClass(item.class)) do
                if existing.GetOwnerPlayer and existing:GetOwnerPlayer() == ply then
                    count = count + 1
                end
            end
            if count >= item.max then
                GW.Notify(ply, string.format("You have reached the maximum limit of %d %s!", item.max, item.name), NOTIFY_ERROR)
                return
            end
        end

        local trace = ply:GetEyeTrace()
        local spawnPos = trace.HitPos + trace.HitNormal * 15

        local ent = ents.Create(item.class)
        if IsValid(ent) then
            ply:AddMoney(-item.cost)
            ent:SetPos(spawnPos)
            ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
            if ent.SetOwnerPlayer then
                ent:SetOwnerPlayer(ply)
            end
            ent:Spawn()
            ent:Activate()
            GW.Notify(ply, "Purchased " .. item.name .. "!", NOTIFY_GENERIC)
        else
            GW.Notify(ply, "Unable to spawn " .. item.name .. "! (Please reload map with 'changelevel')", NOTIFY_ERROR)
        end
    elseif item.type == "shipment" then
        ply:AddMoney(-item.cost)
        local trace = ply:GetEyeTrace()
        local spawnPos = trace.HitPos + trace.HitNormal * 20

        local crate = ents.Create("gw_shipment")
        if IsValid(crate) then
            crate:SetPos(spawnPos)
            crate:SetAngles(Angle(0, ply:EyeAngles().y, 0))
            crate:SetWeaponClass(item.weapon)
            crate:SetWeaponName(item.weaponName)
            crate:SetCount(item.count)
            crate:Spawn()
            crate:Activate()
            GW.Notify(ply, "Delivered " .. item.name .. "!", NOTIFY_GENERIC)
        end
    elseif item.type == "armor" then
        ply:AddMoney(-item.cost)
        ply:SetArmor(100)
        GW.Notify(ply, "Armor fully restored!", NOTIFY_GENERIC)
    elseif item.type == "medkit" then
        ply:AddMoney(-item.cost)
        ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + 60))
        GW.Notify(ply, "Health restored by +60 HP!", NOTIFY_GENERIC)
    elseif item.type == "buff" then
        ply:AddMoney(-item.cost)
        if ply.AddBuff and item.buffId then
            ply:AddBuff(item.buffId, item.buffDuration, item.buffData)
            GW.Notify(ply, "Applied " .. item.name .. "!", NOTIFY_GENERIC)
        end
    elseif item.type == "consumable" then
        local targetId = item.itemId or item.class
        local invDef = GW.Inventory and GW.Inventory.GetItemData and GW.Inventory.GetItemData(targetId)
        local added = false

        if GW.Database and GW.Database.AddInventoryItem then
            added = GW.Database.AddInventoryItem(ply:SteamID(), targetId, "consumable", 1, "{}")
        end

        if added then
            ply:AddMoney(-item.cost)
            GW.Notify(ply, "Purchased " .. item.name .. " (Added to Bag)!", NOTIFY_GENERIC)
            if GW.Inventory and GW.Inventory.Sync then
                GW.Inventory.Sync(ply)
            end
        else
            -- If inventory is full or failed, apply effect directly as fallback
            ply:AddMoney(-item.cost)
            if invDef and invDef.buffId and ply.AddBuff then
                ply:AddBuff(invDef.buffId, invDef.buffDuration)
            end
            GW.Notify(ply, "Bag full! Automatically consumed " .. item.name .. ".", NOTIFY_HINT)
        end
    elseif item.type == "cleanse" then
        ply:AddMoney(-item.cost)
        if ply.ClearBuffs then
            ply:ClearBuffs(false)
        end
        GW.Notify(ply, "Cleansed all active buffs and debuffs!", NOTIFY_GENERIC)
    end
end)
