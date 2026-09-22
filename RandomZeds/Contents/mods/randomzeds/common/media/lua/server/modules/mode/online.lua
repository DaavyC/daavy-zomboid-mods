local RandomZeds = require "rz_shared"

local Online = {}

local COMMAND_MODULE = "RandomZeds"
local STATE_COMMAND = "ZombieState"
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local REROLL_TAG = "RandomZedsReroll"
local STATE_BATCH_SIZE = 16
local INITIAL_STATE_BUDGET_MS = 3
local STATE_CONFIRMATION_BUDGET_MS = 3
local PENDING_STATE_TIMEOUT_MS = 60000
local rerollRevision = 0
local queuedServerStates = table.newarray()
local pendingServerStates = {}
local pendingStateConfirmations = {}
local serverTick = 0

function Online.forEachPlayer(callback)
    local players = getOnlinePlayers()
    if not players then return false end
    local playerCount = players:size()
    for playerIndex = 0, playerCount - 1 do
        callback(players:get(playerIndex))
    end
    return true
end

function Online.registerInitialization(initialize)
    Events.OnServerStarted.Add(initialize)
end

function Online.resetStateSync()
    pendingServerStates = {}
    pendingStateConfirmations = {}
    queuedServerStates = table.newarray()
    serverTick = 0
end

local function queueIdentifiedServerState(zombie, state, onlineID)
    if RandomZeds.isExcluded(zombie) then return end

    zombie:transmitModData()
    state.id = onlineID
    queuedServerStates[#queuedServerStates + 1] = state
end

local function queueServerState(zombie, state)
    if RandomZeds.isExcluded(zombie) then return end

    local onlineID = zombie:getOnlineID()
    local modData = zombie:getModData()
    if not modData then return end
    local baseSpeed
    if state.speedType == "sprinter" then
        baseSpeed = tonumber(modData[SPRINTER_BASE_SPEED_TAG])
    end
    local synchronizedState = {
        period = state.period,
        speedType = state.speedType,
        multiplier = state.multiplier,
        baseSpeed = baseSpeed,
        health = state.health,
        sight = state.sight,
        hearing = state.hearing,
        cognition = state.cognition,
        strength = state.strength,
        memory = state.memory,
        reroll = tonumber(state.reroll) or tonumber(modData[REROLL_TAG])
            or rerollRevision,
    }

    if not RandomZeds.isValidOnlineID(onlineID) then
        synchronizedState.expiresAt = getTimestampMs() + PENDING_STATE_TIMEOUT_MS
        pendingServerStates[zombie] = synchronizedState
        return
    end

    pendingServerStates[zombie] = nil
    queueIdentifiedServerState(zombie, synchronizedState, onlineID)
end

function Online.flushServerStates()
    local queuedStates = queuedServerStates
    local queuedCount = #queuedStates
    if queuedCount == 0 then return end

    for first = 1, queuedCount, STATE_BATCH_SIZE do
        local states = {}
        local last = math.min(first + STATE_BATCH_SIZE - 1, queuedCount)
        for index = first, last do
            states[#states + 1] = queuedStates[index]
        end
        sendServerCommand(COMMAND_MODULE, STATE_COMMAND, { states = states })
    end

    queuedServerStates = table.newarray()
end

function Online.deferStateConfirmation(zombie, state)
    local modData = zombie:getModData()
    if not modData then return false end
    if state.reroll == nil then
        state.reroll = tonumber(modData[REROLL_TAG]) or rerollRevision
    end
    state.readyTick = serverTick + 1
    state.expiresAt = getTimestampMs() + PENDING_STATE_TIMEOUT_MS
    pendingStateConfirmations[zombie] = state
    return true
end

local function processPendingStateConfirmations()
    local getTimestamp = getTimestampMs
    local now = getTimestamp()
    local deadline = now + STATE_CONFIRMATION_BUDGET_MS
    local visited = 0
    for zombie, state in pairs(pendingStateConfirmations) do
        if visited > 0 and getTimestamp() >= deadline then break end
        visited = visited + 1
        if not zombie:getCurrentSquare() or zombie:isDead()
                or RandomZeds.isExcluded(zombie)
                or now >= state.expiresAt then
            pendingStateConfirmations[zombie] = nil
        elseif serverTick >= state.readyTick and zombie:getSquare()
                and zombie:getCurrentActionContextStateName() ~= "getup"
                and (state.speedType == "crawler" or not zombie:isCrawling()) then
            if RandomZeds.isZombieSpeedTypeApplied(
                    zombie, state.speedType) then
                if state.speedType == "sprinter" then
                    RandomZeds.reconcileSprinterMotion(zombie)
                end
                pendingStateConfirmations[zombie] = nil
                queueServerState(zombie, state)
            end
        end
    end
end

function Online.processPendingServerStates()
    local visited = 0
    local getTimestamp = getTimestampMs
    local now = getTimestamp()
    local deadline = now + INITIAL_STATE_BUDGET_MS
    for zombie, state in pairs(pendingServerStates) do
        if visited > 0 and getTimestamp() >= deadline then break end
        visited = visited + 1
        local onlineID = zombie:getOnlineID()
        if not state or not zombie:getCurrentSquare()
                or zombie:isDead() or RandomZeds.isExcluded(zombie)
                or (state.expiresAt and now >= state.expiresAt) then
            pendingServerStates[zombie] = nil
        elseif RandomZeds.isValidOnlineID(onlineID) then
            pendingServerStates[zombie] = nil
            queueIdentifiedServerState(zombie, state, onlineID)
        end
    end
end

function Online.processNetworkStateWork()
    serverTick = serverTick + 1

    if RandomZeds.hasPendingEntries(pendingStateConfirmations) then
        processPendingStateConfirmations()
    end
    if #queuedServerStates > 0 then
        Online.flushServerStates()
    end
end

function Online.advanceRerollRevision()
    rerollRevision = rerollRevision + 1
end

function Online.persistRerollRevision(modData)
    modData[REROLL_TAG] = rerollRevision
end

return Online
