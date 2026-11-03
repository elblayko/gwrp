--[[
    GangWars RP (GWRP) by Toxic
    gamemode/shared.lua - Shared Gamemode Entry Point
--]]

GM.Name = "GangWars RP"
GM.Author = "Toxic"
GM.Email = ""
GM.Website = ""

DeriveGamemode("sandbox")

GWRP = GWRP or {}
GWRP.Version = "2.0.0 (2026)"

-- Core Shared Includes (relative to gamemode/)
include("core/sh_config.lua")
include("core/sh_player_meta.lua")
include("core/sh_entity_meta.lua")
include("core/sh_notifications.lua")
include("buffs/sh_buffs.lua")
include("buffs/sh_buff_definitions.lua")
include("factions/sh_factions.lua")
include("turf/sh_turf.lua")
include("crafting/sh_crafting.lua")

function GM:Initialize()
    print("[GWRP] Initializing GangWars RP by Toxic...")
end

-- Disable sandbox noclip unless admin
function GM:PlayerNoClip(ply, desiredNoClipState)
    if not desiredNoClipState then return true end
    return ply:IsAdmin() or ply:IsSuperAdmin()
end

-- Restrict suicide in RP
function GM:CanPlayerSuicide(ply)
    return false
end

-- Alias "fists" to GMod's "weapon_fists" for universal compatibility
hook.Add("Initialize", "GWRP_RegisterFistsAlias", function()
    if weapons and weapons.Get and weapons.Register then
        local baseFists = weapons.Get("weapon_fists")
        if baseFists and not weapons.Get("fists") then
            local fistsCopy = table.Copy(baseFists)
            fistsCopy.ClassName = "fists"
            weapons.Register(fistsCopy, "fists")
        end
    end
end)

-- Shared Viewmodel Hands Model Configuration
function GM:PlayerSetHandsModel(ply, ent)
    local info = player_manager.RunClass(ply, "GetHandsModel")
    if not info then
        local playermodel = player_manager.TranslateToPlayerModelName(ply:GetModel())
        info = player_manager.TranslatePlayerHands(playermodel)
    end

    if info and info.model then
        ent:SetModel(info.model)
        ent:SetSkin(info.matchBodySkin and ply:GetSkin() or (info.skin or 0))
        ent:SetBodyGroups(info.body or "0000000")
    else
        ent:SetModel("models/weapons/c_arms_citizen.mdl")
        ent:SetSkin(0)
        ent:SetBodyGroups("0000000")
    end
end

hook.Add("PlayerSetHandsModel", "GWRP_PlayerSetHandsModelHook", function(ply, ent)
    return GAMEMODE:PlayerSetHandsModel(ply, ent)
end)
