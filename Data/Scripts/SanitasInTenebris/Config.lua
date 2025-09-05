-- Config.lua
System.LogAlways("4$ [Sanitas] ✅ Loaded: Config")

Config = {
    bedDetectionRadius = 3.5,
    doorDetectionRadius = 4.0,
    pollingInterval = 1000,
    outdoorHeatInterval = 2000,
    fireDetectionRadius = 1.5,
    fireRainResistanceFactor = 0.7, -- max % resistance against rain when near fire
    rainWetnessGain = 0.5,          -- base wetness gain per tick from rain
    -- MAIN DEBUG FLAGS
    enableLogOnce = false,
    mainDebug = false,
    debugPolling = true,
    debugIndoorPolling = true, --indoor poll tick + related
    debugRainTracker = true,
    debugBuffLogic = true,
    debugRoofDetection = false,
    fireDebug = true,
    interiorLogicDebug = true,
    debugDrying = true,
    rainCleansDebug = false,
    --
    drying = {
        tickInterval = 2000,
        startDelay = 3000,
        buffHoldSeconds = 4
    },
    shelter = {
        applyDelaySec  = 1.5,  -- must remain sheltered this long before showing the buff
        releaseHoldSec = 3.0,  -- keep the buff this long after losing shelter (prevents flicker)
    },
    dryingMultiplier = {
        indoorNoFire = 0.001,  -- 🏠 Drying rate indoors without any fire
        outdoorNoRain = 0.002, -- 🌤 Drying rate outdoors, not raining
        nearFire = 0.005,      -- 🔥 Strong drying near heat source (campfire, forge)
        torch = 0.003,         -- 🔥 Torch warmth contribution (additive only when outdoors)
    },
    rainCleans = {
        CleaningThreshold = 2.0,          -- progress needed for full wash
        RainIntensityThreshold = 0.3,     -- minimum rain strength to start
        RainIntensityMultiplier = 0.0300, -- progress gain per second per 1.0 rain, was 0.0300
        TickInterval = 2000               -- update interval in ms
    },
    buffs = {
        sheltered = "61d8e6fd-b3b0-496c-9982-a03e9d020fe5",
        buff_wetness_rain_mild = "6c348be1-24f1-44e4-899f-d5f5fd59395e",
        buff_wetness_rain_moderate = "91e8b6cf-03ad-4a3f-a3c3-bb594a8825d6",
        buff_wetness_rain_severe = "de21390e-bd17-4c4e-a58c-d1ab688177c8",
        buff_drying_normal = "7c4a5e71-23d2-4e26-b70f-b2932a7b0f59",
        buff_drying_firesource = "43d2ef34-8f0f-4b76-8966-5c9aaf29e1bd",
        buff_refreshed = "c98c1439-bae0-43f1-9d3b-6a64a13e5e82",
        buff_cleanse_dried = "1a1e94c5-3e1d-4d58-b442-726ae9f4f7c1",
        buff_coldness = "GUID_HERE",
        buff_coldness_wet = "GUID_HERE"
    },
    rain = {
        dryingThreshold = 0.1,
        dryingDelayAfterRain = 10 -- seconds, set later to 30
    },
    rainExposureThresholds = {
        mild = 60,
        moderate = 800,
        severe = 1600
    },
    -- Wetness tier thresholds with hysteresis (entry/exit)
    wetnessThresholds = {
        tier1 = { enter = 0.10, exit = 0.05 },
        tier2 = { enter = 20, exit = 15 },
        tier3 = { enter = 50, exit = 45 },
    },
    fireSourceClasses = {
        fireplacesmartobject = 0.9,
        -- smith/forge coverage (name- or class-contains, case-insensitive)
        forge                = 1.2, -- hits "light_forge", "coal_forge2", etc.
        light23              = 0.8, -- pig grilling fireplace
    },
    -- Roof ray settings
    roofRayStartHeight = 0.5,  -- meters above player head to start the ray
    roofRayMaxDistance = 10.0, -- how far up to look for a roof/ceiling
    roofIgnoreClasses = {      -- lowercase class names we'll ignore (vegetation etc.)
        tree = true,
        bush = true,
        vegetation = true,
        foliage = true,
        grass = true,
        hedge = true,
        shrub = true
    },

}
