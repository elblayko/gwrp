--[[
    entities/weapons/weapon_gwrp_base/shared.lua
    GWRP Gun Base
--]]

SWEP.PrintName = "GWRP Base"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary: Shoot\nSecondary: Iron Sights\nReload: Reload"

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

SWEP.ViewModel = "models/weapons/v_pistol.mdl"
SWEP.WorldModel = "models/weapons/w_pistol.mdl"
SWEP.HoldType = "pistol"
SWEP.UseHands = true

function SWEP:SetupDataTables()
    self:NetworkVar("Bool", 0, "Ironsights")
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType or "pistol")
end

function SWEP:PrimaryAttack()
    if not self:CanPrimaryAttack() then return end

    local ply = self:GetOwner()
    self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

    self:EmitSound(self.Primary.Sound)
    self:ShootBullet(self.Primary.Damage, self.Primary.NumberofShots, self.Primary.Spread)
    self:TakePrimaryAmmo(self.Primary.TakeAmmo)

    if IsValid(ply) then
        ply:ViewPunch(Angle(-self.Primary.Recoil, math.Rand(-self.Primary.Recoil * 0.5, self.Primary.Recoil * 0.5), 0))
    end
end

function SWEP:SecondaryAttack()
    if not self.IronSightsPos then return end
    self:SetIronsights(not self:GetIronsights())
    self:SetNextSecondaryFire(CurTime() + 0.3)
end

function SWEP:ShootBullet(dmg, numBullets, aimcone)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local bullet = {}
    bullet.Num = numBullets
    bullet.Src = ply:GetShootPos()
    bullet.Dir = ply:GetAimVector()
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
    ply:SetAnimation(PLAYER_ATTACK1)
end

function SWEP:Reload()
    if self:Clip1() >= self.Primary.ClipSize or self:GetOwner():GetAmmoCount(self.Primary.Ammo) <= 0 then return end
    self:DefaultReload(ACT_VM_RELOAD)
    self:SetIronsights(false)
end

function SWEP:Holster()
    self:SetIronsights(false)
    return true
end

if CLIENT then
    local crosshairCol = Color(255, 255, 255, 200)

    function SWEP:DrawHUD()
        if self:GetIronsights() then return end

        local x = ScrW() / 2
        local y = ScrH() / 2
        local len = 8
        local gap = 4

        surface.SetDrawColor(crosshairCol)
        surface.DrawLine(x - len - gap, y, x - gap, y)
        surface.DrawLine(x + gap, y, x + len + gap, y)
        surface.DrawLine(x, y - len - gap, x, y - gap)
        surface.DrawLine(x, y + gap, x, y + len + gap)
    end

    function SWEP:GetViewModelPosition(pos, ang)
        if not self.IronSightsPos then return pos, ang end

        local bIron = self:GetIronsights()
        if bIron ~= self.bLastIron then
            self.bLastIron = bIron
            self.fIronTime = CurTime()
        end

        local fIronTime = self.fIronTime or CurTime()
        local percent = math.Clamp((CurTime() - fIronTime) / 0.2, 0, 1)
        if not bIron then percent = 1 - percent end

        local offset = self.IronSightsPos
        if self.IronSightsAng then
            ang = ang * 1
            ang:RotateAroundAxis(ang:Right(), self.IronSightsAng.x * percent)
            ang:RotateAroundAxis(ang:Up(), self.IronSightsAng.y * percent)
            ang:RotateAroundAxis(ang:Forward(), self.IronSightsAng.z * percent)
        end

        pos = pos + offset.x * ang:Right() * percent
        pos = pos + offset.y * ang:Forward() * percent
        pos = pos + offset.z * ang:Up() * percent

        return pos, ang
    end
end
