-- State.lua
Utils.LogModuleLoaded("State")

State = State or {}

local raw = rawget(_G, "State") or {}

raw.shelteredActive = raw.shelteredActive or false
raw.retryPending = raw.retryPending or false
raw.pollingSuspended = raw.pollingSuspended or false
raw.lastIndoorStatus = raw.lastIndoorStatus or nil
raw.lastRainLevel = raw.lastRainLevel or "none"
raw.wetnessPercent = raw.wetnessPercent or 0
raw.wetnessLevel = raw.wetnessLevel or nil
raw.lastRainEndTime = raw.lastRainEndTime or 0
raw.interiorDetected = raw.interiorDetected or false
raw.environmentScoreIndoors = raw.environmentScoreIndoors or false
raw.lastHeatPollingSuspendedState = raw.lastHeatPollingSuspendedState == true
raw.buffShelteredApplied = raw.buffShelteredApplied or false
raw.lastRainTickLog = raw.lastRainTickLog or 0
raw.wasIndoors = raw.wasIndoors or false
raw.warmingType = raw.warmingType or nil
raw.warmingActive = raw.warmingActive or false
raw.wasDryLogged = raw.wasDryLogged or false
raw.normalDryingActive = raw.normalDryingActive or false
raw.rainStoppedAt = raw.rainStoppedAt or nil
raw.isInitialized = raw.isInitialized or false
raw.lastRainValue = raw.lastRainValue or nil

local originalState = raw

State = setmetatable({}, {
    __index = originalState,
    __newindex = function(_, k, v)
        if k == "shelteredActive" and Utils.IsLogEnabled("buff") then
            Utils.Log("[State]: shelteredActive = " .. tostring(v))
            if Config.logging and Config.logging.stateTraceback == true and debug and debug.traceback then
                Utils.Log("[State]: shelteredActive trace:\n" .. debug.traceback("", 2))
            end
        elseif (k == "warmingType" or k == "warmingActive") and Utils.IsLogEnabled("drying") then
            Utils.ThrottledCh("state", tostring(k), 2, "[State]: " .. tostring(k) .. " = " .. tostring(v))
        end

        rawset(originalState, k, v)
    end
})

SanitasInTenebris = SanitasInTenebris or {}
SanitasInTenebris.State = State
