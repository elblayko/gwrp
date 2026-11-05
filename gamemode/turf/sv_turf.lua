--[[
    sv_turf.lua - Server Turf Engine, Per-Map Profile Persistence & Admin Setup
--]]

GW.Turf = GW.Turf or {}

function GW.Turf.GetProfilePath()
    local map = string.lower(game.GetMap())
    return "gangwarsrp/maps/" .. map .. ".json"
end

function GW.Turf.SaveMapProfile()
    local mapName = game.GetMap()

    -- 1. Primary Persistence: Save directly to MariaDB via stored procedures
    if GW.Database and GW.Database.SaveTurfZones then
        GW.Database.SaveTurfZones(mapName, GW.Turf.Zones)
    end

    -- 2. Secondary Export: JSON snapshot for backup
    file.CreateDir("gangwarsrp/maps")
    local serializable = {}
    for id, zone in pairs(GW.Turf.Zones) do
        table.insert(serializable, {
            id = tonumber(id),
            name = zone.name,
            pos = { x = math.Round(zone.pos.x, 2), y = math.Round(zone.pos.y, 2), z = math.Round(zone.pos.z, 2) },
            radius = tonumber(zone.radius) or 450,
            owner = zone.owner or "neutral",
            progress = tonumber(zone.progress) or 100,
            tax_rate = tonumber(zone.tax_rate) or 10
        })
    end

    local json = util.TableToJSON(serializable, true)
    file.Write(GW.Turf.GetProfilePath(), json)
    print(string.format("[GW-Turf] Saved %d turf zones to MariaDB & JSON profile for '%s'.", #serializable, mapName))
    return true
end

function GW.Turf.LoadMapProfile()
    local mapKey = string.lower(game.GetMap())
    GW.Turf.Zones = {}

    -- 1. Try loading from MariaDB database first
    local dbZones = GW.Database and GW.Database.LoadTurfZones and GW.Database.LoadTurfZones(mapKey)
    if dbZones and table.Count(dbZones) > 0 then
        GW.Turf.Zones = dbZones
        print(string.format("[GW-Turf] Loaded %d turf zones from MariaDB for map '%s'.", table.Count(dbZones), mapKey))
        return
    end

    -- 2. Fallback to existing JSON profile
    local path = GW.Turf.GetProfilePath()
    if file.Exists(path, "DATA") then
        local raw = file.Read(path, "DATA")
        local tbl = util.JSONToTable(raw) or {}

        for _, item in ipairs(tbl) do
            local id = tonumber(item.id) or (#GW.Turf.Zones + 1)
            GW.Turf.Zones[id] = {
                id = id,
                name = item.name or ("Turf Zone #" .. id),
                pos = Vector(item.pos.x, item.pos.y, item.pos.z),
                radius = tonumber(item.radius) or 450,
                owner = item.owner or "neutral",
                progress = tonumber(item.progress) or 100,
                tax_rate = tonumber(item.tax_rate) or 10
            }
        end
        -- Migrate to SQLite
        GW.Turf.SaveMapProfile()
        print(string.format("[GWRP-Turf] Migrated %d zones from JSON profile into SQLite.", table.Count(GW.Turf.Zones)))
        return
    end

    -- 3. Check built-in template for this map
    local defaults = GW.Turf.DefaultTemplates[mapKey]
    if defaults then
        for id, zone in pairs(defaults) do
            GW.Turf.Zones[id] = {
                id = id,
                name = zone.name,
                pos = Vector(zone.pos.x, zone.pos.y, zone.pos.z),
                radius = zone.radius,
                owner = zone.owner,
                progress = zone.progress or 100,
                tax_rate = tonumber(zone.tax_rate) or 10
            }
        end
        GW.Turf.SaveMapProfile()
        print(string.format("[GWRP-Turf] Seeded default template into SQLite for map '%s'.", mapKey))
    else
        print(string.format("[GWRP-Turf] No saved profile for '%s'. Admins can use /turfsetup to create zones.", mapKey))
    end
end

function GW.Turf.SpawnPoles()
    -- Clean up any existing flag poles
    for _, ent in ipairs(ents.FindByClass("gw_flag_pole")) do
        if IsValid(ent) then ent:Remove() end
    end

    -- Spawn configured flag poles
    for id, zone in pairs(GW.Turf.Zones) do
        local pole = ents.Create("gw_flag_pole")
        if IsValid(pole) then
            pole:SetPos(zone.pos)
            pole:SetTurfID(id)
            pole:Spawn()
            pole:Activate()
            zone.entity = pole
        end
    end
end

function GW.Turf.Init()
    GW.Turf.LoadMapProfile()
    GW.Turf.SpawnPoles()

    -- Dividend Timer
    timer.Create("GW_TurfDividends", GW.Config.TurfDividendInterval, 0, function()
        GW.Turf.DistributeDividends()
    end)
end

function GW.Turf.SyncToPlayer(ply)
    local count = table.Count(GW.Turf.Zones)
    net.Start("GW_SyncTurfZones")
        net.WriteUInt(count, 8)
        for id, zone in pairs(GW.Turf.Zones) do
            net.WriteUInt(id, 8)
            net.WriteString(zone.name)
            net.WriteVector(zone.pos)
            net.WriteUInt(zone.radius or 450, 16)
            net.WriteString(zone.owner or "neutral")
            net.WriteUInt(zone.progress or 100, 8)
            net.WriteUInt(zone.tax_rate or 10, 8)
        end
    net.Send(ply)
end

function GW.Turf.SyncToAll()
    local count = table.Count(GW.Turf.Zones)
    net.Start("GW_SyncTurfZones")
        net.WriteUInt(count, 8)
        for id, zone in pairs(GW.Turf.Zones) do
            net.WriteUInt(id, 8)
            net.WriteString(zone.name)
            net.WriteVector(zone.pos)
            net.WriteUInt(zone.radius or 450, 16)
            net.WriteString(zone.owner or "neutral")
            net.WriteUInt(zone.progress or 100, 8)
            net.WriteUInt(zone.tax_rate or 10, 8)
        end
    net.Broadcast()
end

function GW.Turf.BroadcastUpdate(turfId)
    local zone = GW.Turf.Zones[turfId]
    if not zone then return end

    net.Start("GW_TurfUpdate")
        net.WriteUInt(turfId, 8)
        net.WriteString(zone.owner or "neutral")
        net.WriteUInt(zone.progress or 100, 8)
        net.WriteUInt(zone.tax_rate or 10, 8)
    net.Broadcast()
end

function GW.Turf.CaptureFlag(turfId, ply)
    local zone = GW.Turf.Zones[turfId]
    if not zone or not IsValid(ply) then return end

    local faction = ply:GetFaction()
    if not faction or faction.id == "neutral" then
        GW.Notify(ply, "Join a Gang or Police (F4) to contest turf!", NOTIFY_ERROR)
        return
    end

    local claimant = ""
    if faction.id == "police" then
        claimant = "Police"
    else
        claimant = ply:GetGang()
        if claimant == "" then
            GW.Notify(ply, "You must create or join a player gang first! Type: /creategang <name>", NOTIFY_ERROR)
            return
        end
    end

    if string.lower(zone.owner or "") == string.lower(claimant) then
        GW.Notify(ply, zone.name .. " is already controlled by " .. claimant .. "!", NOTIFY_GENERIC)
        return
    end

    -- If a pole entity exists, trigger its progressive use
    if IsValid(zone.entity) and zone.entity:GetClass() == "gw_flag_pole" then
        zone.entity:Use(ply, ply)
        return
    end

    GW.Turf.FinalizeCapture(turfId, ply, claimant)
end

function GW.Turf.FinalizeCapture(turfId, ply, claimant)
    local zone = GW.Turf.Zones[turfId]
    if not zone then return end

    zone.owner = claimant
    zone.progress = 100
    GW.Turf.BroadcastUpdate(turfId)

    if IsValid(ply) then
        ply:AddMoney(GW.Config.TurfCaptureReward)
        if ply.AddXP then
            ply:AddXP((GW.Config and GW.Config.Level and GW.Config.Level.XP_TurfCapture) or 150, "Turf Zone Capture")
        end
        GW.Notify(ply, "Captured " .. zone.name .. " for " .. claimant .. "! (+$" .. GW.Config.TurfCaptureReward .. " bonus)", NOTIFY_GENERIC)
        GW.NotifyAll(string.format("%s captured %s for %s", ply:Nick(), zone.name, claimant), NOTIFY_HINT, 6)
    else
        GW.NotifyAll(string.format("%s was captured for %s", zone.name, claimant), NOTIFY_HINT, 6)
    end
end

function GW.Turf.DistributeDividends()
    local payouts = {}

    for _, zone in pairs(GW.Turf.Zones) do
        local owner = zone.owner
        if owner and owner ~= "neutral" and owner ~= "" then
            payouts[string.lower(owner)] = (payouts[string.lower(owner)] or 0) + GW.Config.TurfDividendAmount
        end
    end

    for _, ply in ipairs(player.GetAll()) do
        local gang = ply:GetGang()
        local faction = ply:GetFaction()
        local claim = (gang ~= "") and gang or (faction and faction.id == "police" and "Police" or "")

        if claim ~= "" and payouts[string.lower(claim)] then
            local amount = payouts[string.lower(claim)]
            ply:AddMoney(amount)
            if ply.AddXP then
                ply:AddXP((GW.Config and GW.Config.Level and GW.Config.Level.XP_TurfHoldTick) or 25, "Territory Domination")
            end
            GW.Notify(ply, string.format("Earned +$%d dividend from controlled territories (%s)", amount, claim), NOTIFY_GENERIC)
        end
    end
end

-- ==========================================
-- TURF TAX & INCURSION ALERTS
-- ==========================================

function GW.Turf.SetTaxRate(turfId, taxRate, ply)
    local zone = GW.Turf.Zones[turfId]
    if not zone then
        if IsValid(ply) then GW.Notify(ply, "Invalid turf zone!", NOTIFY_ERROR) end
        return false
    end

    taxRate = math.Clamp(math.Round(tonumber(taxRate) or 10), 5, 30)

    if IsValid(ply) then
        local pGang = ply:GetGang()
        local isLeader = ply:GetNWBool("GW_IsGangLeader", false) or (ply.GetJob and ply:GetJob() == "gang_leader") or ply:IsAdmin()
        if not isLeader then
            GW.Notify(ply, "Only the Gang Leader can adjust territory protection taxes!", NOTIFY_ERROR)
            return false
        end

        if not ply:IsAdmin() and (pGang == "" or string.lower(pGang) ~= string.lower(zone.owner or "")) then
            GW.Notify(ply, "Your gang does not control this territory!", NOTIFY_ERROR)
            return false
        end
    end

    zone.tax_rate = taxRate

    if GW.Database and GW.Database.SetTurfTax then
        GW.Database.SetTurfTax(game.GetMap(), turfId, taxRate)
    end
    GW.Turf.SaveMapProfile()
    GW.Turf.BroadcastUpdate(turfId)

    if IsValid(ply) then
        GW.Notify(ply, string.format("Set protection tax for %s to %d%%!", zone.name, taxRate), NOTIFY_GENERIC)
    end

    -- Broadcast notification to online gang members
    if zone.owner and zone.owner ~= "" and zone.owner ~= "neutral" and zone.owner ~= "Police" then
        for _, p in ipairs(player.GetAll()) do
            if string.lower(p:GetGang()) == string.lower(zone.owner) and p ~= ply then
                GW.Notify(p, string.format("[GANG] Protection tax in %s was set to %d%%.", zone.name, taxRate), NOTIFY_HINT, 4)
            end
        end
    end

    return true
end

function GW.Turf.SendIncursionAlert(zone, alertMsg)
    if not zone or not zone.owner or zone.owner == "" or zone.owner == "neutral" or zone.owner == "Police" then return end

    local alertText = alertMsg or string.format("POLICE INCURSION in %s! Defend your district and paying civilians!", zone.name)
    for _, p in ipairs(player.GetAll()) do
        if string.lower(p:GetGang()) == string.lower(zone.owner) then
            p:EmitSound("ambient/alarms/klaxon1.wav", 75, 120, 0.7)
            GW.Notify(p, "[DISTRICT ALERT] " .. alertText, NOTIFY_ERROR, 8)
        end
    end
end

net.Receive("GW_SetTurfTax", function(len, ply)
    if not IsValid(ply) then return end
    if not GW.CheckRateLimit(ply, "turf_set_tax", 1.0) then return end

    local turfId = net.ReadUInt(8)
    local taxRate = net.ReadUInt(8)
    GW.Turf.SetTaxRate(turfId, taxRate, ply)
end)

-- ==========================================
-- ADMIN SETUP COMMANDS & NETWORK HANDLERS
-- ==========================================

local function CanUseAdminSetup(ply)
    return IsValid(ply) and (ply:IsAdmin() or ply:IsSuperAdmin())
end

-- Console command for setup tool
concommand.Add("gw_turfsetup", function(ply)
    if not CanUseAdminSetup(ply) then
        GW.Notify(ply, "Access Denied: Admins only!", NOTIFY_ERROR)
        return
    end
    net.Start("GW_OpenTurfSetup")
    net.Send(ply)
end)

-- Chat command for setup tool
hook.Add("PlayerSay", "GW_TurfSetupChatCommand", function(ply, text)
    local lower = string.lower(string.Trim(text))
    if lower == "/turfsetup" or lower == "!turfsetup" or lower == "/adminsetup" or lower == "!adminsetup" then
        if not CanUseAdminSetup(ply) then
            GW.Notify(ply, "Access Denied: Admins only!", NOTIFY_ERROR)
            return ""
        end
        net.Start("GW_OpenTurfSetup")
        net.Send(ply)
        return ""
    end
end)

-- Admin action receiver
net.Receive("GW_AdminTurfAction", function(len, ply)
    if not CanUseAdminSetup(ply) then return end

    local action = net.ReadString()

    -- Ensure Zones table is initialized
    GW.Turf.Zones = GW.Turf.Zones or {}

    -- 1. ADD NEW TURF FLAG POLE
    if action == "add" or action == "create" then
        local name = net.ReadString()
        local pos = net.ReadVector()
        local radius = net.ReadUInt(16)
        local initialOwner = net.ReadString()

        if name == "" then name = "New Territory" end
        if radius < 50 then radius = 450 end
        if initialOwner == "" then initialOwner = "neutral" end

        -- Next available ID
        local newId = 1
        while GW.Turf.Zones[newId] ~= nil do
            newId = newId + 1
        end

        GW.Turf.Zones[newId] = {
            id = newId,
            name = name,
            pos = pos,
            radius = radius,
            owner = initialOwner,
            progress = 100
        }

        -- Spawn Entity
        local pole = ents.Create("gw_flag_pole")
        if IsValid(pole) then
            pole:SetPos(pos)
            pole:SetTurfID(newId)
            pole:Spawn()
            pole:Activate()
            GW.Turf.Zones[newId].entity = pole
        end

        GW.Turf.SaveMapProfile()
        GW.Turf.SyncToAll()
        GW.Notify(ply, string.format("Added Turf Pole #%d: '%s' at position!", newId, name), NOTIFY_GENERIC)

    -- 2. EDIT EXISTING TURF FLAG POLE
    elseif action == "edit" then
        local id = net.ReadUInt(8)
        local name = net.ReadString()
        local pos = net.ReadVector()
        local radius = net.ReadUInt(16)
        local owner = net.ReadString()

        local zone = GW.Turf.Zones[id]
        if not zone then return end

        zone.name = name
        zone.radius = radius
        zone.owner = owner

        if pos ~= Vector(0, 0, 0) then
            zone.pos = pos
            if IsValid(zone.entity) then
                zone.entity:SetPos(pos)
            end
        end

        GW.Turf.SaveMapProfile()
        GW.Turf.SyncToAll()
        GW.Notify(ply, string.format("Updated Turf Pole #%d: '%s'!", id, name), NOTIFY_GENERIC)

    -- 3. REMOVE TURF FLAG POLE
    elseif action == "remove" or action == "delete" then
        local id = net.ReadUInt(8)
        local zone = GW.Turf.Zones[id]
        if not zone then return end

        if IsValid(zone.entity) then
            zone.entity:Remove()
        end

        GW.Turf.Zones[id] = nil
        GW.Turf.SaveMapProfile()
        GW.Turf.SyncToAll()
        GW.Notify(ply, string.format("Removed Turf Pole #%d!", id), NOTIFY_GENERIC)

    -- 4. TELEPORT TO TURF FLAG POLE
    elseif action == "teleport" then
        local id = net.ReadUInt(8)
        local zone = GW.Turf.Zones[id]
        if not zone then return end

        ply:SetPos(zone.pos + Vector(0, 0, 15))
        GW.Notify(ply, string.format("Teleported to Turf #%d: '%s'!", id, zone.name), NOTIFY_GENERIC)

    -- 5. SAVE PROFILE TO DISK
    elseif action == "save" then
        GW.Turf.SaveMapProfile()
        GW.Notify(ply, "Saved all turf flag poles to map profile (" .. game.GetMap() .. ".json)!", NOTIFY_GENERIC)

    -- 6. RELOAD PROFILE FROM DISK
    elseif action == "reload" then
        GW.Turf.LoadMapProfile()
        GW.Turf.SpawnPoles()
        GW.Turf.SyncToAll()
        GW.Notify(ply, "Reloaded turf flag poles from map profile!", NOTIFY_GENERIC)

    -- 7. CLEAR ALL TURF POLES
    elseif action == "clear" then
        for id, zone in pairs(GW.Turf.Zones) do
            if IsValid(zone.entity) then zone.entity:Remove() end
        end
        GW.Turf.Zones = {}
        GW.Turf.SaveMapProfile()
        GW.Turf.SyncToAll()
        GW.Notify(ply, "Cleared all turf flag poles from current map!", NOTIFY_GENERIC)
    end
end)
