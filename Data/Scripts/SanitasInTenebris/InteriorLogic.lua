-- InteriorLogic.lua
Utils.LogModuleLoaded("InteriorLogic")

InteriorLogic = {}

local function ILog(msg)
    Utils.LogIf("interior", tostring(msg))
end

function InteriorLogic.IsPlayerInInterior()
    local player = Utils.GetPlayer()
    if not player then
        ILog("[InteriorLogic]: IsPlayerInInterior: player is nil")
        return false
    end

    local pos = player:GetWorldPos()
    if not pos then
        ILog("[InteriorLogic]: IsPlayerInInterior: player position is nil")
        return false
    end

    local ok, result = pcall(function()
        return XGenAIModule.IsPointInAreaWithLabel(pos, "interior")
    end)

    result = ok and result == true
    if State._lastInteriorLog ~= result then
        ILog("[InteriorLogic]: XGen interior = " .. tostring(result))
        State._lastInteriorLog = result
    end

    return result
end

function InteriorLogic.HandleInteriorState(player, soul)
    if State._indoorInitDone then
        Utils.LogIf("indoor", "[InteriorLogic]: HandleInteriorState skipped; already initialized")
        return
    end

    if not player or not soul then
        Utils.Log("[InteriorLogic]: HandleInteriorState: player or soul is nil")
        return
    end

    State._indoorInitDone = true
    State.pollingSuspended = true

    if SanitasInTenebris.ScheduleExitInterior then
        SanitasInTenebris.ScheduleExitInterior()
    end
    if SanitasInTenebris.ScheduleIndoorPoll then
        SanitasInTenebris.ScheduleIndoorPoll()
    end

    BuffLogic.ApplyShelteredBuff(soul, "Indoors")
    State.wasIndoors = true

    if not State.dryingStarted and SanitasInTenebris.DryingSystem and SanitasInTenebris.DryingSystem.Start then
        State.dryingStarted = true
        local ok, err = pcall(SanitasInTenebris.DryingSystem.Start)
        if ok then
            Utils.LogIf("indoor", "[InteriorLogic]: Started DryingSystem via HandleInteriorState")
        else
            Utils.Log("[InteriorLogic]: DryingSystem.Start failed: " .. tostring(err))
        end
    end
end

SanitasInTenebris.InteriorLogic = InteriorLogic
