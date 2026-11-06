--[[
    gamemode/core/sv_scavenge_spawner.lua
    GridRP Scavenge Node & Recycler Depot Map Spawner & Database / JSON Persistence
    Author: Juicebox & Antigravity
--]]

GRID = GRID or {}
GRID.Scavenge = GRID.Scavenge or {}
GRID.Scavenge.SpawnedEntities = GRID.Scavenge.SpawnedEntities or {}

local DATA_DIR = "gridrp/scavenge"

local function GetFilePath()
    local map = string.lower(game.GetMap())
    return DATA_DIR .. "/" .. map .. ".json"
end

local function GetDBKey()
    return "scavenge_nodes_" .. string.lower(game.GetMap())
end

--- Clears all currently tracked scavenge nodes and recyclers from the world
function GRID.Scavenge.ClearSpawned()
    for _, ent in ipairs(GRID.Scavenge.SpawnedEntities) do
        if IsValid(ent) then
            ent:Remove()
        end
    end
    GRID.Scavenge.SpawnedEntities = {}
end

--- Spawns an individual scavenge entity, anchors it, and tracks it
-- @param class Entity class name
-- @param pos Vector position
-- @param ang Angle orientation
-- @param alignGround Boolean indicating whether pos is a ground hit contact point that needs upward model offset
function GRID.Scavenge.SpawnNode(class, pos, ang, alignGround)
    local ent = ents.Create(class)
    if not IsValid(ent) then
        print(string.format("[GRID-Scavenge] Failed to create entity class '%s'", tostring(class)))
        return nil
    end

    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:Spawn()
    ent:Activate()

    -- When spawned onto a floor surface (e.g. crosshair hit point),
    -- elevate the entity by the bottom bound height so it rests flush on the ground instead of sinking.
    if alignGround then
        local mins = ent:OBBMins()
        if mins and mins.z < -1 then
            local elevation = math.abs(mins.z) + 1.0
            ent:SetPos(pos + Vector(0, 0, elevation))
        end
    end

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Wake()
    end

    table.insert(GRID.Scavenge.SpawnedEntities, ent)
    return ent
end

--- Saves the currently spawned nodes to both the MariaDB/SQLite Database and the JSON file snapshot
function GRID.Scavenge.SaveMapProfile()
    local map = string.lower(game.GetMap())
    local records = {}

    -- Clean up invalid entries and gather coordinates
    local cleanedList = {}
    for _, ent in ipairs(GRID.Scavenge.SpawnedEntities) do
        if IsValid(ent) then
            table.insert(cleanedList, ent)
            local pos = ent:GetPos()
            local ang = ent:GetAngles()
            table.insert(records, {
                class = ent:GetClass(),
                pos = { x = math.Round(pos.x, 2), y = math.Round(pos.y, 2), z = math.Round(pos.z, 2) },
                ang = { p = math.Round(ang.p, 2), y = math.Round(ang.y, 2), r = math.Round(ang.r, 2) }
            })
        end
    end
    GRID.Scavenge.SpawnedEntities = cleanedList

    local json = util.TableToJSON(records, true)

    -- 1. Primary Persistence: Save directly to MariaDB / SQLite grid_settings table
    local dbKey = GetDBKey()
    if GRID.Database and GRID.Database.SetSetting then
        GRID.Database.SetSetting(dbKey, json)
    end

    -- 2. Secondary Export: JSON snapshot on disk for backup & human inspection
    file.CreateDir(DATA_DIR)
    local filePath = GetFilePath()
    file.Write(filePath, json)

    print(string.format("[GRID-Scavenge] Saved %d scavenge/recycler nodes to Database (key: '%s') & JSON profile '%s'.",
        #records, dbKey, filePath))
    return true
end

--- Loads and spawns the scavenge nodes from Database, JSON profile, or built-in fallback
function GRID.Scavenge.LoadAndSpawn()
    GRID.Scavenge.ClearSpawned()

    local map = string.lower(game.GetMap())
    local dbKey = GetDBKey()
    local filePath = GetFilePath()
    local records = nil
    local loadSource = "none"

    -- 1. Attempt load from Database (grid_settings)
    if GRID.Database and GRID.Database.GetSetting then
        local raw = GRID.Database.GetSetting(dbKey)
        if raw and raw ~= "" then
            records = util.JSONToTable(raw)
            if records and #records > 0 then
                loadSource = "Database ('" .. dbKey .. "')"
            end
        end
    end

    -- 2. Fallback to JSON snapshot on disk
    if not records or #records == 0 then
        if file.Exists(filePath, "DATA") then
            local raw = file.Read(filePath, "DATA")
            records = util.JSONToTable(raw)
            if records and #records > 0 then
                loadSource = "JSON Snapshot ('" .. filePath .. "')"
                -- Sync back to database
                if GRID.Database and GRID.Database.SetSetting then
                    GRID.Database.SetSetting(dbKey, raw)
                end
            end
        end
    end

    -- 3. If no saved profile exists yet for this map
    if not records or #records == 0 then
        print(string.format(
        "[GRID-Scavenge] No saved scavenge profile for map '%s'. Admins can place nodes via F4 Admin HUD.", map))
        return
    end

    local count = 0
    for _, data in ipairs(records) do
        local pos = Vector(data.pos.x, data.pos.y, data.pos.z)
        local ang = Angle(data.ang.p, data.ang.y, data.ang.r)
        local ent = GRID.Scavenge.SpawnNode(data.class, pos, ang)
        if IsValid(ent) then
            count = count + 1
        end
    end

    print(string.format("[GRID-Scavenge] Successfully loaded %d nodes/depots from %s.", count, loadSource))
end

-- Map initialization and cleanup hooks
hook.Add("InitPostEntity", "GRID_Scavenge_InitPostEntity", function()
    timer.Simple(2.5, function()
        GRID.Scavenge.LoadAndSpawn()
    end)
end)

hook.Add("PostCleanupMap", "GRID_Scavenge_PostCleanupMap", function()
    GRID.Scavenge.LoadAndSpawn()
end)

-- Admin chat & console commands
local CLASS_ALIASES = {
    ["dumpster"] = "grid_scavenge_dumpster",
    ["trash"] = "grid_scavenge_trashbin",
    ["trashbin"] = "grid_scavenge_trashbin",
    ["scrap"] = "grid_scavenge_scrappile",
    ["scrappile"] = "grid_scavenge_scrappile",
    ["recycler"] = "grid_recycler_depot",
    ["depot"] = "grid_recycler_depot"
}

concommand.Add("grid_scavenge_add", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        GRID.Notify(ply, "You do not have permission to place scavenge nodes.", NOTIFY_ERROR)
        return
    end

    local alias = string.lower(args[1] or "dumpster")
    local class = CLASS_ALIASES[alias] or alias

    local tr
    local ang
    if IsValid(ply) then
        tr = ply:GetEyeTrace()
        ang = Angle(0, ply:EyeAngles().y + 180, 0)
    else
        print("Usage: grid_scavenge_add <dumpster|trash|scrap|recycler> (must be run as player)")
        return
    end

    if not tr.Hit then return end

    local ent = GRID.Scavenge.SpawnNode(class, tr.HitPos, ang, true)
    if IsValid(ent) then
        GRID.Scavenge.SaveMapProfile()
        GRID.Notify(ply, string.format("Spawned %s and saved to Database & Map JSON Profile.", class), NOTIFY_GENERIC)
    else
        GRID.Notify(ply, string.format("Invalid class '%s'. Valid: dumpster, trash, scrap, recycler.", tostring(class)),
            NOTIFY_ERROR)
    end
end)

concommand.Add("grid_scavenge_save", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    GRID.Scavenge.SaveMapProfile()
    if IsValid(ply) then
        GRID.Notify(ply, "Scavenge & recycler nodes saved to Database & Map JSON Profile.", NOTIFY_GENERIC)
    end
end)

concommand.Add("grid_scavenge_respawn", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    GRID.Scavenge.LoadAndSpawn()
    if IsValid(ply) then
        GRID.Notify(ply, "Reloaded and respawned all scavenge nodes from Database/JSON.", NOTIFY_GENERIC)
    end
end)

concommand.Add("grid_scavenge_clear", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    GRID.Scavenge.ClearSpawned()
    GRID.Scavenge.SaveMapProfile()
    if IsValid(ply) then
        GRID.Notify(ply, "Cleared all scavenge nodes from map and updated Database & JSON Profile.", NOTIFY_HINT)
    end
end)
