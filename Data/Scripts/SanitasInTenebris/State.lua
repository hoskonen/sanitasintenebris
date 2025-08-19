-- State.lua
System.LogAlways("4$ [Sanitas] ✅ Loaded: State")

-- 🔒 Ensure top-level State table exists
State                             = State or {}

-- ✅ Pull any existing values (e.g. after reload) for backward safety
local raw                         = rawget(_G, "State") or {}

-- ✅ Explicit default initialization for known fields
raw.shelteredActive               = raw.shelteredActive or false
raw.retryPending                  = raw.retryPending or false
raw.pollingSuspended              = raw.pollingSuspended or false
raw.lastIndoorStatus              = raw.lastIndoorStatus or nil
raw.lastRainLevel                 = raw.lastRainLevel or "none"
raw.wetnessPercent                = raw.wetnessPercent or 0 -- wetnessPercent: true % wetness, 0–100
raw.wetnessLevel                  = raw.wetnessLevel or
    nil                                                     -- wetnessLevel: wetness tier (0–3), derived from %; used for buff tiering only
raw.lastRainEndTime               = raw.lastRainEndTime or 0
raw.interiorDetected              = raw.interiorDetected or false
raw.environmentScoreIndoors       = raw.environmentScoreIndoors or false
raw.lastHeatPollingSuspendedState = raw.lastHeatPollingSuspendedState == true -- force boolean
raw.buffShelteredApplied          = raw.buffShelteredApplied or false
raw.lastRainTickLog               = raw.lastRainTickLog or 0
raw.wasIndoors                    = raw.wasIndoors or false
raw.warmingType                   = raw.warmingType or nil -- "normal", "fire", or nil
raw.warmingActive                 = raw.warmingActive or false
raw.wasDryLogged                  = raw.wasDryLogged or false
raw.normalDryingActive            = raw.normalDryingActive or false
raw.rainStoppedAt                 = raw.rainStoppedAt or nil
raw.isInitialized                 = raw.isInitialized or false
raw.lastRainValue                 = raw.lastRainValue or nil

-- 🧱 Wrap state for guarded writes
local originalState               = raw

State                             = setmetatable({}, {
    __index = originalState,
    __newindex = function(t, k, v)
        if k == "shelteredActive" then
            local stack = debug.traceback("", 2)
            System.LogAlways("4$ [Sanitas] ⚠️ Guard: State.shelteredActive set to " .. tostring(v))
            System.LogAlways("4$ [Sanitas] 🔍 Stack trace:\n" .. stack)
        end
        rawset(originalState, k, v)
    end
})

if k == "warmingType" or k == "warmingActive" then
    System.LogAlways("4$ [Sanitas] 🧠 State." .. k .. " = " .. tostring(v))
end

-- 🌍 Global export
SanitasInTenebris       = SanitasInTenebris or {}
SanitasInTenebris.State = State

-- 🧪 Final confirmation
Utils.Log("🌿 Init: State.shelteredActive = " .. tostring(State.shelteredActive))
