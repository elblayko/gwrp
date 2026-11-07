--[[
    entities/entities/grid_auction_terminal/cl_init.lua
    Client 3D2D Display for Auction Terminal (Surface-Mounted Console Display)
    Author: Juicebox & Antigravity
--]]

include("shared.lua")

local cachedSightTraces = {}

local function HasLineOfSight(ent, startPos, endPos)
    local idx = ent:EntIndex()
    local cached = cachedSightTraces[idx]
    local now = CurTime()

    if cached and cached.time > now then
        return cached.visible
    end

    local tr = util.TraceLine({
        start = startPos,
        endpos = endPos,
        filter = { LocalPlayer(), ent },
        mask = MASK_SOLID_BRUSHONLY
    })

    local isVisible = not tr.Hit
    cachedSightTraces[idx] = {
        visible = isVisible,
        time = now + 0.2
    }
    return isVisible
end

function ENT:Draw()
    self:DrawModel()

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local maxDist = (GRID.Config and GRID.Config.EntityHUDViewDistance) or 320
    local eyePos = ply:EyePos()
    local entPos = self:GetPos()

    if eyePos:DistToSqr(entPos) > (maxDist * maxDist) then return end

    -- Position directly on the Combine Interface monitor screen
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 45)

    local pos = entPos + self:GetUp() * 45 + self:GetForward() * 2

    if not HasLineOfSight(self, eyePos, pos) then return end

    local dist = math.sqrt(eyePos:DistToSqr(pos))
    local alpha = 255
    if dist > 220 then
        alpha = math.Clamp((1 - (dist - 220) / (maxDist - 220)) * 255, 0, 255)
    end
    if alpha <= 0 then return end

    local a = math.floor(alpha)

    cam.Start3D2D(pos, ang, 0.055)
        -- Terminal Screen Housing Plate (240x110)
        draw.RoundedBox(6, -120, -55, 240, 110, Color(11, 15, 25, math.floor(a * 0.96)))
        surface.SetDrawColor(30, 41, 59, math.floor(a * 0.85))
        surface.DrawOutlinedRect(-120, -55, 240, 110, 1)

        -- Top Cyan Line
        draw.RoundedBox(2, -120, -55, 240, 3, Color(6, 182, 212, a))

        -- Brand Header
        draw.SimpleText("GRID AUCTION", "GRID_UI_Header", 0, -32, Color(248, 250, 252, a), TEXT_ALIGN_CENTER)

        -- Subtitle Info
        local count = self.GetActiveAuctions and self:GetActiveAuctions() or 0
        if count == 0 and GRID.Auction and GRID.Auction.Listings then
            count = #GRID.Auction.Listings
        end
        local subText = (count > 0) and string.format("GLOBAL EXCHANGE  |  %d LISTINGS", count) or "GLOBAL MARKETPLACE"
        draw.SimpleText(subText, "GRID_UI_Caption", 0, -10, Color(56, 189, 248, a), TEXT_ALIGN_CENTER)

        -- Action Keycap Badge
        draw.RoundedBox(4, -90, 14, 180, 28, Color(16, 185, 129, math.floor(a * 0.2)))
        surface.SetDrawColor(16, 185, 129, math.floor(a * 0.7))
        surface.DrawOutlinedRect(-90, 14, 180, 28, 1)
        draw.SimpleText("[E] OPEN MARKETPLACE", "GRID_UI_Badge", 0, 28, Color(74, 222, 128, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
