--[[
    entities/weapons/weapon_grid_glock/shared.lua
    GridRP 9mm Glock
--]]

AddCSLuaFile()

SWEP.Base = "weapon_grid_base"
SWEP.PrintName = "Glock 18"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary: Fire Semi-Auto\nSecondary: Iron Sights\nReload: Reload"
SWEP.Category = "GridRP"

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
SWEP.UseHands = true
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false

local hasCStrike = util.IsValidModel("models/weapons/cstrike/c_pist_glock18.mdl")
SWEP.ViewModel = hasCStrike and "models/weapons/cstrike/c_pist_glock18.mdl" or "models/weapons/c_pistol.mdl"
SWEP.WorldModel = util.IsValidModel("models/weapons/w_pist_glock18.mdl") and "models/weapons/w_pist_glock18.mdl" or "models/weapons/w_pistol.mdl"

SWEP.IronSightsPos = hasCStrike and Vector(-5.78, -10, 2.68) or Vector(-5.76, -8, 3.15)
SWEP.IronSightsAng = hasCStrike and Vector(0.7, 0, 0) or Vector(0, -1.1, 0)
