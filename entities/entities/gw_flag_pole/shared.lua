--[[
    entities/entities/gw_flag_pole/shared.lua
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Turf Flag Pole"
ENT.Author = "Toxic"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

-- Exempt Gameplay Objective (No Item Quality)
ENT.NoQuality = true

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "TurfID")
    self:NetworkVar("Bool", 0, "IsCapturing")
    self:NetworkVar("Float", 0, "CaptureStartTime")
    self:NetworkVar("Float", 1, "CaptureEndTime")
    self:NetworkVar("Entity", 0, "CapturingPlayer")
    self:NetworkVar("String", 0, "CapturingGang")
end
