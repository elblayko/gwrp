--[[
    sv_jobs.lua - Server-side Job Management with Faction Transition Feedback
--]]

local meta = FindMetaTable("Player")

function meta:SetJob(jobId, force)
    local jobData = GW.Jobs[jobId]
    if not jobData then return false end

    -- Check Level Requirement
    local reqLevel = jobData.level or 1
    if not force and self:GetLevel() < reqLevel then
        GW.Notify(self, string.format("You must be Level %d to become a %s!", reqLevel, jobData.name), NOTIFY_ERROR)
        return false
    end

    -- Check Slot Limits
    if not force and jobData.max > 0 then
        local currentCount = 0
        for _, p in ipairs(player.GetAll()) do
            if p:GetJob() == jobId then currentCount = currentCount + 1 end
        end
        if currentCount >= jobData.max then
            GW.Notify(self, "That job is currently full! (" .. currentCount .. "/" .. jobData.max .. ")", NOTIFY_ERROR)
            return false
        end
    end

    local oldJobData = self:GetJobData()
    local oldFactionId = oldJobData and oldJobData.faction and oldJobData.faction.id or "neutral"
    local newFactionId = jobData.faction and jobData.faction.id or "neutral"
    local storedGang = self:GetRawGang()

    self:SetNWString("GW_Job", jobId)
    if GW.Database and GW.Database.SavePlayerJob then
        GW.Database.SavePlayerJob(self, jobId)
    end
    self:Spawn()

    GW.Notify(self, "You are now working as a " .. jobData.name .. "!", NOTIFY_GENERIC)

    -- Notify player of gang suspension or restoration
    if storedGang ~= "" and not force then
        if newFactionId == "police" and oldFactionId ~= "police" then
            GW.Notify(self, "On-duty as Police: Street gang affiliations are suspended.", NOTIFY_HINT, 6)
        elseif newFactionId == "neutral" and oldFactionId == "gang" then
            GW.Notify(self, "Civilian status: Street gang affiliations are temporarily inactive.", NOTIFY_HINT, 6)
        elseif newFactionId == "gang" and oldFactionId ~= "gang" then
            GW.Notify(self, string.format("Welcome back to the streets! Gang '%s' is now active.", storedGang), NOTIFY_GENERIC, 6)
        end
    end

    return true
end

net.Receive("GW_ChangeJob", function(len, ply)
    if not GW.CheckRateLimit(ply, "job_change", 2) then return end
    local jobId = net.ReadString()
    ply:SetJob(jobId)
end)
