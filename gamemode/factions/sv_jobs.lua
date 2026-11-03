--[[
    sv_jobs.lua - Server-side Job Management
--]]

local meta = FindMetaTable("Player")

function meta:SetJob(jobId, force)
    local jobData = GWRP.Jobs[jobId]
    if not jobData then return false end

    -- Check Level Requirement
    local reqLevel = jobData.level or 1
    if not force and self:GetLevel() < reqLevel then
        GWRP.Notify(self, string.format("You must be Level %d to become a %s!", reqLevel, jobData.name), NOTIFY_ERROR)
        return false
    end

    -- Check Slot Limits
    if not force and jobData.max > 0 then
        local currentCount = 0
        for _, p in ipairs(player.GetAll()) do
            if p:GetJob() == jobId then currentCount = currentCount + 1 end
        end
        if currentCount >= jobData.max then
            GWRP.Notify(self, "That job is currently full! (" .. currentCount .. "/" .. jobData.max .. ")", NOTIFY_ERROR)
            return false
        end
    end

    self:SetNWString("GWRP_Job", jobId)
    if GWRP.Database and GWRP.Database.SavePlayerJob then
        GWRP.Database.SavePlayerJob(self, jobId)
    end
    self:Spawn()

    GWRP.Notify(self, "You are now working as a " .. jobData.name .. "!", NOTIFY_GENERIC)
    return true
end

net.Receive("GWRP_ChangeJob", function(len, ply)
    if not GWRP.CheckRateLimit(ply, "job_change", 2) then return end
    local jobId = net.ReadString()
    ply:SetJob(jobId)
end)
