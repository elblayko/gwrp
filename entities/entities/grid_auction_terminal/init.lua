--[[
    entities/entities/grid_auction_terminal/init.lua
    Server logic for Auction Terminal
    Author: Juicebox & Antigravity
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel(self.Model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Wake()
    end

    self:SetTerminalName("Central Exchange Terminal")
    self.NextUsePerPlayer = {}
end

function ENT:Use(activator, caller)
    local ply = IsValid(caller) and caller or activator
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[ply] or 0) > now then return end
    self.NextUsePerPlayer[ply] = now + 0.5

    ply:EmitSound("buttons/button14.wav", 65, 110)
    net.Start("GRID_Auction_OpenTerminal")
    net.Send(ply)
end

