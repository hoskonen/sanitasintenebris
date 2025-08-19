-- InteriorLogic.lua
System.LogAlways("4$ [Sanitas] ✅ Loaded: InteriorLogic")

InteriorLogic = {}
local debugEnabled = Config.interiorLogicDebug == true

function InteriorLogic.IsPlayerInInterior()
    local player = Utils.GetPlayer()
    if not player then
        if debugEnabled then
            Utils.Log("⚠️ [InteriorLogic]: IsPlayerInInterior: player is nil")
        end
        return false
    end

    local pos = player:GetPos()
    if not pos then
        if debugEnabled then
            Utils.Log("⚠️ [InteriorLogic]: IsPlayerInInterior: player position is nil")
        end
        return false
    end

    local result = XGenAIModule.IsPointInAreaWithLabel(pos, "interior") == true

    if debugEnabled and State._lastInteriorLog ~= result then
        Utils.Log("🏠 [InteriorLogic]: XGenAIModule result for 'interior' = " .. tostring(result))
        State._lastInteriorLog = result
    end

    return result
end

function InteriorLogic.HandleInteriorState(player, soul)
    if not player or not soul then
        Utils.Log("❌ [InteriorLogic]: HandleInteriorState: player or soul is nil — skipping indoor logic")
        return
    end

    State.pollingSuspended = true

    Script.SetTimerForFunction(3000, "SanitasInTenebris.CheckExitInterior")
    Script.SetTimerForFunction(Config.pollingInterval, "SanitasInTenebris.IndoorPoll")

    BuffLogic.ApplyShelteredBuff(soul)
    State.wasIndoors = true

    -- 💧 Ensure DryingSystem is running
    if not State.dryingStarted then
        State.dryingStarted = true
        Utils.Log("💧 [InteriorLogic]: Started DryingSystem via HandleInteriorState()")
        SanitasInTenebris.DryingSystem.Start()
    end
end
