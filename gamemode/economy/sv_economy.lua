--[[
    sv_economy.lua - Wallets, Payday Timer & Cash Drops
--]]

GWRP.Economy = GWRP.Economy or {}

function GWRP.Economy.StartPaydayTimer()
    timer.Create("GWRP_PaydayTimer", GWRP.Config.PaydayInterval, 0, function()
        for _, ply in ipairs(player.GetAll()) do
            local job = ply:GetJobData()
            if job and job.salary > 0 then
                ply:AddMoney(job.salary)
                GWRP.Notify(ply, string.format("Salary received: +$%d", job.salary), NOTIFY_GENERIC)
            end
        end
    end)
end

function GWRP.Economy.SpawnCashStack(pos, amount)
    local cash = ents.Create("gwrp_cash_stack")
    if IsValid(cash) then
        cash:SetPos(pos)
        cash:SetAmount(amount)
        cash:Spawn()
        cash:Activate()
    end
end

-- Chat command /dropmoney <amount>
hook.Add("PlayerSay", "GWRP_EconomyChatCommands", function(ply, text)
    local args = string.Explode(" ", text)
    if args[1] == "/dropmoney" then
        local amount = tonumber(args[2])
        if not amount or amount <= 0 then
            GWRP.Notify(ply, "Usage: /dropmoney <amount>", NOTIFY_ERROR)
            return ""
        end

        amount = math.floor(amount)
        if not ply:CanAfford(amount) then
            GWRP.Notify(ply, "You do not have enough money!", NOTIFY_ERROR)
            return ""
        end

        ply:AddMoney(-amount)
        local trace = ply:GetEyeTrace()
        local dropPos = trace.HitPos + trace.HitNormal * 10
        GWRP.Economy.SpawnCashStack(dropPos, amount)
        GWRP.Notify(ply, string.format("You dropped $%d on the ground.", amount), NOTIFY_GENERIC)
        return ""
    end
end)
