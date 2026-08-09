-- RainCleans.lua
Utils.LogModuleLoaded("RainCleans")

SanitasInTenebris.RainCleans = SanitasInTenebris.RainCleans or {}
local RC = SanitasInTenebris.RainCleans

local progress = 0.0
local henryBodyCleanProgress = 0.0

local function RCEnabled()
    return Utils and Utils.IsLogEnabled and Utils.IsLogEnabled("rain_cleans")
end

local function RCLog(msg)
    if RCEnabled() then Utils.Log(tostring(msg)) end
end

local function RCThrot(key, intervalSec, msg)
    if RCEnabled() then
        Utils.ThrottledCh("rain_cleans", key, intervalSec, tostring(msg))
    end
end

local function IsIndoors()
    if InteriorLogic and InteriorLogic.IsPlayerInInterior then
        local ok, value = pcall(InteriorLogic.IsPlayerInInterior)
        return ok and value == true
    end
    return false
end

function RC.Start()
    RCLog("[RainCleans->Start]: RainCleans system started")
    Script.SetTimer(Config.rainCleans.TickInterval, RC.Tick)
end

function RC.Tick()
    Script.SetTimer(Config.rainCleans.TickInterval, RC.Tick)

    local rain = EnvironmentModule.GetRainIntensity()
    local isIndoors = IsIndoors()
    local rainThreshold = Config.rainCleans.RainIntensityThreshold
    local multiplier = Config.rainCleans.RainIntensityMultiplier
    local requiredProgress = Config.rainCleans.CleaningThreshold
    local player = Utils.GetPlayer()

    if State.lastIsIndoors ~= isIndoors then
        State.lastIsIndoors = isIndoors
        RCLog("[RainCleans->Tick]: Indoor state changed: " .. tostring(isIndoors))
    end

    if rain >= rainThreshold and not isIndoors then
        local gain = rain * multiplier
        progress = progress + gain

        RCThrot("tick", 5, string.format(
            "[RainCleans->Tick]: rain=%.2f gain=%.2f progress=%.2f",
            rain, gain, progress))

        if progress >= requiredProgress then
            progress = 0.0
            henryBodyCleanProgress = 0.0

            local cleaningStrength = math.min(rain * 1.5, 1.0)
            if player and player.actor and type(player.actor.WashItems) == "function" then
                player.actor:WashItems(cleaningStrength)
                RCLog(string.format("[RainCleans->Tick]: Full wash strength %.2f", cleaningStrength))
            end

            Utils.CleanHenryBody(0.3)
        end

        State.idleRainCleansLog = false
    elseif progress > 0 then
        local partialStrength = math.min(progress * 1.5, 1.0)

        if player and player.actor and type(player.actor.WashItems) == "function" then
            player.actor:WashItems(partialStrength)

            local rounded = math.floor(partialStrength * 100 + 0.5) / 100
            if RCEnabled() and State.lastPartialWashStrength ~= rounded then
                Utils.Log(string.format("[RainCleans->Tick]: Partial wash strength %.2f", rounded))
                State.lastPartialWashStrength = rounded
            end
        end

        local maxAllowed = 0.2
        local remainingClean = maxAllowed - henryBodyCleanProgress
        local bodyClean = math.min(progress * 0.3, remainingClean)

        if bodyClean > 0 then
            Utils.CleanHenryBody(bodyClean)
            henryBodyCleanProgress = henryBodyCleanProgress + bodyClean
            RCLog(string.format("[RainCleans->Tick]: Body cleaned %.2f total=%.2f", bodyClean, henryBodyCleanProgress))
        end

        progress = 0.0
        State.idleRainCleansLog = false
    elseif RCEnabled() and not State.idleRainCleansLog then
        RCThrot("idle", 10, "[RainCleans->Tick]: Idle; no rain cleaning progress")
        State.idleRainCleansLog = true
    end
end
