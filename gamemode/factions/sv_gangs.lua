--[[
    sv_gangs.lua - Player-Created Gang Management with SQLite Persistence
    Author: Toxic
--]]

GWRP.Gangs = GWRP.Gangs or {}
GWRP.GangInvites = GWRP.GangInvites or {}

-- Chat Commands Hook for Gang Operations
hook.Add("PlayerSay", "GWRP_GangChatCommands", function(ply, text)
    local trimmed = string.Trim(text)
    local args = string.Explode(" ", trimmed)
    local cmd = string.lower(args[1] or "")

    -- 1. Create a Gang: /creategang <name>
    if cmd == "/creategang" or cmd == "/gangcreate" then
        table.remove(args, 1)
        local gangName = string.Trim(table.concat(args, " "))

        if #gangName < 2 or #gangName > 24 then
            GWRP.Notify(ply, "Gang name must be between 2 and 24 characters!", NOTIFY_ERROR)
            return ""
        end

        if string.lower(gangName) == "police" or string.lower(gangName) == "neutral" or string.lower(gangName) == "citizens" then
            GWRP.Notify(ply, "That gang name is reserved!", NOTIFY_ERROR)
            return ""
        end

        if ply:IsInGang() then
            GWRP.Notify(ply, "You are already in a gang ('" .. ply:GetGang() .. "')! Use /leavegang first.", NOTIFY_ERROR)
            return ""
        end

        -- Check if gang already exists in SQLite
        if GWRP.Database and GWRP.Database.GetGang and GWRP.Database.GetGang(gangName) then
            GWRP.Notify(ply, "A gang with that name already exists!", NOTIFY_ERROR)
            return ""
        end

        local cost = GWRP.Config.GangCreationCost or 500
        if not ply:CanAfford(cost) then
            GWRP.Notify(ply, "Creating a gang costs $" .. cost .. "!", NOTIFY_ERROR)
            return ""
        end

        ply:AddMoney(-cost)
        ply:SetGang(gangName)
        ply:SetNWBool("GWRP_IsGangLeader", true)

        -- Save gang and leader to SQLite
        if GWRP.Database and GWRP.Database.CreateGang then
            GWRP.Database.CreateGang(gangName, ply:SteamID())
        end

        GWRP.Notify(ply, "Congratulations! You founded the gang '" .. gangName .. "'!", NOTIFY_GENERIC)
        GWRP.NotifyAll(string.format("%s founded a new street gang: '%s'", ply:Nick(), gangName), NOTIFY_HINT, 6)
        return ""

    -- 2. Invite Player to Gang: /invitegang <target>
    elseif cmd == "/invitegang" or (cmd == "/gang" and string.lower(args[2] or "") == "invite") then
        local targetName = cmd == "/invitegang" and args[2] or args[3]
        if not targetName or targetName == "" then
            GWRP.Notify(ply, "Usage: /invitegang <player_name>", NOTIFY_ERROR)
            return ""
        end

        local gang = ply:GetGang()
        if gang == "" then
            GWRP.Notify(ply, "You must be in a gang to invite others! Use /creategang <name>", NOTIFY_ERROR)
            return ""
        end

        local target = nil
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(targetName), 1, true) then
                target = p
                break
            end
        end

        if not IsValid(target) or target == ply then
            GWRP.Notify(ply, "Player not found or invalid!", NOTIFY_ERROR)
            return ""
        end

        if target:IsInGang() then
            GWRP.Notify(ply, target:Nick() .. " is already in a gang!", NOTIFY_ERROR)
            return ""
        end

        GWRP.GangInvites[target:SteamID()] = gang
        GWRP.Notify(ply, "Invited " .. target:Nick() .. " to join '" .. gang .. "'!", NOTIFY_GENERIC)
        GWRP.Notify(target, ply:Nick() .. " invited you to join gang '" .. gang .. "'! Type /acceptgang to join.", NOTIFY_HINT, 10)
        return ""

    -- 3. Accept Gang Invite: /acceptgang
    elseif cmd == "/acceptgang" then
        local pendingGang = GWRP.GangInvites[ply:SteamID()]
        if not pendingGang then
            GWRP.Notify(ply, "You have no pending gang invites!", NOTIFY_ERROR)
            return ""
        end

        GWRP.GangInvites[ply:SteamID()] = nil
        ply:SetGang(pendingGang)
        ply:SetNWBool("GWRP_IsGangLeader", false)

        -- Persist member to SQLite
        if GWRP.Database and GWRP.Database.AddGangMember then
            GWRP.Database.AddGangMember(ply:SteamID(), pendingGang, "member")
        end

        GWRP.Notify(ply, "You have joined the gang '" .. pendingGang .. "'!", NOTIFY_GENERIC)

        -- Notify gang members
        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == pendingGang and p ~= ply then
                GWRP.Notify(p, ply:Nick() .. " has joined your gang!", NOTIFY_GENERIC)
            end
        end
        return ""

    -- 4. Leave Gang: /leavegang
    elseif cmd == "/leavegang" then
        local gang = ply:GetGang()
        if gang == "" then
            GWRP.Notify(ply, "You are not currently in any gang!", NOTIFY_ERROR)
            return ""
        end

        ply:SetGang("")
        ply:SetNWBool("GWRP_IsGangLeader", false)

        -- Remove member from SQLite
        if GWRP.Database and GWRP.Database.RemoveGangMember then
            GWRP.Database.RemoveGangMember(ply:SteamID())
        end

        GWRP.Notify(ply, "You left the gang '" .. gang .. "'.", NOTIFY_GENERIC)

        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == gang then
                GWRP.Notify(p, ply:Nick() .. " has left your gang.", NOTIFY_GENERIC)
            end
        end
        return ""

    -- 5. Disband Gang: /disbandgang (Leader only)
    elseif cmd == "/disbandgang" then
        local gang = ply:GetGang()
        if gang == "" then
            GWRP.Notify(ply, "You are not in a gang!", NOTIFY_ERROR)
            return ""
        end

        if not ply:GetNWBool("GWRP_IsGangLeader", false) then
            GWRP.Notify(ply, "Only the gang leader can disband the gang!", NOTIFY_ERROR)
            return ""
        end

        if GWRP.Database and GWRP.Database.DisbandGang then
            GWRP.Database.DisbandGang(gang)
        end

        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == gang then
                p:SetGang("")
                p:SetNWBool("GWRP_IsGangLeader", false)
                GWRP.Notify(p, "Your gang '" .. gang .. "' was disbanded by the leader.", NOTIFY_ERROR)
            end
        end
        return ""

    -- 6. Gang Info: /gang
    elseif cmd == "/gang" then
        local gang = ply:GetGang()
        if gang == "" then
            GWRP.Notify(ply, "You are not in a gang. Type /creategang <name> to form one!", NOTIFY_HINT)
            return ""
        end

        local members = {}
        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == gang then
                table.insert(members, p:Nick())
            end
        end

        local dbMembers = GWRP.Database and GWRP.Database.GetGangMembers and GWRP.Database.GetGangMembers(gang) or {}
        local turfs = {}
        for _, zone in pairs(GWRP.Turf.Zones) do
            if zone.owner and string.lower(zone.owner) == string.lower(gang) then
                table.insert(turfs, zone.name)
            end
        end

        GWRP.Notify(ply, "--- Gang: " .. gang .. " ---", NOTIFY_GENERIC)
        GWRP.Notify(ply, "Total Registered Members: " .. #dbMembers, NOTIFY_GENERIC)
        GWRP.Notify(ply, "Online Members (" .. #members .. "): " .. table.concat(members, ", "), NOTIFY_GENERIC)
        GWRP.Notify(ply, "Controlled Turfs: " .. (#turfs > 0 and table.concat(turfs, ", ") or "None"), NOTIFY_GENERIC)
        return ""

    -- 7. Private Gang Chat: /g <msg> or /gangchat <msg>
    elseif cmd == "/g" or cmd == "/gangchat" then
        local gang = ply:GetGang()
        if gang == "" then
            GWRP.Notify(ply, "You must be in a gang to use gang chat!", NOTIFY_ERROR)
            return ""
        end

        table.remove(args, 1)
        local msg = table.concat(args, " ")
        if msg == "" then return "" end

        local gangCol = GWRP.GetGangColor(gang)
        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == gang then
                net.Start("GWRP_ChatMessage")
                    net.WriteString(gang)
                    net.WriteString(ply:Nick())
                    net.WriteString(msg)
                net.Send(p)
            end
        end
        return ""
    end
end)
