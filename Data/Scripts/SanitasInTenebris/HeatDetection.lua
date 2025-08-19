-- 🔥 HeatDetection.lua
System.LogAlways("4$ [Sanitas] ✅ Loaded: HeatDetection")

SanitasInTenebris.HeatDetection = SanitasInTenebris.HeatDetection or {}
local HeatDetection = SanitasInTenebris.HeatDetection
_G["HeatDetection"] = SanitasInTenebris.HeatDetection

local debugEnabled = Config.fireDebug == true

-- Returns: nearFire (bool), fireStrength (float)
-- Strength can be used to differentiate strong forge vs weak campfire
function HeatDetection.HasNearbyFireSource(radius)
    radius = radius or 3.0
    if debugEnabled then
        Utils.Log("[HeatDetection->HasNearbyFireSource]: Entered HasNearbyFireSource with radius=" .. tostring(radius))
    end

    local player = Utils.GetPlayer()
    if not player then
        Utils.Log("[HeatDetection->HasNearbyFireSource]: No player found")
        return false, 0.0
    end

    local pos = player:GetWorldPos()
    if not pos then
        Utils.Log("[HeatDetection->HasNearbyFireSource]: No player position found")
        return false, 0.0
    end

    if debugEnabled then
        Utils.Log("[HeatDetection->HasNearbyFireSource]: Player pos: x=" ..
            tostring(pos.x) .. ", y=" .. tostring(pos.y) .. ", z=" .. tostring(pos.z))
    end

    local entities = System.GetEntitiesInSphere(pos, radius)
    if not entities then
        Utils.Log("[HeatDetection->HasNearbyFireSource]: No entities returned in sphere check")
        return false, 0.0
    end

    if debugEnabled then
        Utils.Log("[Heat Detection]: 🔎 Scanning " .. tostring(#entities) .. " entities for fire sources")
    end

    local hasSmartFire = false
    local hasUnlitFire = false
    local bestStrength = 0.0

    for _, e in ipairs(entities) do
        local name = (type(e.GetName) == "function") and e:GetName() or "unknown"
        local class = tostring(e.class or "unknown")
        local prefab = (type(e.GetPrefabName) == "function") and e:GetPrefabName() or "N/A"

        local particleEffect = "—"
        if type(e.GetScriptTable) == "function" then
            local script = e:GetScriptTable()
            if type(script) == "table" and type(script.ParticleEffect) == "string" then
                particleEffect = script.ParticleEffect
            end
        end
        if debugEnabled then
            Utils.Log(("[HeatDetection->HasNearbyFireSource]: Entity: name='%s' | class='%s' | prefab='%s' | particle='%s'")
                :format(name, class, prefab, particleEffect))
        end

        local lname = string.lower(name)
        local lclass = string.lower(class)

        -- 🔕 Skipping unlit detection re-enable as needed
        -- if lname:find("fireplace_off") or lname:find("cauldron_empty") then
        --     hasUnlitFire = true
        --     Utils.Log("🔥⚠️ Detected unlit fire: " .. lname)
        -- end

        local strength = Config.fireSourceClasses[lclass]
        if strength then
            hasSmartFire = true
            bestStrength = strength
            if debugEnabled then
                Utils.Log("Matched fire class: " .. lname .. " [" .. lclass .. "] → " .. tostring(strength))
            end
        else
            for keyword, s in pairs(Config.fireSourceClasses) do
                if lname:find(keyword) then
                    hasSmartFire = true
                    bestStrength = s
                    if debugEnabled then
                        Utils.Log("[HeatDetection->HasNearbyFireSource]: Matched fire by name: " ..
                            lname .. " [" .. lclass .. "] → " .. tostring(s))
                    end
                    break
                end
            end
        end
    end

    if hasSmartFire and hasUnlitFire then
        if debugEnabled then
            Utils.Log("[HeatDetection->HasNearbyFireSource]: Fire downgraded due to nearby unlit prefab")
        end
        return true, 0.2
    elseif hasSmartFire then
        return true, bestStrength
    elseif hasUnlitFire then
        return true, 0.2
    else
        if debugEnabled then
            Utils.Log("[HeatDetection->HasNearbyFireSource]: No fire source found nearby")
        end
        return false, 0.0
    end
end
