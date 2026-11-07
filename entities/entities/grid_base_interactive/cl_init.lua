--[[
    entities/entities/grid_base_interactive/cl_init.lua
    GridRP Unified Interactive Base Entity - Client Rendering & HUD
    Author: GRID Core Team & Antigravity
--]]

include("shared.lua")

surface.CreateFont("GRID_Base_3D_Title", {
    font = "Trebuchet MS",
    size = 28,
    weight = 800,
    antialias = true
})

surface.CreateFont("GRID_Base_3D_Sub", {
    font = "Roboto",
    size = 18,
    weight = 600,
    antialias = true
})

surface.CreateFont("GRID_Base_HUD_Key", {
    font = "Trebuchet MS",
    size = 15,
    weight = 800,
    antialias = true
})

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
    if not cfg or cfg.Enabled == false then return end

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

    local cardW = 280
    local cardH = customText and 84 or 56
    local cardX = -cardW / 2
    local cardY = -cardH / 2

    -- Card Background
    draw.RoundedBox(8, cardX, cardY, cardW, cardH, Color(15, 23, 42, math.floor(alpha * 0.94)))
    surface.SetDrawColor(col.r, col.g, col.b, math.floor(alpha * 0.8))
    surface.DrawOutlinedRect(cardX, cardY, cardW, cardH, 2)

    -- Top Accent Bar
    draw.RoundedBoxEx(8, cardX, cardY, cardW, 4, Color(col.r, col.g, col.b, alpha), true, true, false, false)

    -- Title
    local titleY = customText and (cardY + 22) or (cardY + cardH / 2)
    draw.SimpleText(title, "GRID_Base_3D_Title", 0, titleY, Color(248, 250, 252, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Optional Subtitle or Dynamic Text
    if customText then
        draw.SimpleText(customText, "GRID_Base_3D_Sub", 0, cardY + 54, Color(148, 163, 184, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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

    local scrW = ScrW()
    local scrH = ScrH()
    local cardW = 340
    local cardH = cfg.ShowProgressBar and 108 or 88
    local cardX = (scrW - cardW) / 2
    local cardY = (scrH / 2) + 40

    local badge = cfg.GetBadge and cfg.GetBadge(ent, ply) or (cfg.Badge or "INTERACTIVE")
    local badgeCol = cfg.GetBadgeColor and cfg.GetBadgeColor(ent, ply) or Color(52, 211, 153)
    local title = cfg.GetTitle and cfg.GetTitle(ent, ply) or (ent.PrintName or "Interactive Entity")
    local subtext = cfg.GetSubtext and cfg.GetSubtext(ent, ply) or (cfg.Subtext or "")

    local a = math.floor(hudAlpha)

    -- Card Background
    draw.RoundedBox(8, cardX, cardY, cardW, cardH, Color(11, 15, 25, math.floor(a * 0.95)))
    surface.SetDrawColor(badgeCol.r, badgeCol.g, badgeCol.b, math.floor(a * 0.75))
    surface.DrawOutlinedRect(cardX, cardY, cardW, cardH, 1)

    -- Top Accent Line
    draw.RoundedBoxEx(8, cardX, cardY, cardW, 3, Color(badgeCol.r, badgeCol.g, badgeCol.b, a), true, true, false, false)

    -- Status Pill
    surface.SetFont("GRID_UI_Badge")
    local bTextW = surface.GetTextSize(badge)
    local pillW = bTextW + 16
    draw.RoundedBox(4, cardX + 10, cardY + 10, pillW, 20, Color(badgeCol.r, badgeCol.g, badgeCol.b, math.floor(a * 0.2)))
    surface.SetDrawColor(badgeCol.r, badgeCol.g, badgeCol.b, math.floor(a * 0.6))
    surface.DrawOutlinedRect(cardX + 10, cardY + 10, pillW, 20, 1)
    draw.SimpleText(badge, "GRID_UI_Badge", cardX + 10 + pillW / 2, cardY + 20, Color(badgeCol.r, badgeCol.g, badgeCol.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Entity Name
    draw.SimpleText(title, "GRID_UI_Badge", cardX + pillW + 18, cardY + 20, Color(248, 250, 252, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Subtitle / Description
    if subtext ~= "" then
        draw.SimpleText(subtext, "GRID_FontSmall", cardX + 12, cardY + 42, Color(148, 163, 184, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Optional Progress Bar
    if cfg.ShowProgressBar then
        local progress, progTxt = 0, ""
        if cfg.GetProgress then
            progress, progTxt = cfg.GetProgress(ent, ply)
        end

        local barW = cardW - 24
        local barH = 14
        local barX = cardX + 12
        local barY = cardY + 56

        draw.RoundedBox(4, barX, barY, barW, barH, Color(20, 29, 47, a))
        surface.SetDrawColor(50, 65, 90, math.floor(a * 0.7))
        surface.DrawOutlinedRect(barX, barY, barW, barH, 1)

        if progress and progress > 0 then
            local fillW = math.Clamp(math.floor(barW * progress), 4, barW)
            draw.RoundedBox(3, barX + 1, barY + 1, fillW - 2, barH - 2, Color(badgeCol.r, badgeCol.g, badgeCol.b, a))
        end

        if progTxt and progTxt ~= "" then
            draw.SimpleText(progTxt, "GRID_UI_Caption", barX + barW / 2, barY + barH / 2, Color(255, 255, 255, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    -- Interaction Action Keycaps Row
    local primaryKey = cfg.PrimaryKey or "E"
    local primaryAction = cfg.PrimaryAction or "Interact"
    local secondaryKey = cfg.SecondaryKey
    local secondaryAction = cfg.SecondaryAction

    local footerY = cardY + cardH - 18

    -- Draw Primary Action
    draw.RoundedBox(4, cardX + 12, footerY - 9, 22, 18, Color(badgeCol.r, badgeCol.g, badgeCol.b, math.floor(a * 0.25)))
    surface.SetDrawColor(badgeCol.r, badgeCol.g, badgeCol.b, math.floor(a * 0.8))
    surface.DrawOutlinedRect(cardX + 12, footerY - 9, 22, 18, 1)
    draw.SimpleText(primaryKey, "GRID_Base_HUD_Key", cardX + 23, footerY, Color(248, 250, 252, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(primaryAction, "GRID_FontSmall", cardX + 40, footerY, Color(203, 213, 225, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Draw Secondary Action if defined
    if secondaryKey and secondaryAction then
        surface.SetFont("GRID_Base_HUD_Key")
        local sKeyW = surface.GetTextSize(secondaryKey) + 12
        local sX = cardX + cardW - sKeyW - 12 - 90

        draw.RoundedBox(4, sX, footerY - 9, sKeyW, 18, Color(251, 191, 36, math.floor(a * 0.25)))
        surface.SetDrawColor(251, 191, 36, math.floor(a * 0.8))
        surface.DrawOutlinedRect(sX, footerY - 9, sKeyW, 18, 1)
        draw.SimpleText(secondaryKey, "GRID_Base_HUD_Key", sX + sKeyW / 2, footerY, Color(248, 250, 252, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(secondaryAction, "GRID_FontSmall", sX + sKeyW + 8, footerY, Color(203, 213, 225, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end)

