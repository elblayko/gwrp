--[[
    GangWars - Server Database Layer (MariaDB mysqloo v9 + Stored Procedures + Analytical Views + In-Memory RAM Cache)
    Author: GW Core Team
    Namespace: GW / gw_
]]

GW = GW or {}
GW.Database = GW.Database or {}
GW.Database.Cache = GW.Database.Cache or {
    Players = {},
    Inventories = {},
    Bags = {},
    Gangs = {},
    GangMembers = {},
    Turfs = {},
    Buffs = {},
    Settings = {}
}

GW.Database.Connected = false
GW.Database.Queue = GW.Database.Queue or {}
GW.Database.Connection = GW.Database.Connection or nil

-- Sanitizer / Escaper helper
function GW.Database.Escape(str)
    if str == nil then return "NULL" end
    if isnumber(str) then return tostring(str) end
    if isbool(str) then return str and "1" or "0" end
    if GW.Database.Connection and GW.Database.Connection.escape then
        return "'" .. GW.Database.Connection:escape(tostring(str)) .. "'"
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
function GW.Database.FormatQuery(queryTemplate, params)
    params = params or {}
    local pieces = string.Explode("?", queryTemplate)
    if #pieces <= 1 then return queryTemplate end

    local out = { pieces[1] }
    for i = 1, #pieces - 1 do
        table.insert(out, GW.Database.Escape(params[i]))
        table.insert(out, pieces[i + 1])
    end
    return table.concat(out, "")
end

-- ========================================================
-- CONNECTION MANAGEMENT (mysqloo v9)
-- ========================================================

function GW.Database.Connect()
    local hasMySQLOO, _ = pcall(require, "mysqloo")
    local cfg = GW.Database.LoadConfig and GW.Database.LoadConfig() or GW.Database.Config

    if not hasMySQLOO or not mysqloo then
        ErrorNoHalt("[GW DB WARNING] mysqloo module not found! Falling back to SQLite local emulation for testing.\n")
        GW.Database.UseSQLiteFallback = true
        GW.Database.InitSQLiteFallback()
        return
    end

    print(string.format("[GW DB] Connecting to MariaDB at %s:%d (Database: %s)...", cfg.Host, cfg.Port, cfg.Database))

    local db = mysqloo.connect(cfg.Host, cfg.User, cfg.Password, cfg.Database, cfg.Port, cfg.Socket)

    function db:onConnected()
        GW.Database.Connected = true
        GW.Database.Connection = db
        print("[GW DB] Successfully connected to MariaDB engine!")

        -- Flush queued queries
        if #GW.Database.Queue > 0 then
            print(string.format("[GW DB] Flushing %d queued database operations...", #GW.Database.Queue))
            for _, item in ipairs(GW.Database.Queue) do
                GW.Database.Execute(item.Query, item.Callback, item.ErrorCallback)
            end
            GW.Database.Queue = {}
        end

        hook.Run("GW_DatabaseConnected")
    end

    function db:onConnectionFailed(err)
        GW.Database.Connected = false
        ErrorNoHalt(string.format("[GW DB ERROR] MariaDB connection failed: %s\n", tostring(err)))
        -- Retry connection in 10 seconds
        timer.Simple(10, function()
            if not GW.Database.Connected then
                GW.Database.Connect()
            end
        end)
    end

    db:connect()
end

function GW.Database.Execute(queryString, onDone, onError)
    if GW.Database.UseSQLiteFallback then
        local res = sql.Query(queryString)
        if res == false then
            local err = sql.LastError()
            if onError then onError(err) else ErrorNoHalt(string.format("[GW DB SQLITE ERROR] %s: %s\n", queryString, tostring(err))) end
            return
        end
        if onDone then onDone(res or {}) end
        return
    end

    if not GW.Database.Connected or not GW.Database.Connection then
        table.insert(GW.Database.Queue, { Query = queryString, Callback = onDone, ErrorCallback = onError })
        return
    end

    local q = GW.Database.Connection:query(queryString)
    function q:onSuccess(data)
        if onDone then onDone(data) end
    end
    function q:onError(err)
        ErrorNoHalt(string.format("[GW DB ERROR] Query failed:\n%s\nError: %s\n", queryString, tostring(err)))
        if onError then onError(err) end
    end
    q:start()
end

-- ========================================================
-- STORED PROCEDURE WRAPPERS (100% Stored Procedures for Writes)
-- ========================================================

function GW.Database.CallProcedure(procName, params, onDone, onError)
    local placeholders = {}
    for i = 1, #params do
        table.insert(placeholders, "?")
    end
    local sqlStr = string.format("CALL %s(%s);", procName, table.concat(placeholders, ", "))
    local query = GW.Database.FormatQuery(sqlStr, params)
    GW.Database.Execute(query, onDone, onError)
end

function GW.Database.QueryView(viewName, whereClause, params, onDone, onError)
    local q = "SELECT * FROM " .. viewName
    if whereClause and whereClause ~= "" then
        q = q .. " WHERE " .. whereClause
    end
    local formatted = GW.Database.FormatQuery(q, params)
    GW.Database.Execute(formatted, onDone, onError)
end

-- ========================================================
-- INITIALIZATION
-- ========================================================

function GW.Database.Init()
    GW.Database.Connect()
end

-- SQLite Dev Fallback table creation (only invoked if mysqloo binary module is not present on developer's local PC)
function GW.Database.InitSQLiteFallback()
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gw_players (
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
        CREATE TABLE IF NOT EXISTS gw_gangs (
            name TEXT PRIMARY KEY,
            leader_steamid TEXT,
            bank INTEGER DEFAULT 0,
            respect INTEGER DEFAULT 0,
            created_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS gw_gang_members (
            steamid TEXT PRIMARY KEY,
            gang TEXT,
            rank TEXT DEFAULT 'member',
            joined_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS gw_inventory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            steamid TEXT,
            bag_index INTEGER DEFAULT 0,
            slot_index INTEGER DEFAULT 1,
            item_id TEXT,
            item_type TEXT,
            amount INTEGER DEFAULT 1,
            item_data TEXT DEFAULT '{}'
        );
        CREATE TABLE IF NOT EXISTS gw_player_bags (
            steamid TEXT PRIMARY KEY,
            bag1 TEXT DEFAULT '',
            bag2 TEXT DEFAULT '',
            bag3 TEXT DEFAULT '',
            bag4 TEXT DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS gw_turfs (
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
        CREATE TABLE IF NOT EXISTS gw_settings (
            key TEXT PRIMARY KEY,
            val TEXT
        );
        CREATE TABLE IF NOT EXISTS gw_player_buffs (
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
        CREATE TABLE IF NOT EXISTS gw_telemetry (
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
    GW.Database.Connected = true
    hook.Run("GW_DatabaseConnected")
end

-- ========================================================
-- 1. PLAYER PERSISTENCE OPERATIONS
-- ========================================================

function GW.Database.LoadPlayer(ply, callback)
    local steamID = ply:SteamID()

    -- Analytical Read via v_player_profile view
    GW.Database.QueryView("v_player_profile", "steamid = ? LIMIT 1", { steamID }, function(rows)
        local playerData = {}
        if rows and rows[1] then
            playerData = rows[1]
            ply:SetNWInt("GW_Money", tonumber(playerData.money) or (GW.Config and GW.Config.StartingMoney or 1000))
            ply:SetNWInt("GW_Respect", tonumber(playerData.respect) or 0)
            ply:SetNWString("GW_Gang", playerData.gang or "")
            ply:SetNWString("GW_Job", (playerData.job and playerData.job ~= "") and playerData.job or "citizen")
            ply:SetNWInt("GW_Level", math.max(1, tonumber(playerData.level) or 1))
            ply:SetNWInt("GW_XP", math.max(0, tonumber(playerData.xp) or 0))

            if playerData.gang_rank == "leader" then
                ply:SetNWBool("GW_IsGangLeader", true)
            end
        else
            local initialMoney = GW.Config and GW.Config.StartingMoney or 1000
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
            GW.Database.CallProcedure("gw_upsert_player", {
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

            ply:SetNWInt("GW_Money", initialMoney)
            ply:SetNWInt("GW_Respect", 0)
            ply:SetNWString("GW_Gang", "")
            ply:SetNWString("GW_Job", "citizen")
            ply:SetNWInt("GW_Level", 1)
            ply:SetNWInt("GW_XP", 0)
        end

        GW.Database.Cache.Players[steamID] = playerData
        ply.GW_DataLoaded = true

        -- Pre-populate inventory, bags, buffs into RAM cache
        GW.Database.RefreshPlayerCache(steamID, function()
            if callback then callback(playerData) end
        end)
    end, function(err)
        ErrorNoHalt("[GW DB] Failed to load player " .. steamID .. ": " .. tostring(err) .. "\n")
    end)
end

function GW.Database.RefreshPlayerCache(steamID, callback)
    -- Load bags
    GW.Database.QueryView("v_player_bags", "steamid = ? LIMIT 1", { steamID }, function(bagRows)
        if bagRows and bagRows[1] then
            GW.Database.Cache.Bags[steamID] = bagRows[1]
        else
            GW.Database.Cache.Bags[steamID] = { bag1 = "", bag2 = "", bag3 = "", bag4 = "" }
        end

        -- Load inventory
        GW.Database.QueryView("v_player_inventory", "steamid = ? ORDER BY bag_index ASC, slot_index ASC", { steamID }, function(invRows)
            GW.Database.Cache.Inventories[steamID] = invRows or {}
            if callback then callback() end
        end)
    end)
end

function GW.Database.SavePlayer(ply)
    if not IsValid(ply) or not ply.GW_DataLoaded then return end
    local steamID = ply:SteamID()

    GW.Database.CallProcedure("gw_upsert_player", {
        steamID,
        ply:Nick(),
        ply:GetMoney(),
        ply:GetNWInt("GW_Respect", 0),
        ply:GetGang(),
        ply:GetJob(),
        ply:GetNWInt("GW_Level", 1),
        ply:GetNWInt("GW_XP", 0),
        os.time()
    })

    if GW.Database.Cache.Players[steamID] then
        local p = GW.Database.Cache.Players[steamID]
        p.name = ply:Nick()
        p.money = ply:GetMoney()
        p.respect = ply:GetNWInt("GW_Respect", 0)
        p.gang = ply:GetGang()
        p.job = ply:GetJob()
        p.level = ply:GetNWInt("GW_Level", 1)
        p.xp = ply:GetNWInt("GW_XP", 0)
        p.last_seen = os.time()
    end
end

function GW.Database.SavePlayerLevelXP(ply, level, xp)
    if not IsValid(ply) or not ply.GW_DataLoaded then return end
    local steamID = ply:SteamID()
    local lvl = math.max(1, tonumber(level) or 1)
    local exp = math.max(0, tonumber(xp) or 0)

    GW.Database.CallProcedure("gw_update_player_level_xp", {
        steamID,
        lvl,
        exp,
        os.time()
    })

    if GW.Database.Cache.Players[steamID] then
        GW.Database.Cache.Players[steamID].level = lvl
        GW.Database.Cache.Players[steamID].xp = exp
    end
end

function GW.Database.SavePlayerMoney(ply, amount)
    if not IsValid(ply) or not ply.GW_DataLoaded then return end
    local steamID = ply:SteamID()
    local money = tonumber(amount) or 0

    GW.Database.CallProcedure("gw_update_player_money", {
        steamID,
        money,
        os.time()
    })

    if GW.Database.Cache.Players[steamID] then
        GW.Database.Cache.Players[steamID].money = money
    end
end

function GW.Database.SavePlayerGang(ply, gangName)
    if not IsValid(ply) or not ply.GW_DataLoaded then return end
    local steamID = ply:SteamID()
    gangName = gangName or ""

    GW.Database.CallProcedure("gw_update_player_gang", {
        steamID,
        gangName,
        os.time()
    })

    if GW.Database.Cache.Players[steamID] then
        GW.Database.Cache.Players[steamID].gang = gangName
    end
end

function GW.Database.SavePlayerJob(ply, jobId)
    if not IsValid(ply) or not ply.GW_DataLoaded then return end
    local steamID = ply:SteamID()
    jobId = jobId or "citizen"

    GW.Database.CallProcedure("gw_update_player_job", {
        steamID,
        jobId,
        os.time()
    })

    if GW.Database.Cache.Players[steamID] then
        GW.Database.Cache.Players[steamID].job = jobId
    end
end

-- ========================================================
-- 2. GANG & MEMBER ROSTER PERSISTENCE
-- ========================================================

function GW.Database.CreateGang(gangName, leaderSteamID)
    GW.Database.CallProcedure("gw_create_gang", {
        gangName,
        leaderSteamID,
        os.time()
    })

    GW.Database.Cache.Gangs[gangName] = {
        name = gangName,
        leader_steamid = leaderSteamID,
        bank = 0,
        respect = 0,
        created_at = os.time()
    }
    GW.Database.Cache.GangMembers[leaderSteamID] = {
        steamid = leaderSteamID,
        gang = gangName,
        rank = "leader",
        joined_at = os.time()
    }
    return true
end

function GW.Database.GetGang(gangName)
    if GW.Database.Cache.Gangs[gangName] then
        return GW.Database.Cache.Gangs[gangName]
    end

    if GW.Database.UseSQLiteFallback then
        local rows = sql.Query(string.format("SELECT * FROM gw_gangs WHERE name = %s LIMIT 1;", sql.SQLStr(gangName)))
        if rows and rows[1] then
            GW.Database.Cache.Gangs[gangName] = rows[1]
            return rows[1]
        end
    end
    return nil
end

function GW.Database.AddGangMember(steamID, gangName, rank)
    rank = rank or "member"
    GW.Database.CallProcedure("gw_add_gang_member", {
        steamID,
        gangName,
        rank,
        os.time()
    })

    GW.Database.Cache.GangMembers[steamID] = {
        steamid = steamID,
        gang = gangName,
        rank = rank,
        joined_at = os.time()
    }
    if GW.Database.Cache.Players[steamID] then
        GW.Database.Cache.Players[steamID].gang = gangName
    end
    return true
end

function GW.Database.RemoveGangMember(steamID)
    GW.Database.CallProcedure("gw_remove_gang_member", { steamID })
    GW.Database.Cache.GangMembers[steamID] = nil
    if GW.Database.Cache.Players[steamID] then
        GW.Database.Cache.Players[steamID].gang = ""
    end
    return true
end

function GW.Database.GetGangMember(steamID)
    if GW.Database.Cache.GangMembers[steamID] then
        return GW.Database.Cache.GangMembers[steamID]
    end

    if GW.Database.UseSQLiteFallback then
        local rows = sql.Query(string.format("SELECT * FROM gw_gang_members WHERE steamid = %s LIMIT 1;", sql.SQLStr(steamID)))
        if rows and rows[1] then
            GW.Database.Cache.GangMembers[steamID] = rows[1]
            return rows[1]
        end
    end
    return nil
end

function GW.Database.GetGangMembers(gangName)
    if GW.Database.UseSQLiteFallback then
        local q = string.format([[
            SELECT m.steamid, m.rank, m.joined_at, p.name, p.money, p.last_seen
            FROM gw_gang_members m
            LEFT JOIN gw_players p ON m.steamid = p.steamid
            WHERE m.gang = %s
            ORDER BY CASE m.rank WHEN 'leader' THEN 1 WHEN 'officer' THEN 2 ELSE 3 END, m.joined_at ASC;
        ]], sql.SQLStr(gangName))
        return sql.Query(q) or {}
    end

    local members = {}
    for sid, m in pairs(GW.Database.Cache.GangMembers) do
        if m.gang == gangName then
            local plyData = GW.Database.Cache.Players[sid] or {}
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

function GW.Database.AddGangBank(gangName, amount)
    local amt = tonumber(amount) or 0
    GW.Database.CallProcedure("gw_add_gang_bank", { gangName, amt })
    if GW.Database.Cache.Gangs[gangName] then
        local cur = tonumber(GW.Database.Cache.Gangs[gangName].bank) or 0
        GW.Database.Cache.Gangs[gangName].bank = math.max(0, cur + amt)
    end
end

function GW.Database.TransferGangVault(steamID, gangName, delta)
    local d = tonumber(delta) or 0
    GW.Database.CallProcedure("gw_transfer_gang_vault", {
        steamID,
        gangName,
        d,
        os.time()
    })
    return true
end

function GW.Database.DisbandGang(gangName)
    GW.Database.CallProcedure("gw_disband_gang", { gangName })
    GW.Database.Cache.Gangs[gangName] = nil
    for sid, m in pairs(GW.Database.Cache.GangMembers) do
        if m.gang == gangName then
            GW.Database.Cache.GangMembers[sid] = nil
            if GW.Database.Cache.Players[sid] then
                GW.Database.Cache.Players[sid].gang = ""
            end
        end
    end
    return true
end

function GW.Database.GetAllGangs()
    if GW.Database.UseSQLiteFallback then
        return sql.Query("SELECT * FROM gw_gangs ORDER BY respect DESC, bank DESC;") or {}
    end

    local list = {}
    for _, g in pairs(GW.Database.Cache.Gangs) do
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

function GW.Database.GetInventory(steamID)
    return GW.Database.Cache.Inventories[steamID] or {}
end

function GW.Database.GetInventorySlot(steamID, bagIndex, slotIndex)
    local inv = GW.Database.Cache.Inventories[steamID]
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

function GW.Database.GetPlayerBags(steamID)
    if GW.Database.Cache.Bags[steamID] then
        return GW.Database.Cache.Bags[steamID]
    end
    return { bag1 = "", bag2 = "", bag3 = "", bag4 = "" }
end

function GW.Database.SetPlayerBags(steamID, bag1, bag2, bag3, bag4)
    local bags = {
        steamid = steamID,
        bag1 = bag1 or "",
        bag2 = bag2 or "",
        bag3 = bag3 or "",
        bag4 = bag4 or ""
    }
    GW.Database.Cache.Bags[steamID] = bags

    GW.Database.CallProcedure("gw_set_player_bags", {
        steamID,
        bags.bag1,
        bags.bag2,
        bags.bag3,
        bags.bag4
    })
end

function GW.Database.AddInventoryItem(steamID, itemId, itemType, amount, itemData, targetBag, targetSlot)
    amount = tonumber(amount) or 1
    local iType = itemType or "generic"
    local iData = type(itemData) == "table" and util.TableToJSON(itemData) or (itemData or "{}")

    local inv = GW.Database.Cache.Inventories[steamID] or {}

    -- 1. If explicit target slot provided
    if targetBag and targetSlot then
        local slotOccupant = GW.Database.GetInventorySlot(steamID, targetBag, targetSlot)
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
            GW.Database.Cache.Inventories[steamID] = inv

            GW.Database.CallProcedure("gw_set_inventory_slot", {
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
            GW.Database.CallProcedure("gw_set_inventory_slot", {
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

    local playerBags = GW.Database.GetPlayerBags(steamID)
    local getCap = GW.Inventory.GetBagCapacity or function() return 0 end
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
        GW.Database.Cache.Inventories[steamID] = inv

        GW.Database.CallProcedure("gw_set_inventory_slot", {
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

function GW.Database.MoveInventorySlot(steamID, fromBag, fromSlot, toBag, toSlot)
    fromBag = tonumber(fromBag) or 0
    fromSlot = tonumber(fromSlot) or 1
    toBag = tonumber(toBag) or 0
    toSlot = tonumber(toSlot) or 1

    local inv = GW.Database.Cache.Inventories[steamID] or {}
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
        GW.Database.CallProcedure("gw_move_inventory_slot", { steamID, fromBag, fromSlot, toBag, toSlot })
        return true
    else
        local dstItem = inv[dstIdx]
        if srcItem.item_id == dstItem.item_id then
            -- Stack
            dstItem.amount = (tonumber(dstItem.amount) or 1) + (tonumber(srcItem.amount) or 1)
            table.remove(inv, srcIdx)
            GW.Database.CallProcedure("gw_move_inventory_slot", { steamID, fromBag, fromSlot, toBag, toSlot })
            return true
        else
            -- Swap
            srcItem.bag_index = toBag
            srcItem.slot_index = toSlot
            dstItem.bag_index = fromBag
            dstItem.slot_index = fromSlot
            GW.Database.CallProcedure("gw_move_inventory_slot", { steamID, fromBag, fromSlot, toBag, toSlot })
            return true
        end
    end
end

function GW.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, amount)
    amount = tonumber(amount) or 1
    bagIndex = tonumber(bagIndex) or 0
    slotIndex = tonumber(slotIndex) or 1

    local inv = GW.Database.Cache.Inventories[steamID] or {}
    for idx, it in ipairs(inv) do
        if (tonumber(it.bag_index) or 0) == bagIndex and (tonumber(it.slot_index) or 1) == slotIndex then
            local curAmount = tonumber(it.amount) or 1
            if curAmount <= amount then
                table.remove(inv, idx)
                GW.Database.CallProcedure("gw_delete_inventory_slot", { steamID, bagIndex, slotIndex })
            else
                it.amount = curAmount - amount
                GW.Database.CallProcedure("gw_set_inventory_slot", {
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

function GW.Database.RemoveInventoryItem(steamID, itemId, amount)
    amount = tonumber(amount) or 1
    local inv = GW.Database.Cache.Inventories[steamID] or {}
    for idx, it in ipairs(inv) do
        if it.item_id == itemId then
            local curAmount = tonumber(it.amount) or 1
            if curAmount <= amount then
                local b = it.bag_index
                local s = it.slot_index
                table.remove(inv, idx)
                GW.Database.CallProcedure("gw_delete_inventory_slot", { steamID, b, s })
            else
                it.amount = curAmount - amount
                GW.Database.CallProcedure("gw_set_inventory_slot", {
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

function GW.Database.HasInventoryItem(steamID, itemId, amount)
    amount = tonumber(amount) or 1
    local inv = GW.Database.Cache.Inventories[steamID] or {}
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

function GW.Database.SaveTurfZones(mapName, zonesTable)
    local mapKey = string.lower(mapName)
    GW.Database.CallProcedure("gw_clear_map_turfs", { mapKey })

    for id, zone in pairs(zonesTable) do
        local idNum = tonumber(id) or 1
        local name = zone.name or ("Turf #" .. idNum)
        local px = zone.pos and zone.pos.x or 0
        local py = zone.pos and zone.pos.y or 0
        local pz = zone.pos and zone.pos.z or 0
        local radius = tonumber(zone.radius) or 450
        local owner = zone.owner or "neutral"
        local taxRate = tonumber(zone.tax_rate) or 10

        GW.Database.CallProcedure("gw_save_map_turf", {
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
    GW.Database.Cache.Turfs[mapKey] = zonesTable
    return true
end

function GW.Database.LoadTurfZones(mapName, callback)
    local mapKey = string.lower(mapName)
    if GW.Database.Cache.Turfs[mapKey] then
        if callback then callback(GW.Database.Cache.Turfs[mapKey]) end
        return GW.Database.Cache.Turfs[mapKey]
    end

    if GW.Database.UseSQLiteFallback then
        local rows = sql.Query(string.format("SELECT * FROM gw_turfs WHERE map = %s ORDER BY turf_id ASC;", sql.SQLStr(mapKey)))
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
            GW.Database.Cache.Turfs[mapKey] = zones
            if callback then callback(zones) end
            return zones
        end
        return nil
    end

    GW.Database.QueryView("v_map_turfs", "map = ? ORDER BY turf_id ASC", { mapKey }, function(rows)
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
            GW.Database.Cache.Turfs[mapKey] = zones
            if callback then callback(zones) end
        else
            if callback then callback(nil) end
        end
    end)
    return nil
end

function GW.Database.DeleteTurfZone(mapName, turfId)
    local mapKey = string.lower(mapName)
    GW.Database.CallProcedure("gw_delete_map_turf", { mapKey, tonumber(turfId) or 1 })
    if GW.Database.Cache.Turfs[mapKey] then
        GW.Database.Cache.Turfs[mapKey][turfId] = nil
    end
end

function GW.Database.SetTurfTax(mapName, turfId, taxRate)
    local mapKey = string.lower(mapName)
    local rate = tonumber(taxRate) or 10
    GW.Database.CallProcedure("gw_set_turf_tax", { mapKey, tonumber(turfId) or 1, rate })
    if GW.Database.Cache.Turfs[mapKey] and GW.Database.Cache.Turfs[mapKey][turfId] then
        GW.Database.Cache.Turfs[mapKey][turfId].tax_rate = rate
    end
end

-- ========================================================
-- 5. KEY-VALUE SETTINGS PERSISTENCE
-- ========================================================

function GW.Database.SetSetting(key, val)
    GW.Database.Cache.Settings[key] = tostring(val)
    GW.Database.CallProcedure("gw_set_setting", { key, tostring(val) })
end

function GW.Database.GetSetting(key, defaultVal)
    if GW.Database.Cache.Settings[key] ~= nil then
        return GW.Database.Cache.Settings[key]
    end
    if GW.Database.UseSQLiteFallback then
        local rows = sql.Query(string.format("SELECT val FROM gw_settings WHERE key = %s LIMIT 1;", sql.SQLStr(key)))
        if rows and rows[1] then
            GW.Database.Cache.Settings[key] = rows[1].val
            return rows[1].val
        end
    end
    return defaultVal
end

-- ========================================================
-- 6. PLAYER BUFFS & DEBUFFS PERSISTENCE
-- ========================================================

function GW.Database.GetPlayerBuffs(steamID)
    if GW.Database.Cache.Buffs[steamID] then
        return GW.Database.Cache.Buffs[steamID]
    end
    return {}
end

function GW.Database.SavePlayerBuff(steamID, buffId, duration, remaining, stacks, appliedAt, expiresAtUnix, dataStr)
    GW.Database.Cache.Buffs[steamID] = GW.Database.Cache.Buffs[steamID] or {}
    GW.Database.Cache.Buffs[steamID][buffId] = {
        buff_id = buffId,
        duration = tonumber(duration) or 0,
        remaining = tonumber(remaining) or 0,
        stacks = tonumber(stacks) or 1,
        applied_at = tonumber(appliedAt) or os.time(),
        expires_at_unix = tonumber(expiresAtUnix) or 0,
        data = tostring(dataStr or "{}")
    }

    GW.Database.CallProcedure("gw_save_player_buff", {
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

function GW.Database.DeletePlayerBuff(steamID, buffId)
    if GW.Database.Cache.Buffs[steamID] then
        GW.Database.Cache.Buffs[steamID][buffId] = nil
    end
    GW.Database.CallProcedure("gw_delete_player_buff", { steamID, buffId })
end

function GW.Database.ClearPlayerBuffs(steamID)
    GW.Database.Cache.Buffs[steamID] = {}
    GW.Database.CallProcedure("gw_clear_player_buffs", { steamID })
end

-- ========================================================
-- 7. ATOMIC PRINTER TAXED COLLECTION
-- ========================================================

function GW.Database.CollectPrinterTaxed(steamID, gangName, payout, tax)
    GW.Database.CallProcedure("gw_collect_printer_taxed", {
        steamID,
        gangName or "",
        tonumber(payout) or 0,
        tonumber(tax) or 0,
        os.time()
    })
end

-- Auto-initialize database on server startup
hook.Add("Initialize", "GW_DatabaseInit", function()
    GW.Database.Init()
end)
