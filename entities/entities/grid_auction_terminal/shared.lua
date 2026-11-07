--[[
    entities/entities/grid_auction_terminal/shared.lua
    GridRP Player-Driven Auction House Terminal
    Author: Juicebox & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.PrintName = "Auction Terminal"
ENT.Author = "Juicebox & Antigravity"
ENT.Category = "GridRP - World Infrastructure"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model = "models/props_combine/combine_interface001.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "TerminalName")
    self:NetworkVar("Int", 0, "ActiveAuctions")
end

