--[[
    entities/weapons/weapon_gwrp_lockpick/shared.lua
    GWRP Tactical Lockpick
    Author: Toxic
--]]

AddCSLuaFile()

SWEP.PrintName = "Lockpick"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary Fire: Hold on a locked door or lock to pick"
SWEP.Category = "GangWars RP"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Slot = 4
SWEP.SlotPos = 1
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false

SWEP.ViewModel = "models/weapons/c_crowbar.mdl"
SWEP.WorldModel = "models/weapons/w_crowbar.mdl"
SWEP.UseHands = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:SetupDataTables()
    self:NetworkVar("Bool", 0, "IsLockpicking")
    self:NetworkVar("Float", 0, "PickStartTime")
    self:NetworkVar("Float", 1, "PickEndTime")
    self:NetworkVar("Entity", 0, "PickTarget")
end

function SWEP:Initialize()
    self:SetHoldType("normal")
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.5)
    if self:GetIsLockpicking() then return end

    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > (95 * 95) then return end

    local isDoor = ent.isDoor and ent:isDoor() or (ent.IsDoor and ent:IsDoor())
    if not isDoor and ent:GetClass() ~= "prop_physics" then return end

    local pickDuration = math.random(8, 12)
    self:SetHoldType("pistol")
    self:SetIsLockpicking(true)
    self:SetPickTarget(ent)
    self:SetPickStartTime(CurTime())
    self:SetPickEndTime(CurTime() + pickDuration)

    if SERVER then
        GWRP.Notify(ply, "Lockpicking started... stay close!", NOTIFY_GENERIC, 3)
    end
end

function SWEP:SecondaryAttack()
    -- Lockpicks have no secondary fire
end

function SWEP:Holster()
    self:CancelLockpick()
    return true
end

function SWEP:OnDrop()
    self:CancelLockpick()
end

function SWEP:CancelLockpick()
    if self:GetIsLockpicking() then
        self:SetIsLockpicking(false)
        self:SetPickTarget(NULL)
        self:SetHoldType("normal")
    end
end

function SWEP:Think()
    if not self:GetIsLockpicking() then return end

    local ply = self:GetOwner()
    local target = self:GetPickTarget()

    if not IsValid(ply) or not ply:Alive() or not IsValid(target) or ply:GetActiveWeapon() ~= self then
        self:CancelLockpick()
        return
    end

    local tr = ply:GetEyeTrace()
    if tr.Entity ~= target or tr.HitPos:DistToSqr(ply:EyePos()) > (105 * 105) then
        self:CancelLockpick()
        if SERVER then
            GWRP.Notify(ply, "Lockpicking interrupted (moved away)!", NOTIFY_ERROR, 3)
        end
        return
    end

    -- Real-time clicking sound effect
    if (self.NextClickSound or 0) < CurTime() then
        self.NextClickSound = CurTime() + 0.65
        self:EmitSound("weapons/357/357_reload3.wav", 60, math.random(110, 130))
    end

    -- Completion Check
    if CurTime() >= self:GetPickEndTime() then
        if SERVER then
            local isDoor = target.isDoor and target:isDoor() or (target.IsDoor and target:IsDoor())
            if isDoor then
                target:Fire("unlock", "", 0)
                target:Fire("open", "", 0)
                target:EmitSound("doors/door_latch3.wav", 75, 100)
                GWRP.Notify(ply, "Lock picked successfully!", NOTIFY_HINT, 4)
            elseif target:GetClass() == "prop_physics" then
                local phys = target:GetPhysicsObject()
                if IsValid(phys) then
                    phys:EnableMotion(true)
                    phys:Wake()
                end
                GWRP.Notify(ply, "Prop unsealed!", NOTIFY_HINT, 4)
            end
        end
        self:CancelLockpick()
    end
end

if CLIENT then
    function SWEP:DrawHUD()
        if not self:GetIsLockpicking() then return end

        local st = self:GetPickStartTime()
        local et = self:GetPickEndTime()
        local progress = math.Clamp((CurTime() - st) / (et - st), 0, 1)

        local w, h = 320, 42
        local x = (ScrW() - w) / 2
        local y = ScrH() / 2 + 60

        -- Modern Progress Bar Frame
        draw.RoundedBox(6, x, y, w, h, Color(11, 15, 25, 240))
        surface.SetDrawColor(30, 41, 59, 220)
        surface.DrawOutlinedRect(x, y, w, h, 1)

        -- Progress Fill
        local fillW = (w - 8) * progress
        draw.RoundedBox(4, x + 4, y + 4, fillW, h - 8, Color(245, 158, 11, 230))

        -- Text Status
        local pct = math.floor(progress * 100)
        draw.SimpleText("Picking Lock: " .. pct .. "%", "GWRP_UI_Btn", ScrW() / 2, y + h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end
