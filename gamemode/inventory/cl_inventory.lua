--[[
    cl_inventory.lua - Client-Side Inventory Synchronization & Net Action Handlers
    Author: Toxic
--]]

GWRP.Inventory = GWRP.Inventory or {}
GWRP.Inventory.ClientItems = {}
GWRP.Inventory.ClientBags = { bag1 = "", bag2 = "", bag3 = "", bag4 = "" }
GWRP.Inventory.Slots = {}

-- ========================================================
-- NETWORK SYNC RECEIVER (SLOTS & BAGS)
-- ========================================================

net.Receive("GWRP_SyncInventory", function()
    local count = net.ReadUInt(16)
    GWRP.Inventory.ClientItems = {}
    GWRP.Inventory.Slots = {}

    for i = 1, count do
        local id = net.ReadUInt(32)
        local bagIndex = net.ReadUInt(8)
        local slotIndex = net.ReadUInt(8)
        local itemId = net.ReadString()
        local itemType = net.ReadString()
        local amount = net.ReadUInt(16)
        local rawData = net.ReadString()

        local itemEntry = {
            id = id,
            bag_index = bagIndex,
            slot_index = slotIndex,
            item_id = itemId,
            item_type = itemType,
            amount = amount,
            item_data = util.JSONToTable(rawData) or {}
        }

        table.insert(GWRP.Inventory.ClientItems, itemEntry)
        GWRP.Inventory.Slots[bagIndex .. "_" .. slotIndex] = itemEntry
    end

    GWRP.Inventory.ClientBags = {
        bag1 = net.ReadString(),
        bag2 = net.ReadString(),
        bag3 = net.ReadString(),
        bag4 = net.ReadString()
    }

    -- Refresh Bag Window if open
    if GWRP.UI and GWRP.UI.RefreshBag then
        GWRP.UI.RefreshBag()
    end

    -- If F4 menu is open on inventory tab, refresh it
    if IsValid(GWRP.UI.F4Frame) and GWRP.UI.ActiveF4Tab == "inventory" then
        if GWRP.UI.RefreshInventoryTab then
            GWRP.UI.RefreshInventoryTab()
        elseif IsValid(GWRP.UI.CurrentContentPanel) then
            GWRP.UI.CurrentContentPanel:Clear()
            GWRP.UI.RenderContentTab(GWRP.UI.CurrentContentPanel, "inventory", GWRP.UI.F4Frame)
        end
    end
end)

function GWRP.Inventory.MoveSlot(fromBag, fromSlot, toBag, toSlot)
    net.Start("GWRP_MoveInventorySlot")
        net.WriteUInt(fromBag, 8)
        net.WriteUInt(fromSlot, 8)
        net.WriteUInt(toBag, 8)
        net.WriteUInt(toSlot, 8)
    net.SendToServer()
end

function GWRP.Inventory.DropSlot(bagIndex, slotIndex)
    net.Start("GWRP_DropInventorySlot")
        net.WriteUInt(bagIndex, 8)
        net.WriteUInt(slotIndex, 8)
    net.SendToServer()
end

function GWRP.Inventory.UseSlot(bagIndex, slotIndex)
    net.Start("GWRP_UseInventorySlot")
        net.WriteUInt(bagIndex, 8)
        net.WriteUInt(slotIndex, 8)
    net.SendToServer()
end

function GWRP.Inventory.DropItem(rowId)
    net.Start("GWRP_DropInventoryItem")
        net.WriteUInt(rowId, 32)
    net.SendToServer()
end

function GWRP.Inventory.UseItem(rowId)
    net.Start("GWRP_UseInventoryItem")
        net.WriteUInt(rowId, 32)
    net.SendToServer()
end

-- Shortcuts: /inv, /inventory, /bag, console "inventory", console "bag"
concommand.Add("inventory", function()
    if GWRP.UI and GWRP.UI.ToggleBag then
        GWRP.UI.ToggleBag()
    else
        GWRP.UI.ActiveF4Tab = "inventory"
        GWRP.UI.ToggleF4Menu()
    end
end)

concommand.Add("inv", function()
    if GWRP.UI and GWRP.UI.ToggleBag then
        GWRP.UI.ToggleBag()
    else
        GWRP.UI.ActiveF4Tab = "inventory"
        GWRP.UI.ToggleF4Menu()
    end
end)

concommand.Add("bag", function()
    if GWRP.UI and GWRP.UI.ToggleBag then
        GWRP.UI.ToggleBag()
    end
end)

concommand.Add("bags", function()
    if GWRP.UI and GWRP.UI.ToggleBag then
        GWRP.UI.ToggleBag()
    end
end)
