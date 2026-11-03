--[[
    sv_database.lua - Exploit-Proof SQLite Engine with Prepared Statements & Canned Stored Procedures
    Author: Toxic
--]]

GWRP.Database = GWRP.Database or {}

-- ========================================================
-- PREPARED STATEMENT & SANITIZATION ENGINE
-- ========================================================

function GWRP.Database.SanitizeParam(val)
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
function GWRP.Database.Prepare(queryTemplate, params)
    params = params or {}
    local pieces = string.Explode("?", queryTemplate)
    if #pieces <= 1 then return queryTemplate end

    local out = { pieces[1] }
    for i = 1, #pieces - 1 do
        table.insert(out, GWRP.Database.SanitizeParam(params[i]))
        table.insert(out, pieces[i + 1])
    end
    return table.concat(out, "")
end

function GWRP.Database.QueryPrepared(queryTemplate, params)
    local formatted = GWRP.Database.Prepare(queryTemplate, params)
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

GWRP.Database.Procedures = {
    -- 1. Player Procedures
    GET_PLAYER = "SELECT * FROM gwrp_players WHERE steamid = ? LIMIT 1;",
    CREATE_PLAYER = "INSERT INTO gwrp_players (steamid, name, money, respect, gang, job, level, xp, last_seen) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
    UPDATE_PLAYER = "UPDATE gwrp_players SET name = ?, money = ?, respect = ?, gang = ?, job = ?, level = ?, xp = ?, last_seen = ? WHERE steamid = ?;",
    UPDATE_PLAYER_MONEY = "UPDATE gwrp_players SET money = ?, last_seen = ? WHERE steamid = ?;",
    UPDATE_PLAYER_GANG = "UPDATE gwrp_players SET gang = ?, last_seen = ? WHERE steamid = ?;",
    UPDATE_PLAYER_JOB = "UPDATE gwrp_players SET job = ?, last_seen = ? WHERE steamid = ?;",
    UPDATE_PLAYER_LEVEL_XP = "UPDATE gwrp_players SET level = ?, xp = ?, last_seen = ? WHERE steamid = ?;",

    -- 2. Gang Procedures
    GET_GANG = "SELECT * FROM gwrp_gangs WHERE name = ? LIMIT 1;",
    UPSERT_GANG = "INSERT OR REPLACE INTO gwrp_gangs (name, leader_steamid, bank, respect, created_at) VALUES (?, ?, COALESCE((SELECT bank FROM gwrp_gangs WHERE name = ?), 0), 0, ?);",
    ADD_GANG_BANK = "UPDATE gwrp_gangs SET bank = bank + ? WHERE name = ?;",
    DELETE_GANG = "DELETE FROM gwrp_gangs WHERE name = ?;",
    GET_ALL_GANGS = "SELECT * FROM gwrp_gangs ORDER BY respect DESC, bank DESC;",

    -- 3. Gang Member Procedures
    ADD_GANG_MEMBER = "INSERT OR REPLACE INTO gwrp_gang_members (steamid, gang, rank, joined_at) VALUES (?, ?, ?, ?);",
    REMOVE_GANG_MEMBER = "DELETE FROM gwrp_gang_members WHERE steamid = ?;",
    GET_GANG_MEMBER = "SELECT * FROM gwrp_gang_members WHERE steamid = ? LIMIT 1;",
    GET_GANG_MEMBERS = [[
        SELECT m.steamid, m.rank, m.joined_at, p.name, p.money, p.last_seen
        FROM gwrp_gang_members m
        LEFT JOIN gwrp_players p ON m.steamid = p.steamid
        WHERE m.gang = ?
        ORDER BY CASE m.rank WHEN 'leader' THEN 1 WHEN 'officer' THEN 2 ELSE 3 END, m.joined_at ASC;
    ]],
    CLEAR_GANG_MEMBERS = "DELETE FROM gwrp_gang_members WHERE gang = ?;",
    CLEAR_PLAYERS_GANG = "UPDATE gwrp_players SET gang = '' WHERE gang = ?;",

    -- 4. Inventory Procedures (Slot Grid Architecture)
    GET_INVENTORY = "SELECT * FROM gwrp_inventory WHERE steamid = ? ORDER BY bag_index ASC, slot_index ASC;",
    GET_INVENTORY_ITEM = "SELECT id, amount, bag_index, slot_index FROM gwrp_inventory WHERE steamid = ? AND item_id = ? LIMIT 1;",
    GET_INVENTORY_SLOT = "SELECT * FROM gwrp_inventory WHERE steamid = ? AND bag_index = ? AND slot_index = ? LIMIT 1;",
    INSERT_INVENTORY_ITEM = "INSERT INTO gwrp_inventory (steamid, bag_index, slot_index, item_id, item_type, amount, item_data) VALUES (?, ?, ?, ?, ?, ?, ?);",
    INCREMENT_INVENTORY_ITEM = "UPDATE gwrp_inventory SET amount = amount + ? WHERE id = ?;",
    DECREMENT_INVENTORY_ITEM = "UPDATE gwrp_inventory SET amount = amount - ? WHERE id = ?;",
    UPDATE_INVENTORY_SLOT_POS = "UPDATE gwrp_inventory SET bag_index = ?, slot_index = ? WHERE id = ?;",
    DELETE_INVENTORY_ITEM = "DELETE FROM gwrp_inventory WHERE id = ?;",
    GET_PLAYER_BAGS = "SELECT * FROM gwrp_player_bags WHERE steamid = ? LIMIT 1;",
    SET_PLAYER_BAGS = "INSERT OR REPLACE INTO gwrp_player_bags (steamid, bag1, bag2, bag3, bag4) VALUES (?, ?, ?, ?, ?);",

    -- 5. Turf Procedures (Per-Map)
    GET_MAP_TURFS = "SELECT * FROM gwrp_turfs WHERE map = ? ORDER BY turf_id ASC;",
    CLEAR_MAP_TURFS = "DELETE FROM gwrp_turfs WHERE map = ?;",
    INSERT_MAP_TURF = "INSERT INTO gwrp_turfs (map, turf_id, name, pos_x, pos_y, pos_z, radius, owner) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
    DELETE_MAP_TURF = "DELETE FROM gwrp_turfs WHERE map = ? AND turf_id = ?;",

    -- 6. Settings Procedures
    GET_SETTING = "SELECT val FROM gwrp_settings WHERE key = ? LIMIT 1;",
    SET_SETTING = "INSERT OR REPLACE INTO gwrp_settings (key, val) VALUES (?, ?);",

    -- 7. Player Buffs & Debuffs Procedures
    GET_PLAYER_BUFFS = "SELECT * FROM gwrp_player_buffs WHERE steamid = ?;",
    SAVE_PLAYER_BUFF = "INSERT OR REPLACE INTO gwrp_player_buffs (steamid, buff_id, duration, remaining, stacks, applied_at, expires_at_unix, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
    DELETE_PLAYER_BUFF = "DELETE FROM gwrp_player_buffs WHERE steamid = ? AND buff_id = ?;",
    CLEAR_PLAYER_BUFFS = "DELETE FROM gwrp_player_buffs WHERE steamid = ?;"
}

function GWRP.Database.Call(procedureName, params)
    local qTemplate = GWRP.Database.Procedures[procedureName]
    if not qTemplate then
        error("[GWRP-DB] Attempted to call undefined stored procedure: " .. tostring(procedureName), 2)
        return nil
    end
    return GWRP.Database.QueryPrepared(qTemplate, params)
end

-- ========================================================
-- ATOMIC TRANSACTION WRAPPERS & ACID ENGINE
-- ========================================================

GWRP.Database.TransactionDepth = GWRP.Database.TransactionDepth or 0

function GWRP.Database.BeginTransaction()
    if GWRP.Database.TransactionDepth == 0 then
        sql.Query("BEGIN IMMEDIATE TRANSACTION;")
    end
    GWRP.Database.TransactionDepth = GWRP.Database.TransactionDepth + 1
    return true
end

function GWRP.Database.CommitTransaction()
    if GWRP.Database.TransactionDepth <= 0 then
        GWRP.Database.TransactionDepth = 0
        return false
    end
    GWRP.Database.TransactionDepth = GWRP.Database.TransactionDepth - 1
    if GWRP.Database.TransactionDepth == 0 then
        return sql.Query("COMMIT;")
    end
    return true
end

function GWRP.Database.RollbackTransaction()
    GWRP.Database.TransactionDepth = 0
    return sql.Query("ROLLBACK;")
end

-- Safely executes a function inside an atomic transaction with automatic rollback on error
function GWRP.Database.WithTransaction(callback)
    GWRP.Database.BeginTransaction()
    local success, res1, res2 = pcall(callback)
    if not success then
        GWRP.Database.RollbackTransaction()
        ErrorNoHalt(string.format("[GWRP-DB ACID ERROR] Transaction rolled back due to error: %s\n", tostring(res1)))
        return false, res1
    end
    GWRP.Database.CommitTransaction()
    return res1, res2
end

-- ========================================================
-- SCHEMA INITIALIZATION
-- ========================================================

function GWRP.Database.Init()
    -- Enable Foreign Key Relational Integrity & Durability Pragmas (ACID)
    sql.Query("PRAGMA foreign_keys = ON;")
    sql.Query("PRAGMA synchronous = NORMAL;")

    -- 1. Players Table
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gwrp_players (
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
    local playerCols = sql.Query("PRAGMA table_info(gwrp_players);") or {}
    local hasLevelCol = false
    local hasXPCol = false
    for _, col in ipairs(playerCols) do
        if col.name == "level" then hasLevelCol = true end
        if col.name == "xp" then hasXPCol = true end
    end
    if not hasLevelCol then sql.Query("ALTER TABLE gwrp_players ADD COLUMN level INTEGER DEFAULT 1;") end
    if not hasXPCol then sql.Query("ALTER TABLE gwrp_players ADD COLUMN xp INTEGER DEFAULT 0;") end

    -- 2. Gangs Table
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gwrp_gangs (
            name TEXT PRIMARY KEY,
            leader_steamid TEXT,
            bank INTEGER DEFAULT 0 CHECK (bank >= 0),
            respect INTEGER DEFAULT 0,
            created_at INTEGER
        );
    ]])

    -- 3. Gang Members Table
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gwrp_gang_members (
            steamid TEXT PRIMARY KEY,
            gang TEXT,
            rank TEXT DEFAULT 'member',
            joined_at INTEGER
        );
    ]])

    -- 4. Player Inventory Table (Slot Grid Architecture)
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gwrp_inventory (
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
    local invCols = sql.Query("PRAGMA table_info(gwrp_inventory);") or {}
    local hasBagCol = false
    local hasSlotCol = false
    for _, col in ipairs(invCols) do
        if col.name == "bag_index" then hasBagCol = true end
        if col.name == "slot_index" then hasSlotCol = true end
    end
    if not hasBagCol then sql.Query("ALTER TABLE gwrp_inventory ADD COLUMN bag_index INTEGER DEFAULT 0;") end
    if not hasSlotCol then sql.Query("ALTER TABLE gwrp_inventory ADD COLUMN slot_index INTEGER DEFAULT 1;") end

    -- 5. Equipable Bag Containers Table (Backpack is Bag 0, 4 Equipable Bag Slots 1..4)
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gwrp_player_bags (
            steamid TEXT PRIMARY KEY,
            bag1 TEXT DEFAULT '',
            bag2 TEXT DEFAULT '',
            bag3 TEXT DEFAULT '',
            bag4 TEXT DEFAULT ''
        );
    ]])

    -- 6. Turf Zones Table
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gwrp_turfs (
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
        CREATE TABLE IF NOT EXISTS gwrp_settings (
            key TEXT PRIMARY KEY,
            val TEXT
        );
    ]])

    -- 7. Player Buffs & Debuffs Table
    sql.Query([[
        CREATE TABLE IF NOT EXISTS gwrp_player_buffs (
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
    sql.Query("ALTER TABLE gwrp_players ADD COLUMN gang TEXT DEFAULT ''")
    sql.Query("ALTER TABLE gwrp_players ADD COLUMN job TEXT DEFAULT 'citizen'")
    sql.Query("ALTER TABLE gwrp_players ADD COLUMN respect INTEGER DEFAULT 0")

    print("[GWRP-DB] SQLite Engine initialized with parameterized stored procedures.")
end

-- ========================================================
-- 1. PLAYER PERSISTENCE OPERATIONS
-- ========================================================

function GWRP.Database.LoadPlayer(ply, callback)
    local steamID = ply:SteamID()
    local query = GWRP.Database.Call("GET_PLAYER", { steamID })

    local playerData = {}
    if query and query[1] then
        playerData = query[1]
        ply:SetNWInt("GWRP_Money", tonumber(playerData.money) or GWRP.Config.StartingMoney)
        ply:SetNWInt("GWRP_Respect", tonumber(playerData.respect) or 0)
        ply:SetNWString("GWRP_Gang", playerData.gang or "")
        ply:SetNWString("GWRP_Job", (playerData.job and playerData.job ~= "") and playerData.job or "citizen")
        ply:SetNWInt("GWRP_Level", math.max(1, tonumber(playerData.level) or 1))
        ply:SetNWInt("GWRP_XP", math.max(0, tonumber(playerData.xp) or 0))
    else
        local initialMoney = GWRP.Config.StartingMoney or 1000
        GWRP.Database.Call("CREATE_PLAYER", {
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

        ply:SetNWInt("GWRP_Money", initialMoney)
        ply:SetNWInt("GWRP_Respect", 0)
        ply:SetNWString("GWRP_Gang", "")
        ply:SetNWString("GWRP_Job", "citizen")
        ply:SetNWInt("GWRP_Level", 1)
        ply:SetNWInt("GWRP_XP", 0)
        playerData = { money = initialMoney, respect = 0, gang = "", job = "citizen", level = 1, xp = 0 }
    end

    if ply:GetGang() ~= "" then
        local memberInfo = GWRP.Database.GetGangMember(steamID)
        if memberInfo and memberInfo.rank == "leader" then
            ply:SetNWBool("GWRP_IsGangLeader", true)
        end
    end

    ply.GWRP_DataLoaded = true
    if callback then callback(playerData) end
end

function GWRP.Database.SavePlayer(ply)
    if not IsValid(ply) or not ply.GWRP_DataLoaded then return end
    GWRP.Database.Call("UPDATE_PLAYER", {
        ply:Nick(),
        ply:GetMoney(),
        ply:GetNWInt("GWRP_Respect", 0),
        ply:GetGang(),
        ply:GetJob(),
        ply:GetNWInt("GWRP_Level", 1),
        ply:GetNWInt("GWRP_XP", 0),
        os.time(),
        ply:SteamID()
    })
end

function GWRP.Database.SavePlayerLevelXP(ply, level, xp)
    if not IsValid(ply) or not ply.GWRP_DataLoaded then return end
    GWRP.Database.Call("UPDATE_PLAYER_LEVEL_XP", {
        math.max(1, tonumber(level) or 1),
        math.max(0, tonumber(xp) or 0),
        os.time(),
        ply:SteamID()
    })
end

function GWRP.Database.SavePlayerMoney(ply, amount)
    if not IsValid(ply) or not ply.GWRP_DataLoaded then return end
    GWRP.Database.Call("UPDATE_PLAYER_MONEY", {
        amount,
        os.time(),
        ply:SteamID()
    })
end

function GWRP.Database.SavePlayerGang(ply, gangName)
    if not IsValid(ply) or not ply.GWRP_DataLoaded then return end
    GWRP.Database.Call("UPDATE_PLAYER_GANG", {
        gangName,
        os.time(),
        ply:SteamID()
    })
end

function GWRP.Database.SavePlayerJob(ply, jobId)
    if not IsValid(ply) or not ply.GWRP_DataLoaded then return end
    GWRP.Database.Call("UPDATE_PLAYER_JOB", {
        jobId,
        os.time(),
        ply:SteamID()
    })
end

-- ========================================================
-- 2. GANG & MEMBER ROSTER PERSISTENCE
-- ========================================================

function GWRP.Database.CreateGang(gangName, leaderSteamID)
    return GWRP.Database.WithTransaction(function()
        GWRP.Database.Call("UPSERT_GANG", {
            gangName,
            leaderSteamID,
            gangName,
            os.time()
        })

        GWRP.Database.AddGangMember(leaderSteamID, gangName, "leader")
        print(string.format("[GWRP-DB] Gang '%s' created via stored procedure (Leader: %s).", gangName, leaderSteamID))
        return true
    end)
end

function GWRP.Database.GetGang(gangName)
    local query = GWRP.Database.Call("GET_GANG", { gangName })
    if query and query[1] then
        return query[1]
    end
    return nil
end

function GWRP.Database.AddGangMember(steamID, gangName, rank)
    return GWRP.Database.WithTransaction(function()
        GWRP.Database.Call("ADD_GANG_MEMBER", {
            steamID,
            gangName,
            rank or "member",
            os.time()
        })

        GWRP.Database.Call("UPDATE_PLAYER_GANG", {
            gangName,
            os.time(),
            steamID
        })
        return true
    end)
end

function GWRP.Database.RemoveGangMember(steamID)
    return GWRP.Database.WithTransaction(function()
        GWRP.Database.Call("REMOVE_GANG_MEMBER", { steamID })
        GWRP.Database.Call("UPDATE_PLAYER_GANG", {
            "",
            os.time(),
            steamID
        })
        return true
    end)
end

function GWRP.Database.GetGangMember(steamID)
    local query = GWRP.Database.Call("GET_GANG_MEMBER", { steamID })
    if query and query[1] then
        return query[1]
    end
    return nil
end

function GWRP.Database.GetGangMembers(gangName)
    return GWRP.Database.Call("GET_GANG_MEMBERS", { gangName }) or {}
end

function GWRP.Database.AddGangBank(gangName, amount)
    GWRP.Database.Call("ADD_GANG_BANK", { amount, gangName })
end

function GWRP.Database.DisbandGang(gangName)
    return GWRP.Database.WithTransaction(function()
        GWRP.Database.Call("DELETE_GANG", { gangName })
        GWRP.Database.Call("CLEAR_GANG_MEMBERS", { gangName })
        GWRP.Database.Call("CLEAR_PLAYERS_GANG", { gangName })
        print(string.format("[GWRP-DB] Gang '%s' disbanded via stored procedure.", gangName))
        return true
    end)
end

function GWRP.Database.GetAllGangs()
    return GWRP.Database.Call("GET_ALL_GANGS", {}) or {}
end

-- ========================================================
-- 3. PLAYER INVENTORY PERSISTENCE (SLOTS & BAGS)
-- ========================================================

GWRP.Inventory = GWRP.Inventory or {}

function GWRP.Database.GetInventory(steamID)
    return GWRP.Database.Call("GET_INVENTORY", { steamID }) or {}
end

function GWRP.Database.GetInventorySlot(steamID, bagIndex, slotIndex)
    local rows = GWRP.Database.Call("GET_INVENTORY_SLOT", { steamID, bagIndex or 0, slotIndex or 1 })
    return rows and rows[1] or nil
end

function GWRP.Database.GetPlayerBags(steamID)
    local rows = GWRP.Database.Call("GET_PLAYER_BAGS", { steamID })
    if rows and rows[1] then
        return rows[1]
    end
    return { bag1 = "", bag2 = "", bag3 = "", bag4 = "" }
end

function GWRP.Database.SetPlayerBags(steamID, bag1, bag2, bag3, bag4)
    GWRP.Database.Call("SET_PLAYER_BAGS", {
        steamID,
        bag1 or "",
        bag2 or "",
        bag3 or "",
        bag4 or ""
    })
end

function GWRP.Database.AddInventoryItem(steamID, itemId, itemType, amount, itemData, targetBag, targetSlot)
    return GWRP.Database.WithTransaction(function()
        amount = amount or 1
        local iType = itemType or "generic"
        local iData = type(itemData) == "table" and util.TableToJSON(itemData) or (itemData or "{}")

        -- If target slot is explicitly provided and empty:
        if targetBag and targetSlot then
            local slotOccupant = GWRP.Database.GetInventorySlot(steamID, targetBag, targetSlot)
            if not slotOccupant then
                GWRP.Database.Call("INSERT_INVENTORY_ITEM", { steamID, targetBag, targetSlot, itemId, iType, amount, iData })
                return true
            end
        end

        -- First: check if an identical stack exists and can be incremented
        local existing = GWRP.Database.Call("GET_INVENTORY_ITEM", { steamID, itemId })
        if existing and existing[1] then
            local rowId = tonumber(existing[1].id)
            GWRP.Database.Call("INCREMENT_INVENTORY_ITEM", { amount, rowId })
            return true
        end

        -- Otherwise, find first available slot in equipped bags (Bag 0: slots 1..16, Bags 1..4: slots 1..capacity)
        local allItems = GWRP.Database.GetInventory(steamID)
        local occupied = {}
        for _, it in ipairs(allItems) do
            local b = tonumber(it.bag_index) or 0
            local s = tonumber(it.slot_index) or 1
            occupied[b .. "_" .. s] = true
        end

        local playerBags = GWRP.Database.GetPlayerBags(steamID)
        local getCap = GWRP.Inventory.GetBagCapacity or function() return 0 end
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
            GWRP.Database.Call("INSERT_INVENTORY_ITEM", { steamID, freeBag, freeSlot, itemId, iType, amount, iData })
            return true
        end

        return false -- Bags are completely full!
    end)
end

function GWRP.Database.MoveInventorySlot(steamID, fromBag, fromSlot, toBag, toSlot)
    return GWRP.Database.WithTransaction(function()
        local sourceItem = GWRP.Database.GetInventorySlot(steamID, fromBag, fromSlot)
        if not sourceItem then return false end

        local destItem = GWRP.Database.GetInventorySlot(steamID, toBag, toSlot)
        if not destItem then
            -- Empty destination slot: direct move
            GWRP.Database.Call("UPDATE_INVENTORY_SLOT_POS", { toBag, toSlot, tonumber(sourceItem.id) })
            return true
        else
            -- If same item ID and stackable: combine stacks
            if sourceItem.item_id == destItem.item_id then
                GWRP.Database.Call("INCREMENT_INVENTORY_ITEM", { tonumber(sourceItem.amount) or 1, tonumber(destItem.id) })
                GWRP.Database.Call("DELETE_INVENTORY_ITEM", { tonumber(sourceItem.id) })
                return true
            else
                -- Swap slots
                GWRP.Database.Call("UPDATE_INVENTORY_SLOT_POS", { toBag, toSlot, tonumber(sourceItem.id) })
                GWRP.Database.Call("UPDATE_INVENTORY_SLOT_POS", { fromBag, fromSlot, tonumber(destItem.id) })
                return true
            end
        end
    end)
end

function GWRP.Database.RemoveInventoryItemAtSlot(steamID, bagIndex, slotIndex, amount)
    amount = amount or 1
    local row = GWRP.Database.GetInventorySlot(steamID, bagIndex, slotIndex)
    if not row then return false end

    local rowId = tonumber(row.id)
    local curAmount = tonumber(row.amount) or 1
    if curAmount <= amount then
        GWRP.Database.Call("DELETE_INVENTORY_ITEM", { rowId })
    else
        GWRP.Database.Call("DECREMENT_INVENTORY_ITEM", { amount, rowId })
    end
    return true
end

function GWRP.Database.RemoveInventoryItem(steamID, itemId, amount)
    amount = amount or 1
    local existing = GWRP.Database.Call("GET_INVENTORY_ITEM", { steamID, itemId })

    if existing and existing[1] then
        local rowId = tonumber(existing[1].id)
        local curAmount = tonumber(existing[1].amount) or 1
        if curAmount <= amount then
            GWRP.Database.Call("DELETE_INVENTORY_ITEM", { rowId })
        else
            GWRP.Database.Call("DECREMENT_INVENTORY_ITEM", { amount, rowId })
        end
        return true
    end
    return false
end

function GWRP.Database.HasInventoryItem(steamID, itemId, amount)
    amount = amount or 1
    local query = GWRP.Database.Call("GET_INVENTORY_ITEM", { steamID, itemId })
    if query and query[1] then
        return (tonumber(query[1].amount) or 0) >= amount
    end
    return false
end

-- ========================================================
-- 4. TURF ZONES PERSISTENCE (PER-MAP)
-- ========================================================

function GWRP.Database.SaveTurfZones(mapName, zonesTable)
    local mapKey = string.lower(mapName)
    return GWRP.Database.WithTransaction(function()
        GWRP.Database.Call("CLEAR_MAP_TURFS", { mapKey })

        for id, zone in pairs(zonesTable) do
            local idNum = tonumber(id) or 1
            local name = zone.name or ("Turf #" .. idNum)
            local px = zone.pos and zone.pos.x or 0
            local py = zone.pos and zone.pos.y or 0
            local pz = zone.pos and zone.pos.z or 0
            local radius = tonumber(zone.radius) or 450
            local owner = zone.owner or "neutral"

            GWRP.Database.Call("INSERT_MAP_TURF", {
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

function GWRP.Database.LoadTurfZones(mapName)
    local mapKey = string.lower(mapName)
    local rows = GWRP.Database.Call("GET_MAP_TURFS", { mapKey })
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

function GWRP.Database.DeleteTurfZone(mapName, turfId)
    GWRP.Database.Call("DELETE_MAP_TURF", { string.lower(mapName), turfId })
end

-- ========================================================
-- 5. KEY-VALUE SETTINGS PERSISTENCE
-- ========================================================

function GWRP.Database.SetSetting(key, val)
    GWRP.Database.Call("SET_SETTING", { key, tostring(val) })
end

function GWRP.Database.GetSetting(key, defaultVal)
    local query = GWRP.Database.Call("GET_SETTING", { key })
    if query and query[1] then
        return query[1].val
    end
    return defaultVal
end

-- ========================================================
-- 6. PLAYER BUFFS & DEBUFFS PERSISTENCE
-- ========================================================

function GWRP.Database.GetPlayerBuffs(steamID)
    return GWRP.Database.Call("GET_PLAYER_BUFFS", { steamID }) or {}
end

function GWRP.Database.SavePlayerBuff(steamID, buffId, duration, remaining, stacks, appliedAt, expiresAtUnix, dataStr)
    return GWRP.Database.Call("SAVE_PLAYER_BUFF", {
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

function GWRP.Database.DeletePlayerBuff(steamID, buffId)
    return GWRP.Database.Call("DELETE_PLAYER_BUFF", { steamID, buffId })
end

function GWRP.Database.ClearPlayerBuffs(steamID)
    return GWRP.Database.Call("CLEAR_PLAYER_BUFFS", { steamID })
end
