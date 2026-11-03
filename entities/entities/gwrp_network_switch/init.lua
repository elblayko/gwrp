--[[
    entities/entities/gwrp_network_switch/init.lua
    GWRP 4-Port Layer-2 Network Switch Server Logic (3 Copper Ports + 1 SFP Optical Uplink)
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local function GetPrinterTier(ent)
    if not IsValid(ent) then return 0 end
    if ent.PrinterTier then return ent.PrinterTier end
    local class = ent:GetClass()
    if class == "gwrp_printer_diamond" then return 3 end
    if class == "gwrp_printer_silver" then return 2 end
    if class == "gwrp_printer_bronze" then return 1 end
    if ent.ItemQuality == "epic" or ent.ItemQuality == "rare" then return 3 end
    if ent.ItemQuality == "uncommon" then return 2 end
    return 1
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

    self:SetMaxPorts(4)
    self:SetConnectedCount(0)
    self:SetEfficiency(GWRP.Config.PrinterStandaloneEfficiency or 60)
    self:SetPort1Active(false)
    self:SetPort2Active(false)
    self:SetPort3Active(false)
    self:SetPort4Active(false)
    self:SetUplinkSwitch(NULL)

    -- Broadcast Domain Subnet & Gateway IP
    local subnetId = GWRP.Network and GWRP.Network.GetSubnetID(self) or (((self:EntIndex() * 7) % 240) + 10)
    self:SetSubnetID(subnetId)
    self:SetIPAddress(string.format("192.168.%d.1", subnetId))

    -- Physical Port Slots:
    -- Ports [1..3]: Copper Ethernet (Printers, Computers, Devices)
    -- Port [4]: SFP Optical Transceiver Module (Switch-to-Switch Interconnect Only)
    self.Ports = {
        [1] = nil,
        [2] = nil,
        [3] = nil,
        [4] = nil
    }

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
            "Port4Connected",
            "SFPUplink [ENTITY]",
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
    local timerName = "GWRP_SwitchCableMonitor_" .. self:EntIndex()
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

-- Retrieves next free copper port (1..3) or SFP port (4)
function ENT:GetAvailablePort(isSwitch)
    if isSwitch then
        if self.Ports[4] == nil then
            return 4
        end
        return nil
    end

    -- Other things (printers, computers, synthesizers) only connect to copper ports [1..3]
    for i = 1, 3 do
        if self.Ports[i] == nil then
            return i
        end
    end
    return nil
end

function ENT:GetAvailableCopperPort()
    return self:GetAvailablePort(false)
end

function ENT:GetAvailableSFPPort()
    return self:GetAvailablePort(true)
end

-- Connects this switch to another switch via the 4th port (SFP Module)
function ENT:ConnectSwitch(otherSwitch, rope)
    if not IsValid(otherSwitch) or otherSwitch:GetClass() ~= "gwrp_network_switch" then
        return false, "Invalid switch entity"
    end
    if otherSwitch == self then
        return false, "Cannot wire an entity to itself!"
    end

    if self.Ports[4] ~= nil then
        return false, "This switch's SFP module port (Port 4) is already connected to another switch!"
    end
    if otherSwitch.Ports and otherSwitch.Ports[4] ~= nil then
        return false, "Target switch's SFP module port (Port 4) is already connected to another switch!"
    end

    self.Ports[4] = {
        device = otherSwitch,
        switch = otherSwitch,
        rope = rope,
        type = "sfp_uplink"
    }

    otherSwitch.Ports[4] = {
        device = self,
        switch = self,
        rope = rope,
        type = "sfp_uplink"
    }

    self:SetPort4Active(true)
    otherSwitch:SetPort4Active(true)
    self:SetUplinkSwitch(otherSwitch)
    otherSwitch:SetUplinkSwitch(self)

    self:RecalculateNetwork()
    return true, 4
end

-- Disconnects the SFP module switch uplink
function ENT:DisconnectSFP()
    local sfpData = self.Ports[4]
    if not sfpData then return end

    if IsValid(sfpData.rope) then
        sfpData.rope:Remove()
    end

    local otherSwitch = sfpData.device or sfpData.switch
    self.Ports[4] = nil
    self:SetPort4Active(false)
    self:SetUplinkSwitch(NULL)

    if IsValid(otherSwitch) and otherSwitch:GetClass() == "gwrp_network_switch" then
        if otherSwitch.Ports and otherSwitch.Ports[4] and (otherSwitch.Ports[4].device == self or otherSwitch.Ports[4].switch == self) then
            if IsValid(otherSwitch.Ports[4].rope) then
                otherSwitch.Ports[4].rope:Remove()
            end
            otherSwitch.Ports[4] = nil
            otherSwitch:SetPort4Active(false)
            otherSwitch:SetUplinkSwitch(NULL)
            otherSwitch:RecalculateNetwork()
        end
    end

    self:RecalculateNetwork()
end
ENT.DisconnectSwitch = ENT.DisconnectSFP

function ENT:ConnectDevice(dev, rope)
    if not IsValid(dev) then return false, "Invalid device" end

    -- Switches connect specifically through the 4th port SFP Module
    if dev:GetClass() == "gwrp_network_switch" then
        return self:ConnectSwitch(dev, rope)
    end

    -- Check if device already connected to this switch
    for portNum = 1, 3 do
        local portData = self.Ports[portNum]
        if portData and (portData.device == dev or portData.printer == dev) then
            return false, "Device already linked to this switch"
        end
    end

    -- Standard devices can only connect to copper ports 1..3
    local port = self:GetAvailableCopperPort()
    if not port then
        return false, "Switch copper ports are at maximum capacity (3/3 ports occupied)! Port 4 is an SFP module for switch uplinks only."
    end

    -- If device was connected to another switch, disconnect it first
    local oldSwitch = dev.GetConnectedSwitch and dev:GetConnectedSwitch()
    if IsValid(oldSwitch) and oldSwitch ~= self then
        if oldSwitch.DisconnectDevice then
            oldSwitch:DisconnectDevice(dev)
        elseif oldSwitch.DisconnectPrinter then
            oldSwitch:DisconnectPrinter(dev)
        end
    end

    local isPrinter = dev.PrintAmount ~= nil or string.find(dev:GetClass(), "printer")
    local isComputer = dev:GetClass() == "gwrp_computer" or dev.IsComputer

    self.Ports[port] = {
        device = dev,
        printer = isPrinter and dev or nil,
        rope = rope,
        type = isPrinter and "printer" or (isComputer and "computer" or "device")
    }

    local subnet = self:GetSubnetID()
    if not subnet or subnet <= 0 then
        subnet = GWRP.Network and GWRP.Network.GetSubnetID(self) or (((self:EntIndex() * 7) % 240) + 10)
        self:SetSubnetID(subnet)
    end
    local assignedIP = string.format("192.168.%d.%d", subnet, 10 + port)

    if dev.SetIPAddress then dev:SetIPAddress(assignedIP) end
    if dev.SetConnectedSwitch then dev:SetConnectedSwitch(self) end
    if dev.SetAssignedPort then dev:SetAssignedPort(port) end

    self:RecalculateNetwork()
    return true, port, assignedIP
end
ENT.ConnectPrinter = ENT.ConnectDevice

function ENT:DisconnectDevice(dev)
    if not IsValid(dev) then return end

    if dev:GetClass() == "gwrp_network_switch" then
        if self.Ports[4] and (self.Ports[4].device == dev or self.Ports[4].switch == dev) then
            self:DisconnectSFP()
        end
        return
    end

    local foundPort = nil
    for portNum = 1, 3 do
        local portData = self.Ports[portNum]
        if portData and (portData.device == dev or portData.printer == dev) then
            foundPort = portNum
            if IsValid(portData.rope) then
                portData.rope:Remove()
            end
            self.Ports[portNum] = nil
            break
        end
    end

    if foundPort then
        if dev.SetIPAddress then dev:SetIPAddress("") end
        if dev.SetConnectedSwitch then dev:SetConnectedSwitch(NULL) end
        if dev.SetAssignedPort then dev:SetAssignedPort(0) end

        if dev.SetEfficiency then
            dev:SetEfficiency(GWRP.Config.PrinterStandaloneEfficiency or 60)
        end
        if dev.SetNetworkedCount then
            dev:SetNetworkedCount(1)
        end
        if dev.UpdateWireOutputs then
            dev:UpdateWireOutputs()
        end

        self:RecalculateNetwork()
    end
end
ENT.DisconnectPrinter = ENT.DisconnectDevice

function ENT:DisconnectAll()
    -- Disconnect copper ports 1..3
    for i = 1, 3 do
        local portData = self.Ports[i]
        if portData then
            if IsValid(portData.rope) then
                portData.rope:Remove()
            end
            local dev = portData.device or portData.printer
            if IsValid(dev) then
                if dev.SetIPAddress then dev:SetIPAddress("") end
                if dev.SetConnectedSwitch then dev:SetConnectedSwitch(NULL) end
                if dev.SetAssignedPort then dev:SetAssignedPort(0) end
                if dev.SetEfficiency then
                    dev:SetEfficiency(GWRP.Config.PrinterStandaloneEfficiency or 60)
                end
                if dev.SetNetworkedCount then
                    dev:SetNetworkedCount(1)
                end
                if dev.UpdateWireOutputs then
                    dev:UpdateWireOutputs()
                end
            end
            self.Ports[i] = nil
        end
    end

    -- Disconnect SFP module uplink (Port 4)
    if self.Ports[4] then
        self:DisconnectSFP()
    else
        self:RecalculateNetwork()
    end
end

function ENT:RecalculateNetwork(visited)
    visited = visited or {}
    if visited[self] then return end
    visited[self] = true

    local validPrinters = {}
    local validDevices = {}

    -- Clean invalid entities on copper ports [1..3]
    for i = 1, 3 do
        local portData = self.Ports[i]
        if portData then
            local dev = portData.device or portData.printer
            if IsValid(dev) then
                table.insert(validDevices, dev)
                if dev.PrintAmount ~= nil or string.find(dev:GetClass(), "printer") then
                    table.insert(validPrinters, dev)
                end
            else
                if IsValid(portData.rope) then
                    portData.rope:Remove()
                end
                self.Ports[i] = nil
            end
        end
    end

    -- Validate Port 4 (SFP Module Uplink)
    local sfpData = self.Ports[4]
    local uplinkSwitch = nil
    if sfpData then
        local other = sfpData.device or sfpData.switch
        if IsValid(other) and other:GetClass() == "gwrp_network_switch" then
            uplinkSwitch = other
        else
            if IsValid(sfpData.rope) then
                sfpData.rope:Remove()
            end
            self.Ports[4] = nil
        end
    end

    local count = #validDevices
    self:SetConnectedCount(count)
    self:SetPort1Active(self.Ports[1] ~= nil)
    self:SetPort2Active(self.Ports[2] ~= nil)
    self:SetPort3Active(self.Ports[3] ~= nil)
    self:SetPort4Active(self.Ports[4] ~= nil)
    self:SetUplinkSwitch(uplinkSwitch or NULL)

    -- Propagate recalculation to uplinked switch across SFP if not yet visited
    if IsValid(uplinkSwitch) and not visited[uplinkSwitch] then
        uplinkSwitch:RecalculateNetwork(visited)
    end

    -- Aggregate all printers within the shared Layer-2 broadcast domain (including SFP trunks)
    local allPrintersInDomain = {}
    for sw, _ in pairs(visited) do
        if IsValid(sw) and sw.Ports then
            for i = 1, 3 do
                local pData = sw.Ports[i]
                if pData then
                    local pDev = pData.device or pData.printer
                    if IsValid(pDev) and (pDev.PrintAmount ~= nil or string.find(pDev:GetClass(), "printer")) then
                        table.insert(allPrintersInDomain, pDev)
                    end
                end
            end
        end
    end

    -- Per-printer tier-qualified efficiency calculation based on broadcast domain pool
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

        local eff = GWRP.Config.PrinterStandaloneEfficiency or 60
        if qualifyingCount == 2 then
            eff = GWRP.Config.PrinterNetworkEfficiency2 or 80
        elseif qualifyingCount >= 3 then
            eff = GWRP.Config.PrinterNetworkEfficiency3 or 100
        end

        printer:SetEfficiency(eff)
        printer:SetNetworkedCount(qualifyingCount)
        if printer.UpdateWireOutputs then
            printer:UpdateWireOutputs()
        end

        totalEff = totalEff + eff
    end

    -- Update Resource Fabricator efficiency based on network load (100% when 2+ are attached)
    for _, dev in ipairs(validDevices) do
        if dev:GetClass() == "gwrp_resource_machine" then
            local eff = (#allPrintersInDomain >= 2 or count >= 2) and (GWRP.Config.PrinterNetworkEfficiency3 or 100) or (GWRP.Config.PrinterNetworkEfficiency2 or 80)
            dev:SetEfficiency(eff)
        end
    end

    local printerCount = #validPrinters
    local avgEff = (printerCount > 0) and math.floor(totalEff / printerCount) or (GWRP.Config.PrinterStandaloneEfficiency or 60)
    self:SetEfficiency(avgEff)

    self:UpdateWireOutputs()
end

function ENT:CheckCableDistances()
    local maxDist = GWRP.Config.MaxCableLength or 550
    local maxDistSqr = maxDist * maxDist
    local maxFiberDist = GWRP.Config.MaxFiberCableLength or 800
    local maxFiberDistSqr = maxFiberDist * maxFiberDist
    local myPos = self:GetPos()

    -- Check copper cables (ports 1..3)
    for portNum = 1, 3 do
        local portData = self.Ports[portNum]
        if portData then
            local dev = portData.device or portData.printer
            if IsValid(dev) then
                if myPos:DistToSqr(dev:GetPos()) > maxDistSqr then
                    local effect = EffectData()
                    effect:SetOrigin(dev:GetPos() + Vector(0, 0, 10))
                    util.Effect("cball_bounce", effect)
                    self:EmitSound("ambient/energy/spark1.wav", 75, 100)

                    self:DisconnectDevice(dev)
                    GWRP.NotifyAll("A copper network cable snapped due to tension!", NOTIFY_HINT)
                end
            end
        end
    end

    -- Check SFP optical fiber cable (Port 4)
    local sfpData = self.Ports[4]
    if sfpData then
        local other = sfpData.device or sfpData.switch
        if IsValid(other) then
            if myPos:DistToSqr(other:GetPos()) > maxFiberDistSqr then
                local effect = EffectData()
                effect:SetOrigin(other:GetPos() + Vector(0, 0, 10))
                util.Effect("cball_bounce", effect)
                self:EmitSound("ambient/energy/zap2.wav", 80, 120)

                self:DisconnectSFP()
                GWRP.NotifyAll("An SFP fiber optic uplink cable snapped due to tension!", NOTIFY_HINT)
            end
        end
    end
end

function ENT:GetBroadcastDomainDevices()
    return GWRP.Network and GWRP.Network.GetBroadcastDomain(self) or {}
end

function ENT:UpdateWireOutputs()
    if not WireLib then return end

    local count = self:GetConnectedCount() or 0
    local eff = self:GetEfficiency() or 60
    local sfpActive = self:GetPort4Active() and 1 or 0
    local uplinkSwitch = self:GetUplinkSwitch()

    local totalCash = 0
    local maxTemp = 0
    local allOptimal = (count >= 3)

    local p1 = self.Ports[1] and self.Ports[1].printer or NULL
    local p2 = self.Ports[2] and self.Ports[2].printer or NULL
    local p3 = self.Ports[3] and self.Ports[3].printer or NULL

    local eff1 = IsValid(p1) and (p1:GetEfficiency() or 60) or 0
    local eff2 = IsValid(p2) and (p2:GetEfficiency() or 60) or 0
    local eff3 = IsValid(p3) and (p3:GetEfficiency() or 60) or 0

    for i = 1, 3 do
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

    WireLib.TriggerOutput(self, "ConnectedPrinters", count)
    WireLib.TriggerOutput(self, "NetworkEfficiency", eff)
    WireLib.TriggerOutput(self, "IsOptimal", isOptimal)
    WireLib.TriggerOutput(self, "Port1Connected", IsValid(p1) and 1 or 0)
    WireLib.TriggerOutput(self, "Port2Connected", IsValid(p2) and 1 or 0)
    WireLib.TriggerOutput(self, "Port3Connected", IsValid(p3) and 1 or 0)
    WireLib.TriggerOutput(self, "Port4Connected", sfpActive)
    WireLib.TriggerOutput(self, "SFPUplink", IsValid(uplinkSwitch) and uplinkSwitch or NULL)
    WireLib.TriggerOutput(self, "Port1Efficiency", eff1)
    WireLib.TriggerOutput(self, "Port2Efficiency", eff2)
    WireLib.TriggerOutput(self, "Port3Efficiency", eff3)
    WireLib.TriggerOutput(self, "TotalStoredCash", totalCash)
    WireLib.TriggerOutput(self, "MaxTemp", maxTemp)
    WireLib.TriggerOutput(self, "Printer1", p1)
    WireLib.TriggerOutput(self, "Printer2", p2)
    WireLib.TriggerOutput(self, "Printer3", p3)

    local sfpStatusStr = (sfpActive == 1) and "UP (10G Optical)" or "DOWN"
    WireLib.SetOverlayText(self, string.format(
        "[GWRP L2 Network Switch]\nCopper Ports: %d / 3 (Avg %d%% Eff)\nSFP Uplink: %s\nNet Cash: $%d | Peak Temp: %d°C",
        count, eff, sfpStatusStr, totalCash, maxTemp
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
        local baseBounty = GWRP.Config.PoliceBountyPerSwitch or 300
        local bounty = isPatrol and math.floor(baseBounty * 1.5) or baseBounty
        activator:AddMoney(bounty)
        local msg = isPatrol and string.format("Detective Perk: Network switch seized for +$%d (+50%% Patrol Bounty)!", bounty) or string.format("Contraband network switch confiscated for +$%d bounty!", bounty)
        GWRP.Notify(activator, msg, NOTIFY_GENERIC)
        activator:EmitSound("ambient/levels/labs/coinslot1.wav")
        self:DisconnectAll()
        self:Remove()
    else
        local count = self:GetConnectedCount() or 0
        local subnet = self:GetSubnetID() or 1
        local gateway = self:GetIPAddress() ~= "" and self:GetIPAddress() or string.format("192.168.%d.1", subnet)
        local sfpActive = self:GetPort4Active()
        local sfpText = sfpActive and "SFP: Uplinked (10G)" or "SFP: Standby (Port 4)"
        GWRP.Notify(activator, string.format("L2 Switch: %d/3 Copper Ports Active | %s | Subnet: 192.168.%d.0/24 (Gateway: %s)", count, sfpText, subnet, gateway), NOTIFY_HINT)
        self:EmitSound("buttons/button14.wav", 60, 100)
    end
end

function ENT:OnRemove()
    timer.Remove("GWRP_SwitchCableMonitor_" .. self:EntIndex())
    self:DisconnectAll()

    if WireLib then
        WireLib.Remove(self)
    end
end
