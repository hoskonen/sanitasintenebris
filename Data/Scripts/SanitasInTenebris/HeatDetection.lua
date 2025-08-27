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

-- Returns: nearFire (bool), fireStrength (float)
-- Strength can be used to differentiate strong forge vs weak campfire
function HeatDetection.HasNearbyFireSource(radius)
    radius = radius or 3.0
    if debugEnabled then
        HLog(("[HeatDetection->HasNearbyFireSource]: radius=%.2f"):format(radius))
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
                HLog(("🔥 match class: %s [%s] → %.2f"):format(lname, lclass, strength))
            end
        else
            for keyword, s in pairs(Config.fireSourceClasses) do
                if lname:find(keyword) then
                    hasSmartFire = true
                    bestStrength = s
                    if debugEnabled then
                        HLog(("🔥 match name: %s [%s] → %.2f"):format(lname, lclass, s))
                    end
                    break
                end
            end
        end
    end

    if hasSmartFire and hasUnlitFire then
        HLog("[HeatDetection->HasNearbyFireSource]: fire found but downgraded (unlit nearby) → strength=0.20")
        return true, 0.2
    elseif hasSmartFire then
        HLog(("[HeatDetection->HasNearbyFireSource]: fire nearby → strength=%.2f"):format(bestStrength))
        return true, bestStrength
    elseif hasUnlitFire then
        HLog("[HeatDetection->HasNearbyFireSource]: unlit fire nearby → strength=0.20")
        return true, 0.2
    else
        HLog("[HeatDetection->HasNearbyFireSource]: no fire nearby")
        return false, 0.0
    end
end
