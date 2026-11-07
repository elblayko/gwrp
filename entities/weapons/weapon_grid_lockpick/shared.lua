--[[
    entities/weapons/weapon_grid_lockpick/shared.lua
    GridRP Tactical Lockpick - Shared
    Author: Juicebox
--]]

SWEP.PrintName = "Tactical Lockpick"
SWEP.Author = "Juicebox"
SWEP.Instructions = "Primary Fire: Lockpick a locked door or barricade (20s)\nSecondary Fire: Cancel active lockpicking"
SWEP.Category = "GridRP"

SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.RequiredLevel = 1

SWEP.Slot = 4
SWEP.SlotPos = 1
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false

SWEP.ViewModel = "models/weapons/c_crowbar.mdl"
SWEP.WorldModel = "models/weapons/w_crowbar.mdl"
SWEP.UseHands = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.LockpickTime = 20
SWEP.MaxLockpickDistance = 100
SWEP.BreakLockpickDistance = 125

function SWEP:SetupDataTables()
    self:NetworkVar("Bool", 0, "IsLockpicking")
    self:NetworkVar("Float", 0, "PickStartTime")
    self:NetworkVar("Float", 1, "PickEndTime")
    self:NetworkVar("Entity", 0, "PickTarget")
end

function SWEP:Initialize()
    self:SetHoldType("normal")
end

function SWEP:Deploy()
    self:SetHoldType("normal")
    return true
end

function SWEP:Holster()
    self:CancelLockpick()
    return true
end

function SWEP:OnDrop()
    self:CancelLockpick()
end

function SWEP:OnRemove()
    self:CancelLockpick()
end

function SWEP:OwnerChanged()
    self:CancelLockpick()
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.5)
    if self:GetIsLockpicking() then return end

    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    local distSqr = self.MaxLockpickDistance * self.MaxLockpickDistance
    if not IsValid(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > distSqr then return end

    local isDoor = ent.isDoor and ent:isDoor() or (ent.IsDoor and ent:IsDoor())
    local isPracticeStash = (ent:GetClass() == "grid_practice_stash" or ent.IsPracticeStash == true)
    if not isDoor and ent:GetClass() ~= "prop_physics" and not isPracticeStash then return end

    if SERVER then
        self:StartLockpick(ply, ent)
    end
end

function SWEP:SecondaryAttack()
    if self:GetIsLockpicking() then
        if SERVER then
            local ply = self:GetOwner()
            if IsValid(ply) then
                GRID.Notify(ply, "Lockpicking aborted.", NOTIFY_GENERIC, 2)
            end
        end
        self:CancelLockpick()
    end
end

function SWEP:CancelLockpick()
    if self:GetIsLockpicking() then
        self:SetIsLockpicking(false)
        self:SetPickTarget(NULL)
        self:SetHoldType("normal")
        self.NextClickSound = nil
    end
end
