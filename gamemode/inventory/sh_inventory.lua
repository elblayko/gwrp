--[[
    sh_inventory.lua - Shared Item Definitions, Quality Tiers & Bag Capacities
    Author: Toxic
--]]

GW.Inventory = GW.Inventory or {}

-- Item Quality Tiers & Color Palette
GW.Inventory.Quality = {
    POOR = { id = 0, name = "Poor", color = Color(157, 157, 157) },
    COMMON = { id = 1, name = "Common", color = Color(248, 250, 252) },
    UNCOMMON = { id = 2, name = "Uncommon", color = Color(30, 255, 0) },
    RARE = { id = 3, name = "Rare", color = Color(0, 112, 221) },
    EPIC = { id = 4, name = "Epic", color = Color(163, 53, 238) },
    LEGENDARY = { id = 5, name = "Legendary", color = Color(255, 128, 0) }
}

function GW.Inventory.GetQualityColor(q)
    if type(q) == "table" and q.color then return q.color end
    if q == 0 or q == "poor" then return GW.Inventory.Quality.POOR.color end
    if q == 2 or q == "uncommon" then return GW.Inventory.Quality.UNCOMMON.color end
    if q == 3 or q == "rare" then return GW.Inventory.Quality.RARE.color end
    if q == 4 or q == "epic" then return GW.Inventory.Quality.EPIC.color end
    if q == 5 or q == "legendary" then return GW.Inventory.Quality.LEGENDARY.color end
    return GW.Inventory.Quality.COMMON.color
end

GW.Inventory.Items = {
    -- 1. Firearms & Weapons
    ["weapon_gw_glock"] = {
        name = "Glock-18",
        level = 1,
        type = "weapon",
        subType = "One-Hand Firearm",
        quality = 1, -- Common
        model = "models/weapons/w_pist_glock18.mdl",
        desc = "Standard semi-automatic sidearm.",
        stats = "Damage: 22 | Capacity: 17 rounds"
    },
    ["weapon_gw_deagle"] = {
        name = "Desert Eagle",
        level = 5,
        type = "weapon",
        subType = "Heavy Sidearm",
        quality = 2, -- Uncommon
        model = "models/weapons/w_pist_deagle.mdl",
        desc = "Heavy caliber .50 magnum pistol.",
        stats = "Damage: 45 | Heavy Armor Piercing"
    },
    ["weapon_gw_ak47"] = {
        name = "AK-47 Kalashnikov",
        level = 8,
        type = "weapon",
        subType = "Assault Rifle",
        quality = 3, -- Rare
        model = "models/weapons/w_rif_ak47.mdl",
        desc = "Full-auto gas-operated assault rifle.",
        stats = "Damage: 34 | Full-Auto 600 RPM"
    },
    ["weapon_gw_shotgun"] = {
        name = "SPAS-12 Shotgun",
        level = 3,
        type = "weapon",
        subType = "Combat Shotgun",
        quality = 3, -- Rare
        model = "models/weapons/w_shot_m3super90.mdl",
        desc = "Close-quarters combat pump shotgun.",
        stats = "Damage: 8x12 | Close Quarters Spread"
    },
    ["weapon_gw_lockpick"] = {
        name = "Tactical Lockpick",
        level = 2,
        type = "weapon",
        subType = "Infiltration Tool",
        quality = 2, -- Uncommon
        model = "models/weapons/w_crowbar.mdl",
        desc = "Tool used to infiltrate locked doors and structures.",
        stats = "Breaches locked doors in 8-15 seconds"
    },
    ["weapon_gw_medkit"] = {
        name = "Field Medical Kit",
        level = 1,
        type = "weapon",
        subType = "Field Supplies",
        quality = 1, -- Common
        model = "models/weapons/w_medkit.mdl",
        desc = "Used by medics to heal injuries in the field.",
        stats = "Restores up to +25 Health per treatment"
    },
    ["weapon_stunstick"] = {
        name = "Stunstick",
        level = 1,
        type = "weapon",
        subType = "Melee Weapon",
        quality = 1, -- Common
        model = "models/weapons/w_stunbaton.mdl",
        desc = "Electrified crowd control baton.",
        stats = "Non-lethal electrical stun shock"
    },
    ["weapon_gw_wiretool"] = {
        name = "Copper Wiring Tool",
        level = 1,
        type = "weapon",
        subType = "Networking Tool",
        quality = 2, -- Uncommon
        model = "models/weapons/w_toolgun.mdl",
        desc = "Connects money printers to network switches via copper cables.",
        stats = "Left-Click: Run Wire | Right-Click: Unplug"
    },
    ["weapon_gw_repairtool"] = {
        name = "Cryo-Thermal Calibrator",
        level = 2,
        type = "weapon",
        subType = "Engineering Hardware",
        quality = 2, -- Uncommon
        model = "models/weapons/w_slam.mdl",
        desc = "Handheld field calibrator. Cools overheating printers (-35°C), repairs integrity, and enables Cyber-Tuning.",
        stats = "Primary: Flash-Cool (-100% Heat) | Secondary: Cyber-Tuning"
    },
    ["weapon_gw_scanner"] = {
        name = "Contraband Scanner",
        level = 1,
        type = "weapon",
        subType = "Investigative Device",
        quality = 3, -- Rare
        model = "models/weapons/w_toolgun.mdl",
        desc = "Police acoustic & thermal scanner. Triangulates illegal money printers and broadcasts raid markers to dispatch.",
        stats = "Primary: Triangulate Signal | Secondary: Police Raid Dispatch"
    },
    ["weapon_gw_ram"] = {
        name = "Tactical Battering Ram",
        level = 4,
        type = "weapon",
        subType = "Breaching Device",
        quality = 3, -- Rare
        model = "models/weapons/w_rocket_launcher.mdl",
        desc = "Heavy SWAT kinetic ram used to smash open locked doors and fortified barricades.",
        stats = "Primary: Heavy Kinetic Door Impact | Secondary: Megaphone"
    },

    -- 2. Money Printers & Networking Appliances
    ["gw_network_switch"] = {
        name = "L3 Network Switch (2-Cu + 2-SFP)",
        type = "switch",
        subType = "Network Appliance",
        quality = 2, -- Uncommon
        model = "models/props_lab/reciever01a.mdl",
        desc = "Layer-3 hardware switch featuring 2 dedicated copper ports, Port 3 SFP combo (10G for switches/WAN or 1G for printers), and Port 4 10G SFP uplink.",
        stats = "2x Copper + 2x SFP (Combo + Uplink) | Layer-3 Switch"
    },
    ["gw_wan_uplink"] = {
        name = "Satellite WAN Uplink",
        type = "uplink",
        subType = "Wireless Gateway",
        quality = 3, -- Rare
        model = "models/props_rooftop/roof_dish001.mdl",
        desc = "Encrypted satellite transceiver dish. Plugs into an L3 switch (prefers Port 3 10G SFP) to establish long-range wireless mesh tunnels across the map.",
        stats = "Long-Range L3 Mesh | WPA3 Encrypted"
    },
    ["gw_module_undervolt"] = {
        name = "Undervolt Hardware Module",
        type = "module",
        subType = "Hardware Upgrade",
        quality = 3, -- Rare
        model = "models/items/battery.mdl",
        desc = "Microcontroller module that drops printer operating voltage.",
        stats = "+400% Lifespan | -75% Heat Output"
    },
    ["gw_module_overclock"] = {
        name = "Overclock Hardware Module",
        type = "module",
        subType = "Hardware Upgrade",
        quality = 4, -- Epic
        model = "models/items/car_battery01.mdl",
        desc = "High-frequency microcontroller that maximizes printer hashing yield.",
        stats = "+50% Cash Yield Rate | +60% Heat Output"
    },
    ["gw_printer_bronze"] = {
        name = "Money Printer",
        level = 1,
        type = "printer",
        subType = "Passive Fabricator",
        quality = 1, -- Common
        model = "models/props_c17/consolebox01a.mdl",
        desc = "Generates recurring cash revenue.",
        stats = "Yield: $150 / 60s | Max Temp: 100C"
    },
    ["gw_printer_silver"] = {
        name = "Silver Money Printer",
        level = 4,
        type = "printer",
        subType = "Commercial Fabricator",
        quality = 2, -- Uncommon
        model = "models/props_c17/consolebox01a.mdl",
        desc = "High efficiency commercial money printer.",
        stats = "Yield: $350 / 60s | Max Temp: 100C"
    },
    ["gw_printer_diamond"] = {
        name = "Diamond Money Printer",
        level = 8,
        type = "printer",
        subType = "Industrial Fabricator",
        quality = 3, -- Rare
        model = "models/props_c17/consolebox01a.mdl",
        desc = "Maximum throughput diamond money printer.",
        stats = "Yield: $750 / 60s | Max Temp: 100C"
    },

    -- 3. Shipments
    ["gw_shipment"] = {
        name = "Weapon Crate",
        type = "shipment",
        subType = "Wholesale Container",
        quality = 3, -- Rare
        model = "models/items/item_item_crate.mdl",
        desc = "Wholesale crate containing firearms.",
        stats = "Holds 10x bulk packaged firearms"
    },

    -- 4. Equipable Bag Containers
    ["gw_bag_small"] = {
        name = "Courier Satchel",
        type = "bag",
        subType = "Equipable Container",
        quality = 2, -- Uncommon
        capacity = 6,
        model = "models/props_c17/BriefCase001a.mdl",
        desc = "Compact leather satchel expanding inventory by 6 slots.",
        stats = "+6 Inventory Slots"
    },
    ["gw_bag_medium"] = {
        name = "Tactical Duffel Bag",
        type = "bag",
        subType = "Equipable Container",
        quality = 3, -- Rare
        capacity = 10,
        model = "models/props_c17/Suitcase001a.mdl",
        desc = "Reinforced duffel bag expanding inventory by 10 slots.",
        stats = "+10 Inventory Slots"
    },
    ["gw_bag_large"] = {
        name = "Military Rucksack",
        type = "bag",
        subType = "Equipable Container",
        quality = 4, -- Epic
        capacity = 16,
        model = "models/props_c17/Suitcase_Passenger_Physics.mdl",
        desc = "Heavy-duty tactical rucksack expanding inventory by 16 slots.",
        stats = "+16 Inventory Slots"
    },

    -- 5. Consumables (Buff / Debuff Triggers)
    ["consumable_bandage"] = {
        name = "First Aid Bandage",
        type = "consumable",
        subType = "Medical Supply",
        quality = 2, -- Uncommon
        buffId = "healing_over_time",
        buffDuration = 15,
        model = "models/props_lab/box01a.mdl",
        desc = "Sterile field bandage treating trauma. Applies Trauma Recovery for 15s.",
        stats = "+6 HP every 1.5s (15s duration)"
    },
    ["consumable_energy_drink"] = {
        name = "Nitro Energy Drink",
        type = "consumable",
        subType = "Tactical Stimulant",
        quality = 2, -- Uncommon
        buffId = "swiftness",
        buffDuration = 30,
        model = "models/props_junk/PopCan01a.mdl",
        desc = "Caffeinated combat stimulant. Grants Adrenaline Surge (+30% move speed).",
        stats = "+30% Move Speed (30s duration)"
    },
    ["consumable_armor_shard"] = {
        name = "Ceramic Trauma Plate",
        type = "consumable",
        subType = "Tactical Armor",
        quality = 3, -- Rare
        buffId = "fortitude",
        buffDuration = 600,
        model = "models/props_lab/reciever01b.mdl",
        desc = "Reinforced ceramic ballistic insert. Grants Reinforced Plating (+50 Max Health).",
        stats = "+50 Max Health (10m duration)"
    },
    ["consumable_detox_serum"] = {
        name = "Detox Antidote Serum",
        type = "consumable",
        subType = "Pharmaceutical Antidote",
        quality = 3, -- Rare
        buffId = "detox",
        buffDuration = 5,
        model = "models/props_lab/jar01a.mdl",
        desc = "High-grade pharmaceutical antidote that neutralizes poisons, bleeds, and speeds tissue regeneration.",
        stats = "Purges Poison & Cripples | +3 HP/s (5s)"
    },
    ["consumable_illegal_stim"] = {
        name = "Black Market Adrenaline Shot",
        type = "consumable",
        subType = "Underworld Stimulant",
        quality = 3, -- Rare
        buffId = "illegal_adrenaline",
        buffDuration = 20,
        model = "models/weapons/w_models/w_syringe.mdl",
        desc = "Illicit high-potency combat adrenaline injector. Maximizes speed and pain tolerance.",
        stats = "+40% Sprint Speed | 15% Damage Resist (20s)"
    }
}

function GW.Inventory.GetBagCapacity(bagId)
    if not bagId or bagId == "" then return 0 end
    local item = GW.Inventory.Items[bagId]
    if item and item.capacity then
        return item.capacity
    end
    return 0
end

function GW.Inventory.GetItemData(itemId)
    if GW.Inventory.Items[itemId] then
        local it = GW.Inventory.Items[itemId]
        it.level = it.level or 1
        return it
    end

    local wep = (weapons and (weapons.Get(itemId) or weapons.GetStored(itemId))) or nil
    if wep then
        local q = (wep.ItemQuality and GW.NormalizeQuality and GW.NormalizeQuality(wep.ItemQuality)) or 1
        return {
            name = wep.PrintName or itemId,
            level = wep.RequiredLevel or 1,
            type = "weapon",
            subType = "Firearm",
            quality = q,
            model = (wep.WorldModel and wep.WorldModel ~= "") and wep.WorldModel or "models/weapons/w_pist_glock18.mdl",
            desc = wep.Instructions or "Standard firearm.",
            stats = "Standard Issue Weapon"
        }
    end

    -- Dynamic Scripted Entity Resolution (Checks ENT.ItemQuality in shared.lua)
    local sent = (scripted_ents and (scripted_ents.Get(itemId) or scripted_ents.GetStored(itemId))) or nil
    if sent and sent.t then
        local q = (sent.t.ItemQuality and GW.NormalizeQuality and GW.NormalizeQuality(sent.t.ItemQuality)) or 1
        return {
            name = sent.t.PrintName or itemId,
            level = sent.t.RequiredLevel or 1,
            type = "entity",
            subType = sent.t.ItemSubType or "Deployable Machine",
            quality = q,
            model = sent.t.Model or (sent.t.WorldModel or "models/props_c17/consolebox01a.mdl"),
            desc = sent.t.Instructions or "Deployable game entity.",
            stats = sent.t.Stats or "Interactive Asset"
        }
    end

    -- Central Registry Fallback
    if GW.Config and GW.Config.EntityQualities and GW.Config.EntityQualities[itemId] then
        local cfg = GW.Config.EntityQualities[itemId]
        if cfg and cfg.quality then
            local q = (GW.NormalizeQuality and GW.NormalizeQuality(cfg.quality)) or 1
            return {
                name = itemId,
                type = "entity",
                subType = cfg.subType or "Deployable",
                quality = q,
                model = "models/props_junk/cardboard_box004a.mdl",
                desc = "Stored game entity.",
                stats = cfg.stats or "Interactive Asset"
            }
        end
    end

    return {
        name = itemId,
        type = "generic",
        subType = "Item",
        quality = 1,
        model = "models/props_junk/cardboard_box004a.mdl",
        desc = "Stored inventory item.",
        stats = "Stored Asset"
    }
end
