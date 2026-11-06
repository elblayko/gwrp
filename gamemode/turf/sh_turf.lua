--[[
    sh_turf.lua - Shared Turf Definitions & Zones
--]]

GRID = GRID or {}
GRID.Turf = GRID.Turf or {}

-- Active runtime turf zones on current map
GRID.Turf.Zones = GRID.Turf.Zones or {}

-- Spatial Zone Query Helper
function GRID.Turf.GetZoneAtPos(pos)
    if not pos then return nil, nil end
    for id, zone in pairs(GRID.Turf.Zones) do
        local rad = zone.radius or 450
        if zone.pos and pos:DistToSqr(zone.pos) <= (rad * rad) then
            return zone, id
        end
    end
    return nil, nil
end
