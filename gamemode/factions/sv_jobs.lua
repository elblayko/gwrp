--[[
    GangWars - Server-side Job Management with Anti-Job-Hopping & Role Commitment
    Author: GW Core Team
    Namespace: GW / gw_
]]

local meta = FindMetaTable("Player")

function meta:SetJob(jobId, force)
    local jobData = GW.Jobs[jobId]
    if not jobData then return false end

    local oldJobId = self:GetJob()
    if oldJobId == jobId and not force then return false end

    -- 1. Anti-Job-Hopping Cooldown Check (15 minutes by default)
    local now = CurTime()
    if not force and (self.NextJobChangeTime or 0) > now then
        local remSecs = math.ceil(self.NextJobChangeTime - now)
        local remMins = math.ceil(remSecs / 60)
        GW.Notify(self, string.format("Job transfer cooldown active! Please wait %d minute(s) (%d seconds).", remMins, remSecs), NOTIFY_ERROR)
        return false
    end

    -- 2. Check Level Requirement
    local reqLevel = jobData.level or 1
    if not force and self:GetLevel() < reqLevel then
        GW.Notify(self, string.format("You must be Level %d to become a %s!", reqLevel, jobData.name), NOTIFY_ERROR)
        return false
    end

    -- 3. Check Slot Limits
    if not force and jobData.max > 0 then
        local currentCount = 0
        for _, p in ipairs(player.GetAll()) do
            if p:GetJob() == jobId then currentCount = currentCount + 1 end
        end
        if currentCount >= jobData.max then
            GW.Notify(self, string.format("That job is currently full! (%d/%d)", currentCount, jobData.max), NOTIFY_ERROR)
            return false
        end
    end

    -- 4. Job Licensing & Administrative Induction Fee Sink
    if not force and jobId ~= "citizen" then
        local licenseFee = jobData.licenseFee or 50
        if not self:CanAfford(licenseFee) then
            GW.Notify(self, string.format("You cannot afford the job licensing fee ($%d)!", licenseFee), NOTIFY_ERROR)
            return false
        end
        self:AddMoney(-licenseFee)
        GW.Notify(self, string.format("Paid $%d professional licensing & onboarding fee.", licenseFee), NOTIFY_GENERIC)

        if GW.Telemetry and GW.Telemetry.Log then
            GW.Telemetry.Log("ECONOMY", "JOB_LICENSE_FEE", self:SteamID(), "", licenseFee, { job = jobId })
        end
    end

    -- Set new cooldown
    if not force then
        self.NextJobChangeTime = now + (GW.Config.JobChangeCooldown or 900)
    end

    -- 5. Role Transition Liquidation (Prevent Dealer Self-Purchasing & Job Hopping)
    if not force and oldJobId ~= "" and oldJobId ~= jobId then
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) then
                local isOwner = (ent.GW_Owner == self) or (ent:GetNWEntity("GW_Owner") == self) or (ent.PurchaserSteamID == self:SteamID())
                if isOwner then
                    local c = ent:GetClass()
                    -- Liquidate shipments and specialist pods immediately upon switching away from job
                    if c == "gw_shipment" or (oldJobId == "pharmacist" and c == "gw_clinic_pod") then
                        ent:Remove()
                    end
                end
            end
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

    hook.Run("OnPlayerChangedTeam", self, oldJobId, jobId)

    if GW.Telemetry and GW.Telemetry.Log then
        GW.Telemetry.Log("ECONOMY", "JOB_CHANGE", self:SteamID(), "", 0, { from = oldJobId, to = jobId })
    end

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
