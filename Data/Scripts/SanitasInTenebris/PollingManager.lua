System.LogAlways("4$ [Sanitas] ✅ Loaded: PollingManager")

PollingManager = PollingManager or {}
PollingManager._timers = PollingManager._timers or {}

local debug = Config.debugPolling == true

function PollingManager.Register(name, interval, func, runImmediately)
    if PollingManager._timers[name] then
        Script.KillTimer(PollingManager._timers[name])
        PollingManager._timers[name] = nil
        if debug then Utils.Log("[PollingManager->Register]: Re-registering: " .. name) end
    end

    if runImmediately then
        local ok, err = pcall(func)
        if not ok then
            Utils.Log("[PollingManager->Register]: Immediate call error for '" ..
                name .. "': " .. tostring(err))
        end
    end

    local function wrapped()
        if debug then Utils.Log("[PollingManager->Register]: Timer fired for " .. name) end
        local ok, err = pcall(func)
        if not ok then Utils.Log("[PollingManager->Register]: Error in '" .. name .. "': " .. tostring(err)) end
        PollingManager._timers[name] = Script.SetTimer(interval, wrapped)
    end

    PollingManager._timers[name] = Script.SetTimer(interval, wrapped)

    if debug then Utils.Log("[PollingManager->Register]: Registered: " .. name .. " (" .. tostring(interval) .. "ms)") end
end

function PollingManager.Stop(name)
    local id = PollingManager._timers[name]
    if id then
        Script.KillTimer(id)
        PollingManager._timers[name] = nil
        if debug then Utils.Log("[PollingManager->Stop]: Stopped: " .. name) end
    end
end

function PollingManager.StopAll()
    for name, id in pairs(PollingManager._timers) do
        Script.KillTimer(id)
        if debug then Utils.Log("[PollingManager->Stop]: Stopped: " .. name) end
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
