--[[
    entities/entities/grid_wan_uplink/init.lua
    GridRP Encrypted Satellite WAN Uplink Server Logic
    Author: Toxic
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("GRID_OpenWANConfig")
util.AddNetworkString("GRID_UpdateWANKey")

local function GenerateRandomKey()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local code = ""
    for i = 1, 6 do
        local rand = math.random(1, #chars)
        code = code .. string.sub(chars, rand, rand)
    end
    return "WAN-" .. code
end

function ENT:Initialize()
    self:SetModel("models/props_rooftop/roof_dish001.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    self:SetEncryptionKey(GenerateRandomKey())
    self:SetIPAddress("")
    self:SetAssignedPort(0)
    self:SetConnectedSwitch(NULL)
    self:SetLinkedPeerCount(0)
    self:SetIsOnline(false)

    -- Register in global WAN uplink registry
    GRID.Network = GRID.Network or {}
    GRID.Network.WANUplinks = GRID.Network.WANUplinks or {}
    table.insert(GRID.Network.WANUplinks, self)

    -- Wiremod support
    if WireLib then
        WireLib.CreateInputs(self, { "EncryptionKey [STRING]", "ResetKey" })
        WireLib.CreateOutputs(self, {
            "IsOnline",
            "LinkedPeers",
            "EncryptionKey [STRING]",
            "LocalSubnet",
            "AssignedPort",
            "ConnectedSwitch [ENTITY]"
        })
        self:UpdateWireOutputs()
    end

    GRID.Network.RecalculateWANMesh()
end

function ENT:TriggerInput(name, value)
    if name == "EncryptionKey" and type(value) == "string" and value ~= "" then
        self:UpdateKey(string.Trim(value))
    elseif name == "ResetKey" and value ~= 0 then
        self:UpdateKey(GenerateRandomKey())
    end
end

function ENT:UpdateKey(newKey)
    if not newKey or string.len(newKey) < 2 then return end
    local cleanKey = string.Trim(string.upper(string.sub(newKey, 1, 16)))
    local oldKey = self:GetEncryptionKey()
    self:SetEncryptionKey(cleanKey)
    self:EmitSound("ambient/energy/zap1.wav", 65, 120)

    -- Changing encryption key interrupts any active Cloud Botnet C2 tunnel on this broadcast domain
    if oldKey and oldKey ~= "" and oldKey ~= cleanKey then
        local sw = self:GetConnectedSwitch()
        local botnetPC = IsValid(sw) and GRID.Network and GRID.Network.GetActiveBotnetForSwitch and GRID.Network.GetActiveBotnetForSwitch(sw)
        if IsValid(botnetPC) and botnetPC.StopBotnet then
            botnetPC:StopBotnet("WAN encryption key changed — C2 tunnel handshake dropped.")
        end
    end

    GRID.Network.RecalculateWANMesh()
    self:UpdateWireOutputs()
end

function ENT:UpdateWireOutputs()
    if not WireLib then return end

    local isOnline = self:GetIsOnline() and 1 or 0
    local peers = self:GetLinkedPeerCount() or 0
    local key = self:GetEncryptionKey() or ""
    local sw = self:GetConnectedSwitch()
    local subnet = IsValid(sw) and (sw.GetSubnetID and sw:GetSubnetID() or 1) or 0

    WireLib.TriggerOutput(self, "IsOnline", isOnline)
    WireLib.TriggerOutput(self, "LinkedPeers", peers)
    WireLib.TriggerOutput(self, "EncryptionKey", key)
    WireLib.TriggerOutput(self, "LocalSubnet", subnet)
    WireLib.TriggerOutput(self, "AssignedPort", self:GetAssignedPort() or 0)
    WireLib.TriggerOutput(self, "ConnectedSwitch", sw)

    local statusStr = (isOnline == 1) and string.format("ONLINE (%d Peer%s)", peers, peers == 1 and "" or "s") or "NO SIGNAL (Standalone)"
    WireLib.SetOverlayText(self, string.format(
        "[GridRP Satellite WAN Uplink]\nKey: %s\nStatus: %s\nLocal Subnet: 192.168.%d.0/24",
        key, statusStr, subnet
    ))
end

function ENT:DisconnectFromSwitch()
    local sw = self:GetConnectedSwitch()
    local botnetPC = IsValid(sw) and GRID.Network and GRID.Network.GetActiveBotnetForSwitch and GRID.Network.GetActiveBotnetForSwitch(sw)

    if IsValid(sw) and sw.DisconnectDevice then
        sw:DisconnectDevice(self)
    end

    self:SetConnectedSwitch(NULL)
    self:SetIPAddress("")
    self:SetAssignedPort(0)

    if IsValid(botnetPC) and botnetPC.StopBotnet then
        botnetPC:StopBotnet("Satellite WAN Uplink disconnected from L3 Switch.")
    end

    GRID.Network.RecalculateWANMesh()
    self:UpdateWireOutputs()
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[activator] or 0) > now then return end
    self.NextUsePerPlayer[activator] = now + 0.5

    -- Police confiscation check
    if activator:IsPolice() then
        local baseBounty = 350
        activator:AddMoney(baseBounty)
        GRID.Notify(activator, string.format("Contraband encrypted WAN Satellite Uplink confiscated for +$%d bounty!", baseBounty), NOTIFY_GENERIC)
        activator:EmitSound("ambient/levels/labs/coinslot1.wav")
        self:DisconnectFromSwitch()
        self:Remove()
        return
    end

    -- Open configuration UI for player
    net.Start("GRID_OpenWANConfig")
        net.WriteEntity(self)
        net.WriteString(self:GetEncryptionKey() or "")
        net.WriteBool(self:GetIsOnline())
        net.WriteUInt(self:GetLinkedPeerCount() or 0, 8)
        local sw = self:GetConnectedSwitch()
        net.WriteEntity(sw)
        local subnet = IsValid(sw) and (sw.GetSubnetID and sw:GetSubnetID() or 1) or 0
        net.WriteUInt(subnet, 16)
        net.WriteString(self:GetIPAddress() or "")
    net.Send(activator)

    self:EmitSound("buttons/button14.wav", 60, 100)
end

function ENT:OnRemove()
    self:DisconnectFromSwitch()

    -- Remove from global registry
    if GRID.Network and GRID.Network.WANUplinks then
        table.RemoveByValue(GRID.Network.WANUplinks, self)
        GRID.Network.RecalculateWANMesh()
    end

    if WireLib then
        WireLib.Remove(self)
    end
end

-- Network receiver for player key update
net.Receive("GRID_UpdateWANKey", function(len, ply)
    local uplink = net.ReadEntity()
    local newKey = net.ReadString()

    if not IsValid(ply) or not IsValid(uplink) or uplink:GetClass() ~= "grid_wan_uplink" then return end
    if uplink:GetPos():DistToSqr(ply:GetPos()) > (250 * 250) then return end

    uplink:UpdateKey(newKey)
    GRID.Notify(ply, string.format("WAN Uplink encryption key updated to [%s]. Re-associating mesh...", uplink:GetEncryptionKey()), NOTIFY_GENERIC)
end)
