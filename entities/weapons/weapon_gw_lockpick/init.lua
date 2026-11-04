--[[
    entities/weapons/weapon_gw_lockpick/init.lua
    GWRP Tactical Lockpick - Server
    Author: Toxic
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function SWEP:StartLockpick(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return end

    -- Verify prop state before locking player into a 20s action
    if ent:GetClass() == "prop_physics" then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) and phys:IsMotionEnabled() then
            GW.Notify(ply, "This prop is already unsealed!", NOTIFY_ERROR, 3)
            return
        end
    end

    self:SetHoldType("pistol")
    self:SetIsLockpicking(true)
    self:SetPickTarget(ent)
    self:SetPickStartTime(CurTime())
    self:SetPickEndTime(CurTime() + self.LockpickTime)
    self.NextClickSound = CurTime() + 0.65

    GW.Notify(ply, string.format("Lockpicking started... stay close (%ds)!", math.Round(self.LockpickTime)), NOTIFY_GENERIC, 3)

    -- Silent Alarm Security Trip
    local doorOwner = ent.GetDoorOwner and ent:GetDoorOwner()
    if IsValid(doorOwner) and doorOwner ~= ply then
        if not ply:HasBuff("wanted") then
            ply:AddBuff("wanted", 180, {
                reason = "Armed Burglary in Progress",
                officer = "Silent Security Alarm",
                isBurglary = true,
                raidPos = ent:GetPos(),
                raidTime = CurTime() + 180
            })
        end

        GW.Notify(doorOwner, "SECURITY ALARM: An intruder is lockpicking your front door!", NOTIFY_ERROR, 6)
        doorOwner:EmitSound("ambient/alarms/klaxon1.wav", 65, 120, 0.5)

        for _, p in ipairs(player.GetAll()) do
            if p:IsPolice() then
                p:EmitSound("ambient/alarms/klaxon1.wav", 65, 130, 0.5)
                GW.Notify(p, string.format("[LSPD 911] Silent alarm tripped! Burglary in progress at %s's property!", doorOwner:Nick()), NOTIFY_ERROR, 8)
            end
        end
    end
end

function SWEP:Think()
    if not self:GetIsLockpicking() then return end

    local ply = self:GetOwner()
    local target = self:GetPickTarget()

    if not IsValid(ply) or not ply:Alive() or not IsValid(target) or ply:GetActiveWeapon() ~= self then
        self:CancelLockpick()
        return
    end

    local tr = ply:GetEyeTrace()
    local breakDistSqr = self.BreakLockpickDistance * self.BreakLockpickDistance
    if tr.Entity ~= target or tr.HitPos:DistToSqr(ply:EyePos()) > breakDistSqr then
        self:CancelLockpick()
        GW.Notify(ply, "Lockpicking interrupted (moved away)!", NOTIFY_ERROR, 3)
        return
    end

    -- Server-authoritative clicking sound effect
    if (self.NextClickSound or 0) < CurTime() then
        self.NextClickSound = CurTime() + 0.65
        self:EmitSound("weapons/357/357_reload3.wav", 60, math.random(110, 130))
    end

    -- Completion Check
    if CurTime() >= self:GetPickEndTime() then
        self:OnLockpickSuccess(ply, target)
        self:CancelLockpick()
    end
end

function SWEP:OnLockpickSuccess(ply, target)
    if not IsValid(ply) or not IsValid(target) then return end

    local isDoor = target.isDoor and target:isDoor() or (target.IsDoor and target:IsDoor())
    if isDoor then
        target:Fire("unlock", "", 0)
        target:Fire("open", "", 0)
        target:EmitSound("doors/door_latch3.wav", 75, 100)
        GW.Notify(ply, "Lock picked successfully!", NOTIFY_HINT, 4)
    elseif target:GetClass() == "prop_physics" then
        local phys = target:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(true)
            phys:Wake()
        end
        GW.Notify(ply, "Prop unsealed!", NOTIFY_HINT, 4)
    end
end
