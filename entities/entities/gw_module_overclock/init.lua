--[[
    entities/entities/gw_module_overclock/init.lua
    GWRP Overclock Hardware Module Server Logic
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/items/car_battery01.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    self:SetTrigger(true)
end

local function IsPrinter(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    if class == "gw_printer_bronze" or class == "gw_printer_silver" or class == "gw_printer_diamond" or ent.PrintAmount ~= nil then
        return true
    end
    return false
end

function ENT:StartTouch(ent)
    if not IsPrinter(ent) then return end
    if self.Consumed then return end

    if ent.GetHasOverclock and ent:GetHasOverclock() then return end

    self:InstallIntoPrinter(ent)
end

function ENT:InstallIntoPrinter(printer)
    if self.Consumed then return end
    self.Consumed = true

    if printer.InstallOverclockModule then
        printer:InstallOverclockModule(self)
    elseif printer.SetHasOverclock then
        printer:SetHasOverclock(true)
    end

    self:EmitSound("ambient/energy/zap1.wav", 75, 110)

    -- Particle effect / spark
    local spark = EffectData()
    spark:SetOrigin(self:GetPos())
    spark:SetNormal(Vector(0, 0, 1))
    spark:SetMagnitude(2)
    spark:SetScale(1)
    util.Effect("Sparks", spark)

    self:Remove()
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[activator] or 0) > now then return end
    self.NextUsePerPlayer[activator] = now + 0.4

    local trace = activator:GetEyeTrace()
    if IsValid(trace.Entity) and IsPrinter(trace.Entity) and trace.HitPos:DistToSqr(activator:EyePos()) < (120 * 120) then
        if trace.Entity.GetHasOverclock and not trace.Entity:GetHasOverclock() then
            self:InstallIntoPrinter(trace.Entity)
        end
    end
end
