--[[
    sv_inventory.lua - Server-Side Inventory Pickup, Slot Movement, Drop & Persistence Engine
    Author: Juicebox & Antigravity
--]]

GRID = GRID or {}
GRID.Inventory = GRID.Inventory or {}

-- ========================================================
-- INVENTORY SYNC ENGINE (BAGS & SLOTS)
-- ========================================================

function GRID.Inventory.Sync(ply)
    if not IsValid(ply) then return end
    local steamID = ply:SteamID()
    local rows = GRID.Database.GetInventory(steamID) or {}
    local bags = GRID.Database.GetPlayerBags(steamID)

    local function WriteSyncPayload()
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
    end

    net.Start("GRID_SyncInventory")
    WriteSyncPayload()
    net.Send(ply)
end

hook.Add("PlayerInitialSpawn", "GRID_SyncInventoryOnJoin", function(ply)
    timer.Simple(2.5, function()
        if IsValid(ply) then
            GRID.Inventory.Sync(ply)
        end
    end)
end)

-- ========================================================
-- PICKUP LOGIC (RIGHT-CLICK WITH HANDS)
-- ========================================================

function GRID.Inventory.PickupEntity(ply, ent)
    if not IsValid(ply) or not ply:Alive() or not IsValid(ent) then return false end

    -- Verify Distance (Within 95 source units)
    if ent:GetPos():DistToSqr(ply:EyePos()) > (95 * 95) then
        return false
    end

    local class = ent:GetClass()

    -- Protection: Cannot pickup players, NPCs, world, flag poles, or doors
    if ent:IsPlayer() or ent:IsNPC() or ent:IsWorld() or ent:isDoor() or class == "grid_flag_pole" then
        return false
    end

    -- 1. Cash Stacks: Pocket directly into wallet
    if class == "grid_cash_stack" then
        local amt = ent:GetAmount() or 0
        if amt > 0 then
            ply:AddMoney(amt)
            ent:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 100)
            GRID.Notify(ply, string.format("Pocketed $%s cash.", string.Comma(amt)), NOTIFY_GENERIC)
            ent:Remove()
            return true
        end
        return false
    end

    -- 2. Weapons on Ground
    if ent:IsWeapon() then
        -- Hobo Restriction: Hobos cannot pick up weapons
        local allowed = GRID.HoboAllowedWeapons and GRID.HoboAllowedWeapons[class]
        if ply:GetJob() == "hobo" and not allowed then
            GRID.Notify(ply, "Hobos can only use building tools and hands!", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        local itemId = class
        local itemData = {
            clip1 = ent:Clip1(),
            clip2 = ent:Clip2(),
            durability = (ent.GetDurability and ent:GetDurability()) or 100
        }
        local def = GRID.Inventory.GetItemData(itemId)
        local reqLevel = (def and def.level) or 1

        local added = GRID.Database.AddInventoryItem(ply:SteamID(), itemId, "weapon", 1, itemData)
        if not added then
            if ply:GetLevel() < reqLevel then
                GRID.Notify(ply,
                    string.format("Your bags are full and you must be Level %d to equip %s directly!", reqLevel,
                        def and def.name or itemId), NOTIFY_ERROR)
                ply:EmitSound("common/warning.wav", 65, 100)
                return false
            end
            if not ply:HasWeapon(itemId) then
                ply:Give(itemId)
                ply:SelectWeapon(itemId)
                local givenWep = ply:GetWeapon(itemId)
                if IsValid(givenWep) then
                    givenWep.GRID_DurabilityInitialized = true
                    if givenWep.SetDurability and itemData.durability ~= nil then
                        givenWep:SetDurability(tonumber(itemData.durability) or 100)
                    end
                    if itemData.clip1 and itemData.clip1 >= 0 then
                        givenWep:SetClip1(itemData.clip1)
                    end
                    if itemData.clip2 and itemData.clip2 >= 0 then
                        givenWep:SetClip2(itemData.clip2)
                    end
                end
                ent:EmitSound("items/itempickup.wav", 65, 100)
                GRID.Notify(ply, "Bags full! Equipped " .. (def and def.name or itemId) .. " directly.", NOTIFY_GENERIC)
                ent:Remove()
                return true
            else
                GRID.Notify(ply, "Your bags are full and you already have this weapon equipped!", NOTIFY_ERROR)
                ply:EmitSound("common/warning.wav", 65, 100)
                return false
            end
        end

        ent:EmitSound("items/itempickup.wav", 65, 100)
        GRID.Notify(ply, "Stored " .. def.name .. " into your bag.", NOTIFY_GENERIC)
        ent:Remove()
        GRID.Inventory.Sync(ply)
        return true
    end

    -- 3. Money Printers
    if class == "grid_printer_bronze" or class == "grid_printer_silver" or class == "grid_printer_diamond" then
        local temp = ent.GetTemperature and ent:GetTemperature() or 20
        if temp > 35 then
            GRID.Notify(ply, string.format("Printer is too hot to pocket (%d°C)! Allow it to cool below 35°C.", temp),
                NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        if ply.HasDebuff and ply:HasDebuff("wanted") then
            GRID.Notify(ply, "Cannot pocket contraband while wanted by police!", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end
        if ent.DisconnectFromSwitch then ent:DisconnectFromSwitch() end
        local itemData = {
            storedCash = ent:GetStoredCash() or 0,
            hasUndervolt = ent.GetHasUndervolt and ent:GetHasUndervolt() or false
        }

        local storeClass = class
        local added = GRID.Database.AddInventoryItem(ply:SteamID(), storeClass, "printer", 1, itemData)
        if not added then
            GRID.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        ent:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 65, 100)
        local def = GRID.Inventory.GetItemData(storeClass)
        GRID.Notify(ply, "Stored " .. def.name .. " into your bag.", NOTIFY_GENERIC)
        if ent.HumSound then ent.HumSound:Stop() end
        timer.Remove("GRID_PrintTick_" .. ent:EntIndex())
        ent:Remove()
        GRID.Inventory.Sync(ply)
        return true
    end

    -- 3.5 Network Switch Appliance
    if class == "grid_network_switch_4p" or class == "grid_network_switch_7p" or ent.IsNetworkSwitch then
        if ent.DisconnectAll then ent:DisconnectAll() end
        local storeClass = class
        local added = GRID.Database.AddInventoryItem(ply:SteamID(), storeClass, "switch", 1, {})
        if not added then
            GRID.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        ent:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 65, 100)
        local def = GRID.Inventory.GetItemData(storeClass)
        GRID.Notify(ply, "Stored " .. (def and def.name or "L3 Network Switch") .. " into your bag.", NOTIFY_GENERIC)
        ent:Remove()
        GRID.Inventory.Sync(ply)
        return true
    end

    -- 3.55 Satellite WAN Uplink Gateway
    if class == "grid_wan_uplink" then
        if ent.DisconnectFromSwitch then ent:DisconnectFromSwitch() end
        local storeClass = "grid_wan_uplink"
        local added = GRID.Database.AddInventoryItem(ply:SteamID(), storeClass, "uplink", 1, {})
        if not added then
            GRID.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        ent:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 65, 100)
        local def = GRID.Inventory.GetItemData(storeClass)
        GRID.Notify(ply, "Stored " .. (def and def.name or "Satellite WAN Uplink") .. " into your bag.", NOTIFY_GENERIC)
        ent:Remove()
        GRID.Inventory.Sync(ply)
        return true
    end

    -- 3.6 Hardware Upgrade Modules
    if class == "grid_module_undervolt" or class == "grid_module_overclock" then
        local storeClass = class
        local added = GRID.Database.AddInventoryItem(ply:SteamID(), storeClass, "module", 1, {})
        if not added then
            GRID.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        ent:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 65, 100)
        local def = GRID.Inventory.GetItemData(storeClass)
        GRID.Notify(ply, "Stored " .. (def and def.name or "Hardware Module") .. " into your bag.", NOTIFY_GENERIC)
        ent:Remove()
        GRID.Inventory.Sync(ply)
        return true
    end

    -- 4. Wholesale Weapon Shipments
    if class == "grid_shipment" then
        GRID.Notify(ply, "Weapon shipments are world-bound retail kiosks and cannot be stored in bags!", NOTIFY_ERROR)
        ply:EmitSound("common/warning.wav", 65, 100)
        return false
    end

    -- 5. Crafting Ingot, Carbon Rod & Blueprint Material Props
    if class == "grid_crafting_material" then
        if GRID.Crafting and GRID.Crafting.PickupMaterial then
            return GRID.Crafting.PickupMaterial(ply, ent)
        end
        return false
    end

    -- 6. Resource Fabricator Machine
    if class == "grid_resource_machine" then
        local owner = ent.GetOwnerPlayer and ent:GetOwnerPlayer()
        if IsValid(owner) and owner ~= ply and not ply:IsAdmin() then
            GRID.Notify(ply, "Only the owner can pack up this Resource Fabricator!", NOTIFY_ERROR)
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

        local storeClass = "grid_resource_machine"
        local added = GRID.Database.AddInventoryItem(ply:SteamID(), storeClass, "entity", 1, {})
        if not added then
            GRID.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return false
        end

        ent:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 65, 100)
        local def = GRID.Inventory.GetItemData(storeClass)
        GRID.Notify(ply, "Packed " .. (def and def.name or "Resource Fabricator") .. " into your bag.", NOTIFY_GENERIC)
        ent:Remove()
        GRID.Inventory.Sync(ply)
        return true
    end

    return false
end

-- ========================================================
-- SLOT MOVEMENT & DRAG-AND-DROP HANDLER
-- ========================================================

local function HandleMoveInventorySlot(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "inv_move", 6) then return end

    local fromBag = net.ReadUInt(8)
    local fromSlot = net.ReadUInt(8)
    local toBag = net.ReadUInt(8)
    local toSlot = net.ReadUInt(8)
    local steamID = ply:SteamID()

    local success = GRID.Database.MoveInventorySlot(steamID, fromBag, fromSlot, toBag, toSlot)
    if success then
        ply:EmitSound("weapons/weapon_drop.wav", 55, 110)
        GRID.Inventory.Sync(ply)
    end
end

net.Receive("GRID_MoveInventorySlot", HandleMoveInventorySlot)

-- ========================================================
-- DROP FROM SPECIFIC SLOT
-- ========================================================

local function HandleDropInventorySlot(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "inv_drop", 4) then return end

    local bagIndex = net.ReadUInt(8)
    local slotIndex = net.ReadUInt(8)
    local steamID = ply:SteamID()

    local targetRow = GRID.Database.GetInventorySlot(steamID, bagIndex, slotIndex)
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
            spawnedEnt.GRID_Dropped = true
            spawnedEnt.GRID_DurabilityInitialized = true
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:Spawn()
            spawnedEnt:Activate()
            if spawnedEnt.SetDurability and rawData.durability ~= nil then
                spawnedEnt:SetDurability(tonumber(rawData.durability) or 100)
            end
            if rawData.clip1 then spawnedEnt:SetClip1(rawData.clip1) end
            if rawData.clip2 then spawnedEnt:SetClip2(rawData.clip2) end
        end
    elseif itemType == "printer" or itemType == "switch" or itemId == "grid_resource_machine" then
        if itemType == "printer" then
            local maxPrinters = (GRID.Config and GRID.Config.MaxPrintersPerPlayer) or 4
            local curPrinters = 0
            for _, p in ipairs(ents.GetAll()) do
                local pc = p:GetClass()
                if string.StartWith(pc, "grid_printer_") and ((p.GetOwnerPlayer and p:GetOwnerPlayer() == ply) or p.OwnerPlayer == ply or p.GRID_Owner == ply) then
                    curPrinters = curPrinters + 1
                end
            end
            if curPrinters >= maxPrinters then
                GRID.Notify(ply,
                    string.format("Cannot deploy: you have reached the maximum allowed active printers (%d/%d)!",
                        curPrinters, maxPrinters), NOTIFY_ERROR)
                return
            end
        end
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
        spawnedEnt = ents.Create("grid_crafting_material")
        if IsValid(spawnedEnt) then
            spawnedEnt:SetMaterialID(itemId)
            spawnedEnt:SetAmount(1)
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:Spawn()
            spawnedEnt:Activate()
        end
    elseif itemType == "shipment" then
        spawnedEnt = ents.Create("grid_shipment")
        if IsValid(spawnedEnt) then
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:SetAngles(Angle(0, ply:EyeAngles().y, 0))
            spawnedEnt:SetWeaponClass(rawData.weaponClass or "weapon_grid_glock")
            spawnedEnt:SetWeaponName(rawData.weaponName or "Weapons")
            spawnedEnt:SetCount(rawData.count or 10)
            spawnedEnt:Spawn()
            spawnedEnt:Activate()
        end
    elseif itemType == "bag" then
        -- Bag drop: drops as physical suitcase/satchel
        spawnedEnt = ents.Create("prop_physics")
        if IsValid(spawnedEnt) then
            local def = GRID.Inventory.GetItemData(itemId)
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

        GRID.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, 1)
        local def = GRID.Inventory.GetItemData(itemId)
        GRID.Notify(ply, "Dropped " .. def.name .. " onto the ground.", NOTIFY_GENERIC)
        GRID.Inventory.Sync(ply)
    end
end

net.Receive("GRID_DropInventorySlot", HandleDropInventorySlot)

-- ========================================================
-- USE / EQUIP FROM SPECIFIC SLOT
-- ========================================================

local function HandleUseInventorySlot(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "inv_use", 4) then return end

    local bagIndex = net.ReadUInt(8)
    local slotIndex = net.ReadUInt(8)
    local steamID = ply:SteamID()

    local targetRow = GRID.Database.GetInventorySlot(steamID, bagIndex, slotIndex)
    if not targetRow then return end

    local itemId = targetRow.item_id
    local itemType = targetRow.item_type
    local def = GRID.Inventory.GetItemData(itemId)

    local reqLevel = (def and def.level) or 1
    if ply:GetLevel() < reqLevel then
        GRID.Notify(ply, string.format("You must be Level %d to use/equip %s!", reqLevel, def and def.name or itemId),
            NOTIFY_ERROR)
        return
    end

    if itemType == "weapon" then
        -- Hobo Restriction: Hobos can only use building tools
        local allowed = GRID.HoboAllowedWeapons and GRID.HoboAllowedWeapons[itemId]
        if ply:GetJob() == "hobo" and not allowed then
            GRID.Notify(ply, "Hobos can only use building tools and hands!", NOTIFY_ERROR)
            return
        end

        if ply:HasWeapon(itemId) then
            GRID.Notify(ply, "You already have this weapon equipped!", NOTIFY_ERROR)
            return
        end

        local rawData = util.JSONToTable(targetRow.item_data or "{}") or {}
        ply:Give(itemId)
        ply:SelectWeapon(itemId)
        local givenWep = ply:GetWeapon(itemId)
        if IsValid(givenWep) then
            givenWep.GRID_DurabilityInitialized = true
            if givenWep.SetDurability and rawData.durability ~= nil then
                givenWep:SetDurability(tonumber(rawData.durability) or 100)
            end
            if rawData.clip1 and rawData.clip1 >= 0 then
                givenWep:SetClip1(rawData.clip1)
            end
            if rawData.clip2 and rawData.clip2 >= 0 then
                givenWep:SetClip2(rawData.clip2)
            end
        end
        ply:EmitSound("items/ammo_pickup.wav", 65, 100)

        GRID.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, 1)
        GRID.Notify(ply, "Equipped " .. def.name .. ".", NOTIFY_GENERIC)
        GRID.Inventory.Sync(ply)
    elseif itemType == "bag" then
        -- Equip into first free bag slot 1..4
        local bags = GRID.Database.GetPlayerBags(steamID)
        local equippedSlot = nil
        for i = 1, 4 do
            if not bags["bag" .. i] or bags["bag" .. i] == "" then
                equippedSlot = i
                break
            end
        end

        if not equippedSlot then
            GRID.Notify(ply, "All 4 bag expansion slots are full!", NOTIFY_ERROR)
            return
        end

        bags["bag" .. equippedSlot] = itemId
        GRID.Database.SetPlayerBags(steamID, bags.bag1, bags.bag2, bags.bag3, bags.bag4)
        GRID.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, 1)

        ply:EmitSound("items/ammocrate_open.wav", 65, 100)
        GRID.Notify(ply, "Equipped " .. def.name .. " into Bag Slot " .. equippedSlot .. "!", NOTIFY_GENERIC)
        GRID.Inventory.Sync(ply)
    elseif itemType == "consumable" then
        if def.buffId then
            ply:AddBuff(def.buffId, def.buffDuration)
            ply:EmitSound("npc/barnacle/barnacle_gulp1.wav", 65, 110)
            GRID.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, 1)
            GRID.Notify(ply, "Consumed " .. def.name .. "!", NOTIFY_GENERIC)
            GRID.Inventory.Sync(ply)
        end
    elseif itemType == "printer" or itemType == "shipment" or itemType == "switch" or itemType == "module" then
        if itemType == "printer" then
            local maxPrinters = (GRID.Config and GRID.Config.MaxPrintersPerPlayer) or 4
            local curPrinters = 0
            for _, p in ipairs(ents.GetAll()) do
                local pc = p:GetClass()
                if string.StartWith(pc, "grid_printer_") and ((p.GetOwnerPlayer and p:GetOwnerPlayer() == ply) or p.OwnerPlayer == ply or p.GRID_Owner == ply) then
                    curPrinters = curPrinters + 1
                end
            end
            if curPrinters >= maxPrinters then
                GRID.Notify(ply,
                    string.format("Cannot deploy: you have reached the maximum allowed active printers (%d/%d)!",
                        curPrinters, maxPrinters), NOTIFY_ERROR)
                return
            end
        end
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
                spawnedEnt:SetWeaponClass(rawData.weaponClass or "weapon_grid_glock")
                spawnedEnt:SetWeaponName(rawData.weaponName or "Weapons")
                spawnedEnt:SetCount(rawData.count or 10)
            end

            GRID.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, 1)
            GRID.Notify(ply, "Deployed " .. def.name .. ".", NOTIFY_GENERIC)
            GRID.Inventory.Sync(ply)
        end
    end
end

net.Receive("GRID_UseInventorySlot", HandleUseInventorySlot)

-- ========================================================
-- LEGACY FALLBACK HANDLERS
-- ========================================================

local function HandleDropInventoryItem(len, ply)
    local rowId = net.ReadUInt(32)
    local steamID = ply:SteamID()
    local rows = GRID.Database.GetInventory(steamID) or {}
    for _, r in ipairs(rows) do
        if tonumber(r.id) == rowId then
            local bag = tonumber(r.bag_index) or 0
            local slot = tonumber(r.slot_index) or 1
            GRID.Database.RemoveInventoryItemAtSlot(steamID, bag, slot, 1)
            GRID.Inventory.Sync(ply)
            break
        end
    end
end

net.Receive("GRID_DropInventoryItem", HandleDropInventoryItem)

local function HandleUseInventoryItem(len, ply)
    local rowId = net.ReadUInt(32)
    local steamID = ply:SteamID()
    local rows = GRID.Database.GetInventory(steamID) or {}
    for _, r in ipairs(rows) do
        if tonumber(r.id) == rowId then
            local itemId = r.item_id
            if r.item_type == "weapon" then
                local allowed = GRID.HoboAllowedWeapons and GRID.HoboAllowedWeapons[itemId]
                if ply:GetJob() == "hobo" and not allowed then
                    GRID.Notify(ply, "Hobos can only use building tools and hands!", NOTIFY_ERROR)
                    return
                end
                if not ply:HasWeapon(itemId) then
                    local rawData = util.JSONToTable(r.item_data or "{}") or {}
                    ply:Give(itemId)
                    ply:SelectWeapon(itemId)
                    local givenWep = ply:GetWeapon(itemId)
                    if IsValid(givenWep) then
                        givenWep.GRID_DurabilityInitialized = true
                        if givenWep.SetDurability and rawData.durability ~= nil then
                            givenWep:SetDurability(tonumber(rawData.durability) or 100)
                        end
                        if rawData.clip1 and rawData.clip1 >= 0 then
                            givenWep:SetClip1(rawData.clip1)
                        end
                        if rawData.clip2 and rawData.clip2 >= 0 then
                            givenWep:SetClip2(rawData.clip2)
                        end
                    end
                    GRID.Database.RemoveInventoryItemAtSlot(steamID, tonumber(r.bag_index) or 0,
                        tonumber(r.slot_index) or 1, 1)
                    GRID.Inventory.Sync(ply)
                end
            end
            break
        end
    end
end

net.Receive("GRID_UseInventoryItem", HandleUseInventoryItem)

-- Server Chat Command Handler for /inv, /inventory
hook.Add("PlayerSay", "GRID_InventoryChatCommands", function(ply, text)
    local lower = string.lower(string.Trim(text))
    if lower == "/inv" or lower == "!inv" or lower == "/inventory" or lower == "!inventory" or lower == "/bag" or lower == "!bag" then
        ply:ConCommand("inventory")
        return ""
    end
end)

-- ========================================================
-- DIRECT WORLD ITEM PICKUP (+USE / E KEY)
-- ========================================================
hook.Add("KeyPress", "GRID_WeaponPickupUse", function(ply, key)
    if key ~= IN_USE then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local tr = util.TraceLine({
        start = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * 95,
        filter = ply
    })

    local ent = tr.Entity
    if IsValid(ent) and ent:IsWeapon() then
        GRID.Inventory.PickupEntity(ply, ent)
    end
end)

-- Chat commands to drop currently active weapon (/dropweapon, /dropgun, /drop)
hook.Add("PlayerSay", "GRID_DropWeaponChatCommands", function(ply, text)
    local lower = string.lower(string.Trim(text))
    if lower == "/dropweapon" or lower == "!dropweapon" or lower == "/dropgun" or lower == "!dropgun" or lower == "/drop" or lower == "!drop" then
        if not IsValid(ply) or not ply:Alive() then return "" end

        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) then
            GRID.Notify(ply, "You are not holding a weapon to drop!", NOTIFY_ERROR)
            return ""
        end

        local class = wep:GetClass()
        if class == "weapon_grid_keys" or class == "weapon_physcannon" or class == "weapon_physgun" or class == "weapon_fists" or class == "fists" or class == "gmod_tool" then
            GRID.Notify(ply, "You cannot drop standard utility gear!", NOTIFY_ERROR)
            return ""
        end

        if hook.Run("PlayerCanDropWeapon", ply, wep) == false or wep.GRID_IsStarterItem then
            return ""
        end

        local clip1 = wep:Clip1()
        local clip2 = wep:Clip2()
        local dur = (wep.GetDurability and wep:GetDurability()) or 100

        local tr = ply:GetEyeTrace()
        local spawnPos = ply:GetShootPos() + ply:GetAimVector() * 45
        if tr.Hit and tr.HitPos:DistToSqr(ply:GetShootPos()) < (45 * 45) then
            spawnPos = tr.HitPos + tr.HitNormal * 10
        end

        local spawnedEnt = ents.Create(class)
        if IsValid(spawnedEnt) then
            spawnedEnt.GRID_Dropped = true
            spawnedEnt.GRID_DurabilityInitialized = true
            spawnedEnt:SetPos(spawnPos)
            spawnedEnt:Spawn()
            spawnedEnt:Activate()
            if spawnedEnt.SetDurability then
                spawnedEnt:SetDurability(dur)
            end
            if clip1 and clip1 >= 0 then spawnedEnt:SetClip1(clip1) end
            if clip2 and clip2 >= 0 then spawnedEnt:SetClip2(clip2) end

            local phys = spawnedEnt:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetVelocity(ply:GetAimVector() * 80 + Vector(0, 0, 40))
            end
            spawnedEnt:EmitSound("weapons/weapon_drop.wav", 65, 100)
        end

        ply:StripWeapon(class)
        local def = GRID.Inventory and GRID.Inventory.GetItemData and GRID.Inventory.GetItemData(class)
        GRID.Notify(ply, "Dropped " .. (def and def.name or class) .. " onto the ground.", NOTIFY_GENERIC)
        return ""
    end
end)
