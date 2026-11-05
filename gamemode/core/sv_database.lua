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
    -- Fallback escaping
    local s = tostring(str)
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, "'", "\\'")
    s = string.gsub(s, "\"", "\\\"")
    s = string.gsub(s, "\0", "\\0")
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

    print(string.format("[GRID DB] Connecting to MariaDB at %s:%d (Database: %s)...", cfg.Host, cfg.Port, cfg.Database))

    local db = mysqloo.connect(cfg.Host, cfg.User, cfg.Password, cfg.Database, cfg.Port, cfg.Socket)

    function db:onConnected()
        GRID.Database.Connected = true
        GRID.Database.Connection = db
        print("[GRID DB] Successfully connected to MariaDB engine!")

        -- Flush queued queries
        if #GRID.Database.Queue > 0 then
            print(string.format("[GRID DB] Flushing %d queued database operations...", #GRID.Database.Queue))
            for _, item in ipairs(GRID.Database.Queue) do
                GRID.Database.Execute(item.Query, item.Callback, item.ErrorCallback)
            end
            GRID.Database.Queue = {}
        end

        hook.Run("GRID_DatabaseConnected")
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
-- STORED PROCEDURE WRAPPERS (100% Stored Procedures for Writes)
-- ========================================================

function GRID.Database.CallProcedure(procName, params, onDone, onError)
    local placeholders = {}
    for i = 1, #params do
        table.insert(placeholders, "?")
    end
    local sqlStr = string.format("CALL %s(%s);", procName, table.concat(placeholders, ", "))
    local query = GRID.Database.FormatQuery(sqlStr, params)
    GRID.Database.Execute(query, onDone, onError)
end

function GRID.Database.QueryView(viewName, whereClause, params, onDone, onError)
    local q = "SELECT * FROM " .. viewName
    if whereClause and whereClause ~= "" then
        q = q .. " WHERE " .. whereClause
    end
    local formatted = GRID.Database.FormatQuery(q, params)
    GRID.Database.Execute(formatted, onDone, onError)
end

-- ========================================================
-- INITIALIZATION & SQLITE FALLBACK
-- ========================================================

function GRID.Database.Init()
    GRID.Database.Connect()
end

-- SQLite Dev Fallback table creation (only invoked if mysqloo binary module is not present on developer's local PC)
function GRID.Database.InitSQLiteFallback()
    sql.Query([[
        CREATE TABLE IF NOT EXISTS grid_players (
            steamid TEXT PRIMARY KEY,
            name TEXT,
            money INTEGER DEFAULT 1000,
            respect INTEGER DEFAULT 0,
            gang TEXT DEFAULT '',
            job TEXT DEFAULT 'citizen',
            level INTEGER DEFAULT 1,
            xp INTEGER DEFAULT 0,
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
            local m = tonumber(playerData.money) or (GRID.Config and GRID.Config.StartingMoney or 1000)
            local r = tonumber(playerData.respect) or 0
            local g = playerData.gang or ""
            local j = (playerData.job and playerData.job ~= "") and playerData.job or "citizen"
            local lvl = math.max(1, tonumber(playerData.level) or 1)
            local xp = math.max(0, tonumber(playerData.xp) or 0)

            ply:SetNWInt("GRID_Money", m)
            ply:SetNWInt("GRID_Respect", r)
            ply:SetNWString("GRID_Gang", g)
            ply:SetNWString("GRID_Job", j)
            ply:SetNWInt("GRID_Level", lvl)
            ply:SetNWInt("GRID_XP", xp)

            if playerData.gang_rank == "leader" then
                ply:SetNWBool("GRID_IsGangLeader", true)
            end
        else
            local initialMoney = GRID.Config and GRID.Config.StartingMoney or 1000
            playerData = {
                steamid = steamID,
                name = ply:Nick(),
                money = initialMoney,
                respect = 0,
                gang = "",
                job = "citizen",
                level = 1,
                xp = 0,
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
                os.time()
            })

            ply:SetNWInt("GRID_Money", initialMoney)
            ply:SetNWInt("GRID_Respect", 0)
            ply:SetNWString("GRID_Gang", "")
            ply:SetNWString("GRID_Job", "citizen")
            ply:SetNWInt("GRID_Level", 1)
            ply:SetNWInt("GRID_XP", 0)
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
            if callback then callback() end
        end)
    end)
end

function GRID.Database.SavePlayer(ply)
    if not IsValid(ply) or not ply.GRID_DataLoaded then return end
    local steamID = ply:SteamID()

    GRID.Database.CallProcedure("grid_upsert_player", {
        steamID,
        ply:Nick(),
        ply:GetMoney(),
        ply:GetNWInt("GRID_Respect", 0),
        ply:GetGang(),
        ply:GetJob(),
        ply:GetNWInt("GRID_Level", 1),
        ply:GetNWInt("GRID_XP", 0),
        os.time()
    })

    if GRID.Database.Cache.Players[steamID] then
        local p = GRID.Database.Cache.Players[steamID]
        p.name = ply:Nick()
        p.money = ply:GetMoney()
        p.respect = ply:GetNWInt("GRID_Respect", 0)
        p.gang = ply:GetGang()
        p.job = ply:GetJob()
        p.level = ply:GetNWInt("GRID_Level", 1)
        p.xp = ply:GetNWInt("GRID_XP", 0)
        p.last_seen = os.time()
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
    GRID.Database.CallProcedure("grid_transfer_gang_vault", {
        steamID,
        gangName,
        d,
        os.time()
    })
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

    -- 2. Check identical stack
    for _, it in ipairs(inv) do
        if it.item_id == itemId then
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
        if srcItem.item_id == dstItem.item_id then
            -- Stack
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
    amount = tonumber(amount) or 1
    local inv = GRID.Database.Cache.Inventories[steamID] or {}
    for idx, it in ipairs(inv) do
        if it.item_id == itemId then
            local curAmount = tonumber(it.amount) or 1
            if curAmount <= amount then
                local b = it.bag_index
                local s = it.slot_index
                table.remove(inv, idx)
                GRID.Database.CallProcedure("grid_delete_inventory_slot", { steamID, b, s })
            else
                it.amount = curAmount - amount
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
            return true
        end
    end
    return false
end

function GRID.Database.HasInventoryItem(steamID, itemId, amount)
    amount = tonumber(amount) or 1
    local inv = GRID.Database.Cache.Inventories[steamID] or {}
    for _, it in ipairs(inv) do
        if it.item_id == itemId and (tonumber(it.amount) or 0) >= amount then
            return true
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
    if GRID.Database.Cache.Buffs[steamID] then
        return GRID.Database.Cache.Buffs[steamID]
    end
    return {}
end

function GRID.Database.SavePlayerBuff(steamID, buffId, duration, remaining, stacks, appliedAt, expiresAtUnix, dataStr)
    GRID.Database.Cache.Buffs[steamID] = GRID.Database.Cache.Buffs[steamID] or {}
    GRID.Database.Cache.Buffs[steamID][buffId] = {
        buff_id = buffId,
        duration = tonumber(duration) or 0,
        remaining = tonumber(remaining) or 0,
        stacks = tonumber(stacks) or 1,
        applied_at = tonumber(appliedAt) or os.time(),
        expires_at_unix = tonumber(expiresAtUnix) or 0,
        data = tostring(dataStr or "{}")
    }

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
    if GRID.Database.Cache.Buffs[steamID] then
        GRID.Database.Cache.Buffs[steamID][buffId] = nil
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
    GRID.Database.CallProcedure("grid_collect_printer_taxed", {
        steamID,
        gangName or "",
        tonumber(payout) or 0,
        tonumber(tax) or 0,
        os.time()
    })
end

-- Auto-initialize database on server startup
hook.Add("Initialize", "GRID_DatabaseInit", function()
    GRID.Database.Init()
end)
