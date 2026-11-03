--[[
    sh_crafting.lua - Shared Crafting System, Material Registries, Tints & Recipes
    Author: Toxic & Antigravity
--]]

GWRP = GWRP or {}
GWRP.Crafting = GWRP.Crafting or {}

-- ========================================================
-- 1. MATERIAL DEFINITIONS & VISUAL COLOR PALETTES
-- ========================================================

GWRP.Crafting.Materials = {
    ["crafting_ingot_zinc"] = {
        name = "Zinc Ingot",
        type = "material",
        subType = "Refined Ingot",
        quality = 1, -- Common
        model = "models/gangwars/crafting/ingot.mdl",
        color = Color(180, 215, 230), -- Bluish-Silver tint
        hasTint = true,
        desc = "Refined zinc ingot with a distinct bluish-silver luster. Used in basic firearm and gear fabrication.",
        stats = "Refined Base Metal"
    },
    ["crafting_ingot_iron"] = {
        name = "Iron Ingot",
        type = "material",
        subType = "Structural Ingot",
        quality = 2, -- Uncommon
        model = "models/gangwars/crafting/ingot.mdl",
        color = Color(120, 120, 125), -- Dark Gunmetal / Raw Iron tint
        hasTint = true,
        desc = "Dense raw gunmetal iron ingot. Essential structural metal for sidearms, lockpicks, and tactical bags.",
        stats = "Mid-Tier Structural Metal"
    },
    ["crafting_ingot_steel"] = {
        name = "Steel Ingot",
        type = "material",
        subType = "Military Alloy Ingot",
        quality = 3, -- Rare
        model = "models/gangwars/crafting/ingot.mdl",
        color = Color(245, 250, 255), -- Bright Polished Chrome tint
        hasTint = true,
        desc = "High-carbon polished chrome steel alloy ingot. Required for military rifles, shotguns, and heavy trauma plates.",
        stats = "High-Grade Military Alloy"
    },
    ["crafting_carbon_rod"] = {
        name = "Carbon Rod",
        type = "material",
        subType = "Composite Component",
        quality = 4, -- Epic
        model = "models/gangwars/crafting/carbrod.mdl",
        color = Color(255, 255, 255), -- Default model texture, no tint
        hasTint = false,
        desc = "Ultra-dense advanced carbon composite rod. Exotic high-tier material harvested for advanced fabrication.",
        stats = "Exotic High-Tier Material"
    },

    -- Weapon Blueprints (Retain original technical blueprint model texture)
    ["blueprint_glock"] = {
        name = "Blueprint: Glock-18",
        type = "blueprint",
        subType = "Technical Schematic",
        quality = 2, -- Uncommon
        model = "models/gangwars/crafting/blup.mdl",
        color = Color(255, 255, 255),
        hasTint = false,
        weapon = "weapon_gwrp_glock",
        desc = "Technical engineering schematic detailing the Glock-18 firearm assembly.",
        stats = "Schematic: Glock-18"
    },
    ["blueprint_deagle"] = {
        name = "Blueprint: Desert Eagle",
        type = "blueprint",
        subType = "Technical Schematic",
        quality = 3, -- Rare
        model = "models/gangwars/crafting/blup.mdl",
        color = Color(255, 255, 255),
        hasTint = false,
        weapon = "weapon_gwrp_deagle",
        desc = "Technical schematic for calibrating .50 Action Express magnum components.",
        stats = "Schematic: Desert Eagle"
    },
    ["blueprint_shotgun"] = {
        name = "Blueprint: SPAS-12",
        type = "blueprint",
        subType = "Technical Schematic",
        quality = 3, -- Rare
        model = "models/gangwars/crafting/blup.mdl",
        color = Color(255, 255, 255),
        hasTint = false,
        weapon = "weapon_gwrp_shotgun",
        desc = "Technical schematic detailing the combat pump shotgun action assembly.",
        stats = "Schematic: SPAS-12"
    },
    ["blueprint_ak47"] = {
        name = "Blueprint: AK-47",
        type = "blueprint",
        subType = "Technical Schematic",
        quality = 4, -- Epic
        model = "models/gangwars/crafting/blup.mdl",
        color = Color(255, 255, 255),
        hasTint = false,
        weapon = "weapon_gwrp_ak47",
        desc = "Military schematic detailing gas-piston assembly for the Kalashnikov rifle.",
        stats = "Schematic: AK-47 Kalashnikov"
    }
}

-- Helper: Retrieve color tint for a material entity or item icon
function GWRP.Crafting.GetMaterialColor(matId)
    local def = GWRP.Crafting.Materials[matId]
    if def and def.hasTint and def.color then
        return def.color
    end
    return Color(255, 255, 255)
end

-- Merge into the central inventory item definitions
GWRP.Inventory = GWRP.Inventory or {}
GWRP.Inventory.Items = GWRP.Inventory.Items or {}
for id, data in pairs(GWRP.Crafting.Materials) do
    GWRP.Inventory.Items[id] = data
end

-- Add the machine itself to inventory items
GWRP.Inventory.Items["gwrp_resource_machine"] = {
    name = "Resource Fabricator",
    type = "entity",
    subType = "Automated Extractor",
    quality = 1, -- Common
    model = "models/props_c17/trappropeller_engine.mdl",
    desc = "Legal industrial extractor and crafting station. Generates ingots, blueprints, and carbon rods. Connects to L2 switch for accelerated throughput.",
    stats = "Legal Extractor & Workbench | Network Capable"
}

-- ========================================================
-- 2. RESOURCE FABRICATOR EXTRACTION LOOT TABLE
-- ========================================================

-- Extraction weights (Total = 100)
-- Zinc: 48% (Common Base) | Iron: 24% (Structural) | Steel: 12% (Military Alloy) | Blueprints: 10% | Carbon Rod: 6% (Exotic)
GWRP.Crafting.DropTable = {
    { id = "crafting_ingot_zinc",  weight = 48 },
    { id = "crafting_ingot_iron",  weight = 24 },
    { id = "crafting_ingot_steel", weight = 12 },
    {
        weight = 10,
        isBlueprintPool = true,
        blueprints = {
            "blueprint_glock",
            "blueprint_deagle",
            "blueprint_shotgun",
            "blueprint_ak47"
        }
    },
    { id = "crafting_carbon_rod",  weight = 6 }
}

function GWRP.Crafting.RollRandomResource()
    local totalWeight = 0
    for _, entry in ipairs(GWRP.Crafting.DropTable) do
        totalWeight = totalWeight + (entry.weight or 0)
    end
    if totalWeight <= 0 then return "crafting_ingot_zinc" end

    -- Use Source engine C++ float random generator (high entropy, uniformly distributed across [0, totalWeight))
    local roll = math.Rand(0, totalWeight)
    local cumulative = 0

    for _, entry in ipairs(GWRP.Crafting.DropTable) do
        cumulative = cumulative + entry.weight
        if roll <= cumulative then
            if entry.isBlueprintPool then
                local bpList = entry.blueprints
                local idx = math.Clamp(math.floor(math.Rand(1, #bpList + 1)), 1, #bpList)
                return bpList[idx]
            else
                return entry.id
            end
        end
    end

    return "crafting_ingot_zinc"
end

-- ========================================================
-- 3. CRAFTING RECIPES CATALOG
-- ========================================================

GWRP.Crafting.Recipes = {
    -- 1. FIREARMS (Requires weapon schematic blueprint + ingots)
    {
        id = "craft_glock",
        name = "Glock-18 Sidearm",
        category = "Weapons",
        resultType = "weapon",
        resultId = "weapon_gwrp_glock",
        quality = 1,
        model = "models/weapons/w_pist_glock18.mdl",
        desc = "Standard semi-automatic sidearm. Reliable 17-round capacity.",
        ingredients = {
            { id = "blueprint_glock", name = "Blueprint: Glock-18", amount = 1 },
            { id = "crafting_ingot_zinc", name = "Zinc Ingot", amount = 4 }
        }
    },
    {
        id = "craft_deagle",
        name = "Desert Eagle .50 AE",
        category = "Weapons",
        resultType = "weapon",
        resultId = "weapon_gwrp_deagle",
        quality = 2,
        model = "models/weapons/w_pist_deagle.mdl",
        desc = "Heavy caliber .50 magnum sidearm with heavy armor-piercing kinetic impact.",
        ingredients = {
            { id = "blueprint_deagle", name = "Blueprint: Desert Eagle", amount = 1 },
            { id = "crafting_ingot_iron", name = "Iron Ingot", amount = 4 },
            { id = "crafting_ingot_zinc", name = "Zinc Ingot", amount = 2 }
        }
    },
    {
        id = "craft_shotgun",
        name = "SPAS-12 Combat Shotgun",
        category = "Weapons",
        resultType = "weapon",
        resultId = "weapon_gwrp_shotgun",
        quality = 3,
        model = "models/weapons/w_shot_m3super90.mdl",
        desc = "Close-quarters combat pump shotgun delivering devastating buckshot spread.",
        ingredients = {
            { id = "blueprint_shotgun", name = "Blueprint: SPAS-12", amount = 1 },
            { id = "crafting_ingot_iron", name = "Iron Ingot", amount = 4 },
            { id = "crafting_ingot_steel", name = "Steel Ingot", amount = 2 }
        }
    },
    {
        id = "craft_ak47",
        name = "AK-47 Kalashnikov",
        category = "Weapons",
        resultType = "weapon",
        resultId = "weapon_gwrp_ak47",
        quality = 4,
        model = "models/weapons/w_rif_ak47.mdl",
        desc = "Full-auto gas-operated military assault rifle with high armor penetration.",
        ingredients = {
            { id = "blueprint_ak47", name = "Blueprint: AK-47", amount = 1 },
            { id = "crafting_ingot_steel", name = "Steel Ingot", amount = 5 },
            { id = "crafting_ingot_iron", name = "Iron Ingot", amount = 3 }
        }
    },

    -- 2. CONTAINERS & BAGS (Utility expansion; no blueprints required)
    {
        id = "craft_bag_small",
        name = "Courier Satchel",
        category = "Bags",
        resultType = "bag",
        resultId = "gwrp_bag_small",
        quality = 2,
        model = "models/props_c17/BriefCase001a.mdl",
        desc = "Compact leather satchel expanding personal inventory by +6 slots.",
        ingredients = {
            { id = "crafting_ingot_zinc", name = "Zinc Ingot", amount = 3 }
        }
    },
    {
        id = "craft_bag_medium",
        name = "Tactical Duffel Bag",
        category = "Bags",
        resultType = "bag",
        resultId = "gwrp_bag_medium",
        quality = 3,
        model = "models/props_c17/Suitcase001a.mdl",
        desc = "Reinforced tactical duffel expanding personal inventory by +10 slots.",
        ingredients = {
            { id = "crafting_ingot_iron", name = "Iron Ingot", amount = 4 }
        }
    },
    {
        id = "craft_bag_large",
        name = "Military Rucksack",
        category = "Bags",
        resultType = "bag",
        resultId = "gwrp_bag_large",
        quality = 4,
        model = "models/props_c17/Suitcase_Passenger_Physics.mdl",
        desc = "Heavy-duty tactical rucksack expanding personal inventory by +16 slots.",
        ingredients = {
            { id = "crafting_ingot_steel", name = "Steel Ingot", amount = 4 },
            { id = "crafting_ingot_iron", name = "Iron Ingot", amount = 2 }
        }
    },

    -- 3. UTILITY GEAR & TACTICAL SUPPLIES
    {
        id = "craft_lockpick",
        name = "Tactical Lockpick",
        category = "Gear",
        resultType = "weapon",
        resultId = "weapon_gwrp_lockpick",
        quality = 2,
        model = "models/weapons/w_crowbar.mdl",
        desc = "Mechanical lock bypass tool used to breach locked doors and security pins.",
        ingredients = {
            { id = "crafting_ingot_iron", name = "Iron Ingot", amount = 2 }
        }
    },
    {
        id = "craft_medkit",
        name = "Field Medical Kit",
        category = "Gear",
        resultType = "weapon",
        resultId = "weapon_gwrp_medkit",
        quality = 1,
        model = "models/weapons/w_medkit.mdl",
        desc = "Reusable clinical field pack restoring up to +25 Health per treatment.",
        ingredients = {
            { id = "crafting_ingot_zinc", name = "Zinc Ingot", amount = 2 }
        }
    },
    {
        id = "craft_armor_shard",
        name = "Ceramic Trauma Plate",
        category = "Gear",
        resultType = "consumable",
        resultId = "consumable_armor_shard",
        quality = 3,
        model = "models/props_lab/reciever01b.mdl",
        desc = "Reinforced ceramic ballistic plate granting +50 Max Health for 10 minutes.",
        ingredients = {
            { id = "crafting_ingot_steel", name = "Steel Ingot", amount = 3 }
        }
    },
    {
        id = "craft_ammo",
        name = "Universal Ammo Pack",
        category = "Gear",
        resultType = "ammo",
        resultId = "ammo_universal",
        quality = 1,
        model = "models/items/boxsrounds.mdl",
        desc = "Ammunition pack replenishing pistol, rifle, buckshot, and magnum rounds.",
        ingredients = {
            { id = "crafting_ingot_zinc", name = "Zinc Ingot", amount = 3 }
        }
    }
}

function GWRP.Crafting.GetRecipe(recipeId)
    for _, recipe in ipairs(GWRP.Crafting.Recipes) do
        if recipe.id == recipeId then
            return recipe
        end
    end
    return nil
end
