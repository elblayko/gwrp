--[[
    sh_entity_meta.lua - Metatable Extensions on Entity (Configurable Item Quality System)
    Author: Toxic
--]]

local entMeta = FindMetaTable("Entity")
if not entMeta then return end

-- Quality Normalizer: Maps string keys ("uncommon", "rare", etc.) or numbers (0..5) to integer quality ID
local qualityMap = {
    poor = 0,
    common = 1,
    uncommon = 2,
    rare = 3,
    epic = 4,
    legendary = 5
}

function GW.NormalizeQuality(val)
    if val == nil or val == false then return nil end
    if type(val) == "string" then
        local s = string.lower(string.Trim(val))
        return qualityMap[s]
    elseif type(val) == "number" and val >= 0 and val <= 5 then
        return math.floor(val)
    end
    return nil
end

-- ========================================================
-- ENTITY ITEM QUALITY METHODS
-- ========================================================

function entMeta:GetItemQuality()
    -- Explicitly exclude players, NPCs, world brushes, and doors
    if self:IsPlayer() or self:IsNPC() or self:IsWorld() or (self.isDoor and self:isDoor()) or (self.IsDoor and self:IsDoor()) then
        return nil
    end

    -- Explicit exclusion check (e.g. flag pole or explicit flag)
    if self.NoQuality or self:GetClass() == "gw_flag_pole" or self:GetClass() == "gw_clinic_pod" then
        return nil
    end

    -- 1. Dynamic Networked Instance Quality Override (if set via SetItemQuality)
    local nwQuality = self:GetNWInt("GW_Quality", -1)
    if nwQuality >= 0 then
        return nwQuality
    end

    -- 2. First-Class Check: ENT.ItemQuality defined directly inside the entity's shared.lua
    if self.ItemQuality ~= nil then
        return GW.NormalizeQuality(self.ItemQuality)
    end

    -- 3. Check Scripted Entity Table (Stored Class Definition)
    local sent = scripted_ents.Get(self:GetClass()) or scripted_ents.GetStored(self:GetClass())
    if sent and sent.t and sent.t.ItemQuality ~= nil then
        return GW.NormalizeQuality(sent.t.ItemQuality)
    end

    -- 4. Check Central Registry Fallback in GW.Config.EntityQualities
    if GW.Config and GW.Config.EntityQualities then
        local cfg = GW.Config.EntityQualities[self:GetClass()]
        if cfg and cfg.quality ~= nil then
            return GW.NormalizeQuality(cfg.quality)
        end
    end

    return nil
end

function entMeta:HasItemQuality()
    return self:GetItemQuality() ~= nil
end

function entMeta:GetItemQualityData()
    local q = self:GetItemQuality()
    if q == nil then return nil end

    if GW.Inventory and GW.Inventory.Quality then
        local tiers = {
            [0] = GW.Inventory.Quality.POOR,
            [1] = GW.Inventory.Quality.COMMON,
            [2] = GW.Inventory.Quality.UNCOMMON,
            [3] = GW.Inventory.Quality.RARE,
            [4] = GW.Inventory.Quality.EPIC,
            [5] = GW.Inventory.Quality.LEGENDARY
        }
        if tiers[q] then return tiers[q] end
    end

    return { id = q, name = "Standard", color = Color(248, 250, 252) }
end

function entMeta:SetItemQuality(tier)
    local normalized = GW.NormalizeQuality(tier)
    if normalized ~= nil then
        self:SetNWInt("GW_Quality", normalized)
    else
        self:SetNWInt("GW_Quality", -1)
    end
end
