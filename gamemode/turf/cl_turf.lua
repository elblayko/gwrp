--[[
    cl_turf.lua - Client Turf Synchronization & Top Bar HUD
--]]

GW.Turf = GW.Turf or {}
GW.TurfData = GW.TurfData or {}

-- Full Zone Definitions Sync
net.Receive("GW_SyncTurfZones", function()
    local count = net.ReadUInt(8)
    GW.Turf.Zones = {}

    for i = 1, count do
        local id = net.ReadUInt(8)
        local name = net.ReadString()
        local pos = net.ReadVector()
        local radius = net.ReadUInt(16)
        local owner = net.ReadString()
        local progress = net.ReadUInt(8)

        GW.Turf.Zones[id] = {
            id = id,
            name = name,
            pos = pos,
            radius = radius,
            owner = owner,
            progress = progress
        }

        GW.TurfData[id] = {
            owner = owner,
            progress = progress
        }
    end

    if GW.Turf.RefreshSetupMenu then
        GW.Turf.RefreshSetupMenu()
    end
end)

-- Real-time Ownership & Capture Updates
net.Receive("GW_TurfUpdate", function()
    local id = net.ReadUInt(8)
    local owner = net.ReadString()
    local progress = net.ReadUInt(8)

    GW.TurfData[id] = {
        owner = owner,
        progress = progress
    }

    if GW.Turf.Zones[id] then
        GW.Turf.Zones[id].owner = owner
        GW.Turf.Zones[id].progress = progress
    end
end)

function GW.Turf.DrawHUD()
    local zoneCount = table.Count(GW.Turf.Zones)
    if zoneCount == 0 then return end

    local scrW = ScrW()
    local startY = 16
    local totalW = zoneCount * 160 + (zoneCount - 1) * 12
    local startX = (scrW - totalW) / 2

    local idx = 0
    for id, zone in pairs(GW.Turf.Zones) do
        local data = GW.TurfData[id] or { owner = zone.owner, progress = 100 }
        local curX = startX + idx * 172
        idx = idx + 1

        -- Background Pill
        draw.RoundedBox(6, curX, startY, 160, 32, GW.Colors.Background)

        -- Zone Name
        draw.SimpleText(zone.name, "GW_FontSmall", curX + 80, startY + 4, GW.Colors.White, TEXT_ALIGN_CENTER)

        -- Owner String & Dynamic Color
        local ownerStr = (data.owner and data.owner ~= "" and data.owner ~= "neutral") and data.owner or "Neutral"
        local ownerCol = GW.GetGangColor(data.owner)
        draw.SimpleText(ownerStr, "GW_FontSmall", curX + 80, startY + 16, ownerCol, TEXT_ALIGN_CENTER)

        -- Progress bar underline
        draw.RoundedBox(2, curX + 8, startY + 28, 144, 2, Color(30, 41, 59))
        draw.RoundedBox(2, curX + 8, startY + 28, 144 * (data.progress / 100), 2, ownerCol)
    end
end
