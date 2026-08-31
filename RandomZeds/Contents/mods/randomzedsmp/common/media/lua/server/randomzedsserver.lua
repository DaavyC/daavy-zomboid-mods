if not isServer() then return end

local RandomZeds = require "randomzedsshared"

local DAY_ID = "RandomZeds"
local NIGHT_ID = "RandomZedsNight"
local WEATHER_ID = "RandomZedsWeather"
local MAIN_ID = "RandomZedsMain"
local DAY_PERIOD = "Day"
local NIGHT_PERIOD = "Night"
local WEATHER_PERIOD = "Weather"
local DISABLED_PERIOD = "Disabled"
local COMMAND_MODULE = "RandomZeds"
local STATE_COMMAND = "ZombieState"
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
local REROLL_TAG = "RandomZedsReroll"
local PENDING_SPEED_TAG = "RandomZedsPendingSpeedType"
local PENDING_SPRINTER_MULTIPLIER_TAG = "RandomZedsPendingSprinterMultiplier"
local PENDING_HEALTH_TAG = "RandomZedsPendingHealth"
local PENDING_SIGHT_TAG = "RandomZedsPendingSight"
local PENDING_HEARING_TAG = "RandomZedsPendingHearing"
local PENDING_COGNITION_TAG = "RandomZedsPendingCognition"
local PENDING_STRENGTH_TAG = "RandomZedsPendingStrength"
local PENDING_MEMORY_TAG = "RandomZedsPendingMemory"
local PENDING_PERIOD_TAG = "RandomZedsPendingPeriod"
local PENDING_STATE_FIELDS = {
    { name = "speedType", tag = PENDING_SPEED_TAG },
    { name = "multiplier", tag = PENDING_SPRINTER_MULTIPLIER_TAG },
    { name = "health", tag = PENDING_HEALTH_TAG },
    { name = "sight", tag = PENDING_SIGHT_TAG },
    { name = "hearing", tag = PENDING_HEARING_TAG },
    { name = "cognition", tag = PENDING_COGNITION_TAG },
    { name = "strength", tag = PENDING_STRENGTH_TAG },
    { name = "memory", tag = PENDING_MEMORY_TAG },
    { name = "period", tag = PENDING_PERIOD_TAG },
}
local PROTECTION_RADIUS = 50
local PROTECTION_RADIUS_SQUARED = PROTECTION_RADIUS * PROTECTION_RADIUS
local PROTECTED_CHUNK_RADIUS = math.ceil(PROTECTION_RADIUS / 8)
local STATE_BATCH_SIZE = 16
local SPRINTER_RECONCILE_BUDGET_MS = 4
local SPRINTER_CHECK_COOLDOWN_MS = 1000
local PENDING_STATE_TIMEOUT_MS = 60000
local PENDING_STAND_UP_TIMEOUT_MS = 30000
local SPEED_TYPES = RandomZeds.SPEED_TYPES
local BASE_PROFILE_NAMES = { "health", "sight", "hearing" }
local FEATURE_PROFILE_NAMES = { "cognition", "strength", "memory" }
local ALL_PROFILE_NAMES = {
    "health", "sight", "hearing", "cognition", "strength", "memory",
}
local PROFILE_DEFINITIONS = {
    health = {
        levels = { "normal", "tough", "fragile" },
        optionSuffixes = {
            normal = "NormalChance",
            tough = "ToughChance",
            fragile = "FragileChance",
        },
        remainder = "normal",
        values = { normal = 1.5, tough = 3.5, fragile = 0.5 },
    },
    sight = {
        levels = { "eagle", "normal", "poor" },
        optionSuffixes = {
            eagle = "SightEagleChance",
            normal = "SightNormalChance",
            poor = "SightPoorChance",
        },
        remainder = "normal",
        values = { eagle = 1, normal = 2, poor = 3 },
    },
    hearing = {
        levels = { "pinpoint", "normal", "poor" },
        optionSuffixes = {
            pinpoint = "HearingPinpointChance",
            normal = "HearingNormalChance",
            poor = "HearingPoorChance",
        },
        remainder = "normal",
        values = { pinpoint = 1, normal = 2, poor = 3 },
    },
    cognition = {
        levels = { "navigateDoors", "navigate", "basicNavigation" },
        optionSuffixes = {
            navigateDoors = "CognitionNavigateDoorsChance",
            navigate = "CognitionNavigateChance",
            basicNavigation = "CognitionBasicNavigationChance",
        },
        remainder = "basicNavigation",
        values = { navigateDoors = 1, navigate = 2, basicNavigation = 3 },
    },
    strength = {
        levels = { "superhuman", "normal", "weak" },
        optionSuffixes = {
            superhuman = "StrengthSuperhumanChance",
            normal = "StrengthNormalChance",
            weak = "StrengthWeakChance",
        },
        remainder = "normal",
        values = { superhuman = 1, normal = 2, weak = 3 },
    },
    memory = {
        levels = { "long", "normal", "short", "none" },
        optionSuffixes = {
            long = "MemoryLongChance",
            normal = "MemoryNormalChance",
            short = "MemoryShortChance",
            none = "MemoryNoneChance",
        },
        remainder = "normal",
        values = { long = 1, normal = 2, short = 3, none = 4 },
    },
}
local SEASON_OPTION_NAMES = {
    [1] = "Spring",
    [2] = "Summer",
    [3] = "Summer",
    [4] = "Autumn",
    [5] = "Winter",
}
local initialized = false
local lastEffectiveMode
local lastEffectiveSignature
local rerollRevision = 0
local queuedServerStates = {}
local pendingServerStates = {}
local pendingStateConfirmations = {}
local pendingStandUps = {}
local pendingZombieCreates = {}
local protectedChunks = {}
local protectedChunkCounts = {}
local playerProtectedChunks = {}
local sprinterCheckCursor = { index = 0 }
local sprinterCheckCooldowns = setmetatable({}, { __mode = "k" })
local serverTick = 0

local function readOption(optionPrefix, name)
    local fullName = optionPrefix .. "." .. name
    local option = getSandboxOptions():getOptionByName(fullName)
    if not option then
        error("Missing sandbox option " .. fullName)
    end
    local optionValue = option:getValue()
    RandomZeds.debug("Read option " .. fullName .. "=" .. tostring(optionValue))
    return optionValue
end

local function normalizeChances(chances, order, remainderTarget)
    local total = 0.0
    local normalizedChances = {}
    for _, chanceType in ipairs(order) do
        local chance = RandomZeds.requireRange(
            chances[chanceType], "chance " .. chanceType, 0, 100)
        normalizedChances[chanceType] = chance
        total = total + chance
    end

    if total > 100 then error("Chance total exceeds 100") end
    normalizedChances[remainderTarget] = normalizedChances[remainderTarget]
        + 100 - total
    return normalizedChances
end

local function readProfileChances(optionPrefix, prefix, profileName)
    local definition = PROFILE_DEFINITIONS[profileName]
    local chances = {}
    for _, level in ipairs(definition.levels) do
        chances[level] = readOption(
            optionPrefix,
            prefix .. definition.optionSuffixes[level]
        )
    end
    return normalizeChances(chances, definition.levels, definition.remainder)
end

local function readProfileTables(optionPrefix, profileNames)
    local profiles = {}
    for _, profileName in ipairs(profileNames) do
        profiles[profileName] = {}
    end

    for _, speedType in ipairs(SPEED_TYPES) do
        local prefix = speedType:gsub("^%l", string.upper)
        for _, profileName in ipairs(profileNames) do
            profiles[profileName][speedType] = readProfileChances(
                optionPrefix, prefix, profileName)
        end
    end
    return profiles
end

local function readConfig(optionPrefix)
    RandomZeds.debug("Reading profile config " .. optionPrefix)
    local config = normalizeChances({
        sprinter = readOption(optionPrefix, "SprinterChance"),
        fastShambler = readOption(optionPrefix, "FastShamblerChance"),
        shambler = readOption(optionPrefix, "ShamblerChance"),
        crawler = readOption(optionPrefix, "CrawlerChance"),
    }, SPEED_TYPES, "fastShambler")

    config.sprinterSpeedMultiplier = RandomZeds.requireSprinterMultiplier(
        readOption(optionPrefix, "SprinterSpeedMultiplier"),
        "SprinterSpeedMultiplier")
    config.sprinterSpeedVariationDecrease = RandomZeds.requireRange(
        readOption(optionPrefix, "SprinterSpeedVariationDecrease"),
        "SprinterSpeedVariationDecrease", 0.0, 0.5)
    config.sprinterSpeedVariationIncrease = RandomZeds.requireRange(
        readOption(optionPrefix, "SprinterSpeedVariationIncrease"),
        "SprinterSpeedVariationIncrease", 0.0, 0.5)
    config.featuresEnabled = RandomZeds.hasSynapseFeatureSupport()
    for _, profileName in ipairs(ALL_PROFILE_NAMES) do
        config[profileName] = {}
    end
    local profileNames = BASE_PROFILE_NAMES
    if config.featuresEnabled then
        profileNames = ALL_PROFILE_NAMES
    end
    local profileTables = readProfileTables(
        optionPrefix, profileNames)
    for _, profileName in ipairs(profileNames) do
        config[profileName] = profileTables[profileName]
    end

    RandomZeds.debug("Profile config loaded " .. optionPrefix)
    return config
end

local function readWeatherSettings()
    local settings = {
        rain = RandomZeds.requireBoolean(
            readOption(WEATHER_ID, "Rain"), "weather rain option"),
        fog = RandomZeds.requireBoolean(
            readOption(WEATHER_ID, "Fog"), "weather fog option"),
        snow = RandomZeds.requireBoolean(
            readOption(WEATHER_ID, "Snow"), "weather snow option"),
    }
    RandomZeds.debug("Weather settings rain=" .. tostring(settings.rain)
        .. " fog=" .. tostring(settings.fog) .. " snow=" .. tostring(settings.snow))
    return settings
end

local function getConfigSignature(config)
    local values = {}

    for _, speedType in ipairs(SPEED_TYPES) do
        values[#values + 1] = config[speedType]
    end
    values[#values + 1] = config.sprinterSpeedMultiplier
    values[#values + 1] = config.sprinterSpeedVariationDecrease
    values[#values + 1] = config.sprinterSpeedVariationIncrease

    for _, speedType in ipairs(SPEED_TYPES) do
        local health = config.health[speedType]
        values[#values + 1] = health.fragile
        values[#values + 1] = health.normal
        values[#values + 1] = health.tough
        local sight = config.sight[speedType]
        values[#values + 1] = sight.eagle
        values[#values + 1] = sight.normal
        values[#values + 1] = sight.poor
        local hearing = config.hearing[speedType]
        values[#values + 1] = hearing.pinpoint
        values[#values + 1] = hearing.normal
        values[#values + 1] = hearing.poor
        if config.featuresEnabled then
            local cognition = config.cognition[speedType]
            values[#values + 1] = cognition.navigateDoors
            values[#values + 1] = cognition.navigate
            values[#values + 1] = cognition.basicNavigation
            local strength = config.strength[speedType]
            values[#values + 1] = strength.superhuman
            values[#values + 1] = strength.normal
            values[#values + 1] = strength.weak
            local memory = config.memory[speedType]
            values[#values + 1] = memory.long
            values[#values + 1] = memory.normal
            values[#values + 1] = memory.short
            values[#values + 1] = memory.none
        end
    end

    values[#values + 1] = config.featuresEnabled and "synapse" or "legacy"
    return table.concat(values, ":")
end

local function isWeatherActive(settings)
    if not settings.rain and not settings.fog and not settings.snow then
        RandomZeds.debug("Weather profile disabled by settings")
        return false
    end
    local climate = getClimateManager()
    local rain = climate:getPrecipitationIntensity() > 0
    local fog = climate:getFogIntensity() > 0
    local snow = climate:getSnowStrength() > 0
    local active = false
    if settings.rain and rain then active = true end
    if settings.fog and fog then active = true end
    if settings.snow and snow then active = true end
    RandomZeds.debug("Weather activity rain=" .. tostring(rain) .. " fog=" .. tostring(fog)
        .. " snow=" .. tostring(snow) .. " active=" .. tostring(active))
    return active
end

local function readSeasonStart(options, optionName, description)
    local option = options:getOptionByName(optionName)
    if not option then
        error("Missing sandbox option " .. optionName)
    end
    return RandomZeds.requireRange(option:getValue(), description, -1, 23)
end

local function getSeasonPeriodSettings()
    local climate = getClimateManager()
    local season = climate:getSeason()
    local seasonName = SEASON_OPTION_NAMES[season:getSeason()]
    if not seasonName then error("Unsupported climate season") end
    local options = getSandboxOptions()
    local seasonOptionPrefix = MAIN_ID .. "." .. seasonName
    local dayStart = readSeasonStart(
        options,
        seasonOptionPrefix .. "DayStart",
        "season day start " .. seasonName
    )
    local nightStart = readSeasonStart(
        options,
        seasonOptionPrefix .. "NightStart",
        "season night start " .. seasonName
    )
    return seasonName, dayStart, nightStart
end

local function getExclusivePeriod(dayEnabled, nightEnabled)
    if dayEnabled and not nightEnabled then
        RandomZeds.debug("Current period=Day: night profile disabled")
        return DAY_PERIOD
    end
    if not dayEnabled and nightEnabled then
        RandomZeds.debug("Current period=Night: day profile disabled")
        return NIGHT_PERIOD
    end
    if not dayEnabled and not nightEnabled then
        RandomZeds.debug("Current period disabled: day and night profiles disabled")
        return DISABLED_PERIOD
    end
end

local function getCurrentPeriod()
    local seasonName, dayStart, nightStart = getSeasonPeriodSettings()
    local exclusivePeriod = getExclusivePeriod(
        dayStart >= 0, nightStart >= 0)
    if exclusivePeriod then return exclusivePeriod end

    if dayStart >= nightStart then
        error("Day start must be before night start for " .. seasonName)
    end

    local timeOfDay = getGameTime():getTimeOfDay()
    local isDay = timeOfDay >= dayStart and timeOfDay < nightStart
    local period
    if isDay then
        period = DAY_PERIOD
    else
        period = NIGHT_PERIOD
    end
    RandomZeds.debug("Current period=" .. period .. " season=" .. seasonName
        .. " time=" .. tostring(timeOfDay))
    return period
end

local function getOptionPrefix(period)
    if period == DAY_PERIOD then return DAY_ID end
    if period == NIGHT_PERIOD then return NIGHT_ID end
    error("Unsupported profile period " .. tostring(period))
end

local function readProfile(period, optionPrefix, signatureSuffix)
    local config = readConfig(optionPrefix)
    local signature = period .. ":" .. getConfigSignature(config)
        .. signatureSuffix
    RandomZeds.debug("Profile selected period=" .. period .. " prefix=" .. optionPrefix)
    return period, config, signature
end

local function getEffectiveProfile()
    local weatherSettings = readWeatherSettings()
    if isWeatherActive(weatherSettings) then
        RandomZeds.debug("Weather profile active")
        return readProfile(
            WEATHER_PERIOD,
            WEATHER_ID,
            ":" .. tostring(weatherSettings.rain)
                .. ":" .. tostring(weatherSettings.fog)
                .. ":" .. tostring(weatherSettings.snow)
        )
    end

    local period = getCurrentPeriod()
    if period == DISABLED_PERIOD then
        RandomZeds.debug("No active Random Zeds profile")
        return period, nil, period
    end
    return readProfile(period, getOptionPrefix(period), "")
end

local function rollZombieHealth(chances)
    local roll = ZombRandFloat(0, 100)
    local health

    if roll < chances.normal then
        health = 1.5
    elseif roll < chances.normal + chances.tough then
        health = 3.5
    else
        health = 0.5
    end

    return health + ZombRandFloat(0, 0.3)
end

local function getRandomSpeedType(config, allowCrawler)
    local roll = ZombRandFloat(0, 100)
    local threshold = 0

    for _, speedType in ipairs(SPEED_TYPES) do
        if speedType == "crawler" and allowCrawler == false then
            return "fastShambler"
        end

        threshold = threshold + config[speedType]
        if roll < threshold then
            return speedType
        end
    end

    error("Zombie speed roll did not match a configured profile")
end

local function rollPerception(chances, order, values)
    local roll = ZombRandFloat(0, 100)
    local threshold = 0
    for _, level in ipairs(order) do
        threshold = threshold + chances[level]
        if roll < threshold then return values[level] end
    end
    error("Zombie profile roll did not match a configured profile")
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
    for _, field in ipairs(PENDING_STATE_FIELDS) do
        modData[field.tag] = nil
    end
end

local function writePendingState(modData, state)
    for _, field in ipairs(PENDING_STATE_FIELDS) do
        modData[field.tag] = state[field.name]
    end
end

local function readPendingState(modData)
    local state = {}
    for _, field in ipairs(PENDING_STATE_FIELDS) do
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
    pendingStandUps[zombie] = RandomZeds.requireNumber(
        deadline, "pending stand-up deadline")
end

local function discardPendingRerolls()
    RandomZeds.debug("Discarding pending rerolls")
    pendingStandUps = {}
    pendingZombieCreates = {}
    pendingServerStates = {}
    pendingStateConfirmations = {}
    queuedServerStates = {}
    serverTick = 0
    local discarded = 0
    RandomZeds.forEachLoadedZombie(function(zombie)
        local modData = zombie:getModData()
        if not modData then error("Zombie mod data is required") end
        if not RandomZeds.isExcluded(zombie)
                and hasPendingReroll(modData) then
            clearPendingReroll(modData)
            discarded = discarded + 1
        end
    end)
    RandomZeds.debug("Discarded pending rerolls count=" .. tostring(discarded))
end

local function queuePendingState(zombie, state)
    if RandomZeds.isExcluded(zombie) then return end

    RandomZeds.debug("Queueing pending state period=" .. tostring(state.period)
        .. " speed=" .. tostring(state.speedType))
    local modData = zombie:getModData()
    writePendingState(modData, state)
end

local function queueIdentifiedServerState(zombie, state, onlineID)
    if RandomZeds.isExcluded(zombie) then return end

    RandomZeds.debug("Queueing synchronized state id=" .. tostring(onlineID)
        .. " speed=" .. tostring(state.speedType))
    zombie:transmitModData()
    state.id = onlineID
    queuedServerStates[#queuedServerStates + 1] = state
end

local function queueServerState(zombie, state)
    if RandomZeds.isExcluded(zombie) then return end

    local onlineID = zombie:getOnlineID()
    local modData = zombie:getModData()
    local baseSpeed
    if state.speedType == "sprinter" then
        baseSpeed = RandomZeds.requireNumber(
            modData[SPRINTER_BASE_SPEED_TAG], "sprinter base speed")
    end
    local synchronizedState = {
        period = state.period,
        speedType = state.speedType,
        multiplier = state.multiplier,
        baseSpeed = baseSpeed,
        health = state.health,
        sight = state.sight,
        hearing = state.hearing,
        cognition = state.cognition,
        strength = state.strength,
        memory = state.memory,
        reroll = RandomZeds.requireInteger(state.reroll, "zombie state reroll"),
    }

    if not RandomZeds.isValidOnlineID(onlineID) then
        RandomZeds.debug("Deferring synchronized state without online id")
        synchronizedState.expiresAt = getTimestampMs() + PENDING_STATE_TIMEOUT_MS
        pendingServerStates[zombie] = synchronizedState
        return
    end

    pendingServerStates[zombie] = nil
    queueIdentifiedServerState(zombie, synchronizedState, onlineID)
end

local function flushServerStates()
    if #queuedServerStates == 0 then return end

    RandomZeds.debug("Flushing synchronized states count=" .. tostring(#queuedServerStates))

    for first = 1, #queuedServerStates, STATE_BATCH_SIZE do
        local states = {}
        local last = math.min(first + STATE_BATCH_SIZE - 1, #queuedServerStates)
        for index = first, last do
            states[#states + 1] = queuedServerStates[index]
        end
        sendServerCommand(COMMAND_MODULE, STATE_COMMAND, { states = states })
    end

    queuedServerStates = {}
end

local function deferStateConfirmation(zombie, state)
    local modData = zombie:getModData()
    if not modData then error("Zombie mod data is required") end
    if state.reroll == nil then
        state.reroll = RandomZeds.requireInteger(
            modData[REROLL_TAG], "zombie state reroll")
    end
    state.readyTick = serverTick + 1
    state.expiresAt = getTimestampMs() + PENDING_STATE_TIMEOUT_MS
    pendingStateConfirmations[zombie] = state
end

local function processPendingStateConfirmations()
    local now = getTimestampMs()
    for zombie, state in pairs(pendingStateConfirmations) do
        if RandomZeds.isExcluded(zombie) or zombie:isDead()
                or now >= state.expiresAt then
            pendingStateConfirmations[zombie] = nil
        elseif serverTick >= state.readyTick and zombie:getSquare()
                and zombie:getCurrentActionContextStateName() ~= "getup"
                and (state.speedType == "crawler" or not zombie:isCrawling()) then
            if RandomZeds.isZombieSpeedTypeApplied(
                    zombie, state.speedType) then
                if state.speedType == "sprinter" then
                    RandomZeds.reconcileSprinterMotion(zombie)
                end
                pendingStateConfirmations[zombie] = nil
                queueServerState(zombie, state)
            end
        end
    end
end

local function deferBlockedZombieState(zombie, state, gettingUp)
    if not gettingUp then
        RandomZeds.setCrawlerState(zombie, false)
    end
    queuePendingState(zombie, state)
    queueStandUpRetry(zombie)
    RandomZeds.debug("Zombie state deferred: getting up or crawling")
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
    RandomZeds.validateOptionalFeatureState(
        storedState, "Stored zombie feature state")
    if not RandomZeds.hasFeatureState(state) then
        return not RandomZeds.hasPartialFeatureState(storedState)
    end
    local cognition = storedState.cognition
    local strength = storedState.strength
    local memory = storedState.memory
    return cognition == state.cognition
        and strength == state.strength
        and memory == state.memory
end

local function validateZombieState(state)
    if type(state) ~= "table" then error("Zombie state must be a table") end
    RandomZeds.requireProfilePeriod(state.period)
    if not state.speedType then error("Zombie state speed type is required") end
    RandomZeds.requireSpeedTypeId(state.speedType)
    RandomZeds.requireSprinterMultiplier(
        state.multiplier, "zombie state multiplier")
    RandomZeds.requireRange(
        state.health, "zombie state health", 0.5, 3.8)
    RandomZeds.requireIntegerRange(
        state.sight, "zombie state sight", 1, 3)
    RandomZeds.requireIntegerRange(
        state.hearing, "zombie state hearing", 1, 3)
    RandomZeds.validateOptionalFeatureState(state, "Zombie state")
    if RandomZeds.hasSynapseFeatureSupport()
            and not RandomZeds.hasFeatureState(state) then
        error("Synapse zombie feature profiles are missing")
    end
end

local function isSameZombieState(modData, state)
    local multiplier = RandomZeds.readOptionalNumber(
        modData[SPRINTER_MULTIPLIER_TAG], "stored sprinter multiplier")
    local health = RandomZeds.readOptionalNumber(
        modData[HEALTH_TAG], "stored zombie health")
    local sight = RandomZeds.readOptionalInteger(
        modData[SIGHT_TAG], "stored zombie sight")
    local hearing = RandomZeds.readOptionalInteger(
        modData[HEARING_TAG], "stored zombie hearing")
    return modData[PERIOD_TAG] == state.period
        and modData[SPEED_TAG] == state.speedType
        and multiplier == state.multiplier
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
        state.reroll = modData[REROLL_TAG]
        deferStateConfirmation(zombie, state)
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
    state.reroll = modData[REROLL_TAG]
    deferStateConfirmation(zombie, state)
    pendingStandUps[zombie] = nil
    RandomZeds.debug("Corrected same-state sprinter speed")
end

local function writeAppliedZombieState(zombie, modData, state)
    local synapseEnabled = RandomZeds.hasSynapseFeatureSupport()
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
    modData[REROLL_TAG] = rerollRevision
    clearPendingReroll(modData)
end

local function applyFreshZombieState(zombie, modData, state)
    if not RandomZeds.dispatchZombieState(zombie, state) then
        RandomZeds.applyZombieNativeStats(zombie, state.sight, state.hearing)
        RandomZeds.applyZombieFeatureState(zombie, state)
        RandomZeds.applyZombieSpeedType(zombie, state.speedType, state.multiplier)
    end
    writeAppliedZombieState(zombie, modData, state)
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
    RandomZeds.debug("Zombie state deferred: speed type not yet applied")
end

local function applyZombieState(zombie, state)
    if RandomZeds.isExcluded(zombie) then return end

    validateZombieState(state)

    RandomZeds.debug("Applying zombie state period=" .. tostring(state.period)
        .. " speed=" .. tostring(state.speedType)
        .. " health=" .. tostring(state.health)
        .. " sight=" .. tostring(state.sight)
        .. " hearing=" .. tostring(state.hearing))
    local modData = zombie:getModData()
    local gettingUp = zombie:getCurrentActionContextStateName() == "getup"

    if gettingUp or (state.speedType ~= "crawler"
            and zombie:isCrawling()
            and not RandomZeds.hasSynapseFeatureSupport()) then
        deferBlockedZombieState(zombie, state, gettingUp)
        return
    end

    if applySameZombieState(zombie, modData, state) then return end
    applyFreshZombieState(zombie, modData, state)
    if not RandomZeds.isZombieSpeedTypeApplied(zombie, state.speedType) then
        deferUnappliedZombieState(zombie, state)
        return
    end
    deferStateConfirmation(zombie, state)
    pendingStandUps[zombie] = nil
    RandomZeds.debug("Zombie state applied and synchronized")
end

local function addRolledProfileState(state, config, speedType)
    state.sight = rollProfile(config, "sight", speedType)
    state.hearing = rollProfile(config, "hearing", speedType)
    if not config.featuresEnabled then return end
    for _, profileName in ipairs(FEATURE_PROFILE_NAMES) do
        state[profileName] = rollProfile(config, profileName, speedType)
    end
end

local function applyZombieType(zombie, config, period, allowCrawler)
    if RandomZeds.isExcluded(zombie) then return end

    if not config then
        period, config = getEffectiveProfile()
        if not config then
            RandomZeds.debug("Zombie type skipped: no active profile")
            return
        end
    end

    local speedType = getRandomSpeedType(config, allowCrawler)
    local state = {
        period = period,
        speedType = speedType,
        health = rollZombieHealth(config.health[speedType]),
        multiplier = rollSprinterMultiplier(config, speedType),
    }
    addRolledProfileState(state, config, speedType)
    RandomZeds.debug("Rolled zombie type speed=" .. speedType
        .. " multiplier=" .. tostring(state.multiplier)
        .. " health=" .. tostring(state.health)
        .. " sight=" .. tostring(state.sight)
        .. " hearing=" .. tostring(state.hearing))
    applyZombieState(zombie, state)
end

local function queueCrawlerReroll(zombie, config, period)
    if RandomZeds.isExcluded(zombie) then return end

    local speedType = getRandomSpeedType(config, true)
    local state = {
        period = period,
        speedType = speedType,
        multiplier = rollSprinterMultiplier(config, speedType),
        health = rollZombieHealth(config.health[speedType]),
    }
    addRolledProfileState(state, config, speedType)
    RandomZeds.debug("Queueing crawler reroll period=" .. tostring(period)
        .. " speed=" .. tostring(speedType))
    queuePendingState(zombie, state)
end

local function applyPendingZombieState(zombie, modData)
    if RandomZeds.isExcluded(zombie) then return end

    local state = readPendingState(modData)
    local speedType = state.speedType
    if not speedType then return end

    RandomZeds.debug("Applying pending zombie state speed=" .. tostring(speedType))

    applyZombieState(zombie, state)
end

local function isSprinterReadyForCheck(zombie)
    if not zombie or RandomZeds.isExcluded(zombie)
            or zombie:isDead() or not zombie:getSquare()
            or zombie:isCrawling()
            or zombie:getCurrentActionContextStateName() == "getup" then
        return false
    end

    local modData = zombie:getModData()
    if not modData then error("Zombie mod data is required") end
    return modData[SPEED_TAG] == "sprinter"
        and not modData[PENDING_SPEED_TAG]
end

local function correctSprinterState(zombie)
    local modData = zombie:getModData()
    local state = {
        period = modData[PERIOD_TAG],
        speedType = "sprinter",
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
    validateZombieState(state)
    if state.period == DISABLED_PERIOD then return false end

    local typeApplied = RandomZeds.isZombieSpeedTypeApplied(
        zombie, "sprinter")
    if typeApplied then
        RandomZeds.reconcileSprinterMotion(zombie)
        return false
    end

    if RandomZeds.dispatchZombieState(zombie, state) then
        RandomZeds.reconcileSprinterMotion(zombie)
        if state.baseSpeed ~= nil then
            modData[SPRINTER_BASE_SPEED_TAG] = state.baseSpeed
        end
        deferStateConfirmation(zombie, state)
        return true
    end

    RandomZeds.applyZombieSpeedType(zombie, "sprinter", state.multiplier)
    RandomZeds.reconcileSprinterMotion(zombie)
    if not RandomZeds.isZombieSpeedTypeApplied(zombie, "sprinter") then
        return false
    end

    deferStateConfirmation(zombie, state)
    RandomZeds.debug("Corrected sprinter speed and queued synchronized state")
    return true
end

local function verifyLoadedSprinter(zombie, now)
    if not isSprinterReadyForCheck(zombie) then return false end

    local cooldownAt = sprinterCheckCooldowns[zombie]
    if cooldownAt == nil then
        cooldownAt = 0
    else
        cooldownAt = RandomZeds.requireNumber(
            cooldownAt, "sprinter check cooldown")
    end
    if now < cooldownAt then return false end
    sprinterCheckCooldowns[zombie] = now + SPRINTER_CHECK_COOLDOWN_MS

    return correctSprinterState(zombie)
end

local function verifySprinterStates()
    if lastEffectiveMode == DISABLED_PERIOD then return end

    local now = getTimestampMs()

    local corrected = 0
    RandomZeds.forEachLoadedZombieWithinBudget(
        sprinterCheckCursor,
        SPRINTER_RECONCILE_BUDGET_MS,
        function(zombie)
            if verifyLoadedSprinter(zombie, now) then
                corrected = corrected + 1
            end
        end
    )

    if corrected > 0 then
        RandomZeds.debug("Incrementally corrected sprinter states count="
            .. tostring(corrected))
        flushServerStates()
    end
end

local function getChunkCoordinates(square)
    if not square then return nil, nil end
    local chunkSize = RandomZeds.requireInteger(
        getChunkSizeInSquares(), "chunk size")
    if chunkSize <= 0 then error("Invalid chunk size") end
    local squareX = RandomZeds.requireInteger(square:getX(), "square x coordinate")
    local squareY = RandomZeds.requireInteger(square:getY(), "square y coordinate")
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

    delta = RandomZeds.requireNumber(delta, "protected chunk count delta")
    local currentCount = protectedChunkCounts[chunkKey]
    if currentCount == nil then
        if delta < 0 then
            error("Protected chunk count cannot be decremented before creation")
        end
        currentCount = 0
    else
        currentCount = RandomZeds.requireNumber(
            currentCount, "protected chunk count")
    end
    local count = currentCount + delta
    if count < 0 then error("Protected chunk count cannot be negative") end
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

    for chunkKey in pairs(coverage.chunks) do
        changeProtectedChunkCount(chunkKey, -1)
    end
    playerProtectedChunks[player] = nil
end

local function updatePlayerProtectedChunks(player)
    local square = player:getSquare()
    local chunkX, chunkY = getChunkCoordinates(square)
    local chunkKey = makeChunkKey(chunkX, chunkY)
    local previous = playerProtectedChunks[player]
    if previous and previous.centerKey == chunkKey then
        return
    end

    removePlayerProtectedChunks(player)
    if not chunkKey then return end

    local coverage = { centerKey = chunkKey, chunks = {} }
    for offsetX = -PROTECTED_CHUNK_RADIUS, PROTECTED_CHUNK_RADIUS do
        for offsetY = -PROTECTED_CHUNK_RADIUS, PROTECTED_CHUNK_RADIUS do
            local protectedKey = makeChunkKey(
                chunkX + offsetX,
                chunkY + offsetY
            )
            coverage.chunks[protectedKey] = true
            changeProtectedChunkCount(protectedKey, 1)
        end
    end
    playerProtectedChunks[player] = coverage
end

local function refreshProtectedChunks()
    local players = getOnlinePlayers()
    local seenPlayers = {}
    for playerIndex = 0, players:size() - 1 do
        local player = players:get(playerIndex)
        seenPlayers[player] = true
        updatePlayerProtectedChunks(player)
    end

    for player in pairs(playerProtectedChunks) do
        if not seenPlayers[player] then
            removePlayerProtectedChunks(player)
        end
    end
end

local function isCrawlerProtected(zombie)
    local square = zombie and zombie:getSquare()
    local chunkKey = getChunkKeyFromSquare(square)
    if chunkKey == nil or protectedChunks[chunkKey] ~= true then
        return false
    end

    for player in pairs(playerProtectedChunks) do
        if zombie:DistToSquared(player:getX(), player:getY())
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

local function reconcileCell(cell, period, config)
    local zombies = cell:getZombieList()

    RandomZeds.debug("Reconciling cell zombies=" .. tostring(zombies:size())
        .. " period=" .. tostring(period))

    for zombieIndex = 0, zombies:size() - 1 do
        local zombie = zombies:get(zombieIndex)
        if not RandomZeds.isExcluded(zombie) then
            local modData = zombie:getModData()
            if not zombie:isDead() then
                local crawlerProtected = isCrawlerProtected(zombie)
                if crawlerProtected and (zombie:isCrawling() or modData[SPEED_TAG] == "crawler") then
                    RandomZeds.debug("Protected crawler queued for reroll")
                    queueCrawlerReroll(zombie, config, period)
                else
                    RandomZeds.debug("Applying profile to zombie crawlerProtected="
                        .. tostring(crawlerProtected))
                    applyZombieType(zombie, config, period, not crawlerProtected)
                end
            end
        end
    end

    flushServerStates()
end

local function reconcileZombies(period, config)
    RandomZeds.debug("Reconciling loaded zombies period=" .. tostring(period))
    reconcileCell(getCell(), period, config)
end

local function applyPendingRerolls()
    if lastEffectiveMode == DISABLED_PERIOD then
        RandomZeds.debug("Pending rerolls skipped: profile disabled")
        return
    end

    local pending = {}
    RandomZeds.forEachLoadedZombie(function(zombie)
        local modData = zombie:getModData()
        if not modData then error("Zombie mod data is required") end
        if not RandomZeds.isExcluded(zombie)
                and not zombie:isDead() and modData[PENDING_SPEED_TAG] then
            if modData[PENDING_PERIOD_TAG] ~= lastEffectiveMode then
                if not isCrawlerProtected(zombie) then
                    local pendingPeriod = modData[PENDING_PERIOD_TAG]
                    applyZombieType(zombie)
                    if modData[PENDING_PERIOD_TAG] == pendingPeriod then
                        clearPendingReroll(modData)
                    end
                    flushServerStates()
                end
            elseif not isCrawlerProtected(zombie) then
                pending[#pending + 1] = zombie
            end
        end
    end)

    if #pending == 0 then return end
    RandomZeds.debug("Applying pending rerolls count=" .. tostring(#pending))
    rerollRevision = rerollRevision + 1
    for _, zombie in ipairs(pending) do
        applyPendingZombieState(zombie, zombie:getModData())
    end
    flushServerStates()
end

local function processPendingZombieCreates()
    local processed = 0
    local now = getTimestampMs()
    for zombie in pairs(pendingZombieCreates) do
        local expiresAt = pendingZombieCreates[zombie]
        if RandomZeds.isExcluded(zombie)
                or zombie:isDead() or now >= expiresAt then
            pendingZombieCreates[zombie] = nil
        elseif zombie:getSquare() then
            applyZombieType(zombie)
            pendingZombieCreates[zombie] = nil
            processed = processed + 1
        end
    end
    if processed > 0 then
        RandomZeds.debug("Processed new zombies count=" .. tostring(processed))
    end
end

local function processPendingServerStates()
    local processed = 0
    local now = getTimestampMs()
    for zombie, state in pairs(pendingServerStates) do
        local onlineID = zombie:getOnlineID()
        if RandomZeds.isExcluded(zombie)
                or zombie:isDead() or now >= state.expiresAt then
            pendingServerStates[zombie] = nil
        elseif RandomZeds.isValidOnlineID(onlineID) then
            pendingServerStates[zombie] = nil
            queueIdentifiedServerState(zombie, state, onlineID)
            processed = processed + 1
        end
    end
    if processed > 0 then
        RandomZeds.debug("Processed pending server states count=" .. tostring(processed))
    end
end

local function processPendingStandUps()
    local ready = {}
    local now = getTimestampMs()
    for zombie, expiresAt in pairs(pendingStandUps) do
        if RandomZeds.isExcluded(zombie)
                or zombie:isDead() or not zombie:getSquare() then
            pendingStandUps[zombie] = nil
        elseif now >= expiresAt then
            pendingStandUps[zombie] = nil
            clearPendingReroll(zombie:getModData())
            RandomZeds.debug("Cancelled stuck stand-up state")
        elseif not zombie:isCrawling()
                and zombie:getCurrentActionContextStateName() ~= "getup" then
            pendingStandUps[zombie] = nil
            ready[#ready + 1] = zombie
        end
    end

    if #ready == 0 then return end

    RandomZeds.debug("Processing stand-up states count=" .. tostring(#ready))
    rerollRevision = rerollRevision + 1
    for _, zombie in ipairs(ready) do
        applyPendingZombieState(zombie, zombie:getModData())
    end
end

local function applyPendingStandUps()
    serverTick = serverTick + 1
    refreshProtectedChunks()
    if lastEffectiveMode ~= DISABLED_PERIOD then
        processPendingStateConfirmations()
        processPendingZombieCreates()
        processPendingServerStates()
        processPendingStandUps()
    end
    verifySprinterStates()
    flushServerStates()
    RandomZeds.refreshSprinterAnimationSpeeds()
end

local function applyEffectiveProfile(period, config, signature)
    RandomZeds.debug("Applying effective profile period=" .. tostring(period))
    if not config then
        discardPendingRerolls()
        lastEffectiveMode = period
        lastEffectiveSignature = signature
        return
    end

    rerollRevision = rerollRevision + 1
    reconcileZombies(period, config)
    lastEffectiveMode = period
    lastEffectiveSignature = signature
end

local function updateEffectiveState()
    RandomZeds.debug("Updating effective Random Zeds state")
    RandomZeds.forceVanillaPerceptionDefaults()
    local period, config, signature = getEffectiveProfile()
    if period ~= lastEffectiveMode or signature ~= lastEffectiveSignature then
        RandomZeds.debug("Effective profile changed from " .. tostring(lastEffectiveMode)
            .. " to " .. tostring(period))
        applyEffectiveProfile(period, config, signature)
    end

    applyPendingRerolls()
end

local function onWeatherPeriodComplete()
    RandomZeds.debug("Weather period completed")
    if lastEffectiveMode ~= WEATHER_PERIOD then
        updateEffectiveState()
        return
    end
    RandomZeds.forceVanillaPerceptionDefaults()

    local period = getCurrentPeriod()
    if period == DISABLED_PERIOD then
        applyEffectiveProfile(period, nil, period)
        return
    end
    local _, config, signature = readProfile(
        period, getOptionPrefix(period), "")
    applyEffectiveProfile(period, config, signature)
    applyPendingRerolls()
end

local function onZombieCreate(zombie)
    if RandomZeds.isExcluded(zombie) then return end

    RandomZeds.debug("Zombie created; queueing initialization")
    pendingZombieCreates[zombie] = getTimestampMs() + PENDING_STATE_TIMEOUT_MS
end

local function initialize()
    if initialized then return end

    RandomZeds.debug("Initializing Random Zeds server")
    Events.OnZombieCreate.Add(onZombieCreate)
    Events.OnCreatePlayer.Add(onPlayerCreated)
    Events.OnPlayerMove.Add(onPlayerMove)
    Events.OnWeatherPeriodStart.Add(updateEffectiveState)
    Events.OnWeatherPeriodStage.Add(updateEffectiveState)
    Events.OnWeatherPeriodComplete.Add(onWeatherPeriodComplete)
    Events.OnTick.Add(applyPendingStandUps)
    Events.EveryOneMinute.Add(updateEffectiveState)
    refreshProtectedChunks()
    updateEffectiveState()
    initialized = true
    RandomZeds.debug("Random Zeds server initialized")
end

Events.OnServerStarted.Add(initialize)
