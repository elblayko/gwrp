--[[
    gamemode/mapspawns/sh_map_spawns.lua
    Persistent World Entity Management (GRID.MapSpawns) - Shared Definitions
    Author: GRID Core Team & Antigravity
--]]

GRID = GRID or {}
GRID.MapSpawns = GRID.MapSpawns or {}

-- --------------------------------------------------------
-- Configuration & Constants
-- --------------------------------------------------------

-- Anti-prop-block proximity radius (Safeguard 6)
GRID.MapSpawns.PROP_BLOCK_RADIUS = 85

-- Visual inspector max rendering distance (Safeguard 13)
GRID.MapSpawns.INSPECTOR_DRAW_DISTANCE = 1800

-- Whitelist of entity classes that automatically qualify for persistent database lifecycle
GRID.MapSpawns.WhitelistedClasses = {
    ["grid_auction_terminal"]  = true,
    ["grid_clinic_pod"]        = true,
    ["grid_recycler_depot"]    = true,
    ["grid_resource_machine"]   = true,
    ["grid_scavenge_dumpster"] = true,
    ["grid_scavenge_scrappile"] = true,
    ["grid_scavenge_trashbin"]  = true,
    ["grid_flag_pole"]         = true,
    ["grid_deaddrop_locker"]   = true,
    ["grid_practice_stash"]    = true,
    ["grid_combat_target"]     = true,
    ["grid_atm"]               = true,
}

-- Objective entities that should maintain map-wide transmit state (Safeguard 12)
GRID.MapSpawns.TransmitAlwaysClasses = {
    ["grid_auction_terminal"]  = true,
    ["grid_clinic_pod"]        = true,
    ["grid_recycler_depot"]    = true,
    ["grid_combat_target"]     = true,
    ["grid_atm"]               = true,
}

-- --------------------------------------------------------
-- Shared Helper Functions
-- --------------------------------------------------------

--- Registers an entity class into the persistent map entity whitelist
-- @param className string
function GRID.MapSpawns.RegisterWhitelistedClass(className)
    if not isstring(className) or className == "" then return end
    GRID.MapSpawns.WhitelistedClasses[string.lower(className)] = true
end

--- Determines if an entity class is whitelisted for database persistence
-- @param className string
-- @return boolean
function GRID.MapSpawns.IsWhitelisted(className)
    if not isstring(className) then return false end
    local lower = string.lower(className)
    if GRID.MapSpawns.WhitelistedClasses[lower] then
        return true
    end

    -- Check if the scripted entity table defines ENT.IsPersistentMapEntity = true
    if scripted_ents and scripted_ents.Get then
        local sent = scripted_ents.Get(lower)
        if sent and sent.IsPersistentMapEntity then
            return true
        end
    end

    return false
end

--- Checks if an instantiated entity is tracked as a persistent map entity
-- @param ent Entity
-- @return boolean
function GRID.MapSpawns.IsPersistentEntity(ent)
    if not IsValid(ent) then return false end
    if ent.GRID_IsPersistentMapEntity == true then
        return true
    end
    if ent.GetNWBool and ent:GetNWBool("GRID_MapEntity", false) == true then
        return true
    end
    return false
end

