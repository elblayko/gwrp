--[[
    entities/entities/gw_flag_pole/cl_init.lua
    Crisp Holographic 3D2D Turf Billboard & Progressive Capture UI
--]]

include("shared.lua")

ENT.RenderGroup = RENDERGROUP_BOTH

-- Dedicated High-Legibility Fonts for 3D2D Display
surface.CreateFont("GW_Pole_Title", {
    font = "Roboto",
    size = 38,
    weight = 800,
    antialias = true
})
surface.CreateFont("GW_Pole_Sub", {
    font = "Roboto",
    size = 24,
    weight = 700,
    antialias = true
})
surface.CreateFont("GW_Pole_Body", {
    font = "Roboto",
    size = 20,
    weight = 500,
    antialias = true
})
surface.CreateFont("GW_Pole_Btn", {
    font = "Roboto",
    size = 22,
    weight = 800,
    antialias = true
})

function ENT:DrawBillboard()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local eyePos = ply:EyePos()
    local polePos = self:GetPos()
    local distSqr = eyePos:DistToSqr(polePos)
    if distSqr > (950 * 950) then return end

    local dist = math.sqrt(distSqr)
    local alpha = 255
    if dist > 750 then
        alpha = math.Clamp(math.Remap(dist, 750, 950, 255, 0), 0, 255)
    end
    if alpha <= 5 then return end
    alpha = math.floor(alpha)

    local id = self:GetTurfID()
    local zones = GW.Turf and GW.Turf.Zones
    local zone = zones and zones[id]
    local zoneName = zone and zone.name or ("Territory #" .. id)
    local turfData = GW.TurfData and GW.TurfData[id]
    local data = turfData or (zone and { owner = zone.owner, progress = zone.progress or 100 } or { owner = "neutral", progress = 100 })

    local owner = data.owner
    local isNeutral = (not owner or owner == "" or owner == "neutral")
    local ownerStr = isNeutral and "Unclaimed" or owner
    local gangCol = GW.GetGangColor and GW.GetGangColor(owner) or Color(148, 163, 184)

    -- Capture State
    local isCapturing = self:GetIsCapturing()
    local capturingGang = self:GetCapturingGang()
    local capturingPly = self:GetCapturingPlayer()
    local capSt = self:GetCaptureStartTime()
    local capEt = self:GetCaptureEndTime()
    local capProgress = 0
    if isCapturing and capEt > capSt then
        capProgress = math.Clamp((CurTime() - capSt) / (capEt - capSt), 0, 1)
    end

    local capCol = GW.GetGangColor and GW.GetGangColor(capturingGang) or Color(245, 158, 11)

    -- Local player relationship
    local plyGang = ply.GetGang and ply:GetGang() or ""
    local plyFaction = ply.GetFaction and ply:GetFaction()
    local isOwner = false
    if not isNeutral then
        if plyGang ~= "" and string.lower(plyGang) == string.lower(owner) then
            isOwner = true
        elseif plyFaction and plyFaction.id == "police" and string.lower(owner) == "police" then
            isOwner = true
        end
    end

    local isMyCapture = isCapturing and (capturingPly == ply)
    local isTeammateCapture = false
    if isCapturing and not isMyCapture then
        if plyGang ~= "" and string.lower(plyGang) == string.lower(capturingGang) then
            isTeammateCapture = true
        elseif plyFaction and plyFaction.id == "police" and string.lower(capturingGang) == "police" then
            isTeammateCapture = true
        end
    end

    -- Project billboard outward from pole center facing toward player camera
    local toPlayer = (eyePos - polePos)
    toPlayer.z = 0
    toPlayer:Normalize()

    -- 22 units outward clears utility pole geometry
    local billboardPos = polePos + Vector(0, 0, 115) + toPlayer * 22

    -- Angle oriented with normal facing directly to player (+90 ensures proper text winding)
    local ang = toPlayer:Angle()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    local cardW, cardH = 460, 220
    local halfW, halfH = cardW / 2, cardH / 2
    local scale = 0.085

    cam.Start3D2D(billboardPos, ang, scale)
        -- Glassmorphic Dark Slate Background
        draw.RoundedBox(8, -halfW, -halfH, cardW, cardH, Color(11, 15, 25, math.min(245, alpha)))

        -- Accent Top Border
        local activeBorderCol = isCapturing and capCol or gangCol
        draw.RoundedBoxEx(8, -halfW, -halfH, cardW, 5, activeBorderCol, true, true, false, false)
        surface.SetDrawColor(activeBorderCol.r, activeBorderCol.g, activeBorderCol.b, math.min(100, alpha))
        surface.DrawOutlinedRect(-halfW, -halfH, cardW, cardH, 2)

        -- Territory Title
        draw.SimpleText(zoneName, "GW_Pole_Title", 0, -halfH + 30, Color(248, 250, 252, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Status Pill
        local pillW, pillH = 360, 32
        local pillY = -halfH + 56
        draw.RoundedBox(4, -pillW / 2, pillY, pillW, pillH, Color(24, 32, 47, alpha))
        draw.RoundedBox(4, -pillW / 2, pillY, 5, pillH, activeBorderCol)

        local statusText = ""
        local statusCol = gangCol
        if isCapturing then
            local pulse = (math.sin(CurTime() * 8) + 1) * 0.5
            statusCol = Color(capCol.r, capCol.g, capCol.b, math.floor(180 + pulse * 75))
            statusText = string.format("CONTESTING: %s (%d%%)", string.upper(capturingGang), math.floor(capProgress * 100))
        elseif isNeutral then
            statusText = "UNCLAIMED TERRITORY"
            statusCol = Color(251, 191, 36, alpha)
        else
            statusText = "CONTROLLED BY: " .. string.upper(ownerStr)
            statusCol = gangCol
        end
        draw.SimpleText(statusText, "GW_Pole_Sub", 0, pillY + pillH / 2, statusCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Real-time Progressive Capture Bar
        local barW, barH = 390, 10
        local barY = -halfH + 104
        draw.RoundedBox(4, -barW / 2, barY, barW, barH, Color(30, 41, 59, alpha))

        if isCapturing then
            -- Smooth animated capture fill
            local fillW = math.max(0, barW * capProgress)
            draw.RoundedBox(4, -barW / 2, barY, fillW, barH, capCol)
        else
            -- Static owner hold bar
            local holdProgress = math.Clamp((data.progress or 100) / 100, 0, 1)
            if holdProgress > 0 and not isNeutral then
                draw.RoundedBox(4, -barW / 2, barY, barW * holdProgress, barH, gangCol)
            end
        end

        -- Turf Dividends Info
        local dividendAmt = (GW.Config and GW.Config.TurfDividendAmount) or 25
        local dividendText = "Yields +$" .. dividendAmt .. "/m to controlling gang"
        draw.SimpleText(dividendText, "GW_Pole_Body", 0, -halfH + 130, Color(148, 163, 184, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Interaction / Progress Button
        local btnW, btnH = 380, 36
        local btnY = -halfH + 158
        local btnBg, btnBorder, btnText, btnCol

        if isCapturing then
            local pct = math.floor(capProgress * 100)
            if isMyCapture then
                btnBg = Color(34, 197, 94, math.min(55, alpha))
                btnBorder = Color(34, 197, 94, math.min(220, alpha))
                btnText = string.format("HOLDING POSITION (%d%%) - Stay Close!", pct)
                btnCol = Color(74, 222, 128, alpha)
            elseif isTeammateCapture then
                btnBg = Color(56, 189, 248, math.min(55, alpha))
                btnBorder = Color(56, 189, 248, math.min(220, alpha))
                btnText = string.format("ALLY CAPTURING (%d%%) - Guard Area!", pct)
                btnCol = Color(125, 211, 252, alpha)
            else
                btnBg = Color(239, 68, 68, math.min(65, alpha))
                btnBorder = Color(239, 68, 68, math.min(240, alpha))
                btnText = string.format("CONTESTED BY %s (%d%%) - Intercept!", string.upper(capturingGang), pct)
                btnCol = Color(248, 113, 113, alpha)
            end
        elseif isOwner then
            btnBg = Color(34, 197, 94, math.min(45, alpha))
            btnBorder = Color(34, 197, 94, math.min(180, alpha))
            btnText = "Controlled by your gang"
            btnCol = Color(74, 222, 128, alpha)
        elseif isNeutral then
            btnBg = Color(245, 158, 11, math.min(45, alpha))
            btnBorder = Color(245, 158, 11, math.min(180, alpha))
            btnText = "Press [E] to claim territory"
            btnCol = Color(251, 191, 36, alpha)
        else
            btnBg = Color(239, 68, 68, math.min(45, alpha))
            btnBorder = Color(239, 68, 68, math.min(180, alpha))
            btnText = "Press [E] to contest territory"
            btnCol = Color(248, 113, 113, alpha)
        end

        draw.RoundedBox(4, -btnW / 2, btnY, btnW, btnH, btnBg)
        surface.SetDrawColor(btnBorder.r, btnBorder.g, btnBorder.b, btnBorder.a)
        surface.DrawOutlinedRect(-btnW / 2, btnY, btnW, btnH, 1)
        draw.SimpleText(btnText, "GW_Pole_Btn", 0, btnY + btnH / 2, btnCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

function ENT:Draw()
    self:DrawModel()
    self:DrawBillboard()
    self.LastDrawnFrame = FrameNumber()
end

function ENT:DrawTranslucent()
    if self.LastDrawnFrame == FrameNumber() then return end
    self.LastDrawnFrame = FrameNumber()
    self:DrawBillboard()
end

-- ========================================================
-- Client Screen HUD Progress Bar (Matches Lockpicking UX)
-- ========================================================

hook.Add("HUDPaint", "GW_TurfCapture_LockpickHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    -- Find if local player is capturing any turf flag pole
    local activePole = nil
    for _, ent in ipairs(ents.FindByClass("gw_flag_pole")) do
        if IsValid(ent) and ent:GetIsCapturing() and ent:GetCapturingPlayer() == ply then
            activePole = ent
            break
        end
    end

    if not IsValid(activePole) then return end

    local st = activePole:GetCaptureStartTime()
    local et = activePole:GetCaptureEndTime()
    if et <= st then return end

    local progress = math.Clamp((CurTime() - st) / (et - st), 0, 1)
    local turfId = activePole:GetTurfID()
    local zone = GW.Turf and GW.Turf.Zones and GW.Turf.Zones[turfId]
    local zoneName = zone and zone.name or ("Territory #" .. turfId)
    local gangName = activePole:GetCapturingGang()
    local gangCol = GW.GetGangColor and GW.GetGangColor(gangName) or Color(245, 158, 11)

    local w, h = 340, 48
    local x = (ScrW() - w) / 2
    local y = ScrH() / 2 + 75

    -- Modern Progress Frame (matches lockpick HUD styling)
    draw.RoundedBox(6, x, y, w, h, Color(11, 15, 25, 245))
    surface.SetDrawColor(gangCol.r, gangCol.g, gangCol.b, 200)
    surface.DrawOutlinedRect(x, y, w, h, 2)

    -- Progress Fill
    local fillW = math.max(0, (w - 8) * progress)
    draw.RoundedBox(4, x + 4, y + 4, fillW, h - 8, Color(gangCol.r, gangCol.g, gangCol.b, 220))

    -- Progress Label
    local pct = math.floor(progress * 100)
    local txt = string.format("Contesting %s: %d%%", zoneName, pct)
    draw.SimpleText(txt, "GW_UI_Btn", ScrW() / 2, y + 15, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("Stay close to the flag pole!", "GW_UI_Caption", ScrW() / 2, y + 33, Color(203, 213, 225, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
