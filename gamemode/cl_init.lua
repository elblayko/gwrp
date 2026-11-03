--[[
    GangWars RP (GWRP) by Toxic
    gamemode/cl_init.lua - Client Gamemode Entry Point
--]]

include("shared.lua")
include("core/sh_networking.lua")

-- Client Modules (relative to gamemode/)
include("buffs/sh_buffs.lua")
include("buffs/sh_buff_definitions.lua")
include("buffs/cl_buffs.lua")
include("inventory/sh_inventory.lua")
include("inventory/cl_inventory.lua")
include("inventory/cl_bag.lua")
include("crafting/sh_crafting.lua")
include("crafting/cl_crafting.lua")
include("factions/cl_jobs.lua")
include("turf/cl_turf.lua")
include("turf/cl_turf_setup.lua")
include("economy/cl_economy.lua")
include("doors/cl_doors.lua")
include("ui/cl_hud.lua")
include("ui/cl_f4menu.lua")
include("ui/cl_chatbox.lua")
include("ui/cl_scoreboard.lua")
include("ui/cl_deathscreen.lua")

function GM:Initialize()
    print("[GWRP-Client] Initializing client interface & Source fonts...")
    GWRP.UI.CreateFonts()
end

-- Server Net Receivers for F4 and F2
net.Receive("GWRP_ToggleF4Menu", function()
    GWRP.UI.ToggleF4Menu()
end)

net.Receive("GWRP_ToggleF2Menu", function()
    GWRP.Doors.OpenDoorMenu()
end)

net.Receive("GWRP_OpenAdminMenu", function()
    if GWRP.Turf and GWRP.Turf.OpenSetupMenu then
        GWRP.Turf.OpenSetupMenu()
    end
end)

net.Receive("GWRP_OpenTurfSetup", function()
    if GWRP.Turf and GWRP.Turf.OpenSetupMenu then
        GWRP.Turf.OpenSetupMenu()
    end
end)

-- Direct Physical Key Listener (Hooks KEY_F4, KEY_F2, and KEY_B directly on client)
hook.Add("PlayerButtonDown", "GWRP_FKeyBindings", function(ply, button)
    if button == KEY_F4 then
        GWRP.UI.ToggleF4Menu()
    elseif button == KEY_F2 then
        GWRP.Doors.OpenDoorMenu()
    elseif button == KEY_B then
        GWRP.UI.ToggleBag()
    end
end)

-- Console commands for menu
concommand.Add("gwrp_f4", function() GWRP.UI.ToggleF4Menu() end)
concommand.Add("f4menu", function() GWRP.UI.ToggleF4Menu() end)
concommand.Add("gwrp_menu", function() GWRP.UI.ToggleF4Menu() end)
concommand.Add("gwrp_admin", function() if GWRP.Turf and GWRP.Turf.OpenSetupMenu then GWRP.Turf.OpenSetupMenu() end end)
concommand.Add("admin", function() if GWRP.Turf and GWRP.Turf.OpenSetupMenu then GWRP.Turf.OpenSetupMenu() end end)
concommand.Add("debug", function() if GWRP.Turf and GWRP.Turf.OpenSetupMenu then GWRP.Turf.OpenSetupMenu() end end)

-- Explicitly ensure client viewmodel hands render for SWEP.UseHands weapons
function GM:PostDrawViewModel(vm, ply, wep, flags)
    if not IsValid(wep) then return false end

    if wep.UseHands or not wep:IsScripted() then
        local hands = ply:GetHands()
        if IsValid(hands) and IsValid(hands:GetParent()) then
            if not hook.Call("PreDrawPlayerHands", self, hands, vm, ply, wep, flags) then
                if wep.ViewModelFlip then render.CullMode(MATERIAL_CULLMODE_CW) end
                hands:DrawModel(flags)
                render.CullMode(MATERIAL_CULLMODE_CCW)
            end
            hook.Call("PostDrawPlayerHands", self, hands, vm, ply, wep, flags)
        end
    end

    player_manager.RunClass(ply, "PostDrawViewModel", vm, wep, flags)

    if wep.PostDrawViewModel == nil then return false end
    return wep:PostDrawViewModel(vm, ply, wep, flags)
end
