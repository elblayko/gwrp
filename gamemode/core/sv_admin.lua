--[[
    sv_admin.lua - Server-Side Admin & Debug Executive Controller
    Author: Toxic
--]]

GW.Admin = GW.Admin or {}

local function IsAdminUser(ply)
    return IsValid(ply) and (ply:IsAdmin() or ply:IsSuperAdmin())
end

-- ========================================================
-- NETWORK RECEIVER FOR ADMIN ACTIONS
-- ========================================================

net.Receive("GW_AdminDebugAction", function(len, ply)
    if not IsAdminUser(ply) then return end
    if not GW.CheckRateLimit(ply, "admin_action", 10) then return end

    local action = net.ReadString()

    -- 1. Economy & Money Debug
    if action == "set_money" then
        local target = net.ReadEntity()
        local amount = math.max(0, net.ReadInt(32))
        if IsValid(target) and target:IsPlayer() then
            target:SetMoney(amount)
            GW.Notify(ply, string.format("Set %s's wallet to $%s.", target:Nick(), string.Comma(amount)), NOTIFY_GENERIC)
            GW.Notify(target, string.format("An administrator set your wallet to $%s.", string.Comma(amount)), NOTIFY_HINT)
        end

    elseif action == "add_money" then
        local target = net.ReadEntity()
        local amount = net.ReadInt(32)
        if IsValid(target) and target:IsPlayer() then
            target:AddMoney(amount)
            GW.Notify(ply, string.format("Gave $%s to %s.", string.Comma(amount), target:Nick()), NOTIFY_GENERIC)
            GW.Notify(target, string.format("Received $%s from an administrator.", string.Comma(amount)), NOTIFY_HINT)
        end

    -- Leveling & Progression Debug
    elseif action == "set_level" then
        local target = net.ReadEntity()
        local lvl = net.ReadInt(16)
        if IsValid(target) and target:IsPlayer() and target.SetLevel then
            target:SetLevel(lvl)
            GW.Notify(ply, string.format("Set %s's level to %d.", target:Nick(), target:GetLevel()), NOTIFY_GENERIC)
            GW.Notify(target, string.format("An administrator set your level to %d.", target:GetLevel()), NOTIFY_HINT)
        end

    elseif action == "add_xp" then
        local target = net.ReadEntity()
        local xpAmount = net.ReadInt(32)
        if IsValid(target) and target:IsPlayer() and target.AddXP then
            target:AddXP(xpAmount, "Admin Grant")
            GW.Notify(ply, string.format("Awarded %s XP to %s.", string.Comma(xpAmount), target:Nick()), NOTIFY_GENERIC)
        end

    -- 2. Role & Faction Debug
    elseif action == "set_job" then
        local target = net.ReadEntity()
        local jobId = net.ReadString()
        if IsValid(target) and target:IsPlayer() and GW.Jobs[jobId] then
            target:SetJob(jobId, true)
            GW.Notify(ply, string.format("Forced %s to role: %s.", target:Nick(), GW.Jobs[jobId].name), NOTIFY_GENERIC)
        end

    elseif action == "set_gang" then
        local target = net.ReadEntity()
        local gangName = net.ReadString()
        if IsValid(target) and target:IsPlayer() then
            target:SetGang(gangName)
            if gangName ~= "" and GW.Database and GW.Database.AddGangMember then
                GW.Database.AddGangMember(target:SteamID(), gangName, "member")
            elseif gangName == "" and GW.Database and GW.Database.RemoveGangMember then
                GW.Database.RemoveGangMember(target:SteamID())
            end
            GW.Notify(ply, string.format("Updated %s's gang to '%s'.", target:Nick(), gangName ~= "" and gangName or "None"), NOTIFY_GENERIC)
        end

    -- 3. Vitals & Combat Debug
    elseif action == "set_health" then
        local target = net.ReadEntity()
        local hp = math.Clamp(net.ReadInt(32), 1, 99999)
        if IsValid(target) and target:IsPlayer() then
            target:SetHealth(hp)
            GW.Notify(ply, string.format("Set %s's health to %d.", target:Nick(), hp), NOTIFY_GENERIC)
        end

    elseif action == "set_armor" then
        local target = net.ReadEntity()
        local armor = math.Clamp(net.ReadInt(32), 0, 500)
        if IsValid(target) and target:IsPlayer() then
            target:SetArmor(armor)
            GW.Notify(ply, string.format("Set %s's armor to %d.", target:Nick(), armor), NOTIFY_GENERIC)
        end

    elseif action == "godmode" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() then
            target.GW_HasGod = not target.GW_HasGod
            if target.GW_HasGod then
                target:GodEnable()
                GW.Notify(ply, "Godmode ENABLED for " .. target:Nick(), NOTIFY_GENERIC)
            else
                target:GodDisable()
                GW.Notify(ply, "Godmode DISABLED for " .. target:Nick(), NOTIFY_GENERIC)
            end
        end

    -- 4. Teleportation & Movement
    elseif action == "goto" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() and target ~= ply then
            ply:SetPos(target:GetPos() + Vector(0, 45, 5))
            GW.Notify(ply, "Teleported to " .. target:Nick(), NOTIFY_GENERIC)
        end

    elseif action == "bring" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() and target ~= ply then
            target:SetPos(ply:GetPos() + Vector(0, 45, 5))
            GW.Notify(ply, "Brought " .. target:Nick() .. " to your position.", NOTIFY_GENERIC)
        end

    elseif action == "respawn" then
        local target = net.ReadEntity()
        if IsValid(target) and target:IsPlayer() then
            target:Spawn()
            GW.Notify(ply, "Respawned " .. target:Nick(), NOTIFY_GENERIC)
        end

    -- 5. Game Loop & Economy Simulation Debug
    elseif action == "trigger_payday" then
        for _, p in ipairs(player.GetAll()) do
            local job = p:GetJobData()
            if job and job.salary > 0 then
                p:AddMoney(job.salary)
                GW.Notify(p, string.format("Salary received: +$%d", job.salary), NOTIFY_GENERIC)
            end
        end
        GW.Notify(ply, "Simulated instant server-wide Payday cycle.", NOTIFY_GENERIC)

    elseif action == "trigger_dividends" then
        if GW.Turf and GW.Turf.DistributeDividends then
            GW.Turf.DistributeDividends()
            GW.Notify(ply, "Simulated instant turf dividend distribution.", NOTIFY_GENERIC)
        end

    -- 6. Entity Spawning Debug
    elseif action == "spawn_entity" then
        local class = net.ReadString()
        local tr = ply:GetEyeTrace()
        local spawnPos = tr.HitPos + Vector(0, 0, 15)

        if class == "gw_cash_stack" then
            GW.Economy.SpawnCashStack(spawnPos, 10000)
            GW.Notify(ply, "Spawned $10,000 cash stack at crosshair.", NOTIFY_GENERIC)
        else
            local ent = ents.Create(class)
            if IsValid(ent) then
                ent:SetPos(spawnPos)
                ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
                if ent.SetOwnerPlayer then ent:SetOwnerPlayer(ply) end
                ent:Spawn()
                ent:Activate()
                GW.Notify(ply, "Spawned " .. class .. " at crosshair.", NOTIFY_GENERIC)
            end
        end
    end
end)

-- ========================================================
-- CONSOLE & CHAT COMMANDS
-- ========================================================

local function OpenAdminHUD(ply)
    if not IsAdminUser(ply) then
        GW.Notify(ply, "You must be an administrator to access the Admin HUD!", NOTIFY_ERROR)
        return
    end
    net.Start("GW_OpenAdminMenu")
    net.Send(ply)
end

concommand.Add("gw_admin", OpenAdminHUD)
concommand.Add("admin", OpenAdminHUD)
concommand.Add("debug", OpenAdminHUD)

-- Chat commands: /admin, /debug, /setmoney <target> <amount>, /setjob <target> <job>
hook.Add("PlayerSay", "GW_AdminChatCommands", function(ply, text)
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
            GW.Notify(ply, "Usage: /setmoney <player_name> <amount>", NOTIFY_ERROR)
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
            GW.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        amount = math.max(0, math.floor(amount))
        target:SetMoney(amount)
        GW.Notify(ply, string.format("Set %s's wallet to $%s.", target:Nick(), string.Comma(amount)), NOTIFY_GENERIC)
        GW.Notify(target, string.format("An administrator set your wallet to $%s.", string.Comma(amount)), NOTIFY_HINT)
        return ""
    end

    if cmd == "/addmoney" then
        if not IsAdminUser(ply) then return "" end
        local targetName = args[2]
        local amount = tonumber(args[3])
        if not targetName or not amount then
            GW.Notify(ply, "Usage: /addmoney <player_name> <amount>", NOTIFY_ERROR)
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
            GW.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        target:AddMoney(math.floor(amount))
        GW.Notify(ply, string.format("Gave $%s to %s.", string.Comma(math.floor(amount)), target:Nick()), NOTIFY_GENERIC)
        return ""
    end

    if cmd == "/setlevel" then
        if not IsAdminUser(ply) then return "" end
        local targetName = args[2]
        local lvl = tonumber(args[3])
        if not targetName or not lvl then
            GW.Notify(ply, "Usage: /setlevel <player_name> <level>", NOTIFY_ERROR)
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
            GW.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        target:SetLevel(lvl)
        GW.Notify(ply, string.format("Set %s's level to %d.", target:Nick(), target:GetLevel()), NOTIFY_GENERIC)
        GW.Notify(target, string.format("An administrator set your level to %d.", target:GetLevel()), NOTIFY_HINT)
        return ""
    end

    if cmd == "/addxp" then
        if not IsAdminUser(ply) then return "" end
        local targetName = args[2]
        local xp = tonumber(args[3])
        if not targetName or not xp then
            GW.Notify(ply, "Usage: /addxp <player_name> <amount>", NOTIFY_ERROR)
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
            GW.Notify(ply, "Player not found!", NOTIFY_ERROR)
            return ""
        end

        target:AddXP(math.floor(xp), "Admin Grant")
        GW.Notify(ply, string.format("Awarded %s XP to %s.", string.Comma(math.floor(xp)), target:Nick()), NOTIFY_GENERIC)
        return ""
    end
end)

-- Console Admin Commands
concommand.Add("gw_setlevel", function(ply, cmd, args)
    if IsValid(ply) and not IsAdminUser(ply) then return end
    local targetNick = args[1]
    local lvl = tonumber(args[2])
    if not targetNick or not lvl then
        print("[GWRP-Admin] Usage: gw_setlevel <name> <level>")
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

concommand.Add("gw_addxp", function(ply, cmd, args)
    if IsValid(ply) and not IsAdminUser(ply) then return end
    local targetNick = args[1]
    local xp = tonumber(args[2])
    if not targetNick or not xp then
        print("[GWRP-Admin] Usage: gw_addxp <name> <amount>")
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
