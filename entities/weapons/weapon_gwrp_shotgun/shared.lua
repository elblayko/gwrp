--[[
    entities/weapons/weapon_gwrp_shotgun/shared.lua
    GWRP Pump Shotgun
--]]

SWEP.Base = "weapon_gwrp_base"
SWEP.PrintName = "Pump Shotgun"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary: Shotgun Blast\nSecondary: Iron Sights\nReload: Reload"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Primary.Sound = Sound("Weapon_Shotgun.Single")
SWEP.Primary.Damage = 13
SWEP.Primary.TakeAmmo = 1
SWEP.Primary.ClipSize = 8
SWEP.Primary.DefaultClip = 32
SWEP.Primary.Ammo = "Buckshot"
SWEP.Primary.Spread = 0.08
SWEP.Primary.NumberofShots = 8
SWEP.Primary.Automatic = false
SWEP.Primary.Recoil = 3.2
SWEP.Primary.Delay = 0.85

SWEP.Slot = 3
SWEP.SlotPos = 1
SWEP.HoldType = "shotgun"

local hasCSS = util.IsValidModel("models/weapons/v_shot_m3super90.mdl")
SWEP.ViewModel = hasCSS and "models/weapons/v_shot_m3super90.mdl" or "models/weapons/v_shotgun.mdl"
SWEP.WorldModel = hasCSS and "models/weapons/w_shot_m3super90.mdl" or "models/weapons/w_shotgun.mdl"

SWEP.IronSightsPos = Vector(-5.0, -3, 2.0)
SWEP.IronSightsAng = Vector(0, 0, 0)
