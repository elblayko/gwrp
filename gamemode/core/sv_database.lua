--[[
    sv_database.lua - Exploit-Proof SQLite Engine with Prepared Statements & Canned Stored Procedures
    Author: Toxic
--]]

GW.Database = GW.Database or {}

-- ========================================================
-- PREPARED STATEMENT & SANITIZATION ENGINE
-- ========================================================

function GW.Database.SanitizeParam(val)
    if val == nil then
        return "NULL"
    elseif isnumber(val) then
        return tostring(val)
    elseif isbool(val) then
        return val and "1" or "0"
    else
        return sql.SQLStr(tostring(val))
    end
end

-- Binds parameters to '?' placeholders without regex capture side-effects
function GW.Database.Prepare(queryTemplate, params)
    params = params or {}
    local pieces = string.Explode("?", queryTemplate)
    if #pieces <= 1 then return queryTemplate end

    local out = { pieces[1] }
    for i = 1, #pieces - 1 do
        table.insert(out, GW.Database.SanitizeParam(params[i]))
        table.insert(out, pieces[i + 1])
    end
    return table.concat(out, "")
end

function GW.Database.QueryPrepared(queryTemplate, params)
    local formatted = GW.Database.Prepare(queryTemplate, params)
    local res = sql.Query(formatted)
    if res == false then
        local err = sql.LastError()
        ErrorNoHalt(string.format("[GWRP-DB ERROR] Query failed: %s\nError: %s\n", formatted, tostring(err)))
        return nil
    end
    return res
end

-- ========================================================
-- CANNED STORED PROCEDURES CATALOG
-- ========================================================

GW.Database.Procedures = {
    -- 1. Player Procedures
    GET_PLAYER = "SELECT * FROM gw_players WHERE steamid = ? LIMIT 1;",
    CREATE_PLAYER = "INSERT INTO gw_players (steamid, name, money, respect, gang, job, level, xp, last_seen) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
    UPDATE_PLAYER = "UPDATE gw_players SET name = ?, money = ?, respect = ?, gang = ?, job = ?, level = ?, xp = ?, last_seen = ? WHERE steamid = ?;",
    UPDATE_PLAYER_MONEY = "UPDATE gw_players SET money = ?, last_seen = ? WHERE steamid = ?;",
    UPDATE_PLAYER_GANG = "UPDATE gw_players SET gang = ?, last_seen = ? WHERE steamid = ?;",
    UPDATE_PLAYER_JOB = "UPDATE gw_players SET job = ?, last_seen = ? WHERE steamid = ?;",
    UPDATE_PLAYER_LEVEL_XP = "UPDATE gw_players SET level = ?, xp = ?, last_seen = ? WHERE steamid = ?;",

    -- 2. Gang Procedures
    GET_GANG = "SELECT * FROM gw_gangs WHERE name = ? LIMIT 1;",
    UPSERT_GANG = "INSERT OR REPLACE INTO gw_gangs (name, leader_steamid, bank, respect, created_at) VALUES (?, ?, COALESCE((SELECT bank FROM gw_gangs WHERE name = ?), 0), 0, ?);",
    ADD_GANG_BANK = "UPDATE gw_gangs SET bank = bank + ? WHERE name = ?;",
    DELETE_GANG = "DELETE FROM gw_gangs WHERE name = ?;",
    GET_ALL_GANGS = "SELECT * FROM gw_gangs ORDER BY respect DESC, bank DESC;",

    -- 3. Gang Member Procedures
    ADD_GANG_MEMBER = "INSERT OR REPLACE INTO gw_gang_members (steamid, gang, rank, joined_at) VALUES (?, ?, ?, ?);",
    REMOVE_GANG_MEMBER = "DELETE FROM gw_gang_members WHERE steamid = ?;",
    GET_GANG_MEMBER = "SELECT * FROM gw_gang_members WHERE steamid = ? LIMIT 1;",
    GET_GANG_MEMBERS = [[
        SELECT m.steamid, m.rank, m.joined_at, p.name, p.money, p.last_seen
        FROM gw_gang_members m
        LEFT JOIN gw_players p ON m.steamid = p.steamid
        WHERE m.gang = ?
        ORDER BY CASE m.rank WHEN 'leader' THEN 1 WHEN 'officer' THEN 2 ELSE 3 END, m.joined_at ASC;
    ]],
    CLEAR_GANG_MEMBERS = "DELETE FROM gw_gang_members WHERE gang = ?;",
    CLEAR_PLAYERS_GANG = "UPDATE gw_players SET gang = '' WHERE gang = ?;",

    -- 4. Inventory Procedures (Slot Grid Architecture)
    GET_INVENTORY = "SELECT * FROM gw_inventory WHERE steamid = ? ORDER BY bag_index ASC, slot_index ASC;",
    GET_INVENTORY_ITEM = "SELECT id, amount, bag_index, slot_index FROM gw_inventory WHERE steamid = ? AND item_id = ? LIMIT 1;",
    GET_INVENTORY_SLOT = "SELECT * FROM gw_inventory WHERE steamid = ? AND bag_index = ? AND slot_index = ? LIMIT 1;",
    INSERT_INVENTORY_ITEM = "INSERT INTO gw_inventory (steamid, bag_index, slot_index, item_id, item_type, amount, item_data) VALUES (?, ?, ?, ?, ?, ?, ?);",
    INCREMENT_INVENTORY_ITEM = "UPDATE gw_inventory SET amount = amount + ? WHERE id = ?;",
    DECREMENT_INVENTORY_ITEM = "UPDATE gw_inventory SET amount = amount - ? WHERE id = ?;",
    UPDATE_INVENTORY_SLOT_POS = "UPDATE gw_inventory SET bag_index = ?, slot_index = ? WHERE id = ?;",
    DELETE_INVENTORY_ITEM = "DELETE FROM gw_inventory WHERE id = ?;",
    GET_PLAYER_BAGS = "SELECT * FROM gw_player_bags WHERE steamid = ? LIMIT 1;",
    SET_PLAYER_BAGS = "INSERT OR REPLACE INTO gw_player_bags (steamid, bag1, bag2, bag3, bag4) VALUES (?, ?, ?, ?, ?);",

    -- 5. Turf Procedures (Per-Map)
    GET_MAP_TURFS = "SELECT * FROM gw_turfs WHERE map = ? ORDER BY turf_id ASC;",
    CLEAR_MAP_TURFS = "DELETE FROM gw_turfs WHERE map = ?;",
    INSERT_MAP_TURF = "INSERT INTO gw_turfs (map, turf_id, name, pos_x, pos_y, pos_z, radius, owner) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
    DELETE_MAP_TURF = "DELETE FROM gw_turfs WHERE map = ? AND turf_id = ?;",

    -- 6. Settings Procedures
    GET_SETTING = "SELECT val FROM gw_settings WHERE key = ? LIMIT 1;",
    SET_SETTING = "INSERT OR REPLACE INTO gw_settings (key, val) VALUES (?, ?);",

    -- 7. Player Buffs & Debuffs Procedures
    GET_PLAYER_BUFFS = "SELECT * FROM gw_player_buffs WHERE steamid = ?;",
    SAVE_PLAYER_BUFF = "INSERT OR REPLACE INTO gw_player_buffs (steamid, buff_id, duration, remaining, stacks, applied_at, expires_at_unix, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
    DELETE_PLAYER_BUFF = "DELETE FROM gw_player_buffs WHERE steamid = ? AND buff_id = ?;",
    CLEAR_PLAYER_BUFFS = "DELETE FROM gw_player_buffs WHERE steamid = ?;"
}

function GW.Database.Call(procedureName, params)
    local qTemplate = GW.Database.Procedures[procedureName]
    if not qTemplate then
        error("[GWRP-DB] Attempted to call undefined stored procedure: " .. tostring(procedureName), 2)
        return nil
    end
    return GW.Database.QueryPrepared(qTemplate, params)
end

-- ========================================================
-- ATOMIC TRANSACTION WRAPPERS & ACID ENGINE
-- ========================================================

GW.Database.TransactionDepth = GW.Database.TransactionDepth or 0

function GW.Database.BeginTransaction()
    if GW.Database.TransactionDepth == 0 then
        sql.Query("BEGIN IMMEDIATE TRANSACTION;")
    end
    GW.Database.TransactionDepth = GW.Database.TransactionDepth + 1
    return true
end

function GW.Database.CommitTransaction()
    if GW.Database.TransactionDepth <= 0 then
        GW.Database.TransactionDepth = 0
        return false
    end
    GW.Database.TransactionDepth = GW.Database.TransactionDepth - 1
    if GW.Database.TransactionDepth == 0 then
        return sql.Query("COMMIT;")
    end
    return true
end

function GW.Database.RollbackTransaction()
    GW.Database.TransactionDepth = 0
    return sql.Query("ROLLBACK;")
end

-- Safely executes a function inside an atomic transaction with automatic rollback on error
function GW.Database.WithTransaction(callback)
    GW.Database.BeginTransaction()
    local success, res1, res2 = pcall(callback)
    if not success then
        GW.Database.RollbackTransaction()
        ErrorNoHalt(string.format("[GWRP-DB ACID ERROR] Transaction rolled back due to error: %s\n", tostring(res1)))
        return false, res1
    end
    GW.Database.CommitTransaction()
    return res1, res2
end

-- ========================================================
-- SCHEMA INITIALIZATION
-- ========================================================

function GW.Database.Init()
    -- Enable Foreign Key Relational Integrity & Durability Pragmas (ACID)
    sql.Query("PRAGMA foreign_keys = ON;")
    sql.Query("PRAGMA synchronous = NORMAL;")

    -- 1. Players Table
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gw_players (
            steamid TEXT PRIMARY KEY,
            name TEXT,
            money INTEGER DEFAULT 1000 CHECK (money >= 0),
            respect INTEGER DEFAULT 0,
            gang TEXT DEFAULT '',
            job TEXT DEFAULT 'citizen',
            level INTEGER DEFAULT 1 CHECK (level >= 1),
            xp INTEGER DEFAULT 0 CHECK (xp >= 0),
            last_seen INTEGER
        );
    ]])

    -- Automatic migration for existing player columns (level, xp)
    local playerCols = sql.Query("PRAGMA table_info(gw_players);") or {}
    local hasLevelCol = false
    local hasXPCol = false
    for _, col in ipairs(playerCols) do
        if col.name == "level" then hasLevelCol = true end
        if col.name == "xp" then hasXPCol = true end
    end
    if not hasLevelCol then sql.Query("ALTER TABLE gw_players ADD COLUMN level INTEGER DEFAULT 1;") end
    if not hasXPCol then sql.Query("ALTER TABLE gw_players ADD COLUMN xp INTEGER DEFAULT 0;") end

    -- 2. Gangs Table
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gw_gangs (
            name TEXT PRIMARY KEY,
            leader_steamid TEXT,
            bank INTEGER DEFAULT 0 CHECK (bank >= 0),
            respect INTEGER DEFAULT 0,
            created_at INTEGER
        );
    ]])

    -- 3. Gang Members Table
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gw_gang_members (
            steamid TEXT PRIMARY KEY,
            gang TEXT,
            rank TEXT DEFAULT 'member',
            joined_at INTEGER
        );
    ]])

    -- 4. Player Inventory Table (Slot Grid Architecture)
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gw_inventory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            steamid TEXT,
            bag_index INTEGER DEFAULT 0 CHECK (bag_index >= 0),
            slot_index INTEGER DEFAULT 1 CHECK (slot_index >= 1),
            item_id TEXT,
            item_type TEXT,
            amount INTEGER DEFAULT 1 CHECK (amount > 0),
            item_data TEXT DEFAULT '{}'
        );
    ]])

    -- Automatic migration for existing columns
    local invCols = sql.Query("PRAGMA table_info(gw_inventory);") or {}
    local hasBagCol = false
    local hasSlotCol = false
    for _, col in ipairs(invCols) do
        if col.name == "bag_index" then hasBagCol = true end
        if col.name == "slot_index" then hasSlotCol = true end
    end
    if not hasBagCol then sql.Query("ALTER TABLE gw_inventory ADD COLUMN bag_index INTEGER DEFAULT 0;") end
    if not hasSlotCol then sql.Query("ALTER TABLE gw_inventory ADD COLUMN slot_index INTEGER DEFAULT 1;") end

    -- 5. Equipable Bag Containers Table (Backpack is Bag 0, 4 Equipable Bag Slots 1..4)
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gw_player_bags (
            steamid TEXT PRIMARY KEY,
            bag1 TEXT DEFAULT '',
            bag2 TEXT DEFAULT '',
            bag3 TEXT DEFAULT '',
            bag4 TEXT DEFAULT ''
        );
    ]])

    -- 6. Turf Zones Table
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gw_turfs (
            map TEXT,
            turf_id INTEGER,
            name TEXT,
            pos_x REAL,
            pos_y REAL,
            pos_z REAL,
            radius INTEGER,
            owner TEXT DEFAULT 'neutral',
            PRIMARY KEY (map, turf_id)
        );
    ]])

    -- 6. Global Key-Value Settings Table
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gw_settings (
            key TEXT PRIMARY KEY,
            val TEXT
        );
    ]])

    -- 7. Player Buffs & Debuffs Table
    sql.Query([[
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
    ]])

    -- Column migrations for existing databases
    sql.Query("ALTER TABLE gw_players ADD COLUMN gang TEXT DEFAULT ''")
    sql.Query("ALTER TABLE gw_players ADD COLUMN job TEXT DEFAULT 'citizen'")
    sql.Query("ALTER TABLE gw_players ADD COLUMN respect INTEGER DEFAULT 0")

    print("[GWRP-DB] SQLite Engine initialized with parameterized stored procedures.")
end

-- ========================================================
-- 1. PLAYER PERSISTENCE OPERATIONS
-- ========================================================

function GW.Database.LoadPlayer(ply, callback)
    local steamID = ply:SteamID()
    local query = GW.Database.Call("GET_PLAYER", { steamID })

    local playerData = {}
    if query and query[1] then
        playerData = query[1]
        ply:SetNWInt("GW_Money", tonumber(playerData.money) or GW.Config.StartingMoney)
        ply:SetNWInt("GW_Respect", tonumber(playerData.respect) or 0)
        ply:SetNWString("GW_Gang", playerData.gang or "")
        ply:SetNWString("GW_Job", (playerData.job and playerData.job ~= "") and playerData.job or "citizen")
        ply:SetNWInt("GW_Level", math.max(1, tonumber(playerData.level) or 1))
        ply:SetNWInt("GW_XP", math.max(0, tonumber(playerData.xp) or 0))
    else
        local initialMoney = GW.Config.StartingMoney or 1000
        GW.Database.Call("CREATE_PLAYER", {
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
        playerData = { money = initialMoney, respect = 0, gang = "", job = "citizen", level = 1, xp = 0 }
    end

    if ply:GetGang() ~= "" then
        local memberInfo = GW.Database.GetGangMember(steamID)
        if memberInfo and memberInfo.rank == "leader" then
            ply:SetNWBool("GW_IsGangLeader", true)
        end
    end

    ply.GW_DataLoaded = true
    if callback then callback(playerData) end
end

function GW.Database.SavePlayer(ply)
    if not IsValid(ply) or not ply.GW_DataLoaded then return end
    GW.Database.Call("UPDATE_PLAYER", {
        ply:Nick(),
        ply:GetMoney(),
        ply:GetNWInt("GW_Respect", 0),
        ply:GetGang(),
        ply:GetJob(),
        ply:GetNWInt("GW_Level", 1),
        ply:GetNWInt("GW_XP", 0),
        os.time(),
        ply:SteamID()
    })
end

function GW.Database.SavePlayerLevelXP(ply, level, xp)
    if not IsValid(ply) or not ply.GW_DataLoaded then return end
    GW.Database.Call("UPDATE_PLAYER_LEVEL_XP", {
        math.max(1, tonumber(level) or 1),
        math.max(0, tonumber(xp) or 0),
        os.time(),
        ply:SteamID()
    })
end

function GW.Database.SavePlayerMoney(ply, amount)
    if not IsValid(ply) or not ply.GW_DataLoaded then return end
    GW.Database.Call("UPDATE_PLAYER_MONEY", {
        amount,
        os.time(),
        ply:SteamID()
    })
end

function GW.Database.SavePlayerGang(ply, gangName)
    if not IsValid(ply) or not ply.GW_DataLoaded then return end
    GW.Database.Call("UPDATE_PLAYER_GANG", {
        gangName,
        os.time(),
        ply:SteamID()
    })
end

function GW.Database.SavePlayerJob(ply, jobId)
    if not IsValid(ply) or not ply.GW_DataLoaded then return end
    GW.Database.Call("UPDATE_PLAYER_JOB", {
        jobId,
        os.time(),
        ply:SteamID()
    })
end

-- ========================================================
-- 2. GANG & MEMBER ROSTER PERSISTENCE
-- ========================================================

function GW.Database.CreateGang(gangName, leaderSteamID)
    return GW.Database.WithTransaction(function()
        GW.Database.Call("UPSERT_GANG", {
            gangName,
            leaderSteamID,
            gangName,
            os.time()
        })

        GW.Database.AddGangMember(leaderSteamID, gangName, "leader")
        print(string.format("[GWRP-DB] Gang '%s' created via stored procedure (Leader: %s).", gangName, leaderSteamID))
        return true
    end)
end

function GW.Database.GetGang(gangName)
    local query = GW.Database.Call("GET_GANG", { gangName })
    if query and query[1] then
        return query[1]
    end
    return nil
end

function GW.Database.AddGangMember(steamID, gangName, rank)
    return GW.Database.WithTransaction(function()
        GW.Database.Call("ADD_GANG_MEMBER", {
            steamID,
            gangName,
            rank or "member",
            os.time()
        })

        GW.Database.Call("UPDATE_PLAYER_GANG", {
            gangName,
            os.time(),
            steamID
        })
        return true
    end)
end

function GW.Database.RemoveGangMember(steamID)
    return GW.Database.WithTransaction(function()
        GW.Database.Call("REMOVE_GANG_MEMBER", { steamID })
        GW.Database.Call("UPDATE_PLAYER_GANG", {
            "",
            os.time(),
            steamID
        })
        return true
    end)
end

function GW.Database.GetGangMember(steamID)
    local query = GW.Database.Call("GET_GANG_MEMBER", { steamID })
    if query and query[1] then
        return query[1]
    end
    return nil
end

function GW.Database.GetGangMembers(gangName)
    return GW.Database.Call("GET_GANG_MEMBERS", { gangName }) or {}
end

function GW.Database.AddGangBank(gangName, amount)
    GW.Database.Call("ADD_GANG_BANK", { amount, gangName })
end

function GW.Database.DisbandGang(gangName)
    return GW.Database.WithTransaction(function()
        GW.Database.Call("DELETE_GANG", { gangName })
        GW.Database.Call("CLEAR_GANG_MEMBERS", { gangName })
        GW.Database.Call("CLEAR_PLAYERS_GANG", { gangName })
        print(string.format("[GWRP-DB] Gang '%s' disbanded via stored procedure.", gangName))
        return true
    end)
end

function GW.Database.GetAllGangs()
    return GW.Database.Call("GET_ALL_GANGS", {}) or {}
end

-- ========================================================
-- 3. PLAYER INVENTORY PERSISTENCE (SLOTS & BAGS)
-- ========================================================

GW.Inventory = GW.Inventory or {}

function GW.Database.GetInventory(steamID)
    return GW.Database.Call("GET_INVENTORY", { steamID }) or {}
end

function GW.Database.GetInventorySlot(steamID, bagIndex, slotIndex)
    local rows = GW.Database.Call("GET_INVENTORY_SLOT", { steamID, bagIndex or 0, slotIndex or 1 })
    return rows and rows[1] or nil
end

function GW.Database.GetPlayerBags(steamID)
    local rows = GW.Database.Call("GET_PLAYER_BAGS", { steamID })
    if rows and rows[1] then
        return rows[1]
    end
    return { bag1 = "", bag2 = "", bag3 = "", bag4 = "" }
end

function GW.Database.SetPlayerBags(steamID, bag1, bag2, bag3, bag4)
    GW.Database.Call("SET_PLAYER_BAGS", {
        steamID,
        bag1 or "",
        bag2 or "",
        bag3 or "",
        bag4 or ""
    })
end

function GW.Database.AddInventoryItem(steamID, itemId, itemType, amount, itemData, targetBag, targetSlot)
    return GW.Database.WithTransaction(function()
        amount = amount or 1
        local iType = itemType or "generic"
        local iData = type(itemData) == "table" and util.TableToJSON(itemData) or (itemData or "{}")

        -- If target slot is explicitly provided and empty:
        if targetBag and targetSlot then
            local slotOccupant = GW.Database.GetInventorySlot(steamID, targetBag, targetSlot)
            if not slotOccupant then
                GW.Database.Call("INSERT_INVENTORY_ITEM", { steamID, targetBag, targetSlot, itemId, iType, amount, iData })
                return true
            end
        end

        -- First: check if an identical stack exists and can be incremented
        local existing = GW.Database.Call("GET_INVENTORY_ITEM", { steamID, itemId })
        if existing and existing[1] then
            local rowId = tonumber(existing[1].id)
            GW.Database.Call("INCREMENT_INVENTORY_ITEM", { amount, rowId })
            return true
        end

        -- Otherwise, find first available slot in equipped bags (Bag 0: slots 1..16, Bags 1..4: slots 1..capacity)
        local allItems = GW.Database.GetInventory(steamID)
        local occupied = {}
        for _, it in ipairs(allItems) do
            local b = tonumber(it.bag_index) or 0
            local s = tonumber(it.slot_index) or 1
            occupied[b .. "_" .. s] = true
        end

        local playerBags = GW.Database.GetPlayerBags(steamID)
        local getCap = GW.Inventory.GetBagCapacity or function() return 0 end
        local bagCapacities = {
            [0] = 16, -- Default Backpack
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
            GW.Database.Call("INSERT_INVENTORY_ITEM", { steamID, freeBag, freeSlot, itemId, iType, amount, iData })
            return true
        end

        return false -- Bags are completely full!
    end)
end

function GW.Database.MoveInventorySlot(steamID, fromBag, fromSlot, toBag, toSlot)
    return GW.Database.WithTransaction(function()
        local sourceItem = GW.Database.GetInventorySlot(steamID, fromBag, fromSlot)
        if not sourceItem then return false end

        local destItem = GW.Database.GetInventorySlot(steamID, toBag, toSlot)
        if not destItem then
            -- Empty destination slot: direct move
            GW.Database.Call("UPDATE_INVENTORY_SLOT_POS", { toBag, toSlot, tonumber(sourceItem.id) })
            return true
        else
            -- If same item ID and stackable: combine stacks
            if sourceItem.item_id == destItem.item_id then
                GW.Database.Call("INCREMENT_INVENTORY_ITEM", { tonumber(sourceItem.amount) or 1, tonumber(destItem.id) })
                GW.Database.Call("DELETE_INVENTORY_ITEM", { tonumber(sourceItem.id) })
                return true
            else
                -- Swap slots
                GW.Database.Call("UPDATE_INVENTORY_SLOT_POS", { toBag, toSlot, tonumber(sourceItem.id) })
                GW.Database.Call("UPDATE_INVENTORY_SLOT_POS", { fromBag, fromSlot, tonumber(destItem.id) })
                return true
            end
        end
    end)
end

function GW.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, amount)
    amount = amount or 1
    local row = GW.Database.GetInventorySlot(steamID, bagIndex, slotIndex)
    if not row then return false end

    local rowId = tonumber(row.id)
    local curAmount = tonumber(row.amount) or 1
    if curAmount <= amount then
        GW.Database.Call("DELETE_INVENTORY_ITEM", { rowId })
    else
        GW.Database.Call("DECREMENT_INVENTORY_ITEM", { amount, rowId })
    end
    return true
end

function GW.Database.RemoveInventoryItem(steamID, itemId, amount)
    amount = amount or 1
    local existing = GW.Database.Call("GET_INVENTORY_ITEM", { steamID, itemId })

    if existing and existing[1] then
        local rowId = tonumber(existing[1].id)
        local curAmount = tonumber(existing[1].amount) or 1
        if curAmount <= amount then
            GW.Database.Call("DELETE_INVENTORY_ITEM", { rowId })
        else
            GW.Database.Call("DECREMENT_INVENTORY_ITEM", { amount, rowId })
        end
        return true
    end
    return false
end

function GW.Database.HasInventoryItem(steamID, itemId, amount)
    amount = amount or 1
    local query = GW.Database.Call("GET_INVENTORY_ITEM", { steamID, itemId })
    if query and query[1] then
        return (tonumber(query[1].amount) or 0) >= amount
    end
    return false
end

-- ========================================================
-- 4. TURF ZONES PERSISTENCE (PER-MAP)
-- ========================================================

function GW.Database.SaveTurfZones(mapName, zonesTable)
    local mapKey = string.lower(mapName)
    return GW.Database.WithTransaction(function()
        GW.Database.Call("CLEAR_MAP_TURFS", { mapKey })

        for id, zone in pairs(zonesTable) do
            local idNum = tonumber(id) or 1
            local name = zone.name or ("Turf #" .. idNum)
            local px = zone.pos and zone.pos.x or 0
            local py = zone.pos and zone.pos.y or 0
            local pz = zone.pos and zone.pos.z or 0
            local radius = tonumber(zone.radius) or 450
            local owner = zone.owner or "neutral"

            GW.Database.Call("INSERT_MAP_TURF", {
                mapKey,
                idNum,
                name,
                px,
                py,
                pz,
                radius,
                owner
            })
        end
        print(string.format("[GWRP-DB] Committed %d turf zones via atomic transaction for map '%s'.", table.Count(zonesTable), mapName))
        return true
    end)
end

function GW.Database.LoadTurfZones(mapName)
    local mapKey = string.lower(mapName)
    local rows = GW.Database.Call("GET_MAP_TURFS", { mapKey })
    if not rows or #rows == 0 then return nil end

    local zones = {}
    for _, row in ipairs(rows) do
        local id = tonumber(row.turf_id)
        zones[id] = {
            id = id,
            name = row.name,
            pos = Vector(tonumber(row.pos_x), tonumber(row.pos_y), tonumber(row.pos_z)),
            radius = tonumber(row.radius) or 450,
            owner = row.owner or "neutral",
            progress = 100
        }
    end
    return zones
end

function GW.Database.DeleteTurfZone(mapName, turfId)
    GW.Database.Call("DELETE_MAP_TURF", { string.lower(mapName), turfId })
end

-- ========================================================
-- 5. KEY-VALUE SETTINGS PERSISTENCE
-- ========================================================

function GW.Database.SetSetting(key, val)
    GW.Database.Call("SET_SETTING", { key, tostring(val) })
end

function GW.Database.GetSetting(key, defaultVal)
    local query = GW.Database.Call("GET_SETTING", { key })
    if query and query[1] then
        return query[1].val
    end
    return defaultVal
end

-- ========================================================
-- 6. PLAYER BUFFS & DEBUFFS PERSISTENCE
-- ========================================================

function GW.Database.GetPlayerBuffs(steamID)
    return GW.Database.Call("GET_PLAYER_BUFFS", { steamID }) or {}
end

function GW.Database.SavePlayerBuff(steamID, buffId, duration, remaining, stacks, appliedAt, expiresAtUnix, dataStr)
    return GW.Database.Call("SAVE_PLAYER_BUFF", {
        steamID,
        buffId,
        tonumber(duration) or 0,
        tonumber(remaining) or 0,
        tonumber(stacks) or 1,
        tonumber(appliedAt) or os.time(),
        tonumber(expiresAtUnix) or 0,
        tostring(dataStr or "{}")
    })
end

function GW.Database.DeletePlayerBuff(steamID, buffId)
    return GW.Database.Call("DELETE_PLAYER_BUFF", { steamID, buffId })
end

function GW.Database.ClearPlayerBuffs(steamID)
    return GW.Database.Call("CLEAR_PLAYER_BUFFS", { steamID })
end
