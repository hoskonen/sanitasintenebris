if Utils and Utils.LogModuleLoaded then
    Utils.LogModuleLoaded("PollingManager")
end

local dbg = (Config and Config.debugPolling) == true
local function LogPoll(msg)
    if dbg then System.LogAlways("4$ [Sanitas] " .. tostring(msg)) end
end

local function LogPollTick(msg)
    if Config and Config.debugPollTicks == true then
        System.LogAlways("4$ [Sanitas] " .. tostring(msg))
    end
end

PollingManager = PollingManager or {}
PollingManager._timers = PollingManager._timers or {}
PollingManager._polls = PollingManager._polls or {}
PollingManager._generation = PollingManager._generation or 0

local function Now()
    if System and System.GetCurrTime then
        return System.GetCurrTime()
    end
    return 0
end

local function LogAlways(msg)
    if Utils and Utils.Log then
        Utils.Log(msg)
    elseif System and System.LogAlways then
        System.LogAlways("4$ [Sanitas] " .. tostring(msg))
    end
end

local function NextGeneration()
    PollingManager._generation = (PollingManager._generation or 0) + 1
    return PollingManager._generation
end

local function GetPoll(name)
    return PollingManager._polls and PollingManager._polls[name]
end

local function IsCurrent(name, generation)
    local poll = GetPoll(name)
    return poll and poll.active == true and poll.generation == generation
end

local function KillTimer(id)
    if id then
        Script.KillTimer(id)
    end
end

function PollingManager.Register(name, interval, func, runImmediately)
    if type(name) ~= "string" or name == "" then
        LogAlways("[PollingManager->Register]: Invalid poll name: " .. tostring(name))
        return
    end

    if type(func) ~= "function" then
        LogAlways("[PollingManager->Register]: Invalid callback for '" .. tostring(name) .. "'")
        return
    end

    interval = tonumber(interval) or 1000

    local previous = GetPoll(name)
    if previous then
        previous.active = false
        previous.generation = NextGeneration()
        KillTimer(previous.timerId)
        PollingManager._timers[name] = nil
        previous.timerId = nil
        previous.lastResult = "replaced"
        LogPoll("[PollingManager->Register]: Re-registering: " .. tostring(name))
    elseif PollingManager._timers[name] then
        KillTimer(PollingManager._timers[name])
        PollingManager._timers[name] = nil
        LogPoll("[PollingManager->Register]: Clearing orphan timer: " .. tostring(name))
    end

    local generation = NextGeneration()
    local poll = {
        name = name,
        interval = interval,
        func = func,
        active = true,
        generation = generation,
        timerId = nil,
        tickCount = 0,
        lastTickAt = nil,
        lastSuccessAt = nil,
        lastErrorAt = nil,
        lastError = nil,
        lastResult = "registered",
        registeredAt = Now()
    }
    PollingManager._polls[name] = poll

    local function recordResult(ok, err)
        poll.lastTickAt = Now()
        if ok then
            poll.lastSuccessAt = poll.lastTickAt
            poll.lastError = nil
            poll.lastResult = "ok"
        else
            poll.lastErrorAt = poll.lastTickAt
            poll.lastError = tostring(err)
            poll.lastResult = "error"
        end
    end

    local function wrapped()
        if not IsCurrent(name, generation) then
            LogPollTick("[PollingManager->Register]: Ignoring stale timer for " .. tostring(name))
            return
        end

        LogPollTick("[PollingManager->Register]: Timer fired for " .. tostring(name))
        poll.tickCount = (poll.tickCount or 0) + 1
        poll.timerId = nil
        PollingManager._timers[name] = nil

        local ok, err = pcall(func)
        recordResult(ok, err)
        if not ok then
            LogAlways("[PollingManager->Register]: Error in '" .. name .. "': " .. tostring(err))
        end

        if not IsCurrent(name, generation) then
            LogPoll("[PollingManager->Register]: Not rearming stopped/replaced poll " .. tostring(name))
            return
        end

        local timerId = Script.SetTimer(interval, wrapped)
        if IsCurrent(name, generation) then
            poll.timerId = timerId
            PollingManager._timers[name] = timerId
        else
            KillTimer(timerId)
            LogPoll("[PollingManager->Register]: Killed timer created by stale poll " .. tostring(name))
        end
    end

    if runImmediately then
        local ok, err = pcall(func)
        recordResult(ok, err)
        if not ok then
            LogAlways("[PollingManager->Register]: Immediate call error for '" ..
                name .. "': " .. tostring(err))
        end

        if not IsCurrent(name, generation) then
            LogPoll("[PollingManager->Register]: Immediate call stopped/replaced '" .. name .. "'; not arming timer")
            return
        end
    end

    local timerId = Script.SetTimer(interval, wrapped)
    if IsCurrent(name, generation) then
        poll.timerId = timerId
        PollingManager._timers[name] = timerId
    else
        KillTimer(timerId)
    end

    LogPoll("[PollingManager->Register]: Registered: " .. name .. " (" .. tostring(interval) .. "ms)")
end

function PollingManager.Stop(name)
    if type(name) ~= "string" or name == "" then
        LogAlways("[PollingManager->Stop]: Invalid poll name: " .. tostring(name))
        return
    end

    local poll = GetPoll(name)
    local id = (poll and poll.timerId) or PollingManager._timers[name]

    if poll then
        poll.active = false
        poll.generation = NextGeneration()
        poll.timerId = nil
        poll.lastResult = "stopped"
    end

    if id then KillTimer(id) end
    PollingManager._timers[name] = nil
    LogPoll("[PollingManager->Stop]: Stopped: " .. tostring(name))
end

function PollingManager.StopAll()
    for name, poll in pairs(PollingManager._polls or {}) do
        poll.active = false
        poll.generation = NextGeneration()
        if poll.timerId then
            KillTimer(poll.timerId)
        end
        poll.timerId = nil
        poll.lastResult = "stopped"
        PollingManager._timers[name] = nil
        LogPoll("[PollingManager->Stop]: Stopped: " .. tostring(name))
    end

    for name, id in pairs(PollingManager._timers or {}) do
        KillTimer(id)
        LogPoll("[PollingManager->Stop]: Stopped orphan timer: " .. tostring(name))
    end

    PollingManager._timers = {}
end

function PollingManager.GetHealth()
    local health = {}
    for name, poll in pairs(PollingManager._polls or {}) do
        health[name] = {
            active = poll.active == true,
            interval = poll.interval,
            generation = poll.generation,
            timerId = poll.timerId,
            tickCount = poll.tickCount or 0,
            lastTickAt = poll.lastTickAt,
            lastSuccessAt = poll.lastSuccessAt,
            lastErrorAt = poll.lastErrorAt,
            lastError = poll.lastError,
            lastResult = poll.lastResult
        }
    end
    return health
end

function PollingManager.DumpHealth()
    local lines = { "[PollingManager->DumpHealth]: poll health" }
    local count = 0

    for name, poll in pairs(PollingManager._polls or {}) do
        count = count + 1
        lines[#lines + 1] = string.format(
            "  %s active=%s gen=%s interval=%sms timer=%s ticks=%s result=%s lastTick=%s lastOk=%s lastErr=%s",
            tostring(name),
            tostring(poll.active == true),
            tostring(poll.generation),
            tostring(poll.interval),
            tostring(poll.timerId),
            tostring(poll.tickCount or 0),
            tostring(poll.lastResult),
            tostring(poll.lastTickAt),
            tostring(poll.lastSuccessAt),
            tostring(poll.lastErrorAt)
        )
        if poll.lastError then
            lines[#lines + 1] = "    error=" .. tostring(poll.lastError)
        end
    end

    if count == 0 then
        lines[#lines + 1] = "  no polls registered"
    end

    local text = table.concat(lines, "\n")
    LogAlways(text)
    return text
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
