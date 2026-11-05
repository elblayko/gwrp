--[[
    GridRP - Database Configuration Loader (Server-Side Only)
    Loads MariaDB credentials securely from ConVars, data/grid/database.json, or fallback defaults.
    NEVER Send this file to the client with AddCSLuaFile!
]]

GRID = GRID or {}
GRID.Database = GRID.Database or {}
GRID.Database.Config = GRID.Database.Config or {}

-- 1. Default Configuration
local defaultConfig = {
    Host = "127.0.0.1",
    Port = 3306,
    Database = "grid",
    User = "root",
    Password = "",
    Socket = ""
}

-- 2. Console Variables for Docker/Environment/Server Startup Overrides
local cvHost = CreateConVar("grid_db_host", "127.0.0.1", FCVAR_PROTECTED, "MariaDB Host Address")
local cvPort = CreateConVar("grid_db_port", "3306", FCVAR_PROTECTED, "MariaDB Port Number")
local cvDatabase = CreateConVar("grid_db_database", "grid", FCVAR_PROTECTED, "MariaDB Database Name")
local cvUser = CreateConVar("grid_db_user", "root", FCVAR_PROTECTED, "MariaDB Username")
local cvPass = CreateConVar("grid_db_password", "", FCVAR_PROTECTED, "MariaDB Password")
local cvSocket = CreateConVar("grid_db_socket", "", FCVAR_PROTECTED, "MariaDB Unix Socket Path (optional)")

function GRID.Database.LoadConfig()
    local config = table.Copy(defaultConfig)
    local dataPath = "grid/database.json"

    if file.Exists(dataPath, "DATA") then
        local raw = file.Read(dataPath, "DATA")
        local json = util.JSONToTable(raw or "")
        if json then
            config.Host = json.Host or json.host or config.Host
            config.Port = tonumber(json.Port or json.port) or config.Port
            config.Database = json.Database or json.database or config.Database
            config.User = json.User or json.user or config.User
            config.Password = json.Password or json.password or config.Password
            config.Socket = json.Socket or json.socket or config.Socket
            print(string.format("[GRID DB] Loaded configuration from data/%s", dataPath))
        else
            ErrorNoHalt(string.format("[GRID DB] Failed to parse data/%s; using defaults/ConVars.\n", dataPath))
        end
    else
        file.CreateDir("grid")
        local template = util.TableToJSON(defaultConfig, true)
        file.Write(dataPath, template)
        print("[GRID DB] Created default database config template at garrysmod/data/grid/database.json")
    end

    -- ConVar overrides take highest precedence if altered from standard default
    if cvHost:GetString() ~= "127.0.0.1" then config.Host = cvHost:GetString() end
    if cvPort:GetInt() ~= 3306 then config.Port = cvPort:GetInt() end
    if cvDatabase:GetString() ~= "grid" then config.Database = cvDatabase:GetString() end
    if cvUser:GetString() ~= "root" then config.User = cvUser:GetString() end
    if cvPass:GetString() ~= "" then config.Password = cvPass:GetString() end
    if cvSocket:GetString() ~= "" then config.Socket = cvSocket:GetString() end

    GRID.Database.Config = config
    return config
end

-- Initialize config on file inclusion
GRID.Database.LoadConfig()
