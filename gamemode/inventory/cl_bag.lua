--[[
    cl_bag.lua - High-Legibility Scaled Modern Bag & Container Interface
    Obsidian Glassmorphism Design System (Batch 3)
    Author: Juicebox, GRID Core Team & Antigravity
--]]

GRID = GRID or {}
GRID.UI = GRID.UI or {}
GRID.Inventory = GRID.Inventory or {}

GRID.UI.BagFrame = nil
GRID.UI.ActiveBagIndex = 0 -- 0 = Backpack, 1..4 = Extra Bags
GRID.Inventory.DraggingItem = nil
GRID.Inventory.HoveredItem = nil

-- Fallback text helpers if cl_hud / cl_f4menu not loaded yet
GRID.UI.FitText = GRID.UI.FitText or function(text, font, maxW)
    if not text then return "" end
    surface.SetFont(font)
    local w = surface.GetTextSize(text)
    if w <= maxW then return text end
    while string.len(text) > 3 do
        text = string.sub(text, 1, -2)
        if surface.GetTextSize(text .. "...") <= maxW then
            return text .. "..."
        end
    end
    return text
end

GRID.UI.WrapText = GRID.UI.WrapText or function(text, font, maxW)
    if not text or text == "" then return {} end
    surface.SetFont(font)
    local words = string.Explode(" ", text)
    local lines = {}
    local currentLine = ""

    for _, word in ipairs(words) do
        local testLine = currentLine == "" and word or (currentLine .. " " .. word)
        local w = surface.GetTextSize(testLine)
        if w > maxW and currentLine ~= "" then
            table.insert(lines, currentLine)
            currentLine = word
        else
            currentLine = testLine
        end
    end
    if currentLine ~= "" then table.insert(lines, currentLine) end
    return lines
end

-- Ensure custom UI typography is registered
if GRID.UI.CreateFonts then
    GRID.UI.CreateFonts()
end

-- ========================================================
-- TOGGLE & WINDOW CREATION
-- ========================================================

function GRID.UI.ToggleBag()
    if IsValid(GRID.UI.BagFrame) then
        surface.PlaySound("doors/door_locked1.wav")
        GRID.UI.BagFrame:Close()
        GRID.UI.BagFrame = nil
        GRID.Inventory.DraggingItem = nil
        GRID.Inventory.HoveredItem = nil
        return
    end

    surface.PlaySound("doors/door_latch1.wav")
    GRID.UI.OpenBag()
end

function GRID.UI.RefreshBag()
    if IsValid(GRID.UI.BagFrame) then
        GRID.UI.BagFrame:RebuildGrid()
    end
end

function GRID.UI.OpenBag()
    if GRID.UI.CreateFonts then
        GRID.UI.CreateFonts()
    end

    local scrW, scrH = ScrW(), ScrH()
    local frameW = math.Clamp(math.floor(scrW * 0.30), 480, 540)
    local frameH = math.Clamp(math.floor(scrH * 0.76), 640, 800)

    local posX = math.Clamp(scrW - frameW - 28, 20, scrW - frameW)
    local posY = math.Clamp(math.floor((scrH - frameH) / 2), 30, scrH - frameH - 30)

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetPos(posX, posY)
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(true)
    frame:MakePopup()

    -- Close on ESC or I keypress
    frame.OnKeyCodePressed = function(s, key)
        if key == KEY_ESCAPE or key == KEY_I then
            surface.PlaySound("doors/door_locked1.wav")
            s:Close()
        end
    end

    -- Universal keyboard listener even if child controls hold focus
    frame.releasedInitialKey = false
    frame.Think = function(s)
        if not s.releasedInitialKey then
            if not input.IsKeyDown(KEY_I) then
                s.releasedInitialKey = true
            end
        else
            if input.IsKeyDown(KEY_I) then
                surface.PlaySound("doors/door_locked1.wav")
                s:Close()
            end
        end
    end

    frame.OnClose = function()
        GRID.UI.BagFrame = nil
        GRID.Inventory.DraggingItem = nil
        GRID.Inventory.HoveredItem = nil
    end

    GRID.UI.BagFrame = frame

    -- Modern Obsidian Palette matching F4 Dashboard & ATM Terminals
    frame.Paint = function(s, w, h)
        -- Deep obsidian glassmorphic background
        draw.RoundedBox(10, 0, 0, w, h, Color(11, 15, 25, 252))

        -- Outer Border Outline
        surface.SetDrawColor(30, 41, 59, 230)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- Header Bar Background (64px)
        draw.RoundedBoxEx(10, 0, 0, w, 64, Color(17, 24, 39, 255), true, true, false, false)
        surface.SetDrawColor(30, 41, 59, 255)
        surface.DrawLine(0, 64, w, 64)

        -- Top Cyber Cyan Accent Strip (3px)
        draw.RoundedBox(2, 0, 0, w, 3, Color(56, 189, 248))

        -- Active Bag Information
        local activeBag = GRID.UI.ActiveBagIndex
        local bagTitle = "Backpack"
        local bagCap = 16
        if activeBag > 0 then
            local bags = GRID.Inventory.ClientBags or {}
            local bagItemId = bags["bag" .. activeBag]
            local bDef = GRID.Inventory.GetItemData(bagItemId)
            bagTitle = bDef.name or ("Bag " .. activeBag)
            bagCap = GRID.Inventory.GetBagCapacity(bagItemId)
        end

        -- Category Badge Pill [INVENTORY]
        local badgeText = (activeBag == 0) and "MAIN BACKPACK" or string.format("CONTAINER B%d", activeBag)
        surface.SetFont("GRID_UI_Badge")
        local bW = surface.GetTextSize(badgeText) + 16
        draw.RoundedBox(4, 18, 12, bW, 20, Color(56, 189, 248, 35))
        surface.SetDrawColor(56, 189, 248, 160)
        surface.DrawOutlinedRect(18, 12, bW, 20, 1)
        draw.SimpleText(badgeText, "GRID_UI_Badge", 18 + bW / 2, 22, Color(56, 189, 248), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Header Title
        local displayTitle = (activeBag == 0) and "Tactical Pack" or bagTitle
        local titleX = 18 + bW + 12
        local maxTitleW = w - titleX - 180
        local fittedTitle = (GRID.UI.FitText and GRID.UI.FitText(displayTitle, "GRID_UI_Header", maxTitleW)) or displayTitle
        draw.SimpleText(fittedTitle, "GRID_UI_Header", titleX, 22, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Capacity Pill [X / Y SLOTS]
        local occupiedCount = 0
        for sIdx = 1, bagCap do
            if GRID.Inventory.Slots[activeBag .. "_" .. sIdx] then
                occupiedCount = occupiedCount + 1
            end
        end

        local countStr = occupiedCount .. " / " .. bagCap .. " SLOTS"
        surface.SetFont("GRID_UI_Badge")
        local pillW = surface.GetTextSize(countStr) + 20
        local pillX = w - 52 - pillW

        local isFull = (occupiedCount >= bagCap)
        local pillAccent = isFull and Color(239, 68, 68) or Color(52, 211, 153)
        draw.RoundedBox(4, pillX, 18, pillW, 26, Color(pillAccent.r, pillAccent.g, pillAccent.b, 35))
        surface.SetDrawColor(pillAccent.r, pillAccent.g, pillAccent.b, 150)
        surface.DrawOutlinedRect(pillX, 18, pillW, 26, 1)
        draw.SimpleText(countStr, "GRID_UI_Badge", pillX + pillW / 2, 31, pillAccent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Subtitle Guidance Below Header
        draw.SimpleText("Personal Modular Asset Grid & Equipment System", "GRID_UI_Caption", 18, 48, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Bottom Wallet & Action Instructions Footer (56px)
        draw.RoundedBoxEx(10, 0, h - 56, w, 56, Color(17, 24, 39, 240), false, false, true, true)
        surface.SetDrawColor(30, 41, 59, 255)
        surface.DrawLine(0, h - 56, w, h - 56)

        -- Wallet Display on Left
        local ply = LocalPlayer()
        local curMoney = IsValid(ply) and ply:GetMoney() or 0
        draw.SimpleText("WALLET", "GRID_UI_Caption", 18, h - 40, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("$" .. string.Comma(curMoney), "GRID_UI_Price", 18, h - 20, Color(52, 211, 153), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Keycap Hints on Right
        if GRID.UI.DrawKeycap then
            local yMid = h - 28
            local curRight = w - 18
            local spacing = 12

            local function DrawHint(key, label, keyCol)
                surface.SetFont("GRID_UI_Badge")
                local kw, _ = surface.GetTextSize(key)
                local boxW = kw + 12

                surface.SetFont("GRID_UI_Caption")
                local lw, _ = surface.GetTextSize(label)

                local totalW = boxW + 8 + lw
                local startX = curRight - totalW

                GRID.UI.DrawKeycap(startX, yMid, key, label, keyCol, Color(203, 213, 225))
                curRight = startX - spacing
            end

            DrawHint("DRAG OUT", "Drop", Color(239, 68, 68))
            DrawHint("DRAG", "Move", Color(56, 189, 248))
            DrawHint("R-CLICK", "Use", Color(52, 211, 153))
        else
            draw.SimpleText("R-Click: Use | Drag: Move | Drag Out: Drop", "GRID_UI_Caption", w - 18, h - 28, Color(148, 163, 184), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    -- Close Button "X" (Top Right, Standardized 36x36)
    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(36, 36)
    btnClose:SetPos(frameW - 46, 14)
    btnClose:SetText("")
    btnClose.Paint = function(s, w, h)
        local bg = s:IsHovered() and Color(239, 68, 68, 220) or Color(30, 41, 59, 160)
        draw.RoundedBox(6, 0, 0, w, h, bg)
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("X", "GRID_UI_Header", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnClose.DoClick = function()
        frame:Close()
    end

    -- Content Scroll Panel for Slot Grid & Bag Bar
    local contentScroll = vgui.Create("DScrollPanel", frame)
    contentScroll:SetPos(16, 72)
    contentScroll:SetSize(frameW - 32, frameH - 136)
    contentScroll.Paint = function() end

    -- Stylized Slim Obsidian Scrollbar
    local sbar = contentScroll:GetVBar()
    sbar:SetWide(6)
    sbar.Paint = function(s, w, h)
        draw.RoundedBox(3, 0, 0, w, h, Color(14, 18, 28, 140))
    end
    sbar.btnUp.Paint = function() end
    sbar.btnDown.Paint = function() end
    sbar.btnGrip.Paint = function(s, w, h)
        local col = s:IsHovered() and Color(56, 189, 248, 220) or Color(30, 41, 59, 220)
        draw.RoundedBox(3, 0, 0, w, h, col)
    end

    frame.contentScroll = contentScroll

    frame.RebuildGrid = function(s)
        if not IsValid(s.contentScroll) then return end
        s.contentScroll:Clear()

        local activeBag = GRID.UI.ActiveBagIndex
        local bagCap = (activeBag == 0) and 16 or
            GRID.Inventory.GetBagCapacity((GRID.Inventory.ClientBags or {})["bag" .. activeBag])

        local contW = s.contentScroll:GetWide() - 10
        local cols = 4
        local spacing = 10
        local slotW = math.floor((contW - (spacing * (cols - 1))) / cols)
        local slotH = slotW

        local rows = math.ceil(bagCap / cols)

        -- 1. Slot Grid (4 Columns)
        for i = 1, bagCap do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local sx = col * (slotW + spacing)
            local sy = row * (slotH + spacing)

            local slotKey = activeBag .. "_" .. i
            local item = GRID.Inventory.Slots[slotKey]

            local slotBtn = vgui.Create("DButton", s.contentScroll)
            slotBtn:SetPos(sx, sy)
            slotBtn:SetSize(slotW, slotH)
            slotBtn:SetText("")
            slotBtn.slotIndex = i
            slotBtn.bagIndex = activeBag

            -- Inset Beveled Obsidian Slot Well
            slotBtn.Paint = function(sb, w, h)
                local isHover = sb:IsHovered()
                local isBeingDragged = GRID.Inventory.DraggingItem and
                    (GRID.Inventory.DraggingItem.bag == activeBag and GRID.Inventory.DraggingItem.slot == i)
                local isDragHoverTarget = GRID.Inventory.DraggingItem and isHover and not isBeingDragged

                local bg = isHover and Color(24, 32, 47, 240) or Color(14, 18, 28, 240)
                if isBeingDragged then
                    bg = Color(11, 15, 25, 120)
                end

                draw.RoundedBox(8, 0, 0, w, h, bg)

                if item then
                    local def = GRID.Inventory.GetItemData(item.item_id)
                    local qCol = GRID.Inventory.GetQualityColor(def.quality)

                    -- Glowing Quality Border Outline
                    local alphaOutline = isBeingDragged and 80 or (isHover and 255 or 180)
                    surface.SetDrawColor(qCol.r, qCol.g, qCol.b, alphaOutline)
                    surface.DrawOutlinedRect(0, 0, w, h, 2)

                    -- Subtle Quality Indicator Accent Bar on Slot Top
                    draw.RoundedBox(2, 4, 2, w - 8, 2, Color(qCol.r, qCol.g, qCol.b, isBeingDragged and 60 or 200))

                    -- Stack Count Number Badge
                    if item.amount and item.amount > 1 then
                        local amtText = "x" .. tostring(item.amount)
                        surface.SetFont("GRID_UI_Badge")
                        local badgeW = surface.GetTextSize(amtText) + 12
                        local badgeH = 18

                        draw.RoundedBox(4, w - badgeW - 4, h - badgeH - 4, badgeW, badgeH, Color(11, 15, 25, 230))
                        surface.SetDrawColor(30, 41, 59, 220)
                        surface.DrawOutlinedRect(w - badgeW - 4, h - badgeH - 4, badgeW, badgeH, 1)
                        draw.SimpleText(amtText, "GRID_UI_Badge", w - 4 - badgeW / 2, h - 4 - badgeH / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                else
                    -- Empty Slot: Subtle Slate Outline & Slot Number Watermark
                    local borderCol = isDragHoverTarget and Color(52, 211, 153, 220) or (isHover and Color(56, 189, 248, 160) or Color(30, 41, 59, 140))
                    surface.SetDrawColor(borderCol.r, borderCol.g, borderCol.b, borderCol.a)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)

                    -- Slot Index Watermark
                    draw.SimpleText(tostring(i), "GRID_UI_Caption", 6, 6, Color(71, 85, 105, 100), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end

                -- Drop Target Highlight
                if isDragHoverTarget then
                    surface.SetDrawColor(52, 211, 153, 200)
                    surface.DrawOutlinedRect(1, 1, w - 2, h - 2, 2)
                end
            end

            -- High-Resolution 3D Model Preview
            if item then
                local def = GRID.Inventory.GetItemData(item.item_id)
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
                        if IsValid(ent) then
                            ent:SetAngles(Angle(0, RealTime() * 30 % 360, 0))
                        end
                    end
                end
            end

            -- Tooltip Tracking
            slotBtn.OnCursorEntered = function(sb)
                if item then
                    GRID.Inventory.HoveredItem = {
                        item = item,
                        def = GRID.Inventory.GetItemData(item.item_id),
                        bag = activeBag,
                        slot = i
                    }
                end
            end

            slotBtn.OnCursorExited = function(sb)
                if GRID.Inventory.HoveredItem and GRID.Inventory.HoveredItem.bag == activeBag and GRID.Inventory.HoveredItem.slot == i then
                    GRID.Inventory.HoveredItem = nil
                end
            end

            -- Mouse Press (Left Drag, Right Use)
            slotBtn.OnMousePressed = function(sb, mouseCode)
                if mouseCode == MOUSE_RIGHT then
                    if item then
                        surface.PlaySound("weapons/weapon_drop.wav")
                        GRID.Inventory.UseSlot(activeBag, i)
                        GRID.Inventory.HoveredItem = nil
                    end
                elseif mouseCode == MOUSE_LEFT then
                    if item then
                        GRID.Inventory.DraggingItem = {
                            bag = activeBag,
                            slot = i,
                            item = item,
                            def = GRID.Inventory.GetItemData(item.item_id)
                        }
                    end
                end
            end

            slotBtn.OnMouseReleased = function(sb, mouseCode)
                if mouseCode == MOUSE_LEFT and GRID.Inventory.DraggingItem then
                    local drag = GRID.Inventory.DraggingItem
                    GRID.Inventory.DraggingItem = nil

                    if drag.bag ~= activeBag or drag.slot ~= i then
                        GRID.Inventory.MoveSlot(drag.bag, drag.slot, activeBag, i)
                    end
                end
            end
        end

        -- 2. Equipped Bag Container Bar (Positioned below the grid)
        local barY = rows * (slotH + spacing) + 14
        local bagBarPanel = vgui.Create("DPanel", s.contentScroll)
        bagBarPanel:SetPos(0, barY)
        bagBarPanel:SetSize(contW, 64)
        bagBarPanel.Paint = function(bp, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(14, 18, 28, 220))
            surface.SetDrawColor(30, 41, 59, 180)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText("CONTAINERS", "GRID_UI_Badge", 14, 22, Color(56, 189, 248), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Modular Packs", "GRID_UI_Caption", 14, 42, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local bags = GRID.Inventory.ClientBags or {}
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
                local bg = isSelected and Color(30, 41, 59, 255) or
                    (isEquipped and Color(17, 24, 39, 220) or Color(11, 15, 25, 180))
                draw.RoundedBox(6, 0, 0, w, h, bg)

                local trimCol = isSelected and Color(56, 189, 248) or
                    (isEquipped and Color(52, 211, 153, 140) or Color(30, 41, 59, 140))
                surface.SetDrawColor(trimCol.r, trimCol.g, trimCol.b, 255)
                surface.DrawOutlinedRect(0, 0, w, h, isSelected and 2 or 1)

                if isSelected then
                    draw.RoundedBox(2, 2, 0, w - 4, 3, Color(56, 189, 248))
                end

                if bIdx == 0 then
                    draw.SimpleText("MAIN", "GRID_UI_Badge", w / 2, h / 2,
                        isSelected and Color(56, 189, 248) or Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                elseif isEquipped then
                    draw.SimpleText("B" .. bIdx, "GRID_UI_Sub", w / 2, h / 2,
                        isSelected and Color(56, 189, 248) or Color(226, 232, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                else
                    draw.SimpleText("+", "GRID_UI_Header", w / 2, h / 2 - 2, Color(75, 85, 99), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end

            btnBag.DoClick = function()
                if isEquipped then
                    GRID.UI.ActiveBagIndex = bIdx
                    surface.PlaySound("doors/door_latch1.wav")
                    s:RebuildGrid()
                end
            end

            -- Allow dragging an item directly onto a container tab to transfer
            btnBag.OnMouseReleased = function(bb, mouseCode)
                if mouseCode == MOUSE_LEFT and GRID.Inventory.DraggingItem then
                    local drag = GRID.Inventory.DraggingItem
                    GRID.Inventory.DraggingItem = nil

                    if isEquipped and drag.bag ~= bIdx then
                        local targetCap = (bIdx == 0) and 16 or GRID.Inventory.GetBagCapacity((GRID.Inventory.ClientBags or {})["bag" .. bIdx])
                        local targetSlot = 1
                        for s = 1, targetCap do
                            if not GRID.Inventory.Slots[bIdx .. "_" .. s] then
                                targetSlot = s
                                break
                            end
                        end
                        GRID.Inventory.MoveSlot(drag.bag, drag.slot, bIdx, targetSlot)
                    end
                end
            end
        end

        -- Ensure scroll panel accounts for bagBarPanel height + bottom padding
        local totalContentH = barY + 64 + 14
        local dummySpacer = vgui.Create("DPanel", s.contentScroll)
        dummySpacer:SetPos(0, totalContentH - 2)
        dummySpacer:SetSize(contW, 2)
        dummySpacer.Paint = function() end
    end

    frame:RebuildGrid()
end

-- ========================================================
-- DRAG-AND-DROP WORLD RELEASE HANDLER
-- ========================================================

hook.Add("VGUIMousePressed", "GRID_Bag_DragReleaseDetector", function(panel, mouseCode)
    if mouseCode == MOUSE_LEFT and GRID.Inventory.DraggingItem then
        local drag = GRID.Inventory.DraggingItem
        timer.Simple(0.01, function()
            local hovered = vgui.GetHoveredPanel()
            if not IsValid(hovered) or (not hovered.slotIndex and hovered ~= GRID.UI.BagFrame) then
                GRID.Inventory.DropSlot(drag.bag, drag.slot)
                GRID.Inventory.DraggingItem = nil
            end
        end)
    end
end)

-- ========================================================
-- POST-RENDER: HIGH-LEGIBILITY FLOATING TOOLTIP & GHOST
-- ========================================================

hook.Add("DrawOverlay", "GRID_Bag_TooltipAndDragGhost", function()
    local mx, my = gui.MouseX(), gui.MouseY()

    -- 1. Floating Drag Ghost Icon
    if GRID.Inventory.DraggingItem then
        local drag = GRID.Inventory.DraggingItem
        local def = drag.def or GRID.Inventory.GetItemData(drag.item.item_id)
        local qCol = GRID.Inventory.GetQualityColor(def.quality)

        local ghostSize = 64
        draw.RoundedBox(8, mx - ghostSize / 2, my - ghostSize / 2, ghostSize, ghostSize, Color(11, 15, 25, 240))
        surface.SetDrawColor(qCol.r, qCol.g, qCol.b, 255)
        surface.DrawOutlinedRect(mx - ghostSize / 2, my - ghostSize / 2, ghostSize, ghostSize, 2)

        local fitName = (GRID.UI.FitText and GRID.UI.FitText(def.name, "GRID_UI_Badge", ghostSize - 8)) or def.name
        draw.SimpleText(fitName, "GRID_UI_Badge", mx, my, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        if drag.item and drag.item.amount and drag.item.amount > 1 then
            local amtText = "x" .. tostring(drag.item.amount)
            draw.SimpleText(amtText, "GRID_UI_Badge", mx + ghostSize / 2 - 4, my + ghostSize / 2 - 4, Color(52, 211, 153), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        end
        return
    end

    -- 2. Floating High-Legibility GameTooltip
    if GRID.Inventory.HoveredItem and IsValid(GRID.UI.BagFrame) then
        local hover = GRID.Inventory.HoveredItem
        local def = hover.def
        local item = hover.item
        local qCol = GRID.Inventory.GetQualityColor(def.quality)

        local ttW = 340
        local linesDesc = (GRID.UI.WrapText and GRID.UI.WrapText(def.desc or "", "GRID_UI_Body", ttW - 32)) or
            { def.desc or "" }
        local ttH = 142 + (#linesDesc * 22)

        local tx = math.Clamp(mx + 20, 10, ScrW() - ttW - 10)
        local ty = math.Clamp(my + 20, 10, ScrH() - ttH - 10)

        -- Obsidian Glassmorphism Tooltip Frame
        draw.RoundedBox(8, tx, ty, ttW, ttH, Color(11, 15, 25, 252))
        surface.SetDrawColor(qCol.r, qCol.g, qCol.b, 255)
        surface.DrawOutlinedRect(tx, ty, ttW, ttH, 2)
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(tx + 2, ty + 2, ttW - 4, ttH - 4, 1)

        -- Top Accent Line in Quality Color
        draw.RoundedBox(2, tx + 4, ty + 2, ttW - 8, 2, Color(qCol.r, qCol.g, qCol.b, 220))

        -- Row 1: Item Name (In Quality Color, Header Font)
        draw.SimpleText(def.name, "GRID_UI_Header", tx + 16, ty + 16, qCol, TEXT_ALIGN_LEFT)

        -- Row 2: Subtype Badge & Level Requirement Pill
        local subTypeStr = string.upper(def.subType or "Stored Asset")
        surface.SetFont("GRID_UI_Badge")
        local stW = surface.GetTextSize(subTypeStr) + 12
        draw.RoundedBox(4, tx + 16, ty + 44, stW, 20, Color(56, 189, 248, 35))
        surface.SetDrawColor(56, 189, 248, 140)
        surface.DrawOutlinedRect(tx + 16, ty + 44, stW, 20, 1)
        draw.SimpleText(subTypeStr, "GRID_UI_Badge", tx + 16 + stW / 2, ty + 54, Color(56, 189, 248), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local myLevel = LocalPlayer().GetLevel and LocalPlayer():GetLevel() or 1
        local reqLvl = def.level or 1
        local canEquip = (myLevel >= reqLvl)
        local lvlCol = canEquip and Color(148, 163, 184) or Color(248, 113, 113)
        local lvlText = canEquip and string.format("Requires: Level %d", reqLvl) or
            string.format("Requires: Level %d (Locked)", reqLvl)
        draw.SimpleText(lvlText, "GRID_UI_Sub", tx + ttW - 16, ty + 54, lvlCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        -- Row 3: Stats Tag
        if def.stats and def.stats ~= "" then
            draw.SimpleText(def.stats, "GRID_UI_Sub", tx + 16, ty + 74, Color(245, 158, 11), TEXT_ALIGN_LEFT)
        end

        -- Row 4: Word-Wrapped Description
        local descStartY = (def.stats and def.stats ~= "") and 100 or 80
        for i, l in ipairs(linesDesc) do
            draw.SimpleText(l, "GRID_UI_Body", tx + 16, ty + descStartY + (i - 1) * 22, Color(226, 232, 240), TEXT_ALIGN_LEFT)
        end

        -- Row 5: Interaction Guidance
        local guideY = ty + ttH - 24
        if not canEquip then
            draw.SimpleText("[Level Too Low to Equip]", "GRID_UI_Badge", tx + 16, guideY, Color(239, 68, 68), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("[R-Click to Equip / Use]", "GRID_UI_Badge", tx + 16, guideY, Color(52, 211, 153), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText("[Drag to Move / Drop]", "GRID_UI_Badge", tx + ttW - 16, guideY, Color(148, 163, 184), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
end)
