--[[
    entities/entities/grid_scavenge_trashbin/shared.lua
    GridRP Street Trash Can Scavenge Node
    Author: Juicebox & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "grid_scavenge_node_base"
ENT.PrintName = "Street Trash Can"
ENT.Author = "Juicebox & Antigravity"
ENT.Category = "GridRP Scavenging"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model = "models/props_trainstation/trashcan_indoor001b.mdl"
ENT.NodeTier = "trashbin"
ENT.BaseCooldown = 150   -- 2.5 minutes
ENT.SearchDuration = 1.5 -- Quick rummage
