--[[
    entities/entities/grid_network_switch_base/shared.lua
    GridRP Layer-3 Modular Network Switch Abstract Base
    Author: Juicebox
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Base Network Switch"
ENT.Author = "Juicebox"
ENT.Spawnable = false
ENT.AdminOnly = false
ENT.IsNetworkSwitch = true

-- Abstract port definitions table (to be defined by concrete subclasses)
ENT.PortDefinitions = {}

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "ConnectedCount")
    self:NetworkVar("Int", 1, "MaxPorts")
    self:NetworkVar("Int", 2, "Efficiency")
    self:NetworkVar("Int", 3, "SubnetID")
    self:NetworkVar("Int", 4, "ActivePortsMask") -- Bitmask: Bit (i-1) = Port i active link
    self:NetworkVar("Int", 5, "Port10GMask")     -- Bitmask: Bit (i-1) = Port i 10G SFP/Fiber mode
    self:NetworkVar("Int", 6, "PortUplinkMask")  -- Bitmask: Bit (i-1) = Port i Switch trunk
    self:NetworkVar("Entity", 0, "OwnerPlayer")
    self:NetworkVar("String", 0, "IPAddress")
end

-- Retrieves all defined ports for this switch class
function ENT:GetPortDefinitions()
    return self.PortDefinitions or {}
end

-- Retrieves a single port definition by 1-based index
function ENT:GetPortDefinition(portId)
    local defs = self:GetPortDefinitions()
    return defs[portId]
end

-- Returns total number of ports configured
function ENT:GetPortCount()
    return #self:GetPortDefinitions()
end

-- Bitmask Query: Is port active/linked?
function ENT:IsPortActive(portId)
    if not portId or portId < 1 or portId > 32 then return false end
    local mask = self:GetActivePortsMask() or 0
    return bit.band(mask, bit.lshift(1, portId - 1)) ~= 0
end

-- Bitmask Query: Is port running in 10G speed?
function ENT:IsPort10G(portId)
    if not portId or portId < 1 or portId > 32 then return false end
    local mask = self:GetPort10GMask() or 0
    return bit.band(mask, bit.lshift(1, portId - 1)) ~= 0
end

-- Bitmask Query: Is port connected to an uplink switch?
function ENT:IsPortUplink(portId)
    if not portId or portId < 1 or portId > 32 then return false end
    local mask = self:GetPortUplinkMask() or 0
    return bit.band(mask, bit.lshift(1, portId - 1)) ~= 0
end

-- Backward compatibility getters for legacy code
function ENT:GetPort1Active() return self:IsPortActive(1) end

function ENT:GetPort2Active() return self:IsPortActive(2) end

function ENT:GetPort3Active() return self:IsPortActive(3) end

function ENT:GetPort4Active() return self:IsPortActive(4) end

function ENT:GetPort3Is10G() return self:IsPort10G(3) end

function ENT:GetUplinkSwitch(portId)
    if portId and self.Ports and self.Ports[portId] then
        local p = self.Ports[portId]
        return (IsValid(p.device) and p.device) or (IsValid(p.switch) and p.switch) or NULL
    end
    if self.Ports then
        for _, p in pairs(self.Ports) do
            if p and p.isUplink and IsValid(p.device) then
                return p.device
            end
        end
    end
    return NULL
end

function ENT:GetPort3Switch()
    return self:GetUplinkSwitch(3)
end
