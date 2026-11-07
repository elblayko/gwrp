--[[
    entities/entities/grid_clinic_pod/cl_init.lua
    GridRP Clinical Triage Pod Client & Menu
    Author: Juicebox
--]]

include("shared.lua")

function ENT:Draw()
    self:DrawModel()

    local ply = LocalPlayer()
    if not IsValid(ply) or ply:GetPos():DistToSqr(self:GetPos()) > (420 * 420) then return end

    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    -- In-World 3D2D Front Monitor Screen on pump head
    local pos = self:GetPos() + self:GetUp() * 53 + self:GetForward() * 12.8

    local isDoc = self:GetDoctorOnDuty()
    local owner = self:GetOwnerPlayer()
    local ownerName = IsValid(owner) and owner:Nick() or "Licensed Pharmacist"
    local vaultCash = self:GetVaultCash()

    cam.Start3D2D(pos, ang, 0.065)
    -- Monitor Frame (Deep obsidian slate)
    draw.RoundedBox(8, -120, -55, 240, 110, Color(11, 15, 25, 240))
    surface.SetDrawColor(30, 41, 59, 230)
    surface.DrawOutlinedRect(-120, -55, 240, 110, 1)

    -- Top Header Accent Line
    local topCol = isDoc and Color(52, 211, 153) or Color(6, 182, 212)
    draw.RoundedBoxEx(8, -120, -55, 240, 3, topCol, true, true, false, false)

    -- Title & Medical Cross Badge
    draw.SimpleText("+ CLINICAL TRIAGE POD +", "GRID_UI_Badge", 0, -36, topCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("Dr. " .. ownerName, "GRID_UI_Caption", 0, -20, Color(148, 163, 184), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)

    -- Status Pill
    local statusText = isDoc and "[*] DR. ON DUTY (+50% DURATION)" or "[o] AUTONOMOUS CLINIC"
    local statusCol = isDoc and Color(52, 211, 153) or Color(251, 191, 36)
    local statusBg = isDoc and Color(16, 185, 129, 35) or Color(245, 158, 11, 30)

    draw.RoundedBox(4, -100, -8, 200, 20, statusBg)
    surface.SetDrawColor(statusCol.r, statusCol.g, statusCol.b, 120)
    surface.DrawOutlinedRect(-100, -8, 200, 20, 1)
    draw.SimpleText(statusText, "GRID_UI_Badge", 0, 2, statusCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Bottom Row: Prompt & Vault
    if ply == owner then
        draw.SimpleText(string.format("Vault: $%d  -  [E] CLINIC  -  [CTRL+E] WITHDRAW", vaultCash), "GRID_UI_Caption", 0,
            34, Color(74, 222, 128), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        draw.SimpleText("[E] ACCESS TREATMENT MENU", "GRID_UI_Badge", 0, 34, Color(248, 250, 252), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
    cam.End3D2D()
end

-- Clinical Triage Terminal VGUI Window
local clinicFrame = nil

net.Receive("GRID_OpenClinicMenu", function()
    local pod = net.ReadEntity()
    local isDoc = net.ReadBool()
    local vaultCash = net.ReadInt(32)
    local totalPatients = net.ReadInt(32)

    if not IsValid(pod) then return end
    if IsValid(clinicFrame) then clinicFrame:Remove() end

    local ply = LocalPlayer()
    local owner = pod:GetOwnerPlayer()
    local isOwner = (ply == owner)

    local w, h = 640, 480
    local frame = vgui.Create("DFrame")
    frame:SetSize(w, h)
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:ShowCloseButton(false)
    clinicFrame = frame

    frame.Paint = function(s, pw, ph)
        -- Deep Obsidian Slate Frame
        draw.RoundedBox(10, 0, 0, pw, ph, Color(11, 15, 25, 252))
        surface.SetDrawColor(30, 41, 59, 240)
        surface.DrawOutlinedRect(0, 0, pw, ph, 1)

        -- Top Emerald / Cyan Accent Line
        local accentCol = isDoc and Color(52, 211, 153) or Color(6, 182, 212)
        draw.RoundedBoxEx(10, 0, 0, pw, 3, accentCol, true, true, false, false)

        -- Header Row: Left Badges & Title
        draw.RoundedBox(4, 20, 14, 58, 20, Color(6, 182, 212, 35))
        surface.SetDrawColor(6, 182, 212, 140)
        surface.DrawOutlinedRect(20, 14, 58, 20, 1)
        draw.SimpleText("CLINIC", "GRID_UI_Badge", 49, 24, Color(34, 211, 238), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        draw.SimpleText("Clinical Triage & Bio-Enhancement Terminal", "GRID_UI_Sub", 88, 24, Color(248, 250, 252),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Subtitle info
        local ownerNick = IsValid(owner) and owner:Nick() or "Licensed Pharmacist"
        draw.SimpleText("Station Physician: Dr. " .. ownerNick .. "  -  Patients Served: " .. totalPatients,
            "GRID_UI_Caption", 20, 48, Color(148, 163, 184))

        -- Status Pill on right
        local statusPillText = isDoc and "DR. ON DUTY (+50% BONUS)" or "AUTONOMOUS MODE"
        local statusPillCol = isDoc and Color(52, 211, 153) or Color(251, 191, 36)
        local statusPillBg = isDoc and Color(16, 185, 129, 30) or Color(245, 158, 11, 30)
        local pillW = 200
        draw.RoundedBox(6, pw - 20 - pillW - 32, 14, pillW, 22, statusPillBg)
        surface.SetDrawColor(statusPillCol.r, statusPillCol.g, statusPillCol.b, 140)
        surface.DrawOutlinedRect(pw - 20 - pillW - 32, 14, pillW, 22, 1)
        draw.SimpleText(statusPillText, "GRID_UI_Badge", pw - 20 - (pillW / 2) - 32, 25, statusPillCol, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    -- Close Button [X]
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(28, 24)
    closeBtn:SetPos(w - 38, 14)
    closeBtn:SetText("")
    closeBtn.Paint = function(s, bw, bh)
        local bg = s:IsHovered() and Color(239, 68, 68, 200) or Color(30, 41, 59, 160)
        draw.RoundedBox(4, 0, 0, bw, bh, bg)
        draw.SimpleText("X", "GRID_UI_Badge", bw / 2, bh / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function()
        frame:Close()
    end

    -- Scrollable Treatment List
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetPos(20, 72)
    scroll:SetSize(w - 40, h - 90)

    local treatments = {
        "triage_heal",
        "adrenaline_infusion",
        "subdermal_plating",
        "neuro_detox"
    }

    local cardY = 0
    for _, tId in ipairs(treatments) do
        local def = GRID.ClinicTreatments and GRID.ClinicTreatments[tId]
        if def then
            local card = scroll:Add("DPanel")
            card:SetPos(0, cardY)
            card:SetSize(w - 40, 84)

            card.Paint = function(s, cw, ch)
                -- Card container
                draw.RoundedBox(8, 0, 0, cw, ch, Color(17, 24, 39, 210))
                surface.SetDrawColor(30, 41, 59, 180)
                surface.DrawOutlinedRect(0, 0, cw, ch, 1)

                -- Left Accent Tab
                draw.RoundedBoxEx(8, 0, 0, 4, ch, def.accent, true, false, true, false)

                -- Treatment Name & Cost
                draw.SimpleText(def.name, "GRID_UI_Sub", 18, 18, Color(248, 250, 252))
                draw.SimpleText("$" .. def.cost, "GRID_UI_Price", cw - 130, 20, Color(74, 222, 128), TEXT_ALIGN_RIGHT,
                    TEXT_ALIGN_CENTER)

                -- Description
                local activeDesc = isDoc and def.doctorDesc or def.desc
                local descCol = isDoc and Color(52, 211, 153) or Color(148, 163, 184)
                draw.SimpleText(activeDesc, "GRID_UI_Caption", 18, 44, descCol)
            end

            -- Purchase Action Button
            local buyBtn = vgui.Create("DButton", card)
            buyBtn:SetSize(110, 36)
            buyBtn:SetPos(w - 40 - 120, 24)
            buyBtn:SetText("")

            buyBtn.Paint = function(s, bw, bh)
                local canAfford = ply:CanAfford(def.cost)
                local bg = s:IsHovered() and (canAfford and Color(16, 185, 129, 220) or Color(239, 68, 68, 160))
                    or (canAfford and Color(5, 150, 105, 180) or Color(30, 41, 59, 140))
                draw.RoundedBox(6, 0, 0, bw, bh, bg)

                local txt = canAfford and "RECEIVE" or "NO CASH"
                local txtCol = canAfford and Color(248, 250, 252) or Color(148, 163, 184)
                draw.SimpleText(txt, "GRID_UI_Btn", bw / 2, bh / 2, txtCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            buyBtn.DoClick = function()
                if not ply:CanAfford(def.cost) then
                    surface.PlaySound("buttons/button10.wav")
                    return
                end

                net.Start("GRID_Clinic_PurchaseTreatment")
                net.WriteEntity(pod)
                net.WriteString(tId)
                net.SendToServer()

                surface.PlaySound("buttons/button14.wav")
                frame:Close()
            end

            cardY = cardY + 92
        end
    end
end)
