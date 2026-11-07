--[[
    sv_admin.lua - Server-Side Admin & Debug Executive Controller
    Author: Juicebox
--]]

GRID = GRID or {}
GRID.Admin = GRID.Admin or {}

local function IsAdminUser(ply)
    return IsValid(ply) and (ply:IsAdmin() or ply:IsSuperAdmin())
end

-- ========================================================
-- NETWORK RECEIVER FOR ADMIN ACTIONS
-- ========================================================

local function HandleAdminDebugAction(len, ply)
    if not IsAdminUser(ply) then return end
    if not GRID.CheckRateLimit(ply, "admin_action", 10) then return end

    local action = net.ReadString()

    -- 1. Economy & Money Debug
    if action == "set_money" then
        local target = net.ReadEntity()
        local amount = math.max(0, net.ReadInt(32))
        if IsValid(target) and target:IsPlayer() then
            target:SetMoney(amount)
            GRID.Notify(ply, string.format("Set %s's wallet to $%s.", target:Nick(), string.Comma(amount)),
                NOTIFY_GENERIC)
            GRID.Notify(target, string.format("An administrator set your wallet to $%s.", string.Comma(amount)),
                NOTIFY_HINT)
        end
    elseif action == "add_money" then
        local target = net.ReadEntity()
        local amount = net.ReadInt(32)
        if IsValid(target) and target:IsPlayer() then
            target:AddMoney(amount)
            GRID.Notify(ply, string.format("Gave $%s to %s.", string.Comma(amount), target:Nick()), NOTIFY_GENERIC)
            GRID.Notify(target, string.format("Received $%s from an administrator.", string.Comma(amount)), NOTIFY_HINT)
        end

        -- Leveling & Progression Debug
    elseif action == "set_level" then
        local target = net.ReadEntity()
        local lvl = net.ReadInt(16)
        if IsValid(target) and target:IsPlayer() and target.SetLevel then
            target:SetLevel(lvl)
            GRID.Notify(ply, string.format("Set %s's level to %d.", target:Nick(), target:GetLevel()), NOTIFY_GENERIC)
            GRID.Notify(target, string.format("An administrator set your level to %d.", target:GetLevel()), NOTIFY_HINT)
        end
    elseif action == "add_xp" then
        local target = net.ReadEntity()
        local xpAmount = net.ReadInt(32)
        if IsValid(target) and target:IsPlayer() and target.AddXP then
            target:AddXP(xpAmount, "Admin Grant")
            GRID.Notify(ply, string.format("Awarded %s XP to %s.", string.Comma(xpAmount), target:Nick()), NOTIFY_GENERIC)
        end

    -- Full Profile & Progression Database Reset
    elseif action == "reset_player" then
        local target = net.ReadEntity()
        if not ply:IsSuperAdmin() then
            GRID.Notify(ply, "Access Denied: Only SuperAdmins can fully reset a player profile.", NOTIFY_ERROR)
            return
        end

        if IsValid(target) and target:IsPlayer() then
            local targetSid = target:SteamID()
            local targetNick = target:Nick()

            if GRID.Database and GRID.Database.ResetPlayer then
                GRID.Database.ResetPlayer(targetSid, function()
                    if IsValid(target) then
                        -- Live memory state reset
                        target:SetMoney(0)
                        if target.SetBank then target:SetBank(0) end
                        target:SetNWInt("GRID_Respect", 0)
                        target:SetGang("")
                        target:SetJob("citizen")
                        if target.SetLevel then target:SetLevel(1) end
                        if target.SetXP then target:SetXP(0) end
                        if target.SetOnboardingStage then target:SetOnboardingStage(0) end
                        target:SetNWInt("GRID_OnboardingStage", 0)

                        -- Strip inventory and weapons
                        if target.ClearInventory then target:ClearInventory() end
                        if target.Bags then target.Bags = {} end
                        target:StripWeapons()
                        target:StripAmmo()
                        target:Spawn()

                        GRID.Notify(target, "[ADMIN RESET] Your character profile, progression, and inventory have been reset to Level 1 Rookie.", NOTIFY_ERROR, 10)
                    end

                    GRID.Notify(ply, string.format("Successfully executed full database profile reset for %s (%s).", targetNick, targetSid), NOTIFY_HINT, 6)
                    print(string.format("[GRID Admin] SuperAdmin %s executed full profile reset on %s (%s).", ply:Nick(), targetNick, targetSid))
                end, function(err)
                    GRID.Notify(ply, "Database Error: Failed to reset player profile! See server console.", NOTIFY_ERROR)
                end)
            end
        end

        -- 2. Role & Faction Debug
    elseif action == "set_job" then
        local target = net.ReadEntity()
        local jobId = net.ReadString()
        if IsValid(target) and target:IsPlayer() and GRID.Jobs and GRID.Jobs[jobId] then
            target:SetJob(jobId, true)
            GRID.Notify(ply, string.format("Forced %s to role: %s.", target:Nick(), GRID.Jobs[jobId].name),
                NOTIFY_GENERIC)
        end
    elseif action == "set_gang" then
        local target = net.ReadEntity()
        local gangName = net.ReadString()
        if IsValid(target) and target:IsPlayer() then
            target:SetGang(gangName)
            if gangName ~= "" and GRID.Database and GRID.Database.AddGangMember then
                GRID.Database.AddGangMember(target:SteamID(), gangName, "member")
            elseif gangName == "" and GRID.Database and GRID.Database.RemoveGangMember then
                GRID.Database.RemoveGangMember(target:SteamID())
            end
            GRID.Notify(ply,
                string.format("Updated %s's gang to '%s'.", target:Nick(), gangName ~= "" and gangName or "None"),
                NOTIFY_GENERIC)
        end

        -- 3. Vitals & Combat Debug
    elseif action == "set_health" then
        local target = net.ReadEntity()
        local hp = math.Clamp(net.ReadInt(32), 1, 99999)
        if IsValid(target) and target:IsPlayer() then
            target:SetHealth(hp)
            GRID.Notify(ply, string.format("Set %s's health to %d.", target:Nick(), hp), NOTIFY_GENERIC)
        end
    elseif action == "set_armor" then
        local target = net.ReadEntity()
        local armor = math.Clamp(net.ReadInt(32), 0, 500)
        if IsValid(target) and target:IsPlayer() then
            target:SetArmor(armor)
            GRID.Notify(ply, string.format("Set %s's armor to %d.", target:Nick(), armor), NOTIFY_GENERIC)
        end
    elseif action == "godmode" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() then
            target.GRID_HasGod = not target.GRID_HasGod
            if target.GRID_HasGod then
                target:GodEnable()
                GRID.Notify(ply, "Godmode ENABLED for " .. target:Nick(), NOTIFY_GENERIC)
            else
                target:GodDisable()
                GRID.Notify(ply, "Godmode DISABLED for " .. target:Nick(), NOTIFY_GENERIC)
            end
        end

        -- 4. Teleportation & Movement
    elseif action == "goto" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() and target ~= ply then
            ply:SetPos(target:GetPos() + Vector(0, 45, 5))
            GRID.Notify(ply, "Teleported to " .. target:Nick(), NOTIFY_GENERIC)
        end
    elseif action == "bring" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() and target ~= ply then
            target:SetPos(ply:GetPos() + Vector(0, 45, 5))
            GRID.Notify(ply, "Brought " .. target:Nick() .. " to your position.", NOTIFY_GENERIC)
        end
    elseif action == "respawn" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() then
            target:Spawn()
            GRID.Notify(ply, "Respawned " .. target:Nick(), NOTIFY_GENERIC)
        end

        -- 5. Game Loop & Economy Simulation Debug
    elseif action == "trigger_payday" then
        for _, p in ipairs(player.GetAll()) do
            local job = p:GetJobData()
            if job and job.salary > 0 then
                p:AddMoney(job.salary)
                GRID.Notify(p, string.format("Salary received: +$%d", job.salary), NOTIFY_GENERIC)
            end
        end
        GRID.Notify(ply, "Simulated instant server-wide Payday cycle.", NOTIFY_GENERIC)
    elseif action == "trigger_dividends" then
        if GRID.Turf and GRID.Turf.DistributeDividends then
            GRID.Turf.DistributeDividends()
            GRID.Notify(ply, "Simulated instant turf dividend distribution.", NOTIFY_GENERIC)
        end

        -- 6. Entity Spawning & Persistence Debug
    elseif action == "spawn_entity" then
        local class = net.ReadString()
        local tr = ply:GetEyeTrace()
        local spawnPos = tr.HitPos + Vector(0, 0, 15)

        if class == "grid_cash_stack" then
            GRID.Economy.SpawnCashStack(spawnPos, 10000)
            GRID.Notify(ply, "Spawned $10,000 cash stack at crosshair.", NOTIFY_GENERIC)
        elseif string.StartWith(class, "grid_scavenge_") or class == "grid_recycler_depot" then
            local ang = Angle(0, ply:EyeAngles().y + 180, 0)
            local ent = (GRID.Scavenge and GRID.Scavenge.SpawnNode) and
                GRID.Scavenge.SpawnNode(class, tr.HitPos, ang, true)
            if IsValid(ent) then
                if GRID.Scavenge and GRID.Scavenge.SaveMapProfile then
                    GRID.Scavenge.SaveMapProfile()
                end
                GRID.Notify(ply,
                    string.format("Spawned %s and persisted to Database & Map JSON Profile.", ent.PrintName or class),
                    NOTIFY_GENERIC)
            end
        else
            local ent = ents.Create(class)
            if IsValid(ent) then
                ent:SetPos(spawnPos)
                ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
                if ent.SetOwnerPlayer then ent:SetOwnerPlayer(ply) end
                ent:Spawn()
                ent:Activate()
                GRID.Notify(ply, "Spawned " .. class .. " at crosshair.", NOTIFY_GENERIC)
            end
        end
    elseif action == "save_scavenge_profile" then
        if GRID.Scavenge and GRID.Scavenge.SaveMapProfile then
            GRID.Scavenge.SaveMapProfile()
            GRID.Notify(ply, "Persisted all scavenge nodes & depots to Database and JSON Profile.", NOTIFY_GENERIC)
        end
    elseif action == "clear_scavenge_profile" then
        if GRID.Scavenge and GRID.Scavenge.ClearSpawned then
            GRID.Scavenge.ClearSpawned()
            if GRID.Scavenge.SaveMapProfile then
                GRID.Scavenge.SaveMapProfile()
            end
            GRID.Notify(ply, "Cleared all scavenge nodes & depots from map and database.", NOTIFY_HINT)
        end
    elseif action == "respawn_scavenge_profile" then
        if GRID.Scavenge and GRID.Scavenge.LoadAndSpawn then
            GRID.Scavenge.LoadAndSpawn()
            GRID.Notify(ply, "Reloaded all scavenge nodes & depots from Database & JSON Profile.", NOTIFY_GENERIC)
        end
    end
end

net.Receive("GRID_AdminDebugAction", HandleAdminDebugAction)

-- ========================================================
-- CONSOLE & CHAT COMMANDS
-- ========================================================

local function OpenAdminHUD(ply)
    if not IsAdminUser(ply) then
        GRID.Notify(ply, "You must be an administrator to access the Admin HUD!", NOTIFY_ERROR)
        return
    end
    net.Start("GRID_OpenAdminMenu")
    net.Send(ply)
end

concommand.Add("grid_admin", OpenAdminHUD)
concommand.Add("admin", OpenAdminHUD)
concommand.Add("debug", OpenAdminHUD)

-- Chat commands: /admin, /debug, /setmoney <target> <amount>, /setjob <target> <job>
hook.Add("PlayerSay", "GRID_AdminChatCommands", function(ply, text)
    local trimmed = string.Trim(text)
    local args = string.Explode(" ", trimmed)
    local cmd = string.lower(args[1] or "")

    if cmd == "/admin" or cmd == "!admin" or cmd == "/debug" or cmd == "!debug" then
        OpenAdminHUD(ply)
        return ""
    end

    if cmd == "/setmoney" then
        if not IsAdminUser(ply) then return "" end
        local targetName = args[2]
        local amount = tonumber(args[3])
        if not targetName or not amount then
            GRID.Notify(ply, "Usage: /setmoney <player_name> <amount>", NOTIFY_ERROR)
            return ""
        end

        local target = nil
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(targetName), 1, true) then
                target = p
                break
            end
        end

        if not IsValid(target) then
            GRID.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        amount = math.max(0, math.floor(amount))
        target:SetMoney(amount)
        GRID.Notify(ply, string.format("Set %s's wallet to $%s.", target:Nick(), string.Comma(amount)), NOTIFY_GENERIC)
        GRID.Notify(target, string.format("An administrator set your wallet to $%s.", string.Comma(amount)), NOTIFY_HINT)
        return ""
    end

    if cmd == "/addmoney" then
        if not IsAdminUser(ply) then return "" end
        local targetName = args[2]
        local amount = tonumber(args[3])
        if not targetName or not amount then
            GRID.Notify(ply, "Usage: /addmoney <player_name> <amount>", NOTIFY_ERROR)
            return ""
        end

        local target = nil
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(targetName), 1, true) then
                target = p
                break
            end
        end

        if not IsValid(target) then
            GRID.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        target:AddMoney(math.floor(amount))
        GRID.Notify(ply, string.format("Gave $%s to %s.", string.Comma(math.floor(amount)), target:Nick()),
            NOTIFY_GENERIC)
        return ""
    end

    if cmd == "/setlevel" then
        if not IsAdminUser(ply) then return "" end
        local targetName = args[2]
        local lvl = tonumber(args[3])
        if not targetName or not lvl then
            GRID.Notify(ply, "Usage: /setlevel <player_name> <level>", NOTIFY_ERROR)
            return ""
        end

        local target = nil
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(targetName), 1, true) then
                target = p
                break
            end
        end

        if not IsValid(target) then
            GRID.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        target:SetLevel(lvl)
        GRID.Notify(ply, string.format("Set %s's level to %d.", target:Nick(), target:GetLevel()), NOTIFY_GENERIC)
        GRID.Notify(target, string.format("An administrator set your level to %d.", target:GetLevel()), NOTIFY_HINT)
        return ""
    end

    if cmd == "/addxp" then
        if not IsAdminUser(ply) then return "" end
        local targetName = args[2]
        local xp = tonumber(args[3])
        if not targetName or not xp then
            GRID.Notify(ply, "Usage: /addxp <player_name> <amount>", NOTIFY_ERROR)
            return ""
        end

        local target = nil
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(targetName), 1, true) then
                target = p
                break
            end
        end

        if not IsValid(target) then
            GRID.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        target:AddXP(math.floor(xp), "Admin Grant")
        GRID.Notify(ply, string.format("Awarded %s XP to %s.", string.Comma(math.floor(xp)), target:Nick()),
            NOTIFY_GENERIC)
        return ""
    end
end)

-- Console Admin Commands
local function SetLevelConCmd(ply, cmd, args)
    if IsValid(ply) and not IsAdminUser(ply) then return end
    local targetNick = args[1]
    local lvl = tonumber(args[2])
    if not targetNick or not lvl then
        print("[GridRP-Admin] Usage: grid_setlevel <name> <level>")
        return
    end
    for _, p in ipairs(player.GetAll()) do
        if string.find(string.lower(p:Nick()), string.lower(targetNick), 1, true) then
            p:SetLevel(lvl)
            print(string.format("[GridRP-Admin] Set %s level to %d.", p:Nick(), p:GetLevel()))
            return
        end
    end
    print("[GridRP-Admin] Player not found.")
end

local function AddXPConCmd(ply, cmd, args)
    if IsValid(ply) and not IsAdminUser(ply) then return end
    local targetNick = args[1]
    local xp = tonumber(args[2])
    if not targetNick or not xp then
        print("[GridRP-Admin] Usage: grid_addxp <name> <amount>")
        return
    end
    for _, p in ipairs(player.GetAll()) do
        if string.find(string.lower(p:Nick()), string.lower(targetNick), 1, true) then
            p:AddXP(xp, "Console Grant")
            print(string.format("[GridRP-Admin] Awarded %d XP to %s.", xp, p:Nick()))
            return
        end
    end
    print("[GridRP-Admin] Player not found.")
end

concommand.Add("grid_setlevel", SetLevelConCmd)
concommand.Add("grid_addxp", AddXPConCmd)
