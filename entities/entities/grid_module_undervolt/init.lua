--[[
    entities/entities/grid_module_undervolt/init.lua
    GridRP Undervolt Hardware Module Server Logic
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/items/battery.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    -- Enable physics touch collision detection
    self:SetTrigger(true)
end

local function IsPrinter(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    if class == "grid_printer_bronze" or class == "grid_printer_silver" or class == "grid_printer_diamond" or ent.PrintAmount ~= nil then
        return true
    end
    return false
end

function ENT:StartTouch(ent)
    if not IsPrinter(ent) then return end
    if self.Consumed then return end

    if ent.GetHasUndervolt and ent:GetHasUndervolt() then return end

    self:InstallIntoPrinter(ent)
end

function ENT:InstallIntoPrinter(printer)
    if self.Consumed then return end
    self.Consumed = true

    if printer.InstallUndervoltModule then
        printer:InstallUndervoltModule(self)
    else
        printer:SetHasUndervolt(true)
        if printer.UpdateWireOutputs then
            printer:UpdateWireOutputs()
        end
    end

    -- Visual & sound effects
    local effect = EffectData()
    effect:SetOrigin(self:GetPos())
    util.Effect("cball_bounce", effect)

    printer:EmitSound("weapons/smg1/switch_burst.wav", 75, 105)
    printer:EmitSound("items/battery_pickup.wav", 75, 100)

    local owner = self:GetOwner()
    if IsValid(owner) and owner:IsPlayer() then
        GRID.Notify(owner, string.format("Undervolt Module installed into %s! Heat output reduced by 75%%.", printer.PrintName or "Printer"), NOTIFY_GENERIC)
    else
        GRID.NotifyAll(string.format("An Undervolt Module was installed into a %s!", printer.PrintName or "Money Printer"), NOTIFY_GENERIC)
    end

    self:Remove()
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[activator] or 0) > now then return end
    self.NextUsePerPlayer[activator] = now + 0.4

    if activator:IsPolice() then
        activator:AddMoney(GRID.Config.PoliceBountyPerModule or 150)
        GRID.Notify(activator, "Contraband hardware module confiscated for +$" .. (GRID.Config.PoliceBountyPerModule or 150) .. " bounty!", NOTIFY_GENERIC)
        activator:EmitSound("ambient/levels/labs/coinslot1.wav")
        self:Remove()
        return
    end

    -- Find nearest money printer within 120 units
    local nearestPrinter = nil
    local nearestDist = 120 * 120
    local myPos = self:GetPos()

    for _, ent in ipairs(ents.FindInSphere(myPos, 120)) do
        if IsPrinter(ent) and not ent:GetHasUndervolt() then
            local dist = myPos:DistToSqr(ent:GetPos())
            if dist < nearestDist then
                nearestDist = dist
                nearestPrinter = ent
            end
        end
    end

    if IsValid(nearestPrinter) then
        self:SetOwner(activator)
        self:InstallIntoPrinter(nearestPrinter)
    else
        GRID.Notify(activator, "Drop or carry this module onto a Money Printer to install it.", NOTIFY_HINT)
        self:EmitSound("buttons/button14.wav", 60, 100)
    end
end
