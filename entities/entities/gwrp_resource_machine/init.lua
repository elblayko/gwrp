--[[
    gwrp_resource_machine/init.lua - Server Entity Extraction Engine & Networking
    Author: Toxic & Antigravity
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_c17/trappropeller_engine.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    self:SetMaxMachineHealth(500)
    self:SetMachineHealth(500)
    self:SetEfficiency(GWRP.Config.PrinterStandaloneEfficiency or 60)
    self:SetAssignedPort(0)
    self:SetIPAddress("")
    self:SetHasReadyItem(false)
    self:SetReadyItemID("")
    self:SetReadyItemName("")

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetMass(150)
    end

    self.CurrentItem = nil
    self:StartExtractionCycle()

    -- Continuous monitoring timer for extraction cycle and sitting items
    local timerName = "GWRP_ResourceMachine_" .. self:EntIndex()
    timer.Create(timerName, 0.5, 0, function()
        if not IsValid(self) then
            timer.Remove(timerName)
            return
        end
        self:ExtractionTick()
    end)
end

function ENT:GetCycleDurationForEfficiency(eff)
    eff = math.Clamp(eff or 60, 40, 120)
    local baseSec = 90 -- 90s standalone at 60% eff -> ~54s at 100% eff
    return math.max(30, math.floor(baseSec * (60 / eff)))
end

function ENT:StartExtractionCycle()
    if self:GetHasReadyItem() or IsValid(self.CurrentItem) then return end

    local dur = self:GetCycleDurationForEfficiency(self:GetEfficiency())
    self:SetCycleStartTime(CurTime())
    self:SetCycleDuration(dur)
end

function ENT:ExtractionTick()
    -- Check if ready item is still present
    if self:GetHasReadyItem() then
        if not IsValid(self.CurrentItem) then
            -- Item was picked up or destroyed; resume extraction
            self:SetHasReadyItem(false)
            self:SetReadyItemID("")
            self:SetReadyItemName("")
            self:StartExtractionCycle()
        end
        return
    end

    -- Timer evaluation
    local start = self:GetCycleStartTime()
    local dur = self:GetCycleDuration()
    if dur <= 0 then dur = self:GetCycleDurationForEfficiency(self:GetEfficiency()) end

    if CurTime() >= (start + dur) then
        self:FinishExtraction()
    end
end

function ENT:FinishExtraction()
    if self:GetHasReadyItem() or IsValid(self.CurrentItem) then return end

    local matId = GWRP.Crafting and GWRP.Crafting.RollRandomResource and GWRP.Crafting.RollRandomResource() or "crafting_ingot_zinc"
    local def = GWRP.Crafting and GWRP.Crafting.Materials and GWRP.Crafting.Materials[matId]
    local itemName = def and def.name or matId

    local center = self:OBBCenter()
    local maxs = self:OBBMaxs()
    -- Calculate exact top surface of machine bounding box (resting right on top)
    local topPos = self:LocalToWorld(Vector(center.x, center.y, maxs.z + 1.5))
    local topAng = Angle(0, self:GetAngles().y, 0)

    local matEnt = ents.Create("gwrp_crafting_material")
    if IsValid(matEnt) then
        matEnt:SetPos(topPos)
        matEnt:SetAngles(topAng)
        matEnt:SetMaterialID(matId)
        matEnt:SetAmount(1)
        matEnt:Spawn()
        matEnt:Activate()

        -- Weld to machine top so it sits firmly during motion
        constraint.Weld(self, matEnt, 0, 0, 0, true, false)

        matEnt.ParentMachine = self
        self.CurrentItem = matEnt

        self:SetHasReadyItem(true)
        self:SetReadyItemID(matId)
        self:SetReadyItemName(itemName)

        -- Sound cues & steam release
        self:EmitSound("ambient/machines/steam_release_2.wav", 75, 105)
        self:EmitSound("buttons/lever7.wav", 70, 100)

        local ed = EffectData()
        ed:SetOrigin(topPos)
        ed:SetNormal(self:GetUp())
        ed:SetScale(1.5)
        util.Effect("ElectricSpark", ed, true, true)
    end
end

function ENT:OnMaterialTaken(matEnt)
    if self.CurrentItem == matEnt then
        self.CurrentItem = nil
    end
    self:SetHasReadyItem(false)
    self:SetReadyItemID("")
    self:SetReadyItemName("")
    self:StartExtractionCycle()
end

-- ========================================================
-- NETWORKING SWITCH INTEGRATION
-- ========================================================

function ENT:SetEfficiency(eff)
    eff = math.Clamp(tonumber(eff) or 60, 40, 120)
    local oldEff = self:GetEfficiency()
    self:NetworkVarSetter("Efficiency", eff)

    if oldEff ~= eff and not self:GetHasReadyItem() then
        -- Recalculate remaining cycle time proportionally
        local now = CurTime()
        local elapsed = now - self:GetCycleStartTime()
        local oldDur = self:GetCycleDuration()
        local progress = oldDur > 0 and math.Clamp(elapsed / oldDur, 0, 0.99) or 0

        local newDur = self:GetCycleDurationForEfficiency(eff)
        self:SetCycleDuration(newDur)
        self:SetCycleStartTime(now - (progress * newDur))
    end
end

function ENT:DisconnectFromSwitch()
    local sw = self:GetConnectedSwitch()
    if IsValid(sw) and sw.DisconnectDevice then
        sw:DisconnectDevice(self)
    else
        self:SetConnectedSwitch(NULL)
        self:SetIPAddress("")
        self:SetAssignedPort(0)
        self:SetEfficiency(GWRP.Config.PrinterStandaloneEfficiency or 60)
    end
end

-- ========================================================
-- DAMAGE, DESTRUCTION & REPAIR
-- ========================================================

function ENT:OnTakeDamage(dmginfo)
    self:TakePhysicsDamage(dmginfo)

    local damage = dmginfo:GetDamage()
    local curHP = self:GetMachineHealth()
    local newHP = math.max(0, curHP - damage)
    self:SetMachineHealth(newHP)

    -- Spark on bullet hit
    local ed = EffectData()
    ed:SetOrigin(dmginfo:GetDamagePosition())
    ed:SetNormal(dmginfo:GetDamageForce():GetNormalized())
    util.Effect("MetalSpark", ed)

    if newHP <= 0 then
        self:DestroyMachine()
    end
end

function ENT:DestroyMachine()
    -- Free sitting item if present
    if IsValid(self.CurrentItem) then
        constraint.RemoveAll(self.CurrentItem)
        self.CurrentItem.ParentMachine = nil
        local phys = self.CurrentItem:GetPhysicsObject()
        if IsValid(phys) then
            phys:Wake()
            phys:ApplyForceCenter(Vector(0, 0, 50) + VectorRand() * 40)
        end
        self.CurrentItem = nil
    end

    self:DisconnectFromSwitch()

    -- Visual explosion
    local ed = EffectData()
    ed:SetOrigin(self:GetPos() + Vector(0, 0, 25))
    ed:SetScale(1.8)
    util.Effect("Explosion", ed)
    self:EmitSound("ambient/explosions/explode_4.wav", 80, 100)

    self:Remove()
end

-- ========================================================
-- PLAYER INTERACTION
-- ========================================================

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end

    -- Open crafting menu on client
    net.Start("GWRP_OpenCraftingUI")
        net.WriteEntity(self)
        net.WriteBool(self:GetHasReadyItem())
        net.WriteString(self:GetReadyItemID())
        net.WriteString(self:GetReadyItemName())
    net.Send(activator)

    self:EmitSound("buttons/button14.wav", 60, 105)
end

function ENT:OnRemove()
    timer.Remove("GWRP_ResourceMachine_" .. self:EntIndex())
    self:DisconnectFromSwitch()

    if IsValid(self.CurrentItem) then
        constraint.RemoveAll(self.CurrentItem)
        self.CurrentItem.ParentMachine = nil
    end
end
