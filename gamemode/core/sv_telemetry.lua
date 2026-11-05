--[[
    GangWars - Server Telemetry & Combat Audit Layer
    Author: GW Core Team
    Namespace: GW / gw_
]]

GW = GW or {}
GW.Telemetry = GW.Telemetry or {}
GW.Telemetry.CombatBuffer = GW.Telemetry.CombatBuffer or {}

-- Categories: 'ECONOMY', 'COMBAT', 'TRADE', 'GANG', 'ANTIDEBUG', 'EXPLOIT', 'RATE_LIMIT'

function GW.Telemetry.Log(category, actionType, actorSteamID, targetSteamID, numericValue, metadataTable)
    actorSteamID = actorSteamID or "CONSOLE"
    targetSteamID = targetSteamID or ""
    numericValue = tonumber(numericValue) or 0
    local metaJson = type(metadataTable) == "table" and util.TableToJSON(metadataTable) or "{}"

    if GW.Database and GW.Database.CallProcedure then
        GW.Database.CallProcedure("gw_log_telemetry", {
            category,
            actionType,
            actorSteamID,
            targetSteamID,
            numericValue,
            metaJson
        })
    elseif GW.Database and GW.Database.UseSQLiteFallback then
        local q = string.format([[
            INSERT INTO gw_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata)
            VALUES (%d, %s, %s, %s, %s, %f, %s);
        ]], os.time(), sql.SQLStr(category), sql.SQLStr(actionType), sql.SQLStr(actorSteamID), sql.SQLStr(targetSteamID), numericValue, sql.SQLStr(metaJson))
        sql.Query(q)
    end
end

function GW.Telemetry.LogAnomaly(actorSteamID, anomalyType, detailsTable)
    GW.Telemetry.Log("ANTIDEBUG", anomalyType, actorSteamID, "", 0, detailsTable)
    local alertMsg = string.format("[GW ANOMALY DETECTED] Type: %s | SteamID: %s | Details: %s",
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
    if not GW.Telemetry.CombatBuffer[sid] then
        GW.Telemetry.CombatBuffer[sid] = {
            startTime = CurTime(),
            shotsFired = 0,
            hitsLanded = 0,
            totalDamage = 0,
            weaponClass = "unknown",
            targets = {}
        }
    end
    return GW.Telemetry.CombatBuffer[sid]
end

function GW.Telemetry.RecordShot(ply, wep)
    local session = getCombatSession(ply)
    if not session then return end

    session.shotsFired = session.shotsFired + 1
    if IsValid(wep) then
        session.weaponClass = wep:GetClass()
    end
end

function GW.Telemetry.RecordHit(attacker, victim, wep, damage, hitGroup)
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

function GW.Telemetry.FlushCombat(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local sid = ply:SteamID()
    local session = GW.Telemetry.CombatBuffer[sid]
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

        GW.Telemetry.Log("COMBAT", session.weaponClass, sid, "", session.totalDamage, meta)
    end

    GW.Telemetry.CombatBuffer[sid] = nil
end

-- ========================================================
-- SELF-TEST CONSOLE COMMAND
-- ========================================================

concommand.Add("gw_audit_selftest", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        ply:ChatPrint("[GW Telemetry] Access denied. SuperAdmin required.")
        return
    end

    local printOut = function(str)
        if IsValid(ply) then ply:ChatPrint(str) else print(str) end
    end

    printOut("==================================================")
    printOut("[GW AUDIT SELFTEST] Starting Verification Routine...")
    printOut(string.format("Database Engine: %s", GW.Database.Connected and "MariaDB mysqloo" or (GW.Database.UseSQLiteFallback and "SQLite Fallback" or "Disconnected")))

    -- 1. Test Telemetry Insert
    local testActor = IsValid(ply) and ply:SteamID() or "STEAM_0:0:11111111"
    GW.Telemetry.Log("ECONOMY", "SELFTEST_PING", testActor, "", 100, { test = true, ts = os.time() })
    printOut("[GW AUDIT SELFTEST] Telemetry log procedure dispatched.")

    -- 2. Test Combat Buffer Simulation
    if IsValid(ply) then
        GW.Telemetry.RecordShot(ply, ply:GetActiveWeapon())
        GW.Telemetry.RecordHit(ply, ply, ply:GetActiveWeapon(), 25, HITGROUP_CHEST)
        GW.Telemetry.FlushCombat(ply)
        printOut("[GW AUDIT SELFTEST] In-memory combat buffer recorded and flushed successfully.")
    end

    -- 3. Check Stored Procedures & Analytical Views
    if GW.Database.Connected then
        GW.Database.QueryView("v_economy_metrics", "", {}, function(data)
            printOut(string.format("[GW AUDIT SELFTEST] v_economy_metrics readable. Rows: %d", #data))
        end)
    end

    printOut("[GW AUDIT SELFTEST] Self-test complete. Check server console for any SQL errors.")
    printOut("==================================================")
end)

