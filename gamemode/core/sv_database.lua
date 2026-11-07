--[[
    GridRP - Server Database Layer (MariaDB mysqloo v9 + Stored Procedures + Analytical Views + In-Memory RAM Cache)
    Author: GRID Core Team
    Namespace: GRID / grid_
]]

GRID = GRID or {}
GRID.Database = GRID.Database or {}
GRID.Database.Cache = GRID.Database.Cache or {
    Players = {},
    Inventories = {},
    Bags = {},
    Gangs = {},
    GangMembers = {},
    Turfs = {},
    Buffs = {},
    Settings = {}
}

GRID.Database.Connected = false
GRID.Database.Queue = GRID.Database.Queue or {}
GRID.Database.Connection = GRID.Database.Connection or nil

-- Sanitizer / Escaper helper
function GRID.Database.Escape(str)
    if str == nil then return "NULL" end
    if isnumber(str) then return tostring(str) end
    if isbool(str) then return str and "1" or "0" end
    if GRID.Database.Connection and GRID.Database.Connection.escape then
        return "'" .. GRID.Database.Connection:escape(tostring(str)) .. "'"
    end
    -- SQLite fallback: use the engine's native quoting (doubles single quotes)
    if GRID.Database.UseSQLiteFallback then
        return sql.SQLStr(tostring(str))
    end
    -- Fallback escaping (plain-text replace; a literal "\0" in a Lua pattern matches
    -- the empty string and would inject \0 between every character)
    local s = tostring(str)
    s = string.Replace(s, "\\", "\\\\")
    s = string.Replace(s, "'", "\\'")
    s = string.Replace(s, "\"", "\\\"")
    s = string.Replace(s, "\0", "\\0")
    return "'" .. s .. "'"
end

-- Parameterized format string: replaces ? with properly escaped values
function GRID.Database.FormatQuery(queryTemplate, params)
    params = params or {}
    local pieces = string.Explode("?", queryTemplate)
    if #pieces <= 1 then return queryTemplate end

    local out = { pieces[1] }
    for i = 1, #pieces - 1 do
        table.insert(out, GRID.Database.Escape(params[i]))
        table.insert(out, pieces[i + 1])
    end
    return table.concat(out, "")
end

-- ========================================================
-- CONNECTION MANAGEMENT (mysqloo v9)
-- ========================================================

function GRID.Database.Connect()
    local hasMySQLOO, _ = pcall(require, "mysqloo")
    local cfg = GRID.Database.LoadConfig and GRID.Database.LoadConfig() or GRID.Database.Config

    if not hasMySQLOO or not mysqloo then
        ErrorNoHalt("[GRID DB WARNING] mysqloo module not found! Falling back to SQLite local emulation for testing.\n")
        GRID.Database.UseSQLiteFallback = true
        GRID.Database.InitSQLiteFallback()
        return
    end

    if not cfg then
        ErrorNoHalt("[GRID DB WARNING] Database configuration is missing! Falling back to SQLite local emulation.\n")
        GRID.Database.UseSQLiteFallback = true
        GRID.Database.InitSQLiteFallback()
        return
    end

    print(string.format("[GRID DB] Connecting to MariaDB at %s:%d (Database: %s)...", cfg.Host, cfg.Port, cfg.Database))

    local db = mysqloo.connect(cfg.Host, cfg.User, cfg.Password, cfg.Database, cfg.Port, cfg.Socket)

    function db:onConnected()
        print("[GRID DB] Successfully connected to MariaDB engine! Ensuring schema...")

        GRID.Database.InitMariaDBSchema(db, function()
            GRID.Database.Connected = true
            GRID.Database.Connection = db

            -- Preload gangs, members, and settings into RAM cache
            GRID.Database.PreloadCaches()

            -- Flush queued queries
            if #GRID.Database.Queue > 0 then
                print(string.format("[GRID DB] Flushing %d queued database operations...", #GRID.Database.Queue))
                local queued = GRID.Database.Queue
                GRID.Database.Queue = {}
                for _, item in ipairs(queued) do
                    GRID.Database.Execute(item.Query, item.Callback, item.ErrorCallback)
                end
            end

            hook.Run("GRID_DatabaseConnected")
        end)
    end

    function db:onConnectionFailed(err)
        GRID.Database.Connected = false
        ErrorNoHalt(string.format("[GRID DB ERROR] MariaDB connection failed: %s\n", tostring(err)))
        -- Retry connection in 10 seconds
        timer.Simple(10, function()
            if not GRID.Database.Connected then
                GRID.Database.Connect()
            end
        end)
    end

    db:connect()
end

function GRID.Database.Execute(queryString, onDone, onError)
    if GRID.Database.UseSQLiteFallback then
        local res = sql.Query(queryString)
        if res == false then
            local err = sql.LastError()
            if onError then onError(err) else ErrorNoHalt(string.format("[GRID DB SQLITE ERROR] %s: %s\n", queryString, tostring(err))) end
            return
        end
        if onDone then onDone(res or {}) end
        return
    end

    if not GRID.Database.Connected or not GRID.Database.Connection then
        table.insert(GRID.Database.Queue, { Query = queryString, Callback = onDone, ErrorCallback = onError })
        return
    end

    local q = GRID.Database.Connection:query(queryString)
    function q:onSuccess(data)
        if onDone then onDone(data) end
    end
    function q:onError(err)
        ErrorNoHalt(string.format("[GRID DB ERROR] Query failed:\n%s\nError: %s\n", queryString, tostring(err)))
        if onError then onError(err) end
    end
    q:start()
end

-- ========================================================
-- STORED PROCEDURE & VIEW WRAPPERS (WITH DIRECT SQL FALLBACK)
-- ========================================================

-- Direct MariaDB SQL queries for procedures, used automatically if the DB user lacks
-- CREATE ROUTINE / EXECUTE privileges on shared hosting panels (e.g. Pterodactyl).
GRID.Database.MariaDBDirectProcedures = {
    grid_log_telemetry = function(p, run)
        run(GRID.Database.FormatQuery(
            "INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata) VALUES (UNIX_TIMESTAMP(), ?, ?, ?, ?, ?, ?);",
            p
        ))
    end,
    grid_upsert_player = function(p, run)
        run(GRID.Database.FormatQuery(
            "INSERT INTO grid_players (steamid, name, money, respect, gang, job, level, xp, last_seen, onboarding_stage, bank) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), money = VALUES(money), respect = VALUES(respect), gang = VALUES(gang), job = VALUES(job), level = VALUES(level), xp = VALUES(xp), last_seen = VALUES(last_seen), onboarding_stage = VALUES(onboarding_stage), bank = VALUES(bank);",
            p
        ))
    end,
    grid_update_player_money = function(p, run)
        run(GRID.Database.FormatQuery("UPDATE grid_players SET money = ?, last_seen = ? WHERE steamid = ?;", { p[2], p[3], p[1] }))
    end,
    grid_update_player_bank = function(p, run)
        run(GRID.Database.FormatQuery("UPDATE grid_players SET bank = ?, last_seen = ? WHERE steamid = ?;", { p[2], p[3], p[1] }))
    end,
    grid_transfer_personal_bank = function(p, run)
        -- p = { steamID, delta, unixTime }
        local steamID = p[1]
        local delta = tonumber(p[2]) or 0
        local now = tonumber(p[3]) or os.time()
        GRID.Database.Execute(GRID.Database.FormatQuery("SELECT money, bank FROM grid_players WHERE steamid = ? LIMIT 1;", { steamID }), function(rows)
            local r = rows and rows[1]
            local m = tonumber(r and r.money) or 0
            local b = tonumber(r and r.bank) or 0
            if delta > 0 then
                if m < delta then
                    run("SELECT 'ERR_INSUFFICIENT_WALLET' AS status, " .. m .. " AS money, " .. b .. " AS bank;")
                    return
                end
                m = m - delta
                b = b + delta
            elseif delta < 0 then
                local w = math.abs(delta)
                if b < w then
                    run("SELECT 'ERR_INSUFFICIENT_BANK' AS status, " .. m .. " AS money, " .. b .. " AS bank;")
                    return
                end
                m = m + w
                b = b - w
            else
                run("SELECT 'ERR_ZERO_DELTA' AS status, " .. m .. " AS money, " .. b .. " AS bank;")
                return
            end
            GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET money = ?, bank = ?, last_seen = ? WHERE steamid = ?;", { m, b, now, steamID }), function()
                run("SELECT 'SUCCESS' AS status, " .. m .. " AS money, " .. b .. " AS bank;")
            end)
        end)
    end,
    grid_update_onboarding_stage = function(p, run)
        run(GRID.Database.FormatQuery("UPDATE grid_players SET onboarding_stage = ? WHERE steamid = ?;", { p[2], p[1] }))
    end,
    grid_complete_onboarding = function(p, run)
        -- p = { steamID, bonusCleanCash }
        local steamID = p[1]
        local bonusCash = tonumber(p[2]) or 3500
        GRID.Database.Execute(GRID.Database.FormatQuery(
            "UPDATE grid_players SET onboarding_stage = 3, level = GREATEST(level, 2), bank = bank + ? WHERE steamid = ? AND onboarding_stage < 3;",
            { bonusCash, steamID }
        ), function()
            GRID.Database.Execute(GRID.Database.FormatQuery(
                "INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata) VALUES (?, 'PLAYER_ACTION', 'ONBOARDING_COMPLETED', ?, '', ?, ?);",
                { os.time(), steamID, bonusCash, '{"new_level":2}' }
            ))
        end)
    end,
    grid_reset_player = function(p, run)
        -- p = { steamID }
        local steamID = p[1]
        local now = os.time()
        GRID.Database.Execute(GRID.Database.FormatQuery(
            "UPDATE grid_players SET money = 0, bank = 0, respect = 0, gang = '', job = 'citizen', level = 1, xp = 0, onboarding_stage = 0, last_seen = ? WHERE steamid = ?;",
            { now, steamID }
        ), function()
            GRID.Database.Execute(GRID.Database.FormatQuery("DELETE FROM grid_gang_members WHERE steamid = ?;", { steamID }))
            GRID.Database.Execute(GRID.Database.FormatQuery("DELETE FROM grid_inventory WHERE steamid = ?;", { steamID }))
            GRID.Database.Execute(GRID.Database.FormatQuery("DELETE FROM grid_player_bags WHERE steamid = ?;", { steamID }))
            GRID.Database.Execute(GRID.Database.FormatQuery("DELETE FROM grid_player_buffs WHERE steamid = ?;", { steamID }))
            GRID.Database.Execute(GRID.Database.FormatQuery(
                "INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata) VALUES (?, 'PLAYER_ACTION', 'PLAYER_FULL_RESET', 'CONSOLE', ?, 0, ?);",
                { now, steamID, '{"reason":"admin_hud_reset"}' }
            ))
        end)
    end,
    grid_update_player_gang = function(p, run)
        run(GRID.Database.FormatQuery("UPDATE grid_players SET gang = ?, last_seen = ? WHERE steamid = ?;", { p[2], p[3], p[1] }))
    end,
    grid_update_player_job = function(p, run)
        run(GRID.Database.FormatQuery("UPDATE grid_players SET job = ?, last_seen = ? WHERE steamid = ?;", { p[2], p[3], p[1] }))
    end,
    grid_update_player_level_xp = function(p, run)
        run(GRID.Database.FormatQuery("UPDATE grid_players SET level = ?, xp = ?, last_seen = ? WHERE steamid = ?;", { p[2], p[3], p[4], p[1] }))
    end,
    grid_create_gang = function(p, run)
        -- p = { gangName, leaderSteamID, unixTime }
        GRID.Database.Execute(GRID.Database.FormatQuery(
            "INSERT INTO grid_gangs (name, leader_steamid, bank, respect, created_at) VALUES (?, ?, 0, 0, ?) ON DUPLICATE KEY UPDATE leader_steamid = VALUES(leader_steamid);",
            { p[1], p[2], p[3] }
        ), function()
            GRID.Database.Execute(GRID.Database.FormatQuery(
                "INSERT INTO grid_gang_members (steamid, gang, rank, joined_at) VALUES (?, ?, 'leader', ?) ON DUPLICATE KEY UPDATE gang = VALUES(gang), rank = 'leader';",
                { p[2], p[1], p[3] }
            ))
            run(GRID.Database.FormatQuery(
                "UPDATE grid_players SET gang = ?, last_seen = ? WHERE steamid = ?;",
                { p[1], p[3], p[2] }
            ))
        end)
    end,
    grid_add_gang_member = function(p, run)
        -- p = { steamID, gangName, rank, unixTime }
        GRID.Database.Execute(GRID.Database.FormatQuery(
            "INSERT INTO grid_gang_members (steamid, gang, rank, joined_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE gang = VALUES(gang), rank = VALUES(rank);",
            { p[1], p[2], p[3], p[4] }
        ))
        run(GRID.Database.FormatQuery("UPDATE grid_players SET gang = ?, last_seen = ? WHERE steamid = ?;", { p[2], p[4], p[1] }))
    end,
    grid_remove_gang_member = function(p, run)
        GRID.Database.Execute(GRID.Database.FormatQuery("DELETE FROM grid_gang_members WHERE steamid = ?;", { p[1] }))
        run(GRID.Database.FormatQuery("UPDATE grid_players SET gang = '' WHERE steamid = ?;", { p[1] }))
    end,
    grid_add_gang_bank = function(p, run)
        run(GRID.Database.FormatQuery("UPDATE grid_gangs SET bank = GREATEST(0, bank + ?) WHERE name = ?;", { p[2], p[1] }))
    end,
    grid_transfer_gang_vault = function(p, run)
        -- p = { steamID, gangName, delta, unixTime }
        local delta = tonumber(p[3]) or 0
        if delta > 0 then
            GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET money = GREATEST(0, money - ?), last_seen = ? WHERE steamid = ?;", { delta, p[4], p[1] }))
            run(GRID.Database.FormatQuery("UPDATE grid_gangs SET bank = bank + ? WHERE name = ?;", { delta, p[2] }))
        elseif delta < 0 then
            local absDelta = math.abs(delta)
            GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET money = money + ?, last_seen = ? WHERE steamid = ?;", { absDelta, p[4], p[1] }))
            run(GRID.Database.FormatQuery("UPDATE grid_gangs SET bank = GREATEST(0, bank - ?) WHERE name = ?;", { absDelta, p[2] }))
        end
    end,
    grid_disband_gang = function(p, run)
        GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET gang = '' WHERE gang = ?;", { p[1] }))
        GRID.Database.Execute(GRID.Database.FormatQuery("DELETE FROM grid_gang_members WHERE gang = ?;", { p[1] }))
        run(GRID.Database.FormatQuery("DELETE FROM grid_gangs WHERE name = ?;", { p[1] }))
    end,
    grid_set_inventory_slot = function(p, run)
        -- p = { steamID, bagIndex, slotIndex, itemId, itemType, amount, itemData }
        local amt = tonumber(p[6]) or 0
        GRID.Database.Execute(GRID.Database.FormatQuery(
            "DELETE FROM grid_inventory WHERE steamid = ? AND bag_index = ? AND slot_index = ?;",
            { p[1], p[2], p[3] }
        ), function()
            if amt > 0 then
                run(GRID.Database.FormatQuery(
                    "INSERT INTO grid_inventory (steamid, bag_index, slot_index, item_id, item_type, amount, item_data) VALUES (?, ?, ?, ?, ?, ?, ?);",
                    p
                ))
            else
                run(nil)
            end
        end)
    end,
    grid_delete_inventory_slot = function(p, run)
        run(GRID.Database.FormatQuery("DELETE FROM grid_inventory WHERE steamid = ? AND bag_index = ? AND slot_index = ?;", p))
    end,
    grid_move_inventory_slot = function(p, run)
        -- p = { steamID, fromBag, fromSlot, toBag, toSlot }
        local steamID = p[1]
        local inv = GRID.Database.Cache.Inventories[steamID] or {}
        local fromBag, fromSlot, toBag, toSlot = tonumber(p[2]) or 0, tonumber(p[3]) or 1, tonumber(p[4]) or 0, tonumber(p[5]) or 1
        local srcItem, dstItem
        for _, it in ipairs(inv) do
            if (tonumber(it.bag_index) or 0) == fromBag and (tonumber(it.slot_index) or 1) == fromSlot then
                srcItem = it
            elseif (tonumber(it.bag_index) or 0) == toBag and (tonumber(it.slot_index) or 1) == toSlot then
                dstItem = it
            end
        end
        GRID.Database.Execute(GRID.Database.FormatQuery(
            "DELETE FROM grid_inventory WHERE steamid = ? AND ((bag_index = ? AND slot_index = ?) OR (bag_index = ? AND slot_index = ?));",
            { steamID, fromBag, fromSlot, toBag, toSlot }
        ), function()
            if srcItem then
                GRID.Database.Execute(GRID.Database.FormatQuery(
                    "INSERT INTO grid_inventory (steamid, bag_index, slot_index, item_id, item_type, amount, item_data) VALUES (?, ?, ?, ?, ?, ?, ?);",
                    { steamID, srcItem.bag_index, srcItem.slot_index, srcItem.item_id, srcItem.item_type, srcItem.amount, srcItem.item_data }
                ))
            end
            if dstItem then
                run(GRID.Database.FormatQuery(
                    "INSERT INTO grid_inventory (steamid, bag_index, slot_index, item_id, item_type, amount, item_data) VALUES (?, ?, ?, ?, ?, ?, ?);",
                    { steamID, dstItem.bag_index, dstItem.slot_index, dstItem.item_id, dstItem.item_type, dstItem.amount, dstItem.item_data }
                ))
            else
                run(nil)
            end
        end)
    end,
    grid_set_player_bags = function(p, run)
        run(GRID.Database.FormatQuery(
            "INSERT INTO grid_player_bags (steamid, bag1, bag2, bag3, bag4) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE bag1 = VALUES(bag1), bag2 = VALUES(bag2), bag3 = VALUES(bag3), bag4 = VALUES(bag4);",
            p
        ))
    end,
    grid_save_map_turf = function(p, run)
        run(GRID.Database.FormatQuery(
            "INSERT INTO grid_turfs (map, turf_id, name, pos_x, pos_y, pos_z, radius, owner, tax_rate) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), pos_x = VALUES(pos_x), pos_y = VALUES(pos_y), pos_z = VALUES(pos_z), radius = VALUES(radius), owner = VALUES(owner), tax_rate = VALUES(tax_rate);",
            p
        ))
    end,
    grid_clear_map_turfs = function(p, run)
        run(GRID.Database.FormatQuery("DELETE FROM grid_turfs WHERE map = ?;", p))
    end,
    grid_delete_map_turf = function(p, run)
        run(GRID.Database.FormatQuery("DELETE FROM grid_turfs WHERE map = ? AND turf_id = ?;", p))
    end,
    grid_set_turf_tax = function(p, run)
        run(GRID.Database.FormatQuery("UPDATE grid_turfs SET tax_rate = ? WHERE map = ? AND turf_id = ?;", { p[3], p[1], p[2] }))
    end,
    grid_collect_printer_taxed = function(p, run)
        -- p = { actorSteamID, controllingGang, payoutAmount, taxAmount, unixTime }
        GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET money = money + ?, last_seen = ? WHERE steamid = ?;", { p[3], p[5], p[1] }))
        local tax = tonumber(p[4]) or 0
        local gang = tostring(p[2] or "")
        if tax > 0 and gang ~= "" and gang ~= "neutral" and gang ~= "Police" then
            run(GRID.Database.FormatQuery("UPDATE grid_gangs SET bank = bank + ? WHERE name = ?;", { tax, gang }))
        else
            run(nil)
        end
    end,
    grid_save_player_buff = function(p, run)
        run(GRID.Database.FormatQuery(
            "INSERT INTO grid_player_buffs (steamid, buff_id, duration, remaining, stacks, applied_at, expires_at_unix, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE duration = VALUES(duration), remaining = VALUES(remaining), stacks = VALUES(stacks), applied_at = VALUES(applied_at), expires_at_unix = VALUES(expires_at_unix), data = VALUES(data);",
            p
        ))
    end,
    grid_delete_player_buff = function(p, run)
        run(GRID.Database.FormatQuery("DELETE FROM grid_player_buffs WHERE steamid = ? AND buff_id = ?;", p))
    end,
    grid_clear_player_buffs = function(p, run)
        run(GRID.Database.FormatQuery("DELETE FROM grid_player_buffs WHERE steamid = ?;", p))
    end,
    grid_set_setting = function(p, run)
        run(GRID.Database.FormatQuery("INSERT INTO grid_settings (`key`, `val`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `val` = VALUES(`val`);", p))
    end,
    grid_save_map_entity = function(p, run)
        local spawnId = tonumber(p[1]) or 0
        if spawnId > 0 then
            run(GRID.Database.FormatQuery(
                "UPDATE grid_map_entities SET pos_x = ?, pos_y = ?, pos_z = ?, ang_p = ?, ang_y = ?, ang_r = ?, custom_data = COALESCE(?, custom_data) WHERE spawn_id = ?;",
                { p[4], p[5], p[6], p[7], p[8], p[9], p[11], spawnId }
            ))
        else
            run(GRID.Database.FormatQuery(
                "INSERT INTO grid_map_entities (map_name, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                { p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11] }
            ))
        end
    end,
    grid_delete_map_entity = function(p, run)
        run(GRID.Database.FormatQuery("DELETE FROM grid_map_entities WHERE spawn_id = ?;", { p[1] }))
    end,
    grid_copy_map_spawns = function(p, run)
        run(GRID.Database.FormatQuery(
            "INSERT INTO grid_map_entities (map_name, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data) SELECT ?, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data FROM grid_map_entities WHERE map_name = ?;",
            { p[2], p[1] }
        ))
    end,
}

-- Direct MariaDB SQL queries for views, used if the DB user lacks CREATE VIEW privileges or if SQLite is active.
GRID.Database.DirectViews = {
    v_player_profile = "(SELECT p.steamid, p.name, p.money, p.bank, p.respect, p.gang, p.job, p.level, p.xp, p.onboarding_stage, p.last_seen, m.rank AS gang_rank FROM grid_players p LEFT JOIN grid_gang_members m ON p.steamid = m.steamid) AS v_player_profile",
    v_player_inventory = "grid_inventory",
    v_player_bags = "grid_player_bags",
    v_player_buffs = "grid_player_buffs",
    v_map_turfs = "grid_turfs",
    v_settings = "grid_settings",
    v_auction_metrics = "(SELECT a.item_id, MIN(CASE WHEN a.status = 'ACTIVE' AND a.buyout_price > 0 THEN a.buyout_price ELSE NULL END) AS min_active_buyout, COUNT(CASE WHEN a.status = 'ACTIVE' THEN 1 ELSE NULL END) AS active_listings_count, ROUND(AVG(CASE WHEN a.status = 'SOLD' AND a.closed_at_unix >= (strftime('%s', 'now') - 604800) THEN MAX(a.current_bid, a.buyout_price) ELSE NULL END)) AS avg_sale_price_7d, COALESCE(SUM(CASE WHEN a.status = 'SOLD' AND a.closed_at_unix >= (strftime('%s', 'now') - 86400) THEN a.amount ELSE 0 END), 0) AS sold_volume_24h FROM grid_auctions a GROUP BY a.item_id) AS v_auction_metrics",
    v_auctions = "grid_auctions",
    v_auction_collection = "grid_auction_collection",
    v_grid_map_spawns = "grid_map_entities",
}

-- SQLite has no stored procedures (no CALL). Emulate the ones needed for local dev.
GRID.Database.SQLiteProcedures = {
    grid_log_telemetry = function(p)
        return GRID.Database.FormatQuery(
            "INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata) VALUES (?, ?, ?, ?, ?, ?, ?);",
            { os.time(), p[1], p[2], p[3], p[4], p[5], p[6] }
        )
    end,
    grid_clear_map_turfs = "DELETE FROM grid_turfs WHERE map = ?;",
    grid_save_map_turf = "INSERT OR REPLACE INTO grid_turfs (map, turf_id, name, pos_x, pos_y, pos_z, radius, owner, tax_rate) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
    grid_delete_map_turf = "DELETE FROM grid_turfs WHERE map = ? AND turf_id = ?;",
    grid_set_turf_tax = function(p)
        return GRID.Database.FormatQuery("UPDATE grid_turfs SET tax_rate = ? WHERE map = ? AND turf_id = ?;", { p[3], p[1], p[2] })
    end,
    grid_set_setting = "INSERT OR REPLACE INTO grid_settings (key, val) VALUES (?, ?);",
    grid_upsert_player = "INSERT OR REPLACE INTO grid_players (steamid, name, money, respect, gang, job, level, xp, last_seen, onboarding_stage, bank) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
    grid_update_player_money = function(p)
        return GRID.Database.FormatQuery("UPDATE grid_players SET money = ?, last_seen = ? WHERE steamid = ?;", { p[2], p[3], p[1] })
    end,
    grid_update_player_bank = function(p)
        return GRID.Database.FormatQuery("UPDATE grid_players SET bank = ?, last_seen = ? WHERE steamid = ?;", { p[2], p[3], p[1] })
    end,
    grid_transfer_personal_bank = function(p)
        local steamID = p[1]
        local delta = tonumber(p[2]) or 0
        local now = tonumber(p[3]) or os.time()
        local r = sql.Query(GRID.Database.FormatQuery("SELECT money, bank FROM grid_players WHERE steamid = ? LIMIT 1;", { steamID }))
        local row = r and r[1]
        local m = tonumber(row and row.money) or 0
        local b = tonumber(row and row.bank) or 0
        if delta > 0 then
            if m < delta then
                return string.format("SELECT 'ERR_INSUFFICIENT_WALLET' AS status, %d AS money, %d AS bank;", m, b)
            end
            m = m - delta
            b = b + delta
        elseif delta < 0 then
            local w = math.abs(delta)
            if b < w then
                return string.format("SELECT 'ERR_INSUFFICIENT_BANK' AS status, %d AS money, %d AS bank;", m, b)
            end
            m = m + w
            b = b - w
        else
            return string.format("SELECT 'ERR_ZERO_DELTA' AS status, %d AS money, %d AS bank;", m, b)
        end
        sql.Query(GRID.Database.FormatQuery("UPDATE grid_players SET money = ?, bank = ?, last_seen = ? WHERE steamid = ?;", { m, b, now, steamID }))
        return string.format("SELECT 'SUCCESS' AS status, %d AS money, %d AS bank;", m, b)
    end,
    grid_transfer_gang_vault = function(p)
        local steamID = p[1]
        local gangName = p[2]
        local delta = tonumber(p[3]) or 0
        local now = tonumber(p[4]) or os.time()
        local pr = sql.Query(GRID.Database.FormatQuery("SELECT money FROM grid_players WHERE steamid = ? LIMIT 1;", { steamID }))
        local gr = sql.Query(GRID.Database.FormatQuery("SELECT bank FROM grid_gangs WHERE name = ? LIMIT 1;", { gangName }))
        local m = tonumber(pr and pr[1] and pr[1].money) or 0
        local gb = tonumber(gr and gr[1] and gr[1].bank) or 0
        if delta > 0 and m >= delta then
            sql.Query(GRID.Database.FormatQuery("UPDATE grid_players SET money = money - ?, last_seen = ? WHERE steamid = ?;", { delta, now, steamID }))
            return GRID.Database.FormatQuery("UPDATE grid_gangs SET bank = bank + ? WHERE name = ?;", { delta, gangName })
        elseif delta < 0 and gb >= math.abs(delta) then
            local w = math.abs(delta)
            sql.Query(GRID.Database.FormatQuery("UPDATE grid_gangs SET bank = bank - ? WHERE name = ?;", { w, gangName }))
            return GRID.Database.FormatQuery("UPDATE grid_players SET money = money + ?, last_seen = ? WHERE steamid = ?;", { w, now, steamID })
        end
        return "SELECT 1;"
    end,
    grid_collect_printer_taxed = function(p)
        local steamID = p[1]
        local gang = tostring(p[2] or "")
        local payout = tonumber(p[3]) or 0
        local tax = tonumber(p[4]) or 0
        local now = tonumber(p[5]) or os.time()
        sql.Query(GRID.Database.FormatQuery("UPDATE grid_players SET money = money + ?, last_seen = ? WHERE steamid = ?;", { payout, now, steamID }))
        if tax > 0 and gang ~= "" and gang ~= "neutral" and gang ~= "Police" then
            return GRID.Database.FormatQuery("UPDATE grid_gangs SET bank = bank + ? WHERE name = ?;", { tax, gang })
        end
        return "SELECT 1;"
    end,
    grid_update_onboarding_stage = function(p)
        return GRID.Database.FormatQuery("UPDATE grid_players SET onboarding_stage = ? WHERE steamid = ?;", { p[2], p[1] })
    end,
    grid_complete_onboarding = function(p)
        local steamID = p[1]
        local bonusCash = tonumber(p[2]) or 3500
        sql.Query(GRID.Database.FormatQuery("UPDATE grid_players SET onboarding_stage = 3, level = MAX(level, 2), bank = bank + ? WHERE steamid = ? AND onboarding_stage < 3;", { bonusCash, steamID }))
        local qMeta = sql.SQLStr('{"new_level":2}')
        return string.format("INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata) VALUES (%d, 'PLAYER_ACTION', 'ONBOARDING_COMPLETED', %s, '', %d, %s);", os.time(), sql.SQLStr(steamID), bonusCash, qMeta)
    end,
    grid_reset_player = function(p)
        local steamID = p[1]
        local now = os.time()
        sql.Query(GRID.Database.FormatQuery("UPDATE grid_players SET money = 0, bank = 0, respect = 0, gang = '', job = 'citizen', level = 1, xp = 0, onboarding_stage = 0, last_seen = ? WHERE steamid = ?;", { now, steamID }))
        sql.Query(GRID.Database.FormatQuery("DELETE FROM grid_gang_members WHERE steamid = ?;", { steamID }))
        sql.Query(GRID.Database.FormatQuery("DELETE FROM grid_inventory WHERE steamid = ?;", { steamID }))
        sql.Query(GRID.Database.FormatQuery("DELETE FROM grid_player_bags WHERE steamid = ?;", { steamID }))
        sql.Query(GRID.Database.FormatQuery("DELETE FROM grid_player_buffs WHERE steamid = ?;", { steamID }))
        local qMeta = sql.SQLStr('{"reason":"admin_hud_reset"}')
        return string.format("INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata) VALUES (%d, 'PLAYER_ACTION', 'PLAYER_FULL_RESET', 'CONSOLE', %s, 0, %s);", now, sql.SQLStr(steamID), qMeta)
    end,
    grid_update_player_gang = function(p)
        return GRID.Database.FormatQuery("UPDATE grid_players SET gang = ?, last_seen = ? WHERE steamid = ?;", { p[2], p[3], p[1] })
    end,
    grid_update_player_job = function(p)
        return GRID.Database.FormatQuery("UPDATE grid_players SET job = ?, last_seen = ? WHERE steamid = ?;", { p[2], p[3], p[1] })
    end,
    grid_update_player_level_xp = function(p)
        return GRID.Database.FormatQuery("UPDATE grid_players SET level = ?, xp = ?, last_seen = ? WHERE steamid = ?;", { p[2], p[3], p[4], p[1] })
    end,
    grid_set_player_bags = "INSERT OR REPLACE INTO grid_player_bags (steamid, bag1, bag2, bag3, bag4) VALUES (?, ?, ?, ?, ?);",
    grid_save_player_buff = "INSERT OR REPLACE INTO grid_player_buffs (steamid, buff_id, duration, remaining, stacks, applied_at, expires_at_unix, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
    grid_delete_player_buff = "DELETE FROM grid_player_buffs WHERE steamid = ? AND buff_id = ?;",
    grid_clear_player_buffs = "DELETE FROM grid_player_buffs WHERE steamid = ?;",
    grid_save_map_entity = function(p)
        local spawnId = tonumber(p[1]) or 0
        if spawnId > 0 then
            return GRID.Database.FormatQuery(
                "UPDATE grid_map_entities SET pos_x = ?, pos_y = ?, pos_z = ?, ang_p = ?, ang_y = ?, ang_r = ?, custom_data = COALESCE(?, custom_data) WHERE spawn_id = ?;",
                { p[4], p[5], p[6], p[7], p[8], p[9], p[11], spawnId }
            )
        else
            return GRID.Database.FormatQuery(
                "INSERT INTO grid_map_entities (map_name, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                { p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11] }
            )
        end
    end,
    grid_delete_map_entity = "DELETE FROM grid_map_entities WHERE spawn_id = ?;",
    grid_copy_map_spawns = function(p)
        return GRID.Database.FormatQuery(
            "INSERT INTO grid_map_entities (map_name, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data) SELECT ?, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data FROM grid_map_entities WHERE map_name = ?;",
            { p[2], p[1] }
        )
    end,
}
GRID.Database.SQLiteWarned = GRID.Database.SQLiteWarned or {}

function GRID.Database.CallProcedure(procName, params, onDone, onError)
    if GRID.Database.UseSQLiteFallback then
        local emu = GRID.Database.SQLiteProcedures[procName]
        if isstring(emu) then
            GRID.Database.Execute(GRID.Database.FormatQuery(emu, params), onDone, onError)
        elseif isfunction(emu) then
            GRID.Database.Execute(emu(params), onDone, onError)
        else
            if not GRID.Database.SQLiteWarned[procName] then
                GRID.Database.SQLiteWarned[procName] = true
                print(string.format("[GRID DB] SQLite fallback: no emulation for procedure '%s', skipping.", procName))
            end
            if onDone then onDone({}) end
        end
        return
    end

    -- If MariaDB host disallowed stored procedure creation, or as a fallback when CALL fails
    local function runDirect()
        local directFn = GRID.Database.MariaDBDirectProcedures[procName]
        if directFn then
            directFn(params, function(finalQuery)
                if finalQuery then
                    GRID.Database.Execute(finalQuery, onDone, onError)
                elseif onDone then
                    onDone({})
                end
            end)
        elseif onError then
            onError("No direct SQL fallback for procedure " .. tostring(procName))
        end
    end

    if GRID.Database.UseDirectMariaDBSQL then
        runDirect()
        return
    end

    local placeholders = {}
    for i = 1, #params do
        table.insert(placeholders, "?")
    end
    local sqlStr = string.format("CALL %s(%s);", procName, table.concat(placeholders, ", "))
    local query = GRID.Database.FormatQuery(sqlStr, params)
    GRID.Database.Execute(query, onDone, function(err)
        local errStr = string.lower(tostring(err or ""))
        if string.find(errStr, "does not exist", 1, true) or string.find(errStr, "execute command denied", 1, true) then
            GRID.Database.UseDirectMariaDBSQL = true
            runDirect()
        elseif onError then
            onError(err)
        end
    end)
end

function GRID.Database.QueryView(viewName, whereClause, params, onDone, onError)
    local source = viewName
    if GRID.Database.UseSQLiteFallback or GRID.Database.UseDirectViews then
        source = GRID.Database.DirectViews[viewName] or viewName
    end

    local q = "SELECT * FROM " .. source
    if whereClause and whereClause ~= "" then
        q = q .. " WHERE " .. whereClause
    end
    local formatted = GRID.Database.FormatQuery(q, params)
    GRID.Database.Execute(formatted, onDone, function(err)
        local errStr = string.lower(tostring(err or ""))
        if not GRID.Database.UseDirectViews and GRID.Database.DirectViews[viewName] and (string.find(errStr, "doesn't exist", 1, true) or string.find(errStr, "command denied", 1, true)) then
            GRID.Database.UseDirectViews = true
            GRID.Database.QueryView(viewName, whereClause, params, onDone, onError)
        elseif onError then
            onError(err)
        end
    end)
end

-- ========================================================
-- INITIALIZATION & SQLITE FALLBACK
-- ========================================================

function GRID.Database.Init()
    GRID.Database.Connect()
end

-- Auto-seeds all MariaDB tables, analytical views, and stored procedures on connection.
-- If the database user lacks CREATE ROUTINE or CREATE VIEW privileges on a shared panel,
-- it gracefully enables direct SQL fallback so the server runs with zero errors.
function GRID.Database.InitMariaDBSchema(db, onComplete)
    local tableDDLs = {
        [[CREATE TABLE IF NOT EXISTS grid_players (
            steamid VARCHAR(20) NOT NULL PRIMARY KEY,
            name VARCHAR(64) NOT NULL,
            money BIGINT NOT NULL DEFAULT 0,
            bank BIGINT NOT NULL DEFAULT 0,
            respect INT NOT NULL DEFAULT 0,
            gang VARCHAR(32) NOT NULL DEFAULT '',
            job VARCHAR(32) NOT NULL DEFAULT 'citizen',
            level INT NOT NULL DEFAULT 1,
            xp BIGINT NOT NULL DEFAULT 0,
            onboarding_stage TINYINT UNSIGNED NOT NULL DEFAULT 0,
            last_seen INT UNSIGNED NOT NULL DEFAULT 0,
            INDEX idx_players_gang (gang),
            INDEX idx_players_job (job)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

        [[CREATE TABLE IF NOT EXISTS grid_gangs (
            name VARCHAR(32) NOT NULL PRIMARY KEY,
            leader_steamid VARCHAR(20) NOT NULL,
            bank BIGINT NOT NULL DEFAULT 0,
            respect INT NOT NULL DEFAULT 0,
            created_at INT UNSIGNED NOT NULL DEFAULT 0,
            INDEX idx_gangs_leader (leader_steamid),
            INDEX idx_gangs_respect (respect DESC)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

        [[CREATE TABLE IF NOT EXISTS grid_gang_members (
            steamid VARCHAR(20) NOT NULL PRIMARY KEY,
            gang VARCHAR(32) NOT NULL,
            rank VARCHAR(16) NOT NULL DEFAULT 'member',
            joined_at INT UNSIGNED NOT NULL DEFAULT 0,
            INDEX idx_members_gang (gang)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

        [[CREATE TABLE IF NOT EXISTS grid_inventory (
            id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            steamid VARCHAR(20) NOT NULL,
            bag_index TINYINT UNSIGNED NOT NULL DEFAULT 0,
            slot_index TINYINT UNSIGNED NOT NULL DEFAULT 1,
            item_id VARCHAR(64) NOT NULL,
            item_type VARCHAR(32) NOT NULL DEFAULT 'generic',
            amount INT NOT NULL DEFAULT 1,
            item_data JSON NULL,
            INDEX idx_inventory_steamid (steamid, bag_index, slot_index),
            INDEX idx_inventory_item (steamid, item_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

        [[CREATE TABLE IF NOT EXISTS grid_player_bags (
            steamid VARCHAR(20) NOT NULL PRIMARY KEY,
            bag1 VARCHAR(64) NOT NULL DEFAULT '',
            bag2 VARCHAR(64) NOT NULL DEFAULT '',
            bag3 VARCHAR(64) NOT NULL DEFAULT '',
            bag4 VARCHAR(64) NOT NULL DEFAULT ''
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

        [[CREATE TABLE IF NOT EXISTS grid_turfs (
            map VARCHAR(64) NOT NULL,
            turf_id INT NOT NULL,
            name VARCHAR(64) NOT NULL,
            pos_x DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
            pos_y DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
            pos_z DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
            radius INT NOT NULL DEFAULT 450,
            owner VARCHAR(32) NOT NULL DEFAULT 'neutral',
            tax_rate TINYINT UNSIGNED NOT NULL DEFAULT 10,
            PRIMARY KEY (map, turf_id),
            INDEX idx_turfs_owner (owner)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

        [[CREATE TABLE IF NOT EXISTS grid_settings (
            `key` VARCHAR(64) NOT NULL PRIMARY KEY,
            `val` TEXT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

        [[CREATE TABLE IF NOT EXISTS grid_player_buffs (
            steamid VARCHAR(20) NOT NULL,
            buff_id VARCHAR(32) NOT NULL,
            duration DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
            remaining DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
            stacks TINYINT UNSIGNED NOT NULL DEFAULT 1,
            applied_at INT UNSIGNED NOT NULL DEFAULT 0,
            expires_at_unix INT UNSIGNED NOT NULL DEFAULT 0,
            data JSON NULL,
            PRIMARY KEY (steamid, buff_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

        [[CREATE TABLE IF NOT EXISTS grid_telemetry (
            log_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            unix_ts INT UNSIGNED NOT NULL DEFAULT 0,
            category ENUM('ECONOMY', 'PLAYER_ACTION', 'ANTIDEBUG', 'COMBAT', 'TRADE') NOT NULL,
            action_type VARCHAR(48) NOT NULL,
            actor_steamid VARCHAR(20) NOT NULL,
            target_steamid VARCHAR(20) NULL,
            numeric_value DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
            metadata JSON NULL,
            INDEX idx_actor_time (actor_steamid, created_at),
            INDEX idx_category_action_time (category, action_type, created_at),
            INDEX idx_target_time (target_steamid, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

        [[CREATE TABLE IF NOT EXISTS grid_auctions (
            auction_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            seller_steamid VARCHAR(20) NOT NULL,
            seller_name VARCHAR(64) NOT NULL,
            item_id VARCHAR(64) NOT NULL,
            item_type VARCHAR(32) NOT NULL DEFAULT 'generic',
            amount INT UNSIGNED NOT NULL DEFAULT 1,
            item_data JSON NULL,
            start_bid BIGINT UNSIGNED NOT NULL,
            current_bid BIGINT UNSIGNED NOT NULL DEFAULT 0,
            high_bidder_steamid VARCHAR(20) NULL,
            high_bidder_name VARCHAR(64) NULL,
            buyout_price BIGINT UNSIGNED NOT NULL DEFAULT 0,
            deposit_amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
            status ENUM('ACTIVE', 'SOLD', 'EXPIRED', 'CANCELLED') NOT NULL DEFAULT 'ACTIVE',
            duration_hours TINYINT UNSIGNED NOT NULL DEFAULT 24,
            created_at_unix INT UNSIGNED NOT NULL,
            expires_at_unix INT UNSIGNED NOT NULL,
            closed_at_unix INT UNSIGNED NULL,
            INDEX idx_auction_status_expires (status, expires_at_unix),
            INDEX idx_auction_item (item_id, status),
            INDEX idx_auction_seller (seller_steamid, status),
            INDEX idx_auction_bidder (high_bidder_steamid, status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

        [[CREATE TABLE IF NOT EXISTS grid_auction_collection (
            collection_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            steamid VARCHAR(20) NOT NULL,
            item_id VARCHAR(64) NOT NULL,
            item_type VARCHAR(32) NOT NULL DEFAULT 'generic',
            amount INT UNSIGNED NOT NULL DEFAULT 1,
            item_data JSON NULL,
            source_reason ENUM('WON_AUCTION', 'EXPIRED_AUCTION', 'CANCELLED_AUCTION') NOT NULL,
            source_auction_id BIGINT UNSIGNED NOT NULL,
            created_at_unix INT UNSIGNED NOT NULL,
            claimed TINYINT(1) NOT NULL DEFAULT 0,
            claimed_at_unix INT UNSIGNED NULL,
            INDEX idx_collection_claim (steamid, claimed)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

        [[CREATE TABLE IF NOT EXISTS grid_map_entities (
            spawn_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            map_name VARCHAR(64) NOT NULL,
            class_name VARCHAR(64) NOT NULL,
            pos_x FLOAT NOT NULL,
            pos_y FLOAT NOT NULL,
            pos_z FLOAT NOT NULL,
            ang_p FLOAT NOT NULL,
            ang_y FLOAT NOT NULL,
            ang_r FLOAT NOT NULL,
            placed_by VARCHAR(20) NOT NULL,
            custom_data JSON DEFAULT NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_map_name (map_name)
        ) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;]]
    }

    local viewDDLs = {
        [[CREATE OR REPLACE VIEW v_player_profile AS
            SELECT p.steamid, p.name, p.money, p.bank, p.respect, p.gang, p.job, p.level, p.xp, p.onboarding_stage, p.last_seen, m.rank AS gang_rank
            FROM grid_players p LEFT JOIN grid_gang_members m ON p.steamid = m.steamid;]],
        [[CREATE OR REPLACE VIEW v_player_inventory AS
            SELECT id, steamid, bag_index, slot_index, item_id, item_type, amount, item_data FROM grid_inventory;]],
        [[CREATE OR REPLACE VIEW v_player_bags AS
            SELECT steamid, bag1, bag2, bag3, bag4 FROM grid_player_bags;]],
        [[CREATE OR REPLACE VIEW v_player_buffs AS
            SELECT steamid, buff_id, duration, remaining, stacks, applied_at, expires_at_unix, data FROM grid_player_buffs;]],
        [[CREATE OR REPLACE VIEW v_gang_leaderboard AS
            SELECT g.name, g.leader_steamid, p.name AS leader_name, g.bank, g.respect, g.created_at,
                COUNT(DISTINCT m.steamid) AS member_count, COUNT(DISTINCT t.turf_id) AS turf_count
            FROM grid_gangs g
            LEFT JOIN grid_players p ON g.leader_steamid = p.steamid
            LEFT JOIN grid_gang_members m ON g.name = m.gang
            LEFT JOIN grid_turfs t ON g.name = t.owner
            GROUP BY g.name, g.leader_steamid, p.name, g.bank, g.respect, g.created_at
            ORDER BY g.respect DESC, g.bank DESC;]],
        [[CREATE OR REPLACE VIEW v_gang_roster AS
            SELECT m.gang, m.steamid, m.rank, m.joined_at, p.name, p.money, p.job, p.level, p.last_seen
            FROM grid_gang_members m LEFT JOIN grid_players p ON m.steamid = p.steamid
            ORDER BY CASE m.rank WHEN 'leader' THEN 1 WHEN 'officer' THEN 2 ELSE 3 END, m.joined_at ASC;]],
        [[CREATE OR REPLACE VIEW v_map_turfs AS
            SELECT map, turf_id, name, pos_x, pos_y, pos_z, radius, owner, tax_rate FROM grid_turfs ORDER BY turf_id ASC;]],
        [[CREATE OR REPLACE VIEW v_settings AS SELECT `key`, `val` FROM grid_settings;]],
        [[CREATE OR REPLACE VIEW v_economy_metrics AS
            SELECT category, action_type, COUNT(*) AS event_count, SUM(numeric_value) AS total_volume,
                AVG(numeric_value) AS average_volume, MIN(created_at) AS earliest_record, MAX(created_at) AS latest_record
            FROM grid_telemetry WHERE category IN ('ECONOMY', 'TRADE') GROUP BY category, action_type;]],
        [[CREATE OR REPLACE VIEW v_player_audit_history AS
            SELECT log_id, created_at, category, action_type, actor_steamid, target_steamid, numeric_value, metadata
            FROM grid_telemetry ORDER BY created_at DESC;]],
        [[CREATE OR REPLACE VIEW v_combat_telemetry AS
            SELECT action_type AS weapon_class, COUNT(*) AS total_skirmishes, SUM(numeric_value) AS total_damage_dealt,
                AVG(numeric_value) AS avg_damage_per_engagement
            FROM grid_telemetry WHERE category = 'COMBAT' GROUP BY action_type;]],
        [[CREATE OR REPLACE VIEW v_auction_metrics AS
            SELECT 
                a.item_id,
                MIN(CASE WHEN a.status = 'ACTIVE' AND a.buyout_price > 0 THEN a.buyout_price ELSE NULL END) AS min_active_buyout,
                COUNT(CASE WHEN a.status = 'ACTIVE' THEN 1 ELSE NULL END) AS active_listings_count,
                ROUND(AVG(CASE 
                    WHEN a.status = 'SOLD' 
                     AND a.closed_at_unix >= (UNIX_TIMESTAMP() - 604800) 
                    THEN GREATEST(a.current_bid, a.buyout_price) 
                    ELSE NULL 
                END)) AS avg_sale_price_7d,
                COALESCE(SUM(CASE 
                    WHEN a.status = 'SOLD' 
                     AND a.closed_at_unix >= (UNIX_TIMESTAMP() - 86400) 
                    THEN a.amount 
                    ELSE 0 
                END), 0) AS sold_volume_24h
            FROM grid_auctions a
            GROUP BY a.item_id;]],
        [[CREATE OR REPLACE VIEW v_grid_map_spawns AS
            SELECT spawn_id, map_name, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data
            FROM grid_map_entities;]],
        [[CREATE OR REPLACE VIEW v_auctions AS
            SELECT auction_id, seller_steamid, seller_name, item_id, item_type, amount, item_data,
                   start_bid, current_bid, high_bidder_steamid, high_bidder_name, buyout_price,
                   deposit_amount, status, duration_hours, created_at_unix, expires_at_unix, closed_at_unix
            FROM grid_auctions;]],
        [[CREATE OR REPLACE VIEW v_auction_collection AS
            SELECT collection_id, steamid, item_id, item_type, amount, item_data,
                   source_reason, source_auction_id, created_at_unix, claimed, claimed_at_unix
            FROM grid_auction_collection;]]
    }

    local procDDLs = {
        [[CREATE OR REPLACE PROCEDURE grid_log_telemetry(
            IN p_category VARCHAR(20), IN p_action_type VARCHAR(48), IN p_actor_steamid VARCHAR(20),
            IN p_target_steamid VARCHAR(20), IN p_numeric_value DECIMAL(12, 2), IN p_metadata JSON
        ) BEGIN
            INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata)
            VALUES (UNIX_TIMESTAMP(), p_category, p_action_type, p_actor_steamid, p_target_steamid, p_numeric_value, p_metadata);
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_upsert_player(
            IN p_steamid VARCHAR(20), IN p_name VARCHAR(64), IN p_money BIGINT, IN p_respect INT,
            IN p_gang VARCHAR(32), IN p_job VARCHAR(32), IN p_level INT, IN p_xp BIGINT, IN p_last_seen INT UNSIGNED,
            IN p_onboarding_stage TINYINT UNSIGNED, IN p_bank BIGINT
        ) BEGIN
            INSERT INTO grid_players (steamid, name, money, respect, gang, job, level, xp, last_seen, onboarding_stage, bank)
            VALUES (p_steamid, p_name, p_money, p_respect, p_gang, p_job, p_level, p_xp, p_last_seen, p_onboarding_stage, p_bank)
            ON DUPLICATE KEY UPDATE name = p_name, money = p_money, respect = p_respect, gang = p_gang,
                job = p_job, level = p_level, xp = p_xp, last_seen = p_last_seen,
                onboarding_stage = p_onboarding_stage, bank = p_bank;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_update_player_money(
            IN p_steamid VARCHAR(20), IN p_money BIGINT, IN p_last_seen INT UNSIGNED
        ) BEGIN
            UPDATE grid_players SET money = p_money, last_seen = p_last_seen WHERE steamid = p_steamid;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_update_player_bank(
            IN p_steamid VARCHAR(20), IN p_bank BIGINT, IN p_last_seen INT UNSIGNED
        ) BEGIN
            UPDATE grid_players SET bank = p_bank, last_seen = p_last_seen WHERE steamid = p_steamid;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_transfer_personal_bank(
            IN p_steamid VARCHAR(20), IN p_delta BIGINT, IN p_unix_time INT UNSIGNED
        ) BEGIN
            DECLARE v_money BIGINT DEFAULT 0;
            DECLARE v_bank BIGINT DEFAULT 0;
            DECLARE v_status VARCHAR(32) DEFAULT 'ERROR_SQL';
            DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
                ROLLBACK;
                SELECT 'ERROR_SQL' AS status, v_money AS money, v_bank AS bank;
            END;
            START TRANSACTION;
            SELECT money, bank INTO v_money, v_bank FROM grid_players WHERE steamid = p_steamid FOR UPDATE;
            IF p_delta > 0 THEN
                IF v_money >= p_delta THEN
                    SET v_money = v_money - p_delta;
                    SET v_bank = v_bank + p_delta;
                    UPDATE grid_players SET money = v_money, bank = v_bank, last_seen = p_unix_time WHERE steamid = p_steamid;
                    SET v_status = 'SUCCESS';
                    COMMIT;
                ELSE
                    SET v_status = 'ERR_INSUFFICIENT_WALLET';
                    ROLLBACK;
                END IF;
            ELSEIF p_delta < 0 THEN
                IF v_bank >= ABS(p_delta) THEN
                    SET v_money = v_money + ABS(p_delta);
                    SET v_bank = v_bank - ABS(p_delta);
                    UPDATE grid_players SET money = v_money, bank = v_bank, last_seen = p_unix_time WHERE steamid = p_steamid;
                    SET v_status = 'SUCCESS';
                    COMMIT;
                ELSE
                    SET v_status = 'ERR_INSUFFICIENT_BANK';
                    ROLLBACK;
                END IF;
            ELSE
                SET v_status = 'ERR_ZERO_DELTA';
                ROLLBACK;
            END IF;
            SELECT v_status AS status, v_money AS money, v_bank AS bank;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_update_onboarding_stage(
            IN p_steamid VARCHAR(20), IN p_stage TINYINT UNSIGNED
        ) BEGIN
            UPDATE grid_players SET onboarding_stage = p_stage WHERE steamid = p_steamid;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_complete_onboarding(
            IN p_steamid VARCHAR(20), IN p_bonus_clean_cash INT UNSIGNED
        ) BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION
            BEGIN
                ROLLBACK;
            END;

            START TRANSACTION;

            UPDATE grid_players
            SET onboarding_stage = 3,
                level = GREATEST(level, 2),
                bank = bank + p_bonus_clean_cash
            WHERE steamid = p_steamid AND onboarding_stage < 3;

            IF ROW_COUNT() > 0 THEN
                INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata)
                VALUES (
                    UNIX_TIMESTAMP(),
                    'PLAYER_ACTION',
                    'ONBOARDING_COMPLETED',
                    p_steamid,
                    '',
                    p_bonus_clean_cash,
                    JSON_OBJECT('new_level', 2)
                );
            END IF;

            COMMIT;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_reset_player(IN p_steamid VARCHAR(20))
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION
            BEGIN
                ROLLBACK;
                RESIGNAL;
            END;

            START TRANSACTION;

            UPDATE grid_players
            SET money = 0,
                bank = 0,
                respect = 0,
                gang = '',
                job = 'citizen',
                level = 1,
                xp = 0,
                onboarding_stage = 0,
                last_seen = UNIX_TIMESTAMP()
            WHERE steamid = p_steamid;

            DELETE FROM grid_gang_members WHERE steamid = p_steamid;
            DELETE FROM grid_inventory WHERE steamid = p_steamid;
            DELETE FROM grid_player_bags WHERE steamid = p_steamid;
            DELETE FROM grid_player_buffs WHERE steamid = p_steamid;

            INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata)
            VALUES (
                UNIX_TIMESTAMP(),
                'PLAYER_ACTION',
                'PLAYER_FULL_RESET',
                'CONSOLE',
                p_steamid,
                0,
                JSON_OBJECT('reason', 'admin_hud_reset')
            );

            COMMIT;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_update_player_gang(
            IN p_steamid VARCHAR(20), IN p_gang VARCHAR(32), IN p_last_seen INT UNSIGNED
        ) BEGIN
            UPDATE grid_players SET gang = p_gang, last_seen = p_last_seen WHERE steamid = p_steamid;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_update_player_job(
            IN p_steamid VARCHAR(20), IN p_job VARCHAR(32), IN p_last_seen INT UNSIGNED
        ) BEGIN
            UPDATE grid_players SET job = p_job, last_seen = p_last_seen WHERE steamid = p_steamid;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_update_player_level_xp(
            IN p_steamid VARCHAR(20), IN p_level INT, IN p_xp BIGINT, IN p_last_seen INT UNSIGNED
        ) BEGIN
            UPDATE grid_players SET level = p_level, xp = p_xp, last_seen = p_last_seen WHERE steamid = p_steamid;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_create_gang(
            IN p_gang_name VARCHAR(32), IN p_leader_steamid VARCHAR(20), IN p_unix_time INT UNSIGNED
        ) BEGIN
            INSERT INTO grid_gangs (name, leader_steamid, bank, respect, created_at)
            VALUES (p_gang_name, p_leader_steamid, 0, 0, p_unix_time)
            ON DUPLICATE KEY UPDATE leader_steamid = p_leader_steamid;
            INSERT INTO grid_gang_members (steamid, gang, rank, joined_at)
            VALUES (p_leader_steamid, p_gang_name, 'leader', p_unix_time)
            ON DUPLICATE KEY UPDATE gang = p_gang_name, rank = 'leader';
            UPDATE grid_players SET gang = p_gang_name, last_seen = p_unix_time WHERE steamid = p_leader_steamid;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_add_gang_member(
            IN p_steamid VARCHAR(20), IN p_gang_name VARCHAR(32), IN p_rank VARCHAR(16), IN p_unix_time INT UNSIGNED
        ) BEGIN
            INSERT INTO grid_gang_members (steamid, gang, rank, joined_at)
            VALUES (p_steamid, p_gang_name, p_rank, p_unix_time)
            ON DUPLICATE KEY UPDATE gang = p_gang_name, rank = p_rank;
            UPDATE grid_players SET gang = p_gang_name, last_seen = p_unix_time WHERE steamid = p_steamid;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_remove_gang_member(IN p_steamid VARCHAR(20)) BEGIN
            DELETE FROM grid_gang_members WHERE steamid = p_steamid;
            UPDATE grid_players SET gang = '' WHERE steamid = p_steamid;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_add_gang_bank(IN p_gang_name VARCHAR(32), IN p_amount BIGINT) BEGIN
            UPDATE grid_gangs SET bank = GREATEST(0, bank + p_amount) WHERE name = p_gang_name;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_transfer_gang_vault(
            IN p_steamid VARCHAR(20), IN p_gang_name VARCHAR(32), IN p_delta BIGINT, IN p_unix_time INT UNSIGNED
        ) BEGIN
            DECLARE v_player_money BIGINT DEFAULT 0;
            DECLARE v_gang_bank BIGINT DEFAULT 0;
            SELECT money INTO v_player_money FROM grid_players WHERE steamid = p_steamid FOR UPDATE;
            SELECT bank INTO v_gang_bank FROM grid_gangs WHERE name = p_gang_name FOR UPDATE;
            IF (p_delta > 0 AND v_player_money >= p_delta) THEN
                UPDATE grid_players SET money = money - p_delta, last_seen = p_unix_time WHERE steamid = p_steamid;
                UPDATE grid_gangs SET bank = bank + p_delta WHERE name = p_gang_name;
            ELSEIF (p_delta < 0 AND v_gang_bank >= ABS(p_delta)) THEN
                UPDATE grid_players SET money = money + ABS(p_delta), last_seen = p_unix_time WHERE steamid = p_steamid;
                UPDATE grid_gangs SET bank = bank - ABS(p_delta) WHERE name = p_gang_name;
            END IF;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_disband_gang(IN p_gang_name VARCHAR(32)) BEGIN
            UPDATE grid_players SET gang = '' WHERE gang = p_gang_name;
            DELETE FROM grid_gang_members WHERE gang = p_gang_name;
            DELETE FROM grid_gangs WHERE name = p_gang_name;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_set_inventory_slot(
            IN p_steamid VARCHAR(20), IN p_bag_index TINYINT UNSIGNED, IN p_slot_index TINYINT UNSIGNED,
            IN p_item_id VARCHAR(64), IN p_item_type VARCHAR(32), IN p_amount INT, IN p_item_data JSON
        ) BEGIN
            DELETE FROM grid_inventory WHERE steamid = p_steamid AND bag_index = p_bag_index AND slot_index = p_slot_index;
            IF p_amount > 0 THEN
                INSERT INTO grid_inventory (steamid, bag_index, slot_index, item_id, item_type, amount, item_data)
                VALUES (p_steamid, p_bag_index, p_slot_index, p_item_id, p_item_type, p_amount, p_item_data);
            END IF;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_delete_inventory_slot(
            IN p_steamid VARCHAR(20), IN p_bag_index TINYINT UNSIGNED, IN p_slot_index TINYINT UNSIGNED
        ) BEGIN
            DELETE FROM grid_inventory WHERE steamid = p_steamid AND bag_index = p_bag_index AND slot_index = p_slot_index;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_move_inventory_slot(
            IN p_steamid VARCHAR(20), IN p_from_bag TINYINT UNSIGNED, IN p_from_slot TINYINT UNSIGNED,
            IN p_to_bag TINYINT UNSIGNED, IN p_to_slot TINYINT UNSIGNED
        ) BEGIN
            DECLARE v_src_id BIGINT UNSIGNED;
            DECLARE v_src_item VARCHAR(64);
            DECLARE v_src_type VARCHAR(32);
            DECLARE v_src_amt INT;
            DECLARE v_dst_id BIGINT UNSIGNED;
            DECLARE v_dst_item VARCHAR(64);
            SELECT id, item_id, item_type, amount INTO v_src_id, v_src_item, v_src_type, v_src_amt FROM grid_inventory
                WHERE steamid = p_steamid AND bag_index = p_from_bag AND slot_index = p_from_slot LIMIT 1;
            IF v_src_id IS NOT NULL THEN
                SELECT id, item_id INTO v_dst_id, v_dst_item FROM grid_inventory
                    WHERE steamid = p_steamid AND bag_index = p_to_bag AND slot_index = p_to_slot LIMIT 1;
                IF v_dst_id IS NULL THEN
                    UPDATE grid_inventory SET bag_index = p_to_bag, slot_index = p_to_slot WHERE id = v_src_id;
                ELSEIF v_src_item = v_dst_item AND v_src_type != 'weapon' THEN
                    UPDATE grid_inventory SET amount = amount + v_src_amt WHERE id = v_dst_id;
                    DELETE FROM grid_inventory WHERE id = v_src_id;
                ELSE
                    UPDATE grid_inventory SET bag_index = p_to_bag, slot_index = p_to_slot WHERE id = v_src_id;
                    UPDATE grid_inventory SET bag_index = p_from_bag, slot_index = p_from_slot WHERE id = v_dst_id;
                END IF;
            END IF;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_set_player_bags(
            IN p_steamid VARCHAR(20), IN p_bag1 VARCHAR(64), IN p_bag2 VARCHAR(64), IN p_bag3 VARCHAR(64), IN p_bag4 VARCHAR(64)
        ) BEGIN
            INSERT INTO grid_player_bags (steamid, bag1, bag2, bag3, bag4)
            VALUES (p_steamid, p_bag1, p_bag2, p_bag3, p_bag4)
            ON DUPLICATE KEY UPDATE bag1 = p_bag1, bag2 = p_bag2, bag3 = p_bag3, bag4 = p_bag4;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_save_map_turf(
            IN p_map VARCHAR(64), IN p_turf_id INT, IN p_name VARCHAR(64),
            IN p_pos_x DECIMAL(10, 2), IN p_pos_y DECIMAL(10, 2), IN p_pos_z DECIMAL(10, 2),
            IN p_radius INT, IN p_owner VARCHAR(32), IN p_tax_rate TINYINT UNSIGNED
        ) BEGIN
            INSERT INTO grid_turfs (map, turf_id, name, pos_x, pos_y, pos_z, radius, owner, tax_rate)
            VALUES (p_map, p_turf_id, p_name, p_pos_x, p_pos_y, p_pos_z, p_radius, p_owner, p_tax_rate)
            ON DUPLICATE KEY UPDATE name = p_name, pos_x = p_pos_x, pos_y = p_pos_y, pos_z = p_pos_z,
                radius = p_radius, owner = p_owner, tax_rate = p_tax_rate;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_clear_map_turfs(IN p_map VARCHAR(64)) BEGIN
            DELETE FROM grid_turfs WHERE map = p_map;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_delete_map_turf(IN p_map VARCHAR(64), IN p_turf_id INT) BEGIN
            DELETE FROM grid_turfs WHERE map = p_map AND turf_id = p_turf_id;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_set_turf_tax(IN p_map VARCHAR(64), IN p_turf_id INT, IN p_tax_rate TINYINT UNSIGNED) BEGIN
            UPDATE grid_turfs SET tax_rate = p_tax_rate WHERE map = p_map AND turf_id = p_turf_id;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_collect_printer_taxed(
            IN p_actor_steamid VARCHAR(20), IN p_controlling_gang VARCHAR(32),
            IN p_payout_amount BIGINT, IN p_tax_amount BIGINT, IN p_unix_time INT UNSIGNED
        ) BEGIN
            UPDATE grid_players SET money = money + p_payout_amount, last_seen = p_unix_time WHERE steamid = p_actor_steamid;
            IF p_tax_amount > 0 AND p_controlling_gang != '' AND p_controlling_gang != 'neutral' AND p_controlling_gang != 'Police' THEN
                UPDATE grid_gangs SET bank = bank + p_tax_amount WHERE name = p_controlling_gang;
            END IF;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_save_player_buff(
            IN p_steamid VARCHAR(20), IN p_buff_id VARCHAR(32), IN p_duration DECIMAL(10, 2),
            IN p_remaining DECIMAL(10, 2), IN p_stacks TINYINT UNSIGNED,
            IN p_applied_at INT UNSIGNED, IN p_expires_at_unix INT UNSIGNED, IN p_data JSON
        ) BEGIN
            INSERT INTO grid_player_buffs (steamid, buff_id, duration, remaining, stacks, applied_at, expires_at_unix, data)
            VALUES (p_steamid, p_buff_id, p_duration, p_remaining, p_stacks, p_applied_at, p_expires_at_unix, p_data)
            ON DUPLICATE KEY UPDATE duration = p_duration, remaining = p_remaining, stacks = p_stacks,
                applied_at = p_applied_at, expires_at_unix = p_expires_at_unix, data = p_data;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_delete_player_buff(IN p_steamid VARCHAR(20), IN p_buff_id VARCHAR(32)) BEGIN
            DELETE FROM grid_player_buffs WHERE steamid = p_steamid AND buff_id = p_buff_id;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_clear_player_buffs(IN p_steamid VARCHAR(20)) BEGIN
            DELETE FROM grid_player_buffs WHERE steamid = p_steamid;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_set_setting(IN p_key VARCHAR(64), IN p_val TEXT) BEGIN
            INSERT INTO grid_settings (`key`, `val`) VALUES (p_key, p_val) ON DUPLICATE KEY UPDATE `val` = p_val;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_auction_create(
            IN p_seller_steamid VARCHAR(20), IN p_seller_name VARCHAR(64),
            IN p_bag_index TINYINT UNSIGNED, IN p_slot_index TINYINT UNSIGNED,
            IN p_start_bid BIGINT UNSIGNED, IN p_buyout_price BIGINT UNSIGNED, IN p_duration_hours TINYINT UNSIGNED,
            IN p_deposit_amount BIGINT UNSIGNED, IN p_now_unix INT UNSIGNED
        ) BEGIN
            DECLARE v_active_count INT DEFAULT 0;
            DECLARE v_item_id VARCHAR(64);
            DECLARE v_item_type VARCHAR(32);
            DECLARE v_amount INT DEFAULT 0;
            DECLARE v_item_data JSON;
            DECLARE v_seller_money BIGINT DEFAULT 0;
            DECLARE v_out_status VARCHAR(32) DEFAULT 'ERROR_SQL';
            DECLARE v_out_auction_id BIGINT UNSIGNED DEFAULT 0;

            DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
                ROLLBACK;
                SELECT 'ERROR_SQL' AS status, 0 AS auction_id, '' AS item_id, 0 AS amount;
            END;

            START TRANSACTION;

            SELECT COUNT(*) INTO v_active_count FROM grid_auctions WHERE seller_steamid = p_seller_steamid AND status = 'ACTIVE';
            IF v_active_count >= 10 THEN
                SET v_out_status = 'ERR_MAX_LISTINGS';
                ROLLBACK;
            ELSE
                SELECT money INTO v_seller_money FROM grid_players WHERE steamid = p_seller_steamid FOR UPDATE;
                IF v_seller_money < p_deposit_amount THEN
                    SET v_out_status = 'ERR_INSUFFICIENT_FUNDS';
                    ROLLBACK;
                ELSE
                    SELECT item_id, item_type, amount, item_data INTO v_item_id, v_item_type, v_amount, v_item_data
                    FROM grid_inventory WHERE steamid = p_seller_steamid AND bag_index = p_bag_index AND slot_index = p_slot_index FOR UPDATE;
                    IF v_item_id IS NULL THEN
                        SET v_out_status = 'ERR_ITEM_NOT_FOUND';
                        ROLLBACK;
                    ELSE
                        DELETE FROM grid_inventory WHERE steamid = p_seller_steamid AND bag_index = p_bag_index AND slot_index = p_slot_index;
                        UPDATE grid_players SET money = money - p_deposit_amount WHERE steamid = p_seller_steamid;
                        INSERT INTO grid_auctions (
                            seller_steamid, seller_name, item_id, item_type, amount, item_data,
                            start_bid, current_bid, buyout_price, deposit_amount, status,
                            duration_hours, created_at_unix, expires_at_unix
                        ) VALUES (
                            p_seller_steamid, p_seller_name, v_item_id, v_item_type, v_amount, v_item_data,
                            p_start_bid, 0, p_buyout_price, p_deposit_amount, 'ACTIVE',
                            p_duration_hours, p_now_unix, p_now_unix + (p_duration_hours * 3600)
                        );
                        SET v_out_auction_id = LAST_INSERT_ID();
                        SET v_out_status = 'SUCCESS';
                        INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, numeric_value, metadata)
                        VALUES (p_now_unix, 'ECONOMY', 'AUCTION_LIST', p_seller_steamid, p_deposit_amount, JSON_OBJECT('item_id', v_item_id, 'auction_id', v_out_auction_id, 'buyout', p_buyout_price, 'start_bid', p_start_bid));
                        COMMIT;
                    END IF;
                END IF;
            END IF;
            SELECT v_out_status AS status, v_out_auction_id AS auction_id, COALESCE(v_item_id, '') AS item_id, COALESCE(v_amount, 0) AS amount;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_auction_bid(
            IN p_auction_id BIGINT UNSIGNED, IN p_bidder_steamid VARCHAR(20), IN p_bidder_name VARCHAR(64),
            IN p_bid_amount BIGINT UNSIGNED, IN p_now_unix INT UNSIGNED
        ) BEGIN
            DECLARE v_seller_steamid VARCHAR(20);
            DECLARE v_status VARCHAR(16);
            DECLARE v_expires_at_unix INT UNSIGNED;
            DECLARE v_start_bid BIGINT UNSIGNED;
            DECLARE v_current_bid BIGINT UNSIGNED;
            DECLARE v_buyout_price BIGINT UNSIGNED;
            DECLARE v_prev_bidder VARCHAR(20);
            DECLARE v_bidder_money BIGINT;
            DECLARE v_out_status VARCHAR(32) DEFAULT 'ERROR_SQL';

            DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
                ROLLBACK;
                SELECT 'ERROR_SQL' AS status, '' AS prev_bidder, 0 AS prev_bid;
            END;

            START TRANSACTION;
            SELECT seller_steamid, status, expires_at_unix, start_bid, current_bid, buyout_price, high_bidder_steamid
            INTO v_seller_steamid, v_status, v_expires_at_unix, v_start_bid, v_current_bid, v_buyout_price, v_prev_bidder
            FROM grid_auctions WHERE auction_id = p_auction_id FOR UPDATE;

            IF v_status IS NULL OR v_status != 'ACTIVE' THEN
                SET v_out_status = 'ERR_NOT_ACTIVE';
                ROLLBACK;
            ELSEIF v_expires_at_unix <= p_now_unix THEN
                SET v_out_status = 'ERR_EXPIRED';
                ROLLBACK;
            ELSEIF v_seller_steamid = p_bidder_steamid THEN
                SET v_out_status = 'ERR_SELF_BID';
                ROLLBACK;
            ELSEIF (v_current_bid = 0 AND p_bid_amount < v_start_bid) OR (v_current_bid > 0 AND p_bid_amount <= v_current_bid) THEN
                SET v_out_status = 'ERR_BID_TOO_LOW';
                ROLLBACK;
            ELSE
                SELECT money INTO v_bidder_money FROM grid_players WHERE steamid = p_bidder_steamid FOR UPDATE;
                IF v_bidder_money < p_bid_amount THEN
                    SET v_out_status = 'ERR_INSUFFICIENT_FUNDS';
                    ROLLBACK;
                ELSE
                    IF v_prev_bidder IS NOT NULL AND v_prev_bidder != '' AND v_current_bid > 0 THEN
                        UPDATE grid_players SET money = money + v_current_bid WHERE steamid = v_prev_bidder;
                    END IF;
                    UPDATE grid_players SET money = money - p_bid_amount WHERE steamid = p_bidder_steamid;
                    UPDATE grid_auctions SET current_bid = p_bid_amount, high_bidder_steamid = p_bidder_steamid, high_bidder_name = p_bidder_name WHERE auction_id = p_auction_id;
                    SET v_out_status = 'SUCCESS';
                    INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata)
                    VALUES (p_now_unix, 'ECONOMY', 'AUCTION_BID', p_bidder_steamid, v_seller_steamid, p_bid_amount, JSON_OBJECT('auction_id', p_auction_id));
                    COMMIT;
                END IF;
            END IF;
            SELECT v_out_status AS status, COALESCE(v_prev_bidder, '') AS prev_bidder, COALESCE(v_current_bid, 0) AS prev_bid;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_auction_buyout(
            IN p_auction_id BIGINT UNSIGNED, IN p_buyer_steamid VARCHAR(20), IN p_buyer_name VARCHAR(64),
            IN p_now_unix INT UNSIGNED
        ) BEGIN
            DECLARE v_seller_steamid VARCHAR(20);
            DECLARE v_status VARCHAR(16);
            DECLARE v_expires_at_unix INT UNSIGNED;
            DECLARE v_buyout_price BIGINT UNSIGNED DEFAULT 0;
            DECLARE v_current_bid BIGINT UNSIGNED DEFAULT 0;
            DECLARE v_prev_bidder VARCHAR(20);
            DECLARE v_deposit_amount BIGINT UNSIGNED DEFAULT 0;
            DECLARE v_item_id VARCHAR(64);
            DECLARE v_item_type VARCHAR(32);
            DECLARE v_amount INT DEFAULT 0;
            DECLARE v_item_data JSON;
            DECLARE v_buyer_money BIGINT;
            DECLARE v_tax BIGINT UNSIGNED DEFAULT 0;
            DECLARE v_seller_payout BIGINT UNSIGNED DEFAULT 0;
            DECLARE v_out_status VARCHAR(32) DEFAULT 'ERROR_SQL';

            DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
                ROLLBACK;
                SELECT 'ERROR_SQL' AS status;
            END;

            START TRANSACTION;
            SELECT seller_steamid, status, expires_at_unix, buyout_price, current_bid, high_bidder_steamid,
                   deposit_amount, item_id, item_type, amount, item_data
            INTO v_seller_steamid, v_status, v_expires_at_unix, v_buyout_price, v_current_bid, v_prev_bidder,
                 v_deposit_amount, v_item_id, v_item_type, v_amount, v_item_data
            FROM grid_auctions WHERE auction_id = p_auction_id FOR UPDATE;

            IF v_status IS NULL OR v_status != 'ACTIVE' THEN
                SET v_out_status = 'ERR_NOT_ACTIVE';
                ROLLBACK;
            ELSEIF v_expires_at_unix <= p_now_unix THEN
                SET v_out_status = 'ERR_EXPIRED';
                ROLLBACK;
            ELSEIF v_buyout_price = 0 THEN
                SET v_out_status = 'ERR_NO_BUYOUT';
                ROLLBACK;
            ELSEIF v_seller_steamid = p_buyer_steamid THEN
                SET v_out_status = 'ERR_SELF_BUY';
                ROLLBACK;
            ELSE
                SELECT money INTO v_buyer_money FROM grid_players WHERE steamid = p_buyer_steamid FOR UPDATE;
                IF v_buyer_money < v_buyout_price THEN
                    SET v_out_status = 'ERR_INSUFFICIENT_FUNDS';
                    ROLLBACK;
                ELSE
                    IF v_prev_bidder IS NOT NULL AND v_prev_bidder != '' AND v_current_bid > 0 THEN
                        UPDATE grid_players SET money = money + v_current_bid WHERE steamid = v_prev_bidder;
                    END IF;
                    UPDATE grid_players SET money = money - v_buyout_price WHERE steamid = p_buyer_steamid;
                    SET v_tax = FLOOR(v_buyout_price * 0.075);
                    SET v_seller_payout = (v_buyout_price - v_tax) + v_deposit_amount;
                    UPDATE grid_players SET money = money + v_seller_payout WHERE steamid = v_seller_steamid;
                    INSERT INTO grid_auction_collection (
                        steamid, item_id, item_type, amount, item_data, source_reason, source_auction_id, created_at_unix, claimed
                    ) VALUES (
                        p_buyer_steamid, v_item_id, v_item_type, v_amount, v_item_data, 'WON_AUCTION', p_auction_id, p_now_unix, 0
                    );
                    UPDATE grid_auctions SET status = 'SOLD', closed_at_unix = p_now_unix, high_bidder_steamid = p_buyer_steamid, high_bidder_name = p_buyer_name, current_bid = v_buyout_price WHERE auction_id = p_auction_id;
                    SET v_out_status = 'SUCCESS';
                    INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata)
                    VALUES (p_now_unix, 'ECONOMY', 'AUCTION_SALE', p_buyer_steamid, v_seller_steamid, v_tax, JSON_OBJECT('auction_id', p_auction_id, 'item_id', v_item_id, 'buyout', v_buyout_price, 'tax', v_tax, 'payout', v_seller_payout));
                    COMMIT;
                END IF;
            END IF;
            SELECT v_out_status AS status, COALESCE(v_seller_steamid, '') AS seller_steamid, v_seller_payout AS seller_payout,
                   COALESCE(v_prev_bidder, '') AS prev_bidder, v_current_bid AS prev_bid, v_buyout_price AS buyout_price,
                   v_tax AS tax, COALESCE(v_item_id, '') AS item_id, v_amount AS amount;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_auction_cancel(
            IN p_auction_id BIGINT UNSIGNED, IN p_seller_steamid VARCHAR(20), IN p_now_unix INT UNSIGNED
        ) BEGIN
            DECLARE v_status VARCHAR(16);
            DECLARE v_seller_steamid VARCHAR(20);
            DECLARE v_current_bid BIGINT UNSIGNED;
            DECLARE v_item_id VARCHAR(64);
            DECLARE v_item_type VARCHAR(32);
            DECLARE v_amount INT;
            DECLARE v_item_data JSON;
            DECLARE v_deposit_amount BIGINT UNSIGNED DEFAULT 0;
            DECLARE v_out_status VARCHAR(32) DEFAULT 'ERROR_SQL';

            DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
                ROLLBACK;
                SELECT 'ERROR_SQL' AS status, 0 AS deposit_amount;
            END;

            START TRANSACTION;
            SELECT status, seller_steamid, current_bid, item_id, item_type, amount, item_data, deposit_amount
            INTO v_status, v_seller_steamid, v_current_bid, v_item_id, v_item_type, v_amount, v_item_data, v_deposit_amount
            FROM grid_auctions WHERE auction_id = p_auction_id FOR UPDATE;

            IF v_status IS NULL OR v_status != 'ACTIVE' THEN
                SET v_out_status = 'ERR_NOT_ACTIVE';
                ROLLBACK;
            ELSEIF v_seller_steamid != p_seller_steamid THEN
                SET v_out_status = 'ERR_NOT_OWNER';
                ROLLBACK;
            ELSEIF v_current_bid > 0 THEN
                SET v_out_status = 'ERR_HAS_BIDS';
                ROLLBACK;
            ELSE
                INSERT INTO grid_auction_collection (
                    steamid, item_id, item_type, amount, item_data, source_reason, source_auction_id, created_at_unix, claimed
                ) VALUES (
                    p_seller_steamid, v_item_id, v_item_type, v_amount, v_item_data, 'CANCELLED_AUCTION', p_auction_id, p_now_unix, 0
                );
                UPDATE grid_auctions SET status = 'CANCELLED', closed_at_unix = p_now_unix WHERE auction_id = p_auction_id;
                SET v_out_status = 'SUCCESS';
                INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, numeric_value, metadata)
                VALUES (p_now_unix, 'ECONOMY', 'AUCTION_CANCEL', p_seller_steamid, v_deposit_amount, JSON_OBJECT('auction_id', p_auction_id, 'deposit_forfeited', v_deposit_amount));
                COMMIT;
            END IF;
            SELECT v_out_status AS status, COALESCE(v_deposit_amount, 0) AS deposit_amount;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_auction_claim_collection(
            IN p_collection_id BIGINT UNSIGNED, IN p_steamid VARCHAR(20), IN p_bag_index TINYINT UNSIGNED,
            IN p_slot_index TINYINT UNSIGNED, IN p_now_unix INT UNSIGNED
        ) BEGIN
            DECLARE v_item_id VARCHAR(64);
            DECLARE v_item_type VARCHAR(32);
            DECLARE v_amount INT DEFAULT 1;
            DECLARE v_item_data JSON;
            DECLARE v_claimed TINYINT;
            DECLARE v_out_status VARCHAR(32) DEFAULT 'ERROR_SQL';

            DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
                ROLLBACK;
                SELECT 'ERROR_SQL' AS status;
            END;

            START TRANSACTION;
            SELECT item_id, item_type, amount, item_data, claimed
            INTO v_item_id, v_item_type, v_amount, v_item_data, v_claimed
            FROM grid_auction_collection WHERE collection_id = p_collection_id AND steamid = p_steamid FOR UPDATE;

            IF v_item_id IS NULL THEN
                SET v_out_status = 'ERR_NOT_FOUND';
                ROLLBACK;
            ELSEIF v_claimed = 1 THEN
                SET v_out_status = 'ERR_ALREADY_CLAIMED';
                ROLLBACK;
            ELSE
                INSERT INTO grid_inventory (steamid, bag_index, slot_index, item_id, item_type, amount, item_data)
                VALUES (p_steamid, p_bag_index, p_slot_index, v_item_id, v_item_type, v_amount, v_item_data);
                UPDATE grid_auction_collection SET claimed = 1, claimed_at_unix = p_now_unix WHERE collection_id = p_collection_id;
                SET v_out_status = 'SUCCESS';
                COMMIT;
            END IF;
            SELECT v_out_status AS status, COALESCE(v_item_id, '') AS item_id, COALESCE(v_item_type, 'generic') AS item_type,
                   COALESCE(v_amount, 1) AS amount, COALESCE(v_item_data, '{}') AS item_data;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_auction_process_expirations(IN p_now_unix INT UNSIGNED) BEGIN
            DECLARE done INT DEFAULT FALSE;
            DECLARE v_auc_id BIGINT UNSIGNED;
            DECLARE v_seller VARCHAR(20);
            DECLARE v_bidder VARCHAR(20);
            DECLARE v_bidder_name VARCHAR(64);
            DECLARE v_cur_bid BIGINT UNSIGNED;
            DECLARE v_deposit BIGINT UNSIGNED;
            DECLARE v_item_id VARCHAR(64);
            DECLARE v_item_type VARCHAR(32);
            DECLARE v_amount INT;
            DECLARE v_item_data JSON;
            DECLARE v_tax BIGINT UNSIGNED;
            DECLARE v_payout BIGINT UNSIGNED;

            DECLARE cur CURSOR FOR 
                SELECT auction_id, seller_steamid, high_bidder_steamid, high_bidder_name, current_bid,
                       deposit_amount, item_id, item_type, amount, item_data
                FROM grid_auctions WHERE status = 'ACTIVE' AND expires_at_unix <= p_now_unix;
            DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

            OPEN cur;
            read_loop: LOOP
                FETCH cur INTO v_auc_id, v_seller, v_bidder, v_bidder_name, v_cur_bid,
                               v_deposit, v_item_id, v_item_type, v_amount, v_item_data;
                IF done THEN LEAVE read_loop; END IF;

                IF v_cur_bid > 0 AND v_bidder IS NOT NULL AND v_bidder != '' THEN
                    SET v_tax = FLOOR(v_cur_bid * 0.075);
                    SET v_payout = (v_cur_bid - v_tax) + v_deposit;
                    UPDATE grid_players SET money = money + v_payout WHERE steamid = v_seller;
                    INSERT INTO grid_auction_collection (
                        steamid, item_id, item_type, amount, item_data, source_reason, source_auction_id, created_at_unix, claimed
                    ) VALUES (
                        v_bidder, v_item_id, v_item_type, v_amount, v_item_data, 'WON_AUCTION', v_auc_id, p_now_unix, 0
                    );
                    UPDATE grid_auctions SET status = 'SOLD', closed_at_unix = p_now_unix WHERE auction_id = v_auc_id;
                    INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata)
                    VALUES (p_now_unix, 'ECONOMY', 'AUCTION_EXPIRE_SOLD', v_bidder, v_seller, v_tax, JSON_OBJECT('auction_id', v_auc_id, 'tax', v_tax, 'payout', v_payout));
                ELSE
                    INSERT INTO grid_auction_collection (
                        steamid, item_id, item_type, amount, item_data, source_reason, source_auction_id, created_at_unix, claimed
                    ) VALUES (
                        v_seller, v_item_id, v_item_type, v_amount, v_item_data, 'EXPIRED_AUCTION', v_auc_id, p_now_unix, 0
                    );
                    UPDATE grid_auctions SET status = 'EXPIRED', closed_at_unix = p_now_unix WHERE auction_id = v_auc_id;
                    INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, numeric_value, metadata)
                    VALUES (p_now_unix, 'ECONOMY', 'AUCTION_EXPIRE_UNSOLD', v_seller, v_deposit, JSON_OBJECT('auction_id', v_auc_id, 'deposit_forfeited', v_deposit));
                END IF;
            END LOOP;
            CLOSE cur;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_save_map_entity(
            IN p_spawn_id INT UNSIGNED,
            IN p_map VARCHAR(64),
            IN p_class VARCHAR(64),
            IN p_x FLOAT, IN p_y FLOAT, IN p_z FLOAT,
            IN p_p FLOAT, IN p_yaw FLOAT, IN p_r FLOAT,
            IN p_admin_sid VARCHAR(20),
            IN p_custom_data JSON
        ) BEGIN
            IF p_spawn_id > 0 THEN
                UPDATE grid_map_entities
                SET pos_x = p_x, pos_y = p_y, pos_z = p_z,
                    ang_p = p_p, ang_y = p_yaw, ang_r = p_r,
                    custom_data = COALESCE(p_custom_data, custom_data)
                WHERE spawn_id = p_spawn_id;
                SELECT p_spawn_id AS spawn_id;
            ELSE
                INSERT INTO grid_map_entities (map_name, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data)
                VALUES (p_map, p_class, p_x, p_y, p_z, p_p, p_yaw, p_r, p_admin_sid, p_custom_data);
                SELECT LAST_INSERT_ID() AS spawn_id;
            END IF;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_delete_map_entity(IN p_spawn_id INT UNSIGNED) BEGIN
            DELETE FROM grid_map_entities WHERE spawn_id = p_spawn_id;
        END]],
        [[CREATE OR REPLACE PROCEDURE grid_copy_map_spawns(IN p_old_map VARCHAR(64), IN p_new_map VARCHAR(64)) BEGIN
            INSERT INTO grid_map_entities (map_name, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data)
            SELECT p_new_map, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data
            FROM grid_map_entities WHERE map_name = p_old_map;
        END]]
    }

    -- Schema Migrations: Safely alter existing tables if newer columns are missing
    local migrationDDLs = {
        "ALTER TABLE grid_players ADD COLUMN IF NOT EXISTS bank BIGINT NOT NULL DEFAULT 0 AFTER money;",
        "ALTER TABLE grid_players ADD COLUMN IF NOT EXISTS onboarding_stage TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER xp;"
    }

    local function runBatch(list, idx, onBatchDone, onItemError)
        if idx > #list then
            if onBatchDone then onBatchDone() end
            return
        end
        local q = db:query(list[idx])
        function q:onSuccess()
            runBatch(list, idx + 1, onBatchDone, onItemError)
        end
        function q:onError(err)
            if onItemError then onItemError(err, list[idx]) end
            runBatch(list, idx + 1, onBatchDone, onItemError)
        end
        q:start()
    end

    runBatch(tableDDLs, 1, function()
        runBatch(migrationDDLs, 1, function()
            local viewsFailed = false
            runBatch(viewDDLs, 1, function()
                if viewsFailed then
                    GRID.Database.UseDirectViews = true
                    print("[GRID DB] MariaDB user lacks CREATE VIEW privilege; using direct table SELECT fallback.")
                end
                local procsFailed = false
                runBatch(procDDLs, 1, function()
                    if procsFailed then
                        GRID.Database.UseDirectMariaDBSQL = true
                        print("[GRID DB] MariaDB user lacks CREATE ROUTINE privilege; using direct SQL query fallback.")
                    else
                        print("[GRID DB] MariaDB tables, views, and stored procedures verified & seeded!")
                    end
                    if onComplete then onComplete() end
                end, function()
                    procsFailed = true
                end)
            end, function()
                viewsFailed = true
            end)
        end, function(mErr)
            ErrorNoHalt(string.format("[GRID DB WARNING] Non-fatal migration error: %s\n", tostring(mErr)))
        end)
    end, function(err)
        ErrorNoHalt(string.format("[GRID DB ERROR] Failed creating MariaDB table: %s\n", tostring(err)))
    end)
end

-- Preload gangs, gang members, and settings into RAM cache on connection
function GRID.Database.PreloadCaches()
    GRID.Database.Execute("SELECT * FROM grid_gangs;", function(rows)
        for _, r in ipairs(rows or {}) do
            GRID.Database.Cache.Gangs[r.name] = r
        end
    end)
    GRID.Database.Execute("SELECT * FROM grid_gang_members;", function(rows)
        for _, r in ipairs(rows or {}) do
            GRID.Database.Cache.GangMembers[r.steamid] = r
        end
    end)
    GRID.Database.Execute("SELECT `key`, `val` FROM grid_settings;", function(rows)
        for _, r in ipairs(rows or {}) do
            GRID.Database.Cache.Settings[r.key] = r.val
        end
    end)
end

-- SQLite Dev Fallback table creation (only invoked if mysqloo binary module is not present on developer's local PC)
function GRID.Database.InitSQLiteFallback()
    sql.Query([[
        CREATE TABLE IF NOT EXISTS grid_players (
            steamid TEXT PRIMARY KEY,
            name TEXT,
            money INTEGER DEFAULT 0,
            bank INTEGER DEFAULT 0,
            respect INTEGER DEFAULT 0,
            gang TEXT DEFAULT '',
            job TEXT DEFAULT 'citizen',
            level INTEGER DEFAULT 1,
            xp INTEGER DEFAULT 0,
            onboarding_stage INTEGER DEFAULT 0,
            last_seen INTEGER
        );
        CREATE TABLE IF NOT EXISTS grid_gangs (
            name TEXT PRIMARY KEY,
            leader_steamid TEXT,
            bank INTEGER DEFAULT 0,
            respect INTEGER DEFAULT 0,
            created_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS grid_gang_members (
            steamid TEXT PRIMARY KEY,
            gang TEXT,
            rank TEXT DEFAULT 'member',
            joined_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS grid_inventory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            steamid TEXT,
            bag_index INTEGER DEFAULT 0,
            slot_index INTEGER DEFAULT 1,
            item_id TEXT,
            item_type TEXT,
            amount INTEGER DEFAULT 1,
            item_data TEXT DEFAULT '{}'
        );
        CREATE TABLE IF NOT EXISTS grid_player_bags (
            steamid TEXT PRIMARY KEY,
            bag1 TEXT DEFAULT '',
            bag2 TEXT DEFAULT '',
            bag3 TEXT DEFAULT '',
            bag4 TEXT DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS grid_turfs (
            map TEXT,
            turf_id INTEGER,
            name TEXT,
            pos_x REAL,
            pos_y REAL,
            pos_z REAL,
            radius INTEGER,
            owner TEXT DEFAULT 'neutral',
            tax_rate INTEGER DEFAULT 10,
            PRIMARY KEY (map, turf_id)
        );
        CREATE TABLE IF NOT EXISTS grid_settings (
            key TEXT PRIMARY KEY,
            val TEXT
        );
        CREATE TABLE IF NOT EXISTS grid_player_buffs (
            steamid TEXT NOT NULL,
            buff_id TEXT NOT NULL,
            duration REAL DEFAULT 0,
            remaining REAL DEFAULT 0,
            stacks INTEGER DEFAULT 1,
            applied_at INTEGER DEFAULT 0,
            expires_at_unix INTEGER DEFAULT 0,
            data TEXT DEFAULT '{}',
            PRIMARY KEY (steamid, buff_id)
        );
        CREATE TABLE IF NOT EXISTS grid_telemetry (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            unix_ts INTEGER,
            category TEXT,
            action_type TEXT,
            actor_steamid TEXT,
            target_steamid TEXT,
            numeric_value REAL,
            metadata TEXT
        );
        CREATE TABLE IF NOT EXISTS grid_auctions (
            auction_id INTEGER PRIMARY KEY AUTOINCREMENT,
            seller_steamid TEXT,
            seller_name TEXT,
            item_id TEXT,
            item_type TEXT DEFAULT 'generic',
            amount INTEGER DEFAULT 1,
            item_data TEXT DEFAULT '{}',
            start_bid INTEGER DEFAULT 0,
            current_bid INTEGER DEFAULT 0,
            high_bidder_steamid TEXT,
            high_bidder_name TEXT,
            buyout_price INTEGER DEFAULT 0,
            deposit_amount INTEGER DEFAULT 0,
            status TEXT DEFAULT 'ACTIVE',
            duration_hours INTEGER DEFAULT 24,
            created_at_unix INTEGER,
            expires_at_unix INTEGER,
            closed_at_unix INTEGER
        );
        CREATE TABLE IF NOT EXISTS grid_auction_collection (
            collection_id INTEGER PRIMARY KEY AUTOINCREMENT,
            steamid TEXT,
            item_id TEXT,
            item_type TEXT DEFAULT 'generic',
            amount INTEGER DEFAULT 1,
            item_data TEXT DEFAULT '{}',
            source_reason TEXT,
            source_auction_id INTEGER,
            created_at_unix INTEGER,
            claimed INTEGER DEFAULT 0,
            claimed_at_unix INTEGER
        );
        CREATE TABLE IF NOT EXISTS grid_map_entities (
            spawn_id INTEGER PRIMARY KEY AUTOINCREMENT,
            map_name TEXT NOT NULL,
            class_name TEXT NOT NULL,
            pos_x REAL NOT NULL,
            pos_y REAL NOT NULL,
            pos_z REAL NOT NULL,
            ang_p REAL NOT NULL,
            ang_y REAL NOT NULL,
            ang_r REAL NOT NULL,
            placed_by TEXT NOT NULL,
            custom_data TEXT DEFAULT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    ]])

    GRID.Database.Connected = true
    hook.Run("GRID_DatabaseConnected")
end

-- ========================================================
-- 1. PLAYER PERSISTENCE OPERATIONS
-- ========================================================

function GRID.Database.LoadPlayer(ply, callback)
    local steamID = ply:SteamID()

    -- Analytical Read via v_player_profile view
    GRID.Database.QueryView("v_player_profile", "steamid = ? LIMIT 1", { steamID }, function(rows)
        local playerData = {}
        if rows and rows[1] then
            playerData = rows[1]
            local m = tonumber(playerData.money) or 0
            local b = tonumber(playerData.bank) or 0
            local r = tonumber(playerData.respect) or 0
            local g = playerData.gang or ""
            local j = (playerData.job and playerData.job ~= "") and playerData.job or "citizen"
            local lvl = math.max(1, tonumber(playerData.level) or 1)
            local xp = math.max(0, tonumber(playerData.xp) or 0)
            local stage = tonumber(playerData.onboarding_stage)
            if not stage then
                stage = (lvl >= 2) and 3 or 0
            end

            ply:SetNWInt("GRID_Money", m)
            ply:SetNWInt("GRID_Bank", b)
            ply:SetNWInt("GRID_Respect", r)
            ply:SetNWString("GRID_Gang", g)
            ply:SetNWString("GRID_Job", j)
            ply:SetNWInt("GRID_Level", lvl)
            ply:SetNWInt("GRID_XP", xp)
            ply:SetNWInt("GRID_OnboardingStage", stage)

            if playerData.gang_rank == "leader" then
                ply:SetNWBool("GRID_IsGangLeader", true)
            end
        else
            local initialMoney = 0
            local initialBank = 0
            local initialStage = 0
            playerData = {
                steamid = steamID,
                name = ply:Nick(),
                money = initialMoney,
                bank = initialBank,
                respect = 0,
                gang = "",
                job = "citizen",
                level = 1,
                xp = 0,
                onboarding_stage = initialStage,
                last_seen = os.time()
            }

            -- Insert new player via stored procedure
            GRID.Database.CallProcedure("grid_upsert_player", {
                steamID,
                ply:Nick(),
                initialMoney,
                0,
                "",
                "citizen",
                1,
                0,
                os.time(),
                initialStage,
                initialBank
            })

            ply:SetNWInt("GRID_Money", initialMoney)
            ply:SetNWInt("GRID_Bank", initialBank)
            ply:SetNWInt("GRID_Respect", 0)
            ply:SetNWString("GRID_Gang", "")
            ply:SetNWString("GRID_Job", "citizen")
            ply:SetNWInt("GRID_Level", 1)
            ply:SetNWInt("GRID_XP", 0)
            ply:SetNWInt("GRID_OnboardingStage", initialStage)
        end

        GRID.Database.Cache.Players[steamID] = playerData
        ply.GRID_DataLoaded = true

        -- Pre-populate inventory, bags, buffs into RAM cache
        GRID.Database.RefreshPlayerCache(steamID, function()
            if callback then callback(playerData) end
        end)
    end, function(err)
        ErrorNoHalt("[GRID DB] Failed to load player " .. steamID .. ": " .. tostring(err) .. "\n")
    end)
end

function GRID.Database.RefreshPlayerCache(steamID, callback)
    -- Load bags
    GRID.Database.QueryView("v_player_bags", "steamid = ? LIMIT 1", { steamID }, function(bagRows)
        if bagRows and bagRows[1] then
            GRID.Database.Cache.Bags[steamID] = bagRows[1]
        else
            GRID.Database.Cache.Bags[steamID] = { bag1 = "", bag2 = "", bag3 = "", bag4 = "" }
        end

        -- Load inventory
        GRID.Database.QueryView("v_player_inventory", "steamid = ? ORDER BY bag_index ASC, slot_index ASC", { steamID }, function(invRows)
            GRID.Database.Cache.Inventories[steamID] = invRows or {}

            -- Load buffs
            GRID.Database.QueryView("v_player_buffs", "steamid = ?", { steamID }, function(buffRows)
                GRID.Database.Cache.Buffs[steamID] = buffRows or {}
                if callback then callback() end
            end)
        end)
    end)
end

function GRID.Database.SavePlayer(ply)
    if not IsValid(ply) or not ply.GRID_DataLoaded then return end
    local steamID = ply:SteamID()
    local rawGang = ply.GetRawGang and ply:GetRawGang() or ply:GetGang()

    GRID.Database.CallProcedure("grid_upsert_player", {
        steamID,
        ply:Nick(),
        ply:GetMoney(),
        ply:GetNWInt("GRID_Respect", 0),
        rawGang,
        ply:GetJob(),
        ply:GetNWInt("GRID_Level", 1),
        ply:GetNWInt("GRID_XP", 0),
        os.time(),
        ply:GetNWInt("GRID_OnboardingStage", 0),
        ply:GetNWInt("GRID_Bank", 0)
    })

    if GRID.Database.Cache.Players[steamID] then
        local p = GRID.Database.Cache.Players[steamID]
        p.name = ply:Nick()
        p.money = ply:GetMoney()
        p.bank = ply:GetNWInt("GRID_Bank", 0)
        p.respect = ply:GetNWInt("GRID_Respect", 0)
        p.gang = rawGang
        p.job = ply:GetJob()
        p.level = ply:GetNWInt("GRID_Level", 1)
        p.xp = ply:GetNWInt("GRID_XP", 0)
        p.onboarding_stage = ply:GetNWInt("GRID_OnboardingStage", 0)
        p.last_seen = os.time()
    end
end

function GRID.Database.SavePlayerBank(ply, amount)
    if not IsValid(ply) or not ply.GRID_DataLoaded then return end
    local steamID = ply:SteamID()
    local bank = tonumber(amount) or 0

    GRID.Database.CallProcedure("grid_update_player_bank", {
        steamID,
        bank,
        os.time()
    })

    if GRID.Database.Cache.Players[steamID] then
        GRID.Database.Cache.Players[steamID].bank = bank
    end
end

function GRID.Database.TransferPersonalBank(ply, delta, callback)
    if not IsValid(ply) or not ply.GRID_DataLoaded then
        if callback then callback(false, "ERR_NOT_LOADED") end
        return
    end
    local steamID = ply:SteamID()
    local d = math.floor(tonumber(delta) or 0)
    if d == 0 then
        if callback then callback(false, "ERR_ZERO_DELTA") end
        return
    end

    GRID.Database.CallProcedure("grid_transfer_personal_bank", {
        steamID,
        d,
        os.time()
    }, function(rows)
        local r = rows and rows[1]
        local status = (r and r.status) or "SUCCESS"
        if status == "SUCCESS" then
            local newMoney = tonumber(r and r.money) or math.max(0, ply:GetMoney() - d)
            local newBank = tonumber(r and r.bank) or math.max(0, ply:GetBank() + d)
            if IsValid(ply) then
                ply:SetNWInt("GRID_Money", newMoney)
                ply:SetNWInt("GRID_Bank", newBank)
            end
            if GRID.Database.Cache.Players[steamID] then
                GRID.Database.Cache.Players[steamID].money = newMoney
                GRID.Database.Cache.Players[steamID].bank = newBank
            end
            if callback then callback(true, "SUCCESS", newMoney, newBank) end
        else
            if callback then callback(false, status) end
        end
    end, function(err)
        if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
    end)
end

function GRID.Database.SyncOnlinePlayerMoneyDelta(steamID, delta)
    if not steamID or steamID == "" then return end
    local d = tonumber(delta) or 0
    if d == 0 then return end
    if GRID.Database.Cache.Players[steamID] then
        local cur = tonumber(GRID.Database.Cache.Players[steamID].money) or 0
        GRID.Database.Cache.Players[steamID].money = math.max(0, cur + d)
    end
    for _, p in ipairs(player.GetAll()) do
        if p:SteamID() == steamID then
            local newAmt = math.max(0, p:GetMoney() + d)
            p:SetNWInt("GRID_Money", newAmt)
            return p
        end
    end
    return nil
end

function GRID.Database.SavePlayerOnboardingStage(ply, stage)
    if not IsValid(ply) or not ply.GRID_DataLoaded then return end
    local steamID = ply:SteamID()
    stage = math.Clamp(tonumber(stage) or 0, 0, 3)

    GRID.Database.CallProcedure("grid_update_onboarding_stage", {
        steamID,
        stage
    })

    if GRID.Database.Cache.Players[steamID] then
        GRID.Database.Cache.Players[steamID].onboarding_stage = stage
    end
end

function GRID.Database.SavePlayerLevelXP(ply, level, xp)
    if not IsValid(ply) or not ply.GRID_DataLoaded then return end
    local steamID = ply:SteamID()
    local lvl = math.max(1, tonumber(level) or 1)
    local exp = math.max(0, tonumber(xp) or 0)

    GRID.Database.CallProcedure("grid_update_player_level_xp", {
        steamID,
        lvl,
        exp,
        os.time()
    })

    if GRID.Database.Cache.Players[steamID] then
        GRID.Database.Cache.Players[steamID].level = lvl
        GRID.Database.Cache.Players[steamID].xp = exp
    end
end

function GRID.Database.SavePlayerMoney(ply, amount)
    if not IsValid(ply) or not ply.GRID_DataLoaded then return end
    local steamID = ply:SteamID()
    local money = tonumber(amount) or 0

    GRID.Database.CallProcedure("grid_update_player_money", {
        steamID,
        money,
        os.time()
    })

    if GRID.Database.Cache.Players[steamID] then
        GRID.Database.Cache.Players[steamID].money = money
    end
end

function GRID.Database.SavePlayerGang(ply, gangName)
    if not IsValid(ply) or not ply.GRID_DataLoaded then return end
    local steamID = ply:SteamID()
    gangName = gangName or ""

    GRID.Database.CallProcedure("grid_update_player_gang", {
        steamID,
        gangName,
        os.time()
    })

    if GRID.Database.Cache.Players[steamID] then
        GRID.Database.Cache.Players[steamID].gang = gangName
    end
end

function GRID.Database.SavePlayerJob(ply, jobId)
    if not IsValid(ply) or not ply.GRID_DataLoaded then return end
    local steamID = ply:SteamID()
    jobId = jobId or "citizen"

    GRID.Database.CallProcedure("grid_update_player_job", {
        steamID,
        jobId,
        os.time()
    })

    if GRID.Database.Cache.Players[steamID] then
        GRID.Database.Cache.Players[steamID].job = jobId
    end
end

-- ========================================================
-- 2. GANG & MEMBER ROSTER PERSISTENCE
-- ========================================================

function GRID.Database.CreateGang(gangName, leaderSteamID)
    GRID.Database.CallProcedure("grid_create_gang", {
        gangName,
        leaderSteamID,
        os.time()
    })

    GRID.Database.Cache.Gangs[gangName] = {
        name = gangName,
        leader_steamid = leaderSteamID,
        bank = 0,
        respect = 0,
        created_at = os.time()
    }
    GRID.Database.Cache.GangMembers[leaderSteamID] = {
        steamid = leaderSteamID,
        gang = gangName,
        rank = "leader",
        joined_at = os.time()
    }
    return true
end

function GRID.Database.GetGang(gangName)
    if GRID.Database.Cache.Gangs[gangName] then
        return GRID.Database.Cache.Gangs[gangName]
    end

    if GRID.Database.UseSQLiteFallback then
        local rows = sql.Query(string.format("SELECT * FROM grid_gangs WHERE name = %s LIMIT 1;", sql.SQLStr(gangName)))
        if rows and rows[1] then
            GRID.Database.Cache.Gangs[gangName] = rows[1]
            return rows[1]
        end
    end
    return nil
end

function GRID.Database.AddGangMember(steamID, gangName, rank)
    rank = rank or "member"
    GRID.Database.CallProcedure("grid_add_gang_member", {
        steamID,
        gangName,
        rank,
        os.time()
    })

    GRID.Database.Cache.GangMembers[steamID] = {
        steamid = steamID,
        gang = gangName,
        rank = rank,
        joined_at = os.time()
    }
    if GRID.Database.Cache.Players[steamID] then
        GRID.Database.Cache.Players[steamID].gang = gangName
    end
    return true
end

function GRID.Database.RemoveGangMember(steamID)
    GRID.Database.CallProcedure("grid_remove_gang_member", { steamID })
    GRID.Database.Cache.GangMembers[steamID] = nil
    if GRID.Database.Cache.Players[steamID] then
        GRID.Database.Cache.Players[steamID].gang = ""
    end
    return true
end

function GRID.Database.GetGangMember(steamID)
    if GRID.Database.Cache.GangMembers[steamID] then
        return GRID.Database.Cache.GangMembers[steamID]
    end

    if GRID.Database.UseSQLiteFallback then
        local rows = sql.Query(string.format("SELECT * FROM grid_gang_members WHERE steamid = %s LIMIT 1;", sql.SQLStr(steamID)))
        if rows and rows[1] then
            GRID.Database.Cache.GangMembers[steamID] = rows[1]
            return rows[1]
        end
    end
    return nil
end

function GRID.Database.GetGangMembers(gangName)
    if GRID.Database.UseSQLiteFallback then
        local q = string.format([[
            SELECT m.steamid, m.rank, m.joined_at, p.name, p.money, p.last_seen
            FROM grid_gang_members m
            LEFT JOIN grid_players p ON m.steamid = p.steamid
            WHERE m.gang = %s
            ORDER BY CASE m.rank WHEN 'leader' THEN 1 WHEN 'officer' THEN 2 ELSE 3 END, m.joined_at ASC;
        ]], sql.SQLStr(gangName))
        return sql.Query(q) or {}
    end

    local members = {}
    for sid, m in pairs(GRID.Database.Cache.GangMembers) do
        if m.gang == gangName then
            local plyData = GRID.Database.Cache.Players[sid] or {}
            table.insert(members, {
                steamid = sid,
                rank = m.rank,
                joined_at = m.joined_at,
                name = plyData.name or "Unknown",
                money = plyData.money or 0,
                last_seen = plyData.last_seen or os.time()
            })
        end
    end
    return members
end

function GRID.Database.AddGangBank(gangName, amount)
    local amt = tonumber(amount) or 0
    GRID.Database.CallProcedure("grid_add_gang_bank", { gangName, amt })
    if GRID.Database.Cache.Gangs[gangName] then
        local cur = tonumber(GRID.Database.Cache.Gangs[gangName].bank) or 0
        GRID.Database.Cache.Gangs[gangName].bank = math.max(0, cur + amt)
    end
end

function GRID.Database.TransferGangVault(steamID, gangName, delta)
    local d = tonumber(delta) or 0
    if d == 0 then return false end
    GRID.Database.CallProcedure("grid_transfer_gang_vault", {
        steamID,
        gangName,
        d,
        os.time()
    })
    if GRID.Database.Cache.Gangs[gangName] then
        local cur = tonumber(GRID.Database.Cache.Gangs[gangName].bank) or 0
        GRID.Database.Cache.Gangs[gangName].bank = math.max(0, cur + d)
    end
    GRID.Database.SyncOnlinePlayerMoneyDelta(steamID, -d)
    return true
end

function GRID.Database.DisbandGang(gangName)
    GRID.Database.CallProcedure("grid_disband_gang", { gangName })
    GRID.Database.Cache.Gangs[gangName] = nil
    for sid, m in pairs(GRID.Database.Cache.GangMembers) do
        if m.gang == gangName then
            GRID.Database.Cache.GangMembers[sid] = nil
            if GRID.Database.Cache.Players[sid] then
                GRID.Database.Cache.Players[sid].gang = ""
            end
        end
    end
    return true
end

function GRID.Database.GetAllGangs()
    if GRID.Database.UseSQLiteFallback then
        return sql.Query("SELECT * FROM grid_gangs ORDER BY respect DESC, bank DESC;") or {}
    end

    local list = {}
    for _, g in pairs(GRID.Database.Cache.Gangs) do
        table.insert(list, g)
    end
    table.sort(list, function(a, b)
        if (a.respect or 0) == (b.respect or 0) then
            return (a.bank or 0) > (b.bank or 0)
        end
        return (a.respect or 0) > (b.respect or 0)
    end)
    return list
end

-- ========================================================
-- 3. PLAYER INVENTORY & BAG STORAGE (RAM Cache + Stored Procedures)
-- ========================================================

function GRID.Database.GetInventory(steamID)
    return GRID.Database.Cache.Inventories[steamID] or {}
end

function GRID.Database.GetInventorySlot(steamID, bagIndex, slotIndex)
    local inv = GRID.Database.Cache.Inventories[steamID]
    if not inv then return nil end
    bagIndex = tonumber(bagIndex) or 0
    slotIndex = tonumber(slotIndex) or 1

    for _, it in ipairs(inv) do
        if (tonumber(it.bag_index) or 0) == bagIndex and (tonumber(it.slot_index) or 1) == slotIndex then
            return it
        end
    end
    return nil
end

function GRID.Database.GetPlayerBags(steamID)
    if GRID.Database.Cache.Bags[steamID] then
        return GRID.Database.Cache.Bags[steamID]
    end
    return { bag1 = "", bag2 = "", bag3 = "", bag4 = "" }
end

function GRID.Database.SetPlayerBags(steamID, bag1, bag2, bag3, bag4)
    local bags = {
        steamid = steamID,
        bag1 = bag1 or "",
        bag2 = bag2 or "",
        bag3 = bag3 or "",
        bag4 = bag4 or ""
    }
    GRID.Database.Cache.Bags[steamID] = bags

    GRID.Database.CallProcedure("grid_set_player_bags", {
        steamID,
        bags.bag1,
        bags.bag2,
        bags.bag3,
        bags.bag4
    })
end

function GRID.Database.AddInventoryItem(steamID, itemId, itemType, amount, itemData, targetBag, targetSlot)
    amount = tonumber(amount) or 1
    local iType = itemType or "generic"
    local iData = type(itemData) == "table" and util.TableToJSON(itemData) or (itemData or "{}")

    local inv = GRID.Database.Cache.Inventories[steamID] or {}

    -- 1. If explicit target slot provided
    if targetBag and targetSlot then
        local slotOccupant = GRID.Database.GetInventorySlot(steamID, targetBag, targetSlot)
        if not slotOccupant then
            local newEntry = {
                steamid = steamID,
                bag_index = targetBag,
                slot_index = targetSlot,
                item_id = itemId,
                item_type = iType,
                amount = amount,
                item_data = iData
            }
            table.insert(inv, newEntry)
            GRID.Database.Cache.Inventories[steamID] = inv

            GRID.Database.CallProcedure("grid_set_inventory_slot", {
                steamID,
                targetBag,
                targetSlot,
                itemId,
                iType,
                amount,
                iData
            })
            return true
        end
    end

    -- 2. Check identical stack (weapons never stack so durability/clip state stays unique per slot)
    if iType ~= "weapon" then
        for _, it in ipairs(inv) do
            if it.item_id == itemId and it.item_type ~= "weapon" then
                it.amount = (tonumber(it.amount) or 1) + amount
                GRID.Database.CallProcedure("grid_set_inventory_slot", {
                    steamID,
                    it.bag_index,
                    it.slot_index,
                    it.item_id,
                    it.item_type,
                    it.amount,
                    it.item_data
                })
                return true
            end
        end
    end

    -- 3. Find first open slot
    local occupied = {}
    for _, it in ipairs(inv) do
        local b = tonumber(it.bag_index) or 0
        local s = tonumber(it.slot_index) or 1
        occupied[b .. "_" .. s] = true
    end

    local playerBags = GRID.Database.GetPlayerBags(steamID)
    local getCap = (GRID.Inventory and GRID.Inventory.GetBagCapacity) or function() return 0 end
    local bagCapacities = {
        [0] = 16,
        [1] = getCap(playerBags.bag1),
        [2] = getCap(playerBags.bag2),
        [3] = getCap(playerBags.bag3),
        [4] = getCap(playerBags.bag4)
    }

    local freeBag, freeSlot = nil, nil
    for b = 0, 4 do
        local cap = bagCapacities[b] or 0
        if cap > 0 then
            for s = 1, cap do
                if not occupied[b .. "_" .. s] then
                    freeBag = b
                    freeSlot = s
                    break
                end
            end
        end
        if freeBag then break end
    end

    if freeBag and freeSlot then
        local newEntry = {
            steamid = steamID,
            bag_index = freeBag,
            slot_index = freeSlot,
            item_id = itemId,
            item_type = iType,
            amount = amount,
            item_data = iData
        }
        table.insert(inv, newEntry)
        GRID.Database.Cache.Inventories[steamID] = inv

        GRID.Database.CallProcedure("grid_set_inventory_slot", {
            steamID,
            freeBag,
            freeSlot,
            itemId,
            iType,
            amount,
            iData
        })
        return true
    end

    return false
end

function GRID.Database.FindOpenSlot(steamID)
    local inv = GRID.Database.Cache.Inventories[steamID] or {}
    local occupied = {}
    for _, it in ipairs(inv) do
        local b = tonumber(it.bag_index) or 0
        local s = tonumber(it.slot_index) or 1
        occupied[b .. "_" .. s] = true
    end

    local playerBags = GRID.Database.GetPlayerBags(steamID)
    local getCap = (GRID.Inventory and GRID.Inventory.GetBagCapacity) or function() return 0 end
    local bagCapacities = {
        [0] = 16,
        [1] = getCap(playerBags.bag1),
        [2] = getCap(playerBags.bag2),
        [3] = getCap(playerBags.bag3),
        [4] = getCap(playerBags.bag4)
    }

    for b = 0, 4 do
        local cap = bagCapacities[b] or 0
        if cap > 0 then
            for s = 1, cap do
                if not occupied[b .. "_" .. s] then
                    return b, s
                end
            end
        end
    end
    return nil, nil
end

function GRID.Database.MoveInventorySlot(steamID, fromBag, fromSlot, toBag, toSlot)
    fromBag = tonumber(fromBag) or 0
    fromSlot = tonumber(fromSlot) or 1
    toBag = tonumber(toBag) or 0
    toSlot = tonumber(toSlot) or 1

    local inv = GRID.Database.Cache.Inventories[steamID] or {}
    local srcIdx, dstIdx = nil, nil

    for idx, it in ipairs(inv) do
        if (tonumber(it.bag_index) or 0) == fromBag and (tonumber(it.slot_index) or 1) == fromSlot then
            srcIdx = idx
        elseif (tonumber(it.bag_index) or 0) == toBag and (tonumber(it.slot_index) or 1) == toSlot then
            dstIdx = idx
        end
    end

    if not srcIdx then return false end
    local srcItem = inv[srcIdx]

    if not dstIdx then
        -- Empty destination slot
        srcItem.bag_index = toBag
        srcItem.slot_index = toSlot
        GRID.Database.CallProcedure("grid_move_inventory_slot", { steamID, fromBag, fromSlot, toBag, toSlot })
        return true
    else
        local dstItem = inv[dstIdx]
        if srcItem.item_id == dstItem.item_id and srcItem.item_type ~= "weapon" and dstItem.item_type ~= "weapon" then
            -- Stack non-weapon items
            dstItem.amount = (tonumber(dstItem.amount) or 1) + (tonumber(srcItem.amount) or 1)
            table.remove(inv, srcIdx)
            GRID.Database.CallProcedure("grid_move_inventory_slot", { steamID, fromBag, fromSlot, toBag, toSlot })
            return true
        else
            -- Swap
            srcItem.bag_index = toBag
            srcItem.slot_index = toSlot
            dstItem.bag_index = fromBag
            dstItem.slot_index = fromSlot
            GRID.Database.CallProcedure("grid_move_inventory_slot", { steamID, fromBag, fromSlot, toBag, toSlot })
            return true
        end
    end
end

function GRID.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, amount)
    amount = tonumber(amount) or 1
    bagIndex = tonumber(bagIndex) or 0
    slotIndex = tonumber(slotIndex) or 1

    local inv = GRID.Database.Cache.Inventories[steamID] or {}
    for idx, it in ipairs(inv) do
        if (tonumber(it.bag_index) or 0) == bagIndex and (tonumber(it.slot_index) or 1) == slotIndex then
            local curAmount = tonumber(it.amount) or 1
            if curAmount <= amount then
                table.remove(inv, idx)
                GRID.Database.CallProcedure("grid_delete_inventory_slot", { steamID, bagIndex, slotIndex })
            else
                it.amount = curAmount - amount
                GRID.Database.CallProcedure("grid_set_inventory_slot", {
                    steamID,
                    bagIndex,
                    slotIndex,
                    it.item_id,
                    it.item_type,
                    it.amount,
                    it.item_data
                })
            end
            return true
        end
    end
    return false
end

function GRID.Database.RemoveInventoryItem(steamID, itemId, amount)
    local needed = tonumber(amount) or 1
    if not GRID.Database.HasInventoryItem(steamID, itemId, needed) then
        return false
    end

    local inv = GRID.Database.Cache.Inventories[steamID] or {}
    for idx = #inv, 1, -1 do
        local it = inv[idx]
        if it and it.item_id == itemId and needed > 0 then
            local curAmount = tonumber(it.amount) or 1
            if curAmount <= needed then
                local b = it.bag_index
                local s = it.slot_index
                needed = needed - curAmount
                table.remove(inv, idx)
                GRID.Database.CallProcedure("grid_delete_inventory_slot", { steamID, b, s })
            else
                it.amount = curAmount - needed
                needed = 0
                GRID.Database.CallProcedure("grid_set_inventory_slot", {
                    steamID,
                    it.bag_index,
                    it.slot_index,
                    it.item_id,
                    it.item_type,
                    it.amount,
                    it.item_data
                })
            end
            if needed <= 0 then
                break
            end
        end
    end
    return needed <= 0
end

function GRID.Database.HasInventoryItem(steamID, itemId, amount)
    amount = tonumber(amount) or 1
    local inv = GRID.Database.Cache.Inventories[steamID] or {}
    local total = 0
    for _, it in ipairs(inv) do
        if it.item_id == itemId then
            total = total + (tonumber(it.amount) or 0)
            if total >= amount then
                return true
            end
        end
    end
    return false
end

-- ========================================================
-- 4. TURF ZONES PERSISTENCE (PER-MAP)
-- ========================================================

function GRID.Database.SaveTurfZones(mapName, zonesTable)
    local mapKey = string.lower(mapName)
    GRID.Database.CallProcedure("grid_clear_map_turfs", { mapKey })

    for id, zone in pairs(zonesTable) do
        local idNum = tonumber(id) or 1
        local name = zone.name or ("Turf #" .. idNum)
        local px = zone.pos and zone.pos.x or 0
        local py = zone.pos and zone.pos.y or 0
        local pz = zone.pos and zone.pos.z or 0
        local radius = tonumber(zone.radius) or 450
        local owner = zone.owner or "neutral"
        local taxRate = tonumber(zone.tax_rate) or 10

        GRID.Database.CallProcedure("grid_save_map_turf", {
            mapKey,
            idNum,
            name,
            px,
            py,
            pz,
            radius,
            owner,
            taxRate
        })
    end
    GRID.Database.Cache.Turfs[mapKey] = zonesTable
    return true
end

function GRID.Database.LoadTurfZones(mapName, callback)
    local mapKey = string.lower(mapName)
    if GRID.Database.Cache.Turfs[mapKey] then
        if callback then callback(GRID.Database.Cache.Turfs[mapKey]) end
        return GRID.Database.Cache.Turfs[mapKey]
    end

    if GRID.Database.UseSQLiteFallback then
        local rows = sql.Query(string.format("SELECT * FROM grid_turfs WHERE map = %s ORDER BY turf_id ASC;", sql.SQLStr(mapKey)))
        if rows and #rows > 0 then
            local zones = {}
            for _, row in ipairs(rows) do
                local id = tonumber(row.turf_id)
                zones[id] = {
                    id = id,
                    name = row.name,
                    pos = Vector(tonumber(row.pos_x), tonumber(row.pos_y), tonumber(row.pos_z)),
                    radius = tonumber(row.radius) or 450,
                    owner = row.owner or "neutral",
                    tax_rate = tonumber(row.tax_rate) or 10,
                    progress = 100
                }
            end
            GRID.Database.Cache.Turfs[mapKey] = zones
            if callback then callback(zones) end
            return zones
        end
        if callback then callback(nil) end
        return nil
    end

    GRID.Database.QueryView("v_map_turfs", "map = ? ORDER BY turf_id ASC", { mapKey }, function(rows)
        if rows and #rows > 0 then
            local zones = {}
            for _, row in ipairs(rows) do
                local id = tonumber(row.turf_id)
                zones[id] = {
                    id = id,
                    name = row.name,
                    pos = Vector(tonumber(row.pos_x), tonumber(row.pos_y), tonumber(row.pos_z)),
                    radius = tonumber(row.radius) or 450,
                    owner = row.owner or "neutral",
                    tax_rate = tonumber(row.tax_rate) or 10,
                    progress = 100
                }
            end
            GRID.Database.Cache.Turfs[mapKey] = zones
            if callback then callback(zones) end
        else
            if callback then callback(nil) end
        end
    end)
    return nil
end

function GRID.Database.DeleteTurfZone(mapName, turfId)
    local mapKey = string.lower(mapName)
    GRID.Database.CallProcedure("grid_delete_map_turf", { mapKey, tonumber(turfId) or 1 })
    if GRID.Database.Cache.Turfs[mapKey] then
        GRID.Database.Cache.Turfs[mapKey][turfId] = nil
    end
end

function GRID.Database.SetTurfTax(mapName, turfId, taxRate)
    local mapKey = string.lower(mapName)
    local rate = tonumber(taxRate) or 10
    GRID.Database.CallProcedure("grid_set_turf_tax", { mapKey, tonumber(turfId) or 1, rate })
    if GRID.Database.Cache.Turfs[mapKey] and GRID.Database.Cache.Turfs[mapKey][turfId] then
        GRID.Database.Cache.Turfs[mapKey][turfId].tax_rate = rate
    end
end

-- ========================================================
-- 5. KEY-VALUE SETTINGS PERSISTENCE
-- ========================================================

function GRID.Database.SetSetting(key, val)
    GRID.Database.Cache.Settings[key] = tostring(val)
    GRID.Database.CallProcedure("grid_set_setting", { key, tostring(val) })
end

function GRID.Database.GetSetting(key, defaultVal)
    if GRID.Database.Cache.Settings[key] ~= nil then
        return GRID.Database.Cache.Settings[key]
    end
    if GRID.Database.UseSQLiteFallback then
        local rows = sql.Query(string.format("SELECT val FROM grid_settings WHERE key = %s LIMIT 1;", sql.SQLStr(key)))
        if rows and rows[1] then
            GRID.Database.Cache.Settings[key] = rows[1].val
            return rows[1].val
        end
    end
    return defaultVal
end

-- ========================================================
-- 6. PLAYER BUFFS & DEBUFFS PERSISTENCE
-- ========================================================

function GRID.Database.GetPlayerBuffs(steamID)
    local cached = GRID.Database.Cache.Buffs[steamID]
    if not cached then return {} end
    if cached[1] ~= nil then return cached end
    local list = {}
    for _, b in pairs(cached) do
        table.insert(list, b)
    end
    return list
end

function GRID.Database.SavePlayerBuff(steamID, buffId, duration, remaining, stacks, appliedAt, expiresAtUnix, dataStr)
    GRID.Database.Cache.Buffs[steamID] = GRID.Database.Cache.Buffs[steamID] or {}
    local entry = {
        buff_id = buffId,
        duration = tonumber(duration) or 0,
        remaining = tonumber(remaining) or 0,
        stacks = tonumber(stacks) or 1,
        applied_at = tonumber(appliedAt) or os.time(),
        expires_at_unix = tonumber(expiresAtUnix) or 0,
        data = tostring(dataStr or "{}")
    }
    if GRID.Database.Cache.Buffs[steamID][1] ~= nil then
        local found = false
        for i, b in ipairs(GRID.Database.Cache.Buffs[steamID]) do
            if b.buff_id == buffId then
                GRID.Database.Cache.Buffs[steamID][i] = entry
                found = true
                break
            end
        end
        if not found then
            table.insert(GRID.Database.Cache.Buffs[steamID], entry)
        end
    else
        GRID.Database.Cache.Buffs[steamID][buffId] = entry
    end

    GRID.Database.CallProcedure("grid_save_player_buff", {
        steamID,
        buffId,
        tonumber(duration) or 0,
        tonumber(remaining) or 0,
        tonumber(stacks) or 1,
        tonumber(appliedAt) or os.time(),
        tonumber(expiresAtUnix) or 0,
        tostring(dataStr or "{}")
    })
    return true
end

function GRID.Database.DeletePlayerBuff(steamID, buffId)
    local cached = GRID.Database.Cache.Buffs[steamID]
    if cached then
        if cached[1] ~= nil then
            for i = #cached, 1, -1 do
                if cached[i].buff_id == buffId then
                    table.remove(cached, i)
                end
            end
        else
            cached[buffId] = nil
        end
    end
    GRID.Database.CallProcedure("grid_delete_player_buff", { steamID, buffId })
end

function GRID.Database.ClearPlayerBuffs(steamID)
    GRID.Database.Cache.Buffs[steamID] = {}
    GRID.Database.CallProcedure("grid_clear_player_buffs", { steamID })
end

-- ========================================================
-- 7. ATOMIC PRINTER TAXED COLLECTION
-- ========================================================

function GRID.Database.CollectPrinterTaxed(steamID, gangName, payout, tax)
    local pAmt = tonumber(payout) or 0
    local tAmt = tonumber(tax) or 0
    local gName = gangName or ""
    GRID.Database.CallProcedure("grid_collect_printer_taxed", {
        steamID,
        gName,
        pAmt,
        tAmt,
        os.time()
    })
    if tAmt > 0 and gName ~= "" and gName ~= "neutral" and gName ~= "Police" and GRID.Database.Cache.Gangs[gName] then
        local cur = tonumber(GRID.Database.Cache.Gangs[gName].bank) or 0
        GRID.Database.Cache.Gangs[gName].bank = math.max(0, cur + tAmt)
    end
    GRID.Database.SyncOnlinePlayerMoneyDelta(steamID, pAmt)
end

-- ========================================================
-- 8. AUCTION HOUSE PERSISTENCE & ANALYTICS
-- ========================================================

function GRID.Database.GetActiveAuctions(callback)
    local now = os.time()
    GRID.Database.QueryView("v_auctions", "status = 'ACTIVE' AND expires_at_unix > ? ORDER BY created_at_unix DESC", { now }, function(rows)
        if callback then callback(rows or {}) end
    end, function(err)
        ErrorNoHalt(string.format("[GRID AUCTION DB ERROR] GetActiveAuctions failed: %s\n", tostring(err)))
        if callback then callback({}) end
    end)
end

function GRID.Database.GetPlayerAuctions(steamID, callback)
    GRID.Database.QueryView("v_auctions", "seller_steamid = ? ORDER BY created_at_unix DESC LIMIT 50", { steamID }, function(rows)
        if callback then callback(rows or {}) end
    end, function(err)
        ErrorNoHalt(string.format("[GRID AUCTION DB ERROR] GetPlayerAuctions failed: %s\n", tostring(err)))
        if callback then callback({}) end
    end)
end

function GRID.Database.GetPlayerCollection(steamID, callback)
    GRID.Database.QueryView("v_auction_collection", "steamid = ? AND claimed = 0 ORDER BY created_at_unix DESC", { steamID }, function(rows)
        if callback then callback(rows or {}) end
    end, function(err)
        ErrorNoHalt(string.format("[GRID AUCTION DB ERROR] GetPlayerCollection failed: %s\n", tostring(err)))
        if callback then callback({}) end
    end)
end

function GRID.Database.GetAuctionMetrics(callback)
    if GRID.Database.UseSQLiteFallback then
        local now = os.time()
        local weekAgo = now - 604800
        local dayAgo = now - 86400
        local q = string.format([[
            SELECT 
                a.item_id,
                MIN(CASE WHEN a.status = 'ACTIVE' AND a.buyout_price > 0 THEN a.buyout_price ELSE NULL END) AS min_active_buyout,
                COUNT(CASE WHEN a.status = 'ACTIVE' THEN 1 ELSE NULL END) AS active_listings_count,
                ROUND(AVG(CASE WHEN a.status = 'SOLD' AND a.closed_at_unix >= %d THEN MAX(a.current_bid, a.buyout_price) ELSE NULL END)) AS avg_sale_price_7d,
                COALESCE(SUM(CASE WHEN a.status = 'SOLD' AND a.closed_at_unix >= %d THEN a.amount ELSE 0 END), 0) AS sold_volume_24h
            FROM grid_auctions a
            GROUP BY a.item_id;
        ]], weekAgo, dayAgo)

        GRID.Database.Execute(q, function(rows)
            local metricsMap = {}
            for _, r in ipairs(rows or {}) do
                metricsMap[r.item_id] = {
                    min_buyout = tonumber(r.min_active_buyout) or 0,
                    active_count = tonumber(r.active_listings_count) or 0,
                    avg_7d = tonumber(r.avg_sale_price_7d) or 0,
                    sold_24h = tonumber(r.sold_volume_24h) or 0
                }
            end
            if callback then callback(metricsMap) end
        end, function(err)
            ErrorNoHalt(string.format("[GRID AUCTION DB ERROR] GetAuctionMetrics fallback failed: %s\n", tostring(err)))
            if callback then callback({}) end
        end)
        return
    end

    GRID.Database.QueryView("v_auction_metrics", nil, nil, function(rows)
        local metricsMap = {}
        for _, r in ipairs(rows or {}) do
            metricsMap[r.item_id] = {
                min_buyout = tonumber(r.min_active_buyout) or 0,
                active_count = tonumber(r.active_listings_count) or 0,
                avg_7d = tonumber(r.avg_sale_price_7d) or 0,
                sold_24h = tonumber(r.sold_volume_24h) or 0
            }
        end
        if callback then callback(metricsMap) end
    end, function(err)
        ErrorNoHalt(string.format("[GRID AUCTION DB ERROR] GetAuctionMetrics failed: %s\n", tostring(err)))
        if callback then callback({}) end
    end)
end

function GRID.Database.CreateAuction(sellerSteamID, sellerName, bagIndex, slotIndex, startBid, buyoutPrice, durationHours, depositAmount, callback)
    local now = os.time()
    bagIndex = tonumber(bagIndex) or 0
    slotIndex = tonumber(slotIndex) or 1
    startBid = tonumber(startBid) or 10
    buyoutPrice = tonumber(buyoutPrice) or 0
    durationHours = tonumber(durationHours) or 24
    depositAmount = tonumber(depositAmount) or 0

    if not GRID.Database.UseSQLiteFallback and not GRID.Database.UseDirectMariaDBSQL then
        GRID.Database.CallProcedure("grid_auction_create", {
            sellerSteamID, sellerName, bagIndex, slotIndex, startBid, buyoutPrice, durationHours, depositAmount, now
        }, function(rows)
            local r = rows and rows[1]
            local status = (r and r.status) or "ERROR_SQL"
            if status == "SUCCESS" then
                local newAucID = tonumber(r and r.auction_id) or 0
                -- Remove slot from RAM cache (DB row was deleted atomically inside grid_auction_create)
                local inv = GRID.Database.Cache.Inventories[sellerSteamID] or {}
                for idx, it in ipairs(inv) do
                    if (tonumber(it.bag_index) or 0) == bagIndex and (tonumber(it.slot_index) or 1) == slotIndex then
                        table.remove(inv, idx)
                        break
                    end
                end
                GRID.Database.SyncOnlinePlayerMoneyDelta(sellerSteamID, -depositAmount)
                if callback then callback(true, "SUCCESS", newAucID) end
            else
                if callback then callback(false, status) end
            end
        end, function(err)
            if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
        end)
        return
    end

    local checkQ = GRID.Database.FormatQuery("SELECT COUNT(*) AS cnt FROM grid_auctions WHERE seller_steamid = ? AND status = 'ACTIVE';", { sellerSteamID })
    GRID.Database.Execute(checkQ, function(cRows)
        local cnt = tonumber(cRows and cRows[1] and cRows[1].cnt) or 0
        if cnt >= 10 then
            if callback then callback(false, "ERR_MAX_LISTINGS") end
            return
        end

        local item = GRID.Database.GetInventorySlot(sellerSteamID, bagIndex, slotIndex)
        if not item then
            if callback then callback(false, "ERR_ITEM_NOT_FOUND") end
            return
        end

        local plyQ = GRID.Database.FormatQuery("SELECT money FROM grid_players WHERE steamid = ?;", { sellerSteamID })
        GRID.Database.Execute(plyQ, function(pRows)
            local curMoney = tonumber(pRows and pRows[1] and pRows[1].money) or 0
            if curMoney < depositAmount then
                if callback then callback(false, "ERR_INSUFFICIENT_FUNDS") end
                return
            end

            local itemId = item.item_id
            local itemType = item.item_type or "generic"
            local amount = tonumber(item.amount) or 1
            local itemData = type(item.item_data) == "table" and util.TableToJSON(item.item_data) or (item.item_data or "{}")

            -- 1. Remove from player's inventory cache & DB
            GRID.Database.RemoveInventoryItemAtSlot(sellerSteamID, bagIndex, slotIndex, amount)

            -- 2. Deduct deposit from seller in DB & sync online player
            GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET money = money - ? WHERE steamid = ?;", { depositAmount, sellerSteamID }))
            GRID.Database.SyncOnlinePlayerMoneyDelta(sellerSteamID, -depositAmount)

            -- 3. Insert into grid_auctions
            local insQ = GRID.Database.FormatQuery([[INSERT INTO grid_auctions (
                seller_steamid, seller_name, item_id, item_type, amount, item_data,
                start_bid, current_bid, buyout_price, deposit_amount, status,
                duration_hours, created_at_unix, expires_at_unix
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, 'ACTIVE', ?, ?, ?);]], {
                sellerSteamID, sellerName, itemId, itemType, amount, itemData,
                startBid, buyoutPrice, depositAmount, durationHours, now, now + (durationHours * 3600)
            })

            GRID.Database.Execute(insQ, function(insRes)
                local newAucID = insRes and (insRes.lastid or (insRes[1] and insRes[1].id)) or 0

                -- 4. Log telemetry via procedure wrapper
                local meta = util.TableToJSON({
                    item_id = itemId,
                    amount = amount,
                    buyout = buyoutPrice,
                    start_bid = startBid,
                    duration = durationHours,
                    auction_id = newAucID
                })
                GRID.Database.CallProcedure("grid_log_telemetry", {
                    "ECONOMY", "AUCTION_LIST", sellerSteamID, "", depositAmount, meta
                })

                if callback then callback(true, "SUCCESS", newAucID) end
            end, function(err)
                if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
            end)
        end, function(err)
            if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
        end)
    end, function(err)
        if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
    end)
end

function GRID.Database.BidAuction(auctionID, bidderSteamID, bidderName, bidAmount, callback)
    local now = os.time()
    auctionID = tonumber(auctionID) or 0
    bidAmount = tonumber(bidAmount) or 0

    if not GRID.Database.UseSQLiteFallback and not GRID.Database.UseDirectMariaDBSQL then
        GRID.Database.CallProcedure("grid_auction_bid", {
            auctionID, bidderSteamID, bidderName, bidAmount, now
        }, function(rows)
            local r = rows and rows[1]
            local status = (r and r.status) or "ERROR_SQL"
            if status == "SUCCESS" then
                local prevBidder = r and r.prev_bidder or ""
                local prevBid = tonumber(r and r.prev_bid) or 0
                if prevBidder ~= "" and prevBid > 0 then
                    local pPrev = GRID.Database.SyncOnlinePlayerMoneyDelta(prevBidder, prevBid)
                    if IsValid(pPrev) then
                        GRID.Notify(pPrev, string.format("You were outbid on auction #%d! $%s was refunded to your wallet.", auctionID, string.Comma(prevBid)), NOTIFY_GENERIC)
                    end
                end
                GRID.Database.SyncOnlinePlayerMoneyDelta(bidderSteamID, -bidAmount)
                if callback then callback(true, "SUCCESS") end
            else
                if callback then callback(false, status) end
            end
        end, function(err)
            if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
        end)
        return
    end

    local aucQ = GRID.Database.FormatQuery("SELECT * FROM grid_auctions WHERE auction_id = ?;", { auctionID })
    GRID.Database.Execute(aucQ, function(aRows)
        local auc = aRows and aRows[1]
        if not auc or auc.status ~= "ACTIVE" then
            if callback then callback(false, "ERR_NOT_ACTIVE") end
            return
        end
        if tonumber(auc.expires_at_unix) <= now then
            if callback then callback(false, "ERR_EXPIRED") end
            return
        end
        if auc.seller_steamid == bidderSteamID then
            if callback then callback(false, "ERR_SELF_BID") end
            return
        end
        local curBid = tonumber(auc.current_bid) or 0
        local startBid = tonumber(auc.start_bid) or 0
        if (curBid == 0 and bidAmount < startBid) or (curBid > 0 and bidAmount <= curBid) then
            if callback then callback(false, "ERR_BID_TOO_LOW") end
            return
        end

        local plyQ = GRID.Database.FormatQuery("SELECT money FROM grid_players WHERE steamid = ?;", { bidderSteamID })
        GRID.Database.Execute(plyQ, function(pRows)
            local curMoney = tonumber(pRows and pRows[1] and pRows[1].money) or 0
            if curMoney < bidAmount then
                if callback then callback(false, "ERR_INSUFFICIENT_FUNDS") end
                return
            end

            -- Refund previous high bidder if any
            if auc.high_bidder_steamid and auc.high_bidder_steamid ~= "" and curBid > 0 then
                GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET money = money + ? WHERE steamid = ?;", { curBid, auc.high_bidder_steamid }))
                local pPrev = GRID.Database.SyncOnlinePlayerMoneyDelta(auc.high_bidder_steamid, curBid)
                if IsValid(pPrev) then
                    GRID.Notify(pPrev, string.format("You were outbid on auction #%d! $%s was refunded to your wallet.", auctionID, string.Comma(curBid)), NOTIFY_GENERIC)
                end
            end

            -- Deduct new bid from bidder
            GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET money = money - ? WHERE steamid = ?;", { bidAmount, bidderSteamID }))
            GRID.Database.SyncOnlinePlayerMoneyDelta(bidderSteamID, -bidAmount)

            -- Update auction
            GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_auctions SET current_bid = ?, high_bidder_steamid = ?, high_bidder_name = ? WHERE auction_id = ?;", { bidAmount, bidderSteamID, bidderName, auctionID }))

            -- Log telemetry via procedure wrapper
            local meta = util.TableToJSON({ auction_id = auctionID, bid_amount = bidAmount })
            GRID.Database.CallProcedure("grid_log_telemetry", {
                "ECONOMY", "AUCTION_BID", bidderSteamID, auc.seller_steamid or "", bidAmount, meta
            })

            if callback then callback(true, "SUCCESS") end
        end, function(err)
            if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
        end)
    end, function(err)
        if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
    end)
end

function GRID.Database.BuyoutAuction(auctionID, buyerSteamID, buyerName, callback)
    local now = os.time()
    auctionID = tonumber(auctionID) or 0

    if not GRID.Database.UseSQLiteFallback and not GRID.Database.UseDirectMariaDBSQL then
        GRID.Database.CallProcedure("grid_auction_buyout", {
            auctionID, buyerSteamID, buyerName, now
        }, function(rows)
            local r = rows and rows[1]
            local status = (r and r.status) or "ERROR_SQL"
            if status == "SUCCESS" then
                local prevBidder = r and r.prev_bidder or ""
                local prevBid = tonumber(r and r.prev_bid) or 0
                if prevBidder ~= "" and prevBid > 0 then
                    local pPrev = GRID.Database.SyncOnlinePlayerMoneyDelta(prevBidder, prevBid)
                    if IsValid(pPrev) then
                        GRID.Notify(pPrev, string.format("An auction you bid on was bought out! $%s was refunded.", string.Comma(prevBid)), NOTIFY_GENERIC)
                    end
                end

                local buyout = tonumber(r and r.buyout_price) or 0
                local sellerSteamID = r and r.seller_steamid or ""
                local payout = tonumber(r and r.seller_payout) or 0
                local itemId = r and r.item_id or "item"

                GRID.Database.SyncOnlinePlayerMoneyDelta(buyerSteamID, -buyout)
                local pSeller = GRID.Database.SyncOnlinePlayerMoneyDelta(sellerSteamID, payout)
                if IsValid(pSeller) then
                    GRID.Notify(pSeller, string.format("Your auction for %s was bought out! You received +$%s (including refunded deposit).", itemId, string.Comma(payout)), NOTIFY_GENERIC)
                end

                if callback then callback(true, "SUCCESS") end
            else
                if callback then callback(false, status) end
            end
        end, function(err)
            if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
        end)
        return
    end

    local aucQ = GRID.Database.FormatQuery("SELECT * FROM grid_auctions WHERE auction_id = ?;", { auctionID })
    GRID.Database.Execute(aucQ, function(aRows)
        local auc = aRows and aRows[1]
        if not auc or auc.status ~= "ACTIVE" then
            if callback then callback(false, "ERR_NOT_ACTIVE") end
            return
        end
        if tonumber(auc.expires_at_unix) <= now then
            if callback then callback(false, "ERR_EXPIRED") end
            return
        end
        local buyout = tonumber(auc.buyout_price) or 0
        if buyout <= 0 then
            if callback then callback(false, "ERR_NO_BUYOUT") end
            return
        end
        if auc.seller_steamid == buyerSteamID then
            if callback then callback(false, "ERR_SELF_BUY") end
            return
        end

        local plyQ = GRID.Database.FormatQuery("SELECT money FROM grid_players WHERE steamid = ?;", { buyerSteamID })
        GRID.Database.Execute(plyQ, function(pRows)
            local curMoney = tonumber(pRows and pRows[1] and pRows[1].money) or 0
            if curMoney < buyout then
                if callback then callback(false, "ERR_INSUFFICIENT_FUNDS") end
                return
            end

            -- Refund current high bidder if someone else had bid
            local curBid = tonumber(auc.current_bid) or 0
            if auc.high_bidder_steamid and auc.high_bidder_steamid ~= "" and curBid > 0 then
                GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET money = money + ? WHERE steamid = ?;", { curBid, auc.high_bidder_steamid }))
                local pPrev = GRID.Database.SyncOnlinePlayerMoneyDelta(auc.high_bidder_steamid, curBid)
                if IsValid(pPrev) then
                    GRID.Notify(pPrev, string.format("An auction you bid on was bought out! $%s was refunded.", string.Comma(curBid)), NOTIFY_GENERIC)
                end
            end

            local tax = math.floor(buyout * 0.075)
            local deposit = tonumber(auc.deposit_amount) or 0
            local payout = (buyout - tax) + deposit

            -- Deduct buyout from buyer
            GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET money = money - ? WHERE steamid = ?;", { buyout, buyerSteamID }))
            GRID.Database.SyncOnlinePlayerMoneyDelta(buyerSteamID, -buyout)

            -- Pay seller (proceeds + deposit refund)
            GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET money = money + ? WHERE steamid = ?;", { payout, auc.seller_steamid }))
            local pSeller = GRID.Database.SyncOnlinePlayerMoneyDelta(auc.seller_steamid, payout)
            if IsValid(pSeller) then
                GRID.Notify(pSeller, string.format("Your auction for %s was bought out! You received +$%s (including refunded deposit).", auc.item_id, string.Comma(payout)), NOTIFY_GENERIC)
            end

            -- Put item into collection box for buyer
            local insColQ = GRID.Database.FormatQuery([[INSERT INTO grid_auction_collection (
                steamid, item_id, item_type, amount, item_data, source_reason, source_auction_id, created_at_unix, claimed
            ) VALUES (?, ?, ?, ?, ?, 'WON_AUCTION', ?, ?, 0);]], {
                buyerSteamID, auc.item_id, auc.item_type or "generic", auc.amount or 1, auc.item_data or "{}", auctionID, now
            })
            GRID.Database.Execute(insColQ)

            -- Mark auction as SOLD
            GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_auctions SET status = 'SOLD', closed_at_unix = ?, high_bidder_steamid = ?, high_bidder_name = ?, current_bid = ? WHERE auction_id = ?;", { now, buyerSteamID, buyerName, buyout, auctionID }))

            -- Log telemetry via procedure wrapper
            local meta = util.TableToJSON({ auction_id = auctionID, buyout = buyout, tax = tax, payout = payout })
            GRID.Database.CallProcedure("grid_log_telemetry", {
                "ECONOMY", "AUCTION_SALE", buyerSteamID, auc.seller_steamid or "", tax, meta
            })

            if callback then callback(true, "SUCCESS") end
        end, function(err)
            if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
        end)
    end, function(err)
        if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
    end)
end

function GRID.Database.CancelAuction(auctionID, sellerSteamID, callback)
    local now = os.time()
    auctionID = tonumber(auctionID) or 0

    if not GRID.Database.UseSQLiteFallback and not GRID.Database.UseDirectMariaDBSQL then
        GRID.Database.CallProcedure("grid_auction_cancel", {
            auctionID, sellerSteamID, now
        }, function(rows)
            local r = rows and rows[1]
            local status = (r and r.status) or "ERROR_SQL"
            if status == "SUCCESS" then
                if callback then callback(true, "SUCCESS") end
            else
                if callback then callback(false, status) end
            end
        end, function(err)
            if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
        end)
        return
    end

    local aucQ = GRID.Database.FormatQuery("SELECT * FROM grid_auctions WHERE auction_id = ?;", { auctionID })
    GRID.Database.Execute(aucQ, function(aRows)
        local auc = aRows and aRows[1]
        if not auc or auc.status ~= "ACTIVE" then
            if callback then callback(false, "ERR_NOT_ACTIVE") end
            return
        end
        if auc.seller_steamid ~= sellerSteamID then
            if callback then callback(false, "ERR_NOT_OWNER") end
            return
        end
        if (tonumber(auc.current_bid) or 0) > 0 then
            if callback then callback(false, "ERR_HAS_BIDS") end
            return
        end

        local insColQ = GRID.Database.FormatQuery([[INSERT INTO grid_auction_collection (
            steamid, item_id, item_type, amount, item_data, source_reason, source_auction_id, created_at_unix, claimed
        ) VALUES (?, ?, ?, ?, ?, 'CANCELLED_AUCTION', ?, ?, 0);]], {
            sellerSteamID, auc.item_id, auc.item_type or "generic", auc.amount or 1, auc.item_data or "{}", auctionID, now
        })
        GRID.Database.Execute(insColQ, function()
            local updAucQ = GRID.Database.FormatQuery("UPDATE grid_auctions SET status = 'CANCELLED', closed_at_unix = ? WHERE auction_id = ?;", { now, auctionID })
            GRID.Database.Execute(updAucQ)

            local meta = util.TableToJSON({ auction_id = auctionID, deposit_forfeited = tonumber(auc.deposit_amount) or 0 })
            GRID.Database.CallProcedure("grid_log_telemetry", {
                "ECONOMY", "AUCTION_CANCEL", sellerSteamID, "", tonumber(auc.deposit_amount) or 0, meta
            })

            if callback then callback(true, "SUCCESS") end
        end, function(err)
            if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
        end)
    end, function(err)
        if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
    end)
end

function GRID.Database.ClaimAuctionCollection(collectionID, steamID, bagIndex, slotIndex, callback)
    local now = os.time()
    collectionID = tonumber(collectionID) or 0
    bagIndex = tonumber(bagIndex) or 0
    slotIndex = tonumber(slotIndex) or 1

    if not GRID.Database.UseSQLiteFallback and not GRID.Database.UseDirectMariaDBSQL then
        GRID.Database.CallProcedure("grid_auction_claim_collection", {
            collectionID, steamID, bagIndex, slotIndex, now
        }, function(rows)
            local r = rows and rows[1]
            local status = (r and r.status) or "ERROR_SQL"
            if status == "SUCCESS" then
                local inv = GRID.Database.Cache.Inventories[steamID] or {}
                table.insert(inv, {
                    steamid = steamID,
                    bag_index = bagIndex,
                    slot_index = slotIndex,
                    item_id = r.item_id or "",
                    item_type = r.item_type or "generic",
                    amount = tonumber(r.amount) or 1,
                    item_data = r.item_data or "{}"
                })
                GRID.Database.Cache.Inventories[steamID] = inv
                if callback then callback(true, "SUCCESS") end
            else
                if callback then callback(false, status) end
            end
        end, function(err)
            if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
        end)
        return
    end

    local colQ = GRID.Database.FormatQuery("SELECT * FROM grid_auction_collection WHERE collection_id = ? AND steamid = ?;", { collectionID, steamID })
    GRID.Database.Execute(colQ, function(cRows)
        local item = cRows and cRows[1]
        if not item then
            if callback then callback(false, "ERR_NOT_FOUND") end
            return
        end
        if tonumber(item.claimed) == 1 then
            if callback then callback(false, "ERR_ALREADY_CLAIMED") end
            return
        end

        local itemData = item.item_data or "{}"
        if type(itemData) == "string" and string.sub(itemData, 1, 1) == "{" then
            itemData = util.JSONToTable(itemData) or {}
        end

        -- Add to player's inventory cache & DB
        local added = GRID.Database.AddInventoryItem(steamID, item.item_id, item.item_type or "generic", tonumber(item.amount) or 1, itemData, bagIndex, slotIndex)
        if not added then
            if callback then callback(false, "ERR_BAG_FULL") end
            return
        end

        -- Mark collection row as claimed
        GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_auction_collection SET claimed = 1, claimed_at_unix = ? WHERE collection_id = ?;", { now, collectionID }))

        local meta = util.TableToJSON({ collection_id = collectionID, item_id = item.item_id })
        GRID.Database.CallProcedure("grid_log_telemetry", {
            "ECONOMY", "AUCTION_CLAIM", steamID, "", 0, meta
        })

        if callback then callback(true, "SUCCESS") end
    end, function(err)
        if callback then callback(false, "ERROR_SQL: " .. tostring(err)) end
    end)
end

function GRID.Database.ProcessAuctionExpirations(callback)
    local now = os.time()
    GRID.Database.QueryView("v_auctions", "status = 'ACTIVE' AND expires_at_unix <= ?", { now }, function(rows)
        if not rows or #rows == 0 then
            if callback then callback() end
            return
        end

        if not GRID.Database.UseSQLiteFallback and not GRID.Database.UseDirectMariaDBSQL then
            GRID.Database.CallProcedure("grid_auction_process_expirations", { now }, function()
                for _, auc in ipairs(rows) do
                    local curBid = tonumber(auc.current_bid) or 0
                    local deposit = tonumber(auc.deposit_amount) or 0
                    if curBid > 0 and auc.high_bidder_steamid and auc.high_bidder_steamid ~= "" then
                        local tax = math.floor(curBid * 0.075)
                        local payout = (curBid - tax) + deposit
                        local pSeller = GRID.Database.SyncOnlinePlayerMoneyDelta(auc.seller_steamid, payout)
                        if IsValid(pSeller) then
                            GRID.Notify(pSeller, string.format("Your auction for %s expired and sold for +$%s!", auc.item_id, string.Comma(payout)), NOTIFY_GENERIC)
                        end
                    end
                end
                if callback then callback() end
            end, function(err)
                ErrorNoHalt(string.format("[GRID AUCTION DB ERROR] grid_auction_process_expirations failed: %s\n", tostring(err)))
                if callback then callback() end
            end)
            return
        end

        for _, auc in ipairs(rows) do
            local curBid = tonumber(auc.current_bid) or 0
            local deposit = tonumber(auc.deposit_amount) or 0
            if curBid > 0 and auc.high_bidder_steamid and auc.high_bidder_steamid ~= "" then
                local tax = math.floor(curBid * 0.075)
                local payout = (curBid - tax) + deposit
                GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_players SET money = money + ? WHERE steamid = ?;", { payout, auc.seller_steamid }))
                local pSeller = GRID.Database.SyncOnlinePlayerMoneyDelta(auc.seller_steamid, payout)
                if IsValid(pSeller) then
                    GRID.Notify(pSeller, string.format("Your auction for %s expired and sold for +$%s!", auc.item_id, string.Comma(payout)), NOTIFY_GENERIC)
                end

                GRID.Database.Execute(GRID.Database.FormatQuery([[INSERT INTO grid_auction_collection (
                    steamid, item_id, item_type, amount, item_data, source_reason, source_auction_id, created_at_unix, claimed
                ) VALUES (?, ?, ?, ?, ?, 'WON_AUCTION', ?, ?, 0);]], {
                    auc.high_bidder_steamid, auc.item_id, auc.item_type or "generic", auc.amount or 1, auc.item_data or "{}", auc.auction_id, now
                }))
                GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_auctions SET status = 'SOLD', closed_at_unix = ? WHERE auction_id = ?;", { now, auc.auction_id }))
            else
                GRID.Database.Execute(GRID.Database.FormatQuery([[INSERT INTO grid_auction_collection (
                    steamid, item_id, item_type, amount, item_data, source_reason, source_auction_id, created_at_unix, claimed
                ) VALUES (?, ?, ?, ?, ?, 'EXPIRED_AUCTION', ?, ?, 0);]], {
                    auc.seller_steamid, auc.item_id, auc.item_type or "generic", auc.amount or 1, auc.item_data or "{}", auc.auction_id, now
                }))
                GRID.Database.Execute(GRID.Database.FormatQuery("UPDATE grid_auctions SET status = 'EXPIRED', closed_at_unix = ? WHERE auction_id = ?;", { now, auc.auction_id }))
            end
        end
        if callback then callback() end
    end, function(err)
        ErrorNoHalt(string.format("[GRID AUCTION DB ERROR] ProcessAuctionExpirations failed: %s\n", tostring(err)))
        if callback then callback() end
    end)
end

-- ========================================================
-- 10. PERSISTENT MAP ENTITIES (GRID.MapSpawns)
-- ========================================================

function GRID.Database.SaveMapEntity(spawnId, mapName, className, pos, ang, adminSid, customData, callback, errback)
    spawnId = tonumber(spawnId) or 0
    local customJson = customData and (istable(customData) and util.TableToJSON(customData) or tostring(customData)) or nil
    local params = {
        spawnId,
        string.lower(mapName),
        className,
        pos.x, pos.y, pos.z,
        ang.p, ang.y, ang.r,
        adminSid or "CONSOLE",
        customJson
    }

    GRID.Database.CallProcedure("grid_save_map_entity", params, function(rows)
        local newId = spawnId
        if rows and rows[1] and rows[1].spawn_id then
            newId = tonumber(rows[1].spawn_id) or newId
        elseif (not newId or newId == 0) and GRID.Database.UseSQLiteFallback then
            local lastRow = sql.QueryRow("SELECT last_insert_rowid() AS spawn_id;")
            if lastRow and lastRow.spawn_id then
                newId = tonumber(lastRow.spawn_id) or newId
            end
        end
        if callback then callback(newId) end
    end, function(err)
        ErrorNoHalt(string.format("[GRID MapSpawns DB ERROR] SaveMapEntity failed: %s\n", tostring(err)))
        if errback then errback(err) end
    end)
end

function GRID.Database.DeleteMapEntity(spawnId, callback, errback)
    spawnId = tonumber(spawnId) or 0
    if spawnId <= 0 then
        if callback then callback() end
        return
    end

    GRID.Database.CallProcedure("grid_delete_map_entity", { spawnId }, function()
        if callback then callback() end
    end, function(err)
        ErrorNoHalt(string.format("[GRID MapSpawns DB ERROR] DeleteMapEntity failed for ID %d: %s\n", spawnId, tostring(err)))
        if errback then errback(err) end
    end)
end

function GRID.Database.LoadMapEntities(mapName, callback, errback)
    local mapKey = string.lower(mapName)
    GRID.Database.QueryView("v_grid_map_spawns", "map_name = ?", { mapKey }, function(rows)
        if callback then callback(rows or {}) end
    end, function(err)
        ErrorNoHalt(string.format("[GRID MapSpawns DB ERROR] LoadMapEntities failed for map '%s': %s\n", mapKey, tostring(err)))
        if errback then errback(err) end
    end)
end

function GRID.Database.CopyMapEntities(oldMap, newMap, callback, errback)
    local oldKey = string.lower(oldMap)
    local newKey = string.lower(newMap)
    GRID.Database.CallProcedure("grid_copy_map_spawns", { oldKey, newKey }, function(data)
        if callback then callback(data) end
    end, function(err)
        ErrorNoHalt(string.format("[GRID MapSpawns DB ERROR] CopyMapEntities failed from '%s' to '%s': %s\n", oldKey, newKey, tostring(err)))
        if errback then errback(err) end
    end)
end

-- ========================================================
-- 11. ADMINISTRATIVE PLAYER RESET
-- ========================================================

function GRID.Database.ResetPlayer(steamID, callback, errback)
    if not steamID or steamID == "" then return end
    GRID.Database.CallProcedure("grid_reset_player", { steamID }, function()
        if callback then callback() end
    end, function(err)
        ErrorNoHalt(string.format("[GRID DB ERROR] ResetPlayer failed for %s: %s\n", steamID, tostring(err)))
        if errback then errback(err) end
    end)
end


