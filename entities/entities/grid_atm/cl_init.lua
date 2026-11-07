--[[
    entities/entities/grid_atm/cl_init.lua
    GridRP Street ATM Banking Terminal - Client UI
    Author: GRID Core Team & Antigravity
--]]

include("shared.lua")

local COLOR_AMBER       = Color(245, 158, 11)
local COLOR_BG_DARK     = Color(15, 23, 42, 230)
local COLOR_TEXT_WHITE  = Color(248, 250, 252)
local COLOR_GREEN       = Color(34, 197, 94)

function ENT:Draw()
    self:DrawModel()

    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    if lp:EyePos():DistToSqr(self:GetPos()) > (350 * 350) then return end

    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    local pos = self:GetPos() + self:GetUp() * 50 + self:GetForward() * 12

    cam.Start3D2D(pos, ang, 0.08)
        draw.RoundedBox(6, -110, -32, 220, 64, COLOR_BG_DARK)
        surface.SetDrawColor(COLOR_GREEN.r, COLOR_GREEN.g, COLOR_GREEN.b, 200)
        surface.DrawOutlinedRect(-110, -32, 220, 64, 2)

        draw.SimpleText("STREET ATM", "GRID_UI_Header", 0, -12, COLOR_GREEN, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E] ACCESS BANKING", "GRID_UI_Caption", 0, 14, COLOR_TEXT_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

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

    local fW, fH = 420, 320
    atmFrame = vgui.Create("DFrame")
    atmFrame:SetSize(fW, fH)
    atmFrame:Center()
    atmFrame:SetTitle("")
    atmFrame:MakePopup()
    atmFrame:ShowCloseButton(false)
    atmFrame.atmEnt = atmEnt
    atmFrame.walletMoney = walletMoney
    atmFrame.bankMoney = bankMoney

    atmFrame.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(15, 23, 42, 250))
        surface.SetDrawColor(34, 197, 94, 220)
        surface.DrawOutlinedRect(0, 0, w, h, 2)

        draw.RoundedBoxEx(8, 0, 0, w, 44, Color(34, 197, 94, 40), true, true, false, false)
        draw.SimpleText("[ATM] STREET ATM & PERSONAL VAULT", "GRID_UI_Header", 16, 22, COLOR_GREEN, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Wallet & Bank Displays
        draw.RoundedBox(6, 16, 60, w - 32, 70, Color(30, 41, 59, 200))
        draw.SimpleText("Carried Wallet Cash:", "GRID_UI_Body", 28, 80, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("$" .. string.Comma(s.walletMoney or 0), "GRID_UI_Price", w - 28, 80, Color(245, 158, 11), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        draw.SimpleText("Clean Bank Balance:", "GRID_UI_Body", 28, 110, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("$" .. string.Comma(s.bankMoney or 0), "GRID_UI_Price", w - 28, 110, COLOR_GREEN, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local closeBtn = vgui.Create("DButton", atmFrame)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPos(fW - 36, 8)
    closeBtn:SetText("X")
    closeBtn:SetFont("GRID_UI_Btn")
    closeBtn:SetTextColor(Color(248, 250, 252))
    closeBtn.Paint = function(s, w, h)
        if s:IsHovered() then
            draw.RoundedBox(4, 0, 0, w, h, Color(239, 68, 68, 180))
        end
    end
    closeBtn.DoClick = function()
        atmFrame:Close()
    end

    local amountEntry = vgui.Create("DTextEntry", atmFrame)
    amountEntry:SetPos(16, 145)
    amountEntry:SetSize(fW - 32, 40)
    amountEntry:SetFont("GRID_UI_Header")
    amountEntry:SetPlaceholderText("Enter transaction amount...")
    amountEntry:SetNumeric(true)

    local btnDeposit = vgui.Create("DButton", atmFrame)
    btnDeposit:SetPos(16, 200)
    btnDeposit:SetSize((fW - 40) / 2, 45)
    btnDeposit:SetText("DEPOSIT CASH")
    btnDeposit:SetFont("GRID_UI_Btn")
    btnDeposit:SetTextColor(COLOR_TEXT_WHITE)
    btnDeposit.Paint = function(s, w, h)
        local col = s:IsHovered() and Color(245, 158, 11, 230) or Color(245, 158, 11, 170)
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnDeposit.DoClick = function()
        local amt = tonumber(amountEntry:GetValue()) or 0
        if amt <= 0 then return end
        net.Start("GRID_ATM_Action")
            net.WriteEntity(atmFrame.atmEnt)
            net.WriteBool(true) -- Deposit
            net.WriteUInt(amt, 32)
        net.SendToServer()
        amountEntry:SetText("")
    end

    local btnWithdraw = vgui.Create("DButton", atmFrame)
    btnWithdraw:SetPos(24 + ((fW - 40) / 2), 200)
    btnWithdraw:SetSize((fW - 40) / 2, 45)
    btnWithdraw:SetText("WITHDRAW CASH")
    btnWithdraw:SetFont("GRID_UI_Btn")
    btnWithdraw:SetTextColor(COLOR_TEXT_WHITE)
    btnWithdraw.Paint = function(s, w, h)
        local col = s:IsHovered() and Color(34, 197, 94, 230) or Color(34, 197, 94, 170)
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    btnWithdraw.DoClick = function()
        local amt = tonumber(amountEntry:GetValue()) or 0
        if amt <= 0 then return end
        net.Start("GRID_ATM_Action")
            net.WriteEntity(atmFrame.atmEnt)
            net.WriteBool(false) -- Withdraw
            net.WriteUInt(amt, 32)
        net.SendToServer()
        amountEntry:SetText("")
    end

    local btnDepositAll = vgui.Create("DButton", atmFrame)
    btnDepositAll:SetPos(16, 255)
    btnDepositAll:SetSize((fW - 40) / 2, 35)
    btnDepositAll:SetText("DEPOSIT ALL")
    btnDepositAll:SetFont("GRID_UI_Caption")
    btnDepositAll:SetTextColor(COLOR_TEXT_WHITE)
    btnDepositAll.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(71, 85, 105) or Color(51, 65, 85))
    end
    btnDepositAll.DoClick = function()
        local curWallet = atmFrame.walletMoney or 0
        if curWallet <= 0 then return end
        net.Start("GRID_ATM_Action")
            net.WriteEntity(atmFrame.atmEnt)
            net.WriteBool(true)
            net.WriteUInt(curWallet, 32)
        net.SendToServer()
    end

    local btnWithdrawAll = vgui.Create("DButton", atmFrame)
    btnWithdrawAll:SetPos(24 + ((fW - 40) / 2), 255)
    btnWithdrawAll:SetSize((fW - 40) / 2, 35)
    btnWithdrawAll:SetText("WITHDRAW ALL")
    btnWithdrawAll:SetFont("GRID_UI_Caption")
    btnWithdrawAll:SetTextColor(COLOR_TEXT_WHITE)
    btnWithdrawAll.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(71, 85, 105) or Color(51, 65, 85))
    end
    btnWithdrawAll.DoClick = function()
        local curBank = atmFrame.bankMoney or 0
        if curBank <= 0 then return end
        net.Start("GRID_ATM_Action")
            net.WriteEntity(atmFrame.atmEnt)
            net.WriteBool(false)
            net.WriteUInt(curBank, 32)
        net.SendToServer()
    end
end)

