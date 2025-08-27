System.LogAlways("4$ [Sanitas] ✅ Loaded: RoofDetection")

SanitasInTenebris.RoofDetection = SanitasInTenebris.RoofDetection or {}
local RoofDetection = SanitasInTenebris.RoofDetection
RoofDetection._rt = RoofDetection._rt or {} -- ← init throttle store once
local function RThrot(key, intervalSec, msg)
    if not (Config and Config.debugRoofDetection == true) then return end
    if Utils and type(Utils.ThrottledCh) == "function" then
        Utils.ThrottledCh("roof", key, intervalSec, tostring(msg))
        return
    end
    local now = System.GetCurrTime()
    local nextAt = RoofDetection._rt[key]
    if not nextAt or now >= nextAt then
        Utils.Log(tostring(msg))
        RoofDetection._rt[key] = now + (intervalSec or 5)
    end
end
local function _lc(s) return (tostring(s or "")):lower() end

function SanitasInTenebris.RoofDetection.IsUnderRoof(maxDistance)
    local player = Utils.GetPlayer()
    if not player then return false end

    local pos = player:GetWorldPos() or player:GetPos()
    if not pos then return false end

    local startH   = Config.roofRayStartHeight or 0.5
    local rayLen   = maxDistance or Config.roofRayMaxDistance or 10.0

    -- Start slightly above head, cast straight up for rayLen meters
    local rayStart = { x = pos.x, y = pos.y, z = pos.z + startH }
    local rayDir   = { x = 0, y = 0, z = rayLen }

    -- IMPORTANT: 3rd arg = nMaxHits (not distance!). Direction magnitude encodes distance.
    -- Use ent_all and skip the player entity so we don't hit our own capsule.
    local hits     = Physics.RayWorldIntersection(rayStart, rayDir, 1, ent_all, player.id)

    if hits and #hits > 0 then
        local hit    = hits[1]
        local e      = hit.entity
        local cls    = _lc(e and e.class or "")
        local ignore = (Config and Config.roofIgnoreClasses) or {}

        if ignore[cls] then
            if Config.debugRoofDetection then
                RThrot("roof_ignore_" .. tostring(cls), 10,
                    ("🪵 [RoofDetection]: Ignored overhead hit (class=%s, name=%s)")
                    :format(cls, e and (e:GetName() or "unnamed") or "nil"))
            end
            return false
        end

        if Config.debugRoofDetection then
            local hx, hy, hz = hit.pos and hit.pos.x or 0, hit.pos and hit.pos.y or 0, hit.pos and hit.pos.z or 0
            RThrot("roof_hit", 2,
                ("🧱 [RoofDetection]: Overhead hit → roofed | class=%s | name=%s | hit=(%.2f, %.2f, %.2f)")
                :format(cls, e and (e:GetName() or "unnamed") or "nil", hx, hy, hz))
        end
        return true
    else
        if Config.debugRoofDetection then
            RThrot("roof_none", 5, "🌞 [RoofDetection]: No overhead geometry detected — not roofed")
        end
        return false
    end
end
