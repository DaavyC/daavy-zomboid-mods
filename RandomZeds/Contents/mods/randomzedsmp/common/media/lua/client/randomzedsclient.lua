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
local DIRTY_ZOMBIE_RETRY_MS = 100
local FALLBACK_SCAN_INTERVAL_MS = 1000
local SPRINTER_CHECK_COOLDOWN_MS = 1000
local ANIMATION_REFRESH_WINDOW_MS = 250
local SPRINTER_WATCHDOG_STALL_MS = 750
local SPRINTER_WATCHDOG_COOLDOWN_MS = 2000
local pendingStates = {}
local authoritativeStates = {}
local latestRevisions = {}
local pendingOrder = table.newarray()
local pendingQueued = {}
local pendingCursor = 1
local dirtyZombies = table.newarray()
local dirtyQueued = setmetatable({}, { __mode = "k" })
local dirtyRetryAt = setmetatable({}, { __mode = "k" })
local dirtyCursor = 1
local loadedZombieCursor = { index = 0 }
local loadedZombiesByOnlineID = setmetatable({}, { __mode = "v" })
local knownZombieIDs = {}
local sprinterCheckCooldowns = setmetatable({}, { __mode = "k" })
local applicationStates = setmetatable({}, { __mode = "k" })
local watchdogStates = {}
local clientTick = 0
local initialScanPending = true
local nextFallbackScanAt = 0

local function resetZombieTracking()
    pendingStates = {}
    pendingQueued = {}
    pendingOrder = table.newarray()
    pendingCursor = 1
    dirtyZombies = table.newarray()
    dirtyQueued = setmetatable({}, { __mode = "k" })
    dirtyRetryAt = setmetatable({}, { __mode = "k" })
    dirtyCursor = 1
    loadedZombiesByOnlineID = setmetatable({}, { __mode = "v" })
    knownZombieIDs = {}
    watchdogStates = {}
end

local function resetClientState()
    resetZombieTracking()
    authoritativeStates = {}
    latestRevisions = {}
    loadedZombieCursor = { index = 0 }
    sprinterCheckCooldowns = setmetatable({}, { __mode = "k" })
    applicationStates = setmetatable({}, { __mode = "k" })
    clientTick = 0
    initialScanPending = true
    nextFallbackScanAt = 0
end

local function queueZombieRefresh(zombie)
    if not zombie or dirtyQueued[zombie] then return end
    dirtyQueued[zombie] = true
    dirtyZombies[#dirtyZombies + 1] = zombie
end

local function discardZombie(zombie)
    if not zombie then return end
    dirtyQueued[zombie] = nil
    dirtyRetryAt[zombie] = nil
    sprinterCheckCooldowns[zombie] = nil
    applicationStates[zombie] = nil
    local onlineID = tonumber(zombie:getOnlineID())
    if onlineID then
        loadedZombiesByOnlineID[onlineID] = nil
        pendingStates[onlineID] = nil
        pendingQueued[onlineID] = nil
        authoritativeStates[onlineID] = nil
        knownZombieIDs[onlineID] = nil
        watchdogStates[onlineID] = nil
    end
end

local function clearUnavailableZombieQueues()
    resetZombieTracking()
end

local function clearQueuesWhenNoLoadedZombies()
    if #dirtyZombies == 0 and #pendingOrder == 0 then return end
    local cell = getCell()
    local zombies = cell and cell:getZombieList()
    if zombies and zombies:size() > 0 then return end
    clearUnavailableZombieQueues()
end

local function markApplication(zombie, now)
    applicationStates[zombie] = {
        tick = clientTick,
        appliedAt = now,
    }
end

local function isApplicationPending(zombie, now)
    local application = applicationStates[zombie]
    if not application then return false end
    return clientTick <= application.tick
        or now - application.appliedAt
            < ANIMATION_REFRESH_WINDOW_MS
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

local function isBlocked(zombie)
    return zombie:isCrawling()
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

local function isLoadedStateRefreshDue(zombie, now)
    local cooldownAt = sprinterCheckCooldowns[zombie]
    if cooldownAt == nil then
        cooldownAt = 0
    else
        cooldownAt = tonumber(cooldownAt) or 0
    end
    return now >= cooldownAt
end

local function scheduleLoadedStateRefresh(zombie, now)
    sprinterCheckCooldowns[zombie] = now + SPRINTER_CHECK_COOLDOWN_MS
end

local function applyFreshClientStateValues(zombie, state)
    if RandomZeds.dispatchZombieState(zombie, state) then return true end
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
    if RandomZeds.dispatchZombieState(zombie, state) then return true end
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

    local now = getTimestampMs()
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
    if applied and not alreadyApplied then markApplication(zombie, now) end
    return applied
end

local function applyClientState(zombie, state, modData)
    if not zombie then return false end
    if RandomZeds.isExcluded(zombie) then return true end
    if zombie:isDead() then return true end
    if not zombie:getCurrentSquare() or isBlocked(zombie) then return false end
    if not validateClientState(state) then return false end
    return applyValidatedClientState(zombie, state, modData)
end

local function removePendingState(onlineID)
    pendingStates[onlineID] = nil
    pendingQueued[onlineID] = nil
    knownZombieIDs[onlineID] = nil
end

local function reconcilePendingState(zombie, state, now)
    local onlineID = tonumber(zombie:getOnlineID())
    if RandomZeds.isExcluded(zombie) or zombie:isDead() then
        removePendingState(onlineID)
        return true
    end
    if state.expiresAt and now >= state.expiresAt then
        removePendingState(onlineID)
        return true
    end
    if not zombie:getCurrentSquare() or isBlocked(zombie) then return false end
    if now < (state.retryAfter or 0) then return false end

    local nextRetryAfter = now + STATE_RETRY_MS
    if applyValidatedClientState(zombie, state, nil) then
        state.stableChecks = (state.stableChecks or 0) + 1
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
    knownZombieIDs[onlineID] = true
    return onlineID
end

local function processPendingStates(deadline)
    local total = #pendingOrder
    local visited = 0
    local getTimestamp = getTimestampMs
    while total > 0 and visited < total do
        local now = getTimestamp()
        if now >= deadline then break end
        if pendingCursor > total then pendingCursor = 1 end
        local onlineID = pendingOrder[pendingCursor]
        pendingCursor = pendingCursor + 1
        visited = visited + 1
        local state = pendingStates[onlineID]
        if pendingQueued[onlineID] then
            if not state then
                removePendingState(onlineID)
            else
                if state.expiresAt and now >= state.expiresAt then
                    removePendingState(onlineID)
                else
                    local zombie = getCachedZombie(onlineID)
                    if zombie then
                        reconcilePendingState(zombie, state, now)
                    elseif knownZombieIDs[onlineID] then
                        removePendingState(onlineID)
                    end
                end
            end
        end
    end

    if total > 1024 or (pendingCursor > total and visited > 0) then
        local compacted = table.newarray()
        for index = 1, total do
            local onlineID = pendingOrder[index]
            if pendingQueued[onlineID] then
                compacted[#compacted + 1] = onlineID
            end
        end
        pendingOrder = compacted
        pendingCursor = 1
    end
end

local function getZombiePosition(zombie)
    return tonumber(zombie:getX()), tonumber(zombie:getY())
end

local function updateSprinterWatchdog(zombie, state, now)
    local onlineID = tonumber(zombie:getOnlineID())
    if not RandomZeds.isValidOnlineID(onlineID)
            or state.speedType ~= "sprinter"
            or isBlocked(zombie) or zombie:isDead()
            or not RandomZeds.isSprinterMotionExpected(zombie)
            or isApplicationPending(zombie, now) then
        if onlineID then watchdogStates[onlineID] = nil end
        return
    end

    local x, y = getZombiePosition(zombie)
    if not x or not y then return end
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

local function refreshAuthoritativeZombieState(zombie, state, now, modData)
    if isBlocked(zombie) then return end

    local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(
        zombie, state.speedType)
    local remoteSpeedIsScaled = isRemoteScaledSprinterState(
        zombie, state, modData)
    local clientStateApplied = isClientStateApplied(zombie, state, modData)
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
    applyValidatedClientState(zombie, state, modData)
    if state.speedType == "sprinter" then
        updateSprinterWatchdog(zombie, state, now)
    end
end

local function refreshStoredZombieState(zombie, state, now, modData)
    if not state or isBlocked(zombie) then return end

    local speedType = state.speedType
    local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
    if not isClientStateApplied(zombie, state, modData) or not nativeApplied then
        local remoteSpeedIsScaled = isRemoteScaledSprinterState(
            zombie, state, modData)
        local refreshDue = isLoadedStateRefreshDue(zombie, now)
        if speedType == "sprinter" and not remoteSpeedIsScaled
                and not refreshDue then
            return
        end
        if speedType == "sprinter" and not remoteSpeedIsScaled then
            scheduleLoadedStateRefresh(zombie, now)
        end
        applyClientState(zombie, state, modData)
    end
end

local function refreshLoadedZombieState(zombie, now, onlineID)
    if onlineID and pendingQueued[onlineID] then return end
    if RandomZeds.isExcluded(zombie) then return end

    local modData = zombie:getModData()
    local state = onlineID and authoritativeStates[onlineID]
    if state then
        refreshAuthoritativeZombieState(zombie, state, now, modData)
        return
    end
    refreshStoredZombieState(
        zombie, makeModDataState(zombie, modData), now, modData)
end

local function processLoadedZombie(zombie, deadline, now)
    if not zombie or zombie:isDead() then
        return nil, true
    end
    if not zombie:getCurrentSquare() then
        return nil, true
    end
    local onlineID = cacheLoadedZombie(zombie)
    if onlineID and pendingQueued[onlineID] then
        local state = pendingStates[onlineID]
        if state then reconcilePendingState(zombie, state, now) end
        now = getTimestampMs()
    end
    if now < deadline and (not onlineID or not pendingQueued[onlineID]) then
        refreshLoadedZombieState(zombie, now, onlineID)
    end
    return onlineID, onlineID ~= nil
end

local function processNextDirtyZombie(total, deadline, now)
    if dirtyCursor > total then dirtyCursor = 1 end
    local zombie = dirtyZombies[dirtyCursor]
    dirtyCursor = dirtyCursor + 1
    if not zombie or not dirtyQueued[zombie] then return end

    local retryAt = dirtyRetryAt[zombie]
    if retryAt and now < retryAt then return end
    local _, resolved = processLoadedZombie(zombie, deadline, now)
    if resolved then
        dirtyQueued[zombie] = nil
        dirtyRetryAt[zombie] = nil
    else
        dirtyRetryAt[zombie] = now + DIRTY_ZOMBIE_RETRY_MS
    end
end

local function compactDirtyZombies(total, visited)
    if dirtyCursor <= total or visited == 0 then return end
    local compacted = table.newarray()
    for index = 1, total do
        local zombie = dirtyZombies[index]
        if zombie and dirtyQueued[zombie] then
            compacted[#compacted + 1] = zombie
        end
    end
    dirtyZombies = compacted
    dirtyCursor = 1
end

local function processDirtyZombies(deadline)
    local total = #dirtyZombies
    local visited = 0
    local getTimestamp = getTimestampMs
    while total > 0 and visited < total do
        local now = getTimestamp()
        if now >= deadline then break end
        processNextDirtyZombie(total, deadline, now)
        visited = visited + 1
    end
    compactDirtyZombies(total, visited)
end

local function processFallbackLoadedZombieScan(deadline)
    local scanNow = getTimestampMs()
    if not initialScanPending and scanNow < nextFallbackScanAt then return end
    if scanNow >= deadline then return end

    local remaining = deadline - scanNow
    local processed = RandomZeds.forEachLoadedZombieWithinBudget(
        loadedZombieCursor,
        remaining,
        function(zombie, now) processLoadedZombie(zombie, deadline, now) end
    )
    if processed == 0 then
        clearUnavailableZombieQueues()
    end
    if initialScanPending and loadedZombieCursor.index == 0 then
        initialScanPending = false
    end
    if initialScanPending then
        nextFallbackScanAt = 0
    else
        nextFallbackScanAt = getTimestampMs() + FALLBACK_SCAN_INTERVAL_MS
    end
end

local function refreshPendingStates()
    clientTick = clientTick + 1
    local getTimestamp = getTimestampMs
    local now = getTimestamp()
    local deadline = now + RECONCILE_BUDGET_MS
    clearQueuesWhenNoLoadedZombies()
    processDirtyZombies(deadline)
    processFallbackLoadedZombieScan(deadline)
    processPendingStates(deadline)
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

local function receiveValidatedServerState(state, onlineID, revision, now)

    local latestRevision = latestRevisions[onlineID]
    if latestRevision and revision < latestRevision then return end

    now = now or getTimestampMs()
    latestRevisions[onlineID] = revision
    authoritativeStates[onlineID] = state
    state.expiresAt = now + STATE_PENDING_TIMEOUT_MS
    state.stableChecks = 0
    state.retryAfter = 0
    pendingStates[onlineID] = state
    if not pendingQueued[onlineID] then
        pendingQueued[onlineID] = true
        pendingOrder[#pendingOrder + 1] = onlineID
    end
end

local function receiveServerState(state, now)
    if not validateClientState(state) then return end
    local onlineID, revision = validateServerStateIdentity(state)
    if not onlineID then return end
    receiveValidatedServerState(state, onlineID, revision, now)
end

local function onServerCommand(module, command, packet)
    if module ~= COMMAND_MODULE or command ~= STATE_COMMAND then return end
    if type(packet) ~= "table" then return end
    if packet.states ~= nil then
        if type(packet.states) ~= "table" then return end
        local now = getTimestampMs()
        local states = packet.states
        for index = 1, #states do
            local state = states[index]
            if validateClientState(state) then
                local onlineID, revision = validateServerStateIdentity(state)
                if onlineID then
                    receiveValidatedServerState(state, onlineID, revision, now)
                end
            end
        end
    else
        receiveServerState(packet, getTimestampMs())
    end
end

local function onConnected()
    resetClientState()
    RandomZeds.forceVanillaPerceptionDefaults()
end

local function onDisconnect()
    resetClientState()
end

local function onZombieCreate(zombie)
    queueZombieRefresh(zombie)
end

local function onZombieDead(zombie)
    discardZombie(zombie)
end

RandomZeds.debug("Registering Random Zeds client events")
Events.OnTick.Add(refreshPendingStates)
Events.OnServerCommand.Add(onServerCommand)
Events.OnConnected.Add(onConnected)
Events.OnDisconnect.Add(onDisconnect)
Events.OnGameStart.Add(RandomZeds.forceVanillaPerceptionDefaults)
Events.OnZombieCreate.Add(onZombieCreate)
Events.OnZombieDead.Add(onZombieDead)
