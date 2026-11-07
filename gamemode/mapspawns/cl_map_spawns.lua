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

local matBeam = Material("sprites/physbeam")
local matLaser = Material("cable/redlaser")
local matGlow = Material("sprites/glow04_noz")

local function DrawThickCircle(pos, radius, col, thickness, segments)
    segments = segments or 64
    thickness = thickness or 14
    local step = (math.pi * 2) / segments

    render.SetMaterial(matBeam)
    render.StartBeam(segments + 1)
    for i = 0, segments do
        local angle = i * step
        local p = pos + Vector(math.cos(angle) * radius, math.sin(angle) * radius, 0)
        render.AddBeam(p, thickness, i / segments, col)
    end
    render.EndBeam()
end

local function DrawHolographicSphere(pos, radius, col)
    -- 1. Clean Translucent Volumetric Color Dome (Smooth 360-degree fill)
    render.SetColorMaterial()
    local domeCol = Color(col.r, col.g, col.b, 35)
    render.DrawSphere(pos, radius, 36, 36, domeCol)
    render.DrawSphere(pos, -radius, 36, 36, domeCol)

    -- 2. Clean High-Visibility Ground Perimeter Rings
    local pulse = (math.sin(CurTime() * 4) * 0.15) + 0.85
    local groundAlpha = math.Clamp(math.floor(col.a * pulse), 160, 255)
    local groundCol = Color(col.r, col.g, col.b, groundAlpha)

    -- Thick outer boundary beam on ground
    DrawThickCircle(Vector(pos.x, pos.y, pos.z + 8), radius, groundCol, 32, 72)
    -- Sleek bright core accent stripe
    DrawThickCircle(Vector(pos.x, pos.y, pos.z + 10), radius, Color(255, 255, 255, math.floor(groundAlpha * 0.8)), 8, 72)

    -- 3. Subtle Equator Ring (gives clean spherical horizon depth without noisy grid lattice)
    local equatorCol = Color(col.r, col.g, col.b, math.floor(col.a * 0.4))
    DrawThickCircle(Vector(pos.x, pos.y, pos.z), radius, equatorCol, 8, 64)
end

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

    -- Check if SuperAdmin is currently aiming at or configuring a gang pole
    local tr = lp:GetEyeTrace()
    local targetedEnt = tr.Entity
    local activeConfigEnt = GRID.MapSpawns.ActiveConfigEntity

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or not ent:GetNWBool("GRID_MapEntity", false) then continue end

        local entPos = ent:GetPos()
        if eyePos:DistToSqr(entPos) > maxDistSqr then continue end

        local isFlagPole = (ent:GetClass() == "grid_flag_pole")

        -- Render Gang Pole Influence Boundary Sphere & Rings
        if isFlagPole then
            local isBeingEdited = (IsValid(activeConfigEnt) and activeConfigEnt == ent)
            local isAimedAt = (IsValid(targetedEnt) and targetedEnt == ent)

            -- Determine zone capture radius, influence radius, and owner color
            local turfId = ent:GetTurfID()
            local zone = GRID.Turf and GRID.Turf.Zones and GRID.Turf.Zones[turfId]
            local capRad = (ent.GetCaptureRadius and ent:GetCaptureRadius() > 0 and ent:GetCaptureRadius()) or (zone and (tonumber(zone.capture_radius) or tonumber(zone.radius))) or 250
            local infRad = (ent.GetInfluenceRadius and ent:GetInfluenceRadius() > 0 and ent:GetInfluenceRadius()) or (zone and (tonumber(zone.influence_radius) or tonumber(zone.radius))) or 800
            local owner = (zone and zone.owner) or "neutral"

            -- Live override when slider is being adjusted in config panel
            if isBeingEdited then
                if GRID.MapSpawns.PreviewCaptureRadius then
                    capRad = GRID.MapSpawns.PreviewCaptureRadius
                end
                if GRID.MapSpawns.PreviewInfluenceRadius then
                    infRad = GRID.MapSpawns.PreviewInfluenceRadius
                end
            end

            local baseColor = (GRID.GetGangColor and GRID.GetGangColor(owner)) or COLOR_CYAN
            local ringAlpha = (isBeingEdited or isAimedAt) and 220 or 120

            -- 1. Outer Extortion / Influence Radius Sphere (Gold/Amber or Owner Tone)
            local infCol = Color(baseColor.r, baseColor.g, baseColor.b, math.floor(ringAlpha * 0.8))
            DrawHolographicSphere(entPos, infRad, infCol)

            -- 2. Inner Flag Capture Zone (Crimson/Amber Hot-Zone)
            local capCol = Color(245, 158, 11, ringAlpha) -- Amber/Gold core zone
            local pulse = (math.sin(CurTime() * 5) * 0.2) + 0.8
            DrawThickCircle(Vector(entPos.x, entPos.y, entPos.z + 6), capRad, Color(245, 158, 11, math.Clamp(math.floor(ringAlpha * pulse), 60, 255)), 8, 48)
            DrawThickCircle(Vector(entPos.x, entPos.y, entPos.z + 12), capRad * 0.98, Color(239, 68, 68, math.floor(ringAlpha * 0.5)), 4, 48)
        end

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

            local hintStr = "[E] Configure Infrastructure"
            surface.SetFont("GRID_MapSpawn_Header")
            local tW = surface.GetTextSize(title)
            surface.SetFont("GRID_MapSpawn_Sub")
            local sW = math.max(surface.GetTextSize(posStr), surface.GetTextSize(hintStr))

            local boxW = math.max(tW, sW) + 40
            local boxH = 88
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
            draw.SimpleText(posStr, "GRID_MapSpawn_Sub", 0, boxY + 38, COLOR_SUBTEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText(hintStr, "GRID_MapSpawn_Sub", 0, boxY + 60, COLOR_CYAN, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        cam.End3D2D()
    end
end)

-- --------------------------------------------------------
-- SuperAdmin Infrastructure Configuration Menu
-- --------------------------------------------------------

local configFrame = nil

function GRID.MapSpawns.OpenConfigUI(ent, className, configData)
    if IsValid(configFrame) then
        configFrame:Close()
        configFrame = nil
    end

    if not IsValid(ent) then return end

    local frameW = 540
    local frameH = 590

    configFrame = vgui.Create("DFrame")
    configFrame:SetSize(frameW, frameH)
    configFrame:Center()
    configFrame:SetTitle("")
    configFrame:ShowCloseButton(false)
    configFrame:SetDraggable(true)
    configFrame:MakePopup()

    configFrame.Paint = function(s, w, h)
        -- Deep obsidian cyber card background
        draw.RoundedBox(8, 0, 0, w, h, Color(15, 23, 42, 250))
        surface.SetDrawColor(0, 220, 255, 160)
        surface.DrawOutlinedRect(0, 0, w, h, 2)

        -- Top title header banner
        draw.RoundedBoxEx(8, 0, 0, w, 56, Color(30, 41, 59, 240), true, true, false, false)
        draw.RoundedBox(0, 0, 54, w, 2, Color(0, 220, 255, 255))

        draw.SimpleText("⚙ CONFIGURE WORLD INFRASTRUCTURE", "GRID_UI_Header", 20, 14, Color(248, 250, 252))
        local sub = string.format("Entity: %s | DB ID: #%d", className, ent:GetNWInt("GRID_MapSpawnID", 0))
        draw.SimpleText(sub, "GRID_UI_Caption", 20, 36, Color(148, 163, 184))
    end

    GRID.MapSpawns.ActiveConfigEntity = ent
    GRID.MapSpawns.PreviewCaptureRadius = tonumber(configData.capture_radius) or tonumber(configData.radius) or 250
    GRID.MapSpawns.PreviewInfluenceRadius = tonumber(configData.influence_radius) or tonumber(configData.radius) or 800

    configFrame.OnClose = function()
        GRID.MapSpawns.ActiveConfigEntity = nil
        GRID.MapSpawns.PreviewCaptureRadius = nil
        GRID.MapSpawns.PreviewInfluenceRadius = nil
    end

    configFrame.OnRemove = function()
        GRID.MapSpawns.ActiveConfigEntity = nil
        GRID.MapSpawns.PreviewCaptureRadius = nil
        GRID.MapSpawns.PreviewInfluenceRadius = nil
    end

    local btnClose = vgui.Create("DButton", configFrame)
    btnClose:SetSize(32, 32)
    btnClose:SetPos(frameW - 44, 12)
    btnClose:SetText("✕")
    btnClose:SetFont("GRID_UI_Header")
    btnClose:SetTextColor(Color(148, 163, 184))
    btnClose.Paint = function(s, w, h)
        if s:IsHovered() then
            draw.RoundedBox(6, 0, 0, w, h, Color(239, 68, 68, 180))
            s:SetTextColor(Color(255, 255, 255))
        else
            draw.RoundedBox(6, 0, 0, w, h, Color(51, 65, 85, 120))
            s:SetTextColor(Color(148, 163, 184))
        end
    end
    btnClose.DoClick = function()
        configFrame:Close()
    end

    local scroll = vgui.Create("DScrollPanel", configFrame)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 68, 20, 70)

    -- Fields specific to grid_flag_pole / Turf Zones
    if className == "grid_flag_pole" then
        -- 1. Territory Name Panel
        local pnlName = scroll:Add("DPanel")
        pnlName:Dock(TOP)
        pnlName:DockMargin(0, 0, 0, 14)
        pnlName:SetTall(68)
        pnlName.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(30, 41, 59, 140))
            draw.SimpleText("Territory / Zone Name", "GRID_UI_Sub", 12, 8, Color(0, 220, 255))
        end

        local txtName = vgui.Create("DTextEntry", pnlName)
        txtName:SetPos(12, 32)
        txtName:SetSize(frameW - 64, 28)
        txtName:SetFont("GRID_UI_Body")
        txtName:SetText(tostring(configData.name or "Turf Zone"))

        -- 2. Capture Zone Radius Panel (Contest boundary)
        local pnlCapRadius = scroll:Add("DPanel")
        pnlCapRadius:Dock(TOP)
        pnlCapRadius:DockMargin(0, 0, 0, 14)
        pnlCapRadius:SetTall(72)
        pnlCapRadius.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(30, 41, 59, 140))
            draw.SimpleText("Capture Zone Radius (Contest Boundary)", "GRID_UI_Sub", 12, 8, Color(245, 158, 11))
        end

        local sliderCapRadius = vgui.Create("DNumSlider", pnlCapRadius)
        sliderCapRadius:SetPos(12, 30)
        sliderCapRadius:SetSize(frameW - 64, 32)
        sliderCapRadius:SetText("")
        sliderCapRadius:SetMin(50)
        sliderCapRadius:SetMax(1000)
        sliderCapRadius:SetDecimals(0)
        sliderCapRadius:SetValue(tonumber(configData.capture_radius) or tonumber(configData.radius) or 250)
        if IsValid(sliderCapRadius.Label) then sliderCapRadius.Label:SetVisible(false) end
        sliderCapRadius.OnValueChanged = function(s, val)
            GRID.MapSpawns.PreviewCaptureRadius = val
        end

        -- 3. Influence Radius Panel (Extortion tax & Turf boundary)
        local pnlInfRadius = scroll:Add("DPanel")
        pnlInfRadius:Dock(TOP)
        pnlInfRadius:DockMargin(0, 0, 0, 14)
        pnlInfRadius:SetTall(72)
        pnlInfRadius.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(30, 41, 59, 140))
            draw.SimpleText("Influence Radius (Extortion & Protection Area)", "GRID_UI_Sub", 12, 8, Color(0, 220, 255))
        end

        local sliderInfRadius = vgui.Create("DNumSlider", pnlInfRadius)
        sliderInfRadius:SetPos(12, 30)
        sliderInfRadius:SetSize(frameW - 64, 32)
        sliderInfRadius:SetText("")
        sliderInfRadius:SetMin(200)
        sliderInfRadius:SetMax(4000)
        sliderInfRadius:SetDecimals(0)
        sliderInfRadius:SetValue(tonumber(configData.influence_radius) or tonumber(configData.radius) or 800)
        if IsValid(sliderInfRadius.Label) then sliderInfRadius.Label:SetVisible(false) end
        sliderInfRadius.OnValueChanged = function(s, val)
            GRID.MapSpawns.PreviewInfluenceRadius = val
        end

        -- 4. Default Controller / Faction Panel
        local pnlOwner = scroll:Add("DPanel")
        pnlOwner:Dock(TOP)
        pnlOwner:DockMargin(0, 0, 0, 14)
        pnlOwner:SetTall(68)
        pnlOwner.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(30, 41, 59, 140))
            draw.SimpleText("Initial / Default Controller", "GRID_UI_Sub", 12, 8, Color(0, 220, 255))
        end

        local cmbOwner = vgui.Create("DComboBox", pnlOwner)
        cmbOwner:SetPos(12, 32)
        cmbOwner:SetSize(frameW - 64, 28)
        cmbOwner:SetFont("GRID_UI_Body")
        cmbOwner:AddChoice("neutral", "neutral", (configData.owner or "neutral") == "neutral")
        cmbOwner:AddChoice("Police", "Police", (configData.owner or "") == "Police")

        -- Populate active gangs if any
        if GRID.Turf and GRID.Turf.Zones then
            local seenGangs = {}
            for _, z in pairs(GRID.Turf.Zones) do
                if z.owner and z.owner ~= "neutral" and z.owner ~= "Police" and not seenGangs[z.owner] then
                    seenGangs[z.owner] = true
                    cmbOwner:AddChoice(z.owner, z.owner, (configData.owner or "") == z.owner)
                end
            end
        end

        -- 5. Protection Tax Rate Panel
        local pnlTax = scroll:Add("DPanel")
        pnlTax:Dock(TOP)
        pnlTax:DockMargin(0, 0, 0, 14)
        pnlTax:SetTall(72)
        pnlTax.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(30, 41, 59, 140))
            draw.SimpleText("Protection Tax Rate (%)", "GRID_UI_Sub", 12, 8, Color(0, 220, 255))
        end

        local sliderTax = vgui.Create("DNumSlider", pnlTax)
        sliderTax:SetPos(12, 30)
        sliderTax:SetSize(frameW - 64, 32)
        sliderTax:SetText("")
        sliderTax:SetMin(0)
        sliderTax:SetMax(50)
        sliderTax:SetDecimals(0)
        sliderTax:SetValue(tonumber(configData.tax_rate) or 10)
        if IsValid(sliderTax.Label) then sliderTax.Label:SetVisible(false) end

        -- Save & Apply Button
        local btnSave = vgui.Create("DButton", configFrame)
        btnSave:SetSize(frameW - 40, 44)
        btnSave:SetPos(20, frameH - 56)
        btnSave:SetText("SAVE CONFIGURATION")
        btnSave:SetFont("GRID_UI_Btn")
        btnSave:SetTextColor(Color(15, 23, 42))
        btnSave.Paint = function(s, w, h)
            if s:IsHovered() then
                draw.RoundedBox(6, 0, 0, w, h, Color(0, 240, 255))
            else
                draw.RoundedBox(6, 0, 0, w, h, Color(0, 220, 255))
            end
        end
        btnSave.DoClick = function()
            local updatedData = {
                turf_id = configData.turf_id,
                name = txtName:GetText(),
                capture_radius = sliderCapRadius:GetValue(),
                influence_radius = sliderInfRadius:GetValue(),
                radius = sliderInfRadius:GetValue(),
                owner = cmbOwner:GetSelected() or "neutral",
                tax_rate = sliderTax:GetValue()
            }

            net.Start("GRID_SaveEntityConfig")
                net.WriteEntity(ent)
                net.WriteString(className)
                net.WriteString(util.TableToJSON(updatedData))
            net.SendToServer()

            configFrame:Close()
        end
    else
        -- Generic entity configuration placeholder panel
        local pnlGeneric = scroll:Add("DPanel")
        pnlGeneric:Dock(FILL)
        pnlGeneric.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(30, 41, 59, 140))
            draw.SimpleText("World Infrastructure Properties", "GRID_UI_Sub", 12, 12, Color(0, 220, 255))
            draw.SimpleText("Class: " .. className, "GRID_UI_Body", 12, 40, Color(248, 250, 252))
            draw.SimpleText("Pos: " .. tostring(ent:GetPos()), "GRID_UI_Body", 12, 65, Color(148, 163, 184))
            draw.SimpleText("Ang: " .. tostring(ent:GetAngles()), "GRID_UI_Body", 12, 90, Color(148, 163, 184))
        end

        local btnSave = vgui.Create("DButton", configFrame)
        btnSave:SetSize(frameW - 40, 44)
        btnSave:SetPos(20, frameH - 56)
        btnSave:SetText("CLOSE")
        btnSave:SetFont("GRID_UI_Btn")
        btnSave:SetTextColor(Color(15, 23, 42))
        btnSave.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(0, 220, 255))
        end
        btnSave.DoClick = function()
            configFrame:Close()
        end
    end
end

net.Receive("GRID_OpenEntityConfig", function()
    local ent = net.ReadEntity()
    local className = net.ReadString()
    local json = net.ReadString()

    local data = util.JSONToTable(json) or {}
    GRID.MapSpawns.OpenConfigUI(ent, className, data)
end)

