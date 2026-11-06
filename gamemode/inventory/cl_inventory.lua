--[[
    cl_inventory.lua - Client-Side Inventory Synchronization & Net Action Handlers
    Author: Juicebox & Antigravity
--]]

GRID = GRID or {}
GRID.Inventory = GRID.Inventory or {}
GRID.Inventory.ClientItems = {}
GRID.Inventory.ClientBags = { bag1 = "", bag2 = "", bag3 = "", bag4 = "" }
GRID.Inventory.Slots = {}

-- ========================================================
-- NETWORK SYNC RECEIVER (SLOTS & BAGS)
-- ========================================================

local function HandleSyncInventory()
    local count = net.ReadUInt(16)
    GRID.Inventory.ClientItems = {}
    GRID.Inventory.Slots = {}

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

        table.insert(GRID.Inventory.ClientItems, itemEntry)
        GRID.Inventory.Slots[bagIndex .. "_" .. slotIndex] = itemEntry
    end

    GRID.Inventory.ClientBags = {
        bag1 = net.ReadString(),
        bag2 = net.ReadString(),
        bag3 = net.ReadString(),
        bag4 = net.ReadString()
    }

    -- Refresh Bag Window if open
    local ui = GRID.UI
    if ui and ui.RefreshBag then
        ui.RefreshBag()
    end

    -- If F4 menu is open on inventory tab, refresh it
    if ui and IsValid(ui.F4Frame) and ui.ActiveF4Tab == "inventory" then
        if ui.RefreshInventoryTab then
            ui.RefreshInventoryTab()
        elseif IsValid(ui.CurrentContentPanel) then
            ui.CurrentContentPanel:Clear()
            ui.RenderContentTab(ui.CurrentContentPanel, "inventory", ui.F4Frame)
        end
    end

    hook.Run("GRID_InventorySynced")
end

net.Receive("GRID_SyncInventory", HandleSyncInventory)

function GRID.Inventory.MoveSlot(fromBag, fromSlot, toBag, toSlot)
    net.Start("GRID_MoveInventorySlot")
    net.WriteUInt(fromBag, 8)
    net.WriteUInt(fromSlot, 8)
    net.WriteUInt(toBag, 8)
    net.WriteUInt(toSlot, 8)
    net.SendToServer()
end

function GRID.Inventory.DropSlot(bagIndex, slotIndex)
    net.Start("GRID_DropInventorySlot")
    net.WriteUInt(bagIndex, 8)
    net.WriteUInt(slotIndex, 8)
    net.SendToServer()
end

function GRID.Inventory.UseSlot(bagIndex, slotIndex)
    net.Start("GRID_UseInventorySlot")
    net.WriteUInt(bagIndex, 8)
    net.WriteUInt(slotIndex, 8)
    net.SendToServer()
end

function GRID.Inventory.DropItem(rowId)
    net.Start("GRID_DropInventoryItem")
    net.WriteUInt(rowId, 32)
    net.SendToServer()
end

function GRID.Inventory.UseItem(rowId)
    net.Start("GRID_UseInventoryItem")
    net.WriteUInt(rowId, 32)
    net.SendToServer()
end

-- Shortcuts: /inv, /inventory, /bag, console "inventory", console "bag"
concommand.Add("inventory", function()
    local ui = GRID.UI
    if ui and ui.ToggleBag then
        ui.ToggleBag()
    elseif ui then
        ui.ActiveF4Tab = "inventory"
        ui.ToggleF4Menu()
    end
end)

concommand.Add("inv", function()
    local ui = GRID.UI
    if ui and ui.ToggleBag then
        ui.ToggleBag()
    elseif ui then
        ui.ActiveF4Tab = "inventory"
        ui.ToggleF4Menu()
    end
end)

concommand.Add("bag", function()
    local ui = GRID.UI
    if ui and ui.ToggleBag then
        ui.ToggleBag()
    end
end)

concommand.Add("bags", function()
    local ui = GRID.UI
    if ui and ui.ToggleBag then
        ui.ToggleBag()
    end
end)
