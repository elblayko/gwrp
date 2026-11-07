--[[
    entities/entities/grid_flag_pole/init.lua
    Progressive Territory Capture Flag Pole
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_trainstation/trainstation_post001.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    self:DrawShadow(true)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Wake()
    else
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 300))
    end

    self:SetIsCapturing(false)
    self:SetCaptureStartTime(0)
    self:SetCaptureEndTime(0)
    self:SetCapturingGang("")
    self:SetCaptureRadius(250)
    self:SetInfluenceRadius(800)
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[activator] or 0) > now then return end
    self.NextUsePerPlayer[activator] = now + 1.0

    -- SuperAdmin with Physgun: Open Entity Configuration UI
    if activator:IsSuperAdmin() and IsValid(activator:GetActiveWeapon()) and activator:GetActiveWeapon():GetClass() == "weapon_physgun" then
        if GRID.MapSpawns and GRID.MapSpawns.OpenEntityConfig then
            GRID.MapSpawns.OpenEntityConfig(activator, self)
            return
        end
    end

    local turfId = self:GetTurfID()
    local zone = GRID.Turf and GRID.Turf.Zones and GRID.Turf.Zones[turfId]
    if not zone then return end

    if GRID.Population and GRID.Population.CanCaptureTurf then
        local canCap, reason = GRID.Population.CanCaptureTurf()
        if not canCap then
            GRID.Notify(activator, reason, NOTIFY_ERROR)
            return
        end
    end

    local faction = activator:GetFaction()
    if not faction or faction.id == "neutral" then
        GRID.Notify(activator, "Join a Gang or Police (F4) to contest turf!", NOTIFY_ERROR)
        return
    end

    local claimant = ""
    if faction.id == "police" then
        claimant = "Police"
    else
        claimant = activator:GetGang()
        if claimant == "" then
            GRID.Notify(activator, "You must create or join a player gang first! Type: /creategang <name>", NOTIFY_ERROR)
            return
        end
    end

    if string.lower(zone.owner or "") == string.lower(claimant) then
        if activator:GetNWBool("GRID_IsGangLeader", false) or (activator.GetJob and activator:GetJob() == "gang_leader") or activator:IsAdmin() then
            local gData = GRID.Database and GRID.Database.GetGang and GRID.Database.GetGang(claimant)
            local bank = gData and gData.bank or 0
            net.Start("GRID_OpenTurfTaxMenu")
            net.WriteUInt(turfId, 8)
            net.WriteString(zone.name or "")
            net.WriteUInt(zone.tax_rate or 10, 8)
            net.WriteUInt(bank, 32)
            net.Send(activator)
            return
        else
            GRID.Notify(activator,
                string.format(
                "%s is controlled by %s (Protection Tax: %d%%). Only your Gang Leader can configure taxes.", zone.name,
                    claimant, zone.tax_rate or 10), NOTIFY_GENERIC)
            return
        end
    end

    -- Already being captured?
    if self:GetIsCapturing() then
        local curPly = self:GetCapturingPlayer()
        if curPly == activator then
            GRID.Notify(activator, "You are already contesting this territory! Stay close.", NOTIFY_HINT, 2)
            return
        elseif IsValid(curPly) and string.lower(self:GetCapturingGang()) == string.lower(claimant) then
            GRID.Notify(activator, "Your ally " .. curPly:Nick() .. " is capturing this territory! Guard them!",
                NOTIFY_HINT, 3)
            return
        else
            local capturerName = IsValid(curPly) and curPly:Nick() or self:GetCapturingGang()
            GRID.Notify(activator,
                "Territory is currently being contested by " .. capturerName .. "! Eliminate them to stop capture.",
                NOTIFY_ERROR, 3)
            return
        end
    end

    -- Begin progressive lockpick-style capture
    local duration = (GRID.Config and GRID.Config.TurfCaptureTime) or 15
    self:SetIsCapturing(true)
    self:SetCaptureStartTime(CurTime())
    self:SetCaptureEndTime(CurTime() + duration)
    self:SetCapturingPlayer(activator)
    self:SetCapturingGang(claimant)
    self.NextBeep = CurTime() + 0.8

    self:EmitSound("ambient/machines/thumper_startup1.wav", 75, 115)
    GRID.Notify(activator,
        string.format("Contesting %s for %s! Stay close to the pole (%ds)...", zone.name, claimant, duration),
        NOTIFY_HINT, 4)

    -- Alert current territory controllers
    local currentOwner = zone.owner
    if currentOwner and currentOwner ~= "" and currentOwner ~= "neutral" then
        for _, p in ipairs(player.GetAll()) do
            local pGang = p:GetGang()
            local pFaction = p:GetFaction()
            local pClaim = (pGang ~= "") and pGang or (pFaction and pFaction.id == "police" and "Police" or "")
            if string.lower(pClaim) == string.lower(currentOwner) then
                GRID.Notify(p, string.format("[TURF WAR ALERT] %s is contesting %s!", claimant, zone.name), NOTIFY_ERROR,
                    5)
            end
        end
    end

    self:NextThink(CurTime())
end

function ENT:Think()
    if not self:GetIsCapturing() then return end

    local ply = self:GetCapturingPlayer()
    local turfId = self:GetTurfID()
    local zone = GRID.Turf and GRID.Turf.Zones and GRID.Turf.Zones[turfId]

    -- Interruption validation against configurable Capture Zone Radius
    local capRadius = self:GetCaptureRadius()
    if not capRadius or capRadius <= 0 then
        capRadius = (zone and (tonumber(zone.capture_radius) or tonumber(zone.radius))) or 250
    end
    local maxDistSqr = capRadius * capRadius

    if not IsValid(ply) or not ply:Alive() or ply:GetPos():DistToSqr(self:GetPos()) > maxDistSqr then
        self:CancelCapture("Capture interrupted (you moved outside the capture zone or died)!")
        return
    end

    -- Real-time audio cue
    if (self.NextBeep or 0) < CurTime() then
        self.NextBeep = CurTime() + 1.2
        self:EmitSound("buttons/blip1.wav", 65, 120)
    end

    -- Completion Check
    if CurTime() >= self:GetCaptureEndTime() then
        local claimant = self:GetCapturingGang()
        if claimant == "" then claimant = "Contender" end

        self:SetIsCapturing(false)
        self:SetCapturingPlayer(NULL)
        self:SetCapturingGang("")

        self:EmitSound("buttons/button3.wav", 75, 100)
        GRID.Turf.FinalizeCapture(turfId, ply, claimant)
    end

    self:NextThink(CurTime() + 0.1)
    return true
end

function ENT:CancelCapture(reason)
    if not self:GetIsCapturing() then return end

    local ply = self:GetCapturingPlayer()
    self:SetIsCapturing(false)
    self:SetCaptureStartTime(0)
    self:SetCaptureEndTime(0)
    self:SetCapturingPlayer(NULL)
    self:SetCapturingGang("")

    self:EmitSound("buttons/button10.wav", 70, 90)

    if IsValid(ply) and reason then
        GRID.Notify(ply, reason, NOTIFY_ERROR, 3)
    end
end

function ENT:OnRemove()
    self:CancelCapture()

    -- If this pole was registered as an active zone entity, clean up on removal
    local turfId = self:GetTurfID()
    if turfId and turfId > 0 and GRID.Turf and GRID.Turf.Zones and GRID.Turf.Zones[turfId] then
        if GRID.Turf.Zones[turfId].entity == self then
            GRID.Turf.Zones[turfId] = nil
            if GRID.Turf.SaveMapProfile then
                GRID.Turf.SaveMapProfile()
            end
            if GRID.Turf.SyncToAll then
                GRID.Turf.SyncToAll()
            end
        end
    end
end

-- Custom metadata integration with GRID.MapSpawns
function ENT:GetMapData()
    local turfId = self:GetTurfID()
    local zone = GRID.Turf and GRID.Turf.Zones and GRID.Turf.Zones[turfId]
    return {
        turf_id = turfId,
        name = zone and zone.name or ("Turf Zone #" .. tostring(turfId)),
        capture_radius = zone and (tonumber(zone.capture_radius) or tonumber(zone.radius)) or self:GetCaptureRadius(),
        influence_radius = zone and (tonumber(zone.influence_radius) or tonumber(zone.radius)) or
        self:GetInfluenceRadius(),
        owner = zone and zone.owner or "neutral",
        tax_rate = zone and zone.tax_rate or 10
    }
end

function ENT:OnMapDataLoaded(data)
    if not istable(data) then return end
    local turfId = tonumber(data.turf_id) or 0
    if turfId > 0 then
        self:SetTurfID(turfId)
        local capRad = tonumber(data.capture_radius) or tonumber(data.radius) or 250
        local infRad = tonumber(data.influence_radius) or tonumber(data.radius) or 800
        self:SetCaptureRadius(capRad)
        self:SetInfluenceRadius(infRad)

        if GRID.Turf and GRID.Turf.Zones then
            GRID.Turf.Zones[turfId] = GRID.Turf.Zones[turfId] or {}
            GRID.Turf.Zones[turfId].id = turfId
            GRID.Turf.Zones[turfId].name = data.name or ("Turf Zone #" .. turfId)
            GRID.Turf.Zones[turfId].pos = self:GetPos()
            GRID.Turf.Zones[turfId].radius = infRad
            GRID.Turf.Zones[turfId].capture_radius = capRad
            GRID.Turf.Zones[turfId].influence_radius = infRad
            GRID.Turf.Zones[turfId].owner = data.owner or "neutral"
            GRID.Turf.Zones[turfId].progress = 100
            GRID.Turf.Zones[turfId].tax_rate = tonumber(data.tax_rate) or 10
            GRID.Turf.Zones[turfId].entity = self

            if GRID.Turf.SyncToAll then
                GRID.Turf.SyncToAll()
            end
        end
    end
end
