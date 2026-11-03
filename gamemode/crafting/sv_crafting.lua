--[[
    sv_crafting.lua - Server Crafting Validation, Ingredient Deduction & Execution
    Author: Toxic & Antigravity
--]]

GWRP = GWRP or {}
GWRP.Crafting = GWRP.Crafting or {}

-- ========================================================
-- 1. MATERIAL PICKUP HANDLER
-- ========================================================

function GWRP.Crafting.PickupMaterial(ply, matEnt)
    if not IsValid(ply) or not ply:Alive() or not IsValid(matEnt) then return false end

    -- Verify proximity (within 130 Source units)
    if matEnt:GetPos():DistToSqr(ply:EyePos()) > (130 * 130) then
        return false
    end

    local matId = matEnt.GetMaterialID and matEnt:GetMaterialID() or "crafting_ingot_zinc"
    local amount = matEnt.GetAmount and matEnt:GetAmount() or 1
    if amount <= 0 then amount = 1 end

    local iType = string.StartWith(matId, "blueprint_") and "blueprint" or "material"
    local added = GWRP.Database.AddInventoryItem(ply:SteamID(), matId, iType, amount, {})
    if not added then
        GWRP.Notify(ply, "Your bags are full! Equip extra bags or drop items.", NOTIFY_ERROR)
        ply:EmitSound("common/warning.wav", 65, 100)
        return false
    end

    matEnt:EmitSound("items/itempickup.wav", 65, 100)
    local def = GWRP.Crafting.Materials[matId] or (GWRP.Inventory.GetItemData and GWRP.Inventory.GetItemData(matId))
    local itemName = def and def.name or matId
    GWRP.Notify(ply, string.format("Pocketed %dx %s into your bag.", amount, itemName), NOTIFY_GENERIC)

    -- Notify parent machine that resource was harvested
    if IsValid(matEnt.ParentMachine) then
        matEnt.ParentMachine:OnMaterialTaken(matEnt)
    end

    matEnt:Remove()
    GWRP.Inventory.Sync(ply)
    return true
end

-- ========================================================
-- 2. INVENTORY INGREDIENT DEDUCTION ENGINE
-- ========================================================

function GWRP.Crafting.GetPlayerMaterialCount(steamID, itemId)
    local rows = GWRP.Database.GetInventory(steamID) or {}
    local total = 0
    for _, row in ipairs(rows) do
        if row.item_id == itemId then
            total = total + (tonumber(row.amount) or 1)
        end
    end
    return total
end

function GWRP.Crafting.DeductMaterial(steamID, itemId, totalAmount)
    local needed = totalAmount
    while needed > 0 do
        local rows = GWRP.Database.Call("GET_INVENTORY_ITEM", { steamID, itemId })
        if not rows or not rows[1] then break end
        local row = rows[1]
        local rowId = tonumber(row.id)
        local curAmt = tonumber(row.amount) or 1

        if curAmt <= needed then
            GWRP.Database.Call("DELETE_INVENTORY_ITEM", { rowId })
            needed = needed - curAmt
        else
            GWRP.Database.Call("DECREMENT_INVENTORY_ITEM", { needed, rowId })
            needed = 0
        end
    end
    return needed == 0
end

-- ========================================================
-- 3. CRAFTING REQUEST NETWORK HANDLER
-- ========================================================

net.Receive("GWRP_CraftItem", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GWRP.CheckRateLimit(ply, "craft_item", 3) then return end

    local machine = net.ReadEntity()
    local recipeId = net.ReadString()

    if not IsValid(machine) or machine:GetClass() ~= "gwrp_resource_machine" then
        GWRP.Notify(ply, "Invalid Resource Fabricator!", NOTIFY_ERROR)
        return
    end

    if machine:GetPos():DistToSqr(ply:GetPos()) > (140 * 140) then
        GWRP.Notify(ply, "You are too far from the Resource Fabricator!", NOTIFY_ERROR)
        return
    end

    local recipe = GWRP.Crafting.GetRecipe(recipeId)
    if not recipe then
        GWRP.Notify(ply, "Unknown crafting recipe!", NOTIFY_ERROR)
        return
    end

    local steamID = ply:SteamID()

    -- 1. Verify player has all ingredients
    for _, ing in ipairs(recipe.ingredients) do
        local have = GWRP.Crafting.GetPlayerMaterialCount(steamID, ing.id)
        if have < ing.amount then
            local matDef = GWRP.Crafting.Materials[ing.id] or (GWRP.Inventory.GetItemData and GWRP.Inventory.GetItemData(ing.id))
            local matName = matDef and matDef.name or ing.name or ing.id
            GWRP.Notify(ply, string.format("Missing materials: %s (%d/%d required)!", matName, have, ing.amount), NOTIFY_ERROR)
            ply:EmitSound("common/warning.wav", 65, 100)
            return
        end
    end

    -- 2. Deduct materials
    for _, ing in ipairs(recipe.ingredients) do
        GWRP.Crafting.DeductMaterial(steamID, ing.id, ing.amount)
    end

    -- 3. Grant crafted item
    local rType = recipe.resultType
    local rId = recipe.resultId

    if rType == "weapon" then
        local def = GWRP.Inventory.GetItemData(rId)
        local reqLevel = (def and def.level) or 1

        local added = GWRP.Database.AddInventoryItem(steamID, rId, "weapon", 1, {})
        if not added then
            if ply:GetLevel() >= reqLevel and not ply:HasWeapon(rId) then
                ply:Give(rId)
                ply:SelectWeapon(rId)
                GWRP.Notify(ply, "Bags full! Equipped " .. recipe.name .. " directly.", NOTIFY_GENERIC)
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
                GWRP.Notify(ply, "Bags full! Dropped " .. recipe.name .. " onto the ground.", NOTIFY_HINT)
            end
        else
            GWRP.Notify(ply, "Crafted " .. recipe.name .. " into your bag!", NOTIFY_GENERIC)
        end

    elseif rType == "bag" then
        local added = GWRP.Database.AddInventoryItem(steamID, rId, "bag", 1, {})
        if not added then
            local dropBag = ents.Create("prop_physics")
            if IsValid(dropBag) then
                dropBag:SetModel(recipe.model or "models/props_c17/Suitcase001a.mdl")
                dropBag:SetPos(ply:GetShootPos() + ply:GetAimVector() * 35)
                dropBag:Spawn()
                dropBag:Activate()
            end
            GWRP.Notify(ply, "Bags full! Dropped " .. recipe.name .. " onto the ground.", NOTIFY_HINT)
        else
            GWRP.Notify(ply, "Crafted " .. recipe.name .. " into your bag!", NOTIFY_GENERIC)
        end

    elseif rType == "consumable" then
        local added = GWRP.Database.AddInventoryItem(steamID, rId, "consumable", 1, {})
        if not added then
            GWRP.Notify(ply, "Bags full! Unable to store " .. recipe.name .. ".", NOTIFY_ERROR)
        else
            GWRP.Notify(ply, "Crafted " .. recipe.name .. " into your bag!", NOTIFY_GENERIC)
        end

    elseif rType == "ammo" then
        ply:GiveAmmo(90, "Pistol", true)
        ply:GiveAmmo(120, "AR2", true)
        ply:GiveAmmo(32, "Buckshot", true)
        ply:GiveAmmo(28, "357", true)
        GWRP.Notify(ply, "Crafted Universal Ammo Pack (Restored all standard ammo)!", NOTIFY_GENERIC)
    end

    -- Visual & sound effects on machine
    machine:EmitSound("ambient/machines/thumper_dust.wav", 75, 115)
    machine:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 70, 100)

    local ed = EffectData()
    ed:SetOrigin(machine:GetPos() + Vector(0, 0, 30))
    ed:SetNormal(machine:GetUp())
    ed:SetScale(1.5)
    util.Effect("ElectricSpark", ed, true, true)

    GWRP.Inventory.Sync(ply)
end)

-- Quick Collect button from UI
net.Receive("GWRP_CollectMachineResource", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local machine = net.ReadEntity()

    if not IsValid(machine) or machine:GetClass() ~= "gwrp_resource_machine" then return end
    if machine:GetPos():DistToSqr(ply:GetPos()) > (140 * 140) then return end

    if IsValid(machine.CurrentItem) then
        GWRP.Crafting.PickupMaterial(ply, machine.CurrentItem)
    end
end)
