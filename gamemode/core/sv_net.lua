--[[
    sv_net.lua - Centralized Network Protocol & Rate Limiter
--]]

util.AddNetworkString("GWRP_Notification")
util.AddNetworkString("GWRP_PlayerDied")
util.AddNetworkString("GWRP_TurfUpdate")
util.AddNetworkString("GWRP_TurfAlert")
util.AddNetworkString("GWRP_ChangeJob")
util.AddNetworkString("GWRP_BuyItem")
util.AddNetworkString("GWRP_DoorAction")
util.AddNetworkString("GWRP_ChatMessage")
util.AddNetworkString("GWRP_SyncTurfZones")
util.AddNetworkString("GWRP_OpenTurfSetup")
util.AddNetworkString("GWRP_AdminTurfAction")
util.AddNetworkString("GWRP_AdminDebugAction")
util.AddNetworkString("GWRP_OpenAdminMenu")
util.AddNetworkString("GWRP_ToggleF4Menu")
util.AddNetworkString("GWRP_ToggleF2Menu")
util.AddNetworkString("GWRP_SyncInventory")
util.AddNetworkString("GWRP_UseInventoryItem")
util.AddNetworkString("GWRP_DropInventoryItem")
util.AddNetworkString("GWRP_MoveInventorySlot")
util.AddNetworkString("GWRP_DropInventorySlot")
util.AddNetworkString("GWRP_UseInventorySlot")
util.AddNetworkString("GWRP_EquipBag")
util.AddNetworkString("GWRP_ToggleBagWindow")
util.AddNetworkString("GWRP_SyncAllBuffs")
util.AddNetworkString("GWRP_SyncBuffAdded")
util.AddNetworkString("GWRP_SyncBuffRemoved")
util.AddNetworkString("GWRP_CancelBuff")
util.AddNetworkString("GWRP_BuffCombatText")
util.AddNetworkString("GWRP_OpenComputerOS")
util.AddNetworkString("GWRP_RunComputerCommand")
util.AddNetworkString("GWRP_ComputerCommandResponse")
util.AddNetworkString("GWRP_LevelUp")
util.AddNetworkString("GWRP_XPGained")

GWRP.NetLimits = GWRP.NetLimits or {}

function GWRP.CheckRateLimit(ply, action, maxPerSec)
    local id = ply:SteamID() .. "_" .. action
    local now = CurTime()
    GWRP.NetLimits[id] = GWRP.NetLimits[id] or { count = 0, reset = now + 1 }

    if now > GWRP.NetLimits[id].reset then
        GWRP.NetLimits[id].count = 1
        GWRP.NetLimits[id].reset = now + 1
        return true
    end

    GWRP.NetLimits[id].count = GWRP.NetLimits[id].count + 1
    return GWRP.NetLimits[id].count <= maxPerSec
end
