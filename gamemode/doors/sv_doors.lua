--[[
    sv_doors.lua - Door Purchasing, Locking & Gang Sharing (Session-based)
    Author: Toxic
--]]

GW.Doors = GW.Doors or {}

function GW.Doors.Init()
    print("[GWRP-Doors] Initialized session-based door management.")
end

function GW.Doors.SyncToPlayer(ply)
    -- Doors use standard SetNWEntity/SetNWString for seamless client prediction
end

net.Receive("GW_DoorAction", function(len, ply)
    if not GW.CheckRateLimit(ply, "door_action", 3) then return end
    local ent = net.ReadEntity()
    local action = net.ReadString()

    if not IsValid(ent) or not ent:isDoor() then return end
    if ply:GetPos():DistToSqr(ent:GetPos()) > (120 * 120) then return end

    local currentOwner = ent:GetNWEntity("GW_DoorOwner")

    if action == "buy" then
        if IsValid(currentOwner) then
            GW.Notify(ply, "This door is already owned!", NOTIFY_ERROR)
            return
        end
        if not ply:CanAfford(GW.Config.DoorCost) then
            GW.Notify(ply, "You cannot afford this door ($" .. GW.Config.DoorCost .. ")!", NOTIFY_ERROR)
            return
        end

        ply:AddMoney(-GW.Config.DoorCost)
        ent:SetNWEntity("GW_DoorOwner", ply)
        local gang = ply:GetGang()
        local factionTag = (gang ~= "") and gang or ply:GetFaction().id
        ent:SetNWString("GW_DoorFaction", factionTag)

        GW.Notify(ply, "Door purchased! Press F2 to manage.", NOTIFY_GENERIC)
    elseif action == "sell" then
        if currentOwner ~= ply then return end
        local refund = math.floor(GW.Config.DoorCost * 0.7)
        ply:AddMoney(refund)

        ent:SetNWEntity("GW_DoorOwner", NULL)
        ent:SetNWString("GW_DoorFaction", "")
        ent:Fire("unlock", "", 0)

        GW.Notify(ply, "Door sold for +$" .. refund .. "!", NOTIFY_GENERIC)
    end
end)
