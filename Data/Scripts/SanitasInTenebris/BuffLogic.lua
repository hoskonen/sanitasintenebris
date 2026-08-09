-- BuffLogic.lua
Utils.LogModuleLoaded("BuffLogic")

BuffLogic = {}

local function BLog(msg)
    Utils.LogIf("buff", tostring(msg))
end

local function DLog(msg)
    Utils.LogIf("drying", tostring(msg))
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

    local removed = soul:RemoveAllBuffsByGuid(guid) or 0
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

    local removed = soul:RemoveAllBuffsByGuid(guid) or 0
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

    soul:RemoveAllBuffsByGuid(Config.buffs.buff_wetness_rain_mild)
    soul:RemoveAllBuffsByGuid(Config.buffs.buff_wetness_rain_moderate)
    soul:RemoveAllBuffsByGuid(Config.buffs.buff_wetness_rain_severe)

    State.wetnessLevel = nil
    State.warmingActive = false

    BLog("[BuffLogic->RemoveWetnessBuffs]: Removed wetness buffs")
end

function BuffLogic.RemoveDryingBuffsOnly()
    DLog("[BuffLogic->RemoveDryingBuffsOnly]: Called")

    local player = Utils.GetPlayer()
    local soul = player and player.soul
    if not soul then return end

    local removed = false

    if Config.buffs.buff_drying_normal then
        local ok = soul:RemoveAllBuffsByGuid(Config.buffs.buff_drying_normal)
        removed = removed or ok
        if ok then State.normalDryingActive = false end
    end

    if Config.buffs.buff_drying_firesource then
        local ok = soul:RemoveAllBuffsByGuid(Config.buffs.buff_drying_firesource)
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

    local result = soul:RemoveAllBuffsByGuid(guid)
    DLog("[BuffLogic->RemoveBuffByGuid]: Removed buff " .. tostring(guid) .. " success=" .. tostring(result))

    if isNormalDrying and result then
        State.normalDryingActive = false
    end

    return result
end

function BuffLogic.ApplyDryingBuff(type)
    local player = Utils.GetPlayer()
    local soul = player and player.soul
    if not soul then return end

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
