--[[
    sh_turf.lua - Shared Turf Definitions & Zones
--]]

GRID = GRID or {}
GRID.Turf = GRID.Turf or {}

-- Default Starter Templates (Used if no per-map JSON profile exists yet)
GRID.Turf.DefaultTemplates = {
    ["rp_downtown_v4c_v2"] = {
        [1] = { id = 1, name = "Downtown Plaza", pos = Vector(-137, -196, -143), radius = 500, owner = "neutral", progress = 100, tax_rate = 10 },
        [2] = { id = 2, name = "Eastside Slums", pos = Vector(-2010, -1480, -140), radius = 450, owner = "neutral", progress = 100, tax_rate = 10 },
        [3] = { id = 3, name = "Industrial Warehouses", pos = Vector(1620, -1890, -140), radius = 450, owner = "neutral", progress = 100, tax_rate = 10 },
        [4] = { id = 4, name = "Central Bank Vault", pos = Vector(-1420, -560, -140), radius = 350, owner = "Police", progress = 100, tax_rate = 10 }
    }
}

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
