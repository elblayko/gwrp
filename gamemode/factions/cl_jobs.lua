--[[
    cl_jobs.lua - Client Job Cache & Team Color Helpers
--]]

GRID.JobsClient = GRID.JobsClient or {}

function GRID.GetTeamColor(ply)
    if not IsValid(ply) then return (GRID.Colors and GRID.Colors.White) or Color(248, 250, 252) end
    local job = ply:GetJobData()
    return job and job.faction and job.faction.color or (GRID.Colors and GRID.Colors.White) or Color(248, 250, 252)
end
