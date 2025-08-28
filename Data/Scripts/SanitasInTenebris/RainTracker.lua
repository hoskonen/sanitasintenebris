-- 🌧 RainTracker.lua
System.LogAlways("4$ [Sanitas] ✅ Loaded: RainTracker")

RainTracker = {}

local debugEnabled = Config.debugRainTracker == true
local logPrefix = "4$ [Sanitas] 🌧"

local function RLog(msg)
    if Config and Config.debugRainTracker == true then
        Utils.Log(tostring(msg))
    end
end

-- --- helpers: keep behavior identical, just centralize reads

-- rain value (number, never nil)
function RainTracker.GetRainSafe()
    local r = 0
    if State and State.lastRainAmount ~= nil then
        r = tonumber(State.lastRainAmount) or 0
    else
        local ok, rv = pcall(function()
            return (EnvironmentModule and EnvironmentModule.GetRainIntensity and EnvironmentModule.GetRainIntensity()) or
                0
        end)
        r = (ok and tonumber(rv)) or 0
    end
    return r
end

-- XGen interior first; then cache from OutdoorPoll; then ray fallback
function RainTracker.GetShelterFlags()
    local isIndoors = (InteriorLogic and InteriorLogic.IsPlayerInInterior and InteriorLogic.IsPlayerInInterior()) == true
    local roofed    = false
    if not isIndoors then
        roofed = (State and State.roofedOutside) or false
        if roofed == false and RoofDetection and RoofDetection.IsUnderRoof then
            local ok, rf = pcall(RoofDetection.IsUnderRoof, Config and Config.roofRayMaxDistance)
            roofed = ok and (rf == true)
        end
    end
    local isSheltered = isIndoors or roofed
    return isIndoors, roofed, isSheltered
end

-- run drying if (not raining) OR (raining but sheltered)
function RainTracker.CanDryNow(rain, isSheltered)
    return (rain <= 0) or (isSheltered == true)
end

-- Local throttled logger with safe fallback (no Utils dependency required)
RainTracker._rt = RainTracker._rt or {}
local function RThrot(key, intervalSec, msg)
    -- respect the rain tracker flag
    if not (Config and Config.debugRainTracker == true) then return end

    -- prefer Utils.ThrottledCh if available
    if Utils and type(Utils.ThrottledCh) == "function" then
        Utils.ThrottledCh("rain", key, intervalSec, tostring(msg))
        return
    end

    -- fallback: simple per-key throttle
    local now = System.GetCurrTime()
    local nextAt = RainTracker._rt[key]
    if not nextAt or now >= nextAt then
        Utils.Log(tostring(msg))
        RainTracker._rt[key] = now + (intervalSec or 5)
    end
end

function RainTracker.RefreshWetnessBuffTier()
    if not State.isInitialized then
        if Config.debugRainTracker then
            Utils.Log("⏳ [RainTracker->RefreshWetnessBuffTier]: Skipping — system not initialized")
        end
        return
    end

    local soul = Utils.GetPlayer().soul
    if not soul then return end

    -- Get thresholds from config
    local t = Config.wetnessThresholds
    if not t or not t.tier1 or not t.tier2 or not t.tier3 then
        System.LogAlways(
            "⚠️ [RainTracker->RefreshWetnessBuffTier]: Wetness thresholds missing or invalid — skipping buff check")
        return
    end

    local t1, t2, t3 = t.tier1, t.tier2, t.tier3
    local wetness = State.wetnessPercent or 0
    local previous = State.wetnessLevel or 0
    local tier = previous

    if Config.debugBuffLogic then
        Utils.Log(string.format(
            "🧪 [RainTracker->RefreshWetnessBuffTier]: Thresholds → t1.enter = %.2f / t1.exit = %.2f", t1.enter, t1
            .exit))
        Utils.Log(string.format("💧 [RainTracker->RefreshWetnessBuffTier]: Current wetness: %.2f%% | Previous tier: %s",
            wetness,
            tostring(previous)))
    end

    -- ⛔ Stop all tier logic if we're already below lowest threshold
    if wetness < t1.exit then
        if previous > 0 then
            Utils.Log(
                "💧 [RainTracker->RefreshWetnessBuffTier]: Wetness dropped below lowest threshold — removing wetness buff")
            BuffLogic.RemoveWetnessBuffs()
            State.wetnessLevel = 0
        else
            if Config.debugBuffLogic then
                Utils.Log(
                    "💧 [RainTracker->RefreshWetnessBuffTier]: Below tier 1 threshold — not applying wetness buff")
            end
        end
        return
    end


    -- ✅ Hysteresis-based tier transitions (only if wet enough)
    if previous == nil or previous == 0 then
        if wetness >= t1.enter then
            tier = 1
        end
    elseif previous == 1 then
        if wetness >= t2.enter then
            tier = 2
        elseif wetness < t1.exit then
            tier = 0
        else
            tier = 1
        end
    elseif previous == 2 then
        if wetness >= t3.enter then
            tier = 3
        elseif wetness < t2.exit then
            tier = 1
        else
            tier = 2
        end
    elseif previous == 3 then
        if wetness < t3.exit then
            tier = 2
        else
            tier = 3
        end
    end

    -- ✅ Apply buff if tier changed
    if tier ~= previous then
        RLog("💧 [RainTracker]: Wetness tier changed: " .. tostring(previous) .. " → " .. tostring(tier))

        BuffLogic.RemoveWetnessBuffs()
        if tier == 1 then
            soul:AddBuff(Config.buffs.buff_wetness_rain_mild)
        elseif tier == 2 then
            soul:AddBuff(Config.buffs.buff_wetness_rain_moderate)
        elseif tier == 3 then
            soul:AddBuff(Config.buffs.buff_wetness_rain_severe)
        end
        State.wetnessLevel = tier
    else
        if Config.debugBuffLogic then Utils.Log("♻️ [RainTracker->RefreshWetnessBuffTier]: Wetness tier unchanged") end
    end

    -- ✅ Check if drying system should start
    RainTracker.TryStartDryingSystem()
end

function RainTracker.TryStartDryingSystem()
    if State.warmingActive then
        Utils.Log("🚫 [RainTracker->TryStartDryingSystem]: Already active — skipping re-schedule")
        return
    end

    local wetness = State.wetnessPercent or 0
    local isOutside = not InteriorLogic.IsPlayerInInterior()
    local rain = 0
    local okRain, rv = pcall(function()
        return (EnvironmentModule and EnvironmentModule.GetRainIntensity and EnvironmentModule.GetRainIntensity()) or 0
    end)
    if okRain and type(rv) == "number" then rain = rv end

    -- Drying only applies if we're wet
    if wetness <= 0 then return end

    local canDry = (not isOutside) or (isOutside and rain == 0)

    if canDry and not State.warmingActive then
        RLog("🌬️ [RainTracker->TryStartDryingSystem]: Conditions OK — starting drying system")
        State.warmingActive = true
        Script.SetTimer(Config.drying.tickInterval or 5000, SanitasInTenebris.DryingSystem.Tick)
    end
end

function RainTracker.CheckRain()
    RThrot("checkrain_running", 5, "📡 [RainTracker->CheckRain]: Running...")

    local ok, err = pcall(function()
        if State.pollingSuspended then
            if debugEnabled then Utils.Log("⏸️ [RainTracker->CheckRain]: Rain check skipped — polling suspended") end
            return
        end

        local rain = 0
        local okRain, rv = pcall(function()
            return (EnvironmentModule and EnvironmentModule.GetRainIntensity and EnvironmentModule.GetRainIntensity()) or
                0
        end)
        if okRain and type(rv) == "number" then rain = rv end
        local level = (rain >= 0.6 and "heavy") or (rain >= 0.2 and "light") or "none"
        local isOutside = not InteriorLogic.IsPlayerInInterior()
        local now = System.GetCurrTime()

        -- Skip rain wetness when roofed but outdoors
        local isIndoors = InteriorLogic and InteriorLogic.IsPlayerInInterior and InteriorLogic.IsPlayerInInterior()
        local roofed = false

        if not isIndoors then
            -- Prefer the value computed by OutdoorPoll (cheap)
            roofed = (State and State.roofedOutside) or false

            -- Fallback to direct ray if we don't have a cached state
            if not roofed and RoofDetection and RoofDetection.IsUnderRoof then
                local ok, rf = pcall(RoofDetection.IsUnderRoof, Config.roofRayMaxDistance)
                roofed = ok and (rf == true)
            end
        end

        if roofed then
            -- throttle this debug line; replace if you use a different helper
            if Config and Config.debugRainTracker == true then
                if not RainTracker._rt then RainTracker._rt = {} end
                local now = System.GetCurrTime()
                if (RainTracker._rt.roof or 0) <= now then
                    Utils.Log("⛱️ [RainTracker->CheckRain]: Roofed outside — suppressing rain wetness")
                    RainTracker._rt.roof = now + 5
                end
            end

            local _ok, _err = pcall(RainTracker.TryToDryOut)
            return -- do not add wetness this tick
        end

        -- if unsheltered & raining, proactively clear drying UI
        if (rain > 0) then
            local isIndoors = InteriorLogic and InteriorLogic.IsPlayerInInterior and InteriorLogic.IsPlayerInInterior()
            local roofed    = (State and State.roofedOutside) or false
            if (not isIndoors) and (not roofed) then
                local player = Utils.GetPlayer()
                local soul   = player and player.soul
                if soul and RainTracker.UpdateDryingBuffs then
                    -- indoorish=false, nearFire=false → UpdateDryingBuffs will remove any drying buff
                    pcall(RainTracker.UpdateDryingBuffs, false, false, soul)
                end
            end
        end

        if level ~= "none" and isOutside then
            local wetness = State.wetnessPercent or 0
            local gainBase = 0.1 + (rain ^ 1.2) * 0.9
            local gainModifier = math.max(0.3, 1 - (wetness / 100) ^ 1.3)
            local adjustedGain = gainBase * gainModifier * (Config.rainWetnessGain or 1.0)

            State.wetnessPercent = math.min(100, wetness + adjustedGain)

            if debugEnabled then
                System.LogAlways(string.format(
                    "%s [RainTracker->CheckRain]: Rain Tick — rain=%.2f → +%.2f (wetness=%.2f%%)",
                    logPrefix, rain, adjustedGain, State.wetnessPercent or 0))
                State.lastRainTickLog = now
            end

            RainTracker.RefreshWetnessBuffTier()
        end

        -- ▼ Compute stop threshold from nested config
        local stopThresh = (Config.rain and Config.rain.dryingThreshold) or 0.1

        -- ▼ If we just crossed from >= stopThresh to < stopThresh, mark the time
        if rain < stopThresh and (State.lastRainAmount or 1) >= stopThresh then
            State.rainStoppedAt = now
            if debugEnabled then
                Utils.Log("[RainTracker->CheckRain] Rain dropped below drying threshold — setting rainStoppedAt = " ..
                    now)
            end
        end

        -- Always update lastRainAmount for threshold comparison
        State.lastRainAmount = rain

        if level == "none" and State.lastRainLevel ~= "none" then
            State.lastRainEndTime = now
            if debugEnabled then Utils.Log("[RainTracker->CheckRain]: Rain ended — delaying drying") end
        end

        if level ~= State.lastRainLevel then
            if debugEnabled then
                Utils.Log(string.format("[RainTracker->CheckRain]: Rain level changed: %s → %s (%.2f)",
                    State.lastRainLevel, level,
                    rain))
            end
            State.lastRainLevel = level
        end

        -- Remove normal drying buff if raining and outside
        if level ~= "none" and isOutside and State.warmingActive and State.warmingType == "normal" then
            local soul = Utils.GetPlayer().soul
            if soul then soul:RemoveAllBuffsByGuid(Config.buffs.buff_drying_normal) end
            State.warmingActive = false
            State.warmingType = nil

            if Config.debugDrying then
                Utils.Log(
                    "⛈️ [RainTracker->CheckRain]: Removed normal drying due to rain outside")
            end
        end

        if not isOutside or level == "none" then
            RainTracker.TryToDryOut()
        end
    end)
    if not ok then Utils.Log("💥 [RainTracker->CheckRain]: INTERNAL error in CheckRain(): " .. tostring(err)) end
end

function RainTracker.TryToDryOut()
    if not State.isInitialized then
        if Config.debugRainTracker then
            RThrot("trytodryout_notinit", 10, "[RainTracker->TryToDryOut]: Skipping — system not initialized")
        end
        return
    end

    local ok, err = pcall(function()
        -- modules & entities
        local HeatDetection = SanitasInTenebris.HeatDetection
        if not HeatDetection or not HeatDetection.HasNearbyFireSource then
            if Config.debugRainTracker then
                Utils.Log("[RainTracker->TryToDryOut]: HeatDetection not available — skipping drying logic")
            end
            return
        end

        local player = Utils.GetPlayer()
        local soul   = player and player.soul
        if not player or not soul then
            if Config.debugDrying then Utils.Log("[RainTracker->TryToDryOut]: player or soul missing") end
            return
        end

        -- readings (centralized helpers)
        local rain                         = RainTracker.GetRainSafe()
        local isIndoors, roofed, sheltered = RainTracker.GetShelterFlags()
        local wetness                      = State.wetnessPercent or 0
        local holdingTorch                 = (Utils.IsTorchEquipped and Utils.IsTorchEquipped()) or false

        -- heat / fire source (safe)
        local nearFire, fireStrength       = false, 0
        do
            local okFire, nf, fs = pcall(HeatDetection.HasNearbyFireSource, Config.fireDetectionRadius or 2.0)
            if okFire then nearFire, fireStrength = (nf == true), (fs or 0) end
        end
        if Config.debugDrying then
            Utils.Log("[RainTracker->TryToDryOut]: Fire: near=" ..
                tostring(nearFire) .. ", strength=" .. tostring(fireStrength))
        end

        -- ensure indoor-style drying UI where sheltered (also shows fire_signal when dry+near fire)
        if sheltered and RainTracker.UpdateDryingBuffs then
            local _okUB, _errUB = pcall(RainTracker.UpdateDryingBuffs, true, nearFire, soul)
            if not _okUB and Config.debugDrying then
                Utils.Log("💥 [RainTracker->TryToDryOut]: UpdateDryingBuffs failed: " .. tostring(_errUB))
            end
        end

        -- context breadcrumb (throttled)
        if Config and Config.debugDrying == true then
            RainTracker._dbg = RainTracker._dbg or {}
            local now = System.GetCurrTime()
            if (RainTracker._dbg.dryctx or 0) <= now then
                local w = (State and (State.wetnessPercent or State.wetness)) or 0
                if w <= 1 and (State and State.wetnessPercent == nil) then w = w * 100 end
                Utils.Log(("[DryCtx] indoors=%s roofed=%s sheltered=%s nearFire=%s heat=%.2f wet=%.2f%%")
                    :format(tostring(isIndoors), tostring(roofed), tostring(sheltered),
                        tostring(nearFire), tonumber(fireStrength or 0) or 0, w))
                RainTracker._dbg.dryctx = now + 3
            end
        end

        -- drying permission: allowed if (not raining) OR (raining but sheltered)
        local allowDry = RainTracker.CanDryNow(rain, sheltered)

        -- quick wetness diagnostics
        if Config and Config.debugRainTracker == true then
            if (wetness or 0) > 0 then
                RLog(string.format("[RainTracker->TryToDryOut]: Wetness = %.2f", wetness))
            else
                RThrot("trytodryout_wet0", 30, "[RainTracker->TryToDryOut]: Wetness = 0")
            end
        end

        if wetness > 0 then
            -- any of these can permit drying
            local canDry = allowDry or nearFire or holdingTorch

            if not canDry then
                if Config.debugDrying then Utils.Log("[RainTracker->TryToDryOut]: No drying conditions met — skipping") end
                return
            end

            -- if we are UNSHELTERED outdoors (i.e., canDry only because rain is low),
            -- enforce the “rain has stopped for a while” window before allowing dry
            local isOutside = not isIndoors
            if isOutside and not sheltered and not nearFire and not holdingTorch then
                local stopThresh = (Config.rain and Config.rain.dryingThreshold) or 0.1
                local delaySec   = (Config.rain and Config.rain.dryingDelayAfterRain) or 10
                local now        = System.GetCurrTime()

                if rain >= stopThresh then
                    if Config.debugDrying then
                        Utils.Log("[RainTracker->TryToDryOut]: Raining at/above threshold — skip drying")
                    end
                    return
                end

                if not State.rainStoppedAt or (now - State.rainStoppedAt) < delaySec then
                    if Config.debugDrying then
                        Utils.Log(("⏱ [RainTracker->TryToDryOut]: Waiting after-rain delay — elapsed=%.2f / required=%s")
                            :format(State.rainStoppedAt and (now - State.rainStoppedAt) or 0, tostring(delaySec)))
                    end
                    return
                end
            end

            -- ready → perform one drying tick
            if Config.debugDrying then Utils.Log("💧 [RainTracker->TryToDryOut]: Drying conditions met — proceeding") end
            local okTick, errTick = pcall(SanitasInTenebris.DryingSystem.Tick)
            if not okTick then
                Utils.Log("[RainTracker->TryToDryOut]: DryingSystem.Tick error: " .. tostring(errTick))
            end
        else
            -- fully dry: clear drying UI if any (UpdateDryingBuffs already shows fire_signal when appropriate)
            if Config.debugDrying then Utils.Log("[RainTracker->TryToDryOut]: Player is fully dry — no drying needed") end
            if RainTracker.RemoveDryingBuffIfNeeded then
                RainTracker.RemoveDryingBuffIfNeeded(soul)
            end
        end
    end)

    if not ok then
        Utils.Log("[RainTracker->TryToDryOut]: INTERNAL error in TryToDryOut(): " .. tostring(err))
    end
end

function RainTracker.CheckNearbyFire()
    local nearFire, fireStrength = false, 0.0
    if type(HeatDetection.HasNearbyFireSource) == "function" then
        local ok, v1, v2 = pcall(function()
            return HeatDetection.HasNearbyFireSource(Config.fireDetectionRadius or 3.0)
        end)
        if ok then
            nearFire = v1
            fireStrength = v2 or 1.0
        elseif debugEnabled then
            Utils.Log("❌ [RainTracker]: Fire detection failed: " .. tostring(v1))
        end
    end
    if debugEnabled then
        Utils.Log("🔥 [RainTracker]: Fire: near=" .. tostring(nearFire) .. ", strength=" .. tostring(fireStrength))
    end
    return nearFire, fireStrength
end

function RainTracker.UpdateDryingBuffs(isIndoors, nearFire, soul)
    local wetness = State.wetnessPercent or 0
    if not soul then return end

    -- Sticky "nearFire"
    local now  = System.GetCurrTime()
    local hold = (Config and Config.drying and Config.drying.buffHoldSeconds) or 0
    if nearFire then
        State._lastFireSeenAt = now
    else
        local last = State._lastFireSeenAt or 0
        if hold > 0 and (now - last) < hold then
            nearFire = true
        end
    end

    -- local helpers (unchanged)
    local function _wet()
        local w = (State and (State.wetnessPercent or State.wetness)) or 0
        if w <= 1 and (State and State.wetnessPercent == nil) then w = w * 100 end
        return w
    end
    RainTracker._ub_rt = RainTracker._ub_rt or {}
    local function _tick(key, secs)
        local now = System.GetCurrTime()
        local t   = RainTracker._ub_rt
        if not t[key] or now >= t[key] then
            t[key] = now + (secs or 3); return true
        end
        return false
    end

    -- decide newType
    local newType = nil
    local indoorish = isIndoors or (State and State.shelteredActive == true)

    if wetness > 0 then
        -- ☔ Actively drying
        newType = indoorish and (nearFire and "fire" or "normal") or nil
    elseif wetness <= 0 and nearFire and indoorish then
        -- 🌡️ Dry but near fire = show signal
        newType = "fire_signal"
    end

    -- 👇 move the decision log *after* newType is computed
    if Config and Config.debugDrying == true and _tick("ub_decide", 3) then
        Utils.Log(string.format(
            "[UpdateDryingBuffs] indoors=%s nearFire=%s wet=%.2f%% → newType=%s",
            tostring(isIndoors), tostring(nearFire), _wet(), tostring(newType)
        ))
    end

    -- same-type short-circuit
    if State.warmingActive and State.warmingType == newType then
        if Config.debugDrying and _tick("ub_same", 5) then
            Utils.Log("🔁 [UpdateDryingBuffs]: already '" .. tostring(newType) .. "' — skipping")
        end
        return
    end

    -- switching types → remove old
    if State.warmingActive and State.warmingType ~= newType then
        if Config.debugDrying and _tick("ub_remove", 3) then
            Utils.Log("🔄 [UpdateDryingBuffs]: removing '" .. tostring(State.warmingType) .. "'")
        end
        BuffLogic.RemoveDryingBuffsOnly()
    end

    -- no valid target → clear state and exit
    if not newType then
        State.warmingType   = nil
        State.warmingActive = false
        if Config.debugDrying and _tick("ub_none", 3) then
            Utils.Log("🚫 [UpdateDryingBuffs]: no valid drying condition")
        end
        return
    end

    -- ✅ apply new
    BuffLogic.ApplyDryingBuff(newType)

    -- keep only ONE apply log (remove the earlier manual-throttle block)
    if Config and Config.debugDrying == true and _tick("ub_apply", 3) then
        Utils.Log("[UpdateDryingBuffs]: applied '" .. tostring(newType) .. "'")
    end
end
