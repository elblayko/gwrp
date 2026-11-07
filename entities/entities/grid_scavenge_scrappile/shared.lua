--[[
    entities/entities/grid_scavenge_scrappile/shared.lua
    GridRP Scrap Debris Pile Scavenge Node
    Author: Juicebox & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "grid_scavenge_node_base"
ENT.PrintName = "Scrap Debris Pile"
ENT.Author = "Juicebox & Antigravity"
ENT.Category = "GridRP - Scavenging"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model = "models/props_junk/trashcluster01a_corner.mdl"
ENT.NodeTier = "scrappile"
ENT.BaseCooldown = 240 -- 4 minutes
ENT.SearchDuration = 2.5
