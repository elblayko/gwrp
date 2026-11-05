--[[
    sv_doors.lua - Door Purchasing, Locking & Gang Sharing (Session-based)
    Author: Toxic & Antigravity
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
        -- Disallow purchasing func_door entities
        if ent:GetClass() == "func_door" then
            GW.Notify(ply, "This type of door cannot be purchased!", NOTIFY_ERROR)
            return
        end

        -- Hobos cannot purchase property
        if ply:GetJob() == "hobo" then
            GW.Notify(ply, "Hobos are homeless and cannot purchase properties!", NOTIFY_ERROR)
            return
        end

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

function GW.Doors.GetOwnedDoors(ply)
    if not IsValid(ply) then return {} end
    local owned = {}
    for _, ent in ipairs(ents.GetAll()) do
        if ent:isDoor() and ent:GetNWEntity("GW_DoorOwner") == ply then
            table.insert(owned, ent)
        end
    end
    return owned
end

function GW.Doors.UnownAll(ply)
    if not IsValid(ply) then return end
    for _, door in ipairs(GW.Doors.GetOwnedDoors(ply)) do
        door:SetNWEntity("GW_DoorOwner", NULL)
        door:SetNWString("GW_DoorFaction", "")
        door:Fire("unlock", "", 0)
    end
end
