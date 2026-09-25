require "ui/rz_sandbox_settings"

if not isClient() then return end

local RandomZeds = require "rz_shared"

local PERIOD_TAG = "RandomZedsPeriod"
local SPEED_TAG = "RandomZedsSpeedType"
local SPRINTER_MULTIPLIER_TAG = "RandomZedsSprinterMultiplier"
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local HEALTH_TAG = "RandomZedsHealth"
local SIGHT_TAG = "RandomZedsSight"
local HEARING_TAG = "RandomZedsHearing"
local COGNITION_TAG = "RandomZedsCognition"
local STRENGTH_TAG = "RandomZedsStrength"
local MEMORY_TAG = "RandomZedsMemory"
local FEATURES_APPLIED_TAG = "RandomZedsClientFeaturesApplied"
local REROLL_TAG = "RandomZedsReroll"
local CLIENT_PERIOD_VARIABLE = "RandomZedsClientPeriod"
local CLIENT_REROLL_VARIABLE = "RandomZedsClientReroll"
local COMMAND_MODULE = "RandomZeds"
local STATE_COMMAND = "ZombieState"
local authoritativeStates = {}
local loadedZombiesByOnlineID = setmetatable({}, { __mode = "v" })

local function resetZombieTracking()
    authoritativeStates = {}
    loadedZombiesByOnlineID = setmetatable({}, { __mode = "v" })
end

local function discardZombie(zombie)
    if not zombie then return end
    local onlineID = tonumber(zombie:getOnlineID())
    if onlineID then
        loadedZombiesByOnlineID[onlineID] = nil
        authoritativeStates[onlineID] = nil
    end
end

local function validateClientState(state)
    if type(state) ~= "table" then return false end
    state.period = RandomZeds.requireProfilePeriod(state.period)
    if not state.period or not RandomZeds.requireSpeedTypeId(state.speedType) then
        return false
    end
    state.multiplier = RandomZeds.requireSprinterMultiplier(
        state.multiplier, "client zombie state multiplier") or 1.0
    state.health = RandomZeds.requireRange(
        state.health, "client zombie state health", 0.5, 3.8) or 1.5
    state.sight = RandomZeds.requireIntegerRange(
        state.sight, "client zombie state sight", 1, 3) or 2
    state.hearing = RandomZeds.requireIntegerRange(
        state.hearing, "client zombie state hearing", 1, 3) or 2
    state.reroll = RandomZeds.requireInteger(
        state.reroll, "client zombie state reroll") or 0
    if state.speedType == "sprinter" then
        state.baseSpeed = RandomZeds.requireNumber(
            state.baseSpeed, "client zombie state base speed")
        if state.baseSpeed and state.baseSpeed <= 0 then
            state.baseSpeed = nil
        end
    end
    return RandomZeds.validateOptionalFeatureState(state, "Client zombie state")
end

local function isClientFeatureStateApplied(modData, state)
    if not RandomZeds.hasFeatureState(state)
            or not RandomZeds.hasSynapseFeatureSupport() then
        return true
    end
    local featuresApplied = RandomZeds.readOptionalBoolean(
        modData[FEATURES_APPLIED_TAG],
        "stored client feature application flag")
    local storedFeatureState = {
        cognition = RandomZeds.readOptionalInteger(
            modData[COGNITION_TAG], "stored client cognition profile"),
        strength = RandomZeds.readOptionalInteger(
            modData[STRENGTH_TAG], "stored client strength profile"),
        memory = RandomZeds.readOptionalInteger(
            modData[MEMORY_TAG], "stored client memory profile"),
    }
    if not RandomZeds.validateOptionalFeatureState(
            storedFeatureState, "Stored client feature state") then
        return false
    end
    if not featuresApplied then return false end
    return storedFeatureState.cognition == state.cognition
        and storedFeatureState.strength == state.strength
        and storedFeatureState.memory == state.memory
end

local function isClientRevisionApplied(zombie, state)
    return zombie:getVariableString(CLIENT_PERIOD_VARIABLE) == state.period
        and zombie:getVariableString(CLIENT_REROLL_VARIABLE)
            == tostring(state.reroll)
end

local function isClientProfileApplied(modData, state)
    local health = RandomZeds.readOptionalNumber(
        modData[HEALTH_TAG], "stored client zombie health")
    local sight = RandomZeds.readOptionalInteger(
        modData[SIGHT_TAG], "stored client zombie sight")
    local hearing = RandomZeds.readOptionalInteger(
        modData[HEARING_TAG], "stored client zombie hearing")
    if health ~= state.health or sight ~= state.sight
            or hearing ~= state.hearing then
        return false
    end
    return isClientFeatureStateApplied(modData, state)
end

local function isClientSprinterStateApplied(state, modData)
    local currentMultiplier = RandomZeds.readOptionalNumber(
        modData[SPRINTER_MULTIPLIER_TAG], "stored sprinter multiplier")
    local currentBaseSpeed = RandomZeds.readOptionalNumber(
        modData[SPRINTER_BASE_SPEED_TAG], "stored sprinter base speed")
    local multiplier = tonumber(state.multiplier)
    local baseSpeed = tonumber(state.baseSpeed) or currentBaseSpeed
    return multiplier ~= nil and baseSpeed ~= nil
        and currentMultiplier ~= nil and currentBaseSpeed ~= nil
        and math.abs(multiplier - currentMultiplier) <= 0.005
        and math.abs(baseSpeed - currentBaseSpeed) <= 0.005
end

local function isClientStateApplied(zombie, state, modData)
    if not isClientRevisionApplied(zombie, state) then return false end
    modData = modData or zombie:getModData()
    if not modData or modData[SPEED_TAG] ~= state.speedType then return false end
    if not isClientProfileApplied(modData, state) then return false end
    if state.speedType ~= "sprinter" then return true end
    return isClientSprinterStateApplied(state, modData)
end

local function isBlocked(zombie, speedType)
    return (speedType ~= "crawler" and zombie:isCrawling())
        or zombie:getCurrentActionContextStateName() == "getup"
end

local function applyClientSpeedType(zombie, speedType, multiplier)
    if speedType == "sprinter" and zombie.isRemoteZombie
            and zombie:isRemoteZombie() then
        return RandomZeds.applySprinterSpeed(zombie, multiplier)
    end
    return RandomZeds.applyZombieSpeedType(zombie, speedType, multiplier)
end

local function isRemoteScaledSprinterState(zombie, state, modData)
    if not state or state.speedType ~= "sprinter" then return false end

    modData = modData or zombie:getModData()
    if not modData then return false end
    local baseSpeed = tonumber(state.baseSpeed)
        or tonumber(modData[SPRINTER_BASE_SPEED_TAG])
    local multiplier = tonumber(state.multiplier)
        or tonumber(modData[SPRINTER_MULTIPLIER_TAG])
    if not baseSpeed or not multiplier then return false end

    return RandomZeds.isRemoteSprinterSpeedScaled(
        zombie, baseSpeed * multiplier)
end

local function isClientNativeStateApplied(zombie, state, modData)
    if state.speedType == "crawler" and not zombie:isOnFloor() then
        return false
    end
    return isRemoteScaledSprinterState(zombie, state, modData)
        or RandomZeds.isZombieSpeedTypeApplied(zombie, state.speedType)
end

local function writeStateToModData(zombie, state, modData)
    modData = modData or zombie:getModData()
    if not modData then return false end
    local featuresApplied = RandomZeds.hasFeatureState(state)
        and RandomZeds.hasSynapseFeatureSupport()
    modData[PERIOD_TAG] = state.period
    modData[SPEED_TAG] = state.speedType
    modData[SPRINTER_MULTIPLIER_TAG] = state.multiplier
    if state.speedType == "sprinter" then
        local baseSpeed = RandomZeds.requireNumber(
            state.baseSpeed, "client zombie state base speed")
        if baseSpeed and baseSpeed > 0 then
            modData[SPRINTER_BASE_SPEED_TAG] = baseSpeed
        end
    else
        modData[SPRINTER_BASE_SPEED_TAG] = nil
    end
    modData[HEALTH_TAG] = state.health
    modData[SIGHT_TAG] = state.sight
    modData[HEARING_TAG] = state.hearing
    modData[COGNITION_TAG] = state.cognition
    modData[STRENGTH_TAG] = state.strength
    modData[MEMORY_TAG] = state.memory
    modData[FEATURES_APPLIED_TAG] = featuresApplied
    modData[REROLL_TAG] = state.reroll
    return true
end

local function makeModDataState(zombie, modData)
    modData = modData or zombie:getModData()
    if not modData then return nil end
    local period = modData[PERIOD_TAG]
    local speedType = modData[SPEED_TAG]
    if period == nil and speedType == nil then
        return nil
    end
    if period == nil or speedType == nil then return nil end
    local state = {
        period = period,
        speedType = speedType,
        multiplier = modData[SPRINTER_MULTIPLIER_TAG],
        baseSpeed = modData[SPRINTER_BASE_SPEED_TAG],
        health = modData[HEALTH_TAG],
        sight = modData[SIGHT_TAG],
        hearing = modData[HEARING_TAG],
        cognition = modData[COGNITION_TAG],
        strength = modData[STRENGTH_TAG],
        memory = modData[MEMORY_TAG],
        reroll = modData[REROLL_TAG],
    }
    return state
end

local function applyFreshClientStateValues(zombie, state)
    RandomZeds.applyZombieNativeStats(zombie, state.sight, state.hearing)
    RandomZeds.applyZombieFeatureState(zombie, state)
    if not applyClientSpeedType(
            zombie, state.speedType, tonumber(state.multiplier) or 1.0) then
        return false
    end
    local health = tonumber(state.health)
    if health then zombie:setHealth(health) end
    return true
end

local function reapplyClientStateValues(zombie, state)
    return applyClientSpeedType(
        zombie, state.speedType, tonumber(state.multiplier) or 1.0)
end

local function applyValidatedClientState(zombie, state, modData)
    local speedType = state.speedType
    local alreadyApplied = isClientStateApplied(zombie, state, modData)
    if alreadyApplied and isClientNativeStateApplied(zombie, state, modData) then
        if speedType == "sprinter" then
            RandomZeds.reconcileSprinterMotion(zombie)
        end
        return true
    end

    local appliedValues
    if alreadyApplied then
        appliedValues = reapplyClientStateValues(zombie, state)
    else
        appliedValues = applyFreshClientStateValues(zombie, state)
    end
    if not appliedValues then
        return false
    end

    zombie:setVariable(CLIENT_PERIOD_VARIABLE, state.period)
    zombie:setVariable(CLIENT_REROLL_VARIABLE,
        tostring(tonumber(state.reroll) or 0))
    if not writeStateToModData(zombie, state, modData) then return false end
    if speedType == "sprinter" then
        RandomZeds.reconcileSprinterMotion(zombie)
    end
    local applied = RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
    return applied
end

local function applyClientState(zombie, state, modData)
    if not zombie then return false end
    modData = modData or zombie:getModData()
    if RandomZeds.isExcluded(zombie, modData) then return true end
    if zombie:isDead() then return true end
    if not validateClientState(state) then return false end
    if not zombie:getCurrentSquare() or isBlocked(zombie, state.speedType) then
        return false
    end
    return applyValidatedClientState(zombie, state, modData)
end

local function getCachedZombie(onlineID)
    local zombie = onlineID and loadedZombiesByOnlineID[onlineID]
    if not zombie then return nil end
    if tonumber(zombie:getOnlineID()) ~= onlineID
            or zombie:isDead() or not zombie:getCurrentSquare() then
        loadedZombiesByOnlineID[onlineID] = nil
        return nil
    end
    return zombie
end

local function cacheLoadedZombie(zombie)
    local onlineID = zombie and tonumber(zombie:getOnlineID())
    if not RandomZeds.isValidOnlineID(onlineID) then return nil end
    loadedZombiesByOnlineID[onlineID] = zombie
    return onlineID
end

local function refreshStoredZombieState(zombie, state, modData)
    if not state or isBlocked(zombie, state.speedType) then return end

    if not isClientStateApplied(zombie, state, modData)
            or not isClientNativeStateApplied(zombie, state, modData) then
        applyClientState(zombie, state, modData)
    end
end

local function refreshLoadedZombieState(zombie, onlineID)
    local modData = zombie:getModData()
    if RandomZeds.isExcluded(zombie, modData) then
        if onlineID then authoritativeStates[onlineID] = nil end
        return
    end

    local state = onlineID and authoritativeStates[onlineID]
    if state then
        local stateRevision = tonumber(state.reroll) or 0
        local storedRevision = tonumber(modData and modData[REROLL_TAG])
        local appliedRevision = tonumber(
            zombie:getVariableString(CLIENT_REROLL_VARIABLE))
        if (storedRevision and storedRevision > stateRevision)
                or (appliedRevision and appliedRevision > stateRevision) then
            state = makeModDataState(zombie, modData)
            if not state or not validateClientState(state) then return end
            authoritativeStates[onlineID] = state
        end
    else
        state = makeModDataState(zombie, modData)
    end

    if state and validateClientState(state) then
        if onlineID then authoritativeStates[onlineID] = state end
        refreshStoredZombieState(zombie, state, modData)
    end
end

local function processLoadedZombie(zombie)
    if not zombie then return end
    if zombie:isDead() then
        discardZombie(zombie)
        return
    end
    if not zombie:getCurrentSquare() then
        return
    end
    local onlineID = cacheLoadedZombie(zombie)
    refreshLoadedZombieState(zombie, onlineID)
end

local function refreshLoadedZombies()
    loadedZombiesByOnlineID = setmetatable({}, { __mode = "v" })
    RandomZeds.debugLog("Starting client zombie state reconciliation")
    RandomZeds.forEachLoadedZombie(function(zombie)
        processLoadedZombie(zombie)
    end)
    RandomZeds.refreshSprinterAnimationSpeeds()
end

local function validateServerStateIdentity(state)
    if type(state) ~= "table" then return nil, nil end
    local onlineID = RandomZeds.requireInteger(
        state.id, "server zombie state online id")
    local revision = RandomZeds.requireInteger(
        state.reroll, "server zombie state reroll")
    if not RandomZeds.isValidOnlineID(onlineID) or not revision or revision < 0 then
        return nil, nil
    end
    return onlineID, revision
end

local function receiveValidatedServerState(state, onlineID, revision)
    local latestState = authoritativeStates[onlineID]
    local latestRevision = latestState and tonumber(latestState.reroll)
    local zombie = getCachedZombie(onlineID)
    if zombie then
        local modData = zombie:getModData()
        local storedRevision = tonumber(modData and modData[REROLL_TAG])
        local appliedRevision = tonumber(
            zombie:getVariableString(CLIENT_REROLL_VARIABLE))
        if storedRevision and (not latestRevision or storedRevision > latestRevision) then
            latestRevision = storedRevision
        end
        if appliedRevision and (not latestRevision or appliedRevision > latestRevision) then
            latestRevision = appliedRevision
        end
    end
    if latestRevision and revision < latestRevision then
        RandomZeds.debugLog(
            "Ignored stale server state",
            "id", onlineID,
            "revision", revision,
            "latest revision", latestRevision
        )
        return
    end

    authoritativeStates[onlineID] = state
    if zombie then
        local applied = applyClientState(zombie, state)
        RandomZeds.debugLog(
            "Received server state",
            "id", onlineID,
            "revision", revision,
            "type", state.speedType,
            "applied", applied
        )
    else
        RandomZeds.debugLog(
            "Stored server state for unloaded zombie",
            "id", onlineID,
            "revision", revision,
            "type", state.speedType
        )
    end
end

local function onServerCommand(module, command, packet)
    if module ~= COMMAND_MODULE or command ~= STATE_COMMAND then return end
    if type(packet) ~= "table" then return end
    if packet.states ~= nil then
        if type(packet.states) ~= "table" then return end
        local states = packet.states
        RandomZeds.debugLog("Received server state packet", "count", #states)
        for index = 1, #states do
            local state = states[index]
            if validateClientState(state) then
                local onlineID, revision = validateServerStateIdentity(state)
                if onlineID then
                    receiveValidatedServerState(state, onlineID, revision)
                end
            end
        end
    else
        if not validateClientState(packet) then return end
        local onlineID, revision = validateServerStateIdentity(packet)
        if onlineID then
            receiveValidatedServerState(packet, onlineID, revision)
        end
    end
end

local function onConnected()
    resetZombieTracking()
    RandomZeds.forceVanillaPerceptionDefaults()
end

local function onDisconnect()
    resetZombieTracking()
end

local function onGameStart()
    RandomZeds.forceVanillaPerceptionDefaults()
    refreshLoadedZombies()
end

local function onZombieDead(zombie)
    discardZombie(zombie)
end

Events.EveryOneMinute.Add(refreshLoadedZombies)
Events.OnServerCommand.Add(onServerCommand)
Events.OnConnected.Add(onConnected)
Events.OnDisconnect.Add(onDisconnect)
Events.OnGameStart.Add(onGameStart)
Events.OnZombieDead.Add(onZombieDead)
Events.OnZombieCreate.Add(processLoadedZombie)
