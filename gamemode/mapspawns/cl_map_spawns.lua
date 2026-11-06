--[[
    gamemode/mapspawns/cl_map_spawns.lua
    Persistent World Entity Management (GRID.MapSpawns) - SuperAdmin Visual Inspector (Safeguard 13)
    Author: GRID Core Team & Antigravity
--]]

GRID = GRID or {}
GRID.MapSpawns = GRID.MapSpawns or {}

local COLOR_CYAN       = Color(0, 220, 255, 220)
local COLOR_BG         = Color(16, 20, 28, 230)
local COLOR_BORDER     = Color(0, 220, 255, 180)
local COLOR_WHITE      = Color(255, 255, 255, 240)
local COLOR_SUBTEXT    = Color(180, 200, 220, 200)

surface.CreateFont("GRID_MapSpawn_Header", {
    font = "Trebuchet MS",
    size = 28,
    weight = 800,
    antialias = true
})

surface.CreateFont("GRID_MapSpawn_Sub", {
    font = "Trebuchet MS",
    size = 18,
    weight = 600,
    antialias = true
})

-- --------------------------------------------------------
-- Visual Inspector 3D2D Overlay & Wireframe Bounds
-- --------------------------------------------------------

hook.Add("PostDrawTranslucentRenderables", "GRID_MapSpawns_VisualInspector", function(bDepth, bSkybox)
    if bSkybox then return end

    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:IsSuperAdmin() then return end

    local activeWep = lp:GetActiveWeapon()
    if not IsValid(activeWep) then return end

    local wepClass = activeWep:GetClass()
    if wepClass ~= "weapon_physgun" and wepClass ~= "gmod_tool" then return end

    local eyePos = lp:EyePos()
    local maxDistSqr = GRID.MapSpawns.INSPECTOR_DRAW_DISTANCE * GRID.MapSpawns.INSPECTOR_DRAW_DISTANCE

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or not ent:GetNWBool("GRID_MapEntity", false) then continue end

        local entPos = ent:GetPos()
        if eyePos:DistToSqr(entPos) > maxDistSqr then continue end

        -- 1. Bounding Wireframe Box
        render.DrawWireframeBox(entPos, ent:GetAngles(), ent:OBBMins(), ent:OBBMaxs(), COLOR_CYAN, true)

        -- 2. 3D2D Floating Billboard Badge
        local spawnId = ent:GetNWInt("GRID_MapSpawnID", 0)
        local topPos = entPos + Vector(0, 0, ent:OBBMaxs().z + 12)
        local ang = (eyePos - topPos):Angle()
        ang:RotateAroundAxis(ang:Right(), 90)
        ang:RotateAroundAxis(ang:Up(), -90)

        cam.Start3D2D(topPos, ang, 0.08)
            local title = string.format("[DB ID #%d] %s", spawnId, ent:GetClass())
            local posStr = string.format("Pos: %.1f, %.1f, %.1f  Ang: %.1f, %.1f, %.1f", entPos.x, entPos.y, entPos.z, ent:GetAngles().p, ent:GetAngles().y, ent:GetAngles().r)

            surface.SetFont("GRID_MapSpawn_Header")
            local tW = surface.GetTextSize(title)
            surface.SetFont("GRID_MapSpawn_Sub")
            local sW = surface.GetTextSize(posStr)

            local boxW = math.max(tW, sW) + 40
            local boxH = 65
            local boxX = -boxW / 2
            local boxY = -boxH / 2

            -- Background card
            draw.RoundedBox(6, boxX, boxY, boxW, boxH, COLOR_BG)

            -- Border
            surface.SetDrawColor(COLOR_BORDER)
            surface.DrawOutlinedRect(boxX, boxY, boxW, boxH, 2)

            -- Cyan accent top strip
            draw.RoundedBox(2, boxX, boxY, boxW, 4, COLOR_CYAN)

            -- Labels
            draw.SimpleText(title, "GRID_MapSpawn_Header", 0, boxY + 12, COLOR_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText(posStr, "GRID_MapSpawn_Sub", 0, boxY + 40, COLOR_SUBTEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        cam.End3D2D()
    end
end)

