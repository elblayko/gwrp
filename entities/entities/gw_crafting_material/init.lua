--[[
    gw_crafting_material/init.lua - Server Entity Logic for In-World Materials
    Author: Toxic & Antigravity
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    local matId = self:GetMaterialID()
    if not matId or matId == "" then
        matId = "crafting_ingot_zinc"
        self:SetMaterialID(matId)
    end

    if self:GetAmount() <= 0 then
        self:SetAmount(1)
    end

    self:ApplyMaterialProperties(matId)

    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end
end

function ENT:ApplyMaterialProperties(matId)
    local def = GW.Crafting and GW.Crafting.Materials and GW.Crafting.Materials[matId]
    local mdl = "models/gangwars/crafting/ingot.mdl"

    if matId == "crafting_carbon_rod" then
        mdl = "models/gangwars/crafting/carbrod.mdl"
    elseif string.StartWith(matId, "blueprint_") then
        mdl = "models/gangwars/crafting/blup.mdl"
    elseif def and def.model then
        mdl = def.model
    end

    self:SetModel(mdl)

    if def and def.hasTint and def.color then
        self:SetColor(def.color)
        self:SetTintColor(Vector(def.color.r / 255, def.color.g / 255, def.color.b / 255))
    else
        self:SetColor(Color(255, 255, 255))
        self:SetTintColor(Vector(1, 1, 1))
    end
end

function ENT:SetMaterial(matId, amount)
    self:SetMaterialID(matId)
    self:SetAmount(amount or 1)
    self:ApplyMaterialProperties(matId)
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end

    if GW.Crafting and GW.Crafting.PickupMaterial then
        GW.Crafting.PickupMaterial(activator, self)
    end
end
