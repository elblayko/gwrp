--[[
    gamemode/onboarding/sv_onboarding.lua
    GridRP First-5-Minutes Onboarding & Syndicate Initiation - Server Authority
    Author: GRID Core Team & Antigravity
    Namespace: GRID.Onboarding
--]]

GRID = GRID or {}
GRID.Onboarding = GRID.Onboarding or {}

util.AddNetworkString("GRID_OnboardingSync")
util.AddNetworkString("GRID_OnboardingCompleted")
util.AddNetworkString("GRID_OnboardingGatedAlert")

-- --------------------------------------------------------
-- Step 1: Claim Fixer Dead-Drop
-- --------------------------------------------------------
function GRID.Onboarding.ClaimDeadDrop(ply, lockerEnt)
    if not IsValid(ply) or not ply:Alive() then return false end
    if not IsValid(lockerEnt) or lockerEnt:GetClass() ~= "grid_deaddrop_locker" then return false end

    -- Verify distance (anti-remote-trigger exploit)
    if ply:EyePos():DistToSqr(lockerEnt:GetPos()) > (120 * 120) then
        return false
    end

    -- Server-authoritative stage check (anti-replay exploit)
    if ply:GetOnboardingStage() ~= GRID.Onboarding.STAGE_ROOKIE then
        GRID.Notify(ply, "You have already claimed this dead-drop!", NOTIFY_ERROR, 4)
        return false
    end

    -- Atomic progression to Stage 1
    ply:SetOnboardingStage(GRID.Onboarding.STAGE_DEAD_DROP)

    -- Grant $1,000 starter seed cash
    ply:AddMoney(GRID.Onboarding.REWARD_DEAD_DROP_CASH)

    -- Give 1x Starter Glock-18 (at 90% durability)
    local glock = ply:Give(GRID.Onboarding.STARTER_WEAPON_CLASS)
    if IsValid(glock) then
        if glock.SetDurability then
            glock:SetDurability(GRID.Onboarding.STARTER_WEAPON_DURABILITY)
        end
        glock.GRID_IsStarterItem = true
    end

    -- Give 1x Tactical Lockpick (temporary training equipment)
    local lockpick = ply:Give("weapon_grid_lockpick")
    if IsValid(lockpick) then
        lockpick.GRID_IsStarterItem = true
    end

    -- Audio & feedback
    lockerEnt:EmitSound("doors/door_latch3.wav", 75, 100)
    ply:EmitSound("garrysmod/save_load1.wav", 65, 110)

    GRID.Notify(ply, string.format("Starter kit claimed! +$%s cash, Glock-18 (90%% Durability) & Tactical Lockpick.", string.Comma(GRID.Onboarding.REWARD_DEAD_DROP_CASH)), NOTIFY_HINT, 6)
    GRID.Notify(ply, "[STEP 2/2] Check your Burner Pager. Locate the Practice Stash and pick it!", NOTIFY_GENERIC, 7)

    net.Start("GRID_OnboardingSync")
        net.WriteUInt(GRID.Onboarding.STAGE_DEAD_DROP, 4)
    net.Send(ply)

    if GRID.Telemetry and GRID.Telemetry.Log then
        GRID.Telemetry.Log("PLAYER_ACTION", "ONBOARDING_CLAIM_DROP", ply:SteamID(), "", GRID.Onboarding.REWARD_DEAD_DROP_CASH, {
            weapon = GRID.Onboarding.STARTER_WEAPON_CLASS,
            durability = GRID.Onboarding.STARTER_WEAPON_DURABILITY
        })
    end

    return true
end

-- --------------------------------------------------------
-- Step 2: Breach Practice Stash & Syndicate Initiation
-- --------------------------------------------------------
function GRID.Onboarding.CompletePracticeStash(ply, stashEnt)
    if not IsValid(ply) or not ply:Alive() then return false end
    if not IsValid(stashEnt) or stashEnt:GetClass() ~= "grid_practice_stash" then return false end

    -- Distance verification
    if ply:EyePos():DistToSqr(stashEnt:GetPos()) > (120 * 120) then
        return false
    end

    -- Stage check: must be at Stage 1
    if ply:GetOnboardingStage() ~= GRID.Onboarding.STAGE_DEAD_DROP then
        if ply:GetOnboardingStage() >= GRID.Onboarding.STAGE_COMPLETED then
            GRID.Notify(ply, "You have already completed the practice breach!", NOTIFY_ERROR, 3)
        end
        return false
    end

    -- Grant Kevlar Armor (+50)
    ply:SetArmor(math.min(100, ply:Armor() + GRID.Onboarding.REWARD_ARMOR))

    -- Grant fresh 9mm ammunition
    local ammoCount = GRID.Onboarding.REWARD_STASH_AMMO or 34
    ply:GiveAmmo(ammoCount, "Pistol", true)

    -- Feedback
    stashEnt:EmitSound("ambient/materials/wood_box_break1.wav", 75, 100)
    ply:EmitSound("items/ammo_pickup.wav", 65, 100)

    GRID.Notify(ply, string.format("Stash breached! +%d Kevlar Armor & +%d 9mm ammunition.", GRID.Onboarding.REWARD_ARMOR, ammoCount), NOTIFY_HINT, 6)

    if GRID.Telemetry and GRID.Telemetry.Log then
        GRID.Telemetry.Log("PLAYER_ACTION", "ONBOARDING_BREACH_STASH", ply:SteamID(), "", ammoCount, {
            armor = GRID.Onboarding.REWARD_ARMOR,
            ammo = ammoCount
        })
    end

    local cleanBonus = GRID.Onboarding.TOTAL_CLEAN_CASH or 2500
    local steamID = ply:SteamID()

    -- Reclaim temporary training lockpick (Thief job exclusive)
    if ply:HasWeapon("weapon_grid_lockpick") then
        ply:StripWeapon("weapon_grid_lockpick")
    end
    if GRID.Database and GRID.Database.RemoveInventoryItem then
        GRID.Database.RemoveInventoryItem(steamID, "weapon_grid_lockpick", 1)
    end
    GRID.Notify(ply, "Tactical Lockpick returned to Syndicate Armory (Thief job specialization).", NOTIFY_HINT, 6)

    -- Atomic execution via MariaDB Stored Procedure / SQLite fallback
    if GRID.Database and GRID.Database.CallProcedure then
        GRID.Database.CallProcedure("grid_complete_onboarding", {
            steamID,
            cleanBonus
        }, function()
            if not IsValid(ply) then return end

            ply:SetNWInt("GRID_OnboardingStage", GRID.Onboarding.STAGE_COMPLETED)
            ply:SetNWInt("GRID_Bank", ply:GetBank() + cleanBonus)

            local currentLvl = ply:GetLevel()
            if currentLvl < 2 then
                ply:SetNWInt("GRID_Level", 2)
                ply:SetNWInt("GRID_XP", 0)
            end

            -- Update in-memory player cache
            if GRID.Database.Cache and GRID.Database.Cache.Players and GRID.Database.Cache.Players[steamID] then
                local p = GRID.Database.Cache.Players[steamID]
                p.onboarding_stage = 2
                p.level = math.max(p.level or 1, 2)
                p.bank = (p.bank or 0) + cleanBonus
            end

            -- Audio & Celebration Banner Dispatch
            ply:EmitSound("garrysmod/save_load1.wav", 70, 100)

            net.Start("GRID_OnboardingCompleted")
                net.WriteUInt(cleanBonus, 32)
            net.Send(ply)

            GRID.Notify(ply, string.format("[SYNDICATE VERIFIED] Initiation cleared! +$%s bonus deposited to bank! Promoted to Level 2!", string.Comma(cleanBonus)), NOTIFY_GENERIC, 8)
            GRID.Notify(ply, "Base building, Toolgun, Auction House listings, and advanced careers are now unlocked!", NOTIFY_HINT, 10)
        end)
    end

    return true
end

-- --------------------------------------------------------
-- Anti-Troll Level 2 Gates & Griefing Protection
-- --------------------------------------------------------
local function HandleGatedAttempt(ply, actionName)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsAdmin() then return end

    if ply:GetLevel() < 2 or ply:GetOnboardingStage() < GRID.Onboarding.STAGE_COMPLETED then
        ply:EmitSound("buttons/button10.wav", 60, 100)

        GRID.Notify(ply, "[SYNDICATE UNVERIFIED] The Fixer doesn't trust you yet! Complete your 60-second Alleyway Dead-Drop (marked on HUD) to earn your Grid Credentials, $3,500 cash, and a free 9mm Pistol!", NOTIFY_ERROR, 7)

        net.Start("GRID_OnboardingGatedAlert")
            net.WriteString(actionName or "This Action")
        net.Send(ply)

        return true -- Block action
    end

    return false
end

-- Gate 1: Prop & Entity Sandbox Spawning
hook.Add("PlayerSpawnProp", "GRID_Onboarding_GateProp", function(ply, model)
    if HandleGatedAttempt(ply, "Spawning Props") then return false end
end)

hook.Add("PlayerSpawnRagdoll", "GRID_Onboarding_GateRagdoll", function(ply, model)
    if HandleGatedAttempt(ply, "Spawning Ragdolls") then return false end
end)

hook.Add("PlayerSpawnVehicle", "GRID_Onboarding_GateVehicle", function(ply, model, name, table)
    if HandleGatedAttempt(ply, "Spawning Vehicles") then return false end
end)

hook.Add("PlayerSpawnEffect", "GRID_Onboarding_GateEffect", function(ply, model)
    if HandleGatedAttempt(ply, "Spawning Effects") then return false end
end)

-- Gate 2: Toolgun Usage
hook.Add("CanTool", "GRID_Onboarding_GateToolgun", function(ply, tr, toolname)
    if HandleGatedAttempt(ply, "Using Toolgun") then return false end
end)

-- Gate 3: Careers & Job Progression Gate
hook.Add("GRID_CanChangeJob", "GRID_Onboarding_GateJobs", function(ply, jobId)
    if not IsValid(ply) or ply:IsAdmin() then return end

    local highImpactJobs = {
        ["police_officer"]      = true,
        ["police_chief"]        = true,
        ["swat_specialist"]     = true,
        ["arms_dealer"]         = true,
        ["black_market_dealer"] = true
    }

    if highImpactJobs[jobId] then
        if ply:GetLevel() < 2 or ply:GetOnboardingStage() < GRID.Onboarding.STAGE_COMPLETED then
            HandleGatedAttempt(ply, "Joining Career")
            return false
        end
    end
end)

-- Gate 4: Auction House Listing Gate
hook.Add("GRID_CanCreateAuction", "GRID_Onboarding_GateAuctions", function(ply, item)
    if not IsValid(ply) or ply:IsAdmin() then return end

    if ply:GetLevel() < 2 or ply:GetOnboardingStage() < GRID.Onboarding.STAGE_COMPLETED then
        HandleGatedAttempt(ply, "Posting Auction Listings")
        return false
    end

    -- Block soulbound starter items
    if item and (item.GRID_IsStarterItem or (item.item_data and item.item_data.is_starter)) then
        GRID.Notify(ply, "Introductory syndicate starter items are Soulbound and cannot be auctioned!", NOTIFY_ERROR, 5)
        return false
    end
end)

-- Soulbound Drop Protection: Block dropping starter Glock-18
hook.Add("PlayerCanDropWeapon", "GRID_Onboarding_BlockDropStarter", function(ply, wep)
    if IsValid(wep) and wep.GRID_IsStarterItem then
        GRID.Notify(ply, "This starter firearm is Soulbound to your syndicate identity and cannot be dropped!", NOTIFY_ERROR, 4)
        return false
    end
end)

-- --------------------------------------------------------
-- Admin Testing & Diagnostics ConCommands
-- --------------------------------------------------------
concommand.Add("grid_onboarding_reset", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        GRID.Notify(ply, "Access Denied: SuperAdmin only.", NOTIFY_ERROR)
        return
    end

    local target = ply
    if args[1] and args[1] ~= "" then
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(args[1]), 1, true) or p:SteamID() == args[1] then
                target = p
                break
            end
        end
    end

    if not IsValid(target) then
        print("[GRID Onboarding] Target player not found.")
        return
    end

    target:SetOnboardingStage(GRID.Onboarding.STAGE_ROOKIE)
    target:SetNWInt("GRID_Money", 0)
    target:SetNWInt("GRID_Level", 1)
    target:SetNWInt("GRID_XP", 0)

    if GRID.Database and GRID.Database.SavePlayer then
        GRID.Database.SavePlayer(target)
    end

    net.Start("GRID_OnboardingSync")
        net.WriteUInt(GRID.Onboarding.STAGE_ROOKIE, 4)
    net.Send(target)

    local msg = string.format("[GRID Onboarding] Reset %s to Stage 0 (Rookie, Level 1, $0).", target:Nick())
    print(msg)
    if IsValid(ply) then
        GRID.Notify(ply, msg, NOTIFY_HINT, 5)
    end
end)

concommand.Add("grid_onboarding_setstage", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        GRID.Notify(ply, "Access Denied: SuperAdmin only.", NOTIFY_ERROR)
        return
    end

    local newStage = tonumber(args[1]) or 0
    newStage = math.Clamp(newStage, 0, 2)

    local target = ply
    if args[2] and args[2] ~= "" then
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(args[2]), 1, true) or p:SteamID() == args[2] then
                target = p
                break
            end
        end
    end

    if not IsValid(target) then
        print("[GRID Onboarding] Target player not found.")
        return
    end

    target:SetOnboardingStage(newStage)
    if newStage >= 2 and target:GetLevel() < 2 then
        target:SetNWInt("GRID_Level", 2)
    end

    if GRID.Database and GRID.Database.SavePlayer then
        GRID.Database.SavePlayer(target)
    end

    net.Start("GRID_OnboardingSync")
        net.WriteUInt(newStage, 4)
    net.Send(target)

    local msg = string.format("[GRID Onboarding] Set %s to Stage %d.", target:Nick(), newStage)
    print(msg)
    if IsValid(ply) then
        GRID.Notify(ply, msg, NOTIFY_HINT, 5)
    end
end)

-- --------------------------------------------------------
-- Map Profile & World Infrastructure Persistence (JSON & DB Backup)
-- --------------------------------------------------------
local ONBOARDING_DATA_DIR = "gridrp/onboarding"

local function GetOnboardingFilePath()
    local map = string.lower(game.GetMap())
    return ONBOARDING_DATA_DIR .. "/" .. map .. ".json"
end

local function GetOnboardingDBKey()
    return "onboarding_props_" .. string.lower(game.GetMap())
end

local ONBOARDING_CLASSES = {
    ["grid_deaddrop_locker"] = true,
    ["grid_practice_stash"]  = true,
    ["grid_atm"]             = true
}

--- Saves all world onboarding entities to disk and database
function GRID.Onboarding.SaveMapProfile()
    local records = {}
    for class, _ in pairs(ONBOARDING_CLASSES) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            if IsValid(ent) then
                local pos = ent:GetPos()
                local ang = ent:GetAngles()
                table.insert(records, {
                    class = class,
                    pos = { x = math.Round(pos.x, 2), y = math.Round(pos.y, 2), z = math.Round(pos.z, 2) },
                    ang = { p = math.Round(ang.p, 2), y = math.Round(ang.y, 2), r = math.Round(ang.r, 2) }
                })
            end
        end
    end

    local json = util.TableToJSON(records, true)

    -- 1. Primary DB persistence
    local dbKey = GetOnboardingDBKey()
    if GRID.Database and GRID.Database.SetSetting then
        GRID.Database.SetSetting(dbKey, json)
    end

    -- 2. File snapshot
    file.CreateDir(ONBOARDING_DATA_DIR)
    local filePath = GetOnboardingFilePath()
    file.Write(filePath, json)

    print(string.format("[GRID Onboarding] Saved %d onboarding props to Database ('%s') & JSON '%s'.", #records, dbKey, filePath))
    return true
end

--- Loads and spawns onboarding entities from JSON/Database if persistent map spawns did not load any
function GRID.Onboarding.LoadMapProfile()
    local existingCount = 0
    for class, _ in pairs(ONBOARDING_CLASSES) do
        existingCount = existingCount + #ents.FindByClass(class)
    end

    -- If entities already spawned (e.g. from v_grid_map_spawns), don't duplicate
    if existingCount > 0 then
        return
    end

    local dbKey = GetOnboardingDBKey()
    local filePath = GetOnboardingFilePath()
    local records = nil
    local loadSource = "none"

    if GRID.Database and GRID.Database.GetSetting then
        local raw = GRID.Database.GetSetting(dbKey)
        if raw and raw ~= "" then
            records = util.JSONToTable(raw)
            if records and #records > 0 then
                loadSource = "Database ('" .. dbKey .. "')"
            end
        end
    end

    if not records or #records == 0 then
        if file.Exists(filePath, "DATA") then
            local raw = file.Read(filePath, "DATA")
            records = util.JSONToTable(raw)
            if records and #records > 0 then
                loadSource = "JSON Snapshot ('" .. filePath .. "')"
            end
        end
    end

    if not records or #records == 0 then return end

    local count = 0
    for _, data in ipairs(records) do
        if data.class and data.pos and data.ang then
            local pos = Vector(data.pos.x, data.pos.y, data.pos.z)
            local ang = Angle(data.ang.p, data.ang.y, data.ang.r)
            local ent = ents.Create(data.class)
            if IsValid(ent) then
                ent:SetPos(pos)
                ent:SetAngles(ang)
                ent:Spawn()
                ent:Activate()

                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    phys:EnableMotion(false)
                    phys:Wake()
                end

                if GRID.MapSpawns and GRID.MapSpawns.ApplyWorldProtection then
                    GRID.MapSpawns.ApplyWorldProtection(ent)
                end

                count = count + 1
            end
        end
    end

    print(string.format("[GRID Onboarding] Successfully restored %d onboarding props from %s.", count, loadSource))
end

-- Auto-load hook after map and DB initialization
hook.Add("InitPostEntity", "GRID_Onboarding_InitPostEntity", function()
    timer.Simple(3.0, function()
        GRID.Onboarding.LoadMapProfile()
    end)
end)

hook.Add("PostCleanupMap", "GRID_Onboarding_PostCleanupMap", function()
    timer.Simple(1.0, function()
        GRID.Onboarding.LoadMapProfile()
    end)
end)

-- Admin helper concommands
concommand.Add("grid_onboarding_save", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        GRID.Notify(ply, "Access Denied: SuperAdmin only.", NOTIFY_ERROR)
        return
    end

    GRID.Onboarding.SaveMapProfile()
    if IsValid(ply) then
        GRID.Notify(ply, "Onboarding world props saved to Database & Map JSON Profile.", NOTIFY_GENERIC)
    end
end)

concommand.Add("grid_onboarding_respawn", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        GRID.Notify(ply, "Access Denied: SuperAdmin only.", NOTIFY_ERROR)
        return
    end

    GRID.Onboarding.LoadMapProfile()
    if IsValid(ply) then
        GRID.Notify(ply, "Restored onboarding world props from Database / JSON Profile.", NOTIFY_GENERIC)
    end
end)



