--[[
    entities/entities/grid_cash_stack/init.lua
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = util.IsValidModel("models/props/cs_assault/money.mdl") and "models/props/cs_assault/money.mdl" or "models/props_lab/box01a.mdl"
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetAmount() <= 0 then
        self:SetAmount(10000)
    end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetMass(5)
    end
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if self.Collected then return end

    local amount = self:GetAmount()
    if amount <= 0 then
        self:Remove()
        return
    end

    self.Collected = true
    activator:AddMoney(amount)
    GRID.Notify(activator, "Picked up $" .. string.Comma(amount) .. "!", NOTIFY_GENERIC)
    activator:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 120)

    self:Remove()
end
