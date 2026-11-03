--[[
    entities/entities/gwrp_network_switch/init.lua
    GWRP 3-Port Layer-2 Network Switch Server Logic
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

    self:SetMaxPorts(GWRP.Config.SwitchMaxPorts or 3)
    self:SetConnectedCount(0)
    self:SetEfficiency(GWRP.Config.PrinterStandaloneEfficiency or 60)
    self:SetPort1Active(false)
    self:SetPort2Active(false)
    self:SetPort3Active(false)

    -- Broadcast Domain Subnet & Gateway IP
    local subnetId = GWRP.Network and GWRP.Network.GetSubnetID(self) or (((self:EntIndex() * 7) % 240) + 10)
    self:SetSubnetID(subnetId)
    self:SetIPAddress(string.format("192.168.%d.1", subnetId))

    -- Physical Port Slots [1..3]
    self.Ports = {
        [1] = nil,
        [2] = nil,
        [3] = nil
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

function ENT:GetAvailablePort()
    local maxPorts = self:GetMaxPorts() or 3
    for i = 1, maxPorts do
        if self.Ports[i] == nil then
            return i
        end
    end
    return nil
end

function ENT:ConnectDevice(dev, rope)
    if not IsValid(dev) then return false, "Invalid device" end

    -- Check if device already connected to this switch
    for portNum, portData in pairs(self.Ports) do
        if portData and (portData.device == dev or portData.printer == dev) then
            return false, "Device already linked to this switch"
        end
    end

    local port = self:GetAvailablePort()
    if not port then
        return false, "Switch is at maximum capacity (3/3 ports occupied)"
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

    local foundPort = nil
    for portNum, portData in pairs(self.Ports) do
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
    local maxPorts = self:GetMaxPorts() or 3
    for i = 1, maxPorts do
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

    self:RecalculateNetwork()
end

function ENT:RecalculateNetwork()
    local maxPorts = self:GetMaxPorts() or 3
    local validPrinters = {}
    local validDevices = {}

    -- Clean invalid entities
    for i = 1, maxPorts do
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

    local count = #validDevices
    self:SetConnectedCount(count)
    self:SetPort1Active(self.Ports[1] ~= nil)
    self:SetPort2Active(self.Ports[2] ~= nil)
    self:SetPort3Active(self.Ports[3] ~= nil)

    -- Per-printer tier-qualified efficiency calculation
    local totalEff = 0
    for _, printer in ipairs(validPrinters) do
        local pTier = GetPrinterTier(printer)
        local qualifyingCount = 0

        for _, other in ipairs(validPrinters) do
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

    local printerCount = #validPrinters
    local avgEff = (printerCount > 0) and math.floor(totalEff / printerCount) or (GWRP.Config.PrinterStandaloneEfficiency or 60)
    self:SetEfficiency(avgEff)

    self:UpdateWireOutputs()
end

function ENT:CheckCableDistances()
    local maxDist = GWRP.Config.MaxCableLength or 550
    local maxDistSqr = maxDist * maxDist
    local myPos = self:GetPos()

    for portNum, portData in pairs(self.Ports) do
        if portData then
            local dev = portData.device or portData.printer
            if IsValid(dev) then
                if myPos:DistToSqr(dev:GetPos()) > maxDistSqr then
                    -- Visual spark & sound on snap
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
end

function ENT:GetBroadcastDomainDevices()
    return GWRP.Network and GWRP.Network.GetBroadcastDomain(self) or {}
end

function ENT:UpdateWireOutputs()
    if not WireLib then return end

    local count = self:GetConnectedCount() or 0
    local eff = self:GetEfficiency() or 60

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
    WireLib.TriggerOutput(self, "Port1Efficiency", eff1)
    WireLib.TriggerOutput(self, "Port2Efficiency", eff2)
    WireLib.TriggerOutput(self, "Port3Efficiency", eff3)
    WireLib.TriggerOutput(self, "TotalStoredCash", totalCash)
    WireLib.TriggerOutput(self, "MaxTemp", maxTemp)
    WireLib.TriggerOutput(self, "Printer1", p1)
    WireLib.TriggerOutput(self, "Printer2", p2)
    WireLib.TriggerOutput(self, "Printer3", p3)

    WireLib.SetOverlayText(self, string.format(
        "[GWRP L2 Network Switch]\nLinks: %d / 3 (Avg %d%% Eff)\nNet Cash: $%d | Peak Temp: %d°C",
        count, eff, totalCash, maxTemp
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
        GWRP.Notify(activator, string.format("L2 Switch: %d/3 Ports Active | Subnet: 192.168.%d.0/24 (Gateway: %s)", count, subnet, gateway), NOTIFY_HINT)
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
