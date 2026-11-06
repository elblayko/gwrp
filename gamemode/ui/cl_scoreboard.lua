--[[
    cl_scoreboard.lua - GridRP Faction Scoreboard
    Author: Juicebox & Antigravity
--]]

local ScoreboardFrame = nil

function GM:ScoreboardShow()
    if IsValid(ScoreboardFrame) then
        ScoreboardFrame:Show()
        return
    end

    local frame = vgui.Create("DFrame")
    frame:SetSize(750, 520)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    ScoreboardFrame = frame

    local colors = (GRID and GRID.Colors) or {}

    frame.Paint = function(s, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(15, 23, 42, 245))
        draw.RoundedBox(8, 0, 0, w, 45, Color(30, 41, 59))
        draw.SimpleText("GRIDRP — Juicebox", "GRID_FontLarge", 20, 10, colors.Border or Color(56, 189, 248))
        draw.SimpleText("Players Online: " .. #player.GetAll(), "GRID_FontSmall", w - 20, 15,
            colors.White or Color(255, 255, 255), TEXT_ALIGN_RIGHT)
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
        local getGangCol = GRID and GRID.GetGangColor
        local col = (gang ~= "") and (getGangCol and getGangCol(gang) or Color(168, 85, 247)) or
        (job and job.faction and job.faction.color or colors.White or Color(255, 255, 255))

        line.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(24, 32, 47))
            draw.RoundedBox(4, 0, 0, 6, h, col)

            -- Player Level Capsule Badge
            local lvl = ply.GetLevel and ply:GetLevel() or 1
            local lvlStr = "LVL " .. lvl
            surface.SetFont("GRID_UI_Badge")
            local lw = surface.GetTextSize(lvlStr)
            local pillW = lw + 14
            draw.RoundedBox(4, 16, 8, pillW, 22, Color(245, 158, 11, 40))
            surface.SetDrawColor(245, 158, 11, 160)
            surface.DrawOutlinedRect(16, 8, pillW, 22, 1)
            draw.SimpleText(lvlStr, "GRID_UI_Badge", 16 + pillW / 2, 19, Color(251, 191, 36), TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)

            draw.SimpleText(ply:Nick(), "GRID_FontMedium", 16 + pillW + 10, 8, colors.White or Color(255, 255, 255))
            if gang ~= "" then
                draw.SimpleText("[" .. gang .. "]", "GRID_FontSmall", 250, 11, col)
            end
            draw.SimpleText(job and job.name or "Citizen", "GRID_FontSmall", 410, 11, col)
            draw.SimpleText("Ping: " .. ply:Ping() .. "ms", "GRID_FontSmall", w - 20, 11,
                colors.Muted or Color(148, 163, 184), TEXT_ALIGN_RIGHT)
        end
    end
end

function GM:ScoreboardHide()
    if IsValid(ScoreboardFrame) then
        ScoreboardFrame:Hide()
    end
end
