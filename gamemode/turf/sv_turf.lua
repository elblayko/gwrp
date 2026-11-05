--[[
    sv_turf.lua - Server Turf Engine, Per-Map Profile Persistence & Admin Setup
--]]

GRID = GRID or {}
GRID.Turf = GRID.Turf or {}

function GRID.Turf.GetProfilePath()
    local map = string.lower(game.GetMap())
    return "gridrp/maps/" .. map .. ".json"
end

function GRID.Turf.SaveMapProfile()
    local mapName = game.GetMap()

    -- 1. Primary Persistence: Save directly to MariaDB via stored procedures
    if GRID.Database and GRID.Database.SaveTurfZones then
        GRID.Database.SaveTurfZones(mapName, GRID.Turf.Zones)
    end

    -- 2. Secondary Export: JSON snapshot for backup
    file.CreateDir("gridrp/maps")
    local serializable = {}
    for id, zone in pairs(GRID.Turf.Zones) do
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
    file.Write(GRID.Turf.GetProfilePath(), json)
    print(string.format("[GRID-Turf] Saved %d turf zones to MariaDB & JSON profile for '%s'.", #serializable, mapName))
    return true
end

function GRID.Turf.LoadMapProfile()
    local mapKey = string.lower(game.GetMap())
    GRID.Turf.Zones = {}

    -- 1. Try loading from MariaDB database first
    local dbZones = GRID.Database and GRID.Database.LoadTurfZones and GRID.Database.LoadTurfZones(mapKey)
    if dbZones and table.Count(dbZones) > 0 then
        GRID.Turf.Zones = dbZones
        print(string.format("[GRID-Turf] Loaded %d turf zones from MariaDB for map '%s'.", table.Count(dbZones), mapKey))
        return
    end

    -- 2. Fallback to existing JSON profile
    local path = GRID.Turf.GetProfilePath()

    if file.Exists(path, "DATA") then
        local raw = file.Read(path, "DATA")
        local tbl = util.JSONToTable(raw) or {}

        for _, item in ipairs(tbl) do
            local id = tonumber(item.id) or (#GRID.Turf.Zones + 1)
            GRID.Turf.Zones[id] = {
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
        GRID.Turf.SaveMapProfile()
        print(string.format("[GridRP-Turf] Migrated %d zones from JSON profile into SQLite.", table.Count(GRID.Turf.Zones)))
        return
    end

    -- 3. Check built-in template for this map
    local defaults = GRID.Turf.DefaultTemplates and GRID.Turf.DefaultTemplates[mapKey]
    if defaults then
        for id, zone in pairs(defaults) do
            GRID.Turf.Zones[id] = {
                id = id,
                name = zone.name,
                pos = Vector(zone.pos.x, zone.pos.y, zone.pos.z),
                radius = zone.radius,
                owner = zone.owner,
                progress = zone.progress or 100,
                tax_rate = tonumber(zone.tax_rate) or 10
            }
        end
        GRID.Turf.SaveMapProfile()
        print(string.format("[GridRP-Turf] Seeded default template into SQLite for map '%s'.", mapKey))
    else
        print(string.format("[GridRP-Turf] No saved profile for '%s'. Admins can use /turfsetup to create zones.", mapKey))
    end
end

function GRID.Turf.SpawnPoles()
    -- Clean up any existing flag poles
    for _, ent in ipairs(ents.FindByClass("grid_flag_pole")) do
        if IsValid(ent) then ent:Remove() end
    end

    -- Spawn configured flag poles
    for id, zone in pairs(GRID.Turf.Zones) do
        local pole = ents.Create("grid_flag_pole")
        if IsValid(pole) then
            pole:SetPos(zone.pos)
            pole:SetTurfID(id)
            pole:Spawn()
            pole:Activate()
            zone.entity = pole
        end
    end
end

function GRID.Turf.Init()
    GRID.Turf.LoadMapProfile()
    GRID.Turf.SpawnPoles()

    -- Dividend Timer
    timer.Create("GRID_TurfDividends", (GRID.Config and GRID.Config.TurfDividendInterval) or 90, 0, function()
        GRID.Turf.DistributeDividends()
    end)
end

function GRID.Turf.SyncToPlayer(ply)
    local count = table.Count(GRID.Turf.Zones)
    net.Start("GRID_SyncTurfZones")
        net.WriteUInt(count, 8)
        for id, zone in pairs(GRID.Turf.Zones) do
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

function GRID.Turf.SyncToAll()
    local count = table.Count(GRID.Turf.Zones)
    net.Start("GRID_SyncTurfZones")
        net.WriteUInt(count, 8)
        for id, zone in pairs(GRID.Turf.Zones) do
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

function GRID.Turf.BroadcastUpdate(turfId)
    local zone = GRID.Turf.Zones[turfId]
    if not zone then return end

    net.Start("GRID_TurfUpdate")
        net.WriteUInt(turfId, 8)
        net.WriteString(zone.owner or "neutral")
        net.WriteUInt(zone.progress or 100, 8)
        net.WriteUInt(zone.tax_rate or 10, 8)
    net.Broadcast()
end

function GRID.Turf.CaptureFlag(turfId, ply)
    local zone = GRID.Turf.Zones[turfId]
    if not zone or not IsValid(ply) then return end

    local faction = ply:GetFaction()
    if not faction or faction.id == "neutral" then
        GRID.Notify(ply, "Join a Gang or Police (F4) to contest turf!", NOTIFY_ERROR)
        return
    end

    local claimant = ""
    if faction.id == "police" then
        claimant = "Police"
    else
        claimant = ply:GetGang()
        if claimant == "" then
            GRID.Notify(ply, "You must create or join a player gang first! Type: /creategang <name>", NOTIFY_ERROR)
            return
        end
    end

    if string.lower(zone.owner or "") == string.lower(claimant) then
        GRID.Notify(ply, zone.name .. " is already controlled by " .. claimant .. "!", NOTIFY_GENERIC)
        return
    end

    -- If a pole entity exists, trigger its progressive use
    if IsValid(zone.entity) and zone.entity:GetClass() == "grid_flag_pole" then
        zone.entity:Use(ply, ply)
        return
    end

    GRID.Turf.FinalizeCapture(turfId, ply, claimant)
end

function GRID.Turf.FinalizeCapture(turfId, ply, claimant)
    local zone = GRID.Turf.Zones[turfId]
    if not zone then return end

    zone.owner = claimant
    zone.progress = 100
    GRID.Turf.BroadcastUpdate(turfId)

    local reward = (GRID.Config and GRID.Config.TurfCaptureReward) or 40
    if IsValid(ply) then
        ply:AddMoney(reward)
        if ply.AddXP then
            ply:AddXP((GRID.Config and GRID.Config.Level and GRID.Config.Level.XP_TurfCapture) or 150, "Turf Zone Capture")
        end
        GRID.Notify(ply, "Captured " .. zone.name .. " for " .. claimant .. "! (+$" .. reward .. " bonus)", NOTIFY_GENERIC)
        GRID.NotifyAll(string.format("%s captured %s for %s", ply:Nick(), zone.name, claimant), NOTIFY_HINT, 6)
    else
        GRID.NotifyAll(string.format("%s was captured for %s", zone.name, claimant), NOTIFY_HINT, 6)
    end
end

function GRID.Turf.DistributeDividends()
    local payouts = {}
    local divAmount = (GRID.Config and GRID.Config.TurfDividendAmount) or 25

    for _, zone in pairs(GRID.Turf.Zones) do
        local owner = zone.owner
        if owner and owner ~= "neutral" and owner ~= "" then
            payouts[string.lower(owner)] = (payouts[string.lower(owner)] or 0) + divAmount
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
                ply:AddXP((GRID.Config and GRID.Config.Level and GRID.Config.Level.XP_TurfHoldTick) or 25, "Territory Domination")
            end
            GRID.Notify(ply, string.format("Earned +$%d dividend from controlled territories (%s)", amount, claim), NOTIFY_GENERIC)
        end
    end
end

-- ==========================================
-- TURF TAX & INCURSION ALERTS
-- ==========================================

function GRID.Turf.SetTaxRate(turfId, taxRate, ply)
    local zone = GRID.Turf.Zones[turfId]
    if not zone then
        if IsValid(ply) then GRID.Notify(ply, "Invalid turf zone!", NOTIFY_ERROR) end
        return false
    end

    taxRate = math.Clamp(math.Round(tonumber(taxRate) or 10), 5, 30)

    if IsValid(ply) then
        local pGang = ply:GetGang()
        local isLeader = ply:GetNWBool("GRID_IsGangLeader", false) or (ply.GetJob and ply:GetJob() == "gang_leader") or ply:IsAdmin()
        if not isLeader then
            GRID.Notify(ply, "Only the Gang Leader can adjust territory protection taxes!", NOTIFY_ERROR)
            return false
        end

        if not ply:IsAdmin() and (pGang == "" or string.lower(pGang) ~= string.lower(zone.owner or "")) then
            GRID.Notify(ply, "Your gang does not control this territory!", NOTIFY_ERROR)
            return false
        end
    end

    zone.tax_rate = taxRate

    if GRID.Database and GRID.Database.SetTurfTax then
        GRID.Database.SetTurfTax(game.GetMap(), turfId, taxRate)
    end
    GRID.Turf.SaveMapProfile()
    GRID.Turf.BroadcastUpdate(turfId)

    if IsValid(ply) then
        GRID.Notify(ply, string.format("Set protection tax for %s to %d%%!", zone.name, taxRate), NOTIFY_GENERIC)
    end

    -- Broadcast notification to online gang members
    if zone.owner and zone.owner ~= "" and zone.owner ~= "neutral" and zone.owner ~= "Police" then
        for _, p in ipairs(player.GetAll()) do
            if string.lower(p:GetGang()) == string.lower(zone.owner) and p ~= ply then
                GRID.Notify(p, string.format("[GANG] Protection tax in %s was set to %d%%.", zone.name, taxRate), NOTIFY_HINT, 4)
            end
        end
    end

    return true
end

function GRID.Turf.SendIncursionAlert(zone, alertMsg)
    if not zone or not zone.owner or zone.owner == "" or zone.owner == "neutral" or zone.owner == "Police" then return end

    local alertText = alertMsg or string.format("POLICE INCURSION in %s! Defend your district and paying civilians!", zone.name)
    for _, p in ipairs(player.GetAll()) do
        if string.lower(p:GetGang()) == string.lower(zone.owner) then
            p:EmitSound("ambient/alarms/klaxon1.wav", 75, 120, 0.7)
            GRID.Notify(p, "[DISTRICT ALERT] " .. alertText, NOTIFY_ERROR, 8)
        end
    end
end

local function HandleSetTurfTax(len, ply)
    if not IsValid(ply) then return end
    if not GRID.CheckRateLimit(ply, "turf_set_tax", 1.0) then return end

    local turfId = net.ReadUInt(8)
    local taxRate = net.ReadUInt(8)
    GRID.Turf.SetTaxRate(turfId, taxRate, ply)
end

net.Receive("GRID_SetTurfTax", HandleSetTurfTax)

-- ==========================================
-- ADMIN SETUP COMMANDS & NETWORK HANDLERS
-- ==========================================

local function CanUseAdminSetup(ply)
    return IsValid(ply) and (ply:IsAdmin() or ply:IsSuperAdmin())
end

local function OpenTurfSetup(ply)
    if not CanUseAdminSetup(ply) then
        GRID.Notify(ply, "Access Denied: Admins only!", NOTIFY_ERROR)
        return
    end
    net.Start("GRID_OpenTurfSetup")
    net.Send(ply)
end

concommand.Add("grid_turfsetup", OpenTurfSetup)

-- Chat command for setup tool
hook.Add("PlayerSay", "GRID_TurfSetupChatCommand", function(ply, text)
    local lower = string.lower(string.Trim(text))
    if lower == "/turfsetup" or lower == "!turfsetup" or lower == "/adminsetup" or lower == "!adminsetup" then
        OpenTurfSetup(ply)
        return ""
    end
end)

-- Admin action receiver
local function HandleAdminTurfAction(len, ply)
    if not CanUseAdminSetup(ply) then return end

    local action = net.ReadString()
    GRID.Turf.Zones = GRID.Turf.Zones or {}

    -- 1. ADD NEW TURF FLAG POLE
    if action == "add" or action == "create" then
        local name = net.ReadString()
        local pos = net.ReadVector()
        local radius = net.ReadUInt(16)
        local initialOwner = net.ReadString()

        if name == "" then name = "New Territory" end
        if radius < 50 then radius = 450 end
        if initialOwner == "" then initialOwner = "neutral" end

        local newId = 1
        while GRID.Turf.Zones[newId] ~= nil do
            newId = newId + 1
        end

        GRID.Turf.Zones[newId] = {
            id = newId,
            name = name,
            pos = pos,
            radius = radius,
            owner = initialOwner,
            progress = 100
        }

        local pole = ents.Create("grid_flag_pole")
        if IsValid(pole) then
            pole:SetPos(pos)
            pole:SetTurfID(newId)
            pole:Spawn()
            pole:Activate()
            GRID.Turf.Zones[newId].entity = pole
        end

        GRID.Turf.SaveMapProfile()
        GRID.Turf.SyncToAll()
        GRID.Notify(ply, string.format("Added Turf Pole #%d: '%s' at position!", newId, name), NOTIFY_GENERIC)

    -- 2. EDIT EXISTING TURF FLAG POLE
    elseif action == "edit" then
        local id = net.ReadUInt(8)
        local name = net.ReadString()
        local pos = net.ReadVector()
        local radius = net.ReadUInt(16)
        local owner = net.ReadString()

        local zone = GRID.Turf.Zones[id]
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

        GRID.Turf.SaveMapProfile()
        GRID.Turf.SyncToAll()
        GRID.Notify(ply, string.format("Updated Turf Pole #%d: '%s'!", id, name), NOTIFY_GENERIC)

    -- 3. REMOVE TURF FLAG POLE
    elseif action == "remove" or action == "delete" then
        local id = net.ReadUInt(8)
        local zone = GRID.Turf.Zones[id]
        if not zone then return end

        if IsValid(zone.entity) then
            zone.entity:Remove()
        end

        GRID.Turf.Zones[id] = nil
        GRID.Turf.SaveMapProfile()
        GRID.Turf.SyncToAll()
        GRID.Notify(ply, string.format("Removed Turf Pole #%d!", id), NOTIFY_GENERIC)

    -- 4. TELEPORT TO TURF FLAG POLE
    elseif action == "teleport" then
        local id = net.ReadUInt(8)
        local zone = GRID.Turf.Zones[id]
        if not zone then return end

        ply:SetPos(zone.pos + Vector(0, 0, 15))
        GRID.Notify(ply, string.format("Teleported to Turf #%d: '%s'!", id, zone.name), NOTIFY_GENERIC)

    -- 5. SAVE PROFILE TO DISK
    elseif action == "save" then
        GRID.Turf.SaveMapProfile()
        GRID.Notify(ply, "Saved all turf flag poles to map profile (" .. game.GetMap() .. ".json)!", NOTIFY_GENERIC)

    -- 6. RELOAD PROFILE FROM DISK
    elseif action == "reload" then
        GRID.Turf.LoadMapProfile()
        GRID.Turf.SpawnPoles()
        GRID.Turf.SyncToAll()
        GRID.Notify(ply, "Reloaded turf flag poles from map profile!", NOTIFY_GENERIC)

    -- 7. CLEAR ALL TURF POLES
    elseif action == "clear" then
        for id, zone in pairs(GRID.Turf.Zones) do
            if IsValid(zone.entity) then zone.entity:Remove() end
        end
        GRID.Turf.Zones = {}
        GRID.Turf.SaveMapProfile()
        GRID.Turf.SyncToAll()
        GRID.Notify(ply, "Cleared all turf flag poles from current map!", NOTIFY_GENERIC)
    end
end

net.Receive("GRID_AdminTurfAction", HandleAdminTurfAction)
