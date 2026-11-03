--[[
    entities/weapons/weapon_gw_medkit/shared.lua
    GWRP Field Medical Kit
    Author: Toxic
--]]

AddCSLuaFile()

SWEP.PrintName = "Medical Kit"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary Fire: Heal targeted ally\nSecondary Fire: Self-Heal or Adrenaline Injector (Target Ally)\nReload: Self Adrenaline Injection (Pharmacist)"
SWEP.Category = "GangWars RP"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Slot = 4
SWEP.SlotPos = 2
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_medkit.mdl"
SWEP.WorldModel = "models/weapons/w_medkit.mdl"
SWEP.UseHands = true

SWEP.Primary.Recoil = 0
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Delay = 0.4
SWEP.Primary.Ammo = "none"

SWEP.Secondary.Recoil = 0
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Delay = 0.5
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
    self:SetHoldType("slam")
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local target = tr.Entity

    if not IsValid(target) or not target:IsPlayer() or not target:Alive() or tr.HitPos:DistToSqr(ply:EyePos()) > (85 * 85) then
        return
    end

    local maxHp = target:GetMaxHealth() or 100
    if target:Health() >= maxHp then return end

    if SERVER then
        local healAmount = 15
        local newHp = math.min(target:Health() + healAmount, maxHp)
        target:SetHealth(newHp)
        target:EmitSound("items/smallmedkit1.wav", 65, 100)
        self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    end
end

function SWEP:SecondaryAttack()
    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:Alive() then return end

    local isPharmacist = (ply:GetJob() == "pharmacist")
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    local isTargetAlly = IsValid(target) and target:IsPlayer() and target:Alive() and (tr.HitPos:DistToSqr(ply:EyePos()) <= (95 * 95))

    -- Pharmacist Specialty: If targeting an ally, administer Combat Adrenaline Stim (+25% speed for 45s)
    if isPharmacist and isTargetAlly then
        self:SetNextSecondaryFire(CurTime() + 15) -- 15s tactical cooldown

        if SERVER then
            if target.AddBuff then
                target:AddBuff("swiftness", 45)
            elseif GW.Buffs and GW.Buffs.Apply then
                GW.Buffs.Apply(target, "swiftness", 45)
            end
            target:EmitSound("items/medshot4.wav", 75, 105)
            self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)

            GW.Notify(target, string.format("Dr. %s administered Combat Adrenaline! (+25%% Speed for 45s)", ply:Nick()), NOTIFY_GENERIC, 5)
            GW.Notify(ply, string.format("Administered Combat Adrenaline to %s!", target:Nick()), NOTIFY_HINT, 4)
        end
        return
    end

    -- Default: Self-heal
    self:SetNextSecondaryFire(CurTime() + self.Secondary.Delay)

    local maxHp = ply:GetMaxHealth() or 100
    if ply:Health() >= maxHp then return end

    if SERVER then
        local healAmount = 10
        local newHp = math.min(ply:Health() + healAmount, maxHp)
        ply:SetHealth(newHp)
        ply:EmitSound("items/smallmedkit1.wav", 65, 95)
        self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    end
end

function SWEP:Reload()
    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:Alive() then return end

    -- Pharmacist emergency adrenaline self-injection
    if ply:GetJob() == "pharmacist" then
        if (self.NextSelfAdrenaline or 0) > CurTime() then
            if CLIENT and IsFirstTimePredicted() then
                local remaining = math.ceil(self.NextSelfAdrenaline - CurTime())
                ply:ChatPrint(string.format("[Medical Kit] Self-Adrenaline ready in %ds", remaining))
            end
            return
        end

        self.NextSelfAdrenaline = CurTime() + 30
        self:SetNextPrimaryFire(CurTime() + 1.0)
        self:SetNextSecondaryFire(CurTime() + 1.0)

        if SERVER then
            if ply.AddBuff then
                ply:AddBuff("swiftness", 30)
            elseif GW.Buffs and GW.Buffs.Apply then
                GW.Buffs.Apply(ply, "swiftness", 30)
            end
            ply:EmitSound("items/medshot4.wav", 75, 110)
            self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
            GW.Notify(ply, "Administered Emergency Combat Adrenaline (+25% Speed for 30s)!", NOTIFY_GENERIC, 5)
        end
    end
end
