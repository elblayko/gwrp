--[[
    entities/entities/grid_recycler_depot/cl_init.lua
    GridRP Street Recycling Depot 3D2D Display & Interactive Minigame Dialog
    Author: Juicebox & Antigravity
--]]

include("shared.lua")

local COLOR_BG = Color(11, 15, 25, 245)
local COLOR_BORDER = Color(30, 41, 59, 230)
local COLOR_ACCENT = Color(52, 211, 153) -- Emerald green
local COLOR_AMBER = Color(251, 191, 36)
local COLOR_TEXT_MUTED = Color(148, 163, 184)
local COLOR_WHITE = Color(248, 250, 252)

--- Scans LocalPlayer's synced inventory for recyclable items and returns aggregate metrics
local function GetLocalRecyclables()
    local items = GRID.Inventory and GRID.Inventory.ClientItems or {}
    local recyclables = GRID.Scavenge and GRID.Scavenge.Recyclables or {}

    local totalCount = 0
    local baseCash = 0
    local baseXP = 0
    local categories = {}

    for _, it in ipairs(items) do
        local def = recyclables[it.item_id]
        if def then
            local amt = tonumber(it.amount) or 1
            if amt > 0 then
                totalCount = totalCount + amt
                local price = tonumber(def.cash or def.price) or 0
                local xp = tonumber(def.xp) or 0
                baseCash = baseCash + (price * amt)
                baseXP = baseXP + (xp * amt)
                categories[def.category or it.item_id] = true
            end
        end
    end

    local numCategories = table.Count(categories)
    local bonusPercent = (GRID.Scavenge and GRID.Scavenge.GetDepositBonus) and
        GRID.Scavenge.GetDepositBonus(numCategories) or 0
    local finalCash = math.floor(baseCash * (1 + bonusPercent))
    local finalXP = math.floor(baseXP * (1 + bonusPercent))

    return totalCount, finalCash, finalXP, numCategories, bonusPercent
end

function ENT:Draw()
    self:DrawModel()
end

-- ========================================================
-- INTERACTIVE RECYCLER TERMINAL & COMPACTION MINIGAME DIALOG
-- ========================================================

local recyclerFrame = nil

net.Receive("GRID_OpenRecyclerMenu", function()
    local depot = net.ReadEntity()
    local totalItems = net.ReadInt(32)
    local totalPaid = net.ReadInt(32)

    if not IsValid(depot) then return end
    if IsValid(recyclerFrame) then recyclerFrame:Remove() end

    local ply = LocalPlayer()
    local clientItems = GRID.Inventory and GRID.Inventory.ClientItems or {}
    local recyclables = GRID.Scavenge and GRID.Scavenge.Recyclables or {}

    -- Filter player's inventory for recyclable items
    local availableItems = {}
    for _, it in ipairs(clientItems) do
        local def = recyclables[it.item_id]
        if def and (tonumber(it.amount) or 0) > 0 then
            table.insert(availableItems, {
                bag = tonumber(it.bag_index) or 0,
                slot = tonumber(it.slot_index) or 1,
                item_id = it.item_id,
                amount = tonumber(it.amount) or 1,
                name = def.name,
                cash = tonumber(def.cash or def.price) or 0,
                xp = tonumber(def.xp) or 0,
                category = def.category or "scrap"
            })
        end
    end

    -- Hopper state: table of items loaded into the machine
    local hopperItems = {}

    local frameW, frameH = 720, 520
    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:ShowCloseButton(false)
    recyclerFrame = frame

    frame.Paint = function(s, pw, ph)
        -- Deep Obsidian Slate Frame
        draw.RoundedBox(10, 0, 0, pw, ph, Color(11, 15, 25, 252))
        surface.SetDrawColor(30, 41, 59, 240)
        surface.DrawOutlinedRect(0, 0, pw, ph, 1)

        -- Top Emerald Accent Line
        draw.RoundedBoxEx(10, 0, 0, pw, 4, COLOR_ACCENT, true, true, false, false)

        -- Title & Subtitle
        draw.SimpleText("STREET RECYCLING DEPOT", "GRID_UI_Title", 24, 16, COLOR_ACCENT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("City Materials Reclaimer & Hydraulic Compactor Terminal", "GRID_UI_Caption", 24, 40,
            COLOR_TEXT_MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    -- Close Button
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(30, 26)
    closeBtn:SetPos(frameW - 44, 14)
    closeBtn:SetText("")
    closeBtn.Paint = function(s, bw, bh)
        local bg = s:IsHovered() and Color(239, 68, 68, 220) or Color(30, 41, 59, 180)
        draw.RoundedBox(4, 0, 0, bw, bh, bg)
        draw.SimpleText("X", "GRID_UI_Badge", bw / 2, bh / 2, COLOR_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function()
        frame:Close()
    end

    -- Panels Layout: Left (Inventory) and Right (Hopper & Minigame)
    local colW = (frameW - 60) / 2
    local colH = frameH - 85

    -- ----------------------------------------------------
    -- LEFT COLUMN: Player's Available Refuse
    -- ----------------------------------------------------
    local leftPanel = vgui.Create("DPanel", frame)
    leftPanel:SetPos(20, 70)
    leftPanel:SetSize(colW, colH)
    leftPanel.Paint = function(s, pw, ph)
        draw.RoundedBox(8, 0, 0, pw, ph, Color(15, 23, 42, 220))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(0, 0, pw, ph, 1)
        draw.SimpleText("YOUR RECYCLABLE JUNK", "GRID_UI_BodyBold", 14, 12, COLOR_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    -- Right Column holder
    local rightPanel = vgui.Create("DPanel", frame)
    rightPanel:SetPos(35 + colW, 70)
    rightPanel:SetSize(colW, colH)

    -- Forward declaration to allow cross-refreshing
    local RefreshHopper = nil
    local RefreshInventoryList = nil

    -- Transfer All Button
    local loadAllBtn = vgui.Create("DButton", leftPanel)
    loadAllBtn:SetSize(colW - 28, 28)
    loadAllBtn:SetPos(14, 38)
    loadAllBtn:SetText("")
    loadAllBtn.Paint = function(s, bw, bh)
        local count = #availableItems
        local bg = (count > 0) and (s:IsHovered() and Color(16, 185, 129, 230) or Color(5, 150, 105, 190)) or
            Color(30, 41, 59, 140)
        draw.RoundedBox(6, 0, 0, bw, bh, bg)
        local txt = (count > 0) and "+ LOAD ALL JUNK INTO HOPPER" or "NO RECYCLABLES IN BAGS"
        local col = (count > 0) and COLOR_WHITE or COLOR_TEXT_MUTED
        draw.SimpleText(txt, "GRID_UI_Badge", bw / 2, bh / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    loadAllBtn.DoClick = function()
        if #availableItems <= 0 then return end
        for _, it in ipairs(availableItems) do
            local existing = nil
            for _, h in ipairs(hopperItems) do
                if h.bag == it.bag and h.slot == it.slot then
                    existing = h; break
                end
            end
            if existing then
                existing.amount = it.amount
            else
                table.insert(hopperItems, {
                    bag = it.bag,
                    slot = it.slot,
                    item_id = it.item_id,
                    amount = it.amount,
                    name = it.name,
                    cash = it.cash,
                    xp = it.xp,
                    category = it.category
                })
            end
        end
        surface.PlaySound("physics/cardboard/cardboard_box_impact_soft1.wav")
        RefreshHopper()
    end

    local invScroll = vgui.Create("DScrollPanel", leftPanel)
    invScroll:SetPos(14, 74)
    invScroll:SetSize(colW - 28, colH - 84)

    RefreshInventoryList = function()
        invScroll:Clear()
        if #availableItems == 0 then
            local emptyLabel = invScroll:Add("DLabel")
            emptyLabel:SetText("No recyclable items in your bag.\nScavenge dumpsters & trash bins!")
            emptyLabel:SetFont("GRID_UI_Caption")
            emptyLabel:SetTextColor(COLOR_TEXT_MUTED)
            emptyLabel:SetContentAlignment(5)
            emptyLabel:SetSize(colW - 32, 80)
            return
        end

        for _, it in ipairs(availableItems) do
            local card = invScroll:Add("DPanel")
            card:SetSize(colW - 32, 54)
            card:Dock(TOP)
            card:DockMargin(0, 0, 0, 6)
            card.Paint = function(s, bw, bh)
                draw.RoundedBox(6, 0, 0, bw, bh, Color(20, 29, 47, 240))
                surface.SetDrawColor(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 120)
                surface.DrawOutlinedRect(0, 0, bw, bh, 1)

                -- Item Name and count
                draw.SimpleText(string.format("%dx %s", it.amount, it.name), "GRID_UI_BodyBold", 10, 10, COLOR_WHITE,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(string.format("+$%d cash - +%d XP each", it.cash, it.xp), "GRID_UI_Caption", 10, 30,
                    COLOR_ACCENT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end

            -- Add Button (+1)
            local addOneBtn = vgui.Create("DButton", card)
            addOneBtn:SetSize(40, 32)
            addOneBtn:SetPos(colW - 32 - 95, 11)
            addOneBtn:SetText("+1")
            addOneBtn:SetFont("GRID_UI_Badge")
            addOneBtn:SetTextColor(COLOR_WHITE)
            addOneBtn.Paint = function(s, bw, bh)
                local bg = s:IsHovered() and Color(56, 189, 248, 220) or Color(30, 41, 59, 200)
                draw.RoundedBox(4, 0, 0, bw, bh, bg)
            end
            addOneBtn.DoClick = function()
                local existing = nil
                for _, h in ipairs(hopperItems) do
                    if h.bag == it.bag and h.slot == it.slot then
                        existing = h; break
                    end
                end
                if existing then
                    if existing.amount < it.amount then
                        existing.amount = existing.amount + 1
                    end
                else
                    table.insert(hopperItems, {
                        bag = it.bag,
                        slot = it.slot,
                        item_id = it.item_id,
                        amount = 1,
                        name = it.name,
                        cash = it.cash,
                        xp = it.xp,
                        category = it.category
                    })
                end
                surface.PlaySound("physics/metal/metal_box_impact_soft1.wav")
                RefreshHopper()
            end

            -- Add All Button
            local addAllBtn = vgui.Create("DButton", card)
            addAllBtn:SetSize(46, 32)
            addAllBtn:SetPos(colW - 32 - 50, 11)
            addAllBtn:SetText("ALL")
            addAllBtn:SetFont("GRID_UI_Badge")
            addAllBtn:SetTextColor(COLOR_WHITE)
            addAllBtn.Paint = function(s, bw, bh)
                local bg = s:IsHovered() and Color(16, 185, 129, 220) or Color(15, 118, 110, 200)
                draw.RoundedBox(4, 0, 0, bw, bh, bg)
            end
            addAllBtn.DoClick = function()
                local existing = nil
                for _, h in ipairs(hopperItems) do
                    if h.bag == it.bag and h.slot == it.slot then
                        existing = h; break
                    end
                end
                if existing then
                    existing.amount = it.amount
                else
                    table.insert(hopperItems, {
                        bag = it.bag,
                        slot = it.slot,
                        item_id = it.item_id,
                        amount = it.amount,
                        name = it.name,
                        cash = it.cash,
                        xp = it.xp,
                        category = it.category
                    })
                end
                surface.PlaySound("physics/cardboard/cardboard_box_impact_soft1.wav")
                RefreshHopper()
            end
        end
    end

    -- ----------------------------------------------------
    -- RIGHT COLUMN: Compactor Hopper & Hydraulic Minigame
    -- ----------------------------------------------------
    local isMinigameActive = false
    local minigameStartTime = 0
    local sweetMin = 0.65
    local sweetMax = 0.85
    local minigameFinished = false
    local minigameResultText = ""
    local minigameResultCol = COLOR_ACCENT

    RefreshHopper = function()
        rightPanel:Clear()

        if isMinigameActive then
            -- ================================================
            -- MINIGAME MODE: PNEUMATIC COMPACTOR TIMING GAUGE
            -- ================================================
            rightPanel.Paint = function(s, pw, ph)
                draw.RoundedBox(8, 0, 0, pw, ph, Color(15, 23, 42, 230))
                surface.SetDrawColor(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 200)
                surface.DrawOutlinedRect(0, 0, pw, ph, 1)

                draw.SimpleText("HYDRAULIC COMPACTOR ENGAGED", "GRID_UI_BodyBold", pw / 2, 20, COLOR_ACCENT,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                draw.SimpleText("Hit CRUSH when needle is inside the GREEN SWEET SPOT!", "GRID_UI_Caption", pw / 2, 44,
                    COLOR_TEXT_MUTED, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end

            -- Live Gauge Canvas
            local gaugePanel = vgui.Create("DPanel", rightPanel)
            gaugePanel:SetPos(16, 80)
            gaugePanel:SetSize(colW - 32, 120)

            local currentProgress = 0
            gaugePanel.Paint = function(s, gw, gh)
                draw.RoundedBox(6, 0, 0, gw, gh, Color(11, 15, 25, 245))
                surface.SetDrawColor(30, 41, 59, 220)
                surface.DrawOutlinedRect(0, 0, gw, gh, 1)

                -- Gauge Track Bar
                local trackW = gw - 40
                local trackH = 28
                local trackX = 20
                local trackY = 46

                draw.RoundedBox(4, trackX, trackY, trackW, trackH, Color(20, 29, 47, 240))
                surface.SetDrawColor(50, 65, 90, 180)
                surface.DrawOutlinedRect(trackX, trackY, trackW, trackH, 1)

                -- Sweet Spot Zone (Highlighted Emerald Green)
                local zoneX = trackX + math.floor(trackW * sweetMin)
                local zoneW = math.floor(trackW * (sweetMax - sweetMin))
                local pulse = math.abs(math.sin(CurTime() * 8)) * 40
                draw.RoundedBox(2, zoneX, trackY + 2, zoneW, trackH - 4, Color(52, 211, 153, 190 + pulse))
                draw.SimpleText("SWEET SPOT (+25%)", "GRID_UI_Badge", zoneX + zoneW / 2, trackY - 14, COLOR_ACCENT,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

                -- Needle Calculation (Oscillates 0 to 1 at ~1.8 Hz)
                if not minigameFinished then
                    local elapsed = CurTime() - minigameStartTime
                    currentProgress = (math.sin(elapsed * 4.5) + 1) / 2
                end

                local needleX = trackX + math.floor(trackW * currentProgress)
                draw.RoundedBox(2, needleX - 3, trackY - 4, 6, trackH + 8, Color(255, 255, 255, 255))
                draw.RoundedBox(2, needleX - 1, trackY - 2, 2, trackH + 4, COLOR_AMBER)
            end

            -- Status Result Box
            local resultLabel = vgui.Create("DLabel", rightPanel)
            resultLabel:SetPos(16, 215)
            resultLabel:SetSize(colW - 32, 30)
            resultLabel:SetFont("GRID_UI_BodyBold")
            resultLabel:SetContentAlignment(5)
            resultLabel:SetText(minigameResultText)
            resultLabel:SetTextColor(minigameResultCol)

            -- Crush Trigger Button
            local crushBtn = vgui.Create("DButton", rightPanel)
            crushBtn:SetSize(colW - 32, 54)
            crushBtn:SetPos(16, 260)
            crushBtn:SetText("")

            crushBtn.Paint = function(s, bw, bh)
                if minigameFinished then
                    draw.RoundedBox(6, 0, 0, bw, bh, Color(30, 41, 59, 200))
                    draw.SimpleText("PROCESSING COMPLETE...", "GRID_UI_BodyBold", bw / 2, bh / 2, COLOR_WHITE,
                        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                else
                    local pulse = math.abs(math.sin(CurTime() * 6))
                    local btnCol = s:IsHovered() and Color(16, 185, 129, 240) or Color(5, 150, 105, 200 + pulse * 50)
                    draw.RoundedBox(6, 0, 0, bw, bh, btnCol)
                    draw.SimpleText("[*] CRUSH NOW! [CLICK OR SPACE] [*]", "GRID_UI_BodyBold", bw / 2, bh / 2, COLOR_WHITE,
                        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end

            local function ExecuteCrush()
                if minigameFinished then return end
                minigameFinished = true

                local elapsed = CurTime() - minigameStartTime
                local hitProg = (math.sin(elapsed * 4.5) + 1) / 2
                local isSweet = (hitProg >= sweetMin and hitProg <= sweetMax)

                if isSweet then
                    minigameResultText = "[*] CRUSH OPTIMIZED! +25% BONUS! [*]"
                    minigameResultCol = COLOR_ACCENT
                    surface.PlaySound("ambient/materials/metal_groan.wav")
                    surface.PlaySound("physics/metal/metal_box_break1.wav")
                else
                    minigameResultText = "COMPACTED (STANDARD YIELD)"
                    minigameResultCol = COLOR_WHITE
                    surface.PlaySound("ambient/machines/hydraulic_1.wav")
                end
                resultLabel:SetText(minigameResultText)
                resultLabel:SetTextColor(minigameResultCol)

                -- Send deposit to server with specific items and minigame sweet spot flag
                net.Start("GRID_RecycleDeposit")
                net.WriteEntity(depot)
                net.WriteBool(isSweet)
                net.WriteUInt(#hopperItems, 16)
                for _, it in ipairs(hopperItems) do
                    net.WriteUInt(it.bag, 8)
                    net.WriteUInt(it.slot, 8)
                    net.WriteUInt(it.amount, 16)
                    net.WriteString(it.item_id)
                end
                net.SendToServer()

                timer.Simple(1.4, function()
                    if IsValid(frame) then
                        frame:Close()
                    end
                end)
            end

            crushBtn.DoClick = ExecuteCrush

            -- Allow hitting spacebar to crush
            frame.OnKeyCodePressed = function(s, key)
                if key == KEY_SPACE and not minigameFinished then
                    ExecuteCrush()
                end
            end

            return
        end

        -- ================================================
        -- NORMAL MODE: HOPPER QUEUE & PROJECTED REWARDS
        -- ================================================
        rightPanel.Paint = function(s, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, Color(15, 23, 42, 220))
            surface.SetDrawColor(30, 41, 59, 200)
            surface.DrawOutlinedRect(0, 0, pw, ph, 1)
            draw.SimpleText("COMPACTOR HOPPER", "GRID_UI_BodyBold", 14, 12, COLOR_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        -- Clear Hopper Button
        local clearBtn = vgui.Create("DButton", rightPanel)
        clearBtn:SetSize(110, 24)
        clearBtn:SetPos(colW - 124, 10)
        clearBtn:SetText("Clear Hopper")
        clearBtn:SetFont("GRID_UI_Badge")
        clearBtn:SetTextColor(COLOR_TEXT_MUTED)
        clearBtn.Paint = function(s, bw, bh)
            local bg = s:IsHovered() and Color(239, 68, 68, 160) or Color(30, 41, 59, 120)
            draw.RoundedBox(4, 0, 0, bw, bh, bg)
        end
        clearBtn.DoClick = function()
            hopperItems = {}
            RefreshHopper()
        end

        -- Hopper Items Scroll Panel
        local hopperScroll = vgui.Create("DScrollPanel", rightPanel)
        hopperScroll:SetPos(14, 42)
        hopperScroll:SetSize(colW - 28, 170)

        local totalCount = 0
        local baseCash = 0
        local baseXP = 0
        local categories = {}

        if #hopperItems == 0 then
            local emptyHop = hopperScroll:Add("DLabel")
            emptyHop:SetText("Hopper is empty.\nTransfer items from the left to begin!")
            emptyHop:SetFont("GRID_UI_Caption")
            emptyHop:SetTextColor(COLOR_TEXT_MUTED)
            emptyHop:SetContentAlignment(5)
            emptyHop:SetSize(colW - 32, 90)
        else
            for idx, h in ipairs(hopperItems) do
                totalCount = totalCount + h.amount
                baseCash = baseCash + (h.cash * h.amount)
                baseXP = baseXP + (h.xp * h.amount)
                categories[h.category or h.item_id] = true

                local row = hopperScroll:Add("DPanel")
                row:SetSize(colW - 32, 34)
                row:Dock(TOP)
                row:DockMargin(0, 0, 0, 4)
                row.Paint = function(s, bw, bh)
                    draw.RoundedBox(4, 0, 0, bw, bh, Color(20, 29, 47, 240))
                    draw.SimpleText(string.format("%dx %s", h.amount, h.name), "GRID_UI_Badge", 10, bh / 2, COLOR_WHITE,
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(string.format("+$%d  +%d XP", h.cash * h.amount, h.xp * h.amount), "GRID_UI_Caption",
                        bw - 44, bh / 2, COLOR_ACCENT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end

                local removeBtn = vgui.Create("DButton", row)
                removeBtn:SetSize(24, 24)
                removeBtn:SetPos(colW - 32 - 30, 5)
                removeBtn:SetText("X")
                removeBtn:SetFont("GRID_UI_Badge")
                removeBtn:SetTextColor(COLOR_TEXT_MUTED)
                removeBtn.Paint = function(s, bw, bh)
                    local bg = s:IsHovered() and Color(239, 68, 68, 200) or Color(30, 41, 59, 140)
                    draw.RoundedBox(4, 0, 0, bw, bh, bg)
                end
                removeBtn.DoClick = function()
                    table.remove(hopperItems, idx)
                    RefreshHopper()
                end
            end
        end

        -- Summary Box (Bottom of Right Column)
        local numCats = table.Count(categories)
        local comboBonus = (GRID.Scavenge and GRID.Scavenge.GetDepositBonus) and GRID.Scavenge.GetDepositBonus(numCats) or
            0
        local finalCash = math.floor(baseCash * (1 + comboBonus))
        local finalXP = math.floor(baseXP * (1 + comboBonus))

        local sumBox = vgui.Create("DPanel", rightPanel)
        sumBox:SetPos(14, 222)
        sumBox:SetSize(colW - 28, 120)
        sumBox.Paint = function(s, bw, bh)
            draw.RoundedBox(6, 0, 0, bw, bh, Color(11, 15, 25, 240))
            surface.SetDrawColor(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 160)
            surface.DrawOutlinedRect(0, 0, bw, bh, 1)

            draw.SimpleText(string.format("Loaded: %d items  (%d Categories)", totalCount, numCats), "GRID_UI_BodyBold",
                12, 12, COLOR_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            local comboText = (comboBonus > 0) and string.format("Combo Bonus: +%d%%", math.Round(comboBonus * 100)) or
                "Combo Bonus: None"
            local comboCol = (comboBonus > 0) and COLOR_AMBER or COLOR_TEXT_MUTED
            draw.SimpleText(comboText, "GRID_UI_Caption", 12, 34, comboCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            draw.SimpleText(string.format("Estimated Yield: $%s Cash, %d XP", string.Comma(finalCash), finalXP),
                "GRID_UI_BodyBold", 12, 58, COLOR_ACCENT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("Sweet spot awards an extra 25%!", "GRID_UI_Caption", 12, 84, COLOR_AMBER,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        -- Action Button: Start Hydraulic Compactor
        local startBtn = vgui.Create("DButton", rightPanel)
        startBtn:SetSize(colW - 28, 48)
        startBtn:SetPos(14, colH - 58)
        startBtn:SetText("")

        startBtn.Paint = function(s, bw, bh)
            if totalCount > 0 then
                local bg = s:IsHovered() and Color(16, 185, 129, 240) or Color(5, 150, 105, 200)
                draw.RoundedBox(6, 0, 0, bw, bh, bg)
                draw.SimpleText("START HYDRAULIC COMPACTOR [E]", "GRID_UI_BodyBold", bw / 2, bh / 2, COLOR_WHITE,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                draw.RoundedBox(6, 0, 0, bw, bh, Color(30, 41, 59, 140))
                draw.SimpleText("LOAD JUNK TO RECYCLE", "GRID_UI_BodyBold", bw / 2, bh / 2, COLOR_TEXT_MUTED,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        startBtn.DoClick = function()
            if totalCount <= 0 then
                surface.PlaySound("buttons/button10.wav")
                return
            end

            -- Launch compaction minigame
            isMinigameActive = true
            minigameStartTime = CurTime()
            minigameFinished = false
            minigameResultText = ""
            surface.PlaySound("ambient/machines/hydraulic_1.wav")
            RefreshHopper()
        end
    end

    -- Initial populate
    RefreshInventoryList()
    RefreshHopper()
end)
