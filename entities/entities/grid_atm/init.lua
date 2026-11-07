--[[
    entities/entities/grid_atm/init.lua
    GridRP Street ATM & Syndicate Laundering Terminal - Server
    Author: GRID Core Team & Antigravity
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("GRID_ATM_Open")
util.AddNetworkString("GRID_ATM_Action")

function ENT:Initialize()
    self:SetModel("models/props_unique/atm01.mdl")
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

    -- Check if completing Onboarding Stage 2 -> 3
    if activator:GetOnboardingStage() == GRID.Onboarding.STAGE_STASH then
        GRID.Onboarding.CompleteInitiation(activator, self)
        return
    end

    -- Regular ATM interface
    net.Start("GRID_ATM_Open")
        net.WriteEntity(self)
        net.WriteUInt(activator:GetMoney(), 32)
        net.WriteUInt(activator:GetBank(), 32)
    net.Send(activator)
end

-- ATM Deposit / Withdraw Network Handler
net.Receive("GRID_ATM_Action", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end

    local atmEnt = net.ReadEntity()
    local isDeposit = net.ReadBool()
    local amount = net.ReadUInt(32)

    if not IsValid(atmEnt) or atmEnt:GetClass() ~= "grid_atm" then return end
    if ply:EyePos():DistToSqr(atmEnt:GetPos()) > (120 * 120) then return end
    if amount <= 0 then return end

    if isDeposit then
        if not ply:CanAfford(amount) then
            GRID.Notify(ply, "You do not carry that much cash!", NOTIFY_ERROR, 3)
            return
        end

        ply:AddMoney(-amount)
        ply:AddBank(amount)
        atmEnt:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 100)
        GRID.Notify(ply, string.format("Deposited $%s into personal bank account.", string.Comma(amount)), NOTIFY_GENERIC, 4)
    else
        if not ply:CanAffordBank(amount) then
            GRID.Notify(ply, "Your bank balance has insufficient funds!", NOTIFY_ERROR, 3)
            return
        end

        ply:AddBank(-amount)
        ply:AddMoney(amount)
        atmEnt:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 110)
        GRID.Notify(ply, string.format("Withdrew $%s from personal bank account.", string.Comma(amount)), NOTIFY_GENERIC, 4)
    end

    -- Re-sync
    net.Start("GRID_ATM_Open")
        net.WriteEntity(atmEnt)
        net.WriteUInt(ply:GetMoney(), 32)
        net.WriteUInt(ply:GetBank(), 32)
    net.Send(ply)
end)

