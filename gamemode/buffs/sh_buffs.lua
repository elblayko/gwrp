--[[
    sh_buffs.lua - Buff & Debuff Core Framework
    Author: Toxic
--]]

GWRP.Buffs = GWRP.Buffs or {}
GWRP.Buffs.Registry = GWRP.Buffs.Registry or {}

-- ========================================================
-- REGISTRY API
-- ========================================================

--- Registers a new buff or debuff definition into the framework.
-- @param buffId (string) Unique identifier for the buff
-- @param data (table) Specification definition
function GWRP.Buffs.Register(buffId, data)
    if not buffId or buffId == "" then
        error("[GWRP-Buffs] Attempted to register buff with invalid ID!", 2)
        return
    end

    data = data or {}
    data.id = buffId
    data.name = data.name or buffId
    data.desc = data.desc or "No description provided."
    data.isDebuff = data.isDebuff or false
    -- Buffs can be right-click dismissed by player, Debuffs cannot
    if data.canCancel == nil then
        data.canCancel = not data.isDebuff
    end
    data.persist = (data.persist == nil) and true or data.persist
    data.persistDeath = data.persistDeath or false
    data.tickOffline = data.tickOffline or false -- true = real-time wall clock countdown; false = freeze in-game time
    data.maxStacks = data.maxStacks or 1
    data.duration = data.duration or 30 -- -1 for indefinite / permanent
    data.tickInterval = data.tickInterval or nil

    -- Icon visuals & styling
    data.icon = data.icon or "generic"
    data.iconColor = data.iconColor or (data.isDebuff and Color(239, 68, 68) or Color(34, 197, 94))
    data.borderColor = data.borderColor or (data.isDebuff and Color(220, 38, 38) or Color(245, 158, 11))

    -- Lifecycle Hooks
    data.OnApplied = data.OnApplied or function(ply, instance, isFirst) end
    data.OnTick = data.OnTick or function(ply, instance) end
    data.OnRemoved = data.OnRemoved or function(ply, instance, reason) end
    data.ModifySpeed = data.ModifySpeed or nil

    GWRP.Buffs.Registry[buffId] = data
end

--- Retrieves a buff definition from the registry.
-- @param buffId (string) Unique identifier
-- @return table|nil
function GWRP.Buffs.Get(buffId)
    return GWRP.Buffs.Registry[buffId]
end

--- Returns all registered buff specifications.
-- @return table
function GWRP.Buffs.GetAll()
    return GWRP.Buffs.Registry
end

--- Convenience Wrapper: Apply a buff to a player.
function GWRP.Buffs.Apply(ply, buffId, duration, customData, initialStacks)
    if IsValid(ply) and ply.AddBuff then
        return ply:AddBuff(buffId, duration, customData, initialStacks)
    end
    return false
end

--- Convenience Wrapper: Remove a buff from a player.
function GWRP.Buffs.Remove(ply, buffId, reason)
    if IsValid(ply) and ply.RemoveBuff then
        return ply:RemoveBuff(buffId, reason)
    end
    return false
end

-- ========================================================
-- PLAYER METATABLE EXTENSIONS
-- ========================================================

local meta = FindMetaTable("Player")
if meta then
    --- Returns table of all active buff instances on the player.
    function meta:GetBuffs()
        return self.GWRP_ActiveBuffs or {}
    end

    --- Checks if the player currently has the specified buff active.
    -- @param buffId (string)
    -- @return boolean
    function meta:HasBuff(buffId)
        local buffs = self:GetBuffs()
        return buffs[buffId] ~= nil
    end

    --- Retrieves the active instance table for a given buff on the player.
    -- @param buffId (string)
    -- @return table|nil
    function meta:GetBuff(buffId)
        local buffs = self:GetBuffs()
        return buffs[buffId]
    end

    --- Returns stack count of active buff, or 0 if inactive.
    -- @param buffId (string)
    -- @return number
    function meta:GetBuffStacks(buffId)
        local inst = self:GetBuff(buffId)
        return inst and (inst.stacks or 1) or 0
    end

    --- Computes total movement speed multiplier from all active buffs/debuffs.
    -- @return number (e.g. 1.0 = normal, 1.3 = +30%, 0.6 = -40%)
    function meta:GetSpeedMultiplier()
        local multiplier = 1.0
        local buffs = self:GetBuffs()

        for buffId, inst in pairs(buffs) do
            local def = GWRP.Buffs.Get(buffId)
            if def and def.ModifySpeed then
                local mod = def.ModifySpeed(self, inst)
                if isnumber(mod) then
                    multiplier = multiplier * mod
                end
            end
        end

        return math.Clamp(multiplier, 0.2, 3.0)
    end

    --- Recalculates and reapplies walk and run speeds according to job base & buffs.
    function meta:RecalculateSpeed()
        local job = self:GetJobData()
        local baseWalk = (job and job.walkSpeed) or 220
        local baseRun = (job and job.runSpeed) or 320

        local mult = self:GetSpeedMultiplier()
        local newWalk = math.max(40, math.floor(baseWalk * mult))
        local newRun = math.max(60, math.floor(baseRun * mult))

        self:SetWalkSpeed(newWalk)
        self:SetRunSpeed(newRun)
    end

    -- ========================================================
    -- DARKRP & RP COMPATIBILITY METATABLE BRIDGE
    -- ========================================================

    --- DarkRP standard isWanted check mapped to 'wanted' debuff.
    function meta:isWanted()
        return self:HasBuff("wanted")
    end

    function meta:IsWanted()
        return self:isWanted()
    end

    --- Fallback for getDarkRPVar("wanted")
    local oldGetDarkRPVar = meta.getDarkRPVar
    function meta:getDarkRPVar(var)
        if var == "wanted" then
            return self:isWanted()
        end
        if oldGetDarkRPVar then
            return oldGetDarkRPVar(self, var)
        end
        return nil
    end
end
