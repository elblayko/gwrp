--[[
    cl_doors.lua - Door Client Interface & F2 Management Menu
    Door Raycast HUD Tag is handled natively in cl_hud.lua (matching printer & clinic pod HUD elements)
--]]

GRID = GRID or {}
GRID.Doors = GRID.Doors or {}

-- Remove legacy 3D2D in-world door text hook to prevent text clipping into door frames
hook.Remove("PostDrawOpaqueRenderables", "GRID_DrawDoorText")

function GRID.Doors.OpenDoorMenu()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or not ent:isDoor() then return end
    if tr.HitPos:DistToSqr(ply:EyePos()) > (180 * 180) and ply:GetPos():DistToSqr(ent:GetPos()) > (180 * 180) then return end

    if IsValid(GRID.Doors.ActiveMenu) then
        GRID.Doors.ActiveMenu:Remove()
    end

    local owner = ent:GetNWEntity("GRID_DoorOwner")
    local gangName = ent:GetNWString("GRID_DoorFaction", "")
    local isOwned = IsValid(owner)
    local isOwner = isOwned and (owner == ply)
    local cost = (GRID.Config and GRID.Config.DoorCost) or 15
    local isHobo = (ply:GetJob() == "hobo")

    local w, h = 380, 200
    local frame = vgui.Create("DFrame")
    frame:SetSize(w, h)
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:ShowCloseButton(false)
    GRID.Doors.ActiveMenu = frame

    local accentCol = isOwner and Color(52, 211, 153) or (isOwned and Color(251, 191, 36) or Color(6, 182, 212))

    frame.Paint = function(s, pw, ph)
        -- Deep Obsidian Slate Frame
        draw.RoundedBox(10, 0, 0, pw, ph, Color(11, 15, 25, 252))
        surface.SetDrawColor(30, 41, 59, 240)
        surface.DrawOutlinedRect(0, 0, pw, ph, 1)

        -- Top Accent Line
        draw.RoundedBoxEx(10, 0, 0, pw, 3, accentCol, true, true, false, false)

        -- Header: Badge Pill + Title
        draw.RoundedBox(4, 18, 14, 52, 20, Color(accentCol.r, accentCol.g, accentCol.b, 35))
        surface.SetDrawColor(accentCol.r, accentCol.g, accentCol.b, 140)
        surface.DrawOutlinedRect(18, 14, 52, 20, 1)
        draw.SimpleText("DOOR", "GRID_UI_Badge", 44, 24, accentCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        draw.SimpleText("Property Management", "GRID_UI_Sub", 80, 24, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Subtitle Info
        local subInfo
        if not isOwned then
            subInfo = isHobo and "Vacant Real Estate  •  Hobos Cannot Purchase" or string.format("Vacant Real Estate  •  Price: $%s", string.Comma(cost))
        elseif isOwner then
            local refund = math.floor(cost * 0.7)
            subInfo = string.format("Owner: %s  •  Refund on Sale: +$%s", ply:Nick(), string.Comma(refund))
        else
            subInfo = string.format("Owner: %s%s", owner:Nick(), (gangName ~= "" and (" [" .. gangName .. "]") or ""))
        end
        draw.SimpleText(subInfo, "GRID_UI_Caption", 18, 48, Color(148, 163, 184))
    end

    -- Close Button [X]
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(28, 24)
    closeBtn:SetPos(w - 38, 14)
    closeBtn:SetText("")
    closeBtn.Paint = function(s, bw, bh)
        local bg = s:IsHovered() and Color(239, 68, 68, 200) or Color(30, 41, 59, 160)
        draw.RoundedBox(4, 0, 0, bw, bh, bg)
        draw.SimpleText("✕", "GRID_UI_Badge", bw / 2, bh / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function()
        frame:Close()
    end

    -- Action Container Card
    local card = vgui.Create("DPanel", frame)
    card:SetPos(18, 76)
    card:SetSize(w - 36, 104)
    card.Paint = function(s, cw, ch)
        draw.RoundedBox(8, 0, 0, cw, ch, Color(17, 24, 39, 210))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, cw, ch, 1)
        draw.RoundedBoxEx(8, 0, 0, 4, ch, accentCol, true, false, true, false)
    end

    if not isOwned then
        -- Unowned Door: Purchase Action
        local descLabel = vgui.Create("DLabel", card)
        descLabel:SetPos(16, 14)
        descLabel:SetSize(w - 68, 22)
        descLabel:SetFont("GRID_FontSmall")
        descLabel:SetTextColor(Color(226, 232, 240))
        descLabel:SetText(isHobo and "Hobos are homeless and cannot purchase properties." or "Purchase this door to lock, unlock, and secure access.")

        local buyBtn = vgui.Create("DButton", card)
        buyBtn:SetSize(w - 68, 42)
        buyBtn:SetPos(16, 46)
        buyBtn:SetText("")
        buyBtn:SetEnabled(not isHobo)
        buyBtn.Paint = function(s, bw, bh)
            if isHobo then
                draw.RoundedBox(6, 0, 0, bw, bh, Color(51, 65, 85, 180))
                draw.SimpleText("HOBOS CANNOT PURCHASE PROPERTY", "GRID_UI_Btn", bw / 2, bh / 2, Color(156, 163, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                return
            end

            local canAfford = ply:CanAfford(cost)
            local bg = s:IsHovered() and (canAfford and Color(16, 185, 129, 220) or Color(239, 68, 68, 160))
                or (canAfford and Color(5, 150, 105, 180) or Color(30, 41, 59, 140))
            draw.RoundedBox(6, 0, 0, bw, bh, bg)

            local txt = canAfford and ("PURCHASE PROPERTY ($" .. string.Comma(cost) .. ")") or ("CANNOT AFFORD ($" .. string.Comma(cost) .. ")")
            local txtCol = canAfford and Color(248, 250, 252) or Color(148, 163, 184)
            draw.SimpleText(txt, "GRID_UI_Btn", bw / 2, bh / 2, txtCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        buyBtn.DoClick = function()
            if isHobo then
                GRID.Notify(ply, "Hobos are homeless and cannot purchase properties!", NOTIFY_ERROR)
                surface.PlaySound("buttons/button10.wav")
                return
            end
            if not ply:CanAfford(cost) then
                surface.PlaySound("buttons/button10.wav")
                return
            end
            net.Start("GRID_DoorAction")
                net.WriteEntity(ent)
                net.WriteString("buy")
            net.SendToServer()
            surface.PlaySound("buttons/button14.wav")
            frame:Close()
        end
    elseif isOwner then
        -- Owned Door: Sell Action
        local refund = math.floor(cost * 0.7)

        local descLabel = vgui.Create("DLabel", card)
        descLabel:SetPos(16, 14)
        descLabel:SetSize(w - 68, 22)
        descLabel:SetFont("GRID_FontSmall")
        descLabel:SetTextColor(Color(226, 232, 240))
        descLabel:SetText("You are the registered owner of this property.")

        local sellBtn = vgui.Create("DButton", card)
        sellBtn:SetSize(w - 68, 42)
        sellBtn:SetPos(16, 46)
        sellBtn:SetText("")
        sellBtn.Paint = function(s, bw, bh)
            local bg = s:IsHovered() and Color(239, 68, 68, 200) or Color(185, 28, 28, 160)
            draw.RoundedBox(6, 0, 0, bw, bh, bg)
            draw.SimpleText("SELL PROPERTY (+$" .. string.Comma(refund) .. ")", "GRID_UI_Btn", bw / 2, bh / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        sellBtn.DoClick = function()
            net.Start("GRID_DoorAction")
                net.WriteEntity(ent)
                net.WriteString("sell")
            net.SendToServer()
            surface.PlaySound("buttons/button14.wav")
            frame:Close()
        end
    else
        -- Another player's door: Informational
        local descLabel = vgui.Create("DLabel", card)
        descLabel:SetPos(16, 20)
        descLabel:SetSize(w - 68, 24)
        descLabel:SetFont("GRID_FontSmall")
        descLabel:SetTextColor(Color(248, 250, 252))
        descLabel:SetText("Private Residence - No Unauthorized Access")

        local subDesc = vgui.Create("DLabel", card)
        subDesc:SetPos(16, 50)
        subDesc:SetSize(w - 68, 22)
        subDesc:SetFont("GRID_UI_Caption")
        subDesc:SetTextColor(Color(148, 163, 184))
        subDesc:SetText("This property is currently occupied and managed by another citizen.")
    end
end
