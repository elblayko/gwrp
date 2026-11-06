--[[
    cl_chatbox.lua - Roleplay Chat Coloration (/advert, /ooc, /radio, /g)
    Author: Juicebox & Antigravity
--]]

GRID = GRID or {}
GRID.UI = GRID.UI or {}

local function HandleChatMessage()
    local gang = net.ReadString()
    local nick = net.ReadString()
    local msg = net.ReadString()
    local getGangCol = GRID and GRID.GetGangColor
    local col = getGangCol and getGangCol(gang) or Color(168, 85, 247)
    local colors = (GRID and GRID.Colors) or {}
    chat.AddText(col, gang .. " | ", colors.White or Color(255, 255, 255), nick, ": ", Color(230, 230, 230), msg)
end

net.Receive("GRID_ChatMessage", HandleChatMessage)

hook.Add("OnPlayerChat", "GRID_FormatChat", function(ply, strText, bTeam, bDead)
    local colors = (GRID and GRID.Colors) or {}
    local getGangCol = GRID and GRID.GetGangColor

    if not IsValid(ply) then
        -- Console / Server announcement
        chat.AddText(Color(56, 189, 248), "Server: ", colors.White or Color(255, 255, 255), strText)
        return true
    end

    local job = ply:GetJobData()
    local faction = ply:GetFaction()
    local gangName = ply:GetGang()
    local gangCol = (gangName ~= "") and (getGangCol and getGangCol(gangName) or Color(168, 85, 247)) or
    (faction and faction.color or colors.White or Color(255, 255, 255))

    local lower = string.lower(string.Trim(strText))
    local ui = GRID.UI
    if lower == "/f4" or lower == "!f4" or lower == "/menu" or lower == "!menu" then
        if ui and ui.ToggleF4Menu then
            ui.ToggleF4Menu()
        end
        return true
    elseif lower == "/inv" or lower == "!inv" or lower == "/inventory" or lower == "!inventory" then
        if ui then
            ui.ActiveF4Tab = "inventory"
            if IsValid(ui.F4Frame) then
                if ui.RefreshInventoryTab then
                    ui.RefreshInventoryTab()
                end
            elseif ui.ToggleF4Menu then
                ui.ToggleF4Menu()
            end
        end
        return true
    end

    if string.StartWith(strText, "/advert ") then
        local msg = string.sub(strText, 9)
        chat.AddText(colors.Gold or Color(245, 158, 11), "Advert | ", gangCol, ply:Nick(),
            colors.White or Color(255, 255, 255), ": " .. msg)
        return true
    elseif string.StartWith(strText, "/ooc ") then
        local msg = string.sub(strText, 6)
        chat.AddText(colors.Muted or Color(148, 163, 184), "OOC | ", gangCol, ply:Nick(),
            colors.White or Color(255, 255, 255), ": " .. msg)
        return true
    elseif string.StartWith(strText, "/radio ") then
        local msg = string.sub(strText, 8)
        local radioTag = (gangName ~= "") and gangName or (faction and faction.name or "Citizen")
        chat.AddText(gangCol, "Radio (" .. radioTag .. "): ", ply:Nick(), colors.White or Color(255, 255, 255),
            ": " .. msg)
        return true
    else
        -- Standard proximity speech
        local tag = (gangName ~= "") and (gangName .. " - " .. (job and job.name or "Citizen")) or
        (job and job.name or "Citizen")
        chat.AddText(gangCol, tag .. " | ", Color(255, 255, 255), ply:Nick(), Color(220, 220, 220), ": " .. strText)
        return true
    end
end)
