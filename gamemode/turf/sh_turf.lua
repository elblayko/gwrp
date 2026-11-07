--[[
    sh_turf.lua - Shared Turf Definitions & Zones
--]]

GRID = GRID or {}
GRID.Turf = GRID.Turf or {}

-- Active runtime turf zones on current map
GRID.Turf.Zones = GRID.Turf.Zones or {}

-- Spatial Zone Query Helper (queries against Influence / Extortion radius)
-- If areas overlap, the territory captured FIRST (oldest captured_at timestamp) has prevalence.
function GRID.Turf.GetZoneAtPos(pos)
    if not pos then return nil, nil end

    local bestZone, bestId = nil, nil
    local bestCapturedAt = math.huge
    local bestDistSqr = math.huge

    for id, zone in pairs(GRID.Turf.Zones) do
        local rad = tonumber(zone.influence_radius) or tonumber(zone.radius) or 800
        if zone.pos then
            local distSqr = pos:DistToSqr(zone.pos)
            if distSqr <= (rad * rad) then
                local isControlled = zone.owner and zone.owner ~= "" and zone.owner ~= "neutral"
                local capturedAt = tonumber(zone.captured_at) or (isControlled and 0 or math.huge)

                -- 1. Prioritize controlled zones over neutral
                -- 2. Prioritize earlier captured zones (first captured has prevalence)
                -- 3. Tie-breaker: closer distance to pole
                if not bestZone then
                    bestZone, bestId = zone, id
                    bestCapturedAt = capturedAt
                    bestDistSqr = distSqr
                else
                    local bestIsControlled = bestZone.owner and bestZone.owner ~= "" and bestZone.owner ~= "neutral"
                    if isControlled and not bestIsControlled then
                        bestZone, bestId = zone, id
                        bestCapturedAt = capturedAt
                        bestDistSqr = distSqr
                    elseif (isControlled == bestIsControlled) then
                        if capturedAt < bestCapturedAt then
                            bestZone, bestId = zone, id
                            bestCapturedAt = capturedAt
                            bestDistSqr = distSqr
                        elseif capturedAt == bestCapturedAt and distSqr < bestDistSqr then
                            bestZone, bestId = zone, id
                            bestCapturedAt = capturedAt
                            bestDistSqr = distSqr
                        end
                    end
                end
            end
        end
    end

    return bestZone, bestId
end

-- Spatial Capture Zone Query Helper (queries against Pole Contest / Capture radius)
function GRID.Turf.GetCaptureZoneAtPos(pos)
    if not pos then return nil, nil end

    local bestZone, bestId = nil, nil
    local bestDistSqr = math.huge

    for id, zone in pairs(GRID.Turf.Zones) do
        local rad = tonumber(zone.capture_radius) or tonumber(zone.radius) or 250
        if zone.pos then
            local distSqr = pos:DistToSqr(zone.pos)
            if distSqr <= (rad * rad) and distSqr < bestDistSqr then
                bestZone, bestId = zone, id
                bestDistSqr = distSqr
            end
        end
    end

    return bestZone, bestId
end
