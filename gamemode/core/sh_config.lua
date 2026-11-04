--[[
    sh_config.lua - Gamemode Constants, Economy Items & Balancing
--]]

GW.Config = GW.Config or {}

-- Economy
GW.Config.StartingMoney = 250
GW.Config.PaydayInterval = 90    -- seconds between salary ticks
GW.Config.DropMoneyOnDeathMax = 75
GW.Config.GangCreationCost = 200 -- cost to register a new player gang

-- Respawn Times
GW.Config.DefaultRespawnTime = 30 -- Baseline respawn time for all players (seconds)
GW.Config.PoliceRespawnTime = 5   -- Rapid dispatch respawn for base police officer (seconds)

-- Turf Warfare
GW.Config.TurfCaptureRadius = 450   -- Hammer units
GW.Config.TurfCaptureTime = 15      -- seconds of holding uncontested to capture
GW.Config.TurfDividendInterval = 90 -- seconds between turf payouts
GW.Config.TurfDividendAmount = 25   -- cash given to each online gang member per owned turf
GW.Config.TurfCaptureReward = 40    -- instant cash reward to capturing player

-- Contraband Money Printers & Networking
GW.Config.MaxPrintersPerPlayer = 4
GW.Config.PoliceBountyPerPrinter = 125
GW.Config.PoliceBountyPerSwitch = 50
GW.Config.PoliceBountyPerModule = 25
GW.Config.EntityHUDViewDistance = 380 -- Shared max 3D2D HUD visibility distance for printers & synthesizers

-- Thermal Regulation & Undervolt Module
GW.Config.PrinterHeatRiseStandard = 4    -- +4C per cycle
GW.Config.PrinterHeatRiseUndervolted = 1 -- +1C per cycle (+400% lifespan)
GW.Config.ModuleUndervoltCost = 80

-- Network Switch & Efficiency Rates
GW.Config.SwitchMaxPorts = 3               -- 2 copper ports + Port 3 combo SFP (10G/1G) + Port 4 10G SFP uplink
GW.Config.MaxCableLength = 550             -- maximum length in hammer units before copper cable snaps
GW.Config.MaxFiberCableLength = 800        -- maximum length in hammer units for SFP fiber optic cable
GW.Config.WLANSniffMaxDistance = 2500      -- maximum distance in hammer units for airmon & computer WLAN traffic sniffing
GW.Config.PrinterStandaloneEfficiency = 60 -- 1 printer or unlinked = 60%
GW.Config.PrinterNetworkEfficiency2 = 80   -- 2 printers on switch = 80%
GW.Config.PrinterNetworkEfficiency3 = 100  -- 3 printers on switch = 100%

-- Cloud Botnet C2 Daemon (Personal Computer + Satellite WAN Uplink)
GW.Config.BotnetTickInterval = 20.0           -- Seconds between automated cloud attack payouts
GW.Config.BotnetBaseTrickle = 2               -- Minimum cash per tick when 0 printers are connected
GW.Config.BotnetPrinterYieldMultiplier = 0.50 -- Fraction of connected printers' base yield paid per tick (~1/3 = acts as a 4th printer)
GW.Config.BotnetMaxCountedPrinters = 24       -- Max printers on the broadcast domain that contribute hashpower
GW.Config.BotnetEngineerBonusMultiplier = 1.5 -- Payout multiplier when started by a Cyber Engineer (+25%)

-- Centralized Entity Quality Registry (Entities can also set ENT.ItemQuality in their shared.lua)
GW.Config.EntityQualities = {
    ["gw_printer_bronze"] = { quality = 1, subType = "Passive Fabricator", stats = "Yield: $12 / 60s" },
    ["gw_printer_silver"] = { quality = 2, subType = "Commercial Fabricator", stats = "Yield: $30 / 60s" },
    ["gw_printer_diamond"] = { quality = 3, subType = "Industrial Fabricator", stats = "Yield: $75 / 60s" },
    ["gw_network_switch"] = { quality = 2, subType = "Network Appliance", stats = "2x Cu + 2x SFP (10G/Cu Combo + 10G Uplink) | L3 Layer" },
    ["gw_computer"] = { quality = 3, subType = "Cyber Appliance", stats = "Layer-3 Terminal | Cloud Botnet C2" },
    ["gw_wan_uplink"] = { quality = 3, subType = "Wireless Gateway", stats = "Cloud Botnet Gateway | WPA3 L3 Mesh" },
    ["gw_module_undervolt"] = { quality = 3, subType = "Hardware Upgrade", stats = "+400% Lifespan | -75% Heat" },
    ["gw_shipment"] = { quality = 3, subType = "Wholesale Container", stats = "Holds 10x Packaged Firearms" },
    ["gw_resource_machine"] = { quality = 1, subType = "Automated Extractor", stats = "Extracts Metals & Blueprints | Network Capable" },

    -- Explicit Exclusions (Never have item quality)
    ["gw_flag_pole"] = false,
    ["gw_cash_stack"] = false
}

-- Door Pricing
GW.Config.DoorCost = 15

-- Leveling & Progression System (MMO Curve, Capped at Level 50)
GW.Config.Level = {
    MaxLevel = 50,
    StartLevel = 1,
    BaseXP = 250,
    Exponent = 1.65,
    CashRewardPerLevel = 500, -- Cash given upon leveling up ($500 * new level)

    -- Gameplay XP Rewards (Paychecks do NOT give XP)
    XP_PlayerKill = 50,
    XP_RivalGangKillBonus = 50,
    XP_TurfCapture = 150,
    XP_TurfHoldTick = 25,
    XP_PrinterCollect = 20,
}

function GW.GetRequiredXP(level)
    level = math.Clamp(tonumber(level) or 1, 1, GW.Config.Level.MaxLevel)
    if level >= GW.Config.Level.MaxLevel then
        return 0 -- Max level cap reached
    end
    -- MMO Curve: Floor(250 * level ^ 1.65)
    return math.floor(GW.Config.Level.BaseXP * (level ^ GW.Config.Level.Exponent))
end

-- F4 Shop Retail Surcharge & Markup Settings (200% - 300% convenience markup)
GW.Config.ShowShopMarkup = true          -- Display markup badges and savings hints in F4 menu
GW.Config.DefaultShopMarkupPercent = 250 -- Default surcharge percentage for public kiosk convenience items

-- Whitelist of allowed tools and RP equipment for the Hobo job
GW.HoboAllowedWeapons = {
    ["weapon_physgun"] = true,
    ["gmod_tool"] = true,
    ["weapon_physcannon"] = true,
    ["weapon_fists"] = true,
    ["weapon_gw_keys"] = true,
    ["weapon_bugbait"] = true,
    ["gmod_camera"] = true
}

-- Default Colors
GW.Colors = {
    Background = Color(15, 23, 42, 230),
    Border = Color(56, 189, 248),
    HealthRed = Color(220, 38, 38),
    ArmorBlue = Color(56, 189, 248),
    MoneyGreen = Color(74, 222, 128),
    Gold = Color(245, 158, 11),
    White = Color(248, 250, 252),
    Muted = Color(148, 163, 184)
}

-- Dynamic Gang Color Generator: converts any gang name into a unique, persistent vivid color
function GW.GetGangColor(gangName)
    if not gangName or gangName == "" or gangName == "neutral" or gangName == "Unclaimed" then
        return GW.Colors.Muted
    end
    if string.lower(gangName) == "police" then
        return GW.Colors.MoneyGreen
    end

    local hash = 0
    for i = 1, #gangName do
        hash = (hash * 31 + string.byte(gangName, i)) % 360
    end
    return HSVToColor(hash, 0.8, 0.95)
end

-- Helper: Retrieve dynamic purchase price for an item based on player's job (Wholesale vs Retail)
function GW.GetItemCost(item, ply)
    if not item then return 0 end
    local baseCost = item.cost or 0
    if not IsValid(ply) then return baseCost end

    local plyJob = ply:GetJob()
    local qualifiesWholesale = false

    if item.wholesaleJob and plyJob == item.wholesaleJob then
        qualifiesWholesale = true
    elseif item.wholesaleJobs and table.HasValue(item.wholesaleJobs, plyJob) then
        qualifiesWholesale = true
    elseif item.markupRole then
        local jobData = ply:GetJobData()
        if jobData and string.lower(jobData.name) == string.lower(item.markupRole) then
            qualifiesWholesale = true
        end
    end

    if qualifiesWholesale and item.wholesaleCost then
        return item.wholesaleCost
    end

    return baseCost
end

-- Helper: Retrieve configured or calculated shop markup percentage for an item
function GW.GetItemMarkupPercent(item, ply)
    if not GW.Config.ShowShopMarkup then return nil end
    if not item then return nil end

    -- If player is a specialist receiving wholesale cost, no retail markup applies to them
    if IsValid(ply) and item.wholesaleCost then
        local cost = GW.GetItemCost(item, ply)
        if cost <= item.wholesaleCost then
            return nil
        end
    end

    if item.markupPercent then return item.markupPercent end
    if item.wholesaleCost and item.cost and item.cost > item.wholesaleCost then
        return math.Round(((item.cost - item.wholesaleCost) / item.wholesaleCost) * 100)
    end
    if item.isMarkedUp then
        return GW.Config.DefaultShopMarkupPercent or 250
    end
    return nil
end

-- F4 Shop Items
GW.ShopItems = {
    -- ========================================================
    -- 1. PUBLIC STREET SUPPLIES & BASIC TOOLS
    -- ========================================================
    ["ammo_universal"] = {
        name = "Universal Ammo Crate",
        level = 1,
        cost = 70,
        wholesaleCost = 20,
        markupPercent = 250,
        markupRole = "Arms Dealer",
        wholesaleJob = "arms_dealer",
        type = "ammo",
        category = "supplies",
        desc = "Emergency street ammunition pack for pistols, rifles, shotguns & magnums."
    },
    ["item_bandage"] = {
        name = "Tactical Field Bandage (Bag Item)",
        level = 1,
        cost = 18,
        wholesaleCost = 5,
        markupPercent = 260,
        markupRole = "Pharmacist",
        wholesaleJob = "pharmacist",
        type = "consumable",
        category = "supplies",
        itemId = "consumable_bandage",
        desc = "Basic field dressing. Adds bandage to bag; applies Trauma Recovery HoT when used."
    },

    -- ========================================================
    -- 2. ARMS DEALER EXCLUSIVES (LEGAL DEFENSE & BULK AMMO)
    -- ========================================================
    ["ammo_bulk_crate"] = {
        name = "Wholesale Ammo Crate",
        level = 2,
        cost = 20,
        type = "ammo",
        category = "supplies",
        jobs = { "arms_dealer" },
        desc = "Discount bulk ammunition crate for authorized weapons dealers."
    },
    ["armor_vest"] = {
        name = "Heavy Kevlar Vest",
        level = 3,
        cost = 35,
        type = "armor",
        category = "supplies",
        jobs = { "arms_dealer" },
        desc = "Reinforced ceramic ballistic vest. Restores body armor to 100%."
    },
    ["shipment_glock"] = {
        name = "Shipment: Glock-18 (10x)",
        level = 1,
        cost = 180,
        type = "shipment",
        weapon = "weapon_gw_glock",
        weaponName = "Glock-18",
        count = 10,
        jobs = { "arms_dealer" },
        isContraband = true
    },
    ["shipment_shotgun"] = {
        name = "Shipment: Shotgun (10x)",
        level = 3,
        cost = 750,
        type = "shipment",
        weapon = "weapon_gw_shotgun",
        weaponName = "Pump Shotgun",
        count = 10,
        jobs = { "arms_dealer" },
        isContraband = true
    },

    -- ========================================================
    -- 3. BLACK MARKET DEALER EXCLUSIVES (CONTRABAND & INFILTRATION)
    -- ========================================================
    ["weapon_lockpick"] = {
        name = "Tactical Lockpick",
        level = 2,
        cost = 45,
        type = "weapon",
        class = "weapon_gw_lockpick",
        jobs = { "black_market_dealer", "thief" },
        isContraband = true,
        desc = "Mechanical lock bypass tool. Used to breach locked doors and security pins."
    },
    ["shipment_lockpick"] = {
        name = "Shipment: Tactical Lockpick (5x)",
        level = 2,
        cost = 120,
        type = "shipment",
        weapon = "weapon_gw_lockpick",
        weaponName = "Tactical Lockpick",
        count = 5,
        jobs = { "black_market_dealer" },
        isContraband = true
    },
    ["item_illegal_stim"] = {
        name = "Black Market Adrenaline (Bag Item)",
        level = 4,
        cost = 15,
        type = "consumable",
        category = "supplies",
        itemId = "consumable_illegal_stim",
        jobs = { "black_market_dealer" },
        isContraband = true,
        desc = "Underground combat injector. Grants +40% speed and 15% damage reduction for 20s."
    },
    ["shipment_deagle"] = {
        name = "Shipment: Desert Eagle (10x)",
        level = 5,
        cost = 420,
        type = "shipment",
        weapon = "weapon_gw_deagle",
        weaponName = "Desert Eagle",
        count = 10,
        jobs = { "black_market_dealer" },
        isContraband = true
    },
    ["shipment_ak47"] = {
        name = "Shipment: AK-47 (10x)",
        level = 8,
        cost = 1500,
        type = "shipment",
        weapon = "weapon_gw_ak47",
        weaponName = "AK-47",
        count = 10,
        jobs = { "black_market_dealer" },
        isContraband = true
    },

    -- ========================================================
    -- 4. PHARMACIST EXCLUSIVES (CLINICAL TRIAGE & DEPLOYABLE POD)
    -- ========================================================
    ["entity_clinic_pod"] = {
        name = "Clinical Triage Pod",
        level = 1,
        cost = 150,
        type = "entity",
        class = "gw_clinic_pod",
        category = "supplies",
        jobs = { "pharmacist" },
        desc =
        "Deployable automated triage clinic. Dispenses heals and combat bio-enhancements to passing citizens. Generates passive income for the Pharmacist."
    },
    ["weapon_medkit"] = {
        name = "Field Medical Kit",
        level = 1,
        cost = 50,
        type = "weapon",
        class = "weapon_gw_medkit",
        jobs = { "pharmacist" },
        desc = "Deployable trauma kit used to treat injuries and administer combat adrenaline stims in the field."
    },
    ["medkit"] = {
        name = "First Aid Kit (Instant)",
        level = 1,
        cost = 85,
        wholesaleCost = 25,
        markupPercent = 240,
        markupRole = "Pharmacist",
        wholesaleJob = "pharmacist",
        type = "medkit",
        category = "supplies",
        desc = "Emergency clinical trauma pack; restores +60 Health immediately."
    },

    -- ========================================================
    -- 5. NETWORKING & HARDWARE (ACCESSIBLE TO ALL CITIZENS)
    -- ========================================================
    ["weapon_wiretool"] = {
        name = "Copper Wiring Tool",
        level = 1,
        cost = 50,
        wholesaleCost = 15,
        markupPercent = 233,
        markupRole = "Cyber Engineer",
        wholesaleJob = "cyber_engineer",
        type = "weapon",
        class = "weapon_gw_wiretool",
        category = "networking",
        desc = "Cabling tool used to connect printers, switches, and computer terminals."
    },
    ["weapon_repairtool"] = {
        name = "Printer Calibrator",
        level = 2,
        cost = 105,
        wholesaleCost = 30,
        markupPercent = 250,
        markupRole = "Cyber Engineer",
        wholesaleJob = "cyber_engineer",
        type = "weapon",
        class = "weapon_gw_repairtool",
        category = "networking",
        desc =
        "Handheld printer calibrator. Cools printers (-35°C), repairs integrity, and allows Cyber Engineers to Supercharge hardware."
    },
    ["entity_network_switch"] = {
        name = "L3 Network Switch (2-Cu + 2-SFP)",
        level = 2,
        cost = 120,
        type = "entity",
        class = "gw_network_switch",
        category = "networking",
        desc =
        "Layer-3 hardware switch featuring 2 copper ports, Port 3 SFP combo (10G for switches/WAN or 1G for printers), and Port 4 10G SFP uplink."
    },
    ["entity_computer"] = {
        name = "Personal Computer",
        level = 5,
        cost = 200,
        type = "entity",
        class = "gw_computer",
        category = "networking",
        desc =
        "CyberDeck OS terminal. Connect to an L3 switch with a Satellite WAN Uplink to run automated Cloud Botnet C2 attacks (scales with networked printers), plus nmap & Metasploit."
    },
    ["entity_wan_uplink"] = {
        name = "Satellite WAN Uplink",
        level = 3,
        cost = 180,
        type = "entity",
        class = "gw_wan_uplink",
        category = "networking",
        desc =
        "Encrypted microwave satellite dish. Unlocks automated Cloud Botnet C2 income on a networked Personal Computer and links separate L3 switch networks wirelessly across the map."
    },
    ["weapon_cyberphone"] = {
        name = "CyberDeck Mobile Phone",
        level = 3,
        cost = 250,
        type = "weapon",
        class = "weapon_gw_cyberphone",
        category = "networking",
        jobs = { "cyber_engineer" },
        desc =
        "Handheld mobile CyberDeck handset exclusively for Cyber Engineers. Runs CyberDeck OS with built-in wireless spectrum reconnaissance and mobile Metasploit."
    },
    ["module_undervolt"] = {
        name = "Undervolt Hardware Module",
        level = 3,
        cost = 80,
        type = "entity",
        class = "gw_module_undervolt",
        category = "networking",
        isContraband = true,
        desc = "Microcontroller module that drops operating voltage (-75% heat, +400% lifespan)."
    },
    ["module_overclock"] = {
        name = "Overclock Hardware Module",
        level = 4,
        cost = 150,
        type = "entity",
        class = "gw_module_overclock",
        category = "networking",
        isContraband = true,
        desc = "High-frequency module that boosts printer cash yield by +50% (+60% heat output)."
    },

    -- ========================================================
    -- 6. PUBLIC MONEY PRINTERS (ACCESSIBLE TO ALL CITIZENS)
    -- ========================================================
    ["printer_bronze"] = {
        name = "Money Printer",
        level = 1,
        cost = 250,
        type = "entity",
        class = "gw_printer_bronze",
        category = "printers",
        isContraband = true,
        desc = "Entry-level contraband printer. Generates steady cash revenue."
    },
    ["printer_silver"] = {
        name = "Silver Money Printer",
        level = 4,
        cost = 750,
        type = "entity",
        class = "gw_printer_silver",
        category = "printers",
        isContraband = true,
        desc = "Commercial grade contraband printer. High efficiency throughput."
    },
    ["printer_diamond"] = {
        name = "Diamond Money Printer",
        level = 8,
        cost = 2200,
        type = "entity",
        class = "gw_printer_diamond",
        category = "printers",
        isContraband = true,
        desc = "Maximum tier industrial printer. High yields, benefits greatly from networking."
    },
    ["entity_resource_machine"] = {
        name = "Resource Fabricator",
        level = 2,
        cost = 500,
        max = 2,
        type = "entity",
        class = "gw_resource_machine",
        category = "printers",
        badge = "Legal Tech",
        desc =
        "Automated legal extractor & crafting station. Generates ingots, blueprints, and carbon rods. Connects to L3 switch for accelerated throughput."
    },

    -- ========================================================
    -- DEBUG / TEST: BUFFS, DEBUFFS & CONSUMABLES
    -- ========================================================
    ["debug_buff_swiftness"] = {
        name = "[DEBUG] Adrenaline Surge (+30% Speed)",
        cost = 10,
        type = "buff",
        category = "debug",
        debug = true,
        buffId = "swiftness",
        buffDuration = 30,
        desc = "Instantly grants +30% movement speed for 30 seconds."
    },
    ["debug_buff_hot"] = {
        name = "[DEBUG] Trauma Recovery (+6 HP HoT)",
        cost = 10,
        type = "buff",
        category = "debug",
        debug = true,
        buffId = "healing_over_time",
        buffDuration = 15,
        desc = "Restores +6 Health every 1.5 seconds for 15 seconds."
    },
    ["debug_buff_fortitude"] = {
        name = "[DEBUG] Reinforced Plating (+50 Max HP)",
        cost = 10,
        type = "buff",
        category = "debug",
        debug = true,
        buffId = "fortitude",
        buffDuration = 600,
        desc = "Equips ceramic trauma plating, granting +50 Max Health for 10 minutes."
    },
    ["debug_debuff_wanted"] = {
        name = "[DEBUG] Wanted by Police (Debuff)",
        cost = 10,
        type = "buff",
        category = "debug",
        debug = true,
        isDebuff = true,
        buffId = "wanted",
        buffDuration = 180,
        buffData = { reason = "F4 Debug Testing", officer = "Admin Console" },
        desc = "Flags player wanted by police. Persists across death and logout."
    },
    ["debug_debuff_crippled"] = {
        name = "[DEBUG] Crippled Leg (-40% Speed)",
        cost = 10,
        type = "buff",
        category = "debug",
        debug = true,
        isDebuff = true,
        buffId = "crippled",
        buffDuration = 25,
        desc = "Inflicts leg fracture, slowing walk & sprint speed by -40%."
    },
    ["debug_debuff_poison"] = {
        name = "[DEBUG] Lethal Neurotoxin (DoT Debuff)",
        cost = 10,
        type = "buff",
        category = "debug",
        debug = true,
        isDebuff = true,
        buffId = "poison",
        buffDuration = 14,
        desc = "Inflicts venomous toxin dealing 4 damage every 2 seconds."
    },
    ["debug_cleanse_all"] = {
        name = "[DEBUG] Clear All Status Effects",
        cost = 0,
        type = "cleanse",
        category = "debug",
        debug = true,
        desc = "Clears all active positive and negative status effects."
    }
}
