--[[
    sv_admin.lua - Server-Side Admin & Debug Executive Controller
    Author: Toxic
--]]

GWRP.Admin = GWRP.Admin or {}

local function IsAdminUser(ply)
    return IsValid(ply) and (ply:IsAdmin() or ply:IsSuperAdmin())
end

-- ========================================================
-- NETWORK RECEIVER FOR ADMIN ACTIONS
-- ========================================================

net.Receive("GWRP_AdminDebugAction", function(len, ply)
    if not IsAdminUser(ply) then return end
    if not GWRP.CheckRateLimit(ply, "admin_action", 10) then return end

    local action = net.ReadString()

    -- 1. Economy & Money Debug
    if action == "set_money" then
        local target = net.ReadEntity()
        local amount = math.max(0, net.ReadInt(32))
        if IsValid(target) and target:IsPlayer() then
            target:SetMoney(amount)
            GWRP.Notify(ply, string.format("Set %s's wallet to $%s.", target:Nick(), string.Comma(amount)), NOTIFY_GENERIC)
            GWRP.Notify(target, string.format("An administrator set your wallet to $%s.", string.Comma(amount)), NOTIFY_HINT)
        end

    elseif action == "add_money" then
        local target = net.ReadEntity()
        local amount = net.ReadInt(32)
        if IsValid(target) and target:IsPlayer() then
            target:AddMoney(amount)
            GWRP.Notify(ply, string.format("Gave $%s to %s.", string.Comma(amount), target:Nick()), NOTIFY_GENERIC)
            GWRP.Notify(target, string.format("Received $%s from an administrator.", string.Comma(amount)), NOTIFY_HINT)
        end

    -- Leveling & Progression Debug
    elseif action == "set_level" then
        local target = net.ReadEntity()
        local lvl = net.ReadInt(16)
        if IsValid(target) and target:IsPlayer() and target.SetLevel then
            target:SetLevel(lvl)
            GWRP.Notify(ply, string.format("Set %s's level to %d.", target:Nick(), target:GetLevel()), NOTIFY_GENERIC)
            GWRP.Notify(target, string.format("An administrator set your level to %d.", target:GetLevel()), NOTIFY_HINT)
        end

    elseif action == "add_xp" then
        local target = net.ReadEntity()
        local xpAmount = net.ReadInt(32)
        if IsValid(target) and target:IsPlayer() and target.AddXP then
            target:AddXP(xpAmount, "Admin Grant")
            GWRP.Notify(ply, string.format("Awarded %s XP to %s.", string.Comma(xpAmount), target:Nick()), NOTIFY_GENERIC)
        end

    -- 2. Role & Faction Debug
    elseif action == "set_job" then
        local target = net.ReadEntity()
        local jobId = net.ReadString()
        if IsValid(target) and target:IsPlayer() and GWRP.Jobs[jobId] then
            target:SetJob(jobId, true)
            GWRP.Notify(ply, string.format("Forced %s to role: %s.", target:Nick(), GWRP.Jobs[jobId].name), NOTIFY_GENERIC)
        end

    elseif action == "set_gang" then
        local target = net.ReadEntity()
        local gangName = net.ReadString()
        if IsValid(target) and target:IsPlayer() then
            target:SetGang(gangName)
            if gangName ~= "" and GWRP.Database and GWRP.Database.AddGangMember then
                GWRP.Database.AddGangMember(target:SteamID(), gangName, "member")
            elseif gangName == "" and GWRP.Database and GWRP.Database.RemoveGangMember then
                GWRP.Database.RemoveGangMember(target:SteamID())
            end
            GWRP.Notify(ply, string.format("Updated %s's gang to '%s'.", target:Nick(), gangName ~= "" and gangName or "None"), NOTIFY_GENERIC)
        end

    -- 3. Vitals & Combat Debug
    elseif action == "set_health" then
        local target = net.ReadEntity()
        local hp = math.Clamp(net.ReadInt(32), 1, 99999)
        if IsValid(target) and target:IsPlayer() then
            target:SetHealth(hp)
            GWRP.Notify(ply, string.format("Set %s's health to %d.", target:Nick(), hp), NOTIFY_GENERIC)
        end

    elseif action == "set_armor" then
        local target = net.ReadEntity()
        local armor = math.Clamp(net.ReadInt(32), 0, 500)
        if IsValid(target) and target:IsPlayer() then
            target:SetArmor(armor)
            GWRP.Notify(ply, string.format("Set %s's armor to %d.", target:Nick(), armor), NOTIFY_GENERIC)
        end

    elseif action == "godmode" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() then
            target.GWRP_HasGod = not target.GWRP_HasGod
            if target.GWRP_HasGod then
                target:GodEnable()
                GWRP.Notify(ply, "Godmode ENABLED for " .. target:Nick(), NOTIFY_GENERIC)
            else
                target:GodDisable()
                GWRP.Notify(ply, "Godmode DISABLED for " .. target:Nick(), NOTIFY_GENERIC)
            end
        end

    -- 4. Teleportation & Movement
    elseif action == "goto" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() and target ~= ply then
            ply:SetPos(target:GetPos() + Vector(0, 45, 5))
            GWRP.Notify(ply, "Teleported to " .. target:Nick(), NOTIFY_GENERIC)
        end

    elseif action == "bring" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() and target ~= ply then
            target:SetPos(ply:GetPos() + Vector(0, 45, 5))
            GWRP.Notify(ply, "Brought " .. target:Nick() .. " to your position.", NOTIFY_GENERIC)
        end

    elseif action == "respawn" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() then
            target:Spawn()
            GWRP.Notify(ply, "Respawned " .. target:Nick(), NOTIFY_GENERIC)
        end

    -- 5. Game Loop & Economy Simulation Debug
    elseif action == "trigger_payday" then
        for _, p in ipairs(player.GetAll()) do
            local job = p:GetJobData()
            if job and job.salary > 0 then
                p:AddMoney(job.salary)
                GWRP.Notify(p, string.format("Salary received: +$%d", job.salary), NOTIFY_GENERIC)
            end
        end
        GWRP.Notify(ply, "Simulated instant server-wide Payday cycle.", NOTIFY_GENERIC)

    elseif action == "trigger_dividends" then
        if GWRP.Turf and GWRP.Turf.DistributeDividends then
            GWRP.Turf.DistributeDividends()
            GWRP.Notify(ply, "Simulated instant turf dividend distribution.", NOTIFY_GENERIC)
        end

    -- 6. Entity Spawning Debug
    elseif action == "spawn_entity" then
        local class = net.ReadString()
        local tr = ply:GetEyeTrace()
        local spawnPos = tr.HitPos + Vector(0, 0, 15)

        if class == "gwrp_cash_stack" then
            GWRP.Economy.SpawnCashStack(spawnPos, 10000)
            GWRP.Notify(ply, "Spawned $10,000 cash stack at crosshair.", NOTIFY_GENERIC)
        else
            local ent = ents.Create(class)
            if IsValid(ent) then
                ent:SetPos(spawnPos)
                ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
                if ent.SetOwnerPlayer then ent:SetOwnerPlayer(ply) end
                ent:Spawn()
                ent:Activate()
                GWRP.Notify(ply, "Spawned " .. class .. " at crosshair.", NOTIFY_GENERIC)
            end
        end
    end
end)

-- ========================================================
-- CONSOLE & CHAT COMMANDS
-- ========================================================

local function OpenAdminHUD(ply)
    if not IsAdminUser(ply) then
        GWRP.Notify(ply, "You must be an administrator to access the Admin HUD!", NOTIFY_ERROR)
        return
    end
    net.Start("GWRP_OpenAdminMenu")
    net.Send(ply)
end

concommand.Add("gwrp_admin", OpenAdminHUD)
concommand.Add("admin", OpenAdminHUD)
concommand.Add("debug", OpenAdminHUD)

-- Chat commands: /admin, /debug, /setmoney <target> <amount>, /setjob <target> <job>
hook.Add("PlayerSay", "GWRP_AdminChatCommands", function(ply, text)
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
            GWRP.Notify(ply, "Usage: /setmoney <player_name> <amount>", NOTIFY_ERROR)
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
            GWRP.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        amount = math.max(0, math.floor(amount))
        target:SetMoney(amount)
        GWRP.Notify(ply, string.format("Set %s's wallet to $%s.", target:Nick(), string.Comma(amount)), NOTIFY_GENERIC)
        GWRP.Notify(target, string.format("An administrator set your wallet to $%s.", string.Comma(amount)), NOTIFY_HINT)
        return ""
    end

    if cmd == "/addmoney" then
        if not IsAdminUser(ply) then return "" end
        local targetName = args[2]
        local amount = tonumber(args[3])
        if not targetName or not amount then
            GWRP.Notify(ply, "Usage: /addmoney <player_name> <amount>", NOTIFY_ERROR)
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
            GWRP.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        target:AddMoney(math.floor(amount))
        GWRP.Notify(ply, string.format("Gave $%s to %s.", string.Comma(math.floor(amount)), target:Nick()), NOTIFY_GENERIC)
        return ""
    end

    if cmd == "/setlevel" then
        if not IsAdminUser(ply) then return "" end
        local targetName = args[2]
        local lvl = tonumber(args[3])
        if not targetName or not lvl then
            GWRP.Notify(ply, "Usage: /setlevel <player_name> <level>", NOTIFY_ERROR)
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
            GWRP.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        target:SetLevel(lvl)
        GWRP.Notify(ply, string.format("Set %s's level to %d.", target:Nick(), target:GetLevel()), NOTIFY_GENERIC)
        GWRP.Notify(target, string.format("An administrator set your level to %d.", target:GetLevel()), NOTIFY_HINT)
        return ""
    end

    if cmd == "/addxp" then
        if not IsAdminUser(ply) then return "" end
        local targetName = args[2]
        local xp = tonumber(args[3])
        if not targetName or not xp then
            GWRP.Notify(ply, "Usage: /addxp <player_name> <amount>", NOTIFY_ERROR)
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
            GWRP.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        target:AddXP(math.floor(xp), "Admin Grant")
        GWRP.Notify(ply, string.format("Awarded %s XP to %s.", string.Comma(math.floor(xp)), target:Nick()), NOTIFY_GENERIC)
        return ""
    end
end)

-- Console Admin Commands
concommand.Add("gwrp_setlevel", function(ply, cmd, args)
    if IsValid(ply) and not IsAdminUser(ply) then return end
    local targetNick = args[1]
    local lvl = tonumber(args[2])
    if not targetNick or not lvl then
        print("[GWRP-Admin] Usage: gwrp_setlevel <name> <level>")
        return
    end
    for _, p in ipairs(player.GetAll()) do
        if string.find(string.lower(p:Nick()), string.lower(targetNick), 1, true) then
            p:SetLevel(lvl)
            print(string.format("[GWRP-Admin] Set %s level to %d.", p:Nick(), p:GetLevel()))
            return
        end
    end
    print("[GWRP-Admin] Player not found.")
end)

concommand.Add("gwrp_addxp", function(ply, cmd, args)
    if IsValid(ply) and not IsAdminUser(ply) then return end
    local targetNick = args[1]
    local xp = tonumber(args[2])
    if not targetNick or not xp then
        print("[GWRP-Admin] Usage: gwrp_addxp <name> <amount>")
        return
    end
    for _, p in ipairs(player.GetAll()) do
        if string.find(string.lower(p:Nick()), string.lower(targetNick), 1, true) then
            p:AddXP(xp, "Console Grant")
            print(string.format("[GWRP-Admin] Awarded %d XP to %s.", xp, p:Nick()))
            return
        end
    end
    print("[GWRP-Admin] Player not found.")
end)
