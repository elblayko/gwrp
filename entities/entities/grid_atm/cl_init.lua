--[[
    entities/entities/grid_atm/cl_init.lua
    GridRP Street ATM Banking Terminal & Stock Exchange Hub - Client UI
    Author: GRID Core Team & Antigravity
--]]

include("shared.lua")

local atmFrame = nil

local function BuildBankingTab(container, frame)
    container:Clear()

    local p = LocalPlayer()
    local subX = 16
    local subY = 16
    local subW = container:GetWide() - 32
    if subW <= 0 then subW = 1048 end
    local subH = 80

    -- Account Balances Sub-Card
    local balanceCard = vgui.Create("DPanel", container)
    balanceCard:SetPos(subX, subY)
    balanceCard:SetSize(subW, subH)
    balanceCard.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(20, 29, 47, 230))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        surface.DrawLine(w / 2, 10, w / 2, h - 10)

        draw.SimpleText("CARRIED WALLET", "GRID_UI_Caption", 24, 22, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("$" .. string.Comma(frame.walletMoney or 0), "GRID_UI_Price", 24, 52, Color(245, 158, 11), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        draw.SimpleText("CLEAN VAULT BALANCE", "GRID_UI_Caption", (w / 2) + 24, 22, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("$" .. string.Comma(frame.bankMoney or 0), "GRID_UI_Price", (w / 2) + 24, 52, Color(52, 211, 153), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Transaction Amount Input Field
    local amountEntry = vgui.Create("DTextEntry", container)
    amountEntry:SetPos(subX, subY + subH + 20)
    amountEntry:SetSize(subW, 46)
    amountEntry:SetFont("GRID_UI_Header")
    amountEntry:SetPlaceholderText("Enter transaction amount ($)...")
    amountEntry:SetNumeric(true)
    amountEntry:SetTextColor(Color(248, 250, 252))
    amountEntry:SetCursorColor(Color(52, 211, 153))
    amountEntry.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(15, 23, 42, 240))
        local outlineCol = s:HasFocus() and Color(52, 211, 153, 220) or Color(30, 41, 59, 220)
        surface.SetDrawColor(outlineCol.r, outlineCol.g, outlineCol.b, outlineCol.a)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        s:DrawTextEntryText(Color(248, 250, 252), Color(52, 211, 153), Color(248, 250, 252))
    end

    -- Quick Amount Shortcut Pills
    local quickAmounts = { 500, 2500, 10000, 50000, "MAX" }
    local pillW = (subW - (4 * 10)) / 5
    local pillY = subY + subH + 78
    for i, amt in ipairs(quickAmounts) do
        local qBtn = vgui.Create("DButton", container)
        qBtn:SetPos(subX + ((i - 1) * (pillW + 10)), pillY)
        qBtn:SetSize(pillW, 32)
        local btnLabel = (amt == "MAX") and "MAX" or ("+$" .. string.Comma(amt))
        qBtn:SetText(btnLabel)
        qBtn:SetFont("GRID_UI_Badge")
        qBtn:SetTextColor(Color(203, 213, 225))
        qBtn.Paint = function(s, w, h)
            local bg = s:IsHovered() and Color(51, 65, 85, 240) or Color(30, 41, 59, 200)
            draw.RoundedBox(4, 0, 0, w, h, bg)
            surface.SetDrawColor(51, 65, 85, 200)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
        qBtn.DoClick = function()
            if amt == "MAX" then
                amountEntry:SetText(tostring(frame.walletMoney or 0))
            else
                local cur = tonumber(amountEntry:GetValue()) or 0
                amountEntry:SetText(tostring(cur + amt))
            end
        end
    end

    -- Primary Actions: Deposit Cash & Withdraw Cash
    local actY = pillY + 48
    local actW = (subW - 16) / 2

    local btnDeposit = vgui.Create("DButton", container)
    btnDeposit:SetPos(subX, actY)
    btnDeposit:SetSize(actW, 52)
    btnDeposit:SetText("DEPOSIT CASH")
    btnDeposit:SetFont("GRID_UI_Btn")
    btnDeposit:SetTextColor(Color(248, 250, 252))
    btnDeposit.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(52, 211, 153, 240) or Color(16, 185, 129, 200))
    end
    btnDeposit.DoClick = function()
        local amt = tonumber(amountEntry:GetValue()) or 0
        if amt <= 0 then return end
        net.Start("GRID_ATM_Action")
        net.WriteEntity(frame.atmEnt)
        net.WriteBool(true)
        net.WriteUInt(amt, 32)
        net.SendToServer()
        amountEntry:SetText("")
    end

    local btnWithdraw = vgui.Create("DButton", container)
    btnWithdraw:SetPos(subX + actW + 16, actY)
    btnWithdraw:SetSize(actW, 52)
    btnWithdraw:SetText("WITHDRAW CASH")
    btnWithdraw:SetFont("GRID_UI_Btn")
    btnWithdraw:SetTextColor(Color(248, 250, 252))
    btnWithdraw.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(56, 189, 248, 240) or Color(6, 182, 212, 200))
    end
    btnWithdraw.DoClick = function()
        local amt = tonumber(amountEntry:GetValue()) or 0
        if amt <= 0 then return end
        net.Start("GRID_ATM_Action")
        net.WriteEntity(frame.atmEnt)
        net.WriteBool(false)
        net.WriteUInt(amt, 32)
        net.SendToServer()
        amountEntry:SetText("")
    end

    -- Secondary Actions: Deposit All & Withdraw All
    local secY = actY + 62
    local btnDepositAll = vgui.Create("DButton", container)
    btnDepositAll:SetPos(subX, secY)
    btnDepositAll:SetSize(actW, 40)
    btnDepositAll:SetText("DEPOSIT ALL WALLET")
    btnDepositAll:SetFont("GRID_UI_Badge")
    btnDepositAll:SetTextColor(Color(203, 213, 225))
    btnDepositAll.Paint = function(s, w, h)
        local bg = s:IsHovered() and Color(51, 65, 85, 240) or Color(30, 41, 59, 200)
        draw.RoundedBox(6, 0, 0, w, h, bg)
        surface.SetDrawColor(51, 65, 85, 200)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    btnDepositAll.DoClick = function()
        local cur = frame.walletMoney or 0
        if cur <= 0 then return end
        net.Start("GRID_ATM_Action")
        net.WriteEntity(frame.atmEnt)
        net.WriteBool(true)
        net.WriteUInt(cur, 32)
        net.SendToServer()
        amountEntry:SetText("")
    end

    local btnWithdrawAll = vgui.Create("DButton", container)
    btnWithdrawAll:SetPos(subX + actW + 16, secY)
    btnWithdrawAll:SetSize(actW, 40)
    btnWithdrawAll:SetText("WITHDRAW ALL VAULT")
    btnWithdrawAll:SetFont("GRID_UI_Badge")
    btnWithdrawAll:SetTextColor(Color(203, 213, 225))
    btnWithdrawAll.Paint = function(s, w, h)
        local bg = s:IsHovered() and Color(51, 65, 85, 240) or Color(30, 41, 59, 200)
        draw.RoundedBox(6, 0, 0, w, h, bg)
        surface.SetDrawColor(51, 65, 85, 200)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    btnWithdrawAll.DoClick = function()
        local cur = frame.bankMoney or 0
        if cur <= 0 then return end
        net.Start("GRID_ATM_Action")
        net.WriteEntity(frame.atmEnt)
        net.WriteBool(false)
        net.WriteUInt(cur, 32)
        net.SendToServer()
        amountEntry:SetText("")
    end
end

net.Receive("GRID_ATM_Open", function()
    local atmEnt = net.ReadEntity()
    local walletMoney = net.ReadUInt(32)
    local bankMoney = net.ReadUInt(32)

    if IsValid(atmFrame) then
        atmFrame.atmEnt = atmEnt
        atmFrame.walletMoney = walletMoney
        atmFrame.bankMoney = bankMoney
        if atmFrame.CurrentTab == "bank" and IsValid(atmFrame.ContentPane) then
            BuildBankingTab(atmFrame.ContentPane, atmFrame)
        end
        return
    end

    local fW, fH = 1080, 720
    atmFrame = vgui.Create("DFrame")
    atmFrame:SetSize(fW, fH)
    atmFrame:Center()
    atmFrame:SetTitle("")
    atmFrame:MakePopup()
    atmFrame:ShowCloseButton(false)
    atmFrame.atmEnt = atmEnt
    atmFrame.walletMoney = walletMoney
    atmFrame.bankMoney = bankMoney
    atmFrame.CurrentTab = "bank"

    atmFrame.OnKeyCodePressed = function(s, key)
        if key == KEY_ESCAPE then
            s:Close()
        end
    end

    atmFrame.Paint = function(s, w, h)
        -- Primary Obsidian Background
        draw.RoundedBox(8, 0, 0, w, h, Color(11, 15, 25, 252))
        surface.SetDrawColor(30, 41, 59, 240)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- Header Strip
        draw.RoundedBoxEx(8, 0, 0, w, 52, Color(17, 24, 39, 255), true, true, false, false)
        surface.SetDrawColor(30, 41, 59, 255)
        surface.DrawLine(0, 51, w, 51)

        -- Top Emerald Accent Line
        draw.RoundedBox(2, 0, 0, w, 3, Color(52, 211, 153))

        -- Status Pill [ATM / EXCHANGE]
        local badgeText = "STREET TERMINAL"
        draw.RoundedBox(4, 16, 14, 128, 24, Color(52, 211, 153, 40))
        surface.SetDrawColor(52, 211, 153, 160)
        surface.DrawOutlinedRect(16, 14, 128, 24, 1)
        draw.SimpleText(badgeText, "GRID_UI_Badge", 80, 26, Color(52, 211, 153), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Header Title
        draw.SimpleText("SECURE WIRE VAULT & GANG STOCK EXCHANGE", "GRID_UI_Header", 156, 26, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Close Button [X]
    local closeBtn = vgui.Create("DButton", atmFrame)
    closeBtn:SetSize(36, 36)
    closeBtn:SetPos(fW - 46, 8)
    closeBtn:SetText("X")
    closeBtn:SetFont("GRID_UI_Header")
    closeBtn:SetTextColor(Color(203, 213, 225))
    closeBtn.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and Color(239, 68, 68, 220) or Color(30, 41, 59, 140))
    end
    closeBtn.DoClick = function()
        atmFrame:Close()
    end

    -- Navigation Bar (Tabs: Bank Vault vs Stock Exchange)
    local navBar = vgui.Create("DPanel", atmFrame)
    navBar:SetPos(16, 60)
    navBar:SetSize(fW - 32, 40)
    navBar.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(17, 24, 39, 220))
        surface.SetDrawColor(30, 41, 59, 180)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local contentPane = vgui.Create("DPanel", atmFrame)
    contentPane:SetPos(16, 108)
    contentPane:SetSize(fW - 32, fH - 124)
    contentPane.Paint = function() end
    atmFrame.ContentPane = contentPane

    local function SwitchATMTab(tabKey)
        atmFrame.CurrentTab = tabKey
        contentPane:Clear()
        if tabKey == "bank" then
            BuildBankingTab(contentPane, atmFrame)
        elseif tabKey == "stocks" then
            if GRID.Stocks and GRID.Stocks.CreateExchangeTab then
                GRID.Stocks.CreateExchangeTab(contentPane, atmEnt)
            end
        end
    end

    local tabButtons = {
        { id = "bank", title = "PERSONAL BANKING & WIRE VAULT" },
        { id = "stocks", title = "GANG STOCK EXCHANGE" }
    }

    local tW = (fW - 32 - 12) / 2
    for i, t in ipairs(tabButtons) do
        local btn = vgui.Create("DButton", navBar)
        btn:SetPos((i - 1) * (tW + 12), 0)
        btn:SetSize(tW, 40)
        btn:SetText(t.title)
        btn:SetFont("GRID_UI_Btn")

        btn.Paint = function(s, w, h)
            local isActive = (atmFrame.CurrentTab == t.id)
            local bg = isActive and Color(30, 41, 59, 255) or (s:IsHovered() and Color(24, 32, 47, 200) or Color(0, 0, 0, 0))
            draw.RoundedBox(6, 0, 0, w, h, bg)

            if isActive then
                draw.RoundedBox(2, 6, h - 3, w - 12, 3, Color(52, 211, 153))
            end

            s:SetTextColor(isActive and Color(248, 250, 252) or Color(148, 163, 184))
        end

        btn.DoClick = function()
            SwitchATMTab(t.id)
        end
    end

    SwitchATMTab("bank")
end)
