--[[
    entities/weapons/weapon_grid_wiretool/shared.lua
    GridRP Copper Wiring Tool SWEP
    Author: Juicebox
--]]

AddCSLuaFile()

SWEP.PrintName = "Network Wiring Tool"
SWEP.Author = "Juicebox"
SWEP.Instructions =
"Left Click: Connect Device <-> Switch (Copper) or Switch <-> Switch (SFP Fiber)\nRight Click: Disconnect / Unplug entity\nReload: Clear selection"
SWEP.Category = "GridRP"

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

SWEP.Slot = 1
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

local function IsSwitch(ent)
    if not IsValid(ent) then return false end
    if ent.IsNetworkSwitch then return true end
    local c = ent:GetClass()
    return c == "grid_network_switch" or string.StartWith(c, "grid_network_switch")
end

local function IsValidNetworkTarget(ent)
    if not IsValid(ent) then return false end
    if IsSwitch(ent) then return true end
    local class = ent:GetClass()
    if string.StartWith(class, "grid_printer_") or ent.PrintAmount ~= nil then
        return true
    end
    if class == "grid_computer" or ent.IsComputer then
        return true
    end
    if class == "grid_resource_machine" or class == "grid_wan_uplink" or ent.IsNetworkDevice or ent.IsWANUplink then
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
    if not SERVER then return end
    if not IsValid(self.SelectedEntity) then
        self.SelectedEntity = ent
        self:SetNWEntity("GRID_WireSrc", ent)
        ply:EmitSound("buttons/button14.wav", 65, 110)
        local label = IsSwitch(ent) and (ent.PrintName or "Network Switch") or (ent.PrintName or "Printer")
        GRID.Notify(ply, "Selected " .. label .. ". Now click the second device to link.", NOTIFY_GENERIC)
        return
    end
    if false and not IsValid(self.SelectedEntity) then
        self.SelectedEntity = ent
        if SERVER then
            self:SetNWEntity("GRID_WireSrc", ent)
            ply:EmitSound("buttons/button14.wav", 65, 110)
            local label = IsSwitch(ent) and (ent.PrintName or "Network Switch") or (ent.PrintName or "Printer")
            GRID.Notify(ply, "Selected " .. label .. ". Now click the second device to link.", NOTIFY_GENERIC)
        end
        return
    end

    -- Step 2: Target already selected -> Validate and connect
    local ent1 = self.SelectedEntity
    local ent2 = ent

    if ent1 == ent2 then
        if SERVER then
            GRID.Notify(ply, "Cannot wire an entity to itself!", NOTIFY_ERROR)
            ply:EmitSound("buttons/button10.wav", 65, 100)
        end
        return
    end

    local isSwitch1 = IsSwitch(ent1)
    local isSwitch2 = IsSwitch(ent2)

    -- Case A: Switch-to-Switch interconnection via SFP / Trunk Ports
    if isSwitch1 and isSwitch2 then
        local maxFiberDist = GRID.Config.MaxFiberCableLength or 800
        if ent1:GetPos():DistToSqr(ent2:GetPos()) > (maxFiberDist * maxFiberDist) then
            if SERVER then
                GRID.Notify(ply, "Distance is too far for SFP fiber optic cable (Max " .. maxFiberDist .. " units)!",
                    NOTIFY_ERROR)
                ply:EmitSound("buttons/button10.wav", 65, 100)
            end
            return
        end

        if SERVER then
            local port1 = ent1.GetAvailableSwitchPort and ent1:GetAvailableSwitchPort()
            local port2 = ent2.GetAvailableSwitchPort and ent2:GetAvailableSwitchPort()

            if not port1 then
                GRID.Notify(ply,
                    string.format("%s has no available SFP/Combo ports for uplink!", ent1.PrintName or "First switch"),
                    NOTIFY_ERROR)
                ply:EmitSound("buttons/button10.wav", 65, 100)
                self.SelectedEntity = nil
                self:SetNWEntity("GRID_WireSrc", NULL)
                return
            end

            if not port2 then
                GRID.Notify(ply,
                    string.format("%s has no available SFP/Combo ports for uplink!", ent2.PrintName or "Second switch"),
                    NOTIFY_ERROR)
                ply:EmitSound("buttons/button10.wav", 65, 100)
                self.SelectedEntity = nil
                self:SetNWEntity("GRID_WireSrc", NULL)
                return
            end

            -- Create physical fiber optic constraint
            local length = math.max(10, ent1:GetPos():Distance(ent2:GetPos()))
            local rope = constraint.Rope(
                ent1, ent2,
                0, 0,
                Vector(0, 0, 8), Vector(0, 0, 8),
                length, 25, 0, 1.4,
                "cable/cable2", false,
                Color(0, 220, 255) -- vibrant glowing cyan for fiber optic SFP
            )

            local success, assignedPort1, assignedPort2 = ent1:ConnectSwitch(ent2, rope, port1, port2)
            if success then
                ent1:EmitSound("ambient/energy/zap1.wav", 75, 130)
                ent2:EmitSound("buttons/button9.wav", 75, 120)
                GRID.Notify(ply,
                    string.format("Linked switches via SFP 10G Optical Uplink (Port %d <-> Port %d)!",
                        assignedPort1 or port1, assignedPort2 or port2), NOTIFY_GENERIC)
            else
                if IsValid(rope) then rope:Remove() end
                GRID.Notify(ply, assignedPort1 or "Failed to connect switches", NOTIFY_ERROR)
            end

            self.SelectedEntity = nil
            self:SetNWEntity("GRID_WireSrc", NULL)
        else
            self.SelectedEntity = nil
        end
        return
    end

    -- Case B: Neither entity is a switch
    if not isSwitch1 and not isSwitch2 then
        if SERVER then
            GRID.Notify(ply,
                "You must connect a network device (Printer, WAN, Computer) to a Network Switch, or link two switches together via SFP!",
                NOTIFY_ERROR)
            ply:EmitSound("buttons/button10.wav", 65, 100)
        end
        return
    end

    -- Case C: One entity is a switch and the other is a device (Printer, WAN Uplink, Computer, Synthesizer)
    local sw = isSwitch1 and ent1 or ent2
    local pr = isSwitch1 and ent2 or ent1

    local isWAN = (pr:GetClass() == "grid_wan_uplink" or pr.IsWANUplink)
    local maxDist = isWAN and (GRID.Config.MaxFiberCableLength or 800) or (GRID.Config.MaxCableLength or 550)
    if sw:GetPos():DistToSqr(pr:GetPos()) > (maxDist * maxDist) then
        if SERVER then
            local cableType = isWAN and "SFP cable" or "copper cable"
            GRID.Notify(ply, "Distance is too far for " .. cableType .. " (Max " .. maxDist .. " units)!", NOTIFY_ERROR)
            ply:EmitSound("buttons/button10.wav", 65, 100)
        end
        return
    end

    if SERVER then
        local port = sw.GetAvailablePort and sw:GetAvailablePort(pr) or
        (sw.GetAvailableCopperPort and sw:GetAvailableCopperPort())
        if not port then
            GRID.Notify(ply, string.format("All suitable ports on %s are occupied!", sw.PrintName or "Switch"),
                NOTIFY_ERROR)
            ply:EmitSound("buttons/button10.wav", 65, 100)
            self.SelectedEntity = nil
            self:SetNWEntity("GRID_WireSrc", NULL)
            return
        end

        local portDef = sw.GetPortDefinition and sw:GetPortDefinition(port)
        local is10G = (portDef and (portDef.type == "sfp" or (portDef.type == "combo" and isWAN)))
        local ropeCol = is10G and Color(0, 220, 255) or Color(205, 127, 50)
        local ropeWidth = is10G and 1.4 or 1.6

        -- Create physical rope constraint
        local length = math.max(10, sw:GetPos():Distance(pr:GetPos()))
        local rope = constraint.Rope(
            sw, pr,
            0, 0,
            Vector(0, 0, 5), Vector(0, 0, 10),
            length, 25, 0, ropeWidth,
            "cable/cable2", false,
            ropeCol
        )

        local connectFunc = sw.ConnectDevice or sw.ConnectPrinter
        local success, assignedOrErr, assignedIP, assignedIs10G = connectFunc(sw, pr, rope, port)
        if success then
            sw:EmitSound("ambient/energy/zap1.wav", 70, 115)
            pr:EmitSound("buttons/button9.wav", 70, 100)
            local ipInfo = assignedIP and (" (IP: " .. assignedIP .. ")") or ""
            local effInfo = (pr.PrintAmount ~= nil or string.find(pr:GetClass(), "printer") or pr:GetClass() == "grid_resource_machine") and
            string.format(" [%d%% eff]", pr.GetEfficiency and pr:GetEfficiency() or 60) or ""

            local assignedDef = sw.GetPortDefinition and sw:GetPortDefinition(assignedOrErr)
            local modeTag
            if assignedIs10G then
                modeTag = string.format(" [Port %d: 10G SFP]", assignedOrErr)
            elseif assignedDef and assignedDef.type == "combo" then
                modeTag = string.format(" [Port %d: 1G Copper SFP]", assignedOrErr)
            else
                modeTag = string.format(" [Copper Port %d]", assignedOrErr)
            end

            GRID.Notify(ply,
                string.format("Linked %s to %s%s%s%s!", pr.PrintName or "Device", sw.PrintName or "Switch", modeTag,
                    effInfo, ipInfo), NOTIFY_GENERIC)
        else
            if IsValid(rope) then rope:Remove() end
            GRID.Notify(ply, assignedOrErr or "Failed to connect", NOTIFY_ERROR)
        end

        self.SelectedEntity = nil
        self:SetNWEntity("GRID_WireSrc", NULL)
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
        if IsSwitch(ent) then
            ent:DisconnectAll()
            ent:EmitSound("physics/metal/metal_box_impact_bullet1.wav", 65, 100)
            GRID.Notify(ply, string.format("Disconnected all cables from %s.", ent.PrintName or "switch"), NOTIFY_GENERIC)
        else
            if ent.DisconnectFromSwitch then
                ent:DisconnectFromSwitch()
            end
            ent:EmitSound("physics/metal/metal_box_impact_bullet1.wav", 65, 100)
            GRID.Notify(ply, string.format("Unplugged %s from network switch.", ent.PrintName or "device"),
                NOTIFY_GENERIC)
        end

        self.SelectedEntity = nil
        self:SetNWEntity("GRID_WireSrc", NULL)
    end
end

function SWEP:Reload()
    if CurTime() < (self.NextReload or 0) then return end
    self.NextReload = CurTime() + 0.5

    if IsValid(self.SelectedEntity) or IsValid(self:GetNWEntity("GRID_WireSrc")) then
        self.SelectedEntity = nil
        if SERVER then
            self:SetNWEntity("GRID_WireSrc", NULL)
            self:GetOwner():EmitSound("buttons/button16.wav", 60, 100)
            GRID.Notify(self:GetOwner(), "Cable selection canceled.", NOTIFY_HINT)
        end
    end
end

function SWEP:Holster()
    self.SelectedEntity = nil
    if SERVER then
        self:SetNWEntity("GRID_WireSrc", NULL)
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
        local srcEnt = self:GetNWEntity("GRID_WireSrc")

        local scrW, scrH = ScrW(), ScrH()
        local cx, cy = scrW / 2, scrH / 2

        -- If an entity is currently selected, draw indicator line/beam
        if IsValid(srcEnt) then
            local isSrcSwitch = IsSwitch(srcEnt)
            local isTargetSwitch = IsValid(ent) and IsSwitch(ent)
            local isFiber = isSrcSwitch and isTargetSwitch

            local lineColor = isFiber and Color(0, 220, 255, 220) or Color(205, 127, 50, 200)
            local boxColor = isFiber and Color(56, 189, 248) or Color(245, 158, 11)

            local srcPos = srcEnt:GetPos() + Vector(0, 0, 10)
            local s2d = srcPos:ToScreen()
            if s2d.visible then
                surface.SetDrawColor(lineColor.r, lineColor.g, lineColor.b, lineColor.a)
                surface.DrawLine(s2d.x, s2d.y, cx, cy)
                draw.RoundedBox(3, s2d.x - 4, s2d.y - 4, 8, 8, boxColor)
            end

            local promptText = "SOURCE SELECTED: " .. (srcEnt.PrintName or "Device") .. " (Aim at target & Left-Click)"
            if isFiber then
                promptText = "SWITCH UPLINK: Aim at target switch & Left-Click to link via SFP 10G Optical Port"
            end

            draw.SimpleText(promptText, "GRID_FontSmall", cx, cy + 30,
                isFiber and Color(56, 189, 248) or Color(251, 191, 36), TEXT_ALIGN_CENTER)
            draw.SimpleText("[Reload] Cancel Selection", "GRID_FontSmall", cx, cy + 46, GRID.Colors.Muted,
                TEXT_ALIGN_CENTER)
        end
    end
end
