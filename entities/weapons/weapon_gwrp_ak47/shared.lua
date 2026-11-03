--[[
    entities/weapons/weapon_gwrp_ak47/shared.lua
    GWRP AK-47 Assault Rifle
--]]

AddCSLuaFile()

SWEP.Base = "weapon_gwrp_base"
SWEP.PrintName = "AK-47"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary: Fully Automatic Fire\nSecondary: Iron Sights\nReload: Reload"
SWEP.Category = "GangWars RP"

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
SWEP.UseHands = true
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false

local hasCStrike = util.IsValidModel("models/weapons/cstrike/c_rif_ak47.mdl")
SWEP.ViewModel = hasCStrike and "models/weapons/cstrike/c_rif_ak47.mdl" or "models/weapons/c_smg1.mdl"
SWEP.WorldModel = util.IsValidModel("models/weapons/w_rif_ak47.mdl") and "models/weapons/w_rif_ak47.mdl" or "models/weapons/w_smg1.mdl"

SWEP.IronSightsPos = hasCStrike and Vector(-6.6, -15, 2.6) or Vector(-6.43, -10, 1.05)
SWEP.IronSightsAng = hasCStrike and Vector(2.4, 0.02, 0) or Vector(0, 0, 0)
