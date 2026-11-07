--[[
    grid_crafting_material/shared.lua - Shared Crafting Material Entity
    Author: Juicebox & Antigravity
--]]

ENT.Type = "anim"
ENT.Base = "grid_base_interactive"
ENT.PrintName = "Crafting Material"
ENT.Author = "Juicebox"
ENT.Category = "GridRP - Economy & Items"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.OverheadConfig = {
    Enabled = true,
    FaceCamera = true,
    Offset = Vector(0, 0, 14),
    MaxDistance = 220,
    FadeStart = 150,
    Scale = 0.08,
    CustomDraw = function(self, pos, ang, alpha)
        local matId = self:GetMaterialID()
        if not matId or matId == "" then matId = "crafting_ingot_zinc" end

        local def = GRID.Crafting and GRID.Crafting.Materials and GRID.Crafting.Materials[matId]
        local itemName = def and def.name or matId
        local itemAmount = self:GetAmount() or 1
        local qColor = (GRID.Inventory and GRID.Inventory.GetQualityColor and GRID.Inventory.GetQualityColor(def and def.quality or 1)) or Color(248, 250, 252)

        local w, h = 180, 50
        local x, y = -w / 2, -h / 2

        -- Glassmorphic container
        draw.RoundedBox(6, x, y, w, h, Color(11, 15, 25, math.floor(alpha * 0.9)))
        surface.SetDrawColor(30, 41, 59, math.floor(alpha * 0.86))
        surface.DrawOutlinedRect(x, y, w, h, 1)

        -- Top accent glow matching quality
        draw.RoundedBox(2, x + 4, y + 3, w - 8, 2, Color(qColor.r, qColor.g, qColor.b, alpha))

        -- Title & count
        draw.SimpleText(string.format("%dx %s", itemAmount, itemName), "GRID_UI_BodyBold", 0, y + 16, Color(qColor.r, qColor.g, qColor.b, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Interaction prompt
        draw.SimpleText("[E] Collect into Bag", "GRID_UI_Badge", 0, y + 36, Color(148, 163, 184, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
}

ENT.InteractionConfig = {
    Enabled = true,
    MaxUseDistance = 120,
    GetBadge = function(self, ply)
        local matId = self:GetMaterialID()
        local def = GRID.Crafting and GRID.Crafting.Materials and GRID.Crafting.Materials[matId]
        return def and (def.tier and ("TIER " .. def.tier) or "RESOURCE") or "MATERIAL"
    end,
    GetBadgeColor = function(self, ply)
        local matId = self:GetMaterialID()
        local def = GRID.Crafting and GRID.Crafting.Materials and GRID.Crafting.Materials[matId]
        return (GRID.Inventory and GRID.Inventory.GetQualityColor and GRID.Inventory.GetQualityColor(def and def.quality or 1)) or Color(52, 211, 153)
    end,
    GetTitle = function(self, ply)
        local matId = self:GetMaterialID()
        local def = GRID.Crafting and GRID.Crafting.Materials and GRID.Crafting.Materials[matId]
        local count = self:GetAmount() or 1
        return string.format("%dx %s", count, def and def.name or "Crafting Scrap")
    end,
    GetSubtext = function(self, ply)
        local matId = self:GetMaterialID()
        local def = GRID.Crafting and GRID.Crafting.Materials and GRID.Crafting.Materials[matId]
        return def and def.desc or "Industrial crafting material for recipes."
    end,
    PrimaryAction = "Collect Scrap",
    PrimaryKey = "E",
    ShowProgressBar = false,
    CanUse = function(self, ply)
        return true
    end
}

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "MaterialID")
    self:NetworkVar("Int", 0, "Amount")
    self:NetworkVar("Vector", 0, "TintColor")
end
