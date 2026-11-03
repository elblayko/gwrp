--[[
    entities/weapons/weapon_gwrp_repairtool/shared.lua
    GWRP Printer Maintenance Welder & Coolant Tool
    Author: Toxic
--]]

SWEP.PrintName = "Cryo-Thermal Calibrator"
SWEP.Author = "Toxic"
SWEP.Instructions = "Left Click: Flash-Cool & Repair Printer (Instant 20°C)\nRight Click: Cyber-Tune Printer (Cyber Engineer)"
SWEP.Category = "GangWars RP"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Weight = 2
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false

SWEP.Slot = 2
SWEP.SlotPos = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/weapons/w_slam.mdl"
SWEP.UseHands = true

function SWEP:Initialize()
    self:SetHoldType("slam")
end

local function IsPrinter(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    if class == "gwrp_printer_bronze" or class == "gwrp_printer_silver" or class == "gwrp_printer_diamond" or ent.PrintAmount ~= nil or class == "gwrp_resource_machine" then
        return true
    end
    return false
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.8)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity

    if not IsValid(ent) or not IsPrinter(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > (130 * 130) then
        if CLIENT and IsFirstTimePredicted() then
            -- Muted click if missing target
        end
        return
    end

    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    ply:SetAnimation(PLAYER_ATTACK1)

    if SERVER then
        local curTemp = ent.GetTemperature and ent:GetTemperature() or 20
        if curTemp <= 20 then
            GWRP.Notify(ply, "Printer is already at optimal ambient temperature (20°C).", NOTIFY_HINT)
            return
        end

        local coolDrop = curTemp - 20
        if ent.CoolAndRepair then
            ent:CoolAndRepair(coolDrop)
        else
            ent:SetTemperature(20)
        end

        local spark = EffectData()
        spark:SetOrigin(tr.HitPos)
        spark:SetNormal(tr.HitNormal)
        spark:SetMagnitude(2)
        spark:SetScale(1)
        util.Effect("Sparks", spark)

        GWRP.Notify(ply, string.format("Flash-Cooled printer instantly to optimal ambient temp (20°C)! (-%d°C dissipated)", coolDrop), NOTIFY_GENERIC)
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1.0)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity

    if not IsValid(ent) or not IsPrinter(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > (150 * 150) then return end

    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    ply:SetAnimation(PLAYER_ATTACK1)

    if SERVER then
        local isEngineer = (ply.GetJob and ply:GetJob() == "cyber_engineer")
        if not isEngineer then
            GWRP.Notify(ply, "Cyber-Tuning requires a Cyber Engineer.", NOTIFY_HINT)
            return
        end

        local isTuned = ent.GetIsTuned and ent:GetIsTuned()
        if isTuned then
            GWRP.Notify(ply, string.format("%s is already Cyber-Tuned (+20%% Yield, -25%% Heat).", ent.PrintName or "Printer"), NOTIFY_HINT, 4)
            return
        end

        if ent.TunePrinter then
            ent:TunePrinter(ply)
        elseif ent.SetIsTuned then
            ent:SetIsTuned(true)
        end

        local spark = EffectData()
        spark:SetOrigin(tr.HitPos)
        spark:SetNormal(tr.HitNormal)
        spark:SetMagnitude(3)
        spark:SetScale(1.5)
        util.Effect("Sparks", spark)

        GWRP.Notify(ply, string.format("Supercharged %s! Applied Cyber-Tuned calibration (+20%% Yield, -25%% Heat)!", ent.PrintName or "Printer"), NOTIFY_GENERIC, 6)

        local owner = ent.GetOwnerPlayer and ent:GetOwnerPlayer() or ent.OwnerPlayer
        if IsValid(owner) and owner:IsPlayer() and owner ~= ply then
            GWRP.Notify(owner, string.format("A Cyber Engineer fine-tuned your %s (+20%% Yield, -25%% Heat)!", ent.PrintName or "Printer"), NOTIFY_GENERIC, 6)
        end
    end
end
