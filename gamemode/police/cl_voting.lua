--[[
    gamemode/police/cl_voting.lua
    GridRP Police Department Warrant Voting System - Client GUI Modal
    Author: GRID Core Team
--]]

include("sh_voting.lua")

GRID.PoliceVoting.ActivePanel = nil

net.Receive("GRID_PoliceVoteEnd", function()
    local passed = net.ReadBool()
    if IsValid(GRID.PoliceVoting.ActivePanel) then
        GRID.PoliceVoting.ActivePanel:Close()
        GRID.PoliceVoting.ActivePanel = nil
    end
end)

net.Receive("GRID_PoliceVoteStart", function()
    local target = net.ReadEntity()
    local suspectNick = net.ReadString()
    local reason = net.ReadString()
    local initiatorNick = net.ReadString()
    local duration = net.ReadFloat()

    if IsValid(GRID.PoliceVoting.ActivePanel) then
        GRID.PoliceVoting.ActivePanel:Close()
    end

    local scrW, scrH = ScrW(), ScrH()
    local cardW, cardH = 380, 175
    local cardX = scrW - cardW - 24
    local cardY = 120

    local frame = vgui.Create("DFrame")
    frame:SetSize(cardW, cardH)
    frame:SetPos(cardX, cardY)
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame.StartTime = CurTime()
    frame.EndTime = CurTime() + duration

    surface.PlaySound("ambient/alarms/warningbell1.wav")

    frame.Paint = function(s, w, h)
        -- Obsidian Glassmorphic Base
        draw.RoundedBox(8, 0, 0, w, h, Color(11, 15, 25, 245))
        surface.SetDrawColor(30, 41, 59, 220)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- Top Cyan Stripe
        draw.RoundedBoxEx(4, 0, 0, w, 3, Color(6, 182, 212), true, true, false, false)

        -- Header
        draw.SimpleText("POLICE WARRANT VOTE", "GRID_UI_Badge", 16, 12, Color(6, 182, 212), TEXT_ALIGN_LEFT)
        draw.SimpleText("Initiated by: " .. initiatorNick, "GRID_UI_Caption", w - 16, 12, Color(148, 163, 184), TEXT_ALIGN_RIGHT)

        -- Suspect Name & Reason
        draw.SimpleText("Suspect: " .. suspectNick, "GRID_UI_Header", 16, 32, Color(248, 250, 252), TEXT_ALIGN_LEFT)
        draw.SimpleText("Reason: " .. reason, "GRID_UI_Body", 16, 60, Color(203, 213, 225), TEXT_ALIGN_LEFT)

        -- Time Remaining Bar
        local now = CurTime()
        local pct = math.Clamp((s.EndTime - now) / duration, 0, 1)
        draw.RoundedBox(3, 16, 92, w - 32, 6, Color(30, 41, 59, 200))
        draw.RoundedBox(3, 16, 92, math.floor((w - 32) * pct), 6, Color(56, 189, 248, 220))

        draw.SimpleText(string.format("Voting Closes: %ds", math.ceil(math.max(0, s.EndTime - now))), "GRID_UI_Caption", 16, 102, Color(148, 163, 184), TEXT_ALIGN_LEFT)
    end

    local function CastVote(choice)
        net.Start("GRID_PoliceCastVote")
        net.WriteBool(choice)
        net.SendToServer()

        if IsValid(frame) then
            frame:Close()
            GRID.PoliceVoting.ActivePanel = nil
        end
    end

    -- Vote YES Button
    local btnYes = vgui.Create("DButton", frame)
    btnYes:SetPos(16, 124)
    btnYes:SetSize((cardW - 42) / 2, 36)
    btnYes:SetText("")
    btnYes.Paint = function(s, w, h)
        local bg = s:IsHovered() and Color(16, 185, 129, 240) or Color(5, 150, 105, 200)
        draw.RoundedBox(6, 0, 0, w, h, bg)
        draw.SimpleText("VOTE YES", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnYes.DoClick = function()
        CastVote(true)
    end

    -- Vote NO Button
    local btnNo = vgui.Create("DButton", frame)
    btnNo:SetPos(cardW / 2 + 5, 124)
    btnNo:SetSize((cardW - 42) / 2, 36)
    btnNo:SetText("")
    btnNo.Paint = function(s, w, h)
        local bg = s:IsHovered() and Color(239, 68, 68, 240) or Color(185, 28, 28, 200)
        draw.RoundedBox(6, 0, 0, w, h, bg)
        draw.SimpleText("VOTE NO", "GRID_UI_Btn", w / 2, h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnNo.DoClick = function()
        CastVote(false)
    end

    GRID.PoliceVoting.ActivePanel = frame
end)

