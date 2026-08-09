-- RoofDetection.lua
Utils.LogModuleLoaded("RoofDetection")

SanitasInTenebris.RoofDetection = SanitasInTenebris.RoofDetection or {}
local RoofDetection = SanitasInTenebris.RoofDetection

local function RThrot(key, intervalSec, msg)
    Utils.ThrottledLog("roof", key, intervalSec, tostring(msg))
end

local function _lc(s) return (tostring(s or "")):lower() end

function RoofDetection.IsUnderRoof(maxDistance)
    local player = Utils.GetPlayer()
    if not player then return false end

    local pos = player:GetWorldPos() or player:GetPos()
    if not pos then return false end

    local startH = Config.roofRayStartHeight or 0.5
    local rayLen = maxDistance or Config.roofRayMaxDistance or 10.0

    local rayStart = { x = pos.x, y = pos.y, z = pos.z + startH }
    local rayDir = { x = 0, y = 0, z = rayLen }

    local hits = Physics.RayWorldIntersection(rayStart, rayDir, 1, ent_all, player.id)

    if hits and #hits > 0 then
        local hit = hits[1]
        local e = hit.entity
        local cls = _lc(e and e.class or "")
        local ignore = (Config and Config.roofIgnoreClasses) or {}

        if ignore[cls] then
            RThrot("roof_ignore_" .. tostring(cls), 10,
                ("[RoofDetection]: Ignored overhead hit class=%s name=%s")
                :format(cls, e and (e:GetName() or "unnamed") or "nil"))
            return false
        end

        local hx = hit.pos and hit.pos.x or 0
        local hy = hit.pos and hit.pos.y or 0
        local hz = hit.pos and hit.pos.z or 0
        RThrot("roof_hit", 2,
            ("[RoofDetection]: Overhead hit -> roofed | class=%s | name=%s | hit=(%.2f, %.2f, %.2f)")
            :format(cls, e and (e:GetName() or "unnamed") or "nil", hx, hy, hz))
        return true
    end

    RThrot("roof_none", 10, "[RoofDetection]: No overhead geometry detected")
    return false
end
