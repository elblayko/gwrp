--[[
    grid_resource_machine/init.lua - Server Entity Extraction Engine, Thermal Regulation & Venting
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
    self:SetEfficiency(GRID.Config.PrinterStandaloneEfficiency or 60)
    self:SetAssignedPort(0)
    self:SetIPAddress("")
    self:SetHasReadyItem(false)
    self:SetReadyItemID("")
    self:SetReadyItemName("")

    -- Thermal Regulation & Venting Datatables
    self:SetTemperature(20)
    self:SetVentActive(false)
    self:SetVentStartTime(0)
    self:SetVentDuration(1.25)
    self:SetVentSweetMin(0)
    self:SetVentSweetMax(0)
    self:SetValveJammedUntil(0)
    self:SetThermalSpikeUntil(0)
    self:SetIsTuned(false)
    self:SetHasUndervolt(false)

    self.ThermalTargetTemp = nil
    self.NextThermalTick = 0
    self.NextHeatTick = CurTime() + 12

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetMass(150)
    end

    self.CurrentItem = nil
    self:StartExtractionCycle()

    -- Continuous monitoring timer for extraction cycle and sitting items
    local timerName = "GRID_ResourceMachine_" .. self:EntIndex()
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

-- ========================================================
-- THERMAL SIMULATION & LINEAR DEGREE TRANSITIONS
-- ========================================================

function ENT:Think()
    local now = CurTime()

    -- Linear thermal transition (stepping up on fail, stepping down on vent success at 0.12s per degree)
    if self.ThermalTargetTemp then
        if now >= (self.NextThermalTick or 0) then
            local cur = self:GetTemperature()
            if cur < self.ThermalTargetTemp then
                -- Raising linearly (+1°C every 0.12s)
                local nextTemp = cur + 1
                self:SetTemperature(nextTemp)
                self.NextThermalTick = now + 0.12

                if nextTemp >= self.MaxTemp then
                    self.ThermalTargetTemp = nil
                    self:Explode()
                    return true
                end
            elseif cur > self.ThermalTargetTemp then
                -- Lowering linearly (-1°C every 0.12s)
                self:SetTemperature(cur - 1)
                self.NextThermalTick = now + 0.12

                if (self.NextCoolSound or 0) <= now then
                    self.NextCoolSound = now + 0.5
                    self:EmitSound("ambient/levels/canals/steam_hiss1.wav", 55, 120, 0.35)
                end
            else
                self.ThermalTargetTemp = nil
            end
        end
    end

    -- Check if active sweet-spot sweep is running
    if self:GetVentActive() then
        -- Track key release from initial [E] press
        if self.VentWaitingForRelease and IsValid(self.VentPlayer) then
            if not self.VentPlayer:KeyDown(IN_USE) then
                self.VentWaitingForRelease = false
            end
        end

        local duration = math.max(0.1, self:GetVentDuration())
        local progress = (now - self:GetVentStartTime()) / duration
        if progress >= 1.0 then
            -- Soft depressurization reset: no penalty, valve gently closes
            self:SetVentActive(false)
            self.VentWaitingForRelease = false
            self.VentPlayer = nil
            self:EmitSound("weapons/shotgun/shotgun_empty.wav", 55, 110, 0.4)
        end
    end

    self:NextThink(now + 0.05)
    return true
end

function ENT:ExtractionTick()
    local now = CurTime()

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

    -- Passive thermal rise during continuous synthesis operation
    if now >= (self.NextHeatTick or 0) then
        local interval = self:GetHasUndervolt() and 25 or 12
        if self:GetIsTuned() then interval = interval + 6 end
        self.NextHeatTick = now + interval

        local curT = self:GetTemperature()
        if curT < self.MaxTemp then
            self:SetTemperature(curT + 1)
            if self:GetTemperature() >= self.MaxTemp then
                self:Explode()
                return
            end
        end
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

    local matId = GRID.Crafting and GRID.Crafting.RollRandomResource and GRID.Crafting.RollRandomResource() or "crafting_ingot_zinc"
    local def = GRID.Crafting and GRID.Crafting.Materials and GRID.Crafting.Materials[matId]
    local itemName = def and def.name or matId

    local center = self:OBBCenter()
    local maxs = self:OBBMaxs()
    -- Calculate exact top surface of machine bounding box (resting flush on top)
    local topPos = self:LocalToWorld(Vector(center.x, center.y, maxs.z + 1.5))
    local topAng = Angle(0, self:GetAngles().y, 0)

    local matEnt = ents.Create("grid_crafting_material")
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

        -- Cycle Heat Surge (+4°C standard, +1°C undervolted, -25% tuned)
        local heatRise = self:GetHasUndervolt() and (GRID.Config.PrinterHeatRiseUndervolted or 1) or (GRID.Config.PrinterHeatRiseStandard or 4)
        if self:GetIsTuned() then
            heatRise = math.max(1, math.floor(heatRise * 0.75))
        end
        local newTemp = self:GetTemperature() + heatRise
        self:SetTemperature(newTemp)

        -- Sound cues & steam release
        self:EmitSound("ambient/machines/steam_release_2.wav", 75, 105)
        self:EmitSound("buttons/lever7.wav", 70, 100)

        local ed = EffectData()
        ed:SetOrigin(topPos)
        ed:SetNormal(self:GetUp())
        ed:SetScale(1.5)
        util.Effect("ElectricSpark", ed, true, true)

        if newTemp >= self.MaxTemp then
            self:Explode()
        end
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
-- MAINTENANCE, REPAIR & HARDWARE UPGRADES
-- ========================================================

function ENT:CoolAndRepair(tempReduction)
    tempReduction = tempReduction or 35
    local curTemp = self:GetTemperature()
    local newTemp = math.max(20, curTemp - tempReduction)
    self:SetTemperature(newTemp)
    self:SetVentActive(false)
    self.VentWaitingForRelease = false
    self.VentPlayer = nil
    self.ThermalTargetTemp = nil
    self:SetValveJammedUntil(0)
    self:EmitSound("ambient/levels/canals/steam_hiss2.wav", 70, 110)
end

function ENT:InstallUndervoltModule(moduleEnt)
    self:SetHasUndervolt(true)
    self:EmitSound("ambient/energy/zap1.wav", 70, 115)
end

function ENT:TunePrinter(ply)
    self:SetIsTuned(true)
    self:EmitSound("buttons/button9.wav", 70, 110)
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
        self:SetEfficiency(GRID.Config.PrinterStandaloneEfficiency or 60)
    end
end

-- ========================================================
-- DAMAGE, DESTRUCTION & EXPLOSION
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

function ENT:Explode()
    if self.Exploded then return end
    self.Exploded = true
    self:SetVentActive(false)
    self.ThermalTargetTemp = nil

    if self.HumSound then self.HumSound:Stop() end
    timer.Remove("GRID_ResourceMachine_" .. self:EntIndex())

    self:DisconnectFromSwitch()

    -- Drop sitting item
    if IsValid(self.CurrentItem) then
        constraint.RemoveAll(self.CurrentItem)
        self.CurrentItem.ParentMachine = nil
        local phys = self.CurrentItem:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
        self.CurrentItem = nil
    end

    local pos = self:GetPos()
    local effect = EffectData()
    effect:SetOrigin(pos)
    util.Effect("Explosion", effect)

    util.BlastDamage(self, self, pos, 250, 85)
    GRID.NotifyAll("A Resource Fabricator overheated and suffered catastrophic engine failure!", NOTIFY_ERROR)
    self:Remove()
end

function ENT:DestroyMachine()
    self:Explode()
end

-- ========================================================
-- PLAYER INTERACTION & VENTING MECHANICS
-- ========================================================

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[activator] or 0) > now then return end
    self.NextUsePerPlayer[activator] = now + 0.22

    local curTemp = self:GetTemperature()

    -- 1. If active sweet-spot sweep is running: THIS [E] PRESS IS THE TIMING ATTEMPT!
    if self:GetVentActive() then
        -- Debounce protection: ignore if held from sweep launch
        if (now - self:GetVentStartTime()) < 0.22 or self.VentWaitingForRelease then
            if not activator:KeyDown(IN_USE) then
                self.VentWaitingForRelease = false
            end
            return
        end

        local duration = math.max(0.1, self:GetVentDuration())
        local progress = math.Clamp((now - self:GetVentStartTime()) / duration, 0, 1)
        local sMin = self:GetVentSweetMin()
        local sMax = self:GetVentSweetMax()

        if progress >= sMin and progress <= sMax then
            -- SUCCESS: Clean exhaust vent (linear dissipation down towards 20°C)
            local coolTarget = math.max(20, curTemp - 15)
            self.ThermalTargetTemp = coolTarget
            self.NextThermalTick = now
            self:SetVentActive(false)
            self.VentWaitingForRelease = false
            self.VentPlayer = nil

            self.NextVentAllowed = now + 1.5

            -- Satisfying steam exhaust release
            self:EmitSound("ambient/machines/steam_release_2.wav", 75, 105, 0.85)
            self:EmitSound("ambient/levels/canals/steam_hiss2.wav", 70, 115, 0.7)

            local ed = EffectData()
            ed:SetOrigin(self:GetPos() + Vector(0, 0, 18))
            ed:SetNormal(Vector(0, 0, 1))
            ed:SetScale(0.9)
            util.Effect("WheelDust", ed)

            GRID.Notify(activator, "Pressure vented! Engine core dissipating heat.", NOTIFY_GENERIC)
            return
        else
            -- FAIL / MISS: Over-pressurization + valve jam!
            self:SetVentActive(false)
            self.VentWaitingForRelease = false
            self.VentPlayer = nil
            self:SetValveJammedUntil(now + 3.5)

            -- Linearly raise temperature on fail (+4°C surge)
            local failHeat = 4
            self.ThermalTargetTemp = math.min(self.MaxTemp, curTemp + failHeat)
            self.NextThermalTick = now

            -- Short-circuit zap
            self:EmitSound("ambient/levels/labs/electric_explosion1.wav", 85, 110, 0.95)
            self:EmitSound("ambient/energy/zap1.wav", 80, 115, 0.85)

            local ed = EffectData()
            ed:SetOrigin(self:GetPos() + Vector(0, 0, 20))
            ed:SetNormal(Vector(0, 0, 1))
            ed:SetMagnitude(2)
            ed:SetScale(1.5)
            util.Effect("Sparks", ed)

            GRID.Notify(activator, "Valve over-pressurized! Relief valve jammed for 3.5s.", NOTIFY_ERROR)
            return
        end
    end

    -- 2. If holding SPRINT (Shift), or if temp is at ambient (20°C): open Crafting Workbench!
    if activator:KeyDown(IN_SPEED) or curTemp <= 20 then
        net.Start("GRID_OpenCraftingUI")
            net.WriteEntity(self)
            net.WriteBool(self:GetHasReadyItem())
            net.WriteString(self:GetReadyItemID())
            net.WriteString(self:GetReadyItemName())
        net.Send(activator)
        self:EmitSound("buttons/button14.wav", 60, 105)
        return
    end

    -- 3. If hot (curTemp > 20°C): tap [E] triggers the Vent Pressure gauge!
    if curTemp > 20 then
        -- Check if valve is jammed
        if self:GetValveJammedUntil() > now then
            local remain = math.ceil(self:GetValveJammedUntil() - now)
            GRID.Notify(activator, string.format("Relief valve jammed for %ds! Stand clear.", remain), NOTIFY_ERROR)
            self:EmitSound("weapons/pistol/pistol_empty.wav", 65, 110, 0.6)
            return
        end

        -- Check cooldown between vents
        if (self.NextVentAllowed or 0) > now then
            self:EmitSound("physics/metal/metal_box_impact_soft1.wav", 55, 120, 0.4)
            return
        end

        -- Start the active sweet-spot sweep
        local duration = 1.25
        local sweetCenter = math.Rand(0.40, 0.72)
        local sweetWidth = 0.18

        self:SetVentDuration(duration)
        self:SetVentStartTime(now)
        self:SetVentSweetMin(sweetCenter - (sweetWidth / 2))
        self:SetVentSweetMax(sweetCenter + (sweetWidth / 2))
        self:SetVentActive(true)

        self.VentWaitingForRelease = true
        self.VentPlayer = activator

        -- Valve latch click
        self:EmitSound("weapons/slam/mine_mode.wav", 60, 115, 0.6)
    end
end

function ENT:OnRemove()
    self:SetVentActive(false)
    self.ThermalTargetTemp = nil
    timer.Remove("GRID_ResourceMachine_" .. self:EntIndex())
    self:DisconnectFromSwitch()

    if IsValid(self.CurrentItem) then
        constraint.RemoveAll(self.CurrentItem)
        self.CurrentItem.ParentMachine = nil
    end
end
