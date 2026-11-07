--[[
    entities/weapons/weapon_grid_stunstick/shared.lua
    GridRP Police Tactical Stun Baton (Vanilla Strike + Arrest Warrant Booking)
    Author: Juicebox / GRID Core Team
--]]

AddCSLuaFile()

SWEP.PrintName = "Tactical Stun Baton"
SWEP.Author = "GRID Core Team"
SWEP.Instructions = "Primary Fire: Non-lethal compliance strike\nSecondary Fire: Arrest wanted suspect and book into jail"
SWEP.Category = "GridRP"

SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.Base = "weapon_base"

SWEP.Slot = 0
SWEP.SlotPos = 2
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_stunstick.mdl"
SWEP.WorldModel = "models/weapons/w_stunbaton.mdl"
SWEP.UseHands = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Delay = 0.75
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Delay = 1.0
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
    self:SetHoldType("melee")
end

function SWEP:Deploy()
    self:EmitSound("weapons/stunstick/spark" .. math.random(1, 3) .. ".wav", 65, 100)
    return true
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
    self:SetNextSecondaryFire(CurTime() + self.Primary.Delay)

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    owner:SetAnimation(PLAYER_ATTACK1)

    local startPos = owner:GetShootPos()
    local aimVec = owner:GetAimVector()
    local endPos = startPos + (aimVec * 75)

    local tr = util.TraceLine({
        start = startPos,
        endpos = endPos,
        filter = owner,
        mask = MASK_SHOT_HULL
    })

    if not tr.Hit then
        tr = util.TraceHull({
            start = startPos,
            endpos = endPos,
            filter = owner,
            mins = Vector(-10, -10, -8),
            maxs = Vector(10, 10, 8),
            mask = MASK_SHOT_HULL
        })
    end

    if tr.Hit then
        self:SendWeaponAnim(ACT_VM_HITCENTER)
        self:EmitSound("weapons/stunstick/stunstick_impact" .. math.random(1, 2) .. ".wav", 75, 100)

        local ed = EffectData()
        ed:SetOrigin(tr.HitPos)
        ed:SetNormal(tr.HitNormal)
        util.Effect("StunstickImpact", ed)

        if SERVER and IsValid(tr.Entity) then
            local dmg = DamageInfo()
            dmg:SetAttacker(owner)
            dmg:SetInflictor(self)
            dmg:SetDamage(35)
            dmg:SetDamageType(DMG_CLUB)
            dmg:SetDamagePosition(tr.HitPos)
            dmg:SetDamageForce(aimVec * 8000)
            tr.Entity:TakeDamageInfo(dmg)
        end
    else
        self:SendWeaponAnim(ACT_VM_MISSCENTER)
        self:EmitSound("weapons/stunstick/stunstick_swing" .. math.random(1, 2) .. ".wav", 70, 100)
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + self.Secondary.Delay)
    self:SetNextPrimaryFire(CurTime() + 0.5)

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local startPos = owner:GetShootPos()
    local aimVec = owner:GetAimVector()
    local endPos = startPos + (aimVec * 85)

    local tr = util.TraceHull({
        start = startPos,
        endpos = endPos,
        filter = owner,
        mins = Vector(-12, -12, -12),
        maxs = Vector(12, 12, 12),
        mask = MASK_SHOT_HULL
    })

    local target = tr.Entity
    if IsValid(target) and target:IsPlayer() then
        if SERVER then
            local isLockdownWarrantless = (GRID.Turf and GRID.Turf.IsLockdownActive and GRID.Turf.IsLockdownActive() and not target:IsPolice())
            if target:IsWanted() or isLockdownWarrantless then
                self:SendWeaponAnim(ACT_VM_HITCENTER)
                self:EmitSound("weapons/stunstick/spark" .. math.random(1, 3) .. ".wav", 80, 100)

                local ed = EffectData()
                ed:SetOrigin(tr.HitPos)
                ed:SetNormal(tr.HitNormal)
                util.Effect("cball_explode", ed)

                local bookingReason = isLockdownWarrantless and "Martial Law Curfew Enforcement" or nil
                GRID.Jail.JailPlayer(target, owner, nil, nil, bookingReason)
            else
                owner:EmitSound("buttons/button10.wav", 65, 100)
                GRID.Notify(owner, "Suspect is not wanted!", NOTIFY_ERROR, 5)
            end
        end
    else
        self:SendWeaponAnim(ACT_VM_MISSCENTER)
        self:EmitSound("weapons/stunstick/stunstick_swing1.wav", 65, 100)
    end
end

