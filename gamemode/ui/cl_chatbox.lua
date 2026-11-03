--[[
    cl_chatbox.lua - Roleplay Chat Coloration (/advert, /ooc, /radio, /g)
--]]

net.Receive("GWRP_ChatMessage", function()
    local gang = net.ReadString()
    local nick = net.ReadString()
    local msg = net.ReadString()
    local col = GWRP.GetGangColor(gang)
    chat.AddText(col, gang .. " | ", GWRP.Colors.White, nick, ": ", Color(230, 230, 230), msg)
end)

hook.Add("OnPlayerChat", "GWRP_FormatChat", function(ply, strText, bTeam, bDead)
    if not IsValid(ply) then
        -- Console / Server announcement
        chat.AddText(Color(56, 189, 248), "Server: ", GWRP.Colors.White, strText)
        return true
    end

    local job = ply:GetJobData()
    local faction = ply:GetFaction()
    local gangName = ply:GetGang()
    local gangCol = (gangName ~= "") and GWRP.GetGangColor(gangName) or (faction and faction.color or GWRP.Colors.White)

    local lower = string.lower(string.Trim(strText))
    if lower == "/f4" or lower == "!f4" or lower == "/menu" or lower == "!menu" then
        GWRP.UI.ToggleF4Menu()
        return true
    elseif lower == "/inv" or lower == "!inv" or lower == "/inventory" or lower == "!inventory" then
        GWRP.UI.ActiveF4Tab = "inventory"
        if IsValid(GWRP.UI.F4Frame) then
            if GWRP.UI.RefreshInventoryTab then
                GWRP.UI.RefreshInventoryTab()
            end
        else
            GWRP.UI.ToggleF4Menu()
        end
        return true
    end

    if string.StartWith(strText, "/advert ") then
        local msg = string.sub(strText, 9)
        chat.AddText(GWRP.Colors.Gold, "Advert | ", gangCol, ply:Nick(), GWRP.Colors.White, ": " .. msg)
        return true
    elseif string.StartWith(strText, "/ooc ") then
        local msg = string.sub(strText, 6)
        chat.AddText(GWRP.Colors.Muted, "OOC | ", gangCol, ply:Nick(), GWRP.Colors.White, ": " .. msg)
        return true
    elseif string.StartWith(strText, "/radio ") then
        local msg = string.sub(strText, 8)
        local radioTag = (gangName ~= "") and gangName or (faction and faction.name or "Citizen")
        chat.AddText(gangCol, "Radio (" .. radioTag .. "): ", ply:Nick(), GWRP.Colors.White, ": " .. msg)
        return true
    else
        -- Standard proximity speech
        local tag = (gangName ~= "") and (gangName .. " - " .. (job and job.name or "Citizen")) or (job and job.name or "Citizen")
        chat.AddText(gangCol, tag .. " | ", Color(255, 255, 255), ply:Nick(), Color(220, 220, 220), ": " .. strText)
        return true
    end
end)
