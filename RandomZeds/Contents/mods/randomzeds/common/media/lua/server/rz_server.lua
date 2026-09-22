if isClient() then return end

local mode = isServer() and require "modules/mode/online" or require "modules/mode/offline"
local RandomZeds = require "rz_shared"
local Config = require "modules/config"
local initialized = false

local function createProtection(mode)
    local PROTECTION_RADIUS = 50
    local PROTECTION_RADIUS_SQUARED = PROTECTION_RADIUS * PROTECTION_RADIUS
    local PROTECTED_CHUNK_RADIUS = math.ceil(PROTECTION_RADIUS / 8)
    local crawlerProtectionEnabled = isMultiplayer()
    local protectedChunks = {}
    local protectedChunkCounts = {}
    local playerProtectedChunks = {}
    local protectedPlayers = table.newarray()
    local protectedPlayerIndices = {}
    local isCrawlerProtected

    local function getChunkCoordinates(square)
        if not square then return nil, nil end
        local chunk = square:getChunk()
        local chunkX = chunk and tonumber(chunk.wx)
        local chunkY = chunk and tonumber(chunk.wy)
        if chunkX and chunkY then return chunkX, chunkY end
        local chunkSize = getChunkSizeInSquares and tonumber(getChunkSizeInSquares()) or 8
        if not chunkSize or chunkSize <= 0 then return nil, nil end
        local squareX = tonumber(square:getX())
        local squareY = tonumber(square:getY())
        if not squareX or not squareY then return nil, nil end
        return math.floor(squareX / chunkSize), math.floor(squareY / chunkSize)
    end

    local function makeChunkKey(chunkX, chunkY)
        if not chunkX or not chunkY then return nil end
        return tostring(chunkX) .. ":" .. tostring(chunkY)
    end

    local function getChunkKeyFromSquare(square)
        local chunkX, chunkY = getChunkCoordinates(square)
        return makeChunkKey(chunkX, chunkY)
    end

    local function changeProtectedChunkCount(chunkKey, delta)
        if not chunkKey then return end

        delta = tonumber(delta) or 0
        local count = (tonumber(protectedChunkCounts[chunkKey]) or 0) + delta
        if count > 0 then
            protectedChunkCounts[chunkKey] = count
            protectedChunks[chunkKey] = true
        else
            protectedChunkCounts[chunkKey] = nil
            protectedChunks[chunkKey] = nil
        end
    end

    local function removePlayerProtectedChunks(player)
        local coverage = playerProtectedChunks[player]
        if not coverage then return end

        for index = 1, #coverage.chunks do
            changeProtectedChunkCount(coverage.chunks[index], -1)
        end
        playerProtectedChunks[player] = nil

        local playerIndex = protectedPlayerIndices[player]
        if not playerIndex then return end
        local lastIndex = #protectedPlayers
        local lastPlayer = protectedPlayers[lastIndex]
        protectedPlayers[playerIndex] = lastPlayer
        protectedPlayerIndices[lastPlayer] = playerIndex
        protectedPlayers[lastIndex] = nil
        protectedPlayerIndices[player] = nil
    end

    local function updatePlayerProtectedChunks(player)
        if not player then return end
        local playerX = player:getX()
        local playerY = player:getY()
        local square = player:getSquare()
        local chunkX, chunkY = getChunkCoordinates(square)
        local chunkKey = makeChunkKey(chunkX, chunkY)
        local previous = playerProtectedChunks[player]
        if previous and previous.centerKey == chunkKey then
            previous.x = playerX
            previous.y = playerY
            return
        end

        removePlayerProtectedChunks(player)
        if not chunkKey then return end

        local coverage = {
            centerKey = chunkKey,
            x = playerX,
            y = playerY,
            chunks = table.newarray(),
        }
        for offsetX = -PROTECTED_CHUNK_RADIUS, PROTECTED_CHUNK_RADIUS do
            for offsetY = -PROTECTED_CHUNK_RADIUS, PROTECTED_CHUNK_RADIUS do
                local protectedKey = makeChunkKey(
                    chunkX + offsetX,
                    chunkY + offsetY
                )
                coverage.chunks[#coverage.chunks + 1] = protectedKey
                changeProtectedChunkCount(protectedKey, 1)
            end
        end
        playerProtectedChunks[player] = coverage
        protectedPlayers[#protectedPlayers + 1] = player
        protectedPlayerIndices[player] = #protectedPlayers
    end

    local function refreshProtectedChunks()
        local seenPlayers = {}
        local refreshed = mode.forEachPlayer(function(player)
            seenPlayers[player] = true
            updatePlayerProtectedChunks(player)
        end)
        if not refreshed then return end

        for index = #protectedPlayers, 1, -1 do
            local player = protectedPlayers[index]
            if not seenPlayers[player] then
                removePlayerProtectedChunks(player)
            end
        end
    end

    isCrawlerProtected = function(zombie)
        if not crawlerProtectionEnabled then return false end
        local square = zombie and zombie:getSquare()
        local chunkKey = getChunkKeyFromSquare(square)
        if chunkKey == nil or protectedChunks[chunkKey] ~= true then
            return false
        end

        for index = 1, #protectedPlayers do
            local player = protectedPlayers[index]
            local coverage = playerProtectedChunks[player]
            if zombie:DistToSquared(coverage.x, coverage.y)
                    <= PROTECTION_RADIUS_SQUARED then
                return true
            end
        end

        return false
    end

    local function onPlayerCreated(_playerIndex, player)
        updatePlayerProtectedChunks(player)
    end

    local function onPlayerMove(player)
        updatePlayerProtectedChunks(player)
    end

    return {
        refreshProtectedChunks = refreshProtectedChunks,
        onPlayerCreated = onPlayerCreated,
        onPlayerMove = onPlayerMove,
        isCrawlerProtected = isCrawlerProtected,
    }
end

local protection = createProtection(mode)

local WEATHER_PERIOD = Config.WEATHER_PERIOD
local DISABLED_PERIOD = Config.DISABLED_PERIOD
local FEATURE_PROFILE_NAMES = Config.FEATURE_PROFILE_NAMES
local PROFILE_DEFINITIONS = Config.PROFILE_DEFINITIONS
local SPEED_TYPES = RandomZeds.SPEED_TYPES

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
local PENDING_SPEED_TAG = "RandomZedsPendingSpeedType"
local PENDING_SPRINTER_MULTIPLIER_TAG = "RandomZedsPendingSprinterMultiplier"
local PENDING_HEALTH_TAG = "RandomZedsPendingHealth"
local PENDING_SIGHT_TAG = "RandomZedsPendingSight"
local PENDING_HEARING_TAG = "RandomZedsPendingHearing"
local PENDING_COGNITION_TAG = "RandomZedsPendingCognition"
local PENDING_STRENGTH_TAG = "RandomZedsPendingStrength"
local PENDING_MEMORY_TAG = "RandomZedsPendingMemory"
local PENDING_PERIOD_TAG = "RandomZedsPendingPeriod"
local PENDING_STATE_FIELDS = table.newarray(
    { name = "speedType", tag = PENDING_SPEED_TAG },
    { name = "multiplier", tag = PENDING_SPRINTER_MULTIPLIER_TAG },
    { name = "health", tag = PENDING_HEALTH_TAG },
    { name = "sight", tag = PENDING_SIGHT_TAG },
    { name = "hearing", tag = PENDING_HEARING_TAG },
    { name = "cognition", tag = PENDING_COGNITION_TAG },
    { name = "strength", tag = PENDING_STRENGTH_TAG },
    { name = "memory", tag = PENDING_MEMORY_TAG },
    { name = "period", tag = PENDING_PERIOD_TAG }
)
local INITIAL_STATE_BUDGET_MS = 3
local SPRINTER_RECONCILE_BUDGET_MS = 4
local SPRINTER_CHECK_COOLDOWN_MS = 1000
local PENDING_STATE_TIMEOUT_MS = 60000
local PENDING_STAND_UP_TIMEOUT_MS = 30000
local PENDING_REROLL_CHECK_INTERVAL_MS = 1000

local lastEffectiveMode
local lastEffectiveSignature
local lastEffectiveConfig
local pendingStandUps = {}
local pendingZombieCreates = {}
local pendingCrawlerRerollCheckRequired = false
local nextPendingRerollCheckAt = 0
local sprinterCheckCursor = { index = 0 }
local sprinterCheckCooldowns = setmetatable({}, { __mode = "k" })

local function getRandomSpeedType(config, allowCrawler)
    local roll = ZombRandFloat(0, 100)
    local threshold = 0

    for index = 1, #SPEED_TYPES do
        local speedType = SPEED_TYPES[index]
        if speedType == "crawler" and allowCrawler == false then
            return "fastShambler"
        end

        threshold = threshold + config[speedType]
        if roll < threshold then
            return speedType
        end
    end

    return "crawler"
end

local function rollPerception(chances, order, values)
    local roll = ZombRandFloat(0, 100)
    local threshold = 0
    for index = 1, #order do
        local level = order[index]
        threshold = threshold + chances[level]
        if roll < threshold then return values[level] end
    end
    return values[order[#order]]
end

local function rollZombieHealth(chances)
    local definition = PROFILE_DEFINITIONS.health
    local health = rollPerception(chances, definition.levels, definition.values)
    return health + ZombRandFloat(0, 0.3)
end

local function rollProfile(config, profileName, speedType)
    local definition = PROFILE_DEFINITIONS[profileName]
    return rollPerception(
        config[profileName][speedType], definition.levels, definition.values)
end

local function rollSprinterMultiplier(config, speedType)
    local multiplier = config.sprinterSpeedMultiplier
    local decrease = config.sprinterSpeedVariationDecrease
    local increase = config.sprinterSpeedVariationIncrease
    if speedType ~= "sprinter" or (decrease <= 0 and increase <= 0) then
        return multiplier
    end

    return ZombRandFloat(
        math.max(RandomZeds.MIN_SPRINTER_MULTIPLIER, multiplier - decrease),
        math.min(RandomZeds.MAX_SPRINTER_MULTIPLIER, multiplier + increase)
    )
end

local function hasPendingReroll(modData)
    return modData[PENDING_SPEED_TAG] ~= nil
end

local function clearPendingReroll(modData)
    for index = 1, #PENDING_STATE_FIELDS do
        local field = PENDING_STATE_FIELDS[index]
        modData[field.tag] = nil
    end
end

local function writePendingState(modData, state)
    for index = 1, #PENDING_STATE_FIELDS do
        local field = PENDING_STATE_FIELDS[index]
        modData[field.tag] = state[field.name]
    end
end

local function readPendingState(modData)
    local state = {}
    for index = 1, #PENDING_STATE_FIELDS do
        local field = PENDING_STATE_FIELDS[index]
        state[field.name] = modData[field.tag]
    end
    return state
end

local function queueStandUpRetry(zombie)
    local deadline = pendingStandUps[zombie]
    if deadline == nil then
        pendingStandUps[zombie] = getTimestampMs() + PENDING_STAND_UP_TIMEOUT_MS
        return
    end
    pendingStandUps[zombie] = tonumber(deadline)
        or getTimestampMs() + PENDING_STAND_UP_TIMEOUT_MS
end

local function discardPendingRerolls()
    pendingStandUps = {}
    pendingZombieCreates = {}
    pendingCrawlerRerollCheckRequired = false
    if mode.resetStateSync then mode.resetStateSync() end
    RandomZeds.forEachLoadedZombie(function(zombie)
        local modData = zombie:getModData()
        if modData and not RandomZeds.isExcluded(zombie, modData)
                and hasPendingReroll(modData) then
            clearPendingReroll(modData)
        end
    end)
end

local function queuePendingState(zombie, state)
    if RandomZeds.isExcluded(zombie) then return end

    local modData = zombie:getModData()
    if not modData then return end
    writePendingState(modData, state)
end

local function deferBlockedZombieState(zombie, state, gettingUp)
    if not gettingUp then
        RandomZeds.setCrawlerState(zombie, false)
    end
    queuePendingState(zombie, state)
    queueStandUpRetry(zombie)
end

local function isSameFeatureState(modData, state)
    local storedState = {
        cognition = RandomZeds.readOptionalInteger(
            modData[COGNITION_TAG], "stored cognition profile"),
        strength = RandomZeds.readOptionalInteger(
            modData[STRENGTH_TAG], "stored strength profile"),
        memory = RandomZeds.readOptionalInteger(
            modData[MEMORY_TAG], "stored memory profile"),
    }
    if not RandomZeds.validateOptionalFeatureState(
            storedState, "Stored zombie feature state") then
        return false
    end
    if not RandomZeds.hasFeatureState(state) then
        return not RandomZeds.hasPartialFeatureState(storedState)
    end
    return storedState.cognition == state.cognition
        and storedState.strength == state.strength
        and storedState.memory == state.memory
end

local function validateZombieState(state)
    if type(state) ~= "table" then return false end
    state.period = RandomZeds.requireProfilePeriod(state.period)
    if not state.period or not RandomZeds.requireSpeedTypeId(state.speedType) then
        return false
    end
    state.multiplier = RandomZeds.requireSprinterMultiplier(
        state.multiplier, "zombie state multiplier") or 1.0
    state.health = RandomZeds.requireRange(
        state.health, "zombie state health", 0.5, 3.8) or 1.5
    state.sight = RandomZeds.requireIntegerRange(
        state.sight, "zombie state sight", 1, 3) or 2
    state.hearing = RandomZeds.requireIntegerRange(
        state.hearing, "zombie state hearing", 1, 3) or 2
    return RandomZeds.validateOptionalFeatureState(state, "Zombie state")
end

local function isSameZombieState(modData, state)
    if modData[PERIOD_TAG] ~= state.period
            or modData[SPEED_TAG] ~= state.speedType then
        return false
    end
    local multiplier = RandomZeds.readOptionalNumber(
        modData[SPRINTER_MULTIPLIER_TAG], "stored sprinter multiplier")
    local health = RandomZeds.readOptionalNumber(
        modData[HEALTH_TAG], "stored zombie health")
    local sight = RandomZeds.readOptionalInteger(
        modData[SIGHT_TAG], "stored zombie sight")
    local hearing = RandomZeds.readOptionalInteger(
        modData[HEARING_TAG], "stored zombie hearing")
    return multiplier == state.multiplier
        and health == state.health
        and sight == state.sight
        and hearing == state.hearing
        and isSameFeatureState(modData, state)
end

local function repairSameStateSprinter(zombie, state, modData)
    if RandomZeds.dispatchZombieState(zombie, state) then
        RandomZeds.reconcileSprinterMotion(zombie)
        if state.baseSpeed ~= nil then
            modData[SPRINTER_BASE_SPEED_TAG] = state.baseSpeed
        end
        clearPendingReroll(modData)
        if mode.deferStateConfirmation then mode.deferStateConfirmation(zombie, state) end
        pendingStandUps[zombie] = nil
        return
    end

    RandomZeds.applyZombieSpeedType(zombie, state.speedType, state.multiplier)
    if not RandomZeds.isZombieSpeedTypeApplied(
            zombie, state.speedType) then
        return
    end

    RandomZeds.reconcileSprinterMotion(zombie)
    clearPendingReroll(modData)
    if mode.deferStateConfirmation then mode.deferStateConfirmation(zombie, state) end
    pendingStandUps[zombie] = nil
end

local function writeAppliedZombieState(zombie, modData, state, synapseEnabled)
    if not synapseEnabled then
        zombie:setHealth(state.health)
    end
    modData[PERIOD_TAG] = state.period
    modData[SPEED_TAG] = state.speedType
    modData[SPRINTER_MULTIPLIER_TAG] = state.multiplier
    if synapseEnabled then
        if state.speedType == "sprinter" and state.baseSpeed ~= nil then
            modData[SPRINTER_BASE_SPEED_TAG] = state.baseSpeed
        elseif state.speedType ~= "sprinter" then
            modData[SPRINTER_BASE_SPEED_TAG] = nil
        end
    end
    modData[HEALTH_TAG] = state.health
    modData[SIGHT_TAG] = state.sight
    modData[HEARING_TAG] = state.hearing
    modData[COGNITION_TAG] = state.cognition
    modData[STRENGTH_TAG] = state.strength
    modData[MEMORY_TAG] = state.memory
    if mode.persistRerollRevision then mode.persistRerollRevision(modData) end
    clearPendingReroll(modData)
end

local function applyFreshZombieState(zombie, modData, state)
    local synapseApplied = RandomZeds.dispatchZombieState(zombie, state)
    if synapseApplied then
        writeAppliedZombieState(zombie, modData, state, true)
        return true
    end

    RandomZeds.applyZombieNativeStats(zombie, state.sight, state.hearing)
    RandomZeds.applyZombieFeatureState(zombie, state)
    if not RandomZeds.applyZombieSpeedType(zombie, state.speedType, state.multiplier) then
        return false
    end
    writeAppliedZombieState(zombie, modData, state, false)
    return true
end

local function applySameZombieState(zombie, modData, state)
    if not isSameZombieState(modData, state) then return false end

    if RandomZeds.dispatchZombieState(zombie, state) then
        if state.speedType == "sprinter" then
            RandomZeds.reconcileSprinterMotion(zombie)
            if state.baseSpeed ~= nil then
                modData[SPRINTER_BASE_SPEED_TAG] = state.baseSpeed
            end
        end
        clearPendingReroll(modData)
        pendingStandUps[zombie] = nil
        return true
    end

    local typeApplied = RandomZeds.isZombieSpeedTypeApplied(
        zombie, state.speedType)
    if typeApplied then
        if state.speedType == "sprinter" then
            if not isMultiplayer() and RandomZeds.hasSynapseFeatureSupport() then
                RandomZeds.applyZombieSpeedType(
                    zombie, "sprinter", state.multiplier)
            elseif mode.applySprinterAnimationSpeed then
                mode.applySprinterAnimationSpeed(zombie, state.multiplier)
            end
            RandomZeds.reconcileSprinterMotion(zombie)
        end
        zombie:setHealth(state.health)
        clearPendingReroll(modData)
        pendingStandUps[zombie] = nil
        return true
    end

    if state.speedType ~= "sprinter" then return false end
    repairSameStateSprinter(zombie, state, modData)
    return true
end

local function deferUnappliedZombieState(zombie, state)
    queuePendingState(zombie, state)
    queueStandUpRetry(zombie)
end

local function applyValidatedZombieState(zombie, state)
    if not zombie then return false end
    local modData = zombie:getModData()
    if not modData then return false end
    local gettingUp = zombie:getCurrentActionContextStateName() == "getup"

    if gettingUp or (state.speedType ~= "crawler"
            and zombie:isCrawling()
            and not RandomZeds.hasSynapseFeatureSupport()) then
        deferBlockedZombieState(zombie, state, gettingUp)
        return
    end

    if applySameZombieState(zombie, modData, state) then return end
    if not applyFreshZombieState(zombie, modData, state) then
        return false
    end
    if not RandomZeds.isZombieSpeedTypeApplied(zombie, state.speedType) then
        deferUnappliedZombieState(zombie, state)
        return
    end
    if mode.deferStateConfirmation then mode.deferStateConfirmation(zombie, state) end
    pendingStandUps[zombie] = nil
end

local function applyZombieState(zombie, state)
    if not zombie or RandomZeds.isExcluded(zombie) then return false end
    if not validateZombieState(state) then return false end
    return applyValidatedZombieState(zombie, state)
end

local function addRolledProfileState(state, config, speedType)
    state.sight = rollProfile(config, "sight", speedType)
    state.hearing = rollProfile(config, "hearing", speedType)
    if not config.featuresEnabled then return end
    for index = 1, #FEATURE_PROFILE_NAMES do
        local profileName = FEATURE_PROFILE_NAMES[index]
        state[profileName] = rollProfile(config, profileName, speedType)
    end
end

local function rollZombieState(config, period, allowCrawler)
    local speedType = getRandomSpeedType(config, allowCrawler)
    local state = {
        period = period,
        speedType = speedType,
        health = rollZombieHealth(config.health[speedType]),
        multiplier = rollSprinterMultiplier(config, speedType),
    }
    addRolledProfileState(state, config, speedType)
    return state
end

local function applyZombieType(zombie, config, period, allowCrawler)
    if RandomZeds.isExcluded(zombie) then return end

    if not config then
        period = lastEffectiveMode
        config = lastEffectiveConfig
        if not config then
            period, config = Config.getEffectiveProfile()
        end
        if not config then
            return
        end
    end

    applyValidatedZombieState(zombie, rollZombieState(config, period, allowCrawler))
end

local function queueCrawlerReroll(zombie, config, period)
    if RandomZeds.isExcluded(zombie) then return end

    queuePendingState(zombie, rollZombieState(config, period, true))
    pendingCrawlerRerollCheckRequired = true
end

local function applyPendingZombieState(zombie, modData)
    if not modData or RandomZeds.isExcluded(zombie, modData) then return end

    local state = readPendingState(modData)
    local speedType = state.speedType
    if not speedType then return end
    state.period = state.period or Config.getCurrentPeriod()
    state.multiplier = tonumber(state.multiplier) or 1.0
    state.health = tonumber(state.health) or zombie:getHealth()
    state.sight = tonumber(state.sight) or 2
    state.hearing = tonumber(state.hearing) or 2

    applyZombieState(zombie, state)
end

local function applyUnprotectedPendingReroll(zombie, modData)
    if modData[PENDING_PERIOD_TAG] ~= lastEffectiveMode then
        local pendingPeriod = modData[PENDING_PERIOD_TAG]
        applyZombieType(zombie)
        if modData[PENDING_PERIOD_TAG] == pendingPeriod then
            clearPendingReroll(modData)
        end
    else
        applyPendingZombieState(zombie, modData)
    end
end

local function isSprinterReadyForCheck(zombie, modData)
    if not zombie or not modData or RandomZeds.isExcluded(zombie, modData)
            or zombie:isDead() or not zombie:getSquare()
            or zombie:isCrawling()
            or zombie:getCurrentActionContextStateName() == "getup" then
        return false
    end

    return modData[SPEED_TAG] == "sprinter"
        and not modData[PENDING_SPEED_TAG]
end

local function correctSprinterState(zombie)
    local modData = zombie:getModData()
    if not modData then return false end
    local state = {
        period = modData[PERIOD_TAG] or lastEffectiveMode,
        speedType = "sprinter",
        multiplier = modData[SPRINTER_MULTIPLIER_TAG],
        baseSpeed = modData[SPRINTER_BASE_SPEED_TAG],
        health = modData[HEALTH_TAG],
        sight = modData[SIGHT_TAG],
        hearing = modData[HEARING_TAG],
        cognition = modData[COGNITION_TAG],
        strength = modData[STRENGTH_TAG],
        memory = modData[MEMORY_TAG],
    }
    if not validateZombieState(state) then return false end
    if state.period == DISABLED_PERIOD then return false end

    local typeApplied = RandomZeds.isZombieSpeedTypeApplied(
        zombie, "sprinter")
    if typeApplied then
        if not RandomZeds.hasSynapseFeatureSupport() then
            if mode.applySprinterAnimationSpeed then mode.applySprinterAnimationSpeed(zombie, state.multiplier) end
        end
        RandomZeds.reconcileSprinterMotion(zombie)
        return false
    end

    if RandomZeds.dispatchZombieState(zombie, state) then
        RandomZeds.reconcileSprinterMotion(zombie)
        if state.baseSpeed ~= nil then
            modData[SPRINTER_BASE_SPEED_TAG] = state.baseSpeed
        end
        if mode.deferStateConfirmation then mode.deferStateConfirmation(zombie, state) end
        return true
    end

    RandomZeds.applyZombieSpeedType(zombie, "sprinter", state.multiplier)
    RandomZeds.reconcileSprinterMotion(zombie)
    if not RandomZeds.isZombieSpeedTypeApplied(zombie, "sprinter") then
        return false
    end

    if mode.deferStateConfirmation then mode.deferStateConfirmation(zombie, state) end
    return true
end

local function verifyLoadedSprinter(zombie, now, modData)
    if not isSprinterReadyForCheck(zombie, modData) then return false end

    local cooldownAt = sprinterCheckCooldowns[zombie]
    if cooldownAt == nil then
        cooldownAt = 0
    else
        cooldownAt = tonumber(cooldownAt) or 0
    end
    if now < cooldownAt then return false end
    sprinterCheckCooldowns[zombie] = now + SPRINTER_CHECK_COOLDOWN_MS

    return correctSprinterState(zombie)
end

local function verifySprinterStates()
    if lastEffectiveMode == DISABLED_PERIOD then return end

    local now = getTimestampMs()

    local corrected = false
    RandomZeds.forEachLoadedZombieWithinBudget(
        sprinterCheckCursor,
        SPRINTER_RECONCILE_BUDGET_MS,
        function(zombie)
            local modData = zombie and zombie:getModData()
            if modData and modData[PENDING_SPEED_TAG]
                    and (zombie:isCrawling() or modData[SPEED_TAG] == "crawler")
                    and not pendingStandUps[zombie]
                    and not zombie:isDead()
                    and zombie:getCurrentSquare()
                    and not RandomZeds.isExcluded(zombie, modData)
                    and not protection.isCrawlerProtected(zombie) then
                applyUnprotectedPendingReroll(zombie, modData)
            end
            if verifyLoadedSprinter(zombie, now, modData) then
                corrected = true
            end
        end
    )

    if corrected then
        if mode.flushServerStates then mode.flushServerStates() end
    end
end

local function reconcileCell(cell, period, config)
    if not cell then return end
    local zombies = cell:getZombieList()
    if not zombies then return end

    local zombieCount = zombies:size()

    for zombieIndex = 0, zombieCount - 1 do
        local zombie = zombies:get(zombieIndex)
        if zombie then
            local modData = zombie:getModData()
            if modData and not RandomZeds.isExcluded(zombie, modData)
                    and not zombie:isDead() then
                local crawlerProtected = protection.isCrawlerProtected(zombie)
                if crawlerProtected and (zombie:isCrawling() or modData[SPEED_TAG] == "crawler") then
                    queueCrawlerReroll(zombie, config, period)
                else
                    applyZombieType(zombie, config, period, not crawlerProtected)
                end
            end
        end
    end

    if mode.flushServerStates then mode.flushServerStates() end
end

local function reconcileZombies(period, config)
    reconcileCell(getCell(), period, config)
end

local function processPendingRerollCandidate(zombie, pending)
    local modData = zombie:getModData()
    if not modData or RandomZeds.isExcluded(zombie, modData)
            or zombie:isDead() or not modData[PENDING_SPEED_TAG] then
        return
    end

    if protection.isCrawlerProtected(zombie) then
        pendingCrawlerRerollCheckRequired = true
    elseif modData[PENDING_PERIOD_TAG] ~= lastEffectiveMode then
        applyUnprotectedPendingReroll(zombie, modData)
        if mode.flushServerStates then mode.flushServerStates() end
    else
        pending[#pending + 1] = zombie
    end
end

local function applyPendingRerolls()
    if lastEffectiveMode == DISABLED_PERIOD then
        pendingCrawlerRerollCheckRequired = false
        return
    end

    local pending = table.newarray()
    pendingCrawlerRerollCheckRequired = false
    RandomZeds.forEachLoadedZombie(function(zombie)
        processPendingRerollCandidate(zombie, pending)
    end)

    if #pending == 0 then return end
    if mode.advanceRerollRevision then mode.advanceRerollRevision() end
    for index = 1, #pending do
        local zombie = pending[index]
        applyUnprotectedPendingReroll(zombie, zombie:getModData())
    end
    if mode.flushServerStates then mode.flushServerStates() end
end

local function processPendingZombieCreates()
    local visited = 0
    local getTimestamp = getTimestampMs
    local now = getTimestamp()
    local deadline = now + INITIAL_STATE_BUDGET_MS
    for zombie in pairs(pendingZombieCreates) do
        if visited > 0 and getTimestamp() >= deadline then break end
        visited = visited + 1
        local expiresAt = pendingZombieCreates[zombie]
        if not zombie:getCurrentSquare() or zombie:isDead()
                or RandomZeds.isExcluded(zombie) then
            pendingZombieCreates[zombie] = nil
        elseif mode.shouldDeferPendingZombie
                and mode.shouldDeferPendingZombie(zombie, protection.isCrawlerProtected) then
            pendingZombieCreates[zombie] = now + PENDING_STATE_TIMEOUT_MS
        elseif expiresAt and now >= expiresAt then
            pendingZombieCreates[zombie] = nil
        elseif zombie:getSquare() then
            applyZombieType(
                zombie, nil, nil, mode.pendingZombieCrawlerAllowed)
            pendingZombieCreates[zombie] = nil
        end
    end
end

local function processPendingStandUps()
    local ready = table.newarray()
    local now = getTimestampMs()
    for zombie, expiresAt in pairs(pendingStandUps) do
        if not zombie:getCurrentSquare() or zombie:isDead()
                or RandomZeds.isExcluded(zombie) then
            pendingStandUps[zombie] = nil
        elseif expiresAt and now >= expiresAt then
            pendingStandUps[zombie] = nil
            local modData = zombie:getModData()
            if modData then clearPendingReroll(modData) end
        elseif not zombie:isCrawling()
                and zombie:getCurrentActionContextStateName() ~= "getup" then
            pendingStandUps[zombie] = nil
            ready[#ready + 1] = zombie
        end
    end

    if #ready == 0 then return end

    if mode.advanceRerollRevision then mode.advanceRerollRevision() end
    for index = 1, #ready do
        local zombie = ready[index]
        applyPendingZombieState(zombie, zombie:getModData())
    end
end

local function applyEffectiveProfile(period, config, signature)
    if not config then
        discardPendingRerolls()
        lastEffectiveMode = period
        lastEffectiveSignature = signature
        lastEffectiveConfig = nil
        return
    end

    protection.refreshProtectedChunks()
    if mode.advanceRerollRevision then mode.advanceRerollRevision() end
    reconcileZombies(period, config)
    lastEffectiveMode = period
    lastEffectiveSignature = signature
    lastEffectiveConfig = config
end

local function updateEffectiveState()
    RandomZeds.forceVanillaPerceptionDefaults()
    local period, config, signature = Config.getEffectiveProfile()
    if period ~= lastEffectiveMode or signature ~= lastEffectiveSignature then
        applyEffectiveProfile(period, config, signature)
    end

    applyPendingRerolls()
end

local function onWeatherPeriodComplete()
    if lastEffectiveMode ~= WEATHER_PERIOD then
        updateEffectiveState()
        return
    end
    RandomZeds.forceVanillaPerceptionDefaults()

    local period = Config.getCurrentPeriod()
    if period == DISABLED_PERIOD then
        applyEffectiveProfile(period, nil, period)
        return
    end
    local _, config, signature = Config.readProfile(
        period, Config.getOptionPrefix(period), "")
    applyEffectiveProfile(period, config, signature)
    applyPendingRerolls()
end

local function onZombieCreate(zombie)
    if RandomZeds.isExcluded(zombie) then return end

    if lastEffectiveConfig and zombie:getSquare() then
        local modData = zombie:getModData()
        local crawlerProtected = protection.isCrawlerProtected(zombie)
        if crawlerProtected and (zombie:isCrawling()
                    or (modData and modData[SPEED_TAG] == "crawler")) then
            queueCrawlerReroll(zombie, lastEffectiveConfig, lastEffectiveMode)
        else
            applyZombieType(zombie, lastEffectiveConfig, lastEffectiveMode)
        end
        return
    end
    pendingZombieCreates[zombie] = getTimestampMs() + PENDING_STATE_TIMEOUT_MS
end

local function processPendingZombieWork()
    if lastEffectiveMode == DISABLED_PERIOD then return end
    if RandomZeds.hasPendingEntries(pendingZombieCreates) then
        processPendingZombieCreates()
    end
    if mode.processPendingServerStates then
        mode.processPendingServerStates()
    end
    if RandomZeds.hasPendingEntries(pendingStandUps) then
        processPendingStandUps()
    end
    verifySprinterStates()
end

local function processPendingCrawlerRerolls(now)
    if not pendingCrawlerRerollCheckRequired
            or now < nextPendingRerollCheckAt then
        return
    end
    nextPendingRerollCheckAt = now + PENDING_REROLL_CHECK_INTERVAL_MS
    protection.refreshProtectedChunks()
    applyPendingRerolls()
end

local SCHEDULE_INTERVAL_MS = 250
local nextScheduledWorkAt = 0

local function processScheduledZombieWork()
    local now = getTimestampMs()
    if now < nextScheduledWorkAt then return end
    nextScheduledWorkAt = now + SCHEDULE_INTERVAL_MS
    processPendingZombieWork()
    processPendingCrawlerRerolls(now)
    RandomZeds.refreshSprinterAnimationSpeeds()
end

local function processScheduledWork()
    if mode.processNetworkStateWork then
        mode.processNetworkStateWork()
    end
    processScheduledZombieWork()
end

local function initialize()
    if initialized then return end

    Events.OnZombieCreate.Add(onZombieCreate)
    Events.OnCreatePlayer.Add(protection.onPlayerCreated)
    Events.OnPlayerMove.Add(protection.onPlayerMove)
    Events.OnWeatherPeriodStart.Add(updateEffectiveState)
    Events.OnWeatherPeriodStage.Add(updateEffectiveState)
    Events.OnWeatherPeriodComplete.Add(onWeatherPeriodComplete)
    Events.OnTick.Add(processScheduledWork)
    Events.EveryOneMinute.Add(updateEffectiveState)
    Events.EveryOneMinute.Add(protection.refreshProtectedChunks)
    protection.refreshProtectedChunks()
    updateEffectiveState()
    initialized = true
end

mode.registerInitialization(initialize)
