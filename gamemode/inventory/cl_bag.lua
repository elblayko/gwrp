--[[
    cl_bag.lua - High-Legibility Scaled Modern Bag & Container Interface
    Author: Toxic
--]]

GW.UI = GW.UI or {}
GW.UI.BagFrame = nil
GW.UI.ActiveBagIndex = 0 -- 0 = Backpack, 1..4 = Extra Bags
GW.Inventory.DraggingItem = nil
GW.Inventory.HoveredItem = nil

-- Ensure custom UI typography is registered
if GW.UI.CreateFonts then
    GW.UI.CreateFonts()
end

-- ========================================================
-- TOGGLE & WINDOW CREATION
-- ========================================================

function GW.UI.ToggleBag()
    if IsValid(GW.UI.BagFrame) then
        surface.PlaySound("doors/door_locked1.wav")
        GW.UI.BagFrame:Close()
        GW.UI.BagFrame = nil
        GW.Inventory.DraggingItem = nil
        GW.Inventory.HoveredItem = nil
        return
    end

    surface.PlaySound("doors/door_latch1.wav")
    GW.UI.OpenBag()
end

function GW.UI.RefreshBag()
    if IsValid(GW.UI.BagFrame) then
        GW.UI.BagFrame:RebuildGrid()
    end
end

function GW.UI.OpenBag()
    if GW.UI.CreateFonts then
        GW.UI.CreateFonts()
    end

    local scrW, scrH = ScrW(), ScrH()
    local frameW = math.Clamp(scrW * 0.28, 440, 520)
    local frameH = math.Clamp(scrH * 0.72, 650, 800)

    local posX = scrW - frameW - 28
    local posY = math.Clamp(scrH - frameH - 85, 40, scrH - 100)

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetPos(posX, posY)
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(true)
    frame:MakePopup()
    frame.OnClose = function()
        GW.UI.BagFrame = nil
        GW.Inventory.DraggingItem = nil
        GW.Inventory.HoveredItem = nil
    end

    GW.UI.BagFrame = frame

    -- Modern Obsidian Palette matching F4 Dashboard
    frame.Paint = function(s, w, h)
        -- Deep obsidian glassmorphic background
        draw.RoundedBox(10, 0, 0, w, h, Color(11, 15, 25, 252))

        -- Header Bar Background (64px)
        draw.RoundedBoxEx(10, 0, 0, w, 64, Color(17, 24, 39, 255), true, true, false, false)
        surface.SetDrawColor(30, 41, 59, 255)
        surface.DrawLine(0, 64, w, 64)

        -- Outer Border Outline
        surface.SetDrawColor(30, 41, 59, 220)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- Active Bag Information
        local activeBag = GW.UI.ActiveBagIndex
        local bagTitle = "Backpack"
        local bagCap = 16
        if activeBag > 0 then
            local bags = GW.Inventory.ClientBags or {}
            local bagItemId = bags["bag" .. activeBag]
            local bDef = GW.Inventory.GetItemData(bagItemId)
            bagTitle = bDef.name or ("Bag " .. activeBag)
            bagCap = GW.Inventory.GetBagCapacity(bagItemId)
        end

        -- Header Title
        draw.SimpleText(bagTitle, "GW_UI_Header", 20, 32, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Capacity Pill
        local occupiedCount = 0
        for sIdx = 1, bagCap do
            if GW.Inventory.Slots[activeBag .. "_" .. sIdx] then
                occupiedCount = occupiedCount + 1
            end
        end

        local countStr = occupiedCount .. " / " .. bagCap .. " Slots"
        surface.SetFont("GW_UI_Badge")
        local pillW = surface.GetTextSize(countStr) + 24
        local pillX = w - 60 - pillW

        draw.RoundedBox(6, pillX, 18, pillW, 28, Color(6, 182, 212, 35))
        surface.SetDrawColor(6, 182, 212, 140)
        surface.DrawOutlinedRect(pillX, 18, pillW, 28, 1)
        draw.SimpleText(countStr, "GW_UI_Badge", pillX + pillW / 2, 32, Color(34, 211, 238), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Bottom Wallet & Instructions Footer (56px)
        draw.RoundedBoxEx(10, 0, h - 56, w, 56, Color(17, 24, 39, 240), false, false, true, true)
        surface.SetDrawColor(30, 41, 59, 255)
        surface.DrawLine(0, h - 56, w, h - 56)

        local ply = LocalPlayer()
        local curMoney = IsValid(ply) and ply:GetMoney() or 0
        draw.SimpleText("$" .. string.Comma(curMoney), "GW_UI_Price", 20, h - 28, Color(74, 222, 128), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Drag out to drop", "GW_UI_Caption", w - 20, h - 28, Color(148, 163, 184), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    -- Close Button "X" (Top Right)
    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(36, 36)
    btnClose:SetPos(frameW - 48, 14)
    btnClose:SetText("")
    btnClose.Paint = function(s, w, h)
        local bg = s:IsHovered() and Color(239, 68, 68, 220) or Color(30, 41, 59, 160)
        draw.RoundedBox(6, 0, 0, w, h, bg)
        draw.SimpleText("X", "GW_UI_Header", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnClose.DoClick = function()
        frame:Close()
    end

    -- Scroll / Content Container for Slot Grid & Bag Bar
    local contentPanel = vgui.Create("DPanel", frame)
    contentPanel:SetPos(16, 76)
    contentPanel:SetSize(frameW - 32, frameH - 144)
    contentPanel.Paint = function() end
    frame.contentPanel = contentPanel

    frame.RebuildGrid = function(s)
        if not IsValid(s.contentPanel) then return end
        s.contentPanel:Clear()

        local activeBag = GW.UI.ActiveBagIndex
        local bagCap = (activeBag == 0) and 16 or GW.Inventory.GetBagCapacity((GW.Inventory.ClientBags or {})["bag" .. activeBag])

        -- 1. Slot Grid (4 Columns, Generous 84px Slots)
        local contW = s.contentPanel:GetWide()
        local cols = 4
        local spacing = 12
        local slotW = math.floor((contW - (spacing * (cols - 1))) / cols)
        local slotH = slotW

        local rows = math.ceil(bagCap / cols)

        for i = 1, bagCap do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local sx = col * (slotW + spacing)
            local sy = row * (slotH + spacing)

            local slotKey = activeBag .. "_" .. i
            local item = GW.Inventory.Slots[slotKey]

            local slotBtn = vgui.Create("DButton", s.contentPanel)
            slotBtn:SetPos(sx, sy)
            slotBtn:SetSize(slotW, slotH)
            slotBtn:SetText("")
            slotBtn.slotIndex = i
            slotBtn.bagIndex = activeBag

            -- Inset Beveled Slot Well
            slotBtn.Paint = function(sb, w, h)
                local isHover = sb:IsHovered()
                local bg = isHover and Color(24, 32, 47, 240) or Color(14, 18, 28, 240)

                draw.RoundedBox(8, 0, 0, w, h, bg)

                if item then
                    local def = GW.Inventory.GetItemData(item.item_id)
                    local qCol = GW.Inventory.GetQualityColor(def.quality)

                    -- Glowing Quality Border Outline
                    surface.SetDrawColor(qCol.r, qCol.g, qCol.b, isHover and 255 or 190)
                    surface.DrawOutlinedRect(0, 0, w, h, 2)

                    -- Stack Count Number
                    if item.amount and item.amount > 1 then
                        local amtText = "x" .. tostring(item.amount)
                        draw.SimpleText(amtText, "GW_UI_Sub", w - 7, h - 5, Color(0, 0, 0, 240), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
                        draw.SimpleText(amtText, "GW_UI_Sub", w - 8, h - 6, Color(248, 250, 252), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
                    end
                else
                    surface.SetDrawColor(30, 41, 59, isHover and 255 or 160)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)
                end
            end

            -- High-Resolution 3D Model Preview
            if item then
                local def = GW.Inventory.GetItemData(item.item_id)
                local mdl = vgui.Create("DModelPanel", slotBtn)
                mdl:SetSize(slotW - 8, slotH - 8)
                mdl:SetPos(4, 4)
                mdl:SetModel(def.model or "models/props_junk/cardboard_box004a.mdl")
                mdl:SetMouseInputEnabled(false)

                if IsValid(mdl.Entity) then
                    local mn, mx = mdl.Entity:GetRenderBounds()
                    local size = 0
                    size = math.max(size, math.abs(mn.x) + math.abs(mx.x))
                    size = math.max(size, math.abs(mn.y) + math.abs(mx.y))
                    size = math.max(size, math.abs(mn.z) + math.abs(mx.z))
                    mdl:SetFOV(45)
                    mdl:SetCamPos(Vector(size * 1.3, size * 1.3, size * 0.9))
                    mdl:SetLookAt((mn + mx) * 0.5)
                    function mdl:LayoutEntity(ent)
                        ent:SetAngles(Angle(0, RealTime() * 30 % 360, 0))
                    end
                end
            end

            -- Tooltip Tracking
            slotBtn.OnCursorEntered = function(sb)
                if item then
                    GW.Inventory.HoveredItem = {
                        item = item,
                        def = GW.Inventory.GetItemData(item.item_id),
                        bag = activeBag,
                        slot = i
                    }
                end
            end

            slotBtn.OnCursorExited = function(sb)
                if GW.Inventory.HoveredItem and GW.Inventory.HoveredItem.bag == activeBag and GW.Inventory.HoveredItem.slot == i then
                    GW.Inventory.HoveredItem = nil
                end
            end

            -- Mouse Press (Left Drag, Right Use)
            slotBtn.OnMousePressed = function(sb, mouseCode)
                if mouseCode == MOUSE_RIGHT then
                    if item then
                        surface.PlaySound("weapons/weapon_drop.wav")
                        GW.Inventory.UseSlot(activeBag, i)
                        GW.Inventory.HoveredItem = nil
                    end
                elseif mouseCode == MOUSE_LEFT then
                    if item then
                        GW.Inventory.DraggingItem = {
                            bag = activeBag,
                            slot = i,
                            item = item,
                            def = GW.Inventory.GetItemData(item.item_id)
                        }
                    end
                end
            end

            slotBtn.OnMouseReleased = function(sb, mouseCode)
                if mouseCode == MOUSE_LEFT and GW.Inventory.DraggingItem then
                    local drag = GW.Inventory.DraggingItem
                    GW.Inventory.DraggingItem = nil

                    if drag.bag ~= activeBag or drag.slot ~= i then
                        GW.Inventory.MoveSlot(drag.bag, drag.slot, activeBag, i)
                    end
                end
            end
        end

        -- 2. Equipped Bag Bar (Positioned below the grid)
        local barY = rows * (slotH + spacing) + 16
        local bagBarPanel = vgui.Create("DPanel", s.contentPanel)
        bagBarPanel:SetPos(0, barY)
        bagBarPanel:SetSize(contW, 64)
        bagBarPanel.Paint = function(bp, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(14, 18, 28, 220))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            draw.SimpleText("Containers:", "GW_UI_Sub", 14, h / 2, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local bags = GW.Inventory.ClientBags or {}
        local iconSize = 46
        local iconSpacing = 8
        local barStartX = contW - (5 * (iconSize + iconSpacing))

        for bIdx = 0, 4 do
            local bx = barStartX + bIdx * (iconSize + iconSpacing)
            local btnBag = vgui.Create("DButton", bagBarPanel)
            btnBag:SetPos(bx, 9)
            btnBag:SetSize(iconSize, iconSize)
            btnBag:SetText("")

            local isEquipped = (bIdx == 0) or (bags["bag" .. bIdx] and bags["bag" .. bIdx] ~= "")
            local isSelected = (activeBag == bIdx)

            btnBag.Paint = function(bb, w, h)
                local bg = isSelected and Color(30, 41, 59, 255) or (isEquipped and Color(17, 24, 39, 220) or Color(11, 15, 25, 180))
                draw.RoundedBox(6, 0, 0, w, h, bg)

                local trimCol = isSelected and Color(6, 182, 212) or (isEquipped and Color(34, 211, 238, 120) or Color(30, 41, 59, 140))
                surface.SetDrawColor(trimCol.r, trimCol.g, trimCol.b, 255)
                surface.DrawOutlinedRect(0, 0, w, h, isSelected and 2 or 1)

                if bIdx == 0 then
                    draw.SimpleText("MAIN", "GW_UI_Badge", w / 2, h / 2, isSelected and Color(34, 211, 238) or Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                elseif isEquipped then
                    draw.SimpleText("B" .. bIdx, "GW_UI_Sub", w / 2, h / 2, isSelected and Color(34, 211, 238) or Color(226, 232, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                else
                    draw.SimpleText("+", "GW_UI_Header", w / 2, h / 2 - 2, Color(75, 85, 99), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end

            btnBag.DoClick = function()
                if isEquipped then
                    GW.UI.ActiveBagIndex = bIdx
                    surface.PlaySound("doors/door_latch1.wav")
                    s:RebuildGrid()
                end
            end
        end
    end

    frame:RebuildGrid()
end

-- ========================================================
-- DRAG-AND-DROP WORLD RELEASE HANDLER
-- ========================================================

hook.Add("VGUIMousePressed", "GW_Bag_DragReleaseDetector", function(panel, mouseCode)
    if mouseCode == MOUSE_LEFT and GW.Inventory.DraggingItem then
        local drag = GW.Inventory.DraggingItem
        timer.Simple(0.01, function()
            local hovered = vgui.GetHoveredPanel()
            if not IsValid(hovered) or (not hovered.slotIndex and hovered ~= GW.UI.BagFrame) then
                GW.Inventory.DropSlot(drag.bag, drag.slot)
                GW.Inventory.DraggingItem = nil
            end
        end)
    end
end)

-- ========================================================
-- POST-RENDER: HIGH-LEGIBILITY FLOATING TOOLTIP & GHOST
-- ========================================================

hook.Add("DrawOverlay", "GW_Bag_TooltipAndDragGhost", function()
    local mx, my = gui.MouseX(), gui.MouseY()

    -- 1. Floating Drag Ghost Icon
    if GW.Inventory.DraggingItem then
        local drag = GW.Inventory.DraggingItem
        local def = drag.def or GW.Inventory.GetItemData(drag.item.item_id)
        local qCol = GW.Inventory.GetQualityColor(def.quality)

        local ghostSize = 64
        draw.RoundedBox(8, mx - ghostSize / 2, my - ghostSize / 2, ghostSize, ghostSize, Color(11, 15, 25, 230))
        surface.SetDrawColor(qCol.r, qCol.g, qCol.b, 255)
        surface.DrawOutlinedRect(mx - ghostSize / 2, my - ghostSize / 2, ghostSize, ghostSize, 2)
        local fitName = GW.UI.FitText(def.name, "GW_UI_Badge", ghostSize - 8)
        draw.SimpleText(fitName, "GW_UI_Badge", mx, my, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    -- 2. Floating High-Legibility GameTooltip
    if GW.Inventory.HoveredItem and IsValid(GW.UI.BagFrame) then
        local hover = GW.Inventory.HoveredItem
        local def = hover.def
        local item = hover.item
        local qCol = GW.Inventory.GetQualityColor(def.quality)

        local ttW = 340
        local linesDesc = GW.UI.WrapText(def.desc or "", "GW_UI_Body", ttW - 32)
        local ttH = 136 + (#linesDesc * 22)

        local tx = math.Clamp(mx + 20, 10, ScrW() - ttW - 10)
        local ty = math.Clamp(my + 20, 10, ScrH() - ttH - 10)

        -- Obsidian Glassmorphism Tooltip Frame
        draw.RoundedBox(8, tx, ty, ttW, ttH, Color(11, 15, 25, 252))
        surface.SetDrawColor(qCol.r, qCol.g, qCol.b, 255)
        surface.DrawOutlinedRect(tx, ty, ttW, ttH, 2)
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(tx + 2, ty + 2, ttW - 4, ttH - 4, 1)

        -- Row 1: Item Name (In Quality Color, Header Font)
        draw.SimpleText(def.name, "GW_UI_Header", tx + 16, ty + 16, qCol, TEXT_ALIGN_LEFT)

        -- Row 2: Subtype / Classification & Level Requirement
        draw.SimpleText(def.subType or "Stored Asset", "GW_UI_Sub", tx + 16, ty + 44, Color(148, 163, 184), TEXT_ALIGN_LEFT)

        local myLevel = LocalPlayer().GetLevel and LocalPlayer():GetLevel() or 1
        local reqLvl = def.level or 1
        local lvlCol = (myLevel >= reqLvl) and Color(148, 163, 184) or Color(248, 113, 113)
        local lvlText = (myLevel >= reqLvl) and string.format("Requires: Level %d", reqLvl) or string.format("Requires: Level %d (Locked)", reqLvl)
        draw.SimpleText(lvlText, "GW_UI_Sub", tx + ttW - 16, ty + 44, lvlCol, TEXT_ALIGN_RIGHT)

        -- Row 3: Stats Tag
        if def.stats and def.stats ~= "" then
            draw.SimpleText(def.stats, "GW_UI_Sub", tx + 16, ty + 68, Color(245, 158, 11), TEXT_ALIGN_LEFT)
        end

        -- Row 4: Word-Wrapped Description
        for i, l in ipairs(linesDesc) do
            draw.SimpleText(l, "GW_UI_Body", tx + 16, ty + 96 + (i - 1) * 22, Color(226, 232, 240), TEXT_ALIGN_LEFT)
        end

        -- Row 5: Interaction Guidance
        local guideY = ty + ttH - 26
        if myLevel < reqLvl then
            draw.SimpleText("<Level Too Low to Equip>", "GW_UI_Badge", tx + 16, guideY, Color(239, 68, 68), TEXT_ALIGN_LEFT)
        else
            draw.SimpleText("<Right Click to Equip / Use>", "GW_UI_Badge", tx + 16, guideY, Color(34, 211, 238), TEXT_ALIGN_LEFT)
        end
        draw.SimpleText("<Drag to Move / Drop>", "GW_UI_Badge", tx + ttW - 16, guideY, Color(148, 163, 184), TEXT_ALIGN_RIGHT)
    end
end)
