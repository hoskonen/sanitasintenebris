-- RainCleans.lua
System.LogAlways("4$ [Sanitas] ✅ Loaded: RainCleans")
SanitasInTenebris.RainCleans = SanitasInTenebris.RainCleans or {}
local RC = SanitasInTenebris.RainCleans

local function RCEnabled()
    return Config and (Config.rainCleansDebug == true or Config.debugPolling == true)
end

-- local throttle so we don’t depend on Utils load order
SanitasInTenebris._rc_rt = SanitasInTenebris._rc_rt or {}
local function RCThrot(key, intervalSec, msg)
    if not RCEnabled() then return end
    if Utils and type(Utils.ThrottledCh) == "function" then
        Utils.ThrottledCh("rain", key, intervalSec, msg)
        return
    end
    local now = System.GetCurrTime()
    local t = SanitasInTenebris._rc_rt
    local nextAt = t[key]
    if not nextAt or now >= nextAt then
        System.LogAlways(tostring(msg))
        t[key] = now + (intervalSec or 5)
    end
end


local progress = 0.0
local henryBodyCleanProgress = 0.0

function SanitasInTenebris.RainCleans.Start()
    if RCEnabled() then
        System.LogAlways("4$ [Sanitas->Start]: RainCleans system started.")
    end
    Script.SetTimer(Config.rainCleans.TickInterval, SanitasInTenebris.RainCleans.Tick)
end

function SanitasInTenebris.RainCleans.Tick()
    Script.SetTimer(Config.rainCleans.TickInterval, SanitasInTenebris.RainCleans.Tick)

    local rain = EnvironmentModule.GetRainIntensity()
    local isIndoors = SanitasInTenebris.IsIndoors
    local rainThreshold = Config.rainCleans.RainIntensityThreshold
    local multiplier = Config.rainCleans.RainIntensityMultiplier
    local requiredProgress = Config.rainCleans.CleaningThreshold

    local logPrefix = "4$ [Sanitas->Tick]:"
    local shouldLog = Config.rainCleansDebug

    if State.lastIsIndoors ~= isIndoors then
        State.lastIsIndoors = isIndoors
        if shouldLog then
            System.LogAlways(logPrefix .. " Indoor state changed: " .. tostring(isIndoors))
        end
    end

    if rain >= rainThreshold and not isIndoors then
        -- 🌧️ Active rain cleaning
        local gain = rain * multiplier
        progress = progress + gain

        if shouldLog then
            RCThrot("rc_tick", 5, string.format(
                "%s Rain Cleaning Tick — rain=%.2f → +%.2f (progress=%.2f)",
                logPrefix, rain, gain, progress))
        end

        if progress >= requiredProgress then
            progress = 0.0
            henryBodyCleanProgress = 0.0

            local cleaningStrength = math.min(rain * 1.5, 1.0)
            if player and player.actor and type(player.actor.WashItems) == "function" then
                player.actor:WashItems(cleaningStrength)
                if shouldLog then
                    System.LogAlways(string.format(
                        "%s Full rain wash triggered with strength %.2f", logPrefix, cleaningStrength))
                end
            end

            Utils.CleanHenryBody(0.3)
        end

        -- Reset passive log state
        State.idleRainCleansLog = false
    elseif progress > 0 then
        -- 💦 Partial clean using leftover progress
        local partialStrength = math.min(progress * 1.5, 1.0)

        if player and player.actor and type(player.actor.WashItems) == "function" then
            player.actor:WashItems(partialStrength)

            -- 👇 Log only when strength changes
            local rounded = math.floor(partialStrength * 100 + 0.5) / 100
            if Config.rainCleansDebug and State.lastPartialWashStrength ~= rounded then
                System.LogAlways(string.format(
                    "%s Partial rain wash triggered with strength %.2f", logPrefix, rounded))
                State.lastPartialWashStrength = rounded
            end
        end

        -- Cap body cleaning at maxAllowed
        local maxAllowed = 0.2
        local remainingClean = maxAllowed - henryBodyCleanProgress
        local bodyClean = math.min(progress * 0.3, remainingClean)

        if bodyClean > 0 then
            Utils.CleanHenryBody(bodyClean)
            henryBodyCleanProgress = henryBodyCleanProgress + bodyClean

            if shouldLog then
                System.LogAlways(string.format(
                    "%s Henry body cleaned by %.2f (partial wash, total=%.2f)",
                    logPrefix, bodyClean, henryBodyCleanProgress))
            end
        end

        progress = 0.0
        State.idleRainCleansLog = false
    elseif shouldLog and not State.idleRainCleansLog then
        -- Suppress duplicate idle logs
        RCThrot("rc_idle", 10, logPrefix .. " Rain stopped / indoors but no progress to apply")
        State.idleRainCleansLog = true
    end
end
