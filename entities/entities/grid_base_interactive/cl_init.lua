--[[
    entities/entities/grid_base_interactive/cl_init.lua
    GridRP Unified Interactive Base Entity - Client Rendering & HUD
    Author: GRID Core Team & Antigravity
--]]

include("shared.lua")

local cachedSightTraces = {}

--- Performs a cached line-of-sight trace to prevent rendering 3D2D through walls
local function HasLineOfSight(ent, startPos, endPos)
    local idx = ent:EntIndex()
    local now = CurTime()
    local cached = cachedSightTraces[idx]
    if cached and cached.time > now then
        return cached.visible
    end

    local tr = util.TraceLine({
        start = startPos,
        endpos = endPos,
        filter = { LocalPlayer(), ent },
        mask = MASK_OPAQUE
    })

    local isVisible = not tr.Hit
    cachedSightTraces[idx] = {
        visible = isVisible,
        time = now + 0.15 + (idx % 5) * 0.02
    }
    return isVisible
end

-- --------------------------------------------------------
-- In-World 3D2D Overhead / Surface Rendering
-- --------------------------------------------------------
function ENT:Draw()
    self:DrawModel()

    local cfg = self.OverheadConfig
    if not cfg then return end

    local isEnabled = cfg.Enabled
    if isfunction(isEnabled) then
        isEnabled = isEnabled(self)
    end
    if isEnabled == false then return end

    if cfg.ShouldDraw and isfunction(cfg.ShouldDraw) and not cfg.ShouldDraw(self) then
        return
    end

    -- If default overhead has no content to display, suppress rendering completely
    if not cfg.CustomDraw then
        local testTitle = cfg.GetTitle and cfg.GetTitle(self) or (cfg.Title or self.PrintName or "")
        local testCustom = cfg.GetCustomText and cfg.GetCustomText(self) or ""
        local hasTitle = isstring(testTitle) and string.Trim(testTitle) ~= ""
        local hasCustom = isstring(testCustom) and string.Trim(testCustom) ~= ""

        if not hasTitle and not hasCustom then
            return
        end
    end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local eyePos = EyePos()
    local entPos = self:GetPos()
    local distSqr = eyePos:DistToSqr(entPos)

    local maxDist = cfg.MaxDistance or 450
    if distSqr > (maxDist * maxDist) then return end

    local dist = math.sqrt(distSqr)
    local fadeStart = cfg.FadeStart or 300
    local alpha = 255
    if dist > fadeStart then
        alpha = math.Clamp((1 - (dist - fadeStart) / math.max(1, maxDist - fadeStart)) * 255, 0, 255)
    end
    if alpha <= 0 then return end

    local renderPos
    local renderAng

    if cfg.FaceCamera then
        local offset = cfg.Offset or Vector(0, 0, 48)
        renderPos = entPos + offset

        if not HasLineOfSight(self, eyePos, renderPos) then return end

        local toCamera = (eyePos - renderPos):Angle()
        renderAng = Angle(0, toCamera.y - 90, 90)
    else
        local localOffset = cfg.Offset or Vector(0, 0, 15)
        local worldOffset = self:GetForward() * localOffset.x + self:GetRight() * localOffset.y + self:GetUp() * localOffset.z
        renderPos = entPos + worldOffset

        if not HasLineOfSight(self, eyePos, renderPos) then return end

        renderAng = self:GetAngles()
        local angOffset = cfg.AngleOffset or Angle(0, 0, 0)
        if angOffset.p ~= 0 then renderAng:RotateAroundAxis(renderAng:Right(), angOffset.p) end
        if angOffset.y ~= 0 then renderAng:RotateAroundAxis(renderAng:Up(), angOffset.y) end
        if angOffset.r ~= 0 then renderAng:RotateAroundAxis(renderAng:Forward(), angOffset.r) end
    end

    local scale = cfg.Scale or 0.05

    cam.Start3D2D(renderPos, renderAng, scale)
        if cfg.CustomDraw and isfunction(cfg.CustomDraw) then
            cfg.CustomDraw(self, renderPos, renderAng, alpha)
        else
            self:DrawDefaultOverhead(alpha, cfg)
        end
    cam.End3D2D()
end

function ENT:DrawDefaultOverhead(alpha, cfg)
    local title = cfg.GetTitle and cfg.GetTitle(self) or self.PrintName or "Interactive Node"
    local col = cfg.GetColor and cfg.GetColor(self) or Color(52, 211, 153)
    local customText = cfg.GetCustomText and cfg.GetCustomText(self)

    local hasTitle = isstring(title) and string.Trim(title) ~= ""
    local hasCustom = isstring(customText) and string.Trim(customText) ~= ""

    -- If there is nothing to say, do not draw an empty floating box
    if not hasTitle and not hasCustom then return end

    local cardW = 300
    local cardH = hasCustom and 92 or 64
    local cardX = -cardW / 2
    local cardY = -cardH / 2

    -- Card Background
    draw.RoundedBox(8, cardX, cardY, cardW, cardH, Color(11, 15, 25, math.floor(alpha * 0.94)))
    surface.SetDrawColor(col.r, col.g, col.b, math.floor(alpha * 0.8))
    surface.DrawOutlinedRect(cardX, cardY, cardW, cardH, 2)

    -- Top Accent Bar
    draw.RoundedBoxEx(8, cardX, cardY, cardW, 4, Color(col.r, col.g, col.b, alpha), true, true, false, false)

    -- Title
    if hasTitle then
        local titleY = hasCustom and (cardY + 26) or (cardY + cardH / 2)
        draw.SimpleText(title, "GRID_FontMedium", 0, titleY, Color(248, 250, 252, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Optional Subtitle or Dynamic Text
    if hasCustom then
        draw.SimpleText(customText, "GRID_FontSmall", 0, cardY + 62, Color(148, 163, 184, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

-- --------------------------------------------------------
-- Centralized Look-At Raytrace HUD Prompt Engine
-- --------------------------------------------------------
local currentLookEntity = nil
local hudAlpha = 0

hook.Add("HUDPaint", "GRID_InteractiveBase_HUDPaint", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then
        currentLookEntity = nil
        hudAlpha = 0
        return
    end

    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    local isValidTarget = false

    if IsValid(target) and target.IsGridInteractive then
        local cfg = target.InteractionConfig
        if cfg and cfg.Enabled ~= false then
            local maxDist = cfg.MaxUseDistance or 120
            if tr.HitPos:DistToSqr(ply:EyePos()) <= (maxDist * maxDist) then
                isValidTarget = true
                currentLookEntity = target
            end
        end
    end

    local targetAlpha = isValidTarget and 255 or 0
    hudAlpha = Lerp(FrameTime() * 12, hudAlpha, targetAlpha)

    if hudAlpha <= 1 or not IsValid(currentLookEntity) then
        return
    end

    local ent = currentLookEntity
    local cfg = ent.InteractionConfig or {}

    local showBar = false
    if isfunction(cfg.ShowProgressBar) then
        showBar = cfg.ShowProgressBar(ent, ply)
    elseif cfg.ShowProgressBar ~= nil then
        showBar = (cfg.ShowProgressBar == true)
    end

    local scrW = ScrW()
    local scrH = ScrH()
    local cardW = 360
    local cardH = showBar and 132 or 94
    local cardX = (scrW - cardW) / 2
    local cardY = (scrH / 2) + 38

    local badge = cfg.GetBadge and cfg.GetBadge(ent, ply) or (cfg.Badge or "INTERACTIVE")
    local badgeCol = cfg.GetBadgeColor and cfg.GetBadgeColor(ent, ply) or Color(52, 211, 153)
    local title = cfg.GetTitle and cfg.GetTitle(ent, ply) or (ent.PrintName or "Interactive Entity")
    local subtext = cfg.GetSubtext and cfg.GetSubtext(ent, ply) or (cfg.Subtext or "")

    local a = math.floor(hudAlpha)

    -- Card Background
    draw.RoundedBox(8, cardX, cardY, cardW, cardH, Color(11, 15, 25, math.floor(a * 0.95)))
    surface.SetDrawColor(badgeCol.r, badgeCol.g, badgeCol.b, math.floor(a * 0.8))
    surface.DrawOutlinedRect(cardX, cardY, cardW, cardH, 1)

    -- Top Accent Line
    draw.RoundedBoxEx(8, cardX, cardY, cardW, 3, Color(badgeCol.r, badgeCol.g, badgeCol.b, a), true, true, false, false)

    -- Status Pill
    surface.SetFont("GRID_UI_Badge")
    local bTextW = surface.GetTextSize(badge)
    local pillW = bTextW + 16
    draw.RoundedBox(4, cardX + 12, cardY + 10, pillW, 22, Color(badgeCol.r, badgeCol.g, badgeCol.b, math.floor(a * 0.2)))
    surface.SetDrawColor(badgeCol.r, badgeCol.g, badgeCol.b, math.floor(a * 0.7))
    surface.DrawOutlinedRect(cardX + 12, cardY + 10, pillW, 22, 1)
    draw.SimpleText(badge, "GRID_UI_Badge", cardX + 12 + pillW / 2, cardY + 21, Color(badgeCol.r, badgeCol.g, badgeCol.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Entity Name
    draw.SimpleText(title, "GRID_UI_Header", cardX + pillW + 22, cardY + 21, Color(248, 250, 252, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Subtitle / Description
    if subtext ~= "" then
        draw.SimpleText(subtext, "GRID_UI_Caption", cardX + 14, cardY + 44, Color(148, 163, 184, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Progress Bar or Sweet-Spot Minigame
    if showBar then
        local barW = cardW - 28
        local barH = 16
        local barX = cardX + 14
        local barY = cardY + 74

        -- Check if entity provides Sweet-Spot Needle Minigame logic
        local hasSweetSpot = false
        if cfg.GetSweetSpot then
            local sMin, sMax, inZone, needleProg, hintText, barTitle = cfg.GetSweetSpot(ent, ply)
            if sMin and sMax and needleProg then
                hasSweetSpot = true

                -- Labels placed above the bar so the sweet spot and needle are never obstructed
                local leftLabel = barTitle or "EXHAUST PRESSURE"
                local rightLabel = hintText or (inZone and "HIT [E] NOW!" or "TIMING WINDOW")
                local rightCol = inZone and Color(52, 211, 153, a) or Color(251, 191, 36, a)

                draw.SimpleText(leftLabel, "GRID_UI_Caption", barX, cardY + 62, Color(148, 163, 184, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(rightLabel, "GRID_UI_Badge", barX + barW, cardY + 62, rightCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

                -- Background Track
                draw.RoundedBox(4, barX, barY, barW, barH, Color(17, 24, 39, a))
                surface.SetDrawColor(30, 41, 59, math.floor(a * 0.8))
                surface.DrawOutlinedRect(barX, barY, barW, barH, 1)

                -- Draw Green Sweet-Spot Zone
                local sx = barX + math.floor(sMin * barW)
                local sw = math.max(6, math.floor((sMax - sMin) * barW))
                draw.RoundedBox(2, sx, barY + 2, sw, barH - 4, Color(52, 211, 153, math.floor(a * 0.85)))

                -- Draw Moving Needle Cursor
                local nx = barX + math.floor(needleProg * barW)
                local needleCol = inZone and Color(52, 211, 153, a) or Color(251, 191, 36, a)
                draw.RoundedBox(2, nx - 2, barY - 2, 4, barH + 4, needleCol)
            end
        end

        -- Standard Progress Bar Fallback
        if not hasSweetSpot and cfg.GetProgress then
            local progress, progTxt = cfg.GetProgress(ent, ply)

            -- Status text placed above the bar
            if progTxt and progTxt ~= "" then
                draw.SimpleText(progTxt, "GRID_UI_Caption", barX, cardY + 62, Color(248, 250, 252, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            -- Background Track
            draw.RoundedBox(4, barX, barY, barW, barH, Color(17, 24, 39, a))
            surface.SetDrawColor(30, 41, 59, math.floor(a * 0.8))
            surface.DrawOutlinedRect(barX, barY, barW, barH, 1)

            if progress and progress > 0 then
                local fillW = math.Clamp(math.floor(barW * progress), 4, barW)
                draw.RoundedBox(4, barX, barY, fillW, barH, Color(badgeCol.r, badgeCol.g, badgeCol.b, a))
            end
        end
    end

    -- Interaction Action Keycaps Row
    local primaryKey = cfg.PrimaryKey
    if isfunction(primaryKey) then
        primaryKey = primaryKey(ent, ply)
    end
    if not isstring(primaryKey) or primaryKey == "" then
        primaryKey = "E"
    end

    local primaryAction = cfg.PrimaryAction
    if isfunction(primaryAction) then
        primaryAction = primaryAction(ent, ply)
    end
    if not isstring(primaryAction) or primaryAction == "" then
        primaryAction = "Interact"
    end

    local secondaryKey = cfg.SecondaryKey
    if isfunction(secondaryKey) then
        secondaryKey = secondaryKey(ent, ply)
    end

    local secondaryAction = cfg.SecondaryAction
    if isfunction(secondaryAction) then
        secondaryAction = secondaryAction(ent, ply)
    end

    local footerY = cardY + cardH - 18

    -- Draw Primary Action Keycap
    surface.SetFont("GRID_UI_Badge")
    local pKeyW = surface.GetTextSize(primaryKey) + 16
    draw.RoundedBox(4, cardX + 14, footerY - 10, pKeyW, 20, Color(badgeCol.r, badgeCol.g, badgeCol.b, math.floor(a * 0.25)))
    surface.SetDrawColor(badgeCol.r, badgeCol.g, badgeCol.b, math.floor(a * 0.8))
    surface.DrawOutlinedRect(cardX + 14, footerY - 10, pKeyW, 20, 1)
    draw.SimpleText(primaryKey, "GRID_UI_Badge", cardX + 14 + pKeyW / 2, footerY, Color(248, 250, 252, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(primaryAction, "GRID_UI_Btn", cardX + 14 + pKeyW + 8, footerY, Color(203, 213, 225, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Draw Secondary Action Keycap if defined
    if isstring(secondaryKey) and isstring(secondaryAction) and secondaryKey ~= "" and secondaryAction ~= "" then
        local sKeyW = surface.GetTextSize(secondaryKey) + 16
        local sActW = surface.GetTextSize(secondaryAction)
        local totalSecW = sKeyW + 8 + sActW
        local sX = cardX + cardW - totalSecW - 14

        draw.RoundedBox(4, sX, footerY - 10, sKeyW, 20, Color(251, 191, 36, math.floor(a * 0.25)))
        surface.SetDrawColor(251, 191, 36, math.floor(a * 0.8))
        surface.DrawOutlinedRect(sX, footerY - 10, sKeyW, 20, 1)
        draw.SimpleText(secondaryKey, "GRID_UI_Badge", sX + sKeyW / 2, footerY, Color(248, 250, 252, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(secondaryAction, "GRID_UI_Btn", sX + sKeyW + 8, footerY, Color(203, 213, 225, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end)


