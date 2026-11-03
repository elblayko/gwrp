--[[
    entities/entities/gw_network_switch/init.lua
    GWRP 4-Port Layer-3 Network Switch Server Logic
    (Ports 1-2: Dedicated Copper | Port 3: SFP Combo 10G/1G | Port 4: Dedicated 10G SFP)
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local function GetPrinterTier(ent)
    if not IsValid(ent) then return 0 end
    if ent.PrinterTier then return ent.PrinterTier end
    local class = ent:GetClass()
    if class == "gw_printer_diamond" then return 3 end
    if class == "gw_printer_silver" then return 2 end
    if class == "gw_printer_bronze" then return 1 end
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
    self:SetEfficiency(GW.Config.PrinterStandaloneEfficiency or 60)
    self:SetPort1Active(false)
    self:SetPort2Active(false)
    self:SetPort3Active(false)
    self:SetPort3Is10G(false)
    self:SetPort4Active(false)
    self:SetUplinkSwitch(NULL)
    self:SetPort3Switch(NULL)

    -- Broadcast Domain Subnet & Gateway IP
    local subnetId = GW.Network and GW.Network.GetSubnetID(self) or (((self:EntIndex() * 7) % 240) + 10)
    self:SetSubnetID(subnetId)
    self:SetIPAddress(string.format("192.168.%d.1", subnetId))

    -- Physical Port Slots:
    -- Ports [1..2]: Dedicated Copper Ethernet (Printers, Computers, Devices)
    -- Port [3]: SFP Combo Port (10G for Switches / WAN Uplink, or 1G Copper SFP for Printers)
    -- Port [4]: Dedicated SFP 10G Optical Transceiver (Switch-to-Switch Interconnect Only)
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
    local timerName = "GW_SwitchCableMonitor_" .. self:EntIndex()
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

-- Retrieves next available SFP port for switch uplinks (checks Port 4 first, then Port 3)
function ENT:GetAvailableSwitchPort()
    if self.Ports[4] == nil then return 4 end
    if self.Ports[3] == nil then return 3 end
    return nil
end

-- Retrieves next available port for standard devices (1..3)
function ENT:GetAvailableCopperPort()
    for i = 1, 3 do
        if self.Ports[i] == nil then return i end
    end
    return nil
end

-- General port finder based on device characteristics
function ENT:GetAvailablePort(targetDev)
    local isSwitch = (IsValid(targetDev) and targetDev:GetClass() == "gw_network_switch") or (targetDev == true)
    if isSwitch then
        return self:GetAvailableSwitchPort()
    end

    local isWAN = IsValid(targetDev) and (targetDev:GetClass() == "gw_wan_uplink" or targetDev.IsWANUplink)
    if isWAN then
        -- WAN prefers Port 3 for 10G SFP, then ports 1 and 2
        if self.Ports[3] == nil then return 3 end
        if self.Ports[1] == nil then return 1 end
        if self.Ports[2] == nil then return 2 end
        return nil
    end

    -- Printers and regular devices prefer copper ports 1-2, then Port 3 in 1G copper mode
    if self.Ports[1] == nil then return 1 end
    if self.Ports[2] == nil then return 2 end
    if self.Ports[3] == nil then return 3 end
    return nil
end

-- Connects this switch to another switch via SFP (using Port 4 or Port 3)
function ENT:ConnectSwitch(otherSwitch, rope, myPort, otherPort)
    if not IsValid(otherSwitch) or otherSwitch:GetClass() ~= "gw_network_switch" then
        return false, "Invalid switch entity"
    end
    if otherSwitch == self then
        return false, "Cannot wire an entity to itself!"
    end

    myPort = myPort or self:GetAvailableSwitchPort()
    otherPort = otherPort or (otherSwitch.GetAvailableSwitchPort and otherSwitch:GetAvailableSwitchPort() or (otherSwitch.Ports[4] == nil and 4 or (otherSwitch.Ports[3] == nil and 3 or nil)))

    if not myPort then
        return false, "This switch's SFP ports (Ports 3 and 4) are both in use!"
    end
    if not otherPort then
        return false, "Target switch's SFP ports (Ports 3 and 4) are both in use!"
    end

    self.Ports[myPort] = {
        device = otherSwitch,
        switch = otherSwitch,
        rope = rope,
        type = "sfp_uplink",
        is10G = true
    }

    otherSwitch.Ports[otherPort] = {
        device = self,
        switch = self,
        rope = rope,
        type = "sfp_uplink",
        is10G = true
    }

    if myPort == 3 then
        self:SetPort3Active(true)
        self:SetPort3Is10G(true)
        self:SetPort3Switch(otherSwitch)
    else
        self:SetPort4Active(true)
        self:SetUplinkSwitch(otherSwitch)
    end

    if otherPort == 3 then
        otherSwitch:SetPort3Active(true)
        otherSwitch:SetPort3Is10G(true)
        otherSwitch:SetPort3Switch(self)
    else
        otherSwitch:SetPort4Active(true)
        otherSwitch:SetUplinkSwitch(self)
    end

    self:RecalculateNetwork()
    otherSwitch:RecalculateNetwork()
    return true, myPort, otherPort
end

-- Disconnects Port 4 (Dedicated SFP Uplink)
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

    if IsValid(otherSwitch) and otherSwitch:GetClass() == "gw_network_switch" then
        if otherSwitch.Ports then
            for p = 3, 4 do
                if otherSwitch.Ports[p] and (otherSwitch.Ports[p].device == self or otherSwitch.Ports[p].switch == self) then
                    if IsValid(otherSwitch.Ports[p].rope) then otherSwitch.Ports[p].rope:Remove() end
                    otherSwitch.Ports[p] = nil
                    if p == 3 then
                        otherSwitch:SetPort3Active(false)
                        otherSwitch:SetPort3Is10G(false)
                        otherSwitch:SetPort3Switch(NULL)
                    else
                        otherSwitch:SetPort4Active(false)
                        otherSwitch:SetUplinkSwitch(NULL)
                    end
                    otherSwitch:RecalculateNetwork()
                end
            end
        end
    end

    self:RecalculateNetwork()
end
ENT.DisconnectSwitch = ENT.DisconnectSFP

function ENT:ConnectDevice(dev, rope)
    if not IsValid(dev) then return false, "Invalid device" end

    -- Switches connect through SFP ports (Port 4 or Port 3)
    if dev:GetClass() == "gw_network_switch" then
        return self:ConnectSwitch(dev, rope)
    end

    -- Check if device already connected to this switch
    for portNum = 1, 3 do
        local portData = self.Ports[portNum]
        if portData and (portData.device == dev or portData.printer == dev) then
            return false, "Device already linked to this switch"
        end
    end

    local isWAN = (dev:GetClass() == "gw_wan_uplink" or dev.IsWANUplink)
    local isPrinter = dev.PrintAmount ~= nil or string.find(dev:GetClass(), "printer")
    local isComputer = dev:GetClass() == "gw_computer" or dev.IsComputer

    -- Port selection:
    -- If WAN uplink: prefers Port 3 for 10G SFP mode, otherwise copper ports 1..2
    -- If Printer or regular device: prefers copper ports 1..2, then Port 3 in 1G copper SFP mode
    local chosenPort = nil
    if isWAN then
        if self.Ports[3] == nil then
            chosenPort = 3
        elseif self.Ports[1] == nil then
            chosenPort = 1
        elseif self.Ports[2] == nil then
            chosenPort = 2
        end
    else
        if self.Ports[1] == nil then
            chosenPort = 1
        elseif self.Ports[2] == nil then
            chosenPort = 2
        elseif self.Ports[3] == nil then
            chosenPort = 3
        end
    end

    if not chosenPort then
        return false, "Switch device ports are full (Ports 1-3 occupied)! Port 4 is dedicated to 10G switch uplinks."
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

    local is10G = (chosenPort == 3 and isWAN)

    self.Ports[chosenPort] = {
        device = dev,
        printer = isPrinter and dev or nil,
        rope = rope,
        type = isPrinter and "printer" or (isComputer and "computer" or (isWAN and "wan_uplink" or "device")),
        is10G = is10G
    }

    if chosenPort == 3 then
        self:SetPort3Active(true)
        self:SetPort3Is10G(is10G)
        self:SetPort3Switch(NULL)
    end

    local subnet = self:GetSubnetID()
    if not subnet or subnet <= 0 then
        subnet = GW.Network and GW.Network.GetSubnetID(self) or (((self:EntIndex() * 7) % 240) + 10)
        self:SetSubnetID(subnet)
    end
    local assignedIP = string.format("192.168.%d.%d", subnet, 10 + chosenPort)

    if dev.SetIPAddress then dev:SetIPAddress(assignedIP) end
    if dev.SetConnectedSwitch then dev:SetConnectedSwitch(self) end
    if dev.SetAssignedPort then dev:SetAssignedPort(chosenPort) end

    if isWAN and GW.Network and GW.Network.RecalculateWANMesh then
        GW.Network.RecalculateWANMesh()
    end

    self:RecalculateNetwork()
    return true, chosenPort, assignedIP, is10G
end
ENT.ConnectPrinter = ENT.ConnectDevice

local function CleanDeviceParams(dev)
    if not IsValid(dev) then return end
    if dev.SetIPAddress then dev:SetIPAddress("") end
    if dev.SetConnectedSwitch then dev:SetConnectedSwitch(NULL) end
    if dev.SetAssignedPort then dev:SetAssignedPort(0) end

    if dev.SetEfficiency then
        dev:SetEfficiency(GW.Config.PrinterStandaloneEfficiency or 60)
    end
    if dev.SetNetworkedCount then
        dev:SetNetworkedCount(1)
    end
    if dev.UpdateWireOutputs then
        dev:UpdateWireOutputs()
    end
end

function ENT:DisconnectDevice(dev)
    if not IsValid(dev) then return end

    -- Check Port 3 (SFP Combo: Switch 10G, WAN 10G, or Device 1G)
    if self.Ports[3] and (self.Ports[3].device == dev or self.Ports[3].switch == dev) then
        if IsValid(self.Ports[3].rope) then self.Ports[3].rope:Remove() end

        if dev:GetClass() == "gw_network_switch" and dev.Ports then
            for p = 3, 4 do
                if dev.Ports[p] and (dev.Ports[p].device == self or dev.Ports[p].switch == self) then
                    if IsValid(dev.Ports[p].rope) then dev.Ports[p].rope:Remove() end
                    dev.Ports[p] = nil
                    if p == 3 then
                        dev:SetPort3Active(false)
                        dev:SetPort3Is10G(false)
                        dev:SetPort3Switch(NULL)
                    else
                        dev:SetPort4Active(false)
                        dev:SetUplinkSwitch(NULL)
                    end
                    dev:RecalculateNetwork()
                end
            end
        end

        local isWAN = (dev:GetClass() == "gw_wan_uplink" or dev.IsWANUplink)
        self.Ports[3] = nil
        self:SetPort3Active(false)
        self:SetPort3Is10G(false)
        self:SetPort3Switch(NULL)

        CleanDeviceParams(dev)
        if isWAN and GW.Network and GW.Network.RecalculateWANMesh then
            GW.Network.RecalculateWANMesh()
        end
        self:RecalculateNetwork()
        return
    end

    -- Check Port 4 (Dedicated SFP 10G Uplink)
    if self.Ports[4] and (self.Ports[4].device == dev or self.Ports[4].switch == dev) then
        self:DisconnectSFP()
        return
    end

    -- Check Ports 1..2
    for portNum = 1, 2 do
        local portData = self.Ports[portNum]
        if portData and (portData.device == dev or portData.printer == dev) then
            if IsValid(portData.rope) then portData.rope:Remove() end
            self.Ports[portNum] = nil

            local isWAN = (dev:GetClass() == "gw_wan_uplink" or dev.IsWANUplink)
            CleanDeviceParams(dev)
            if isWAN and GW.Network and GW.Network.RecalculateWANMesh then
                GW.Network.RecalculateWANMesh()
            end
            self:RecalculateNetwork()
            break
        end
    end
end
ENT.DisconnectPrinter = ENT.DisconnectDevice

function ENT:DisconnectAll()
    -- Disconnect ports 1..3
    for i = 1, 3 do
        local portData = self.Ports[i]
        if portData then
            if IsValid(portData.rope) then portData.rope:Remove() end
            local dev = portData.device or portData.printer or portData.switch
            if IsValid(dev) then
                if dev:GetClass() == "gw_network_switch" then
                    for p = 3, 4 do
                        if dev.Ports and dev.Ports[p] and (dev.Ports[p].device == self or dev.Ports[p].switch == self) then
                            if IsValid(dev.Ports[p].rope) then dev.Ports[p].rope:Remove() end
                            dev.Ports[p] = nil
                            if p == 3 then
                                dev:SetPort3Active(false)
                                dev:SetPort3Is10G(false)
                                dev:SetPort3Switch(NULL)
                            else
                                dev:SetPort4Active(false)
                                dev:SetUplinkSwitch(NULL)
                            end
                            dev:RecalculateNetwork()
                        end
                    end
                else
                    CleanDeviceParams(dev)
                end
            end
            self.Ports[i] = nil
        end
    end

    self:SetPort3Active(false)
    self:SetPort3Is10G(false)
    self:SetPort3Switch(NULL)

    -- Disconnect Port 4 SFP uplink
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

    -- Clean invalid entities on ports [1..2]
    for i = 1, 2 do
        local portData = self.Ports[i]
        if portData then
            local dev = portData.device or portData.printer
            if IsValid(dev) then
                table.insert(validDevices, dev)
                if dev.PrintAmount ~= nil or string.find(dev:GetClass(), "printer") then
                    table.insert(validPrinters, dev)
                end
            else
                if IsValid(portData.rope) then portData.rope:Remove() end
                self.Ports[i] = nil
            end
        end
    end

    -- Validate Port 3 (SFP Combo: Switch 10G, WAN 10G, or Device 1G)
    local p3Data = self.Ports[3]
    local uplinkSwitch3 = nil
    local p3Is10G = false
    if p3Data then
        local dev = p3Data.device or p3Data.switch or p3Data.printer
        if IsValid(dev) then
            if dev:GetClass() == "gw_network_switch" then
                uplinkSwitch3 = dev
                p3Is10G = true
            elseif dev:GetClass() == "gw_wan_uplink" or dev.IsWANUplink then
                p3Is10G = true
                table.insert(validDevices, dev)
            else
                -- 1G Copper SFP mode (Printer or Device)
                p3Is10G = false
                table.insert(validDevices, dev)
                if dev.PrintAmount ~= nil or string.find(dev:GetClass(), "printer") then
                    table.insert(validPrinters, dev)
                end
            end
        else
            if IsValid(p3Data.rope) then p3Data.rope:Remove() end
            self.Ports[3] = nil
        end
    end

    -- Validate Port 4 (Dedicated SFP 10G Uplink)
    local sfpData = self.Ports[4]
    local uplinkSwitch4 = nil
    if sfpData then
        local other = sfpData.device or sfpData.switch
        if IsValid(other) and other:GetClass() == "gw_network_switch" then
            uplinkSwitch4 = other
        else
            if IsValid(sfpData.rope) then sfpData.rope:Remove() end
            self.Ports[4] = nil
        end
    end

    local count = #validDevices
    self:SetConnectedCount(count)
    self:SetPort1Active(self.Ports[1] ~= nil)
    self:SetPort2Active(self.Ports[2] ~= nil)
    self:SetPort3Active(self.Ports[3] ~= nil)
    self:SetPort3Is10G(p3Is10G)
    self:SetPort3Switch(uplinkSwitch3 or NULL)
    self:SetPort4Active(self.Ports[4] ~= nil)
    self:SetUplinkSwitch(uplinkSwitch4 or NULL)

    -- Propagate recalculation to uplinked switches across SFP trunks
    if IsValid(uplinkSwitch3) and not visited[uplinkSwitch3] then
        uplinkSwitch3:RecalculateNetwork(visited)
    end
    if IsValid(uplinkSwitch4) and not visited[uplinkSwitch4] then
        uplinkSwitch4:RecalculateNetwork(visited)
    end

    -- Aggregate all printers within the shared Layer-3 broadcast domain (including SFP trunks)
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

        local eff = GW.Config.PrinterStandaloneEfficiency or 60
        if qualifyingCount == 2 then
            eff = GW.Config.PrinterNetworkEfficiency2 or 80
        elseif qualifyingCount >= 3 then
            eff = GW.Config.PrinterNetworkEfficiency3 or 100
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
        if dev:GetClass() == "gw_resource_machine" then
            local eff = (#allPrintersInDomain >= 2 or count >= 2) and (GW.Config.PrinterNetworkEfficiency3 or 100) or (GW.Config.PrinterNetworkEfficiency2 or 80)
            dev:SetEfficiency(eff)
        end
    end

    local printerCount = #validPrinters
    local avgEff = (printerCount > 0) and math.floor(totalEff / printerCount) or (GW.Config.PrinterStandaloneEfficiency or 60)
    self:SetEfficiency(avgEff)

    self:UpdateWireOutputs()
end

function ENT:CheckCableDistances()
    local maxDist = GW.Config.MaxCableLength or 550
    local maxDistSqr = maxDist * maxDist
    local maxFiberDist = GW.Config.MaxFiberCableLength or 800
    local maxFiberDistSqr = maxFiberDist * maxFiberDist
    local myPos = self:GetPos()

    -- Check copper ports 1..2
    for portNum = 1, 2 do
        local portData = self.Ports[portNum]
        if portData then
            local dev = portData.device or portData.printer
            if IsValid(dev) and myPos:DistToSqr(dev:GetPos()) > maxDistSqr then
                local effect = EffectData()
                effect:SetOrigin(dev:GetPos() + Vector(0, 0, 10))
                util.Effect("cball_bounce", effect)
                self:EmitSound("ambient/energy/spark1.wav", 75, 100)

                self:DisconnectDevice(dev)
                GW.NotifyAll("A copper network cable snapped due to tension!", NOTIFY_HINT)
            end
        end
    end

    -- Check Port 3 (SFP Combo: 10G mode uses fiber distance, 1G mode uses copper distance)
    local p3Data = self.Ports[3]
    if p3Data then
        local dev = p3Data.device or p3Data.switch or p3Data.printer
        if IsValid(dev) then
            local limitSqr = (self:GetPort3Is10G() and maxFiberDistSqr or maxDistSqr)
            if myPos:DistToSqr(dev:GetPos()) > limitSqr then
                local effect = EffectData()
                effect:SetOrigin(dev:GetPos() + Vector(0, 0, 10))
                util.Effect("cball_bounce", effect)
                self:EmitSound("ambient/energy/zap2.wav", 80, 120)

                local is10G = self:GetPort3Is10G()
                self:DisconnectDevice(dev)
                local msg = is10G and "An SFP 10G optical cable snapped due to tension!" or "A copper network cable snapped due to tension!"
                GW.NotifyAll(msg, NOTIFY_HINT)
            end
        end
    end

    -- Check Port 4 (SFP 10G Dedicated Uplink)
    local sfpData = self.Ports[4]
    if sfpData then
        local other = sfpData.device or sfpData.switch
        if IsValid(other) and myPos:DistToSqr(other:GetPos()) > maxFiberDistSqr then
            local effect = EffectData()
            effect:SetOrigin(other:GetPos() + Vector(0, 0, 10))
            util.Effect("cball_bounce", effect)
            self:EmitSound("ambient/energy/zap2.wav", 80, 120)

            self:DisconnectSFP()
            GW.NotifyAll("An SFP 10G fiber optic uplink cable snapped due to tension!", NOTIFY_HINT)
        end
    end
end

function ENT:GetBroadcastDomainDevices()
    return GW.Network and GW.Network.GetBroadcastDomain(self) or {}
end

function ENT:UpdateWireOutputs()
    if not WireLib then return end

    local count = self:GetConnectedCount() or 0
    local eff = self:GetEfficiency() or 60
    local p3Active = self:GetPort3Active() and 1 or 0
    local p3Is10G = self:GetPort3Is10G()
    local p3ModeStr = (p3Active == 1) and (p3Is10G and "10G SFP" or "1G Copper") or "EMPTY"
    local sfpActive = self:GetPort4Active() and 1 or 0
    local uplinkSwitch4 = self:GetUplinkSwitch()
    local uplinkSwitch3 = self:GetPort3Switch()

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

    local p4StatusStr = (sfpActive == 1) and "UP (10G Optical)" or "DOWN"
    WireLib.SetOverlayText(self, string.format(
        "[GWRP L3 Network Switch]\nPorts: P1/P2 Cu (%d links) | P3: %s | P4: %s\nAvg Eff: %d%% | Net Cash: $%d | Peak Temp: %d°C",
        count, p3ModeStr, p4StatusStr, eff, totalCash, maxTemp
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
        local baseBounty = GW.Config.PoliceBountyPerSwitch or 300
        local bounty = isPatrol and math.floor(baseBounty * 1.5) or baseBounty
        activator:AddMoney(bounty)
        local msg = isPatrol and string.format("Detective Perk: Network switch seized for +$%d (+50%% Patrol Bounty)!", bounty) or string.format("Contraband network switch confiscated for +$%d bounty!", bounty)
        GW.Notify(activator, msg, NOTIFY_GENERIC)
        activator:EmitSound("ambient/levels/labs/coinslot1.wav")
        self:DisconnectAll()
        self:Remove()
    else
        local count = self:GetConnectedCount() or 0
        local subnet = self:GetSubnetID() or 1
        local gateway = self:GetIPAddress() ~= "" and self:GetIPAddress() or string.format("192.168.%d.1", subnet)
        local p3Active = self:GetPort3Active()
        local p3Is10G = self:GetPort3Is10G()
        local p3Str = p3Active and (p3Is10G and "P3: SFP 10G" or "P3: Copper 1G") or "P3: Empty"
        local sfpActive = self:GetPort4Active()
        local p4Str = sfpActive and "P4: Uplinked (10G)" or "P4: Standby"
        GW.Notify(activator, string.format("L3 Switch: %s | %s | Subnet: 192.168.%d.0/24 (Gateway: %s)", p3Str, p4Str, subnet, gateway), NOTIFY_HINT)
        self:EmitSound("buttons/button14.wav", 60, 100)
    end
end

function ENT:OnRemove()
    timer.Remove("GW_SwitchCableMonitor_" .. self:EntIndex())
    self:DisconnectAll()

    if WireLib then
        WireLib.Remove(self)
    end
end
