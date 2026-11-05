--[[
    entities/weapons/weapon_grid_cyberphone/shared.lua
    GridRP CyberDeck Mobile Handset SWEP (Cyber Engineer Exclusive)
    Author: Toxic
--]]

SWEP.PrintName = "CyberDeck Mobile Phone"
SWEP.Author = "Toxic"
SWEP.Instructions = "Primary / Secondary Fire: Launch Mobile CyberDeck OS Terminal\nReload: Run quick wireless spectrum scan"
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

SWEP.Slot = 2
SWEP.SlotPos = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false

SWEP.ViewModel = "models/weapons/c_toolgun.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.UseHands = true

function SWEP:SetupDataTables()
    self:NetworkVar("String", 0, "AssociatedWANKey")
    self:NetworkVar("String", 1, "IPAddress")
    self:NetworkVar("Bool", 0, "IsConnected")
end

function SWEP:Initialize()
    self:SetHoldType("pistol")
    self:SetAssociatedWANKey("")
    self:SetIPAddress("10.84.1.25")
    self:SetIsConnected(false)
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.4)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    if SERVER then
        local isEngineer = (ply.GetJob and ply:GetJob() == "cyber_engineer")
        if not isEngineer then
            GRID.Notify(ply, "Terminal locked: Hardware restricted to Cyber Engineer security clearance.", NOTIFY_ERROR)
            ply:EmitSound("buttons/button10.wav", 60, 100)
            return
        end

        local ip = self:GetIPAddress() ~= "" and self:GetIPAddress() or "10.84.1.25"
        local isNet = self:GetIsConnected() or (self:GetAssociatedWANKey() ~= "")

        net.Start("GRID_OpenComputerOS")
            net.WriteEntity(self)
            net.WriteEntity(NULL)
            net.WriteString(ip)
            net.WriteBool(isNet)
        net.Send(ply)

        self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
        ply:EmitSound("buttons/button14.wav", 60, 120)
    end
end

function SWEP:SecondaryAttack()
    self:PrimaryAttack()
end

function SWEP:Reload()
    if CurTime() < (self.NextReload or 0) then return end
    self.NextReload = CurTime() + 1.5
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    if SERVER then
        local spectrum = GRID.Network and GRID.Network.GetActiveWANSpectrum and GRID.Network.GetActiveWANSpectrum() or {}
        local count = #spectrum
        if count == 0 then
            GRID.Notify(ply, "Wireless Scanner: No active WAN Satellite uplinks detected in map airspace.", NOTIFY_HINT)
        else
            GRID.Notify(ply, string.format("Wireless Scanner: Detected %d active WAN transmitter%s! Launch CyberDeck OS to scan.", count, count == 1 and "" or "s"), NOTIFY_GENERIC)
        end
        ply:EmitSound("ambient/energy/zap1.wav", 60, 130)
    end
end

if CLIENT then
    function SWEP:DrawHUD()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local scrW, scrH = ScrW(), ScrH()
        local cx, cy = scrW / 2, scrH / 2

        draw.SimpleText("CYBERDECK MOBILE PHONE", "GRID_FontSmall", cx, cy + 30, Color(56, 189, 248), TEXT_ALIGN_CENTER)
        draw.SimpleText("[Left-Click / Right-Click] Open CyberDeck OS Shell", "GRID_UI_Caption", cx, cy + 48, Color(248, 250, 252), TEXT_ALIGN_CENTER)
        draw.SimpleText("[Reload] Quick Spectrum Reconnaissance Scan", "GRID_UI_Caption", cx, cy + 64, GRID.Colors.Muted, TEXT_ALIGN_CENTER)
    end
end
