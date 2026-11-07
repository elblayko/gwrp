--[[
    entities/entities/grid_flag_pole/cl_init.lua
    Crisp Holographic 3D2D Turf Billboard & Progressive Capture UI
--]]

include("shared.lua")

ENT.RenderGroup = RENDERGROUP_BOTH

-- Dedicated High-Legibility Fonts for 3D2D Display
surface.CreateFont("GRID_Pole_Title", {
    font = "Roboto",
    size = 38,
    weight = 800,
    antialias = true,
    extended = true
})
surface.CreateFont("GRID_Pole_Sub", {
    font = "Roboto",
    size = 24,
    weight = 700,
    antialias = true,
    extended = true
})
surface.CreateFont("GRID_Pole_Body", {
    font = "Roboto",
    size = 20,
    weight = 500,
    antialias = true,
    extended = true
})
surface.CreateFont("GRID_Pole_Btn", {
    font = "Roboto",
    size = 22,
    weight = 800,
    antialias = true,
    extended = true
})

function ENT:DrawBillboardContents(pos, ang, alpha)
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local a = math.floor(math.Clamp(alpha or 255, 0, 255))
    if a <= 0 then return end

    local id = self:GetTurfID()
    local zones = GRID.Turf and GRID.Turf.Zones
    local zone = zones and zones[id]
    local nwName = self:GetNWString("GRID_ZoneName", "")
    local nwOwner = self:GetNWString("GRID_ZoneOwner", "")
    local nwTax = self:GetNWInt("GRID_TaxRate", 10)
    local zoneName = (zone and zone.name) or (nwName ~= "" and nwName) or ("Territory #" .. id)
    local turfData = GRID.TurfData and GRID.TurfData[id]
    local data = turfData or (zone and { owner = zone.owner, progress = zone.progress or 100, tax_rate = zone.tax_rate or 10 } or { owner = (nwOwner ~= "" and nwOwner) or "neutral", progress = 100, tax_rate = nwTax })

    local owner = data.owner
    local isNeutral = (not owner or owner == "" or owner == "neutral")
    local ownerStr = isNeutral and "Unclaimed" or owner
    local gangCol = GRID.GetGangColor and GRID.GetGangColor(owner) or Color(148, 163, 184)

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

    local capCol = GRID.GetGangColor and GRID.GetGangColor(capturingGang) or Color(245, 158, 11)

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

    local cardW, cardH = 380, 170
    local halfW, halfH = cardW / 2, cardH / 2

    -- Glassmorphic Dark Slate Background
    draw.RoundedBox(8, -halfW, -halfH, cardW, cardH, Color(11, 15, 25, math.min(245, a)))

    -- Accent Top Border
    local activeBorderCol = isCapturing and capCol or gangCol
    draw.RoundedBoxEx(8, -halfW, -halfH, cardW, 4, activeBorderCol, true, true, false, false)
    surface.SetDrawColor(activeBorderCol.r, activeBorderCol.g, activeBorderCol.b, math.min(120, a))
    surface.DrawOutlinedRect(-halfW, -halfH, cardW, cardH, 1)

    -- Territory Title
    draw.SimpleText(zoneName, "GRID_UI_Header", 0, -halfH + 22, Color(248, 250, 252, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Status Pill
    local pillW, pillH = 320, 26
    local pillY = -halfH + 42
    draw.RoundedBox(4, -pillW / 2, pillY, pillW, pillH, Color(24, 32, 47, a))
    draw.RoundedBox(4, -pillW / 2, pillY, 4, pillH, activeBorderCol)

    local statusText = ""
    local statusCol = gangCol
    if isCapturing then
        local pulse = (math.sin(CurTime() * 8) + 1) * 0.5
        statusCol = Color(capCol.r, capCol.g, capCol.b, math.floor(180 + pulse * 75))
        statusText = string.format("CONTESTING: %s (%d%%)", string.upper(capturingGang), math.floor(capProgress * 100))
    elseif isNeutral then
        statusText = "UNCLAIMED TERRITORY"
        statusCol = Color(251, 191, 36, a)
    else
        statusText = "CONTROLLED BY: " .. string.upper(ownerStr)
        statusCol = gangCol
    end
    draw.SimpleText(statusText, "GRID_UI_Badge", 0, pillY + pillH / 2, statusCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Real-time Progressive Capture Bar
    local barW, barH = 340, 8
    local barY = -halfH + 76
    draw.RoundedBox(4, -barW / 2, barY, barW, barH, Color(30, 41, 59, a))

    if isCapturing then
        local fillW = math.max(0, barW * capProgress)
        draw.RoundedBox(4, -barW / 2, barY, fillW, barH, capCol)
    else
        local holdProgress = math.Clamp((data.progress or 100) / 100, 0, 1)
        if holdProgress > 0 and not isNeutral then
            draw.RoundedBox(4, -barW / 2, barY, barW * holdProgress, barH, gangCol)
        end
    end

    -- Turf Dividends Info
    local dividendAmt = (GRID.Config and GRID.Config.TurfDividendAmount) or 25
    local taxRate = data.tax_rate or (zone and zone.tax_rate) or 10
    local dividendText
    if ownerStr == "Police" then
        dividendText = string.format("Secured Police District | Stipend: +$%d/m", dividendAmt)
    elseif not isNeutral then
        dividendText = string.format("Yield: +$%d/m | Extortion Tax: %d%%", dividendAmt, taxRate)
    else
        dividendText = string.format("Yields +$%d/m to controlling syndicate", dividendAmt)
    end
    draw.SimpleText(dividendText, "GRID_UI_Caption", 0, -halfH + 96, Color(148, 163, 184, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Interaction / Progress Button
    local btnW, btnH = 340, 32
    local btnY = -halfH + 118
    local btnBg, btnBorder, btnText, btnCol

    if isCapturing then
        local pct = math.floor(capProgress * 100)
        if isMyCapture then
            btnBg = Color(34, 197, 94, math.min(55, a))
            btnBorder = Color(34, 197, 94, math.min(220, a))
            btnText = string.format("HOLDING POSITION (%d%%) - Stay Close!", pct)
            btnCol = Color(74, 222, 128, a)
        elseif isTeammateCapture then
            btnBg = Color(56, 189, 248, math.min(55, a))
            btnBorder = Color(56, 189, 248, math.min(220, a))
            btnText = string.format("ALLY CAPTURING (%d%%) - Guard Area!", pct)
            btnCol = Color(125, 211, 252, a)
        else
            btnBg = Color(239, 68, 68, math.min(65, a))
            btnBorder = Color(239, 68, 68, math.min(240, a))
            btnText = string.format("CONTESTED BY %s (%d%%) - Intercept!", string.upper(capturingGang), pct)
            btnCol = Color(248, 113, 113, a)
        end
    elseif isOwner then
        btnBg = Color(34, 197, 94, math.min(45, a))
        btnBorder = Color(34, 197, 94, math.min(180, a))
        if ownerStr == "Police" then
            btnText = "Secured Police Jurisdiction"
        else
            local isLeader = ply:GetNWBool("GRID_IsGangLeader", false) or (ply.GetJob and ply:GetJob() == "gang_leader") or ply:IsAdmin()
            btnText = isLeader and string.format("[E] Manage Extortion Tax (%d%%)", taxRate) or string.format("Controlled by your gang (Tax: %d%%)", taxRate)
        end
        btnCol = Color(74, 222, 128, a)
    elseif isNeutral then
        btnBg = Color(245, 158, 11, math.min(45, a))
        btnBorder = Color(245, 158, 11, math.min(180, a))
        local plyFaction = ply.GetFaction and ply:GetFaction()
        local isPolice = plyFaction and plyFaction.id == "police"
        btnText = isPolice and "[E] Secure District for Police" or "[E] Claim Territory for Gang"
        btnCol = Color(251, 191, 36, a)
    else
        btnBg = Color(239, 68, 68, math.min(45, a))
        btnBorder = Color(239, 68, 68, math.min(180, a))
        btnText = "[E] Contest Territory"
        btnCol = Color(248, 113, 113, a)
    end

    draw.RoundedBox(4, -btnW / 2, btnY, btnW, btnH, btnBg)
    surface.SetDrawColor(btnBorder.r, btnBorder.g, btnBorder.b, btnBorder.a)
    surface.DrawOutlinedRect(-btnW / 2, btnY, btnW, btnH, 1)
    draw.SimpleText(btnText, "GRID_UI_Btn", 0, btnY + btnH / 2, btnCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- ENT:Draw is inherited from grid_base_interactive, calling ENT.OverheadConfig.CustomDraw (DrawBillboardContents)

-- ========================================================
-- Client Screen HUD Progress Bar (Matches Lockpicking UX)
-- ========================================================

hook.Add("HUDPaint", "GRID_TurfCapture_LockpickHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    -- Find if local player is capturing any turf flag pole
    local activePole = nil
    for _, ent in ipairs(ents.FindByClass("grid_flag_pole")) do
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
    local zone = GRID.Turf and GRID.Turf.Zones and GRID.Turf.Zones[turfId]
    local zoneName = zone and zone.name or ("Territory #" .. turfId)
    local gangName = activePole:GetCapturingGang()
    local gangCol = GRID.GetGangColor and GRID.GetGangColor(gangName) or Color(245, 158, 11)

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
    draw.SimpleText(txt, "GRID_UI_Btn", ScrW() / 2, y + 15, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("Stay close to the flag pole!", "GRID_UI_Caption", ScrW() / 2, y + 33, Color(203, 213, 225, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
