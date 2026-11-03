--[[
    sh_notifications.lua - On-screen RP Notifications & Audio
--]]

GW.Notifications = GW.Notifications or {}

NOTIFY_GENERIC = 0
NOTIFY_ERROR = 1
NOTIFY_UNDO = 2
NOTIFY_HINT = 3
NOTIFY_CLEANUP = 4

if SERVER then
    function GW.Notify(ply, message, ntype, duration)
        -- Handle both GW:Notify(ply, msg, ...) and GW.Notify(ply, msg, ...)
        if ply == GW then
            ply = message
            message = ntype
            ntype = duration
            duration = 5
        end

        if not IsValid(ply) or not ply:IsPlayer() then return end

        net.Start("GW_Notification")
            net.WriteString(message or "")
            net.WriteUInt(ntype or NOTIFY_GENERIC, 4)
            net.WriteUInt(duration or 5, 8)
        net.Send(ply)
    end

    function GW.NotifyAll(message, ntype, duration)
        if message == GW then
            message = ntype
            ntype = duration
            duration = 5
        end

        net.Start("GW_Notification")
            net.WriteString(message or "")
            net.WriteUInt(ntype or NOTIFY_GENERIC, 4)
            net.WriteUInt(duration or 5, 8)
        net.Broadcast()
    end
else
    net.Receive("GW_Notification", function()
        local msg = net.ReadString()
        local nType = net.ReadUInt(4)
        local dur = net.ReadUInt(8)

        notification.AddLegacy(msg, nType, dur)
        surface.PlaySound("buttons/lightswitch2.wav")
    end)
end
