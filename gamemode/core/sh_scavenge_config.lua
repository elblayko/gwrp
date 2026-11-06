--[[
    gamemode/core/sh_scavenge_config.lua
    GridRP Passive Scavenging & Street Recycling Shared Configuration
    Author: Juicebox & Antigravity
--]]

GRID = GRID or {}
GRID.Scavenge = GRID.Scavenge or {}

-- ========================================================
-- 1. SCAVENGE NODE COOLDOWNS & SEARCH TIMERS
-- ========================================================

GRID.Scavenge.Config = {
    SearchDuration = 1.5,                                                                 -- Standard search hold duration in seconds
    HoboSearchDuration = (GRID.Config and GRID.Config.HoboScavengeSearchDuration) or 1.2, -- Hobo class perk
    HoboYieldBonus = (GRID.Config and GRID.Config.HoboScavengeYieldBonus) or 0.15,        -- Hobo loot yield perk (+15%)
    MaxInteractDistance = 110,                                                            -- Maximum distance player can move before search cancels
    InteractionCooldown = 0.5,                                                            -- Debounce delay between Use triggers

    -- Node base cooldowns in seconds (modified dynamically by population balancer)
    Cooldowns = {
        dumpster = 300, -- 5 minutes
        trashbin = 150, -- 2.5 minutes
        scrappile = 240 -- 4 minutes
    },

    -- Multi-item Recycling Bonus Curve (+5% per distinct category, capped at +25%)
    RecycleBonusPerCategory = 0.05,
    RecycleMaxBonus = 0.25,
    GangBankTributePct = 0.10 -- 10% matching bonus deposited into player's gang bank
}

-- ========================================================
-- 2. RECYCLABLE ITEM VALUES & REWARDS
-- ========================================================

GRID.Scavenge.Recyclables = {
    ["junk_scrap_metal"] = {
        name = "Scrap Metal",
        cash = 18,
        price = 18,
        xp = 12,
        category = "metal",
        desc = "Twisted sheet metal, rebar, and scrap pipes."
    },
    ["junk_gunpowder"] = {
        name = "Gunpowder Residue",
        cash = 25,
        price = 25,
        xp = 16,
        category = "chemical",
        desc = "Unspent propellant granules salvaged from discarded cartridges."
    },
    ["junk_electronics"] = {
        name = "Broken Electronics",
        cash = 45,
        price = 45,
        xp = 25,
        category = "electronics",
        desc = "Salvaged circuit boards, blown capacitors, and wiring."
    },
    ["junk_plastic_bottle"] = {
        name = "Plastic Bottle",
        cash = 8,
        price = 8,
        xp = 5,
        category = "plastic",
        desc = "Empty plastic soda bottle eligible for deposit refund."
    },
    ["junk_aluminum_can"] = {
        name = "Aluminum Can",
        cash = 10,
        price = 10,
        xp = 6,
        category = "can",
        desc = "Crushed aluminum soda can ready for metal recycling."
    }
}

-- ========================================================
-- 3. SERVER-AUTHORITATIVE WEIGHTED LOOT TABLES
-- ========================================================

GRID.Scavenge.LootTables = {
    ["dumpster"] = {
        cashChance = 0.60,
        minCash = 10,
        maxCash = 40,
        rolls = { min = 2, max = 4 },
        pool = {
            { item = "junk_scrap_metal",    weight = 35, min = 1, max = 3 },
            { item = "junk_electronics",    weight = 30, min = 1, max = 2 },
            { item = "junk_plastic_bottle", weight = 15, min = 1, max = 3 },
            { item = "junk_aluminum_can",   weight = 15, min = 1, max = 3 },
            { item = "junk_gunpowder",      weight = 5,  min = 1, max = 1 }
        }
    },
    ["trashbin"] = {
        cashChance = 0.75,
        minCash = 5,
        maxCash = 25,
        rolls = { min = 1, max = 3 },
        pool = {
            { item = "junk_plastic_bottle", weight = 40, min = 1, max = 3 },
            { item = "junk_aluminum_can",   weight = 35, min = 1, max = 3 },
            { item = "junk_scrap_metal",    weight = 15, min = 1, max = 2 },
            { item = "junk_electronics",    weight = 8,  min = 1, max = 1 },
            { item = "junk_gunpowder",      weight = 2,  min = 1, max = 1 }
        }
    },
    ["scrappile"] = {
        cashChance = 0.35,
        minCash = 5,
        maxCash = 20,
        rolls = { min = 2, max = 4 },
        pool = {
            { item = "junk_scrap_metal",  weight = 50, min = 2, max = 4 },
            { item = "junk_gunpowder",    weight = 25, min = 1, max = 2 },
            { item = "junk_electronics",  weight = 15, min = 1, max = 2 },
            { item = "junk_aluminum_can", weight = 10, min = 1, max = 2 }
        }
    }
}
