--[[
    gamemode/police/sh_jail.lua
    GridRP Jail, Sentence, Bail & Holding Cell System - Shared Definitions
    Author: GRID Core Team
--]]

GRID = GRID or {}
GRID.Jail = GRID.Jail or {}

GRID.Jail.DefaultSentence = 90 -- seconds
GRID.Jail.DefaultBail = 500     -- dollars
GRID.Jail.Points = GRID.Jail.Points or {}
GRID.Jail.ReleasePoint = GRID.Jail.ReleasePoint or nil

local meta = FindMetaTable("Player")

function meta:IsJailed()
    return self:GetNWBool("GRID_IsJailed", false)
end

function meta:GetJailTimeRemaining()
    local relTime = self:GetNWFloat("GRID_JailReleaseTime", 0)
    return math.max(0, math.ceil(relTime - CurTime()))
end

function meta:GetJailBail()
    return self:GetNWInt("GRID_JailBail", GRID.Jail.DefaultBail)
end

