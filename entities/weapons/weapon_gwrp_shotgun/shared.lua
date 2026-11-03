--[[
    entities/weapons/weapon_gwrp_shotgun/shared.lua
    GWRP Pump Shotgun
--]]

AddCSLuaFile()

SWEP.Base = "weapon_gwrp_base"
SWEP.PrintName = "Pump Shotgun"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary: Shotgun Blast\nSecondary: Iron Sights\nReload: Reload"
SWEP.Category = "GangWars RP"

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
SWEP.UseHands = true
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false

local hasCStrike = util.IsValidModel("models/weapons/cstrike/c_shot_m3super90.mdl")
SWEP.ViewModel = hasCStrike and "models/weapons/cstrike/c_shot_m3super90.mdl" or "models/weapons/c_shotgun.mdl"
SWEP.WorldModel = util.IsValidModel("models/weapons/w_shot_m3super90.mdl") and "models/weapons/w_shot_m3super90.mdl" or "models/weapons/w_shotgun.mdl"

SWEP.IronSightsPos = hasCStrike and Vector(-7.65, -8, 3.5) or Vector(-8.96, -10, 4.15)
SWEP.IronSightsAng = Vector(0, 0, 0)
