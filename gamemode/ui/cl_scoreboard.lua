--[[
    cl_scoreboard.lua - GangWars RP Faction Scoreboard
--]]

local ScoreboardFrame = nil

function GM:ScoreboardShow()
    if IsValid(ScoreboardFrame) then ScoreboardFrame:Show() return end

    local frame = vgui.Create("DFrame")
    frame:SetSize(750, 520)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    ScoreboardFrame = frame

    frame.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(15, 23, 42, 245))
        draw.RoundedBox(8, 0, 0, w, 45, Color(30, 41, 59))
        draw.SimpleText("GANGWARS RP — Toxic", "GW_FontLarge", 20, 10, GW.Colors.Border)
        draw.SimpleText("Players Online: " .. #player.GetAll(), "GW_FontSmall", w - 20, 15, GW.Colors.White, TEXT_ALIGN_RIGHT)
    end

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(10, 50, 10, 10)

    for _, ply in ipairs(player.GetAll()) do
        local line = scroll:Add("DPanel")
        line:Dock(TOP)
        line:SetTall(38)
        line:DockMargin(0, 0, 0, 4)

        local job = ply:GetJobData()
        local gang = ply:GetGang()
        local col = (gang ~= "") and GW.GetGangColor(gang) or (job and job.faction and job.faction.color or GW.Colors.White)

        line.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(24, 32, 47))
            draw.RoundedBox(4, 0, 0, 6, h, col)

            -- Player Level Capsule Badge
            local lvl = ply.GetLevel and ply:GetLevel() or 1
            local lvlStr = "LVL " .. lvl
            surface.SetFont("GW_UI_Badge")
            local lw = surface.GetTextSize(lvlStr)
            local pillW = lw + 14
            draw.RoundedBox(4, 16, 8, pillW, 22, Color(245, 158, 11, 40))
            surface.SetDrawColor(245, 158, 11, 160)
            surface.DrawOutlinedRect(16, 8, pillW, 22, 1)
            draw.SimpleText(lvlStr, "GW_UI_Badge", 16 + pillW / 2, 19, Color(251, 191, 36), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            draw.SimpleText(ply:Nick(), "GW_FontMedium", 16 + pillW + 10, 8, GW.Colors.White)
            if gang ~= "" then
                draw.SimpleText("[" .. gang .. "]", "GW_FontSmall", 250, 11, col)
            end
            draw.SimpleText(job and job.name or "Citizen", "GW_FontSmall", 410, 11, col)
            draw.SimpleText("Ping: " .. ply:Ping() .. "ms", "GW_FontSmall", w - 20, 11, GW.Colors.Muted, TEXT_ALIGN_RIGHT)
        end
    end
end

function GM:ScoreboardHide()
    if IsValid(ScoreboardFrame) then
        ScoreboardFrame:Hide()
    end
end
