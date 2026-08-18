-- Main.lua
local debugEnabled = Utils.IsLogEnabled("main")

State.isInitialized = false -- Delay rain logic until ready

SanitasInTenebris = SanitasInTenebris or {}

local manager = Script.ReloadScript("Scripts/SanitasInTenebris/PollingManager.lua")
PollingManager = manager or PollingManager

if debugEnabled then
    Utils.Log("[Main] Main.lua loaded - system initialized")
end

SanitasInTenebris._rt = SanitasInTenebris._rt or {}
local function IThrot(key, intervalSec, msg)
    if not (Utils.IsLogEnabled("indoor") or Utils.IsLogEnabled("polling")) then return end
    -- Prefer Utils.ThrottledCh if available
    if Utils and type(Utils.ThrottledCh) == "function" then
        Utils.ThrottledCh("indoor", key, intervalSec, msg)
        return
    end
    -- Fallback: local per-key throttle
    local now = System.GetCurrTime()
    local nextAt = SanitasInTenebris._rt[key]
    if not nextAt or now >= nextAt then
        Utils.Log(msg)
        SanitasInTenebris._rt[key] = now + (intervalSec or 5)
    end
end

function SanitasInTenebris.StopPoll()
    if debugEnabled then Utils.Log("[Main->StopPoll]: StopPoll() called") end
    PollingManager.StopAll()
end

function SanitasInTenebris.Poll()
    local ok, err = pcall(function()
        if Utils.IsLogEnabled("main") then
            Utils.Log("[Main->Poll]: Poll() started from OnGameplayStarted")
            Utils.Log("[Main->Poll]: Starting Poll()")
        end

        local isIndoors = InteriorLogic.IsPlayerInInterior()
        if Utils.IsLogEnabled("main") then
            if not isIndoors then
                Utils.Log("[Main->Poll]: OUTSIDE: Outdoor polling (rain, fire, etc.) is active")
            else
                Utils.Log("[Main->Poll]: INDOORS: Indoor polling active - rain/fire polling suspended")
            end
        end

        if isIndoors then
            PollingManager.SetPollState("indoor")
        else
            PollingManager.SetPollState("outdoor")
        end
    end)

    if not ok then
        Utils.Log("[Main->Poll]: Poll() crashed: " .. tostring(err))
    end
end

function SanitasInTenebris.RestartAfterLoad()
    if Utils.IsLogEnabled("main") then
        Utils.Log("[Main->RestartAfterLoad]: RestartAfterLoad() called - evaluating restart conditions")
    end

    State.pollingSuspended = false

    local isIndoors = InteriorLogic.IsPlayerInInterior()
    if isIndoors then
        if Utils.IsLogEnabled("main") then
            Utils.Log("[Main->RestartAfterLoad]: RestartAfterLoad skipped - player is indoors")
        end
        return
    end


    if Utils.IsLogEnabled("main") then
        Utils.Log("[Main->RestartAfterLoad]: Player is outdoors - resuming polling systems")
    end

    -- Restart other modules
    if SanitasInTenebris.RainCleans and SanitasInTenebris.RainCleans.Start then
        SanitasInTenebris.RainCleans.Start()
    end

    -- Drying is condition-driven; reconciliation and rain/shelter checks will start it when valid.
end

function SanitasInTenebris.CheckRain()
    if State.pollingSuspended then
        Utils.ThrottledLog("polling", "rain_suspended", 10,
            "[Main->CheckRain]: Skipped; polling suspended")
        return
    end

    if State.pollingSuspended then
        if Config.debugRainTracker then
            Utils.Log("[Main->CheckRain] CheckRain skipped - polling suspended")
        end
    else
        RainTracker.CheckRain()
    end
end

function SanitasInTenebris.OutdoorPoll()
    if State.pollingSuspended then
        Utils.ThrottledLog("polling", "outdoor_suspended", 10,
            "[Main->OutdoorPoll]: Skipped; polling suspended")
        return
    end

    if State.pollingSuspended then
        if debugEnabled then Utils.Log("[Main->OutdoorPoll]: Skipped - polling suspended") end
        return
    end

    -- Query interior ONCE and reuse the result
    local isInterior = InteriorLogic.IsPlayerInInterior()
    if isInterior then
        if not State._indoorInitDone then
            State.pollingSuspended = true
            PollingManager.SetPollState("indoor")

            -- Arm exit detector immediately so we can resume when the player walks out
            SanitasInTenebris.ScheduleExitInterior()

            local player = Utils.GetPlayer()
            local soul = player and player.soul
            if player and soul then
                local ok, err = pcall(function()
                    InteriorLogic.HandleInteriorState(player, soul)
                end)
                if not ok then
                    Utils.Log("[Main->OutdoorPoll]: Immediate HandleInteriorState error: " .. tostring(err))
                end
            end
        end
        return -- skip roof/fire while indoors
    end

    if debugEnabled and Config.enableLogOnce then
        Utils.LogOnce("drying_skipped_rain", "[Main->OutdoorPoll]: OutdoorPoll running...")
    end

    -- Fire detection (only when truly outside)
    HeatDetection.HasNearbyFireSource()

    -- Roof detection (only when truly outside)
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
                BuffLogic.ApplyShelteredBuff(soul, "RoofedOutside")
            elseif (not roofed) and State.shelteredActive then
                BuffLogic.RemoveShelteredBuff(player, soul, "RoofedOutsideLost")
            end
        end
    end
end

-- Single-shot IndoorPoll wrapper (disarms, runs, then re-arms if still indoors)
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
            Utils.Log("[Main->IndoorPoll]: IndoorPoll skipped - polling not suspended")
        end
        State.lastIndoorPollSuspended = false
        return
    end
    State.lastIndoorPollSuspended = true

    if Utils.IsLogEnabled("indoor") then
        IThrot("indoor_tick", 5, "[Main->IndoorPoll]: IndoorPoll tick")
    end

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
        if Utils.IsLogEnabled("indoor") then
            Utils.Log("[Main->IndoorPoll]: Indoor state changed: " ..
                tostring(State.wasIndoors) .. " -> " .. tostring(isIndoors))
        end

        if isIndoors then
            BuffLogic.ApplyShelteredBuff(soul, "IndoorPoll")
            -- one-time indoor init
            local ok, err = pcall(function()
                InteriorLogic.HandleInteriorState(player, soul)
            end)
            if not ok then
                Utils.Log("[Main->IndoorPoll]: HandleInteriorState() error: " .. tostring(err))
            end
        else
            BuffLogic.RemoveShelteredBuff(player, soul, "IndoorPollExit")
        end

        State.wasIndoors = isIndoors
        if debugEnabled then
            Utils.Log("[Main->IndoorPoll]: Indoors state changed -> " .. (isIndoors and "Indoors" or "Outdoors"))
        end
    end

    -- Guarantee Sheltered is applied while indoors even if no transition was detected
    if isIndoors and not State.shelteredActive then
        BuffLogic.ApplyShelteredBuff(soul, "Indoors")
    end

    -- Light work while indoors (optional)
    if isIndoors then
        local okDry, errDry = pcall(function()
            RainTracker.TryToDryOut()
        end)
        if not okDry then
            Utils.Log("[Main->IndoorPoll]: TryToDryOut() error: " .. tostring(errDry))
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

    -- If still indoors, just re-arm ONE timer and bail
    if stillIndoors then
        SanitasInTenebris.ScheduleExitInterior()
        return
    end

    -- Transition: went from indoors to outdoors
    if State.wasIndoors == true then
        if debugEnabled then
            Utils.Log("[Main->CheckExitInterior]: Player exited interior - resuming outdoor polling")
        end

        if soul then BuffLogic.RemoveShelteredBuff(player, soul, "ExitInterior") end
        BuffLogic.RemoveDryingBuffsOnly()

        local wetness = State.wetnessPercent or 0
        if wetness <= 0 then
            State.warmingActive = false
            State.warmingType = nil
            if debugEnabled then Utils.Log("[Main->CheckExitInterior]: Exited interior while dry - warming reset") end
        end

        -- Resume outdoor systems
        State.pollingSuspended = false
        State._indoorInitDone = false
        State._indoorTimerArmed = false
        State.wasIndoors = false

        PollingManager.SetPollState("outdoor")
    end
end

function SanitasInTenebris.ReconcileBuffState(reason, attempt)
    local cfg = Config and Config.reconcile or {}
    if cfg.enabled == false then return false end

    attempt = attempt or 1
    reason = reason or "manual"

    local player = Utils.GetPlayer()
    local soul = player and player.soul
    if not player or not soul then
        local maxRetries = tonumber(cfg.maxRetries) or 0
        if attempt <= maxRetries then
            Utils.LogIf("reconcile", "[Main->ReconcileBuffState]: player/soul missing; retry " ..
                tostring(attempt) .. "/" .. tostring(maxRetries))
            Script.SetTimer(tonumber(cfg.retryDelayMs) or 1000, function()
                SanitasInTenebris.ReconcileBuffState(reason, attempt + 1)
            end)
        else
            Utils.Log("[Main->ReconcileBuffState]: player/soul missing; reconciliation abandoned")
        end
        return false
    end

    local wetness = tonumber(State.wetnessPercent or 0) or 0
    local wetnessPolicy = cfg.wetnessPolicy or "state"

    if SanitasInTenebris.DryingSystem and SanitasInTenebris.DryingSystem.Stop then
        SanitasInTenebris.DryingSystem.Stop("reconcile")
    end

    local _, removedBuffs = BuffLogic.RemoveSanitasRuntimeBuffs(soul, {
        shelter = true,
        drying = true,
        wetness = wetnessPolicy == "state",
    })

    if wetnessPolicy == "state" and cfg.recoverWetnessFromBuff ~= false and removedBuffs then
        local recoveredTier = 0
        if (removedBuffs.wetnessTier3 or 0) > 0 then
            recoveredTier = 3
        elseif (removedBuffs.wetnessTier2 or 0) > 0 then
            recoveredTier = 2
        elseif (removedBuffs.wetnessTier1 or 0) > 0 then
            recoveredTier = 1
        end

        local recovered = nil
        local values = cfg.recoveredWetnessPercentByTier or {}
        if recoveredTier == 3 then
            recovered = tonumber(values.tier3)
                or tonumber(Config.wetnessThresholds and Config.wetnessThresholds.tier3 and Config.wetnessThresholds.tier3.enter)
        elseif recoveredTier == 2 then
            recovered = tonumber(values.tier2)
                or tonumber(Config.wetnessThresholds and Config.wetnessThresholds.tier2 and Config.wetnessThresholds.tier2.enter)
        elseif recoveredTier == 1 then
            recovered = tonumber(values.tier1)
                or tonumber(Config.wetnessThresholds and Config.wetnessThresholds.tier1 and Config.wetnessThresholds.tier1.enter)
        end

        if recovered and recovered > wetness then
            Utils.LogIf("reconcile", string.format(
                "[Main->ReconcileBuffState]: recovered wetness from persisted tier %d %.2f -> %.2f",
                recoveredTier, wetness, recovered))
            wetness = recovered
        end
    end

    State.wetnessPercent = wetness
    State.wetnessLevel = nil
    State._lastDryingShelterSeenAt = nil
    State._lastFireSeenAt = nil

    local isIndoors, roofed, sheltered = false, false, false
    if RainTracker and RainTracker.GetShelterFlags then
        local okShelter, v1, v2, v3 = pcall(RainTracker.GetShelterFlags)
        if okShelter then
            isIndoors, roofed, sheltered = v1 == true, v2 == true, v3 == true
        end
    elseif InteriorLogic and InteriorLogic.IsPlayerInInterior then
        local okIndoor, value = pcall(InteriorLogic.IsPlayerInInterior)
        isIndoors = okIndoor and value == true
        sheltered = isIndoors
    end

    if sheltered then
        local delay = (Config.shelter and Config.shelter.applyDelaySec) or 0
        State._shelterCandidateAt = System.GetCurrTime() - delay
        BuffLogic.ApplyShelteredBuff(soul, isIndoors and "ReconcileIndoors" or "ReconcileRoofed")
    end

    if wetnessPolicy == "state" and wetness > 0 and RainTracker and RainTracker.RefreshWetnessBuffTier then
        RainTracker.RefreshWetnessBuffTier()
    end

    if RainTracker and RainTracker.TryToDryOut then
        pcall(RainTracker.TryToDryOut)
    end

    Utils.LogIf("reconcile", string.format(
        "[Main->ReconcileBuffState]: reason=%s wetness=%.2f policy=%s indoors=%s roofed=%s sheltered=%s removedWetness=%s/%s/%s",
        tostring(reason), wetness, tostring(wetnessPolicy), tostring(isIndoors), tostring(roofed), tostring(sheltered),
        tostring(removedBuffs and removedBuffs.wetnessTier1 or 0),
        tostring(removedBuffs and removedBuffs.wetnessTier2 or 0),
        tostring(removedBuffs and removedBuffs.wetnessTier3 or 0)))

    return true
end

function SanitasInTenebris.OnGameplayStarted(actionName, eventName, argTable)
    if Utils.IsLogEnabled("main") then
        Utils.Log("[Main->OnGameplayStarted]: OnGameplayStarted received")
    end

    local player = Utils.GetPlayer()
    local soul = player and player.soul

    if not player or not soul then
        local cfg = Config and Config.startup or {}
        local maxRetries = tonumber(cfg.maxRetries) or 0
        local attempt = tonumber(State._startupRetryAttempt or 0) + 1
        State._startupRetryAttempt = attempt

        if attempt <= maxRetries then
            Utils.LogIf("reconcile", "[Main->OnGameplayStarted]: player/soul missing; retry " ..
                tostring(attempt) .. "/" .. tostring(maxRetries))
            Script.SetTimer(tonumber(cfg.retryDelayMs) or 1000, function()
                SanitasInTenebris.OnGameplayStarted(actionName, eventName, argTable)
            end)
        else
            Utils.Log("[Main->OnGameplayStarted]: player/soul missing; startup abandoned")
        end
        return
    end
    State._startupRetryAttempt = nil

    -- clear fire sense cache so detection doesn't carry across loads
    State._fireSense = { active = false, pos = 0, neg = 0, strength = 0.0 }

    local isIndoors = InteriorLogic.IsPlayerInInterior()
    if Config.mainDebug then
        Utils.Log("[Main->OnGameplayStarted]: Interior state at load: isIndoors = " .. tostring(isIndoors))
    end

    if isIndoors then
        if Config.mainDebug then
            Utils.Log("[Main->OnGameplayStarted]: Player is indoors at load - applying interior logic")
        end
        InteriorLogic.HandleInteriorState(player, soul)
        PollingManager.SetPollState("indoor")

        Script.SetTimer(5000, function()
            State.isInitialized = true
            SanitasInTenebris.ReconcileBuffState("startup indoors")
            if Utils.IsLogEnabled("main") then
                Utils.Log("[Main->OnGameplayStarted]: State.isInitialized = true (indoors load)")
            end
        end)
    else
        if Config.mainDebug then
            Utils.Log("[Main->OnGameplayStarted]: Player is outdoors at load - enabling polling systems")
        end

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

        -- Delay system initialization until wetness state has had time to populate
        Script.SetTimer(5000, function()
            State.isInitialized = true
            SanitasInTenebris.ReconcileBuffState("startup outdoors")
            if Utils.IsLogEnabled("main") then
                Utils.Log("[Main->OnGameplayStarted]: State.isInitialized = true - rain/dry logic enabled")
            end
        end)
    end
end

-- Schedule IndoorPoll only if not already armed
function SanitasInTenebris.ScheduleIndoorPoll()
    if State._indoorTimerArmed then return end
    State._indoorTimerArmed = true
    Script.SetTimerForFunction((Config.pollingInterval or 1000), "SanitasInTenebris.SafeIndoorPoll")
end

function SanitasInTenebris.CheckReEnterInterior()
    local isNowIndoors = InteriorLogic.IsPlayerInInterior()

    if isNowIndoors and State.wasIndoors == false and State.pollingSuspended ~= true then
        -- Transition: went from outdoors to indoors
        if debugEnabled then
            Utils.Log(
                "[Main->ScheduleIndoorPoll]: Player re-entered interior - suspending rain polling and restarting IndoorPoll")
        end

        State.pollingSuspended = true
        PollingManager.SetPollState("indoor")

        -- NEW: apply Sheltered immediately (idempotent on engine side)
        local player           = Utils.GetPlayer()
        local soul             = player and player.soul
        if soul then
            BuffLogic.ApplyShelteredBuff(soul, "Indoors")
        end

        -- Arm exit checker so we can resume cleanly when stepping back outside
        SanitasInTenebris.ScheduleExitInterior()

        -- Kick first indoor tick
        SanitasInTenebris.IndoorPoll()
        SanitasInTenebris.ScheduleIndoorPoll()
    end


    -- Continue checking periodically
    Script.SetTimer(3000, SanitasInTenebris.CheckReEnterInterior)
end

-- Single-shot scheduler for CheckExitInterior (3s cadence)
function SanitasInTenebris.ScheduleExitInterior()
    if State._exitTimerArmed then return end
    State._exitTimerArmed = true
    Script.SetTimerForFunction(3000, "SanitasInTenebris.CheckExitInterior")
end

UIAction.RegisterEventSystemListener(SanitasInTenebris, "System", "OnGameplayStarted", "OnGameplayStarted")

return SanitasInTenebris
