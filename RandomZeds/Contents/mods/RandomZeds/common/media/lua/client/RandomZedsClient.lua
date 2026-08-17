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
local STATE_CONFIRM_MS = 2000
local STATE_RETRY_MS = 250
local STATE_PENDING_TIMEOUT_MS = 60000
local SPRINTER_CHECK_INTERVAL_MS = 250
local SPRINTER_CHECK_BATCH_SIZE = 16
local SPRINTER_CHECK_COOLDOWN_MS = 1000
local pendingStates = {}
local latestRevisions = {}
local sprinterCheckCursor = { index = 0 }
local sprinterCheckCooldowns = setmetatable({}, { __mode = "k" })
local nextSprinterCheckAt = 0

local function applyServerState(zombie)
    if not zombie then return false end
    if RandomZeds.isExcluded(zombie) then
        RandomZeds.debug("Synchronized state skipped: zombie is excluded")
        return true
    end

    RandomZeds.debug("Applying synchronized state to zombie")
    local onlineID = tonumber(zombie:getOnlineID())
    if zombie:isDead() then
        RandomZeds.debug("Synchronized state skipped: zombie is dead")
        return true
    end
    if not zombie:getSquare() then
        RandomZeds.debug("Synchronized state deferred: zombie is not loaded")
        return false
    end

    local modData = zombie:getModData()
    local period = modData[PERIOD_TAG]
    local speedType = modData[SPEED_TAG]
    local revision = tonumber(modData[REROLL_TAG]) or 0
    local reroll = tostring(revision)
    if onlineID and latestRevisions[onlineID] and revision < latestRevisions[onlineID] then
        RandomZeds.debug("Synchronized state skipped: stale revision")
        return false
    end

    if not period or not speedType then
        RandomZeds.debug("Synchronized state skipped: incomplete modData")
        return false
    end
    local alreadyApplied = zombie:getVariableString(CLIENT_PERIOD_VARIABLE) == period
        and zombie:getVariableString(CLIENT_REROLL_VARIABLE) == reroll

    local multiplier = tonumber(modData[SPRINTER_MULTIPLIER_TAG]) or 1.0
    if speedType == "sprinter" then
        modData[SPRINTER_MULTIPLIER_TAG] = multiplier
    end
    local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
    local gettingUp = zombie:getCurrentActionContextStateName() == "getup"
    if alreadyApplied and nativeApplied then
        RandomZeds.debug("Synchronized state already applied")
        return true
    end

    if alreadyApplied and speedType == "sprinter" and not nativeApplied
            and not gettingUp then
        if not RandomZeds.applyZombieSpeedType(zombie, speedType, multiplier) then
            RandomZeds.debug("Sprinter correction failed: speed application failed")
            return false
        end
        local corrected = RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
        RandomZeds.debug("Sprinter correction result=" .. tostring(corrected))
        return corrected
    end

    if gettingUp then
        RandomZeds.debug("Synchronized state deferred: zombie is getting up")
        return false
    end

    if speedType ~= "crawler" and zombie:isCrawling() then
        RandomZeds.debug("Synchronized state deferred: standing zombie is crawling")
        RandomZeds.setCrawlerState(zombie, false)
        return false
    end

    local sight = tonumber(modData[SIGHT_TAG])
    local hearing = tonumber(modData[HEARING_TAG])
    if not RandomZeds.applyZombieNativeStats(zombie, sight, hearing) then
        RandomZeds.debug("Client native stats application failed; continuing with synchronized speed")
    end
    if not RandomZeds.applyZombieSpeedType(zombie, speedType, multiplier) then
        RandomZeds.debug("Synchronized state failed: speed application failed")
        return false
    end

    local health = tonumber(modData[HEALTH_TAG])
    if health and not alreadyApplied then
        zombie:setHealth(health)
    end

    zombie:setVariable(CLIENT_PERIOD_VARIABLE, period)
    zombie:setVariable(CLIENT_REROLL_VARIABLE, reroll)
    local applied = RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
    RandomZeds.debug("Synchronized state result=" .. tostring(applied))
    return applied
end

local function applyCommandState(zombie, state)
    if RandomZeds.isExcluded(zombie) then
        RandomZeds.debug("Synchronized state ignored: zombie is excluded")
        return false
    end

    RandomZeds.debug("Received state period=" .. tostring(state and state.period)
        .. " speed=" .. tostring(state and state.speedType)
        .. " reroll=" .. tostring(state and state.reroll))
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
    return applyServerState(zombie)
end

local function applyPendingState(zombie)
    if not zombie then return false end

    local onlineID = tonumber(zombie:getOnlineID())
    local state = onlineID and pendingStates[onlineID]
    if not state then return false end
    if RandomZeds.isExcluded(zombie) then
        pendingStates[onlineID] = nil
        RandomZeds.debug("Removed pending state: zombie is excluded")
        return true
    end

    RandomZeds.debug("Applying pending synchronized state id=" .. tostring(onlineID))
    if zombie:isDead() then
        pendingStates[onlineID] = nil
        RandomZeds.debug("Removed pending state: zombie is dead")
        return true
    end

    local now = getTimestampMs()
    if state.expiresAt and now >= state.expiresAt then
        pendingStates[onlineID] = nil
        return false
    end
    if state.retryAfter and now < state.retryAfter then return false end
    state.retryAfter = now + STATE_RETRY_MS

    local nativeApplied = RandomZeds.isZombieSpeedTypeApplied(zombie, state.speedType)
    if not applyCommandState(zombie, state) then
        return false
    end

    if not nativeApplied then
        state.confirmAfter = now + STATE_CONFIRM_MS
        RandomZeds.debug("Pending state awaiting native confirmation")
        return false
    end
    if not state.confirmAfter then
        state.confirmAfter = now + STATE_CONFIRM_MS
        RandomZeds.debug("Pending state confirmation timer started")
        return false
    end
    if now < state.confirmAfter then return false end

    pendingStates[onlineID] = nil
    RandomZeds.debug("Pending state confirmed id=" .. tostring(onlineID))
    return true
end

local function refreshLoadedZombieState(zombie, now)
    if applyPendingState(zombie) then return end

    local onlineID = tonumber(zombie and zombie:getOnlineID())
    if onlineID and pendingStates[onlineID] then return end
    if not zombie or RandomZeds.isExcluded(zombie)
            or zombie:isDead() or not zombie:getSquare() then
        return
    end

    local modData = zombie:getModData()
    if not modData or not modData[PERIOD_TAG] or not modData[SPEED_TAG] then
        return
    end

    if modData[SPEED_TAG] ~= "sprinter" then
        local revision = tostring(tonumber(modData[REROLL_TAG]) or 0)
        local stateApplied = zombie:getVariableString(CLIENT_PERIOD_VARIABLE)
                == modData[PERIOD_TAG]
            and zombie:getVariableString(CLIENT_REROLL_VARIABLE) == revision
        if not stateApplied then
            applyServerState(zombie)
        end
        return
    end

    if zombie:isCrawling()
            or zombie:getCurrentActionContextStateName() == "getup" then
        return
    end

    local cooldownAt = sprinterCheckCooldowns[zombie] or 0
    if now < cooldownAt then return end
    sprinterCheckCooldowns[zombie] = now + SPRINTER_CHECK_COOLDOWN_MS

    if not RandomZeds.isZombieSpeedTypeApplied(zombie, "sprinter") then
        applyServerState(zombie)
    end
end

local function refreshPendingStates()
    local now = getTimestampMs()
    if now >= nextSprinterCheckAt then
        nextSprinterCheckAt = now + SPRINTER_CHECK_INTERVAL_MS
        RandomZeds.forEachLoadedZombieIncremental(
            sprinterCheckCursor,
            SPRINTER_CHECK_BATCH_SIZE,
            function(zombie) refreshLoadedZombieState(zombie, now) end
        )
    end

    for onlineID, state in pairs(pendingStates) do
        if state.expiresAt and now >= state.expiresAt then
            pendingStates[onlineID] = nil
        end
    end
end

local function receiveServerState(state)
    if not state then
        RandomZeds.debug("Ignoring empty server state")
        return
    end

    local onlineID = tonumber(state.id)
    local revision = tonumber(state.reroll)
    if not onlineID or onlineID < 0 or not revision then
        RandomZeds.debug("Ignoring invalid server state")
        return
    end

    local latestRevision = latestRevisions[onlineID]
    if latestRevision and revision < latestRevision then
        RandomZeds.debug("Ignoring stale server state id=" .. tostring(onlineID))
        return
    end

    latestRevisions[onlineID] = revision
    state.expiresAt = getTimestampMs() + STATE_PENDING_TIMEOUT_MS
    pendingStates[onlineID] = state
    RandomZeds.debug("Queued server state id=" .. tostring(onlineID)
        .. " revision=" .. tostring(revision))
end

local function onServerCommand(module, command, packet)
    if module ~= COMMAND_MODULE or command ~= STATE_COMMAND then return end
    if not packet then return end

    RandomZeds.debug("Received Random Zeds server command")

    if packet.states then
        for _, state in pairs(packet.states) do
            receiveServerState(state)
        end
    else
        receiveServerState(packet)
    end
end

RandomZeds.debug("Registering Random Zeds client events")
Events.OnTick.Add(refreshPendingStates)
Events.OnServerCommand.Add(onServerCommand)
Events.OnConnected.Add(RandomZeds.forceVanillaPerceptionDefaults)
Events.OnGameStart.Add(RandomZeds.forceVanillaPerceptionDefaults)
