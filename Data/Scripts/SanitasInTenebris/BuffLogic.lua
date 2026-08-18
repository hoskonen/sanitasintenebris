-- BuffLogic.lua
Utils.LogModuleLoaded("BuffLogic")

BuffLogic = {}

local function BLog(msg)
    Utils.LogIf("buff", tostring(msg))
end

local function DLog(msg)
    Utils.LogIf("drying", tostring(msg))
end

local function RemoveByGuid(soul, guid)
    if not soul or not guid or guid == "" then return 0 end

    local ok, removed = pcall(function()
        return soul:RemoveAllBuffsByGuid(guid)
    end)

    if not ok then
        Utils.Log("[BuffLogic->RemoveByGuid]: Failed for " .. tostring(guid) .. ": " .. tostring(removed))
        return 0
    end

    return tonumber(removed) or (removed and 1) or 0
end

function BuffLogic.ApplyShelteredBuff(soul, reason)
    reason = reason or "Unknown"

    if not soul then
        Utils.Log("[BuffLogic->ApplyShelteredBuff]: Soul is nil")
        return
    end

    local guid = Config and Config.buffs and Config.buffs.sheltered
    if not guid then
        Utils.Log("[BuffLogic->ApplyShelteredBuff]: missing sheltered GUID in Config")
        return
    end

    local now = System.GetCurrTime()
    local delay = (Config.shelter and Config.shelter.applyDelaySec) or 0

    State._shelterCandidateAt = State._shelterCandidateAt or now
    State._shelterLastSeenAt = now

    if State.shelteredActive then
        BLog("[BuffLogic->ApplyShelteredBuff]: Already active -> " .. tostring(reason))
        return
    end

    if (now - State._shelterCandidateAt) < delay then
        Utils.ThrottledLog("buff", "shelter_debounce", 2,
            "[BuffLogic->ApplyShelteredBuff]: Debouncing -> " .. tostring(reason) .. " " ..
            string.format("%.2fs / %.2fs", now - State._shelterCandidateAt, delay))
        return
    end

    if State._shelterApplying then
        BLog("[BuffLogic->ApplyShelteredBuff]: Re-entry blocked")
        return
    end
    State._shelterApplying = true

    local removed = RemoveByGuid(soul, guid)
    BLog("[BuffLogic->ApplyShelteredBuff]: Removed previous sheltered buff(s): " .. tostring(removed))
    BLog("[BuffLogic->ApplyShelteredBuff]: Adding Sheltered Buff -> " .. tostring(reason))

    local added = soul:AddBuff(guid)
    if added then
        State.shelteredActive = true
        BLog("[BuffLogic->ApplyShelteredBuff]: Added Sheltered Buff -> " .. tostring(reason))
    else
        Utils.Log("[BuffLogic->ApplyShelteredBuff]: Failed to apply sheltered buff")
    end

    State._shelterApplying = false
end

function BuffLogic.RemoveShelteredBuff(player, soul, reason)
    reason = reason or "Unknown"

    soul = soul or (player and player.soul)
    if not soul then
        Utils.Log("[BuffLogic->RemoveShelteredBuff]: soul is nil")
        return
    end

    local guid = Config and Config.buffs and Config.buffs.sheltered
    if not guid then
        Utils.Log("[BuffLogic->RemoveShelteredBuff]: missing sheltered GUID in Config")
        return
    end

    local now = System.GetCurrTime()
    local hold = (Config.shelter and Config.shelter.releaseHoldSec) or 0
    local last = State._shelterLastSeenAt or 0

    if (now - last) < hold then
        Utils.ThrottledLog("buff", "shelter_hold", 2,
            "[BuffLogic->RemoveShelteredBuff]: Holding " ..
            string.format("%.2fs remaining", hold - (now - last)))
        return
    end

    local removed = RemoveByGuid(soul, guid)
    BLog("[BuffLogic->RemoveShelteredBuff]: Removing Sheltered Buff -> " .. tostring(reason) ..
        " success=" .. tostring(removed))

    State.shelteredActive = false
    State._shelterCandidateAt = nil
    State._shelterLastSeenAt = nil
end

function BuffLogic.RemoveWetnessBuffs()
    if not State.isInitialized then
        BLog("[BuffLogic->RemoveWetnessBuffs]: Skipping; system not initialized")
        return
    end

    local player = Utils.GetPlayer()
    local soul = player and player.soul
    if not soul then return end

    RemoveByGuid(soul, Config.buffs.buff_wetness_rain_mild)
    RemoveByGuid(soul, Config.buffs.buff_wetness_rain_moderate)
    RemoveByGuid(soul, Config.buffs.buff_wetness_rain_severe)

    State.wetnessLevel = nil
    State.warmingActive = false

    BLog("[BuffLogic->RemoveWetnessBuffs]: Removed wetness buffs")
end

function BuffLogic.RemoveDryingBuffsOnly()
    local player = Utils.GetPlayer()
    local soul = player and player.soul
    if not soul then return end

    local removed = false

    if Config.buffs.buff_drying_normal then
        local ok = RemoveByGuid(soul, Config.buffs.buff_drying_normal) > 0
        removed = removed or ok
        if ok then State.normalDryingActive = false end
    end

    if Config.buffs.buff_drying_firesource then
        local ok = RemoveByGuid(soul, Config.buffs.buff_drying_firesource) > 0
        removed = removed or ok
        if ok then State.fireDryingActive = false end
    end

    if removed then
        DLog("[BuffLogic->RemoveDryingBuffsOnly]: Removed drying buff(s)")
    else
        DLog("[BuffLogic->RemoveDryingBuffsOnly]: No drying buffs were active")
    end
end

function BuffLogic.RemoveBuffByGuid(guid)
    local player = Utils.GetPlayer()
    local soul = player and player.soul

    if not soul or not guid then
        Utils.Log("[BuffLogic->RemoveBuffByGuid]: Missing soul or guid")
        return false
    end

    local isNormalDrying = guid == Config.buffs.buff_drying_normal

    if isNormalDrying and not State.normalDryingActive then
        DLog("[BuffLogic->RemoveBuffByGuid]: Normal drying buff already removed; skipping")
        return false
    end

    local result = RemoveByGuid(soul, guid) > 0
    DLog("[BuffLogic->RemoveBuffByGuid]: Removed buff " .. tostring(guid) .. " success=" .. tostring(result))

    if isNormalDrying and result then
        State.normalDryingActive = false
    end

    return result
end

function BuffLogic.RemoveSanitasRuntimeBuffs(soul, options)
    options = options or {}
    local buffs = Config and Config.buffs or {}
    if not soul then
        Utils.Log("[BuffLogic->RemoveSanitasRuntimeBuffs]: soul is nil")
        return 0
    end

    local total = 0
    local removed = {
        shelter = 0,
        dryingNormal = 0,
        dryingFire = 0,
        wetnessTier1 = 0,
        wetnessTier2 = 0,
        wetnessTier3 = 0,
    }

    if options.shelter ~= false then
        removed.shelter = RemoveByGuid(soul, buffs.sheltered)
        total = total + removed.shelter
        State.shelteredActive = false
        State._shelterCandidateAt = nil
        State._shelterLastSeenAt = nil
    end

    if options.drying ~= false then
        removed.dryingNormal = RemoveByGuid(soul, buffs.buff_drying_normal)
        removed.dryingFire = RemoveByGuid(soul, buffs.buff_drying_firesource)
        total = total + removed.dryingNormal + removed.dryingFire
        State.warmingActive = false
        State.warmingType = nil
        State.normalDryingActive = false
        State.fireDryingActive = false
    end

    if options.wetness ~= false then
        removed.wetnessTier1 = RemoveByGuid(soul, buffs.buff_wetness_rain_mild)
        removed.wetnessTier2 = RemoveByGuid(soul, buffs.buff_wetness_rain_moderate)
        removed.wetnessTier3 = RemoveByGuid(soul, buffs.buff_wetness_rain_severe)
        total = total + removed.wetnessTier1 + removed.wetnessTier2 + removed.wetnessTier3
        State.wetnessLevel = nil
    end

    Utils.LogIf("reconcile", string.format(
        "[BuffLogic->RemoveSanitasRuntimeBuffs]: removed=%s shelter=%s dryingNormal=%s dryingFire=%s wet1=%s wet2=%s wet3=%s",
        tostring(total),
        tostring(removed.shelter),
        tostring(removed.dryingNormal),
        tostring(removed.dryingFire),
        tostring(removed.wetnessTier1),
        tostring(removed.wetnessTier2),
        tostring(removed.wetnessTier3)))
    return total, removed
end

function BuffLogic.ApplyDryingBuff(type)
    local player = Utils.GetPlayer()
    local soul = player and player.soul
    if not soul then return end

    if State.warmingActive and State.warmingType == type then
        return
    end

    if type == "fire" and Config.buffs.buff_drying_firesource then
        soul:AddBuff(Config.buffs.buff_drying_firesource)
        State.warmingType = "fire"
        State.warmingActive = true
        State.fireDryingActive = true
        State.normalDryingActive = false
        DLog("[BuffLogic->ApplyDryingBuff]: Applied fire drying")
    elseif type == "fire_signal" and Config.buffs.buff_drying_firesource then
        soul:AddBuff(Config.buffs.buff_drying_firesource)
        State.warmingType = "fire_signal"
        State.warmingActive = true
        DLog("[BuffLogic->ApplyDryingBuff]: Applied fire signal")
    elseif type == "normal" and Config.buffs.buff_drying_normal then
        soul:AddBuff(Config.buffs.buff_drying_normal)
        State.warmingType = "normal"
        State.warmingActive = true
        State.normalDryingActive = true
        State.fireDryingActive = false
        DLog("[BuffLogic->ApplyDryingBuff]: Applied normal drying")
    else
        DLog("[BuffLogic->ApplyDryingBuff]: No valid drying type to apply")
    end
end
