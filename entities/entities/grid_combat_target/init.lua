--[[
    entities/entities/grid_combat_target/init.lua
    GridRP Syndicate Live-Fire Combat Drone - Server
    Author: GRID Core Team & Antigravity
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local DEFAULT_MAX_HP = 75
local RESPAWN_DELAY = 8.0

function ENT:Initialize()
    local mdl = util.IsValidModel("models/combine_scanner.mdl") and "models/combine_scanner.mdl" or "models/props_junk/metal_paintcan001a.mdl"
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:EnableMotion(false)
    end

    self:SetMaxTargetHealth(DEFAULT_MAX_HP)
    self:SetTargetHealth(DEFAULT_MAX_HP)
    self:SetIsActive(true)

    -- Ambient scanner hum
    self.NextPing = CurTime() + math.Rand(3, 6)
end

function ENT:Think()
    if not self:GetIsActive() then return end

    if CurTime() >= (self.NextPing or 0) then
        self:EmitSound("npc/scanner/scanner_scan1.wav", 55, math.random(95, 105))
        self.NextPing = CurTime() + math.Rand(4, 8)
    end

    self:NextThink(CurTime() + 1.0)
    return true
end

function ENT:OnTakeDamage(dmginfo)
    if not self:GetIsActive() then return end

    local damage = dmginfo:GetDamage()
    if damage <= 0 then return end

    local curHP = self:GetTargetHealth()
    local newHP = math.max(0, curHP - math.floor(damage))
    self:SetTargetHealth(newHP)

    -- Kinetic & spark audio feedback
    local hitSounds = {
        "physics/metal/metal_grenade_impact_hard1.wav",
        "physics/metal/metal_grenade_impact_hard2.wav",
        "physics/metal/metal_grenade_impact_hard3.wav"
    }
    self:EmitSound(hitSounds[math.random(#hitSounds)], 70, math.random(110, 125))

    -- Visual sparks at impact position
    local ed = EffectData()
    ed:SetOrigin(dmginfo:GetDamagePosition())
    ed:SetNormal(dmginfo:GetDamageForce():GetNormalized() * -1)
    ed:SetMagnitude(2)
    ed:SetScale(1)
    util.Effect("MetalSpark", ed, true, true)

    if newHP <= 0 then
        local attacker = dmginfo:GetAttacker()
        self:Destruct(attacker)
    end
end

function ENT:Destruct(attacker)
    self:SetIsActive(false)

    -- Detonation audio & visual explosion
    self:EmitSound("weapons/explode3.wav", 80, math.random(100, 115))

    local ed = EffectData()
    ed:SetOrigin(self:WorldSpaceCenter())
    ed:SetScale(1.5)
    ed:SetMagnitude(2)
    util.Effect("Explosion", ed, true, true)

    -- Onboarding progression verification
    if IsValid(attacker) and attacker:IsPlayer() then
        if attacker:GetOnboardingStage() == GRID.Onboarding.STAGE_STASH then
            if GRID.Onboarding and GRID.Onboarding.CompleteInitiation then
                GRID.Onboarding.CompleteInitiation(attacker, self)
            end
        else
            GRID.Notify(attacker, "🎯 Target drone neutralized!", NOTIFY_HINT, 3)
        end
    end

    -- Temporarily make invisible & non-solid while awaiting recharge/respawn
    self:SetNoDraw(true)
    self:SetSolid(SOLID_NONE)

    timer.Simple(RESPAWN_DELAY, function()
        if not IsValid(self) then return end
        self:SetTargetHealth(self:GetMaxTargetHealth())
        self:SetIsActive(true)
        self:SetNoDraw(false)
        self:SetSolid(SOLID_VPHYSICS)
        self:EmitSound("items/suitchargeok1.wav", 70, 110)
    end)
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if not self:GetIsActive() then return end

    if activator:GetOnboardingStage() == GRID.Onboarding.STAGE_STASH then
        GRID.Notify(activator, "Draw your Glock-18 and destroy the drone with live fire!", NOTIFY_HINT, 4)
    else
        GRID.Notify(activator, "Syndicate live-fire combat drill drone. Neutralize with firearms.", NOTIFY_GENERIC, 4)
    end
end

