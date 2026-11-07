--[[
    gamemode/police/sv_jail.lua
    GridRP Jail, Sentence, Bail & Holding Cell System - Server Engine
    Author: GRID Core Team
--]]

include("sh_jail.lua")

GRID.Jail.ActiveSentences = GRID.Jail.ActiveSentences or {}

local DATA_DIR = "gridrp/jail"
local function GetSaveFilePath()
    return string.format("%s/%s.json", DATA_DIR, game.GetMap())
end

local function GetDBKey()
    return "jail_profile_" .. string.lower(game.GetMap())
end

function GRID.Jail.SavePoints()
    local data = {
        points = GRID.Jail.Points or {},
        releasePoint = GRID.Jail.ReleasePoint or nil
    }

    local json = util.TableToJSON(data, true)

    -- 1. Primary Database Persistence: MariaDB / SQLite grid_settings table for current map
    if GRID.Database and GRID.Database.SetSetting then
        GRID.Database.SetSetting(GetDBKey(), json)
        print(string.format("[GRID Jail DB] Persisted %d jail cells to MariaDB for map '%s'.", #GRID.Jail.Points, game.GetMap()))
    end

    -- 2. Secondary Snapshot: Local JSON backup on disk
    if not file.IsDir(DATA_DIR, "DATA") then
        file.CreateDir(DATA_DIR)
    end
    file.Write(GetSaveFilePath(), json)
end

function GRID.Jail.LoadPoints()
    local mapKey = GetDBKey()
    local dbJson = GRID.Database and GRID.Database.GetSetting and GRID.Database.GetSetting(mapKey, nil)

    if dbJson and dbJson ~= "" then
        local tbl = util.JSONToTable(dbJson)
        if tbl then
            GRID.Jail.Points = tbl.points or {}
            GRID.Jail.ReleasePoint = tbl.releasePoint or nil
            print(string.format("[GRID Jail DB] Loaded %d jail cells from MariaDB for map '%s'.", #GRID.Jail.Points, game.GetMap()))
            return
        end
    end

    -- Fallback to local JSON snapshot
    local path = GetSaveFilePath()
    if file.Exists(path, "DATA") then
        local raw = file.Read(path, "DATA")
        if raw and raw ~= "" then
            local tbl = util.JSONToTable(raw)
            if tbl then
                GRID.Jail.Points = tbl.points or {}
                GRID.Jail.ReleasePoint = tbl.releasePoint or nil
                print(string.format("[GRID Jail] Loaded %d jail cells from local disk snapshot for map '%s'.", #GRID.Jail.Points, game.GetMap()))

                -- Migrate disk snapshot into MariaDB if connected
                if GRID.Database and GRID.Database.SetSetting then
                    GRID.Database.SetSetting(mapKey, raw)
                end
                return
            end
        end
    end

    GRID.Jail.Points = {}
    GRID.Jail.ReleasePoint = nil
end

hook.Add("Initialize", "GRID_JailLoadPoints", function()
    GRID.Jail.LoadPoints()
end)

hook.Add("GRID_DatabaseConnected", "GRID_JailOnDatabaseConnected", function()
    GRID.Jail.LoadPoints()
end)

-- Find optimal cell furthest from already occupied cells
function GRID.Jail.GetBestCell()
    if not GRID.Jail.Points or #GRID.Jail.Points == 0 then
        return nil
    end

    local occupiedPositions = {}
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() and ply:IsJailed() then
            table.insert(occupiedPositions, ply:GetPos())
        end
    end

    -- If no current prisoners, choose a random cell
    if #occupiedPositions == 0 then
        local pt = table.Random(GRID.Jail.Points)
        return pt.pos, pt.ang
    end

    local bestPoint = nil
    local maxMinDist = -1

    for _, pt in ipairs(GRID.Jail.Points) do
        local minDist = math.huge
        for _, occPos in ipairs(occupiedPositions) do
            local d = pt.pos:DistToSqr(occPos)
            if d < minDist then
                minDist = d
            end
        end

        if minDist > maxMinDist then
            maxMinDist = minDist
            bestPoint = pt
        end
    end

    bestPoint = bestPoint or GRID.Jail.Points[1]
    return bestPoint.pos, bestPoint.ang
end

-- Jail execution
function GRID.Jail.JailPlayer(target, officer, duration, bail)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then return false end
    if target:IsJailed() then return false end

    local cellPos, cellAng = GRID.Jail.GetBestCell()
    if not cellPos then
        if IsValid(officer) then
            GRID.Notify(officer, "No jail points configured on this map! An admin must use /setjail or Admin HUD.", NOTIFY_ERROR, 8)
        end
        return false
    end

    duration = duration or GRID.Jail.DefaultSentence
    bail = bail or GRID.Jail.DefaultBail

    -- Confiscate current weapons
    local confiscated = {}
    for _, wep in ipairs(target:GetWeapons()) do
        if IsValid(wep) then
            local class = wep:GetClass()
            if class ~= "weapon_fists" and class ~= "fists" then
                table.insert(confiscated, {
                    class = class,
                    clip1 = wep:Clip1(),
                    clip2 = wep:Clip2()
                })
            end
        end
    end
    target.GRID_ConfiscatedWeapons = confiscated

    target:StripWeapons()
    target:Give("weapon_fists")

    -- Teleport to designated cell
    target:SetPos(cellPos + Vector(0, 0, 5))
    if cellAng then target:SetEyeAngles(cellAng) end
    target:SetVelocity(Vector(0, 0, 0))

    -- Remove wanted debuff
    if target.RemoveBuff then
        target:RemoveBuff("wanted", "arrested")
    end
    target:SetNWBool("GRID_IsWanted", false)

    -- Set Jailed state
    local releaseTime = CurTime() + duration
    target:SetNWBool("GRID_IsJailed", true)
    target:SetNWFloat("GRID_JailReleaseTime", releaseTime)
    target:SetNWInt("GRID_JailBail", bail)

    GRID.Jail.ActiveSentences[target:SteamID()] = {
        releaseTime = releaseTime,
        bail = bail,
        confiscated = confiscated
    }

    -- Notifications
    local officerName = IsValid(officer) and officer:Nick() or "Civil Protection"
    GRID.Notify(target, string.format("You were arrested by %s! Sentence: %ds. Bail: $%d.", officerName, duration, bail), NOTIFY_ERROR, 10)

    if IsValid(officer) and officer:IsPlayer() then
        GRID.Notify(officer, string.format("Successfully booked %s! +$150 Booking Bounty & +75 XP.", target:Nick()), NOTIFY_GENERIC, 8)
        officer:AddMoney(150)
        if officer.AddXP then officer:AddXP(75, "Criminal Apprehension") end
    end

    -- Broadcast dispatch message to police
    for _, p in ipairs(player.GetAll()) do
        if p:IsPolice() and p ~= officer then
            GRID.Notify(p, string.format("[LSPD DISPATCH] Suspect %s was booked by %s (%ds sentence).", target:Nick(), officerName, duration), NOTIFY_HINT, 6)
        end
    end

    return true
end

-- Unjail execution
function GRID.Jail.UnjailPlayer(target, reason)
    if not IsValid(target) or not target:IsPlayer() then return end
    if not target:IsJailed() then return end

    local sid = target:SteamID()
    GRID.Jail.ActiveSentences[sid] = nil

    target:SetNWBool("GRID_IsJailed", false)
    target:SetNWFloat("GRID_JailReleaseTime", 0)
    target:SetNWInt("GRID_JailBail", 0)

    -- Teleport to release point or spawn
    if GRID.Jail.ReleasePoint and GRID.Jail.ReleasePoint.pos then
        target:SetPos(GRID.Jail.ReleasePoint.pos + Vector(0, 0, 5))
        if GRID.Jail.ReleasePoint.ang then target:SetEyeAngles(GRID.Jail.ReleasePoint.ang) end
    else
        target:Spawn()
    end

    -- Restore confiscated weapons
    if target.GRID_ConfiscatedWeapons then
        for _, item in ipairs(target.GRID_ConfiscatedWeapons) do
            local wep = target:Give(item.class)
            if IsValid(wep) then
                if item.clip1 and item.clip1 >= 0 then wep:SetClip1(item.clip1) end
                if item.clip2 and item.clip2 >= 0 then wep:SetClip2(item.clip2) end
            end
        end
        target.GRID_ConfiscatedWeapons = nil
    end

    if reason == "bail" then
        GRID.Notify(target, "Bail was posted! You have been released from holding.", NOTIFY_GENERIC, 8)
    else
        GRID.Notify(target, "Your jail sentence has expired! You are free to go.", NOTIFY_GENERIC, 8)
    end
end

-- Bail payment
function GRID.Jail.PayBail(payer, prisoner)
    if not IsValid(payer) or not IsValid(prisoner) or not prisoner:IsJailed() then return false end

    local cost = prisoner:GetJailBail()
    if cost <= 0 then cost = GRID.Jail.DefaultBail end

    if not payer:CanAfford(cost) then
        GRID.Notify(payer, string.format("Insufficient funds to post bail ($%s required)!", string.Comma(cost)), NOTIFY_ERROR)
        return false
    end

    payer:AddMoney(-cost)
    GRID.Notify(payer, string.format("Posted $%s bail for %s.", string.Comma(cost), prisoner:Nick()), NOTIFY_HINT, 6)

    GRID.Jail.UnjailPlayer(prisoner, "bail")
    return true
end

-- ========================================================
-- TASER RAGDOLL CONTROLLER (3-SECOND NON-LETHAL IMMOBILIZATION)
-- ========================================================

function GRID.Jail.TasePlayer(target)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then return end
    if target.GRID_IsTased then return end
    if target:InVehicle() then target:ExitVehicle() end

    target.GRID_IsTased = true
    local oldHealth = target:Health()
    local oldArmor = target:Armor()
    local oldPos = target:GetPos()

    -- Save active loadout
    local savedWeapons = {}
    for _, wep in ipairs(target:GetWeapons()) do
        if IsValid(wep) then
            table.insert(savedWeapons, {
                class = wep:GetClass(),
                clip1 = wep:Clip1(),
                clip2 = wep:Clip2()
            })
        end
    end
    local activeWep = target:GetActiveWeapon()
    local activeClass = IsValid(activeWep) and activeWep:GetClass() or ""

    -- Create physics ragdoll clone
    local ragdoll = ents.Create("prop_ragdoll")
    ragdoll:SetModel(target:GetModel())
    ragdoll:SetPos(target:GetPos())
    ragdoll:SetAngles(target:GetAngles())
    ragdoll:SetSkin(target:GetSkin())
    for i = 0, target:GetNumBodyGroups() - 1 do
        ragdoll:SetBodygroup(i, target:GetBodygroup(i))
    end
    ragdoll:Spawn()
    ragdoll:Activate()
    ragdoll:SetCollisionGroup(COLLISION_GROUP_WEAPON)

    -- Transfer velocities to physics bones
    local plyVel = target:GetVelocity()
    for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            local boneIdx = ragdoll:TranslatePhysBoneToBone(i)
            local bPos, bAng = target:GetBonePosition(boneIdx)
            if bPos and bAng then
                phys:SetPos(bPos)
                phys:SetAngles(bAng)
            end
            phys:SetVelocity(plyVel)
            phys:Wake()
        end
    end

    -- Electrical spark effects loop on ragdoll
    local zapTimerId = "GRID_TaserZaps_" .. target:EntIndex()
    timer.Create(zapTimerId, 0.4, 7, function()
        if IsValid(ragdoll) then
            local ed = EffectData()
            ed:SetOrigin(ragdoll:GetPos() + Vector(0, 0, 25))
            ed:SetMagnitude(2)
            ed:SetScale(1)
            util.Effect("TeslaHitBoxes", ed)
            ragdoll:EmitSound("ambient/energy/zap" .. math.random(1, 3) .. ".wav", 65, math.random(110, 130))
        end
    end)

    -- Lock player to spectating ragdoll
    target:StripWeapons()
    target:Spectate(OBS_MODE_CHASE)
    target:SpectateEntity(ragdoll)

    -- Recover after 3 seconds
    timer.Simple(3.0, function()
        timer.Remove(zapTimerId)
        if not IsValid(target) then
            if IsValid(ragdoll) then ragdoll:Remove() end
            return
        end

        local unragdollPos = oldPos
        if IsValid(ragdoll) then
            unragdollPos = ragdoll:GetPos() + Vector(0, 0, 8)
            ragdoll:Remove()
        end

        -- Safe hull un-stuck check
        local tr = util.TraceHull({
            start = unragdollPos,
            endpos = unragdollPos + Vector(0, 0, 20),
            mins = Vector(-16, -16, 0),
            maxs = Vector(16, 16, 72),
            mask = MASK_PLAYERSOLID
        })
        if tr.Hit then
            unragdollPos = tr.HitPos
        end

        target:UnSpectate()
        target:Spawn()
        target:SetPos(unragdollPos)
        target:SetHealth(oldHealth)
        target:SetArmor(oldArmor)

        -- Restore weapons
        target:StripWeapons()
        for _, it in ipairs(savedWeapons) do
            local w = target:Give(it.class)
            if IsValid(w) then
                if it.clip1 >= 0 then w:SetClip1(it.clip1) end
                if it.clip2 >= 0 then w:SetClip2(it.clip2) end
            end
        end
        if activeClass ~= "" then
            target:SelectWeapon(activeClass)
        end

        target.GRID_IsTased = false
        GRID.Notify(target, "You have recovered from the taser shock.", NOTIFY_GENERIC, 4)
    end)
end

-- Network receiver for bail payment
net.Receive("GRID_JailPayBail", function(len, ply)
    if not IsValid(ply) then return end
    local prisoner = net.ReadEntity()
    if not IsValid(prisoner) then
        prisoner = ply
    end

    GRID.Jail.PayBail(ply, prisoner)
end)

-- Regular timer tick to release expired prisoners
timer.Create("GRID_JailSentenceTicker", 1, 0, function()
    local now = CurTime()
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsJailed() then
            local relTime = ply:GetNWFloat("GRID_JailReleaseTime", 0)
            if relTime > 0 and now >= relTime then
                GRID.Jail.UnjailPlayer(ply, "time")
            end
        end
    end
end)

-- Reconnection and Death persistence
hook.Add("PlayerInitialSpawn", "GRID_JailReconnectHandler", function(ply)
    local sid = ply:SteamID()
    local record = GRID.Jail.ActiveSentences[sid]
    if record and CurTime() < record.releaseTime then
        ply:SetNWBool("GRID_IsJailed", true)
        ply:SetNWFloat("GRID_JailReleaseTime", record.releaseTime)
        ply:SetNWInt("GRID_JailBail", record.bail)
        ply.GRID_ConfiscatedWeapons = record.confiscated
    end
end)

hook.Add("PlayerSpawn", "GRID_JailSpawnKeeper", function(ply)
    if ply:IsJailed() then
        timer.Simple(0.1, function()
            if IsValid(ply) and ply:IsJailed() then
                local cellPos, cellAng = GRID.Jail.GetBestCell()
                if cellPos then
                    ply:SetPos(cellPos + Vector(0, 0, 5))
                    if cellAng then ply:SetEyeAngles(cellAng) end
                end
                ply:StripWeapons()
                ply:Give("weapon_fists")
            end
        end)
    end
end)

-- Admin HUD Network Actions
net.Receive("GRID_JailAdminAction", function(len, ply)
    if not IsValid(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then return end

    local action = net.ReadString()
    if action == "add_cell" then
        local pos = ply:GetPos()
        local ang = ply:GetAngles()
        table.insert(GRID.Jail.Points, { pos = pos, ang = ang })
        GRID.Jail.SavePoints()
        GRID.Notify(ply, string.format("Added Jail Cell #%d at your position.", #GRID.Jail.Points), NOTIFY_GENERIC)
        GRID.Jail.SyncPointsToAdmin(ply)
    elseif action == "remove_cell" then
        local idx = net.ReadInt(16)
        if GRID.Jail.Points[idx] then
            table.remove(GRID.Jail.Points, idx)
            GRID.Jail.SavePoints()
            GRID.Notify(ply, string.format("Removed Jail Cell #%d.", idx), NOTIFY_GENERIC)
            GRID.Jail.SyncPointsToAdmin(ply)
        end
    elseif action == "clear_cells" then
        GRID.Jail.Points = {}
        GRID.Jail.SavePoints()
        GRID.Notify(ply, "Cleared all jail cells for this map.", NOTIFY_GENERIC)
        GRID.Jail.SyncPointsToAdmin(ply)
    elseif action == "set_release" then
        GRID.Jail.ReleasePoint = { pos = ply:GetPos(), ang = ply:GetAngles() }
        GRID.Jail.SavePoints()
        GRID.Notify(ply, "Set jail public release point at your position.", NOTIFY_GENERIC)
        GRID.Jail.SyncPointsToAdmin(ply)
    elseif action == "teleport_cell" then
        local idx = net.ReadInt(16)
        local pt = GRID.Jail.Points[idx]
        if pt then
            ply:SetPos(pt.pos + Vector(0, 0, 5))
            if pt.ang then ply:SetEyeAngles(pt.ang) end
            GRID.Notify(ply, string.format("Teleported to Jail Cell #%d.", idx), NOTIFY_HINT)
        end
    elseif action == "request_points" then
        GRID.Jail.SyncPointsToAdmin(ply)
    end
end)

function GRID.Jail.SyncPointsToAdmin(ply)
    if not IsValid(ply) then return end
    net.Start("GRID_JailSyncPoints")
    net.WriteUInt(#GRID.Jail.Points, 16)
    for i, pt in ipairs(GRID.Jail.Points) do
        net.WriteVector(pt.pos)
        net.WriteAngle(pt.ang or Angle(0, 0, 0))
    end
    net.WriteBool(GRID.Jail.ReleasePoint ~= nil)
    if GRID.Jail.ReleasePoint then
        net.WriteVector(GRID.Jail.ReleasePoint.pos)
        net.WriteAngle(GRID.Jail.ReleasePoint.ang or Angle(0, 0, 0))
    end
    net.Send(ply)
end

-- Chat Commands
hook.Add("PlayerSay", "GRID_JailChatCommands", function(ply, text)
    local lower = string.lower(string.Trim(text))

    if lower == "/setjail" or lower == "!setjail" then
        if not ply:IsAdmin() and not ply:IsSuperAdmin() then
            GRID.Notify(ply, "Admins only!", NOTIFY_ERROR)
            return ""
        end
        table.insert(GRID.Jail.Points, { pos = ply:GetPos(), ang = ply:GetAngles() })
        GRID.Jail.SavePoints()
        GRID.Notify(ply, string.format("Jail cell #%d registered at current coordinates.", #GRID.Jail.Points), NOTIFY_GENERIC)
        return ""
    end

    if lower == "/clearjail" or lower == "!clearjail" then
        if not ply:IsAdmin() and not ply:IsSuperAdmin() then
            GRID.Notify(ply, "Admins only!", NOTIFY_ERROR)
            return ""
        end
        GRID.Jail.Points = {}
        GRID.Jail.SavePoints()
        GRID.Notify(ply, "Cleared all jail cells for this map.", NOTIFY_GENERIC)
        return ""
    end

    if lower == "/setjailrelease" or lower == "!setjailrelease" then
        if not ply:IsAdmin() and not ply:IsSuperAdmin() then
            GRID.Notify(ply, "Admins only!", NOTIFY_ERROR)
            return ""
        end
        GRID.Jail.ReleasePoint = { pos = ply:GetPos(), ang = ply:GetAngles() }
        GRID.Jail.SavePoints()
        GRID.Notify(ply, "Jail release point registered at current coordinates.", NOTIFY_GENERIC)
        return ""
    end

    if string.StartWith(lower, "/unjail ") or string.StartWith(lower, "!unjail ") then
        if not ply:IsPolice() and not ply:IsAdmin() then
            GRID.Notify(ply, "Only Law Enforcement or Admins can unjail players!", NOTIFY_ERROR)
            return ""
        end
        local targetNick = string.Trim(string.sub(text, 8))
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(targetNick), 1, true) then
                if p:IsJailed() then
                    GRID.Jail.UnjailPlayer(p, "officer_pardon")
                    GRID.Notify(ply, string.format("Unjailed %s.", p:Nick()), NOTIFY_GENERIC)
                else
                    GRID.Notify(ply, string.format("%s is not currently jailed.", p:Nick()), NOTIFY_ERROR)
                end
                return ""
            end
        end
        GRID.Notify(ply, "Player not found.", NOTIFY_ERROR)
        return ""
    end

    if string.StartWith(lower, "/paybail") or string.StartWith(lower, "!paybail") then
        local target = ply
        local args = string.Explode(" ", string.Trim(text))
        if args[2] then
            for _, p in ipairs(player.GetAll()) do
                if string.find(string.lower(p:Nick()), string.lower(args[2]), 1, true) then
                    target = p
                    break
                end
            end
        end
        if target:IsJailed() then
            GRID.Jail.PayBail(ply, target)
        else
            GRID.Notify(ply, "Selected player is not currently in jail.", NOTIFY_ERROR)
        end
        return ""
    end
end)
