--[[
    sv_inventory.lua - Server-Side Inventory Pickup, Slot Movement, Drop & Persistence Engine
    Author: Toxic & Antigravity
--]]

GW.Inventory = GW.Inventory or {}

-- ========================================================
-- INVENTORY SYNC ENGINE (BAGS & SLOTS)
-- ========================================================

function GW.Inventory.Sync(ply)
    if not IsValid(ply) then return end
    local steamID = ply:SteamID()
    local rows = GW.Database.GetInventory(steamID) or {}
    local bags = GW.Database.GetPlayerBags(steamID)

    net.Start("GW_SyncInventory")
        net.WriteUInt(#rows, 16)
        for _, row in ipairs(rows) do
            net.WriteUInt(tonumber(row.id) or 0, 32)
            net.WriteUInt(tonumber(row.bag_index) or 0, 8)
            net.WriteUInt(tonumber(row.slot_index) or 1, 8)
            net.WriteString(row.item_id or "")
            net.WriteString(row.item_type or "generic")
            net.WriteUInt(tonumber(row.amount) or 1, 16)
            net.WriteString(row.item_data or "{}")
        end

        -- Equipped Bags in Bag Slots 1..4 (Bag 0 is the permanent 16-slot Backpack)
        net.WriteString(bags.bag1 or "")
        net.WriteString(bags.bag2 or "")
        net.WriteString(bags.bag3 or "")
        net.WriteString(bags.bag4 or "")
    net.Send(ply)
end

hook.Add("PlayerInitialSpawn", "GW_SyncInventoryOnJoin", function(ply)
    timer.Simple(2.5, function()
        if IsValid(ply) then
            GW.Inventory.Sync(ply)
        end
    end)
end)

-- ========================================================
-- PICKUP LOGIC (RIGHT-CLICK WITH HANDS)
-- ========================================================

function GW.Inventory.PickupEntity(ply, ent)
    if not IsValid(ply) or not ply:Alive() or not IsValid(ent) then return false end

    -- Verify Distance (Within 95 source units)
    if ent:GetPos():DistToSqr(ply:EyePos()) > (95 * 95) then
        return false
    end

    -- Protection: Cannot pickup players, NPCs, world, flag poles, or doors
    if ent:IsPlayer() or ent:IsNPC() or ent:IsWorld() or ent:isDoor() or ent:GetClass() == "gw_flag_pole" then
        return false
    end

    local class = ent:GetClass()

    -- 1. Cash Stacks: Pocket directly into wallet
    if class == "gw_cash_stack" then
        local amt = ent:GetAmount() or 0
        if amt > 0 then
            ply:AddMoney(amt)
            ent:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 100)
            GW.Notify(ply, string.format("Pocketed $%s cash.", string.Comma(amt)), NOTIFY_GENERIC)
            ent:Remove()
            return true
        end
        return false
    end

    -- 2. Weapons on Ground
    if ent:IsWeapon() then
        -- Hobo Restriction: Hobos cannot pick up weapons
        if ply:GetJob() == "hobo" and not (GW.HoboAllowedWeapons and GW.HoboAllowedWeapons[class]) then
            GW.Notify(ply, "Hobos can only use building tools and hands!", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        local itemId = class
        local itemData = {
            clip1 = ent:Clip1(),
            clip2 = ent:Clip2()
        }
        local def = GW.Inventory.GetItemData(itemId)
        local reqLevel = (def and def.level) or 1

        local added = GW.Database.AddInventoryItem(ply:SteamID(), itemId, "weapon", 1, itemData)
        if not added then
            if ply:GetLevel() < reqLevel then
                GW.Notify(ply, string.format("Your bags are full and you must be Level %d to equip %s directly!", reqLevel, def and def.name or itemId), NOTIFY_ERROR)
                ply:EmitSound("common/warning.wav", 65, 100)
                return false
            end
            if not ply:HasWeapon(itemId) then
                ply:Give(itemId)
                ply:SelectWeapon(itemId)
                local givenWep = ply:GetWeapon(itemId)
                if IsValid(givenWep) and itemData.clip1 and itemData.clip1 >= 0 then
                    givenWep:SetClip1(itemData.clip1)
                end
                ent:EmitSound("items/itempickup.wav", 65, 100)
                local def = GW.Inventory.GetItemData(itemId)
                GW.Notify(ply, "Bags full! Equipped " .. (def and def.name or itemId) .. " directly.", NOTIFY_GENERIC)
                ent:Remove()
                return true
            else
                GW.Notify(ply, "Your bags are full and you already have this weapon equipped!", NOTIFY_ERROR)
                ply:EmitSound("common/warning.wav", 65, 100)
                return false
            end
        end

        ent:EmitSound("items/itempickup.wav", 65, 100)
        local def = GW.Inventory.GetItemData(itemId)
        GW.Notify(ply, "Stored " .. def.name .. " into your bag.", NOTIFY_GENERIC)
        ent:Remove()
        GW.Inventory.Sync(ply)
        return true
    end

    -- 3. Money Printers
    if class == "gw_printer_bronze" or class == "gw_printer_silver" or class == "gw_printer_diamond" then
        if ent.DisconnectFromSwitch then ent:DisconnectFromSwitch() end
        local itemData = {
            storedCash = ent:GetStoredCash() or 0,
            hasUndervolt = ent.GetHasUndervolt and ent:GetHasUndervolt() or false
        }

        local added = GW.Database.AddInventoryItem(ply:SteamID(), class, "printer", 1, itemData)
        if not added then
            GW.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        ent:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 65, 100)
        local def = GW.Inventory.GetItemData(class)
        GW.Notify(ply, "Stored " .. def.name .. " into your bag.", NOTIFY_GENERIC)
        if ent.HumSound then ent.HumSound:Stop() end
        timer.Remove("GW_PrintTick_" .. ent:EntIndex())
        ent:Remove()
        GW.Inventory.Sync(ply)
        return true
    end

    -- 3.5 Network Switch Appliance
    if class == "gw_network_switch" then
        if ent.DisconnectAll then ent:DisconnectAll() end
        local added = GW.Database.AddInventoryItem(ply:SteamID(), class, "switch", 1, {})
        if not added then
            GW.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        ent:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 65, 100)
        local def = GW.Inventory.GetItemData(class)
        GW.Notify(ply, "Stored " .. (def and def.name or "L3 Network Switch") .. " into your bag.", NOTIFY_GENERIC)
        ent:Remove()
        GW.Inventory.Sync(ply)
        return true
    end

    -- 3.55 Satellite WAN Uplink Gateway
    if class == "gw_wan_uplink" then
        if ent.DisconnectFromSwitch then ent:DisconnectFromSwitch() end
        local added = GW.Database.AddInventoryItem(ply:SteamID(), class, "uplink", 1, {})
        if not added then
            GW.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        ent:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 65, 100)
        local def = GW.Inventory.GetItemData(class)
        GW.Notify(ply, "Stored " .. (def and def.name or "Satellite WAN Uplink") .. " into your bag.", NOTIFY_GENERIC)
        ent:Remove()
        GW.Inventory.Sync(ply)
        return true
    end

    -- 3.6 Hardware Upgrade Modules
    if class == "gw_module_undervolt" then
        local added = GW.Database.AddInventoryItem(ply:SteamID(), class, "module", 1, {})
        if not added then
            GW.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        ent:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 65, 100)
        local def = GW.Inventory.GetItemData(class)
        GW.Notify(ply, "Stored " .. (def and def.name or "Undervolt Module") .. " into your bag.", NOTIFY_GENERIC)
        ent:Remove()
        GW.Inventory.Sync(ply)
        return true
    end

    -- 4. Wholesale Weapon Shipments
    if class == "gw_shipment" then
        local itemData = {
            weaponClass = ent:GetWeaponClass() or "weapon_gw_glock",
            weaponName = ent:GetWeaponName() or "Weapons",
            count = ent:GetCount() or 10
        }

        local added = GW.Database.AddInventoryItem(ply:SteamID(), "gw_shipment", "shipment", 1, itemData)
        if not added then
            GW.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        ent:EmitSound("items/ammo_pickup.wav", 65, 100)
        GW.Notify(ply, "Stored " .. itemData.weaponName .. " Crate into your bag.", NOTIFY_GENERIC)
        ent:Remove()
        GW.Inventory.Sync(ply)
        return true
    end

    -- 5. Crafting Ingot, Carbon Rod & Blueprint Material Props
    if class == "gw_crafting_material" then
        if GW.Crafting and GW.Crafting.PickupMaterial then
            return GW.Crafting.PickupMaterial(ply, ent)
        end
        return false
    end

    -- 6. Resource Fabricator Machine
    if class == "gw_resource_machine" then
        local owner = ent.GetOwnerPlayer and ent:GetOwnerPlayer()
        if IsValid(owner) and owner ~= ply and not ply:IsAdmin() then
            GW.Notify(ply, "Only the owner can pack up this Resource Fabricator!", NOTIFY_ERROR)
            return false
        end

        if ent.DisconnectFromSwitch then ent:DisconnectFromSwitch() end
        if IsValid(ent.CurrentItem) then
            constraint.RemoveAll(ent.CurrentItem)
            ent.CurrentItem.ParentMachine = nil
            local phys = ent.CurrentItem:GetPhysicsObject()
            if IsValid(phys) then phys:Wake() end
            ent.CurrentItem = nil
        end

        local added = GW.Database.AddInventoryItem(ply:SteamID(), class, "entity", 1, {})
        if not added then
            GW.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        ent:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 65, 100)
        local def = GW.Inventory.GetItemData(class)
        GW.Notify(ply, "Packed " .. (def and def.name or "Resource Fabricator") .. " into your bag.", NOTIFY_GENERIC)
        ent:Remove()
        GW.Inventory.Sync(ply)
        return true
    end

    return false
end

-- ========================================================
-- SLOT MOVEMENT & DRAG-AND-DROP HANDLER
-- ========================================================

net.Receive("GW_MoveInventorySlot", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GW.CheckRateLimit(ply, "inv_move", 6) then return end

    local fromBag = net.ReadUInt(8)
    local fromSlot = net.ReadUInt(8)
    local toBag = net.ReadUInt(8)
    local toSlot = net.ReadUInt(8)
    local steamID = ply:SteamID()

    local success = GW.Database.MoveInventorySlot(steamID, fromBag, fromSlot, toBag, toSlot)
    if success then
        ply:EmitSound("weapons/weapon_drop.wav", 55, 110)
        GW.Inventory.Sync(ply)
    end
end)

-- ========================================================
-- DROP FROM SPECIFIC SLOT
-- ========================================================

net.Receive("GW_DropInventorySlot", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GW.CheckRateLimit(ply, "inv_drop", 4) then return end

    local bagIndex = net.ReadUInt(8)
    local slotIndex = net.ReadUInt(8)
    local steamID = ply:SteamID()

    local targetRow = GW.Database.GetInventorySlot(steamID, bagIndex, slotIndex)
    if not targetRow then return end

    local itemId = targetRow.item_id
    local itemType = targetRow.item_type
    local rawData = util.JSONToTable(targetRow.item_data or "{}") or {}

    local tr = ply:GetEyeTrace()
    local spawnPos = ply:GetShootPos() + ply:GetAimVector() * 45
    if tr.Hit and tr.HitPos:DistToSqr(ply:GetShootPos()) < (45 * 45) then
        spawnPos = tr.HitPos + tr.HitNormal * 10
    end

    local spawnedEnt = nil

    if itemType == "weapon" then
        spawnedEnt = ents.Create(itemId)
        if IsValid(spawnedEnt) then
            spawnedEnt.GW_Dropped = true
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:Spawn()
            spawnedEnt:Activate()
            if rawData.clip1 then spawnedEnt:SetClip1(rawData.clip1) end
            if rawData.clip2 then spawnedEnt:SetClip2(rawData.clip2) end
        end

    elseif itemType == "printer" or itemType == "switch" or itemId == "gw_resource_machine" then
        spawnedEnt = ents.Create(itemId)
        if IsValid(spawnedEnt) then
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:SetAngles(Angle(0, ply:EyeAngles().y, 0))
            if spawnedEnt.SetOwnerPlayer then spawnedEnt:SetOwnerPlayer(ply) end
            spawnedEnt:Spawn()
            spawnedEnt:Activate()
            if rawData.storedCash and rawData.storedCash > 0 and spawnedEnt.SetStoredCash then
                spawnedEnt:SetStoredCash(rawData.storedCash)
            end
            if rawData.hasUndervolt and spawnedEnt.SetHasUndervolt then
                spawnedEnt:SetHasUndervolt(true)
            end
        end

    elseif itemType == "material" or itemType == "blueprint" then
        spawnedEnt = ents.Create("gw_crafting_material")
        if IsValid(spawnedEnt) then
            spawnedEnt:SetMaterialID(itemId)
            spawnedEnt:SetAmount(1)
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:Spawn()
            spawnedEnt:Activate()
        end

    elseif itemType == "shipment" then
        spawnedEnt = ents.Create("gw_shipment")
        if IsValid(spawnedEnt) then
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:SetAngles(Angle(0, ply:EyeAngles().y, 0))
            spawnedEnt:SetWeaponClass(rawData.weaponClass or "weapon_gw_glock")
            spawnedEnt:SetWeaponName(rawData.weaponName or "Weapons")
            spawnedEnt:SetCount(rawData.count or 10)
            spawnedEnt:Spawn()
            spawnedEnt:Activate()
        end

    elseif itemType == "bag" then
        -- Bag drop: drops as physical suitcase/satchel
        spawnedEnt = ents.Create("prop_physics")
        if IsValid(spawnedEnt) then
            local def = GW.Inventory.GetItemData(itemId)
            spawnedEnt:SetModel(def.model or "models/props_c17/Suitcase001a.mdl")
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:Spawn()
            spawnedEnt:Activate()
        end
    else
        spawnedEnt = ents.Create(itemId)
        if IsValid(spawnedEnt) then
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:Spawn()
            spawnedEnt:Activate()
        end
    end

    if IsValid(spawnedEnt) then
        local phys = spawnedEnt:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(ply:GetAimVector() * 80 + Vector(0, 0, 40))
        end
        spawnedEnt:EmitSound("physics/metal/metal_box_impact_soft1.wav", 65, 100)

        GW.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, 1)
        local def = GW.Inventory.GetItemData(itemId)
        GW.Notify(ply, "Dropped " .. def.name .. " onto the ground.", NOTIFY_GENERIC)
        GW.Inventory.Sync(ply)
    end
end)

-- ========================================================
-- USE / EQUIP FROM SPECIFIC SLOT
-- ========================================================

net.Receive("GW_UseInventorySlot", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GW.CheckRateLimit(ply, "inv_use", 4) then return end

    local bagIndex = net.ReadUInt(8)
    local slotIndex = net.ReadUInt(8)
    local steamID = ply:SteamID()

    local targetRow = GW.Database.GetInventorySlot(steamID, bagIndex, slotIndex)
    if not targetRow then return end

    local itemId = targetRow.item_id
    local itemType = targetRow.item_type
    local def = GW.Inventory.GetItemData(itemId)

    local reqLevel = (def and def.level) or 1
    if ply:GetLevel() < reqLevel then
        GW.Notify(ply, string.format("You must be Level %d to use/equip %s!", reqLevel, def and def.name or itemId), NOTIFY_ERROR)
        return
    end

    if itemType == "weapon" then
        -- Hobo Restriction: Hobos can only use building tools
        if ply:GetJob() == "hobo" and not (GW.HoboAllowedWeapons and GW.HoboAllowedWeapons[itemId]) then
            GW.Notify(ply, "Hobos can only use building tools and hands!", NOTIFY_ERROR)
            return
        end

        if ply:HasWeapon(itemId) then
            GW.Notify(ply, "You already have this weapon equipped!", NOTIFY_ERROR)
            return
        end

        ply:Give(itemId)
        ply:SelectWeapon(itemId)
        ply:EmitSound("items/ammo_pickup.wav", 65, 100)

        GW.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, 1)
        GW.Notify(ply, "Equipped " .. def.name .. ".", NOTIFY_GENERIC)
        GW.Inventory.Sync(ply)

    elseif itemType == "bag" then
        -- Equip into first free bag slot 1..4
        local bags = GW.Database.GetPlayerBags(steamID)
        local equippedSlot = nil
        for i = 1, 4 do
            if not bags["bag" .. i] or bags["bag" .. i] == "" then
                equippedSlot = i
                break
            end
        end

        if not equippedSlot then
            GW.Notify(ply, "All 4 bag expansion slots are full!", NOTIFY_ERROR)
            return
        end

        bags["bag" .. equippedSlot] = itemId
        GW.Database.SetPlayerBags(steamID, bags.bag1, bags.bag2, bags.bag3, bags.bag4)
        GW.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, 1)

        ply:EmitSound("items/ammocrate_open.wav", 65, 100)
        GW.Notify(ply, "Equipped " .. def.name .. " into Bag Slot " .. equippedSlot .. "!", NOTIFY_GENERIC)
        GW.Inventory.Sync(ply)

    elseif itemType == "consumable" then
        if def.buffId then
            ply:AddBuff(def.buffId, def.buffDuration)
            ply:EmitSound("npc/barnacle/barnacle_gulp1.wav", 65, 110)
            GW.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, 1)
            GW.Notify(ply, "Consumed " .. def.name .. "!", NOTIFY_GENERIC)
            GW.Inventory.Sync(ply)
        end

    elseif itemType == "printer" or itemType == "shipment" or itemType == "switch" or itemType == "module" then
        -- Quick-deploy to ground
        local rawData = util.JSONToTable(targetRow.item_data or "{}") or {}
        local tr = ply:GetEyeTrace()
        local spawnPos = ply:GetShootPos() + ply:GetAimVector() * 50
        if tr.Hit and tr.HitPos:DistToSqr(ply:GetShootPos()) < (50 * 50) then
            spawnPos = tr.HitPos + tr.HitNormal * 10
        end

        local spawnedEnt = ents.Create(itemId)
        if IsValid(spawnedEnt) then
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:SetAngles(Angle(0, ply:EyeAngles().y, 0))
            if spawnedEnt.SetOwnerPlayer then spawnedEnt:SetOwnerPlayer(ply) end
            spawnedEnt:Spawn()
            spawnedEnt:Activate()

            if itemType == "printer" then
                if rawData.storedCash and rawData.storedCash > 0 and spawnedEnt.SetStoredCash then
                    spawnedEnt:SetStoredCash(rawData.storedCash)
                end
                if rawData.hasUndervolt and spawnedEnt.SetHasUndervolt then
                    spawnedEnt:SetHasUndervolt(true)
                end
            elseif itemType == "shipment" then
                spawnedEnt:SetWeaponClass(rawData.weaponClass or "weapon_gw_glock")
                spawnedEnt:SetWeaponName(rawData.weaponName or "Weapons")
                spawnedEnt:SetCount(rawData.count or 10)
            end

            GW.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, 1)
            GW.Notify(ply, "Deployed " .. def.name .. ".", NOTIFY_GENERIC)
            GW.Inventory.Sync(ply)
        end
    end
end)

-- ========================================================
-- LEGACY FALLBACK HANDLERS
-- ========================================================

net.Receive("GW_DropInventoryItem", function(len, ply)
    local rowId = net.ReadUInt(32)
    local steamID = ply:SteamID()
    local rows = GW.Database.GetInventory(steamID) or {}
    for _, r in ipairs(rows) do
        if tonumber(r.id) == rowId then
            net.Start("GW_DropInventorySlot")
            -- Re-route internally
            local bag = tonumber(r.bag_index) or 0
            local slot = tonumber(r.slot_index) or 1
            GW.Database.RemoveInventoryItemAtSlot(steamID, bag, slot, 1)
            GW.Inventory.Sync(ply)
            break
        end
    end
end)

net.Receive("GW_UseInventoryItem", function(len, ply)
    local rowId = net.ReadUInt(32)
    local steamID = ply:SteamID()
    local rows = GW.Database.GetInventory(steamID) or {}
    for _, r in ipairs(rows) do
        if tonumber(r.id) == rowId then
            local itemId = r.item_id
            if r.item_type == "weapon" then
                if ply:GetJob() == "hobo" and not (GW.HoboAllowedWeapons and GW.HoboAllowedWeapons[itemId]) then
                    GW.Notify(ply, "Hobos can only use building tools and hands!", NOTIFY_ERROR)
                    return
                end
                if not ply:HasWeapon(itemId) then
                    ply:Give(itemId)
                    ply:SelectWeapon(itemId)
                    GW.Database.RemoveInventoryItemAtSlot(steamID, tonumber(r.bag_index) or 0, tonumber(r.slot_index) or 1, 1)
                    GW.Inventory.Sync(ply)
                end
            end
            break
        end
    end
end)

-- Server Chat Command Handler for /inv, /inventory
hook.Add("PlayerSay", "GW_InventoryChatCommands", function(ply, text)
    local lower = string.lower(string.Trim(text))
    if lower == "/inv" or lower == "!inv" or lower == "/inventory" or lower == "!inventory" or lower == "/bag" or lower == "!bag" then
        ply:ConCommand("inventory")
        return ""
    end
end)

-- ========================================================
-- DIRECT WORLD ITEM PICKUP (+USE / E KEY)
-- ========================================================
hook.Add("KeyPress", "GW_WeaponPickupUse", function(ply, key)
    if key ~= IN_USE then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local tr = util.TraceLine({
        start = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * 95,
        filter = ply
    })

    local ent = tr.Entity
    if IsValid(ent) and ent:IsWeapon() then
        GW.Inventory.PickupEntity(ply, ent)
    end
end)

-- Chat commands to drop currently active weapon (/dropweapon, /dropgun, /drop)
hook.Add("PlayerSay", "GW_DropWeaponChatCommands", function(ply, text)
    local lower = string.lower(string.Trim(text))
    if lower == "/dropweapon" or lower == "!dropweapon" or lower == "/dropgun" or lower == "!dropgun" or lower == "/drop" or lower == "!drop" then
        if not IsValid(ply) or not ply:Alive() then return "" end

        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) then
            GW.Notify(ply, "You are not holding a weapon to drop!", NOTIFY_ERROR)
            return ""
        end

        local class = wep:GetClass()
        if class == "weapon_gw_keys" or class == "weapon_physcannon" or class == "weapon_physgun" or class == "weapon_fists" or class == "fists" or class == "gmod_tool" then
            GW.Notify(ply, "You cannot drop standard utility gear!", NOTIFY_ERROR)
            return ""
        end

        local clip1 = wep:Clip1()
        local clip2 = wep:Clip2()

        local tr = ply:GetEyeTrace()
        local spawnPos = ply:GetShootPos() + ply:GetAimVector() * 45
        if tr.Hit and tr.HitPos:DistToSqr(ply:GetShootPos()) < (45 * 45) then
            spawnPos = tr.HitPos + tr.HitNormal * 10
        end

        local spawnedEnt = ents.Create(class)
        if IsValid(spawnedEnt) then
            spawnedEnt.GW_Dropped = true
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:Spawn()
            spawnedEnt:Activate()
            if clip1 and clip1 >= 0 then spawnedEnt:SetClip1(clip1) end
            if clip2 and clip2 >= 0 then spawnedEnt:SetClip2(clip2) end

            local phys = spawnedEnt:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetVelocity(ply:GetAimVector() * 80 + Vector(0, 0, 40))
            end
            spawnedEnt:EmitSound("weapons/weapon_drop.wav", 65, 100)
        end

        ply:StripWeapon(class)
        local def = GW.Inventory and GW.Inventory.GetItemData and GW.Inventory.GetItemData(class)
        GW.Notify(ply, "Dropped " .. (def and def.name or class) .. " onto the ground.", NOTIFY_GENERIC)
        return ""
    end
end)
