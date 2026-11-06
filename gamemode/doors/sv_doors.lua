--[[
    sv_doors.lua - Door Purchasing, Locking & Gang Sharing (Session-based)
    Author: Juicebox & Antigravity
--]]

GRID = GRID or {}
GRID.Doors = GRID.Doors or {}

function GRID.Doors.Init()
    print("[GridRP-Doors] Initialized session-based door management.")
end

function GRID.Doors.SyncToPlayer(ply)
    -- Doors use standard SetNWEntity/SetNWString for seamless client prediction
end

local function HandleDoorAction(len, ply)
    if not GRID.CheckRateLimit(ply, "door_action", 3) then return end
    local ent = net.ReadEntity()
    local action = net.ReadString()

    if not IsValid(ent) or not ent:isDoor() then return end
    if ply:GetPos():DistToSqr(ent:GetPos()) > (120 * 120) then return end

    local currentOwner = ent:GetNWEntity("GRID_DoorOwner")

    if action == "buy" then
        -- Disallow purchasing func_door entities
        if ent:GetClass() == "func_door" then
            GRID.Notify(ply, "This type of door cannot be purchased!", NOTIFY_ERROR)
            return
        end

        -- Hobos cannot purchase property
        if ply:GetJob() == "hobo" then
            GRID.Notify(ply, "Hobos are homeless and cannot purchase properties!", NOTIFY_ERROR)
            return
        end

        if IsValid(currentOwner) then
            GRID.Notify(ply, "This door is already owned!", NOTIFY_ERROR)
            return
        end
        local cost = (GRID.Config and GRID.Config.DoorCost) or 15
        if not ply:CanAfford(cost) then
            GRID.Notify(ply, "You cannot afford this door ($" .. cost .. ")!", NOTIFY_ERROR)
            return
        end

        ply:AddMoney(-cost)
        ent:SetNWEntity("GRID_DoorOwner", ply)
        local gang = ply:GetGang()
        local factionTag = (gang ~= "") and gang or ply:GetFaction().id
        ent:SetNWString("GRID_DoorFaction", factionTag)

        GRID.Notify(ply, "Door purchased! Press F2 to manage.", NOTIFY_GENERIC)
    elseif action == "sell" then
        if currentOwner ~= ply then return end
        local cost = (GRID.Config and GRID.Config.DoorCost) or 15
        local refund = math.floor(cost * 0.7)
        ply:AddMoney(refund)

        ent:SetNWEntity("GRID_DoorOwner", NULL)
        ent:SetNWString("GRID_DoorFaction", "")
        ent:Fire("unlock", "", 0)

        GRID.Notify(ply, "Door sold for +$" .. refund .. "!", NOTIFY_GENERIC)
    end
end

net.Receive("GRID_DoorAction", HandleDoorAction)

function GRID.Doors.GetOwnedDoors(ply)
    if not IsValid(ply) then return {} end
    local owned = {}
    for _, ent in ipairs(ents.GetAll()) do
        if ent:isDoor() then
            local o = ent:GetNWEntity("GRID_DoorOwner")
            if o == ply then
                table.insert(owned, ent)
            end
        end
    end
    return owned
end

function GRID.Doors.UnownAll(ply)
    if not IsValid(ply) then return end
    for _, door in ipairs(GRID.Doors.GetOwnedDoors(ply)) do
        door:SetNWEntity("GRID_DoorOwner", NULL)
        door:SetNWString("GRID_DoorFaction", "")
        door:Fire("unlock", "", 0)
    end
end
