--[[
    cl_inventory.lua - Client-Side Inventory Synchronization & Net Action Handlers
    Author: Toxic
--]]

GW.Inventory = GW.Inventory or {}
GW.Inventory.ClientItems = {}
GW.Inventory.ClientBags = { bag1 = "", bag2 = "", bag3 = "", bag4 = "" }
GW.Inventory.Slots = {}

-- ========================================================
-- NETWORK SYNC RECEIVER (SLOTS & BAGS)
-- ========================================================

net.Receive("GW_SyncInventory", function()
    local count = net.ReadUInt(16)
    GW.Inventory.ClientItems = {}
    GW.Inventory.Slots = {}

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

        table.insert(GW.Inventory.ClientItems, itemEntry)
        GW.Inventory.Slots[bagIndex .. "_" .. slotIndex] = itemEntry
    end

    GW.Inventory.ClientBags = {
        bag1 = net.ReadString(),
        bag2 = net.ReadString(),
        bag3 = net.ReadString(),
        bag4 = net.ReadString()
    }

    -- Refresh Bag Window if open
    if GW.UI and GW.UI.RefreshBag then
        GW.UI.RefreshBag()
    end

    -- If F4 menu is open on inventory tab, refresh it
    if IsValid(GW.UI.F4Frame) and GW.UI.ActiveF4Tab == "inventory" then
        if GW.UI.RefreshInventoryTab then
            GW.UI.RefreshInventoryTab()
        elseif IsValid(GW.UI.CurrentContentPanel) then
            GW.UI.CurrentContentPanel:Clear()
            GW.UI.RenderContentTab(GW.UI.CurrentContentPanel, "inventory", GW.UI.F4Frame)
        end
    end

    hook.Run("GW_InventorySynced")
end)

function GW.Inventory.MoveSlot(fromBag, fromSlot, toBag, toSlot)
    net.Start("GW_MoveInventorySlot")
        net.WriteUInt(fromBag, 8)
        net.WriteUInt(fromSlot, 8)
        net.WriteUInt(toBag, 8)
        net.WriteUInt(toSlot, 8)
    net.SendToServer()
end

function GW.Inventory.DropSlot(bagIndex, slotIndex)
    net.Start("GW_DropInventorySlot")
        net.WriteUInt(bagIndex, 8)
        net.WriteUInt(slotIndex, 8)
    net.SendToServer()
end

function GW.Inventory.UseSlot(bagIndex, slotIndex)
    net.Start("GW_UseInventorySlot")
        net.WriteUInt(bagIndex, 8)
        net.WriteUInt(slotIndex, 8)
    net.SendToServer()
end

function GW.Inventory.DropItem(rowId)
    net.Start("GW_DropInventoryItem")
        net.WriteUInt(rowId, 32)
    net.SendToServer()
end

function GW.Inventory.UseItem(rowId)
    net.Start("GW_UseInventoryItem")
        net.WriteUInt(rowId, 32)
    net.SendToServer()
end

-- Shortcuts: /inv, /inventory, /bag, console "inventory", console "bag"
concommand.Add("inventory", function()
    if GW.UI and GW.UI.ToggleBag then
        GW.UI.ToggleBag()
    else
        GW.UI.ActiveF4Tab = "inventory"
        GW.UI.ToggleF4Menu()
    end
end)

concommand.Add("inv", function()
    if GW.UI and GW.UI.ToggleBag then
        GW.UI.ToggleBag()
    else
        GW.UI.ActiveF4Tab = "inventory"
        GW.UI.ToggleF4Menu()
    end
end)

concommand.Add("bag", function()
    if GW.UI and GW.UI.ToggleBag then
        GW.UI.ToggleBag()
    end
end)

concommand.Add("bags", function()
    if GW.UI and GW.UI.ToggleBag then
        GW.UI.ToggleBag()
    end
end)
