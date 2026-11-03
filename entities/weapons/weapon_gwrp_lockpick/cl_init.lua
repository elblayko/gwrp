--[[
    entities/weapons/weapon_gwrp_lockpick/cl_init.lua
    GWRP Tactical Lockpick - Client
    Author: Toxic
--]]

include("shared.lua")

function SWEP:DrawHUD()
    local ply = self:GetOwner()
    if not IsValid(ply) or ply ~= LocalPlayer() then return end

    if self:GetIsLockpicking() then
        local st = self:GetPickStartTime()
        local et = self:GetPickEndTime()
        local duration = math.max(et - st, 0.1)
        local progress = math.Clamp((CurTime() - st) / duration, 0, 1)
        local remaining = math.max(0, math.ceil(et - CurTime()))

        local w, h = 320, 42
        local x = (ScrW() - w) / 2
        local y = ScrH() / 2 + 60

        -- Background Frame
        draw.RoundedBox(6, x, y, w, h, Color(11, 15, 25, 240))
        surface.SetDrawColor(30, 41, 59, 220)
        surface.DrawOutlinedRect(x, y, w, h, 1)

        -- Progress Fill
        local fillW = (w - 8) * progress
        if fillW > 4 then
            draw.RoundedBox(4, x + 4, y + 4, fillW, h - 8, Color(245, 158, 11, 230))
        end

        -- Status Text
        local pct = math.floor(progress * 100)
        local text = string.format("Picking Lock: %d%% (%ds)", pct, remaining)
        draw.SimpleText(text, "GWRP_UI_Btn", ScrW() / 2, y + h / 2, Color(248, 250, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        -- Contextual prompt when aiming at a valid target
        local tr = ply:GetEyeTrace()
        local ent = tr.Entity
        local distSqr = self.MaxLockpickDistance * self.MaxLockpickDistance

        if IsValid(ent) and tr.HitPos:DistToSqr(ply:EyePos()) <= distSqr then
            local isDoor = ent.isDoor and ent:isDoor() or (ent.IsDoor and ent:IsDoor())
            local isProp = ent:GetClass() == "prop_physics"

            if isDoor or isProp then
                local cx, cy = ScrW() / 2, ScrH() / 2
                local prompt = isDoor and "[ Left-Click ] Pick Door Lock" or "[ Left-Click ] Unseal Barricade"
                draw.SimpleText(prompt, "GWRP_UI_Caption", cx, cy + 35, Color(245, 158, 11, 220), TEXT_ALIGN_CENTER)
            end
        end
    end
end

