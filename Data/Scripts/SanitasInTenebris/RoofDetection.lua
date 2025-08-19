System.LogAlways("4$ [Sanitas] ✅ Loaded: RoofDetection")

SanitasInTenebris.RoofDetection = {}

function SanitasInTenebris.RoofDetection.IsUnderRoof(maxDistance)
    local player = Utils.GetPlayer()
    if not player then return false end

    local origin = player:GetWorldPos()
    local direction = { x = 0, y = 0, z = 1 } -- Upward
    maxDistance = maxDistance or 5.0

    local hits = Physics.RayWorldIntersection(origin, direction, maxDistance, ent_static)

    if hits and #hits > 0 then
        if Config.debugRoofDetection then
            Utils.Log("🧱 [RoofDetection]: Overhead hit detected — likely under a roof")
        end
        return true
    else
        if Config.debugRoofDetection then
            Utils.Log("🌞 [RoofDetection]: No overhead geometry detected — likely outdoors")
        end
        return false
    end
end
