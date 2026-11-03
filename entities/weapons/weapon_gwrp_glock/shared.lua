--[[
    entities/weapons/weapon_gwrp_glock/shared.lua
    GWRP 9mm Glock
--]]

SWEP.Base = "weapon_gwrp_base"
SWEP.PrintName = "Glock 18"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary: Fire Semi-Auto\nSecondary: Iron Sights\nReload: Reload"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Primary.Sound = Sound("Weapon_Pistol.Single")
SWEP.Primary.Damage = 22
SWEP.Primary.TakeAmmo = 1
SWEP.Primary.ClipSize = 20
SWEP.Primary.DefaultClip = 60
SWEP.Primary.Ammo = "Pistol"
SWEP.Primary.Spread = 0.025
SWEP.Primary.NumberofShots = 1
SWEP.Primary.Automatic = false
SWEP.Primary.Recoil = 0.8
SWEP.Primary.Delay = 0.15

SWEP.Slot = 1
SWEP.SlotPos = 2
SWEP.HoldType = "pistol"

local hasCSS = util.IsValidModel("models/weapons/v_pist_glock18.mdl")
SWEP.ViewModel = hasCSS and "models/weapons/v_pist_glock18.mdl" or "models/weapons/v_pistol.mdl"
SWEP.WorldModel = hasCSS and "models/weapons/w_pist_glock18.mdl" or "models/weapons/w_pistol.mdl"

SWEP.IronSightsPos = Vector(-5.9, -4, 2.7)
SWEP.IronSightsAng = Vector(0, 0, 0)
