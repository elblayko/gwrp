--[[
    entities/weapons/weapon_gwrp_deagle/shared.lua
    GWRP Desert Eagle .50 AE
--]]

SWEP.Base = "weapon_gwrp_base"
SWEP.PrintName = "Desert Eagle"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary: Fire .50 Hand Cannon\nSecondary: Iron Sights\nReload: Reload"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Primary.Sound = Sound("Weapon_357.Single")
SWEP.Primary.Damage = 52
SWEP.Primary.TakeAmmo = 1
SWEP.Primary.ClipSize = 7
SWEP.Primary.DefaultClip = 28
SWEP.Primary.Ammo = "357"
SWEP.Primary.Spread = 0.02
SWEP.Primary.NumberofShots = 1
SWEP.Primary.Automatic = false
SWEP.Primary.Recoil = 2.8
SWEP.Primary.Delay = 0.35

SWEP.Slot = 1
SWEP.SlotPos = 3
SWEP.HoldType = "pistol"

local hasCSS = util.IsValidModel("models/weapons/v_pist_deagle.mdl")
SWEP.ViewModel = hasCSS and "models/weapons/v_pist_deagle.mdl" or "models/weapons/v_357.mdl"
SWEP.WorldModel = hasCSS and "models/weapons/w_pist_deagle.mdl" or "models/weapons/w_357.mdl"

SWEP.IronSightsPos = Vector(-6.3, -4, 2.2)
SWEP.IronSightsAng = Vector(0, 0, 0)
