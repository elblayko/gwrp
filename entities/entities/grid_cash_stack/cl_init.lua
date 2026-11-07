--[[
    entities/entities/grid_cash_stack/cl_init.lua
    GridRP Cash Stack & Forensic Crime Scene Evidence - Client Display & Halos
    Author: Juicebox / GRID Core Team
--]]

include("shared.lua")

local currentInvestigateEnt = nil
local investigateEndTime = 0
local investigateDuration = 3.0

net.Receive("GRID_EvidenceInvestigate", function()
    local ent = net.ReadEntity()
    local dur = net.ReadFloat()

    if IsValid(ent) and dur > 0 then
        currentInvestigateEnt = ent
        investigateDuration = dur
        investigateEndTime = CurTime() + dur
    else
        currentInvestigateEnt = nil
        investigateEndTime = 0
    end
end)

-- Screen-space investigation progress bar
hook.Add("HUDPaint", "GRID_ForensicsInvestigationHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:IsPolice() then return end
    if not IsValid(currentInvestigateEnt) then return end

    -- Cancel if player released E or walked too far away
    if not input.IsKeyDown(KEY_E) or (ply:EyePos():DistToSqr(currentInvestigateEnt:GetPos()) > 130 * 130) then
        currentInvestigateEnt = nil
        return
    end

    local now = CurTime()
    local rem = math.max(0, investigateEndTime - now)
    local pct = math.Clamp(1 - (rem / investigateDuration), 0, 1)

    local scrW, scrH = ScrW(), ScrH()
    local barW, barH = 320, 48
    local barX = (scrW - barW) / 2
    local barY = (scrH / 2) + 60

    draw.RoundedBox(8, barX, barY, barW, barH, Color(11, 15, 25, 240))
    surface.SetDrawColor(30, 41, 59, 220)
    surface.DrawOutlinedRect(barX, barY, barW, barH, 1)

    -- Progress fill
    draw.RoundedBox(6, barX + 4, barY + 4, math.floor((barW - 8) * pct), barH - 8, Color(245, 158, 11, 230))

    -- Text
    draw.SimpleText("ANALYZING FORENSIC EVIDENCE...", "GRID_UI_Badge", scrW / 2, barY + 12, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    draw.SimpleText(string.format("%.1fs / %.1fs", (investigateDuration - rem), investigateDuration), "GRID_UI_Caption", scrW / 2, barY + 28, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end)

-- Halo highlighting for line-of-sight evidence
hook.Add("PreDrawHalos", "GRID_EvidenceHalos", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:IsPolice() then return end

    local visibleEvidence = {}
    local pPos = ply:EyePos()

    for _, ent in ipairs(ents.FindByClass("grid_cash_stack")) do
        if IsValid(ent) and ent:GetNWBool("GRID_IsDeathEvidence", false) then
            local dist = pPos:DistToSqr(ent:GetPos())
            if dist <= 1500 * 1500 then
                -- Direct Line-of-Sight Check
                local tr = util.TraceLine({
                    start = pPos,
                    endpos = ent:WorldSpaceCenter(),
                    filter = ply,
                    mask = MASK_VISIBLE
                })
                if not tr.HitWorld then
                    table.insert(visibleEvidence, ent)
                end
            end
        end
    end

    if #visibleEvidence > 0 then
        local pulse = math.abs(math.sin(CurTime() * 3))
        local alpha = math.floor(180 + (75 * pulse))
        halo.Add(visibleEvidence, Color(245, 158, 11, alpha), 2, 2, 1, true, false)
    end
end)

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + Vector(0, 0, 8)
    local ply = LocalPlayer()
    local isPolice = IsValid(ply) and ply:IsPolice()
    local isEvidence = self:GetNWBool("GRID_IsDeathEvidence", false)

    local dist = EyePos():DistToSqr(pos)
    if dist > 350 * 350 and not (isPolice and isEvidence and dist <= 1500 * 1500) then return end

    local ang = EyeAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    -- If police and evidence: check line-of-sight
    if isPolice and isEvidence then
        local tr = util.TraceLine({
            start = EyePos(),
            endpos = self:WorldSpaceCenter(),
            filter = ply,
            mask = MASK_VISIBLE
        })
        if tr.HitWorld then return end -- Blocked by wall/geometry

        local vicName = self:GetNWString("GRID_VictimNick", "Deceased")
        local amount = self:GetAmount()

        cam.Start3D2D(pos + Vector(0, 0, 10), Angle(0, ang.y, 90), 0.07)
            local pulse = math.abs(math.sin(CurTime() * 4))
            local boxCol = Color(15, 23, 42, 240)
            local borderCol = Color(245, 158, 11, math.floor(200 + (55 * pulse)))

            draw.RoundedBox(6, -150, -42, 300, 84, boxCol)
            draw.RoundedBox(6, -150, -42, 300, 3, borderCol)

            draw.SimpleText("[CRIME SCENE EVIDENCE]", "GRID_FontSmall", 0, -32, borderCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText("Victim: " .. vicName .. " ($" .. string.Comma(amount) .. ")", "GRID_FontSmall", 0, -12, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText("[HOLD E TO INVESTIGATE]", "GRID_FontSmall", 0, 10, Color(52, 211, 153), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        cam.End3D2D()
    else
        local amount = self:GetAmount()
        local text = "$" .. string.Comma(amount)

        cam.Start3D2D(pos, Angle(0, ang.y, 90), 0.08)
            draw.SimpleTextOutlined(text, "GRID_HUD_Small", 0, 0, Color(46, 204, 113, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
        cam.End3D2D()
    end
end
