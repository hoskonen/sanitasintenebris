-- Main.lua
local debugEnabled = Config.mainDebug == true

State.isInitialized = false -- Delay rain logic until ready

SanitasInTenebris = SanitasInTenebris or {}

local manager = Script.ReloadScript("Scripts/SanitasInTenebris/PollingManager.lua")
PollingManager = manager or PollingManager

if debugEnabled then
    Utils.Log("[Main] Main.lua loaded — system initialized")
end

function SanitasInTenebris.StopPoll()
    if debugEnabled then Utils.Log("[Main->StopPoll]: StopPoll() called") end
    PollingManager.StopAll()
end

function SanitasInTenebris.Poll()
    local ok, err = pcall(function()
        if Config.debugEnabled then
            Utils.Log("[Main->Poll]: Poll() started from OnGameplayStarted")
            Utils.Log("[Main->Poll]: Starting Poll()")
        end

        local isIndoors = InteriorLogic.IsPlayerInInterior()
        if Config.debugEnabled then
            if not isIndoors then
                Utils.Log("[Main->Poll]: OUTSIDE: Outdoor polling (rain, fire, etc.) is active")
            else
                Utils.Log("[Main->Poll]: INDOORS: Indoor polling active — rain/fire polling suspended")
            end
        end

        -- Safe polling registration
        Utils.SafePollRegister("RainCheck", Config.pollingInterval, SanitasInTenebris.CheckRain, false)
        Utils.SafePollRegister("OutdoorPoll", Config.outdoorHeatInterval or 2000, SanitasInTenebris.OutdoorPoll, true)
    end)

    if not ok then
        Utils.Log("[Main->Poll]: Poll() crashed: " .. tostring(err))
    end
end

function SanitasInTenebris.RestartAfterLoad()
    if Config.debugMain then
        Utils.Log("[Main->RestartAfterLoad]: RestartAfterLoad() called — evaluating restart conditions")
    end

    State.pollingSuspended = false

    local isIndoors = InteriorLogic.IsPlayerInInterior()
    if isIndoors then
        if Config.debugMain then
            Utils.Log("[Main->RestartAfterLoad]: RestartAfterLoad skipped — player is indoors")
        end
        return
    end


    if Config.debugMain then
        Utils.Log("[Main->RestartAfterLoad]: Player is outdoors — resuming polling systems")
    end

    -- Restart other modules
    if SanitasInTenebris.RainCleans and SanitasInTenebris.RainCleans.Start then
        SanitasInTenebris.RainCleans.Start()
    end

    if SanitasInTenebris.DryingSystem and SanitasInTenebris.DryingSystem.Start then
        SanitasInTenebris.DryingSystem.Start()
    end
end

function SanitasInTenebris.CheckRain()
    if State.pollingSuspended then
        if Config.debugRainTracker then
            Utils.Log("[Main->CheckRain] CheckRain skipped — polling suspended")
        end
    else
        RainTracker.CheckRain()
    end
end

function SanitasInTenebris.OutdoorPoll()
    if State.pollingSuspended then
        if debugEnabled then Utils.Log("[Main->OutdoorPoll]: Skipped — polling suspended") end
        return
    end

    -- Query interior ONCE and reuse the result
    local isInterior = InteriorLogic.IsPlayerInInterior()
    if isInterior then
        if not State._indoorInitDone then
            State.pollingSuspended = true

            -- Arm exit detector immediately so we can resume when the player walks out
            SanitasInTenebris.ScheduleExitInterior()

            local player = Utils.GetPlayer()
            local soul = player and player.soul
            if player and soul then
                local ok, err = pcall(function()
                    InteriorLogic.HandleInteriorState(player, soul)
                end)
                if not ok then
                    Utils.Log("💥 [Main->OutdoorPoll]: Immediate HandleInteriorState error: " .. tostring(err))
                end
            end
        end
        return -- skip roof/fire while indoors
    end

    if debugEnabled and Config.enableLogOnce then
        Utils.LogOnce("drying_skipped_rain", "[Main->OutdoorPoll]: OutdoorPoll running...")
    end

    -- 🔥 Fire detection (only when truly outside)
    HeatDetection.HasNearbyFireSource()

    -- 🏠 Roof detection (only when truly outside)
    local roofed = SanitasInTenebris.RoofDetection.IsUnderRoof()
    State.roofedOutside = roofed
    if Config.debugRoofDetection then
        Utils.Log("[Main->OutdoorPoll]: RoofedOutside = " .. tostring(roofed))
    end

    -- Debounce roof state (prevents thrash at thresholds)
    State._roofPrev = (State._roofPrev == nil) and roofed or State._roofPrev
    State._roofStableSince = State._roofStableSince or System.GetCurrTime()

    local now = System.GetCurrTime()
    if roofed ~= State._roofPrev then
        State._roofPrev = roofed
        State._roofStableSince = now
    end
    local stable = (now - State._roofStableSince) >= 2.0

    -- Fallback shelter when XGen didn't mark interior
    if stable then
        local player = Utils.GetPlayer()
        local soul = player and player.soul
        if soul then
            if roofed and not State.shelteredActive then
                BuffLogic.ApplyShelteredBuff(soul)
            elseif (not roofed) and State.shelteredActive then
                BuffLogic.RemoveShelteredBuff(player, soul)
            end
        end
    end
end

-- 🔒 Single-shot IndoorPoll wrapper (disarms, runs, then re-arms if still indoors)
function SanitasInTenebris.SafeIndoorPoll()
    State._indoorTimerArmed = false -- consume this one-shot

    local ok, err = pcall(SanitasInTenebris.IndoorPoll)
    if not ok then
        Utils.Log("[Main->SafeIndoorPoll] IndoorPoll runtime error: " .. tostring(err))
    end

    -- Re-arm only if we're still in indoor loop
    if State.pollingSuspended or State.wasIndoors == true then
        SanitasInTenebris.ScheduleIndoorPoll()
    end
end

function SanitasInTenebris.IndoorPoll()
    -- no direct Script.SetTimer here; SafeIndoorPoll handles re-arm

    local player = Utils.GetPlayer()
    local soul = player and player.soul
    if not soul then
        if debugEnabled then Utils.Log("[Main->IndoorPoll]: Player or soul not available, skipping") end
        return
    end

    if not State.pollingSuspended then
        if State.lastIndoorPollSuspended ~= false and debugEnabled then
            Utils.Log("[Main->IndoorPoll]: IndoorPoll skipped — polling not suspended")
        end
        State.lastIndoorPollSuspended = false
        return
    end
    State.lastIndoorPollSuspended = true

    if debugEnabled then Utils.Log("[Main->IndoorPoll]: IndoorPoll tick") end

    local isIndoors = InteriorLogic.IsPlayerInInterior()

    -- Debounce
    State._indoorPrev = (State._indoorPrev == nil) and isIndoors or State._indoorPrev
    State._indoorStableSince = State._indoorStableSince or System.GetCurrTime()
    local now = System.GetCurrTime()
    if isIndoors ~= State._indoorPrev then
        State._indoorPrev = isIndoors
        State._indoorStableSince = now
    end
    local indoorStable = (now - State._indoorStableSince) >= 1.5
    if not indoorStable then return end

    local changed = (isIndoors ~= State.wasIndoors)

    if changed then
        if Config.debugIndoor then
            Utils.Log("[Main->IndoorPoll]: Indoor state changed: " ..
                tostring(State.wasIndoors) .. " → " .. tostring(isIndoors))
        end

        if isIndoors then
            BuffLogic.ApplyShelteredBuff(soul)
            -- one-time indoor init
            local ok, err = pcall(function()
                InteriorLogic.HandleInteriorState(player, soul)
            end)
            if not ok then
                Utils.Log("💥 [Main->IndoorPoll]: HandleInteriorState() error: " .. tostring(err))
            end
        else
            BuffLogic.RemoveShelteredBuff(player, soul)
        end

        State.wasIndoors = isIndoors
        if debugEnabled then
            Utils.Log("[Main->IndoorPoll]: Indoors state changed → " .. (isIndoors and "Indoors" or "Outdoors"))
        end
    end

    -- Light work while indoors (optional)
    if isIndoors then
        local okDry, errDry = pcall(function()
            RainTracker.TryToDryOut()
        end)
        if not okDry then
            Utils.Log("💥 [Main->IndoorPoll]: TryToDryOut() error: " .. tostring(errDry))
        end
    end

    -- No explicit reschedule here; SafeIndoorPoll auto re-arms if we are still indoors.
end

function SanitasInTenebris.CheckExitInterior()
    State._exitTimerArmed = false -- consume one-shot

    local player = Utils.GetPlayer()
    local soul = player and player.soul
    if not player then return end

    local stillIndoors = InteriorLogic.IsPlayerInInterior()
    if debugEnabled then
        Utils.Log("[Main->CheckExitInterior]: CheckExitInterior: isNowIndoors = " .. tostring(stillIndoors))
    end

    -- If still indoors → just re-arm ONE timer and bail
    if stillIndoors then
        SanitasInTenebris.ScheduleExitInterior()
        return
    end

    -- Transition: went from indoors → outdoors
    if State.wasIndoors == true then
        if debugEnabled then
            Utils.Log("[Main->CheckExitInterior]: Player exited interior — resuming outdoor polling")
        end

        if soul then BuffLogic.RemoveShelteredBuff(player, soul) end
        BuffLogic.RemoveDryingBuffsOnly()

        local wetness = State.wetnessPercent or 0
        if wetness <= 0 then
            State.warmingActive = false
            State.warmingType = nil
            if debugEnabled then Utils.Log("[Main->CheckExitInterior]: Exited interior while dry — warming reset") end
        end

        -- Resume outdoor systems
        State.pollingSuspended = false
        State._indoorInitDone = false
        State._indoorTimerArmed = false
        State.wasIndoors = false

        -- Restart PollingManager loops cleanly
        SanitasInTenebris.StopPoll()
        SanitasInTenebris.Poll()
    end
end

function SanitasInTenebris.OnGameplayStarted(actionName, eventName, argTable)
    if Config.debugEnabled then
        Utils.Log("[Main->OnGameplayStarted]: OnGameplayStarted received")
    end

    local player = Utils.GetPlayer()
    local soul = player and player.soul

    if not player or not soul then
        Utils.Log("[Main->OnGameplayStarted]: Player or soul missing — aborting startup logic")
        return
    end

    local isIndoors = InteriorLogic.IsPlayerInInterior()
    Utils.Log("📍 [Main->OnGameplayStarted]: Interior state at load: isIndoors = " .. tostring(isIndoors))

    if isIndoors then
        Utils.Log("[Main->OnGameplayStarted]: Player is indoors at load — applying interior logic")
        InteriorLogic.HandleInteriorState(player, soul)
        SanitasInTenebris.StopPoll()
    else
        Utils.Log("[Main->OnGameplayStarted]: Player is outdoors at load — enabling polling systems")

        --SanitasInTenebris.RainCleans.Start()
        --SanitasInTenebris.DryingSystem.Start()
        SanitasInTenebris.RestartAfterLoad()

        -- Delay CheckReEnterInterior
        Script.SetTimer(3000, SanitasInTenebris.CheckReEnterInterior)

        -- Start polling after delay
        Script.SetTimer(3000, function()
            if debugEnabled then
                Utils.Log("[Main->OnGameplayStarted]: Restarting Poll() after save load")
            end
            SanitasInTenebris.Poll()
        end)

        -- 🕒 Delay system initialization until wetness state has had time to populate
        Script.SetTimer(5000, function()
            State.isInitialized = true
            if Config.debugMain then
                Utils.Log("[Main->OnGameplayStarted]: State.isInitialized = true — rain/dry logic enabled")
            end
        end)
    end
end

-- 🔒 Schedule IndoorPoll only if not already armed
function SanitasInTenebris.ScheduleIndoorPoll()
    if State._indoorTimerArmed then return end
    State._indoorTimerArmed = true
    Script.SetTimerForFunction((Config.pollingInterval or 1000), "SanitasInTenebris.SafeIndoorPoll")
end

function SanitasInTenebris.CheckReEnterInterior()
    local isNowIndoors = InteriorLogic.IsPlayerInInterior()

    if isNowIndoors and State.wasIndoors == false then
        -- Transition: went from outdoors → indoors
        if debugEnabled then
            Utils.Log(
                "[Main->ScheduleIndoorPoll]: Player re-entered interior — suspending rain polling and restarting IndoorPoll")
        end

        State.pollingSuspended = true
        SanitasInTenebris.ScheduleExitInterior() -- ← arm exit checker immediately
        SanitasInTenebris.IndoorPoll()

        -- Update transition state
        State.wasIndoors = true
    end

    -- Continue checking periodically
    Script.SetTimer(3000, SanitasInTenebris.CheckReEnterInterior)
end

-- 🔒 Single-shot scheduler for CheckExitInterior (3s cadence)
function SanitasInTenebris.ScheduleExitInterior()
    if State._exitTimerArmed then return end
    State._exitTimerArmed = true
    Script.SetTimerForFunction(3000, "SanitasInTenebris.CheckExitInterior")
end

UIAction.RegisterEventSystemListener(SanitasInTenebris, "System", "OnGameplayStarted", "OnGameplayStarted")

return SanitasInTenebris
