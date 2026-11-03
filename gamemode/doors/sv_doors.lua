--[[
    sv_doors.lua - Door Purchasing, Locking & Gang Sharing (Session-based)
    Author: Toxic
--]]

GWRP.Doors = GWRP.Doors or {}

function GWRP.Doors.Init()
    print("[GWRP-Doors] Initialized session-based door management.")
end

function GWRP.Doors.SyncToPlayer(ply)
    -- Doors use standard SetNWEntity/SetNWString for seamless client prediction
end

net.Receive("GWRP_DoorAction", function(len, ply)
    if not GWRP.CheckRateLimit(ply, "door_action", 3) then return end
    local ent = net.ReadEntity()
    local action = net.ReadString()

    if not IsValid(ent) or not ent:isDoor() then return end
    if ply:GetPos():DistToSqr(ent:GetPos()) > (120 * 120) then return end

    local currentOwner = ent:GetNWEntity("GWRP_DoorOwner")

    if action == "buy" then
        if IsValid(currentOwner) then
            GWRP.Notify(ply, "This door is already owned!", NOTIFY_ERROR)
            return
        end
        if not ply:CanAfford(GWRP.Config.DoorCost) then
            GWRP.Notify(ply, "You cannot afford this door ($" .. GWRP.Config.DoorCost .. ")!", NOTIFY_ERROR)
            return
        end

        ply:AddMoney(-GWRP.Config.DoorCost)
        ent:SetNWEntity("GWRP_DoorOwner", ply)
        local gang = ply:GetGang()
        local factionTag = (gang ~= "") and gang or ply:GetFaction().id
        ent:SetNWString("GWRP_DoorFaction", factionTag)

        GWRP.Notify(ply, "Door purchased! Press F2 to manage.", NOTIFY_GENERIC)
    elseif action == "sell" then
        if currentOwner ~= ply then return end
        local refund = math.floor(GWRP.Config.DoorCost * 0.7)
        ply:AddMoney(refund)

        ent:SetNWEntity("GWRP_DoorOwner", NULL)
        ent:SetNWString("GWRP_DoorFaction", "")
        ent:Fire("unlock", "", 0)

        GWRP.Notify(ply, "Door sold for +$" .. refund .. "!", NOTIFY_GENERIC)
    end
end)
