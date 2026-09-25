local RandomZeds = require "rz_shared"

local Online = {}

local COMMAND_MODULE = "RandomZeds"
local STATE_COMMAND = "ZombieState"
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local REROLL_TAG = "RandomZedsReroll"
local SERVER_COMMAND_BUFFER_CAPACITY_BYTES = 1000000
local SERVER_STATE_FIELDS = table.newarray(
    "period", "speedType", "multiplier", "baseSpeed", "health", "sight",
    "hearing", "cognition", "strength", "memory", "reroll", "id")
local rerollRevision = 0
local queuedServerStates = table.newarray()
local pendingServerStates = {}

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
        pendingServerStates[zombie] = synchronizedState
        return
    end

    queueIdentifiedServerState(zombie, synchronizedState, onlineID)
end

local function getEmptyStatePacketSize()
    return 3 + 2 + #COMMAND_MODULE + 2 + #STATE_COMMAND + 1 + 4
        + 1 + 2 + #"states" + 1 + 4
end

local function sendServerStateBatch(states)
    if #states > 0 then
        RandomZeds.debugLog("Sending server state packet", "count", #states)
        sendServerCommand(COMMAND_MODULE, STATE_COMMAND, { states = states })
    end
end

function Online.flushServerStates()
    local queuedStates = queuedServerStates
    local queuedCount = #queuedStates
    if queuedCount == 0 then return end

    local states = {}
    local packetSize = getEmptyStatePacketSize()
    for stateIndex = 1, queuedCount do
        local state = queuedStates[stateIndex]
        local encodedEntrySize = 10 + getEncodedStateSize(state)
        if #states > 0
                and packetSize + encodedEntrySize
                    > SERVER_COMMAND_BUFFER_CAPACITY_BYTES then
            sendServerStateBatch(states)
            states = {}
            packetSize = getEmptyStatePacketSize()
        end
        if packetSize + encodedEntrySize
                > SERVER_COMMAND_BUFFER_CAPACITY_BYTES then
            error("A zombie state exceeds the server command buffer capacity")
        end
        states[#states + 1] = state
        packetSize = packetSize + encodedEntrySize
    end

    sendServerStateBatch(states)
    queuedServerStates = table.newarray()
end

function Online.processPendingServerStates()
    for zombie, state in pairs(pendingServerStates) do
        local onlineID = zombie:getOnlineID()
        if not state or not zombie:getCurrentSquare() or zombie:isDead()
                or RandomZeds.isExcluded(zombie)
                or not RandomZeds.isValidOnlineID(onlineID) then
            pendingServerStates[zombie] = nil
        else
            pendingServerStates[zombie] = nil
            queueIdentifiedServerState(zombie, state, onlineID)
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
    modData[REROLL_TAG] = rerollRevision
end

Events.OnZombieDead.Add(discardPendingServerState)

return Online
