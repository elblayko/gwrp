--[[
    entities/weapons/weapon_gw_keys/shared.lua
    GWRP Hands & Key Utilities
    Author: Toxic
--]]

AddCSLuaFile()

SWEP.PrintName = "Hands"
SWEP.Author = "Toxic"
SWEP.Instructions = "Left Click: Lock Door\nRight Click: Unlock Door / Pickup Item to Inventory\nReload: Knock on Door"
SWEP.Category = "GangWars RP"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Weight = 1
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false

SWEP.Slot = 0
SWEP.SlotPos = 1
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""
SWEP.UseHands = true

function SWEP:Initialize()
    self:SetHoldType("normal")
end

local function GetTargetDoor(ply)
    local tr = ply:GetEyeTrace()
    if not tr.Hit or not IsValid(tr.Entity) then return nil end
    local isDoor = tr.Entity.isDoor and tr.Entity:isDoor() or (tr.Entity.IsDoor and tr.Entity:IsDoor())
    if not isDoor then return nil end
    if tr.HitPos:DistToSqr(ply:EyePos()) > 85 * 85 then return nil end
    return tr.Entity
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.4)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local door = GetTargetDoor(ply)
    if not door then return end

    if SERVER then
        if door:CanAccessDoor(ply) then
            door:Fire("lock", "", 0)
            door:EmitSound("doors/door_locked2.wav", 65, 100)
            GW.Notify(ply, "Door locked.", NOTIFY_GENERIC)
        else
            GW.Notify(ply, "You do not have keys to this door!", NOTIFY_ERROR)
            door:EmitSound("doors/handle_pushbar_locked1.wav", 65, 100)
        end
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.4)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local door = GetTargetDoor(ply)
    if door then
        if SERVER then
            if door:CanAccessDoor(ply) then
                door:Fire("unlock", "", 0)
                door:EmitSound("doors/door_latch3.wav", 65, 100)
                GW.Notify(ply, "Door unlocked.", NOTIFY_GENERIC)
            else
                GW.Notify(ply, "You do not have keys to this door!", NOTIFY_ERROR)
                door:EmitSound("doors/handle_pushbar_locked1.wav", 65, 100)
            end
        end
        return
    end

    -- If not looking at a door, check for pickupable entities/items
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if IsValid(ent) and tr.HitPos:DistToSqr(ply:EyePos()) <= (95 * 95) then
        self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
        if SERVER and GW.Inventory and GW.Inventory.PickupEntity then
            GW.Inventory.PickupEntity(ply, ent)
        end
    end
end

function SWEP:Reload()
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local door = GetTargetDoor(ply)
    if not door then return end

    if CurTime() < (self.NextKnock or 0) then return end
    self.NextKnock = CurTime() + 1.0

    if SERVER then
        door:EmitSound("physics/wood/wood_crate_impact_hard2.wav", 75, 110)
        door:Fire("open", "", 0)
    end
end
