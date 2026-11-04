--[[
    sv_net.lua - Centralized Network Protocol & Rate Limiter
--]]

util.AddNetworkString("GW_Notification")
util.AddNetworkString("GW_PlayerDied")
util.AddNetworkString("GW_TurfUpdate")
util.AddNetworkString("GW_TurfAlert")
util.AddNetworkString("GW_OpenTurfTaxMenu")
util.AddNetworkString("GW_SetTurfTax")
util.AddNetworkString("GW_ChangeJob")
util.AddNetworkString("GW_BuyItem")
util.AddNetworkString("GW_DoorAction")
util.AddNetworkString("GW_ChatMessage")
util.AddNetworkString("GW_SyncTurfZones")
util.AddNetworkString("GW_OpenTurfSetup")
util.AddNetworkString("GW_AdminTurfAction")
util.AddNetworkString("GW_AdminDebugAction")
util.AddNetworkString("GW_OpenAdminMenu")
util.AddNetworkString("GW_ToggleF4Menu")
util.AddNetworkString("GW_ToggleF2Menu")
util.AddNetworkString("GW_SyncInventory")
util.AddNetworkString("GW_UseInventoryItem")
util.AddNetworkString("GW_DropInventoryItem")
util.AddNetworkString("GW_MoveInventorySlot")
util.AddNetworkString("GW_DropInventorySlot")
util.AddNetworkString("GW_UseInventorySlot")
util.AddNetworkString("GW_EquipBag")
util.AddNetworkString("GW_ToggleBagWindow")
util.AddNetworkString("GW_SyncAllBuffs")
util.AddNetworkString("GW_SyncBuffAdded")
util.AddNetworkString("GW_SyncBuffRemoved")
util.AddNetworkString("GW_CancelBuff")
util.AddNetworkString("GW_BuffCombatText")
util.AddNetworkString("GW_OpenComputerOS")
util.AddNetworkString("GW_RunComputerCommand")
util.AddNetworkString("GW_ComputerCommandResponse")
util.AddNetworkString("GW_LevelUp")
util.AddNetworkString("GW_XPGained")
util.AddNetworkString("GW_OpenCraftingUI")
util.AddNetworkString("GW_CraftItem")
util.AddNetworkString("GW_CollectMachineResource")
util.AddNetworkString("GW_RequestGangData")
util.AddNetworkString("GW_SendGangData")
util.AddNetworkString("GW_GangUIAction")

GW.NetLimits = GW.NetLimits or {}

function GW.CheckRateLimit(ply, action, maxPerSec)
    local id = ply:SteamID() .. "_" .. action
    local now = CurTime()
    GW.NetLimits[id] = GW.NetLimits[id] or { count = 0, reset = now + 1 }

    if now > GW.NetLimits[id].reset then
        GW.NetLimits[id].count = 1
        GW.NetLimits[id].reset = now + 1
        return true
    end

    GW.NetLimits[id].count = GW.NetLimits[id].count + 1
    return GW.NetLimits[id].count <= maxPerSec
end
