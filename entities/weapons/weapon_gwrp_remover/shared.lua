--[[
    entities/weapons/weapon_gwrp_remover/shared.lua
    GWRP Dedicated Remover Tool
    Author: Toxic
--]]

AddCSLuaFile()

SWEP.PrintName = "Remover Tool"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary Fire: Remove targeted prop or entity\nSecondary Fire: Remove connected constraints"
SWEP.Category = "GangWars RP"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Delay = 0.25
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Delay = 0.5
SWEP.Secondary.Ammo = "none"

SWEP.Weight = 2
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false

SWEP.Slot = 0
SWEP.SlotPos = 5
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_toolgun.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.UseHands = true

function SWEP:Initialize()
    self:SetHoldType("pistol")
end

local function CanRemove(ply, ent)
    if not IsValid(ent) then return false end
    if ent:IsPlayer() or ent:IsNPC() or ent:IsWorld() then return false end

    -- Map protection: never remove doors or map geometry
    local class = ent:GetClass()
    if class == "func_door" or class == "func_door_rotating" or class == "prop_door_rotating" or class == "func_brush" or class == "func_wall" then
        return false
    end

    -- Server Admin can remove anything
    if ply:IsAdmin() or ply:IsSuperAdmin() then
        return true
    end

    -- CPPI / Prop Protection check
    if ent.CPPICanTool then
        local ok = ent:CPPICanTool(ply, "remover")
        if ok ~= nil then return ok end
    end

    -- Direct owner match
    if ent.GetOwnerPlayer and ent:GetOwnerPlayer() == ply then
        return true
    end
    if ent.Owner == ply or ent.PropOwner == ply or ent.GWRP_Owner == ply then
        return true
    end

    -- Props spawned by this player
    if ent.GetPhysicsObject and ent:GetClass() == "prop_physics" then
        if not ent.Owner or ent.Owner == ply then
            return true
        end
    end

    return false
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity

    if not IsValid(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > (450 * 450) then
        return
    end

    if not CanRemove(ply, ent) then
        if CLIENT and IsFirstTimePredicted() then
            surface.PlaySound("buttons/button10.wav")
        end
        if SERVER then
            GWRP.Notify(ply, "You do not have permission to remove this entity!", NOTIFY_ERROR)
        end
        return
    end

    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    ply:SetAnimation(PLAYER_ATTACK1)

    -- Red Toolgun Laser Beam Effect
    local effect = EffectData()
    effect:SetOrigin(tr.HitPos)
    effect:SetStart(ply:GetShootPos())
    effect:SetAttachment(1)
    effect:SetEntity(self)
    util.Effect("ToolTracer", effect)

    -- Sparks at impact
    local spark = EffectData()
    spark:SetOrigin(tr.HitPos)
    spark:SetNormal(tr.HitNormal)
    spark:SetMagnitude(2)
    spark:SetScale(1)
    util.Effect("Sparks", spark)

    self:EmitSound("weapons/airboat/airboat_gun_energy1.wav", 65, 120, 0.6)

    if SERVER then
        local entName = ent.PrintName or ent:GetClass()
        ent:Remove()
        GWRP.Notify(ply, "Removed " .. entName .. "!", NOTIFY_HINT)
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + self.Secondary.Delay)

    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity

    if not IsValid(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > (450 * 450) then
        return
    end

    if not CanRemove(ply, ent) then
        if CLIENT and IsFirstTimePredicted() then
            surface.PlaySound("buttons/button10.wav")
        end
        if SERVER then
            GWRP.Notify(ply, "You do not have permission to remove constraints on this entity!", NOTIFY_ERROR)
        end
        return
    end

    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    ply:SetAnimation(PLAYER_ATTACK1)

    self:EmitSound("buttons/button19.wav", 65, 100)

    if SERVER then
        if constraint and constraint.RemoveAll then
            constraint.RemoveAll(ent)
            GWRP.Notify(ply, "Removed all constraints on " .. (ent.PrintName or ent:GetClass()) .. "!", NOTIFY_HINT)
        end
    end
end
