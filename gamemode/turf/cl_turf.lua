--[[
    cl_turf.lua - Client Turf Synchronization & Top Bar HUD
--]]

GWRP.Turf = GWRP.Turf or {}
GWRP.TurfData = GWRP.TurfData or {}

-- Full Zone Definitions Sync
net.Receive("GWRP_SyncTurfZones", function()
    local count = net.ReadUInt(8)
    GWRP.Turf.Zones = {}

    for i = 1, count do
        local id = net.ReadUInt(8)
        local name = net.ReadString()
        local pos = net.ReadVector()
        local radius = net.ReadUInt(16)
        local owner = net.ReadString()
        local progress = net.ReadUInt(8)

        GWRP.Turf.Zones[id] = {
            id = id,
            name = name,
            pos = pos,
            radius = radius,
            owner = owner,
            progress = progress
        }

        GWRP.TurfData[id] = {
            owner = owner,
            progress = progress
        }
    end

    if GWRP.Turf.RefreshSetupMenu then
        GWRP.Turf.RefreshSetupMenu()
    end
end)

-- Real-time Ownership & Capture Updates
net.Receive("GWRP_TurfUpdate", function()
    local id = net.ReadUInt(8)
    local owner = net.ReadString()
    local progress = net.ReadUInt(8)

    GWRP.TurfData[id] = {
        owner = owner,
        progress = progress
    }

    if GWRP.Turf.Zones[id] then
        GWRP.Turf.Zones[id].owner = owner
        GWRP.Turf.Zones[id].progress = progress
    end
end)

function GWRP.Turf.DrawHUD()
    local zoneCount = table.Count(GWRP.Turf.Zones)
    if zoneCount == 0 then return end

    local scrW = ScrW()
    local startY = 16
    local totalW = zoneCount * 160 + (zoneCount - 1) * 12
    local startX = (scrW - totalW) / 2

    local idx = 0
    for id, zone in pairs(GWRP.Turf.Zones) do
        local data = GWRP.TurfData[id] or { owner = zone.owner, progress = 100 }
        local curX = startX + idx * 172
        idx = idx + 1

        -- Background Pill
        draw.RoundedBox(6, curX, startY, 160, 32, GWRP.Colors.Background)

        -- Zone Name
        draw.SimpleText(zone.name, "GWRP_FontSmall", curX + 80, startY + 4, GWRP.Colors.White, TEXT_ALIGN_CENTER)

        -- Owner String & Dynamic Color
        local ownerStr = (data.owner and data.owner ~= "" and data.owner ~= "neutral") and data.owner or "Neutral"
        local ownerCol = GWRP.GetGangColor(data.owner)
        draw.SimpleText(ownerStr, "GWRP_FontSmall", curX + 80, startY + 16, ownerCol, TEXT_ALIGN_CENTER)

        -- Progress bar underline
        draw.RoundedBox(2, curX + 8, startY + 28, 144, 2, Color(30, 41, 59))
        draw.RoundedBox(2, curX + 8, startY + 28, 144 * (data.progress / 100), 2, ownerCol)
    end
end
