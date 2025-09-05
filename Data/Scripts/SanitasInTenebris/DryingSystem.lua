System.LogAlways("4$ [Sanitas] ✅ Loaded: DryingSystem")

SanitasInTenebris.DryingSystem = SanitasInTenebris.DryingSystem or {}

local Config                   = Config or (SanitasInTenebris and SanitasInTenebris.Config)
local State                    = State or (SanitasInTenebris and SanitasInTenebris.State)
local Utils                    = Utils or (SanitasInTenebris and SanitasInTenebris.Utils)
local InteriorLogic            = InteriorLogic or (SanitasInTenebris and SanitasInTenebris.InteriorLogic)
local BuffLogic                = BuffLogic or (SanitasInTenebris and SanitasInTenebris.BuffLogic)
local HeatDetection            = HeatDetection or (SanitasInTenebris and SanitasInTenebris.HeatDetection)

local debugEnabled             = (Config and Config.debugDrying) == true

-- Local throttle so we don't depend on Utils.ThrottledCh load order
SanitasInTenebris._dry_rt      = SanitasInTenebris._dry_rt or {}
local function DThrot(key, intervalSec, msg)
    -- inline debug gate
    if not (Config and ((Config.debugDrying == true) or (Config.debugPolling == true))) then return end

    if Utils and type(Utils.ThrottledCh) == "function" then
        Utils.ThrottledCh("drying", key, intervalSec, msg)
        return
    end
    local now    = System.GetCurrTime()
    local t      = SanitasInTenebris._dry_rt
    local nextAt = t[key]
    if not nextAt or now >= nextAt then
        Utils.Log(msg)
        t[key] = now + (intervalSec or 3)
    end
end

local function SafeCall(where, fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        System.LogAlways(string.format("4$ [Sanitas] [DryingSystem->%s] ❌ %s", where, tostring(res)))
        if debug and debug.traceback then
            System.LogAlways("4$ [Sanitas] [DryingSystem->" .. where .. "] Trace:\n" .. debug.traceback())
        end
    end
    return ok, res
end

-- Defer RainTracker resolution until call time (load order safe)
local function _RT()
    return RainTracker or (SanitasInTenebris and SanitasInTenebris.RainTracker)
end

-- Nil-safe helpers for nested config
local function _rainStopThresh()
    return (Config.rain and Config.rain.dryingThreshold) or 0.1
end

local function _dryingStartDelaySec()
    -- (ms in config) → seconds here; fall back to 30s
    local ms = (Config.drying and Config.drying.startDelay) or 30000
    return ms / 1000
end

local function _tickIntervalSec()
    local ms = (Config and Config.drying and tonumber(Config.drying.tickInterval)) or 5000
    return ms / 1000
end


function SanitasInTenebris.DryingSystem.Start()
    return SafeCall("start", function()
        -- Initialize rainStoppedAt if the game hasn't set it yet
        if not State.rainStoppedAt then
            State.rainStoppedAt = System.GetCurrTime()
            if debugEnabled then
                Utils.Log("[DryingSystem->Start]: Initialized rainStoppedAt = " .. tostring(State.rainStoppedAt))
            end
        end

        if debugEnabled then Utils.Log("💧 [DryingSystem->Start]: Scheduling first Tick") end
        Script.SetTimer((Config.drying and Config.drying.tickInterval) or 5000, SanitasInTenebris.DryingSystem.Tick)
    end)
end

function SanitasInTenebris.DryingSystem.Tick()
    return SafeCall("tick", function()
        -- Unconditional breadcrumb so we know we actually entered
        if debugEnabled then Utils.Log("[DryingSystem->Tick]: Top-level entry") end

        -- Sequence:
        -- 1. ✅ Check wetness and rainStoppedAt — skip if invalid
        -- 2. 🔥 Check environment (indoor/outdoor, fire, torch, rain)
        -- 3. 📊 Calculate drying rate (via GetCurrentDryingRate)
        -- 4. 💧 Decrease wetness based on time + rate
        -- 5. 🔁 Update wetness state, buffs, and re-arm timer

        local ok, err = pcall(function()
            -------------------------------------------------------------------
            -- 1) Preconditions
            -------------------------------------------------------------------
            local player = Utils.GetPlayer()
            local soul = player and player.soul
            if not player or not soul then
                if debugEnabled then Utils.Log("❌ [DryingSystem->Tick]: player or soul is nil — skip") end
                return
            end

            local isOutside = not InteriorLogic.IsPlayerInInterior()
            local isIndoors = not isOutside
            local dryingThreshold = _rainStopThresh()

            -- Safe rain read
            -- Wrapping the lookup + call inside the anonymous function guarantees the error is caught, not thrown.
            local rain = 0
            local okRain, rv = pcall(function()
                return (EnvironmentModule and EnvironmentModule.GetRainIntensity and EnvironmentModule.GetRainIntensity()) or
                    0
            end)
            if okRain and type(rv) == "number" then
                rain = rv
            elseif debugEnabled then
                Utils.Log("⚠️ [DryingSystem->Tick]: GetRainIntensity failed/invalid, default rain=0")
            end

            local now = System.GetCurrTime()

            -- Track threshold crossing locally too (robust with RainTracker’s logic)
            if State.lastRainValue ~= nil then
                if rain < dryingThreshold and State.lastRainValue >= dryingThreshold then
                    State.rainStoppedAt = now
                    if debugEnabled then
                        Utils.Log("[DryingSystem->Tick]: Crossed below threshold — rainStoppedAt=" ..
                            now)
                    end
                elseif rain >= dryingThreshold and State.lastRainValue < dryingThreshold then
                    State.rainStoppedAt = nil
                    if debugEnabled then Utils.Log("[DryingSystem->Tick]: Crossed above threshold — abort dry delay") end
                end
            end
            State.lastRainValue = rain

            -- Block outdoor drying if raining enough
            if isOutside and rain >= dryingThreshold then
                if debugEnabled then Utils.Log("⛔ [DryingSystem->Tick]: Raining outside — skip") end
                return
            end

            -------------------------------------------------------------------
            -- 2) Already dry?
            -------------------------------------------------------------------
            local wetness = State.wetnessPercent or 0
            if wetness <= 0 then
                -- Remove drying buff(s) safely
                local removed = false
                if BuffLogic and BuffLogic.RemoveBuffByGuid then
                    removed = BuffLogic.RemoveBuffByGuid(Config.buffs.buff_drying_normal)
                elseif soul and soul.RemoveAllBuffsByGuid then
                    removed = soul:RemoveAllBuffsByGuid(Config.buffs.buff_drying_normal)
                end
                if removed and debugEnabled then Utils.Log("[DryingSystem->Tick]: Dry — removed drying buffs") end

                State.warmingActive = false
                State.normalDryingActive = false
                State.fireDryingActive = false

                if RainTracker and RainTracker.UpdateDryingBuffs and HeatDetection and HeatDetection.HasNearbyFireSource then
                    local nearFire = false
                    local okFire, nf = pcall(HeatDetection.HasNearbyFireSource, Config.fireDetectionRadius or 2.0)
                    if okFire then nearFire = (nf == true) end
                    local indoorish = (not isOutside) or (State and State.shelteredActive == true)
                    pcall(RainTracker.UpdateDryingBuffs, indoorish, nearFire, soul)
                end
                return
            end

            -------------------------------------------------------------------
            -- 3) Delay since rain stopped (seconds)
            -------------------------------------------------------------------
            local delaySec = _dryingStartDelaySec()
            if isOutside then
                if not State.rainStoppedAt then
                    if debugEnabled then Utils.Log("[DryingSystem->Tick]: rainStoppedAt=nil — wait") end
                    return
                end
                local elapsed = now - State.rainStoppedAt
                if elapsed < delaySec then
                    if debugEnabled then
                        Utils.Log(string.format("[DryingSystem->Tick]: Waiting delay (%.1fs/%.1fs)", elapsed,
                            delaySec))
                    end
                    return
                end
            end

            -------------------------------------------------------------------
            -- 4) Heat detection
            -------------------------------------------------------------------
            if not HeatDetection or type(HeatDetection.HasNearbyFireSource) ~= "function" then
                if debugEnabled then
                    Utils.Log(
                        "🔥 [DryingSystem->Tick]: HeatDetection unavailable — continuing without fire")
                end
            end

            local nearFire, fireStrength = false, 0
            if HeatDetection and HeatDetection.HasNearbyFireSource then
                local okFire, v1, v2 = pcall(function() return HeatDetection.HasNearbyFireSource(2.0) end)
                if okFire then
                    nearFire, fireStrength = v1, v2 or 1.0
                elseif debugEnabled then
                    Utils.Log("🔥 [DryingSystem->Tick]: Fire detection failed")
                end
            end
            if debugEnabled then
                Utils.Log("[DryingSystem->Tick]: Fire near=" ..
                    tostring(nearFire) .. " strength=" .. tostring(fireStrength))
            end

            -------------------------------------------------------------------
            -- 5) Drying rate (math only) — UI is handled by RainTracker
            -------------------------------------------------------------------
            -- Use your helper if present, otherwise fall back to the old math
            local dryingRate
            if SanitasInTenebris.DryingSystem.CalculateDryingMultiplier then
                dryingRate = SanitasInTenebris.DryingSystem.CalculateDryingMultiplier(isIndoors, isOutside, nearFire)
            else
                local m = Config.dryingMultiplier or {}
                dryingRate = nearFire and (m.nearFire or 1.0)
                    or (isIndoors and (m.indoorNoFire or 0.1))
                    or (m.outdoorNoRain or 0.2)
                if isOutside and Utils.IsTorchEquipped and Utils.IsTorchEquipped() then
                    dryingRate = dryingRate + (m.torch or 0.3)
                end
            end

            local dt     = _tickIntervalSec()
            local amount = math.min(wetness, (tonumber(dryingRate) or 0) * (tonumber(dt) or 0))

            if Config.debugDrying then
                Utils.Log(("[DryingSystem->Tick]: rate=%.3f, dt=%.2f, amount=%.3f")
                    :format(tonumber(dryingRate) or 0, tonumber(dt) or 0, tonumber(amount) or 0))
            end

            -- Apply wetness reduction
            State.wetnessPercent = math.max(0, wetness - amount)

            if Config and Config.debugDrying then
                Utils.Log(("[DryTick] wet=%.2f%% → %.2f%% (Δ=%.3f | rate=%.3f, dt=%.2f)")
                    :format(tonumber(wetness) or 0, tonumber(State.wetnessPercent) or 0, tonumber(amount) or 0,
                        tonumber(dryingRate) or 0, tonumber(dt) or 0))
            end

            -- Refresh tier if available
            local RT = _RT()
            if RT and type(RT.RefreshWetnessBuffTier) == "function" then
                RT.RefreshWetnessBuffTier()
            elseif debugEnabled then
                Utils.Log("⚠️ [DryingSystem->Tick]: RainTracker.RefreshWetnessBuffTier missing")
            end

            -- Hand off drying UI to RainTracker (single owner)
            if RainTracker and type(RainTracker.UpdateDryingBuffs) == "function" then
                local player = Utils.GetPlayer()
                local soul   = player and player.soul
                if soul then
                    local indoorish = isIndoors or (State and State.shelteredActive == true)
                    pcall(RainTracker.UpdateDryingBuffs, indoorish, nearFire, soul)
                end
            end

            -------------------------------------------------------------------
            -- 6) Re-arm
            -------------------------------------------------------------------
            Script.SetTimer((Config.drying and Config.drying.tickInterval) or 5000, SanitasInTenebris.DryingSystem.Tick)
        end)

        if not ok then
            -- This log is unconditional so you actually see the stack context
            Utils.Log("💥 [DryingSystem->Tick]: ERROR: " .. tostring(err))
        end
    end)
end

function SanitasInTenebris.DryingSystem.CalculateDryingMultiplier(isIndoors, isOutside, nearFire)
    local m = Config.dryingMultiplier or {}
    local holdingTorch = Utils.IsTorchEquipped()
    local multiplier = 0

    -- 🏠 Indoors:
    --   🔥 nearFire = fast drying (e.g., oven or forge)
    --   🕯 torch = moderate passive warmth
    --   🚫 otherwise slow drying from ambient air

    if isIndoors then
        if nearFire then
            multiplier = m.nearFire or 1.0
        else
            multiplier = m.indoorNoFire or 0.1
            if holdingTorch then
                multiplier = multiplier + (m.torch or 0.3)
            end
        end
    elseif isOutside then
        if nearFire then
            multiplier = m.nearFire or 1.0
        else
            multiplier = m.outdoorNoRain or 0.2
        end
        if holdingTorch then
            multiplier = multiplier + (m.torch or 0.3)
        end
    end

    -- nice, explicit breakdown log (no math changes)
    do
        local dbg = (Config and ((Config.debugDrying == true)))
        if dbg then
            local function n(x) return tonumber(x) or 0 end
            local m = Config.dryingMultiplier or {}
            local rain = (RainTracker and RainTracker.GetRainSafe and RainTracker.GetRainSafe()) or 0
            local torchOn = (Utils.IsTorchEquipped and Utils.IsTorchEquipped()) or false
            local sheltered = isIndoors or (State and State.shelteredActive == true)

            -- recompute a *breakdown* that mirrors your current logic
            local base
            if nearFire then
                base = m.nearFire or 1.0
            elseif isIndoors then
                base = m.indoorNoFire or 0.1
            elseif isOutside then
                -- isCovered is currently false / TODO, keep as in your code
                base = m.outdoorNoRain or 0.2
            else
                base = 0
            end

            local torchBump = 0
            if torchOn and not nearFire then
                -- same rule you use above: add torch when not near fire
                torchBump = m.torch or 0.3
            end

            Utils.Log(("[DryRate] base=%.3f torch=%.3f ⇒ final=%.3f  |  flags: indoors=%s outside=%s fire=%s torch=%s sheltered=%s rain=%.2f")
                :format(n(base), n(torchBump), n(multiplier),
                    tostring(isIndoors), tostring(isOutside), tostring(nearFire),
                    tostring(torchOn), tostring(sheltered), n(rain)))
        end
    end

    return multiplier
end
