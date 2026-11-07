--[[
    entities/entities/grid_deaddrop_locker/init.lua
    GridRP The Fixer's Alleyway Dead-Drop Locker - Server
    Author: GRID Core Team & Antigravity
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_c17/Lockers001a.mdl")
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

    if activator:GetOnboardingStage() == GRID.Onboarding.STAGE_ROOKIE then
        GRID.Onboarding.ClaimDeadDrop(activator, self)
    elseif activator:GetOnboardingStage() > GRID.Onboarding.STAGE_ROOKIE then
        GRID.Notify(activator, "You have already claimed your starter dead-drop package.", NOTIFY_GENERIC, 3)
    else
        GRID.Notify(activator, "The locker is locked tight. No drop is pending for you.", NOTIFY_ERROR, 3)
    end
end

