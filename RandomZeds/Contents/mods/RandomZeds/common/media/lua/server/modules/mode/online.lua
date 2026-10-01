local RandomZeds = require "rz_shared"

local Online = {}

local COMMAND_MODULE = "RandomZeds"
local STATE_COMMAND = "ZombieState"
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local SPEED_BASE_SPEED_TAG = "RandomZedsSpeedBaseSpeed"
local REROLL_TAG = "RandomZedsReroll"
local SERVER_COMMAND_BUFFER_CAPACITY_BYTES = 1000000
local PENDING_SERVER_STATE_CHECK_INTERVAL_MS = 1000
local PENDING_SERVER_STATE_TIMEOUT_MS = 60000
local SERVER_STATE_FIELDS = table.newarray(
    "period", "speedType", "multiplier", "baseSpeed", "health", "sight",
    "hearing", "cognition", "strength", "memory", "reroll", "id", "restore")
local STORED_STATE_TAGS = {
    period = "RandomZedsPeriod",
    speedType = "RandomZedsSpeedType",
    multiplier = "RandomZedsSprinterMultiplier",
    health = "RandomZedsHealth",
    sight = "RandomZedsSight",
    hearing = "RandomZedsHearing",
    cognition = "RandomZedsCognition",
    strength = "RandomZedsStrength",
    memory = "RandomZedsMemory",
    reroll = REROLL_TAG,
}
local lastStateRequests = setmetatable({}, { __mode = "k" })
local rerollRevision = 0
local queuedServerStates = table.newarray()
local pendingServerStates = {}
local nextPendingServerStateCheckAt = 0

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
    queuedServerStates = table.newarray()
end

local function getEncodedStateSize(state)
    local byteCount = 4
    for fieldIndex = 1, #SERVER_STATE_FIELDS do
        local field = SERVER_STATE_FIELDS[fieldIndex]
        local value = state[field]
        if value ~= nil then
            byteCount = byteCount + 4 + #field
            local valueType = type(value)
            if valueType == "number" then
                byteCount = byteCount + 8
            elseif valueType == "string" then
                byteCount = byteCount + 2 + #value
            elseif valueType == "boolean" then
                byteCount = byteCount + 1
            else
                error("Unsupported zombie state network value: " .. field)
            end
        end
    end
    return byteCount
end

local function queueIdentifiedServerState(zombie, state, onlineID)
    zombie:transmitModData()
    state.id = onlineID
    queuedServerStates[#queuedServerStates + 1] = state
    RandomZeds.debugLog(
        "Queued server state",
        "id", onlineID,
        "type", state.speedType,
        "queue size", #queuedServerStates
    )
end

function Online.queueServerState(zombie, state)
    if RandomZeds.isExcluded(zombie) then return end
    pendingServerStates[zombie] = nil

    local onlineID = zombie:getOnlineID()
    local modData = zombie:getModData()
    if not modData then return end
    local baseSpeed
    if state.speedType == "sprinter" then
        baseSpeed = tonumber(modData[SPRINTER_BASE_SPEED_TAG])
    else
        baseSpeed = tonumber(modData[SPEED_BASE_SPEED_TAG])
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
        pendingServerStates[zombie] = {
            state = synchronizedState,
            queuedAt = getTimestampMs(),
        }
        return
    end

    queueIdentifiedServerState(zombie, synchronizedState, onlineID)
end

local function getEmptyStatePacketSize()
    return 3 + 2 + #COMMAND_MODULE + 2 + #STATE_COMMAND + 1 + 4
        + 1 + 2 + #"states" + 1 + 4
end

local function sendServerStateBatch(states, player)
    if #states > 0 then
        RandomZeds.debugLog("Sending server state packet", "count", #states)
        if player then
            sendServerCommand(player, COMMAND_MODULE, STATE_COMMAND, { states = states })
        else
            sendServerCommand(COMMAND_MODULE, STATE_COMMAND, { states = states })
        end
    end
end

local function getServerStateBatchEnd(queuedStates, firstIndex)
    local packetSize = getEmptyStatePacketSize()
    for stateIndex = firstIndex, #queuedStates do
        local encodedEntrySize = 10 + getEncodedStateSize(queuedStates[stateIndex])
        if packetSize + encodedEntrySize
                > SERVER_COMMAND_BUFFER_CAPACITY_BYTES then
            if stateIndex == firstIndex then
                error("A zombie state exceeds the server command buffer capacity")
            end
            return stateIndex - 1
        end
        packetSize = packetSize + encodedEntrySize
    end
    return #queuedStates
end

local function sendServerStates(queuedStates, player)
    local firstIndex = 1
    while firstIndex <= #queuedStates do
        local lastIndex = getServerStateBatchEnd(queuedStates, firstIndex)
        local states = {}
        for stateIndex = firstIndex, lastIndex do
            states[#states + 1] = queuedStates[stateIndex]
        end
        sendServerStateBatch(states, player)
        firstIndex = lastIndex + 1
    end
end

function Online.flushServerStates()
    sendServerStates(queuedServerStates)
    queuedServerStates = table.newarray()
end

local function snapshotZombieState(zombie)
    local modData = zombie:getModData()
    local onlineID = zombie:getOnlineID()
    if zombie:isDead() or RandomZeds.isExcluded(zombie, modData)
            or not RandomZeds.isValidOnlineID(onlineID)
            or not modData.RandomZedsPeriod or not modData.RandomZedsSpeedType then
        return nil
    end
    local state = { id = onlineID, restore = true }
    for index = 1, #SERVER_STATE_FIELDS do
        local field = SERVER_STATE_FIELDS[index]
        local tag = STORED_STATE_TAGS[field]
        if tag then state[field] = modData[tag] end
    end
    state.baseSpeed = modData[state.speedType == "sprinter"
        and SPRINTER_BASE_SPEED_TAG or SPEED_BASE_SPEED_TAG]
    return state
end

local function onClientCommand(module, command, player)
    if module ~= COMMAND_MODULE or command ~= "RequestStates"
            or not player then return end
    local now = getTimestampMs()
    local previousRequest = lastStateRequests[player]
    if previousRequest and now - previousRequest < 5000 then return end
    lastStateRequests[player] = now
    local states = table.newarray()
    RandomZeds.forEachLoadedZombie(function(zombie)
        local state = snapshotZombieState(zombie)
        if state then states[#states + 1] = state end
    end)
    sendServerStates(states, player)
end

function Online.processPendingServerStates()
    local now = getTimestampMs()
    if now >= nextPendingServerStateCheckAt then
        nextPendingServerStateCheckAt = now
            + PENDING_SERVER_STATE_CHECK_INTERVAL_MS
        for zombie, pendingState in pairs(pendingServerStates) do
            if now - pendingState.queuedAt >= PENDING_SERVER_STATE_TIMEOUT_MS then
                pendingServerStates[zombie] = nil
            elseif not zombie:getCurrentSquare() or zombie:isDead()
                    or RandomZeds.isExcluded(zombie) then
                pendingServerStates[zombie] = nil
            else
                local onlineID = zombie:getOnlineID()
                if RandomZeds.isValidOnlineID(onlineID) then
                    pendingServerStates[zombie] = nil
                    queueIdentifiedServerState(zombie, pendingState.state,
                        onlineID)
                end
            end
        end
    end

    Online.flushServerStates()
end

local function discardPendingServerState(zombie)
    pendingServerStates[zombie] = nil
end

function Online.advanceRerollRevision()
    rerollRevision = rerollRevision + 1
end

function Online.persistRerollRevision(modData)
    local storedRevision = RandomZeds.readOptionalInteger(
        modData[REROLL_TAG], "stored zombie reroll revision") or 0
    rerollRevision = math.max(rerollRevision, storedRevision + 1)
    modData[REROLL_TAG] = rerollRevision
end

Events.OnZombieDead.Add(discardPendingServerState)
Events.OnClientCommand.Add(onClientCommand)

return Online
