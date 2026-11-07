--[[
    GridRP (GRID) by Juicebox
    gamemode/init.lua - Server Gamemode Entry Point
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

-- Add Shared Files to Client
AddCSLuaFile("core/sh_config.lua")
AddCSLuaFile("core/sh_networking.lua")
AddCSLuaFile("core/sh_player_meta.lua")
AddCSLuaFile("core/sh_entity_meta.lua")
AddCSLuaFile("core/sh_notifications.lua")
AddCSLuaFile("buffs/sh_buffs.lua")
AddCSLuaFile("buffs/sh_buff_definitions.lua")
AddCSLuaFile("factions/sh_factions.lua")
AddCSLuaFile("turf/sh_turf.lua")
AddCSLuaFile("inventory/sh_inventory.lua")
AddCSLuaFile("crafting/sh_crafting.lua")
AddCSLuaFile("core/sh_scavenge_config.lua")
AddCSLuaFile("auction/sh_auction.lua")
AddCSLuaFile("mapspawns/sh_map_spawns.lua")
AddCSLuaFile("onboarding/sh_onboarding.lua")
AddCSLuaFile("onboarding/cl_onboarding.lua")

-- Add Client Files to Client
AddCSLuaFile("mapspawns/cl_map_spawns.lua")
AddCSLuaFile("auction/cl_auction.lua")
AddCSLuaFile("crafting/cl_crafting.lua")
AddCSLuaFile("buffs/cl_buffs.lua")
AddCSLuaFile("factions/cl_jobs.lua")
AddCSLuaFile("turf/cl_turf.lua")
AddCSLuaFile("turf/cl_turf_setup.lua")
AddCSLuaFile("economy/cl_economy.lua")
AddCSLuaFile("doors/cl_doors.lua")
AddCSLuaFile("inventory/cl_inventory.lua")
AddCSLuaFile("inventory/cl_bag.lua")
AddCSLuaFile("ui/cl_hud.lua")
AddCSLuaFile("ui/cl_f4menu.lua")
AddCSLuaFile("ui/cl_chatbox.lua")
AddCSLuaFile("ui/cl_scoreboard.lua")
AddCSLuaFile("ui/cl_deathscreen.lua")

-- Server Includes
include("shared.lua")
include("core/sh_networking.lua")
include("core/sv_db_config.lua")
include("core/sv_database.lua")
include("core/sv_telemetry.lua")
include("core/sv_net.lua")
include("buffs/sh_buffs.lua")
include("buffs/sh_buff_definitions.lua")
include("buffs/sv_buffs.lua")
include("factions/sv_jobs.lua")
include("factions/sv_gangs.lua")
include("turf/sv_turf.lua")
include("economy/sv_economy.lua")
include("economy/sv_vendors.lua")
include("doors/sv_doors.lua")
include("inventory/sh_inventory.lua")
include("inventory/sv_inventory.lua")
include("crafting/sh_crafting.lua")
include("crafting/sv_crafting.lua")
include("core/sv_population_balancer.lua")
include("core/sv_scavenge_spawner.lua")
include("core/sv_admin.lua")
include("auction/sh_auction.lua")
include("auction/sv_auction.lua")
include("mapspawns/sh_map_spawns.lua")
include("mapspawns/sv_map_spawns.lua")
include("onboarding/sh_onboarding.lua")
include("onboarding/sv_onboarding.lua")

function GM:Initialize()
    math.randomseed(os.time() + math.floor(SysTime() * 1000))
    for i = 1, 5 do math.random() end

    print("==================================================")
    print("           GridRP (by Juicebox)                      ")
    print("   Gamemode Loaded Successfully!                  ")
    print("==================================================")

    GRID.Database.Init()
    GRID.Turf.Init()
    GRID.Doors.Init()
    GRID.Economy.StartPaydayTimer()
end

function GM:PlayerInitialSpawn(ply)
    ply.GRID_DataLoaded = false
    GRID.Database.LoadPlayer(ply, function(data)
        local initialJob = (data and data.job and GRID.Jobs[data.job]) and data.job or "citizen"
        ply:SetJob(initialJob, true)
        GRID.Turf.SyncToPlayer(ply)
        GRID.Doors.SyncToPlayer(ply)

        timer.Simple(1, function()
            if IsValid(ply) then
                GRID.Notify(ply, "Welcome to GridRP! Press F4 to open the Store & Jobs.", NOTIFY_GENERIC, 8)
                GRID.Notify(ply, "Claim Turf Flag Poles for your gang to earn dividends!", NOTIFY_HINT, 10)
            end
        end)
    end)
end

function GM:PlayerDisconnected(ply)
    -- Flush pending combat skirmish buffer
    if GRID.Telemetry and GRID.Telemetry.FlushCombat then
        GRID.Telemetry.FlushCombat(ply)
    end

    -- Despawn active money-generating entities and job deployables on disconnect
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then
            local isOwner = (ent.GRID_Owner == ply) or (ent:GetNWEntity("GRID_Owner") == ply) or
            (ent.PurchaserSteamID == ply:SteamID())
            if isOwner then
                local c = ent:GetClass()
                if string.StartWith(c, "grid_printer_") or c == "grid_resource_machine" or c == "grid_clinic_pod" or c == "grid_computer" or c == "grid_shipment" or string.StartWith(c, "grid_network_switch") or ent.IsNetworkSwitch or c == "grid_wan_uplink" then
                    ent:Remove()
                end
            end
        end
    end

    -- Unown all session-based purchased doors
    if GRID.Doors and GRID.Doors.UnownAll then
        GRID.Doors.UnownAll(ply)
    end
    if GRID.Database and GRID.Database.SavePlayer then
        GRID.Database.SavePlayer(ply)
    end
end

function GM:ShutDown()
    for _, ply in ipairs(player.GetAll()) do
        if GRID.Database and GRID.Database.SavePlayer then
            GRID.Database.SavePlayer(ply)
        end
    end
    if GRID.Turf and GRID.Turf.SaveMapProfile then
        GRID.Turf.SaveMapProfile()
    end
    print("[GridRP] All player, gang, and turf records committed to SQLite.")
end

function GM:PlayerSpawn(ply)
    ply:UnSpectate()
    player_manager.SetPlayerClass(ply, "player_sandbox")

    local job = ply:GetJobData()
    if job then
        -- Set Player Model
        local mdl = job.models[math.random(#job.models)]
        ply:SetModel(mdl)

        -- Health & Armor
        ply:SetMaxHealth(job.maxHealth or 100)
        ply:SetHealth(job.maxHealth or 100)
        ply:SetArmor(job.armor or 0)

        -- Walk / Run Speeds
        ply:SetWalkSpeed(job.walkSpeed or 220)
        ply:SetRunSpeed(job.runSpeed or 320)

        -- Give Loadout
        ply:StripWeapons()
        ply:StripAmmo()

        -- Universal RP tools (Given to ALL jobs)
        ply:Give("weapon_fists")
        ply:Give("weapon_grid_keys")
        ply:Give("weapon_physgun")
        ply:Give("weapon_physcannon")
        ply:Give("gmod_tool")

        -- Job specific tools and weapons
        if job.weapons then
            for _, wep in ipairs(job.weapons) do
                ply:Give(wep)
            end
        end

        -- Only Police faction receives duty ammunition loadout on spawn
        if ply:IsPolice() then
            ply:GiveAmmo(120, "Pistol", true)
            ply:GiveAmmo(150, "SMG1", true)
            ply:GiveAmmo(120, "AR2", true)
            ply:GiveAmmo(40, "Buckshot", true)
            ply:GiveAmmo(36, "357", true)
        end
    end

    -- Setup viewmodel hands entity for c_ models and weapon_fists
    ply:SetupHands()
end

function GM:PlayerSetHandsModel(ply, ent)
    local info = player_manager.RunClass(ply, "GetHandsModel")
    if not info then
        local playermodel = player_manager.TranslateToPlayerModelName(ply:GetModel())
        info = player_manager.TranslatePlayerHands(playermodel)
    end

    if info and info.model then
        ent:SetModel(info.model)
        ent:SetSkin(info.matchBodySkin and ply:GetSkin() or (info.skin or 0))
        ent:SetBodyGroups(info.body or "0000000")
    else
        ent:SetModel("models/weapons/c_arms_citizen.mdl")
        ent:SetSkin(0)
        ent:SetBodyGroups("0000000")
    end
end

-- Ensure any existing spawned players receive their hands immediately on lua reload
for _, p in ipairs(player.GetAll()) do
    if IsValid(p) and not IsValid(p:GetHands()) then
        p:SetupHands()
    end
end

-- ========================================================
-- WEAPON PICKUP & PROGRAMMATIC GIVE CONTROL
-- ========================================================
local plyMeta = FindMetaTable("Player")
if plyMeta and not plyMeta.GRID_OldGive then
    plyMeta.GRID_OldGive = plyMeta.Give
    function plyMeta:Give(class, bNoAmmo)
        self.GRID_GivingWeapon = true
        local wep = self:GRID_OldGive(class, bNoAmmo)
        self.GRID_GivingWeapon = nil
        return wep
    end
end

function GM:PlayerCanPickupWeapon(ply, wep)
    if not IsValid(ply) or not IsValid(wep) then return false end

    -- Hobo Restriction: Hobos can only use building tools and hands
    if ply:GetJob() == "hobo" and not (GRID.HoboAllowedWeapons and GRID.HoboAllowedWeapons[wep:GetClass()]) then
        return false
    end

    -- Allow programmatic Give() calls (job spawn loadout, vendor purchase, inventory equip)
    if ply.GRID_GivingWeapon then
        return true
    end

    -- NEVER allow picking up world weapons as ammo if the player already has that weapon!
    if ply:HasWeapon(wep:GetClass()) then
        return false
    end

    -- Prevent automatic walk-over pickup of dropped or world weapons
    return false
end

function GM:PlayerSwitchWeapon(ply, oldWep, newWep)
    if GRID.Telemetry and GRID.Telemetry.FlushCombat and oldWep ~= newWep then
        GRID.Telemetry.FlushCombat(ply)
    end
    if not IsValid(ply) or not IsValid(newWep) then return end
    local class = newWep:GetClass()

    -- Hobo Restriction: Hobos can only wield building tools and hands
    if ply:GetJob() == "hobo" and not (GRID.HoboAllowedWeapons and GRID.HoboAllowedWeapons[class]) then
        GRID.Notify(ply, "Hobos can only use building tools and hands!", NOTIFY_ERROR)
        return true -- Blocks switching to this weapon
    end

    local def = GRID.Inventory and GRID.Inventory.GetItemData and GRID.Inventory.GetItemData(class)
    local reqLvl = (def and def.level) or (newWep.RequiredLevel or 1)
    if reqLvl > 1 and ply:GetLevel() < reqLvl and not newWep.GRID_IsStarterItem then
        GRID.Notify(ply, string.format("You must be Level %d to wield %s!", reqLvl, def and def.name or class),
            NOTIFY_ERROR)
        return true -- Blocks switching to this weapon
    end
end

function GM:PlayerDeath(victim, inflictor, attacker)
    -- Flush pending combat telemetry
    if GRID.Telemetry and GRID.Telemetry.FlushCombat then
        GRID.Telemetry.FlushCombat(victim)
        if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
            GRID.Telemetry.FlushCombat(attacker)
        end
    end

    -- Server-Authoritative Durability Shock Wear on Death
    local activeWep = victim:GetActiveWeapon()
    if IsValid(activeWep) and activeWep.GetDurability and activeWep.SetDurability then
        activeWep:SetDurability(math.max(0, activeWep:GetDurability() - 15))
    end

    -- Dynamic Anti-Inflation Resuscitation Fee (Hybrid Base + Total Net Worth %, auto-drafts from Bank if Wallet insufficient)
    if GRID.Economy and GRID.Economy.CalculateDynamicFee then
        local hospFee = GRID.Economy.CalculateDynamicFee(victim, GRID.Config.HospitalFeeBase or 50,
            GRID.Config.HospitalFeeWealthPct or 0.015)
        if hospFee > 0 then
            local paid, fromWallet, fromBank = false, 0, 0
            if GRID.Economy.DeductFeeWithBankFallback then
                paid, fromWallet, fromBank = GRID.Economy.DeductFeeWithBankFallback(victim, hospFee)
            elseif victim:CanAfford(hospFee) then
                victim:AddMoney(-hospFee)
                paid, fromWallet = true, hospFee
            end
            if paid then
                GRID.Notify(victim, string.format("Emergency Medical Resuscitation Fee: -$%d", hospFee), NOTIFY_ERROR)
                if GRID.Telemetry and GRID.Telemetry.Log then
                    GRID.Telemetry.Log("ECONOMY", "HOSPITAL_FEE", victim:SteamID(), "", hospFee, {
                        from_wallet = fromWallet,
                        from_bank = fromBank
                    })
                end
            end
        end
    end
    -- Rapid Dispatch: Patrol Officers respawn in 5s, baseline for all other roles is 30s
    local defaultSecs = (GRID.Config and GRID.Config.DefaultRespawnTime) or 30
    local policeSecs = (GRID.Config and GRID.Config.PoliceRespawnTime) or 5
    local respawnSecs = (victim:GetJob() == "police_officer") and policeSecs or defaultSecs
    victim.NextSpawnTime = CurTime() + respawnSecs

    local killerName = "Unknown"
    if IsValid(attacker) then
        if attacker == victim then
            killerName = "Suicide"
        elseif attacker:IsPlayer() then
            killerName = attacker:Nick()
        elseif attacker.GetClass then
            killerName = attacker:GetClass()
        end
    elseif IsValid(inflictor) then
        if inflictor == victim then
            killerName = "Suicide"
        elseif inflictor.GetClass then
            killerName = inflictor:GetClass()
        end
    else
        killerName = "Suicide"
    end

    net.Start("GRID_PlayerDied")
    net.WriteString(killerName)
    net.WriteUInt(respawnSecs, 8)
    net.Send(victim)

    -- Drop a small amount of cash on death (Protected during onboarding)
    local isRookie = (victim:GetNWInt("GRID_OnboardingStage", 0) < 3)
    local dropAmount = isRookie and 0 or math.min(GRID.Config.DropMoneyOnDeathMax or 75, math.floor(victim:GetMoney() * 0.1))
    if dropAmount > 0 then
        victim:AddMoney(-dropAmount)
        GRID.Economy.SpawnCashStack(victim:GetPos() + Vector(0, 0, 10), dropAmount)
    end

    -- Award Combat XP
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
        local xpReward = (GRID.Config and GRID.Config.Level and GRID.Config.Level.XP_PlayerKill) or 50
        local isRival = false
        local aGang = attacker:GetGang()
        local vGang = victim:GetGang()
        if aGang ~= "" and vGang ~= "" and string.lower(aGang) ~= string.lower(vGang) then
            isRival = true
            xpReward = xpReward + ((GRID.Config and GRID.Config.Level and GRID.Config.Level.XP_RivalGangKillBonus) or 50)
        end
        if attacker.AddXP then
            local reason = isRival and "Rival Gang Kill" or "Player Kill"
            attacker:AddXP(xpReward, reason)
        end

        -- Turf Defense Bonus: Eliminating police within your gang's territory
        local zone = GRID.Turf and GRID.Turf.GetZoneAtPos and GRID.Turf.GetZoneAtPos(victim:GetPos())
        if aGang ~= "" and zone and zone.owner and string.lower(zone.owner) == string.lower(aGang) and victim.IsPolice and victim:IsPolice() then
            attacker:AddMoney(100)
            if attacker.AddXP then
                attacker:AddXP(100, "Turf Defense: Incursion Repelled")
            end
            GRID.Notify(attacker,
                string.format("[TURF DEFENDER] +$100 & +100 XP for eliminating Police in %s!", zone.name), NOTIFY_GENERIC)
        end
    end
end

function GM:PlayerDeathThink(ply)
    if (ply.NextSpawnTime or 0) > CurTime() then
        return false
    end

    -- Respawn automatically once timer finishes, or immediately on click / jump
    if ply:KeyPressed(IN_ATTACK) or ply:KeyPressed(IN_ATTACK2) or ply:KeyPressed(IN_JUMP) or CurTime() >= (ply.NextSpawnTime or 0) then
        ply:Spawn()
        return true
    end

    return true
end

-- Hook F4 (gm_showspare2) and F2 (gm_showteam) from engine
function GM:ShowSpare2(ply)
    net.Start("GRID_ToggleF4Menu")
    net.Send(ply)
end

function GM:ShowTeam(ply)
    net.Start("GRID_ToggleF2Menu")
    net.Send(ply)
end
