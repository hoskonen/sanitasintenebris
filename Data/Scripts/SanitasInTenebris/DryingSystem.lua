System.LogAlways("4$ [Sanitas] ✅ Loaded: DryingSystem")

SanitasInTenebris.DryingSystem = SanitasInTenebris.DryingSystem or {}

local Config = SanitasInTenebris.Config
local State = SanitasInTenebris.State
local Utils = SanitasInTenebris.Utils
local InteriorLogic = SanitasInTenebris.InteriorLogic
local BuffLogic = SanitasInTenebris.BuffLogic
local HeatDetection = SanitasInTenebris.HeatDetection

local debugEnabled = Config.debugDrying == true

function SanitasInTenebris.DryingSystem.Start()
    if not State.rainStoppedAt then
        State.rainStoppedAt = System.GetCurrTime()
        if debugEnabled then
            Utils.Log("[DryingSystem->Start]: Initialized rainStoppedAt to current time = " ..
                tostring(State.rainStoppedAt))
        end
    end

    Utils.Log("💧 [DryingSystem->Start]: Scheduling first Tick")
    Script.SetTimer(Config.drying.tickInterval or 5000, SanitasInTenebris.DryingSystem.Tick)
end

function SanitasInTenebris.DryingSystem.Tick()
    --[[ 📦 DryingSystem.Tick — Main Drying Loop

    Sequence:
    1. ✅ Check wetness and rainStoppedAt — skip if invalid
    2. 🔥 Check environment (indoor/outdoor, fire, torch, rain)
    3. 📊 Calculate drying rate (via GetCurrentDryingRate)
    4. 💧 Decrease wetness based on time + rate
    5. 🔁 Update wetness state, buffs, and re-arm timer
    ]]

    Utils.Log("[DryingSystem->Tick]: Top-level entry reached")

    local success, err = pcall(function()
        -------------------------------------------------------------------
        -- 🔎 1. Preconditions and Early Exit
        -------------------------------------------------------------------
        local player = Utils.GetPlayer()
        local soul = player and player.soul

        if debugEnabled then
            Utils.Log("[DryingSystem->Tick]: entered")
            Utils.Log("[DryingSystem->Tick]: Wetness level check: " .. tostring(State.wetnessPercent or "nil"))
        end

        if not player or not soul then
            if debugEnabled then Utils.Log("❌ [DryingSystem->Tick]: player or soul is nil") end
            return
        end

        local isOutside = not InteriorLogic.IsPlayerInInterior()
        local isIndoors = not isOutside
        local dryingThreshold = Config.rain.dryingThreshold or 0.1

        Utils.Log("[DryingSystem->Tick]: Getting rain intensity...")
        local rain = 0
        local okRain, rainResult = pcall(EnvironmentModule.GetRainIntensity)

        if okRain and rainResult then
            rain = rainResult
        else
            Utils.Log("[DryingSystem->Tick]: GetRainIntensity failed or returned nil")
        end

        Utils.Log("📡 [DryingSystem->Tick]: rain = " .. tostring(rain))
        local now = System.GetCurrTime()

        if State.lastRainValue == nil then
            Utils.Log("[DryingSystem->Tick]: No previous rain — deferring rainStoppedAt logic")
        else
            if rain < dryingThreshold and State.lastRainValue >= dryingThreshold then
                State.rainStoppedAt = now
                Utils.Log("[DryingSystem->Tick]: Rain dropped below threshold — starting drying countdown")
            elseif rain >= dryingThreshold and State.lastRainValue < dryingThreshold then
                State.rainStoppedAt = nil
                Utils.Log("[DryingSystem->Tick]: Rain started again — aborting countdown")
            end
        end

        -- Skip if raining enough to prevent drying
        if isOutside and rain >= dryingThreshold then
            if debugEnabled then Utils.Log("[DryingSystem->Tick]: Raining outside — skipping drying") end
            return
        end

        State.lastRainValue = rain

        -------------------------------------------------------------------
        -- 🚿 2. Dryness Check
        -------------------------------------------------------------------
        local wetness = State.wetnessPercent or 0

        if wetness <= 0 then
            if State.normalDryingActive then
                if debugEnabled then
                    Utils.Log("[DryingSystem->Tick]: BuffLogic = " .. tostring(BuffLogic))
                    Utils.Log("[DryingSystem->Tick]: RemoveBuffByGuid = " ..
                        tostring(BuffLogic and BuffLogic.RemoveBuffByGuid))
                end

                local removed = BuffLogic.RemoveBuffByGuid(Config.buffs.buff_drying_normal)
                if removed and debugEnabled then
                    Utils.Log("[DryingSystem->Tick]: Dry — removed drying buffs")
                end
            end

            if debugEnabled and not State.wasDryLogged then
                Utils.Log("[DryingSystem->Tick]: Already dry — skipping")
            end

            State.wasDryLogged = true
            State.warmingActive = false
            return
        end

        State.wasDryLogged = false
        Utils.Log("[DryingSystem->Tick]: rainStoppedAt = " .. tostring(State.rainStoppedAt))

        -------------------------------------------------------------------
        -- ⏳ 3. Delay Check
        -------------------------------------------------------------------
        local dryingDelay = (Config.drying.startDelay or 30000) / 1000

        if State.rainStoppedAt == nil then
            if debugEnabled then
                Utils.Log("[DryingSystem->Tick]: Skipping drying — rainStoppedAt is nil")
            end
            return
        end

        local elapsed = now - State.rainStoppedAt
        if elapsed < dryingDelay then
            if debugEnabled then
                Utils.Log("[DryingSystem->Tick]: Elapsed since rain stopped = " .. tostring(elapsed))
            end
            return
        end

        -------------------------------------------------------------------
        -- 🔥 4. Heat Detection
        -------------------------------------------------------------------
        local nearFire, fireStrength
        if not HeatDetection then
            Utils.Log("[DryingSystem->Tick]: HeatDetection is nil!")
            return
        end

        local okFire, fireErr = pcall(function()
            nearFire, fireStrength = HeatDetection.HasNearbyFireSource(2.0)
        end)

        if not okFire then
            Utils.Log("[DryingSystem->Tick]: HasNearbyFireSource failed: " .. tostring(fireErr))
            return
        end

        Utils.Log("[DryingSystem->Tick]: HeatDetection — nearFire=" ..
            tostring(nearFire) .. ", strength=" .. tostring(fireStrength))

        -------------------------------------------------------------------
        -- 📊 5. Calculate Drying Rate
        -------------------------------------------------------------------
        local dryingRate = 0

        if isIndoors and not nearFire then
            dryingRate = Config.dryingMultiplier.indoorNoFire
        elseif isOutside and not nearFire and rain < dryingThreshold then
            dryingRate = Config.dryingMultiplier.outdoorNoRain
        elseif nearFire then
            dryingRate = Config.dryingMultiplier.nearFire
        end

        if isOutside and Utils.IsTorchEquipped() then
            dryingRate = dryingRate + (Config.dryingMultiplier.torch or 0)
        end

        local tickIntervalSec = (Config.drying.tickInterval or 5000) / 1000
        local dryingAmount = math.min(wetness, dryingRate * tickIntervalSec)

        if debugEnabled then
            Utils.Log("[DryingSystem->Tick]: DryingRate = " .. dryingRate ..
                ", interval = " .. tickIntervalSec ..
                ", amount = " .. dryingAmount)
        end

        State.wetnessPercent = math.max(0, wetness - dryingAmount)
        RainTracker.RefreshWetnessBuffTier()

        ------------------------------------------------------------
        -- 🧼 6. Apply Buffs Based on Drying State
        ------------------------------------------------------------
        if rain < dryingThreshold then
            if nearFire then
                if not State.fireDryingActive then
                    BuffLogic.ApplyDryingBuff("fire")
                end
            elseif not State.normalDryingActive then
                -- Covers both indoors & outdoors when no fire is near
                BuffLogic.ApplyDryingBuff("normal")
            end
        end

        if debugEnabled then
            Utils.Log("[DryingSystem->Tick]: Applied drying buff based on current state")
        end


        ------------------------------------------------------------
        -- ⏱️ 7. Re-arm Polling
        ------------------------------------------------------------
        Script.SetTimer(Config.drying.tickInterval or 5000, SanitasInTenebris.DryingSystem.Tick)
    end)

    if not success and debugEnabled then
        Utils.Log("[DryingSystem->Tick]: ERROR: " .. tostring(err))
    end
end

function SanitasInTenebris.DryingSystem.CalculateDryingMultiplier(isIndoors, isOutside, nearFire)
    local m = Config.dryingMultiplier or {}

    -- TODO: investigate later isCovered
    --local isCovered = IndoorDetection.IsCoveredArea()
    local isCovered = false -- 🔧 Temporarily disabled to avoid false positives
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
        -- 🌤 Outdoors:
        --   Covered tents give slight bonus (tracking needs to be developed)
        --   Torch stacks additively with passive drying (no fire nearby)
        --   Fire overrides everything
    elseif isOutside then
        if nearFire then
            multiplier = m.nearFire or 1.0
        elseif isCovered then
            multiplier = m.coveredOutdoor or 0.15
        else
            multiplier = m.outdoorNoRain or 0.2
        end

        if holdingTorch then
            multiplier = multiplier + (m.torch or 0.3)
        end
    end

    if debugEnabled then
        Utils.Log(string.format(
            "[DryingSystem->CalculateDryingMultiplier]: Drying multiplier: %.2f (indoors=%s, fire=%s, covered=%s, torch=%s)",
            multiplier, tostring(isIndoors), tostring(nearFire), tostring(isCovered), tostring(holdingTorch)))
    end

    return multiplier
end
