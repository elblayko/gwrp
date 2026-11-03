--[[
    cl_buffs.lua - Buff & Debuff Interface (Unified GWRP Theme)
    Author: Toxic
--]]

GWRP.UI = GWRP.UI or {}
GWRP.Buffs = GWRP.Buffs or {}
GWRP.Buffs.Active = GWRP.Buffs.Active or {}
GWRP.Buffs.CombatTexts = GWRP.Buffs.CombatTexts or {}
GWRP.Buffs.HoveredBuff = nil

-- Ensure unified gamemode typography is initialized
if GWRP.UI.CreateFonts then
    GWRP.UI.CreateFonts()
end

-- Fallback text wrappers if loaded before other UI files
GWRP.UI.WrapText = GWRP.UI.WrapText or function(text, font, maxW)
    surface.SetFont(font)
    local words = string.Explode(" ", text)
    local lines = {}
    local currentLine = ""

    for _, word in ipairs(words) do
        local testLine = (currentLine == "") and word or (currentLine .. " " .. word)
        local w, _ = surface.GetTextSize(testLine)
        if w > maxW and currentLine ~= "" then
            table.insert(lines, currentLine)
            currentLine = word
        else
            currentLine = testLine
        end
    end

    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end
    return lines
end

GWRP.UI.FitText = GWRP.UI.FitText or function(text, font, maxW)
    surface.SetFont(font)
    local w, _ = surface.GetTextSize(text)
    if w <= maxW then return text end

    local trimmed = text
    while #trimmed > 3 do
        trimmed = string.sub(trimmed, 1, #trimmed - 1)
        local testStr = trimmed .. "..."
        local tw, _ = surface.GetTextSize(testStr)
        if tw <= maxW then return testStr end
    end
    return text
end

-- ========================================================
-- NETWORK RECEIVERS
-- ========================================================

net.Receive("GWRP_SyncAllBuffs", function()
    local count = net.ReadUInt(8)
    GWRP.Buffs.Active = {}
    local now = CurTime()

    for i = 1, count do
        local id = net.ReadString()
        local duration = net.ReadFloat()
        local remaining = net.ReadFloat()
        local stacks = net.ReadUInt(8)
        local dataStr = net.ReadString()

        GWRP.Buffs.Active[id] = {
            id = id,
            duration = duration,
            remaining = remaining,
            expiresAt = (remaining > 0) and (now + remaining) or -1,
            stacks = stacks,
            data = util.JSONToTable(dataStr or "{}") or {}
        }
    end
end)

net.Receive("GWRP_SyncBuffAdded", function()
    local id = net.ReadString()
    local duration = net.ReadFloat()
    local remaining = net.ReadFloat()
    local stacks = net.ReadUInt(8)
    local dataStr = net.ReadString()
    local now = CurTime()

    GWRP.Buffs.Active[id] = {
        id = id,
        duration = duration,
        remaining = remaining,
        expiresAt = (remaining > 0) and (now + remaining) or -1,
        stacks = stacks,
        data = util.JSONToTable(dataStr or "{}") or {}
    }
end)

net.Receive("GWRP_SyncBuffRemoved", function()
    local id = net.ReadString()
    local reason = net.ReadString()
    GWRP.Buffs.Active[id] = nil
end)

net.Receive("GWRP_BuffCombatText", function()
    local pos = net.ReadVector()
    local text = net.ReadString()
    local col = net.ReadColor()

    table.insert(GWRP.Buffs.CombatTexts, {
        pos = pos,
        text = text,
        color = col,
        dieTime = CurTime() + 1.6,
        startTime = CurTime()
    })
end)

-- Metatable link for client
local meta = FindMetaTable("Player")
if meta then
    function meta:GetBuffs()
        if self == LocalPlayer() then
            return GWRP.Buffs.Active
        end
        return self.GWRP_ActiveBuffs or {}
    end

    function meta:HasBuff(buffId)
        local buffs = self:GetBuffs()
        return buffs[buffId] ~= nil
    end

    function meta:GetBuff(buffId)
        local buffs = self:GetBuffs()
        return buffs[buffId]
    end

    function meta:isWanted()
        return self:HasBuff("wanted")
    end

    function meta:IsWanted()
        return self:isWanted()
    end
end

-- ========================================================
-- PROCEDURAL ICON PAINTER (CRISP HIGH-RES DRAWING)
-- ========================================================

local function DrawBuffIconContent(iconType, x, y, size, col)
    local cx, cy = x + size / 2, y + size / 2

    if iconType == "hot" then
        -- Green Medical Cross + Heart Pip
        draw.RoundedBox(2, cx - 4, cy - 11, 8, 22, col)
        draw.RoundedBox(2, cx - 11, cy - 4, 22, 8, col)
        draw.RoundedBox(1, cx - 2, cy - 2, 4, 4, Color(248, 250, 252))

    elseif iconType == "speed" then
        -- Lightning Bolt / Adrenaline Flash
        local poly = {
            { x = cx - 2, y = cy - 12 },
            { x = cx + 9, y = cy - 12 },
            { x = cx - 1, y = cy - 1 },
            { x = cx + 8, y = cy - 1 },
            { x = cx - 7, y = cy + 13 },
            { x = cx - 2, y = cy + 3 },
            { x = cx - 9, y = cy + 3 }
        }
        surface.SetDrawColor(col.r, col.g, col.b, 255)
        draw.NoTexture()
        surface.DrawPoly(poly)

    elseif iconType == "wanted" then
        -- 5-Point Law Enforcement Star Badge
        local rOuter = size * 0.36
        local rInner = size * 0.16
        local pts = {}
        for i = 0, 9 do
            local angle = math.rad(-90 + i * 36)
            local r = (i % 2 == 0) and rOuter or rInner
            table.insert(pts, {
                x = cx + math.cos(angle) * r,
                y = cy + math.sin(angle) * r
            })
        end
        surface.SetDrawColor(col.r, col.g, col.b, 255)
        draw.NoTexture()
        surface.DrawPoly(pts)

        -- Center Star Core Pip
        draw.RoundedBox(2, cx - 3, cy - 3, 6, 6, Color(254, 240, 138))

    elseif iconType == "crippled" then
        -- Broken Bone Cross
        surface.SetDrawColor(col.r, col.g, col.b, 255)
        surface.DrawLine(cx - 10, cy - 10, cx + 10, cy + 10)
        surface.DrawLine(cx - 9, cy - 10, cx + 11, cy + 10)
        surface.SetDrawColor(239, 68, 68, 255)
        surface.DrawLine(cx - 7, cy + 9, cx + 9, cy - 7)
        draw.RoundedBox(2, cx - 11, cy - 11, 6, 6, col)
        draw.RoundedBox(2, cx + 6, cy + 6, 6, 6, col)

    elseif iconType == "poison" then
        -- Neurotoxin Skull
        draw.RoundedBox(4, cx - 9, cy - 10, 18, 13, col)
        draw.RoundedBox(2, cx - 6, cy + 2, 12, 7, col)
        draw.RoundedBox(1, cx - 6, cy - 5, 4, 4, Color(11, 15, 25))
        draw.RoundedBox(1, cx + 2, cy - 5, 4, 4, Color(11, 15, 25))

    elseif iconType == "fortitude" then
        -- Fortress Aegis Shield
        local poly = {
            { x = cx - 10, y = cy - 11 },
            { x = cx + 10, y = cy - 11 },
            { x = cx + 10, y = cy + 2 },
            { x = cx, y = cy + 12 },
            { x = cx - 10, y = cy + 2 }
        }
        surface.SetDrawColor(col.r, col.g, col.b, 255)
        draw.NoTexture()
        surface.DrawPoly(poly)
        draw.RoundedBox(1, cx - 1, cy - 8, 2, 13, Color(248, 250, 252))
        draw.RoundedBox(1, cx - 7, cy - 4, 14, 2, Color(248, 250, 252))

    else
        -- Diamond Asset Glyph
        local poly = {
            { x = cx, y = cy - 10 },
            { x = cx + 10, y = cy },
            { x = cx, y = cy + 10 },
            { x = cx - 10, y = cy }
        }
        surface.SetDrawColor(col.r, col.g, col.b, 255)
        draw.NoTexture()
        surface.DrawPoly(poly)
    end
end

-- ========================================================
-- RADIAL COOLDOWN SWEEP MASK
-- ========================================================

local function DrawCooldownSweep(x, y, size, progress)
    if progress <= 0 then return end
    if progress >= 1 then
        draw.RoundedBox(8, x, y, size, size, Color(0, 0, 0, 165))
        return
    end

    render.SetScissorRect(x, y, x + size, y + size, true)
    local cx, cy = x + size / 2, y + size / 2
    local r = size * 0.75
    local sweepAngle = progress * 360
    local segments = 24
    local segProgress = math.ceil(segments * progress)

    surface.SetDrawColor(0, 0, 0, 165)
    draw.NoTexture()

    for i = 0, segProgress - 1 do
        local a1 = math.rad(-90 + (i / segments) * 360)
        local a2 = math.rad(-90 + math.min(sweepAngle, ((i + 1) / segments) * 360))

        local tri = {
            { x = cx, y = cy },
            { x = cx + math.cos(a1) * r, y = cy + math.sin(a1) * r },
            { x = cx + math.cos(a2) * r, y = cy + math.sin(a2) * r }
        }
        surface.DrawPoly(tri)
    end
    render.SetScissorRect(0, 0, 0, 0, false)
end

-- ========================================================
-- TIME FORMATTER
-- ========================================================

local function FormatBuffTime(sec)
    if sec <= 0 then return "∞" end
    if sec >= 3600 then
        return math.floor(sec / 3600) .. "h"
    elseif sec >= 60 then
        return math.floor(sec / 60) .. "m"
    else
        return math.ceil(sec) .. "s"
    end
end

-- ========================================================
-- MAIN HUD PAINT HOOK (UNIFIED OBSIDIAN TOP-RIGHT HUD)
-- ========================================================

hook.Add("HUDPaint", "GWRP_DrawBuffs", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local activeBuffs = GWRP.Buffs.Active
    if not activeBuffs or table.IsEmpty(activeBuffs) then
        GWRP.Buffs.HoveredBuff = nil
        return
    end

    local now = CurTime()
    local iconSize = 42
    local iconSpacingX = 50
    local iconSpacingY = 62
    local startX = ScrW() - 40 - iconSize
    local startY = 24

    local mouseX, mouseY = gui.MousePos()
    local isMouseActive = (mouseX > 0 or mouseY > 0)
    local newHovered = nil

    local index = 0
    for buffId, inst in pairs(activeBuffs) do
        local def = GWRP.Buffs.Get(buffId)
        if def then
            local col = index % 8
            local row = math.floor(index / 8)
            local slotX = startX - (col * iconSpacingX)
            local slotY = startY + (row * iconSpacingY)

            -- Hover detection
            local isHovered = isMouseActive and (mouseX >= slotX and mouseX <= slotX + iconSize and mouseY >= slotY and mouseY <= slotY + iconSize)
            if isHovered then
                newHovered = {
                    id = buffId,
                    inst = inst,
                    def = def,
                    x = slotX,
                    y = slotY
                }
            end

            -- 1. Outer Accent Frame & Border Color
            local borderCol = def.borderColor or (def.isDebuff and Color(239, 68, 68) or Color(245, 158, 11))
            if buffId == "wanted" then
                -- Flashing Police beacon border (Cyan/Blue & Red)
                local flash = math.sin(now * 8)
                borderCol = (flash > 0) and Color(239, 68, 68) or Color(6, 182, 212)
            end

            -- Modern Obsidian Card Background (Unified Theme)
            draw.RoundedBox(8, slotX, slotY, iconSize, iconSize, Color(11, 15, 25, 245))

            -- Dual-Layer Precision Border Outlines
            surface.SetDrawColor(borderCol.r, borderCol.g, borderCol.b, 255)
            surface.DrawOutlinedRect(slotX, slotY, iconSize, iconSize, 2)
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(slotX + 2, slotY + 2, iconSize - 4, iconSize - 4, 1)

            -- 2. Icon Art
            DrawBuffIconContent(def.icon, slotX, slotY, iconSize, def.iconColor or Color(248, 250, 252))

            -- 3. Radial Cooldown Sweep
            local remaining = (inst.expiresAt > 0) and math.max(0, inst.expiresAt - now) or -1
            if inst.duration > 0 and remaining > 0 then
                local elapsed = inst.duration - remaining
                local progress = math.Clamp(elapsed / inst.duration, 0, 1)
                DrawCooldownSweep(slotX, slotY, iconSize, progress)
            end

            -- 4. Stack Counter (Bottom-Right Pill Badge)
            local stacks = inst.stacks or 1
            if stacks > 1 then
                surface.SetFont("GWRP_UI_Badge")
                local stTxt = tostring(stacks)
                local stW = surface.GetTextSize(stTxt) + 8
                draw.RoundedBox(4, slotX + iconSize - stW, slotY + iconSize - 16, stW, 16, Color(11, 15, 25, 240))
                surface.SetDrawColor(borderCol.r, borderCol.g, borderCol.b, 180)
                surface.DrawOutlinedRect(slotX + iconSize - stW, slotY + iconSize - 16, stW, 16, 1)
                draw.SimpleText(stTxt, "GWRP_UI_Badge", slotX + iconSize - (stW / 2), slotY + iconSize - 9, Color(254, 240, 138), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            -- 5. Remaining Duration (Unified Caption Capsule Pill Underneath)
            local timeStr = FormatBuffTime(remaining)
            surface.SetFont("GWRP_UI_Caption")
            local tw, th = surface.GetTextSize(timeStr)
            local pillW = math.max(iconSize, tw + 10)
            local pillX = slotX + (iconSize - pillW) / 2
            local pillY = slotY + iconSize + 3

            local timerCol = Color(248, 250, 252)
            if remaining > 0 and remaining <= 5 then
                -- Pulsing Red when about to expire
                local pulse = math.abs(math.sin(now * 7))
                timerCol = Color(255, 60 + pulse * 180, 60 + pulse * 180)
            end

            draw.RoundedBox(4, pillX, pillY, pillW, 18, Color(11, 15, 25, 220))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(pillX, pillY, pillW, 18, 1)
            draw.SimpleText(timeStr, "GWRP_UI_Caption", pillX + (pillW / 2), pillY + 9, timerCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            index = index + 1
        end
    end

    GWRP.Buffs.HoveredBuff = newHovered

    -- ========================================================
    -- UNIFIED FLOATING GAMETOOLTIP (MATCHING CL_BAG.LUA THEME)
    -- ========================================================
    if GWRP.Buffs.HoveredBuff then
        local hb = GWRP.Buffs.HoveredBuff
        local def = hb.def
        local inst = hb.inst
        local remaining = (inst.expiresAt > 0) and math.max(0, inst.expiresAt - now) or -1

        local ttW = 330
        local linesDesc = GWRP.UI.WrapText(def.desc or "", "GWRP_UI_Body", ttW - 32)
        local ttH = 110 + (#linesDesc * 22)
        if def.canCancel then ttH = ttH + 24 end

        local tx = math.Clamp(hb.x - ttW - 14, 12, ScrW() - ttW - 12)
        local ty = math.Clamp(hb.y, 12, ScrH() - ttH - 12)
        if tx < 14 then tx = hb.x + iconSize + 14 end

        local accentCol = def.borderColor or (def.isDebuff and Color(239, 68, 68) or Color(245, 158, 11))

        -- Deep Obsidian Glassmorphic Frame
        draw.RoundedBox(8, tx, ty, ttW, ttH, Color(11, 15, 25, 252))
        surface.SetDrawColor(accentCol.r, accentCol.g, accentCol.b, 255)
        surface.DrawOutlinedRect(tx, ty, ttW, ttH, 2)
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(tx + 2, ty + 2, ttW - 4, ttH - 4, 1)

        -- Row 1: Header Title in GWRP_UI_Header
        local fitTitle = GWRP.UI.FitText(def.name, "GWRP_UI_Header", ttW - 32)
        draw.SimpleText(fitTitle, "GWRP_UI_Header", tx + 16, ty + 14, Color(248, 250, 252))

        -- Row 2: Category Pill Badge & Time Remaining Tag
        local isDebuff = def.isDebuff
        local badgeLabel = isDebuff and "DEBUFF" or "BUFF"
        local badgeCol = isDebuff and Color(239, 68, 68) or Color(16, 185, 129)

        surface.SetFont("GWRP_UI_Badge")
        local bW = surface.GetTextSize(badgeLabel) + 16
        draw.RoundedBox(4, tx + 16, ty + 44, bW, 22, Color(badgeCol.r, badgeCol.g, badgeCol.b, 35))
        surface.SetDrawColor(badgeCol.r, badgeCol.g, badgeCol.b, 160)
        surface.DrawOutlinedRect(tx + 16, ty + 44, bW, 22, 1)
        draw.SimpleText(badgeLabel, "GWRP_UI_Badge", tx + 16 + (bW / 2), ty + 55, badgeCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local durStr = (remaining > 0) and ("Duration: " .. FormatBuffTime(remaining)) or "Permanent"
        draw.SimpleText(durStr, "GWRP_UI_Caption", tx + ttW - 16, ty + 55, Color(148, 163, 184), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        -- Row 3: Horizontal Slate Divider Line
        surface.SetDrawColor(30, 41, 59, 220)
        surface.DrawLine(tx + 16, ty + 74, tx + ttW - 16, ty + 74)

        -- Row 4: Word-Wrapped Description in GWRP_UI_Body
        for i, l in ipairs(linesDesc) do
            draw.SimpleText(l, "GWRP_UI_Body", tx + 16, ty + 84 + (i - 1) * 22, Color(226, 232, 240), TEXT_ALIGN_LEFT)
        end

        -- Row 5: Interaction Guidance Hint
        if def.canCancel then
            local guideY = ty + ttH - 22
            draw.SimpleText("<Right Click to Dismiss>", "GWRP_UI_Badge", tx + 16, guideY, Color(34, 211, 238), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Cancel Effect", "GWRP_UI_Caption", tx + ttW - 16, guideY, Color(148, 163, 184), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
end)

-- ========================================================
-- RIGHT-CLICK DISMISS INPUT LISTENERS
-- ========================================================

hook.Add("VGUIMousePressed", "GWRP_BuffRightClickDismiss", function(pnl, mouseCode)
    if mouseCode == MOUSE_RIGHT and GWRP.Buffs.HoveredBuff then
        local hb = GWRP.Buffs.HoveredBuff
        if hb.def and hb.def.canCancel then
            net.Start("GWRP_CancelBuff")
                net.WriteString(hb.id)
            net.SendToServer()
            surface.PlaySound("buttons/button15.wav")
        end
    end
end)

hook.Add("PlayerButtonDown", "GWRP_BuffMouseRawClick", function(ply, button)
    if button == MOUSE_RIGHT and GWRP.Buffs.HoveredBuff then
        local hb = GWRP.Buffs.HoveredBuff
        if hb.def and hb.def.canCancel then
            net.Start("GWRP_CancelBuff")
                net.WriteString(hb.id)
            net.SendToServer()
            surface.PlaySound("buttons/button15.wav")
        end
    end
end)

-- ========================================================
-- FLOATING COMBAT TEXT RENDERER (UNIFIED GWRP_FONTMEDIUM)
-- ========================================================

hook.Add("HUDPaint", "GWRP_DrawBuffCombatText", function()
    local now = CurTime()
    for i = #GWRP.Buffs.CombatTexts, 1, -1 do
        local item = GWRP.Buffs.CombatTexts[i]
        if now > item.dieTime then
            table.remove(GWRP.Buffs.CombatTexts, i)
        else
            local lifePct = 1 - ((item.dieTime - now) / 1.6)
            local alpha = math.Clamp((1 - lifePct) * 255, 0, 255)
            local offsetUp = lifePct * 48

            local scr = (item.pos + Vector(0, 0, offsetUp)):ToScreen()
            if scr.visible then
                draw.SimpleText(item.text, "GWRP_FontMedium", scr.x + 1, scr.y + 1, Color(11, 15, 25, alpha), TEXT_ALIGN_CENTER)
                draw.SimpleText(item.text, "GWRP_FontMedium", scr.x, scr.y, Color(item.color.r, item.color.g, item.color.b, alpha), TEXT_ALIGN_CENTER)
            end
        end
    end
end)

-- ========================================================
-- 3D2D OVERHEAD WANTED STAR (MATCHING TURF & DOOR LABELS)
-- ========================================================

hook.Add("PostPlayerDraw", "GWRP_DrawOverheadWantedStatus", function(ply)
    if not IsValid(ply) or not ply:Alive() or ply == LocalPlayer() then return end
    if not ply:isWanted() then return end

    local distSq = ply:GetPos():DistToSqr(LocalPlayer():GetPos())
    if distSq > (900 * 900) then return end

    local attachId = ply:LookupAttachment("eyes")
    local headPos = Vector(0, 0, 0)
    if attachId > 0 then
        local att = ply:GetAttachment(attachId)
        if att then headPos = att.Pos + Vector(0, 0, 18) end
    else
        headPos = ply:GetPos() + Vector(0, 0, 80)
    end

    local ang = EyeAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    local flash = math.sin(CurTime() * 8)
    local beaconCol = (flash > 0) and Color(239, 68, 68) or Color(6, 182, 212)

    cam.Start3D2D(headPos, Angle(0, ang.y, 90), 0.12)
        local pillW, pillH = 170, 36
        draw.RoundedBox(8, -pillW / 2, -pillH / 2, pillW, pillH, Color(11, 15, 25, 240))
        surface.SetDrawColor(beaconCol.r, beaconCol.g, beaconCol.b, 255)
        surface.DrawOutlinedRect(-pillW / 2, -pillH / 2, pillW, pillH, 2)
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(-pillW / 2 + 2, -pillH / 2 + 2, pillW - 4, pillH - 4, 1)

        draw.SimpleText("★ WANTED SUSPECT ★", "GWRP_FontMedium", 0, -1, Color(254, 240, 138), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end)
