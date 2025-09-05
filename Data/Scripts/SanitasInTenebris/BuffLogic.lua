-- BuffLogic.lua
System.LogAlways("4$ [Sanitas] ✅ Loaded: BuffLogic")

BuffLogic = {}

local function BLog(msg)
    if Config and Config.debugBuffLogic == true then
        Utils.Log(tostring(msg))
    end
end

function BuffLogic.ApplyShelteredBuff(soul)
    if not soul then
        Utils.Log("[BuffLogic->ApplyShelteredBuff]: Soul is nil")
        return
    end

    local guid = Config and Config.buffs and Config.buffs.sheltered
    if not guid then
        Utils.Log("[BuffLogic->ApplyShelteredBuff]: missing sheltered GUID in Config")
        return
    end

    local now                 = System.GetCurrTime()
    local delay               = (Config.shelter and Config.shelter.applyDelaySec) or 0

    -- Start (or continue) the debounce window the first tick we detect shelter.
    -- IMPORTANT: even if buff is already active, we refresh lastSeen each tick.
    State._shelterCandidateAt = State._shelterCandidateAt or now
    State._shelterLastSeenAt  = now

    -- If buff already active, nothing else to do (we still updated lastSeen above).
    if State.shelteredActive then
        if Config.debugBuffLogic then
            BLog("[BuffLogic->ApplyShelteredBuff]: Skipped — already active (debounce maintained)")
        end
        return
    end

    -- Not enough continuous shelter time yet → do not apply
    if (now - State._shelterCandidateAt) < delay then
        if Config.debugBuffLogic then
            BLog("[BuffLogic->ApplyShelteredBuff]: Debouncing… " ..
                string.format("%.2fs / %.2fs", now - State._shelterCandidateAt, delay))
        end
        return
    end

    -- Re-entrancy guard (kept from your original)
    if State._shelterApplying then
        if Config.debugBuffLogic then BLog("[BuffLogic->ApplyShelteredBuff]: Re-entry blocked") end
        return
    end
    State._shelterApplying = true

    -- Defensive: clear any stale copies before adding
    local removed = soul:RemoveAllBuffsByGuid(guid) or 0
    if Config.debugBuffLogic then
        BLog("[BuffLogic->ApplyShelteredBuff]: Removed previous sheltered buff(s): " .. tostring(removed))
    end

    local added = soul:AddBuff(guid)
    if added then
        State.shelteredActive = true
        Utils.Log("[BuffLogic->ApplyShelteredBuff]: Sheltered buff successfully applied (debounced)")
    else
        Utils.Log("[BuffLogic->ApplyShelteredBuff]: Failed to apply sheltered buff")
    end

    State._shelterApplying = false
end

function BuffLogic.RemoveShelteredBuff(player, soul)
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

    local now  = System.GetCurrTime()
    local hold = (Config.shelter and Config.shelter.releaseHoldSec) or 0
    local last = State._shelterLastSeenAt or 0

    -- Hold the buff briefly after leaving shelter to avoid HUD flicker
    if (now - last) < hold then
        if Config.debugBuffLogic then
            BLog("[BuffLogic->RemoveShelteredBuff]: Holding for " ..
                string.format("%.2fs remaining", hold - (now - last)))
        end
        return
    end

    -- Remove and fully reset debounce state so next shelter requires full delay again
    local removed = soul:RemoveAllBuffsByGuid(guid) or 0
    BLog("[BuffLogic->RemoveShelteredBuff]: Buff removed? " .. tostring(removed))

    State.shelteredActive     = false
    State._shelterCandidateAt = nil
    State._shelterLastSeenAt  = nil
    BLog("[BuffLogic->RemoveShelteredBuff]: Guard: State.shelteredActive set to false")
end

function BuffLogic.RemoveWetnessBuffs()
    if not State.isInitialized then
        Utils.Log("[BuffLogic->RemoveWetnessBuffs]: Skipping buff removal — system not initialized")
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

    if debugEnabled then Utils.Log("[BuffLogic->RemoveWetnessBuffs]: Removed wetness-related buffs and reset state") end
end

function BuffLogic.RemoveDryingBuffsOnly()
    if debugEnabled then
        Utils.Log("[BuffLogic->RemoveDryingBuffsOnly]: Called (likely clearing normal drying)")
    end

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
        if Config.debugDrying then Utils.Log("[BuffLogic->RemoveDryingBuffsOnly]: Removed drying buff(s)") end
    else
        if Config.debugDrying then
            Utils.Log(
                "[BuffLogic->RemoveDryingBuffsOnly]: Tried to remove drying buffs — none were active")
        end
    end
end

function BuffLogic.RemoveBuffByGuid(guid)
    local player = Utils.GetPlayer()
    local soul = player and player.soul

    if not soul or not guid then
        Utils.Log("[BuffLogic->RemoveBuffByGuid]: Missing soul or guid")
        return false
    end

    -- Only track state for known drying buff
    local isNormalDrying = guid == Config.buffs.buff_drying_normal

    if isNormalDrying and not State.normalDryingActive then
        Utils.Log("[BuffLogic->RemoveBuffByGuid]: Normal drying buff already removed — skipping")
        return false
    end

    local result = soul:RemoveAllBuffsByGuid(guid)
    Utils.Log("[BuffLogic->RemoveBuffByGuid]: Removed buff with GUID " ..
        tostring(guid) .. " → success=" .. tostring(result))

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

        if Config.debugDrying then
            Utils.Log("[BuffLogic->ApplyDryingBuff]: Applied: buff_drying_firesource (drying)")
        end
    elseif type == "fire_signal" and Config.buffs.buff_drying_firesource then
        -- This is the passive detection (non-drying visual)
        soul:AddBuff(Config.buffs.buff_drying_firesource)
        State.warmingType = "fire_signal"
        State.warmingActive = true
        -- Do not toggle dryingActive states here

        if Config.debugDrying then
            Utils.Log("[BuffLogic->ApplyDryingBuff]: Applied: buff_drying_firesource (signal only)")
        end
    elseif type == "normal" and Config.buffs.buff_drying_normal then
        soul:AddBuff(Config.buffs.buff_drying_normal)
        State.warmingType = "normal"
        State.warmingActive = true
        State.normalDryingActive = true
        State.fireDryingActive = false

        if Config.debugDrying then
            Utils.Log("[BuffLogic->ApplyDryingBuff]: Applied: buff_drying_normal")
        end
    else
        if Config.debugDrying then
            Utils.Log("[BuffLogic->ApplyDryingBuff]: No valid drying type to apply")
        end
    end
end
