--[[
    cl_jobs.lua - Client Job Cache & Team Color Helpers
--]]

GWRP.JobsClient = GWRP.JobsClient or {}

function GWRP.GetTeamColor(ply)
    if not IsValid(ply) then return GWRP.Colors.White end
    local job = ply:GetJobData()
    return job and job.faction and job.faction.color or GWRP.Colors.White
end
