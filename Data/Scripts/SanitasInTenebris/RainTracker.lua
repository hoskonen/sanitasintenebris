-- 🌧 RainTracker.lua
System.LogAlways("4$ [Sanitas] ✅ Loaded: RainTracker")

RainTracker = {}

local debugEnabled = Config.debugRainTracker == true
local logPrefix = "4$ [Sanitas] 🌧"

-- Thresholds for applying wetness buffs
local exposureThresholds = {
    { seconds = Config.rainExposureThresholds.mild,     buff = Config.buffs.buff_wetness_rain_mild },
    { seconds = Config.rainExposureThresholds.moderate, buff = Config.buffs.buff_wetness_rain_moderate },
    { seconds = Config.rainExposureThresholds.severe,   buff = Config.buffs.buff_wetness_rain_severe },
}

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
        Utils.Log("💧 [RainTracker]: Wetness tier changed: " .. tostring(previous) .. " → " .. tostring(tier))
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
    local rain = EnvironmentModule.GetRainIntensity() or 0

    -- Drying only applies if we're wet
    if wetness <= 0 then return end

    local canDry = (not isOutside) or (isOutside and rain == 0)

    if canDry and not State.warmingActive then
        Utils.Log("🌬️ [RainTracker->TryStartDryingSystem]: Conditions OK — starting drying system")
        State.warmingActive = true
        Script.SetTimer(Config.drying.tickInterval or 5000, SanitasInTenebris.DryingSystem.Tick)
    end
end

function RainTracker.CheckRain()
    if debugEnabled then Utils.Log("📡 [RainTracker->CheckRain]: Running...") end

    local ok, err = pcall(function()
        if State.pollingSuspended then
            if debugEnabled then Utils.Log("⏸️ [RainTracker->CheckRain]: Rain check skipped — polling suspended") end
            return
        end

        local rain = EnvironmentModule.GetRainIntensity() or 0
        local level = (rain >= 0.6 and "heavy") or (rain >= 0.2 and "light") or "none"
        local isOutside = not InteriorLogic.IsPlayerInInterior()
        local now = System.GetCurrTime()

        if level ~= "none" and isOutside then
            local wetness = State.wetnessPercent or 0
            local gainBase = 0.1 + (rain ^ 1.2) * 0.9
            local gainModifier = math.max(0.3, 1 - (wetness / 100) ^ 1.3)
            local adjustedGain = gainBase * gainModifier * (Config.rainWetnessGain or 1.0)

            State.wetnessPercent = math.min(100, wetness + adjustedGain)

            if debugEnabled then
                System.LogAlways(string.format(
                    "%s 🧼 [RainTracker->CheckRain]: Rain Tick — rain=%.2f → +%.2f (wetness=%.2f%%)",
                    logPrefix, rain, adjustedGain, State.wetnessPercent or 0))
                State.lastRainTickLog = now
            end

            RainTracker.RefreshWetnessBuffTier()
        end

        -- Record rain stop time when dropping below drying threshold
        if rain < (Config.dryingThreshold or 0.1) and (State.lastRainAmount or 1) >= (Config.dryingThreshold or 0.1) then
            State.rainStoppedAt = now
            if debugEnabled then
                Utils.Log(
                    "🌤️ [RainTracker->CheckRain] Rain dropped below drying threshold — setting rainStoppedAt = " .. now)
            end
        end

        -- Always update lastRainAmount for threshold comparison
        State.lastRainAmount = rain

        if level == "none" and State.lastRainLevel ~= "none" then
            State.lastRainEndTime = now
            if debugEnabled then Utils.Log("🌤️ [RainTracker->CheckRain]: Rain ended — delaying drying") end
        end

        if level ~= State.lastRainLevel then
            if debugEnabled then
                Utils.Log(string.format("🌧️ [RainTracker->CheckRain]: Rain level changed: %s → %s (%.2f)",
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
            Utils.Log("⏳ [RainTracker->TryToDryOut]: Skipping — system not initialized")
        end
        return
    end

    local ok, err = pcall(function()
        local HeatDetection = SanitasInTenebris.HeatDetection
        if not HeatDetection or not HeatDetection.HasNearbyFireSource then
            if Config.debugRainTracker then
                Utils.Log(
                    "🔥 [RainTracker->TryToDryOut]: HeatDetection not available or incomplete — skipping drying logic")
            end
            return
        end

        local player = Utils.GetPlayer()
        local soul = player and player.soul
        if not player or not soul then
            if Config.debugDrying then Utils.Log("❌ [RainTracker->TryToDryOut]: player or soul missing") end
            return
        end

        local rain = EnvironmentModule.GetRainIntensity() or 0
        local isOutside = not InteriorLogic.IsPlayerInInterior()
        local isIndoors = not isOutside
        --local wetness = State.wetnessLevel or 0
        local wetness = State.wetnessPercent or 0
        local holdingTorch = Utils.IsTorchEquipped()

        -- 🔥 Always check for fire and apply buff
        local nearFire, fireStrength = HeatDetection.HasNearbyFireSource()
        if Config.debugDrying then
            Utils.Log("🔥 [RainTracker->TryToDryOut]: Fire: near=" ..
                tostring(nearFire) .. ", strength=" .. tostring(fireStrength))
        end

        -- Drying System takes care of the adding drying buffs from now on
        -- -- 🌡️ Apply visual warmth buff (even if not drying)
        -- if RainTracker.UpdateDryingBuffs then
        --     RainTracker.UpdateDryingBuffs(isIndoors, nearFire, soul)
        -- else
        --     Utils.Log("💥 [RainTracker->TryToDryOut]: ERROR: RainTracker.UpdateDryingBuffs is nil")
        -- end

        -- ☔ Skip drying if it's raining and you're outside
        if rain >= 0.2 and isOutside then
            if Config.debugDrying then
                Utils.Log("⛔ [RainTracker->TryToDryOut]: Skipping TryToDryOut — rain outside blocks drying")
            end
            return
        end

        -- 🚫 Skip drying only if player is fully dry and not in any drying condition
        -- (Torch, fire, outdoor air can all allow drying to proceed)

        if debugEnabled then
            Utils.Log("💧 [RainTracker->TryToDryOut]: Wetness = " .. tostring(wetness))
        end
        if wetness > 0 then
            local canDry =
                isIndoors or
                nearFire or
                holdingTorch or
                isOutside -- assumes not raining due to earlier check

            if canDry then
                if Config.debugDrying then Utils.Log("💧 [RainTracker->TryToDryOut]: Drying conditions met — proceeding") end
                SanitasInTenebris.DryingSystem.Tick()
            else
                if Config.debugDrying then Utils.Log("🚫 [RainTracker->TryToDryOut]: No drying conditions met — skipping") end
            end
        else
            if Config.debugDrying then Utils.Log("💤 [RainTracker->TryToDryOut]: Player is fully dry — no drying needed") end

            -- 💧 Remove drying buff if fully dry
            if RainTracker.RemoveDryingBuffIfNeeded then
                RainTracker.RemoveDryingBuffIfNeeded(soul)
            end
        end
    end)

    if not ok then
        Utils.Log("💥 [RainTracker->TryToDryOut]: INTERNAL error in TryToDryOut(): " .. tostring(err))
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

    local newType = nil

    if wetness > 0 then
        -- ☔ Actively drying
        newType = isIndoors and (nearFire and "fire" or "normal") or nil
    elseif wetness <= 0 and nearFire and isIndoors then
        -- 🌡️ Dry but near fire = show signal
        newType = "fire_signal"
    end

    -- ♻️ Skip if already active with same type
    if State.warmingActive and State.warmingType == newType then
        if Config.debugDrying then Utils.Log("🔁 [RainTracker->UpdateDryingBuffs]: Drying buff already active — skipping") end
        return
    end

    -- 🔄 Remove old buff if switching type
    if State.warmingActive and State.warmingType ~= newType then
        if Config.debugDrying then
            Utils.Log(
                "🔄 [RainTracker->UpdateDryingBuffs]: Changing drying type — removing old buff")
        end
        BuffLogic.RemoveDryingBuffsOnly()
    end

    -- 🚫 No valid drying condition
    if not newType then
        if Config.debugDrying then
            Utils.Log(
                "🚫 [RainTracker->UpdateDryingBuffs]: No valid drying condition — not applying")
        end
        State.warmingType = nil
        State.warmingActive = false
        return
    end

    -- ✅ Apply drying buff or fire proximity signal
    BuffLogic.ApplyDryingBuff(newType)
end
