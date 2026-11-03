--[[
    sh_config.lua - Gamemode Constants, Economy Items & Balancing
--]]

GWRP.Config = GWRP.Config or {}

-- Economy
GWRP.Config.StartingMoney = 250
GWRP.Config.PaydayInterval = 90 -- seconds between salary ticks
GWRP.Config.DropMoneyOnDeathMax = 75
GWRP.Config.GangCreationCost = 200 -- cost to register a new player gang

-- Turf Warfare
GWRP.Config.TurfCaptureRadius = 450 -- Hammer units
GWRP.Config.TurfCaptureTime = 15 -- seconds of holding uncontested to capture
GWRP.Config.TurfDividendInterval = 90 -- seconds between turf payouts
GWRP.Config.TurfDividendAmount = 25 -- cash given to each online gang member per owned turf
GWRP.Config.TurfCaptureReward = 40 -- instant cash reward to capturing player

-- Contraband Money Printers & Networking
GWRP.Config.MaxPrintersPerPlayer = 4
GWRP.Config.PoliceBountyPerPrinter = 125
GWRP.Config.PoliceBountyPerSwitch = 50
GWRP.Config.PoliceBountyPerModule = 25
GWRP.Config.EntityHUDViewDistance = 380 -- Shared max 3D2D HUD visibility distance for printers & synthesizers

-- Thermal Regulation & Undervolt Module
GWRP.Config.PrinterHeatRiseStandard = 4      -- +4C per cycle
GWRP.Config.PrinterHeatRiseUndervolted = 1   -- +1C per cycle (+400% lifespan)
GWRP.Config.ModuleUndervoltCost = 80

-- Network Switch & Efficiency Rates
GWRP.Config.SwitchMaxPorts = 3 -- 3 physical ports per L2 switch
GWRP.Config.MaxCableLength = 550 -- maximum length in hammer units before cable snaps
GWRP.Config.PrinterStandaloneEfficiency = 60 -- 1 printer or unlinked = 60%
GWRP.Config.PrinterNetworkEfficiency2 = 80   -- 2 printers on switch = 80%
GWRP.Config.PrinterNetworkEfficiency3 = 100  -- 3 printers on switch = 100%

-- Centralized Entity Quality Registry (Entities can also set ENT.ItemQuality in their shared.lua)
GWRP.Config.EntityQualities = {
    ["gwrp_printer_bronze"] = { quality = 1, subType = "Passive Fabricator", stats = "Yield: $12 / 60s" },
    ["gwrp_printer_silver"] = { quality = 2, subType = "Commercial Fabricator", stats = "Yield: $30 / 60s" },
    ["gwrp_printer_diamond"] = { quality = 3, subType = "Industrial Fabricator", stats = "Yield: $75 / 60s" },
    ["gwrp_network_switch"] = { quality = 3, subType = "Network Appliance", stats = "3x Ports | L2 Layer" },
    ["gwrp_computer"] = { quality = 3, subType = "Cyber Appliance", stats = "Layer-2 Terminal | Port Scanner" },
    ["gwrp_module_undervolt"] = { quality = 3, subType = "Hardware Upgrade", stats = "+400% Lifespan | -75% Heat" },
    ["gwrp_shipment"] = { quality = 3, subType = "Wholesale Container", stats = "Holds 10x Packaged Firearms" },
    ["gwrp_resource_machine"] = { quality = 1, subType = "Automated Extractor", stats = "Extracts Metals & Blueprints | Network Capable" },

    -- Explicit Exclusions (Never have item quality)
    ["gwrp_flag_pole"] = false,
    ["gwrp_cash_stack"] = false
}

-- Door Pricing
GWRP.Config.DoorCost = 15

-- Leveling & Progression System (MMO Curve, Capped at Level 50)
GWRP.Config.Level = {
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

function GWRP.GetRequiredXP(level)
    level = math.Clamp(tonumber(level) or 1, 1, GWRP.Config.Level.MaxLevel)
    if level >= GWRP.Config.Level.MaxLevel then
        return 0 -- Max level cap reached
    end
    -- MMO Curve: Floor(250 * level ^ 1.65)
    return math.floor(GWRP.Config.Level.BaseXP * (level ^ GWRP.Config.Level.Exponent))
end

-- F4 Shop Retail Surcharge & Markup Settings
GWRP.Config.ShowShopMarkup = true           -- Display markup badges and savings hints in F4 menu
GWRP.Config.DefaultShopMarkupPercent = 65  -- Default surcharge percentage for public kiosk convenience items

-- Default Colors
GWRP.Colors = {
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
function GWRP.GetGangColor(gangName)
    if not gangName or gangName == "" or gangName == "neutral" or gangName == "Unclaimed" then
        return GWRP.Colors.Muted
    end
    if string.lower(gangName) == "police" then
        return GWRP.Colors.MoneyGreen
    end

    local hash = 0
    for i = 1, #gangName do
        hash = (hash * 31 + string.byte(gangName, i)) % 360
    end
    return HSVToColor(hash, 0.8, 0.95)
end

-- Helper: Retrieve configured or calculated shop markup percentage for an item
function GWRP.GetItemMarkupPercent(item)
    if not GWRP.Config.ShowShopMarkup then return nil end
    if not item then return nil end
    if item.markupPercent then return item.markupPercent end
    if item.wholesaleCost and item.cost and item.cost > item.wholesaleCost then
        return math.Round(((item.cost - item.wholesaleCost) / item.wholesaleCost) * 100)
    end
    if item.isMarkedUp then
        return GWRP.Config.DefaultShopMarkupPercent or 65
    end
    return nil
end

-- F4 Shop Items
GWRP.ShopItems = {
    -- ========================================================
    -- 1. PUBLIC STREET SUPPLIES & BASIC TOOLS
    -- ========================================================
    ["ammo_universal"] = { 
        name = "Universal Ammo Crate", 
        level = 1,
        cost = 35, 
        wholesaleCost = 20,
        markupPercent = 75,
        markupRole = "Arms Dealer",
        type = "ammo", 
        category = "supplies", 
        desc = "Emergency street ammunition pack for pistols, rifles, shotguns & magnums." 
    },
    ["item_bandage"] = {
        name = "Tactical Field Bandage (Bag Item)",
        level = 1,
        cost = 12,
        wholesaleCost = 5,
        markupPercent = 140,
        markupRole = "Pharmacist",
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
        weapon = "weapon_gwrp_glock", 
        weaponName = "Glock-18", 
        count = 10, 
        jobs = { "arms_dealer" } 
    },
    ["shipment_shotgun"] = { 
        name = "Shipment: Shotgun (10x)", 
        level = 3,
        cost = 750, 
        type = "shipment", 
        weapon = "weapon_gwrp_shotgun", 
        weaponName = "Pump Shotgun", 
        count = 10, 
        jobs = { "arms_dealer" } 
    },

    -- ========================================================
    -- 3. BLACK MARKET DEALER EXCLUSIVES (CONTRABAND & INFILTRATION)
    -- ========================================================
    ["weapon_lockpick"] = { 
        name = "Tactical Lockpick", 
        level = 2,
        cost = 45, 
        type = "weapon", 
        class = "weapon_gwrp_lockpick", 
        jobs = { "black_market_dealer", "thief" }, 
        desc = "Mechanical lock bypass tool. Used to breach locked doors and security pins." 
    },
    ["shipment_lockpick"] = { 
        name = "Shipment: Tactical Lockpick (5x)", 
        level = 2,
        cost = 120, 
        type = "shipment", 
        weapon = "weapon_gwrp_lockpick", 
        weaponName = "Tactical Lockpick", 
        count = 5, 
        jobs = { "black_market_dealer" } 
    },
    ["item_illegal_stim"] = {
        name = "Black Market Adrenaline (Bag Item)",
        level = 4,
        cost = 15,
        type = "consumable",
        category = "supplies",
        itemId = "consumable_illegal_stim",
        jobs = { "black_market_dealer" },
        desc = "Underground combat injector. Grants +40% speed and 15% damage reduction for 20s."
    },
    ["shipment_deagle"] = { 
        name = "Shipment: Desert Eagle (10x)", 
        level = 5,
        cost = 420, 
        type = "shipment", 
        weapon = "weapon_gwrp_deagle", 
        weaponName = "Desert Eagle", 
        count = 10, 
        jobs = { "black_market_dealer" } 
    },
    ["shipment_ak47"] = { 
        name = "Shipment: AK-47 (10x)", 
        level = 8,
        cost = 1500, 
        type = "shipment", 
        weapon = "weapon_gwrp_ak47", 
        weaponName = "AK-47", 
        count = 10, 
        jobs = { "black_market_dealer" } 
    },

    -- ========================================================
    -- 4. PHARMACIST EXCLUSIVES (CLINICAL TRIAGE & DEPLOYABLE POD)
    -- ========================================================
    ["entity_clinic_pod"] = {
        name = "Clinical Triage Pod",
        level = 1,
        cost = 150,
        type = "entity",
        class = "gwrp_clinic_pod",
        category = "supplies",
        jobs = { "pharmacist" },
        desc = "Deployable automated triage clinic. Dispenses heals and combat bio-enhancements to passing citizens. Generates passive income for the Pharmacist."
    },
    ["weapon_medkit"] = { 
        name = "Field Medical Kit", 
        level = 1,
        cost = 50, 
        type = "weapon", 
        class = "weapon_gwrp_medkit", 
        jobs = { "pharmacist" }, 
        desc = "Deployable trauma kit used to treat injuries and administer combat adrenaline stims in the field." 
    },
    ["medkit"] = { 
        name = "First Aid Kit (Instant)", 
        level = 1,
        cost = 25, 
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
        cost = 15, 
        type = "weapon", 
        class = "weapon_gwrp_wiretool", 
        category = "networking", 
        desc = "Cabling tool used to connect printers, switches, and computer terminals." 
    },
    ["weapon_repairtool"] = { 
        name = "Cryo-Thermal Calibrator", 
        level = 2,
        cost = 30, 
        type = "weapon", 
        class = "weapon_gwrp_repairtool", 
        category = "networking", 
        desc = "Handheld cryo-calibrator. Cools printers (-35°C), repairs integrity, and allows Cyber Engineers to Supercharge hardware." 
    },
    ["entity_network_switch"] = { 
        name = "L2 Network Switch (3-Port)", 
        level = 2,
        cost = 120, 
        type = "entity", 
        class = "gwrp_network_switch", 
        category = "networking", 
        desc = "Hardware Layer-2 switch with 3 copper ports to boost printer efficiency to 100%." 
    },
    ["entity_computer"] = { 
        name = "Personal Computer", 
        level = 5,
        cost = 200, 
        type = "entity", 
        class = "gwrp_computer", 
        category = "networking", 
        desc = "Hacking OS terminal; connect to switch for network operations & nmap." 
    },
    ["module_undervolt"] = { 
        name = "Undervolt Hardware Module", 
        level = 3,
        cost = 80, 
        type = "entity", 
        class = "gwrp_module_undervolt", 
        category = "networking", 
        desc = "Microcontroller module that drops operating voltage (-75% heat, +400% lifespan)." 
    },
    ["module_overclock"] = { 
        name = "Overclock Hardware Module", 
        level = 4,
        cost = 150, 
        type = "entity", 
        class = "gwrp_module_overclock", 
        category = "networking", 
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
        class = "gwrp_printer_bronze", 
        category = "printers",
        desc = "Entry-level contraband printer. Generates steady cash revenue."
    },
    ["printer_silver"] = { 
        name = "Silver Money Printer", 
        level = 4,
        cost = 750, 
        type = "entity", 
        class = "gwrp_printer_silver", 
        category = "printers",
        desc = "Commercial grade contraband printer. High efficiency throughput."
    },
    ["printer_diamond"] = { 
        name = "Diamond Money Printer", 
        level = 8,
        cost = 2200, 
        type = "entity", 
        class = "gwrp_printer_diamond", 
        category = "printers",
        desc = "Maximum tier industrial printer. High yields, benefits greatly from networking."
    },
    ["entity_resource_machine"] = {
        name = "Resource Fabricator",
        level = 2,
        cost = 500,
        max = 2,
        type = "entity",
        class = "gwrp_resource_machine",
        category = "printers",
        badge = "Legal Tech",
        desc = "Automated legal extractor & crafting station. Generates ingots, blueprints, and carbon rods. Connects to L2 switch for accelerated throughput."
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
