--[[
    GangWars - Database Configuration Loader (Server-Side Only)
    Loads MariaDB credentials securely from ConVars, data/gw/database.json, or fallback defaults.
    NEVER Send this file to the client with AddCSLuaFile!
]]

GW = GW or {}
GW.Database = GW.Database or {}
GW.Database.Config = GW.Database.Config or {}

-- 1. Default Configuration
local defaultConfig = {
    Host = "127.0.0.1",
    Port = 3306,
    Database = "gw",
    User = "root",
    Password = "",
    Socket = ""
}

-- 2. Console Variables for Docker/Environment/Server Startup Overrides
local cvHost = CreateConVar("gw_db_host", "127.0.0.1", FCVAR_PROTECTED, "MariaDB Host Address")
local cvPort = CreateConVar("gw_db_port", "3306", FCVAR_PROTECTED, "MariaDB Port Number")
local cvDatabase = CreateConVar("gw_db_database", "gw", FCVAR_PROTECTED, "MariaDB Database Name")
local cvUser = CreateConVar("gw_db_user", "root", FCVAR_PROTECTED, "MariaDB Username")
local cvPass = CreateConVar("gw_db_password", "", FCVAR_PROTECTED, "MariaDB Password")
local cvSocket = CreateConVar("gw_db_socket", "", FCVAR_PROTECTED, "MariaDB Unix Socket Path (optional)")

function GW.Database.LoadConfig()
    local config = table.Copy(defaultConfig)

    -- Check garrysmod/data/gw/database.json
    local dataPath = "gw/database.json"
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
            print("[GW DB] Loaded configuration from data/gw/database.json")
        else
            ErrorNoHalt("[GW DB] Failed to parse data/gw/database.json; using defaults/ConVars.\n")
        end
    else
        -- Create directory and write a template if not existing
        file.CreateDir("gw")
        local template = util.TableToJSON(defaultConfig, true)
        file.Write(dataPath, template)
        print("[GW DB] Created default database config template at garrysmod/data/gw/database.json")
    end

    -- ConVar overrides take highest precedence if altered from standard default
    if cvHost:GetString() ~= "127.0.0.1" then config.Host = cvHost:GetString() end
    if cvPort:GetInt() ~= 3306 then config.Port = cvPort:GetInt() end
    if cvDatabase:GetString() ~= "gw" then config.Database = cvDatabase:GetString() end
    if cvUser:GetString() ~= "root" then config.User = cvUser:GetString() end
    if cvPass:GetString() ~= "" then config.Password = cvPass:GetString() end
    if cvSocket:GetString() ~= "" then config.Socket = cvSocket:GetString() end

    GW.Database.Config = config
    return config
end

-- Initialize config on file inclusion
GW.Database.LoadConfig()

