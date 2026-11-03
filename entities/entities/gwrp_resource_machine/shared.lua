--[[
    gwrp_resource_machine/shared.lua - Shared Resource Fabricator & Crafting Station
    Author: Toxic & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Resource Fabricator"
ENT.Author = "Toxic & Antigravity"
ENT.Category = "GangWars RP"
ENT.Spawnable = true
ENT.AdminOnly = false

ENT.IsNetworkDevice = true
ENT.ItemQuality = 1 -- Common
ENT.ItemSubType = "Automated Extractor"
ENT.Model = "models/props_c17/trappropeller_engine.mdl"
ENT.Instructions = "Automated legal extractor and crafting station. Generates ingots, blueprints, and carbon rods. Connects to L2 switch for accelerated throughput."
ENT.Stats = "Extracts Metals & Blueprints | Network Capable | Crafting Station"
ENT.MaxTemp = 100

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "MachineHealth")
    self:NetworkVar("Int", 1, "MaxMachineHealth")
    self:NetworkVar("Int", 2, "Efficiency")
    self:NetworkVar("Int", 3, "AssignedPort")
    self:NetworkVar("Int", 4, "Temperature")

    self:NetworkVar("Float", 0, "CycleStartTime")
    self:NetworkVar("Float", 1, "CycleDuration")
    self:NetworkVar("Float", 2, "VentStartTime")
    self:NetworkVar("Float", 3, "VentDuration")
    self:NetworkVar("Float", 4, "VentSweetMin")
    self:NetworkVar("Float", 5, "VentSweetMax")
    self:NetworkVar("Float", 6, "ValveJammedUntil")
    self:NetworkVar("Float", 7, "ThermalSpikeUntil")

    self:NetworkVar("Bool", 0, "HasReadyItem")
    self:NetworkVar("Bool", 1, "VentActive")
    self:NetworkVar("Bool", 2, "IsTuned")
    self:NetworkVar("Bool", 3, "HasUndervolt")

    self:NetworkVar("String", 0, "ReadyItemID")
    self:NetworkVar("String", 1, "ReadyItemName")
    self:NetworkVar("String", 2, "IPAddress")

    self:NetworkVar("Entity", 0, "ConnectedSwitch")
    self:NetworkVar("Entity", 1, "OwnerPlayer")
end
