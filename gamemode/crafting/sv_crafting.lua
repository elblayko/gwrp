--[[
    sv_crafting.lua - Server Crafting Validation, Ingredient Deduction & Execution
    Author: Toxic & Antigravity
--]]

GW = GW or {}
GW.Crafting = GW.Crafting or {}

-- ========================================================
-- 1. MATERIAL PICKUP HANDLER
-- ========================================================

function GW.Crafting.PickupMaterial(ply, matEnt)
    if not IsValid(ply) or not ply:Alive() or not IsValid(matEnt) then return false end

    -- Verify proximity (within 130 Source units)
    if matEnt:GetPos():DistToSqr(ply:EyePos()) > (130 * 130) then
        return false
    end

    local matId = matEnt.GetMaterialID and matEnt:GetMaterialID() or "crafting_ingot_zinc"
    local amount = matEnt.GetAmount and matEnt:GetAmount() or 1
    if amount <= 0 then amount = 1 end

    local iType = string.StartWith(matId, "blueprint_") and "blueprint" or "material"
    local added = GW.Database.AddInventoryItem(ply:SteamID(), matId, iType, amount, {})
    if not added then
        GW.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
        ply:EmitSound("common/warning.wav", 65, 100)
        return false
    end

    matEnt:EmitSound("items/itempickup.wav", 65, 100)
    local def = GW.Crafting.Materials[matId] or (GW.Inventory.GetItemData and GW.Inventory.GetItemData(matId))
    local itemName = def and def.name or matId
    GW.Notify(ply, string.format("Pocketed %dx %s into your bag.", amount, itemName), NOTIFY_GENERIC)

    -- Notify parent machine that resource was harvested
    if IsValid(matEnt.ParentMachine) then
        matEnt.ParentMachine:OnMaterialTaken(matEnt)
    end

    matEnt:Remove()
    GW.Inventory.Sync(ply)
    return true
end

-- ========================================================
-- 2. INVENTORY INGREDIENT DEDUCTION ENGINE
-- ========================================================

function GW.Crafting.GetPlayerMaterialCount(steamID, itemId)
    local rows = GW.Database.GetInventory(steamID) or {}
    local total = 0
    for _, row in ipairs(rows) do
        if row.item_id == itemId then
            total = total + (tonumber(row.amount) or 1)
        end
    end
    return total
end

function GW.Crafting.DeductMaterial(steamID, itemId, totalAmount)
    local needed = totalAmount
    while needed > 0 do
        local rows = GW.Database.Call("GET_INVENTORY_ITEM", { steamID, itemId })
        if not rows or not rows[1] then break end
        local row = rows[1]
        local rowId = tonumber(row.id)
        local curAmt = tonumber(row.amount) or 1

        if curAmt <= needed then
            GW.Database.Call("DELETE_INVENTORY_ITEM", { rowId })
            needed = needed - curAmt
        else
            GW.Database.Call("DECREMENT_INVENTORY_ITEM", { needed, rowId })
            needed = 0
        end
    end
    return needed == 0
end

-- ========================================================
-- 3. CRAFTING REQUEST NETWORK HANDLER
-- ========================================================

net.Receive("GW_CraftItem", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GW.CheckRateLimit(ply, "craft_item", 3) then return end

    local machine = net.ReadEntity()
    local recipeId = net.ReadString()

    if not IsValid(machine) or machine:GetClass() ~= "gw_resource_machine" then
        GW.Notify(ply, "Invalid Resource Fabricator!", NOTIFY_ERROR)
        return
    end

    if machine:GetPos():DistToSqr(ply:GetPos()) > (140 * 140) then
        GW.Notify(ply, "You are too far from the Resource Fabricator!", NOTIFY_ERROR)
        return
    end

    local recipe = GW.Crafting.GetRecipe(recipeId)
    if not recipe then
        GW.Notify(ply, "Unknown crafting recipe!", NOTIFY_ERROR)
        return
    end

    local steamID = ply:SteamID()

    -- 1. Verify player has all ingredients
    for _, ing in ipairs(recipe.ingredients) do
        local have = GW.Crafting.GetPlayerMaterialCount(steamID, ing.id)
        if have < ing.amount then
            local matDef = GW.Crafting.Materials[ing.id] or (GW.Inventory.GetItemData and GW.Inventory.GetItemData(ing.id))
            local matName = matDef and matDef.name or ing.name or ing.id
            GW.Notify(ply, string.format("Missing materials: %s (%d/%d required)!", matName, have, ing.amount), NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return
        end
    end

    -- 2. Deduct materials
    for _, ing in ipairs(recipe.ingredients) do
        GW.Crafting.DeductMaterial(steamID, ing.id, ing.amount)
    end

    -- 3. Grant crafted item
    local rType = recipe.resultType
    local rId = recipe.resultId

    if rType == "weapon" then
        local def = GW.Inventory.GetItemData(rId)
        local reqLevel = (def and def.level) or 1

        local added = GW.Database.AddInventoryItem(steamID, rId, "weapon", 1, {})
        if not added then
            if ply:GetLevel() >= reqLevel and not ply:HasWeapon(rId) then
                ply:Give(rId)
                ply:SelectWeapon(rId)
                GW.Notify(ply, "Bags full! Equipped " .. recipe.name .. " directly.", NOTIFY_GENERIC)
            else
                -- Spawn weapon on ground
                local tr = ply:GetEyeTrace()
                local dropPos = ply:GetShootPos() + ply:GetAimVector() * 35
                local dropWep = ents.Create(rId)
                if IsValid(dropWep) then
                    dropWep:SetPos(dropPos)
                    dropWep:Spawn()
                    dropWep:Activate()
                end
                GW.Notify(ply, "Bags full! Dropped " .. recipe.name .. " onto the ground.", NOTIFY_HINT)
            end
        else
            GW.Notify(ply, "Crafted " .. recipe.name .. " into your bag!", NOTIFY_GENERIC)
        end

    elseif rType == "bag" then
        local added = GW.Database.AddInventoryItem(steamID, rId, "bag", 1, {})
        if not added then
            local dropBag = ents.Create("prop_physics")
            if IsValid(dropBag) then
                dropBag:SetModel(recipe.model or "models/props_c17/Suitcase001a.mdl")
                dropBag:SetPos(ply:GetShootPos() + ply:GetAimVector() * 35)
                dropBag:Spawn()
                dropBag:Activate()
            end
            GW.Notify(ply, "Bags full! Dropped " .. recipe.name .. " onto the ground.", NOTIFY_HINT)
        else
            GW.Notify(ply, "Crafted " .. recipe.name .. " into your bag!", NOTIFY_GENERIC)
        end

    elseif rType == "consumable" then
        local added = GW.Database.AddInventoryItem(steamID, rId, "consumable", 1, {})
        if not added then
            GW.Notify(ply, "Bags full! Unable to store " .. recipe.name .. ".", NOTIFY_ERROR)
        else
            GW.Notify(ply, "Crafted " .. recipe.name .. " into your bag!", NOTIFY_GENERIC)
        end

    elseif rType == "ammo" then
        ply:GiveAmmo(90, "Pistol", true)
        ply:GiveAmmo(120, "AR2", true)
        ply:GiveAmmo(32, "Buckshot", true)
        ply:GiveAmmo(28, "357", true)
        GW.Notify(ply, "Crafted Universal Ammo Pack (Restored all standard ammo)!", NOTIFY_GENERIC)
    end

    -- Visual & sound effects on machine
    machine:EmitSound("ambient/machines/thumper_dust.wav", 75, 115)
    machine:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 70, 100)

    local ed = EffectData()
    ed:SetOrigin(machine:GetPos() + Vector(0, 0, 30))
    ed:SetNormal(machine:GetUp())
    ed:SetScale(1.5)
    util.Effect("ElectricSpark", ed, true, true)

    GW.Inventory.Sync(ply)
end)

-- Quick Collect button from UI
net.Receive("GW_CollectMachineResource", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local machine = net.ReadEntity()

    if not IsValid(machine) or machine:GetClass() ~= "gw_resource_machine" then return end
    if machine:GetPos():DistToSqr(ply:GetPos()) > (140 * 140) then return end

    if IsValid(machine.CurrentItem) then
        GW.Crafting.PickupMaterial(ply, machine.CurrentItem)
    end
end)

-- Debug verification concommand: gw_test_drops <count>
concommand.Add("gw_test_drops", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then return end

    local count = math.Clamp(tonumber(args[1]) or 1000, 10, 50000)
    local results = {}

    for i = 1, count do
        local id = GW.Crafting.RollRandomResource()
        results[id] = (results[id] or 0) + 1
    end

    local out = string.format("\n[GWRP Crafting] Simulated %d extraction rolls:\n", count)
    for id, cnt in pairs(results) do
        local pct = (cnt / count) * 100
        local def = GW.Crafting.Materials[id]
        local name = def and def.name or id
        out = out .. string.format("  %-28s: %5d  (%5.1f%%)\n", name, cnt, pct)
    end

    if IsValid(ply) then
        ply:ChatPrint(out)
    else
        print(out)
    end
end)
