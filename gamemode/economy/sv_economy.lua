--[[
    GridRP - Wallets, Payday Timer, Dynamic Anti-Inflation Sinks & Cash Drops
    Author: GRID Core Team
    Namespace: GRID / grid_
]]

GRID = GRID or {}
GRID.Economy = GRID.Economy or {}

-- Calculate dynamic fee: Base Flat + Percentage of Total Net Worth (Wallet + Bank) (Anti-Inflation Sink)
function GRID.Economy.CalculateDynamicFee(ply, flatBase, wealthPct)
    flatBase = tonumber(flatBase) or 0
    wealthPct = tonumber(wealthPct) or 0
    if not IsValid(ply) or not ply:IsPlayer() then return flatBase end

    local wallet = math.max(0, ply:GetMoney())
    local bank = math.max(0, ply.GetBank and ply:GetBank() or 0)
    local netWorth = wallet + bank
    local wealthFee = math.floor(netWorth * wealthPct)
    return math.max(0, flatBase + wealthFee)
end

-- Deduct mandatory dynamic fee from Wallet first, auto-drafting remainder from Personal Bank if needed
function GRID.Economy.DeductFeeWithBankFallback(ply, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return true, 0, 0 end
    if not IsValid(ply) or not ply:IsPlayer() then return false, 0, 0 end

    local wallet = math.max(0, ply:GetMoney())
    local bank = math.max(0, ply.GetBank and ply:GetBank() or 0)
    if (wallet + bank) < amount then
        return false, 0, 0
    end

    local fromWallet = math.min(wallet, amount)
    local fromBank = amount - fromWallet
    if fromWallet > 0 then
        ply:AddMoney(-fromWallet)
    end
    if fromBank > 0 and ply.AddBank then
        ply:AddBank(-fromBank)
    end
    return true, fromWallet, fromBank
end

function GRID.Economy.StartPaydayTimer()
    timer.Create("GRID_PaydayTimer", (GRID.Config and GRID.Config.PaydayInterval) or 90, 0, function()
        -- 1. Player Paychecks & Property Upkeep
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply.GRID_DataLoaded then
                local job = ply:GetJobData()
                if job and job.salary > 0 then
                    ply:AddMoney(job.salary)
                    GRID.Notify(ply, string.format("Salary received: +$%d", job.salary), NOTIFY_GENERIC)

                    if GRID.Telemetry and GRID.Telemetry.Log then
                        GRID.Telemetry.Log("ECONOMY", "SALARY_PAYOUT", ply:SteamID(), "", job.salary, { job = ply:GetJob() })
                    end
                end

                -- Dynamic Property Upkeep Sink
                if GRID.Doors and GRID.Doors.GetOwnedDoors then
                    local ownedDoors = GRID.Doors.GetOwnedDoors(ply)
                    local doorCount = #ownedDoors
                    if doorCount > 0 then
                        local flatUpkeep = ((GRID.Config and GRID.Config.PropertyUpkeepBase) or 15) + (doorCount * ((GRID.Config and GRID.Config.PropertyUpkeepPerDoor) or 5))
                        local upkeepFee = GRID.Economy.CalculateDynamicFee(ply, flatUpkeep, (GRID.Config and GRID.Config.PropertyUpkeepWealthPct) or 0.005)

                        local paid, fromWallet, fromBank = GRID.Economy.DeductFeeWithBankFallback(ply, upkeepFee)
                        if paid then
                            GRID.Notify(ply, string.format("Property taxes paid: -$%d (%d doors)", upkeepFee, doorCount), NOTIFY_GENERIC)

                            if GRID.Telemetry and GRID.Telemetry.Log then
                                GRID.Telemetry.Log("ECONOMY", "PROPERTY_UPKEEP", ply:SteamID(), "", upkeepFee, {
                                    doors = doorCount,
                                    from_wallet = fromWallet,
                                    from_bank = fromBank
                                })
                            end
                        else
                            -- Foreclose property if player cannot afford upkeep
                            GRID.Doors.UnownAll(ply)
                            GRID.Notify(ply, "Defaulted on property upkeep! All owned doors have been foreclosed.", NOTIFY_ERROR)

                            if GRID.Telemetry and GRID.Telemetry.Log then
                                GRID.Telemetry.Log("ECONOMY", "PROPERTY_FORECLOSURE", ply:SteamID(), "", 0, { doors = doorCount })
                            end
                        end
                    end
                end
            end
        end

        -- 2. Gang Syndicate Vault Anti-Hoarding Tax Sink
        if GRID.Database and GRID.Database.GetAllGangs then
            local gangs = GRID.Database.GetAllGangs()
            local threshold = (GRID.Config and GRID.Config.GangVaultUpkeepThreshold) or 5000
            local rate = (GRID.Config and GRID.Config.GangVaultUpkeepPct) or 0.02

            for _, g in ipairs(gangs) do
                local currentBank = tonumber(g.bank) or 0
                if currentBank > threshold then
                    local tax = math.floor((currentBank - threshold) * rate)
                    if tax > 0 then
                        GRID.Database.AddGangBank(g.name, -tax)
                        if GRID.Telemetry and GRID.Telemetry.Log then
                            GRID.Telemetry.Log("ECONOMY", "SYNDICATE_VAULT_TAX", g.leader_steamid or "", g.name, tax, {
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

function GRID.Economy.SpawnCashStack(pos, amount)
    local cash = ents.Create("grid_cash_stack")
    if IsValid(cash) then
        cash:SetPos(pos)
        cash:SetAmount(amount)
        cash:Spawn()
        cash:Activate()
    end
end

-- Chat command /dropmoney <amount>
hook.Add("PlayerSay", "GRID_EconomyChatCommands", function(ply, text)
    local args = string.Explode(" ", text)
    if args[1] == "/dropmoney" then
        local amount = tonumber(args[2])
        if not amount or amount <= 0 then
            GRID.Notify(ply, "Usage: /dropmoney <amount>", NOTIFY_ERROR)
            return ""
        end

        amount = math.floor(amount)
        if not ply:CanAfford(amount) then
            GRID.Notify(ply, "You do not have enough money!", NOTIFY_ERROR)
            return ""
        end

        ply:AddMoney(-amount)
        local trace = ply:GetEyeTrace()
        local dropPos = trace.HitPos + trace.HitNormal * 10
        GRID.Economy.SpawnCashStack(dropPos, amount)
        GRID.Notify(ply, string.format("You dropped $%d on the ground.", amount), NOTIFY_GENERIC)

        if GRID.Telemetry and GRID.Telemetry.Log then
            GRID.Telemetry.Log("ECONOMY", "CASH_DROP", ply:SteamID(), "", amount, { pos = tostring(dropPos) })
        end

        return ""
    end
end)
