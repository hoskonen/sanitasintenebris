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
        if debugEnabled then
            Utils.Log("[Main->OutdoorPoll]: Skipped — polling suspended")
        end
        return
    end

    if debugEnabled and Config.enableLogOnce then
        Utils.LogOnce("drying_skipped_rain", "[Main->OutdoorPoll]: OutdoorPoll running...")
    end

    -- 🔥 Fire detection
    HeatDetection.HasNearbyFireSource()

    -- 🏠 Roof detection
    local roofed = SanitasInTenebris.RoofDetection.IsUnderRoof()
    State.roofedOutside = roofed

    if Config.debugRoofDetection then
        Utils.Log("[Main->OutdoorPoll]: RoofedOutside = " .. tostring(roofed))
    end
end

function SanitasInTenebris.SafeIndoorPoll()
    local ok, err = pcall(SanitasInTenebris.IndoorPoll)
    if not ok then
        Utils.Log("[Main->SafeIndoorPoll] IndoorPoll runtime error: " .. tostring(err))
    end
end

function SanitasInTenebris.IndoorPoll()
    Script.SetTimer(Config.pollInterval, SanitasInTenebris.SafeIndoorPoll)

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
    local changed = (isIndoors ~= State.wasIndoors)

    if changed then
        if Config.debugIndoor then
            Utils.Log("[Main->IndoorPoll]: Indoor state changed: " ..
                tostring(State.wasIndoors) .. " → " .. tostring(isIndoors))
        end

        if isIndoors then
            BuffLogic.ApplyShelteredBuff(soul)
            State.shelteredActive = true
        else
            BuffLogic.RemoveShelteredBuff(soul)
            State.shelteredActive = false
        end

        State.wasIndoors = isIndoors
    elseif Config.debugIndoor and Config.debugIdleTicks then
        Utils.Log("[Main->IndoorPoll]: IndoorPoll: no change")
    end

    if isIndoors then
        local ok, err = pcall(function()
            InteriorLogic.HandleInteriorState(player, soul)
        end)
        if not ok then
            Utils.Log("💥 [Main->IndoorPoll]: HandleInteriorState() error: " .. tostring(err))
        end

        local okDry, errDry = pcall(function()
            RainTracker.TryToDryOut()
        end)
        if not okDry then
            Utils.Log("💥 [Main->IndoorPoll]: TryToDryOut() error: " .. tostring(errDry))
        end
    end

    if changed then
        local emoji = isIndoors and "Indoors" or "Outdoors"
        Utils.Log("[Main->IndoorPoll]: Indoors state changed → " .. emoji)

        if isIndoors then
            SanitasInTenebris.ScheduleIndoorPoll()
        else
            BuffLogic.RemoveShelteredBuff(player, soul)
        end
    end
end

function SanitasInTenebris.CheckExitInterior()
    local player = Utils.GetPlayer()
    local soul = player and player.soul
    if not player then return end

    local isNowIndoors = InteriorLogic.IsPlayerInInterior()
    if debugEnabled then
        Utils.Log("[Main->CheckExitInterior]: CheckExitInterior: isNowIndoors = " .. tostring(isNowIndoors))
    end

    if not isNowIndoors and State.wasIndoors == true then
        -- Transition: went from indoors → outdoors
        if debugEnabled then
            Utils.Log("[Main->CheckExitInterior]: Player exited interior — resuming rain and fire polling")
        end

        if soul then BuffLogic.RemoveShelteredBuff(player, soul) end
        BuffLogic.RemoveDryingBuffsOnly()

        local wetness = State.wetnessPercent or 0
        if wetness <= 0 then
            State.warmingActive = false
            State.warmingType = nil
            if debugEnabled then Utils.Log("[Main->CheckExitInterior]: Exited interior while dry — warming reset") end
        else
            if debugEnabled then
                Utils.Log(
                    "[Main->CheckExitInterior]: Exited interior while wet — keeping warmingActive")
            end
        end

        -- Resume polling
        State.pollingSuspended = false
        SanitasInTenebris.StopPoll()
        SanitasInTenebris.Poll()

        -- Update transition state
        State.wasIndoors = false
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

function SanitasInTenebris.ScheduleIndoorPoll()
    if debugEnabled then Utils.Log("[Main->ScheduleIndoorPoll]: IndoorPoll scheduled") end
    Script.SetTimer(Config.pollInterval, SanitasInTenebris.IndoorPoll)
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
        SanitasInTenebris.IndoorPoll()

        -- Update transition state
        State.wasIndoors = true
    end

    -- Continue checking periodically
    Script.SetTimer(3000, SanitasInTenebris.CheckReEnterInterior)
end

UIAction.RegisterEventSystemListener(SanitasInTenebris, "System", "OnGameplayStarted", "OnGameplayStarted")

return SanitasInTenebris
