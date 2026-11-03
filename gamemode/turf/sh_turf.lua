--[[
    sh_turf.lua - Shared Turf Definitions & Zones
--]]

GWRP.Turf = GWRP.Turf or {}

-- Default Starter Templates (Used if no per-map JSON profile exists yet)
GWRP.Turf.DefaultTemplates = {
    ["rp_downtown_v4c_v2"] = {
        [1] = { id = 1, name = "Downtown Plaza", pos = Vector(-137, -196, -143), radius = 500, owner = "neutral", progress = 100 },
        [2] = { id = 2, name = "Eastside Slums", pos = Vector(-2010, -1480, -140), radius = 450, owner = "neutral", progress = 100 },
        [3] = { id = 3, name = "Industrial Warehouses", pos = Vector(1620, -1890, -140), radius = 450, owner = "neutral", progress = 100 },
        [4] = { id = 4, name = "Central Bank Vault", pos = Vector(-1420, -560, -140), radius = 350, owner = "Police", progress = 100 }
    }
}

-- Active runtime turf zones on current map
GWRP.Turf.Zones = GWRP.Turf.Zones or {}
