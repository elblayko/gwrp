--[[
    entities/entities/gwrp_computer/init.lua
    GWRP Personal Computer Server Logic & Terminal Execution Engine
    Author: Toxic
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

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

    -- Wiremod Support
    if WireLib then
        WireLib.CreateInputs(self, { "RunNmap" })
        WireLib.CreateOutputs(self, {
            "IsNetworked",
            "AssignedPort",
            "GatewaySwitch [ENTITY]"
        })
        self:UpdateWireOutputs()
    end
end

function ENT:TriggerInput(name, value)
    if name == "RunNmap" and value ~= 0 then
        -- Wire trigger can refresh network info
        self:UpdateWireOutputs()
    end
end

function ENT:UpdateWireOutputs()
    if not WireLib then return end
    local isNet = IsValid(self:GetConnectedSwitch()) and 1 or 0
    WireLib.TriggerOutput(self, "IsNetworked", isNet)
    WireLib.TriggerOutput(self, "AssignedPort", self:GetAssignedPort() or 0)
    WireLib.TriggerOutput(self, "GatewaySwitch", self:GetConnectedSwitch())

    local ip = self:GetIPAddress()
    local ipStr = (ip and ip ~= "") and ("IP: " .. ip) or "NO CARRIER"
    local portStr = isNet == 1 and ("Port " .. self:GetAssignedPort()) or "Unlinked"
    WireLib.SetOverlayText(self, string.format("[GWRP CyberDeck Terminal]\nStatus: %s\n%s", portStr, ipStr))
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
        self:UpdateWireOutputs()
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

    net.Start("GWRP_OpenComputerOS")
        net.WriteEntity(self)
        net.WriteEntity(sw)
        net.WriteString(ip)
        net.WriteBool(isNet)
    net.Send(activator)
end

function ENT:OnRemove()
    self:DisconnectFromSwitch()

    if WireLib then
        WireLib.Remove(self)
    end
end

-- Server Terminal Command Processor
net.Receive("GWRP_RunComputerCommand", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not GWRP.CheckRateLimit(ply, "computer_cmd", 8) then return end

    local computer = net.ReadEntity()
    local rawCmd = string.Trim(net.ReadString() or "")

    if not IsValid(computer) or computer:GetClass() ~= "gwrp_computer" then return end
    if ply:EyePos():DistToSqr(computer:GetPos()) > (220 * 220) then
        GWRP.Notify(ply, "You are too far from the computer terminal!", NOTIFY_ERROR)
        return
    end

    local sw = computer:GetConnectedSwitch()
    local isConnected = IsValid(sw)
    local localIP = computer:GetIPAddress() or ""
    local subnet = isConnected and (GWRP.Network and GWRP.Network.GetSubnetID(sw) or sw:GetSubnetID()) or 0
    local isEngineer = (ply.GetJob and ply:GetJob() == "cyber_engineer")

    local parts = string.Explode(" ", rawCmd)
    local cmd = string.lower(parts[1] or "")
    local arg1 = parts[2] or ""

    local responseLines = {}

    if cmd == "nmap" then
        if not isConnected then
            table.insert(responseLines, { text = "Starting Nmap 7.94 ( https://nmap.org )", color = "muted" })
            table.insert(responseLines, { text = "nmap: FATAL: No active network interface found on eth0.", color = "red" })
            table.insert(responseLines, { text = "Interface eth0 has NO CARRIER (Physical copper cable unplugged).", color = "yellow" })
            table.insert(responseLines, { text = "Tip: Use Copper Wiring Tool to link this computer to an L2 Switch.", color = "muted" })
        else
            local devices = GWRP.Network and GWRP.Network.GetBroadcastDomain(sw) or {}
            local gatewayIP = GWRP.Network and GWRP.Network.GetGatewayIP(sw) or string.format("192.168.%d.1", subnet)
            local targetSubnet = string.format("192.168.%d.0/24", subnet)

            table.insert(responseLines, { text = string.format("Starting Nmap 7.94 ( https://nmap.org ) at %s", os.date("%Y-%m-%d %H:%M:%S")), color = "cyan" })
            table.insert(responseLines, { text = string.format("Initiating ARP Ping Scan on broadcast domain %s", targetSubnet), color = "muted" })
            table.insert(responseLines, { text = string.format("Completed ARP Ping Scan (%d live devices discovered).", #devices), color = "green" })
            table.insert(responseLines, { text = "----------------------------------------------------------------------", color = "dark" })

            local liveCount = 0
            for _, dev in ipairs(devices) do
                liveCount = liveCount + 1
                local isLocal = (dev.entity == computer)
                local hostLabel = isLocal and " (this terminal [localhost])" or ""

                table.insert(responseLines, { text = string.format("Nmap scan report for %s (%s)%s", dev.ip, dev.name, hostLabel), color = "highlight" })
                table.insert(responseLines, { text = string.format("Host is UP (0.00%02ds latency). MAC: %s", math.random(12, 65), dev.mac), color = "white" })

                if dev.type == "printer" then
                    local ent = dev.entity
                    local eff = (IsValid(ent) and ent.GetEfficiency) and ent:GetEfficiency() or 60
                    local temp = (IsValid(ent) and ent.GetTemperature) and ent:GetTemperature() or 20
                    local uv = (IsValid(ent) and ent.GetHasUndervolt and ent:GetHasUndervolt()) and " [Undervolted]" or ""
                    table.insert(responseLines, { text = "PORT     STATE SERVICE      VERSION", color = "muted" })
                    table.insert(responseLines, { text = string.format("8080/tcp OPEN  http-proxy   MoneyFab Daemon (%d%% eff, %d°C)%s", eff, temp, uv), color = "green" })
                elseif dev.type == "switch" then
                    table.insert(responseLines, { text = "PORT     STATE SERVICE      VERSION", color = "muted" })
                    table.insert(responseLines, { text = "22/tcp   OPEN  ssh          GWRP-Switch-OS L2.1 (OpenSSH 8.9)", color = "cyan" })
                    table.insert(responseLines, { text = "80/tcp   OPEN  http         Switch Management Web Console", color = "cyan" })
                elseif dev.type == "computer" then
                    table.insert(responseLines, { text = "PORT     STATE SERVICE      VERSION", color = "muted" })
                    table.insert(responseLines, { text = "23/tcp   OPEN  telnet       CyberDeck BSD Terminal Daemon", color = "blue" })
                elseif dev.type == "synthesizer" then
                    local ent = dev.entity
                    local eff = (IsValid(ent) and ent.GetEfficiency) and ent:GetEfficiency() or 60
                    local temp = (IsValid(ent) and ent.GetTemperature) and ent:GetTemperature() or 20
                    table.insert(responseLines, { text = "PORT     STATE SERVICE      VERSION", color = "muted" })
                    table.insert(responseLines, { text = string.format("502/tcp  OPEN  modbus       Modbus/TCP OT Synthesizer PLC (%d%% eff, %d°C)", eff, temp), color = "yellow" })
                    table.insert(responseLines, { text = "4840/tcp OPEN  opcua        OPC-UA Material Fabrication Service", color = "yellow" })
                end
                table.insert(responseLines, { text = " ", color = "muted" })
            end

            table.insert(responseLines, { text = "----------------------------------------------------------------------", color = "dark" })
            table.insert(responseLines, { text = string.format("Nmap done: %d IP addresses (%d hosts up) scanned in 0.42 seconds.", liveCount, liveCount), color = "cyan" })
        end

    elseif cmd == "ifconfig" or cmd == "ip" then
        if not isConnected then
            table.insert(responseLines, { text = "eth0: flags=4098<BROADCAST,MULTICAST>  mtu 1500", color = "white" })
            table.insert(responseLines, { text = "        ether 02:42:c0:00:00:00  txqueuelen 1000  (Ethernet)", color = "muted" })
            table.insert(responseLines, { text = "        status: NO CARRIER (Cable unplugged)", color = "red" })
        else
            local mac = GWRP.Network and GWRP.Network.FormatMAC(computer, subnet, 10 + (computer:GetAssignedPort() or 1)) or "02:42:C0:00:00:00"
            table.insert(responseLines, { text = "eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500", color = "white" })
            table.insert(responseLines, { text = string.format("        inet %s  netmask 255.255.255.0  broadcast 192.168.%d.255", localIP, subnet), color = "green" })
            table.insert(responseLines, { text = string.format("        ether %s  txqueuelen 1000  (Ethernet)", mac), color = "muted" })
            table.insert(responseLines, { text = string.format("        gateway: 192.168.%d.1 (Switch on Port %d)", subnet, computer:GetAssignedPort() or 0), color = "cyan" })
        end

    elseif cmd == "ping" then
        if not isConnected then
            table.insert(responseLines, { text = "ping: connect: Network is unreachable (eth0 is down).", color = "red" })
        elseif arg1 == "" then
            table.insert(responseLines, { text = "Usage: ping <ip_address>", color = "yellow" })
        else
            local devices = GWRP.Network and GWRP.Network.GetBroadcastDomain(sw) or {}
            local found = false
            for _, dev in ipairs(devices) do
                if dev.ip == arg1 then
                    found = true
                    break
                end
            end

            table.insert(responseLines, { text = string.format("PING %s (%s) 56(84) bytes of data.", arg1, arg1), color = "muted" })
            if found then
                for i = 1, 3 do
                    table.insert(responseLines, { text = string.format("64 bytes from %s: icmp_seq=%d ttl=64 time=0.%02d ms", arg1, i, math.random(15, 75)), color = "green" })
                end
                table.insert(responseLines, { text = string.format("--- %s ping statistics --- 3 packets transmitted, 3 received, 0%% packet loss", arg1), color = "cyan" })
            else
                table.insert(responseLines, { text = string.format("From %s icmp_seq=1 Destination Host Unreachable", localIP), color = "red" })
                table.insert(responseLines, { text = string.format("--- %s ping statistics --- 3 packets transmitted, 0 received, 100%% packet loss", arg1), color = "yellow" })
            end
        end

    elseif cmd == "use" or (cmd == "msf" and arg1 == "use") then
        if not isEngineer then
            table.insert(responseLines, { text = "[-] Permission Denied: Metasploit framework requires root cybersec clearance.", color = "red" })
            table.insert(responseLines, { text = "[-] Cyber Engineer security credentials required.", color = "yellow" })
            table.insert(responseLines, { text = "[!] Security violation logged to base security daemon.", color = "muted" })
        else
            local targetMod = (cmd == "use") and arg1 or (parts[3] or "")
            targetMod = string.lower(targetMod)

            if string.find(targetMod, "siphon") or string.find(targetMod, "cash") then
                computer.ActiveMSFModule = "siphon"
                table.insert(responseLines, { text = "[+] Loaded module: exploit/printer/cash_siphon", color = "green" })
                table.insert(responseLines, { text = "[*] Description : Bypasses EEPROM vault lockbox to extract all stored cash", color = "muted" })
                table.insert(responseLines, { text = "[*] Target      : Money Printers only", color = "muted" })
                table.insert(responseLines, { text = "[*] Ready. Type 'msf <ip>' or 'msf run <ip>' to execute against target.", color = "highlight" })
            elseif string.find(targetMod, "overheat") or string.find(targetMod, "thermal") or string.find(targetMod, "burn") or string.find(targetMod, "synth") or string.find(targetMod, "meltdown") then
                computer.ActiveMSFModule = "overheat"
                table.insert(responseLines, { text = "[+] Loaded module: exploit/multi/thermal_overheat", color = "red" })
                table.insert(responseLines, { text = "[*] Description : Overclocks thermal elements to detonate target printer or synthesizer", color = "muted" })
                table.insert(responseLines, { text = "[*] Target      : Money Printers & Material Synthesizers", color = "muted" })
                table.insert(responseLines, { text = "[*] Ready. Type 'msf <ip>' or 'msf run <ip>' to execute against target.", color = "highlight" })
            else
                table.insert(responseLines, { text = "[-] Unknown module. Available modules:", color = "yellow" })
                table.insert(responseLines, { text = "  use siphon    - Exploit lockbox & siphon stored cash (Printers)", color = "green" })
                table.insert(responseLines, { text = "  use overheat  - Overclock & detonate target (Printers & Synthesizers)", color = "red" })
            end
        end

    elseif cmd == "msf" or cmd == "metasploit" then
        if not isEngineer then
            table.insert(responseLines, { text = "[-] Permission Denied: Metasploit framework requires root cybersec clearance.", color = "red" })
            table.insert(responseLines, { text = "[-] Cyber Engineer security credentials required.", color = "yellow" })
            table.insert(responseLines, { text = "[!] Security violation logged to base security daemon.", color = "muted" })
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
            table.insert(responseLines, { text = "[-] msf: Exploit failed: eth0 has NO CARRIER (Unplugged).", color = "red" })
            table.insert(responseLines, { text = "    Connect this terminal to an L2 Switch to reach target subnets.", color = "yellow" })
        elseif targetIP == "" or targetIP == "help" or targetIP == "modules" or targetIP == "show" then
            table.insert(responseLines, { text = "  _|_|_|    _|_|    _|_|_|  ", color = "cyan" })
            table.insert(responseLines, { text = " _|        _|  _|  _|       ", color = "cyan" })
            table.insert(responseLines, { text = " _|  _|_|  _|_|_|  _|_|_|   ", color = "cyan" })
            table.insert(responseLines, { text = " _|    _|  _|  _|  _|       ", color = "cyan" })
            table.insert(responseLines, { text = "  _|_|_|   _|  _|  _|       ", color = "cyan" })
            table.insert(responseLines, { text = "Metasploit Framework Console (MSF v6.4.12-toxic)", color = "white" })
            local modDisplay = chosenModule == "overheat" and "exploit/multi/thermal_overheat" or "exploit/printer/cash_siphon"
            table.insert(responseLines, { text = string.format("Active Module : %s", modDisplay), color = "highlight" })
            table.insert(responseLines, { text = "----------------------------------------------------------------------", color = "dark" })
            table.insert(responseLines, { text = "Available Exploit Modules:", color = "white" })
            table.insert(responseLines, { text = "  1) exploit/printer/cash_siphon", color = "green" })
            table.insert(responseLines, { text = "     Syntax : msf siphon <ip> (or 'use siphon')", color = "muted" })
            table.insert(responseLines, { text = "     Target : Money Printers only", color = "muted" })
            table.insert(responseLines, { text = "     Action : Drains 100% of printer cash vault into your wallet", color = "muted" })
            table.insert(responseLines, { text = "  2) exploit/multi/thermal_overheat", color = "red" })
            table.insert(responseLines, { text = "     Syntax : msf overheat <ip> (or 'use overheat')", color = "muted" })
            table.insert(responseLines, { text = "     Target : Money Printers & Material Synthesizers", color = "muted" })
            table.insert(responseLines, { text = "     Action : Overclocks thermal regulators & detonates target device in 3s", color = "muted" })
            table.insert(responseLines, { text = "----------------------------------------------------------------------", color = "dark" })
            table.insert(responseLines, { text = "MSF Console Commands:", color = "white" })
            table.insert(responseLines, { text = "  run <ip>         - Execute active module on target IP (or 'exploit <ip>')", color = "green" })
            table.insert(responseLines, { text = "  use siphon       - Select Cash Siphon exploit module", color = "white" })
            table.insert(responseLines, { text = "  use overheat     - Select Thermal Overheat exploit module", color = "white" })
            table.insert(responseLines, { text = "  show modules     - List available exploit modules", color = "white" })
            table.insert(responseLines, { text = "  help             - Display this MSF help menu", color = "white" })
            table.insert(responseLines, { text = "  back / exit      - Exit Metasploit console back to bash shell", color = "muted" })
        else
            -- Check cooldown on computer entity
            local now = CurTime()
            if computer.NextExploitTime and now < computer.NextExploitTime then
                local remaining = math.ceil(computer.NextExploitTime - now)
                table.insert(responseLines, { text = string.format("[-] msf: Module cooldown active. Please wait %ds before re-arming payload.", remaining), color = "yellow" })
            else
                local devices = GWRP.Network and GWRP.Network.GetBroadcastDomain(sw) or {}
                local targetDev = nil
                for _, dev in ipairs(devices) do
                    if dev.ip == targetIP then
                        targetDev = dev
                        break
                    end
                end

                local modName = chosenModule == "overheat" and "exploit/multi/thermal_overheat" or "exploit/printer/cash_siphon"
                table.insert(responseLines, { text = string.format("[*] Started reverse TCP handler on %s:4444", localIP), color = "muted" })
                table.insert(responseLines, { text = string.format("[*] Using module: %s", modName), color = "cyan" })

                if not targetDev then
                    table.insert(responseLines, { text = string.format("[-] Exploit failed: Host %s is unreachable or not in broadcast domain.", targetIP), color = "red" })

                -- ========================================================
                -- MODULE 1: CASH SIPHON (Money Printers only)
                -- ========================================================
                elseif chosenModule == "siphon" then
                    if targetDev.type ~= "printer" then
                        table.insert(responseLines, { text = string.format("[*] Probing %s ...", targetIP), color = "muted" })
                        if targetDev.type == "synthesizer" then
                            table.insert(responseLines, { text = string.format("[-] Exploit failed: Host %s (%s) is a Material Synthesizer and does not store cash.", targetIP, targetDev.name), color = "red" })
                            table.insert(responseLines, { text = "[-] Use 'use overheat' or 'msf overheat <ip>' to sabotage synthesizers.", color = "yellow" })
                        else
                            table.insert(responseLines, { text = string.format("[-] Exploit failed: Host %s (%s) is not a Money Printer.", targetIP, targetDev.name), color = "red" })
                        end
                    else
                        local printer = targetDev.entity
                        if not IsValid(printer) then
                            table.insert(responseLines, { text = "[-] Exploit failed: Target entity has disconnected or was removed.", color = "red" })
                        else
                            computer.NextExploitTime = now + 6 -- 6-second exploit cooldown

                            table.insert(responseLines, { text = string.format("[*] Targeting %s:8080 (%s)", targetIP, targetDev.name), color = "muted" })
                            table.insert(responseLines, { text = "[*] Sending stage (1536 bytes) to MoneyFab daemon...", color = "muted" })
                            table.insert(responseLines, { text = string.format("[+] Meterpreter session 1 opened (%s:4444 -> %s:8080)", localIP, targetIP), color = "green" })
                            table.insert(responseLines, { text = "[+] EEPROM buffer overflow triggered at 0x7FFF0042!", color = "green" })

                            local stolenCash = printer.GetStoredCash and printer:GetStoredCash() or 0
                            if stolenCash > 0 then
                                ply:AddMoney(stolenCash)
                                printer:SetStoredCash(0)
                                if printer.UpdateWireOutputs then printer:UpdateWireOutputs() end

                                -- Sound effects
                                computer:EmitSound("ambient/levels/labs/coinslot1.wav", 75, 100)
                                printer:EmitSound("ambient/energy/spark1.wav", 75, 120)
                                printer:EmitSound("ambient/levels/labs/coinslot1.wav", 75, 80)

                                table.insert(responseLines, { text = "[+] Lockbox override accepted. Draining cash reservoir...", color = "highlight" })
                                table.insert(responseLines, { text = string.format("[+] SUCCESS: Siphoned +$%s directly into your wallet!", string.Comma(stolenCash)), color = "highlight" })

                                GWRP.Notify(ply, string.format("MSF Siphon Succeeded: +$%s from %s!", string.Comma(stolenCash), targetDev.name), NOTIFY_GENERIC)

                                -- Alert victim if online and different player
                                local victim = printer.GetOwnerPlayer and printer:GetOwnerPlayer() or printer.OwnerPlayer
                                if IsValid(victim) and victim:IsPlayer() and victim ~= ply then
                                    GWRP.Notify(victim, string.format("SECURITY BREACH: Your %s was remotely hacked and drained via MSF exploit!", targetDev.name), NOTIFY_ERROR, 8)
                                    victim:EmitSound("ambient/alarms/klaxon1.wav", 65, 115)
                                end
                            else
                                table.insert(responseLines, { text = "[+] Exploit succeeded, but the printer's cash vault is currently empty ($0).", color = "yellow" })
                            end
                        end
                    end

                -- ========================================================
                -- MODULE 2: THERMAL OVERHEAT (Printers & Synthesizers)
                -- ========================================================
                elseif chosenModule == "overheat" then
                    if targetDev.type ~= "printer" and targetDev.type ~= "synthesizer" then
                        table.insert(responseLines, { text = string.format("[*] Probing %s ...", targetIP), color = "muted" })
                        table.insert(responseLines, { text = string.format("[-] Exploit failed: Host %s (%s) does not have a vulnerable thermal regulator.", targetIP, targetDev.name), color = "red" })
                        table.insert(responseLines, { text = "[-] Thermal Overheat targets Money Printers and Material Synthesizers only.", color = "muted" })
                    else
                        local targetEnt = targetDev.entity
                        if not IsValid(targetEnt) then
                            table.insert(responseLines, { text = "[-] Exploit failed: Target entity has disconnected or was removed.", color = "red" })
                        else
                            computer.NextExploitTime = now + 6 -- 6-second exploit cooldown

                            local isSynth = (targetDev.type == "synthesizer")
                            local targetPort = isSynth and 502 or 8080
                            local protoName = isSynth and "Modbus/TCP SCADA" or "MoneyFab daemon"

                            table.insert(responseLines, { text = string.format("[*] Targeting %s:%d (%s - %s)", targetIP, targetPort, protoName, targetDev.name), color = "muted" })
                            table.insert(responseLines, { text = string.format("[*] Transmitting thermal overload payload to %s...", protoName), color = "muted" })
                            table.insert(responseLines, { text = string.format("[+] Meterpreter session 1 opened (%s:4444 -> %s:%d)", localIP, targetIP, targetPort), color = "green" })

                            if isSynth then
                                table.insert(responseLines, { text = "[+] Modbus holding registers 40001-40016 poisoned! Safety interlocks BYPASSED.", color = "yellow" })
                                table.insert(responseLines, { text = "[!] OVERCHARGE: Material synthesis rotor speed set to 600%!", color = "red" })
                                table.insert(responseLines, { text = "[!] CRITICAL: Core temperature spiked past 100°C! Meltdown initiated!", color = "red" })
                                table.insert(responseLines, { text = string.format("[!] Target %s will detonate in 3 seconds!", targetDev.name), color = "highlight" })

                                targetEnt:EmitSound("ambient/alarms/klaxon1.wav", 80, 130)
                                targetEnt:EmitSound("ambient/energy/zap2.wav", 80, 110)
                                local effect = EffectData()
                                effect:SetOrigin(targetEnt:GetPos() + Vector(0, 0, 20))
                                util.Effect("cball_bounce", effect)
                            else
                                table.insert(responseLines, { text = "[+] Thermal safety governor registers disabled in BIOS!", color = "yellow" })
                                table.insert(responseLines, { text = "[+] Voltage multiplier forced to 400% maximum output!", color = "red" })
                                table.insert(responseLines, { text = "[!] CRITICAL: Core temperature spiked past 100°C! Meltdown initiated!", color = "red" })
                                table.insert(responseLines, { text = string.format("[!] Target %s will detonate in 3 seconds!", targetDev.name), color = "highlight" })

                                targetEnt:EmitSound("ambient/alarms/klaxon1.wav", 80, 125)
                                local effect = EffectData()
                                effect:SetOrigin(targetEnt:GetPos() + Vector(0, 0, 10))
                                util.Effect("cball_bounce", effect)
                            end

                            targetEnt:SetTemperature(98)
                            if targetEnt.UpdateWireOutputs then targetEnt:UpdateWireOutputs() end

                            GWRP.Notify(ply, string.format("Thermal exploit injected into %s at %s! Detonation in 3 seconds!", targetDev.name, targetIP), NOTIFY_GENERIC)

                            local victim = targetEnt.GetOwnerPlayer and targetEnt:GetOwnerPlayer() or targetEnt.OwnerPlayer
                            if IsValid(victim) and victim:IsPlayer() and victim ~= ply then
                                GWRP.Notify(victim, string.format("CRITICAL THERMAL ALERT: Your %s at %s was sabotaged via remote exploit and is detonating!", targetDev.name, targetIP), NOTIFY_ERROR, 8)
                                victim:EmitSound("ambient/alarms/klaxon1.wav", 80, 120)
                            end

                            -- Detonate after 3 seconds
                            local timerId = "GWRP_ThermalMeltdown_" .. targetEnt:EntIndex()
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

    elseif cmd == "help" then
        table.insert(responseLines, { text = "=== GWRP CyberDeck OS - Built-in Shell Utility Commands ===", color = "cyan" })
        table.insert(responseLines, { text = "  nmap         - Scan broadcast domain & enumerate device IP addresses / ports", color = "white" })
        table.insert(responseLines, { text = "  msf          - Launch Metasploit Framework console (Cyber Engineer only)", color = "highlight" })
        table.insert(responseLines, { text = "  ifconfig     - Show local ethernet adapter status, IP, netmask & gateway", color = "white" })
        table.insert(responseLines, { text = "  ping <ip>    - Test connectivity to an IP address in the broadcast domain", color = "white" })
        table.insert(responseLines, { text = "  clear        - Clear the terminal screen buffer", color = "white" })
        table.insert(responseLines, { text = "  exit         - Close the terminal session", color = "white" })
        table.insert(responseLines, { text = "Tip: Type 'msf' to enter Metasploit console, then type 'help' for exploit commands.", color = "muted" })

    else
        table.insert(responseLines, { text = string.format("bash: %s: command not found. Type 'help' for available commands.", cmd), color = "red" })
    end

    net.Start("GWRP_ComputerCommandResponse")
        net.WriteEntity(computer)
        net.WriteString(rawCmd)
        net.WriteUInt(#responseLines, 8)
        for _, line in ipairs(responseLines) do
            net.WriteString(line.text)
            net.WriteString(line.color or "white")
        end
    net.Send(ply)
end)
