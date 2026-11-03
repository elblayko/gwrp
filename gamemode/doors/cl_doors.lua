--[[
    cl_doors.lua - 3D2D Door Text Rendering & F2 Menu (Player Gang Support)
--]]

GWRP.Doors = GWRP.Doors or {}

hook.Add("PostDrawOpaqueRenderables", "GWRP_DrawDoorText", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or not ent:isDoor() then return end
    if ply:GetPos():DistToSqr(ent:GetPos()) > (200 * 200) then return end

    local owner = ent:GetNWEntity("GWRP_DoorOwner")
    local gangName = ent:GetNWString("GWRP_DoorFaction", "")

    local text = "Press F2 to Purchase ($" .. GWRP.Config.DoorCost .. ")"
    local col = GWRP.Colors.White

    if IsValid(owner) then
        if gangName ~= "" and gangName ~= "neutral" then
            text = "Owned by: " .. owner:Nick() .. " [" .. gangName .. "]"
            col = GWRP.GetGangColor(gangName)
        else
            text = "Owned by: " .. owner:Nick()
            col = GWRP.Colors.White
        end
    end

    local ang = ent:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    local pos = ent:GetPos() + ent:GetUp() * 5 + ent:GetForward() * 2

    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleText(text, "GWRP_FontSmall", 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end)

function GWRP.Doors.OpenDoorMenu()
    local ply = LocalPlayer()
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or not ent:isDoor() then return end
    if ply:GetPos():DistToSqr(ent:GetPos()) > (120 * 120) then return end

    local owner = ent:GetNWEntity("GWRP_DoorOwner")

    local frame = vgui.Create("DFrame")
    frame:SetSize(280, 140)
    frame:Center()
    frame:SetTitle("Door Management")
    frame:MakePopup()

    if not IsValid(owner) then
        local btn = vgui.Create("DButton", frame)
        btn:SetSize(240, 45)
        btn:SetPos(20, 50)
        btn:SetText("Purchase Door ($" .. GWRP.Config.DoorCost .. ")")
        btn.DoClick = function()
            net.Start("GWRP_DoorAction")
                net.WriteEntity(ent)
                net.WriteString("buy")
            net.SendToServer()
            frame:Close()
        end
    else
        if owner == ply then
            local btn = vgui.Create("DButton", frame)
            btn:SetSize(240, 45)
            btn:SetPos(20, 50)
            btn:SetText("Sell Door")
            btn.DoClick = function()
                net.Start("GWRP_DoorAction")
                    net.WriteEntity(ent)
                    net.WriteString("sell")
                net.SendToServer()
                frame:Close()
            end
        end
    end
end
