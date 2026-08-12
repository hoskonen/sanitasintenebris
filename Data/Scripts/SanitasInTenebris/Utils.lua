-- Utils.lua
Utils = Utils or {}

function Utils.Log(msg)
    System.LogAlways("4$ [Sanitas] " .. tostring(msg))
end

function Utils.LogModuleLoaded(name)
    if Config and Config.logging and Config.logging.moduleLoads then
        Utils.Log("Loaded: " .. tostring(name))
    end
end

local _logFlagByCategory = {
    main = "mainDebug",
    polling = "debugPolling",
    indoor = "debugIndoorPolling",
    interior = "interiorLogicDebug",
    rain = "debugRainTracker",
    buff = "debugBuffLogic",
    roof = "debugRoofDetection",
    fire = "fireDebug",
    fire_trace = "debugFireScan",
    drying = "debugDrying",
    drying_trace = "debugDryingTrace",
    rain_cleans = "rainCleansDebug",
}

function Utils.IsLogEnabled(category)
    if not Config or (Config.logging and Config.logging.enabled == false) then
        return false
    end

    local flag = _logFlagByCategory[category] or category
    return Config[flag] == true
end

function Utils.LogIf(category, msg)
    if Utils.IsLogEnabled(category) then
        Utils.Log(msg)
        return true
    end
    return false
end

Utils._throttled = Utils._throttled or {}

function Utils.ThrottledCh(channel, key, intervalSec, msg)
    channel = tostring(channel or "default")
    key = tostring(key or "default")

    local now = System.GetCurrTime()
    local channelState = Utils._throttled[channel] or {}
    Utils._throttled[channel] = channelState

    local nextAt = channelState[key]
    if not nextAt or now >= nextAt then
        Utils.Log(tostring(msg))
        channelState[key] = now + (intervalSec or 5)
        return true
    end
    return false
end

function Utils.ThrottledLog(category, key, intervalSec, msg)
    if not Utils.IsLogEnabled(category) then return false end
    return Utils.ThrottledCh(category, key, intervalSec, msg)
end

Utils.LogModuleLoaded("Utils")

function Utils.GetPlayer()
    return System.GetEntityByName("Henry") or System.GetEntityByName("dude")
end

function Utils.ScanNearbyEntities(label, radius)
    local player = Utils.GetPlayer()
    if not player then
        Utils.Log("Scan failed: no player")
        return
    end

    local pos = player:GetWorldPos()
    local entities = System.GetEntitiesInSphere(pos, radius or 12)

    Utils.Log("Entity scan [" .. tostring(label) .. "] found " .. tostring(#entities) .. " entities")
    for _, entity in ipairs(entities) do
        local name = entity:GetName() or "no-name"
        local class = entity.class or "no-class"
        Utils.Log(tostring(name) .. " | Class: " .. tostring(class))
    end
end

function Utils.GetKeys(tbl)
    local keys = {}
    for k, _ in pairs(tbl or {}) do
        table.insert(keys, k)
    end
    return keys
end

function Utils.LogWithInteriorContext(label, message)
    local ok, result = pcall(function()
        return InteriorLogic.IsPlayerInInterior()
    end)
    local context = (ok and result == true) and "INSIDE" or "OUTSIDE"
    Utils.Log(tostring(label) .. " [" .. context .. "] " .. tostring(message))
end

function Utils.CleanHenryBody(strength)
    local player = Utils.GetPlayer()
    if not player or not player.actor then return end

    local dirtBefore = player.actor:GetDirtiness()
    local cleanStrength = math.min(math.max(strength or 0.3, 0), 1)

    player.actor:CleanDirt(cleanStrength)

    local dirtAfter = player.actor:GetDirtiness()

    if Utils.IsLogEnabled("rain_cleans") then
        Utils.Log(string.format("Henry cleaned by rain: dirtiness %.2f -> %.2f (strength=%.2f)",
            dirtBefore, dirtAfter, cleanStrength))
    end
end

function Utils.SafeGetState(key, default)
    local ok, value = pcall(function() return State[key] end)
    if not ok or value == nil then
        return default
    end
    return value
end

Utils._loggedOnce = Utils._loggedOnce or {}

function Utils.LogOnce(key, message)
    if not Config or not Config.enableLogOnce then return end
    if Utils._loggedOnce[key] then return end

    Utils.Log(message)
    Utils._loggedOnce[key] = true
end

function Utils.SafePollRegister(name, interval, func, repeatable)
    local dbg = Utils.IsLogEnabled("polling")
    if dbg then Utils.Log("[SafePoll] PollingManager = " .. tostring(PollingManager)) end
    if dbg then
        Utils.Log("[SafePoll] PollingManager.Register = " ..
            tostring(PollingManager and PollingManager.Register))
    end
    if type(name) ~= "string" then
        Utils.Log("[SafePoll] Invalid name: " .. tostring(name))
        return
    end

    if type(func) ~= "function" then
        Utils.Log("[SafePoll] Invalid function for poll '" .. name .. "': got " .. tostring(func))
        return
    end

    if dbg then
        Utils.Log("[SafePoll] Registering: " ..
            name .. " (interval=" .. tostring(interval) .. ", repeat=" .. tostring(repeatable) .. ")")
    end
    PollingManager.Register(name, interval, func, repeatable)
end

function Utils.IsTorchEquipped()
    local player = Utils.GetPlayer()
    if not player or not player.human then return false end

    local left = player.human:GetItemInHand(HS_LEFT)
    local right = player.human:GetItemInHand(HS_RIGHT)

    local function isTorch(id)
        local item = ItemManager.GetItem(id)
        local name = item and ItemManager.GetItemName(item.class)
        return name == "torch_weapon"
    end

    return isTorch(left) or isTorch(right)
end
