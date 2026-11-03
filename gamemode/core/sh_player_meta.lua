--[[
    sh_player_meta.lua - Metatable Extensions on Player & Doors (Player-Created Gang Support)
--]]

local meta = FindMetaTable("Player")
if meta then
    -- Money Methods
    function meta:GetMoney()
        return self:GetNWInt("GWRP_Money", 0)
    end

    function meta:CanAfford(amount)
        return self:GetMoney() >= amount
    end

    -- Job Methods
    function meta:GetJob()
        return self:GetNWString("GWRP_Job", "citizen")
    end

    function meta:GetJobData()
        return GWRP.Jobs[self:GetJob()] or GWRP.Jobs["citizen"]
    end

    -- Player Gang Methods
    function meta:GetGang()
        return self:GetNWString("GWRP_Gang", "")
    end

    function meta:IsInGang()
        return self:GetGang() ~= ""
    end

    function meta:GetFaction()
        local job = self:GetJobData()
        local baseFaction = job and job.faction or GWRP.Factions.FACTION_CITIZEN

        -- If in a player-created gang, return dynamic faction object with custom gang color
        local gangName = self:GetGang()
        if gangName ~= "" and baseFaction.id == "gang" then
            return {
                id = string.lower(gangName),
                name = gangName,
                color = GWRP.GetGangColor(gangName)
            }
        end

        return baseFaction
    end

    function meta:IsGangMember(factionIdOrGang)
        if not factionIdOrGang or factionIdOrGang == "" then return false end
        local gang = self:GetGang()
        if gang ~= "" and string.lower(gang) == string.lower(factionIdOrGang) then
            return true
        end

        local f = self:GetFaction()
        return f and string.lower(f.id) == string.lower(factionIdOrGang)
    end

    function meta:IsPolice()
        local f = self:GetFaction()
        return f and f.id == "police"
    end

    -- Level & Progression Methods
    function meta:GetLevel()
        return math.max(1, self:GetNWInt("GWRP_Level", 1))
    end

    function meta:GetXP()
        return math.max(0, self:GetNWInt("GWRP_XP", 0))
    end

    function meta:GetRequiredXP()
        return GWRP.GetRequiredXP and GWRP.GetRequiredXP(self:GetLevel()) or 0
    end

    function meta:CanUseItemLevel(reqLevel)
        return self:GetLevel() >= (tonumber(reqLevel) or 1)
    end

    if SERVER then
        function meta:SetMoney(amount)
            amount = math.max(0, math.floor(amount))
            self:SetNWInt("GWRP_Money", amount)
            GWRP.Database.SavePlayerMoney(self, amount)
        end

        function meta:AddMoney(amount)
            self:SetMoney(self:GetMoney() + amount)
        end

        function meta:SetGang(gangName)
            gangName = string.Trim(gangName or "")
            self:SetNWString("GWRP_Gang", gangName)
            GWRP.Database.SavePlayerGang(self, gangName)
        end

        function meta:SetLevel(lvl)
            local maxLvl = (GWRP.Config and GWRP.Config.Level and GWRP.Config.Level.MaxLevel) or 50
            lvl = math.Clamp(math.floor(tonumber(lvl) or 1), 1, maxLvl)
            self:SetNWInt("GWRP_Level", lvl)
            if GWRP.Database and GWRP.Database.SavePlayerLevelXP then
                GWRP.Database.SavePlayerLevelXP(self, lvl, self:GetXP())
            end
        end

        function meta:SetXP(xp)
            xp = math.max(0, math.floor(tonumber(xp) or 0))
            self:SetNWInt("GWRP_XP", xp)
            if GWRP.Database and GWRP.Database.SavePlayerLevelXP then
                GWRP.Database.SavePlayerLevelXP(self, self:GetLevel(), xp)
            end
        end

        function meta:AddXP(amount, reason)
            amount = math.floor(tonumber(amount) or 0)
            if amount <= 0 then return end

            local maxLvl = (GWRP.Config and GWRP.Config.Level and GWRP.Config.Level.MaxLevel) or 50
            local curLvl = self:GetLevel()
            if curLvl >= maxLvl then return end -- Max level cap

            local curXP = self:GetXP() + amount
            local leveledUp = false
            local initialLvl = curLvl

            while curLvl < maxLvl and curXP >= GWRP.GetRequiredXP(curLvl) do
                local req = GWRP.GetRequiredXP(curLvl)
                if req <= 0 then break end
                curXP = curXP - req
                curLvl = curLvl + 1
                leveledUp = true
            end

            if curLvl >= maxLvl then
                curXP = 0
            end

            self:SetNWInt("GWRP_Level", curLvl)
            self:SetNWInt("GWRP_XP", curXP)

            if GWRP.Database and GWRP.Database.SavePlayerLevelXP then
                GWRP.Database.SavePlayerLevelXP(self, curLvl, curXP)
            end

            -- Dispatch XP popup combat text / floating HUD event
            net.Start("GWRP_XPGained")
                net.WriteInt(amount, 32)
                net.WriteString(reason or "Action")
            net.Send(self)

            if leveledUp then
                local cashMultiplier = (GWRP.Config and GWRP.Config.Level and GWRP.Config.Level.CashRewardPerLevel) or 500
                local rewardCash = curLvl * cashMultiplier
                self:AddMoney(rewardCash)
                self:SetHealth(self:GetMaxHealth())

                net.Start("GWRP_LevelUp")
                    net.WriteInt(curLvl, 16)
                    net.WriteInt(rewardCash, 32)
                net.Send(self)

                GWRP.Notify(self, string.format("★ LEVEL UP! You reached Level %d! Awarded +$%s & Health Restored!", curLvl, string.Comma(rewardCash)), NOTIFY_GENERIC, 6)
            end
        end
    end
end

-- Entity / Door Methods
local entMeta = FindMetaTable("Entity")
if entMeta then
    function entMeta:isDoor()
        local class = self:GetClass()
        return class == "prop_door_rotating" or class == "func_door" or class == "func_door_rotating"
    end

    function entMeta:IsDoor()
        return self:isDoor()
    end

    function entMeta:GetDoorOwner()
        return self:GetNWEntity("GWRP_DoorOwner")
    end

    function entMeta:GetDoorFaction()
        return self:GetNWString("GWRP_DoorFaction", "")
    end

    function entMeta:CanAccessDoor(ply)
        if not IsValid(ply) then return false end
        local owner = self:GetDoorOwner()
        if not IsValid(owner) then return false end
        if owner == ply then return true end

        local doorGang = self:GetDoorFaction()
        if doorGang ~= "" then
            -- Match player-created gang or faction
            if ply:GetGang() ~= "" and string.lower(ply:GetGang()) == string.lower(doorGang) then
                return true
            end
            if ply:IsGangMember(doorGang) then
                return true
            end
        end

        return false
    end
end
