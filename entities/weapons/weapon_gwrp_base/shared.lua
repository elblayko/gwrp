--[[
    entities/weapons/weapon_gwrp_base/shared.lua
    GWRP Gun Base
--]]

AddCSLuaFile()

SWEP.PrintName = "GWRP Base"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary: Shoot\nSecondary: Iron Sights\nReload: Reload"
SWEP.Category = "GangWars RP"

SWEP.Spawnable = false
SWEP.AdminOnly = false

SWEP.Primary.Sound = Sound("Weapon_Pistol.Single")
SWEP.Primary.Damage = 20
SWEP.Primary.TakeAmmo = 1
SWEP.Primary.ClipSize = 15
SWEP.Primary.DefaultClip = 45
SWEP.Primary.Ammo = "Pistol"
SWEP.Primary.Spread = 0.02
SWEP.Primary.NumberofShots = 1
SWEP.Primary.Automatic = false
SWEP.Primary.Recoil = 1.0
SWEP.Primary.Delay = 0.2

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Weight = 5
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false

SWEP.Slot = 1
SWEP.SlotPos = 1
SWEP.DrawAmmo = true
SWEP.DrawCrosshair = false

SWEP.ViewModel = "models/weapons/c_pistol.mdl"
SWEP.WorldModel = "models/weapons/w_pistol.mdl"
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.HoldType = "pistol"
SWEP.UseHands = true

SWEP.IronSightsPos = Vector(-5.76, -8, 3.15)
SWEP.IronSightsAng = Vector(0, -1.1, 0)
SWEP.IronSightsFOV = 0.8

function SWEP:SetupDataTables()
    self:NetworkVar("Bool", 0, "Ironsights")
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType or "pistol")
    self:SetIronsights(false)
end

function SWEP:Deploy()
    self:SetHoldType(self.HoldType or "pistol")
    self:SetIronsights(false)
    self.IronSightsProgress = 0
    return true
end

function SWEP:PrimaryAttack()
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    if not self:CanPrimaryAttack() then return end

    self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

    local isIron = self:GetIronsights()
    local spread = isIron and (self.Primary.Spread * 0.5) or self.Primary.Spread
    local recoil = isIron and (self.Primary.Recoil * 0.7) or self.Primary.Recoil

    self:EmitSound(self.Primary.Sound)
    self:ShootBullet(self.Primary.Damage, self.Primary.NumberofShots, spread)
    self:TakePrimaryAmmo(self.Primary.TakeAmmo)

    local yawKick = util.SharedRandom("GWRP_RecoilYaw", -recoil * 0.5, recoil * 0.5)
    ply:ViewPunch(Angle(-recoil, yawKick, 0))
end

function SWEP:SecondaryAttack()
    if not self.IronSightsPos then return end
    self:SetIronsights(not self:GetIronsights())
    self:SetNextSecondaryFire(CurTime() + 0.25)
end

function SWEP:ShootBullet(dmg, numBullets, aimcone)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    -- Include ViewPunchAngles so shots always align with the camera and crosshair during recoil
    local aimDir = (ply:EyeAngles() + ply:GetViewPunchAngles()):Forward()

    local bullet = {}
    bullet.Num = numBullets
    bullet.Src = ply:GetShootPos()
    bullet.Dir = aimDir
    bullet.Spread = Vector(aimcone, aimcone, 0)
    bullet.Tracer = 1
    bullet.Force = dmg * 0.5
    bullet.Damage = dmg
    bullet.AmmoType = self.Primary.Ammo

    bullet.Callback = function(att, tr, dmginfo)
        -- Can add custom hit effects or damage mod here
    end

    ply:FireBullets(bullet)
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    ply:MuzzleFlash()
    ply:SetAnimation(PLAYER_ATTACK1)
end

function SWEP:Reload()
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    if self:Clip1() >= self.Primary.ClipSize or ply:GetAmmoCount(self.Primary.Ammo) <= 0 then return end

    if self:DefaultReload(ACT_VM_RELOAD) then
        self:SetIronsights(false)
    end
end

function SWEP:Holster()
    self:SetIronsights(false)
    self.IronSightsProgress = 0
    return true
end

if CLIENT then
    local crosshairCol = Color(255, 255, 255, 200)
    local crosshairOutlineCol = Color(0, 0, 0, 180)

    function SWEP:DrawHUD()
        if self:GetIronsights() or (self.IronSightsProgress and self.IronSightsProgress > 0.5) then return end

        local ply = self:GetOwner()
        local x = math.Round(ScrW() / 2)
        local y = math.Round(ScrH() / 2)

        if IsValid(ply) then
            local shootPos = ply:GetShootPos()
            local aimDir = (ply:EyeAngles() + ply:GetViewPunchAngles()):Forward()
            local tr = util.TraceLine({
                start = shootPos,
                endpos = shootPos + aimDir * 16384,
                filter = ply,
                mask = MASK_SHOT
            })
            local screenPos = tr.HitPos:ToScreen()
            if screenPos.visible then
                x = math.Round(screenPos.x)
                y = math.Round(screenPos.y)
            end
        end

        local len = 8
        local gap = 4

        -- Subtle dark outline for visibility on bright surfaces
        surface.SetDrawColor(crosshairOutlineCol)
        surface.DrawRect(x - len - gap - 1, y - 1, len + 2, 3)
        surface.DrawRect(x + gap - 1, y - 1, len + 2, 3)
        surface.DrawRect(x - 1, y - len - gap - 1, 3, len + 2)
        surface.DrawRect(x - 1, y + gap - 1, 3, len + 2)

        surface.SetDrawColor(crosshairCol)
        surface.DrawLine(x - len - gap, y, x - gap, y)
        surface.DrawLine(x + gap, y, x + len + gap, y)
        surface.DrawLine(x, y - len - gap, x, y - gap)
        surface.DrawLine(x, y + gap, x, y + len + gap)
    end

    function SWEP:GetViewModelPosition(pos, ang)
        if not self.IronSightsPos then return pos, ang end

        local target = self:GetIronsights() and 1 or 0
        self.IronSightsProgress = math.Approach(self.IronSightsProgress or 0, target, FrameTime() * 5)

        local percent = self.IronSightsProgress
        if percent <= 0 then return pos, ang end

        -- Smooth step interpolation for natural ADS feel
        local smooth = percent * percent * (3 - 2 * percent)
        local rightMul = self.ViewModelFlip and -1 or 1

        local offset = self.IronSightsPos
        if self.IronSightsAng then
            ang = ang * 1
            ang:RotateAroundAxis(ang:Right(), self.IronSightsAng.x * smooth)
            ang:RotateAroundAxis(ang:Up(), self.IronSightsAng.y * smooth * rightMul)
            ang:RotateAroundAxis(ang:Forward(), self.IronSightsAng.z * smooth * rightMul)
        end

        pos = pos + offset.x * ang:Right() * smooth * rightMul
        pos = pos + offset.y * ang:Forward() * smooth
        pos = pos + offset.z * ang:Up() * smooth

        return pos, ang
    end

    function SWEP:TranslateFOV(currentFOV)
        local percent = self.IronSightsProgress or 0
        if percent <= 0 then return currentFOV end

        local targetFOV = currentFOV * (self.IronSightsFOV or 0.8)
        return Lerp(percent, currentFOV, targetFOV)
    end

    function SWEP:AdjustMouseSensitivity()
        if self:GetIronsights() then
            return self.IronSightsFOV or 0.8
        end
        return 1
    end
end
