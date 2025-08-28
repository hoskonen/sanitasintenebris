-- Utils.lua
System.LogAlways("4$ [Sanitas] ✅ Loaded: Utils")

Utils = {}

-- Safe logging wrapper
function Utils.Log(msg)
    System.LogAlways("4$ [Sanitas] " .. tostring(msg))
end

-- Try to get the player entity
function Utils.GetPlayer()
    return System.GetEntityByName("Henry") or System.GetEntityByName("dude")
end

-- Debug helper: Scan nearby entities with label
function Utils.ScanNearbyEntities(label, radius)
    local player = Utils.GetPlayer()
    if not player then
        Utils.Log("❌ Scan failed: no player")
        return
    end

    local pos = player:GetWorldPos()
    local entities = System.GetEntitiesInSphere(pos, radius or 12)

    Utils.Log("🛰️ Entity scan [" .. label .. "] — found " .. #entities .. " entities")
    for _, entity in ipairs(entities) do
        local name = entity:GetName() or "no-name"
        local class = entity.class or "no-class"
        Utils.Log("🔹 " .. tostring(name) .. " | Class: " .. tostring(class))
    end
end

-- Get all keys from a table
function Utils.GetKeys(tbl)
    local keys = {}
    for k, _ in pairs(tbl or {}) do
        table.insert(keys, k)
    end
    return keys
end

-- Context-aware interior logging
function Utils.LogWithInteriorContext(label, message)
    local indoors = false
    local ok, result = pcall(function()
        return InteriorLogic.IsPlayerInInterior()
    end)
    indoors = ok and result == true

    local context = indoors and "🏠 INSIDE" or "🌧️ OUTSIDE"
    Utils.Log(label .. " [" .. context .. "] " .. message)
end

-- Apply cleaning logic to Henry's body
function Utils.CleanHenryBody(strength)
    local player = Utils.GetPlayer()
    if not player or not player.actor then return end

    local dirtBefore = player.actor:GetDirtiness()
    local cleanStrength = math.min(math.max(strength or 0.3, 0), 1)

    player.actor:CleanDirt(cleanStrength)

    local dirtAfter = player.actor:GetDirtiness()

    if Config.rainCleansDebug then
        Utils.Log(string.format("🧽 Henry cleaned by rain: dirtiness %.2f → %.2f (strength=%.2f)",
            dirtBefore, dirtAfter, cleanStrength))
    end
end

-- Safe accessor for state variables
function Utils.SafeGetState(key, default)
    local ok, value = pcall(function() return State[key] end)
    if not ok or value == nil then
        return default
    end
    return value
end

Utils._loggedOnce = {}

function Utils.LogOnce(key, message)
    if not Config or not Config.enableLogOnce then return end
    if Utils._loggedOnce[key] then return end

    System.LogAlways(message)
    Utils._loggedOnce[key] = true
end

function Utils.SafePollRegister(name, interval, func, repeatable)
    local dbg = Config.debugPolling == true
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
