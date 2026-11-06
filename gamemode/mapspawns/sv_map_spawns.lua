--[[
    gamemode/mapspawns/sv_map_spawns.lua
    Persistent World Entity Management (GRID.MapSpawns) - Server Engine
    Author: GRID Core Team & Antigravity
--]]

GRID = GRID or {}
GRID.MapSpawns = GRID.MapSpawns or {}

-- --------------------------------------------------------
-- World Protection & Engine Hardening (Safeguards 2, 3, 4)
-- --------------------------------------------------------

--- Applies comprehensive world ownership, FPP decoupling, and anti-duplicator flags
-- @param ent Entity
function GRID.MapSpawns.ApplyWorldProtection(ent)
    if not IsValid(ent) then return end

    -- Core identity flags
    ent.GRID_IsPersistentMapEntity = true
    ent:SetNWBool("GRID_MapEntity", true)
    if ent.GRID_MapSpawnID then
        ent:SetNWInt("GRID_MapSpawnID", ent.GRID_MapSpawnID)
    end

    -- Safeguard 4: Anti-Duplicator / AdvDupe2 protection
    ent.DoNotDuplicate = true
    local entTable = scripted_ents.GetStored(ent:GetClass())
    if entTable and entTable.t then
        entTable.t.DisableDuplicator = true
    end

    -- Safeguard 3: Prevent FPP / Prop Protection disconnect wipe
    ent:SetCreator(NULL)
    ent:SetOwner(NULL)
    if ent.CPPISetWorld then
        ent:CPPISetWorld()
    elseif ent.CPPISetOwner then
        ent:CPPISetOwner(game.GetWorld())
    end
    ent.FPPOwner = game.GetWorld()
end

--- Spawns an individual persistent entity from a database row with Havok collision resolution fix
-- @param row Table Database record from v_grid_map_spawns
-- @return Entity|nil
function GRID.MapSpawns.SpawnPersistentEntity(row)
    if not istable(row) or not row.class_name then return nil end

    local className = row.class_name
    local pos = Vector(tonumber(row.pos_x) or 0, tonumber(row.pos_y) or 0, tonumber(row.pos_z) or 0)
    local ang = Angle(tonumber(row.ang_p) or 0, tonumber(row.ang_y) or 0, tonumber(row.ang_r) or 0)
    local spawnId = tonumber(row.spawn_id) or 0

    local ent = ents.Create(className)
    if not IsValid(ent) then
        ErrorNoHalt(string.format("[GRID MapSpawns ERROR] Failed to create entity class '%s' (Spawn ID #%d)!\n", tostring(className), spawnId))
        return nil
    end

    ent.GRID_MapSpawnID = spawnId
    ent:SetPos(pos)
    ent:SetAngles(ang)

    -- Safeguard 12: TRANSMIT_ALWAYS for objective entities
    if GRID.MapSpawns.TransmitAlwaysClasses[string.lower(className)] or ent.TransmitAlways then
        function ent:UpdateTransmitState()
            return TRANSMIT_ALWAYS
        end
    end

    ent:Spawn()
    ent:Activate()

    -- Safeguard 9: Wall-Ejection / Floor-Sink Physics Fix
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Sleep()
    end
    ent:SetMoveType(MOVETYPE_NONE)

    -- Re-apply coordinates AFTER physics initialization so 1st tick of collision resolution doesn't shift flush entities
    ent:SetPos(pos)
    ent:SetAngles(ang)

    -- Safeguard 2 & 3: World protection and FPP disconnect immunity
    GRID.MapSpawns.ApplyWorldProtection(ent)

    -- Safeguard 10: Per-instance JSON metadata hydration
    if row.custom_data and row.custom_data ~= "" and row.custom_data ~= "NULL" then
        local customTbl = util.JSONToTable(row.custom_data)
        if istable(customTbl) and ent.OnMapDataLoaded then
            pcall(ent.OnMapDataLoaded, ent, customTbl)
        end
    end

    return ent
end

-- --------------------------------------------------------
-- World Loading & Lifecycle Management (Safeguards 7, 8)
-- --------------------------------------------------------

--- Loads all persistent map entities from the database for the active map
function GRID.MapSpawns.LoadAllMapEntities()
    local currentMap = game.GetMap()

    -- Safeguard 8: Lua Auto-Refresh Double-Spawn Prevention
    -- Remove any pre-existing persistent entities, clearing GRID_MapSpawnID first so deletion never touches MariaDB
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent.GRID_IsPersistentMapEntity then
            ent.GRID_MapSpawnID = nil
            ent:Remove()
        end
    end

    print(string.format("[GRID MapSpawns] Loading persistent map entities for '%s'...", currentMap))

    GRID.Database.LoadMapEntities(currentMap, function(rows)
        local spawnedCount = 0
        for _, row in ipairs(rows or {}) do
            local ent = GRID.MapSpawns.SpawnPersistentEntity(row)
            if IsValid(ent) then
                spawnedCount = spawnedCount + 1
            end
        end
        print(string.format("[GRID MapSpawns] Successfully loaded & anchored %d persistent map entities on '%s'.", spawnedCount, currentMap))
    end, function(err)
        ErrorNoHalt(string.format("[GRID MapSpawns ERROR] Failed to query map entities: %s\n", tostring(err)))
    end)
end

-- Safeguard 7: Trigger loading on database connection and PostCleanupMap
hook.Add("GRID_DatabaseConnected", "GRID_MapSpawns_OnDatabaseConnected", function()
    GRID.MapSpawns.LoadAllMapEntities()
end)

hook.Add("PostCleanupMap", "GRID_MapSpawns_OnPostCleanupMap", function()
    GRID.MapSpawns.LoadAllMapEntities()
end)

hook.Add("InitPostEntity", "GRID_MapSpawns_OnInitPostEntity", function()
    if GRID.Database and GRID.Database.Connected then
        GRID.MapSpawns.LoadAllMapEntities()
    end
end)

-- --------------------------------------------------------
-- Live Placement & Q-Menu Spawning
-- --------------------------------------------------------

-- Block non-SuperAdmins from spawning whitelisted persistent SENTs from Q menu
hook.Add("PlayerSpawnSENT", "GRID_MapSpawns_PlayerSpawnSENT", function(ply, class)
    if GRID.MapSpawns.IsWhitelisted(class) then
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            GRID.Notify(ply, "Access Denied: Only SuperAdmins can spawn persistent map entities.", NOTIFY_ERROR)
            return false
        end
    end
end)

-- Live Placement: When a SuperAdmin spawns a whitelisted SENT, save it to MariaDB
hook.Add("PlayerSpawnedSENT", "GRID_MapSpawns_PlayerSpawnedSENT", function(ply, ent)
    if not IsValid(ply) or not ply:IsSuperAdmin() or not IsValid(ent) then return end

    local className = ent:GetClass()
    if not GRID.MapSpawns.IsWhitelisted(className) then return end

    -- Safeguard 9: Freeze motion & lock movetype
    ent:SetMoveType(MOVETYPE_NONE)
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Sleep()
    end
    ent:SetPos(ent:GetPos())
    ent:SetAngles(ent:GetAngles())

    -- Safeguards 2, 3, 4: World protection
    GRID.MapSpawns.ApplyWorldProtection(ent)

    -- Safeguard 10: Check if entity provides initial custom metadata
    local customData = nil
    if ent.GetMapData and isfunction(ent.GetMapData) then
        local ok, data = pcall(ent.GetMapData, ent)
        if ok and istable(data) then customData = data end
    end

    -- Save row to MariaDB (spawn_id = 0 for INSERT)
    local adminSid = ply:SteamID()
    GRID.Database.SaveMapEntity(0, game.GetMap(), className, ent:GetPos(), ent:GetAngles(), adminSid, customData, function(newSpawnId)
        if IsValid(ent) then
            ent.GRID_MapSpawnID = newSpawnId
            ent:SetNWInt("GRID_MapSpawnID", newSpawnId)
            GRID.Notify(ply, string.format("Permanent map entity #%d (%s) saved to MariaDB!", newSpawnId, className), NOTIFY_HINT, 6)
            print(string.format("[GRID MapSpawns] SuperAdmin %s (%s) placed new persistent entity #%d (%s).", ply:Nick(), adminSid, newSpawnId, className))
        end
    end, function(err)
        GRID.Notify(ply, "Failed to save persistent entity to MariaDB! See server console.", NOTIFY_ERROR, 8)
    end)
end)

-- --------------------------------------------------------
-- Live Repositioning & Anti-Prop-Block (Safeguards 6, 9)
-- --------------------------------------------------------

-- Physgun pickup: allow SuperAdmins to temporarily lift and reposition persistent entities
hook.Add("PhysgunPickup", "GRID_MapSpawns_PhysgunPickup", function(ply, ent)
    if IsValid(ent) and ent.GRID_IsPersistentMapEntity then
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            return false
        end

        -- Temporarily unlock physics for fluid movement
        ent:SetMoveType(MOVETYPE_VPHYSICS)
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(true)
            phys:Wake()
        end
        return true
    end
end)

-- On freeze: lock persistent entities back down and update MariaDB, OR enforce prop-block radius on props
hook.Add("OnPhysgunFreeze", "GRID_MapSpawns_OnPhysgunFreeze", function(weapon, phys, ent, ply)
    if not IsValid(ent) then return end

    -- Case 1: SuperAdmin repositioning a persistent map entity
    if ent.GRID_IsPersistentMapEntity then
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            return false
        end

        -- Lock back to MOVETYPE_NONE
        ent:SetMoveType(MOVETYPE_NONE)
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:Sleep()
        end
        ent:SetPos(ent:GetPos())
        ent:SetAngles(ent:GetAngles())

        local spawnId = ent.GRID_MapSpawnID or 0
        local customData = nil
        if ent.GetMapData and isfunction(ent.GetMapData) then
            local ok, data = pcall(ent.GetMapData, ent)
            if ok and istable(data) then customData = data end
        end

        -- Update row in MariaDB
        GRID.Database.SaveMapEntity(spawnId, game.GetMap(), ent:GetClass(), ent:GetPos(), ent:GetAngles(), ply:SteamID(), customData, function(savedId)
            GRID.Notify(ply, string.format("Updated persistent entity #%d position in MariaDB.", savedId), NOTIFY_HINT, 4)
        end)

        return true
    end

    -- Case 2: Safeguard 6 - Anti-Prop-Block radius for regular props
    if IsValid(ply) and not ply:IsSuperAdmin() then
        local nearby = ents.FindInSphere(ent:GetPos(), GRID.MapSpawns.PROP_BLOCK_RADIUS)
        for _, other in ipairs(nearby) do
            if IsValid(other) and other.GRID_IsPersistentMapEntity then
                if IsValid(phys) then
                    phys:EnableMotion(true)
                    phys:Wake()
                end
                GRID.Notify(ply, "Prop-block violation: You cannot freeze objects near persistent world entities (ATMs, Terminals, Safes).", NOTIFY_ERROR)
                return false
            end
        end
    end
end)

-- Safeguard 6: Block non-SuperAdmins from spawning props directly on top of persistent map entities
hook.Add("PlayerSpawnedProp", "GRID_MapSpawns_AntiPropBlockSpawn", function(ply, model, ent)
    if not IsValid(ply) or ply:IsSuperAdmin() or not IsValid(ent) then return end

    local nearby = ents.FindInSphere(ent:GetPos(), GRID.MapSpawns.PROP_BLOCK_RADIUS)
    for _, other in ipairs(nearby) do
        if IsValid(other) and other.GRID_IsPersistentMapEntity then
            SafeRemoveEntity(ent)
            GRID.Notify(ply, "You cannot spawn props within 85 units of a persistent map entity.", NOTIFY_ERROR)
            return
        end
    end
end)

-- --------------------------------------------------------
-- Live Deletion & Access Controls (Safeguards 1, 2)
-- --------------------------------------------------------

-- Safeguard 1: Delete from MariaDB ONLY on explicit SuperAdmin Undo ('Z')
hook.Add("CanUndo", "GRID_MapSpawns_CanUndo", function(ply, undoTable)
    if not istable(undoTable) or not istable(undoTable.Entities) then return end

    for _, ent in ipairs(undoTable.Entities) do
        if IsValid(ent) and ent.GRID_IsPersistentMapEntity then
            if not IsValid(ply) or not ply:IsSuperAdmin() then
                GRID.Notify(ply, "Access Denied: Only SuperAdmins can undo persistent map entities.", NOTIFY_ERROR)
                return false
            end

            local spawnId = ent.GRID_MapSpawnID
            ent.GRID_MapSpawnID = nil -- Clear so EntityRemoved or cleanup never triggers DB action
            if spawnId and spawnId > 0 then
                GRID.Database.DeleteMapEntity(spawnId, function()
                    print(string.format("[GRID MapSpawns] SuperAdmin %s (%s) undid persistent entity #%d (%s).", ply:Nick(), ply:SteamID(), spawnId, ent:GetClass()))
                end)
                GRID.Notify(ply, string.format("Removed persistent map entity #%d from MariaDB.", spawnId), NOTIFY_GENERIC)
            end
        end
    end
end)

-- Safeguard 1 & 2: Delete from MariaDB ONLY on explicit SuperAdmin Toolgun Remover, block other tools
hook.Add("CanTool", "GRID_MapSpawns_CanTool", function(ply, tr, toolname)
    if not IsValid(tr.Entity) or not tr.Entity.GRID_IsPersistentMapEntity then return end

    if not IsValid(ply) or not ply:IsSuperAdmin() then
        GRID.Notify(ply, "Access Denied: Persistent map entities can only be modified by SuperAdmins.", NOTIFY_ERROR)
        return false
    end

    if toolname == "remover" then
        local ent = tr.Entity
        local spawnId = ent.GRID_MapSpawnID
        ent.GRID_MapSpawnID = nil -- Clear so accidental duplicate removal calls do nothing
        if spawnId and spawnId > 0 then
            GRID.Database.DeleteMapEntity(spawnId, function()
                print(string.format("[GRID MapSpawns] SuperAdmin %s (%s) removed persistent entity #%d (%s) via Remover.", ply:Nick(), ply:SteamID(), spawnId, ent:GetClass()))
            end)
            GRID.Notify(ply, string.format("Deleted persistent map entity #%d from MariaDB.", spawnId), NOTIFY_GENERIC)
        end
        return true
    end

    return true
end)

-- Safeguard 2: Block C-Menu properties on persistent entities
hook.Add("CanProperty", "GRID_MapSpawns_CanProperty", function(ply, property, ent)
    if IsValid(ent) and ent.GRID_IsPersistentMapEntity then
        return false
    end
end)

-- Safeguard 2: Block Gravity Gun interaction entirely
hook.Add("GravGunPickupAllowed", "GRID_MapSpawns_GravGunPickup", function(ply, ent)
    if IsValid(ent) and ent.GRID_IsPersistentMapEntity then
        return false
    end
end)

hook.Add("GravGunPunt", "GRID_MapSpawns_GravGunPunt", function(ply, ent)
    if IsValid(ent) and ent.GRID_IsPersistentMapEntity then
        return false
    end
end)

-- Safeguard 5: Damage, Crush, & Fire Immunity
hook.Add("EntityTakeDamage", "GRID_MapSpawns_EntityTakeDamage", function(target, dmginfo)
    if IsValid(target) and target.GRID_IsPersistentMapEntity then
        dmginfo:SetDamage(0)
        if target:IsOnFire() then
            target:Extinguish()
        end
        return true
    end
end)

-- --------------------------------------------------------
-- Map Migration Command (Safeguard 11)
-- --------------------------------------------------------

concommand.Add("grid_copy_map_spawns", function(ply, cmd, args)
    local isConsole = not IsValid(ply)
    local isSuperAdmin = IsValid(ply) and ply:IsSuperAdmin()

    if not isConsole and not isSuperAdmin then
        if IsValid(ply) then
            GRID.Notify(ply, "Only SuperAdmins can execute grid_copy_map_spawns.", NOTIFY_ERROR)
        end
        return
    end

    local oldMap = args[1]
    if not oldMap or oldMap == "" then
        local msg = "Usage: grid_copy_map_spawns <old_map_name>"
        if isConsole then print(msg) else GRID.Notify(ply, msg, NOTIFY_ERROR) end
        return
    end

    local currentMap = game.GetMap()
    print(string.format("[GRID MapSpawns] Copying persistent map spawns from '%s' to '%s'...", oldMap, currentMap))

    GRID.Database.CopyMapEntities(oldMap, currentMap, function()
        local successMsg = string.format("Successfully copied spawns from '%s' to '%s'! Reloading world entities...", oldMap, currentMap)
        print("[GRID MapSpawns] " .. successMsg)
        if IsValid(ply) then
            GRID.Notify(ply, successMsg, NOTIFY_HINT, 8)
        end
        GRID.MapSpawns.LoadAllMapEntities()
    end, function(err)
        local errMsg = "Failed to copy map spawns: " .. tostring(err)
        print("[GRID MapSpawns ERROR] " .. errMsg)
        if IsValid(ply) then
            GRID.Notify(ply, errMsg, NOTIFY_ERROR, 8)
        end
    end)
end)

