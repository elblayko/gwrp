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
GRID.Onboarding.STAGE_STASH     = 2 -- Breached stash, needs to deposit at Street ATM
GRID.Onboarding.STAGE_COMPLETED = 3 -- Syndicate Verified (Level 2+)

GRID.Onboarding.REWARD_DEAD_DROP_CASH = 2500
GRID.Onboarding.REWARD_STASH_CASH     = 1000
GRID.Onboarding.TOTAL_CLEAN_CASH      = 3500 -- Deposited into clean bank upon Stage 3 completion
GRID.Onboarding.REWARD_ARMOR          = 50

GRID.Onboarding.STARTER_WEAPON_CLASS      = "weapon_grid_glock"
GRID.Onboarding.STARTER_WEAPON_DURABILITY = 90
GRID.Onboarding.PRACTICE_STASH_PICK_TIME  = 4.0 -- Seconds to lockpick practice stash

-- Fixer Pager Briefings
GRID.Onboarding.Transmissions = {
    [0] = {
        title = "STEP 1/3: CLAIM STARTER KIT",
        objective = "Locate the Fixer's Alleyway Dead-Drop Locker",
        body = "Rookie, the Fixer left a sterile care package in an alleyway locker. Claim your Glock-18, lockpick, and $2,500 dirty seed cash.",
        markerText = "FIXER DEAD-DROP"
    },
    [1] = {
        title = "STEP 2/3: BREACH PRACTICE STASH",
        objective = "Use your Tactical Lockpick on the Stash Crate",
        body = "Prove your hands are steady. Equip your Tactical Lockpick and pop open the nearby training stash crate for Kevlar armor and +$1,000.",
        markerText = "PRACTICE STASH"
    },
    [2] = {
        title = "STEP 3/3: SECURE & WASH FUNDS",
        objective = "Deposit your $3,500 Dirty Cash at the Street ATM",
        body = "Don't walk the streets with dirty bills. Reach the nearest Street ATM to wash and deposit your $3,500 cut into your clean bank.",
        markerText = "STREET ATM"
    },
    [3] = {
        title = "INITIATION COMPLETE // SYNDICATE VERIFIED",
        objective = "Full GridRP Permissions Unlocked",
        body = "Credentials verified. Base building, toolguns, auction listings, and advanced careers are now accessible.",
        markerText = "VERIFIED"
    }
}

