--[[
    sv_turf.lua - Server Turf Engine, Per-Map Profile Persistence & Admin Setup
--]]

GWRP.Turf = GWRP.Turf or {}

function GWRP.Turf.GetProfilePath()
    local map = string.lower(game.GetMap())
    return "gangwarsrp/maps/" .. map .. ".json"
end

function GWRP.Turf.SaveMapProfile()
    local mapName = game.GetMap()

    -- 1. Primary Persistence: Save directly to SQLite
    if GWRP.Database and GWRP.Database.SaveTurfZones then
        GWRP.Database.SaveTurfZones(mapName, GWRP.Turf.Zones)
    end

    -- 2. Secondary Export: JSON snapshot for backup
    file.CreateDir("gangwarsrp/maps")
    local serializable = {}
    for id, zone in pairs(GWRP.Turf.Zones) do
        table.insert(serializable, {
            id = tonumber(id),
            name = zone.name,
            pos = { x = math.Round(zone.pos.x, 2), y = math.Round(zone.pos.y, 2), z = math.Round(zone.pos.z, 2) },
            radius = tonumber(zone.radius) or 450,
            owner = zone.owner or "neutral",
            progress = tonumber(zone.progress) or 100
        })
    end

    local json = util.TableToJSON(serializable, true)
    file.Write(GWRP.Turf.GetProfilePath(), json)
    print(string.format("[GWRP-Turf] Saved %d turf zones to SQLite & JSON profile for '%s'.", #serializable, mapName))
    return true
end

function GWRP.Turf.LoadMapProfile()
    local mapKey = string.lower(game.GetMap())
    GWRP.Turf.Zones = {}

    -- 1. Try loading from SQLite database first
    local dbZones = GWRP.Database and GWRP.Database.LoadTurfZones and GWRP.Database.LoadTurfZones(mapKey)
    if dbZones and table.Count(dbZones) > 0 then
        GWRP.Turf.Zones = dbZones
        print(string.format("[GWRP-Turf] Loaded %d turf zones from SQLite for map '%s'.", table.Count(dbZones), mapKey))
        return
    end

    -- 2. Fallback to existing JSON profile
    local path = GWRP.Turf.GetProfilePath()
    if file.Exists(path, "DATA") then
        local raw = file.Read(path, "DATA")
        local tbl = util.JSONToTable(raw) or {}

        for _, item in ipairs(tbl) do
            local id = tonumber(item.id) or (#GWRP.Turf.Zones + 1)
            GWRP.Turf.Zones[id] = {
                id = id,
                name = item.name or ("Turf Zone #" .. id),
                pos = Vector(item.pos.x, item.pos.y, item.pos.z),
                radius = tonumber(item.radius) or 450,
                owner = item.owner or "neutral",
                progress = tonumber(item.progress) or 100
            }
        end
        -- Migrate to SQLite
        GWRP.Turf.SaveMapProfile()
        print(string.format("[GWRP-Turf] Migrated %d zones from JSON profile into SQLite.", table.Count(GWRP.Turf.Zones)))
        return
    end

    -- 3. Check built-in template for this map
    local defaults = GWRP.Turf.DefaultTemplates[mapKey]
    if defaults then
        for id, zone in pairs(defaults) do
            GWRP.Turf.Zones[id] = {
                id = id,
                name = zone.name,
                pos = Vector(zone.pos.x, zone.pos.y, zone.pos.z),
                radius = zone.radius,
                owner = zone.owner,
                progress = zone.progress or 100
            }
        end
        GWRP.Turf.SaveMapProfile()
        print(string.format("[GWRP-Turf] Seeded default template into SQLite for map '%s'.", mapKey))
    else
        print(string.format("[GWRP-Turf] No saved profile for '%s'. Admins can use /turfsetup to create zones.", mapKey))
    end
end

function GWRP.Turf.SpawnPoles()
    -- Clean up any existing flag poles
    for _, ent in ipairs(ents.FindByClass("gwrp_flag_pole")) do
        if IsValid(ent) then ent:Remove() end
    end

    -- Spawn configured flag poles
    for id, zone in pairs(GWRP.Turf.Zones) do
        local pole = ents.Create("gwrp_flag_pole")
        if IsValid(pole) then
            pole:SetPos(zone.pos)
            pole:SetTurfID(id)
            pole:Spawn()
            pole:Activate()
            zone.entity = pole
        end
    end
end

function GWRP.Turf.Init()
    GWRP.Turf.LoadMapProfile()
    GWRP.Turf.SpawnPoles()

    -- Dividend Timer
    timer.Create("GWRP_TurfDividends", GWRP.Config.TurfDividendInterval, 0, function()
        GWRP.Turf.DistributeDividends()
    end)
end

function GWRP.Turf.SyncToPlayer(ply)
    local count = table.Count(GWRP.Turf.Zones)
    net.Start("GWRP_SyncTurfZones")
        net.WriteUInt(count, 8)
        for id, zone in pairs(GWRP.Turf.Zones) do
            net.WriteUInt(id, 8)
            net.WriteString(zone.name)
            net.WriteVector(zone.pos)
            net.WriteUInt(zone.radius or 450, 16)
            net.WriteString(zone.owner or "neutral")
            net.WriteUInt(zone.progress or 100, 8)
        end
    net.Send(ply)
end

function GWRP.Turf.SyncToAll()
    local count = table.Count(GWRP.Turf.Zones)
    net.Start("GWRP_SyncTurfZones")
        net.WriteUInt(count, 8)
        for id, zone in pairs(GWRP.Turf.Zones) do
            net.WriteUInt(id, 8)
            net.WriteString(zone.name)
            net.WriteVector(zone.pos)
            net.WriteUInt(zone.radius or 450, 16)
            net.WriteString(zone.owner or "neutral")
            net.WriteUInt(zone.progress or 100, 8)
        end
    net.Broadcast()
end

function GWRP.Turf.BroadcastUpdate(turfId)
    local zone = GWRP.Turf.Zones[turfId]
    if not zone then return end

    net.Start("GWRP_TurfUpdate")
        net.WriteUInt(turfId, 8)
        net.WriteString(zone.owner or "neutral")
        net.WriteUInt(zone.progress or 100, 8)
    net.Broadcast()
end

function GWRP.Turf.CaptureFlag(turfId, ply)
    local zone = GWRP.Turf.Zones[turfId]
    if not zone or not IsValid(ply) then return end

    local faction = ply:GetFaction()
    if not faction or faction.id == "neutral" then
        GWRP.Notify(ply, "Join a Gang or Police (F4) to contest turf!", NOTIFY_ERROR)
        return
    end

    local claimant = ""
    if faction.id == "police" then
        claimant = "Police"
    else
        claimant = ply:GetGang()
        if claimant == "" then
            GWRP.Notify(ply, "You must create or join a player gang first! Type: /creategang <name>", NOTIFY_ERROR)
            return
        end
    end

    if string.lower(zone.owner or "") == string.lower(claimant) then
        GWRP.Notify(ply, zone.name .. " is already controlled by " .. claimant .. "!", NOTIFY_GENERIC)
        return
    end

    -- If a pole entity exists, trigger its progressive use
    if IsValid(zone.entity) and zone.entity:GetClass() == "gwrp_flag_pole" then
        zone.entity:Use(ply, ply)
        return
    end

    GWRP.Turf.FinalizeCapture(turfId, ply, claimant)
end

function GWRP.Turf.FinalizeCapture(turfId, ply, claimant)
    local zone = GWRP.Turf.Zones[turfId]
    if not zone then return end

    zone.owner = claimant
    zone.progress = 100
    GWRP.Turf.BroadcastUpdate(turfId)

    if IsValid(ply) then
        ply:AddMoney(GWRP.Config.TurfCaptureReward)
        if ply.AddXP then
            ply:AddXP((GWRP.Config and GWRP.Config.Level and GWRP.Config.Level.XP_TurfCapture) or 150, "Turf Zone Capture")
        end
        GWRP.Notify(ply, "Captured " .. zone.name .. " for " .. claimant .. "! (+$" .. GWRP.Config.TurfCaptureReward .. " bonus)", NOTIFY_GENERIC)
        GWRP.NotifyAll(string.format("%s captured %s for %s", ply:Nick(), zone.name, claimant), NOTIFY_HINT, 6)
    else
        GWRP.NotifyAll(string.format("%s was captured for %s", zone.name, claimant), NOTIFY_HINT, 6)
    end
end

function GWRP.Turf.DistributeDividends()
    local payouts = {}

    for _, zone in pairs(GWRP.Turf.Zones) do
        local owner = zone.owner
        if owner and owner ~= "neutral" and owner ~= "" then
            payouts[string.lower(owner)] = (payouts[string.lower(owner)] or 0) + GWRP.Config.TurfDividendAmount
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
                ply:AddXP((GWRP.Config and GWRP.Config.Level and GWRP.Config.Level.XP_TurfHoldTick) or 25, "Territory Domination")
            end
            GWRP.Notify(ply, string.format("Earned +$%d dividend from controlled territories (%s)", amount, claim), NOTIFY_GENERIC)
        end
    end
end

-- ==========================================
-- ADMIN SETUP COMMANDS & NETWORK HANDLERS
-- ==========================================

local function CanUseAdminSetup(ply)
    return IsValid(ply) and (ply:IsAdmin() or ply:IsSuperAdmin())
end

-- Console command for setup tool
concommand.Add("gwrp_turfsetup", function(ply)
    if not CanUseAdminSetup(ply) then
        GWRP.Notify(ply, "Access Denied: Admins only!", NOTIFY_ERROR)
        return
    end
    net.Start("GWRP_OpenTurfSetup")
    net.Send(ply)
end)

-- Chat command for setup tool
hook.Add("PlayerSay", "GWRP_TurfSetupChatCommand", function(ply, text)
    local lower = string.lower(string.Trim(text))
    if lower == "/turfsetup" or lower == "!turfsetup" or lower == "/adminsetup" or lower == "!adminsetup" then
        if not CanUseAdminSetup(ply) then
            GWRP.Notify(ply, "Access Denied: Admins only!", NOTIFY_ERROR)
            return ""
        end
        net.Start("GWRP_OpenTurfSetup")
        net.Send(ply)
        return ""
    end
end)

-- Admin action receiver
net.Receive("GWRP_AdminTurfAction", function(len, ply)
    if not CanUseAdminSetup(ply) then return end

    local action = net.ReadString()

    -- Ensure Zones table is initialized
    GWRP.Turf.Zones = GWRP.Turf.Zones or {}

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
        while GWRP.Turf.Zones[newId] ~= nil do
            newId = newId + 1
        end

        GWRP.Turf.Zones[newId] = {
            id = newId,
            name = name,
            pos = pos,
            radius = radius,
            owner = initialOwner,
            progress = 100
        }

        -- Spawn Entity
        local pole = ents.Create("gwrp_flag_pole")
        if IsValid(pole) then
            pole:SetPos(pos)
            pole:SetTurfID(newId)
            pole:Spawn()
            pole:Activate()
            GWRP.Turf.Zones[newId].entity = pole
        end

        GWRP.Turf.SaveMapProfile()
        GWRP.Turf.SyncToAll()
        GWRP.Notify(ply, string.format("Added Turf Pole #%d: '%s' at position!", newId, name), NOTIFY_GENERIC)

    -- 2. EDIT EXISTING TURF FLAG POLE
    elseif action == "edit" then
        local id = net.ReadUInt(8)
        local name = net.ReadString()
        local pos = net.ReadVector()
        local radius = net.ReadUInt(16)
        local owner = net.ReadString()

        local zone = GWRP.Turf.Zones[id]
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

        GWRP.Turf.SaveMapProfile()
        GWRP.Turf.SyncToAll()
        GWRP.Notify(ply, string.format("Updated Turf Pole #%d: '%s'!", id, name), NOTIFY_GENERIC)

    -- 3. REMOVE TURF FLAG POLE
    elseif action == "remove" or action == "delete" then
        local id = net.ReadUInt(8)
        local zone = GWRP.Turf.Zones[id]
        if not zone then return end

        if IsValid(zone.entity) then
            zone.entity:Remove()
        end

        GWRP.Turf.Zones[id] = nil
        GWRP.Turf.SaveMapProfile()
        GWRP.Turf.SyncToAll()
        GWRP.Notify(ply, string.format("Removed Turf Pole #%d!", id), NOTIFY_GENERIC)

    -- 4. TELEPORT TO TURF FLAG POLE
    elseif action == "teleport" then
        local id = net.ReadUInt(8)
        local zone = GWRP.Turf.Zones[id]
        if not zone then return end

        ply:SetPos(zone.pos + Vector(0, 0, 15))
        GWRP.Notify(ply, string.format("Teleported to Turf #%d: '%s'!", id, zone.name), NOTIFY_GENERIC)

    -- 5. SAVE PROFILE TO DISK
    elseif action == "save" then
        GWRP.Turf.SaveMapProfile()
        GWRP.Notify(ply, "Saved all turf flag poles to map profile (" .. game.GetMap() .. ".json)!", NOTIFY_GENERIC)

    -- 6. RELOAD PROFILE FROM DISK
    elseif action == "reload" then
        GWRP.Turf.LoadMapProfile()
        GWRP.Turf.SpawnPoles()
        GWRP.Turf.SyncToAll()
        GWRP.Notify(ply, "Reloaded turf flag poles from map profile!", NOTIFY_GENERIC)

    -- 7. CLEAR ALL TURF POLES
    elseif action == "clear" then
        for id, zone in pairs(GWRP.Turf.Zones) do
            if IsValid(zone.entity) then zone.entity:Remove() end
        end
        GWRP.Turf.Zones = {}
        GWRP.Turf.SaveMapProfile()
        GWRP.Turf.SyncToAll()
        GWRP.Notify(ply, "Cleared all turf flag poles from current map!", NOTIFY_GENERIC)
    end
end)
