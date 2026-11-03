--[[
    entities/entities/gwrp_clinic_pod/shared.lua
    GWRP Clinical Triage Pod
    Author: Toxic
--]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Clinical Triage Pod"
ENT.Author = "Toxic"
ENT.Spawnable = true
ENT.Category = "GangWars RP"

-- Exclude from rarity badges
ENT.NoQuality = true

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "OwnerPlayer")
    self:NetworkVar("Int", 0, "VaultCash")
    self:NetworkVar("Int", 1, "TotalPatients")
    self:NetworkVar("Bool", 0, "DoctorOnDuty")
end

-- Treatment Registry & Metadata
GWRP.ClinicTreatments = {
    ["triage_heal"] = {
        name = "Emergency Trauma Surgery",
        desc = "Full surgical triage. Restores Health to 100% capacity.",
        doctorDesc = "Clinical Bonus: Restores Health to 100% + grants +30 HP Overheal!",
        cost = 50,
        icon = "items/smallmedkit1.wav",
        accent = Color(52, 211, 153),
        Apply = function(ply, isDoctorPresent)
            local maxHp = ply:GetMaxHealth() or 100
            local targetHp = isDoctorPresent and (maxHp + 30) or maxHp
            ply:SetHealth(targetHp)
            ply:EmitSound("items/smallmedkit1.wav", 75, 100)
            ply:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 110)
        end
    },
    ["adrenaline_infusion"] = {
        name = "Adrenaline Infusion Stim",
        desc = "Neuro-stimulant cocktail. Grants +30% Sprint Speed for 8 minutes.",
        doctorDesc = "Clinical Bonus: +50% Buff Duration (12 Minutes total duration)!",
        cost = 75,
        icon = "npc/fast_zombie/wake1.wav",
        accent = Color(251, 191, 36),
        Apply = function(ply, isDoctorPresent)
            local dur = isDoctorPresent and 720 or 480 -- 12m or 8m
            if ply.AddBuff then
                ply:AddBuff("swiftness", dur)
            elseif GWRP.Buffs and GWRP.Buffs.Apply then
                GWRP.Buffs.Apply(ply, "swiftness", dur)
            end
            ply:EmitSound("npc/fast_zombie/wake1.wav", 70, 130)
            ply:EmitSound("items/medshot4.wav", 70, 105)
        end
    },
    ["subdermal_plating"] = {
        name = "Subdermal Trauma Plating",
        desc = "Reinforced ceramic tissue mesh. Grants +50 Max Health for 8 minutes.",
        doctorDesc = "Clinical Bonus: +50% Buff Duration (12 Minutes total duration)!",
        cost = 100,
        icon = "items/suitchargeok1.wav",
        accent = Color(56, 189, 248),
        Apply = function(ply, isDoctorPresent)
            local dur = isDoctorPresent and 720 or 480 -- 12m or 8m
            if ply.AddBuff then
                ply:AddBuff("fortitude", dur)
            elseif GWRP.Buffs and GWRP.Buffs.Apply then
                GWRP.Buffs.Apply(ply, "fortitude", dur)
            end
            ply:EmitSound("items/suitchargeok1.wav", 75, 100)
        end
    },
    ["neuro_detox"] = {
        name = "Neuro-Detox Flush",
        desc = "Full biochemical flush. Cleanses poison/slow debuffs + gives Trauma Recovery HoT for 5 minutes.",
        doctorDesc = "Clinical Bonus: Cleanses debuffs + 7.5 Minutes of Trauma Recovery (+6 HP / 1.5s)!",
        cost = 60,
        icon = "ambient/levels/canals/steam_hiss2.wav",
        accent = Color(168, 85, 247),
        Apply = function(ply, isDoctorPresent)
            local dur = isDoctorPresent and 450 or 300 -- 7.5m or 5m
            if ply.RemoveBuff then
                ply:RemoveBuff("poison", "treatment")
                ply:RemoveBuff("crippled", "treatment")
            end
            if ply.AddBuff then
                ply:AddBuff("healing_over_time", dur, { healPerTick = 6 })
            elseif GWRP.Buffs and GWRP.Buffs.Apply then
                GWRP.Buffs.Apply(ply, "healing_over_time", dur, { healPerTick = 6 })
            end
            ply:EmitSound("ambient/levels/canals/steam_hiss2.wav", 70, 115)
            ply:EmitSound("items/medshot4.wav", 70, 100)
        end
    }
}
