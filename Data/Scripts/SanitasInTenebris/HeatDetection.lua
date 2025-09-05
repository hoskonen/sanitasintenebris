-- 🔥 HeatDetection.lua
System.LogAlways("4$ [Sanitas] ✅ Loaded: HeatDetection")

SanitasInTenebris.HeatDetection = SanitasInTenebris.HeatDetection or {}
local HeatDetection = SanitasInTenebris.HeatDetection
_G["HeatDetection"] = SanitasInTenebris.HeatDetection

local debugEnabled = Config.fireDebug == true

local function HLog(msg)
    if Config and Config.fireDebug == true then
        Utils.Log(tostring(msg))
    end
end

-- add after HLog(...) in HeatDetection.lua
local FD = Config.fireDetection or {}

local function _empty(t) return (not t) or (next(t) == nil) end
if _empty(FD.classes) and _empty(FD.name) and _empty(FD.prefab) and _empty(FD.particle) then
    if Config.fireDebug then
        Utils.Log("[HeatDetection] ⚠️ fireDetection has no match rules (classes/name/prefab/particle empty)")
    end
end

-- plain, case-insensitive contains
local function contains(haystack, needle)
    if not haystack or not needle then return false end
    return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
end

local function scoreFromList(s, list)
    local best = 0
    if not s then return best end
    for k, v in pairs(list or {}) do
        if contains(s, k) then best = (v > best) and v or best end
    end
    return best
end

-- Classify one entity → positiveStrength (0..), negativeFlag, debugReason
local function classifyEntity(e)
    local name     = (type(e.GetName) == "function") and (e:GetName() or "") or ""
    local class    = tostring(e.class or "")
    local prefab   = (type(e.GetPrefabName) == "function") and (e:GetPrefabName() or "") or ""
    local particle = ""
    if type(e.GetScriptTable) == "function" then
        local st = e:GetScriptTable()
        if type(st) == "table" and type(st.ParticleEffect) == "string" then
            particle = st.ParticleEffect
        end
    end

    local lc = string.lower(class)
    local pos = 0
    -- exact class strength
    if FD.classes and FD.classes[lc] then pos = math.max(pos, FD.classes[lc]) end
    -- name/prefab/particle strengths (best match wins)
    pos = math.max(pos, scoreFromList(name, FD.name))
    pos = math.max(pos, scoreFromList(prefab, FD.prefab))
    pos = math.max(pos, scoreFromList(particle, FD.particle))

    local neg = false
    for k, _ in pairs(FD.negative or {}) do
        if contains(name, k) or contains(prefab, k) or contains(particle, k) then
            neg = true; break
        end
    end

    return pos, neg, string.format("class=%s name=%s prefab=%s particle=%s", class, name, prefab, particle)
end


-- Returns: nearFire (bool), fireStrength (float)
-- Strength can be used to differentiate strong forge vs weak campfire
function HeatDetection.HasNearbyFireSource(radius)
    -- base radius from config
    radius = radius or FD.radius or 1.0

    -- clamp radius by interior state
    local indoors = false
    if InteriorLogic and InteriorLogic.IsPlayerInInterior then
        local ok, res = pcall(InteriorLogic.IsPlayerInInterior)
        indoors = ok and (res == true)
    end
    radius = indoors and (FD.indoorRadius or radius) or (FD.outdoorRadius or radius)

    if debugEnabled then
        HLog(("[HeatDetection->HasNearbyFireSource]: radius=%.2f (indoors=%s)"):format(radius, tostring(indoors)))
    end

    local player = Utils.GetPlayer()
    if not player then
        Utils.Log("[HeatDetection->HasNearbyFireSource]: No player found")
        return false, 0.0
    end

    local pos = player:GetWorldPos() or player:GetPos()
    if not pos then
        Utils.Log("[HeatDetection->HasNearbyFireSource]: No player position found")
        return false, 0.0
    end

    if debugEnabled then
        HLog(("[HeatDetection->HasNearbyFireSource]: pos=(%.2f, %.2f, %.2f)")
            :format(pos.x or 0, pos.y or 0, pos.z or 0))
    end

    local entities = System.GetEntitiesInSphere(pos, radius)
    if not entities then
        Utils.Log("[HeatDetection->HasNearbyFireSource]: No entities returned in sphere check")
        return false, 0.0
    end
    if debugEnabled then
        HLog(("🔎 [HeatDetection]: scanning %d entities"):format(#entities))
    end

    -- NOTE: initialize to numeric sentinels; avoids engine complaints about nil math args
    local bestStrength   = 0.0
    local positiveHits   = 0
    local closestPosDist = math.huge -- numeric sentinel; "no positive seen" = still huge

    for _, e in ipairs(entities) do
        local s, neg, why = classifyEntity(e)

        -- per-entity effective strength (only this entity’s negatives can downgrade it)
        local eff = s
        if neg and s > 0 and FD.downgradeUnlitStrength then
            eff = math.min(s, FD.downgradeUnlitStrength)
        end

        if debugEnabled then
            HLog(string.format("[HeatDetection]: scan s=%.2f neg=%s eff=%.2f :: %s",
                s, tostring(neg), eff, why))
        end

        if eff > 0 then
            positiveHits = positiveHits + 1
            if eff > bestStrength then bestStrength = eff end

            -- distance to this positive/effective entity
            local epos = (type(e.GetWorldPos) == "function" and e:GetWorldPos())
                or (type(e.GetPos) == "function" and e:GetPos())
            if epos and pos then
                local dx       = (epos.x - pos.x); local dy = (epos.y - pos.y); local dz = (epos.z - pos.z)
                local d        = math.sqrt(dx * dx + dy * dy + dz * dz)
                closestPosDist = math.min(closestPosDist, d)
            end
        end
    end

    -- gates
    local minS                = tonumber(FD.minStrength or 0.6)
    local prox                = tonumber(FD.proximityMeters or (indoors and 1.6 or 1.8))
    local inProx              = (closestPosDist <= prox) -- safe: closestPosDist is numeric

    local rawGot, rawStrength = false, 0.0
    if positiveHits >= (FD.requireAny or 1) and inProx and (bestStrength >= minS) then
        rawGot      = true
        rawStrength = bestStrength
    end

    -- stability gate (prevents flicker: need N consecutive confirmations)
    State._fireSense = State._fireSense or { active = false, pos = 0, neg = 0, strength = 0.0 }
    local S          = State._fireSense
    local ON         = tonumber(FD.onConsecutive or 2)
    local OFF        = tonumber(FD.offConsecutive or 2)

    if rawGot and rawStrength > 0 then
        S.pos      = (S.pos or 0) + 1
        S.neg      = 0
        S.strength = rawStrength
        if not S.active and S.pos >= ON then
            S.active = true
            if debugEnabled then HLog(string.format("[HeatDetection]: 🔥 ON (pos=%d, strength=%.2f)", S.pos, S.strength)) end
        end
    else
        S.neg = (S.neg or 0) + 1
        S.pos = 0
        if S.active and S.neg >= OFF then
            S.active   = false
            S.strength = 0.0
            if debugEnabled then HLog(string.format("[HeatDetection]: 🔻 OFF (neg=%d)", S.neg)) end
        end
    end

    return (S.active == true), (S.strength or 0.0)
end
