local RandomZeds = {}
local print = print
local DEBUG_SANDBOX_SECTION = "RandomZedsMain"
local SPEED_TYPE_IDS = {
    sprinter = 1,
    fastShambler = 2,
    shambler = 3,
    crawler = 3,
}
RandomZeds.SPEED_TYPES = table.newarray(
    "sprinter", "fastShambler", "shambler", "crawler"
)
local SPEED_TAG = "RandomZedsSpeedType"
local EXCLUDED_TAG = "RandomZedsExcluded"
local MIN_SPRINTER_MULTIPLIER = 0.5
local MAX_SPRINTER_MULTIPLIER = 1.5
local function hasPendingEntries(entries)
    for _ in pairs(entries) do
        return true
    end
    return false
end
RandomZeds.SPEED_TYPE_IDS = SPEED_TYPE_IDS
RandomZeds.SPEED_TAG = SPEED_TAG
RandomZeds.MIN_SPRINTER_MULTIPLIER = MIN_SPRINTER_MULTIPLIER
RandomZeds.MAX_SPRINTER_MULTIPLIER = MAX_SPRINTER_MULTIPLIER
RandomZeds.hasPendingEntries = hasPendingEntries

function RandomZeds.isDebugEnabled()
    local settings = SandboxVars and SandboxVars[DEBUG_SANDBOX_SECTION]
    return settings ~= nil and settings.Debug == true
end

function RandomZeds.debugLog(...)
    if not RandomZeds.isDebugEnabled() then return end
    print("[RandomZeds][Debug]", ...)
end

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

function RandomZeds.isExcluded(zombie, modData)
    if not zombie then return false end
    modData = modData or zombie:getModData()
    if not modData then return false end
    local excluded = modData[EXCLUDED_TAG]
    if excluded == nil then return false end
    return excluded
end

function RandomZeds.isValidOnlineID(onlineID)
    onlineID = tonumber(onlineID)
    return onlineID ~= nil and onlineID ~= -1
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

local SPEED_TYPE_IDS = RandomZeds.SPEED_TYPE_IDS
local SPEED_TAG = RandomZeds.SPEED_TAG
local SPRINTER_MULTIPLIER_TAG = "RandomZedsSprinterMultiplier"
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local SPRINTER_SPEED_SCALE_VARIABLE = "RandomZedsSprinterSpeedScale"
local SPRINTER_SPEED_REFRESH_VARIABLE = "RandomZedsSprinterSpeedRefresh"
local SPRINTER_ANIMATION_REFRESH_DURATION_MS = 500
local MAX_SPRINTER_REFRESHES_PER_CALL = 32
local SPRINTER_SPEED_TOLERANCE = 0.005
local NATIVE_OPTION_NAMES = table.newarray("Sight", "Hearing")
local pendingSprinterAnimationRefreshes = setmetatable({}, { __mode = "k" })
local synapseApi
local synapseApiAvailable = false

local function getSynapseApi()
    if synapseApiAvailable then return synapseApi end
    local apiRoot = _G.Synapse and _G.Synapse.API
    local api = apiRoot and (apiRoot.RandomZeds or apiRoot)
    if not apiRoot or type(apiRoot.getApiVersion) ~= "function"
            or not api or type(api.applyZombieFeatures) ~= "function"
            or type(api.applyZombieSenses) ~= "function" then return nil end
    if apiRoot.getApiVersion() ~= 2 then return nil end
    synapseApi = api
    synapseApiAvailable = true
    return api
end

local function clearSprinterAnimationRefresh(zombie)
    zombie:setVariable(SPRINTER_SPEED_REFRESH_VARIABLE, false)
    pendingSprinterAnimationRefreshes[zombie] = nil
end

function RandomZeds.forceVanillaPerceptionDefaults()
    local options = getSandboxOptions and getSandboxOptions()
    if not options then return false end
    local sight = options:getOptionByName("ZombieLore.Sight")
    local hearing = options:getOptionByName("ZombieLore.Hearing")
    if sight then sight:setValue(2) end
    if hearing then hearing:setValue(2) end
    return sight ~= nil and hearing ~= nil
end

function RandomZeds.applyZombieNativeStats(zombie, sight, hearing)
    local nativeStatValues = table.newarray(
        RandomZeds.requireIntegerRange(sight, "zombie sight", 1, 3),
        RandomZeds.requireIntegerRange(hearing, "zombie hearing", 1, 3)
    )
    if not nativeStatValues[1] and not nativeStatValues[2] then
        return false
    end
    if not zombie then return false end
    local api = getSynapseApi()
    if api and nativeStatValues[1] and nativeStatValues[2] then
        api.applyZombieSenses(zombie, nativeStatValues[1], nativeStatValues[2])
        return true
    end
    if nativeStatValues[1] == 2 and nativeStatValues[2] == 2 then
        return true
    end
    local options = getSandboxOptions and getSandboxOptions()
    if not options then return false end

    local nativeOptions = table.newarray()
    local previousNativeValues = table.newarray()
    for index = 1, #NATIVE_OPTION_NAMES do
        local name = NATIVE_OPTION_NAMES[index]
        local option = options:getOptionByName("ZombieLore." .. name)
        if not option then
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
    for index = 1, #nativeOptions do
        local option = nativeOptions[index]
        option:setValue(previousNativeValues[index])
    end
    return true
end

function RandomZeds.hasSynapseFeatureSupport()
    return getSynapseApi() ~= nil
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

local function getSprinterBaseSpeed(zombie, modData)
    if not zombie then return nil end
    modData = modData or zombie:getModData()
    if not modData then return nil end
    local baseSpeed = modData[SPRINTER_BASE_SPEED_TAG]
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

function RandomZeds.applyZombieFeatureState(zombie, state)
    if not zombie then return false end
    if not RandomZeds.validateOptionalFeatureState(state, "Zombie feature state") then
        return false
    end
    if not RandomZeds.hasFeatureState(state) then
        return true
    end
    return RandomZeds.applyZombieFeatures(
        zombie, state.cognition, state.strength, state.memory)
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
        or (isMultiplayer() and getVariableBoolean(zombie, "bMovingNetwork"))
        or zombie:isMoving()
end

local function getSprinterMotionState(zombie)
    if not zombie or zombie:isDead() or zombie:isCrawling()
            or zombie:getCurrentActionContextStateName() == "getup" then
        return false, false, false
    end

    local target = zombie:getTarget()
    local moving = getVariableBoolean(zombie, "bMoving")
    local movementIntent = target ~= nil or hasSprinterMovementIntent(zombie)
    return target ~= nil or moving or movementIntent, movementIntent, moving
end

function RandomZeds.isSprinterMotionExpected(zombie)
    local expected = getSprinterMotionState(zombie)
    return expected
end

function RandomZeds.isRemoteSprinterSpeedScaled(zombie, expectedSpeed)
    if not isMultiplayer() or not zombie or not zombie.isRemoteZombie
            or not zombie:isRemoteZombie() then
        return false
    end

    expectedSpeed = tonumber(expectedSpeed)
    local speedMod = tonumber(zombie:getSpeedMod())
    if not expectedSpeed or not speedMod then return false end
    return speedMod >= 10
        and math.abs(speedMod / 1000 - expectedSpeed)
            <= SPRINTER_SPEED_TOLERANCE
end

function RandomZeds.repairRemoteSprinterType(zombie)
    if not isMultiplayer() or not zombie or not zombie.isRemoteZombie
            or not zombie:isRemoteZombie() then
        return false
    end
    local walkType = tostring(zombie:getWalkType() or "")
    local changed = false
    if walkType:sub(1, 6) ~= "sprint" then
        zombie:setWalkType("sprint")
        changed = true
    end
    if zombie:getSpeedType() ~= SPEED_TYPE_IDS.sprinter then
        zombie:setSpeedTypeFromWalkType()
        changed = true
    end
    if not zombie:isCanWalk() then
        zombie:setCanWalk(true)
        changed = true
    end
    return changed
end

local function reconcileOfflineSprinterMotion(zombie)
    if not RandomZeds.isSprinterMotionExpected(zombie) then return end
    if not zombie:isRunning() then zombie:setRunning(true) end
    local movementIntent = zombie:getTarget() ~= nil
        or hasSprinterMovementIntent(zombie)
    if not getVariableBoolean(zombie, "bMoving") and movementIntent then
        zombie:setVariable("bMoving", true)
    end
end

local function reconcileOnlineSprinterMotion(zombie)
    local expected, movementIntent, moving = getSprinterMotionState(zombie)
    if not expected then return end
    if not zombie:isRunning() then zombie:setRunning(true) end
    if not moving and movementIntent then
        zombie:setVariable("bMoving", true)
    end
end

function RandomZeds.reconcileSprinterMotion(zombie)
    if isMultiplayer() then
        reconcileOnlineSprinterMotion(zombie)
        return
    end
    reconcileOfflineSprinterMotion(zombie)
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
    local remoteSpeedIsScaled = isMultiplayer()
        and RandomZeds.isRemoteSprinterSpeedScaled(zombie, expectedSpeed)
    if not nativeSpeedMatches and not remoteSpeedIsScaled then return false end

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

function RandomZeds.applySprinterAnimationSpeed(zombie, multiplier)
    if not zombie then return false end
    local validMultiplier = RandomZeds.requireSprinterMultiplier(
        multiplier, "sprinter speed multiplier")
    if not validMultiplier and not isMultiplayer() then return false end
    multiplier = validMultiplier or 1.0
    local speedScale = 0.8 * multiplier
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

function RandomZeds.applySprinterSpeed(zombie, multiplier)
    if not zombie then return false end
    multiplier = RandomZeds.requireSprinterMultiplier(
        multiplier, "sprinter speed multiplier") or 1.0
    local modData = zombie:getModData()
    if not modData then return false end
    local baseSpeed = getSprinterBaseSpeed(zombie, modData)
    if not baseSpeed then
        baseSpeed = tonumber(zombie:getSpeedMod()) or 1.0
        if baseSpeed <= 0 then baseSpeed = 1.0 end
    end
    local expectedSpeed = baseSpeed * multiplier
    local remote = isMultiplayer()
        and zombie.isRemoteZombie and zombie:isRemoteZombie()
    local nativeTypeValid = zombie:getSpeedType() == SPEED_TYPE_IDS.sprinter
        and not zombie:isCrawling()
        and zombie:isCanWalk()
        and tostring(zombie:getWalkType() or ""):sub(1, 6) == "sprint"
    if remote then
        RandomZeds.repairRemoteSprinterType(zombie)
    elseif not nativeTypeValid then
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
    RandomZeds.debugLog(
        "Sprinter speed applied",
        "multiplier", multiplier,
        "base speed", baseSpeed,
        "expected speed", expectedSpeed,
        "native type valid before repair", nativeTypeValid,
        "remote", remote
    )
    if RandomZeds.isDebugEnabled() then
        RandomZeds.debugLog(
            "Sprinter result",
            "speed type", zombie:getSpeedType(),
            "speed mod", zombie:getSpeedMod(),
            "walk type", zombie:getWalkType(),
            "crawling", zombie:isCrawling(),
            "can walk", zombie:isCanWalk()
        )
    end
    return true
end

function RandomZeds.refreshSprinterAnimationSpeeds()
    if not RandomZeds.hasPendingEntries(pendingSprinterAnimationRefreshes) then return end

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

function RandomZeds.setCrawlerState(zombie, crawling)
    if not zombie or (crawling ~= true and crawling ~= false) then return false end
    if zombie:isCrawling() ~= crawling then
        zombie:toggleCrawling()
    end
    zombie:setCanWalk(not crawling)
    if crawling then
        if isMultiplayer() then zombie:setOnFloor(true) end
    else
        zombie:setOnFloor(false)
        zombie:setFallOnFront(false)
    end
    return true
end

function RandomZeds.applyZombieSpeedType(zombie, speedType, multiplier)
    if not zombie or not SPEED_TYPE_IDS[speedType] then return false end

    RandomZeds.debugLog(
        "Applying zombie speed type",
        "type", speedType,
        "multiplier", multiplier
    )

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
    end
    if speedType == "fastShambler" then
        zombie:doFastShambler()
    else
        zombie:doShambler()
    end
    return true
end

return RandomZeds
