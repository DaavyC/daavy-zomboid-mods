if not isClient() then return end

local RandomZeds = require "randomzedsshared"

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
local STATE_RETRY_MS = 100
local STATE_PENDING_TIMEOUT_MS = 60000
local STATE_CONFIRM_STABLE_CHECKS = 2
local RECONCILE_BUDGET_MS = 4
local SPRINTER_CHECK_COOLDOWN_MS = 1000
local ANIMATION_REFRESH_WINDOW_MS = 250
local SPRINTER_WATCHDOG_STALL_MS = 750
local SPRINTER_WATCHDOG_COOLDOWN_MS = 2000
local pendingStates = {}
local authoritativeStates = {}
local latestRevisions = {}
local pendingOrder = {}
local pendingQueued = {}
local pendingCursor = 1
local loadedZombieCursor = { index = 0 }
local loadedZombiesByOnlineID = setmetatable({}, { __mode = "v" })
local sprinterCheckCooldowns = setmetatable({}, { __mode = "k" })
local applicationStates = setmetatable({}, { __mode = "k" })
local watchdogStates = {}
local clientTick = 0

local function resetClientState()
    pendingStates = {}
    authoritativeStates = {}
    latestRevisions = {}
    pendingOrder = {}
    pendingQueued = {}
    pendingCursor = 1
    loadedZombieCursor = { index = 0 }
    loadedZombiesByOnlineID = setmetatable({}, { __mode = "v" })
    sprinterCheckCooldowns = setmetatable({}, { __mode = "k" })
    applicationStates = setmetatable({}, { __mode = "k" })
    watchdogStates = {}
    clientTick = 0
end

local function markApplication(zombie, now)
    applicationStates[zombie] = {
        tick = clientTick,
        appliedAt = now,
    }
end

local function isApplicationPending(zombie)
    local application = applicationStates[zombie]
    if not application then return false end
    return clientTick <= application.tick
        or getTimestampMs() - application.appliedAt
            < ANIMATION_REFRESH_WINDOW_MS
end

local function validateClientState(state)
    if type(state) ~= "table" then error("Client zombie state must be a table") end
    RandomZeds.requireProfilePeriod(state.period)
    RandomZeds.requireSpeedTypeId(state.speedType)
    RandomZeds.requireSprinterMultiplier(
        state.multiplier, "client zombie state multiplier")
    RandomZeds.requireRange(
        state.health, "client zombie state health", 0.5, 3.8)
    RandomZeds.requireIntegerRange(
        state.sight, "client zombie state sight", 1, 3)
    RandomZeds.requireIntegerRange(
        state.hearing, "client zombie state hearing", 1, 3)
    RandomZeds.requireInteger(
        state.reroll, "client zombie state reroll")
    if state.speedType == "sprinter" then
        RandomZeds.requireNumber(
            state.baseSpeed, "client zombie state base speed")
        if state.baseSpeed <= 0 then
            error("Client zombie state base speed must be positive")
        end
    end
    RandomZeds.validateOptionalFeatureState(state, "Client zombie state")
end

local function isClientFeatureStateApplied(modData, state)
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
    RandomZeds.validateOptionalFeatureState(
        storedFeatureState, "Stored client feature state")
    if not RandomZeds.hasFeatureState(state)
            or not RandomZeds.hasSynapseFeatureSupport() then
        return true
    end
    if not featuresApplied then return false end
    return storedFeatureState.cognition == state.cognition
        and storedFeatureState.strength == state.strength
        and storedFeatureState.memory == state.memory
end

local function isClientStateApplied(zombie, state)
    local period = state.period
    local revision = tostring(state.reroll)
    if zombie:getVariableString(CLIENT_PERIOD_VARIABLE) ~= period
            or zombie:getVariableString(CLIENT_REROLL_VARIABLE) ~= revision then
        return false
    end
    local modData = zombie:getModData()
    if not modData then error("Zombie mod data is required") end
    if modData[SPEED_TAG] ~= state.speedType then return false end
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
    if not isClientFeatureStateApplied(modData, state) then return false end
    if state.speedType ~= "sprinter" then return true end
    local multiplier = RandomZeds.requireNumber(
        state.multiplier, "client zombie state multiplier")
    local baseSpeed = RandomZeds.requireNumber(
        state.baseSpeed, "client zombie state base speed")
    local currentMultiplier = RandomZeds.readOptionalNumber(
        modData[SPRINTER_MULTIPLIER_TAG], "stored sprinter multiplier")
    local currentBaseSpeed = RandomZeds.readOptionalNumber(
        modData[SPRINTER_BASE_SPEED_TAG], "stored sprinter base speed")
    return currentMultiplier ~= nil and currentBaseSpeed ~= nil
        and math.abs(multiplier - currentMultiplier) <= 0.005
        and math.abs(baseSpeed - currentBaseSpeed) <= 0.005
end

local function isBlocked(zombie)
    return zombie:isCrawling()
        or zombie:getCurrentActionContextStateName() == "getup"
end

local function applyClientSpeedType(zombie, speedType, multiplier)
    if speedType == "sprinter" and zombie:isRemoteZombie() then
        RandomZeds.applySprinterSpeed(zombie, multiplier)
        return
    end
    RandomZeds.applyZombieSpeedType(zombie, speedType, multiplier)
end

local function isRemoteScaledSprinterState(zombie, state)
    if state.speedType ~= "sprinter" then return false end

    local baseSpeed = RandomZeds.requireNumber(
        state.baseSpeed, "client zombie state base speed")
    local multiplier = RandomZeds.requireNumber(
        state.multiplier, "client zombie state multiplier")

    return RandomZeds.isRemoteSprinterSpeedScaled(
        zombie, baseSpeed * multiplier)
end

local function writeStateToModData(zombie, state)
    local modData = zombie:getModData()
    if not modData then error("Zombie mod data is required") end
    local featuresApplied = RandomZeds.hasFeatureState(state)
        and RandomZeds.hasSynapseFeatureSupport()
    modData[PERIOD_TAG] = state.period
    modData[SPEED_TAG] = state.speedType
    modData[SPRINTER_MULTIPLIER_TAG] = state.multiplier
    if state.speedType == "sprinter" then
        modData[SPRINTER_BASE_SPEED_TAG] = state.baseSpeed
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
end

local function makeModDataState(zombie)
    local modData = zombie:getModData()
    if not modData then error("Zombie mod data is required") end
    local period = modData[PERIOD_TAG]
    local speedType = modData[SPEED_TAG]
    if period == nil and speedType == nil then
        return nil
    end
    if period == nil or speedType == nil then
        error("Zombie mod data state is incomplete")
    end
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
    validateClientState(state)
    return state
end

local function isLoadedStateRefreshDue(zombie, now)
    local cooldownAt = sprinterCheckCooldowns[zombie]
    if cooldownAt == nil then
        cooldownAt = 0
    else
        cooldownAt = RandomZeds.requireNumber(
            cooldownAt, "sprinter check cooldown")
    end
    return now >= cooldownAt
end

local function scheduleLoadedStateRefresh(zombie, now)
    sprinterCheckCooldowns[zombie] = now + SPRINTER_CHECK_COOLDOWN_MS
end

local function applyState(zombie, state)
    if not zombie then error("Zombie is required") end
    validateClientState(state)

    local speedType = state.speedType
    local multiplier = RandomZeds.requireNumber(
        state.multiplier, "client zombie state multiplier")
    local alreadyApplied = isClientStateApplied(zombie, state)
    local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)

    if alreadyApplied and nativeApplied then
        if speedType == "sprinter" then
            RandomZeds.reconcileSprinterMotion(zombie)
        end
        return true
    end

    local now = getTimestampMs()
    if not RandomZeds.dispatchZombieState(zombie, state) then
        if not alreadyApplied then
            RandomZeds.applyZombieNativeStats(zombie, state.sight, state.hearing)
            RandomZeds.applyZombieFeatureState(zombie, state)
        end
        applyClientSpeedType(zombie, speedType, multiplier)
        if not alreadyApplied then
            zombie:setHealth(RandomZeds.requireNumber(
                state.health, "client zombie state health"))
        end
    end

    zombie:setVariable(CLIENT_PERIOD_VARIABLE, state.period)
    zombie:setVariable(CLIENT_REROLL_VARIABLE,
        tostring(RandomZeds.requireInteger(
            state.reroll, "client zombie state reroll")))
    writeStateToModData(zombie, state)
    if speedType == "sprinter" then
        RandomZeds.reconcileSprinterMotion(zombie)
    end
    local applied = RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
    if applied and not alreadyApplied then markApplication(zombie, now) end
    return applied
end

local function removePendingState(onlineID)
    pendingStates[onlineID] = nil
    pendingQueued[onlineID] = nil
end

local function reconcilePendingState(zombie, state, now)
    local onlineID = zombie:getOnlineID()
    if RandomZeds.isExcluded(zombie) or zombie:isDead() then
        removePendingState(onlineID)
        return true
    end
    if now >= state.expiresAt then
        removePendingState(onlineID)
        return true
    end
    if not zombie:getSquare() or isBlocked(zombie) then return false end
    if now < state.retryAfter then return false end

    local nextRetryAfter = now + STATE_RETRY_MS
    if applyState(zombie, state) then
        state.stableChecks = state.stableChecks + 1
    else
        state.stableChecks = 0
    end
    state.retryAfter = nextRetryAfter
    if state.stableChecks >= STATE_CONFIRM_STABLE_CHECKS then
        removePendingState(onlineID)
        return true
    end
    return false
end

local function getCachedZombie(onlineID)
    local zombie = onlineID and loadedZombiesByOnlineID[onlineID]
    if not zombie then return nil end
    if zombie:getOnlineID() ~= onlineID
            or zombie:isDead() or not zombie:getSquare() then
        loadedZombiesByOnlineID[onlineID] = nil
        return nil
    end
    return zombie
end

local function cacheLoadedZombie(zombie)
    local onlineID = zombie:getOnlineID()
    if not RandomZeds.isValidOnlineID(onlineID) then return nil end
    loadedZombiesByOnlineID[onlineID] = zombie
    return onlineID
end

local function processPendingStates(deadline)
    local total = #pendingOrder
    local visited = 0
    while total > 0 and visited < total and getTimestampMs() < deadline do
        if pendingCursor > #pendingOrder then pendingCursor = 1 end
        local onlineID = pendingOrder[pendingCursor]
        pendingCursor = pendingCursor + 1
        visited = visited + 1
        local state = pendingStates[onlineID]
        if pendingQueued[onlineID] then
            if not state then error("Pending client state is missing") end
            local now = getTimestampMs()
            if now >= state.expiresAt then
                removePendingState(onlineID)
            else
                local zombie = getCachedZombie(onlineID)
                if zombie then
                    reconcilePendingState(zombie, state, now)
                end
            end
        end
    end

    if #pendingOrder > 1024 or (pendingCursor > #pendingOrder and visited > 0) then
        local compacted = {}
        for _, onlineID in ipairs(pendingOrder) do
            if pendingQueued[onlineID] then
                compacted[#compacted + 1] = onlineID
            end
        end
        pendingOrder = compacted
        pendingCursor = 1
    end
end

local function getZombiePosition(zombie)
    return RandomZeds.requireNumber(zombie:getX(), "zombie x position"),
        RandomZeds.requireNumber(zombie:getY(), "zombie y position")
end

local function updateSprinterWatchdog(zombie, state, now)
    local onlineID = zombie:getOnlineID()
    if not RandomZeds.isValidOnlineID(onlineID)
            or state.speedType ~= "sprinter"
            or isBlocked(zombie) or zombie:isDead()
            or not RandomZeds.isSprinterMotionExpected(zombie)
            or isApplicationPending(zombie) then
        if onlineID then watchdogStates[onlineID] = nil end
        return
    end

    local x, y = getZombiePosition(zombie)
    local record = watchdogStates[onlineID]
    if not record then
        watchdogStates[onlineID] = {
            x = x,
            y = y,
            stationarySince = now,
            lastRecoveryAt = -math.huge,
        }
        return
    end
    if record.x ~= x or record.y ~= y then
        record.x = x
        record.y = y
        record.stationarySince = now
        return
    end
    if now - record.stationarySince < SPRINTER_WATCHDOG_STALL_MS
            or now - record.lastRecoveryAt < SPRINTER_WATCHDOG_COOLDOWN_MS then
        return
    end
    record.lastRecoveryAt = now
    record.stationarySince = now
    if not RandomZeds.dispatchZombieState(zombie, state) then
        RandomZeds.applySprinterAnimationSpeed(zombie, state.multiplier)
    end
end

local function refreshAuthoritativeZombieState(zombie, state, now)
    if isBlocked(zombie) then return end

    local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(
        zombie, state.speedType)
    local remoteSpeedIsScaled = isRemoteScaledSprinterState(zombie, state)
    local clientStateApplied = isClientStateApplied(zombie, state)
    if clientStateApplied and (nativeApplied or remoteSpeedIsScaled) then
        if state.speedType == "sprinter" then
            RandomZeds.reconcileSprinterMotion(zombie)
            updateSprinterWatchdog(zombie, state, now)
        end
        return
    end
    local refreshDue = isLoadedStateRefreshDue(zombie, now)
    if not remoteSpeedIsScaled and not refreshDue then
        return
    end
    if not remoteSpeedIsScaled then
        scheduleLoadedStateRefresh(zombie, now)
    end
    applyState(zombie, state)
    if state.speedType == "sprinter" then
        updateSprinterWatchdog(zombie, state, now)
    end
end

local function refreshStoredZombieState(zombie, state, now)
    if not state or isBlocked(zombie) then return end

    local speedType = state.speedType
    local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
    if not isClientStateApplied(zombie, state) or not nativeApplied then
        local remoteSpeedIsScaled = isRemoteScaledSprinterState(zombie, state)
        local refreshDue = isLoadedStateRefreshDue(zombie, now)
        if speedType == "sprinter" and not remoteSpeedIsScaled
                and not refreshDue then
            return
        end
        if speedType == "sprinter" and not remoteSpeedIsScaled then
            scheduleLoadedStateRefresh(zombie, now)
        end
        applyState(zombie, state)
    end
end

local function refreshLoadedZombieState(zombie, now)
    local onlineID = zombie:getOnlineID()
    if onlineID and pendingQueued[onlineID] then return end
    if RandomZeds.isExcluded(zombie) or zombie:isDead() or not zombie:getSquare() then
        return
    end

    local state = onlineID and authoritativeStates[onlineID]
    if state then
        refreshAuthoritativeZombieState(zombie, state, now)
        return
    end
    refreshStoredZombieState(zombie, makeModDataState(zombie), now)
end

local function processLoadedZombie(zombie, deadline)
    local onlineID = cacheLoadedZombie(zombie)
    if onlineID and pendingQueued[onlineID] then
        local state = pendingStates[onlineID]
        if not state then error("Pending client state is missing") end
        reconcilePendingState(zombie, state, getTimestampMs())
    end
    if getTimestampMs() < deadline and (not onlineID or not pendingQueued[onlineID]) then
        refreshLoadedZombieState(zombie, getTimestampMs())
    end
end

local function refreshPendingStates()
    clientTick = clientTick + 1
    local now = getTimestampMs()
    local deadline = now + RECONCILE_BUDGET_MS
    local remaining = deadline - getTimestampMs()
    if remaining > 0 then
        RandomZeds.forEachLoadedZombieWithinBudget(
            loadedZombieCursor,
            remaining,
            function(zombie) processLoadedZombie(zombie, deadline) end
        )
    end

    if getTimestampMs() < deadline then
        processPendingStates(deadline)
    end
    RandomZeds.refreshSprinterAnimationSpeeds()
end

local function validateServerStateIdentity(state)
    local onlineID = RandomZeds.requireInteger(
        state.id, "server zombie state online id")
    local revision = RandomZeds.requireInteger(
        state.reroll, "server zombie state reroll")
    if not RandomZeds.isValidOnlineID(onlineID) then
        error("Server zombie state has an invalid online id")
    end
    if revision < 0 then
        error("Server zombie state has an invalid reroll revision")
    end
    return onlineID, revision
end

local function receiveValidatedServerState(state, onlineID, revision)

    local latestRevision = latestRevisions[onlineID]
    if latestRevision and revision < latestRevision then return end

    latestRevisions[onlineID] = revision
    authoritativeStates[onlineID] = state
    state.expiresAt = getTimestampMs() + STATE_PENDING_TIMEOUT_MS
    state.stableChecks = 0
    state.retryAfter = 0
    pendingStates[onlineID] = state
    if not pendingQueued[onlineID] then
        pendingQueued[onlineID] = true
        pendingOrder[#pendingOrder + 1] = onlineID
    end
    local zombie = getCachedZombie(onlineID)
    if zombie then
        reconcilePendingState(zombie, state, getTimestampMs())
    end
end

local function receiveServerState(state)
    validateClientState(state)
    local onlineID, revision = validateServerStateIdentity(state)
    receiveValidatedServerState(state, onlineID, revision)
end

local function validateServerStateEntry(state)
    validateClientState(state)
    local onlineID, revision = validateServerStateIdentity(state)
    return {
        state = state,
        onlineID = onlineID,
        revision = revision,
    }
end

local function validateServerStateBatch(states)
    local stateCount = #states
    local validatedStates = {}
    for index, state in ipairs(states) do
        validatedStates[index] = validateServerStateEntry(state)
    end
    if #validatedStates ~= stateCount then
        error("Random Zeds server state list has missing entries")
    end
    for index in pairs(states) do
        if type(index) ~= "number" or index % 1 ~= 0
                or index < 1 or index > stateCount then
            error("Random Zeds server state list has invalid indexes")
        end
    end
    return validatedStates
end

local function onServerCommand(module, command, packet)
    if module ~= COMMAND_MODULE or command ~= STATE_COMMAND then return end
    if not packet then error("Random Zeds server state packet is required") end
    if type(packet) ~= "table" then
        error("Random Zeds server state packet must be a table")
    end
    if packet.states ~= nil then
        if type(packet.states) ~= "table" then
            error("Random Zeds server state list must be a table")
        end
        local validatedStates = validateServerStateBatch(packet.states)
        for _, validatedState in ipairs(validatedStates) do
            receiveValidatedServerState(
                validatedState.state,
                validatedState.onlineID,
                validatedState.revision
            )
        end
    else
        receiveServerState(packet)
    end
end

local function onConnected()
    resetClientState()
    RandomZeds.forceVanillaPerceptionDefaults()
end

local function onDisconnect()
    resetClientState()
end

RandomZeds.debug("Registering Random Zeds client events")
Events.OnTick.Add(refreshPendingStates)
Events.OnServerCommand.Add(onServerCommand)
Events.OnConnected.Add(onConnected)
Events.OnDisconnect.Add(onDisconnect)
Events.OnGameStart.Add(RandomZeds.forceVanillaPerceptionDefaults)
