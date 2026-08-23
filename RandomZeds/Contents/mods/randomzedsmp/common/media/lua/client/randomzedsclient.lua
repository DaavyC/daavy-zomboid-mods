if not isClient() then return end

local PERIOD_TAG = "RandomZedsPeriod"
local SPEED_TAG = "RandomZedsSpeedType"
local SPRINTER_MULTIPLIER_TAG = "RandomZedsSprinterMultiplier"
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local HEALTH_TAG = "RandomZedsHealth"
local SIGHT_TAG = "RandomZedsSight"
local HEARING_TAG = "RandomZedsHearing"
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
local animationRefreshRequested = false
local animationRefreshDueAt = 0
local animationRefreshDueTick = 0
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
    animationRefreshRequested = false
    animationRefreshDueAt = 0
    animationRefreshDueTick = 0
    clientTick = 0
end

local function requestAnimationRefresh(now)
    now = tonumber(now) or getTimestampMs()
    if not animationRefreshRequested then
        animationRefreshRequested = true
        animationRefreshDueAt = now + ANIMATION_REFRESH_WINDOW_MS
        animationRefreshDueTick = clientTick + 1
    end
end

local function flushAnimationRefresh(now)
    if not animationRefreshRequested
            or clientTick <= animationRefreshDueTick
            or now < animationRefreshDueAt then
        return
    end

    animationRefreshRequested = false
    local refresh = rawget(_G, "refreshAnimSets")
    if type(refresh) == "function" then
        local ok, errorMessage = pcall(function() refresh(false) end)
        if not ok then
            RandomZeds.debug("Animation refresh failed: " .. tostring(errorMessage))
        end
    else
        RandomZeds.debug("Animation refresh unavailable")
    end
end

local function markApplication(zombie, now)
    applicationStates[zombie] = {
        tick = clientTick,
        appliedAt = now,
    }
    requestAnimationRefresh(now)
end

local function isApplicationPending(zombie)
    local application = applicationStates[zombie]
    if not application then return false end
    return clientTick <= application.tick
        or getTimestampMs() - application.appliedAt
            < ANIMATION_REFRESH_WINDOW_MS
end

local function isClientStateApplied(zombie, state)
    local period = state and state.period
    local revision = tostring(tonumber(state and state.reroll) or 0)
    if zombie:getVariableString(CLIENT_PERIOD_VARIABLE) ~= period
            or zombie:getVariableString(CLIENT_REROLL_VARIABLE) ~= revision then
        return false
    end
    local modData = zombie:getModData()
    if not modData or modData[SPEED_TAG] ~= state.speedType then return false end
    if tonumber(modData[HEALTH_TAG]) ~= tonumber(state.health)
            or tonumber(modData[SIGHT_TAG]) ~= tonumber(state.sight)
            or tonumber(modData[HEARING_TAG]) ~= tonumber(state.hearing) then
        return false
    end
    if state.speedType ~= "sprinter" then return true end
    local multiplier = tonumber(state.multiplier)
    local currentMultiplier = tonumber(modData[SPRINTER_MULTIPLIER_TAG])
    local currentBaseSpeed = tonumber(modData[SPRINTER_BASE_SPEED_TAG])
    local baseSpeed = tonumber(state.baseSpeed) or currentBaseSpeed
    return multiplier ~= nil and baseSpeed ~= nil
        and currentMultiplier ~= nil and currentBaseSpeed ~= nil
        and math.abs(multiplier - currentMultiplier) <= 0.005
        and math.abs(baseSpeed - currentBaseSpeed) <= 0.005
end

local function isBlocked(zombie)
    return zombie:isCrawling()
        or zombie:getCurrentActionContextStateName() == "getup"
end

local function applyClientSpeedType(zombie, speedType, multiplier)
    if speedType == "sprinter" and zombie.isRemoteZombie
            and zombie:isRemoteZombie() then
        RandomZeds.applySprinterSpeed(zombie, multiplier)
        return true
    end
    return RandomZeds.applyZombieSpeedType(zombie, speedType, multiplier)
end

local function isRemoteScaledSprinterState(zombie, state)
    if not state or state.speedType ~= "sprinter" then return false end

    local modData = zombie:getModData()
    local baseSpeed = tonumber(state.baseSpeed)
        or tonumber(modData[SPRINTER_BASE_SPEED_TAG])
    local multiplier = tonumber(state.multiplier)
        or tonumber(modData[SPRINTER_MULTIPLIER_TAG])
    if not baseSpeed or not multiplier then return false end

    return RandomZeds.isRemoteSprinterSpeedScaled(
        zombie, baseSpeed * multiplier)
end

local function writeStateToModData(zombie, state)
    local modData = zombie:getModData()
    modData[PERIOD_TAG] = state.period
    modData[SPEED_TAG] = state.speedType
    modData[SPRINTER_MULTIPLIER_TAG] = state.multiplier
    local baseSpeed = tonumber(state.baseSpeed)
    if baseSpeed and baseSpeed > 0 then
        modData[SPRINTER_BASE_SPEED_TAG] = baseSpeed
    end
    modData[HEALTH_TAG] = state.health
    modData[SIGHT_TAG] = state.sight
    modData[HEARING_TAG] = state.hearing
    modData[REROLL_TAG] = state.reroll
end

local function makeModDataState(zombie)
    local modData = zombie:getModData()
    if not modData or not modData[PERIOD_TAG] or not modData[SPEED_TAG] then
        return nil
    end
    return {
        period = modData[PERIOD_TAG],
        speedType = modData[SPEED_TAG],
        multiplier = modData[SPRINTER_MULTIPLIER_TAG],
        baseSpeed = modData[SPRINTER_BASE_SPEED_TAG],
        health = modData[HEALTH_TAG],
        sight = modData[SIGHT_TAG],
        hearing = modData[HEARING_TAG],
        reroll = modData[REROLL_TAG],
    }
end

local function applyState(zombie, state)
    if not zombie or not state then return false end
    if RandomZeds.isExcluded(zombie) then return true end
    if zombie:isDead() then return true end
    if not zombie:getSquare() then return false end
    if isBlocked(zombie) then return false end

    local speedType = state.speedType
    local multiplier = tonumber(state.multiplier) or 1.0
    local alreadyApplied = isClientStateApplied(zombie, state)
    local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(
        zombie, speedType, false)

    if alreadyApplied and nativeApplied then
        if speedType == "sprinter" then
            RandomZeds.reconcileSprinterMotion(zombie)
        end
        return true
    end

    local now = getTimestampMs()
    RandomZeds.beginStateApplication(zombie)
    local ok, applied = pcall(function()
        if not alreadyApplied then
            local sight = tonumber(state.sight)
            local hearing = tonumber(state.hearing)
            if not RandomZeds.applyZombieNativeStats(zombie, sight, hearing) then
                RandomZeds.debug("Client native stats application failed; continuing")
            end
        end
        if not applyClientSpeedType(zombie, speedType, multiplier) then
            return false
        end

        local health = tonumber(state.health)
        if health and not alreadyApplied then
            zombie:setHealth(health)
        end

        zombie:setVariable(CLIENT_PERIOD_VARIABLE, state.period)
        zombie:setVariable(CLIENT_REROLL_VARIABLE,
            tostring(tonumber(state.reroll) or 0))
        writeStateToModData(zombie, state)
        if speedType == "sprinter" then
            RandomZeds.reconcileSprinterMotion(zombie)
        end
        return RandomZeds.isZombieSpeedTypeApplied(zombie, speedType, false)
    end)
    RandomZeds.finishStateApplication(zombie)
    if not ok then
        RandomZeds.debug("Client state application failed: " .. tostring(applied))
        return false
    end
    if applied and not alreadyApplied then markApplication(zombie, now) end
    return applied == true
end

local function applyCommandState(zombie, state)
    if RandomZeds.isExcluded(zombie) then return false end
    return applyState(zombie, state)
end

local function removePendingState(onlineID)
    pendingStates[onlineID] = nil
    pendingQueued[onlineID] = nil
end

local function reconcilePendingState(zombie, state, now)
    if not zombie then return false end
    local onlineID = tonumber(zombie:getOnlineID())
    if RandomZeds.isExcluded(zombie) or zombie:isDead() then
        removePendingState(onlineID)
        return true
    end
    if state.expiresAt and now >= state.expiresAt then
        removePendingState(onlineID)
        return true
    end
    if not zombie:getSquare() or isBlocked(zombie) then return false end
    if state.retryAfter and now < state.retryAfter then return false end

    state.retryAfter = now + STATE_RETRY_MS
    if applyCommandState(zombie, state) then
        state.stableChecks = (state.stableChecks or 0) + 1
    else
        state.stableChecks = 0
    end
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
            or zombie:isDead() or not zombie:getSquare() then
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

local function processPendingStates(deadline)
    local total = #pendingOrder
    local visited = 0
    while total > 0 and visited < total and getTimestampMs() < deadline do
        if pendingCursor > #pendingOrder then pendingCursor = 1 end
        local onlineID = pendingOrder[pendingCursor]
        pendingCursor = pendingCursor + 1
        visited = visited + 1
        local state = pendingStates[onlineID]
        if state and pendingQueued[onlineID] then
            local now = getTimestampMs()
            if state.expiresAt and now >= state.expiresAt then
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
    local okX, x = pcall(function() return zombie:getX() end)
    local okY, y = pcall(function() return zombie:getY() end)
    if not okX or not okY or x == nil or y == nil then return nil, nil end
    return tonumber(x), tonumber(y)
end

local function updateSprinterWatchdog(zombie, state, now, authoritative)
    local onlineID = tonumber(zombie and zombie:getOnlineID())
    if not RandomZeds.isValidOnlineID(onlineID)
            or not authoritative or state.speedType ~= "sprinter"
            or isBlocked(zombie) or zombie:isDead()
            or not RandomZeds.isSprinterMotionExpected(zombie)
            or isApplicationPending(zombie) then
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
    requestAnimationRefresh(now)
end

local function refreshLoadedZombieState(zombie, now)
    if not zombie then return end
    if RandomZeds.isStateApplicationInProgress(zombie) then return end
    local onlineID = tonumber(zombie:getOnlineID())
    if onlineID and pendingQueued[onlineID] then return end
    if RandomZeds.isExcluded(zombie) or zombie:isDead() or not zombie:getSquare() then
        return
    end

    local state = onlineID and authoritativeStates[onlineID]
    if state then
        if isBlocked(zombie) then return end
        local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(
            zombie, state.speedType, false)
        local remoteSpeedIsScaled = isRemoteScaledSprinterState(zombie, state)
        if nativeApplied and not remoteSpeedIsScaled then
            if state.speedType == "sprinter" then
                RandomZeds.reconcileSprinterMotion(zombie)
                updateSprinterWatchdog(zombie, state, now, true)
            end
            return
        end
        local cooldownAt = sprinterCheckCooldowns[zombie] or 0
        if now < cooldownAt and not remoteSpeedIsScaled then return end
        if not remoteSpeedIsScaled then
            sprinterCheckCooldowns[zombie] = now + SPRINTER_CHECK_COOLDOWN_MS
        end
        applyCommandState(zombie, state)
        if state.speedType == "sprinter" then
            updateSprinterWatchdog(zombie, state, now, true)
        end
        return
    end

    state = makeModDataState(zombie)
    if not state or isBlocked(zombie) then return end
    local speedType = state.speedType
    local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(
        zombie, speedType, false)
    if not isClientStateApplied(zombie, state) or not nativeApplied then
        local remoteSpeedIsScaled = isRemoteScaledSprinterState(zombie, state)
        local cooldownAt = sprinterCheckCooldowns[zombie] or 0
        if speedType == "sprinter" and now < cooldownAt
                and not remoteSpeedIsScaled then
            return
        end
        if speedType == "sprinter" and not remoteSpeedIsScaled then
            sprinterCheckCooldowns[zombie] = now + SPRINTER_CHECK_COOLDOWN_MS
        end
        applyState(zombie, state)
    end
end

local function processLoadedZombie(zombie, deadline)
    local onlineID = cacheLoadedZombie(zombie)
    if onlineID and pendingQueued[onlineID] then
        local state = pendingStates[onlineID]
        if state then
            reconcilePendingState(zombie, state, getTimestampMs())
        end
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
    flushAnimationRefresh(getTimestampMs())
end

local function receiveServerState(state)
    if not state then return end
    local onlineID = tonumber(state.id)
    local revision = tonumber(state.reroll)
    if not RandomZeds.isValidOnlineID(onlineID) or not revision then return end

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

local function onServerCommand(module, command, packet)
    if module ~= COMMAND_MODULE or command ~= STATE_COMMAND then return end
    if not packet then return end
    if packet.states then
        for _, state in ipairs(packet.states) do
            receiveServerState(state)
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
