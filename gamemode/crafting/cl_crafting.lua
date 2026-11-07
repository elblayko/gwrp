--[[
    cl_crafting.lua - Modern Glassmorphic Crafting Workbench Dashboard
    Author: Juicebox & Antigravity
--]]

GRID = GRID or {}
GRID.Crafting = GRID.Crafting or {}
GRID.Crafting.ActiveFrame = nil
GRID.Crafting.CurrentMachine = nil
GRID.Crafting.ActiveCategory = "All"

surface.CreateFont("GRID_UI_BodyBold", {
    font = "Roboto",
    size = 19,
    weight = 700,
    antialias = true,
    extended = true
})

function GRID.Crafting.GetClientMaterialCount(itemId)
    local count = 0
    local items = (GRID.Inventory and GRID.Inventory.ClientItems) or {}
    for _, item in ipairs(items) do
        local id = item.itemId or item.item_id
        if id == itemId then
            count = count + (tonumber(item.amount) or 1)
        end
    end
    return count
end

function GRID.Crafting.OpenCraftingMenu(machine)
    if IsValid(GRID.Crafting.ActiveFrame) then
        GRID.Crafting.ActiveFrame:Close()
        GRID.Crafting.ActiveFrame = nil
    end

    if not IsValid(machine) then return end
    GRID.Crafting.CurrentMachine = machine

    local scrW, scrH = ScrW(), ScrH()
    local frameW = math.Clamp(scrW * 0.78, 980, 1360)
    local frameH = math.Clamp(scrH * 0.82, 650, 900)

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(true)
    frame:MakePopup()
    GRID.Crafting.ActiveFrame = frame

    frame.OnClose = function()
        GRID.Crafting.ActiveFrame = nil
        GRID.Crafting.CurrentMachine = nil
    end

    -- Paint main frame background (Obsidian Palette)
    frame.Paint = function(s, w, h)
        -- Deep obsidian glass background
        draw.RoundedBox(10, 0, 0, w, h, Color(11, 15, 25, 252))

        -- Header Bar
        draw.RoundedBoxEx(10, 0, 0, w, 70, Color(17, 24, 39, 255), true, true, false, false)
        surface.SetDrawColor(30, 41, 59, 255)
        surface.DrawLine(0, 70, w, 70)

        -- Outer Border
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- Title & Dynamic Badge Placement (No Overlap)
        surface.SetFont("GRID_UI_Title")
        local titleText = "Resource Fabricator"
        local titleW = surface.GetTextSize(titleText)
        draw.SimpleText(titleText, "GRID_UI_Title", 24, 18, Color(248, 250, 252), TEXT_ALIGN_LEFT)

        local badgeX = 24 + titleW + 16
        local badgeW = 130
        draw.RoundedBox(4, badgeX, 23, badgeW, 24, Color(6, 182, 212, 35))
        surface.SetDrawColor(6, 182, 212, 120)
        surface.DrawOutlinedRect(badgeX, 23, badgeW, 24, 1)
        draw.SimpleText("CRAFTING STATION", "GRID_UI_Badge", badgeX + badgeW / 2, 35, Color(34, 211, 238),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        draw.SimpleText("Assemble firearms, tactical gear, and utility containers from extracted ingots and blueprints.",
            "GRID_UI_Caption", 25, 49, Color(148, 163, 184), TEXT_ALIGN_LEFT)
    end

    -- Close Button
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(32, 32)
    closeBtn:SetPos(frameW - 46, 19)
    closeBtn:SetText("")
    closeBtn.Paint = function(s, w, h)
        local bg = s:IsHovered() and Color(239, 68, 68, 200) or Color(30, 41, 59, 150)
        draw.RoundedBox(6, 0, 0, w, h, bg)
        draw.SimpleText("X", "GRID_UI_BodyBold", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function()
        frame:Close()
    end

    -- ========================================================
    -- TOP MACHINE STATUS BANNER
    -- ========================================================
    local statusBanner = vgui.Create("DPanel", frame)
    statusBanner:SetPos(20, 82)
    statusBanner:SetSize(frameW - 40, 56)
    statusBanner.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(15, 23, 42, 230))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        if not IsValid(machine) then return end

        local curHP = machine.GetMachineHealth and machine:GetMachineHealth() or 500
        local maxHP = machine.GetMaxMachineHealth and machine:GetMaxMachineHealth() or 500
        local curTemp = machine.GetTemperature and machine:GetTemperature() or 20
        local eff = machine.GetEfficiency and machine:GetEfficiency() or 60
        local isNet = IsValid(machine.GetConnectedSwitch and machine:GetConnectedSwitch())
        local ip = machine.GetIPAddress and machine:GetIPAddress() or ""
        local port = machine.GetAssignedPort and machine:GetAssignedPort() or 0

        -- 1. Machine Health indicator
        draw.SimpleText("FABRICATOR STATUS", "GRID_UI_Badge", 16, 16, Color(148, 163, 184), TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("Integrity: %d / %d HP", curHP, maxHP), "GRID_UI_BodyBold", 16, 36,
            Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- 2. Core Thermal indicator
        local tempCol = (curTemp >= 75) and Color(239, 68, 68) or
        ((curTemp >= 50) and Color(245, 158, 11) or Color(52, 211, 153))
        local tempStatus = (curTemp >= 75) and "CRITICAL" or ((curTemp >= 50) and "ELEVATED" or "OPTIMAL")
        draw.SimpleText("CORE THERMAL", "GRID_UI_Badge", 220, 16, Color(148, 163, 184), TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("%dC / 100C [%s]", curTemp, tempStatus), "GRID_UI_BodyBold", 220, 36, tempCol,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- 3. Network line
        local netX = 430
        draw.SimpleText("NETWORK CONNECTION", "GRID_UI_Badge", netX, 16, Color(148, 163, 184), TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        if isNet then
            local netMsg = string.format("L3 Switch Port %d  |  %s  |  %d%% Speed", port, ip ~= "" and ip or "DHCP", eff)
            draw.SimpleText(netMsg, "GRID_UI_BodyBold", netX, 36, Color(52, 211, 153), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("Standalone (60% Speed) - Link to Switch via Wire Tool", "GRID_UI_BodyBold", netX, 36,
                Color(245, 158, 11), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    -- Collect Resource button if ready item present
    local collectBtn = vgui.Create("DButton", statusBanner)
    collectBtn:SetSize(220, 38)
    collectBtn:SetPos(frameW - 40 - 232, 9)
    collectBtn:SetText("")
    collectBtn.Think = function(s)
        local has = IsValid(machine) and machine.GetHasReadyItem and machine:GetHasReadyItem()
        s:SetVisible(has == true)
    end
    collectBtn.Paint = function(s, w, h)
        local pulse = math.abs(math.sin(CurTime() * 4))
        local glow = Color(16 + math.floor(pulse * 20), 185 + math.floor(pulse * 30), 129)
        draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(16, 185, 129, 230) or Color(16, 185, 129, 160))
        surface.SetDrawColor(glow)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        local rName = IsValid(machine) and machine:GetReadyItemName() or "Resource"
        draw.SimpleText("COLLECT " .. string.upper(rName), "GRID_UI_Badge", w / 2, h / 2, Color(248, 250, 252),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    collectBtn.DoClick = function()
        if IsValid(machine) then
            net.Start("GRID_CollectMachineResource")
            net.WriteEntity(machine)
            net.SendToServer()
        end
    end

    -- ========================================================
    -- CATEGORY SELECTOR TABS
    -- ========================================================
    local catPanel = vgui.Create("DPanel", frame)
    catPanel:SetPos(20, 150)
    catPanel:SetSize(frameW - 40, 36)
    catPanel.Paint = function(s, w, h)
        surface.SetDrawColor(30, 41, 59, 150)
        surface.DrawLine(0, h - 1, w, h - 1)
    end

    local categories = { "All", "Weapons", "Bags", "Gear" }
    local tabButtons = {}
    local contentScroll = nil

    local function RefreshRecipes()
        if not IsValid(contentScroll) then return end
        contentScroll:Clear()

        local recipes = GRID.Crafting.Recipes or {}
        local filter = GRID.Crafting.ActiveCategory

        local list = vgui.Create("DIconLayout", contentScroll)
        list:Dock(TOP)
        list:SetSpaceX(14)
        list:SetSpaceY(14)

        -- Subtract extra 18px for the vertical scrollbar + margin
        local cardW = math.floor((frameW - 74) / 2)
        local cardH = 172

        for _, recipe in ipairs(recipes) do
            if filter ~= "All" and recipe.category ~= filter then continue end

            -- Evaluate can craft
            local canCraft = true
            for _, ing in ipairs(recipe.ingredients) do
                local have = GRID.Crafting.GetClientMaterialCount(ing.id)
                if have < ing.amount then
                    canCraft = false
                    break
                end
            end

            local card = list:Add("DPanel")
            card:SetSize(cardW, cardH)

            local qColor = (GRID.Inventory and GRID.Inventory.GetQualityColor and GRID.Inventory.GetQualityColor(recipe.quality or 1)) or
            Color(248, 250, 252)

            card.Paint = function(s, w, h)
                -- Card container
                draw.RoundedBox(6, 0, 0, w, h, Color(15, 23, 42, 220))
                surface.SetDrawColor(canCraft and Color(30, 41, 59, 200) or Color(23, 31, 46, 160))
                surface.DrawOutlinedRect(0, 0, w, h, 1)

                -- Quality Accent Tag
                draw.RoundedBox(2, 4, 4, 3, h - 8, qColor)

                -- Title & Category
                draw.SimpleText(recipe.name, "GRID_UI_BodyBold", 16, 16, Color(248, 250, 252), TEXT_ALIGN_LEFT,
                    TEXT_ALIGN_CENTER)
                draw.SimpleText(recipe.category, "GRID_UI_Badge", 16, 33, qColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                -- Description (generous width avoiding model preview)
                if recipe.desc then
                    local fitDesc = (GRID.UI and GRID.UI.FitText and GRID.UI.FitText(recipe.desc, "GRID_UI_Caption", w - 105)) or
                    recipe.desc
                    draw.SimpleText(fitDesc, "GRID_UI_Caption", 16, 52, Color(148, 163, 184), TEXT_ALIGN_LEFT,
                        TEXT_ALIGN_CENTER)
                end

                -- Ingredient Header
                draw.SimpleText("Required Materials:", "GRID_UI_Badge", 16, 73, Color(100, 116, 139), TEXT_ALIGN_LEFT,
                    TEXT_ALIGN_CENTER)

                -- Ingredients Pills (clean row wrapping with ample clearance from the Craft button)
                local curX = 16
                local curY = 92
                for _, ing in ipairs(recipe.ingredients) do
                    local have = GRID.Crafting.GetClientMaterialCount(ing.id)
                    local met = have >= ing.amount
                    local col = met and Color(52, 211, 153) or Color(239, 68, 68)
                    local bg = met and Color(16, 185, 129, 25) or Color(239, 68, 68, 25)

                    local txt = string.format("%d/%d %s", have, ing.amount, ing.name)
                    surface.SetFont("GRID_UI_Badge")
                    local tw = surface.GetTextSize(txt) + 16

                    if curX + tw > w - 118 then
                        curX = 16
                        curY = curY + 24
                    end

                    draw.RoundedBox(4, curX, curY, tw, 20, bg)
                    surface.SetDrawColor(col.r, col.g, col.b, 100)
                    surface.DrawOutlinedRect(curX, curY, tw, 20, 1)
                    draw.SimpleText(txt, "GRID_UI_Badge", curX + tw / 2, curY + 10, col, TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)

                    curX = curX + tw + 6
                end
            end

            -- Model Preview
            if recipe.model then
                local modelP = vgui.Create("DModelPanel", card)
                modelP:SetSize(80, 80)
                modelP:SetPos(cardW - 90, 8)
                modelP:SetModel(recipe.model)
                modelP:SetFOV(38)
                if IsValid(modelP.Entity) then
                    local mn, mx = modelP.Entity:GetRenderBounds()
                    local size = 0
                    size = math.max(size, math.abs(mx.x) + math.abs(mn.x))
                    size = math.max(size, math.abs(mx.y) + math.abs(mn.y))
                    size = math.max(size, math.abs(mx.z) + math.abs(mn.z))
                    modelP:SetCamPos(Vector(size * 1.5, size * 1.5, size * 1.2))
                    modelP:SetLookAt((mn + mx) * 0.5)
                end
                function modelP:LayoutEntity(ent)
                    ent:SetAngles(Angle(0, RealTime() * 25, 0))
                end
            end

            -- Craft Button
            local craftBtn = vgui.Create("DButton", card)
            craftBtn:SetSize(102, 34)
            craftBtn:SetPos(cardW - 114, cardH - 44)
            craftBtn:SetText("")
            craftBtn.Paint = function(s, w, h)
                if canCraft then
                    local bg = s:IsHovered() and Color(6, 182, 212, 220) or Color(6, 182, 212, 170)
                    draw.RoundedBox(4, 0, 0, w, h, bg)
                    draw.SimpleText("CRAFT", "GRID_UI_BodyBold", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                else
                    draw.RoundedBox(4, 0, 0, w, h, Color(30, 41, 59, 120))
                    draw.SimpleText("MISSING", "GRID_UI_Badge", w / 2, h / 2, Color(100, 116, 139), TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                end
            end
            craftBtn.DoClick = function()
                if not canCraft then
                    surface.PlaySound("common/warning.wav")
                    return
                end
                if not IsValid(machine) then
                    surface.PlaySound("common/warning.wav")
                    return
                end

                net.Start("GRID_CraftItem")
                net.WriteEntity(machine)
                net.WriteString(recipe.id)
                net.SendToServer()

                surface.PlaySound("buttons/button14.wav")
            end
        end
    end

    local tabX = 0
    for _, cat in ipairs(categories) do
        local btn = vgui.Create("DButton", catPanel)
        btn:SetSize(110, 32)
        btn:SetPos(tabX, 0)
        btn:SetText("")

        btn.Paint = function(s, w, h)
            local active = (GRID.Crafting.ActiveCategory == cat)
            if active then
                draw.RoundedBox(4, 0, 0, w, h, Color(6, 182, 212, 35))
                surface.SetDrawColor(6, 182, 212, 180)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText(cat, "GRID_UI_BodyBold", w / 2, h / 2, Color(34, 211, 238), TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
            else
                local bg = s:IsHovered() and Color(30, 41, 59, 120) or Color(0, 0, 0, 0)
                draw.RoundedBox(4, 0, 0, w, h, bg)
                draw.SimpleText(cat, "GRID_UI_Sub", w / 2, h / 2, Color(148, 163, 184), TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
            end
        end

        btn.DoClick = function()
            GRID.Crafting.ActiveCategory = cat
            RefreshRecipes()
        end

        table.insert(tabButtons, btn)
        tabX = tabX + 118
    end

    -- ========================================================
    -- RECIPE SCROLL CONTAINER
    -- ========================================================
    contentScroll = vgui.Create("DScrollPanel", frame)
    contentScroll:SetPos(20, 194)
    contentScroll:SetSize(frameW - 40, frameH - 210)

    local sbar = contentScroll:GetVBar()
    sbar:SetWide(6)
    sbar.Paint = function() end
    sbar.btnUp.Paint = function() end
    sbar.btnDown.Paint = function() end
    sbar.btnGrip.Paint = function(s, w, h)
        draw.RoundedBox(3, 0, 0, w, h, Color(56, 189, 248, 120))
    end

    RefreshRecipes()
end

-- Server Net Receiver: Open UI
local function HandleOpenCraftingUI()
    local machine = net.ReadEntity()
    GRID.Crafting.OpenCraftingMenu(machine)
end

net.Receive("GRID_OpenCraftingUI", HandleOpenCraftingUI)

-- Auto-refresh recipe card states when inventory syncs
hook.Add("GRID_InventorySynced", "GRID_Crafting_RefreshOnSync", function()
    if IsValid(GRID.Crafting.ActiveFrame) and IsValid(GRID.Crafting.CurrentMachine) then
        GRID.Crafting.OpenCraftingMenu(GRID.Crafting.CurrentMachine)
    end
end)
