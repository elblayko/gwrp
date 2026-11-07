--[[
    entities/entities/grid_computer/init.lua
    GridRP Personal Computer Server Logic & Terminal Execution Engine
    Author: Juicebox
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local BotnetCloudTargets = {
    { name = "Apex Financial Cloud",      ip = "45.33.102.18",    vector = "OAuth Token Replay" },
    { name = "Meridian Crypto Custodian", ip = "198.51.100.44",   vector = "Hot-Wallet API Drain" },
    { name = "Solstice Offshore Ledger",  ip = "203.0.113.89",    vector = "SQLi Wire Transfer" },
    { name = "Kestrel Defense Payroll",   ip = "91.198.174.192",  vector = "Credential Stuffing" },
    { name = "Vanguard MedTech Vault",    ip = "185.199.108.153", vector = "Ransomware Extortion" },
    { name = "NovaBank SWIFT Relay",      ip = "104.16.132.229",  vector = "BGP Session Hijack" },
    { name = "Synthetix DeFi Liquidity",  ip = "172.67.188.91",   vector = "Smart-Contract Flash Siphon" },
    { name = "Helios Logistics ERP",      ip = "151.101.1.69",    vector = "Invoice Redirect Payload" },
    { name = "Aegis Insurance Treasury",  ip = "34.117.59.81",    vector = "Automated Claim Forgery" },
    { name = "Cobalt Exchange Cold-Link", ip = "52.84.228.114",   vector = "SSH Key Exfiltration" }
}

local BOTNET_TICK_INTERVAL = 20.0

function ENT:Initialize()
    self:SetModel(self.ComputerModel or "models/props/cs_office/computer.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    self:SetIPAddress("")
    self:SetAssignedPort(0)
    self:SetConnectedSwitch(NULL)
    self:SetBotnetActive(false)
    self:SetBotnetYield(0)
    self:SetBotnetTotalEarned(0)
    self:SetBotnetOperator(NULL)

    self.BotnetWANKey = ""
    self.BotnetCyclesCompleted = 0
    self.BotnetBuffer = 0
    self:SetNWInt("GRID_BotnetBuffer", 0)
end

function ENT:PushTerminalLines(ply, lines)
    if not IsValid(ply) or not ply:IsPlayer() or not lines or #lines == 0 then return end
    net.Start("GRID_ComputerCommandResponse")
    net.WriteEntity(self)
    net.WriteString("botnet_stream")
    net.WriteUInt(math.min(#lines, 250), 8)
    for i = 1, math.min(#lines, 250) do
        net.WriteString(lines[i].text or "")
        net.WriteString(lines[i].color or "white")
    end
    net.Send(ply)
end

function ENT:GetBroadcastDomainPrinters()
    local sw = self:GetConnectedSwitch()
    if not IsValid(sw) or not GRID.Network or not GRID.Network.GetBroadcastDomain then
        return {}
    end

    local devices = GRID.Network.GetBroadcastDomain(sw)
    local printers = {}
    for _, dev in ipairs(devices) do
        if dev.type == "printer" and IsValid(dev.entity) then
            table.insert(printers, dev.entity)
        end
    end

    table.sort(printers, function(a, b)
        return (a.PrintAmount or 4) > (b.PrintAmount or 4)
    end)

    return printers
end

function ENT:CalculateBotnetYield(operator)
    local printers = self:GetBroadcastDomainPrinters()
    local maxNodes = (GRID.Config and GRID.Config.BotnetMaxCountedPrinters) or 3
    local baseTrickle = (GRID.Config and GRID.Config.BotnetBaseTrickle) or 2
    local yieldMult = (GRID.Config and GRID.Config.BotnetPrinterYieldMultiplier) or (1 / 3)
    local engMult = (GRID.Config and GRID.Config.BotnetEngineerBonusMultiplier) or 1.25

    local countedPrinters = math.min(#printers, maxNodes)
    local totalBasePrinterYield = 0

    for i = 1, countedPrinters do
        local p = printers[i]
        totalBasePrinterYield = totalBasePrinterYield + (p.PrintAmount or 4)
    end

    -- Base trickle when 0 printers connected; scaled by BotnetPrinterYieldMultiplier when printers are connected
    local yield = baseTrickle
    if countedPrinters > 0 then
        yield = math.max(baseTrickle, math.Round(totalBasePrinterYield * yieldMult))
    end

    local op = IsValid(operator) and operator or self:GetBotnetOperator()
    local isEng = IsValid(op) and op.GetJob and (op:GetJob() == "cyber_engineer")
    if isEng then
        yield = math.ceil(yield * engMult)
    end

    return yield, #printers, countedPrinters, isEng
end

function ENT:StopBotnet(reason)
    local timerName = "GRID_BotnetTick_" .. self:EntIndex()
    timer.Remove(timerName)

    local wasActive = self:GetBotnetActive()
    local operator = self:GetBotnetOperator()

    self:SetBotnetActive(false)
    self:SetBotnetYield(0)
    self.BotnetWANKey = ""

    if wasActive then
        self:EmitSound("buttons/button10.wav", 65, 95)
        if reason and IsValid(operator) and operator:IsPlayer() then
            GRID.Notify(operator, "Botnet C2 Halted: " .. reason, NOTIFY_ERROR)
            self:PushTerminalLines(operator, {
                { text = string.format("[!] [BOTNET-C2] DAEMON HALTED: %s", reason), color = "red" }
            })
        end
    end
end

function ENT:RefreshBotnetState()
    if not self:GetBotnetActive() then return end

    local sw = self:GetConnectedSwitch()
    if not IsValid(sw) then
        self:StopBotnet("Ethernet link to L3 Switch disconnected.")
        return
    end

    local uplink = GRID.Network and GRID.Network.GetUplinkForSwitch and GRID.Network.GetUplinkForSwitch(sw)
    if not IsValid(uplink) then
        self:StopBotnet("Satellite WAN Uplink disconnected from broadcast domain.")
        return
    end

    local curKey = string.Trim(string.upper(uplink:GetEncryptionKey() or ""))
    if curKey == "" or (self.BotnetWANKey ~= "" and curKey ~= self.BotnetWANKey) then
        self:StopBotnet("Satellite WAN encryption key changed -- C2 tunnel dropped.")
        return
    end

    local operator = self:GetBotnetOperator()
    if not IsValid(operator) then
        local owner = self:GetOwnerPlayer()
        if IsValid(owner) then
            operator = owner
            self:SetBotnetOperator(owner)
        else
            self:StopBotnet("Operator session disconnected.")
            return
        end
    end

    local newYield = self:CalculateBotnetYield(operator)
    self:SetBotnetYield(newYield)
end

function ENT:BotnetCycle()
    if not self:GetBotnetActive() then return end

    self:RefreshBotnetState()
    if not self:GetBotnetActive() then return end

    local operator = self:GetBotnetOperator()
    if not IsValid(operator) or not operator:IsPlayer() then
        self:StopBotnet("Operator session offline.")
        return
    end

    local yield, totalPrinters = self:CalculateBotnetYield(operator)
    self:SetBotnetYield(yield)

    self.BotnetBuffer = (self.BotnetBuffer or 0) + yield
    self:SetNWInt("GRID_BotnetBuffer", self.BotnetBuffer)
    local newTotal = (self:GetBotnetTotalEarned() or 0) + yield
    self:SetBotnetTotalEarned(newTotal)
    self.BotnetCyclesCompleted = (self.BotnetCyclesCompleted or 0) + 1

    self:EmitSound("ambient/levels/labs/coinslot1.wav", 58, 115)

    local target = BotnetCloudTargets[math.random(1, #BotnetCloudTargets)]
    self:PushTerminalLines(operator, {
        {
            text = string.format(
                "[+] [BOTNET-C2] Cycle #%d | Breached %s (%s) via %s -> Exfiltrated +$%s (%d Printer Node%s)",
                self.BotnetCyclesCompleted,
                target.name,
                target.ip,
                target.vector,
                string.Comma(yield),
                totalPrinters,
                totalPrinters == 1 and "" or "s"
            ),
            color = "green"
        }
    })
end

function ENT:StartBotnet(ply)
    local sw = self:GetConnectedSwitch()
    if not IsValid(sw) then
        return false, "Interface eth0 has NO CARRIER. Wire this computer to an L3 Switch first."
    end

    local uplink = GRID.Network and GRID.Network.GetUplinkForSwitch and GRID.Network.GetUplinkForSwitch(sw)
    if not IsValid(uplink) then
        return false,
            "No Satellite WAN Uplink detected on this broadcast domain. Wire a WAN Uplink dish to your switch to reach cloud targets."
    end

    local existingBotnet = GRID.Network and GRID.Network.GetActiveBotnetForSwitch and
    GRID.Network.GetActiveBotnetForSwitch(sw)
    if IsValid(existingBotnet) and existingBotnet ~= self then
        return false,
            string.format("A Cloud Botnet C2 daemon is already running on this network (%s).",
                existingBotnet:GetIPAddress() or "peer terminal")
    end

    local wanKey = string.Trim(string.upper(uplink:GetEncryptionKey() or ""))
    if wanKey == "" then
        return false, "Satellite WAN Uplink has no valid encryption key configured."
    end

    self.BotnetWANKey = wanKey
    self.BotnetCyclesCompleted = 0
    self.BotnetBuffer = 0
    self:SetNWInt("GRID_BotnetBuffer", 0)
    self:SetBotnetOperator(ply)
    self:SetBotnetActive(true)

    local yield, totalPrinters, countedPrinters, isEng = self:CalculateBotnetYield(ply)
    self:SetBotnetYield(yield)

    self:EmitSound("ambient/machines/thumper_startup1.wav", 65, 130)

    local tickInterval = (GRID.Config and GRID.Config.BotnetTickInterval) or BOTNET_TICK_INTERVAL
    local timerName = "GRID_BotnetTick_" .. self:EntIndex()
    timer.Create(timerName, tickInterval, 0, function()
        if not IsValid(self) then
            timer.Remove(timerName)
            return
        end
        self:BotnetCycle()
    end)

    return true, yield, totalPrinters, countedPrinters, isEng, uplink
end

function ENT:DisconnectFromSwitch()
    if self:GetBotnetActive() then
        self:StopBotnet("Ethernet cable unplugged from L3 Switch.")
    end

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
    end
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if not activator:Alive() then return end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[activator] or 0) > now then return end
    self.NextUsePerPlayer[activator] = now + 0.4

    local sw = self:GetConnectedSwitch()
    local ip = self:GetIPAddress() or ""
    local isNet = IsValid(sw)

    self:EmitSound("buttons/button14.wav", 65, 110)

    net.Start("GRID_OpenComputerOS")
    net.WriteEntity(self)
    net.WriteEntity(sw)
    net.WriteString(ip)
    net.WriteBool(isNet)
    net.Send(activator)
end

function ENT:OnRemove()
    if (self.BotnetBuffer or 0) > 0 and GRID.Economy and GRID.Economy.SpawnCashStack then
        GRID.Economy.SpawnCashStack(self:GetPos() + Vector(0, 0, 15), self.BotnetBuffer)
        self.BotnetBuffer = 0
    end
    self:DisconnectFromSwitch()
end

-- Server Terminal Command Processor
net.Receive("GRID_RunComputerCommand", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GRID.CheckRateLimit(ply, "computer_cmd", 8) then return end

    local computer = net.ReadEntity()
    local rawCmd = string.Trim(net.ReadString() or "")

    if not IsValid(computer) then return end
    local isPhone = computer:GetClass() == "weapon_grid_cyberphone"
    if computer:GetClass() ~= "grid_computer" and not isPhone then return end

    if isPhone then
        if computer:GetOwner() ~= ply then return end
    else
        if ply:EyePos():DistToSqr(computer:GetPos()) > (220 * 220) then
            GRID.Notify(ply, "You are too far from the computer terminal!", NOTIFY_ERROR)
            return
        end
    end

    local sw = nil
    local isConnected = false
    local localIP = ""
    local subnet = 0
    local scanOrigin = isPhone and ply or computer
    local maxSniffDist = (GRID.Config and GRID.Config.WLANSniffMaxDistance) or 2500

    if isPhone then
        local wanKey = string.Trim(string.upper(computer:GetAssociatedWANKey() or ""))
        local maxRangeSqr = maxSniffDist * maxSniffDist
        if wanKey ~= "" then
            for _, uplink in ipairs(GRID.Network.WANUplinks or {}) do
                if IsValid(uplink) and string.Trim(string.upper(uplink:GetEncryptionKey() or "")) == wanKey then
                    if ply:GetPos():DistToSqr(uplink:GetPos()) <= maxRangeSqr then
                        local pSw = uplink:GetConnectedSwitch()
                        if IsValid(pSw) then
                            sw = pSw
                            isConnected = true
                            subnet = GRID.Network.GetSubnetID(sw)
                            break
                        end
                    end
                end
            end
        end
        localIP = computer:GetIPAddress() ~= "" and computer:GetIPAddress() or "10.84.1.25"
    else
        sw = computer:GetConnectedSwitch()
        isConnected = IsValid(sw)
        localIP = computer:GetIPAddress() or ""
        subnet = isConnected and (GRID.Network and GRID.Network.GetSubnetID(sw) or sw:GetSubnetID()) or 0
    end

    local isEngineer = (ply.GetJob and ply:GetJob() == "cyber_engineer")

    local parts = string.Explode(" ", rawCmd)
    local cmd = string.lower(parts[1] or "")
    local arg1 = string.lower(parts[2] or "")

    local responseLines = {}

    if cmd == "nmap" then
        if not isConnected then
            table.insert(responseLines, { text = "Starting Nmap 7.94 ( https://nmap.org )", color = "muted" })
            if isPhone then
                local wanKey = computer:GetAssociatedWANKey() or ""
                if wanKey ~= "" then
                    table.insert(responseLines,
                        {
                            text = string.format("nmap: SIGNAL LOST: Out of range of WAN transmitter '%s' (Max: %du).",
                                wanKey, maxSniffDist),
                            color = "red"
                        })
                    table.insert(responseLines,
                        {
                            text = "Move closer to an active Satellite WAN Uplink to re-establish wireless link.",
                            color =
                            "yellow"
                        })
                else
                    table.insert(responseLines,
                        { text = "nmap: No active wireless WAN mesh association on wlan0.", color = "yellow" })
                    table.insert(responseLines,
                        {
                            text = "Tip: Type 'airmon' to scan wireless airspace, then 'wan connect <key>'.",
                            color =
                            "cyan"
                        })
                end
            else
                table.insert(responseLines,
                    { text = "nmap: FATAL: No active network interface found on eth0.", color = "red" })
                table.insert(responseLines,
                    { text = "Interface eth0 has NO CARRIER (Physical copper cable unplugged).", color = "yellow" })
                table.insert(responseLines,
                    { text = "Tip: Use Network Wiring Tool to link this computer to an L3 Switch.", color = "muted" })
            end
        else
            local devices = GRID.Network and GRID.Network.GetAllReachableDevices(sw) or {}
            local gatewayIP = GRID.Network and GRID.Network.GetGatewayIP(sw) or string.format("192.168.%d.1", subnet)
            local targetSubnet = string.format("192.168.%d.0/24", subnet)

            table.insert(responseLines,
                {
                    text = string.format("Starting Nmap 7.94 ( https://nmap.org ) at %s", os.date("%Y-%m-%d %H:%M:%S")),
                    color =
                    "cyan"
                })
            table.insert(responseLines,
                {
                    text = string.format("Initiating ARP/L3 Routing Scan on %s and active WAN tunnels", targetSubnet),
                    color =
                    "muted"
                })
            table.insert(responseLines,
                {
                    text = string.format("Completed Scan: Discovered %d live reachable devices.", #devices),
                    color =
                    "green"
                })
            table.insert(responseLines,
                { text = "----------------------------------------------------------------------", color = "dark" })

            local liveCount = 0
            for _, dev in ipairs(devices) do
                liveCount = liveCount + 1
                local isLocal = (dev.entity == computer)
                local hostLabel = isLocal and " (this terminal [localhost])" or
                    (dev.isRemoteWAN and " [Routed via WAN Mesh]" or "")

                table.insert(responseLines,
                    {
                        text = string.format("Nmap scan report for %s (%s)%s", dev.ip, dev.name, hostLabel),
                        color = dev
                            .isRemoteWAN and "cyan" or "highlight"
                    })
                table.insert(responseLines,
                    {
                        text = string.format("Host is UP (0.00%02ds latency). MAC: %s", math.random(12, 65), dev.mac),
                        color =
                        "white"
                    })

                if dev.type == "printer" then
                    local ent = dev.entity
                    local eff = (IsValid(ent) and ent.GetEfficiency) and ent:GetEfficiency() or 60
                    local temp = (IsValid(ent) and ent.GetTemperature) and ent:GetTemperature() or 20
                    local uv = (IsValid(ent) and ent.GetHasUndervolt and ent:GetHasUndervolt()) and " [Undervolted]" or
                        ""
                    table.insert(responseLines, { text = "PORT     STATE SERVICE      VERSION", color = "muted" })
                    table.insert(responseLines,
                        {
                            text = string.format("8080/tcp OPEN  http-proxy   MoneyFab Daemon (%d%% eff, %dC)%s", eff,
                                temp, uv),
                            color = "green"
                        })
                elseif dev.type == "switch" then
                    table.insert(responseLines, { text = "PORT     STATE SERVICE      VERSION", color = "muted" })
                    table.insert(responseLines,
                        { text = "22/tcp   OPEN  ssh          Switch-OS L3.1 (OpenSSH 8.9)", color = "cyan" })
                    table.insert(responseLines,
                        { text = "80/tcp   OPEN  http         Switch Management Web Console", color = "cyan" })
                elseif dev.type == "computer" then
                    local ent = dev.entity
                    local isBotnet = IsValid(ent) and ent.GetBotnetActive and ent:GetBotnetActive()
                    table.insert(responseLines, { text = "PORT     STATE SERVICE      VERSION", color = "muted" })
                    table.insert(responseLines,
                        { text = "23/tcp   OPEN  telnet       CyberDeck BSD Terminal Daemon", color = "blue" })
                    if isBotnet then
                        table.insert(responseLines,
                            {
                                text = string.format(
                                    "6667/tcp OPEN  irc-c2       Cloud Botnet C2 Daemon (+$%d/20s) [BOTNET ACTIVE]",
                                    ent.GetBotnetYield and ent:GetBotnetYield() or 0),
                                color = "highlight"
                            })
                    end
                elseif dev.type == "synthesizer" then
                    local ent = dev.entity
                    local eff = (IsValid(ent) and ent.GetEfficiency) and ent:GetEfficiency() or 60
                    local temp = (IsValid(ent) and ent.GetTemperature) and ent:GetTemperature() or 20
                    table.insert(responseLines, { text = "PORT     STATE SERVICE      VERSION", color = "muted" })
                    table.insert(responseLines,
                        {
                            text = string.format(
                                "502/tcp  OPEN  modbus       Modbus/TCP OT Synthesizer PLC (%d%% eff, %dC)", eff, temp),
                            color =
                            "yellow"
                        })
                    table.insert(responseLines,
                        { text = "4840/tcp OPEN  opcua        OPC-UA Material Fabrication Service", color = "yellow" })
                elseif dev.type == "wan_uplink" then
                    table.insert(responseLines, { text = "PORT     STATE SERVICE      VERSION", color = "muted" })
                    table.insert(responseLines,
                        {
                            text = "443/tcp  OPEN  https        Satellite WAN Mesh Gateway (WPA3-Enterprise)",
                            color =
                            "cyan"
                        })
                    table.insert(responseLines,
                        { text = "1194/udp OPEN  openvpn      L3 Wireless Tunnel Router (AES-256-GCM)", color = "cyan" })
                end
                table.insert(responseLines, { text = " ", color = "muted" })
            end

            table.insert(responseLines,
                { text = "----------------------------------------------------------------------", color = "dark" })
            table.insert(responseLines,
                {
                    text = string.format("Nmap done: %d IP addresses (%d hosts up) scanned in 0.42 seconds.", liveCount,
                        liveCount),
                    color = "cyan"
                })
        end
    elseif cmd == "ifconfig" or cmd == "ip" then
        if isPhone then
            local wanKey = computer:GetAssociatedWANKey() or ""
            local statusStr = (wanKey ~= "" and isConnected) and
                string.format("ASSOCIATED (Key: %s | Gateway: 192.168.%d.1)", wanKey, subnet) or
                "STANDALONE (No mesh association)"
            table.insert(responseLines,
                { text = "wlan0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500", color = "white" })
            table.insert(responseLines,
                { text = string.format("        inet %s  netmask 255.255.0.0", localIP), color = "green" })
            table.insert(responseLines,
                { text = "        ether 02:42:0a:54:01:19  txqueuelen 1000  (Wireless 802.11ax)", color = "muted" })
            table.insert(responseLines,
                { text = "        wireless: " .. statusStr, color = isConnected and "cyan" or "yellow" })
        elseif not isConnected then
            table.insert(responseLines, { text = "eth0: flags=4098<BROADCAST,MULTICAST>  mtu 1500", color = "white" })
            table.insert(responseLines,
                { text = "        ether 02:42:c0:00:00:00  txqueuelen 1000  (Ethernet)", color = "muted" })
            table.insert(responseLines, { text = "        status: NO CARRIER (Cable unplugged)", color = "red" })
        else
            local mac = GRID.Network and GRID.Network.FormatMAC(computer, subnet, 10 + (computer:GetAssignedPort() or 1)) or
                "02:42:C0:00:00:00"
            table.insert(responseLines,
                { text = "eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500", color = "white" })
            table.insert(responseLines,
                {
                    text = string.format("        inet %s  netmask 255.255.255.0  broadcast 192.168.%d.255", localIP,
                        subnet),
                    color = "green"
                })
            table.insert(responseLines,
                { text = string.format("        ether %s  txqueuelen 1000  (Ethernet)", mac), color = "muted" })
            table.insert(responseLines,
                {
                    text = string.format("        gateway: 192.168.%d.1 (Switch on Port %d)", subnet,
                        computer:GetAssignedPort() or 0),
                    color = "cyan"
                })

            local uplink = GRID.Network and GRID.Network.GetUplinkForSwitch(sw)
            if IsValid(uplink) then
                local wanKey = uplink:GetEncryptionKey() or "NONE"
                local isOnline = uplink:GetIsOnline()
                local peers = uplink:GetLinkedPeerCount() or 0
                local wanStatus = isOnline and string.format("TUNNEL UP (%d Peers)", peers) or "STANDBY"
                table.insert(responseLines,
                    {
                        text = "wan0: flags=4163<UP,POINTOPOINT,RUNNING>  mtu 1420 (Satellite WAN Gateway)",
                        color =
                        "white"
                    })
                table.insert(responseLines,
                    {
                        text = string.format("        inet %s  wan_key %s  status: %s",
                            uplink:GetIPAddress() ~= "" and uplink:GetIPAddress() or "Pending", wanKey, wanStatus),
                        color =
                            isOnline and "cyan" or "yellow"
                    })
            end
        end
    elseif cmd == "ping" then
        if not isConnected then
            table.insert(responseLines,
                { text = "ping: connect: Network is unreachable (Interface is down).", color = "red" })
        elseif arg1 == "" then
            table.insert(responseLines, { text = "Usage: ping <ip_address>", color = "yellow" })
        else
            local devices = GRID.Network and GRID.Network.GetAllReachableDevices(sw) or {}
            local found = false
            for _, dev in ipairs(devices) do
                if dev.ip == arg1 then
                    found = true
                    break
                end
            end

            table.insert(responseLines,
                { text = string.format("PING %s (%s) 56(84) bytes of data.", arg1, arg1), color = "muted" })
            if found then
                for i = 1, 3 do
                    table.insert(responseLines,
                        {
                            text = string.format("64 bytes from %s: icmp_seq=%d ttl=64 time=0.%02d ms", arg1, i,
                                math.random(15, 75)),
                            color = "green"
                        })
                end
                table.insert(responseLines,
                    {
                        text = string.format(
                            "--- %s ping statistics --- 3 packets transmitted, 3 received, 0%% packet loss", arg1),
                        color =
                        "cyan"
                    })
            else
                table.insert(responseLines,
                    { text = string.format("From %s icmp_seq=1 Destination Host Unreachable", localIP), color = "red" })
                table.insert(responseLines,
                    {
                        text = string.format(
                            "--- %s ping statistics --- 3 packets transmitted, 0 received, 100%% packet loss", arg1),
                        color =
                        "yellow"
                    })
            end
        end

        -- Wireless Airspace Reconnaissance
    elseif cmd == "airmon" or cmd == "airodump" or (cmd == "wan" and (arg1 == "scan" or arg1 == "recon")) then
        local spectrum = GRID.Network and GRID.Network.GetActiveWANSpectrum and
            GRID.Network.GetActiveWANSpectrum(scanOrigin, maxSniffDist) or {}
        table.insert(responseLines,
            {
                text = string.format("[*] Airmon-ng 1.7 - Wireless Airspace Reconnaissance (Max Range: %du)",
                    maxSniffDist),
                color =
                "cyan"
            })
        table.insert(responseLines,
            {
                text = string.format(
                    "[+] Sniffing 2.4/5.8GHz Satellite Relay bands... Found %d active signal(s) in range.", #spectrum),
                color =
                "muted"
            })
        table.insert(responseLines,
            { text = "--------------------------------------------------------------------------------", color = "dark" })
        table.insert(responseLines,
            { text = "BSSID              PWR  DIST   CH  ENC      SUBNET          SSID", color = "highlight" })

        if #spectrum == 0 then
            table.insert(responseLines,
                {
                    text = string.format("No active satellite WAN transmitters detected within %du.", maxSniffDist),
                    color =
                    "yellow"
                })
            table.insert(responseLines,
                { text = "Move closer to suspected transmitter locations to sniff wireless packets.", color = "muted" })
        else
            for _, sig in ipairs(spectrum) do
                local subStr = sig.subnet > 0 and string.format("192.168.%d.0/24", sig.subnet) or "Unlinked"
                local botTag = sig.hasBotnet and " [BOTNET ACTIVE]" or ""
                table.insert(responseLines,
                    {
                        text = string.format("%-18s %4ddBm %4du  %2d  WPA3-ENT %-15s %s%s", sig.bssid, sig.rssi,
                            sig.dist or 0, sig.channel, subStr, sig.ssid, botTag),
                        color = sig.hasBotnet and "highlight" or "green"
                    })
            end
        end
        table.insert(responseLines,
            { text = "--------------------------------------------------------------------------------", color = "dark" })
        table.insert(responseLines,
            { text = "Tip: Type 'wan crack <bssid>' to capture handshake & crack encryption key.", color = "muted" })
        if isPhone then
            table.insert(responseLines,
                { text = "Tip: Type 'wan connect <key>' to link handset wlan0 interface to mesh.", color = "muted" })
        end

        -- Wireless Handshake Cracking
    elseif cmd == "wan" and (arg1 == "crack" or arg1 == "brute") then
        local targetBSSID = string.upper(parts[3] or "")
        if targetBSSID == "" then
            table.insert(responseLines, { text = "Usage: wan crack <bssid>", color = "yellow" })
            table.insert(responseLines,
                { text = "Run 'airmon' to view active transmitter BSSIDs within range.", color = "muted" })
        else
            local spectrum = GRID.Network and GRID.Network.GetActiveWANSpectrum and
                GRID.Network.GetActiveWANSpectrum(scanOrigin, maxSniffDist) or {}
            local matchedSig = nil
            for _, sig in ipairs(spectrum) do
                if string.upper(sig.bssid) == targetBSSID or string.find(string.upper(sig.ssid), targetBSSID) then
                    matchedSig = sig
                    break
                end
            end

            if not matchedSig then
                table.insert(responseLines,
                    {
                        text = string.format("[-] crack: No active transmitter found matching '%s' within range (%du).",
                            targetBSSID, maxSniffDist),
                        color = "red"
                    })
                table.insert(responseLines,
                    { text = "Transmitter may be powered off, offline, or beyond sniffing distance.", color = "muted" })
            else
                table.insert(responseLines,
                    {
                        text = string.format(
                            "[*] Initiating deauthentication attack against %s (Signal: %ddBm, Distance: %du)...",
                            matchedSig.bssid, matchedSig.rssi, matchedSig.dist or 0),
                        color = "muted"
                    })
                table.insert(responseLines, { text = "[+] WPA3/AES 4-way handshake captured!", color = "green" })
                table.insert(responseLines,
                    { text = "[*] Running dictionary attack against GPU wordlist...", color = "muted" })
                table.insert(responseLines,
                    {
                        text = string.format("[+] KEY CRACKED! Plaintext Encryption Key: [ %s ]", matchedSig.fullKey),
                        color =
                        "highlight"
                    })
                table.insert(responseLines,
                    {
                        text = string.format("[*] Associated Subnet: 192.168.%d.0/24 (%d Mesh Peers)", matchedSig.subnet,
                            matchedSig.peers),
                        color = "cyan"
                    })
            end
        end

        -- Handset Wireless Mesh Association
    elseif (cmd == "wan" or cmd == "wifi") and (arg1 == "connect" or arg1 == "link") then
        local reqKey = string.Trim(string.upper(parts[3] or ""))
        if reqKey == "" then
            table.insert(responseLines, { text = "Usage: wan connect <encryption_key>", color = "yellow" })
        elseif not isPhone then
            table.insert(responseLines,
                {
                    text =
                    "[-] Fixed terminals use copper cables. Set encryption keys directly on your physical Satellite WAN Uplink entity.",
                    color =
                    "yellow"
                })
        else
            local inRangeUplink = nil
            local closestDist = nil
            for _, uplink in ipairs(GRID.Network.WANUplinks or {}) do
                if IsValid(uplink) and string.Trim(string.upper(uplink:GetEncryptionKey() or "")) == reqKey then
                    local d = ply:GetPos():Distance(uplink:GetPos())
                    if d <= maxSniffDist and (not closestDist or d < closestDist) then
                        closestDist = d
                        inRangeUplink = uplink
                    end
                end
            end

            if not inRangeUplink then
                table.insert(responseLines,
                    {
                        text = string.format(
                            "[-] Association failed: No active WAN transmitter with key '%s' found within wireless range (%du).",
                            reqKey, maxSniffDist),
                        color = "red"
                    })
                table.insert(responseLines,
                    { text = "Move closer to the target network's Satellite WAN Uplink dish.", color = "muted" })
            else
                computer:SetAssociatedWANKey(reqKey)
                computer:SetIsConnected(true)
                local mobileIP = string.format("10.84.%d.%d", math.random(2, 50), math.random(10, 200))
                computer:SetIPAddress(mobileIP)
                table.insert(responseLines,
                    {
                        text = string.format("[+] Handset wlan0 associated with WAN mesh [ %s ] (Distance: %du)", reqKey,
                            math.floor(closestDist)),
                        color = "green"
                    })
                table.insert(responseLines,
                    { text = string.format("[+] DHCP Lease granted. Mobile IP: %s / 16", mobileIP), color = "cyan" })
                table.insert(responseLines,
                    { text = "[*] Routed WAN packets active. Type 'nmap' to scan mesh subnets.", color = "muted" })
            end
        end

        -- WAN Gateway Status
    elseif cmd == "wan" and (arg1 == "status" or arg1 == "") then
        local uplink = isConnected and GRID.Network.GetUplinkForSwitch(sw) or nil
        if isPhone then
            local key = computer:GetAssociatedWANKey() or ""
            local inRange = false
            local closestDist = nil
            if key ~= "" then
                for _, up in ipairs(GRID.Network.WANUplinks or {}) do
                    if IsValid(up) and string.Trim(string.upper(up:GetEncryptionKey() or "")) == key then
                        local d = ply:GetPos():Distance(up:GetPos())
                        if not closestDist or d < closestDist then
                            closestDist = d
                        end
                        if d <= maxSniffDist then
                            inRange = true
                        end
                    end
                end
            end

            table.insert(responseLines, { text = "=== CyberDeck Mobile Handset WAN Status ===", color = "cyan" })
            table.insert(responseLines,
                {
                    text = string.format("  Associated Mesh Key : %s", key ~= "" and key or "NONE (Standalone)"),
                    color =
                    "white"
                })
            table.insert(responseLines,
                {
                    text = string.format("  Wireless Signal     : %s",
                        (key ~= "" and inRange) and "ONLINE (In-Range)" or
                        ((key ~= "" and not inRange) and "SIGNAL LOST (Out of Range)" or "DISCONNECTED")),
                    color = (key ~= "" and inRange) and
                        "green" or "red"
                })
            if closestDist then
                table.insert(responseLines,
                    {
                        text = string.format("  Transmitter Range   : %du / %du", math.floor(closestDist), maxSniffDist),
                        color =
                            inRange and "muted" or "yellow"
                    })
            end
            table.insert(responseLines, { text = string.format("  Mobile IP Address   : %s", localIP), color = "white" })
        elseif IsValid(uplink) then
            local isOnline = uplink:GetIsOnline()
            local peers = uplink:GetLinkedPeerCount() or 0
            local key = uplink:GetEncryptionKey() or "NONE"
            table.insert(responseLines, { text = "=== Satellite WAN Gateway Status ===", color = "cyan" })
            table.insert(responseLines, { text = string.format("  Encryption Key      : %s", key), color = "white" })
            table.insert(responseLines,
                {
                    text = string.format("  Mesh Status         : %s", isOnline and "ONLINE" or "SEARCHING FOR PEERS"),
                    color =
                        isOnline and "green" or "yellow"
                })
            table.insert(responseLines,
                { text = string.format("  Linked Mesh Peers   : %d remote site(s)", peers), color = "white" })
            table.insert(responseLines,
                { text = string.format("  Local Subnet Gateway: 192.168.%d.1", subnet), color = "white" })
        else
            table.insert(responseLines,
                { text = "[-] No Satellite WAN Uplink attached to this L3 Switch.", color = "yellow" })
            table.insert(responseLines,
                {
                    text = "Tip: Plug a Satellite WAN Uplink into a copper port using the Network Wiring Tool.",
                    color =
                    "muted"
                })
        end
    elseif cmd == "use" or (cmd == "msf" and arg1 == "use") then
        if not isEngineer then
            table.insert(responseLines,
                { text = "[-] Permission Denied: Metasploit framework requires root cybersec clearance.", color = "red" })
            table.insert(responseLines, { text = "[-] Cyber Engineer security credentials required.", color = "yellow" })
            table.insert(responseLines,
                { text = "[!] Security violation logged to base security daemon.", color = "muted" })
        else
            local targetMod = (cmd == "use") and arg1 or (parts[3] or "")
            targetMod = string.lower(targetMod)

            if string.find(targetMod, "siphon") or string.find(targetMod, "cash") then
                computer.ActiveMSFModule = "siphon"
                table.insert(responseLines, { text = "[+] Loaded module: exploit/printer/cash_siphon", color = "green" })
                table.insert(responseLines,
                    {
                        text = "[*] Description : Bypasses EEPROM vault lockbox to extract all stored cash",
                        color =
                        "muted"
                    })
                table.insert(responseLines, { text = "[*] Target      : Money Printers only", color = "muted" })
                table.insert(responseLines,
                    {
                        text = "[*] Ready. Type 'msf <ip>' or 'msf run <ip>' to execute against target.",
                        color =
                        "highlight"
                    })
            elseif string.find(targetMod, "overheat") or string.find(targetMod, "thermal") or string.find(targetMod, "burn") or string.find(targetMod, "synth") or string.find(targetMod, "meltdown") then
                computer.ActiveMSFModule = "overheat"
                table.insert(responseLines, { text = "[+] Loaded module: exploit/multi/thermal_overheat", color = "red" })
                table.insert(responseLines,
                    {
                        text = "[*] Description : Overclocks thermal elements to detonate target printer or synthesizer",
                        color =
                        "muted"
                    })
                table.insert(responseLines,
                    { text = "[*] Target      : Money Printers & Material Synthesizers", color = "muted" })
                table.insert(responseLines,
                    {
                        text = "[*] Ready. Type 'msf <ip>' or 'msf run <ip>' to execute against target.",
                        color =
                        "highlight"
                    })
            else
                table.insert(responseLines, { text = "[-] Unknown module. Available modules:", color = "yellow" })
                table.insert(responseLines,
                    { text = "  use siphon    - Exploit lockbox & siphon stored cash (Printers)", color = "green" })
                table.insert(responseLines,
                    { text = "  use overheat  - Overclock & detonate target (Printers & Synthesizers)", color = "red" })
            end
        end
    elseif cmd == "msf" or cmd == "metasploit" then
        if not isEngineer then
            table.insert(responseLines,
                { text = "[-] Permission Denied: Metasploit framework requires root cybersec clearance.", color = "red" })
            table.insert(responseLines, { text = "[-] Cyber Engineer security credentials required.", color = "yellow" })
            table.insert(responseLines,
                { text = "[!] Security violation logged to base security daemon.", color = "muted" })
        else
            local targetIP = arg1
            local chosenModule = computer.ActiveMSFModule or "siphon"

            -- Support explicit module in command line: e.g. "msf siphon <ip>" or "msf overheat <ip>"
            if arg1 == "siphon" or arg1 == "cash" then
                chosenModule = "siphon"
                targetIP = parts[3] or ""
            elseif arg1 == "overheat" or arg1 == "thermal" or arg1 == "burn" or arg1 == "synth" then
                chosenModule = "overheat"
                targetIP = parts[3] or ""
            elseif (arg1 == "run" or arg1 == "exploit") and parts[3] then
                targetIP = parts[3]
            end

            if not isConnected then
                table.insert(responseLines,
                    {
                        text = "[-] msf: Exploit failed: Interface has NO CARRIER (Unplugged or no mesh association).",
                        color =
                        "red"
                    })
                table.insert(responseLines,
                    {
                        text = "    Connect this terminal to an L3 Switch or associate handset to an active WAN mesh.",
                        color =
                        "yellow"
                    })
            elseif targetIP == "" or targetIP == "help" or targetIP == "modules" or targetIP == "show" then
                table.insert(responseLines, { text = "  _|_|_|    _|_|    _|_|_|  ", color = "cyan" })
                table.insert(responseLines, { text = " _|        _|  _|  _|       ", color = "cyan" })
                table.insert(responseLines, { text = " _|  _|_|  _|_|_|  _|_|_|   ", color = "cyan" })
                table.insert(responseLines, { text = " _|    _|  _|  _|  _|       ", color = "cyan" })
                table.insert(responseLines, { text = "  _|_|_|   _|  _|  _|       ", color = "cyan" })
                table.insert(responseLines,
                    { text = "Metasploit Framework Console (MSF v6.4.12-Juicebox)", color = "white" })
                local modDisplay = chosenModule == "overheat" and "exploit/multi/thermal_overheat" or
                    "exploit/printer/cash_siphon"
                table.insert(responseLines,
                    { text = string.format("Active Module : %s", modDisplay), color = "highlight" })
                table.insert(responseLines,
                    { text = "----------------------------------------------------------------------", color = "dark" })
                table.insert(responseLines, { text = "Available Exploit Modules:", color = "white" })
                table.insert(responseLines, { text = "  1) exploit/printer/cash_siphon", color = "green" })
                table.insert(responseLines, { text = "     Syntax : msf siphon <ip> (or 'use siphon')", color = "muted" })
                table.insert(responseLines, { text = "     Target : Money Printers only", color = "muted" })
                table.insert(responseLines,
                    { text = "     Action : Drains 100% of printer cash vault into your wallet", color = "muted" })
                table.insert(responseLines, { text = "  2) exploit/multi/thermal_overheat", color = "red" })
                table.insert(responseLines,
                    { text = "     Syntax : msf overheat <ip> (or 'use overheat')", color = "muted" })
                table.insert(responseLines,
                    { text = "     Target : Money Printers & Material Synthesizers", color = "muted" })
                table.insert(responseLines,
                    {
                        text = "     Action : Overclocks thermal regulators & detonates target device in 3s",
                        color =
                        "muted"
                    })
                table.insert(responseLines,
                    { text = "----------------------------------------------------------------------", color = "dark" })
                table.insert(responseLines, { text = "MSF Console Commands:", color = "white" })
                table.insert(responseLines,
                    {
                        text = "  run <ip>         - Execute active module on target IP (or 'exploit <ip>')",
                        color =
                        "green"
                    })
                table.insert(responseLines,
                    { text = "  use siphon       - Select Cash Siphon exploit module", color = "white" })
                table.insert(responseLines,
                    { text = "  use overheat     - Select Thermal Overheat exploit module", color = "white" })
                table.insert(responseLines,
                    { text = "  show modules     - List available exploit modules", color = "white" })
                table.insert(responseLines, { text = "  help             - Display this MSF help menu", color = "white" })
                table.insert(responseLines,
                    { text = "  back / exit      - Exit Metasploit console back to bash shell", color = "muted" })
            else
                -- Check cooldown on computer entity
                local now = CurTime()
                if computer.NextExploitTime and now < computer.NextExploitTime then
                    local remaining = math.ceil(computer.NextExploitTime - now)
                    table.insert(responseLines,
                        {
                            text = string.format(
                                "[-] msf: Module cooldown active. Please wait %ds before re-arming payload.", remaining),
                            color =
                            "yellow"
                        })
                else
                    local devices = GRID.Network and GRID.Network.GetAllReachableDevices(sw) or {}
                    local targetDev = nil
                    for _, dev in ipairs(devices) do
                        if dev.ip == targetIP then
                            targetDev = dev
                            break
                        end
                    end

                    local modName = chosenModule == "overheat" and "exploit/multi/thermal_overheat" or
                        "exploit/printer/cash_siphon"
                    table.insert(responseLines,
                        { text = string.format("[*] Started reverse TCP handler on %s:4444", localIP), color = "muted" })
                    table.insert(responseLines, { text = string.format("[*] Using module: %s", modName), color = "cyan" })

                    if not targetDev then
                        table.insert(responseLines,
                            {
                                text = string.format(
                                    "[-] Exploit failed: Host %s is unreachable or not in broadcast domain.", targetIP),
                                color =
                                "red"
                            })

                        -- ========================================================
                        -- MODULE 1: CASH SIPHON (Money Printers only)
                        -- ========================================================
                    elseif chosenModule == "siphon" then
                        if targetDev.type ~= "printer" then
                            table.insert(responseLines,
                                { text = string.format("[*] Probing %s ...", targetIP), color = "muted" })
                            if targetDev.type == "synthesizer" then
                                table.insert(responseLines,
                                    {
                                        text = string.format(
                                            "[-] Exploit failed: Host %s (%s) is a Material Synthesizer and does not store cash.",
                                            targetIP, targetDev.name),
                                        color = "red"
                                    })
                                table.insert(responseLines,
                                    {
                                        text = "[-] Use 'use overheat' or 'msf overheat <ip>' to sabotage synthesizers.",
                                        color =
                                        "yellow"
                                    })
                            else
                                table.insert(responseLines,
                                    {
                                        text = string.format("[-] Exploit failed: Host %s (%s) is not a Money Printer.",
                                            targetIP, targetDev.name),
                                        color = "red"
                                    })
                            end
                        else
                            local printer = targetDev.entity
                            if not IsValid(printer) then
                                table.insert(responseLines,
                                    {
                                        text = "[-] Exploit failed: Target entity has disconnected or was removed.",
                                        color =
                                        "red"
                                    })
                            else
                                computer.NextExploitTime = now + 6 -- 6-second exploit cooldown

                                table.insert(responseLines,
                                    {
                                        text = string.format("[*] Targeting %s:8080 (%s)", targetIP, targetDev.name),
                                        color =
                                        "muted"
                                    })
                                table.insert(responseLines,
                                    { text = "[*] Sending stage (1536 bytes) to MoneyFab daemon...", color = "muted" })
                                table.insert(responseLines,
                                    {
                                        text = string.format("[+] Meterpreter session 1 opened (%s:4444 -> %s:8080)",
                                            localIP, targetIP),
                                        color = "green"
                                    })
                                table.insert(responseLines,
                                    { text = "[+] EEPROM buffer overflow triggered at 0x7FFF0042!", color = "green" })

                                local stolenCash = printer.GetStoredCash and printer:GetStoredCash() or 0
                                if stolenCash > 0 then
                                    ply:AddMoney(stolenCash)
                                    printer:SetStoredCash(0)

                                    -- Sound effects
                                    computer:EmitSound("ambient/levels/labs/coinslot1.wav", 75, 100)
                                    printer:EmitSound("ambient/energy/spark1.wav", 75, 120)
                                    printer:EmitSound("ambient/levels/labs/coinslot1.wav", 75, 80)

                                    table.insert(responseLines,
                                        {
                                            text = "[+] Lockbox override accepted. Draining cash reservoir...",
                                            color =
                                            "highlight"
                                        })
                                    table.insert(responseLines,
                                        {
                                            text = string.format("[+] SUCCESS: Siphoned +$%s directly into your wallet!",
                                                string.Comma(stolenCash)),
                                            color = "highlight"
                                        })

                                    GRID.Notify(ply,
                                        string.format("MSF Siphon Succeeded: +$%s from %s!", string.Comma(stolenCash),
                                            targetDev.name), NOTIFY_GENERIC)

                                    -- Alert victim if online and different player
                                    local victim = printer.GetOwnerPlayer and printer:GetOwnerPlayer() or
                                        printer.OwnerPlayer
                                    if IsValid(victim) and victim:IsPlayer() and victim ~= ply then
                                        GRID.Notify(victim,
                                            string.format(
                                                "SECURITY BREACH: Your %s was remotely hacked and drained via MSF exploit!",
                                                targetDev.name), NOTIFY_ERROR, 8)
                                        victim:EmitSound("ambient/alarms/klaxon1.wav", 65, 115)
                                    end
                                else
                                    table.insert(responseLines,
                                        {
                                            text =
                                            "[+] Exploit succeeded, but the printer's cash vault is currently empty ($0).",
                                            color =
                                            "yellow"
                                        })
                                end
                            end
                        end

                        -- ========================================================
                        -- MODULE 2: THERMAL OVERHEAT (Printers & Synthesizers)
                        -- ========================================================
                    elseif chosenModule == "overheat" then
                        if targetDev.type ~= "printer" and targetDev.type ~= "synthesizer" then
                            table.insert(responseLines,
                                { text = string.format("[*] Probing %s ...", targetIP), color = "muted" })
                            table.insert(responseLines,
                                {
                                    text = string.format(
                                        "[-] Exploit failed: Host %s (%s) does not have a vulnerable thermal regulator.",
                                        targetIP, targetDev.name),
                                    color = "red"
                                })
                            table.insert(responseLines,
                                {
                                    text = "[-] Thermal Overheat targets Money Printers and Material Synthesizers only.",
                                    color =
                                    "muted"
                                })
                        else
                            local targetEnt = targetDev.entity
                            if not IsValid(targetEnt) then
                                table.insert(responseLines,
                                    {
                                        text = "[-] Exploit failed: Target entity has disconnected or was removed.",
                                        color =
                                        "red"
                                    })
                            else
                                computer.NextExploitTime = now + 6 -- 6-second exploit cooldown

                                local isSynth = (targetDev.type == "synthesizer")
                                local targetPort = isSynth and 502 or 8080
                                local protoName = isSynth and "Modbus/TCP SCADA" or "MoneyFab daemon"

                                table.insert(responseLines,
                                    {
                                        text = string.format("[*] Targeting %s:%d (%s - %s)", targetIP, targetPort,
                                            protoName, targetDev.name),
                                        color = "muted"
                                    })
                                table.insert(responseLines,
                                    {
                                        text = string.format("[*] Transmitting thermal overload payload to %s...",
                                            protoName),
                                        color = "muted"
                                    })
                                table.insert(responseLines,
                                    {
                                        text = string.format("[+] Meterpreter session 1 opened (%s:4444 -> %s:%d)",
                                            localIP,
                                            targetIP, targetPort),
                                        color = "green"
                                    })

                                if isSynth then
                                    table.insert(responseLines,
                                        {
                                            text =
                                            "[+] Modbus holding registers 40001-40016 poisoned! Safety interlocks BYPASSED.",
                                            color =
                                            "yellow"
                                        })
                                    table.insert(responseLines,
                                        {
                                            text = "[!] OVERCHARGE: Material synthesis rotor speed set to 600%!",
                                            color =
                                            "red"
                                        })
                                    table.insert(responseLines,
                                        {
                                            text =
                                            "[!] CRITICAL: Core temperature spiked past 100C! Meltdown initiated!",
                                            color =
                                            "red"
                                        })
                                    table.insert(responseLines,
                                        {
                                            text = string.format("[!] Target %s will detonate in 3 seconds!",
                                                targetDev.name),
                                            color = "highlight"
                                        })

                                    targetEnt:EmitSound("ambient/alarms/klaxon1.wav", 80, 130)
                                    targetEnt:EmitSound("ambient/energy/zap2.wav", 80, 110)
                                    local effect = EffectData()
                                    effect:SetOrigin(targetEnt:GetPos() + Vector(0, 0, 20))
                                    util.Effect("cball_bounce", effect)
                                else
                                    table.insert(responseLines,
                                        {
                                            text = "[+] Thermal safety governor registers disabled in BIOS!",
                                            color =
                                            "yellow"
                                        })
                                    table.insert(responseLines,
                                        { text = "[+] Voltage multiplier forced to 400% maximum output!", color = "red" })
                                    table.insert(responseLines,
                                        {
                                            text =
                                            "[!] CRITICAL: Core temperature spiked past 100C! Meltdown initiated!",
                                            color =
                                            "red"
                                        })
                                    table.insert(responseLines,
                                        {
                                            text = string.format("[!] Target %s will detonate in 3 seconds!",
                                                targetDev.name),
                                            color = "highlight"
                                        })

                                    targetEnt:EmitSound("ambient/alarms/klaxon1.wav", 80, 125)
                                    local effect = EffectData()
                                    effect:SetOrigin(targetEnt:GetPos() + Vector(0, 0, 10))
                                    util.Effect("cball_bounce", effect)
                                end

                                targetEnt:SetTemperature(98)

                                GRID.Notify(ply,
                                    string.format("Thermal exploit injected into %s at %s! Detonation in 3 seconds!",
                                        targetDev.name, targetIP), NOTIFY_GENERIC)

                                local victim = targetEnt.GetOwnerPlayer and targetEnt:GetOwnerPlayer() or
                                    targetEnt.OwnerPlayer
                                if IsValid(victim) and victim:IsPlayer() and victim ~= ply then
                                    GRID.Notify(victim,
                                        string.format(
                                            "CRITICAL THERMAL ALERT: Your %s at %s was sabotaged via remote exploit and is detonating!",
                                            targetDev.name, targetIP), NOTIFY_ERROR, 8)
                                    victim:EmitSound("ambient/alarms/klaxon1.wav", 80, 120)
                                end

                                -- Detonate after 3 seconds
                                local timerId = "GRID_ThermalMeltdown_" .. targetEnt:EntIndex()
                                timer.Create(timerId, 3.0, 1, function()
                                    if IsValid(targetEnt) then
                                        targetEnt:SetTemperature(105)
                                        if targetEnt.Explode then
                                            targetEnt:Explode()
                                        end
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end
    elseif cmd == "botnet" or cmd == "c2" then
        if isPhone then
            table.insert(responseLines,
                {
                    text = "[-] botnet: Cloud Botnet C2 daemon requires dedicated x86_64 Personal Computer hardware.",
                    color =
                    "red"
                })
            table.insert(responseLines,
                { text = "    Mobile ARM handsets cannot host continuous C2 attack threads.", color = "muted" })
        elseif arg1 == "start" or arg1 == "run" then
            if computer:GetBotnetActive() then
                computer:RefreshBotnetState()
                if computer:GetBotnetActive() then
                    table.insert(responseLines,
                        {
                            text = string.format(
                                "[*] Cloud Botnet C2 daemon is already running (+$%s / 20s). Type 'botnet status' or 'botnet stop'.",
                                string.Comma(computer:GetBotnetYield() or 0)),
                            color = "yellow"
                        })
                end
            else
                local ok, yieldOrErr, totalPrinters, countedPrinters, isEng, uplink = computer:StartBotnet(ply)
                if not ok then
                    table.insert(responseLines, { text = "[-] botnet: Failed to initialize C2 daemon:", color = "red" })
                    table.insert(responseLines, { text = "    " .. tostring(yieldOrErr), color = "yellow" })
                else
                    local wanKey = IsValid(uplink) and uplink:GetEncryptionKey() or "WAN"
                    local engBonusStr = isEng and " [Cyber Engineer +25% Bonus Active]" or ""
                    table.insert(responseLines,
                        { text = "=== Cloud Botnet C2 Daemon Initialized (v4.2-hydra) ===", color = "cyan" })
                    table.insert(responseLines,
                        {
                            text = string.format("[+] Satellite WAN Tunnel Up : Gateway %s (Key: %s)",
                                IsValid(uplink) and (uplink:GetIPAddress() ~= "" and uplink:GetIPAddress() or "Attached") or
                                "Attached",
                                wanKey),
                            color = "green"
                        })
                    table.insert(responseLines,
                        {
                            text = string.format(
                                "[+] Compute Cluster Nodes   : %d Money Printer%s attached (%d active hash node%s)",
                                totalPrinters, totalPrinters == 1 and "" or "s",
                                countedPrinters, countedPrinters == 1 and "" or "s"),
                            color = "white"
                        })
                    table.insert(responseLines,
                        {
                            text = string.format("[+] Automated Payout Rate   : +$%s every 20s (Direct to wallet)%s",
                                string.Comma(yieldOrErr), engBonusStr),
                            color = "highlight"
                        })
                    table.insert(responseLines,
                        {
                            text =
                            "[!] WARNING: Active C2 traffic flags your Satellite WAN Uplink as [BOTNET ACTIVE] on wireless airmon scans.",
                            color = "yellow"
                        })
                    table.insert(responseLines,
                        {
                            text = "[*] Launching continuous automated attacks against remote cloud targets...",
                            color = "muted"
                        })
                end
            end
        elseif arg1 == "stop" or arg1 == "kill" or arg1 == "halt" then
            if not computer:GetBotnetActive() then
                table.insert(responseLines,
                    {
                        text = "[-] botnet: No active Cloud Botnet C2 daemon is running on this terminal.",
                        color =
                        "yellow"
                    })
            else
                local totalEarned = computer:GetBotnetTotalEarned() or 0
                local cycles = computer.BotnetCyclesCompleted or 0
                computer:StopBotnet(nil)
                table.insert(responseLines,
                    { text = "[+] Cloud Botnet C2 daemon gracefully terminated.", color = "green" })
                -- Check if pending buffer exists when stopped
                if (computer.BotnetBuffer or 0) > 0 then
                    table.insert(responseLines,
                        { text = string.format("    Pending Buffer          : +$%s (Type 'botnet collect' to withdraw)",
                            string.Comma(computer.BotnetBuffer)), color = "yellow" })
                end
                table.insert(responseLines,
                    {
                        text = string.format("    Completed Attack Cycles : %d  |  Total Session Siphoned : $%s",
                            cycles, string.Comma(totalEarned)),
                        color = "cyan"
                    })
            end
        else
            if arg1 == "collect" or arg1 == "withdraw" or arg1 == "claim" then
                local pending = computer.BotnetBuffer or 0
                if pending <= 0 then
                    table.insert(responseLines,
                        { text = "[-] No siphoned funds pending in terminal buffer ($0).", color = "yellow" })
                else
                    computer.BotnetBuffer = 0
                    computer:SetNWInt("GRID_BotnetBuffer", 0)
                    ply:AddMoney(pending)
                    table.insert(responseLines,
                        { text = string.format("[+] Withdrew +$%s from Botnet C2 buffer directly to your wallet!",
                            string.Comma(pending)), color = "green" })
                    GRID.Notify(ply, string.format("Collected +$%s from Botnet C2 buffer!", string.Comma(pending)),
                        NOTIFY_GENERIC)
                    if GRID.Telemetry and GRID.Telemetry.Log then
                        GRID.Telemetry.Log("ECONOMY", "BOTNET_COLLECT", ply:SteamID(), "", pending, {})
                    end
                end
                return
            end

            -- Default: status & help
            computer:RefreshBotnetState()
            local isActive = computer:GetBotnetActive()
            local uplink = isConnected and GRID.Network and GRID.Network.GetUplinkForSwitch and
                GRID.Network.GetUplinkForSwitch(sw) or nil
            local estYield, totalPrinters, countedPrinters, isEng = computer:CalculateBotnetYield(ply)
            local operator = computer:GetBotnetOperator()
            local opName = IsValid(operator) and operator:Nick() or "None"
            local maxNodes = GRID.Config.BotnetMaxCountedPrinters or 3

            table.insert(responseLines, { text = "=== Cloud Botnet C2 Attack Daemon Status ===", color = "cyan" })
            table.insert(responseLines,
                {
                    text = string.format("  Daemon State        : %s",
                        isActive and "ACTIVE (Attacking Cloud Targets)" or "IDLE (Stopped)"),
                    color = isActive and "green" or "yellow"
                })
            table.insert(responseLines,
                {
                    text = string.format("  Satellite WAN Link  : %s",
                        IsValid(uplink) and
                        string.format("CONNECTED (Key: %s | IP: %s)", uplink:GetEncryptionKey() or "NONE",
                            uplink:GetIPAddress() or "DHCP") or "MISSING (Wire a Satellite WAN Uplink to your switch)"),
                    color = IsValid(uplink) and "cyan" or "red"
                })
            table.insert(responseLines,
                {
                    text = string.format("  Printer Hash Nodes  : %d connected (%d/%d optimal compute nodes)",
                        totalPrinters, countedPrinters, maxNodes),
                    color = totalPrinters > 0 and "green" or "muted"
                })
            table.insert(responseLines,
                {
                    text = string.format("  Payout Yield (20s)  : +$%s / cycle%s",
                        string.Comma(isActive and (computer:GetBotnetYield() or estYield) or estYield),
                        isEng and " (Includes +25% Cyber Engineer Bonus)" or ""),
                    color = "highlight"
                })
            if isActive then
                table.insert(responseLines,
                    {
                        text = string.format("  Active Operator     : %s  |  Cycles: %d  |  Total Earned: $%s",
                            opName, computer.BotnetCyclesCompleted or 0,
                            string.Comma(computer:GetBotnetTotalEarned() or 0)),
                        color = "white"
                    })
            end
            table.insert(responseLines,
                { text = "----------------------------------------------------------------------", color = "dark" })
            table.insert(responseLines, { text = "Commands:", color = "white" })
            table.insert(responseLines,
                { text = "  botnet start   - Start continuous automated cloud cyber-attacks", color = "green" })
            table.insert(responseLines,
                { text = "  botnet stop    - Halt the botnet daemon & drop C2 traffic", color = "yellow" })
            table.insert(responseLines,
                { text = "  botnet status  - View cluster compute nodes & payout rate", color = "white" })
        end
    elseif cmd == "help" then
        table.insert(responseLines,
            { text = "=== CyberDeck OS - Built-in Shell Utility Commands ===", color = "cyan" })
        table.insert(responseLines,
            {
                text = "  botnet       - Launch automated Cloud Botnet C2 daemon (Requires WAN Uplink)",
                color =
                "green"
            })
        table.insert(responseLines,
            {
                text = "  nmap         - Scan reachable broadcast domain & routed WAN mesh device IP addresses",
                color =
                "white"
            })
        table.insert(responseLines,
            { text = "  msf          - Launch Metasploit Framework console (Cyber Engineer only)", color = "highlight" })
        table.insert(responseLines,
            {
                text = "  airmon       - Scan wireless airspace for active Satellite WAN Uplink transmitters",
                color =
                "cyan"
            })
        table.insert(responseLines,
            { text = "  wan crack    - Capture handshake & crack encryption key on a detected BSSID", color = "yellow" })
        table.insert(responseLines,
            { text = "  wan connect  - Associate CyberDeck Mobile Handset with a wireless WAN mesh key", color = "green" })
        table.insert(responseLines,
            { text = "  wan status   - Display active Satellite WAN gateway status & peer subnets", color = "white" })
        table.insert(responseLines,
            {
                text = "  ifconfig     - Show local ethernet/wireless adapter status, IP, netmask & gateway",
                color =
                "white"
            })
        table.insert(responseLines,
            { text = "  ping <ip>    - Test connectivity to an IP address across local and WAN subnets", color = "white" })
        table.insert(responseLines, { text = "  clear        - Clear the terminal screen buffer", color = "white" })
        table.insert(responseLines, { text = "  exit         - Close the terminal session", color = "white" })
        table.insert(responseLines,
            {
                text = "Tip: Type 'msf' to enter Metasploit console, then type 'help' for exploit commands.",
                color =
                "muted"
            })
    else
        table.insert(responseLines,
            {
                text = string.format("bash: %s: command not found. Type 'help' for available commands.", cmd),
                color =
                "red"
            })
    end

    net.Start("GRID_ComputerCommandResponse")
    net.WriteEntity(computer)
    net.WriteString(rawCmd)
    net.WriteUInt(#responseLines, 8)
    for _, line in ipairs(responseLines) do
        net.WriteString(line.text)
        net.WriteString(line.color or "white")
    end
    net.Send(ply)
end)
