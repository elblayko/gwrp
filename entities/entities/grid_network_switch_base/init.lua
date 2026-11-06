--[[
    entities/entities/grid_network_switch_base/init.lua
    GridRP Layer-3 Modular Network Switch Abstract Base Server Logic
    Author: Toxic
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local function GetPrinterTier(ent)
    if not IsValid(ent) then return 0 end
    if ent.PrinterTier then return ent.PrinterTier end
    local class = ent:GetClass()
    if class == "grid_printer_diamond" then return 3 end
    if class == "grid_printer_silver" then return 2 end
    if class == "grid_printer_bronze" then return 1 end
    if ent.ItemQuality == "epic" or ent.ItemQuality == "rare" then return 3 end
    if ent.ItemQuality == "uncommon" then return 2 end
    return 1
end

local function IsSwitchEntity(ent)
    if not IsValid(ent) then return false end
    if ent.IsNetworkSwitch then return true end
    local c = ent:GetClass()
    return c == "grid_network_switch" or string.StartWith(c, "grid_network_switch")
end

function ENT:Initialize()
    self:SetModel("models/props_lab/reciever01a.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetColor(self.SwitchColor or Color(30, 144, 255))
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    local portCount = self:GetPortCount()
    if portCount <= 0 then
        -- Default to 4 ports if subclass did not define any
        self.PortDefinitions = {
            { id = 1, type = "copper", speed = "1G",  name = "Port 1", allowSwitch = false, allowDevice = true, allowWAN = true },
            { id = 2, type = "copper", speed = "1G",  name = "Port 2", allowSwitch = false, allowDevice = true, allowWAN = true },
            { id = 3, type = "combo",  speed = "10G", name = "Port 3", allowSwitch = true,  allowDevice = true, allowWAN = true },
            { id = 4, type = "sfp",    speed = "10G", name = "Port 4", allowSwitch = true,  allowDevice = false, allowWAN = false },
        }
        portCount = 4
    end

    self:SetMaxPorts(portCount)
    self:SetConnectedCount(0)
    self:SetEfficiency(GRID.Config.PrinterStandaloneEfficiency or 60)
    self:SetActivePortsMask(0)
    self:SetPort10GMask(0)
    self:SetPortUplinkMask(0)

    -- Broadcast Domain Subnet & Gateway IP
    local subnetId = GRID.Network and GRID.Network.GetSubnetID(self) or (((self:EntIndex() * 7) % 240) + 10)
    self:SetSubnetID(subnetId)
    self:SetIPAddress(string.format("192.168.%d.1", subnetId))

    -- Modular Physical Port Slots
    self.Ports = {}
    for i = 1, portCount do
        self.Ports[i] = nil
    end

    -- Wiremod Support
    if WireLib then
        WireLib.CreateInputs(self, { "ClearLinks" })
        WireLib.CreateOutputs(self, {
            "ConnectedPrinters",
            "NetworkEfficiency",
            "IsOptimal",
            "Port1Connected",
            "Port2Connected",
            "Port3Connected",
            "Port3Is10G",
            "Port3Mode [STRING]",
            "Port4Connected",
            "SFPUplink [ENTITY]",
            "Port3Uplink [ENTITY]",
            "Port1Efficiency",
            "Port2Efficiency",
            "Port3Efficiency",
            "TotalStoredCash",
            "MaxTemp",
            "Printer1 [ENTITY]",
            "Printer2 [ENTITY]",
            "Printer3 [ENTITY]"
        })
        self:UpdateWireOutputs()
    end

    -- Distance Cable Snapping Monitor
    local timerName = "GRID_SwitchCableMonitor_" .. self:EntIndex()
    timer.Create(timerName, 1.5, 0, function()
        if not IsValid(self) then
            timer.Remove(timerName)
            return
        end
        self:CheckCableDistances()
    end)
end

function ENT:TriggerInput(name, value)
    if name == "ClearLinks" and value ~= 0 then
        self:DisconnectAll()
    end
end

-- Retrieves next available port capable of switch-to-switch uplinks (dedicated SFP first, then Combo)
function ENT:GetAvailableSwitchPort()
    local defs = self:GetPortDefinitions()
    -- Pass 1: Check dedicated SFP ports (highest preference)
    for i, def in ipairs(defs) do
        if self.Ports[i] == nil and def.type == "sfp" and def.allowSwitch ~= false then
            return i
        end
    end
    -- Pass 2: Check Combo ports
    for i, def in ipairs(defs) do
        if self.Ports[i] == nil and def.type == "combo" and def.allowSwitch ~= false then
            return i
        end
    end
    return nil
end

-- Retrieves next available port for standard copper devices (dedicated Copper first, then Combo)
function ENT:GetAvailableCopperPort()
    local defs = self:GetPortDefinitions()
    -- Pass 1: Check dedicated Copper ports
    for i, def in ipairs(defs) do
        if self.Ports[i] == nil and def.type == "copper" and def.allowDevice ~= false then
            return i
        end
    end
    -- Pass 2: Check Combo ports in copper mode
    for i, def in ipairs(defs) do
        if self.Ports[i] == nil and def.type == "combo" and def.allowDevice ~= false then
            return i
        end
    end
    return nil
end

-- General port finder based on device characteristics
function ENT:GetAvailablePort(targetDev)
    local isSwitch = IsSwitchEntity(targetDev) or (targetDev == true)
    if isSwitch then
        return self:GetAvailableSwitchPort()
    end

    local isWAN = IsValid(targetDev) and (targetDev:GetClass() == "grid_wan_uplink" or targetDev.IsWANUplink)
    local defs = self:GetPortDefinitions()

    if isWAN then
        -- WAN prefers Combo port for 10G optical SFP mode, then Copper ports
        for i, def in ipairs(defs) do
            if self.Ports[i] == nil and def.type == "combo" and def.allowWAN ~= false then
                return i
            end
        end
        for i, def in ipairs(defs) do
            if self.Ports[i] == nil and def.type == "copper" and def.allowWAN ~= false then
                return i
            end
        end
        return nil
    end

    -- Printers and regular devices prefer copper ports, then Combo ports
    for i, def in ipairs(defs) do
        if self.Ports[i] == nil and def.type == "copper" and def.allowDevice ~= false then
            return i
        end
    end
    for i, def in ipairs(defs) do
        if self.Ports[i] == nil and def.type == "combo" and def.allowDevice ~= false then
            return i
        end
    end
    return nil
end

-- Connects this switch to another switch via SFP / Trunk
function ENT:ConnectSwitch(otherSwitch, rope, myPort, otherPort)
    if not IsSwitchEntity(otherSwitch) then
        return false, "Invalid switch entity"
    end
    if otherSwitch == self then
        return false, "Cannot wire an entity to itself!"
    end

    myPort = myPort or self:GetAvailableSwitchPort()
    otherPort = otherPort or (otherSwitch.GetAvailableSwitchPort and otherSwitch:GetAvailableSwitchPort())

    if not myPort then
        return false, string.format("This switch (%s) has no available SFP/Combo ports for uplink!", self.PrintName or "Switch")
    end
    if not otherPort then
        return false, string.format("Target switch (%s) has no available SFP/Combo ports for uplink!", otherSwitch.PrintName or "Switch")
    end

    local myDef = self:GetPortDefinition(myPort)
    local otherDef = otherSwitch.GetPortDefinition and otherSwitch:GetPortDefinition(otherPort)

    self.Ports[myPort] = {
        port = myPort,
        device = otherSwitch,
        switch = otherSwitch,
        rope = rope,
        type = "sfp_uplink",
        is10G = true,
        isUplink = true
    }

    if otherSwitch.Ports then
        otherSwitch.Ports[otherPort] = {
            port = otherPort,
            device = self,
            switch = self,
            rope = rope,
            type = "sfp_uplink",
            is10G = true,
            isUplink = true
        }
    end

    self:RecalculateNetwork()
    if otherSwitch.RecalculateNetwork then
        otherSwitch:RecalculateNetwork()
    end

    return true, myPort, otherPort
end

local function CleanDeviceParams(dev)
    if not IsValid(dev) then return end
    if dev.GetBotnetActive and dev:GetBotnetActive() and dev.StopBotnet then
        dev:StopBotnet("Ethernet link to L3 Switch lost.")
    end
    if dev.SetIPAddress then dev:SetIPAddress("") end
    if dev.SetConnectedSwitch then dev:SetConnectedSwitch(NULL) end
    if dev.SetAssignedPort then dev:SetAssignedPort(0) end

    if dev.SetEfficiency then
        dev:SetEfficiency(GRID.Config.PrinterStandaloneEfficiency or 60)
    end
    if dev.SetNetworkedCount then
        dev:SetNetworkedCount(1)
    end
    if dev.UpdateWireOutputs then
        dev:UpdateWireOutputs()
    end
end

-- Connects a device (Printer, Computer, WAN Uplink, Synthesizer)
function ENT:ConnectDevice(dev, rope, chosenPort)
    if not IsValid(dev) then return false, "Invalid device" end

    -- Switch-to-switch links forward to ConnectSwitch
    if IsSwitchEntity(dev) then
        return self:ConnectSwitch(dev, rope)
    end

    -- Check if device is already linked to this switch
    for pId, pData in pairs(self.Ports) do
        if pData and (pData.device == dev or pData.printer == dev) then
            return false, "Device already linked to this switch"
        end
    end

    chosenPort = chosenPort or self:GetAvailablePort(dev)
    if not chosenPort then
        return false, string.format("Switch ports are full! (%d/%d ports occupied)", self:GetConnectedCount() or 0, self:GetPortCount())
    end

    local portDef = self:GetPortDefinition(chosenPort)
    local isWAN = (dev:GetClass() == "grid_wan_uplink" or dev.IsWANUplink)
    local isPrinter = dev.PrintAmount ~= nil or string.find(dev:GetClass(), "printer")
    local isComputer = dev:GetClass() == "grid_computer" or dev.IsComputer
    local is10G = (portDef and (portDef.type == "sfp" or (portDef.type == "combo" and isWAN)))

    -- Disconnect device from previous switch if any
    local oldSwitch = dev.GetConnectedSwitch and dev:GetConnectedSwitch()
    if IsValid(oldSwitch) and oldSwitch ~= self then
        if oldSwitch.DisconnectDevice then
            oldSwitch:DisconnectDevice(dev)
        elseif oldSwitch.DisconnectPrinter then
            oldSwitch:DisconnectPrinter(dev)
        end
    end

    self.Ports[chosenPort] = {
        port = chosenPort,
        device = dev,
        printer = isPrinter and dev or nil,
        rope = rope,
        type = isPrinter and "printer" or (isComputer and "computer" or (isWAN and "wan_uplink" or "device")),
        is10G = is10G,
        isUplink = false
    }

    local subnet = self:GetSubnetID()
    if not subnet or subnet <= 0 then
        subnet = GRID.Network and GRID.Network.GetSubnetID(self) or (((self:EntIndex() * 7) % 240) + 10)
        self:SetSubnetID(subnet)
    end
    local assignedIP = string.format("192.168.%d.%d", subnet, 10 + chosenPort)

    if dev.SetIPAddress then dev:SetIPAddress(assignedIP) end
    if dev.SetConnectedSwitch then dev:SetConnectedSwitch(self) end
    if dev.SetAssignedPort then dev:SetAssignedPort(chosenPort) end

    if isWAN and GRID.Network and GRID.Network.RecalculateWANMesh then
        GRID.Network.RecalculateWANMesh()
    end

    self:RecalculateNetwork()
    return true, chosenPort, assignedIP, is10G
end
ENT.ConnectPrinter = ENT.ConnectDevice

-- Generic Disconnect for any port ID
function ENT:DisconnectPort(portId)
    local portData = self.Ports[portId]
    if not portData then return end

    if IsValid(portData.rope) then
        portData.rope:Remove()
    end

    local dev = portData.device or portData.switch or portData.printer
    self.Ports[portId] = nil

    if IsValid(dev) then
        if IsSwitchEntity(dev) and dev.Ports then
            -- Find reciprocal link on other switch and unlink
            for remotePortId, remoteData in pairs(dev.Ports) do
                if remoteData and (remoteData.device == self or remoteData.switch == self) then
                    if IsValid(remoteData.rope) then remoteData.rope:Remove() end
                    dev.Ports[remotePortId] = nil
                    if dev.RecalculateNetwork then
                        dev:RecalculateNetwork()
                    end
                end
            end
        else
            CleanDeviceParams(dev)
            local isWAN = (dev:GetClass() == "grid_wan_uplink" or dev.IsWANUplink)
            if isWAN and GRID.Network and GRID.Network.RecalculateWANMesh then
                GRID.Network.RecalculateWANMesh()
            end
        end
    end

    self:RecalculateNetwork()
end

-- Disconnects a specific device from whatever port it is in
function ENT:DisconnectDevice(dev)
    if not IsValid(dev) then return end
    for portId, portData in pairs(self.Ports) do
        if portData and (portData.device == dev or portData.switch == dev or portData.printer == dev) then
            self:DisconnectPort(portId)
            return
        end
    end
end
ENT.DisconnectPrinter = ENT.DisconnectDevice

-- Disconnects first active SFP / switch uplink port
function ENT:DisconnectSFP()
    for portId, portData in pairs(self.Ports) do
        if portData and portData.isUplink then
            self:DisconnectPort(portId)
            return
        end
    end
    -- Fallback: check port definitions for SFP
    local defs = self:GetPortDefinitions()
    for i = #defs, 1, -1 do
        if self.Ports[i] and defs[i].type == "sfp" then
            self:DisconnectPort(i)
            return
        end
    end
end
ENT.DisconnectSwitch = ENT.DisconnectSFP

-- Disconnects all linked ports
function ENT:DisconnectAll()
    local portCount = self:GetPortCount()
    for portId = 1, portCount do
        if self.Ports[portId] then
            self:DisconnectPort(portId)
        end
    end
    self:RecalculateNetwork()
end

-- Dynamic network recalculation across broadcast domains
function ENT:RecalculateNetwork(visited)
    visited = visited or {}
    if visited[self] then return end
    visited[self] = true

    local validPrinters = {}
    local validDevices = {}
    local uplinkSwitches = {}

    local activeMask = 0
    local speedMask = 0
    local uplinkMask = 0

    local portCount = self:GetPortCount()
    for portId = 1, portCount do
        local portData = self.Ports[portId]
        if portData then
            local dev = portData.device or portData.switch or portData.printer
            if IsValid(dev) then
                local bitVal = bit.lshift(1, portId - 1)
                activeMask = bit.bor(activeMask, bitVal)

                if portData.is10G then
                    speedMask = bit.bor(speedMask, bitVal)
                end

                if IsSwitchEntity(dev) then
                    uplinkMask = bit.bor(uplinkMask, bitVal)
                    table.insert(uplinkSwitches, dev)
                else
                    table.insert(validDevices, dev)
                    if dev.PrintAmount ~= nil or string.find(dev:GetClass(), "printer") then
                        table.insert(validPrinters, dev)
                    end
                end
            else
                -- Entity became invalid, clean up port
                if IsValid(portData.rope) then portData.rope:Remove() end
                self.Ports[portId] = nil
            end
        end
    end

    self:SetConnectedCount(#validDevices)
    self:SetActivePortsMask(activeMask)
    self:SetPort10GMask(speedMask)
    self:SetPortUplinkMask(uplinkMask)

    -- Propagate to all connected uplink switches
    for _, sw in ipairs(uplinkSwitches) do
        if not visited[sw] and sw.RecalculateNetwork then
            sw:RecalculateNetwork(visited)
        end
    end

    -- Aggregate all printers within shared broadcast domain
    local allPrintersInDomain = {}
    for sw, _ in pairs(visited) do
        if IsValid(sw) and sw.Ports then
            for _, pData in pairs(sw.Ports) do
                if pData then
                    local pDev = pData.device or pData.printer
                    if IsValid(pDev) and (pDev.PrintAmount ~= nil or string.find(pDev:GetClass(), "printer")) then
                        table.insert(allPrintersInDomain, pDev)
                    end
                end
            end
        end
    end

    -- Tier-qualified printer efficiency calculation
    local totalEff = 0
    for _, printer in ipairs(validPrinters) do
        local pTier = GetPrinterTier(printer)
        local qualifyingCount = 0

        for _, other in ipairs(allPrintersInDomain) do
            local otherTier = GetPrinterTier(other)
            if otherTier >= pTier then
                qualifyingCount = qualifyingCount + 1
            end
        end

        local eff = GRID.Config.PrinterStandaloneEfficiency or 60
        if qualifyingCount == 2 then
            eff = GRID.Config.PrinterNetworkEfficiency2 or 80
        elseif qualifyingCount >= 3 then
            eff = GRID.Config.PrinterNetworkEfficiency3 or 100
        end

        printer:SetEfficiency(eff)
        printer:SetNetworkedCount(qualifyingCount)
        if printer.UpdateWireOutputs then
            printer:UpdateWireOutputs()
        end

        totalEff = totalEff + eff
    end

    -- Update Resource Fabricator & Botnet state
    for _, dev in ipairs(validDevices) do
        if dev:GetClass() == "grid_resource_machine" then
            local eff = (#allPrintersInDomain >= 2 or #validDevices >= 2) and (GRID.Config.PrinterNetworkEfficiency3 or 100) or (GRID.Config.PrinterNetworkEfficiency2 or 80)
            dev:SetEfficiency(eff)
        elseif dev:GetClass() == "grid_computer" and dev.RefreshBotnetState then
            dev:RefreshBotnetState()
        end
    end

    local printerCount = #validPrinters
    local avgEff = (printerCount > 0) and math.floor(totalEff / printerCount) or (GRID.Config.PrinterStandaloneEfficiency or 60)
    self:SetEfficiency(avgEff)

    self:UpdateWireOutputs()
end

-- Distance Cable Snapping Monitor
function ENT:CheckCableDistances()
    local maxDist = GRID.Config.MaxCableLength or 550
    local maxDistSqr = maxDist * maxDist
    local maxFiberDist = GRID.Config.MaxFiberCableLength or 800
    local maxFiberDistSqr = maxFiberDist * maxFiberDist
    local myPos = self:GetPos()

    local defs = self:GetPortDefinitions()
    for portId, def in ipairs(defs) do
        local portData = self.Ports[portId]
        if portData then
            local dev = portData.device or portData.switch or portData.printer
            if IsValid(dev) then
                local isFiber = portData.is10G or def.type == "sfp"
                local limitSqr = isFiber and maxFiberDistSqr or maxDistSqr

                if myPos:DistToSqr(dev:GetPos()) > limitSqr then
                    local effect = EffectData()
                    effect:SetOrigin(dev:GetPos() + Vector(0, 0, 10))
                    util.Effect("cball_bounce", effect)
                    self:EmitSound(isFiber and "ambient/energy/zap2.wav" or "ambient/energy/spark1.wav", 75, 100)

                    self:DisconnectPort(portId)
                    local msg = isFiber and string.format("An SFP 10G optical cable on Port %d snapped due to tension!", portId) or string.format("A copper network cable on Port %d snapped due to tension!", portId)
                    GRID.NotifyAll(msg, NOTIFY_HINT)
                end
            end
        end
    end
end

function ENT:GetBroadcastDomainDevices()
    return GRID.Network and GRID.Network.GetBroadcastDomain(self) or {}
end

function ENT:UpdateWireOutputs()
    if not WireLib then return end

    local count = self:GetConnectedCount() or 0
    local eff = self:GetEfficiency() or 60
    local portCount = self:GetPortCount()

    local totalCash = 0
    local maxTemp = 0
    local allOptimal = (count >= 3)

    local p1 = self.Ports[1] and self.Ports[1].printer or NULL
    local p2 = self.Ports[2] and self.Ports[2].printer or NULL
    local p3 = self.Ports[3] and self.Ports[3].printer or NULL

    local eff1 = IsValid(p1) and (p1:GetEfficiency() or 60) or 0
    local eff2 = IsValid(p2) and (p2:GetEfficiency() or 60) or 0
    local eff3 = IsValid(p3) and (p3:GetEfficiency() or 60) or 0

    for i = 1, portCount do
        local p = self.Ports[i] and self.Ports[i].printer
        if IsValid(p) then
            totalCash = totalCash + (p:GetStoredCash() or 0)
            local t = p:GetTemperature() or 20
            if t > maxTemp then maxTemp = t end
            if (p:GetEfficiency() or 60) < 100 then
                allOptimal = false
            end
        end
    end

    local isOptimal = (count >= 3 and allOptimal) and 1 or 0
    local p3Active = self:IsPortActive(3) and 1 or 0
    local p3Is10G = self:IsPort10G(3)
    local p3ModeStr = (p3Active == 1) and (p3Is10G and "10G SFP" or "1G Copper") or "EMPTY"
    local sfpActive = self:IsPortActive(4) and 1 or 0

    local uplinkSwitch4 = self:GetUplinkSwitch(4)
    local uplinkSwitch3 = self:GetUplinkSwitch(3)

    WireLib.TriggerOutput(self, "ConnectedPrinters", count)
    WireLib.TriggerOutput(self, "NetworkEfficiency", eff)
    WireLib.TriggerOutput(self, "IsOptimal", isOptimal)
    WireLib.TriggerOutput(self, "Port1Connected", IsValid(p1) and 1 or 0)
    WireLib.TriggerOutput(self, "Port2Connected", IsValid(p2) and 1 or 0)
    WireLib.TriggerOutput(self, "Port3Connected", p3Active)
    WireLib.TriggerOutput(self, "Port3Is10G", p3Is10G and 1 or 0)
    WireLib.TriggerOutput(self, "Port3Mode", p3ModeStr)
    WireLib.TriggerOutput(self, "Port4Connected", sfpActive)
    WireLib.TriggerOutput(self, "SFPUplink", IsValid(uplinkSwitch4) and uplinkSwitch4 or NULL)
    WireLib.TriggerOutput(self, "Port3Uplink", IsValid(uplinkSwitch3) and uplinkSwitch3 or NULL)
    WireLib.TriggerOutput(self, "Port1Efficiency", eff1)
    WireLib.TriggerOutput(self, "Port2Efficiency", eff2)
    WireLib.TriggerOutput(self, "Port3Efficiency", eff3)
    WireLib.TriggerOutput(self, "TotalStoredCash", totalCash)
    WireLib.TriggerOutput(self, "MaxTemp", maxTemp)
    WireLib.TriggerOutput(self, "Printer1", p1)
    WireLib.TriggerOutput(self, "Printer2", p2)
    WireLib.TriggerOutput(self, "Printer3", p3)

    WireLib.SetOverlayText(self, string.format(
        "[%s]\nPorts: %d/%d Active\nAvg Eff: %d%% | Net Cash: $%d | Peak Temp: %d°C",
        self.PrintName or "GridRP L3 Switch",
        count, portCount, eff, totalCash, maxTemp
    ))
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[activator] or 0) > now then return end
    self.NextUsePerPlayer[activator] = now + 0.4

    if activator:IsPolice() then
        local isPatrol = (activator:GetJob() == "police_officer")
        local baseBounty = GRID.Config.PoliceBountyPerSwitch or 300
        local bounty = isPatrol and math.floor(baseBounty * 1.5) or baseBounty
        activator:AddMoney(bounty)
        local msg = isPatrol and string.format("Detective Perk: Network switch seized for +$%d (+50%% Patrol Bounty)!", bounty) or string.format("Contraband network switch confiscated for +$%d bounty!", bounty)
        GRID.Notify(activator, msg, NOTIFY_GENERIC)
        activator:EmitSound("ambient/levels/labs/coinslot1.wav")
        self:DisconnectAll()
        self:Remove()
    else
        local count = self:GetConnectedCount() or 0
        local portCount = self:GetPortCount()
        local subnet = self:GetSubnetID() or 1
        local gateway = self:GetIPAddress() ~= "" and self:GetIPAddress() or string.format("192.168.%d.1", subnet)

        GRID.Notify(activator, string.format("%s: %d/%d Ports Linked | Subnet: 192.168.%d.0/24 (GW: %s)", self.PrintName or "L3 Switch", count, portCount, subnet, gateway), NOTIFY_HINT)
        self:EmitSound("buttons/button14.wav", 60, 100)
    end
end

function ENT:OnRemove()
    timer.Remove("GRID_SwitchCableMonitor_" .. self:EntIndex())
    self:DisconnectAll()

    if WireLib then
        WireLib.Remove(self)
    end
end

