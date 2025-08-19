System.LogAlways("4$ [Sanitas] ✅ DebugTools.lua loaded")
SanitasInTenebris.DebugTools = {}

local SIT = SanitasInTenebris.DebugTools

function SIT.Ping()
    System.LogAlways("🔧 [DebugTools->Ping]: Debug ping executed successfully!")
end

function SIT.ResetWetness()
    local player = Utils.GetPlayer()
    local soul = player and player.soul
    if not player or not soul then return end

    -- Remove drying buffs
    soul:RemoveAllBuffsByGuid(Config.buffs.buff_drying_normal)
    soul:RemoveAllBuffsByGuid(Config.buffs.buff_drying_firesource)

    -- Remove wetness debuffs
    soul:RemoveAllBuffsByGuid(Config.buffs.buff_wetness_rain_mild)
    soul:RemoveAllBuffsByGuid(Config.buffs.buff_wetness_rain_moderate)
    soul:RemoveAllBuffsByGuid(Config.buffs.buff_wetness_rain_severe)

    State.wetnessLevel = 0
    State.wetnessPercent = 0
    State.warmingType = nil
    State.warmingActive = false

    System.LogAlways("🧼 [DebugTools->ResetWetness]: Wetness + buffs reset")
end

function SIT.ForceWetness(value)
    local tier
    if value >= Config.thresholds.t3.enter then
        tier = 3
    elseif value >= Config.thresholds.t2.enter then
        tier = 2
    elseif value >= Config.thresholds.t1.enter then
        tier = 1
    else
        tier = 0
    end

    State.wetnessPercent = value
    State.wetnessLevel = tier

    Utils.Log(string.format("🧪 [DebugTools->ForceWetness]: Wetness forced to %.2f%% (tier = %d)", value, tier))

    RainTracker.RefreshWetnessBuffTier()
end
