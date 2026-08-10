if not isClient() then return end

local PERIOD_TAG = "RandomZedsPeriod"
local SPEED_TAG = "RandomZedsSpeedType"
local SPRINTER_MULTIPLIER_TAG = "RandomZedsSprinterMultiplier"
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local HEALTH_TAG = "RandomZedsHealth"
local REROLL_TAG = "RandomZedsReroll"
local CLIENT_PERIOD_VARIABLE = "RandomZedsClientPeriod"
local CLIENT_REROLL_VARIABLE = "RandomZedsClientReroll"
local COMMAND_MODULE = "RandomZeds"
local STATE_COMMAND = "ZombieState"
local STATE_CONFIRM_MS = 2000
local pendingStates = {}
local latestRevisions = {}

local function applyServerState(zombie)
    if not zombie then return false end
    local onlineID = tonumber(zombie:getOnlineID())
    if zombie:isDead() then
        return true
    end

    local modData = zombie:getModData()
    local period = modData[PERIOD_TAG]
    local speedType = modData[SPEED_TAG]
    local revision = tonumber(modData[REROLL_TAG]) or 0
    local reroll = tostring(revision)
    if onlineID and latestRevisions[onlineID] and revision < latestRevisions[onlineID] then
        return false
    end

    local alreadyApplied = false
    if period and speedType then
        alreadyApplied = zombie:getVariableString(CLIENT_PERIOD_VARIABLE) == period
            and zombie:getVariableString(CLIENT_REROLL_VARIABLE) == reroll
    end
    if not period or not speedType then
        return false
    end

    local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
    if alreadyApplied and nativeApplied then
        return true
    end

    local gettingUp = zombie:getCurrentActionContextStateName() == "getup"
    if gettingUp then return false end

    if speedType ~= "crawler" and zombie:isCrawling() then
        RandomZeds.setCrawlerState(zombie, false)
        return false
    end

    local multiplier = tonumber(modData[SPRINTER_MULTIPLIER_TAG]) or 1.0
    if not RandomZeds.applyZombieSpeedType(zombie, speedType, multiplier) then
        return false
    end

    local health = tonumber(modData[HEALTH_TAG])
    if health and not alreadyApplied then
        zombie:setHealth(health)
    end

    zombie:setVariable(CLIENT_PERIOD_VARIABLE, period)
    zombie:setVariable(CLIENT_REROLL_VARIABLE, reroll)
    return RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
end

local function applyCommandState(zombie, state)
    local modData = zombie:getModData()
    modData[PERIOD_TAG] = state.period
    modData[SPEED_TAG] = state.speedType
    modData[SPRINTER_MULTIPLIER_TAG] = state.multiplier
    local baseSpeed = tonumber(state.baseSpeed)
    if baseSpeed and baseSpeed > 0 then
        modData[SPRINTER_BASE_SPEED_TAG] = baseSpeed
    end
    modData[HEALTH_TAG] = state.health
    modData[REROLL_TAG] = state.reroll
    return applyServerState(zombie)
end

local function forEachLoadedZombie(callback)
    local cell = getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then return end

    for zombieIndex = 0, zombies:size() - 1 do
        callback(zombies:get(zombieIndex))
    end
end

local function applyPendingState(zombie)
    local onlineID = zombie and tonumber(zombie:getOnlineID())
    local state = onlineID and pendingStates[onlineID]
    if not state then return false end
    if zombie:isDead() then
        pendingStates[onlineID] = nil
        return true
    end

    local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(zombie, state.speedType)
    if not applyCommandState(zombie, state) then
        return false
    end

    local now = getTimestampMs()
    if not nativeApplied then
        state.confirmAfter = now + STATE_CONFIRM_MS
        return false
    end
    if not state.confirmAfter then
        state.confirmAfter = now + STATE_CONFIRM_MS
        return false
    end
    if now < state.confirmAfter then return false end

    pendingStates[onlineID] = nil
    return true
end

local function refreshPendingStates()
    if table.isempty(pendingStates) then return end
    forEachLoadedZombie(applyPendingState)
end

local function receiveServerState(state)
    if not state then
        return
    end

    local onlineID = tonumber(state.id)
    local revision = tonumber(state.reroll)
    if not onlineID or onlineID < 0 or not revision then
        return
    end

    local latestRevision = latestRevisions[onlineID]
    if latestRevision and revision < latestRevision then
        return
    end

    latestRevisions[onlineID] = revision
    pendingStates[onlineID] = state
end

local function onServerCommand(module, command, packet)
    if module ~= COMMAND_MODULE or command ~= STATE_COMMAND then return end
    if not packet then return end

    if packet.states then
        for _, state in pairs(packet.states) do
            receiveServerState(state)
        end
    else
        receiveServerState(packet)
    end
end

local function refreshZombie(zombie)
    return applyPendingState(zombie) or applyServerState(zombie)
end

local function refreshLoadedZombies()
    forEachLoadedZombie(refreshZombie)
end

Events.OnTick.Add(refreshPendingStates)
Events.EveryOneMinute.Add(refreshLoadedZombies)
Events.OnServerCommand.Add(onServerCommand)
