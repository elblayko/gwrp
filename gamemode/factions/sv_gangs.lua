--[[
    sv_gangs.lua - Player-Created Gang Management with SQLite Persistence & UI Synchronization
    Author: Juicebox & Antigravity
--]]

GRID = GRID or {}
GRID.Gangs = GRID.Gangs or {}
GRID.GangInvites = GRID.GangInvites or {}

-- Chat Commands Hook for Gang Operations
hook.Add("PlayerSay", "GRID_GangChatCommands", function(ply, text)
    local trimmed = string.Trim(text)
    local args = string.Explode(" ", trimmed)
    local cmd = string.lower(args[1] or "")

    -- 1. Create a Gang: /creategang <name>
    if cmd == "/creategang" or cmd == "/gangcreate" then
        table.remove(args, 1)
        local gangName = string.Trim(table.concat(args, " "))

        if not ply:IsGangFaction() then
            GRID.Notify(ply, "Only Street Gang members can create a gang! Switch to a Gang role in F4 first.",
                NOTIFY_ERROR)
            return ""
        end

        if #gangName < 2 or #gangName > 24 then
            GRID.Notify(ply, "Gang name must be between 2 and 24 characters!", NOTIFY_ERROR)
            return ""
        end

        if string.lower(gangName) == "police" or string.lower(gangName) == "neutral" or string.lower(gangName) == "citizens" then
            GRID.Notify(ply, "That gang name is reserved!", NOTIFY_ERROR)
            return ""
        end

        if ply:HasStoredGang() then
            GRID.Notify(ply, "You are already in a gang ('" .. ply:GetRawGang() .. "')! Use /leavegang first.",
                NOTIFY_ERROR)
            return ""
        end

        -- Check if gang already exists in SQLite
        if GRID.Database and GRID.Database.GetGang and GRID.Database.GetGang(gangName) then
            GRID.Notify(ply, "A gang with that name already exists!", NOTIFY_ERROR)
            return ""
        end

        local cost = (GRID.Config and GRID.Config.GangCreationCost) or 500
        if not ply:CanAfford(cost) then
            GRID.Notify(ply, "Creating a gang costs $" .. cost .. "!", NOTIFY_ERROR)
            return ""
        end

        ply:AddMoney(-cost)
        ply:SetGang(gangName)
        ply:SetNWBool("GRID_IsGangLeader", true)

        -- Save gang and leader to SQLite
        if GRID.Database and GRID.Database.CreateGang then
            GRID.Database.CreateGang(gangName, ply:SteamID())
        end

        GRID.Notify(ply, "Congratulations! You founded the gang '" .. gangName .. "'!", NOTIFY_GENERIC)
        GRID.NotifyAll(string.format("%s founded a new street gang: '%s'", ply:Nick(), gangName), NOTIFY_HINT, 6)
        GRID.Gangs.SendSync(ply)
        return ""

        -- 2. Invite Player to Gang: /invitegang <target>
    elseif cmd == "/invitegang" or (cmd == "/gang" and string.lower(args[2] or "") == "invite") then
        local targetName = cmd == "/invitegang" and args[2] or args[3]
        if not targetName or targetName == "" then
            GRID.Notify(ply, "Usage: /invitegang <player_name>", NOTIFY_ERROR)
            return ""
        end

        if not ply:IsGangFaction() then
            GRID.Notify(ply, "Your gang is inactive while off-duty. Switch to Street Gangs to invite members.",
                NOTIFY_ERROR)
            return ""
        end

        local gang = ply:GetGang()
        if gang == "" then
            GRID.Notify(ply, "You must be in a gang to invite others! Use /creategang <name>", NOTIFY_ERROR)
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
            GRID.Notify(ply, "Player not found or invalid!", NOTIFY_ERROR)
            return ""
        end

        if not target:IsGangFaction() then
            GRID.Notify(ply,
                target:Nick() ..
                " cannot join a gang while playing as " ..
                target:GetJobData().name .. "! They must switch to Street Gangs first.", NOTIFY_ERROR)
            return ""
        end

        if target:HasStoredGang() then
            GRID.Notify(ply, target:Nick() .. " is already in a gang!", NOTIFY_ERROR)
            return ""
        end

        GRID.GangInvites[target:SteamID()] = gang
        GRID.Notify(ply, "Invited " .. target:Nick() .. " to join '" .. gang .. "'!", NOTIFY_GENERIC)
        GRID.Notify(target, ply:Nick() .. " invited you to join gang '" .. gang .. "'! Type /acceptgang to join.",
            NOTIFY_HINT, 10)
        return ""

        -- 3. Accept Gang Invite: /acceptgang
    elseif cmd == "/acceptgang" then
        if not ply:IsGangFaction() then
            GRID.Notify(ply,
                "You cannot join a gang while playing as " ..
                ply:GetJobData().name .. "! Switch to Street Gangs in F4 first.", NOTIFY_ERROR)
            return ""
        end

        local pendingGang = GRID.GangInvites[ply:SteamID()]
        if not pendingGang then
            GRID.Notify(ply, "You have no pending gang invites!", NOTIFY_ERROR)
            return ""
        end

        GRID.GangInvites[ply:SteamID()] = nil
        ply:SetGang(pendingGang)
        ply:SetNWBool("GRID_IsGangLeader", false)

        -- Persist member to SQLite
        if GRID.Database and GRID.Database.AddGangMember then
            GRID.Database.AddGangMember(ply:SteamID(), pendingGang, "member")
        end

        GRID.Notify(ply, "You have joined the gang '" .. pendingGang .. "'!", NOTIFY_GENERIC)

        -- Notify gang members
        for _, p in ipairs(player.GetAll()) do
            if p:GetRawGang() == pendingGang and p ~= ply then
                GRID.Notify(p, ply:Nick() .. " has joined your gang!", NOTIFY_GENERIC)
            end
        end
        GRID.Gangs.SendSync(ply)
        return ""

        -- 4. Leave Gang: /leavegang (Allowed even while off-duty)
    elseif cmd == "/leavegang" then
        local storedGang = ply:GetRawGang()
        if storedGang == "" then
            GRID.Notify(ply, "You are not currently in any gang!", NOTIFY_ERROR)
            return ""
        end

        ply:SetGang("")
        ply:SetNWBool("GRID_IsGangLeader", false)

        -- Remove member from SQLite
        if GRID.Database and GRID.Database.RemoveGangMember then
            GRID.Database.RemoveGangMember(ply:SteamID())
        end

        GRID.Notify(ply, "You left the gang '" .. storedGang .. "'.", NOTIFY_GENERIC)

        for _, p in ipairs(player.GetAll()) do
            if p:GetRawGang() == storedGang and p ~= ply then
                GRID.Notify(p, ply:Nick() .. " has left your gang.", NOTIFY_GENERIC)
            end
        end
        GRID.Gangs.SendSync(ply)
        return ""

        -- 5. Disband Gang: /disbandgang (Leader only)
    elseif cmd == "/disbandgang" then
        if not ply:IsGangFaction() then
            GRID.Notify(ply, "You must be playing as a Street Gangster to manage your gang!", NOTIFY_ERROR)
            return ""
        end

        local gang = ply:GetGang()
        if gang == "" then
            GRID.Notify(ply, "You are not in a gang!", NOTIFY_ERROR)
            return ""
        end

        local isLdr = ply:GetNWBool("GRID_IsGangLeader", false)
        if not isLdr then
            GRID.Notify(ply, "Only the gang leader can disband the gang!", NOTIFY_ERROR)
            return ""
        end

        if GRID.Database and GRID.Database.DisbandGang then
            GRID.Database.DisbandGang(gang)
        end

        for _, p in ipairs(player.GetAll()) do
            if p:GetRawGang() == gang then
                p:SetGang("")
                p:SetNWBool("GRID_IsGangLeader", false)
                GRID.Notify(p, "Your gang '" .. gang .. "' was disbanded by the leader.", NOTIFY_ERROR)
            end
        end
        GRID.Gangs.SendSync(ply)
        return ""

        -- 6. Gang Info & Vault Banking: /gang [deposit|withdraw|tax]
    elseif cmd == "/gang" then
        if not ply:IsGangFaction() then
            if ply:HasStoredGang() then
                GRID.Notify(ply,
                    string.format(
                    "Your gang '%s' is temporarily suspended while on duty as %s. Switch to Street Gangs to participate.",
                        ply:GetRawGang(), ply:GetJobData().name), NOTIFY_HINT, 6)
            else
                GRID.Notify(ply, "You are not in a gang. Switch to Street Gangs and type /creategang <name> to form one!",
                    NOTIFY_HINT)
            end
            return ""
        end

        local gang = ply:GetGang()
        if gang == "" then
            GRID.Notify(ply, "You are not in a gang. Type /creategang <name> to form one!", NOTIFY_HINT)
            return ""
        end

        local sub = string.lower(args[2] or "")
        if sub == "deposit" then
            local amt = math.floor(tonumber(args[3]) or 0)
            if amt <= 0 then
                GRID.Notify(ply, "Usage: /gang deposit <amount>", NOTIFY_ERROR)
                return ""
            end
            if not ply:CanAfford(amt) then
                GRID.Notify(ply, "You cannot afford to deposit $" .. amt .. "!", NOTIFY_ERROR)
                return ""
            end
            if GRID.Database and GRID.Database.TransferGangVault then
                GRID.Database.TransferGangVault(ply:SteamID(), gang, amt)
            else
                ply:AddMoney(-amt)
                if GRID.Database and GRID.Database.AddGangBank then
                    GRID.Database.AddGangBank(gang, amt)
                end
            end
            if GRID.Telemetry and GRID.Telemetry.Log then
                GRID.Telemetry.Log("ECONOMY", "GANG_VAULT_DEPOSIT", ply:SteamID(), gang, amt, {})
            end
            GRID.Notify(ply, string.format("Deposited +$%d into the gang vault!", amt), NOTIFY_GENERIC)
            GRID.Gangs.SendSync(ply)
            return ""
        elseif sub == "withdraw" then
            local isLeader = ply:GetNWBool("GRID_IsGangLeader", false) or (ply.GetJob and ply:GetJob() == "gang_leader") or
            ply:IsAdmin()
            if not isLeader then
                GRID.Notify(ply, "Only the Gang Leader can withdraw funds from the gang vault!", NOTIFY_ERROR)
                return ""
            end
            local amt = math.floor(tonumber(args[3]) or 0)
            if amt <= 0 then
                GRID.Notify(ply, "Usage: /gang withdraw <amount>", NOTIFY_ERROR)
                return ""
            end
            local gData = GRID.Database and GRID.Database.GetGang and GRID.Database.GetGang(gang)
            local bank = gData and tonumber(gData.bank) or 0
            if amt > bank then
                GRID.Notify(ply, string.format("The gang vault only contains $%d!", bank), NOTIFY_ERROR)
                return ""
            end
            if GRID.Database and GRID.Database.TransferGangVault then
                GRID.Database.TransferGangVault(ply:SteamID(), gang, -amt)
            else
                if GRID.Database and GRID.Database.AddGangBank then
                    GRID.Database.AddGangBank(gang, -amt)
                end
                ply:AddMoney(amt)
            end
            if GRID.Telemetry and GRID.Telemetry.Log then
                GRID.Telemetry.Log("ECONOMY", "GANG_VAULT_WITHDRAW", ply:SteamID(), gang, amt, {})
            end
            GRID.Notify(ply, string.format("Withdrew $%d from the gang vault!", amt), NOTIFY_GENERIC)
            GRID.Gangs.SendSync(ply)
            return ""
        elseif sub == "tax" or sub == "settax" then
            local rate = math.floor(tonumber(args[3]) or 0)
            local zone, zId = GRID.Turf and GRID.Turf.GetZoneAtPos and GRID.Turf.GetZoneAtPos(ply:GetPos())
            if not zone then
                GRID.Notify(ply,
                    "You must be standing inside a territory to set its tax rate! (Or press [E] on its flag pole)",
                    NOTIFY_ERROR)
                return ""
            end
            GRID.Turf.SetTaxRate(zId, rate, ply)
            GRID.Gangs.SendSync(ply)
            return ""
        end

        local members = {}
        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == gang then
                table.insert(members, p:Nick())
            end
        end

        local dbMembers = GRID.Database and GRID.Database.GetGangMembers and GRID.Database.GetGangMembers(gang) or {}
        local gData = GRID.Database and GRID.Database.GetGang and GRID.Database.GetGang(gang)
        local bank = gData and gData.bank or 0
        local turfs = {}
        if GRID.Turf and GRID.Turf.Zones then
            for _, zone in pairs(GRID.Turf.Zones) do
                if zone.owner and string.lower(zone.owner) == string.lower(gang) then
                    table.insert(turfs, string.format("%s (%d%% tax)", zone.name, zone.tax_rate or 10))
                end
            end
        end

        GRID.Notify(ply, "--- Gang: " .. gang .. " ---", NOTIFY_GENERIC)
        GRID.Notify(ply, string.format("Gang Vault Balance: $%d", bank), NOTIFY_GENERIC)
        GRID.Notify(ply, "Total Registered Members: " .. #dbMembers, NOTIFY_GENERIC)
        GRID.Notify(ply, "Online Active Gangsters (" .. #members .. "): " .. table.concat(members, ", "), NOTIFY_GENERIC)
        GRID.Notify(ply, "Controlled Turfs: " .. (#turfs > 0 and table.concat(turfs, ", ") or "None"), NOTIFY_GENERIC)
        return ""

        -- 7. Set Turf Tax: /settax <5-30> or /turftax <5-30>
    elseif cmd == "/settax" or cmd == "/turftax" then
        if not ply:IsGangFaction() then
            GRID.Notify(ply, "You must be in an active street gang to configure territory taxes!", NOTIFY_ERROR)
            return ""
        end
        local gang = ply:GetGang()
        if gang == "" then
            GRID.Notify(ply, "You must be in a gang to configure territory taxes!", NOTIFY_ERROR)
            return ""
        end
        local rate = math.floor(tonumber(args[2]) or 0)
        local zone, zId = GRID.Turf and GRID.Turf.GetZoneAtPos and GRID.Turf.GetZoneAtPos(ply:GetPos())
        if not zone then
            GRID.Notify(ply, "You must be standing inside a territory zone to set its tax rate!", NOTIFY_ERROR)
            return ""
        end
        GRID.Turf.SetTaxRate(zId, rate, ply)
        GRID.Gangs.SendSync(ply)
        return ""

        -- 8. Private Gang Chat: /g <msg> or /gangchat <msg>
    elseif cmd == "/g" or cmd == "/gangchat" then
        if not ply:IsGangFaction() then
            GRID.Notify(ply, "Gang chat is unavailable while playing as " .. ply:GetJobData().name .. "!", NOTIFY_ERROR)
            return ""
        end

        local gang = ply:GetGang()
        if gang == "" then
            GRID.Notify(ply, "You must be in an active gang to use gang chat!", NOTIFY_ERROR)
            return ""
        end

        table.remove(args, 1)
        local msg = table.concat(args, " ")
        if msg == "" then return "" end

        for _, p in ipairs(player.GetAll()) do
            if p:GetGang() == gang then
                net.Start("GRID_ChatMessage")
                net.WriteString(gang)
                net.WriteString(ply:Nick())
                net.WriteString(msg)
                net.Send(p)
            end
        end
        return ""
    end
end)

-- ========================================================
-- GANG MANAGEMENT UI DATA SYNCHRONIZATION & ACTIONS
-- ========================================================

function GRID.Gangs.BuildGangData(ply)
    local rawGang = ply:GetRawGang()
    local curGang = ply:GetGang()
    local isGangFaction = ply:IsGangFaction()
    local isSuspended = (rawGang ~= "" and not isGangFaction)
    local isLeader = ply:GetNWBool("GRID_IsGangLeader", false)

    local payload = {
        hasGang = (rawGang ~= ""),
        gangName = rawGang,
        isActive = (isGangFaction and curGang ~= ""),
        isSuspended = isSuspended,
        isGangFaction = isGangFaction,
        currentJob = ply:GetJobData() and ply:GetJobData().name or "Citizen",
        isLeader = isLeader,
        bank = 0,
        respect = 0,
        leaderSteamID = "",
        creationCost = (GRID.Config and GRID.Config.GangCreationCost) or 500,
        members = {},
        turfs = {},
        cityGangs = {}
    }

    if rawGang ~= "" then
        local gData = GRID.Database and GRID.Database.GetGang and GRID.Database.GetGang(rawGang)
        if gData then
            payload.bank = tonumber(gData.bank) or 0
            payload.respect = tonumber(gData.respect) or 0
            payload.leaderSteamID = gData.leader_steamid or ""
            if gData.leader_steamid == ply:SteamID() then
                payload.isLeader = true
                ply:SetNWBool("GRID_IsGangLeader", true)
            end
        end

        local dbMembers = GRID.Database and GRID.Database.GetGangMembers and GRID.Database.GetGangMembers(rawGang) or {}
        local onlineMap = {}
        for _, p in ipairs(player.GetAll()) do
            onlineMap[p:SteamID()] = p
        end

        for _, m in ipairs(dbMembers) do
            local p = onlineMap[m.steamid]
            local isOnline = IsValid(p)
            local name = isOnline and p:Nick() or (m.name or m.steamid)
            local jobName = isOnline and (p:GetJobData() and p:GetJobData().name or "Civilian") or "Offline"
            local isRankLeader = (m.rank == "leader") or
            (payload.leaderSteamID ~= "" and m.steamid == payload.leaderSteamID)
            table.insert(payload.members, {
                steamid = m.steamid,
                name = name,
                rank = isRankLeader and "leader" or "member",
                isOnline = isOnline,
                job = jobName,
                isLeader = isRankLeader
            })
        end

        if GRID.Turf and GRID.Turf.Zones then
            for zId, zone in pairs(GRID.Turf.Zones) do
                if zone.owner and string.lower(zone.owner) == string.lower(rawGang) then
                    table.insert(payload.turfs, {
                        id = zId,
                        name = zone.name or ("Turf #" .. zId),
                        tax_rate = tonumber(zone.tax_rate) or 10
                    })
                end
            end
        end
    else
        local allGangs = GRID.Database and GRID.Database.GetAllGangs and GRID.Database.GetAllGangs() or {}
        for _, g in ipairs(allGangs) do
            local members = GRID.Database and GRID.Database.GetGangMembers and GRID.Database.GetGangMembers(g.name) or {}
            table.insert(payload.cityGangs, {
                name = g.name,
                bank = tonumber(g.bank) or 0,
                respect = tonumber(g.respect) or 0,
                memberCount = #members
            })
        end
    end

    return payload
end

function GRID.Gangs.SendSync(ply)
    if not IsValid(ply) then return end
    local data = GRID.Gangs.BuildGangData(ply)
    local jsonStr = util.TableToJSON(data) or "{}"
    net.Start("GRID_SendGangData")
    net.WriteString(jsonStr)
    net.Send(ply)
end

local function HandleRequestGangData(len, ply)
    if not IsValid(ply) then return end
    if not GRID.CheckRateLimit(ply, "gang_sync", 4) then return end
    GRID.Gangs.SendSync(ply)
end

net.Receive("GRID_RequestGangData", HandleRequestGangData)

local function HandleGangUIAction(len, ply)
    if not IsValid(ply) then return end
    if not GRID.CheckRateLimit(ply, "gang_action", 5) then return end

    local action = net.ReadString()
    local payload = util.JSONToTable(net.ReadString() or "{}") or {}

    -- 1. Create Gang
    if action == "create" then
        local gangName = string.Trim(payload.name or "")
        if not ply:IsGangFaction() then
            GRID.Notify(ply, "Only Street Gang members can create a gang! Switch to a Gang role in F4 first.",
                NOTIFY_ERROR)
            return
        end
        if #gangName < 2 or #gangName > 24 then
            GRID.Notify(ply, "Gang name must be between 2 and 24 characters!", NOTIFY_ERROR)
            return
        end
        local lower = string.lower(gangName)
        if lower == "police" or lower == "neutral" or lower == "citizens" then
            GRID.Notify(ply, "That gang name is reserved!", NOTIFY_ERROR)
            return
        end
        if ply:HasStoredGang() then
            GRID.Notify(ply, "You are already in a gang ('" .. ply:GetRawGang() .. "')! Leave it first.", NOTIFY_ERROR)
            return
        end
        if GRID.Database and GRID.Database.GetGang and GRID.Database.GetGang(gangName) then
            GRID.Notify(ply, "A gang with that name already exists!", NOTIFY_ERROR)
            return
        end
        local cost = (GRID.Config and GRID.Config.GangCreationCost) or 500
        if not ply:CanAfford(cost) then
            GRID.Notify(ply, "Creating a gang costs $" .. cost .. "!", NOTIFY_ERROR)
            return
        end

        ply:AddMoney(-cost)
        ply:SetGang(gangName)
        ply:SetNWBool("GRID_IsGangLeader", true)

        if GRID.Database and GRID.Database.CreateGang then
            GRID.Database.CreateGang(gangName, ply:SteamID())
        end

        GRID.Notify(ply, "Congratulations! You founded the gang '" .. gangName .. "'!", NOTIFY_GENERIC)
        GRID.NotifyAll(string.format("%s founded a new street gang: '%s'", ply:Nick(), gangName), NOTIFY_HINT, 6)
        GRID.Gangs.SendSync(ply)

        -- 2. Vault Deposit
    elseif action == "deposit" then
        if not ply:IsGangFaction() then
            GRID.Notify(ply, "You must be active on the Street Gang faction to access the vault!", NOTIFY_ERROR)
            return
        end
        local gang = ply:GetGang()
        if gang == "" then return end
        local amt = math.floor(tonumber(payload.amount) or 0)
        if amt <= 0 or not ply:CanAfford(amt) then
            GRID.Notify(ply, "Invalid amount or insufficient funds!", NOTIFY_ERROR)
            return
        end
        if GRID.Database and GRID.Database.TransferGangVault then
            GRID.Database.TransferGangVault(ply:SteamID(), gang, amt)
        else
            ply:AddMoney(-amt)
            if GRID.Database and GRID.Database.AddGangBank then
                GRID.Database.AddGangBank(gang, amt)
            end
        end
        if GRID.Telemetry and GRID.Telemetry.Log then
            GRID.Telemetry.Log("ECONOMY", "GANG_VAULT_DEPOSIT", ply:SteamID(), gang, amt, {})
        end
        GRID.Notify(ply, string.format("Deposited +$%s into the gang vault!", string.Comma(amt)), NOTIFY_GENERIC)
        GRID.Gangs.SendSync(ply)

        -- 3. Vault Withdrawal
    elseif action == "withdraw" then
        if not ply:IsGangFaction() then
            GRID.Notify(ply, "You must be active on the Street Gang faction to access the vault!", NOTIFY_ERROR)
            return
        end
        local gang = ply:GetGang()
        if gang == "" then return end
        local isLeader = ply:GetNWBool("GRID_IsGangLeader", false) or (ply.GetJob and ply:GetJob() == "gang_leader") or
        ply:IsAdmin()
        if not isLeader then
            GRID.Notify(ply, "Only the Gang Leader can withdraw funds from the gang vault!", NOTIFY_ERROR)
            return
        end
        local amt = math.floor(tonumber(payload.amount) or 0)
        if amt <= 0 then return end
        local gData = GRID.Database and GRID.Database.GetGang and GRID.Database.GetGang(gang)
        local bank = gData and tonumber(gData.bank) or 0
        if amt > bank then
            GRID.Notify(ply, string.format("The vault only contains $%s!", string.Comma(bank)), NOTIFY_ERROR)
            return
        end
        if GRID.Database and GRID.Database.TransferGangVault then
            GRID.Database.TransferGangVault(ply:SteamID(), gang, -amt)
        else
            if GRID.Database and GRID.Database.AddGangBank then
                GRID.Database.AddGangBank(gang, -amt)
            end
            ply:AddMoney(amt)
        end
        if GRID.Telemetry and GRID.Telemetry.Log then
            GRID.Telemetry.Log("ECONOMY", "GANG_VAULT_WITHDRAW", ply:SteamID(), gang, amt, {})
        end
        GRID.Notify(ply, string.format("Withdrew $%s from the gang vault!", string.Comma(amt)), NOTIFY_GENERIC)
        GRID.Gangs.SendSync(ply)

        -- 4. Set Territory Tax Rate
    elseif action == "settax" then
        if not ply:IsGangFaction() then return end
        local gang = ply:GetGang()
        if gang == "" then return end
        local isLeader = ply:GetNWBool("GRID_IsGangLeader", false) or ply:IsAdmin()
        if not isLeader then
            GRID.Notify(ply, "Only the gang leader can configure territory taxes!", NOTIFY_ERROR)
            return
        end
        local turfId = tonumber(payload.turfId)
        local rate = math.Clamp(math.floor(tonumber(payload.rate) or 10), 5, 30)
        if turfId and GRID.Turf and GRID.Turf.Zones and GRID.Turf.Zones[turfId] then
            local zone = GRID.Turf.Zones[turfId]
            if zone.owner and string.lower(zone.owner) == string.lower(gang) then
                GRID.Turf.SetTaxRate(turfId, rate, ply)
                GRID.Gangs.SendSync(ply)
            end
        end

        -- 5. Invite Player
    elseif action == "invite" then
        if not ply:IsGangFaction() then
            GRID.Notify(ply, "Switch to Street Gangs to invite members.", NOTIFY_ERROR)
            return
        end
        local gang = ply:GetGang()
        if gang == "" then return end
        local targetNick = string.Trim(payload.target or "")
        local target = nil
        for _, p in ipairs(player.GetAll()) do
            if string.lower(p:Nick()) == string.lower(targetNick) or p:SteamID() == targetNick then
                target = p
                break
            end
        end
        if not IsValid(target) or target == ply then
            GRID.Notify(ply, "Player not found or invalid!", NOTIFY_ERROR)
            return
        end
        if not target:IsGangFaction() then
            GRID.Notify(ply, target:Nick() .. " must switch to Street Gangs before joining a gang!", NOTIFY_ERROR)
            return
        end
        if target:HasStoredGang() then
            GRID.Notify(ply, target:Nick() .. " is already in a gang!", NOTIFY_ERROR)
            return
        end
        GRID.GangInvites[target:SteamID()] = gang
        GRID.Notify(ply, "Invited " .. target:Nick() .. " to '" .. gang .. "'!", NOTIFY_GENERIC)
        GRID.Notify(target, ply:Nick() .. " invited you to join gang '" .. gang .. "'! Type /acceptgang to join.",
            NOTIFY_HINT, 10)

        -- 6. Kick Member (Leader only)
    elseif action == "kick" then
        if not ply:IsGangFaction() then return end
        local gang = ply:GetGang()
        local isLeader = ply:GetNWBool("GRID_IsGangLeader", false) or ply:IsAdmin()
        if not isLeader then
            GRID.Notify(ply, "Only the gang leader can kick members!", NOTIFY_ERROR)
            return
        end
        local targetSteamID = payload.steamid
        if not targetSteamID or targetSteamID == ply:SteamID() then return end
        if GRID.Database and GRID.Database.RemoveGangMember then
            GRID.Database.RemoveGangMember(targetSteamID)
        end
        for _, p in ipairs(player.GetAll()) do
            if p:SteamID() == targetSteamID then
                p:SetGang("")
                p:SetNWBool("GRID_IsGangLeader", false)
                GRID.Notify(p, "You were removed from gang '" .. gang .. "'.", NOTIFY_ERROR)
                break
            end
        end
        GRID.Notify(ply, "Member removed from gang.", NOTIFY_GENERIC)
        GRID.Gangs.SendSync(ply)

        -- 7. Leave Gang (Safe for off-duty as well)
    elseif action == "leave" then
        local storedGang = ply:GetRawGang()
        if storedGang == "" then return end
        ply:SetGang("")
        ply:SetNWBool("GRID_IsGangLeader", false)
        if GRID.Database and GRID.Database.RemoveGangMember then
            GRID.Database.RemoveGangMember(ply:SteamID())
        end
        GRID.Notify(ply, "You left the gang '" .. storedGang .. "'.", NOTIFY_GENERIC)
        GRID.Gangs.SendSync(ply)

        -- 8. Disband Gang (Leader only)
    elseif action == "disband" then
        local gang = ply:GetRawGang()
        if gang == "" then return end
        local isLeader = ply:GetNWBool("GRID_IsGangLeader", false) or ply:IsAdmin()
        if not isLeader then
            GRID.Notify(ply, "Only the gang leader can disband the gang!", NOTIFY_ERROR)
            return
        end
        if GRID.Database and GRID.Database.DisbandGang then
            GRID.Database.DisbandGang(gang)
        end
        for _, p in ipairs(player.GetAll()) do
            if p:GetRawGang() == gang then
                p:SetGang("")
                p:SetNWBool("GRID_IsGangLeader", false)
                GRID.Notify(p, "Your gang '" .. gang .. "' was disbanded by the leader.", NOTIFY_ERROR)
            end
        end
        GRID.Gangs.SendSync(ply)
    end
end

net.Receive("GRID_GangUIAction", HandleGangUIAction)
