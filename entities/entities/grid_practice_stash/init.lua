--[[
    entities/entities/grid_practice_stash/init.lua
    GridRP Practice Stash Crate - Server
    Author: GRID Core Team & Antigravity
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_junk/wood_crate001a.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:EnableMotion(false)
    end
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    if activator:GetOnboardingStage() == GRID.Onboarding.STAGE_DEAD_DROP then
        GRID.Notify(activator, "This crate has a heavy padlock. Equip your Tactical Lockpick and pick it!", NOTIFY_HINT, 4)
    else
        GRID.Notify(activator, "A reinforced practice training crate used for syndicate initiation.", NOTIFY_GENERIC, 3)
    end
end

