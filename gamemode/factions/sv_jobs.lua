--[[
    GridRP - Server-side Job Management with Anti-Job-Hopping & Role Commitment
    Author: GRID Core Team
    Namespace: GRID / grid_
]]

local meta = FindMetaTable("Player")

function meta:SetJob(jobId, force)
    local jobData = GRID.Jobs and GRID.Jobs[jobId]
    if not jobData then return false end

    local oldJobId = self:GetJob()
    if oldJobId == jobId and not force then return false end

    -- Hook override check (e.g. Onboarding gates)
    if not force and hook.Run("GRID_CanChangeJob", self, jobId) == false then
        return false
    end

    -- 1. Anti-Job-Hopping Cooldown Check (15 minutes by default)
    local now = CurTime()
    if not force and (self.NextJobChangeTime or 0) > now then
        local remSecs = math.ceil(self.NextJobChangeTime - now)
        local remMins = math.ceil(remSecs / 60)
        GRID.Notify(self, string.format("Job transfer cooldown active! Please wait %d minute(s) (%d seconds).", remMins, remSecs), NOTIFY_ERROR)
        return false
    end

    -- 2. Check Level Requirement
    local reqLevel = jobData.level or 1
    if not force and self:GetLevel() < reqLevel then
        GRID.Notify(self, string.format("You must be Level %d to become a %s!", reqLevel, jobData.name), NOTIFY_ERROR)
        return false
    end

    -- 3. Check Slot Limits
    if not force and jobData.max > 0 then
        local currentCount = 0
        for _, p in ipairs(player.GetAll()) do
            if p:GetJob() == jobId then currentCount = currentCount + 1 end
        end
        if currentCount >= jobData.max then
            GRID.Notify(self, string.format("That job is currently full! (%d/%d)", currentCount, jobData.max), NOTIFY_ERROR)
            return false
        end
    end

    -- 4. Job Licensing & Administrative Induction Fee Sink
    if not force and jobId ~= "citizen" then
        local licenseFee = jobData.licenseFee or 50
        if not self:CanAfford(licenseFee) then
            GRID.Notify(self, string.format("You cannot afford the job licensing fee ($%d)!", licenseFee), NOTIFY_ERROR)
            return false
        end
        self:AddMoney(-licenseFee)
        GRID.Notify(self, string.format("Paid $%d professional licensing & onboarding fee.", licenseFee), NOTIFY_GENERIC)

        if GRID.Telemetry and GRID.Telemetry.Log then
            GRID.Telemetry.Log("ECONOMY", "JOB_LICENSE_FEE", self:SteamID(), "", licenseFee, { job = jobId })
        end
    end

    -- Set new cooldown
    if not force then
        self.NextJobChangeTime = now + (GRID.Config and GRID.Config.JobChangeCooldown or 900)
    end

    -- 5. Role Transition Liquidation (Prevent Dealer Self-Purchasing & Job Hopping)
    if not force and oldJobId ~= "" and oldJobId ~= jobId then
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) then
                local isOwner = (ent.GRID_Owner == self) or (ent:GetNWEntity("GRID_Owner") == self) or (ent.PurchaserSteamID == self:SteamID())
                if isOwner then
                    local c = ent:GetClass()
                    -- Liquidate shipments and specialist pods immediately upon switching away from job
                    if c == "grid_shipment" or (oldJobId == "pharmacist" and c == "grid_clinic_pod") then
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

    self:SetNWString("GRID_Job", jobId)
    if GRID.Database and GRID.Database.SavePlayerJob then
        GRID.Database.SavePlayerJob(self, jobId)
    end
    self:Spawn()

    hook.Run("OnPlayerChangedTeam", self, oldJobId, jobId)

    if GRID.Telemetry and GRID.Telemetry.Log then
        GRID.Telemetry.Log("ECONOMY", "JOB_CHANGE", self:SteamID(), "", 0, { from = oldJobId, to = jobId })
    end

    GRID.Notify(self, "You are now working as a " .. jobData.name .. "!", NOTIFY_GENERIC)

    -- Notify player of gang suspension or restoration
    if storedGang ~= "" and not force then
        if newFactionId == "police" and oldFactionId ~= "police" then
            GRID.Notify(self, "On-duty as Police: Street gang affiliations are suspended.", NOTIFY_HINT, 6)
        elseif newFactionId == "neutral" and oldFactionId == "gang" then
            GRID.Notify(self, "Civilian status: Street gang affiliations are temporarily inactive.", NOTIFY_HINT, 6)
        elseif newFactionId == "gang" and oldFactionId ~= "gang" then
            GRID.Notify(self, string.format("Welcome back to the streets! Gang '%s' is now active.", storedGang), NOTIFY_GENERIC, 6)
        end
    end

    return true
end

local function HandleChangeJob(len, ply)
    if not GRID.CheckRateLimit(ply, "job_change", 2) then return end
    local jobId = net.ReadString()
    ply:SetJob(jobId)
end

net.Receive("GRID_ChangeJob", HandleChangeJob)
