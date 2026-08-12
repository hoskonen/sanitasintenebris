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

    if SanitasInTenebris.DryingSystem and SanitasInTenebris.DryingSystem.Stop then
        SanitasInTenebris.DryingSystem.Stop("resetWetness")
    end

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
    State.wetnessLevel = nil

    Utils.Log(string.format("[DebugTools->ForceWetness]: Wetness forced to %.2f%% (targetTier=%d)", value, tier))

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

function SIT.DumpDryingStatus()
    local running = false
    local tickCount = nil
    local lastResult = nil

    if PollingManager and PollingManager.GetHealth then
        local health = PollingManager.GetHealth()
        local drying = health and health.DryingLoop
        running = drying ~= nil and drying.active == true
        tickCount = drying and drying.tickCount
        lastResult = drying and drying.lastResult
    end

    local text = string.format(
        "[DebugTools->DumpDryingStatus]: running=%s wetness=%.2f warmingActive=%s warmingType=%s normalBuff=%s fireBuff=%s rainStoppedAt=%s tickCount=%s lastResult=%s",
        tostring(running),
        tonumber(State and State.wetnessPercent) or 0,
        tostring(State and State.warmingActive == true),
        tostring(State and State.warmingType),
        tostring(State and State.normalDryingActive == true),
        tostring(State and State.fireDryingActive == true),
        tostring(State and State.rainStoppedAt),
        tostring(tickCount),
        tostring(lastResult)
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
        HelpLine("sanitas.drying()", "dump drying loop and buff state"),
        HelpLine("sanitas.resetWetness()", "clear wetness and wetness/drying buffs"),
        HelpLine("sanitas.forceWetness(value)", "set wetness percent and refresh tier buffs"),
        HelpLine("sanitas_help()", "safe console alias for sanitas.help()"),
        HelpLine("sanitas_drying()", "safe console alias for sanitas.drying()"),
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

function sanitas.drying()
    return SIT.DumpDryingStatus()
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
_G["sanitas.drying"] = sanitas.drying
_G["sanitas.resetWetness"] = sanitas.resetWetness
_G["sanitas.forceWetness"] = sanitas.forceWetness

sanitas_help = sanitas.help
sanitas_ping = sanitas.ping
sanitas_polls = sanitas.polls
sanitas_shelter = sanitas.shelter
sanitas_drying = sanitas.drying
sanitas_resetWetness = sanitas.resetWetness
sanitas_forceWetness = sanitas.forceWetness
