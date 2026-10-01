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
local MIN_SPEED_MULTIPLIER = 0.5
local MAX_SPEED_MULTIPLIER = 1.5
local SPEED_VARIATION_STEP = 0.1
local function hasPendingEntries(entries)
    for _ in pairs(entries) do
        return true
    end
    return false
end
RandomZeds.SPEED_TYPE_IDS = SPEED_TYPE_IDS
RandomZeds.SPEED_TAG = SPEED_TAG
RandomZeds.MIN_SPEED_MULTIPLIER = MIN_SPEED_MULTIPLIER
RandomZeds.MAX_SPEED_MULTIPLIER = MAX_SPEED_MULTIPLIER
RandomZeds.SPEED_VARIATION_STEP = SPEED_VARIATION_STEP
RandomZeds.MIN_SPRINTER_MULTIPLIER = MIN_SPEED_MULTIPLIER
RandomZeds.MAX_SPRINTER_MULTIPLIER = MAX_SPEED_MULTIPLIER
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

function RandomZeds.requireSpeedMultiplier(numericInput, description)
    return RandomZeds.requireRange(
        numericInput,
        description,
        MIN_SPEED_MULTIPLIER,
        MAX_SPEED_MULTIPLIER
    )
end

RandomZeds.requireSprinterMultiplier = RandomZeds.requireSpeedMultiplier

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
local SPEED_BASE_SPEED_TAG = "RandomZedsSpeedBaseSpeed"
local SPRINTER_SPEED_SCALE_VARIABLE = "RandomZedsSprinterSpeedScale"
local SPRINTER_SPEED_TOLERANCE = 0.005
local NATIVE_OPTION_NAMES = table.newarray("Sight", "Hearing")
local ANIMATION_SPEED_SCALES = {
    sprinter = table.newarray({
        { variable = SPRINTER_SPEED_SCALE_VARIABLE, base = 0.8 }
    }),
    fastShambler = table.newarray(
        { variable = "RandomZedsFastShamblerSpeedScale1", base = 0.92 },
        { variable = "RandomZedsFastShamblerSpeedScale2", base = 1.04 },
        { variable = "RandomZedsFastShamblerSpeedScale3", base = 0.8 },
        { variable = "RandomZedsFastShamblerSpeedScale4", base = 0.6 },
        { variable = "RandomZedsFastShamblerSpeedScale5", base = 0.92 },
        { variable = "RandomZedsLungeSpeedScale1", base = 0.64 },
        { variable = "RandomZedsLungeSpeedScale2", base = 0.8 }
    ),
    shambler = table.newarray(
        { variable = "RandomZedsShamblerSpeedScale1", base = 0.8 },
        { variable = "RandomZedsShamblerSpeedScale2", base = 0.64 },
        { variable = "RandomZedsShamblerSpeedScale3", base = 0.72 },
        { variable = "RandomZedsLungeSpeedScale1", base = 0.64 },
        { variable = "RandomZedsLungeSpeedScale2", base = 0.8 }
    ),
    crawler = table.newarray({
        { variable = "RandomZedsCrawlerSpeedScale", base = 0.64 }
    }),
}
local synapseApi
local synapseApiAvailable = false

local function deferRemoteClientSpeed(zombie, speedType, multiplier)
    if not isClient() or not zombie.isRemoteZombie
            or not zombie:isRemoteZombie() then return false end
    RandomZeds.applyZombieAnimationSpeed(zombie, speedType, multiplier)
    return true
end

function RandomZeds.initializeZombieAnimationSpeed(zombie)
    if zombie:getVariableBoolean("RandomZedsAnimationInitialized") then return end
    for speedIndex = 1, #RandomZeds.SPEED_TYPES do
        local scales = ANIMATION_SPEED_SCALES[RandomZeds.SPEED_TYPES[speedIndex]]
        for scaleIndex = 1, #scales do
            local scale = scales[scaleIndex]
            if zombie:getVariableFloat(scale.variable, 0.0) == 0.0 then
                zombie:setVariable(scale.variable, scale.base)
            end
        end
    end
    zombie:setVariable("RandomZedsAnimationInitialized", true)
end

function RandomZeds.applyZombieProfile(zombie, state)
    if deferRemoteClientSpeed(zombie, state.speedType, state.multiplier) then
        return false
    end
    RandomZeds.setCrawlerState(zombie, state.speedType == "crawler")
    RandomZeds.applyZombieNativeStats(zombie, state.sight, state.hearing)
    RandomZeds.applyZombieFeatureState(zombie, state)
    return RandomZeds.applyZombieSpeedType(
        zombie, state.speedType, state.multiplier, state.baseSpeed)
end

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

local function getSprinterBaseSpeed(zombie, modData, baseSpeedOverride)
    if not zombie then return nil end
    modData = modData or zombie:getModData()
    if not modData then return nil end
    local baseSpeed = baseSpeedOverride or modData[SPRINTER_BASE_SPEED_TAG]
        or modData[SPEED_BASE_SPEED_TAG]
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

function RandomZeds.isRemoteZombieSpeedScaled(zombie, expectedSpeed)
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

RandomZeds.isRemoteSprinterSpeedScaled = RandomZeds.isRemoteZombieSpeedScaled

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
        and RandomZeds.isRemoteZombieSpeedScaled(zombie, expectedSpeed)
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
    if modData[SPEED_TAG] ~= speedType then return false end

    local applied = hasExpectedNativeSpeedType(zombie, speedType, speedTypeId)
    if applied and speedType == "sprinter" then
        applied = hasExpectedSprinterSpeed(zombie, modData)
    elseif applied then
        local baseSpeed = tonumber(modData[SPEED_BASE_SPEED_TAG])
        local multiplier = tonumber(modData[SPRINTER_MULTIPLIER_TAG])
        local speedMod = tonumber(zombie:getSpeedMod())
        local expectedSpeed = baseSpeed and multiplier
            and baseSpeed * multiplier
        local nativeSpeedMatches = expectedSpeed and speedMod
            and math.abs(speedMod - expectedSpeed) <= SPRINTER_SPEED_TOLERANCE
        local remoteSpeedIsScaled = expectedSpeed
            and RandomZeds.isRemoteZombieSpeedScaled(zombie, expectedSpeed)
        applied = nativeSpeedMatches or remoteSpeedIsScaled
    end

    return applied
end

local function updateAnimationSpeedScales(zombie, animationScales, multiplier)
    for index = 1, #animationScales do
        local animationScale = animationScales[index]
        local speedScale = animationScale.base * multiplier
        local currentSpeedScale = zombie:getVariableFloat(
            animationScale.variable, 0.0)
        if math.abs(currentSpeedScale - speedScale)
                > SPRINTER_SPEED_TOLERANCE then
            zombie:setVariable(animationScale.variable, speedScale)
        end
    end
end

function RandomZeds.applyZombieAnimationSpeed(zombie, speedType, multiplier)
    if not zombie then return false end
    local animationScales = ANIMATION_SPEED_SCALES[speedType]
    if not animationScales then return false end
    local validMultiplier = RandomZeds.requireSpeedMultiplier(
        multiplier, speedType .. " speed multiplier")
    if not validMultiplier and not isMultiplayer() then return false end
    multiplier = validMultiplier or 1.0
    updateAnimationSpeedScales(zombie, animationScales, multiplier)
    return true
end

local function getZombieSpeedBaseSpeed(zombie, modData, baseSpeedOverride)
    local baseSpeed = RandomZeds.requireNumber(
        baseSpeedOverride, "zombie base speed")
    if not baseSpeed then
        baseSpeed = RandomZeds.requireNumber(
            modData[SPEED_BASE_SPEED_TAG], "stored zombie base speed")
    end
    if not baseSpeed then
        baseSpeed = RandomZeds.requireNumber(
            zombie:getSpeedMod(), "zombie base speed")
        if zombie.isRemoteZombie and zombie:isRemoteZombie()
                and baseSpeed and baseSpeed >= 10 then
            baseSpeed = baseSpeed / 1000
        end
    end
    if not baseSpeed or baseSpeed <= 0 then return nil end
    return baseSpeed
end

local function applyScaledZombieSpeed(
        zombie, modData, speedType, multiplier, baseSpeedOverride)
    if not modData then return false end
    multiplier = RandomZeds.requireSpeedMultiplier(
        multiplier, speedType .. " speed multiplier") or 1.0
    local baseSpeed = getZombieSpeedBaseSpeed(
        zombie, modData, baseSpeedOverride)
    if not baseSpeed then return false end

    zombie:setSpeedMod(baseSpeed * multiplier)
    if not RandomZeds.applyZombieAnimationSpeed(zombie, speedType, multiplier) then
        return false
    end
    modData[SPRINTER_MULTIPLIER_TAG] = multiplier
    modData[SPEED_BASE_SPEED_TAG] = baseSpeed
    return true
end

function RandomZeds.applySprinterSpeed(
        zombie, multiplier, baseSpeedOverride, modDataOverride)
    if not zombie then return false end
    if deferRemoteClientSpeed(zombie, "sprinter", multiplier) then return false end
    multiplier = RandomZeds.requireSpeedMultiplier(
        multiplier, "sprinter speed multiplier") or 1.0
    local modData = modDataOverride or zombie:getModData()
    if not modData then return false end
    local nativeTypeValid = zombie:getSpeedType() == SPEED_TYPE_IDS.sprinter
        and not zombie:isCrawling()
        and zombie:isCanWalk()
        and tostring(zombie:getWalkType() or ""):sub(1, 6) == "sprint"
    if not nativeTypeValid then
        RandomZeds.setCrawlerState(zombie, false)
        zombie:doSprinter()
    end
    local baseSpeed = getSprinterBaseSpeed(
        zombie, modData, baseSpeedOverride)
    if not baseSpeed then
        baseSpeed = tonumber(zombie:getSpeedMod()) or 1.0
        if baseSpeed <= 0 then baseSpeed = 1.0 end
    end
    local expectedSpeed = baseSpeed * multiplier
    zombie:setSpeedMod(expectedSpeed)
    RandomZeds.applyZombieAnimationSpeed(zombie, "sprinter", multiplier)
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
        "native type valid before application", nativeTypeValid
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

local function applyNativeZombieSpeedType(zombie, speedType)
    if speedType == "crawler" then
        RandomZeds.setCrawlerState(zombie, true)
        zombie:doCrawlerSpeed(3)
        return
    end

    RandomZeds.setCrawlerState(zombie, false)
    if speedType == "fastShambler" then
        zombie:doFastShambler()
    else
        zombie:doShambler()
    end
end

function RandomZeds.applyZombieSpeedType(
        zombie, speedType, multiplier, baseSpeedOverride)
    if not zombie or not SPEED_TYPE_IDS[speedType] then return false end
    if deferRemoteClientSpeed(zombie, speedType, multiplier) then return false end

    RandomZeds.debugLog(
        "Applying zombie speed type",
        "type", speedType,
        "multiplier", multiplier
    )

    local modData = zombie:getModData()
    if not modData then return false end
    if modData[SPEED_TAG] ~= speedType then
        modData[SPEED_BASE_SPEED_TAG] = nil
        modData[SPRINTER_BASE_SPEED_TAG] = nil
    end
    if speedType == "sprinter" then
        return RandomZeds.applySprinterSpeed(
            zombie, multiplier, baseSpeedOverride, modData)
    end

    applyNativeZombieSpeedType(zombie, speedType)
    return applyScaledZombieSpeed(
        zombie, modData, speedType, multiplier, baseSpeedOverride)
end

return RandomZeds
