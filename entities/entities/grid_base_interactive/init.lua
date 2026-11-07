--[[
    entities/entities/grid_base_interactive/init.lua
    GridRP Unified Interactive Base Entity - Server Authority
    Author: GRID Core Team & Antigravity
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel(self.Model or "models/props_c17/consolebox01a.mdl")
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

--- Validates if a player is authorized and in range to interact
-- @param ply Player
-- @return boolean, string
function ENT:CanPlayerUse(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then
        return false, "Invalid player"
    end

    local cfg = self.InteractionConfig or {}
    local maxDist = cfg.MaxUseDistance or 120
    if ply:EyePos():DistToSqr(self:GetPos()) > (maxDist * maxDist) then
        return false, "Too far away"
    end

    if GRID and GRID.CheckRateLimit and not GRID.CheckRateLimit(ply, "ent_interact_" .. self:EntIndex(), 4) then
        return false, "Rate limited"
    end

    if cfg.CanUse and isfunction(cfg.CanUse) then
        local allowed, reason = cfg.CanUse(self, ply)
        if allowed == false then
            return false, reason or "Interaction blocked"
        end
    end

    return true
end

--- Server use dispatcher
function ENT:Use(activator, caller, useType, value)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local canUse, reason = self:CanPlayerUse(activator)
    if not canUse then
        if reason and reason ~= "Too far away" and reason ~= "Rate limited" and GRID and GRID.Notify then
            GRID.Notify(activator, reason, NOTIFY_ERROR, 3)
        end
        return
    end

    -- Check secondary modifier (Sprint / Shift or Duck / Ctrl)
    local isSecondary = activator:KeyDown(IN_SPEED) or activator:KeyDown(IN_DUCK)

    if isSecondary and self.OnPlayerUseSecondary then
        self:OnPlayerUseSecondary(activator)
        return
    end

    if self.OnPlayerUse then
        self:OnPlayerUse(activator)
        return
    end
end

function ENT:OnPlayerUse(ply)
    -- Virtual hook: Override in derived classes
end

function ENT:OnPlayerUseSecondary(ply)
    -- Virtual hook: Override in derived classes
end

