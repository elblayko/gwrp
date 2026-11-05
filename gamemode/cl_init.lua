--[[
    GridRP (GRID) by Toxic
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
    print("[GRID-Client] Initializing client interface & Source fonts...")
    GRID.UI.CreateFonts()
end

-- Server Net Receivers for F4 and F2
net.Receive("GRID_ToggleF4Menu", function()
    GRID.UI.ToggleF4Menu()
end)

net.Receive("GRID_ToggleF2Menu", function()
    GRID.Doors.OpenDoorMenu()
end)

net.Receive("GRID_OpenAdminMenu", function()
    if GRID.Turf and GRID.Turf.OpenSetupMenu then
        GRID.Turf.OpenSetupMenu()
    end
end)

net.Receive("GRID_OpenTurfSetup", function()
    if GRID.Turf and GRID.Turf.OpenSetupMenu then
        GRID.Turf.OpenSetupMenu()
    end
end)

-- Direct Physical Key Listener (Hooks KEY_F4, KEY_F2, and KEY_B directly on client)
hook.Add("PlayerButtonDown", "GRID_FKeyBindings", function(ply, button)
    if button == KEY_F4 then
        GRID.UI.ToggleF4Menu()
    elseif button == KEY_F2 then
        GRID.Doors.OpenDoorMenu()
    elseif button == KEY_B then
        GRID.UI.ToggleBag()
    end
end)

-- Console commands for menu
concommand.Add("grid_f4", function() GRID.UI.ToggleF4Menu() end)
concommand.Add("f4menu", function() GRID.UI.ToggleF4Menu() end)
concommand.Add("grid_menu", function() GRID.UI.ToggleF4Menu() end)
concommand.Add("grid_admin", function() if GRID.Turf and GRID.Turf.OpenSetupMenu then GRID.Turf.OpenSetupMenu() end end)
concommand.Add("admin", function() if GRID.Turf and GRID.Turf.OpenSetupMenu then GRID.Turf.OpenSetupMenu() end end)
concommand.Add("debug", function() if GRID.Turf and GRID.Turf.OpenSetupMenu then GRID.Turf.OpenSetupMenu() end end)

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
