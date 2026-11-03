--[[
    gamemode/core/sh_networking.lua
    GWRP Layer 2 / Layer 3 Networking, IP Addressing & Broadcast Domain System
    Author: Toxic
--]]

GWRP.Network = GWRP.Network or {}

-- Generates a deterministic subnet identifier (1..254) for a given network switch
function GWRP.Network.GetSubnetID(switchEnt)
    if not IsValid(switchEnt) then return 1 end
    if switchEnt.GetSubnetID and switchEnt:GetSubnetID() > 0 then
        return switchEnt:GetSubnetID()
    end
    local index = switchEnt:EntIndex()
    if index <= 0 then index = math.random(1, 200) end
    return ((index * 7) % 240) + 10 -- Generates subnets like 10..249
end

-- Formats IPv4 address string given a subnet and host offset
function GWRP.Network.FormatIP(subnetId, hostId)
    return string.format("192.168.%d.%d", subnetId, hostId)
end

-- Gateway IP for a switch
function GWRP.Network.GetGatewayIP(switchEnt)
    local subnet = GWRP.Network.GetSubnetID(switchEnt)
    return string.format("192.168.%d.1", subnet)
end

-- Generates a simulated MAC address for realism in network tools (nmap, ifconfig)
function GWRP.Network.FormatMAC(ent, subnetId, hostId)
    local idx = IsValid(ent) and ent:EntIndex() or 1
    local sub = subnetId or 1
    local hst = hostId or 10
    return string.format("02:42:C0:%02X:%02X:%02X", sub % 256, hst % 256, idx % 256)
end

-- Traverses and retrieves all active devices within the broadcast domain of a switch
function GWRP.Network.GetBroadcastDomain(switchEnt)
    if not IsValid(switchEnt) or switchEnt:GetClass() ~= "gwrp_network_switch" then
        return {}
    end

    local subnet = GWRP.Network.GetSubnetID(switchEnt)
    local devices = {}

    -- 1. The Switch itself (Default Gateway)
    table.insert(devices, {
        entity = switchEnt,
        name = switchEnt.PrintName or "L2 Network Switch (3-Port)",
        type = "switch",
        ip = GWRP.Network.GetGatewayIP(switchEnt),
        mac = GWRP.Network.FormatMAC(switchEnt, subnet, 1),
        port = 0,
        status = "ONLINE",
        services = {
            { port = 22, proto = "tcp", service = "ssh", version = "GWRP-Switch-OS L2.1" },
            { port = 80, proto = "tcp", service = "http", version = "Switch Web Console" }
        }
    })

    -- 2. Connected Devices across the switch ports
    local maxPorts = switchEnt.GetMaxPorts and switchEnt:GetMaxPorts() or 3
    for portNum = 1, maxPorts do
        local portData = switchEnt.Ports and switchEnt.Ports[portNum]
        if portData then
            local dev = portData.device or portData.printer
            if IsValid(dev) then
                local devClass = dev:GetClass()
                local isPrinter = dev.PrintAmount ~= nil or string.find(devClass, "printer")
                local isComputer = devClass == "gwrp_computer" or dev.IsComputer
                local isSynthesizer = devClass == "gwrp_resource_machine" or string.find(devClass, "resource_machine")
                local devType = isPrinter and "printer" or (isComputer and "computer" or (isSynthesizer and "synthesizer" or "device"))

                local hostId = 10 + portNum
                local devIP = (dev.GetIPAddress and dev:GetIPAddress() ~= "") and dev:GetIPAddress() or GWRP.Network.FormatIP(subnet, hostId)
                local devMAC = GWRP.Network.FormatMAC(dev, subnet, hostId)

                local services = {}
                if isPrinter then
                    local tierName = dev.ItemQuality or "standard"
                    local eff = dev.GetEfficiency and dev:GetEfficiency() or 60
                    local temp = dev.GetTemperature and dev:GetTemperature() or 20
                    table.insert(services, {
                        port = 8080,
                        proto = "tcp",
                        service = "http-alt",
                        version = string.format("MoneyFab Daemon v%s (Eff: %d%%, Temp: %dC)", tierName, eff, temp)
                    })
                elseif isComputer then
                    table.insert(services, {
                        port = 23,
                        proto = "tcp",
                        service = "telnet",
                        version = "CyberDeck Terminal Shell"
                    })
                elseif isSynthesizer then
                    local eff = dev.GetEfficiency and dev:GetEfficiency() or 60
                    local temp = dev.GetTemperature and dev:GetTemperature() or 20
                    table.insert(services, {
                        port = 502,
                        proto = "tcp",
                        service = "modbus",
                        version = string.format("Modbus/TCP SCADA OT Synthesizer (Eff: %d%%, Temp: %dC)", eff, temp)
                    })
                    table.insert(services, {
                        port = 4840,
                        proto = "tcp",
                        service = "opcua",
                        version = "OPC-UA Material Fabrication Service"
                    })
                end

                table.insert(devices, {
                    entity = dev,
                    name = dev.PrintName or (isPrinter and "Money Printer" or (isComputer and "Personal Computer" or (isSynthesizer and "Resource Fabricator" or "Network Device"))),
                    type = devType,
                    ip = devIP,
                    mac = devMAC,
                    port = portNum,
                    status = "ONLINE",
                    services = services
                })
            end
        end
    end

    return devices
end
