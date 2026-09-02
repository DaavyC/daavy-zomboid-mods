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
local MAX_SPRINTER_REFRESHES_PER_CALL = 32
local SPRINTER_SPEED_TOLERANCE = 0.005
local EXCLUDED_TAG = "RandomZedsExcluded"
local NATIVE_OPTION_NAMES = table.newarray("Sight", "Hearing")
local DEBUG_OPTION_NAME = "RandomZedsMain.Debug"
local MIN_SPRINTER_MULTIPLIER = 0.5
local MAX_SPRINTER_MULTIPLIER = 1.5
local pendingSprinterAnimationRefreshes = setmetatable({}, { __mode = "k" })

local function hasPendingEntries(entries)
    for _ in pairs(entries) do
        return true
    end
    return false
end

local function clearSprinterAnimationRefresh(zombie)
    zombie:setVariable(SPRINTER_SPEED_REFRESH_VARIABLE, false)
    pendingSprinterAnimationRefreshes[zombie] = nil
end

local synapseApi
local synapseApiAvailable = false
RandomZeds.MIN_SPRINTER_MULTIPLIER = MIN_SPRINTER_MULTIPLIER
RandomZeds.MAX_SPRINTER_MULTIPLIER = MAX_SPRINTER_MULTIPLIER

function RandomZeds.requireNumber(numericInput, _description)
    local number = tonumber(numericInput)
    if number == nil then return nil end
    if number ~= number
            or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

function RandomZeds.requireInteger(numericInput, description)
    local number = RandomZeds.requireNumber(numericInput, description)
    if number == nil or number % 1 ~= 0 then return nil end
    return number
end

function RandomZeds.requireBoolean(booleanInput, _description)
    if booleanInput ~= true and booleanInput ~= false then return nil end
    return booleanInput
end

function RandomZeds.requireRange(numericInput, description, minimum, maximum)
    local number = RandomZeds.requireNumber(numericInput, description)
    if number == nil or number < minimum or number > maximum then return nil end
    return number
end

function RandomZeds.requireIntegerRange(numericInput, description, minimum, maximum)
    local number = RandomZeds.requireRange(numericInput, description, minimum, maximum)
    if number == nil or number % 1 ~= 0 then return nil end
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
    return speedTypeId
end

function RandomZeds.requireProfilePeriod(period)
    if period ~= "Day" and period ~= "Night"
            and period ~= "Weather" and period ~= "Disabled" then
        return nil
    end
    return period
end

function RandomZeds.isDayPeriod(timeOfDay, dayStart, nightStart)
    if dayStart < nightStart then
        return timeOfDay >= dayStart and timeOfDay < nightStart
    end
    return timeOfDay >= dayStart or timeOfDay < nightStart
end

function RandomZeds.isExcluded(zombie)
    if not zombie then return false end
    local modData = zombie:getModData()
    if not modData then return false end
    local excluded = modData[EXCLUDED_TAG]
    if excluded == nil then return false end
    return excluded
end

function RandomZeds.isDebugEnabled()
    local options = getSandboxOptions and getSandboxOptions()
    local option = options and options:getOptionByName(DEBUG_OPTION_NAME)
    return option and option:getValue() == true
end

function RandomZeds.debug(message)
    if RandomZeds.isDebugEnabled() then
        print("[Random Zeds] " .. tostring(message))
    end
end

function RandomZeds.forceVanillaPerceptionDefaults()
    RandomZeds.debug("Restoring vanilla perception defaults")
    local options = getSandboxOptions and getSandboxOptions()
    if not options then return false end
    local sight = options:getOptionByName("ZombieLore.Sight")
    local hearing = options:getOptionByName("ZombieLore.Hearing")
    if sight then sight:setValue(2) end
    if hearing then hearing:setValue(2) end
    return sight ~= nil and hearing ~= nil
end

local function restoreNativeOptionValues(nativeOptions, previousNativeValues)
    for index = 1, #nativeOptions do
        local option = nativeOptions[index]
        option:setValue(previousNativeValues[index])
    end
end

function RandomZeds.applyZombieNativeStats(zombie, sight, hearing)
    local nativeStatValues = {
        RandomZeds.requireIntegerRange(sight, "zombie sight", 1, 3),
        RandomZeds.requireIntegerRange(hearing, "zombie hearing", 1, 3),
    }
    if not nativeStatValues[1] and not nativeStatValues[2] then
        RandomZeds.debug("Native stats skipped: no values")
        return false
    end
    if not zombie then return false end
    if nativeStatValues[1] == 2 and nativeStatValues[2] == 2 then
        return true
    end
    local options = getSandboxOptions and getSandboxOptions()
    if not options then return false end

    local nativeOptions = {}
    local previousNativeValues = {}
    for index = 1, #NATIVE_OPTION_NAMES do
        local name = NATIVE_OPTION_NAMES[index]
        local option = options:getOptionByName("ZombieLore." .. name)
        if not option then
            RandomZeds.debug("Native stats failed: option missing " .. name)
            return false
        end
        nativeOptions[index] = option
        previousNativeValues[index] = option:getValue()
    end

    for index = 1, #nativeOptions do
        local option = nativeOptions[index]
        if nativeStatValues[index] ~= nil then
            option:setValue(nativeStatValues[index])
        end
    end
    zombie:DoZombieStats()
    restoreNativeOptionValues(nativeOptions, previousNativeValues)
    return true
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
    if not api or type(api.getApiVersion) ~= "function"
            or type(api.applyZombieState) ~= "function" then
        return nil
    end
    if api.getApiVersion() ~= 1 then return nil end
    synapseApi = api
    synapseApiAvailable = true
    return api
end

function RandomZeds.hasSynapseFeatureSupport()
    return getSynapseApi() ~= nil
end

function RandomZeds.dispatchZombieState(zombie, zombieState)
    if not RandomZeds.hasSynapseFeatureSupport() then return false end
    return RandomZeds.applySynapseZombieState(zombie, zombieState)
end

function RandomZeds.applyZombieFeatures(
        zombie, cognitionProfile, strengthProfile, memoryProfile)
    if not zombie then return false end
    local api = getSynapseApi()
    if not api or type(api.applyZombieFeatures) ~= "function" then return false end

    local cognition = RandomZeds.requireIntegerRange(
        cognitionProfile, "cognition profile", 1, 3)
    local strength = RandomZeds.requireIntegerRange(
        strengthProfile, "strength profile", 1, 3)
    local memory = RandomZeds.requireIntegerRange(
        memoryProfile, "memory profile", 1, 4)
    if not cognition or not strength or not memory then return false end
    api.applyZombieFeatures(
        zombie,
        cognition,
        strength,
        memory
    )
    return true
end

local function getSprinterBaseSpeed(zombie, providedBaseSpeed)
    if not zombie then return nil end
    local modData = zombie:getModData()
    if not modData then return nil end
    local baseSpeed = providedBaseSpeed
    if baseSpeed == nil then
        baseSpeed = modData[SPRINTER_BASE_SPEED_TAG]
    end
    if baseSpeed == nil then
        baseSpeed = RandomZeds.requireNumber(
            zombie:getSpeedMod(), "sprinter base speed")
        if not baseSpeed then return nil end
        if zombie.isRemoteZombie and zombie:isRemoteZombie() and baseSpeed >= 10 then
            baseSpeed = baseSpeed / 1000
        end
    else
        baseSpeed = RandomZeds.requireNumber(baseSpeed, "sprinter base speed")
    end
    if not baseSpeed or baseSpeed <= 0 then return nil end
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
        if not baseSpeed then return nil end
        zombieState.baseSpeed = baseSpeed
        synapseState.speedMod = baseSpeed * zombieState.multiplier
        synapseState.animationVariable = SPRINTER_SPEED_SCALE_VARIABLE
        synapseState.animationSpeedScale = 0.8 * zombieState.multiplier
    end
    return synapseState
end

function RandomZeds.applySynapseZombieState(zombie, zombieState)
    if not zombie or type(zombieState) ~= "table" then return false end
    local api = getSynapseApi()
    if not api then return false end
    if not RandomZeds.requireSpeedTypeId(zombieState.speedType) then return false end
    if not RandomZeds.requireSprinterMultiplier(
        zombieState.multiplier, "zombie state multiplier")
    then return false end
    if not RandomZeds.requireRange(
        zombieState.health, "zombie state health", 0.5, 3.8)
    then return false end
    if not RandomZeds.requireIntegerRange(
        zombieState.sight, "zombie state sight", 1, 3)
    then return false end
    if not RandomZeds.requireIntegerRange(
        zombieState.hearing, "zombie state hearing", 1, 3)
    then return false end
    if not RandomZeds.validateOptionalFeatureState(zombieState, "Zombie state") then
        return false
    end
    local state = makeSynapseZombieState(zombie, zombieState)
    if not state then return false end
    api.applyZombieState(zombie, state)
    return true
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
    if state == nil then return true end
    if type(state) ~= "table" then
        return false
    end
    if not RandomZeds.hasFeatureState(state) then
        if RandomZeds.hasPartialFeatureState(state) then
            return false
        end
        return true
    end
    state.cognition = RandomZeds.requireIntegerRange(
        state.cognition, description .. " cognition", 1, 3)
    state.strength = RandomZeds.requireIntegerRange(
        state.strength, description .. " strength", 1, 3)
    state.memory = RandomZeds.requireIntegerRange(
        state.memory, description .. " memory", 1, 4)
    return state.cognition ~= nil and state.strength ~= nil
        and state.memory ~= nil
end

function RandomZeds.applyZombieFeatureState(zombie, state)
    if not zombie then return false end
    if not RandomZeds.validateOptionalFeatureState(state, "Zombie feature state") then
        return false
    end
    if not RandomZeds.hasFeatureState(state) then
        return true
    end
    if not RandomZeds.hasSynapseFeatureSupport() then return false end
    return RandomZeds.applyZombieFeatures(
        zombie, state.cognition, state.strength, state.memory)
end

function RandomZeds.applySprinterAnimationSpeed(zombie, multiplier)
    if not zombie then return false end
    multiplier = RandomZeds.requireSprinterMultiplier(
        multiplier, "sprinter speed multiplier")
    if not multiplier then return false end
    local speedScale = 0.8 * multiplier
    local api = getSynapseApi()
    if api and type(api.applyAnimationSpeed) == "function" then
        api.applyAnimationSpeed(
            zombie, SPRINTER_SPEED_SCALE_VARIABLE, speedScale)
        clearSprinterAnimationRefresh(zombie)
        return true
    end
    local currentSpeedScale = zombie:getVariableFloat(
        SPRINTER_SPEED_SCALE_VARIABLE, 0.0)
    if math.abs(currentSpeedScale - speedScale)
            <= SPRINTER_SPEED_TOLERANCE then
        return true
    end
    zombie:setVariable(SPRINTER_SPEED_SCALE_VARIABLE, speedScale)
    zombie:setVariable(SPRINTER_SPEED_REFRESH_VARIABLE, true)
    pendingSprinterAnimationRefreshes[zombie] = getTimestampMs()
        + SPRINTER_ANIMATION_REFRESH_DURATION_MS
    return true
end

function RandomZeds.refreshSprinterAnimationSpeeds()
    if not hasPendingEntries(pendingSprinterAnimationRefreshes) then return end

    local now = getTimestampMs()
    local processed = 0
    for zombie, refreshAt in pairs(pendingSprinterAnimationRefreshes) do
        local refreshDeadline = tonumber(refreshAt)
        if not refreshDeadline or zombie:isDead()
                or not zombie:getCurrentSquare() then
            pendingSprinterAnimationRefreshes[zombie] = nil
        elseif now >= refreshDeadline then
            zombie:setVariable(SPRINTER_SPEED_REFRESH_VARIABLE, false)
            pendingSprinterAnimationRefreshes[zombie] = nil
        end
        processed = processed + 1
        if processed >= MAX_SPRINTER_REFRESHES_PER_CALL then break end
    end
end

function RandomZeds.forEachLoadedZombie(callback)
    local cell = getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then return 0 end

    local zombieCount = zombies:size()
    for zombieIndex = 0, zombieCount - 1 do
        callback(zombies:get(zombieIndex))
    end
    return zombieCount
end

function RandomZeds.forEachLoadedZombieWithinBudget(cursorState, budgetMs, callback)
    if not cursorState then return 0 end
    local cell = getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then
        cursorState.index = 0
        return 0
    end

    local count = zombies:size()
    if count <= 0 then
        cursorState.index = 0
        return 0
    end

    local index = tonumber(cursorState.index) or 0
    if index % 1 ~= 0 or index < 0 then index = 0 end
    if index >= count then index = 0 end
    local getTimestamp = getTimestampMs
    local startedAt = getTimestamp()
    local budget = tonumber(budgetMs) or 1
    if budget <= 0 then budget = 1 end
    local processed = 0
    local currentTime = startedAt
    repeat
        callback(zombies:get(index), currentTime)
        processed = processed + 1
        index = index + 1
        if index >= count then index = 0 end
        if processed >= count then break end
        currentTime = getTimestamp()
    until currentTime - startedAt >= budget

    cursorState.index = index
    return processed
end

local function getVariableBoolean(zombie, name)
    return zombie:getVariableBoolean(name) == true
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
    local baseSpeed = tonumber(modData[SPRINTER_BASE_SPEED_TAG])
    local multiplier = tonumber(modData[SPRINTER_MULTIPLIER_TAG])
    local speedMod = tonumber(zombie:getSpeedMod())
    if not baseSpeed or not multiplier or not speedMod then return false end
    local expectedSpeed = baseSpeed * multiplier
    local nativeSpeedMatches = math.abs(speedMod - expectedSpeed)
        <= SPRINTER_SPEED_TOLERANCE
    if not nativeSpeedMatches then return false end

    local walkType = tostring(zombie:getWalkType() or "")
    if walkType:sub(1, 6) ~= "sprint" then return false end
    return true
end

function RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
    local speedTypeId = SPEED_TYPE_IDS[speedType]
    if not speedTypeId or not zombie or zombie:isDead()
            or not zombie:getCurrentSquare() then return false end

    local modData = zombie:getModData()
    if not modData then return false end
    if speedType == "sprinter" and modData[SPEED_TAG] ~= "sprinter" then
        return false
    end

    local applied = hasExpectedNativeSpeedType(zombie, speedType, speedTypeId)
    if applied and speedType == "sprinter" then
        applied = hasExpectedSprinterSpeed(zombie, modData)
    end

    return applied
end

function RandomZeds.applySprinterSpeed(zombie, multiplier)
    if not zombie then return false end
    multiplier = RandomZeds.requireSprinterMultiplier(
        multiplier, "sprinter speed multiplier") or 1.0
    local modData = zombie:getModData()
    if not modData then return false end
    local baseSpeed = getSprinterBaseSpeed(zombie)
    if not baseSpeed then
        baseSpeed = tonumber(zombie:getSpeedMod()) or 1.0
        if baseSpeed <= 0 then baseSpeed = 1.0 end
    end
    local expectedSpeed = baseSpeed * multiplier
    local nativeTypeValid = zombie:getSpeedType() == SPEED_TYPE_IDS.sprinter
        and not zombie:isCrawling()
        and zombie:isCanWalk()
        and tostring(zombie:getWalkType() or ""):sub(1, 6) == "sprint"
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
    return true
end

function RandomZeds.setCrawlerState(zombie, crawling)
    if not zombie or (crawling ~= true and crawling ~= false) then return false end
    if zombie:isCrawling() ~= crawling then
        zombie:toggleCrawling()
    end
    zombie:setCanWalk(not crawling)
    if not crawling then
        zombie:setOnFloor(false)
        zombie:setFallOnFront(false)
    end
    return true
end

function RandomZeds.applyZombieSpeedType(zombie, speedType, multiplier)
    if not zombie or not SPEED_TYPE_IDS[speedType] then return false end

    if speedType ~= "sprinter" then
        clearSprinterAnimationRefresh(zombie)
    end
    if speedType == "crawler" then
        RandomZeds.setCrawlerState(zombie, true)
        zombie:doCrawlerSpeed(3)
        return true
    end

    RandomZeds.setCrawlerState(zombie, false)
    if speedType == "sprinter" then
        return RandomZeds.applySprinterSpeed(zombie, multiplier)
    elseif speedType == "fastShambler" then
        zombie:doFastShambler()
    else
        zombie:doShambler()
    end
    return true
end

return RandomZeds
