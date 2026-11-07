--[[
    sv_net.lua - Centralized Network Protocol & Rate Limiter
    Author: GRID Core Team
    Namespace: GRID / grid_
--]]

util.AddNetworkString("GRID_Notification")
util.AddNetworkString("GRID_PlayerDied")
util.AddNetworkString("GRID_TurfUpdate")
util.AddNetworkString("GRID_TurfAlert")
util.AddNetworkString("GRID_OpenTurfTaxMenu")
util.AddNetworkString("GRID_SetTurfTax")
util.AddNetworkString("GRID_ChangeJob")
util.AddNetworkString("GRID_BuyItem")
util.AddNetworkString("GRID_DoorAction")
util.AddNetworkString("GRID_ChatMessage")
util.AddNetworkString("GRID_SyncTurfZones")
util.AddNetworkString("GRID_OpenTurfSetup")
util.AddNetworkString("GRID_AdminTurfAction")
util.AddNetworkString("GRID_AdminDebugAction")
util.AddNetworkString("GRID_OpenAdminMenu")
util.AddNetworkString("GRID_ToggleF4Menu")
util.AddNetworkString("GRID_ToggleF2Menu")
util.AddNetworkString("GRID_SyncInventory")
util.AddNetworkString("GRID_UseInventoryItem")
util.AddNetworkString("GRID_DropInventoryItem")
util.AddNetworkString("GRID_MoveInventorySlot")
util.AddNetworkString("GRID_DropInventorySlot")
util.AddNetworkString("GRID_UseInventorySlot")
util.AddNetworkString("GRID_EquipBag")
util.AddNetworkString("GRID_ToggleBagWindow")
util.AddNetworkString("GRID_SyncAllBuffs")
util.AddNetworkString("GRID_SyncBuffAdded")
util.AddNetworkString("GRID_SyncBuffRemoved")
util.AddNetworkString("GRID_CancelBuff")
util.AddNetworkString("GRID_BuffCombatText")
util.AddNetworkString("GRID_OpenComputerOS")
util.AddNetworkString("GRID_RunComputerCommand")
util.AddNetworkString("GRID_ComputerCommandResponse")
util.AddNetworkString("GRID_LevelUp")
util.AddNetworkString("GRID_OpenEntityConfig")
util.AddNetworkString("GRID_SaveEntityConfig")
util.AddNetworkString("GRID_XPGained")
util.AddNetworkString("GRID_OpenCraftingUI")
util.AddNetworkString("GRID_CraftItem")
util.AddNetworkString("GRID_CollectMachineResource")
util.AddNetworkString("GRID_RequestGangData")
util.AddNetworkString("GRID_SendGangData")
util.AddNetworkString("GRID_GangUIAction")

-- Auction House Network Protocols
util.AddNetworkString("GRID_Auction_OpenTerminal")
util.AddNetworkString("GRID_Auction_OpenRemote")
util.AddNetworkString("GRID_Auction_RequestListings")
util.AddNetworkString("GRID_Auction_SendListings")
util.AddNetworkString("GRID_Auction_RequestMetrics")
util.AddNetworkString("GRID_Auction_SendMetrics")
util.AddNetworkString("GRID_Auction_CreateListing")
util.AddNetworkString("GRID_Auction_PlaceBid")
util.AddNetworkString("GRID_Auction_Buyout")
util.AddNetworkString("GRID_Auction_Cancel")
util.AddNetworkString("GRID_Auction_RequestCollection")
util.AddNetworkString("GRID_Auction_SendCollection")
util.AddNetworkString("GRID_Auction_ClaimItem")

-- Police Capabilities, Jail & Warrant Voting
util.AddNetworkString("GRID_JailPayBail")
util.AddNetworkString("GRID_JailAdminAction")
util.AddNetworkString("GRID_JailSyncPoints")
util.AddNetworkString("GRID_PoliceVoteStart")
util.AddNetworkString("GRID_PoliceCastVote")
util.AddNetworkString("GRID_PoliceVoteEnd")
util.AddNetworkString("GRID_EvidenceInvestigate")
util.AddNetworkString("GRID_TurfLockdownAction")

GRID = GRID or {}
GRID.NetLimits = GRID.NetLimits or {}

function GRID.CheckRateLimit(ply, action, maxPerSec)
    local id = ply:SteamID() .. "_" .. action
    local now = CurTime()
    GRID.NetLimits[id] = GRID.NetLimits[id] or { count = 0, reset = now + 1, warned = false }

    if now > GRID.NetLimits[id].reset then
        GRID.NetLimits[id].count = 1
        GRID.NetLimits[id].reset = now + 1
        GRID.NetLimits[id].warned = false
        return true
    end

    GRID.NetLimits[id].count = GRID.NetLimits[id].count + 1
    if GRID.NetLimits[id].count > maxPerSec then
        if not GRID.NetLimits[id].warned then
            GRID.NetLimits[id].warned = true
            if GRID.Telemetry and GRID.Telemetry.LogAnomaly then
                GRID.Telemetry.LogAnomaly(ply:SteamID(), "NET_RATE_LIMIT_EXCEEDED", {
                    action = action,
                    count = GRID.NetLimits[id].count,
                    max = maxPerSec
                })
            end
        end
        return false
    end
    return true
end
