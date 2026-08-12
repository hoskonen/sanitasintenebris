SanitasInTenebris.DebugTools = SanitasInTenebris.DebugTools or {}
Utils.LogModuleLoaded("DebugTools")

local SIT = SanitasInTenebris.DebugTools

function SIT.Ping()
    Utils.Log("[DebugTools->Ping]: Debug ping executed successfully")
end

function SIT.ResetWetness()
    local player = Utils.GetPlayer()
    local soul = player and player.soul
    if not player or not soul then return end

    soul:RemoveAllBuffsByGuid(Config.buffs.buff_drying_normal)
    soul:RemoveAllBuffsByGuid(Config.buffs.buff_drying_firesource)
    soul:RemoveAllBuffsByGuid(Config.buffs.buff_wetness_rain_mild)
    soul:RemoveAllBuffsByGuid(Config.buffs.buff_wetness_rain_moderate)
    soul:RemoveAllBuffsByGuid(Config.buffs.buff_wetness_rain_severe)

    State.wetnessLevel = 0
    State.wetnessPercent = 0
    State.warmingType = nil
    State.warmingActive = false

    Utils.Log("[DebugTools->ResetWetness]: Wetness and buffs reset")
end

function SIT.ForceWetness(value)
    value = tonumber(value) or 0

    local tier
    local thresholds = Config.wetnessThresholds

    if value >= thresholds.tier3.enter then
        tier = 3
    elseif value >= thresholds.tier2.enter then
        tier = 2
    elseif value >= thresholds.tier1.enter then
        tier = 1
    else
        tier = 0
    end

    State.wetnessPercent = value
    State.wetnessLevel = tier

    Utils.Log(string.format("[DebugTools->ForceWetness]: Wetness forced to %.2f%% (tier=%d)", value, tier))

    RainTracker.RefreshWetnessBuffTier()
end

function SIT.DumpPollHealth()
    if PollingManager and PollingManager.DumpHealth then
        return PollingManager.DumpHealth()
    end

    Utils.Log("[DebugTools->DumpPollHealth]: PollingManager.DumpHealth unavailable")
    return nil
end

function SIT.DumpShelterStatus()
    local xgen = false
    local roofed = false

    if InteriorLogic and InteriorLogic.IsPlayerInInterior then
        local ok, value = pcall(InteriorLogic.IsPlayerInInterior)
        xgen = ok and value == true
    end

    if SanitasInTenebris.RoofDetection and SanitasInTenebris.RoofDetection.IsUnderRoof then
        local ok, value = pcall(SanitasInTenebris.RoofDetection.IsUnderRoof)
        roofed = ok and value == true
    end

    local text = string.format(
        "[DebugTools->DumpShelterStatus]: xgenInterior=%s roofed=%s shelteredActive=%s pollingSuspended=%s pollMode=%s wasIndoors=%s indoorInitDone=%s roofedOutside=%s",
        tostring(xgen),
        tostring(roofed),
        tostring(State and State.shelteredActive == true),
        tostring(State and State.pollingSuspended == true),
        tostring(PollingManager and PollingManager._mode or "unknown"),
        tostring(State and State.wasIndoors == true),
        tostring(State and State._indoorInitDone == true),
        tostring(State and State.roofedOutside == true)
    )

    Utils.Log(text)
    return text
end

sanitas = sanitas or {}

local function HelpLine(command, description)
    return "  " .. command .. " - " .. description
end

function sanitas.help()
    local lines = {
        "[sanitas.help]: available developer commands",
        HelpLine("sanitas.help()", "show this command list"),
        HelpLine("sanitas.ping()", "verify Sanitas debug commands are loaded"),
        HelpLine("sanitas.polls()", "dump PollingManager health"),
        HelpLine("sanitas.shelter()", "dump XGen/roof/sheltered state"),
        HelpLine("sanitas.resetWetness()", "clear wetness and wetness/drying buffs"),
        HelpLine("sanitas.forceWetness(value)", "set wetness percent and refresh tier buffs"),
        HelpLine("SanitasInTenebris.DebugTools.*", "full debug namespace for advanced calls"),
    }

    local text = table.concat(lines, "\n")
    Utils.Log(text)
    return text
end

function sanitas.ping()
    return SIT.Ping()
end

function sanitas.polls()
    return SIT.DumpPollHealth()
end

function sanitas.shelter()
    return SIT.DumpShelterStatus()
end

function sanitas.resetWetness()
    return SIT.ResetWetness()
end

function sanitas.forceWetness(value)
    return SIT.ForceWetness(value)
end

_G["sanitas.help"] = sanitas.help
_G["sanitas.ping"] = sanitas.ping
_G["sanitas.polls"] = sanitas.polls
_G["sanitas.shelter"] = sanitas.shelter
_G["sanitas.resetWetness"] = sanitas.resetWetness
_G["sanitas.forceWetness"] = sanitas.forceWetness
