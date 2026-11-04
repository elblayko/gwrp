--[[
    sh_factions.lua - Gangs & Comprehensive Job Hierarchy
    Author: Toxic
--]]

GW.Factions = {
    FACTION_CITIZEN = { id = "neutral", name = "Citizens", color = Color(148, 163, 184) },
    FACTION_GANG = { id = "gang", name = "Street Gangs", color = Color(245, 158, 11) },
    FACTION_POLICE = { id = "police", name = "Police / SWAT", color = Color(16, 185, 129) }
}

GW.Jobs = {
    -- ========================================================
    -- 1. CITIZEN & SPECIALTY SERVICES FACTION
    -- ========================================================
    ["citizen"] = {
        name = "Citizen",
        level = 1,
        faction = GW.Factions.FACTION_CITIZEN,
        salary = 6,
        weapons = { "weapon_fists" },
        models = {
            "models/player/Group01/male_01.mdl",
            "models/player/Group01/male_02.mdl",
            "models/player/Group01/male_07.mdl",
            "models/player/Group01/female_01.mdl"
        },
        max = 0,
        desc = "Standard urban civilian. Build bases, buy printers, or trade items."
    },
    ["pharmacist"] = {
        name = "Pharmacist",
        level = 1,
        faction = GW.Factions.FACTION_CITIZEN,
        salary = 12,
        weapons = { "weapon_fists", "weapon_gw_medkit" },
        models = { "models/player/mossman.mdl", "models/player/mossman_arctic.mdl" },
        max = 3,
        desc = "Clinical physician & bio-chemist. Deploys automated Triage Pods that sell combat buffs & heals for passive income, and administers field Adrenaline stims to allies."
    },
    ["cyber_engineer"] = {
        name = "Cyber Engineer",
        level = 3,
        faction = GW.Factions.FACTION_CITIZEN,
        salary = 14,
        weapons = { "weapon_fists", "weapon_gw_wiretool" },
        armor = 10,
        models = { "models/player/kleiner.mdl", "models/player/magnusson.mdl" },
        max = 3,
        desc = "High-tech network architect & infiltrator. Spawns with network wiring gear, can Supercharge hardware with a Cryo Calibrator, and holds root terminal exploit clearance."
    },
    ["security_guard"] = {
        name = "Security Contractor",
        level = 2,
        faction = GW.Factions.FACTION_CITIZEN,
        salary = 13,
        weapons = { "weapon_fists", "weapon_stunstick" },
        armor = 50,
        models = { "models/player/barney.mdl" },
        max = 4,
        desc = "Hired private protection specialist armed with stun baton. Guards money printer vaults and VIP bases."
    },
    ["arms_dealer"] = {
        name = "Arms Dealer",
        level = 2,
        faction = GW.Factions.FACTION_CITIZEN,
        salary = 10,
        weapons = { "weapon_fists" },
        models = { "models/player/monk.mdl" },
        max = 3,
        desc = "Authorized firearms merchant. Orders wholesale gun shipments and ammo crates to sell to citizens."
    },
    ["hobo"] = {
        name = "Hobo",
        level = 1,
        faction = GW.Factions.FACTION_CITIZEN,
        salary = 0,
        weapons = { "weapon_fists", "weapon_bugbait" },
        models = { "models/player/corpse1.mdl" },
        max = 4,
        desc = "Destitute street vagrant. Free from the law, builds scrap shacks, and begs for change."
    },

    -- ========================================================
    -- 2. STREET GANGS & UNDERWORLD FACTION
    -- ========================================================
    ["gangster"] = {
        name = "Gangster",
        level = 1,
        faction = GW.Factions.FACTION_GANG,
        salary = 10,
        weapons = { "weapon_fists" },
        models = { 
            "models/player/Group03/male_01.mdl", 
            "models/player/Group03/male_02.mdl",
            "models/player/Group03/male_06.mdl",
            "models/player/Group03/male_07.mdl" 
        },
        max = 16,
        desc = "Underworld soldier. Joins syndicates, purchases firearms from arms merchants, contests territory, and defends printers."
    },
    ["gang_boss"] = {
        name = "Gang Leader",
        level = 5,
        faction = GW.Factions.FACTION_GANG,
        salary = 20,
        weapons = { "weapon_fists" },
        armor = 50,
        models = { "models/player/Group03/male_04.mdl", "models/player/Group03/male_09.mdl" },
        max = 4,
        desc = "Commands a player syndicate. Heavy armor protection. Finances firearm shipments and coordinates base raids."
    },
    ["thief"] = {
        name = "Thief",
        level = 3,
        faction = GW.Factions.FACTION_GANG,
        salary = 10,
        weapons = { "weapon_fists", "weapon_gw_lockpick" },
        models = { "models/player/phoenix.mdl", "models/player/arctic.mdl" },
        max = 4,
        desc = "Silent infiltrator. Spawns with tactical lockpick to breach enemy doors, extract contraband, and crack vaults."
    },
    ["hitman"] = {
        name = "Hitman",
        level = 6,
        faction = GW.Factions.FACTION_GANG,
        salary = 16,
        weapons = { "weapon_fists", "weapon_gw_lockpick" },
        armor = 30,
        models = { "models/player/leet.mdl", "models/player/gman_high.mdl" },
        max = 2,
        desc = "Cold-blooded contract assassin for hire. Contracts weapons from dealers to eliminate high-value targets across the city."
    },
    ["black_market_dealer"] = {
        name = "Black Market Dealer",
        level = 4,
        faction = GW.Factions.FACTION_GANG,
        salary = 12,
        weapons = { "weapon_fists" },
        models = { "models/player/eli.mdl" },
        max = 2,
        desc = "Underground arms & contraband smuggler. Exclusive supplier of military firearms (AK-47, Deagle), wholesale Lockpick Crates, and Combat Adrenaline."
    },

    -- ========================================================
    -- 3. LAW ENFORCEMENT & GOVERNMENT FACTION
    -- ========================================================
    ["police_officer"] = {
        name = "Police Officer",
        level = 1,
        faction = GW.Factions.FACTION_POLICE,
        salary = 16,
        weapons = { "weapon_fists", "weapon_gw_glock", "weapon_stunstick", "weapon_gw_scanner" },
        armor = 30,
        walkSpeed = 230,
        runSpeed = 350,
        models = { "models/player/police.mdl" },
        max = 6,
        desc = "Rapid pursuit interceptor & detective. Top 350 sprint speed, exclusive contraband scanner, 5s rapid dispatch respawn, and +50% cash bounties on seized printers."
    },
    ["police_chief"] = {
        name = "Police Chief",
        level = 5,
        faction = GW.Factions.FACTION_POLICE,
        salary = 25,
        weapons = { "weapon_fists", "weapon_gw_deagle", "weapon_gw_shotgun", "weapon_stunstick" },
        armor = 50,
        walkSpeed = 220,
        runSpeed = 315,
        models = { "models/player/combine_soldier_prisonguard.mdl" },
        max = 1,
        desc = "Supreme commander of Civil Protection. Directs street patrols, issues warrants, and initiates city lockdowns."
    },
    ["swat_chief"] = {
        name = "SWAT Specialist",
        level = 7,
        faction = GW.Factions.FACTION_POLICE,
        salary = 22,
        weapons = { "weapon_fists", "weapon_gw_shotgun", "weapon_gw_ram" },
        armor = 100,
        walkSpeed = 160,
        runSpeed = 230,
        models = { "models/player/swat.mdl", "models/player/combine_soldier.mdl" },
        max = 2,
        desc = "Heavy tactical siege breacher with 100 Armor and Battering Ram. Heavy ballistic plating heavily restricts mobility (160 walk / 230 sprint)."
    },
    ["mayor"] = {
        name = "Mayor",
        level = 5,
        faction = GW.Factions.FACTION_POLICE,
        salary = 35,
        weapons = { "weapon_fists", "weapon_gw_deagle" },
        armor = 25,
        models = { "models/player/breen.mdl" },
        max = 1,
        desc = "Chief executive of the metropolis. Authorizes search warrants and initiates city lockdowns."
    }
}
