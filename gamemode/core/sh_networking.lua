--[[
    gamemode/core/sh_networking.lua
    GridRP Layer 2 / Layer 3 Networking, IP Addressing & Broadcast Domain System
    Author: Toxic
--]]

GRID.Network = GRID.Network or {}

-- Generates a deterministic subnet identifier (1..254) for a given network switch
function GRID.Network.GetSubnetID(switchEnt)
    if not IsValid(switchEnt) then return 1 end
    if switchEnt.GetSubnetID and switchEnt:GetSubnetID() > 0 then
        return switchEnt:GetSubnetID()
    end
    local index = switchEnt:EntIndex()
    if index <= 0 then index = math.random(1, 200) end
    return ((index * 7) % 240) + 10 -- Generates subnets like 10..249
end

-- Formats IPv4 address string given a subnet and host offset
function GRID.Network.FormatIP(subnetId, hostId)
    return string.format("192.168.%d.%d", subnetId, hostId)
end

-- Gateway IP for a switch
function GRID.Network.GetGatewayIP(switchEnt)
    local subnet = GRID.Network.GetSubnetID(switchEnt)
    return string.format("192.168.%d.1", subnet)
end

-- Generates a simulated MAC address for realism in network tools (nmap, ifconfig)
function GRID.Network.FormatMAC(ent, subnetId, hostId)
    local idx = IsValid(ent) and ent:EntIndex() or 1
    local sub = subnetId or 1
    local hst = hostId or 10
    return string.format("02:42:C0:%02X:%02X:%02X", sub % 256, hst % 256, idx % 256)
end

-- Helper to check if entity is a network switch
local function isSwitch(dev)
    if not IsValid(dev) then return false end
    if dev.IsNetworkSwitch then return true end
    local c = dev:GetClass()
    return c == "grid_network_switch" or string.StartWith(c, "grid_network_switch")
end

-- Traverses and retrieves all active devices within the broadcast domain of a switch (including SFP-uplinked switches)
function GRID.Network.GetBroadcastDomain(switchEnt, visited)
    if not isSwitch(switchEnt) then
        return {}
    end

    visited = visited or {}
    if visited[switchEnt] then return {} end
    visited[switchEnt] = true

    local subnet = GRID.Network.GetSubnetID(switchEnt)
    local devices = {}

    -- 1. The Switch itself (Default Gateway)
    table.insert(devices, {
        entity = switchEnt,
        name = switchEnt.PrintName or "L3 Network Switch",
        type = "switch",
        ip = GRID.Network.GetGatewayIP(switchEnt),
        mac = GRID.Network.FormatMAC(switchEnt, subnet, 1),
        port = 0,
        status = "ONLINE",
        services = {
            { port = 22, proto = "tcp", service = "ssh", version = "GRID-Switch-OS L3.1" },
            { port = 80, proto = "tcp", service = "http", version = "Switch Web Console" }
        }
    })

    -- 2. Dynamically scan all configured switch ports
    local portDefs = switchEnt.GetPortDefinitions and switchEnt:GetPortDefinitions() or {}
    local totalPorts = math.max(#portDefs, (switchEnt.GetPortCount and switchEnt:GetPortCount()) or 4)

    for portNum = 1, totalPorts do
        local portData = switchEnt.Ports and switchEnt.Ports[portNum]
        if portData then
            local dev = portData.device or portData.printer or portData.switch
            if IsValid(dev) then
                local devClass = dev:GetClass()
                if isSwitch(dev) then
                    -- Interconnected switch trunk across this port
                    if not visited[dev] then
                        local trunkedDevices = GRID.Network.GetBroadcastDomain(dev, visited)
                        for _, devData in ipairs(trunkedDevices) do
                            table.insert(devices, devData)
                        end
                    end
                else
                    local isPrinter = dev.PrintAmount ~= nil or string.find(devClass, "printer")
                    local isComputer = devClass == "grid_computer" or dev.IsComputer
                    local isSynthesizer = devClass == "grid_resource_machine" or string.find(devClass, "resource_machine")
                    local isUplink = devClass == "grid_wan_uplink" or dev.IsWANUplink
                    local devType = isPrinter and "printer" or (isComputer and "computer" or (isSynthesizer and "synthesizer" or (isUplink and "wan_uplink" or "device")))

                    local hostId = 10 + portNum
                    local devIP = (dev.GetIPAddress and dev:GetIPAddress() ~= "") and dev:GetIPAddress() or GRID.Network.FormatIP(subnet, hostId)
                    local devMAC = GRID.Network.FormatMAC(dev, subnet, hostId)

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
                    elseif isUplink then
                        local isOnline = dev.GetIsOnline and dev:GetIsOnline()
                        local peers = dev.GetLinkedPeerCount and dev:GetLinkedPeerCount() or 0
                        local key = dev.GetEncryptionKey and dev:GetEncryptionKey() or "NONE"
                        local portSpeed = portData.is10G and "10G SFP" or "1G Copper"
                        table.insert(services, {
                            port = 443,
                            proto = "tcp",
                            service = "https",
                            version = string.format("Satellite WAN Gateway (%s | Key: %s | %s | %d Peers)", portSpeed, key, isOnline and "MESH ONLINE" or "STANDBY", peers)
                        })
                        table.insert(services, {
                            port = 1194,
                            proto = "udp",
                            service = "openvpn",
                            version = "L3 Wireless Tunnel Router (AES-256-GCM)"
                        })
                    end

                    table.insert(devices, {
                        entity = dev,
                        name = dev.PrintName or (isPrinter and "Money Printer" or (isComputer and "Personal Computer" or (isSynthesizer and "Resource Fabricator" or (isUplink and "Satellite WAN Uplink" or "Network Device")))),
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
    end

    return devices
end

-- ========================================================
-- 4. WAN SATELLITE MESH & INTER-SUBNET ROUTING
-- ========================================================

GRID.Network.WANUplinks = GRID.Network.WANUplinks or {}

-- Recalculates all active wireless WAN mesh groups
function GRID.Network.RecalculateWANMesh()
    local cleanList = {}
    local keyGroups = {}

    for _, uplink in ipairs(GRID.Network.WANUplinks) do
        if IsValid(uplink) and uplink:GetClass() == "grid_wan_uplink" then
            table.insert(cleanList, uplink)
            local key = uplink:GetEncryptionKey()
            if key and key ~= "" then
                local normKey = string.Trim(string.upper(key))
                keyGroups[normKey] = keyGroups[normKey] or {}
                table.insert(keyGroups[normKey], uplink)
            end
        end
    end

    GRID.Network.WANUplinks = cleanList

    for _, group in pairs(keyGroups) do
        local totalInGroup = #group
        local isOnline = (totalInGroup >= 2)
        local peerCount = math.max(0, totalInGroup - 1)

        for _, uplink in ipairs(group) do
            uplink:SetIsOnline(isOnline)
            uplink:SetLinkedPeerCount(peerCount)
            if uplink.UpdateWireOutputs then
                uplink:UpdateWireOutputs()
            end
        end
    end

    -- Mark orphaned uplinks (key has only 1 entity or empty)
    for _, uplink in ipairs(cleanList) do
        local key = uplink:GetEncryptionKey()
        local normKey = key and string.Trim(string.upper(key)) or ""
        if normKey == "" or not keyGroups[normKey] or #keyGroups[normKey] < 2 then
            uplink:SetIsOnline(false)
            uplink:SetLinkedPeerCount(0)
            if uplink.UpdateWireOutputs then
                uplink:UpdateWireOutputs()
            end
        end
    end
end

-- Finds the active WAN uplink connected to a switch or its SFP-trunked broadcast domain (if any)
function GRID.Network.GetUplinkForSwitch(switchEnt, visited)
    if not isSwitch(switchEnt) then return nil end
    if not switchEnt.Ports then return nil end

    visited = visited or {}
    if visited[switchEnt] then return nil end
    visited[switchEnt] = true

    -- 1. Check direct ports on this switch first
    for portNum = 1, 3 do
        local pData = switchEnt.Ports[portNum]
        if pData then
            local dev = pData.device
            if IsValid(dev) and (dev:GetClass() == "grid_wan_uplink" or dev.IsWANUplink) then
                return dev
            end
        end
    end

    -- 2. Traverse SFP-trunked switches in the broadcast domain (Ports 3 and 4)
    for portNum = 3, 4 do
        local pData = switchEnt.Ports[portNum]
        if pData then
            local otherSw = pData.device or pData.switch
            if isSwitch(otherSw) and not visited[otherSw] then
                local found = GRID.Network.GetUplinkForSwitch(otherSw, visited)
                if IsValid(found) then
                    return found
                end
            end
        end
    end

    return nil
end

-- Finds any Personal Computer actively running the Cloud Botnet C2 daemon in the switch's broadcast domain
function GRID.Network.GetActiveBotnetForSwitch(switchEnt)
    if not IsValid(switchEnt) then return nil end
    local devices = GRID.Network.GetBroadcastDomain(switchEnt)
    for _, dev in ipairs(devices) do
        if dev.type == "computer" and IsValid(dev.entity) then
            if dev.entity.GetBotnetActive and dev.entity:GetBotnetActive() then
                return dev.entity
            end
        end
    end
    return nil
end

-- Retrieves devices in peer subnets reachable across an active WAN mesh
function GRID.Network.GetWANMeshDevices(switchEnt)
    local uplink = GRID.Network.GetUplinkForSwitch(switchEnt)
    if not IsValid(uplink) or not uplink:GetIsOnline() then
        return {}
    end

    local myKey = string.Trim(string.upper(uplink:GetEncryptionKey() or ""))
    if myKey == "" then return {} end

    local remoteDevices = {}
    local visitedSwitches = { [switchEnt] = true }

    for _, otherUplink in ipairs(GRID.Network.WANUplinks or {}) do
        if IsValid(otherUplink) and otherUplink ~= uplink then
            local otherKey = string.Trim(string.upper(otherUplink:GetEncryptionKey() or ""))
            if otherKey == myKey then
                local peerSwitch = otherUplink:GetConnectedSwitch()
                if IsValid(peerSwitch) and not visitedSwitches[peerSwitch] then
                    visitedSwitches[peerSwitch] = true
                    local peerDevices = GRID.Network.GetBroadcastDomain(peerSwitch)
                    for _, devData in ipairs(peerDevices) do
                        devData.isRemoteWAN = true
                        devData.viaWAN = otherUplink
                        table.insert(remoteDevices, devData)
                    end
                end
            end
        end
    end

    return remoteDevices
end

-- Retrieves all reachable devices (Local Broadcast Domain + Remote WAN Mesh Subnets)
function GRID.Network.GetAllReachableDevices(switchEnt)
    if not IsValid(switchEnt) then return {} end
    local localDevs = GRID.Network.GetBroadcastDomain(switchEnt)
    local wanDevs = GRID.Network.GetWANMeshDevices(switchEnt)

    local all = {}
    for _, d in ipairs(localDevs) do table.insert(all, d) end
    for _, d in ipairs(wanDevs) do table.insert(all, d) end
    return all
end

-- Searches for any host by IP address reachable from a switch
function GRID.Network.FindReachableDeviceByIP(switchEnt, targetIP)
    if not targetIP or targetIP == "" then return nil end
    local devices = GRID.Network.GetAllReachableDevices(switchEnt)
    for _, dev in ipairs(devices) do
        if dev.ip == targetIP then
            return dev
        end
    end
    return nil
end

-- Scans wireless spectrum for active WAN transmitters within maximum sniffing distance (for airmon / wan scan)
function GRID.Network.GetActiveWANSpectrum(origin, maxDist)
    maxDist = maxDist or (GRID.Config and GRID.Config.WLANSniffMaxDistance) or 2500

    local originPos = nil
    local localUplink = nil

    if isvector(origin) then
        originPos = origin
    elseif isentity(origin) and IsValid(origin) then
        if origin:IsPlayer() then
            originPos = origin:GetPos()
        elseif origin:GetClass() == "weapon_grid_cyberphone" then
            local owner = origin:GetOwner()
            originPos = (IsValid(owner) and owner:GetPos()) or origin:GetPos()
        elseif origin:GetClass() == "grid_computer" then
            originPos = origin:GetPos()
            local sw = origin:GetConnectedSwitch()
            if IsValid(sw) and GRID.Network.GetUplinkForSwitch then
                localUplink = GRID.Network.GetUplinkForSwitch(sw)
            end
        else
            originPos = origin:GetPos()
        end
    end

    local spectrum = {}
    for _, uplink in ipairs(GRID.Network.WANUplinks or {}) do
        if IsValid(uplink) then
            local upPos = uplink:GetPos()
            local dist = originPos and originPos:Distance(upPos) or nil

            -- If the scanner terminal switch has an uplink dish, reception can route through its antenna
            if dist and IsValid(localUplink) and localUplink ~= uplink then
                dist = math.min(dist, localUplink:GetPos():Distance(upPos))
            end

            -- Filter out transmitters beyond maximum WLAN sniffing distance
            if not dist or dist <= maxDist then
                local sw = uplink:GetConnectedSwitch()
                local subnet = IsValid(sw) and (sw.GetSubnetID and sw:GetSubnetID() or 1) or 0
                local key = uplink:GetEncryptionKey() or "NONE"
                local bssid = string.format("00:50:C2:%02X:%02X:%02X", (uplink:EntIndex() * 13) % 256, subnet % 256, (uplink:EntIndex() * 7) % 256)
                local channel = ((uplink:EntIndex() * 3) % 11) + 1

                -- Calculate realistic dynamic RSSI based on physical distance (approx -30 dBm up-close to -88 dBm at boundary)
                local rssi
                if dist then
                    local fraction = math.Clamp(dist / maxDist, 0, 1)
                    rssi = math.floor(-32 - (fraction * 56) + math.random(-2, 2))
                else
                    rssi = -1 * math.random(35, 65)
                end

                local botnetPC = IsValid(sw) and GRID.Network.GetActiveBotnetForSwitch and GRID.Network.GetActiveBotnetForSwitch(sw) or nil
                local hasBotnet = IsValid(botnetPC)

                table.insert(spectrum, {
                    entity = uplink,
                    bssid = bssid,
                    ssid = "GRID-SAT-WAN-" .. string.sub(key, 1, 4) .. "***",
                    fullKey = key,
                    channel = channel,
                    rssi = rssi,
                    dist = dist and math.floor(dist) or 0,
                    encryption = "WPA3-ENT-AES256",
                    isOnline = uplink:GetIsOnline(),
                    peers = uplink:GetLinkedPeerCount() or 0,
                    subnet = subnet,
                    hasBotnet = hasBotnet
                })
            end
        end
    end

    -- Sort by signal strength (strongest RSSI first)
    table.sort(spectrum, function(a, b)
        return (a.rssi or -100) > (b.rssi or -100)
    end)

    return spectrum
end
