--[[
    entities/weapons/weapon_grid_taser/shared.lua
    GridRP Police Electro-Muscular Disruption Taser (3s Ragdoll on Wanted Suspects)
    Author: GRID Core Team
--]]

AddCSLuaFile()

SWEP.PrintName = "Tactical Taser X26"
SWEP.Author = "GRID Core Team"
SWEP.Instructions = "Primary Fire: Fire electrical probe dart (Ragdolls Wanted suspects for 3s)\nAuto-recharges battery every 6 seconds"
SWEP.Category = "GridRP"

SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.Base = "weapon_base"

SWEP.Slot = 1
SWEP.SlotPos = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_pistol.mdl"
SWEP.WorldModel = "models/weapons/w_pistol.mdl"
SWEP.UseHands = true

SWEP.Primary.ClipSize = 1
SWEP.Primary.DefaultClip = 1
SWEP.Primary.Automatic = false
SWEP.Primary.Delay = 6.0
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Delay = 0.5
SWEP.Secondary.Ammo = "none"

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "NextChargeTime")
end

function SWEP:Initialize()
    self:SetHoldType("pistol")
    self:SetNextChargeTime(0)
end

function SWEP:Deploy()
    self:SendWeaponAnim(ACT_VM_DRAW)
    return true
end

function SWEP:PrimaryAttack()
    if self:GetNextChargeTime() > CurTime() then
        self:EmitSound("weapons/pistol/pistol_empty.wav", 60, 100)
        return
    end

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    self:SetNextChargeTime(CurTime() + self.Primary.Delay)
    self:SetNextPrimaryFire(CurTime() + 0.5)
    self:SetNextSecondaryFire(CurTime() + 0.5)

    owner:SetAnimation(PLAYER_ATTACK1)
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    self:EmitSound("ambient/energy/zap1.wav", 75, 120)

    local startPos = owner:GetShootPos()
    local aimVec = owner:GetAimVector()
    local endPos = startPos + (aimVec * 950)

    local tr = util.TraceLine({
        start = startPos,
        endpos = endPos,
        filter = owner,
        mask = MASK_SHOT
    })

    -- Render electrical tracer dart
    local ed = EffectData()
    ed:SetStart(startPos - Vector(0, 0, 4))
    ed:SetOrigin(tr.HitPos)
    ed:SetScale(4000)
    util.Effect("ToolTracer", ed)

    local target = tr.Entity
    if IsValid(target) and target:IsPlayer() then
        if SERVER then
            if target:IsWanted() then
                -- Target is valid wanted suspect: immobilize with ragdoll
                target:EmitSound("ambient/energy/zap7.wav", 80, 100)
                local spark = EffectData()
                spark:SetOrigin(tr.HitPos)
                spark:SetMagnitude(2)
                spark:SetScale(2)
                util.Effect("Sparks", spark)

                GRID.Jail.TasePlayer(target)
                GRID.Notify(owner, string.format("Tased %s! Suspect immobilized for 3s.", target:Nick()), NOTIFY_HINT, 4)
            else
                -- Target is NOT wanted: fizzle & safety lock
                owner:EmitSound("buttons/button10.wav", 65, 100)
                local fizzle = EffectData()
                fizzle:SetOrigin(tr.HitPos)
                fizzle:SetMagnitude(1)
                fizzle:SetScale(1)
                util.Effect("ElectricSpark", fizzle)

                GRID.Notify(owner, "Safety Override: Target is not wanted! Non-wanted players cannot be tased.", NOTIFY_ERROR, 5)
            end
        end
    else
        local spark = EffectData()
        spark:SetOrigin(tr.HitPos)
        spark:SetNormal(tr.HitNormal)
        util.Effect("Sparks", spark)
    end
end

function SWEP:SecondaryAttack()
    -- Reserved
end

if CLIENT then
    function SWEP:DrawHUD()
        local scrW, scrH = ScrW(), ScrH()
        local nextCharge = self:GetNextChargeTime()
        local now = CurTime()
        local isCharged = nextCharge <= now

        local barW, barH = 140, 14
        local barX = (scrW - barW) / 2
        local barY = (scrH / 2) + 36

        -- Background
        draw.RoundedBox(4, barX, barY, barW, barH, Color(15, 23, 42, 220))
        surface.SetDrawColor(30, 41, 59, 200)
        surface.DrawOutlinedRect(barX, barY, barW, barH, 1)

        if isCharged then
            draw.RoundedBox(4, barX + 2, barY + 2, barW - 4, barH - 4, Color(52, 211, 153, 240))
            draw.SimpleText("TASER READY", "GRID_UI_Badge", scrW / 2, barY + barH + 4, Color(52, 211, 153), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        else
            local remaining = nextCharge - now
            local pct = math.Clamp(1 - (remaining / self.Primary.Delay), 0, 1)
            draw.RoundedBox(4, barX + 2, barY + 2, math.floor((barW - 4) * pct), barH - 4, Color(245, 158, 11, 240))
            draw.SimpleText(string.format("RECHARGING (%.1fs)", remaining), "GRID_UI_Badge", scrW / 2, barY + barH + 4, Color(245, 158, 11), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end
end

