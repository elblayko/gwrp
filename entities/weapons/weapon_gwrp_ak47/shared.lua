--[[
    entities/weapons/weapon_gwrp_ak47/shared.lua
    GWRP AK-47 Assault Rifle
--]]

SWEP.Base = "weapon_gwrp_base"
SWEP.PrintName = "AK-47"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary: Fully Automatic Fire\nSecondary: Iron Sights\nReload: Reload"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Primary.Sound = Sound("Weapon_AR2.Single")
SWEP.Primary.Damage = 35
SWEP.Primary.TakeAmmo = 1
SWEP.Primary.ClipSize = 30
SWEP.Primary.DefaultClip = 90
SWEP.Primary.Ammo = "AR2"
SWEP.Primary.Spread = 0.035
SWEP.Primary.NumberofShots = 1
SWEP.Primary.Automatic = true
SWEP.Primary.Recoil = 1.6
SWEP.Primary.Delay = 0.1

SWEP.Slot = 2
SWEP.SlotPos = 1
SWEP.HoldType = "ar2"

local hasCSS = util.IsValidModel("models/weapons/v_rif_ak47.mdl")
SWEP.ViewModel = hasCSS and "models/weapons/v_rif_ak47.mdl" or "models/weapons/v_smg1.mdl"
SWEP.WorldModel = hasCSS and "models/weapons/w_rif_ak47.mdl" or "models/weapons/w_smg1.mdl"

SWEP.IronSightsPos = Vector(-6.6, -6, 2.3)
SWEP.IronSightsAng = Vector(2, 0, 0)
