--[[
    sv_gangs.lua - Player-Created Gang Management with SQLite Persistence
    Author: Toxic
--]]

GW.Gangs = GW.Gangs or {}
GW.GangInvites = GW.GangInvites or {}

-- Chat Commands Hook for Gang Operations
hook.Add("PlayerSay", "GW_GangChatCommands", function(ply, text)
    local trimmed = string.Trim(text)
    local args = string.Explode(" ", trimmed)
    local cmd = string.lower(args[1] or "")

    -- 1. Create a Gang: /creategang <name>
    if cmd == "/creategang" or cmd == "/gangcreate" then
        table.remove(args, 1)
        local gangName = string.Trim(table.concat(args, " "))

        if #gangName < 2 or #gangName > 24 then
            GW.Notify(ply, "Gang name must be between 2 and 24 characters!", NOTIFY_ERROR)
            return ""
        end

        if string.lower(gangName) == "police" or string.lower(gangName) == "neutral" or string.lower(gangName) == "citizens" then
            GW.Notify(ply, "That gang name is reserved!", NOTIFY_ERROR)
            return ""
        end

        if ply:IsInGang() then
            GW.Notify(ply, "You are already in a gang ('" .. ply:GetGang() .. "')! Use /leavegang first.", NOTIFY_ERROR)
            return ""
        end

        -- Check if gang already exists in SQLite
        if GW.Database and GW.Database.GetGang and GW.Database.GetGang(gangName) then
            GW.Notify(ply, "A gang with that name already exists!", NOTIFY_ERROR)
            return ""
        end

        local cost = GW.Config.GangCreationCost or 500
        if not ply:CanAfford(cost) then
            GW.Notify(ply, "Creating a gang costs $" .. cost .. "!", NOTIFY_ERROR)
            return ""
        end

        ply:AddMoney(-cost)
        ply:SetGang(gangName)
        ply:SetNWBool("GW_IsGangLeader", true)

        -- Save gang and leader to SQLite
        if GW.Database and GW.Database.CreateGang then
            GW.Database.CreateGang(gangName, ply:SteamID())
        end

        GW.Notify(ply, "Congratulations! You founded the gang '" .. gangName .. "'!", NOTIFY_GENERIC)
        GW.NotifyAll(string.format("%s founded a new street gang: '%s'", ply:Nick(), gangName), NOTIFY_HINT, 6)
        return ""

    -- 2. Invite Player to Gang: /invitegang <target>
    elseif cmd == "/invitegang" or (cmd == "/gang" and string.lower(args[2] or "") == "invite") then
        local targetName = cmd == "/invitegang" and args[2] or args[3]
        if not targetName or targetName == "" then
            GW.Notify(ply, "Usage: /invitegang <player_name>", NOTIFY_ERROR)
            return ""
        end

        local gang = ply:GetGang()
        if gang == "" then
            GW.Notify(ply, "You must be in a gang to invite others! Use /creategang <name>", NOTIFY_ERROR)
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
            GW.Notify(ply, "Player not found or invalid!", NOTIFY_ERROR)
            return ""
        end

        if target:IsInGang() then
            GW.Notify(ply, target:Nick() .. " is already in a gang!", NOTIFY_ERROR)
            return ""
        end

        GW.GangInvites[target:SteamID()] = gang
        GW.Notify(ply, "Invited " .. target:Nick() .. " to join '" .. gang .. "'!", NOTIFY_GENERIC)
        GW.Notify(target, ply:Nick() .. " invited you to join gang '" .. gang .. "'! Type /acceptgang to join.", NOTIFY_HINT, 10)
        return ""

    -- 3. Accept Gang Invite: /acceptgang
    elseif cmd == "/acceptgang" then
        local pendingGang = GW.GangInvites[ply:SteamID()]
        if not pendingGang then
            GW.Notify(ply, "You have no pending gang invites!", NOTIFY_ERROR)
            return ""
        end

        GW.GangInvites[ply:SteamID()] = nil
        ply:SetGang(pendingGang)
        ply:SetNWBool("GW_IsGangLeader", false)

        -- Persist member to SQLite
        if GW.Database and GW.Database.AddGangMember then
            GW.Database.AddGangMember(ply:SteamID(), pendingGang, "member")
        end

        GW.Notify(ply, "You have joined the gang '" .. pendingGang .. "'!", NOTIFY_GENERIC)

        -- Notify gang members
        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == pendingGang and p ~= ply then
                GW.Notify(p, ply:Nick() .. " has joined your gang!", NOTIFY_GENERIC)
            end
        end
        return ""

    -- 4. Leave Gang: /leavegang
    elseif cmd == "/leavegang" then
        local gang = ply:GetGang()
        if gang == "" then
            GW.Notify(ply, "You are not currently in any gang!", NOTIFY_ERROR)
            return ""
        end

        ply:SetGang("")
        ply:SetNWBool("GW_IsGangLeader", false)

        -- Remove member from SQLite
        if GW.Database and GW.Database.RemoveGangMember then
            GW.Database.RemoveGangMember(ply:SteamID())
        end

        GW.Notify(ply, "You left the gang '" .. gang .. "'.", NOTIFY_GENERIC)

        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == gang then
                GW.Notify(p, ply:Nick() .. " has left your gang.", NOTIFY_GENERIC)
            end
        end
        return ""

    -- 5. Disband Gang: /disbandgang (Leader only)
    elseif cmd == "/disbandgang" then
        local gang = ply:GetGang()
        if gang == "" then
            GW.Notify(ply, "You are not in a gang!", NOTIFY_ERROR)
            return ""
        end

        if not ply:GetNWBool("GW_IsGangLeader", false) then
            GW.Notify(ply, "Only the gang leader can disband the gang!", NOTIFY_ERROR)
            return ""
        end

        if GW.Database and GW.Database.DisbandGang then
            GW.Database.DisbandGang(gang)
        end

        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == gang then
                p:SetGang("")
                p:SetNWBool("GW_IsGangLeader", false)
                GW.Notify(p, "Your gang '" .. gang .. "' was disbanded by the leader.", NOTIFY_ERROR)
            end
        end
        return ""

    -- 6. Gang Info: /gang
    elseif cmd == "/gang" then
        local gang = ply:GetGang()
        if gang == "" then
            GW.Notify(ply, "You are not in a gang. Type /creategang <name> to form one!", NOTIFY_HINT)
            return ""
        end

        local members = {}
        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == gang then
                table.insert(members, p:Nick())
            end
        end

        local dbMembers = GW.Database and GW.Database.GetGangMembers and GW.Database.GetGangMembers(gang) or {}
        local turfs = {}
        for _, zone in pairs(GW.Turf.Zones) do
            if zone.owner and string.lower(zone.owner) == string.lower(gang) then
                table.insert(turfs, zone.name)
            end
        end

        GW.Notify(ply, "--- Gang: " .. gang .. " ---", NOTIFY_GENERIC)
        GW.Notify(ply, "Total Registered Members: " .. #dbMembers, NOTIFY_GENERIC)
        GW.Notify(ply, "Online Members (" .. #members .. "): " .. table.concat(members, ", "), NOTIFY_GENERIC)
        GW.Notify(ply, "Controlled Turfs: " .. (#turfs > 0 and table.concat(turfs, ", ") or "None"), NOTIFY_GENERIC)
        return ""

    -- 7. Private Gang Chat: /g <msg> or /gangchat <msg>
    elseif cmd == "/g" or cmd == "/gangchat" then
        local gang = ply:GetGang()
        if gang == "" then
            GW.Notify(ply, "You must be in a gang to use gang chat!", NOTIFY_ERROR)
            return ""
        end

        table.remove(args, 1)
        local msg = table.concat(args, " ")
        if msg == "" then return "" end

        local gangCol = GW.GetGangColor(gang)
        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == gang then
                net.Start("GW_ChatMessage")
                    net.WriteString(gang)
                    net.WriteString(ply:Nick())
                    net.WriteString(msg)
                net.Send(p)
            end
        end
        return ""
    end
end)
