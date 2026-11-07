--[[
    entities/entities/grid_atm/cl_init.lua
    GridRP Street ATM Banking Terminal - Client UI
    Author: GRID Core Team & Antigravity
--]]

include("shared.lua")

-- ENT:Draw is inherited from grid_base_interactive, handling both ENT:DrawModel and ENT.OverheadConfig

-- --------------------------------------------------------
-- Interactive Banking Derma UI
-- --------------------------------------------------------
local atmFrame = nil

net.Receive("GRID_ATM_Open", function()
    local atmEnt = net.ReadEntity()
    local walletMoney = net.ReadUInt(32)
    local bankMoney = net.ReadUInt(32)

    if IsValid(atmFrame) then
        atmFrame.atmEnt = atmEnt
        atmFrame.walletMoney = walletMoney
        atmFrame.bankMoney = bankMoney
        return
    end

    local fW, fH = 480, 360
    atmFrame = vgui.Create("DFrame")
    atmFrame:SetSize(fW, fH)
    atmFrame:Center()
    atmFrame:SetTitle("")
    atmFrame:MakePopup()
    atmFrame:ShowCloseButton(false)
    atmFrame.atmEnt = atmEnt
    atmFrame.walletMoney = walletMoney
    atmFrame.bankMoney = bankMoney

    -- Allow ESC to close cleanly
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
        draw.RoundedBoxEx(8, 0, 0, w, 44, Color(17, 24, 39, 255), true, true, false, false)
        surface.SetDrawColor(30, 41, 59, 255)
        surface.DrawLine(0, 43, w, 43)

        -- Top Emerald Accent Line
        draw.RoundedBox(2, 0, 0, w, 3, Color(52, 211, 153))

        -- Status Pill [ATM]
        surface.SetFont("GRID_UI_Badge")
        local badgeText = "ATM"
        local bW = surface.GetTextSize(badgeText) + 16
        draw.RoundedBox(4, 16, 11, bW, 22, Color(52, 211, 153, 40))
        surface.SetDrawColor(52, 211, 153, 160)
        surface.DrawOutlinedRect(16, 11, bW, 22, 1)
        draw.SimpleText(badgeText, "GRID_UI_Badge", 16 + bW / 2, 22, Color(52, 211, 153), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Header Title
        draw.SimpleText("SECURE WIRE & BANK VAULT", "GRID_UI_Header", 16 + bW + 12, 22, Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Account Balances Sub-Card
        local subX = 16
        local subY = 56
        local subW = w - 32
        local subH = 74
        draw.RoundedBox(6, subX, subY, subW, subH, Color(20, 29, 47, 230))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(subX, subY, subW, subH, 1)

        -- Vertical divider between wallet and bank
        surface.DrawLine(subX + subW / 2, subY + 10, subX + subW / 2, subY + subH - 10)

        -- Left: Wallet Cash
        draw.SimpleText("CARRIED WALLET", "GRID_UI_Caption", subX + 16, subY + 20, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("$" .. string.Comma(s.walletMoney or 0), "GRID_UI_Price", subX + 16, subY + 48, Color(245, 158, 11), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Right: Bank Vault
        draw.SimpleText("CLEAN VAULT BALANCE", "GRID_UI_Caption", subX + subW / 2 + 16, subY + 20, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("$" .. string.Comma(s.bankMoney or 0), "GRID_UI_Price", subX + subW / 2 + 16, subY + 48, Color(52, 211, 153), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Close Button [X]
    local closeBtn = vgui.Create("DButton", atmFrame)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPos(fW - 38, 8)
    closeBtn:SetText("X")
    closeBtn:SetFont("GRID_UI_Btn")
    closeBtn:SetTextColor(Color(203, 213, 225))
    closeBtn.Paint = function(s, w, h)
        if s:IsHovered() then
            draw.RoundedBox(4, 0, 0, w, h, Color(239, 68, 68, 200))
        else
            draw.RoundedBox(4, 0, 0, w, h, Color(30, 41, 59, 140))
        end
    end
    closeBtn.DoClick = function()
        atmFrame:Close()
    end

    -- Transaction Amount Input Field
    local amountEntry = vgui.Create("DTextEntry", atmFrame)
    amountEntry:SetPos(16, 142)
    amountEntry:SetSize(fW - 32, 42)
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
    local quickAmounts = { 500, 2500, 10000, "MAX" }
    local pillW = (fW - 32 - 18) / 4
    for i, amt in ipairs(quickAmounts) do
        local qBtn = vgui.Create("DButton", atmFrame)
        qBtn:SetPos(16 + (i - 1) * (pillW + 6), 194)
        qBtn:SetSize(pillW, 28)
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
                amountEntry:SetText(tostring(atmFrame.walletMoney or 0))
            else
                local cur = tonumber(amountEntry:GetValue()) or 0
                amountEntry:SetText(tostring(cur + amt))
            end
        end
    end

    -- Primary Action: Deposit Cash
    local btnDeposit = vgui.Create("DButton", atmFrame)
    btnDeposit:SetPos(16, 234)
    btnDeposit:SetSize((fW - 40) / 2, 46)
    btnDeposit:SetText("DEPOSIT CASH")
    btnDeposit:SetFont("GRID_UI_Btn")
    btnDeposit:SetTextColor(Color(248, 250, 252))
    btnDeposit.Paint = function(s, w, h)
        local col = s:IsHovered() and Color(52, 211, 153, 240) or Color(16, 185, 129, 200)
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnDeposit.DoClick = function()
        local amt = tonumber(amountEntry:GetValue()) or 0
        if amt <= 0 then return end
        net.Start("GRID_ATM_Action")
            net.WriteEntity(atmFrame.atmEnt)
            net.WriteBool(true)
            net.WriteUInt(amt, 32)
        net.SendToServer()
        amountEntry:SetText("")
    end

    -- Primary Action: Withdraw Cash
    local btnWithdraw = vgui.Create("DButton", atmFrame)
    btnWithdraw:SetPos(24 + ((fW - 40) / 2), 234)
    btnWithdraw:SetSize((fW - 40) / 2, 46)
    btnWithdraw:SetText("WITHDRAW CASH")
    btnWithdraw:SetFont("GRID_UI_Btn")
    btnWithdraw:SetTextColor(Color(248, 250, 252))
    btnWithdraw.Paint = function(s, w, h)
        local col = s:IsHovered() and Color(56, 189, 248, 240) or Color(6, 182, 212, 200)
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnWithdraw.DoClick = function()
        local amt = tonumber(amountEntry:GetValue()) or 0
        if amt <= 0 then return end
        net.Start("GRID_ATM_Action")
            net.WriteEntity(atmFrame.atmEnt)
            net.WriteBool(false)
            net.WriteUInt(amt, 32)
        net.SendToServer()
        amountEntry:SetText("")
    end

    -- Secondary Action: Deposit All
    local btnDepositAll = vgui.Create("DButton", atmFrame)
    btnDepositAll:SetPos(16, 292)
    btnDepositAll:SetSize((fW - 40) / 2, 34)
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
        local curWallet = atmFrame.walletMoney or 0
        if curWallet <= 0 then return end
        net.Start("GRID_ATM_Action")
            net.WriteEntity(atmFrame.atmEnt)
            net.WriteBool(true)
            net.WriteUInt(curWallet, 32)
        net.SendToServer()
        amountEntry:SetText("")
    end

    -- Secondary Action: Withdraw All
    local btnWithdrawAll = vgui.Create("DButton", atmFrame)
    btnWithdrawAll:SetPos(24 + ((fW - 40) / 2), 292)
    btnWithdrawAll:SetSize((fW - 40) / 2, 34)
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
        local curBank = atmFrame.bankMoney or 0
        if curBank <= 0 then return end
        net.Start("GRID_ATM_Action")
            net.WriteEntity(atmFrame.atmEnt)
            net.WriteBool(false)
            net.WriteUInt(curBank, 32)
        net.SendToServer()
        amountEntry:SetText("")
    end
end)
