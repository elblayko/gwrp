--[[
    entities/weapons/weapon_gw_deagle/shared.lua
    GWRP Desert Eagle .50 AE
--]]

AddCSLuaFile()

SWEP.Base = "weapon_gw_base"
SWEP.PrintName = "Desert Eagle"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary: Fire .50 Hand Cannon\nSecondary: Iron Sights\nReload: Reload"
SWEP.Category = "GangWars RP"

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
SWEP.UseHands = true
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false

local hasCStrike = util.IsValidModel("models/weapons/cstrike/c_pist_deagle.mdl")
SWEP.ViewModel = hasCStrike and "models/weapons/cstrike/c_pist_deagle.mdl" or "models/weapons/c_357.mdl"
SWEP.WorldModel = util.IsValidModel("models/weapons/w_pist_deagle.mdl") and "models/weapons/w_pist_deagle.mdl" or "models/weapons/w_357.mdl"

SWEP.IronSightsPos = hasCStrike and Vector(-6.36, -10, 2.02) or Vector(-4.68, -10, 0.65)
SWEP.IronSightsAng = hasCStrike and Vector(0, 0, 0) or Vector(0, -0.2, 0)
