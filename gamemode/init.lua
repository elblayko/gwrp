--[[
    GangWars RP (GWRP) by Toxic
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

-- Add Client Files to Client
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
include("core/sv_database.lua")
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
include("core/sv_admin.lua")

function GM:Initialize()
    print("==================================================")
    print("           GangWars RP (by Toxic)                 ")
    print("   Gamemode Loaded Successfully!                  ")
    print("==================================================")

    GWRP.Database.Init()
    GWRP.Turf.Init()
    GWRP.Doors.Init()
    GWRP.Economy.StartPaydayTimer()
end

function GM:PlayerInitialSpawn(ply)
    ply.GWRP_DataLoaded = false
    GWRP.Database.LoadPlayer(ply, function(data)
        local initialJob = (data and data.job and GWRP.Jobs[data.job]) and data.job or "citizen"
        ply:SetJob(initialJob, true)
        GWRP.Turf.SyncToPlayer(ply)
        GWRP.Doors.SyncToPlayer(ply)

        timer.Simple(1, function()
            if IsValid(ply) then
                GWRP.Notify(ply, "Welcome to GangWars RP! Press F4 to open the Store & Jobs.", NOTIFY_GENERIC, 8)
                GWRP.Notify(ply, "Claim Turf Flag Poles for your gang to earn dividends!", NOTIFY_HINT, 10)
            end
        end)
    end)
end

function GM:PlayerDisconnected(ply)
    if GWRP.Database and GWRP.Database.SavePlayer then
        GWRP.Database.SavePlayer(ply)
    end
end

function GM:ShutDown()
    for _, ply in ipairs(player.GetAll()) do
        if GWRP.Database and GWRP.Database.SavePlayer then
            GWRP.Database.SavePlayer(ply)
        end
    end
    if GWRP.Turf and GWRP.Turf.SaveMapProfile then
        GWRP.Turf.SaveMapProfile()
    end
    print("[GWRP] All player, gang, and turf records committed to SQLite.")
end

function GM:PlayerSpawn(ply)
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
        ply:Give("weapon_gwrp_keys")
        ply:Give("weapon_physgun")
        ply:Give("weapon_physcannon")
        ply:Give("gmod_tool")
        ply:Give("weapon_gwrp_remover")

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
end

-- ========================================================
-- WEAPON PICKUP & PROGRAMMATIC GIVE CONTROL
-- ========================================================
local plyMeta = FindMetaTable("Player")
if plyMeta and not plyMeta.GWRP_OldGive then
    plyMeta.GWRP_OldGive = plyMeta.Give
    function plyMeta:Give(class, bNoAmmo)
        self.GWRP_GivingWeapon = true
        local wep = self:GWRP_OldGive(class, bNoAmmo)
        self.GWRP_GivingWeapon = nil
        return wep
    end
end

function GM:PlayerCanPickupWeapon(ply, wep)
    if not IsValid(ply) or not IsValid(wep) then return false end

    -- Allow programmatic Give() calls (job spawn loadout, vendor purchase, inventory equip)
    if ply.GWRP_GivingWeapon then
        return true
    end

    -- NEVER allow picking up world weapons as ammo if the player already has that weapon!
    -- This prevents Source engine from turning dropped/shipment guns into reserve ammo.
    if ply:HasWeapon(wep:GetClass()) then
        return false
    end

    -- Prevent automatic walk-over pickup of dropped or world weapons;
    -- weapons should be deliberately picked up via +USE (E key) or Hands into inventory
    return false
end

function GM:PlayerSwitchWeapon(ply, oldWep, newWep)
    if not IsValid(ply) or not IsValid(newWep) then return end
    local class = newWep:GetClass()
    local def = GWRP.Inventory and GWRP.Inventory.GetItemData and GWRP.Inventory.GetItemData(class)
    local reqLvl = (def and def.level) or (newWep.RequiredLevel or 1)
    if reqLvl > 1 and ply:GetLevel() < reqLvl then
        GWRP.Notify(ply, string.format("You must be Level %d to wield %s!", reqLvl, def and def.name or class), NOTIFY_ERROR)
        return true -- Blocks switching to this weapon
    end
end

function GM:PlayerDeath(victim, inflictor, attacker)
    -- Rapid Dispatch: Patrol Officers respawn in 3s, other roles in 5s
    local respawnSecs = (victim:GetJob() == "police_officer") and 3 or 5
    victim.NextSpawnTime = CurTime() + respawnSecs

    net.Start("GWRP_PlayerDied")
        net.WriteUInt(respawnSecs, 8)
    net.Send(victim)

    -- Drop a small amount of cash on death
    local dropAmount = math.min(GWRP.Config.DropMoneyOnDeathMax or 75, math.floor(victim:GetMoney() * 0.1))
    if dropAmount > 0 then
        victim:AddMoney(-dropAmount)
        GWRP.Economy.SpawnCashStack(victim:GetPos() + Vector(0, 0, 10), dropAmount)
    end

    -- Award Combat XP
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
        local xpReward = (GWRP.Config and GWRP.Config.Level and GWRP.Config.Level.XP_PlayerKill) or 50
        local isRival = false
        local aGang = attacker:GetGang()
        local vGang = victim:GetGang()
        if aGang ~= "" and vGang ~= "" and string.lower(aGang) ~= string.lower(vGang) then
            isRival = true
            xpReward = xpReward + ((GWRP.Config and GWRP.Config.Level and GWRP.Config.Level.XP_RivalGangKillBonus) or 50)
        end
        if attacker.AddXP then
            local reason = isRival and "Rival Gang Kill" or "Player Kill"
            attacker:AddXP(xpReward, reason)
        end
    end
end

function GM:PlayerDeathThink(ply)
    if (ply.NextSpawnTime or 0) > CurTime() then
        return false
    end
    return true
end

-- Hook F4 (gm_showspare2) and F2 (gm_showteam) from engine
function GM:ShowSpare2(ply)
    net.Start("GWRP_ToggleF4Menu")
    net.Send(ply)
end

function GM:ShowTeam(ply)
    net.Start("GWRP_ToggleF2Menu")
    net.Send(ply)
end
