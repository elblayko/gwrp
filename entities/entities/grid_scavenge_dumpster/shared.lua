--[[
    entities/entities/grid_scavenge_dumpster/shared.lua
    GridRP Industrial Dumpster Scavenge Node
    Author: Juicebox & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "grid_scavenge_node_base"
ENT.PrintName = "Industrial Dumpster"
ENT.Author = "Juicebox & Antigravity"
ENT.Category = "GridRP Scavenging"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model = "models/props_junk/TrashDumpster01a.mdl"
ENT.NodeTier = "dumpster"
ENT.BaseCooldown = 300 -- 5 minutes
ENT.SearchDuration = 5 -- Takes slightly longer to search a huge dumpster
