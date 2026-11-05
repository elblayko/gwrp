--[[
    GangWars - Wallets, Payday Timer, Dynamic Anti-Inflation Sinks & Cash Drops
    Author: GW Core Team
    Namespace: GW / gw_
]]

GW = GW or {}
GW.Economy = GW.Economy or {}

-- Calculate dynamic fee: Base Flat + Percentage of Wealth (Anti-Inflation Sink)
function GW.Economy.CalculateDynamicFee(ply, flatBase, wealthPct)
    flatBase = tonumber(flatBase) or 0
    wealthPct = tonumber(wealthPct) or 0
    if not IsValid(ply) or not ply:IsPlayer() then return flatBase end

    local wallet = math.max(0, ply:GetMoney())
    local wealthFee = math.floor(wallet * wealthPct)
    return math.max(0, flatBase + wealthFee)
end

function GW.Economy.StartPaydayTimer()
    timer.Create("GW_PaydayTimer", GW.Config.PaydayInterval, 0, function()
        -- 1. Player Paychecks & Property Upkeep
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply.GW_DataLoaded then
                local job = ply:GetJobData()
                if job and job.salary > 0 then
                    ply:AddMoney(job.salary)
                    GW.Notify(ply, string.format("Salary received: +$%d", job.salary), NOTIFY_GENERIC)

                    if GW.Telemetry and GW.Telemetry.Log then
                        GW.Telemetry.Log("ECONOMY", "SALARY_PAYOUT", ply:SteamID(), "", job.salary, { job = ply:GetJob() })
                    end
                end

                -- Dynamic Property Upkeep Sink
                if GW.Doors and GW.Doors.GetOwnedDoors then
                    local ownedDoors = GW.Doors.GetOwnedDoors(ply)
                    local doorCount = #ownedDoors
                    if doorCount > 0 then
                        local flatUpkeep = (GW.Config.PropertyUpkeepBase or 15) + (doorCount * (GW.Config.PropertyUpkeepPerDoor or 5))
                        local upkeepFee = GW.Economy.CalculateDynamicFee(ply, flatUpkeep, GW.Config.PropertyUpkeepWealthPct or 0.005)

                        if ply:CanAfford(upkeepFee) then
                            ply:AddMoney(-upkeepFee)
                            GW.Notify(ply, string.format("Property taxes paid: -$%d (%d doors)", upkeepFee, doorCount), NOTIFY_GENERIC)

                            if GW.Telemetry and GW.Telemetry.Log then
                                GW.Telemetry.Log("ECONOMY", "PROPERTY_UPKEEP", ply:SteamID(), "", upkeepFee, { doors = doorCount })
                            end
                        else
                            -- Foreclose property if player cannot afford upkeep
                            GW.Doors.UnownAll(ply)
                            GW.Notify(ply, "Defaulted on property upkeep! All owned doors have been foreclosed.", NOTIFY_ERROR)

                            if GW.Telemetry and GW.Telemetry.Log then
                                GW.Telemetry.Log("ECONOMY", "PROPERTY_FORECLOSURE", ply:SteamID(), "", 0, { doors = doorCount })
                            end
                        end
                    end
                end
            end
        end

        -- 2. Gang Syndicate Vault Anti-Hoarding Tax Sink
        if GW.Database and GW.Database.GetAllGangs then
            local gangs = GW.Database.GetAllGangs()
            local threshold = GW.Config.GangVaultUpkeepThreshold or 5000
            local rate = GW.Config.GangVaultUpkeepPct or 0.02

            for _, g in ipairs(gangs) do
                local currentBank = tonumber(g.bank) or 0
                if currentBank > threshold then
                    local tax = math.floor((currentBank - threshold) * rate)
                    if tax > 0 then
                        GW.Database.AddGangBank(g.name, -tax)
                        if GW.Telemetry and GW.Telemetry.Log then
                            GW.Telemetry.Log("ECONOMY", "SYNDICATE_VAULT_TAX", g.leader_steamid or "", g.name, tax, {
                                previous_bank = currentBank,
                                new_bank = currentBank - tax
                            })
                        end
                    end
                end
            end
        end
    end)
end

function GW.Economy.SpawnCashStack(pos, amount)
    local cash = ents.Create("gw_cash_stack")
    if IsValid(cash) then
        cash:SetPos(pos)
        cash:SetAmount(amount)
        cash:Spawn()
        cash:Activate()
    end
end

-- Chat command /dropmoney <amount>
hook.Add("PlayerSay", "GW_EconomyChatCommands", function(ply, text)
    local args = string.Explode(" ", text)
    if args[1] == "/dropmoney" then
        local amount = tonumber(args[2])
        if not amount or amount <= 0 then
            GW.Notify(ply, "Usage: /dropmoney <amount>", NOTIFY_ERROR)
            return ""
        end

        amount = math.floor(amount)
        if not ply:CanAfford(amount) then
            GW.Notify(ply, "You do not have enough money!", NOTIFY_ERROR)
            return ""
        end

        ply:AddMoney(-amount)
        local trace = ply:GetEyeTrace()
        local dropPos = trace.HitPos + trace.HitNormal * 10
        GW.Economy.SpawnCashStack(dropPos, amount)
        GW.Notify(ply, string.format("You dropped $%d on the ground.", amount), NOTIFY_GENERIC)

        if GW.Telemetry and GW.Telemetry.Log then
            GW.Telemetry.Log("ECONOMY", "CASH_DROP", ply:SteamID(), "", amount, { pos = tostring(dropPos) })
        end

        return ""
    end
end)
