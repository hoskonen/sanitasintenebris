-- Config.lua

Config = {
    bedDetectionRadius = 3.5,
    doorDetectionRadius = 4.0,
    pollingInterval = 1000,
    outdoorHeatInterval = 2000,
    fireDetectionRadius = 1.5,
    fireRainResistanceFactor = 0.7,
    rainWetnessGain = 0.5,

    logging = {
        enabled = true,
        profile = "drying",
        moduleLoads = false,
        stateTraceback = false,
        profiles = {
            quiet = {
                mainDebug = false,
                debugReconcile = false,
                debugPolling = false,
                debugPollTicks = false,
                debugIndoorPolling = false,
                debugRainTracker = false,
                debugBuffLogic = false,
                debugRoofDetection = false,
                fireDebug = false,
                debugFireScan = false,
                interiorLogicDebug = false,
                debugDrying = false,
                debugDryingTrace = false,
                rainCleansDebug = false,
            },
            polling = {
                mainDebug = true,
                debugReconcile = true,
                debugPolling = true,
                debugPollTicks = false,
                debugIndoorPolling = false,
                debugRainTracker = false,
                debugBuffLogic = false,
                debugRoofDetection = false,
                fireDebug = false,
                debugFireScan = false,
                interiorLogicDebug = false,
                debugDrying = false,
                debugDryingTrace = false,
                rainCleansDebug = false,
            },
            indoor = {
                mainDebug = true,
                debugReconcile = true,
                debugPolling = true,
                debugPollTicks = false,
                debugIndoorPolling = true,
                debugRainTracker = false,
                debugBuffLogic = true,
                debugRoofDetection = false,
                fireDebug = false,
                debugFireScan = false,
                interiorLogicDebug = true,
                debugDrying = false,
                debugDryingTrace = false,
                rainCleansDebug = false,
            },
            roof = {
                mainDebug = false,
                debugReconcile = false,
                debugPolling = false,
                debugPollTicks = false,
                debugIndoorPolling = false,
                debugRainTracker = false,
                debugBuffLogic = false,
                debugRoofDetection = true,
                fireDebug = false,
                debugFireScan = false,
                interiorLogicDebug = true,
                debugDrying = false,
                debugDryingTrace = false,
                rainCleansDebug = false,
            },
            shelter = {
                mainDebug = false,
                debugReconcile = true,
                debugPolling = false,
                debugPollTicks = false,
                debugIndoorPolling = true,
                debugRainTracker = false,
                debugBuffLogic = true,
                debugRoofDetection = true,
                fireDebug = false,
                debugFireScan = false,
                interiorLogicDebug = true,
                debugDrying = false,
                debugDryingTrace = false,
                rainCleansDebug = false,
            },
            fire = {
                mainDebug = false,
                debugReconcile = false,
                debugPolling = false,
                debugPollTicks = false,
                debugIndoorPolling = false,
                debugRainTracker = false,
                debugBuffLogic = false,
                debugRoofDetection = false,
                fireDebug = true,
                debugFireScan = false,
                interiorLogicDebug = false,
                debugDrying = true,
                debugDryingTrace = false,
                rainCleansDebug = false,
            },
            fire_trace = {
                mainDebug = false,
                debugReconcile = false,
                debugPolling = false,
                debugPollTicks = false,
                debugIndoorPolling = false,
                debugRainTracker = false,
                debugBuffLogic = false,
                debugRoofDetection = false,
                fireDebug = true,
                debugFireScan = true,
                interiorLogicDebug = false,
                debugDrying = false,
                debugDryingTrace = false,
                rainCleansDebug = false,
            },
            rain = {
                mainDebug = false,
                debugReconcile = true,
                debugPolling = false,
                debugPollTicks = false,
                debugIndoorPolling = false,
                debugRainTracker = true,
                debugBuffLogic = true,
                debugRoofDetection = false,
                fireDebug = false,
                debugFireScan = false,
                interiorLogicDebug = true,
                debugDrying = false,
                debugDryingTrace = false,
                rainCleansDebug = false,
            },
            drying = {
                mainDebug = false,
                debugReconcile = true,
                debugPolling = false,
                debugPollTicks = false,
                debugIndoorPolling = false,
                debugRainTracker = false,
                debugBuffLogic = false,
                debugRoofDetection = false,
                fireDebug = false,
                debugFireScan = false,
                interiorLogicDebug = true,
                debugDrying = true,
                debugDryingTrace = false,
                rainCleansDebug = false,
            },
            rain_cleans = {
                mainDebug = false,
                debugReconcile = false,
                debugPolling = false,
                debugPollTicks = false,
                debugIndoorPolling = false,
                debugRainTracker = false,
                debugBuffLogic = false,
                debugRoofDetection = false,
                fireDebug = false,
                debugFireScan = false,
                interiorLogicDebug = true,
                debugDrying = false,
                debugDryingTrace = false,
                rainCleansDebug = true,
            },
            all_trace = {
                mainDebug = true,
                debugReconcile = true,
                debugPolling = true,
                debugPollTicks = true,
                debugIndoorPolling = true,
                debugRainTracker = true,
                debugBuffLogic = true,
                debugRoofDetection = true,
                fireDebug = true,
                debugFireScan = true,
                interiorLogicDebug = true,
                debugDrying = true,
                debugDryingTrace = true,
                rainCleansDebug = true,
            },
        },
        overrides = {}
    },

    -- Legacy debug flags are filled from Config.logging.profile below.
    enableLogOnce = true,
    mainDebug = false,
    debugReconcile = false,
    debugPolling = false,
    debugPollTicks = false,
    debugIndoorPolling = false,
    debugRainTracker = false,
    debugBuffLogic = false,
    debugRoofDetection = false,
    fireDebug = false,
    debugFireScan = false,
    interiorLogicDebug = false,
    debugDrying = false,
    debugDryingTrace = false,
    rainCleansDebug = false,

    drying = {
        tickInterval = 2000,
        startDelay = 3000,
        buffHoldSeconds = 3
    },
    reconcile = {
        enabled = true,
        wetnessPolicy = "state",
        recoverWetnessFromBuff = true,
        recoveredWetnessPercentByTier = {
            tier1 = 0.10,
            tier2 = 20,
            tier3 = 50,
        },
        retryDelayMs = 1000,
        maxRetries = 5,
    },
    startup = {
        retryDelayMs = 1000,
        maxRetries = 5,
    },
    shelter = {
        applyDelaySec = 1.5,
        releaseHoldSec = 3.0,
    },
    dryingMultiplier = {
        indoorNoFire = 0.001,
        outdoorNoRain = 0.002,
        nearFire = 0.005,
        torch = 0.003,
    },
    rainCleans = {
        CleaningThreshold = 2.0,
        RainIntensityThreshold = 0.3,
        RainIntensityMultiplier = 0.0300,
        TickInterval = 2000
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
        dryingDelayAfterRain = 10
    },
    rainExposureThresholds = {
        mild = 60,
        moderate = 800,
        severe = 1600
    },
    wetnessThresholds = {
        tier1 = { enter = 0.10, exit = 0.05 },
        tier2 = { enter = 20, exit = 15 },
        tier3 = { enter = 50, exit = 45 },
    },
    fireDetection = {
        minStrength = 0.6,
        classes = { fireplacesmartobject = 0.9, forge = 1.2, stove = 0.8 },
        name = {
            fire = 0.5,
            fireplace = 0.9,
            campfire = 0.8,
            blacksmith = 1.0,
            coal = 0.7,
            forge = 1.2,
            oven = 0.9,
            firesmallexterior5 = 0.8,
            ["staticlights/firesmallexterior5"] = 0.8,
            ["firemediuminterior5"] = 0.8,
            ["staticlights/firemediuminterior5"] = 0.8,
        },
        prefab = { fire = 0.6, fireplace = 0.9, forge = 1.2, oven = 0.9 },
        particle = { fire = 0.9, flame = 0.9, ember = 0.6, smoke = 0.3 },
        negative = {
            fireplace_off = true,
            steam_off = true,
            cauldron_empty = true,
            unlit = true,
            extinguished = true,
            playerheadlight = true,
            torch_runtime_prefab = true,
            torchstanding = true,
            ["staticlights/torch"] = true,
        },
        downgradeUnlitStrength = 0.2,
        requireAny = 1,
        proximityMeters = 1.6,
        indoorRadius = 1.5,
        outdoorRadius = 1.5,
        onConsecutive = 2,
        offConsecutive = 2,
    },
    roofRayStartHeight = 0.5,
    roofRayMaxDistance = 10.0,
    roofIgnoreClasses = {
        tree = true,
        bush = true,
        vegetation = true,
        foliage = true,
        grass = true,
        hedge = true,
        shrub = true
    },
}

local function ApplyLoggingProfile()
    local logging = Config.logging or {}
    local profiles = logging.profiles or {}
    local selected = profiles[logging.profile or "quiet"] or profiles.quiet or {}

    for key, value in pairs(selected) do
        Config[key] = value
    end

    for key, value in pairs(logging.overrides or {}) do
        Config[key] = value
    end

    if logging.enabled == false then
        Config.mainDebug = false
        Config.debugReconcile = false
        Config.debugPolling = false
        Config.debugPollTicks = false
        Config.debugIndoorPolling = false
        Config.debugRainTracker = false
        Config.debugBuffLogic = false
        Config.debugRoofDetection = false
        Config.fireDebug = false
        Config.debugFireScan = false
        Config.interiorLogicDebug = false
        Config.debugDrying = false
        Config.debugDryingTrace = false
        Config.rainCleansDebug = false
    end
end

ApplyLoggingProfile()

SanitasInTenebris = SanitasInTenebris or {}
SanitasInTenebris.Config = Config

if Config.logging and Config.logging.moduleLoads then
    System.LogAlways("4$ [Sanitas] Loaded: Config")
end
