local RandomZeds = require "rz_shared"

local Offline = {
    pendingZombieCrawlerAllowed = true,
}

local SPEED_TAG = "RandomZedsSpeedType"

function Offline.forEachPlayer(callback)
    local playerCount = getNumActivePlayers()
    for playerIndex = 0, playerCount - 1 do
        local player = getSpecificPlayer(playerIndex)
        if player then callback(player) end
    end
    return true
end

function Offline.applySprinterAnimationSpeed(zombie, multiplier)
    RandomZeds.applySprinterAnimationSpeed(zombie, multiplier)
end

function Offline.shouldDeferPendingZombie(zombie, isCrawlerProtected)
    if not zombie:getSquare() or not isCrawlerProtected(zombie) then
        return false
    end
    local modData = zombie:getModData()
    return zombie:isCrawling() or modData[SPEED_TAG] == "crawler"
end

function Offline.registerInitialization(initialize)
    Events.OnGameStart.Add(initialize)
end

return Offline
