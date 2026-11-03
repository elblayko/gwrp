--[[
    entities/entities/gwrp_flag_pole/init.lua
    Progressive Territory Capture Flag Pole
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_c17/utilitypole01a.mdl")
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
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[activator] or 0) > now then return end
    self.NextUsePerPlayer[activator] = now + 1.0

    local turfId = self:GetTurfID()
    local zone = GWRP.Turf and GWRP.Turf.Zones and GWRP.Turf.Zones[turfId]
    if not zone then return end

    local faction = activator:GetFaction()
    if not faction or faction.id == "neutral" then
        GWRP.Notify(activator, "Join a Gang or Police (F4) to contest turf!", NOTIFY_ERROR)
        return
    end

    local claimant = ""
    if faction.id == "police" then
        claimant = "Police"
    else
        claimant = activator:GetGang()
        if claimant == "" then
            GWRP.Notify(activator, "You must create or join a player gang first! Type: /creategang <name>", NOTIFY_ERROR)
            return
        end
    end

    if string.lower(zone.owner or "") == string.lower(claimant) then
        GWRP.Notify(activator, zone.name .. " is already controlled by " .. claimant .. "!", NOTIFY_GENERIC)
        return
    end

    -- Already being captured?
    if self:GetIsCapturing() then
        local curPly = self:GetCapturingPlayer()
        if curPly == activator then
            GWRP.Notify(activator, "You are already contesting this territory! Stay close.", NOTIFY_HINT, 2)
            return
        elseif IsValid(curPly) and string.lower(self:GetCapturingGang()) == string.lower(claimant) then
            GWRP.Notify(activator, "Your ally " .. curPly:Nick() .. " is capturing this territory! Guard them!", NOTIFY_HINT, 3)
            return
        else
            local capturerName = IsValid(curPly) and curPly:Nick() or self:GetCapturingGang()
            GWRP.Notify(activator, "Territory is currently being contested by " .. capturerName .. "! Eliminate them to stop capture.", NOTIFY_ERROR, 3)
            return
        end
    end

    -- Begin progressive lockpick-style capture
    local duration = (GWRP.Config and GWRP.Config.TurfCaptureTime) or 15
    self:SetIsCapturing(true)
    self:SetCaptureStartTime(CurTime())
    self:SetCaptureEndTime(CurTime() + duration)
    self:SetCapturingPlayer(activator)
    self:SetCapturingGang(claimant)
    self.NextBeep = CurTime() + 0.8

    self:EmitSound("ambient/machines/thumper_startup1.wav", 75, 115)
    GWRP.Notify(activator, string.format("Contesting %s for %s! Stay close to the pole (%ds)...", zone.name, claimant, duration), NOTIFY_HINT, 4)

    -- Alert current territory controllers
    local currentOwner = zone.owner
    if currentOwner and currentOwner ~= "" and currentOwner ~= "neutral" then
        for _, p in ipairs(player.GetAll()) do
            local pGang = p:GetGang()
            local pFaction = p:GetFaction()
            local pClaim = (pGang ~= "") and pGang or (pFaction and pFaction.id == "police" and "Police" or "")
            if string.lower(pClaim) == string.lower(currentOwner) then
                GWRP.Notify(p, string.format("[TURF WAR ALERT] %s is contesting %s!", claimant, zone.name), NOTIFY_ERROR, 5)
            end
        end
    end

    self:NextThink(CurTime())
end

function ENT:Think()
    if not self:GetIsCapturing() then return end

    local ply = self:GetCapturingPlayer()
    local turfId = self:GetTurfID()
    local zone = GWRP.Turf and GWRP.Turf.Zones and GWRP.Turf.Zones[turfId]

    -- Interruption validation
    if not IsValid(ply) or not ply:Alive() or ply:GetPos():DistToSqr(self:GetPos()) > (220 * 220) then
        self:CancelCapture("Capture interrupted (you moved too far away or died)!")
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
        GWRP.Turf.FinalizeCapture(turfId, ply, claimant)
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
        GWRP.Notify(ply, reason, NOTIFY_ERROR, 3)
    end
end

function ENT:OnRemove()
    self:CancelCapture()
end
