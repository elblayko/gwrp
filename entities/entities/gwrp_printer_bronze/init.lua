--[[
    entities/entities/gwrp_printer_bronze/init.lua
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_c17/consolebox01a.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetColor(self.PrinterColor)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    self:SetStoredCash(0)
    self:SetTemperature(20)
    self:SetEfficiency(GWRP.Config.PrinterStandaloneEfficiency or 60)
    self:SetNetworkedCount(1)
    self:SetAssignedPort(0)
    self:SetIsTuned(false)
    self:SetHasUndervolt(false)
    self:SetHasOverclock(false)
    self:SetIPAddress("")
    self:SetVentActive(false)
    self:SetVentStartTime(0)
    self:SetVentDuration(1.25)
    self:SetVentSweetMin(0)
    self:SetVentSweetMax(0)
    self:SetValveJammedUntil(0)
    self:SetLowEmissionUntil(0)
    self:SetThermalSpikeUntil(0)

    -- Humming sound loop
    self.HumSound = CreateSound(self, "ambient/machines/combine_terminal_loop1.wav")
    if self.HumSound then self.HumSound:Play() end

    -- Wiremod Support
    if WireLib then
        WireLib.CreateOutputs(self, {
            "StoredCash",
            "Temperature",
            "Efficiency",
            "YieldPerTick",
            "IsNetworked",
            "Overheating",
            "HasUndervolt",
            "IsTuned",
            "LinkedSwitch [ENTITY]"
        })
        self:UpdateWireOutputs()
    end

    -- Print cycle timer
    timer.Create("GWRP_PrintTick_" .. self:EntIndex(), self.PrintInterval, 0, function()
        if not IsValid(self) then return end
        self:PrintCycle()
    end)
end

function ENT:UpdateWireOutputs()
    if not WireLib then return end
    local eff = self:GetEfficiency()
    if not eff or eff <= 0 then eff = 60 end
    local yield = math.max(1, math.Round(self.PrintAmount * (eff / 100)))
    local temp = self:GetTemperature()
    local isNet = IsValid(self:GetConnectedSwitch()) and 1 or 0

    WireLib.TriggerOutput(self, "StoredCash", self:GetStoredCash())
    WireLib.TriggerOutput(self, "Temperature", temp)
    WireLib.TriggerOutput(self, "Efficiency", eff)
    WireLib.TriggerOutput(self, "YieldPerTick", yield)
    WireLib.TriggerOutput(self, "IsNetworked", isNet)
    WireLib.TriggerOutput(self, "Overheating", temp >= 75 and 1 or 0)
    WireLib.TriggerOutput(self, "HasUndervolt", self:GetHasUndervolt() and 1 or 0)
    WireLib.TriggerOutput(self, "IsTuned", self:GetIsTuned() and 1 or 0)
    WireLib.TriggerOutput(self, "LinkedSwitch", self:GetConnectedSwitch())

    local portStr = isNet == 1 and ("Port " .. self:GetAssignedPort()) or "Standalone"
    local ipStr = (self.GetIPAddress and self:GetIPAddress() ~= "") and (" | IP: " .. self:GetIPAddress()) or ""
    local uvStr = self:GetHasUndervolt() and " (UV)" or ""
    local tuneStr = self:GetIsTuned() and " [TUNED]" or ""
    WireLib.SetOverlayText(self, string.format("[%s]%s%s\nStatus: %s%s (%d%% Eff)\nStored: $%d | Temp: %dC", self.PrintName, uvStr, tuneStr, portStr, ipStr, eff, self:GetStoredCash(), temp))
end

function ENT:TunePrinter(ply)
    if self:GetIsTuned() then return false end
    self:SetIsTuned(true)
    self:EmitSound("ambient/energy/zap2.wav", 75, 120)
    self:EmitSound("buttons/button9.wav", 75, 110)
    self:UpdateWireOutputs()
    return true
end

function ENT:InstallUndervoltModule(moduleEnt)
    self:SetHasUndervolt(true)
    self:UpdateWireOutputs()
end

function ENT:InstallOverclockModule(moduleEnt)
    self:SetHasOverclock(true)
    self:UpdateWireOutputs()
end

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
    self:UpdateWireOutputs()
end

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
                self:UpdateWireOutputs()

                local sw = self:GetConnectedSwitch()
                if IsValid(sw) and sw.UpdateWireOutputs then
                    sw:UpdateWireOutputs()
                end

                if nextTemp >= self.MaxTemp then
                    self.ThermalTargetTemp = nil
                    self:Explode()
                    return true
                end
            elseif cur > self.ThermalTargetTemp then
                -- Lowering linearly (-1°C every 0.12s)
                self:SetTemperature(cur - 1)
                self.NextThermalTick = now + 0.12
                self:UpdateWireOutputs()

                local sw = self:GetConnectedSwitch()
                if IsValid(sw) and sw.UpdateWireOutputs then
                    sw:UpdateWireOutputs()
                end

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

function ENT:DisconnectFromSwitch()
    local sw = self:GetConnectedSwitch()
    if IsValid(sw) and (sw.DisconnectDevice or sw.DisconnectPrinter) then
        if sw.DisconnectDevice then
            sw:DisconnectDevice(self)
        else
            sw:DisconnectPrinter(self)
        end
    else
        self:SetConnectedSwitch(NULL)
        self:SetAssignedPort(0)
        self:SetIPAddress("")
        self:SetNetworkedCount(1)
        self:SetEfficiency(GWRP.Config.PrinterStandaloneEfficiency or 60)
        self:UpdateWireOutputs()
    end
end

function ENT:PrintCycle()
    local eff = self:GetEfficiency()
    if not eff or eff <= 0 then eff = 60 end
    local baseYield = math.max(1, math.Round(self.PrintAmount * (eff / 100)))
    local yield = self:GetHasOverclock() and math.Round(baseYield * 1.5) or baseYield
    if self:GetIsTuned() then
        yield = math.Round(yield * 1.2) -- Cyber-Tuned: +20% cash yield
    end

    local heatRise = self:GetHasUndervolt() and (GWRP.Config.PrinterHeatRiseUndervolted or 1) or (GWRP.Config.PrinterHeatRiseStandard or 4)
    if self:GetHasOverclock() then
        heatRise = heatRise + 3
    end
    if self:GetIsTuned() then
        heatRise = math.max(1, math.floor(heatRise * 0.75)) -- Cyber-Tuned: -25% heat generation
    end

    self:SetStoredCash(self:GetStoredCash() + yield)
    self:SetTemperature(self:GetTemperature() + heatRise)
    self:EmitSound("ambient/levels/labs/coinslot1.wav", 60, 100, 0.4)

    self:UpdateWireOutputs()

    -- Inform connected switch if any
    local sw = self:GetConnectedSwitch()
    if IsValid(sw) and sw.UpdateWireOutputs then
        sw:UpdateWireOutputs()
    end

    if self:GetTemperature() >= self.MaxTemp then
        self:Explode()
    end
end

function ENT:Explode()
    if self.Exploded then return end
    self.Exploded = true
    self:SetVentActive(false)
    self.ThermalTargetTemp = nil

    if self.HumSound then self.HumSound:Stop() end
    timer.Remove("GWRP_PrintTick_" .. self:EntIndex())

    self:DisconnectFromSwitch()

    local pos = self:GetPos()
    local effect = EffectData()
    effect:SetOrigin(pos)
    util.Effect("Explosion", effect)

    util.BlastDamage(self, self, pos, 250, 85)
    GWRP.NotifyAll("A money printer overheated and exploded!", NOTIFY_ERROR)
    self:Remove()
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[activator] or 0) > now then return end
    self.NextUsePerPlayer[activator] = now + 0.25

    local reqLvl = self.RequiredLevel or (GWRP.ShopItems and GWRP.ShopItems[self:GetClass()] and GWRP.ShopItems[self:GetClass()].level) or 1
    if not activator:IsPolice() and activator:GetLevel() < reqLvl then
        GWRP.Notify(activator, string.format("You must be Level %d to operate this printer!", reqLvl), NOTIFY_ERROR)
        return
    end

    if activator:IsPolice() then
        -- Police Confiscation (Patrol Officers earn +50% Detective Bounty)
        local isPatrol = (activator:GetJob() == "police_officer")
        local baseBounty = self.BountyAmount or GWRP.Config.PoliceBountyPerPrinter or 125
        local bounty = isPatrol and math.floor(baseBounty * 1.5) or baseBounty
        activator:AddMoney(bounty)
        local msg = isPatrol and string.format("Detective Perk: Printer seized for +$%d (+50%% Patrol Bounty)!", bounty) or string.format("Printer confiscated for +$%d bounty!", bounty)
        GWRP.Notify(activator, msg, NOTIFY_GENERIC)
        activator:EmitSound("ambient/levels/labs/coinslot1.wav")
        if self.HumSound then self.HumSound:Stop() end
        timer.Remove("GWRP_PrintTick_" .. self:EntIndex())
        self:SetVentActive(false)
        self:DisconnectFromSwitch()
        self:Remove()
    else
        -- Collect Cash
        local cash = self:GetStoredCash()
        if cash > 0 then
            activator:AddMoney(cash)
            if activator.AddXP then
                activator:AddXP((GWRP.Config and GWRP.Config.Level and GWRP.Config.Level.XP_PrinterCollect) or 20, "Printer Revenue")
            end
            GWRP.Notify(activator, "Collected $" .. cash .. " from printer!", NOTIFY_GENERIC)
            activator:EmitSound("ambient/levels/labs/coinslot1.wav")
            self:SetStoredCash(0)
            self:UpdateWireOutputs()
        end

        local curTemp = self:GetTemperature()
        local now = CurTime()

        if curTemp > 20 then
            -- Check if valve is jammed
            if self:GetValveJammedUntil() > now then
                self:EmitSound("weapons/pistol/pistol_empty.wav", 65, 110, 0.6)
                return
            end

            -- If sweet spot gauge is running: this [E] press is the TIMING ATTEMPT!
            if self:GetVentActive() then
                -- DEBOUNCE & KEY-RELEASE PROTECTION:
                -- If the player is still holding down [E] from the sweep launch (or within 0.25s of launch),
                -- ignore the tick event so holding [E] for >0.1s never causes an instant blowout!
                if (now - self:GetVentStartTime()) < 0.25 or self.VentWaitingForRelease then
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
                    -- SUCCESS: Clean exhaust vent (Linear step-down towards target: e.g. 30, 29, 28, ..., 20 at 0.12s per degree)
                    local coolTarget = math.max(20, curTemp - 15)
                    self.ThermalTargetTemp = coolTarget
                    self.NextThermalTick = now
                    self:SetVentActive(false)
                    self.VentWaitingForRelease = false
                    self.VentPlayer = nil

                    -- Stealth Dampener Buff for 10 seconds (-30% scanner emission)
                    self:SetLowEmissionUntil(now + 10.0)

                    -- Valve reset cooldown (1.5s)
                    self.NextVentAllowed = now + 1.5

                    -- Satisfying steam exhaust release
                    self:EmitSound("ambient/machines/steam_release_2.wav", 75, 105, 0.85)
                    self:EmitSound("ambient/levels/canals/steam_hiss2.wav", 70, 115, 0.7)

                    local ed = EffectData()
                    ed:SetOrigin(self:GetPos() + Vector(0, 0, 14))
                    ed:SetNormal(Vector(0, 0, 1))
                    ed:SetScale(0.8)
                    util.Effect("WheelDust", ed)

                    self:UpdateWireOutputs()
                else
                    -- FAIL / SPAM: Electrical overload + Police radar flare + Valve Jam!
                    self:SetVentActive(false)
                    self.VentWaitingForRelease = false
                    self.VentPlayer = nil
                    self:SetValveJammedUntil(now + 3.5)
                    self:SetThermalSpikeUntil(now + 8.0)

                    -- Linearly raise temperature on fail (+1°C every 0.12s up to +4°C surge)
                    local failHeat = 4
                    self.ThermalTargetTemp = math.min(self.MaxTemp, curTemp + failHeat)
                    self.NextThermalTick = now

                    -- Electrical overload short-circuit zap audible through walls (~1000 units)
                    self:EmitSound("ambient/levels/labs/electric_explosion1.wav", 85, 110, 0.95)
                    self:EmitSound("ambient/energy/zap1.wav", 80, 115, 0.85)

                    -- Electrical spark burst
                    local ed = EffectData()
                    ed:SetOrigin(self:GetPos() + Vector(0, 0, 15))
                    ed:SetNormal(Vector(0, 0, 1))
                    ed:SetMagnitude(2)
                    ed:SetScale(1.5)
                    util.Effect("Sparks", ed)

                    self:UpdateWireOutputs()
                end
            else
                -- Not active: Check if in valve reset cooldown
                if (self.NextVentAllowed or 0) > now then
                    self:EmitSound("physics/metal/metal_box_impact_soft1.wav", 55, 120, 0.4)
                    return
                end

                -- Start the active sweet-spot sweep
                local duration = 1.25 -- 1.25 seconds sweep
                local sweetCenter = math.Rand(0.40, 0.72)
                local sweetWidth = 0.18

                self:SetVentDuration(duration)
                self:SetVentStartTime(now)
                self:SetVentSweetMin(sweetCenter - (sweetWidth / 2))
                self:SetVentSweetMax(sweetCenter + (sweetWidth / 2))
                self:SetVentActive(true)

                -- Mark key as needing release before attempt can be evaluated
                self.VentWaitingForRelease = true
                self.VentPlayer = activator

                -- Valve latch click sound to signal gauge start
                self:EmitSound("weapons/slam/mine_mode.wav", 60, 115, 0.6)
            end
        elseif cash <= 0 and curTemp <= 20 then
            if (self.NextEmptyClick or 0) <= now then
                self.NextEmptyClick = now + 0.5
                self:EmitSound("physics/metal/metal_box_impact_soft1.wav", 55, 100, 0.5)
            end
        end
    end
end

function ENT:OnRemove()
    self:SetVentActive(false)
    self.ThermalTargetTemp = nil
    if self.HumSound then self.HumSound:Stop() end
    timer.Remove("GWRP_PrintTick_" .. self:EntIndex())

    self:DisconnectFromSwitch()

    if WireLib then
        WireLib.Remove(self)
    end
end
