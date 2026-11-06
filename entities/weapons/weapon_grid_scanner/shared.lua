--[[
    entities/weapons/weapon_grid_scanner/shared.lua
    GridRP Police Acoustic & Thermal Contraband Scanner
    Author: Juicebox
--]]

AddCSLuaFile()

SWEP.PrintName = "Contraband Scanner"
SWEP.Author = "Juicebox"
SWEP.Instructions =
"Primary Fire: Ping Contraband Signal (Triangulate 1/3, 2/3, 3/3)\nSecondary Fire: Broadcast Police Raid Dispatch Waypoint (Requires 3/3 Samples)\nReload (R): Reset Triangulation Radar"
SWEP.Category = "GridRP"

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Slot = 2
SWEP.SlotPos = 5
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_toolgun.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.UseHands = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Delay = 0.8
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Delay = 2.0
SWEP.Secondary.Ammo = "none"

if SERVER then
    util.AddNetworkString("GRID_Scanner_AddSample")
    util.AddNetworkString("GRID_Scanner_Reset")
    util.AddNetworkString("GRID_Scanner_PoliceRaidAlert")
end

function SWEP:Initialize()
    self:SetHoldType("pistol")
    self.Samples = {}
    self.LastSampleTime = 0
    self.LockedTargetPos = nil
    self:SetNWInt("GRID_SignalBars", 0)
end

local function IsPrinter(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    if string.StartWith(class, "grid_printer_") or ent.PrintAmount ~= nil then
        return true
    end
    return false
end

function SWEP:Think()
    if CLIENT then
        local ply = self:GetOwner()
        if not IsValid(ply) or ply ~= LocalPlayer() then return end

        local bars = self:GetNWInt("GRID_SignalBars", 0)
        if bars > 0 then
            local now = CurTime()
            local intervals = { 1.6, 1.25, 0.95, 0.65, 0.45 }
            local interval = intervals[bars] or 1.0

            if (self.NextClientChirp or 0) <= now then
                self.NextClientChirp = now + interval
                ply:EmitSound("npc/scanner/scanner_scan1.wav", 55, 115 + (bars * 8), 0.25)
            end
        end
        return
    end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:Alive() then return end

    local now = CurTime()
    if (self.NextSignalCheck or 0) > now then return end
    self.NextSignalCheck = now + 0.25

    local myPos = ply:EyePos()
    local myAim = ply:GetAimVector()
    local bestRaw = 0

    for _, ent in ipairs(ents.GetAll()) do
        if IsPrinter(ent) then
            local pPos = ent:GetPos() + Vector(0, 0, 10)
            local toEnt = (pPos - myPos)
            local dist = toEnt:Length()

            local baseRadius = 1350
            if ent.GetHasOverclock and ent:GetHasOverclock() then
                baseRadius = baseRadius * 1.5
            end
            if ent.GetHasUndervolt and ent:GetHasUndervolt() then
                baseRadius = baseRadius * 0.5
            end
            if ent.GetIsTuned and ent:GetIsTuned() then
                baseRadius = baseRadius * 0.8
            end
            if ent.GetLowEmissionUntil and ent:GetLowEmissionUntil() > now then
                baseRadius = baseRadius * 0.7 -- Sweet-spot stealth dampener (-30%)
            end
            if ent.GetThermalSpikeUntil and ent:GetThermalSpikeUntil() > now then
                baseRadius = baseRadius * 2.5 -- Whistle blowout thermal spike flare (2.5x radius)
            end

            if dist <= baseRadius then
                local dir = toEnt:GetNormalized()
                local dot = myAim:Dot(dir)

                -- Broad directional forward cone (~90 deg arc: dot > 0.3)
                if dot > 0.3 then
                    local proxRatio = 1 - (dist / baseRadius)
                    local dirWeight = math.Clamp((dot - 0.3) / 0.7, 0.4, 1.0)
                    local score = proxRatio * dirWeight

                    if score > bestRaw then
                        bestRaw = score
                    end
                end
            end
        end
    end

    local bestBars = 0
    if bestRaw > 0.05 then
        if bestRaw < 0.25 then
            bestBars = 1
        elseif bestRaw < 0.45 then
            bestBars = 2
        elseif bestRaw < 0.65 then
            bestBars = 3
        elseif bestRaw < 0.85 then
            bestBars = 4
        else
            bestBars = 5
        end
    end

    if self:GetNWInt("GRID_SignalBars", 0) ~= bestBars then
        self:SetNWInt("GRID_SignalBars", bestBars)
    end
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    ply:SetAnimation(PLAYER_ATTACK1)

    if SERVER then
        local now = CurTime()
        local myPos = ply:GetPos()

        -- Auto-expire samples after 60s of inactivity
        if self.LastSampleTime > 0 and (now - self.LastSampleTime) > 60 then
            self.Samples = {}
            self.LockedTargetPos = nil
            net.Start("GRID_Scanner_Reset")
            net.Send(ply)
        end

        -- Check printer signals in environment with hardware modifiers
        local bestPrinter = nil
        local bestScore = -1
        local detectedDist = 0
        local detectedType = "standard"

        for _, ent in ipairs(ents.GetAll()) do
            if IsPrinter(ent) then
                local baseRadius = 1200 -- ~23m baseline
                local isOc = ent.GetHasOverclock and ent:GetHasOverclock()
                local isUv = ent.GetHasUndervolt and ent:GetHasUndervolt()
                local isTuned = ent.GetIsTuned and ent:GetIsTuned()

                if isOc then
                    baseRadius = baseRadius * 1.5 -- +50% noise range (1800 units / ~35m)
                end
                if isUv then
                    baseRadius = baseRadius * 0.5 -- -50% noise range (600 units / ~12m stealth)
                end
                if isTuned then
                    baseRadius = baseRadius * 0.8 -- -20% thermal noise reduction
                end
                if ent.GetLowEmissionUntil and ent:GetLowEmissionUntil() > now then
                    baseRadius = baseRadius * 0.7 -- Sweet-spot stealth dampener (-30%)
                end
                if ent.GetThermalSpikeUntil and ent:GetThermalSpikeUntil() > now then
                    baseRadius = baseRadius * 2.5 -- Whistle blowout thermal spike flare (2.5x radius)
                end

                local dist = myPos:Distance(ent:GetPos())
                if dist <= baseRadius then
                    local strength = 1 - (dist / baseRadius)
                    if strength > bestScore then
                        bestScore = strength
                        bestPrinter = ent
                        detectedDist = dist
                        detectedType = isOc and "overclocked" or
                        (isUv and "undervolted" or (isTuned and "tuned" or "standard"))
                    end
                end
            end
        end

        -- Check minimum baseline distance from existing samples (~5m / 260 units)
        self.Samples = self.Samples or {}
        local minDist = 260
        for idx, s in ipairs(self.Samples) do
            local sep = myPos:Distance(s.pos)
            if sep < minDist then
                local metersAway = math.max(1, math.Round((minDist - sep) * 0.01905))
                ply:EmitSound("common/warning.wav", 60, 120)
                GRID.Notify(ply,
                    string.format(
                    "Baseline too narrow! Move at least ~%dm further away from Sample #%d to establish triangulation geometry.",
                        metersAway, idx), NOTIFY_ERROR, 5)
                return
            end
        end

        local sampleIndex = #self.Samples + 1

        -- Reset if already at max and starting a new cycle
        if sampleIndex > 3 then
            self.Samples = {}
            sampleIndex = 1
            self.LockedTargetPos = nil
            self.TargetPrinter = nil
        end

        local hasPrinter = IsValid(bestPrinter)
        local sampleRadius = hasPrinter and math.max(50, detectedDist + math.random(-6, 6)) or
        1200                                                                                        -- 1200 units (~23m sweep boundary)

        table.insert(self.Samples, {
            pos = myPos,
            radius = sampleRadius,
            hasPrinter = hasPrinter,
            time = now
        })
        self.LastSampleTime = now

        local isLocked = false
        local targetPos = Vector(0, 0, 0)
        local confidence = 0
        local noContraband = false

        if sampleIndex == 3 then
            -- On 3rd sample, evaluate whether any valid contraband signature was tracked
            local foundTarget = nil
            if IsValid(bestPrinter) then
                foundTarget = bestPrinter
            elseif IsValid(self.TargetPrinter) then
                foundTarget = self.TargetPrinter
            end

            if IsValid(foundTarget) then
                isLocked = true
                targetPos = foundTarget:GetPos() + Vector(math.random(-15, 15), math.random(-15, 15), 0)
                self.LockedTargetPos = targetPos
                confidence = math.random(92, 98)

                ply:EmitSound("npc/scanner/combat_scan1.wav", 75, 110)
                ply:EmitSound("buttons/bell1.wav", 70, 115)

                local distMeters = math.Round(myPos:Distance(targetPos) * 0.01905)
                local modNote = detectedType == "overclocked" and " [HIGH EM FREQUENCY DETECTED]" or
                (detectedType == "undervolted" and " [LOW THERMAL FOOTPRINT]" or "")
                GRID.Notify(ply,
                    string.format(
                    "[TRILATERATION COMPLETE] Target pinpointed ~%dm away (%d%% confidence)!%s Press RIGHT-CLICK to dispatch raid waypoint.",
                        distMeters, confidence, modNote), NOTIFY_GENERIC, 8)
            else
                noContraband = true
                self.LockedTargetPos = nil
                ply:EmitSound("buttons/button10.wav", 65, 90)
                GRID.Notify(ply,
                    "[TRILATERATION COMPLETE] Sector clear. Zero contraband printer signatures detected across all 3 baseline pings.",
                    NOTIFY_HINT, 6)
            end
        else
            if hasPrinter then
                self.TargetPrinter = bestPrinter
                ply:EmitSound("npc/scanner/scanner_scan4.wav", 70, 105 + (sampleIndex * 15))
                local distMeters = math.Round(sampleRadius * 0.01905)
                GRID.Notify(ply,
                    string.format(
                    "[SAMPLE %d/3 RECORDED] Signal detected (~%dm away). Move to next vantage point to cross-reference bearings.",
                        sampleIndex, distMeters), NOTIFY_GENERIC, 5)
            else
                ply:EmitSound("npc/scanner/scanner_scan4.wav", 65, 95 + (sampleIndex * 10))
                GRID.Notify(ply,
                    string.format(
                    "[SAMPLE %d/3 RECORDED] Sector sweep logged. Move to next vantage point to establish triangulation geometry.",
                        sampleIndex), NOTIFY_GENERIC, 5)
            end
        end

        net.Start("GRID_Scanner_AddSample")
        net.WriteUInt(sampleIndex, 4)
        net.WriteVector(myPos)
        net.WriteFloat(sampleRadius)
        net.WriteBool(isLocked)
        net.WriteVector(targetPos)
        net.WriteFloat(confidence)
        net.WriteString(detectedType)
        net.WriteBool(noContraband)
        net.Send(ply)
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + self.Secondary.Delay)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    if SERVER then
        if not self.LockedTargetPos or not self.Samples or #self.Samples < 3 then
            ply:EmitSound("buttons/button10.wav", 60, 90)
            GRID.Notify(ply, "You must complete a 3-point triangulation (3/3 samples) before dispatching a raid alert!",
                NOTIFY_HINT, 5)
            return
        end

        -- Broadcast Tactical Raid Dispatch to all on-duty police officers
        local targetPos = self.LockedTargetPos
        local distMeters = math.Round(ply:GetPos():Distance(targetPos) * 0.01905)

        ply:EmitSound("npc/combine_soldier/gear1.wav", 75, 100)

        for _, officer in ipairs(player.GetAll()) do
            if officer:IsPolice() then
                GRID.Notify(officer,
                    string.format(
                    "[DISPATCH ALERT] Officer %s deployed a Raid Waypoint on suspected contraband (~%dm)! Beacon active for 30s.",
                        ply:Nick(), distMeters), NOTIFY_GENERIC, 10)
                officer:EmitSound("ambient/alarms/klaxon1.wav", 65, 120)
            end
        end

        net.Start("GRID_Scanner_PoliceRaidAlert")
        net.WriteEntity(ply)
        net.WriteVector(targetPos)
        net.WriteFloat(30)
        net.Broadcast()

        GRID.Notify(ply, "Raid dispatch waypoint broadcasted to all police units!", NOTIFY_GENERIC, 5)
    end
end

function SWEP:Reload()
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    if SERVER then
        if self.Samples and #self.Samples > 0 then
            self.Samples = {}
            self.LockedTargetPos = nil
            self.LastSampleTime = 0

            ply:EmitSound("weapons/smg1/switch_burst.wav", 60, 110)
            GRID.Notify(ply, "Contraband triangulation radar reset.", NOTIFY_HINT, 3)

            net.Start("GRID_Scanner_Reset")
            net.Send(ply)
        end
    end
end

if CLIENT then
    local clientSamples = {}
    local clientLockedPos = nil
    local clientConfidence = 0
    local clientNoTarget = false

    net.Receive("GRID_Scanner_AddSample", function()
        local idx = net.ReadUInt(4)
        local pos = net.ReadVector()
        local radius = net.ReadFloat()
        local isLocked = net.ReadBool()
        local targetPos = net.ReadVector()
        local conf = net.ReadFloat()
        local pType = net.ReadString()
        local noTarget = net.ReadBool()

        if idx == 1 then
            clientSamples = {}
            clientLockedPos = nil
            clientNoTarget = false
        end

        clientSamples[idx] = {
            pos = pos,
            radius = radius,
            type = pType,
            hasSignal = (pType ~= "none"),
            time = CurTime()
        }

        if isLocked then
            clientLockedPos = targetPos
            clientConfidence = conf
            clientNoTarget = false
        elseif noTarget then
            clientLockedPos = nil
            clientConfidence = 0
            clientNoTarget = true
        end
    end)

    net.Receive("GRID_Scanner_Reset", function()
        clientSamples = {}
        clientLockedPos = nil
        clientConfidence = 0
        clientNoTarget = false
    end)

    net.Receive("GRID_Scanner_PoliceRaidAlert", function()
        local officer = net.ReadEntity()
        local pos = net.ReadVector()
        local duration = net.ReadFloat()

        GRID.ActivePoliceRaid = {
            officer = officer,
            pos = pos,
            expire = CurTime() + duration
        }
    end)

    local sampleColors = {
        [1] = Color(56, 189, 248, 200), -- Cyan
        [2] = Color(251, 191, 36, 200), -- Amber
        [3] = Color(52, 211, 153, 200)  -- Emerald
    }

    local function Draw3DCircle(origin, radius, col, segments)
        segments = segments or 48
        local step = (math.pi * 2) / segments
        local prevPos = nil
        for i = 0, segments do
            local angle = i * step
            local x = origin.x + math.cos(angle) * radius
            local y = origin.y + math.sin(angle) * radius
            local curPos = Vector(x, y, origin.z + 3)
            if prevPos then
                render.DrawLine(prevPos, curPos, col, true)
            end
            prevPos = curPos
        end
    end

    -- 3D In-World Holographic Render Hook
    hook.Add("PostDrawTranslucentRenderables", "GRID_ContrabandScanner_3DWorld", function(depth, skybox)
        if skybox then return end

        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local wep = ply:GetActiveWeapon()
        local holdingScanner = IsValid(wep) and wep:GetClass() == "weapon_grid_scanner"

        -- Render scanner triangulation rings if holding scanner
        if holdingScanner and #clientSamples > 0 then
            render.SetColorMaterial()

            for idx, s in pairs(clientSamples) do
                local col = s.hasSignal and (sampleColors[idx] or Color(255, 255, 255, 180)) or Color(148, 163, 184, 130)
                Draw3DCircle(s.pos, s.radius, col, 56)

                -- Center beacon pillar at sample point
                render.DrawLine(s.pos, s.pos + Vector(0, 0, 45), col, false)
            end

            -- Render locked target beacon
            if clientLockedPos and not clientNoTarget then
                local pulse = (math.sin(CurTime() * 5) + 1) * 0.5
                local targetCol = Color(239, 68, 68, 180 + math.floor(pulse * 75))

                -- Vertical holographic pillar
                render.DrawLine(clientLockedPos, clientLockedPos + Vector(0, 0, 200), targetCol, false)
                Draw3DCircle(clientLockedPos, 45 + (pulse * 15), targetCol, 32)
                Draw3DCircle(clientLockedPos, 20, Color(255, 255, 255, 220), 16)
            end
        end

        -- Render Police Raid Waypoint for all police officers
        if GRID.ActivePoliceRaid and CurTime() < GRID.ActivePoliceRaid.expire and ply:IsPolice() then
            render.SetColorMaterial()
            local raidPos = GRID.ActivePoliceRaid.pos
            local pulse = (math.sin(CurTime() * 6) + 1) * 0.5
            local raidCol = Color(239, 68, 68, 200 + math.floor(pulse * 55))

            render.DrawLine(raidPos, raidPos + Vector(0, 0, 350), raidCol, false)
            Draw3DCircle(raidPos, 80 + (pulse * 30), raidCol, 40)
            Draw3DCircle(raidPos, 35, Color(251, 191, 36, 240), 24)
        end
    end)

    -- Tactical Scanner 2D HUD (GridRP UI Design System)
    function SWEP:DrawHUD()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local count = #clientSamples
        local bars = self:GetNWInt("GRID_SignalBars", 0)
        local w = 560
        local h = 186
        local x = (ScrW() - w) / 2
        local y = ScrH() - h - 35

        -- Outer Panel Container (Obsidian Slate-950 with 1px slate-800 border)
        draw.RoundedBox(8, x, y, w, h, Color(11, 15, 25, 245))
        surface.SetDrawColor(30, 41, 59, 230)
        surface.DrawOutlinedRect(x, y, w, h, 1)

        -- Top Accent Line
        local topAccent = (count >= 3 and not clientNoTarget) and Color(52, 211, 153, 240)
            or ((count >= 3 and clientNoTarget) and Color(71, 85, 105, 180)
                or ((count > 0) and Color(6, 182, 212, 240) or Color(56, 189, 248, 120)))
        draw.RoundedBoxEx(8, x, y, w, 3, topAccent, true, true, false, false)

        -- Row 1: Header (y + 12)
        -- Left: "POLICE" Category Badge + Title
        draw.RoundedBox(4, x + 16, y + 12, 52, 20, Color(6, 182, 212, 35))
        surface.SetDrawColor(6, 182, 212, 120)
        surface.DrawOutlinedRect(x + 16, y + 12, 52, 20, 1)
        draw.SimpleText("POLICE", "GRID_UI_Badge", x + 42, y + 22, Color(34, 211, 238), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)

        draw.SimpleText("Acoustic Trilateration Radar", "GRID_UI_Sub", x + 76, y + 22, Color(248, 250, 252),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Right: Status Pill Badge
        local statusText = "STANDBY - PING TO SCAN"
        local statusBg = Color(30, 41, 59, 180)
        local statusBorder = Color(71, 85, 105, 120)
        local statusTextCol = Color(148, 163, 184)

        if count == 1 then
            statusText = "SAMPLE 1/3 (MOVE ~5M)"
            statusBg = Color(6, 182, 212, 35)
            statusBorder = Color(6, 182, 212, 140)
            statusTextCol = Color(34, 211, 238)
        elseif count == 2 then
            statusText = "SAMPLE 2/3 (MOVE ~5M)"
            statusBg = Color(245, 158, 11, 35)
            statusBorder = Color(245, 158, 11, 140)
            statusTextCol = Color(251, 191, 36)
        elseif count >= 3 then
            if clientNoTarget then
                statusText = "SECTOR CLEAR (0 SIGNALS)"
                statusBg = Color(30, 41, 59, 180)
                statusBorder = Color(71, 85, 105, 140)
                statusTextCol = Color(148, 163, 184)
            else
                statusText = string.format("PINPOINTED (%d%% LOCK)", math.floor(clientConfidence or 95))
                statusBg = Color(16, 185, 129, 35)
                statusBorder = Color(16, 185, 129, 140)
                statusTextCol = Color(52, 211, 153)
            end
        end

        local statusW = 200
        local statusX = x + w - 16 - statusW
        draw.RoundedBox(10, statusX, y + 12, statusW, 22, statusBg)
        surface.SetDrawColor(statusBorder.r, statusBorder.g, statusBorder.b, statusBorder.a)
        surface.DrawOutlinedRect(statusX, y + 12, statusW, 22, 1)
        draw.SimpleText(statusText, "GRID_UI_Badge", statusX + (statusW / 2), y + 23, statusTextCol, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)

        -- Row 2: Directional Signal Strength Strip (y + 42, h = 32)
        local rssiY = y + 42
        local rssiW = w - 32
        local rssiH = 32
        draw.RoundedBox(6, x + 16, rssiY, rssiW, rssiH, Color(15, 23, 42, 190))
        surface.SetDrawColor(30, 41, 59, 140)
        surface.DrawOutlinedRect(x + 16, rssiY, rssiW, rssiH, 1)

        -- RSSI Label
        draw.SimpleText("FORWARD RSSI", "GRID_UI_Badge", x + 28, rssiY + 16, Color(148, 163, 184), TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        -- 5 Segmented Bars
        local barStartX = x + 120
        local barW, barH = 20, 10
        local barGap = 4
        local barColors = {
            [1] = Color(34, 211, 238), -- Cyan
            [2] = Color(34, 211, 238), -- Cyan
            [3] = Color(251, 191, 36), -- Amber
            [4] = Color(251, 191, 36), -- Amber
            [5] = Color(52, 211, 153), -- Emerald
        }

        for i = 1, 5 do
            local bx = barStartX + (i - 1) * (barW + barGap)
            local by = rssiY + 11
            local isActive = (bars >= i)
            local fillCol = isActive and barColors[i] or Color(30, 41, 59, 140)

            draw.RoundedBox(2, bx, by, barW, barH, fillCol)
            if isActive then
                surface.SetDrawColor(fillCol.r, fillCol.g, fillCol.b, 200)
                surface.DrawOutlinedRect(bx, by, barW, barH, 1)
            end
        end

        -- RSSI Bearing Description
        local bearingDesc = "No Signal Ahead"
        local bearingCol = Color(100, 116, 139)
        if bars == 1 then
            bearingDesc = "Weak Bearing (1/5)"
            bearingCol = Color(34, 211, 238)
        elseif bars == 2 then
            bearingDesc = "Moderate Forward Signal (2/5)"
            bearingCol = Color(34, 211, 238)
        elseif bars == 3 then
            bearingDesc = "Approaching Signature (3/5)"
            bearingCol = Color(251, 191, 36)
        elseif bars == 4 then
            bearingDesc = "Strong Forward Bearing (4/5)"
            bearingCol = Color(251, 191, 36)
        elseif bars >= 5 then
            bearingDesc = "Peak Bearing (~12m Proximity)"
            bearingCol = Color(52, 211, 153)
        end
        draw.SimpleText(bearingDesc, "GRID_UI_Caption", x + w - 28, rssiY + 16, bearingCol, TEXT_ALIGN_RIGHT,
            TEXT_ALIGN_CENTER)

        -- Row 3: 3 Sample Cards (y + 82, h = 50)
        local cardW = (w - 32 - 16) / 3
        local cardH = 50
        local cardY = y + 82

        for i = 1, 3 do
            local cardX = x + 16 + (i - 1) * (cardW + 8)
            local hasSample = (count >= i)
            local sData = clientSamples[i]

            -- Card Frame
            local cardBg = hasSample and Color(17, 24, 39, 230) or Color(15, 23, 42, 160)
            draw.RoundedBox(6, cardX, cardY, cardW, cardH, cardBg)

            local borderCol = hasSample and (sampleColors[i] or Color(6, 182, 212)) or Color(30, 41, 59, 160)
            surface.SetDrawColor(borderCol.r, borderCol.g, borderCol.b, hasSample and 180 or 80)
            surface.DrawOutlinedRect(cardX, cardY, cardW, cardH, 1)

            -- Top mini accent on active cards
            if hasSample then
                draw.RoundedBoxEx(6, cardX, cardY, cardW, 2, borderCol, true, true, false, false)
            end

            -- Card Content
            local stepLabel = string.format("SAMPLE 0%d", i)
            local stepCol = hasSample and borderCol or Color(100, 116, 139)
            draw.SimpleText(stepLabel, "GRID_UI_Badge", cardX + 12, cardY + 13, stepCol, TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)

            if hasSample and sData then
                if sData.hasSignal then
                    local distMeters = math.Round(sData.radius * 0.01905)
                    draw.SimpleText("~" .. distMeters .. "m Signal", "GRID_UI_Sub", cardX + 12, cardY + 34,
                        Color(248, 250, 252), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                else
                    draw.SimpleText(clientNoTarget and "No Signal" or "Sector Sweep", "GRID_UI_Caption", cardX + 12,
                        cardY + 34, Color(148, 163, 184), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            else
                draw.SimpleText("Awaiting Ping", "GRID_UI_Caption", cardX + 12, cardY + 34, Color(100, 116, 139),
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end

        -- Row 4: Action Guidance Bar (y + 140, h = 30)
        local barY = y + 140
        draw.RoundedBox(6, x + 16, barY, w - 32, 30, Color(17, 24, 39, 190))
        surface.SetDrawColor(30, 41, 59, 140)
        surface.DrawOutlinedRect(x + 16, barY, w - 32, 30, 1)

        if count >= 3 then
            if clientNoTarget then
                draw.SimpleText("[LMB] NEW SCAN", "GRID_UI_Badge", x + 30, barY + 15, Color(34, 211, 238),
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("NO CONTRABAND DETECTED IN SECTOR", "GRID_UI_Badge", x + (w / 2), barY + 15,
                    Color(148, 163, 184), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText("[R] RESET", "GRID_UI_Badge", x + w - 30, barY + 15, Color(239, 68, 68), TEXT_ALIGN_RIGHT,
                    TEXT_ALIGN_CENTER)
            else
                draw.SimpleText("[LMB] PING SWEEP", "GRID_UI_Badge", x + 30, barY + 15, Color(148, 163, 184),
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("[RMB] DISPATCH RAID WAYPOINT", "GRID_UI_Badge", x + (w / 2), barY + 15,
                    Color(52, 211, 153), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText("[R] RESET", "GRID_UI_Badge", x + w - 30, barY + 15, Color(239, 68, 68), TEXT_ALIGN_RIGHT,
                    TEXT_ALIGN_CENTER)
            end
        else
            draw.SimpleText("[LMB] PING SAMPLE (MOVE ~5M BETWEEN PINGS)", "GRID_UI_Badge", x + 30, barY + 15,
                Color(34, 211, 238), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("[R] RESET RADAR", "GRID_UI_Badge", x + w - 30, barY + 15, Color(148, 163, 184),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    -- Global Police Raid Dispatch Waypoint HUD Marker
    hook.Add("HUDPaint", "GRID_ContrabandScanner_RaidHUD", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:IsPolice() then return end
        if not GRID.ActivePoliceRaid or CurTime() >= GRID.ActivePoliceRaid.expire then return end

        local raid = GRID.ActivePoliceRaid
        local screen = raid.pos:ToScreen()
        if not screen.visible then return end

        local distMeters = math.Round(ply:GetPos():Distance(raid.pos) * 0.01905)
        local remaining = math.ceil(raid.expire - CurTime())
        local pulse = (math.sin(CurTime() * 6) + 1) * 0.5
        local badgeCol = Color(239, 68, 68, 220 + math.floor(pulse * 35))

        local mw, mh = 260, 48
        local mx, my = screen.x - (mw / 2), screen.y - (mh / 2)

        draw.RoundedBox(6, mx, my, mw, mh, Color(11, 15, 25, 240))
        surface.SetDrawColor(239, 68, 68, 180)
        surface.DrawOutlinedRect(mx, my, mw, mh, 1)
        draw.RoundedBoxEx(6, mx, my, mw, 2, badgeCol, true, true, false, false)

        draw.SimpleText("◆ RAID TARGET: CONTRABAND ◆", "GRID_UI_Badge", screen.x, my + 14, badgeCol, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("Distance: ~%dm  •  Expires: %ds", distMeters, remaining), "GRID_UI_Caption",
            screen.x, my + 32, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end)
end
