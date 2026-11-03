--[[
    entities/weapons/weapon_gw_ram/shared.lua
    GWRP SWAT Tactical Battering Ram
    Author: Toxic
--]]

AddCSLuaFile()

SWEP.PrintName = "Tactical Battering Ram"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary Fire: Deliver heavy kinetic blows to breach locked doors\nSecondary Fire: Sound raid megaphone siren"
SWEP.Category = "GangWars RP"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Slot = 0
SWEP.SlotPos = 6
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_rpg.mdl"
SWEP.WorldModel = "models/weapons/w_rocket_launcher.mdl"
SWEP.UseHands = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Delay = 1.1
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Delay = 3.0
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
    self:SetHoldType("rpg")
    self.HitCounts = {}
    self.SirenSound = nil
end

function SWEP:StopSiren()
    if self.SirenSound then
        self.SirenSound:Stop()
        self.SirenSound = nil
    end
end

function SWEP:Holster()
    self:StopSiren()
    return true
end

function SWEP:OnDrop()
    self:StopSiren()
end

function SWEP:OnRemove()
    self:StopSiren()
end

function SWEP:OwnerChanged()
    self:StopSiren()
end

function SWEP:Think()
    if SERVER and self.SirenSound then
        local ply = self:GetOwner()
        if not IsValid(ply) or not ply:Alive() or ply:GetActiveWeapon() ~= self then
            self:StopSiren()
        end
    end
end

local function IsBreachable(ent)
    if not IsValid(ent) then return false end
    if ent.isDoor and ent:isDoor() then return true end
    if ent.IsDoor and ent:IsDoor() then return true end
    local class = ent:GetClass()
    if class == "prop_door_rotating" or class == "func_door" or class == "func_door_rotating" then
        return true
    end
    if class == "prop_physics" then
        return true
    end
    return false
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity

    if not IsValid(ent) or not IsBreachable(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > (110 * 110) then
        return
    end

    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    ply:SetAnimation(PLAYER_ATTACK1)

    if SERVER then
        local entIdx = ent:EntIndex()
        local hits = (self.HitCounts[entIdx] or 0) + 1
        self.HitCounts[entIdx] = hits

        -- Impact effects
        sound.Play("physics/metal/metal_box_impact_hard3.wav", tr.HitPos, 80, math.random(95, 105))
        util.ScreenShake(tr.HitPos, 4, 10, 0.4, 300)

        local ed = EffectData()
        ed:SetOrigin(tr.HitPos)
        ed:SetNormal(tr.HitNormal)
        ed:SetScale(1.5)
        util.Effect("MetalSpark", ed)

        local doorOwner = ent.GetDoorOwner and ent:GetDoorOwner()
        local ownerIsWanted = IsValid(doorOwner) and doorOwner.HasBuff and doorOwner:HasBuff("wanted")
        local reqHits = ownerIsWanted and 2 or 3

        if hits < reqHits then
            GW.Notify(ply, string.format("[RAM] Kinetic Impact %d/%d! Keep striking to breach!", hits, reqHits), NOTIFY_HINT, 2)
            if IsValid(doorOwner) then
                GW.Notify(doorOwner, "WARNING: Your front door is being hammered by SWAT!", NOTIFY_ERROR, 3)
            end
        else
            -- Door Breached!
            self.HitCounts[entIdx] = nil

            if ent.isDoor and ent:isDoor() or ent.IsDoor and ent:IsDoor() or string.find(ent:GetClass(), "door") then
                ent:Fire("unlock", "", 0)
                ent:Fire("open", "", 0)
                sound.Play("doors/door_metal_large_open1.wav", tr.HitPos, 85, 90)
                GW.Notify(ply, "[RAM BREACH] Door successfully smashed open!", NOTIFY_GENERIC, 4)
            elseif ent:GetClass() == "prop_physics" then
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    phys:EnableMotion(true)
                    phys:Wake()
                    phys:ApplyForceCenter(ply:GetAimVector() * 8000)
                end
                GW.Notify(ply, "[RAM BREACH] Fortified prop barricade smashed aside!", NOTIFY_GENERIC, 4)
            end

            -- Dust and explosion puff
            local puff = EffectData()
            puff:SetOrigin(tr.HitPos)
            puff:SetNormal(tr.HitNormal)
            puff:SetScale(2)
            util.Effect("ThumperDust", puff)
        end
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1.0)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    if SERVER then
        if self.SirenSound then
            self:StopSiren()
            GW.Notify(ply, "[MEGAPHONE] Raid siren deactivated.", NOTIFY_GENERIC, 3)
        else
            self.SirenSound = CreateSound(self, "ambient/alarms/siren.wav")
            if self.SirenSound then
                self.SirenSound:Play()
                self.SirenSound:ChangeVolume(0.85, 0)
                self.SirenSound:ChangePitch(110, 0)
            end
            GW.NotifyAll("[SWAT RAID WARNING] Tactical Breaching Unit is raiding an active structure!", NOTIFY_ERROR, 6)
        end
    end
end

if CLIENT then
    function SWEP:DrawHUD()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local cx, cy = ScrW() / 2, ScrH() / 2
        local tr = ply:GetEyeTrace()
        local ent = tr.Entity

        if IsValid(ent) and IsBreachable(ent) and tr.HitPos:DistToSqr(ply:EyePos()) < (110 * 110) then
            draw.SimpleText("[ LEFT CLICK: RAM DOOR | RIGHT CLICK: MEGAPHONE ]", "GW_UI_Caption", cx, cy + 35, Color(245, 158, 11), TEXT_ALIGN_CENTER)
        end
    end
end
