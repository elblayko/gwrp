--[[
    entities/weapons/weapon_gwrp_wiretool/shared.lua
    GWRP Copper Wiring Tool SWEP
    Author: Toxic
--]]

SWEP.PrintName = "Copper Wiring Tool"
SWEP.Author = "Toxic"
SWEP.Instructions = "Left Click: Connect Printer <-> Switch\nRight Click: Disconnect / Unplug entity\nReload: Clear selection"
SWEP.Category = "GangWars RP"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Weight = 2
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false

SWEP.Slot = 0
SWEP.SlotPos = 3
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_toolgun.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.UseHands = true

function SWEP:Initialize()
    self:SetHoldType("pistol")
    self.SelectedEntity = nil
end

local function IsValidNetworkTarget(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    if class == "gwrp_network_switch" then return true end
    if class == "gwrp_printer_bronze" or class == "gwrp_printer_silver" or class == "gwrp_printer_diamond" or ent.PrintAmount ~= nil then
        return true
    end
    if class == "gwrp_computer" or ent.IsComputer then
        return true
    end
    return false
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.35)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity

    if not tr.Hit or not IsValidNetworkTarget(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > (260 * 260) then
        if CLIENT and IsFirstTimePredicted() then
            ply:EmitSound("common/warning.wav", 55, 120)
        end
        return
    end

    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    ply:SetAnimation(PLAYER_ATTACK1)

    -- Step 1: Nothing selected yet -> Select first entity
    if not IsValid(self.SelectedEntity) then
        self.SelectedEntity = ent
        if SERVER then
            self:SetNWEntity("GWRP_WireSrc", ent)
            ply:EmitSound("buttons/button14.wav", 65, 110)
            local label = (ent:GetClass() == "gwrp_network_switch") and "Network Switch" or (ent.PrintName or "Printer")
            GWRP.Notify(ply, "Selected " .. label .. ". Now click the second device to link.", NOTIFY_GENERIC)
        end
        return
    end

    -- Step 2: Target already selected -> Validate and connect
    local ent1 = self.SelectedEntity
    local ent2 = ent

    if ent1 == ent2 then
        if SERVER then
            GWRP.Notify(ply, "Cannot wire an entity to itself!", NOTIFY_ERROR)
            ply:EmitSound("buttons/button10.wav", 65, 100)
        end
        return
    end

    local isSwitch1 = (ent1:GetClass() == "gwrp_network_switch")
    local isSwitch2 = (ent2:GetClass() == "gwrp_network_switch")

    if (isSwitch1 and isSwitch2) or (not isSwitch1 and not isSwitch2) then
        if SERVER then
            GWRP.Notify(ply, "You must connect a network device (Printer or Computer) to a Network Switch!", NOTIFY_ERROR)
            ply:EmitSound("buttons/button10.wav", 65, 100)
        end
        return
    end

    local sw = isSwitch1 and ent1 or ent2
    local pr = isSwitch1 and ent2 or ent1

    local maxDist = GWRP.Config.MaxCableLength or 550
    if sw:GetPos():DistToSqr(pr:GetPos()) > (maxDist * maxDist) then
        if SERVER then
            GWRP.Notify(ply, "Distance is too far for copper cable (Max " .. maxDist .. " units)!", NOTIFY_ERROR)
            ply:EmitSound("buttons/button10.wav", 65, 100)
        end
        return
    end

    if SERVER then
        local port = sw:GetAvailablePort()
        if not port then
            GWRP.Notify(ply, "Switch is at maximum capacity (3/3 ports occupied)!", NOTIFY_ERROR)
            ply:EmitSound("buttons/button10.wav", 65, 100)
            self.SelectedEntity = nil
            self:SetNWEntity("GWRP_WireSrc", NULL)
            return
        end

        -- Create physical copper rope constraint
        local length = math.max(10, sw:GetPos():Distance(pr:GetPos()))
        local rope = constraint.Rope(
            sw, pr,
            0, 0,
            Vector(0, 0, 5), Vector(0, 0, 10),
            length, 25, 0, 1.6,
            "cable/cable2", false,
            Color(205, 127, 50) -- metallic copper
        )

        local connectFunc = sw.ConnectDevice or sw.ConnectPrinter
        local success, assignedOrErr, assignedIP = connectFunc(sw, pr, rope)
        if success then
            sw:EmitSound("ambient/energy/zap1.wav", 70, 115)
            pr:EmitSound("buttons/button9.wav", 70, 100)
            local ipInfo = assignedIP and (" (IP: " .. assignedIP .. ")") or ""
            local effInfo = (pr.PrintAmount ~= nil or string.find(pr:GetClass(), "printer")) and string.format(" [%d%% eff]", pr.GetEfficiency and pr:GetEfficiency() or 60) or ""
            GWRP.Notify(ply, string.format("Linked %s to Switch on Port %d%s%s!", pr.PrintName or "Device", assignedOrErr, effInfo, ipInfo), NOTIFY_GENERIC)
        else
            if IsValid(rope) then rope:Remove() end
            GWRP.Notify(ply, assignedOrErr or "Failed to connect", NOTIFY_ERROR)
        end

        self.SelectedEntity = nil
        self:SetNWEntity("GWRP_WireSrc", NULL)
    else
        self.SelectedEntity = nil
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.35)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity

    if not tr.Hit or not IsValidNetworkTarget(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > (260 * 260) then
        return
    end

    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    ply:SetAnimation(PLAYER_ATTACK1)

    if SERVER then
        if ent:GetClass() == "gwrp_network_switch" then
            ent:DisconnectAll()
            ent:EmitSound("physics/metal/metal_box_impact_bullet1.wav", 65, 100)
            GWRP.Notify(ply, "Disconnected all copper cables from switch.", NOTIFY_GENERIC)
        else
            if ent.DisconnectFromSwitch then
                ent:DisconnectFromSwitch()
            end
            ent:EmitSound("physics/metal/metal_box_impact_bullet1.wav", 65, 100)
            GWRP.Notify(ply, string.format("Unplugged %s from network switch.", ent.PrintName or "device"), NOTIFY_GENERIC)
        end

        self.SelectedEntity = nil
        self:SetNWEntity("GWRP_WireSrc", NULL)
    end
end

function SWEP:Reload()
    if CurTime() < (self.NextReload or 0) then return end
    self.NextReload = CurTime() + 0.5

    if IsValid(self.SelectedEntity) or IsValid(self:GetNWEntity("GWRP_WireSrc")) then
        self.SelectedEntity = nil
        if SERVER then
            self:SetNWEntity("GWRP_WireSrc", NULL)
            self:GetOwner():EmitSound("buttons/button16.wav", 60, 100)
            GWRP.Notify(self:GetOwner(), "Cable selection canceled.", NOTIFY_HINT)
        end
    end
end

function SWEP:Holster()
    self.SelectedEntity = nil
    if SERVER then
        self:SetNWEntity("GWRP_WireSrc", NULL)
    end
    return true
end

-- Client HUD crosshair target inspection
if CLIENT then
    function SWEP:DrawHUD()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local tr = ply:GetEyeTrace()
        local ent = tr.Entity
        local srcEnt = self:GetNWEntity("GWRP_WireSrc")

        local scrW, scrH = ScrW(), ScrH()
        local cx, cy = scrW / 2, scrH / 2

        -- If an entity is currently selected, draw indicator line/beam
        if IsValid(srcEnt) then
            local srcPos = srcEnt:GetPos() + Vector(0, 0, 10)
            local s2d = srcPos:ToScreen()
            if s2d.visible then
                surface.SetDrawColor(205, 127, 50, 200)
                surface.DrawLine(s2d.x, s2d.y, cx, cy)
                draw.RoundedBox(3, s2d.x - 4, s2d.y - 4, 8, 8, Color(245, 158, 11))
            end

            draw.SimpleText("SOURCE SELECTED: " .. (srcEnt.PrintName or "Device") .. " (Aim at target & Left-Click)", "GWRP_FontSmall", cx, cy + 30, Color(251, 191, 36), TEXT_ALIGN_CENTER)
            draw.SimpleText("[Reload] Cancel Selection", "GWRP_FontSmall", cx, cy + 46, GWRP.Colors.Muted, TEXT_ALIGN_CENTER)
        end
    end
end
