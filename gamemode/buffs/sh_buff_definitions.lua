--[[
    sh_buff_definitions.lua - Standard Buff & Debuff Definitions
    Author: Juicebox
--]]

-- ========================================================
-- 1. HEALING OVER TIME (HoT) - TRAUMA RECOVERY
-- ========================================================
GRID.Buffs.Register("healing_over_time", {
    name = "Trauma Recovery",
    desc = "Field trauma treatment stabilizes bleeding and lacerations, restoring +6 Health every 1.5 seconds.",
    isDebuff = false,
    canCancel = true,
    persist = true,
    persistDeath = false,
    tickOffline = false,
    maxStacks = 1,
    duration = 15,
    tickInterval = 1.5,
    icon = "hot",
    iconColor = Color(74, 222, 128),
    borderColor = Color(34, 197, 94),

    OnApplied = function(ply, inst, isFirst)
        if SERVER and isFirst then
            ply:EmitSound("items/smallmedkit1.wav", 65, 110)
        end
    end,

    OnTick = function(ply, inst)
        if SERVER and IsValid(ply) and ply:Alive() then
            local currentHP = ply:Health()
            local maxHP = ply:GetMaxHealth()
            if currentHP < maxHP then
                local healAmount = inst.data and tonumber(inst.data.healPerTick) or 6
                local newHP = math.min(maxHP, currentHP + healAmount)
                ply:SetHealth(newHP)

                -- Visual Combat Text net event (green +X HP)
                net.Start("GRID_BuffCombatText")
                net.WriteVector(ply:EyePos() + Vector(0, 0, 10))
                net.WriteString("+" .. healAmount .. " HP")
                net.WriteColor(Color(34, 197, 94))
                net.Send(ply)
            end
        end
    end,

    OnRemoved = function(ply, inst, reason)
        if SERVER and IsValid(ply) and reason == "expired" then
            ply:EmitSound("items/medshot4.wav", 60, 100)
        end
    end
})

-- ========================================================
-- 2. MOVEMENT SPEED BUFF - SWIFTNESS / ADRENALINE
-- ========================================================
GRID.Buffs.Register("swiftness", {
    name = "Adrenaline Surge",
    desc = "Increases walk and run movement speed by +30% per stack. Allows rapid tactical flanking.",
    isDebuff = false,
    canCancel = true,
    persist = true,
    persistDeath = false,
    tickOffline = false,
    maxStacks = 2,
    duration = 30,
    icon = "speed",
    iconColor = Color(250, 204, 21),
    borderColor = Color(245, 158, 11),

    ModifySpeed = function(ply, inst)
        local stacks = inst.stacks or 1
        -- +30% for 1 stack, +50% for 2 stacks
        return (stacks >= 2) and 1.50 or 1.30
    end,

    OnApplied = function(ply, inst, isFirst)
        if SERVER then
            ply:EmitSound("npc/fast_zombie/wake1.wav", 60, 140)
            ply:RecalculateSpeed()
        end
    end,

    OnRemoved = function(ply, inst, reason)
        if SERVER and IsValid(ply) then
            ply:RecalculateSpeed()
        end
    end
})

-- ========================================================
-- 3. WANTED BY POLICE - CRIMINAL STATUS DEBUFF
-- ========================================================
GRID.Buffs.Register("wanted", {
    name = "Wanted by Police",
    desc = "Actively pursued by Civil Protection and SWAT! Law enforcement officers have search and arrest authority.",
    isDebuff = true,
    canCancel = false,   -- Player CANNOT dismiss a criminal wanted debuff!
    persist = true,
    persistDeath = true, -- Wanted status persists across death and respawn
    tickOffline = true,  -- Wanted timer ticks down in real-world wall clock time
    maxStacks = 1,
    duration = 180,      -- Default 3 minutes
    icon = "wanted",
    iconColor = Color(239, 68, 68),
    borderColor = Color(220, 38, 38),

    OnApplied = function(ply, inst, isFirst)
        if SERVER and isFirst then
            local reason = (inst.data and inst.data.reason) or "Criminal Activity"
            local officer = (inst.data and inst.data.officer) or "Civil Protection"

            -- Global alert notification
            GRID.Notify(ply, "YOU ARE WANTED BY POLICE! Reason: " .. reason, NOTIFY_ERROR, 10)
            ply:EmitSound("ambient/alarms/klaxon1.wav", 75, 100)

            -- Notify all police officers
            for _, p in ipairs(player.GetAll()) do
                if p:IsPolice() and p ~= ply then
                    GRID.Notify(p,
                        "[LSPD DISPATCH] " ..
                        ply:Nick() .. " is now WANTED! Reason: " .. reason .. " (By " .. officer .. ")", NOTIFY_HINT, 10)
                end
            end
        end
    end,

    OnRemoved = function(ply, inst, reason)
        if SERVER and IsValid(ply) then
            GRID.Notify(ply, "You are no longer wanted by the police.", NOTIFY_GENERIC, 6)
            for _, p in ipairs(player.GetAll()) do
                if p:IsPolice() and p ~= ply then
                    GRID.Notify(p, "[LSPD DISPATCH] Wanted status cleared for " .. ply:Nick() .. ".", NOTIFY_GENERIC, 6)
                end
            end
        end
    end
})

-- ========================================================
-- 4. CRIPPLED LEG - MOVEMENT SPEED DEBUFF
-- ========================================================
GRID.Buffs.Register("crippled", {
    name = "Crippled Leg",
    desc = "Compound bone fracture or severe injury. Reduces movement speed by -40%.",
    isDebuff = true,
    canCancel = false,
    persist = true,
    persistDeath = false,
    tickOffline = false,
    maxStacks = 1,
    duration = 25,
    icon = "crippled",
    iconColor = Color(248, 113, 113),
    borderColor = Color(185, 28, 28),

    ModifySpeed = function(ply, inst)
        return 0.60 -- -40% speed
    end,

    OnApplied = function(ply, inst, isFirst)
        if SERVER then
            ply:EmitSound("player/damage3.wav", 70, 90)
            ply:RecalculateSpeed()
        end
    end,

    OnRemoved = function(ply, inst, reason)
        if SERVER and IsValid(ply) then
            ply:RecalculateSpeed()
            GRID.Notify(ply, "Your crippled leg has healed. Full mobility restored.", NOTIFY_GENERIC)
        end
    end
})

-- ========================================================
-- 5. POISON NEUROTOXIN - DAMAGE OVER TIME (DoT)
-- ========================================================
GRID.Buffs.Register("poison", {
    name = "Lethal Neurotoxin",
    desc = "Juicebox chemical agent coursing through veins. Deals 4 damage every 2 seconds.",
    isDebuff = true,
    canCancel = false,
    persist = true,
    persistDeath = false,
    tickOffline = false,
    maxStacks = 3,
    duration = 14,
    tickInterval = 2.0,
    icon = "poison",
    iconColor = Color(168, 85, 247),
    borderColor = Color(147, 51, 234),

    OnTick = function(ply, inst)
        if SERVER and IsValid(ply) and ply:Alive() then
            local stacks = inst.stacks or 1
            local dmg = 4 * stacks
            local currentHP = ply:Health()

            if currentHP > dmg then
                ply:SetHealth(currentHP - dmg)
            else
                -- Deliver lethal damage via damage info
                local d = DamageInfo()
                d:SetDamage(dmg)
                d:SetDamageType(DMG_POISON)
                d:SetAttacker(game.GetWorld())
                d:SetInflictor(game.GetWorld())
                ply:TakeDamageInfo(d)
            end

            ply:EmitSound("ambient/water/drip" .. math.random(1, 4) .. ".wav", 60, 80)

            -- Visual Combat Text net event (purple -X HP)
            net.Start("GRID_BuffCombatText")
            net.WriteVector(ply:EyePos() + Vector(0, 0, 10))
            net.WriteString("-" .. dmg .. " HP")
            net.WriteColor(Color(168, 85, 247))
            net.Send(ply)
        end
    end
})

-- ========================================================
-- 6. REINFORCED PLATING - MAX HEALTH BUFF
-- ========================================================
GRID.Buffs.Register("fortitude", {
    name = "Reinforced Plating",
    desc = "Hardened ceramic trauma plating shields vital organs, granting +50 Maximum Health for 10 minutes.",
    isDebuff = false,
    canCancel = true,
    persist = true,
    persistDeath = false,
    tickOffline = false,
    maxStacks = 1,
    duration = 600,
    icon = "fortitude",
    iconColor = Color(59, 130, 246),
    borderColor = Color(37, 99, 235),

    OnApplied = function(ply, inst, isFirst)
        if SERVER and isFirst then
            local newMax = ply:GetMaxHealth() + 50
            ply:SetMaxHealth(newMax)
            ply:SetHealth(ply:Health() + 50)
            ply:EmitSound("items/suitchargeok1.wav", 70, 100)
        end
    end,

    OnRemoved = function(ply, inst, reason)
        if SERVER and IsValid(ply) then
            local newMax = math.max(100, ply:GetMaxHealth() - 50)
            ply:SetMaxHealth(newMax)
            if ply:Health() > newMax then
                ply:SetHealth(newMax)
            end
        end
    end
})

-- ========================================================
-- 7. BLACK MARKET ADRENALINE (ILLEGAL STIMULANT)
-- ========================================================
GRID.Buffs.Register("illegal_adrenaline", {
    name = "Combat Adrenaline",
    desc =
    "Black-market combat stimulant. Grants +40% Sprint/Walk Speed and 15% Incoming Damage Reduction for 20s. Causes brief crash upon wearing off.",
    isDebuff = false,
    canCancel = true,
    persist = true,
    persistDeath = false,
    tickOffline = false,
    maxStacks = 1,
    duration = 20,
    icon = "speed",
    iconColor = Color(244, 63, 94),
    borderColor = Color(225, 29, 72),

    ModifySpeed = function(ply, inst)
        return 1.40 -- +40% speed
    end,

    ModifyDamageTaken = function(ply, inst, dmginfo)
        return 0.85 -- 15% damage reduction
    end,

    OnApplied = function(ply, inst, isFirst)
        if SERVER then
            ply:EmitSound("ambient/machines/thumper_dust.wav", 65, 150)
            ply:RecalculateSpeed()
        end
    end,

    OnRemoved = function(ply, inst, reason)
        if SERVER and IsValid(ply) then
            ply:RecalculateSpeed()
            if reason == "expired" and ply:Alive() then
                ply:AddBuff("stim_exhaustion", 10)
            end
        end
    end
})

-- ========================================================
-- 8. ADRENALINE CRASH (POST-STIM DEBUFF)
-- ========================================================
GRID.Buffs.Register("stim_exhaustion", {
    name = "Adrenaline Crash",
    desc = "Severe physiological crash after an adrenaline surge. Decreases movement speed by -15% for 10 seconds.",
    isDebuff = true,
    canCancel = false,
    persist = true,
    persistDeath = false,
    tickOffline = false,
    maxStacks = 1,
    duration = 10,
    icon = "crippled",
    iconColor = Color(156, 163, 175),
    borderColor = Color(107, 114, 128),

    ModifySpeed = function(ply, inst)
        return 0.85 -- -15% speed
    end,

    OnApplied = function(ply, inst, isFirst)
        if SERVER then
            ply:EmitSound("player/suit_sprint.wav", 55, 75)
            ply:RecalculateSpeed()
        end
    end,

    OnRemoved = function(ply, inst, reason)
        if SERVER and IsValid(ply) then
            ply:RecalculateSpeed()
            GRID.Notify(ply, "Heart rate stabilized. Adrenaline crash cleared.", NOTIFY_GENERIC)
        end
    end
})

-- ========================================================
-- 9. DETOX & CLEANSE RECOVERY
-- ========================================================
GRID.Buffs.Register("detox", {
    name = "Detox Recovery",
    desc =
    "High-grade pharmaceutical antidote that neutralizes poisons, heals trauma, and cleanses debilitating status effects.",
    isDebuff = false,
    canCancel = true,
    persist = true,
    persistDeath = false,
    tickOffline = false,
    maxStacks = 1,
    duration = 5,
    tickInterval = 1.0,
    icon = "hot",
    iconColor = Color(45, 212, 191),
    borderColor = Color(13, 148, 136),

    OnApplied = function(ply, inst, isFirst)
        if SERVER and isFirst then
            -- Cleanse debilitating debuffs
            if ply:HasBuff("poison") then ply:RemoveBuff("poison", "cleansed") end
            if ply:HasBuff("crippled") then ply:RemoveBuff("crippled", "cleansed") end
            if ply:HasBuff("stim_exhaustion") then ply:RemoveBuff("stim_exhaustion", "cleansed") end
            ply:EmitSound("items/smallmedkit1.wav", 70, 120)
            GRID.Notify(ply, "Debuffs purged! Cellular detox in progress (+3 HP/s).", NOTIFY_GENERIC)
        end
    end,

    OnTick = function(ply, inst)
        if SERVER and IsValid(ply) and ply:Alive() then
            local currentHP = ply:Health()
            local maxHP = ply:GetMaxHealth()
            if currentHP < maxHP then
                local newHP = math.min(maxHP, currentHP + 3)
                ply:SetHealth(newHP)
            end
        end
    end
})

-- ========================================================
-- 10. SYNDICATE INSOLVENCY DEBUFF (STOCK DEFAULT / JUNK)
-- ========================================================
GRID.Buffs.Register("syndicate_insolvency", {
    name = "Gang Debt Default",
    desc = "Your gang failed to pay stock dividends! Stock is in default, territory capture takes twice as long, and territory payouts go toward debt repayment.",
    isDebuff = true,
    canCancel = false,   -- Cannot dismiss while gang is in default
    persist = true,
    persistDeath = true, -- Persists across death until arrears are cleared
    tickOffline = false,
    maxStacks = 1,
    duration = 0,        -- Indefinite duration until manually removed by clearing default
    icon = "wanted",
    iconColor = Color(239, 68, 68),
    borderColor = Color(185, 28, 28),

    OnApplied = function(ply, inst, isFirst)
        if SERVER and isFirst then
            ply:EmitSound("ambient/alarms/warningbell1.wav", 70, 95)
            GRID.Notify(ply, "[UNPAID DEBT ALERT] Your gang failed to pay dividends! Territory capture takes twice as long until debt is paid.", NOTIFY_ERROR, 8)
        end
    end,

    OnRemoved = function(ply, inst, reason)
        if SERVER and IsValid(ply) then
            GRID.Notify(ply, "Gang debt cleared! Territory capture speed and payouts restored.", NOTIFY_GENERIC, 6)
        end
    end
})
