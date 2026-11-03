--[[
    sv_buffs.lua - Server-Side Buff Engine, State Machine, SQLite Persistence & Network Sync
    Author: Toxic
--]]

GWRP.Buffs = GWRP.Buffs or {}

-- ========================================================
-- BUFF APPLICATION, REMOVAL & SYNC API
-- ========================================================

local meta = FindMetaTable("Player")
if meta then
    --- Adds or stacks a buff on the player.
    -- @param buffId (string) Unique ID
    -- @param duration (number|nil) Custom duration in seconds, or nil for default
    -- @param customData (table|nil) Metadata payload
    -- @param initialStacks (number|nil) Starting stack count
    function meta:AddBuff(buffId, duration, customData, initialStacks)
        local def = GWRP.Buffs.Get(buffId)
        if not def then
            print("[GWRP-Buffs ERROR] Cannot add unregistered buff: " .. tostring(buffId))
            return false
        end

        self.GWRP_ActiveBuffs = self.GWRP_ActiveBuffs or {}
        local now = CurTime()
        local inst = self.GWRP_ActiveBuffs[buffId]
        local dur = duration or def.duration
        local isFirst = (inst == nil)

        if inst then
            -- Increment stacks up to maxStacks
            if def.maxStacks > 1 then
                inst.stacks = math.min(def.maxStacks, (inst.stacks or 1) + (initialStacks or 1))
            end

            -- Refresh or extend duration
            if dur > 0 then
                inst.duration = dur
                inst.expiresAt = now + dur
            end

            if customData then
                table.Merge(inst.data, customData)
            end

            def.OnApplied(self, inst, false)
        else
            inst = {
                id = buffId,
                stacks = initialStacks or 1,
                startTime = now,
                duration = dur,
                expiresAt = (dur > 0) and (now + dur) or -1,
                nextTick = def.tickInterval and (now + def.tickInterval) or nil,
                data = customData or {},
                appliedAtUnix = os.time()
            }
            self.GWRP_ActiveBuffs[buffId] = inst
            def.OnApplied(self, inst, true)
        end

        -- Recalculate movement speed if modifier is present
        if def.ModifySpeed then
            self:RecalculateSpeed()
        end

        -- Network single addition to client
        net.Start("GWRP_SyncBuffAdded")
            net.WriteString(buffId)
            net.WriteFloat(inst.duration)
            net.WriteFloat(inst.expiresAt > 0 and (inst.expiresAt - now) or -1)
            net.WriteUInt(inst.stacks or 1, 8)
            net.WriteString(util.TableToJSON(inst.data or {}))
        net.Send(self)

        -- Persist to SQLite if enabled
        if def.persist ~= false and GWRP.Database and GWRP.Database.SavePlayerBuff then
            local remaining = inst.expiresAt > 0 and math.max(0, inst.expiresAt - now) or -1
            local expiresUnix = (inst.expiresAt > 0) and (os.time() + math.ceil(remaining)) or 0
            GWRP.Database.SavePlayerBuff(
                self:SteamID(),
                buffId,
                inst.duration,
                remaining,
                inst.stacks or 1,
                inst.appliedAtUnix or os.time(),
                expiresUnix,
                util.TableToJSON(inst.data or {})
            )
        end

        return true
    end

    --- Removes an active buff from the player.
    -- @param buffId (string) Unique ID
    -- @param reason (string|nil) "expired", "manual", "cleansed", "death"
    function meta:RemoveBuff(buffId, reason)
        self.GWRP_ActiveBuffs = self.GWRP_ActiveBuffs or {}
        local inst = self.GWRP_ActiveBuffs[buffId]
        if not inst then return false end

        local def = GWRP.Buffs.Get(buffId)
        if def then
            def.OnRemoved(self, inst, reason or "manual")
        end

        self.GWRP_ActiveBuffs[buffId] = nil

        -- Speed recalculation
        if def and def.ModifySpeed then
            self:RecalculateSpeed()
        end

        -- Network removal to client
        net.Start("GWRP_SyncBuffRemoved")
            net.WriteString(buffId)
            net.WriteString(reason or "manual")
        net.Send(self)

        -- Delete from SQLite
        if def and def.persist ~= false and GWRP.Database and GWRP.Database.DeletePlayerBuff then
            GWRP.Database.DeletePlayerBuff(self:SteamID(), buffId)
        end

        return true
    end

    --- Clears all active buffs from the player.
    -- @param onlyNonPersistent (boolean|nil) If true, preserves persistDeath buffs
    function meta:ClearBuffs(onlyNonPersistent)
        self.GWRP_ActiveBuffs = self.GWRP_ActiveBuffs or {}
        for buffId, inst in pairs(self.GWRP_ActiveBuffs) do
            local def = GWRP.Buffs.Get(buffId)
            if not (onlyNonPersistent and def and def.persistDeath) then
                self:RemoveBuff(buffId, "clear")
            end
        end
    end

    --- Synchronizes all active buffs on this player to their client.
    function meta:SyncAllBuffs()
        self.GWRP_ActiveBuffs = self.GWRP_ActiveBuffs or {}
        local list = {}
        local now = CurTime()

        for buffId, inst in pairs(self.GWRP_ActiveBuffs) do
            table.insert(list, {
                id = buffId,
                duration = inst.duration,
                remaining = inst.expiresAt > 0 and math.max(0, inst.expiresAt - now) or -1,
                stacks = inst.stacks or 1,
                data = util.TableToJSON(inst.data or {})
            })
        end

        net.Start("GWRP_SyncAllBuffs")
            net.WriteUInt(#list, 8)
            for _, b in ipairs(list) do
                net.WriteString(b.id)
                net.WriteFloat(b.duration)
                net.WriteFloat(b.remaining)
                net.WriteUInt(b.stacks, 8)
                net.WriteString(b.data)
            end
        net.Send(self)
    end
end

-- ========================================================
-- CENTRALIZED TICK & EXPIRATION THINK LOOP (10Hz)
-- ========================================================

local nextThinkCheck = 0
hook.Add("Think", "GWRP_BuffsThinkEngine", function()
    local now = CurTime()
    if now < nextThinkCheck then return end
    nextThinkCheck = now + 0.1 -- 10Hz throttle

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply.GWRP_ActiveBuffs then
            for buffId, inst in pairs(ply.GWRP_ActiveBuffs) do
                local def = GWRP.Buffs.Get(buffId)
                if def then
                    -- 1. Check Duration Expiration
                    if inst.expiresAt > 0 and now >= inst.expiresAt then
                        ply:RemoveBuff(buffId, "expired")

                    -- 2. Check Periodic Tick (e.g. HoT or DoT)
                    elseif inst.nextTick and now >= inst.nextTick then
                        inst.nextTick = now + (def.tickInterval or 1.0)
                        def.OnTick(ply, inst)
                    end
                end
            end
        end
    end
end)

-- ========================================================
-- PLAYER LIFECYCLE & PERSISTENCE HOOKS
-- ========================================================

-- Player Spawn: Ensure speeds match active buffs
hook.Add("PlayerSpawn", "GWRP_BuffsApplySpeedsOnSpawn", function(ply)
    timer.Simple(0.1, function()
        if IsValid(ply) then
            ply:RecalculateSpeed()
        end
    end)
end)

-- Entity Take Damage: Apply active buff damage modifiers
hook.Add("EntityTakeDamage", "GWRP_BuffsDamageModifiers", function(target, dmginfo)
    if IsValid(target) and target:IsPlayer() and target.GWRP_ActiveBuffs then
        for buffId, inst in pairs(target.GWRP_ActiveBuffs) do
            local def = GWRP.Buffs.Get(buffId)
            if def and def.ModifyDamageTaken then
                local mult = def.ModifyDamageTaken(target, inst, dmginfo)
                if isnumber(mult) then
                    dmginfo:ScaleDamage(mult)
                end
            end
        end
    end
end)

-- Player Death: Remove non-death-persistent buffs (Wanted persists)
hook.Add("PlayerDeath", "GWRP_BuffsHandleDeath", function(victim, inflictor, attacker)
    if not IsValid(victim) or not victim.GWRP_ActiveBuffs then return end

    for buffId, inst in pairs(victim.GWRP_ActiveBuffs) do
        local def = GWRP.Buffs.Get(buffId)
        if def and not def.persistDeath then
            victim:RemoveBuff(buffId, "death")
        end
    end
end)

-- Disconnect: Commit exact remaining time to SQLite
hook.Add("PlayerDisconnected", "GWRP_BuffsSaveOnDisconnect", function(ply)
    if not IsValid(ply) or not ply.GWRP_ActiveBuffs then return end
    local steamID = ply:SteamID()
    local now = CurTime()

    for buffId, inst in pairs(ply.GWRP_ActiveBuffs) do
        local def = GWRP.Buffs.Get(buffId)
        if def and def.persist ~= false and GWRP.Database and GWRP.Database.SavePlayerBuff then
            local remaining = inst.expiresAt > 0 and math.max(0, inst.expiresAt - now) or -1
            local expiresUnix = (inst.expiresAt > 0) and (os.time() + math.ceil(remaining)) or 0
            GWRP.Database.SavePlayerBuff(
                steamID,
                buffId,
                inst.duration,
                remaining,
                inst.stacks or 1,
                inst.appliedAtUnix or os.time(),
                expiresUnix,
                util.TableToJSON(inst.data or {})
            )
        end
    end
end)

-- Player Initial Spawn: Restore persisted buffs from SQLite
hook.Add("PlayerInitialSpawn", "GWRP_BuffsLoadOnJoin", function(ply)
    timer.Simple(1.5, function()
        if not IsValid(ply) or not GWRP.Database or not GWRP.Database.GetPlayerBuffs then return end
        local steamID = ply:SteamID()
        local savedBuffs = GWRP.Database.GetPlayerBuffs(steamID) or {}

        for _, row in ipairs(savedBuffs) do
            local buffId = row.buff_id
            local def = GWRP.Buffs.Get(buffId)
            if def then
                local remaining = tonumber(row.remaining) or 0
                local stacks = tonumber(row.stacks) or 1
                local data = util.JSONToTable(row.data or "{}") or {}

                if def.tickOffline then
                    -- Real-world wall-clock offline calculation (e.g. Wanted by Police)
                    local nowUnix = os.time()
                    local expiresUnix = tonumber(row.expires_at_unix) or 0
                    local offlineRemaining = expiresUnix - nowUnix

                    if offlineRemaining <= 0 then
                        -- Expired while offline: prune from database
                        GWRP.Database.DeletePlayerBuff(steamID, buffId)
                    else
                        ply:AddBuff(buffId, offlineRemaining, data, stacks)
                    end
                else
                    -- In-game time frozen while offline (e.g. Potions / Food / Boosts)
                    if remaining > 0 or remaining == -1 then
                        ply:AddBuff(buffId, remaining, data, stacks)
                    else
                        GWRP.Database.DeletePlayerBuff(steamID, buffId)
                    end
                end
            end
        end

        ply:SyncAllBuffs()
    end)
end)

-- ========================================================
-- CLIENT CANCEL BUFF NET RECEIVER (RIGHT-CLICK DISMISS)
-- ========================================================

net.Receive("GWRP_CancelBuff", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GWRP.CheckRateLimit(ply, "buff_cancel", 5) then return end

    local buffId = net.ReadString()
    local def = GWRP.Buffs.Get(buffId)

    if not def then return end

    -- Verify buff can be canceled (Debuffs cannot be canceled!)
    if not def.canCancel then
        GWRP.Notify(ply, "You cannot dismiss this debuff!", NOTIFY_ERROR)
        return
    end

    if ply:HasBuff(buffId) then
        ply:RemoveBuff(buffId, "dismissed")
        ply:EmitSound("buttons/button15.wav", 55, 120)
    end
end)

-- ========================================================
-- POLICE /WANTED & /UNWANTED CHAT COMMANDS
-- ========================================================

hook.Add("PlayerSay", "GWRP_BuffsPoliceCommands", function(ply, text)
    local lower = string.lower(string.Trim(text))

    -- /wanted <player> [reason]
    if string.StartWith(lower, "/wanted ") or string.StartWith(lower, "!wanted ") then
        if not ply:IsPolice() and not ply:IsAdmin() then
            GWRP.Notify(ply, "Only Law Enforcement officers can flag suspects as wanted!", NOTIFY_ERROR)
            return ""
        end

        local args = string.Explode(" ", text)
        table.remove(args, 1) -- Remove command name
        local targetName = args[1]
        if not targetName then
            GWRP.Notify(ply, "Usage: /wanted <name> [reason]", NOTIFY_HINT)
            return ""
        end

        table.remove(args, 1)
        local reason = table.concat(args, " ")
        if reason == "" then reason = "Evading Police / Criminal Activity" end

        -- Find target player
        local targetPly = nil
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(targetName), 1, true) then
                targetPly = p
                break
            end
        end

        if not IsValid(targetPly) then
            GWRP.Notify(ply, "Player not found matching '" .. targetName .. "'!", NOTIFY_ERROR)
            return ""
        end

        if targetPly:IsPolice() and not ply:IsAdmin() then
            GWRP.Notify(ply, "You cannot flag fellow law enforcement officers as wanted!", NOTIFY_ERROR)
            return ""
        end

        targetPly:AddBuff("wanted", 180, {
            reason = reason,
            officer = ply:Nick()
        })
        return ""

    -- /unwanted <player>
    elseif string.StartWith(lower, "/unwanted ") or string.StartWith(lower, "!unwanted ") then
        if not ply:IsPolice() and not ply:IsAdmin() then
            GWRP.Notify(ply, "Only Law Enforcement officers can revoke wanted status!", NOTIFY_ERROR)
            return ""
        end

        local args = string.Explode(" ", text)
        table.remove(args, 1)
        local targetName = args[1]
        if not targetName then
            GWRP.Notify(ply, "Usage: /unwanted <name>", NOTIFY_HINT)
            return ""
        end

        local targetPly = nil
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(targetName), 1, true) then
                targetPly = p
                break
            end
        end

        if not IsValid(targetPly) then
            GWRP.Notify(ply, "Player not found matching '" .. targetName .. "'!", NOTIFY_ERROR)
            return ""
        end

        if targetPly:HasBuff("wanted") then
            targetPly:RemoveBuff("wanted", "cleared_by_police")
            GWRP.Notify(ply, "Revoked wanted status for " .. targetPly:Nick() .. ".", NOTIFY_GENERIC)
        else
            GWRP.Notify(ply, targetPly:Nick() .. " is not currently wanted.", NOTIFY_ERROR)
        end
        return ""
    end
end)
