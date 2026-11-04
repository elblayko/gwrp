--[[
    sv_vendors.lua - F4 Menu Purchase Engine with Role & Contraband Validation
--]]

net.Receive("GW_BuyItem", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GW.CheckRateLimit(ply, "buy_item", 4) then return end
    local itemId = net.ReadString()
    local item = GW.ShopItems[itemId]
    if not item then return end

    -- 1. Hobo Restriction: Hobos cannot purchase items
    if ply:GetJob() == "hobo" then
        GW.Notify(ply, "Hobos cannot purchase items! You can only use building tools.", NOTIFY_ERROR)
        return
    end

    -- 2. Police Restriction: Police cannot purchase printers, contraband, or weapon shipments
    if ply:IsPolice() then
        if item.category == "printers" or string.find(itemId, "printer_") then
            GW.Notify(ply, "Police officers cannot purchase money printers!", NOTIFY_ERROR)
            return
        end
        if item.isContraband or (item.jobs and table.HasValue(item.jobs, "black_market_dealer")) or (item.jobs and table.HasValue(item.jobs, "thief")) then
            GW.Notify(ply, "Police officers cannot purchase contraband!", NOTIFY_ERROR)
            return
        end
        if item.type == "shipment" then
            GW.Notify(ply, "Police officers cannot purchase wholesale weapon shipments!", NOTIFY_ERROR)
            return
        end
    end

    -- 3. Level Requirement
    local reqLevel = item.level or 1
    if ply:GetLevel() < reqLevel then
        GW.Notify(ply, string.format("You must be Level %d to purchase this item!", reqLevel), NOTIFY_ERROR)
        return
    end

    -- 4. Job Requirement
    if item.jobs then
        if not table.HasValue(item.jobs, ply:GetJob()) then
            GW.Notify(ply, "Your current job cannot purchase this item!", NOTIFY_ERROR)
            return
        end
    elseif item.job and ply:GetJob() ~= item.job then
        GW.Notify(ply, "Your current job cannot purchase this item!", NOTIFY_ERROR)
        return
    end

    -- 5. Calculate Effective Cost (Wholesale for specialists vs Retail kiosk markup)
    local cost = GW.GetItemCost(item, ply)
    if not ply:CanAfford(cost) then
        GW.Notify(ply, "You cannot afford this item ($" .. cost .. ")!", NOTIFY_ERROR)
        return
    end

    -- 6. Execute Transaction & Dispatch Item
    if item.type == "weapon" then
        ply:AddMoney(-cost)
        ply:Give(item.class)
        GW.Notify(ply, "Purchased " .. item.name .. "!", NOTIFY_GENERIC)
    elseif item.type == "ammo" then
        ply:AddMoney(-cost)
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
            ply:AddMoney(-cost)
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
        ply:AddMoney(-cost)
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
        ply:AddMoney(-cost)
        ply:SetArmor(100)
        GW.Notify(ply, "Armor fully restored!", NOTIFY_GENERIC)
    elseif item.type == "medkit" then
        ply:AddMoney(-cost)
        ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + 60))
        GW.Notify(ply, "Health restored by +60 HP!", NOTIFY_GENERIC)
    elseif item.type == "buff" then
        ply:AddMoney(-cost)
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
            ply:AddMoney(-cost)
            GW.Notify(ply, "Purchased " .. item.name .. " (Added to Bag)!", NOTIFY_GENERIC)
            if GW.Inventory and GW.Inventory.Sync then
                GW.Inventory.Sync(ply)
            end
        else
            -- If inventory is full or failed, apply effect directly as fallback
            ply:AddMoney(-cost)
            if invDef and invDef.buffId and ply.AddBuff then
                ply:AddBuff(invDef.buffId, invDef.buffDuration)
            end
            GW.Notify(ply, "Bag full! Automatically consumed " .. item.name .. ".", NOTIFY_HINT)
        end
    elseif item.type == "cleanse" then
        ply:AddMoney(-cost)
        if ply.ClearBuffs then
            ply:ClearBuffs(false)
        end
        GW.Notify(ply, "Cleansed all active buffs and debuffs!", NOTIFY_GENERIC)
    end
end)
