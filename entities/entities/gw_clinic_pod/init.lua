--[[
    entities/entities/gw_clinic_pod/init.lua
    GWRP Clinical Triage Pod Server Logic
    Author: Toxic
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("GW_OpenClinicMenu")
util.AddNetworkString("GW_Clinic_PurchaseTreatment")

function ENT:Initialize()
    self:SetModel("models/props/de_nuke/nucleartestcabinet.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:EnableMotion(false) -- Anchor booth firmly to ground
    end

    self:SetVaultCash(0)
    self:SetTotalPatients(0)
    self:SetDoctorOnDuty(false)
end

function ENT:Think()
    local now = CurTime()
    local owner = self:GetOwnerPlayer()

    -- Check if Pharmacist is physically within clinical proximity (~10m / 200 units)
    local isNear = false
    if IsValid(owner) and owner:Alive() and owner:GetJob() == "pharmacist" then
        if owner:GetPos():DistToSqr(self:GetPos()) <= (220 * 220) then
            isNear = true
        end
    end

    if self:GetDoctorOnDuty() ~= isNear then
        self:SetDoctorOnDuty(isNear)
    end

    self:NextThink(now + 1.0)
    return true
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local now = CurTime()
    self.NextUsePerPlayer = self.NextUsePerPlayer or {}
    if (self.NextUsePerPlayer[activator] or 0) > now then return end
    self.NextUsePerPlayer[activator] = now + 0.4

    local owner = self:GetOwnerPlayer()

    -- If owner is crouching on the pod, collect stored vault cash reserves
    if activator == owner and activator:Crouching() then
        local vault = self:GetVaultCash()
        if vault > 0 then
            activator:AddMoney(vault)
            self:SetVaultCash(0)
            activator:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 100)
            GW.Notify(activator, string.format("Emptied Clinic Vault Reserves: +$%d collected!", vault), NOTIFY_GENERIC)
            return
        else
            GW.Notify(activator, "Clinic Vault Reserves are currently empty ($0).", NOTIFY_HINT)
            return
        end
    end

    -- Send clinical treatment menu
    net.Start("GW_OpenClinicMenu")
    net.WriteEntity(self)
    net.WriteBool(self:GetDoctorOnDuty())
    net.WriteInt(self:GetVaultCash(), 32)
    net.WriteInt(self:GetTotalPatients(), 32)
    net.Send(activator)

    activator:EmitSound("buttons/button14.wav", 60, 100)
end

net.Receive("GW_Clinic_PurchaseTreatment", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end

    local pod = net.ReadEntity()
    local treatId = net.ReadString()

    if not IsValid(pod) or pod:GetClass() ~= "gw_clinic_pod" then return end
    if ply:GetPos():DistToSqr(pod:GetPos()) > (160 * 160) then
        GW.Notify(ply, "You are too far from the Clinic Pod!", NOTIFY_ERROR)
        return
    end

    local treatDef = GW.ClinicTreatments and GW.ClinicTreatments[treatId]
    if not treatDef then return end

    if not ply:CanAfford(treatDef.cost) then
        GW.Notify(ply, "You cannot afford this treatment!", NOTIFY_ERROR)
        return
    end

    -- Process payment
    ply:AddMoney(-treatDef.cost)

    local owner = pod:GetOwnerPlayer()
    local isDoc = pod:GetDoctorOnDuty()

    -- 80% Direct Deposit to Pharmacist, 20% to Pod Vault
    local ownerCut = math.floor(treatDef.cost * 0.80)
    local vaultCut = treatDef.cost - ownerCut

    if IsValid(owner) and owner:IsPlayer() then
        owner:AddMoney(ownerCut)
        GW.Notify(owner,
            string.format("[CLINIC] %s received %s ($%d)! +$%d earned.", ply:Nick(), treatDef.name, treatDef.cost,
                ownerCut), NOTIFY_GENERIC, 6)
        owner:EmitSound("ambient/levels/labs/coinslot1.wav", 55, 110)
    end

    pod:SetVaultCash(pod:GetVaultCash() + vaultCut)
    pod:SetTotalPatients(pod:GetTotalPatients() + 1)

    -- Apply treatment
    treatDef.Apply(ply, isDoc)

    -- Triage effect at pod
    local ed = EffectData()
    ed:SetOrigin(pod:GetPos() + Vector(0, 0, 45))
    ed:SetNormal(Vector(0, 0, 1))
    ed:SetScale(1.0)
    util.Effect("WheelDust", ed)

    local notifyMsg = isDoc and string.format("Received %s with [DR. ON DUTY BONUS]!", treatDef.name) or
    string.format("Received %s from Autonomous Clinic!", treatDef.name)
    GW.Notify(ply, notifyMsg, NOTIFY_GENERIC, 5)
end)
