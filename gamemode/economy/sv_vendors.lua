--[[
    sv_vendors.lua - F4 Menu Purchase Engine with Role, Contraband & Anti-Exploit Validation
    Author: GW Core Team
    Namespace: GW / gw_
]]

net.Receive("GW_BuyItem", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GW.CheckRateLimit(ply, "buy_item", 4) then return end
    local itemId = net.ReadString()
    local item = GW.ShopItems[itemId]
    if not item then return end

    -- 1. Anti-Exploit: Strict SuperAdmin Gating for Debug Items
    if item.debug then
        if not GW.Config.EnableDebugShop or not ply:IsSuperAdmin() then
            GW.Notify(ply, "Debug shop items are strictly disabled for non-developers!", NOTIFY_ERROR)
            if GW.Telemetry and GW.Telemetry.LogAnomaly then
                GW.Telemetry.LogAnomaly(ply:SteamID(), "UNAUTHORIZED_DEBUG_SHOP_BUY", { item = itemId })
            end
            return
        end
    end

    -- 2. Hobo Restriction: Hobos cannot purchase items
    if ply:GetJob() == "hobo" then
        GW.Notify(ply, "Hobos cannot purchase items! You can only use building tools.", NOTIFY_ERROR)
        return
    end

    -- 3. Police Restriction: Police cannot purchase printers, contraband, or weapon shipments
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

    -- 4. Level Requirement
    local reqLevel = item.level or 1
    if ply:GetLevel() < reqLevel then
        GW.Notify(ply, string.format("You must be Level %d to purchase this item!", reqLevel), NOTIFY_ERROR)
        return
    end

    -- 5. Job Requirement
    if item.jobs then
        if not table.HasValue(item.jobs, ply:GetJob()) then
            GW.Notify(ply, "Your current job cannot purchase this item!", NOTIFY_ERROR)
            return
        end
    elseif item.job and ply:GetJob() ~= item.job then
        GW.Notify(ply, "Your current job cannot purchase this item!", NOTIFY_ERROR)
        return
    end

    -- 6. Enforce Global Max Printer Limit per Player (4)
    if item.category == "printers" or string.find(item.class or itemId, "printer_") then
        local maxPrinters = GW.Config.MaxPrintersPerPlayer or 4
        local curPrinters = 0
        for _, p in ipairs(ents.GetAll()) do
            local pc = p:GetClass()
            if (pc == "gw_printer_bronze" or pc == "gw_printer_silver" or pc == "gw_printer_diamond") and ((p.GetOwnerPlayer and p:GetOwnerPlayer() == ply) or p.OwnerPlayer == ply or p.GW_Owner == ply) then
                curPrinters = curPrinters + 1
            end
        end
        if curPrinters >= maxPrinters then
            GW.Notify(ply, string.format("You have reached your maximum active printer limit (%d/%d)!", curPrinters, maxPrinters), NOTIFY_ERROR)
            return
        end
    end

    -- 7. Calculate Effective Cost (Wholesale for specialists vs Retail kiosk markup)
    local cost = GW.GetItemCost(item, ply)
    if not ply:CanAfford(cost) then
        GW.Notify(ply, "You cannot afford this item ($" .. cost .. ")!", NOTIFY_ERROR)
        return
    end

    -- 8. Execute Transaction & Dispatch Item
    if item.type == "weapon" then
        ply:AddMoney(-cost)
        ply:Give(item.class)
        local wep = ply:GetWeapon(item.class)
        if IsValid(wep) and wep.SetDurability then
            wep:SetDurability(100)
        end
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
                if (existing.GetOwnerPlayer and existing:GetOwnerPlayer() == ply) or existing.OwnerPlayer == ply or existing.GW_Owner == ply then
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
            ent.GW_Owner = ply
            ent.PurchaserSteamID = ply:SteamID()
            if ent.SetOwnerPlayer then
                ent:SetOwnerPlayer(ply)
            end
            ent:Spawn()
            ent:Activate()
            GW.Notify(ply, "Purchased " .. item.name .. "!", NOTIFY_GENERIC)
        else
            GW.Notify(ply, "Unable to spawn " .. item.name .. "! (Please reload map with 'changelevel')", NOTIFY_ERROR)
            return
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
            crate.GW_Owner = ply
            crate.PurchaserSteamID = ply:SteamID()
            crate.WholesaleBase = cost
            crate:SetJobAffinity(ply:GetJob())
            crate:SetOwnerPlayer(ply)
            local unitWholesale = math.max(1, math.floor(cost / (item.count or 10)))
            crate:SetUnitPrice(math.floor(unitWholesale * 1.35))
            crate:Spawn()
            crate:Activate()
            GW.Notify(ply, "Delivered " .. item.name .. "! (Set retail price or sell to citizens)", NOTIFY_GENERIC)
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

    if GW.Telemetry and GW.Telemetry.Log then
        GW.Telemetry.Log("TRADE", "VENDOR_PURCHASE", ply:SteamID(), "", cost, {
            item = itemId,
            type = item.type
        })
    end
end)
