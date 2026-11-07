--[[
    entities/entities/grid_cash_stack/init.lua
    GridRP Cash Stack & Forensic Crime Scene Evidence Entity
    Author: Juicebox / GRID Core Team
--]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = util.IsValidModel("models/props/cs_assault/money.mdl") and "models/props/cs_assault/money.mdl" or "models/props_lab/box01a.mdl"
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(CONTINUOUS_USE)

    if self:GetAmount() <= 0 then
        self:SetAmount(10000)
    end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetMass(5)
    end

    self.InvestigatingOfficers = {}
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if self.Collected then return end

    local amount = self:GetAmount()
    if amount <= 0 then
        self:Remove()
        return
    end

    -- If activator is police and this is death evidence: require 3-second investigation channel
    if activator:IsPolice() and self:GetNWBool("GRID_IsDeathEvidence", false) then
        local now = CurTime()
        local record = self.InvestigatingOfficers[activator]
        if not record or (now - record.lastTick > 0.4) then
            -- Started or restarted holding E
            self.InvestigatingOfficers[activator] = {
                startTime = now,
                lastTick = now
            }
            net.Start("GRID_EvidenceInvestigate")
            net.WriteEntity(self)
            net.WriteFloat(3.0)
            net.Send(activator)
            return
        end

        record.lastTick = now
        local elapsed = now - record.startTime
        if elapsed >= 3.0 then
            -- Investigation completed!
            self.Collected = true
            self.InvestigatingOfficers = {}

            activator:AddMoney(amount)
            activator:AddMoney(150) -- Department forensic impound bounty
            if activator.AddXP then activator:AddXP(75, "Forensic Investigation") end

            local victimName = self:GetNWString("GRID_VictimNick", "Victim")
            local killer = self.KillerEntity

            if IsValid(killer) and killer:IsPlayer() and killer ~= activator then
                local killerNick = killer:Nick()
                killer:AddBuff("wanted", 300, {
                    reason = "Homicide of " .. victimName,
                    officer = "Forensics (" .. activator:Nick() .. ")"
                })

                for _, p in ipairs(player.GetAll()) do
                    if p:IsPolice() then
                        GRID.Notify(p, string.format("[LSPD FORENSICS] Officer %s analyzed crime scene evidence! %s is now WANTED for the homicide of %s!", activator:Nick(), killerNick, victimName), NOTIFY_HINT, 10)
                        p:EmitSound("ambient/alarms/warningbell1.wav", 65, 110)
                    end
                end
            else
                GRID.Notify(activator, string.format("[LSPD FORENSICS] Evidence processed for %s. No living suspect identified. Cash ($%s + $150 bounty) impounded.", victimName, string.Comma(amount)), NOTIFY_GENERIC, 8)
            end

            activator:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 120)

            -- Cancel progress bar on client
            net.Start("GRID_EvidenceInvestigate")
            net.WriteEntity(NULL)
            net.WriteFloat(0)
            net.Send(activator)

            self:Remove()
        end
        return
    end

    -- Regular civilian / gangster instant pickup
    self.Collected = true
    activator:AddMoney(amount)
    GRID.Notify(activator, "Picked up $" .. string.Comma(amount) .. "!", NOTIFY_GENERIC)
    activator:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 120)

    self:Remove()
end
