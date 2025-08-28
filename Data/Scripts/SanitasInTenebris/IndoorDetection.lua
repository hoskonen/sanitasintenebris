System.LogAlways("4$ [Sanitas] ✅ Loaded: IndoorDetection")

SanitasInTenebris.IndoorDetection = SanitasInTenebris.IndoorDetection or {}
local IndoorDetection = SanitasInTenebris.IndoorDetection

-- Debug gate for indoor detection logs
local function IndoorDbg()
    return Config and (
        (Config.debugIndoorPolling == true) -- new flag
        or (Config.debugPolling == true)    -- piggyback on global polling
        or (Config.interiorLogicDebug == true)
    )
end

local function GetDistance(pos1, pos2)
    if not pos1 or not pos2 then return math.huge end
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    local dz = pos1.z - pos2.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function IndoorDetection.Check()
    if IndoorDbg() then Utils.Log("[IndoorDetection->Check]: IndoorDetection.Check() started") end

    local player = Utils.GetPlayer()
    if not player then
        if IndoorDbg() then Utils.Log("[IndoorDetection->Check]: Utils.GetPlayer() returned nil") end
        return {
            isIndoors = false,
            source = nil,
            entityName = nil,
            debug = "❌ No player entity found"
        }
    end

    local pos = player:GetWorldPos() or player:GetPos()
    if not pos then
        if IndoorDbg() then Utils.Log("[IndoorDetection->Check]: Could not get player position") end
        return {
            isIndoors = false,
            source = nil,
            entityName = nil,
            debug = "[IndoorDetection->Check]: Player has no valid position"
        }
    end

    if IndoorDbg() then
        Utils.Log(string.format("[IndoorDetection->Check]: Player position: x=%.2f y=%.2f z=%.2f", pos.x, pos.y, pos.z))
    end

    local bedRadius = SanitasInTenebris.config.bedDetectionRadius or 2.0
    local doorRadius = SanitasInTenebris.config.doorDetectionRadius or 15.0

    local confidence = 0.0
    local extraSignals = {}
    local foundBed = false

    local closestDoor, closestDistance = nil, nil
    local hasFireplace = false
    local hasFurniture = false
    local hasActivity = false
    local hasBlacksmith = false
    local hasTrespass = false
    local hasAmbience = false
    local hasLadder = false

    local bedTrigger = System.GetNearestEntityByClass(pos, bedRadius, "BedTrigger")
    if bedTrigger then
        local linkedBed = bedTrigger:GetLinkedSmartObject()
        if linkedBed and linkedBed.Properties and linkedBed.Properties.bOwnedByHome then
            if IndoorDbg() then
                Utils.Log("🛏️ Indoor bed detected: " .. tostring(linkedBed:GetName()))
            end
            foundBed = true
            confidence = confidence + 0.7
            table.insert(extraSignals, "bed")
        end
    else
        if IndoorDbg() then Utils.Log("[IndoorDetection->Check]: No BedTrigger found nearby.") end
    end
    if IndoorDbg() then Utils.Log("🛏️ DetectBed result: " .. tostring(foundBed)) end

    local entities = System.GetEntitiesInSphere(pos, doorRadius)
    for _, entity in ipairs(entities) do
        if entity and entity.class then
            local name = string.lower(entity:GetName() or "")
            local class = string.lower(entity.class)

            if class == "animdoor" then
                local dist = GetDistance(entity:GetWorldPos(), pos)
                if not closestDistance or dist < closestDistance then
                    closestDoor = entity
                    closestDistance = dist
                end
            end

            if name:find("fireplace") or class == "fireplacesmartobject" then
                hasFireplace = true
            end

            if name:find("bench") or name:find("table") or name:find("chair") then
                hasFurniture = true
            end

            if name:find("sweeping") or name:find("cooking") or name:find("dogbehavior") then
                hasActivity = true
            end

            if name:find("blacksmith") or name:find("forge") then
                hasBlacksmith = true
            end

            if class == "triggerarea" and name:find("trespass") then
                hasTrespass = true
            end

            if class == "AudioAreaAmbience" and name:find("smithy") then
                hasAmbience = true
            end

            if class == "ladder" then
                hasLadder = true
            end

            if entity.class == "AudioAreaAmbience" then
                if name:find("tavern") or name:find("inn") or name:find("house") or name:find("pub") then
                    if not name:find("out") and not name:find("village") then
                        local dist = GetDistance(entity:GetWorldPos(), pos)
                        if dist <= 2.5 then
                            confidence = confidence + 0.2
                            table.insert(extraSignals, "ambience:interior")
                            if IndoorDbg() then
                                Utils.Log("[IndoorDetection->Check]: Interior Ambience Detected: " ..
                                    name .. " @ " .. string.format("%.2f", dist) .. "m")
                            end
                        end
                    end
                end
            end
        end
    end

    if closestDoor and closestDistance <= SanitasInTenebris.config.maxValidDoorDistance then
        confidence = confidence + 0.2
        table.insert(extraSignals, "door")
        if IndoorDbg() then
            Utils.Log("[IndoorDetection->Check]: Door detected: " .. tostring(closestDoor:GetName())
                .. " @ " .. string.format("%.2f", closestDistance) .. "m")
        end
    end
    if hasFireplace then
        confidence = confidence + 0.2
        table.insert(extraSignals, "fire")
    end
    if hasFurniture then
        confidence = confidence + 0.1
        table.insert(extraSignals, "furn")
    end
    if hasActivity then
        confidence = confidence + 0.1
        table.insert(extraSignals, "work")
    end
    if hasBlacksmith then
        confidence = confidence + 0.2
        table.insert(extraSignals, "forge")
    end
    if hasTrespass then
        confidence = confidence + 0.1
        table.insert(extraSignals, "trespass")
    end
    if hasAmbience then
        confidence = confidence + 0.1
        table.insert(extraSignals, "ambience")
    end
    if hasLadder then
        confidence = confidence + 0.15
        table.insert(extraSignals, "ladder")
    end

    confidence = math.min(confidence, 1.0)
    local isIndoors = (confidence >= 0.7)

    if IndoorDbg() then
        Utils.Log("[IndoorDetection->Check]: Confidence score: " .. string.format("%.2f", confidence))
    end

    return {
        isIndoors = isIndoors,
        confidence = confidence,
        source = table.concat(extraSignals, "+"),
        debug = isIndoors
            and "Indoors based on environment score"
            or "Outdoors, low environment confidence"
    }
end

function IndoorDetection.IsDoor(entity)
    return entity.class == "AnimDoor"
end

function IndoorDetection.IsFireplace(entity)
    local name = string.lower(entity:GetName() or "")
    return name:find("fireplace") or entity.class == "FireplaceSmartObject"
end

function IndoorDetection.IsFurniture(entity)
    local name = string.lower(entity:GetName() or "")
    return name:find("bench") or name:find("table") or name:find("chair")
end

function IndoorDetection.CheckForIndoorHeat()
    local player = Utils.GetPlayer()
    if not player then
        Utils.Log("[IndoorDetection->CheckForIndoorHeat]: CheckForIndoorHeat: player not found")
        return
    end

    -- Debounce to prevent spam every tick (every 1.5s or whatever your pollingInterval is)
    if not State.lastIndoorHeatCheck then
        State.lastIndoorHeatCheck = 0
    end

    local now = System.GetCurrTime()
    if now - State.lastIndoorHeatCheck < 4 then return end
    State.lastIndoorHeatCheck = now

    if IndoorDbg() then
        Utils.Log("[IndoorDetection->CheckForIndoorHeat]: Checking for indoor fire source...")
    end

    local nearFire, strength = HeatDetection.HasNearbyFireSource(Config.fireDetectionRadius or 2.0)
    if nearFire then
        if IndoorDbg() then
            Utils.Log("[IndoorDetection->CheckForIndoorHeat]: Indoor fire detected: strength = " .. tostring(strength))
        end
        BuffLogic.ApplyWarmingBuff(strength)
    else
        if IndoorDbg() then
            Utils.Log("[IndoorDetection->CheckForIndoorHeat]: No indoor heat source found")
        end
        BuffLogic.RemoveWarmingBuff()
    end
end
