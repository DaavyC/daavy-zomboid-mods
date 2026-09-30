local RandomZeds = require "rz_shared"

local Offline = {
    applyAnimationSpeed = RandomZeds.applyZombieAnimationSpeed,
}

function Offline.forEachPlayer(callback)
    local playerCount = getNumActivePlayers()
    for playerIndex = 0, playerCount - 1 do
        local player = getSpecificPlayer(playerIndex)
        if player then callback(player) end
    end
    return true
end

function Offline.registerInitialization(initialize)
    Events.OnGameStart.Add(initialize)
end

return Offline
