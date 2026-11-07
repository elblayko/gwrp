--[[
    gamemode/core/sv_population_balancer.lua
    GridRP Dynamic Population Balancer & Economy Scaling Hook
    Author: Juicebox & Antigravity
--]]

GRID = GRID or {}
GRID.Population = GRID.Population or {}

-- Population Thresholds & Balancing Multipliers
GRID.Population.Threshold = 4 -- Less than 4 players = Low Pop Mode
GRID.Population.CurrentMode = "standard"

function GRID.Population.GetPlayerCount()
    return #player.GetAll()
end

function GRID.Population.IsLowPop()
    return GRID.Population.GetPlayerCount() < GRID.Population.Threshold
end

function GRID.Population.GetMode()
    return GRID.Population.IsLowPop() and "low" or "standard"
end

-- Node cooldown multiplier (0.667 = 1.5x faster node respawns in low pop)
function GRID.Population.GetCooldownMultiplier()
    if GRID.Population.IsLowPop() then
        return 0.667
    end
    return 1.0
end

-- Loot quantity / cash yield multiplier (1.25x in low pop)
function GRID.Population.GetLootYieldMultiplier()
    if GRID.Population.IsLowPop() then
        return 1.25
    end
    return 1.0
end

-- Turf capture permission (prevents ghost-town capture abuse when low population unless toggled on)
function GRID.Population.CanCaptureTurf()
    local allowLowPop = (GRID.Config and GRID.Config.AllowLowPopTurfCapture == true)
    if GRID.Population.IsLowPop() and not allowLowPop then
        return false,
            string.format("Territory capture locked: Requires at least %d online players to contest turf!",
                GRID.Population.Threshold)
    end
    return true
end

-- Evaluates server population and notifies players of scaling transitions
function GRID.Population.CheckPopulation()
    local count = GRID.Population.GetPlayerCount()
    local newMode = (count < GRID.Population.Threshold) and "low" or "standard"

    if newMode ~= GRID.Population.CurrentMode then
        local prevMode = GRID.Population.CurrentMode
        GRID.Population.CurrentMode = newMode

        local allowLowPop = (GRID.Config and GRID.Config.AllowLowPopTurfCapture == true)
        local turfStatus = allowLowPop and "Turf capture enabled (Launch Mode)." or "Turf capture locked."

        if newMode == "low" then
            GRID.NotifyAll(
                string.format(
                "[GRID BALANCER] Low Pop Mode Active (%d/%d Players) - Scavenge respawns +50%% faster - +25%% Loot Yield - %s",
                    count, GRID.Population.Threshold, turfStatus),
                NOTIFY_HINT,
                5
            )
        else
            GRID.NotifyAll(
                string.format(
                "[GRID BALANCER] Standard Mode Active (%d+ Players) - Full PvP territory capture unlocked - Standard economy rates.",
                    GRID.Population.Threshold),
                NOTIFY_GENERIC,
                5
            )
        end

        if GRID.Telemetry and GRID.Telemetry.Log then
            GRID.Telemetry.Log("ECONOMY", "POPULATION_MODE_CHANGE", "SERVER", "", count, {
                old_mode = prevMode,
                new_mode = newMode,
                player_count = count
            })
        end
    end
end

-- Admin concommand to toggle low pop turf capture on/off live in-game
concommand.Add("grid_pop_allow_lowpop_turf", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        GRID.Notify(ply, "You do not have permission to toggle turf population locks.", NOTIFY_ERROR)
        return
    end

    if args[1] then
        local val = tonumber(args[1])
        GRID.Config.AllowLowPopTurfCapture = (val == 1 or args[1] == "true")
    else
        GRID.Config.AllowLowPopTurfCapture = not GRID.Config.AllowLowPopTurfCapture
    end

    local status = GRID.Config.AllowLowPopTurfCapture and "ENABLED" or "DISABLED (LOCKED)"
    local msg = string.format("[GRID] Low Population Turf Capture is now %s.", status)

    if IsValid(ply) then
        GRID.Notify(ply, msg, NOTIFY_GENERIC)
    end
    print(msg)
end)

-- Hook into player lifecycle events with debounce
local function SchedulePopulationCheck()
    timer.Create("GRID_PopulationCheckDebounce", 1.5, 1, function()
        GRID.Population.CheckPopulation()
    end)
end

hook.Add("PlayerInitialSpawn", "GRID_PopBalancer_Join", function(ply)
    SchedulePopulationCheck()
end)

hook.Add("PlayerDisconnected", "GRID_PopBalancer_Leave", function(ply)
    SchedulePopulationCheck()
end)

hook.Add("Initialize", "GRID_PopBalancer_Init", function()
    timer.Simple(5.0, function()
        GRID.Population.CheckPopulation()
    end)
end)
