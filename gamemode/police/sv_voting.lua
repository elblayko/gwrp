--[[
    gamemode/police/sv_voting.lua
    GridRP Police Department Warrant Voting System - Server Controller
    Author: GRID Core Team
--]]

include("sh_voting.lua")

GRID.PoliceVoting.ActiveVote = nil

local function GetOnlinePolice()
    local police = {}
    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) and p:IsPolice() then
            table.insert(police, p)
        end
    end
    return police
end

function GRID.PoliceVoting.MayorWarrant(mayor, target, reason)
    if not IsValid(target) or not target:IsPlayer() then return false end
    if target:IsWanted() then
        if IsValid(mayor) then GRID.Notify(mayor, target:Nick() .. " is already wanted!", NOTIFY_ERROR) end
        return false
    end

    reason = reason or "Mayor Executive Warrant"
    target:AddBuff("wanted", 180, {
        reason = reason,
        officer = IsValid(mayor) and ("Mayor " .. mayor:Nick()) or "Executive Order"
    })

    for _, p in ipairs(player.GetAll()) do
        if p:IsPolice() then
            GRID.Notify(p, string.format("[MAYOR EXECUTIVE WARRANT] %s is now WANTED! Reason: %s", target:Nick(), reason), NOTIFY_HINT, 10)
        end
    end

    return true
end

function GRID.PoliceVoting.EndVote(passed)
    local vote = GRID.PoliceVoting.ActiveVote
    if not vote then return end

    timer.Remove("GRID_PoliceVoteCountdown")
    GRID.PoliceVoting.ActiveVote = nil

    -- Inform all police that vote concluded
    net.Start("GRID_PoliceVoteEnd")
    net.WriteBool(passed)
    for _, p in ipairs(GetOnlinePolice()) do
        net.Send(p)
    end

    if passed then
        local target = vote.target
        if IsValid(target) and target:IsPlayer() and not target:IsWanted() then
            target:AddBuff("wanted", 180, {
                reason = vote.reason,
                officer = "Department Vote (" .. vote.initiatorNick .. ")"
            })

            for _, p in ipairs(GetOnlinePolice()) do
                GRID.Notify(p, string.format("[WARRANT APPROVED] Majority vote passed! %s is now WANTED for '%s'.", target:Nick(), vote.reason), NOTIFY_GENERIC, 8)
                p:EmitSound("ambient/alarms/warningbell1.wav", 65, 110)
            end
        end
    else
        for _, p in ipairs(GetOnlinePolice()) do
            GRID.Notify(p, string.format("[WARRANT REJECTED] Department vote to flag %s failed.", vote.targetNick), NOTIFY_ERROR, 6)
        end
    end
end

function GRID.PoliceVoting.CheckVoteThreshold()
    local vote = GRID.PoliceVoting.ActiveVote
    if not vote then return end

    local police = GetOnlinePolice()
    local totalPolice = #police
    if totalPolice <= 0 then
        GRID.PoliceVoting.EndVote(false)
        return
    end

    local yesCount = 0
    local noCount = 0
    for _, decision in pairs(vote.votes) do
        if decision == true then
            yesCount = yesCount + 1
        elseif decision == false then
            noCount = noCount + 1
        end
    end

    -- Majority check (>50% of department)
    local needed = math.floor(totalPolice / 2) + 1
    if yesCount >= needed then
        GRID.PoliceVoting.EndVote(true)
        return
    end

    if noCount > (totalPolice - needed) then
        GRID.PoliceVoting.EndVote(false)
        return
    end
end

function GRID.PoliceVoting.StartVote(initiator, target, reason)
    if not IsValid(initiator) or not initiator:IsPolice() then
        GRID.Notify(initiator, "Only police officers can call a department warrant vote!", NOTIFY_ERROR)
        return false
    end

    if not IsValid(target) or not target:IsPlayer() then
        GRID.Notify(initiator, "Invalid target player.", NOTIFY_ERROR)
        return false
    end

    if target == initiator then
        GRID.Notify(initiator, "You cannot warrant yourself!", NOTIFY_ERROR)
        return false
    end

    if target:IsPolice() and not initiator:IsAdmin() then
        GRID.Notify(initiator, "You cannot warrant fellow police officers!", NOTIFY_ERROR)
        return false
    end

    if target:IsWanted() then
        GRID.Notify(initiator, target:Nick() .. " is already wanted!", NOTIFY_ERROR)
        return false
    end

    if GRID.PoliceVoting.ActiveVote then
        GRID.Notify(initiator, "A warrant vote is already in progress. Please wait for it to conclude.", NOTIFY_ERROR)
        return false
    end

    reason = (reason and reason ~= "") and reason or "Probable Cause / Officer Discretion"
    local police = GetOnlinePolice()

    -- Solo officer edge-case: immediate approval
    if #police <= 1 then
        target:AddBuff("wanted", 180, {
            reason = reason,
            officer = initiator:Nick()
        })
        GRID.Notify(initiator, string.format("Sole officer on duty: %s has been flagged as WANTED for '%s'.", target:Nick(), reason), NOTIFY_GENERIC, 8)
        return true
    end

    GRID.PoliceVoting.ActiveVote = {
        target = target,
        targetNick = target:Nick(),
        initiator = initiator,
        initiatorNick = initiator:Nick(),
        reason = reason,
        votes = {
            [initiator:SteamID()] = true -- Initiator automatically votes YES
        },
        endTime = CurTime() + GRID.PoliceVoting.VoteDuration
    }

    -- Broadcast vote card to all police
    net.Start("GRID_PoliceVoteStart")
    net.WriteEntity(target)
    net.WriteString(target:Nick())
    net.WriteString(reason)
    net.WriteString(initiator:Nick())
    net.WriteFloat(GRID.PoliceVoting.VoteDuration)

    for _, p in ipairs(police) do
        net.Send(p)
    end

    -- Timer for expiration
    timer.Create("GRID_PoliceVoteCountdown", GRID.PoliceVoting.VoteDuration, 1, function()
        if not GRID.PoliceVoting.ActiveVote then return end

        local yesCount = 0
        local noCount = 0
        for _, dec in pairs(GRID.PoliceVoting.ActiveVote.votes) do
            if dec == true then yesCount = yesCount + 1 else noCount = noCount + 1 end
        end

        local passed = (yesCount > noCount)
        GRID.PoliceVoting.EndVote(passed)
    end)

    return true
end

-- Network receiver for cast vote
net.Receive("GRID_PoliceCastVote", function(len, ply)
    if not IsValid(ply) or not ply:IsPolice() then return end
    if not GRID.PoliceVoting.ActiveVote then return end

    local voteChoice = net.ReadBool()
    local sid = ply:SteamID()

    GRID.PoliceVoting.ActiveVote.votes[sid] = voteChoice
    GRID.Notify(ply, string.format("You voted %s on the warrant for %s.", voteChoice and "YES" or "NO", GRID.PoliceVoting.ActiveVote.targetNick), NOTIFY_HINT, 3)

    GRID.PoliceVoting.CheckVoteThreshold()
end)

-- Chat commands
hook.Add("PlayerSay", "GRID_PoliceVotingChatCommands", function(ply, text)
    local lower = string.lower(string.Trim(text))

    if string.StartWith(lower, "/votewanted ") or string.StartWith(lower, "!votewanted ") then
        if not ply:IsPolice() and not ply:IsAdmin() then
            GRID.Notify(ply, "Only law enforcement officers can start a warrant vote!", NOTIFY_ERROR)
            return ""
        end

        local raw = string.Trim(string.sub(text, 12))
        local space = string.find(raw, " ")
        local namePart = space and string.sub(raw, 1, space - 1) or raw
        local reasonPart = space and string.Trim(string.sub(raw, space + 1)) or "Suspicious Criminal Activity"

        local targetPly = nil
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(namePart), 1, true) then
                targetPly = p
                break
            end
        end

        if not IsValid(targetPly) then
            GRID.Notify(ply, "Suspect player not found. Usage: /votewanted <name> [reason]", NOTIFY_ERROR)
            return ""
        end

        GRID.PoliceVoting.StartVote(ply, targetPly, reasonPart)
        return ""
    end
end)

