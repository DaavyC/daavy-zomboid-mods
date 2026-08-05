if not isClient() then return end

local PERIOD_TAG = "RandomZedsPeriod"
local SPEED_TAG = "RandomZedsSpeedType"
local SPRINTER_MULTIPLIER_TAG = "RandomZedsSprinterMultiplier"
local HEALTH_TAG = "RandomZedsHealth"
local REROLL_TAG = "RandomZedsReroll"
local CLIENT_PERIOD_VARIABLE = "RandomZedsClientPeriod"
local CLIENT_REROLL_VARIABLE = "RandomZedsClientReroll"
local COMMAND_MODULE = "RandomZeds"
local STATE_COMMAND = "ZombieState"
local pendingStates = {}
local latestRevisions = {}

local function applyServerState(zombie)
    if not zombie then return false end
    local onlineID = tonumber(zombie:getOnlineID())
    if zombie:isDead() then return true end

    local modData = zombie:getModData()
    local period = modData[PERIOD_TAG]
    local speedType = modData[SPEED_TAG]
    local revision = tonumber(modData[REROLL_TAG]) or 0
    local reroll = tostring(revision)
    if onlineID and latestRevisions[onlineID] and revision < latestRevisions[onlineID] then
        return false
    end

    if not period or not speedType
            or zombie:getVariableString(CLIENT_PERIOD_VARIABLE) == period
                and zombie:getVariableString(CLIENT_REROLL_VARIABLE) == reroll then
        return period ~= nil and speedType ~= nil
    end

    if speedType == "sprinter" then
        RandomZeds.setCrawlerState(zombie, false)
        zombie:doSprinter()
        RandomZeds.setZombieWalkType(zombie, speedType)
        RandomZeds.applySprinterSpeed(zombie, tonumber(modData[SPRINTER_MULTIPLIER_TAG]) or 1.0)
    elseif speedType == "fastShambler" then
        RandomZeds.setCrawlerState(zombie, false)
        zombie:doFastShambler()
        RandomZeds.setZombieWalkType(zombie, speedType)
    elseif speedType == "shambler" then
        RandomZeds.setCrawlerState(zombie, false)
        zombie:doShambler()
        RandomZeds.setZombieWalkType(zombie, speedType)
    elseif speedType == "crawler" then
        RandomZeds.setCrawlerState(zombie, true)
        zombie:doCrawlerSpeed(3)
        RandomZeds.setZombieWalkType(zombie, speedType)
    else
        return false
    end

    local health = tonumber(modData[HEALTH_TAG])
    if health then
        zombie:setHealth(health)
    end

    zombie:setVariable(CLIENT_PERIOD_VARIABLE, period)
    zombie:setVariable(CLIENT_REROLL_VARIABLE, reroll)
    zombie:update()
    return true
end

local function applyCommandState(zombie, state)
    local modData = zombie:getModData()
    modData[PERIOD_TAG] = state.period
    modData[SPEED_TAG] = state.speedType
    modData[SPRINTER_MULTIPLIER_TAG] = state.multiplier
    modData[HEALTH_TAG] = state.health
    modData[REROLL_TAG] = state.reroll
    return applyServerState(zombie)
end

local function findZombie(onlineID)
    local cell = getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then return nil end

    for zombieIndex = 0, zombies:size() - 1 do
        local zombie = zombies:get(zombieIndex)
        if zombie and tonumber(zombie:getOnlineID()) == onlineID then
            return zombie
        end
    end
end

local function applyPendingState(zombie)
    local onlineID = zombie and tonumber(zombie:getOnlineID())
    local state = onlineID and pendingStates[onlineID]
    if not state then return false end

    if not applyCommandState(zombie, state) then return false end
    pendingStates[onlineID] = nil
    return true
end

local function receiveServerState(state)
    if not state then return end

    local onlineID = tonumber(state.id)
    local revision = tonumber(state.reroll)
    if not onlineID or onlineID < 0 or not revision
            or latestRevisions[onlineID] and revision < latestRevisions[onlineID] then
        return
    end

    latestRevisions[onlineID] = revision
    pendingStates[onlineID] = state
    local zombie = findZombie(onlineID)
    if zombie then applyPendingState(zombie) end
end

local function onServerCommand(module, command, packet)
    if module ~= COMMAND_MODULE or command ~= STATE_COMMAND then return end
    if not packet then return end

    if packet.states then
        pcall(function()
            for _, state in pairs(packet.states) do
                receiveServerState(state)
            end
        end)
    else
        receiveServerState(packet)
    end
end

local function refreshLoadedZombies()
    local cell = getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then return end

    for zombieIndex = 0, zombies:size() - 1 do
        local zombie = zombies:get(zombieIndex)
        applyPendingState(zombie)
        applyServerState(zombie)
    end
end

local function onZombieCreate(zombie)
    applyPendingState(zombie)
    applyServerState(zombie)
end

Events.OnZombieCreate.Add(onZombieCreate)
Events.EveryOneMinute.Add(refreshLoadedZombies)
Events.OnServerCommand.Add(onServerCommand)
