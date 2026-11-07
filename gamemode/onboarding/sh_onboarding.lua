--[[
    gamemode/onboarding/sh_onboarding.lua
    GridRP First-5-Minutes Onboarding & Syndicate Initiation (GRID.Onboarding)
    Author: GRID Core Team & Antigravity
    Namespace: GRID.Onboarding
--]]

GRID = GRID or {}
GRID.Onboarding = GRID.Onboarding or {}

-- --------------------------------------------------------
-- Configuration & Rewards
-- --------------------------------------------------------
GRID.Onboarding.STAGE_ROOKIE    = 0 -- Spawned in, needs to claim Fixer Dead-Drop
GRID.Onboarding.STAGE_DEAD_DROP = 1 -- Claimed drop, needs to breach Practice Stash
GRID.Onboarding.STAGE_STASH     = 2 -- Breached stash, needs to destroy Combat Drone
GRID.Onboarding.STAGE_COMPLETED = 3 -- Syndicate Verified (Level 2+)

GRID.Onboarding.REWARD_DEAD_DROP_CASH = 1000 -- Immediate cash in locker
GRID.Onboarding.REWARD_STASH_AMMO     = 34   -- 2x full Glock magazines
GRID.Onboarding.REWARD_BONUS_CASH     = 2500 -- Completion bonus deposited to personal bank
GRID.Onboarding.TOTAL_CLEAN_CASH      = 2500
GRID.Onboarding.REWARD_ARMOR          = 50

GRID.Onboarding.STARTER_WEAPON_CLASS      = "weapon_grid_glock"
GRID.Onboarding.STARTER_WEAPON_DURABILITY = 90
GRID.Onboarding.PRACTICE_STASH_PICK_TIME  = 4.0 -- Seconds to lockpick practice stash

-- Fixer Pager Briefings
GRID.Onboarding.Transmissions = {
    [0] = {
        title = "STEP 1/3: CLAIM STARTER KIT",
        objective = "Locate the Fixer's Alleyway Dead-Drop Locker",
        body = "Rookie, the Fixer left a sterile care package in an alleyway locker. Claim your Glock-18, lockpick, and $1,000 starter cash.",
        markerText = "FIXER DEAD-DROP"
    },
    [1] = {
        title = "STEP 2/3: BREACH PRACTICE STASH",
        objective = "Use your Tactical Lockpick on the Stash Crate",
        body = "Test your hands under pressure. Equip your lockpick, crack open the training crate for Kevlar armor and fresh 9mm ammo.",
        markerText = "PRACTICE STASH"
    },
    [2] = {
        title = "STEP 3/3: LIVE-FIRE COMBAT DRILL",
        objective = "Destroy the Syndicate Combat Drone with your Glock-18",
        body = "Live-fire drill active! Draw your Glock-18 sidearm, acquire your target, and eliminate the training drone to prove combat readiness.",
        markerText = "COMBAT DRONE"
    },
    [3] = {
        title = "INITIATION COMPLETE // SYNDICATE VERIFIED",
        objective = "Full GridRP Permissions Unlocked",
        body = "Weapons mastery verified. Tactical lockpick returned to Syndicate Armory. Base building, toolguns, auction listings, and advanced careers are now accessible.",
        markerText = "VERIFIED"
    }
}

