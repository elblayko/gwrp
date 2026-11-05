--[[
    GridRP - Server Telemetry & Combat Audit Layer
    Author: GRID Core Team
    Namespace: GRID / grid_
]]

GRID = GRID or {}
GRID.Telemetry = GRID.Telemetry or {}
GRID.Telemetry.CombatBuffer = GRID.Telemetry.CombatBuffer or {}

-- Categories: 'ECONOMY', 'COMBAT', 'TRADE', 'GANG', 'ANTIDEBUG', 'EXPLOIT', 'RATE_LIMIT'

function GRID.Telemetry.Log(category, actionType, actorSteamID, targetSteamID, numericValue, metadataTable)
    actorSteamID = actorSteamID or "CONSOLE"
    targetSteamID = targetSteamID or ""
    numericValue = tonumber(numericValue) or 0
    local metaJson = type(metadataTable) == "table" and util.TableToJSON(metadataTable) or "{}"

    if GRID.Database and GRID.Database.CallProcedure then
        GRID.Database.CallProcedure("grid_log_telemetry", {
            category,
            actionType,
            actorSteamID,
            targetSteamID,
            numericValue,
            metaJson
        })
    elseif GRID.Database and GRID.Database.UseSQLiteFallback then
        local q = string.format([[
            INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata)
            VALUES (%d, %s, %s, %s, %s, %f, %s);
        ]], os.time(), sql.SQLStr(category), sql.SQLStr(actionType), sql.SQLStr(actorSteamID), sql.SQLStr(targetSteamID), numericValue, sql.SQLStr(metaJson))
        sql.Query(q)
    end
end

function GRID.Telemetry.LogAnomaly(actorSteamID, anomalyType, detailsTable)
    GRID.Telemetry.Log("ANTIDEBUG", anomalyType, actorSteamID, "", 0, detailsTable)
    local alertMsg = string.format("[GRID ANOMALY DETECTED] Type: %s | SteamID: %s | Details: %s",
        tostring(anomalyType),
        tostring(actorSteamID),
        util.TableToJSON(detailsTable or {})
    )
    ErrorNoHalt(alertMsg .. "\n")
end

-- ========================================================
-- IN-MEMORY RAM COMBAT BUFFER
-- ========================================================

local function getCombatSession(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return nil end
    local sid = ply:SteamID()
    if not GRID.Telemetry.CombatBuffer[sid] then
        GRID.Telemetry.CombatBuffer[sid] = {
            startTime = CurTime(),
            shotsFired = 0,
            hitsLanded = 0,
            totalDamage = 0,
            weaponClass = "unknown",
            targets = {}
        }
    end
    return GRID.Telemetry.CombatBuffer[sid]
end

function GRID.Telemetry.RecordShot(ply, wep)
    local session = getCombatSession(ply)
    if not session then return end

    session.shotsFired = session.shotsFired + 1
    if IsValid(wep) then
        session.weaponClass = wep:GetClass()
    end
end

function GRID.Telemetry.RecordHit(attacker, victim, wep, damage, hitGroup)
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    local session = getCombatSession(attacker)
    if not session then return end

    session.hitsLanded = session.hitsLanded + 1
    session.totalDamage = session.totalDamage + (tonumber(damage) or 0)
    if IsValid(wep) then
        session.weaponClass = wep:GetClass()
    end

    if IsValid(victim) and victim:IsPlayer() then
        local vsid = victim:SteamID()
        session.targets[vsid] = (session.targets[vsid] or 0) + (tonumber(damage) or 0)
    end
end

function GRID.Telemetry.FlushCombat(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local sid = ply:SteamID()
    local session = GRID.Telemetry.CombatBuffer[sid]
    if not session then return end

    -- Only log telemetry if combat activity actually took place
    if session.shotsFired > 0 or session.totalDamage > 0 then
        local duration = math.Round(CurTime() - session.startTime, 2)
        local accuracy = session.shotsFired > 0 and math.Round((session.hitsLanded / session.shotsFired) * 100, 1) or 0

        local meta = {
            weapon = session.weaponClass,
            duration = duration,
            shots = session.shotsFired,
            hits = session.hitsLanded,
            accuracy = accuracy,
            targets = session.targets
        }

        GRID.Telemetry.Log("COMBAT", session.weaponClass, sid, "", session.totalDamage, meta)
    end

    GRID.Telemetry.CombatBuffer[sid] = nil
end

-- ========================================================
-- SELF-TEST CONSOLE COMMAND
-- ========================================================

local function runAuditSelfTest(ply, cmd, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        ply:ChatPrint("[GRID Telemetry] Access denied. SuperAdmin required.")
        return
    end

    local printOut = function(str)
        if IsValid(ply) then ply:ChatPrint(str) else print(str) end
    end

    printOut("==================================================")
    printOut("[GRID AUDIT SELFTEST] Starting Verification Routine...")
    printOut(string.format("Database Engine: %s", GRID.Database.Connected and "MariaDB mysqloo" or (GRID.Database.UseSQLiteFallback and "SQLite Fallback" or "Disconnected")))

    -- 1. Test Telemetry Insert
    local testActor = IsValid(ply) and ply:SteamID() or "STEAM_0:0:11111111"
    GRID.Telemetry.Log("ECONOMY", "SELFTEST_PING", testActor, "", 100, { test = true, ts = os.time() })
    printOut("[GRID AUDIT SELFTEST] Telemetry log procedure dispatched.")

    -- 2. Test Combat Buffer Simulation
    if IsValid(ply) then
        GRID.Telemetry.RecordShot(ply, ply:GetActiveWeapon())
        GRID.Telemetry.RecordHit(ply, ply, ply:GetActiveWeapon(), 25, HITGROUP_CHEST)
        GRID.Telemetry.FlushCombat(ply)
        printOut("[GRID AUDIT SELFTEST] In-memory combat buffer recorded and flushed successfully.")
    end

    -- 3. Check Stored Procedures & Analytical Views
    if GRID.Database.Connected then
        GRID.Database.QueryView("v_economy_metrics", "", {}, function(data)
            printOut(string.format("[GRID AUDIT SELFTEST] v_economy_metrics readable. Rows: %d", #data))
        end)
    end

    printOut("[GRID AUDIT SELFTEST] Self-test complete. Check server console for any SQL errors.")
    printOut("==================================================")
end

concommand.Add("grid_audit_selftest", runAuditSelfTest)
