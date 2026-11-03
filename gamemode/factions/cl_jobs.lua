--[[
    cl_jobs.lua - Client Job Cache & Team Color Helpers
--]]

GW.JobsClient = GW.JobsClient or {}

function GW.GetTeamColor(ply)
    if not IsValid(ply) then return GW.Colors.White end
    local job = ply:GetJobData()
    return job and job.faction and job.faction.color or GW.Colors.White
end
