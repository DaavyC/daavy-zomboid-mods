if isClient() then return end

local mode = isServer() and require "modules/mode/online" or require "modules/mode/offline"
local RandomZeds = require "rz_shared"
local Config = require "modules/config"
local MIN_SPEED_MULTIPLIER = RandomZeds.MIN_SPEED_MULTIPLIER
local MAX_SPEED_MULTIPLIER = RandomZeds.MAX_SPEED_MULTIPLIER
local SPEED_VARIATION_STEP = RandomZeds.SPEED_VARIATION_STEP
local SPEED_VARIATION_BOUNDARY_EPSILON = 0.0000001
local initialized = false

local function createProtection(mode)
    local PROTECTION_RADIUS = 50
    local PROTECTION_RADIUS_SQUARED = PROTECTION_RADIUS * PROTECTION_RADIUS
    local PROTECTED_CHUNK_RADIUS = math.ceil(PROTECTION_RADIUS / 8)
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

local DISABLED_PERIOD = Config.DISABLED_PERIOD
local FEATURE_PROFILE_NAMES = Config.FEATURE_PROFILE_NAMES
local PROFILE_DEFINITIONS = Config.PROFILE_DEFINITIONS
local SPEED_TYPES = RandomZeds.SPEED_TYPES
local SPEED_TYPE_IDS = RandomZeds.SPEED_TYPE_IDS

local PERIOD_TAG = "RandomZedsPeriod"
local SPEED_TAG = "RandomZedsSpeedType"
local SPRINTER_MULTIPLIER_TAG = "RandomZedsSprinterMultiplier"
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local SPEED_BASE_SPEED_TAG = "RandomZedsSpeedBaseSpeed"
local HEALTH_TAG = "RandomZedsHealth"
local SIGHT_TAG = "RandomZedsSight"
local HEARING_TAG = "RandomZedsHearing"
local COGNITION_TAG = "RandomZedsCognition"
local STRENGTH_TAG = "RandomZedsStrength"
local MEMORY_TAG = "RandomZedsMemory"
local PENDING_SPEED_TAG = "RandomZedsPendingSpeedType"
local PENDING_SPRINTER_MULTIPLIER_TAG = "RandomZedsPendingSprinterMultiplier"
local PENDING_BASE_SPEED_TAG = "RandomZedsPendingSpeedBaseSpeed"
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
    { name = "baseSpeed", tag = PENDING_BASE_SPEED_TAG },
    { name = "health", tag = PENDING_HEALTH_TAG },
    { name = "sight", tag = PENDING_SIGHT_TAG },
    { name = "hearing", tag = PENDING_HEARING_TAG },
    { name = "cognition", tag = PENDING_COGNITION_TAG },
    { name = "strength", tag = PENDING_STRENGTH_TAG },
    { name = "memory", tag = PENDING_MEMORY_TAG },
    { name = "period", tag = PENDING_PERIOD_TAG }
)
local INITIAL_STATE_BUDGET_MS = 3
local PENDING_STATE_TIMEOUT_MS = 60000
local PENDING_STAND_UP_TIMEOUT_MS = 30000
local PENDING_REROLL_CHECK_INTERVAL_MS = 1000
local lastEffectiveMode
local lastEffectiveSignature
local lastEffectiveConfig
local pendingStandUps = {}
local pendingZombieCreates = {}
local function createPendingCrawlerRerolls()
    return setmetatable({}, { __mode = "k" })
end
local pendingCrawlerRerolls = createPendingCrawlerRerolls()
local pendingCrawlerRerollCheckRequired = false
local nextPendingRerollCheckAt = 0

local function getRandomSpeedType(config)
    local roll = ZombRandFloat(0, 100)
    local threshold = 0

    for index = 1, #SPEED_TYPES do
        local speedType = SPEED_TYPES[index]
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

local function getSpeedVariationSteps(multiplier, decrease, increase)
    local minimumStep = math.ceil(
        (MIN_SPEED_MULTIPLIER - multiplier) / SPEED_VARIATION_STEP
            - SPEED_VARIATION_BOUNDARY_EPSILON)
    local maximumStep = math.floor(
        (MAX_SPEED_MULTIPLIER - multiplier) / SPEED_VARIATION_STEP
            + SPEED_VARIATION_BOUNDARY_EPSILON)
    local firstStep = math.max(
        -math.floor(decrease / SPEED_VARIATION_STEP + 0.5), minimumStep)
    local lastStep = math.min(
        math.floor(increase / SPEED_VARIATION_STEP + 0.5), maximumStep)
    return firstStep, lastStep
end

local function rollSpeedMultiplier(config, speedType)
    local settings = config.speedSettings[speedType]
    local multiplier = settings.multiplier
    local decrease = settings.variationDecrease
    local increase = settings.variationIncrease
    if decrease <= 0 and increase <= 0 then return multiplier end

    local firstStep, lastStep = getSpeedVariationSteps(
        multiplier, decrease, increase)
    local rolledStep = firstStep + ZombRand(lastStep - firstStep + 1)
    return math.max(
        MIN_SPEED_MULTIPLIER,
        math.min(
            MAX_SPEED_MULTIPLIER,
            multiplier + rolledStep * SPEED_VARIATION_STEP
        )
    )
end

local function hasPendingReroll(modData)
    return modData[PENDING_SPEED_TAG] ~= nil
end

local function clearPendingReroll(zombie, modData)
    for index = 1, #PENDING_STATE_FIELDS do
        local field = PENDING_STATE_FIELDS[index]
        modData[field.tag] = nil
    end
    pendingCrawlerRerolls[zombie] = nil
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
    if pendingStandUps[zombie] == nil then
        pendingStandUps[zombie] = {
            expiresAt = getTimestampMs() + PENDING_STAND_UP_TIMEOUT_MS,
            revisionAdvanced = false,
        }
    end
end

local function discardPendingRerolls()
    pendingStandUps = {}
    pendingZombieCreates = {}
    pendingCrawlerRerolls = createPendingCrawlerRerolls()
    pendingCrawlerRerollCheckRequired = false
    if mode.resetStateSync then mode.resetStateSync() end
    RandomZeds.forEachLoadedZombie(function(zombie)
        local modData = zombie:getModData()
        if modData and not RandomZeds.isExcluded(zombie, modData)
                and hasPendingReroll(modData) then
            clearPendingReroll(zombie, modData)
        end
    end)
end

local function queuePendingState(zombie, state)
    if RandomZeds.isExcluded(zombie) then return false end

    local modData = zombie:getModData()
    if not modData then return false end
    writePendingState(modData, state)
    return true
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
    state.multiplier = RandomZeds.requireSpeedMultiplier(
        state.multiplier, "zombie state multiplier") or 1.0
    state.baseSpeed = RandomZeds.readOptionalNumber(
        state.baseSpeed, "zombie state base speed")
    if state.baseSpeed and state.baseSpeed <= 0 then state.baseSpeed = nil end
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

local function repairSameStateSpeed(zombie, state, modData)
    RandomZeds.applyZombieSpeedType(
        zombie, state.speedType, state.multiplier, state.baseSpeed)
    if not RandomZeds.isZombieSpeedTypeApplied(
            zombie, state.speedType) then
        return false
    end

    clearPendingReroll(zombie, modData)
    if mode.queueServerState then mode.queueServerState(zombie, state) end
    pendingStandUps[zombie] = nil
    return true
end

local function writeAppliedZombieState(zombie, modData, state)
    zombie:setHealth(state.health)
    modData[PERIOD_TAG] = state.period
    modData[SPEED_TAG] = state.speedType
    modData[SPRINTER_MULTIPLIER_TAG] = state.multiplier
    if state.speedType == "sprinter" then
        modData[SPEED_BASE_SPEED_TAG] = nil
    else
        modData[SPRINTER_BASE_SPEED_TAG] = nil
    end
    modData[HEALTH_TAG] = state.health
    modData[SIGHT_TAG] = state.sight
    modData[HEARING_TAG] = state.hearing
    modData[COGNITION_TAG] = state.cognition
    modData[STRENGTH_TAG] = state.strength
    modData[MEMORY_TAG] = state.memory
    if mode.persistRerollRevision then mode.persistRerollRevision(modData) end
    clearPendingReroll(zombie, modData)
end

local function applyFreshZombieState(zombie, modData, state)
    if not RandomZeds.applyZombieProfile(zombie, state) then
        return false
    end
    writeAppliedZombieState(zombie, modData, state)
    return true
end

local function applySameZombieState(zombie, modData, state)
    local typeApplied = RandomZeds.isZombieSpeedTypeApplied(
        zombie, state.speedType)
    if typeApplied then
        local hadPendingState = hasPendingReroll(modData)
        if mode.applyAnimationSpeed then
            mode.applyAnimationSpeed(zombie, state.speedType, state.multiplier)
        end
        zombie:setHealth(state.health)
        clearPendingReroll(zombie, modData)
        if hadPendingState and mode.queueServerState then
            mode.queueServerState(zombie, state)
        end
        pendingStandUps[zombie] = nil
        return true
    end

    return repairSameStateSpeed(zombie, state, modData)
end

local function deferUnconfirmedZombieState(zombie, state)
    RandomZeds.debugLog(
        "Zombie speed type not confirmed; queuing retry",
        state.speedType
    )
    queuePendingState(zombie, state)
    queueStandUpRetry(zombie)
end

local function deferBlockedZombieStateIfNeeded(zombie, state)
    local gettingUp = zombie:getCurrentActionContextStateName() == "getup"
    local blockedByCrawling = state.speedType ~= "crawler"
            and zombie:isCrawling()
    if not gettingUp and not blockedByCrawling then return false end

    RandomZeds.debugLog(
        "Deferring zombie state",
        "type", state.speedType,
        "getting up", gettingUp,
        "blocked by crawling", blockedByCrawling
    )
    deferBlockedZombieState(zombie, state, gettingUp)
    return true
end

local function applyFreshZombieStateAndSync(zombie, modData, state)
    if not applyFreshZombieState(zombie, modData, state) then
        RandomZeds.debugLog("Zombie state application failed", state.speedType)
        return
    end
    if not RandomZeds.isZombieSpeedTypeApplied(zombie, state.speedType) then
        deferUnconfirmedZombieState(zombie, state)
        return
    end
    RandomZeds.debugLog(
        "Zombie state applied",
        "type", state.speedType,
        "period", state.period,
        "multiplier", state.multiplier
    )
    if mode.queueServerState then mode.queueServerState(zombie, state) end
    pendingStandUps[zombie] = nil
end

local function applyValidatedZombieState(zombie, state)
    if not zombie then return false end
    local modData = zombie:getModData()
    if not modData then return false end
    if deferBlockedZombieStateIfNeeded(zombie, state) then return end

    if isSameZombieState(modData, state) then
        if applySameZombieState(zombie, modData, state) then
            RandomZeds.debugLog("Zombie state already applied", state.speedType)
        else
            deferUnconfirmedZombieState(zombie, state)
        end
        return
    end

    applyFreshZombieStateAndSync(zombie, modData, state)
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

local function rollZombieState(config, period)
    local speedType = getRandomSpeedType(config)
    local state = {
        period = period,
        speedType = speedType,
        health = rollZombieHealth(config.health[speedType]),
        multiplier = rollSpeedMultiplier(config, speedType),
    }
    addRolledProfileState(state, config, speedType)
    RandomZeds.debugLog(
        "Rolled zombie state",
        "type", state.speedType,
        "period", state.period,
        "multiplier", state.multiplier
    )
    return state
end

local function queuePendingCrawlerState(zombie, state)
    if not queuePendingState(zombie, state) then return end
    pendingStandUps[zombie] = nil
    pendingCrawlerRerolls[zombie] = true
    pendingCrawlerRerollCheckRequired = true
end

local function rollZombieProfile(zombie, config, period)
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

    return rollZombieState(config, period)
end

local function applyNewZombieProfile(zombie, config, period)
    local state = rollZombieProfile(zombie, config, period)
    if state then applyValidatedZombieState(zombie, state) end
end

local function applyZombieProfileReroll(zombie, config, period)
    local state = rollZombieProfile(zombie, config, period)
    if not state then return end

    if state.speedType == "crawler" and protection.isCrawlerProtected(zombie) then
        queuePendingCrawlerState(zombie, state)
        return
    end
    applyValidatedZombieState(zombie, state)
end

local function queueCrawlerReroll(zombie, config, period)
    if RandomZeds.isExcluded(zombie) then return end

    queuePendingCrawlerState(zombie, rollZombieState(config, period))
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
        applyZombieProfileReroll(zombie)
        if modData[PENDING_PERIOD_TAG] == pendingPeriod then
            clearPendingReroll(zombie, modData)
        end
    else
        applyPendingZombieState(zombie, modData)
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
                    applyZombieProfileReroll(zombie, config, period)
                end
            end
        end
    end

    if mode.flushServerStates then mode.flushServerStates() end
end

local function reconcileZombies(period, config)
    reconcileCell(getCell(), period, config)
end

local function classifyPendingCrawlerReroll(zombie, modData, ready, changedPeriod)
    if pendingStandUps[zombie] then
        pendingCrawlerRerollCheckRequired = true
        return
    end

    if not zombie:getCurrentSquare() then
        pendingCrawlerRerollCheckRequired = true
        return
    end

    if protection.isCrawlerProtected(zombie) then
        pendingCrawlerRerollCheckRequired = true
    else
        if modData[PENDING_PERIOD_TAG] ~= lastEffectiveMode then
            changedPeriod[#changedPeriod + 1] = zombie
        else
            ready[#ready + 1] = zombie
        end
    end
end

local function processPendingRerollCandidate(zombie, ready, changedPeriod)
    local modData = zombie:getModData()
    if not modData or RandomZeds.isExcluded(zombie, modData)
            or zombie:isDead() or not modData[PENDING_SPEED_TAG] then
        pendingCrawlerRerolls[zombie] = nil
        return
    end

    classifyPendingCrawlerReroll(zombie, modData, ready, changedPeriod)
end

local function applyPendingCrawlerReroll(zombie)
    applyUnprotectedPendingReroll(zombie, zombie:getModData())
    if pendingCrawlerRerolls[zombie] then
        pendingCrawlerRerollCheckRequired = true
    end
end

local function applyPendingCrawlerRerollBatch(ready, changedPeriod)
    for index = 1, #changedPeriod do
        applyPendingCrawlerReroll(changedPeriod[index])
    end

    if #ready > 0 then
        if mode.advanceRerollRevision then mode.advanceRerollRevision() end
        for index = 1, #ready do
            applyPendingCrawlerReroll(ready[index])
        end
    end
    if mode.flushServerStates then mode.flushServerStates() end
end

local function applyPendingRerolls()
    if lastEffectiveMode == DISABLED_PERIOD then
        pendingCrawlerRerollCheckRequired = false
        pendingCrawlerRerolls = createPendingCrawlerRerolls()
        return
    end
    if not pendingCrawlerRerollCheckRequired then return end

    local ready = table.newarray()
    local changedPeriod = table.newarray()
    pendingCrawlerRerollCheckRequired = false
    for zombie in pairs(pendingCrawlerRerolls) do
        processPendingRerollCandidate(zombie, ready, changedPeriod)
    end
    applyPendingCrawlerRerollBatch(ready, changedPeriod)
end

local function processPendingZombieCreate(zombie, now)
    local expiresAt = pendingZombieCreates[zombie]
    local currentSquare = zombie:getCurrentSquare() ~= nil
    local expired = expiresAt and now >= expiresAt
    if zombie:isDead() or RandomZeds.isExcluded(zombie) then
        pendingZombieCreates[zombie] = nil
    elseif expired then
        pendingZombieCreates[zombie] = nil
    elseif currentSquare and zombie:getSquare() then
        applyNewZombieProfile(zombie, nil, nil)
        pendingZombieCreates[zombie] = nil
    end
end

local function processPendingZombieCreates()
    local visited = 0
    local getTimestamp = getTimestampMs
    local now = getTimestamp()
    local deadline = now + INITIAL_STATE_BUDGET_MS
    for zombie in pairs(pendingZombieCreates) do
        if visited > 0 and getTimestamp() >= deadline then break end
        visited = visited + 1
        processPendingZombieCreate(zombie, now)
    end
end

local function collectReadyPendingStandUp(zombie, pending, now, ready)
    local invalid = not zombie:getCurrentSquare() or zombie:isDead()
        or RandomZeds.isExcluded(zombie)
    local expired = pending.expiresAt and now >= pending.expiresAt
    if invalid or expired then
        pendingStandUps[zombie] = nil
        local modData = zombie:getModData()
        if expired and not invalid and modData then clearPendingReroll(zombie, modData) end
        return false
    end
    local modData = zombie:getModData()
    local pendingCrawler = modData and modData[PENDING_SPEED_TAG] == "crawler"
    local actionState = zombie:getCurrentActionContextStateName()
    if actionState == "getup" or (zombie:isCrawling() and not pendingCrawler) then return false end
    ready[#ready + 1] = zombie
    if pending.revisionAdvanced then return false end
    pending.revisionAdvanced = true
    return true
end

local function processPendingStandUps()
    local ready = table.newarray()
    local shouldAdvanceRevision = false
    local now = getTimestampMs()
    for zombie, pending in pairs(pendingStandUps) do
        if collectReadyPendingStandUp(zombie, pending, now, ready) then
            shouldAdvanceRevision = true
        end
    end

    if #ready == 0 then return end

    if shouldAdvanceRevision and mode.advanceRerollRevision then
        mode.advanceRerollRevision()
    end
    for index = 1, #ready do
        local zombie = ready[index]
        applyPendingZombieState(zombie, zombie:getModData())
    end
end

local function applyEffectiveProfile(period, config, signature)
    RandomZeds.debugLog(
        "Applying profile",
        "period", period,
        "enabled", config ~= nil
    )
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
    local changed = period ~= lastEffectiveMode
        or signature ~= lastEffectiveSignature
    if changed then
        applyEffectiveProfile(period, config, signature)
    end

    applyPendingRerolls()
end

local function onZombieCreate(zombie)
    RandomZeds.initializeZombieAnimationSpeed(zombie)
    if RandomZeds.isExcluded(zombie) then return end

    if lastEffectiveConfig and zombie:getSquare() then
        local modData = zombie:getModData()
        applyNewZombieProfile(zombie, lastEffectiveConfig, lastEffectiveMode)
        RandomZeds.debugLog(
            "Zombie created and profiled",
            "type", modData and modData[SPEED_TAG]
        )
        return
    end
    RandomZeds.debugLog("Zombie created without profile or square; queued")
    pendingZombieCreates[zombie] = getTimestampMs() + PENDING_STATE_TIMEOUT_MS
end

local function processPendingZombieWork()
    if lastEffectiveMode == DISABLED_PERIOD then return end
    if RandomZeds.hasPendingEntries(pendingZombieCreates) then
        processPendingZombieCreates()
    end
    if RandomZeds.hasPendingEntries(pendingStandUps) then
        processPendingStandUps()
    end
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
    if mode.processPendingServerStates then
        mode.processPendingServerStates()
    end
end

local function initialize()
    if initialized then return end

    Events.OnZombieCreate.Add(onZombieCreate)
    Events.OnCreatePlayer.Add(protection.onPlayerCreated)
    Events.OnPlayerMove.Add(protection.onPlayerMove)
    Events.OnWeatherPeriodStart.Add(updateEffectiveState)
    Events.OnWeatherPeriodStage.Add(updateEffectiveState)
    Events.OnWeatherPeriodComplete.Add(updateEffectiveState)
    Events.OnTick.Add(processScheduledZombieWork)
    Events.EveryOneMinute.Add(updateEffectiveState)
    Events.EveryOneMinute.Add(protection.refreshProtectedChunks)
    protection.refreshProtectedChunks()
    RandomZeds.forEachLoadedZombie(RandomZeds.initializeZombieAnimationSpeed)
    updateEffectiveState()
    initialized = true
end

mode.registerInitialization(initialize)
