local RandomZeds = {}

local SPEED_TYPE_IDS = {
    sprinter = 1,
    fastShambler = 2,
    shambler = 3,
    crawler = 3,
}
RandomZeds.SPEED_TYPES = { "sprinter", "fastShambler", "shambler", "crawler" }
local SPEED_TAG = "RandomZedsSpeedType"
local SPRINTER_MULTIPLIER_TAG = "RandomZedsSprinterMultiplier"
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local SPRINTER_SPEED_SCALE_VARIABLE = "RandomZedsSprinterSpeedScale"
local SPRINTER_SPEED_REFRESH_VARIABLE = "RandomZedsSprinterSpeedRefresh"
local SPRINTER_ANIMATION_REFRESH_DURATION_MS = 500
local SPRINTER_SPEED_TOLERANCE = 0.005
local EXCLUDED_TAG = "RandomZedsExcluded"
local NATIVE_OPTION_NAMES = { "Sight", "Hearing" }
local DEBUG_OPTION_NAME = "RandomZedsMain.Debug"
local MIN_SPRINTER_MULTIPLIER = 0.5
local MAX_SPRINTER_MULTIPLIER = 1.5
local pendingSprinterAnimationRefreshes = setmetatable({}, { __mode = "k" })
local synapseApi
local synapseApiAvailable = false
RandomZeds.MIN_SPRINTER_MULTIPLIER = MIN_SPRINTER_MULTIPLIER
RandomZeds.MAX_SPRINTER_MULTIPLIER = MAX_SPRINTER_MULTIPLIER

function RandomZeds.requireNumber(numericInput, description)
    if type(numericInput) ~= "number" then
        error("Invalid numeric value for " .. description)
    end
    local number = numericInput
    if number ~= number
            or number == math.huge or number == -math.huge then
        error("Invalid numeric value for " .. description)
    end
    return number
end

function RandomZeds.requireInteger(numericInput, description)
    local number = RandomZeds.requireNumber(numericInput, description)
    if number % 1 ~= 0 then
        error("Numeric value must be an integer for " .. description)
    end
    return number
end

function RandomZeds.requireBoolean(booleanInput, description)
    if booleanInput ~= true and booleanInput ~= false then
        error("Invalid boolean value for " .. description)
    end
    return booleanInput
end

function RandomZeds.requireRange(numericInput, description, minimum, maximum)
    local number = RandomZeds.requireNumber(numericInput, description)
    if number < minimum or number > maximum then
        error("Numeric value out of range for " .. description)
    end
    return number
end

function RandomZeds.requireIntegerRange(numericInput, description, minimum, maximum)
    local number = RandomZeds.requireRange(numericInput, description, minimum, maximum)
    if number % 1 ~= 0 then
        error("Numeric value must be an integer for " .. description)
    end
    return number
end

function RandomZeds.requireSprinterMultiplier(numericInput, description)
    return RandomZeds.requireRange(
        numericInput,
        description,
        MIN_SPRINTER_MULTIPLIER,
        MAX_SPRINTER_MULTIPLIER
    )
end

function RandomZeds.readOptionalNumber(storedInput, description)
    if storedInput == nil then return nil end
    return RandomZeds.requireNumber(storedInput, description)
end

function RandomZeds.readOptionalInteger(storedInput, description)
    if storedInput == nil then return nil end
    return RandomZeds.requireInteger(storedInput, description)
end

function RandomZeds.readOptionalBoolean(storedInput, description)
    if storedInput == nil then return nil end
    return RandomZeds.requireBoolean(storedInput, description)
end

function RandomZeds.requireSpeedTypeId(speedType)
    local speedTypeId = SPEED_TYPE_IDS[speedType]
    if not speedTypeId then
        error("Unknown zombie speed type " .. tostring(speedType))
    end
    return speedTypeId
end

function RandomZeds.requireProfilePeriod(period)
    if period ~= "Day" and period ~= "Night"
            and period ~= "Weather" and period ~= "Disabled" then
        error("Unknown zombie profile period " .. tostring(period))
    end
    return period
end

function RandomZeds.isExcluded(zombie)
    if not zombie then error("Zombie is required") end
    local modData = zombie:getModData()
    if not modData then error("Zombie mod data is required") end
    local excluded = modData[EXCLUDED_TAG]
    if excluded == nil then return false end
    return RandomZeds.requireBoolean(excluded, "zombie exclusion flag")
end

function RandomZeds.isDebugEnabled()
    local option = getSandboxOptions():getOptionByName(DEBUG_OPTION_NAME)
    if not option then
        error("Missing sandbox option " .. DEBUG_OPTION_NAME)
    end
    return RandomZeds.requireBoolean(
        option:getValue(), "debug sandbox option")
end

function RandomZeds.debug(message)
    if RandomZeds.isDebugEnabled() then
        print("[Random Zeds] " .. tostring(message))
    end
end

function RandomZeds.forceVanillaPerceptionDefaults()
    RandomZeds.debug("Restoring vanilla perception defaults")
    local options = getSandboxOptions()
    local sight = options:getOptionByName("ZombieLore.Sight")
    local hearing = options:getOptionByName("ZombieLore.Hearing")
    if not sight then error("Missing sandbox option ZombieLore.Sight") end
    if not hearing then error("Missing sandbox option ZombieLore.Hearing") end
    sight:setValue(2)
    hearing:setValue(2)
end

local function restoreNativeOptionValues(nativeOptions, previousNativeValues)
    for index, option in ipairs(nativeOptions) do
        option:setValue(previousNativeValues[index])
    end
end

function RandomZeds.applyZombieNativeStats(zombie, sight, hearing)
    RandomZeds.debug("Applying native stats sight=" .. tostring(sight)
        .. " hearing=" .. tostring(hearing))
    local nativeStatValues = {
        RandomZeds.requireIntegerRange(sight, "zombie sight", 1, 3),
        RandomZeds.requireIntegerRange(hearing, "zombie hearing", 1, 3),
    }

    local options = getSandboxOptions()
    local nativeOptions = {}
    local previousNativeValues = {}
    for index, name in ipairs(NATIVE_OPTION_NAMES) do
        local option = options:getOptionByName("ZombieLore." .. name)
        if not option then
            error("Missing sandbox option ZombieLore." .. name)
        end
        nativeOptions[index] = option
        previousNativeValues[index] = option:getValue()
    end

    for index, option in ipairs(nativeOptions) do
        option:setValue(nativeStatValues[index])
    end
    zombie:DoZombieStats()
    restoreNativeOptionValues(nativeOptions, previousNativeValues)
    RandomZeds.debug("Native stats applied using DoZombieStats")
end

local function getSynapseApi()
    if synapseApiAvailable then
        return synapseApi
    end
    local synapse = _G.Synapse
    if not synapse then
        return nil
    end
    local api = synapse.API
    if not api then
        error("Synapse API namespace is unavailable")
    end
    if api.getApiVersion() ~= 1 then
        error("Unsupported Synapse API version")
    end
    if not api.applyZombieState then
        error("Synapse zombie state API is unavailable")
    end
    synapseApi = api
    synapseApiAvailable = true
    return api
end

function RandomZeds.hasSynapseFeatureSupport()
    return getSynapseApi() ~= nil
end

function RandomZeds.dispatchZombieState(zombie, zombieState)
    if not RandomZeds.hasSynapseFeatureSupport() then return false end
    RandomZeds.applySynapseZombieState(zombie, zombieState)
    return true
end

function RandomZeds.applyZombieFeatures(
        zombie, cognitionProfile, strengthProfile, memoryProfile)
    if not zombie then error("Zombie is required") end
    local api = getSynapseApi()
    if not api then error("Synapse API is unavailable") end

    local cognition = RandomZeds.requireIntegerRange(
        cognitionProfile, "cognition profile", 1, 3)
    local strength = RandomZeds.requireIntegerRange(
        strengthProfile, "strength profile", 1, 3)
    local memory = RandomZeds.requireIntegerRange(
        memoryProfile, "memory profile", 1, 4)
    api.applyZombieFeatures(
        zombie,
        cognition,
        strength,
        memory
    )
end

local function getSprinterBaseSpeed(zombie, providedBaseSpeed)
    if not zombie then error("Zombie is required") end
    local modData = zombie:getModData()
    if not modData then error("Zombie mod data is required") end
    local baseSpeed = providedBaseSpeed
    if baseSpeed == nil then
        baseSpeed = modData[SPRINTER_BASE_SPEED_TAG]
    end
    if baseSpeed == nil then
        baseSpeed = RandomZeds.requireNumber(
            zombie:getSpeedMod(), "sprinter base speed")
        if zombie:isRemoteZombie() and baseSpeed >= 10 then
            baseSpeed = baseSpeed / 1000
        end
    else
        baseSpeed = RandomZeds.requireNumber(baseSpeed, "sprinter base speed")
    end
    if baseSpeed <= 0 then error("Sprinter base speed must be positive") end
    return baseSpeed
end

local function makeSynapseZombieState(zombie, zombieState)
    local synapseState = {
        speedType = zombieState.speedType,
        health = zombieState.health,
        sight = zombieState.sight,
        hearing = zombieState.hearing,
    }
    if zombieState.cognition ~= nil then
        synapseState.cognition = zombieState.cognition
        synapseState.strength = zombieState.strength
        synapseState.memory = zombieState.memory
    end
    if zombieState.speedType == "sprinter" then
        local baseSpeed = getSprinterBaseSpeed(
            zombie, zombieState.baseSpeed)
        zombieState.baseSpeed = baseSpeed
        synapseState.speedMod = baseSpeed * zombieState.multiplier
        synapseState.animationVariable = SPRINTER_SPEED_SCALE_VARIABLE
        synapseState.animationSpeedScale = 0.8 * zombieState.multiplier
    end
    return synapseState
end

function RandomZeds.applySynapseZombieState(zombie, zombieState)
    if not zombie then error("Zombie is required") end
    if type(zombieState) ~= "table" then
        error("Zombie state must be a table")
    end
    local api = getSynapseApi()
    RandomZeds.requireSpeedTypeId(zombieState.speedType)
    RandomZeds.requireSprinterMultiplier(
        zombieState.multiplier, "zombie state multiplier")
    RandomZeds.requireRange(
        zombieState.health, "zombie state health", 0.5, 3.8)
    RandomZeds.requireIntegerRange(
        zombieState.sight, "zombie state sight", 1, 3)
    RandomZeds.requireIntegerRange(
        zombieState.hearing, "zombie state hearing", 1, 3)
    RandomZeds.validateOptionalFeatureState(zombieState, "Zombie state")
    api.applyZombieState(zombie, makeSynapseZombieState(zombie, zombieState))
end

function RandomZeds.hasFeatureState(state)
    return state ~= nil and state.cognition ~= nil
        and state.strength ~= nil and state.memory ~= nil
end

function RandomZeds.hasPartialFeatureState(state)
    return state ~= nil and (
        state.cognition ~= nil or state.strength ~= nil or state.memory ~= nil
    )
end

function RandomZeds.validateOptionalFeatureState(state, description)
    if state == nil then return end
    if type(state) ~= "table" then
        error(description .. " must be a table")
    end
    if not RandomZeds.hasFeatureState(state) then
        if RandomZeds.hasPartialFeatureState(state) then
            error(description .. " profiles are incomplete")
        end
        return
    end
    RandomZeds.requireIntegerRange(
        state.cognition, description .. " cognition", 1, 3)
    RandomZeds.requireIntegerRange(
        state.strength, description .. " strength", 1, 3)
    RandomZeds.requireIntegerRange(
        state.memory, description .. " memory", 1, 4)
end

function RandomZeds.applyZombieFeatureState(zombie, state)
    if not zombie then error("Zombie is required") end
    RandomZeds.validateOptionalFeatureState(state, "Zombie feature state")
    if not RandomZeds.hasFeatureState(state) then
        return
    end
    if not RandomZeds.hasSynapseFeatureSupport() then return end
    RandomZeds.applyZombieFeatures(
        zombie, state.cognition, state.strength, state.memory)
end

function RandomZeds.applySprinterAnimationSpeed(zombie, multiplier)
    if not zombie then error("Zombie is required") end
    multiplier = RandomZeds.requireSprinterMultiplier(
        multiplier, "sprinter speed multiplier")
    local speedScale = 0.8 * multiplier
    local api = getSynapseApi()
    if api then
        api.applyAnimationSpeed(
            zombie, SPRINTER_SPEED_SCALE_VARIABLE, speedScale)
        zombie:setVariable(SPRINTER_SPEED_REFRESH_VARIABLE, false)
        pendingSprinterAnimationRefreshes[zombie] = nil
        return
    end
    local currentSpeedScale = zombie:getVariableFloat(
        SPRINTER_SPEED_SCALE_VARIABLE, 0.0)
    if math.abs(currentSpeedScale - speedScale)
            <= SPRINTER_SPEED_TOLERANCE then
        return
    end
    zombie:setVariable(SPRINTER_SPEED_SCALE_VARIABLE, speedScale)
    zombie:setVariable(SPRINTER_SPEED_REFRESH_VARIABLE, true)
    pendingSprinterAnimationRefreshes[zombie] = getTimestampMs()
        + SPRINTER_ANIMATION_REFRESH_DURATION_MS
end

function RandomZeds.refreshSprinterAnimationSpeeds()
    local now = getTimestampMs()
    for zombie, refreshAt in pairs(pendingSprinterAnimationRefreshes) do
        local refreshDeadline = RandomZeds.requireNumber(
            refreshAt, "sprinter animation refresh deadline")
        if zombie:isDead() then
            pendingSprinterAnimationRefreshes[zombie] = nil
        elseif now >= refreshDeadline then
            zombie:setVariable(SPRINTER_SPEED_REFRESH_VARIABLE, false)
            pendingSprinterAnimationRefreshes[zombie] = nil
        end
    end
end

function RandomZeds.forEachLoadedZombie(callback)
    local cell = getCell()
    if not cell then error("Current cell is required") end
    local zombies = cell:getZombieList()

    for zombieIndex = 0, zombies:size() - 1 do
        callback(zombies:get(zombieIndex))
    end
end

function RandomZeds.forEachLoadedZombieWithinBudget(cursorState, budgetMs, callback)
    if not cursorState then error("Zombie iteration cursor is required") end
    local cell = getCell()
    if not cell then error("Current cell is required") end
    local zombies = cell:getZombieList()

    local count = zombies:size()
    if count <= 0 then
        cursorState.index = 0
        return 0
    end

    local index = RandomZeds.requireInteger(
        cursorState.index, "zombie iteration cursor")
    if index < 0 then
        error("Zombie iteration cursor is out of range")
    end
    if index >= count then index = 0 end
    local startedAt = getTimestampMs()
    local budget = RandomZeds.requireNumber(budgetMs, "zombie iteration budget")
    if budget <= 0 then error("Zombie iteration budget must be positive") end
    local processed = 0
    repeat
        callback(zombies:get(index))
        processed = processed + 1
        index = index + 1
        if index >= count then index = 0 end
    until processed >= count
        or (processed > 0 and getTimestampMs() - startedAt >= budget)

    cursorState.index = index
    return processed
end

local function getVariableBoolean(zombie, name)
    return RandomZeds.requireBoolean(
        zombie:getVariableBoolean(name),
        "zombie variable " .. name)
end

local function hasSprinterMovementIntent(zombie)
    return getVariableBoolean(zombie, "bPathfind")
        or zombie:isMoving()
end

function RandomZeds.isSprinterMotionExpected(zombie)
    if not zombie or zombie:isDead() or zombie:isCrawling()
            or zombie:getCurrentActionContextStateName() == "getup" then
        return false
    end

    return zombie:getTarget() ~= nil
        or getVariableBoolean(zombie, "bMoving")
        or hasSprinterMovementIntent(zombie)
end

function RandomZeds.reconcileSprinterMotion(zombie)
    if not RandomZeds.isSprinterMotionExpected(zombie) then
        return
    end

    if not zombie:isRunning() then
        zombie:setRunning(true)
    end
    local movementIntent = zombie:getTarget() ~= nil
        or hasSprinterMovementIntent(zombie)
    if not getVariableBoolean(zombie, "bMoving") and movementIntent then
        zombie:setVariable("bMoving", true)
    end
end

local function hasExpectedNativeSpeedType(zombie, speedType, speedTypeId)
    if speedType == "crawler" then
        return zombie:isCrawling()
            and not zombie:isCanWalk()
            and zombie:getSpeedType() == speedTypeId
    end
    return not zombie:isCrawling()
        and zombie:isCanWalk()
        and zombie:getSpeedType() == speedTypeId
end

local function hasExpectedSprinterSpeed(zombie, modData)
    local baseSpeed = RandomZeds.requireNumber(
        modData[SPRINTER_BASE_SPEED_TAG], "stored sprinter base speed")
    local multiplier = RandomZeds.requireNumber(
        modData[SPRINTER_MULTIPLIER_TAG], "stored sprinter multiplier")
    local speedMod = RandomZeds.requireNumber(
        zombie:getSpeedMod(), "sprinter speed")
    local expectedSpeed = baseSpeed * multiplier
    local nativeSpeedMatches = math.abs(speedMod - expectedSpeed)
        <= SPRINTER_SPEED_TOLERANCE
    if not nativeSpeedMatches then return false end

    local walkType = zombie:getWalkType()
    if not walkType then error("Zombie walk type is required") end
    if walkType:sub(1, 6) ~= "sprint" then return false end
    return true
end

function RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
    local speedTypeId = RandomZeds.requireSpeedTypeId(speedType)
    if not zombie or zombie:isDead() or not zombie:getSquare() then return false end

    local modData = zombie:getModData()
    if speedType == "sprinter" and modData[SPEED_TAG] ~= "sprinter" then
        return false
    end

    local applied = hasExpectedNativeSpeedType(zombie, speedType, speedTypeId)
    if applied and speedType == "sprinter" then
        applied = hasExpectedSprinterSpeed(zombie, modData)
    end

    RandomZeds.debug("Speed type check " .. tostring(speedType)
        .. " applied=" .. tostring(applied))
    return applied
end

function RandomZeds.applySprinterSpeed(zombie, multiplier)
    RandomZeds.debug("Applying sprinter speed multiplier=" .. tostring(multiplier))
    multiplier = RandomZeds.requireSprinterMultiplier(
        multiplier, "sprinter speed multiplier")
    local modData = zombie:getModData()
    local baseSpeed = getSprinterBaseSpeed(zombie)
    local expectedSpeed = baseSpeed * multiplier
    local nativeTypeValid = zombie:getSpeedType() == SPEED_TYPE_IDS.sprinter
        and not zombie:isCrawling()
        and zombie:isCanWalk()
        and zombie:getWalkType() ~= nil
        and zombie:getWalkType():sub(1, 6) == "sprint"
    if not nativeTypeValid then
        zombie:doSprinter()
    end
    zombie:setSpeedMod(expectedSpeed)
    RandomZeds.applySprinterAnimationSpeed(zombie, multiplier)
    if not zombie:isDead() then
        zombie:setRunning(true)
    end
    modData[SPEED_TAG] = "sprinter"
    modData[SPRINTER_MULTIPLIER_TAG] = multiplier
    modData[SPRINTER_BASE_SPEED_TAG] = baseSpeed
end

function RandomZeds.setCrawlerState(zombie, crawling)
    RandomZeds.debug("Setting crawler state crawling=" .. tostring(crawling))
    if crawling ~= true and crawling ~= false then
        error("Crawler state must be boolean")
    end
    if zombie:isCrawling() ~= crawling then
        zombie:toggleCrawling()
    end
    zombie:setCanWalk(not crawling)
    if not crawling then
        zombie:setOnFloor(false)
        zombie:setFallOnFront(false)
    end
end

function RandomZeds.applyZombieSpeedType(zombie, speedType, multiplier)
    RandomZeds.debug("Applying speed type=" .. tostring(speedType) .. " multiplier=" .. tostring(multiplier))
    RandomZeds.requireSpeedTypeId(speedType)

    if speedType ~= "sprinter" then
        zombie:setVariable(SPRINTER_SPEED_REFRESH_VARIABLE, false)
        pendingSprinterAnimationRefreshes[zombie] = nil
    end
    if speedType == "crawler" then
        RandomZeds.setCrawlerState(zombie, true)
        zombie:doCrawlerSpeed(3)
        return
    end

    RandomZeds.setCrawlerState(zombie, false)
    if speedType == "sprinter" then
        RandomZeds.applySprinterSpeed(zombie, multiplier)
    elseif speedType == "fastShambler" then
        zombie:doFastShambler()
    else
        zombie:doShambler()
    end
end

return RandomZeds
