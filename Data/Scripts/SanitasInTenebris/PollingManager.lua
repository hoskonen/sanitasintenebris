System.LogAlways("4$ [Sanitas] ✅ Loaded: PollingManager")

local dbg = (Config and Config.debugPolling) == true
local function LogPoll(msg)
    if dbg then System.LogAlways("4$ [Sanitas] " .. tostring(msg)) end
end

PollingManager = PollingManager or {}
PollingManager._timers = PollingManager._timers or {}

function PollingManager.Register(name, interval, func, runImmediately)
    if PollingManager._timers[name] then
        Script.KillTimer(PollingManager._timers[name])
        PollingManager._timers[name] = nil
        LogPoll("[PollingManager->Register]: Re-registering: " .. tostring(name))
    end

    if runImmediately then
        local ok, err = pcall(func)
        if not ok then
            Utils.Log("[PollingManager->Register]: Immediate call error for '" ..
                name .. "': " .. tostring(err))
        end
    end

    local function wrapped()
        LogPoll("[PollingManager->Register]: Timer fired for " .. tostring(name))
        local ok, err = pcall(func)
        if not ok then Utils.Log("[PollingManager->Register]: Error in '" .. name .. "': " .. tostring(err)) end
        PollingManager._timers[name] = Script.SetTimer(interval, wrapped)
    end

    PollingManager._timers[name] = Script.SetTimer(interval, wrapped)

    LogPoll("[PollingManager->Register]: Registered: " .. name .. " (" .. tostring(interval) .. "ms)")
end

function PollingManager.Stop(name)
    local id = PollingManager._timers[name]
    if id then
        Script.KillTimer(id)
        PollingManager._timers[name] = nil
        LogPoll("[PollingManager->Stop]: Stopped: " .. tostring(name))
    end
end

function PollingManager.StopAll()
    for name, id in pairs(PollingManager._timers) do
        Script.KillTimer(id)
        LogPoll("[PollingManager->Stop]: Stopped: " .. tostring(name))
    end
    PollingManager._timers = {}
end

function PollingManager.SetPollState(state)
    if state == "outdoor_dry" then
        PollingManager.Stop("RainCheck")
        PollingManager.Stop("IndoorPoll")
        PollingManager.Register("OutdoorPoll", 2000, SanitasInTenebris.OutdoorPoll)
    elseif state == "outdoor_rain" then
        PollingManager.Register("OutdoorPoll", 2000, SanitasInTenebris.OutdoorPoll)
        PollingManager.Register("RainCheck", 1000, SanitasInTenebris.CheckRain)
    elseif state == "indoor" then
        PollingManager.Stop("OutdoorPoll")
        PollingManager.Stop("RainCheck")
        PollingManager.Register("IndoorPoll", 3000, SanitasInTenebris.IndoorPoll)
    end
end

return PollingManager
