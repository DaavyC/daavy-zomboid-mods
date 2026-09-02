local RandomZeds = require "randomzedsshared"

local DAY_ID = "RandomZeds"
local NIGHT_ID = "RandomZedsNight"
local WEATHER_ID = "RandomZedsWeather"
local MAIN_ID = "RandomZedsMain"
local DAY_PERIOD = "Day"
local NIGHT_PERIOD = "Night"
local WEATHER_PERIOD = "Weather"
local DISABLED_PERIOD = "Disabled"
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
local PROTECTION_RADIUS = 50
local PROTECTION_RADIUS_SQUARED = PROTECTION_RADIUS * PROTECTION_RADIUS
local PROTECTED_CHUNK_RADIUS = math.ceil(PROTECTION_RADIUS / 8)
local SCHEDULE_INTERVAL_MS = 250
local INITIAL_STATE_BUDGET_MS = 3
local SPRINTER_RECONCILE_BUDGET_MS = 4
local SPRINTER_CHECK_COOLDOWN_MS = 1000
local PENDING_STATE_TIMEOUT_MS = 60000
local PENDING_STAND_UP_TIMEOUT_MS = 30000
local SPEED_TYPES = RandomZeds.SPEED_TYPES
local BASE_PROFILE_NAMES = table.newarray("health", "sight", "hearing")
local FEATURE_PROFILE_NAMES = table.newarray("cognition", "strength", "memory")
local ALL_PROFILE_NAMES = table.newarray(
    "health", "sight", "hearing", "cognition", "strength", "memory"
)
local PROFILE_DEFINITIONS = {
    health = {
        levels = table.newarray("normal", "tough", "fragile"),
        signatureLevels = table.newarray("fragile", "normal", "tough"),
        optionSuffixes = {
            normal = "NormalChance",
            tough = "ToughChance",
            fragile = "FragileChance",
        },
        remainder = "normal",
        values = { normal = 1.5, tough = 3.5, fragile = 0.5 },
    },
    sight = {
        levels = table.newarray("eagle", "normal", "poor"),
        optionSuffixes = {
            eagle = "SightEagleChance",
            normal = "SightNormalChance",
            poor = "SightPoorChance",
        },
        remainder = "normal",
        values = { eagle = 1, normal = 2, poor = 3 },
    },
    hearing = {
        levels = table.newarray("pinpoint", "normal", "poor"),
        optionSuffixes = {
            pinpoint = "HearingPinpointChance",
            normal = "HearingNormalChance",
            poor = "HearingPoorChance",
        },
        remainder = "normal",
        values = { pinpoint = 1, normal = 2, poor = 3 },
    },
    cognition = {
        levels = table.newarray("navigateDoors", "navigate", "basicNavigation"),
        optionSuffixes = {
            navigateDoors = "CognitionNavigateDoorsChance",
            navigate = "CognitionNavigateChance",
            basicNavigation = "CognitionBasicNavigationChance",
        },
        remainder = "basicNavigation",
        values = { navigateDoors = 1, navigate = 2, basicNavigation = 3 },
    },
    strength = {
        levels = table.newarray("superhuman", "normal", "weak"),
        optionSuffixes = {
            superhuman = "StrengthSuperhumanChance",
            normal = "StrengthNormalChance",
            weak = "StrengthWeakChance",
        },
        remainder = "normal",
        values = { superhuman = 1, normal = 2, weak = 3 },
    },
    memory = {
        levels = table.newarray("long", "normal", "short", "none"),
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
local SEASON_DEFAULTS = {
    Spring = { dayStart = 7, nightStart = 19 },
    Summer = { dayStart = 6, nightStart = 20 },
    Autumn = { dayStart = 7, nightStart = 19 },
    Winter = { dayStart = 8, nightStart = 17 },
}
local initialized = false
local lastEffectiveMode
local lastEffectiveSignature
local lastEffectiveConfig
local pendingStandUps = {}
local pendingZombieCreates = {}
local protectedChunks = {}
local protectedChunkCounts = {}
local playerProtectedChunks = {}
local sprinterCheckCursor = { index = 0 }
local sprinterCheckCooldowns = setmetatable({}, { __mode = "k" })
local nextScheduledWorkAt = 0

local function hasPendingEntries(entries)
    for _ in pairs(entries) do
        return true
    end
    return false
end

local function readOption(optionPrefix, name)
    local fullName = optionPrefix .. "." .. name
    local options = getSandboxOptions and getSandboxOptions()
    local option = options and options:getOptionByName(fullName)
    if not option then
        RandomZeds.debug("Missing sandbox option " .. fullName)
        return nil
    end
    local optionValue = option:getValue()
    RandomZeds.debug("Read option " .. fullName .. "=" .. tostring(optionValue))
    return optionValue
end

local function normalizeChances(chances, order, remainderTarget)
    local remaining = 100.0
    local normalizedChances = {}
    for index = 1, #order do
        local chanceType = order[index]
        local chance = RandomZeds.requireNumber(
            chances[chanceType], "chance " .. chanceType) or 0.0
        chance = math.max(0, math.min(chance, remaining))
        normalizedChances[chanceType] = chance
        remaining = remaining - chance
    end

    normalizedChances[remainderTarget] = normalizedChances[remainderTarget]
        + remaining
    return normalizedChances
end

local function readProfileChances(optionPrefix, prefix, profileName)
    local definition = PROFILE_DEFINITIONS[profileName]
    local chances = {}
    for index = 1, #definition.levels do
        local level = definition.levels[index]
        chances[level] = readOption(
            optionPrefix,
            prefix .. definition.optionSuffixes[level]
        )
    end
    return normalizeChances(chances, definition.levels, definition.remainder)
end

local function readProfileTables(optionPrefix, profileNames)
    local profiles = {}
    for index = 1, #profileNames do
        local profileName = profileNames[index]
        profiles[profileName] = {}
    end

    for speedIndex = 1, #SPEED_TYPES do
        local speedType = SPEED_TYPES[speedIndex]
        local prefix = speedType:gsub("^%l", string.upper)
        for profileIndex = 1, #profileNames do
            local profileName = profileNames[profileIndex]
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

    config.sprinterSpeedMultiplier = tonumber(
        readOption(optionPrefix, "SprinterSpeedMultiplier")) or 1.0
    config.sprinterSpeedVariationDecrease = tonumber(
        readOption(optionPrefix, "SprinterSpeedVariationDecrease")) or 0
    config.sprinterSpeedVariationIncrease = tonumber(
        readOption(optionPrefix, "SprinterSpeedVariationIncrease")) or 0
    config.featuresEnabled = RandomZeds.hasSynapseFeatureSupport()
    for index = 1, #ALL_PROFILE_NAMES do
        local profileName = ALL_PROFILE_NAMES[index]
        config[profileName] = {}
    end
    local profileNames = BASE_PROFILE_NAMES
    if config.featuresEnabled then
        profileNames = ALL_PROFILE_NAMES
    end
    local profileTables = readProfileTables(
        optionPrefix, profileNames)
    for index = 1, #profileNames do
        local profileName = profileNames[index]
        config[profileName] = profileTables[profileName]
    end

    RandomZeds.debug("Profile config loaded " .. optionPrefix)
    return config
end

local function readWeatherSettings()
    local settings = {
        rain = readOption(WEATHER_ID, "Rain") == true,
        fog = readOption(WEATHER_ID, "Fog") == true,
        snow = readOption(WEATHER_ID, "Snow") == true,
    }
    RandomZeds.debug("Weather settings rain=" .. tostring(settings.rain)
        .. " fog=" .. tostring(settings.fog) .. " snow=" .. tostring(settings.snow))
    return settings
end

local function getConfigSignature(config)
    local signatureValues = {}

    for index = 1, #SPEED_TYPES do
        local speedType = SPEED_TYPES[index]
        signatureValues[#signatureValues + 1] = config[speedType]
    end
    signatureValues[#signatureValues + 1] = config.sprinterSpeedMultiplier
    signatureValues[#signatureValues + 1] = config.sprinterSpeedVariationDecrease
    signatureValues[#signatureValues + 1] = config.sprinterSpeedVariationIncrease

    local profileNames = BASE_PROFILE_NAMES
    if config.featuresEnabled then profileNames = ALL_PROFILE_NAMES end
    for index = 1, #SPEED_TYPES do
        local speedType = SPEED_TYPES[index]
        for profileIndex = 1, #profileNames do
            local profileName = profileNames[profileIndex]
            local profile = config[profileName][speedType]
            local definition = PROFILE_DEFINITIONS[profileName]
            local levels = definition.signatureLevels or definition.levels
            for levelIndex = 1, #levels do
                signatureValues[#signatureValues + 1] = profile[levels[levelIndex]]
            end
        end
    end

    signatureValues[#signatureValues + 1] = config.featuresEnabled and "synapse" or "legacy"
    return table.concat(signatureValues, ":")
end

local function isWeatherActive(settings)
    if not settings.rain and not settings.fog and not settings.snow then
        RandomZeds.debug("Weather profile disabled by settings")
        return false
    end
    local climate = getClimateManager and getClimateManager()
    if not climate then return false end
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

local function readSeasonStart(options, optionName, fallback)
    local option = options and options:getOptionByName(optionName)
    if not option then
        RandomZeds.debug("Missing sandbox option " .. optionName)
        return fallback
    end
    return tonumber(option:getValue()) or fallback
end

local function getSeasonPeriodSettings()
    local climate = getClimateManager and getClimateManager()
    local season = climate and climate:getSeason()
    local seasonName = season and SEASON_OPTION_NAMES[season:getSeason()] or "Spring"
    local defaults = SEASON_DEFAULTS[seasonName] or SEASON_DEFAULTS.Spring
    local options = getSandboxOptions and getSandboxOptions()
    local seasonOptionPrefix = MAIN_ID .. "." .. seasonName
    local dayStart = readSeasonStart(
        options, seasonOptionPrefix .. "DayStart", defaults.dayStart)
    local nightStart = readSeasonStart(
        options, seasonOptionPrefix .. "NightStart", defaults.nightStart)
    return seasonName, defaults, dayStart, nightStart
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
    local seasonName, defaults, dayStart, nightStart = getSeasonPeriodSettings()
    local dayEnabled = dayStart >= 0
    local nightEnabled = nightStart >= 0
    local exclusivePeriod = getExclusivePeriod(dayEnabled, nightEnabled)
    if exclusivePeriod then return exclusivePeriod end

    if not dayEnabled then dayStart = defaults.dayStart end
    if not nightEnabled then nightStart = defaults.nightStart end
    if dayStart >= nightStart then
        dayStart = defaults.dayStart
        nightStart = defaults.nightStart
    end

    local timeOfDay = getGameTime():getTimeOfDay()
    local isDay = RandomZeds.isDayPeriod(timeOfDay, dayStart, nightStart)
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
    return DAY_ID
end

local function readProfile(period, optionPrefix, signatureSuffix)
    local config = readConfig(optionPrefix)
    local signature = period .. ":" .. getConfigSignature(config)
        .. (signatureSuffix or "")
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

local function getRandomSpeedType(config, crawlerAllowed)
    local roll = ZombRandFloat(0, 100)
    local threshold = 0

    for index = 1, #SPEED_TYPES do
        local speedType = SPEED_TYPES[index]
        if speedType == "crawler" and crawlerAllowed == false then
            return "fastShambler"
        end

        threshold = threshold + config[speedType]
        if roll < threshold then
            return speedType
        end
    end

    return "crawler"
end

local function rollPerception(chances, order, perceptionValues)
    local roll = ZombRandFloat(0, 100)
    local threshold = 0
    for index = 1, #order do
        local level = order[index]
        threshold = threshold + chances[level]
        if roll < threshold then return perceptionValues[level] end
    end
    return perceptionValues[order[#order]]
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
    RandomZeds.debug("Discarding pending rerolls")
    pendingStandUps = {}
    pendingZombieCreates = {}
    local discarded = 0
    RandomZeds.forEachLoadedZombie(function(zombie)
        local modData = zombie:getModData()
        if modData and not RandomZeds.isExcluded(zombie)
                and hasPendingReroll(modData) then
            clearPendingReroll(modData)
            discarded = discarded + 1
        end
    end)
    RandomZeds.debug("Discarded pending rerolls count=" .. tostring(discarded))
end

local function queuePendingState(zombie, state)
    if RandomZeds.isExcluded(zombie) then return end

    local modData = zombie:getModData()
    if not modData then return end
    writePendingState(modData, state)
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

local function applySameZombieState(zombie, modData, state)
    if RandomZeds.dispatchZombieState(zombie, state) then
        if state.speedType == "sprinter" then
            RandomZeds.reconcileSprinterMotion(zombie)
            if state.baseSpeed ~= nil then
                modData[SPRINTER_BASE_SPEED_TAG] = state.baseSpeed
            end
        end
        clearPendingReroll(modData)
        return true
    end

    local typeApplied = RandomZeds.isZombieSpeedTypeApplied(
        zombie, state.speedType)
    if typeApplied then
        if state.speedType == "sprinter" then
            RandomZeds.applySprinterAnimationSpeed(zombie, state.multiplier)
            RandomZeds.reconcileSprinterMotion(zombie)
        end
        zombie:setHealth(state.health)
        clearPendingReroll(modData)
        return true
    end

    if state.speedType ~= "sprinter" then return false end

    RandomZeds.applyZombieSpeedType(zombie, state.speedType, state.multiplier)
    if not RandomZeds.isZombieSpeedTypeApplied(
            zombie, state.speedType) then
        return false
    end

    RandomZeds.reconcileSprinterMotion(zombie)
    clearPendingReroll(modData)
    pendingStandUps[zombie] = nil
    RandomZeds.debug("Corrected same-state sprinter speed")
    return true
end

local function persistZombieState(zombie, modData, state, synapseEnabled)
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
    clearPendingReroll(modData)
end

local function applyFreshZombieState(zombie, modData, state)
    local synapseApplied = RandomZeds.dispatchZombieState(zombie, state)
    if synapseApplied then
        persistZombieState(zombie, modData, state, true)
        return true
    end

    if not RandomZeds.applyZombieNativeStats(zombie, state.sight, state.hearing) then
        RandomZeds.debug("Native stats application failed; continuing")
    end
    RandomZeds.applyZombieFeatureState(zombie, state)
    if not RandomZeds.applyZombieSpeedType(zombie, state.speedType, state.multiplier) then
        return false
    end
    persistZombieState(zombie, modData, state, false)
    return true
end

local function queueStateUntilStanding(zombie, state)
    queuePendingState(zombie, state)
    queueStandUpRetry(zombie)
end

local function applyValidatedZombieState(zombie, state)
    if not zombie then return false end
    local modData = zombie:getModData()
    local gettingUp = zombie:getCurrentActionContextStateName() == "getup"

    if gettingUp or (state.speedType ~= "crawler"
            and zombie:isCrawling()
            and not RandomZeds.hasSynapseFeatureSupport()) then
        if not gettingUp then
            RandomZeds.setCrawlerState(zombie, false)
        end
        queueStateUntilStanding(zombie, state)
        return
    end

    if isSameZombieState(modData, state)
            and applySameZombieState(zombie, modData, state) then
        pendingStandUps[zombie] = nil
        return
    end
    if not applyFreshZombieState(zombie, modData, state) then
        RandomZeds.debug("Zombie state failed: speed application failed")
        return false
    end
    if not RandomZeds.isZombieSpeedTypeApplied(
            zombie, state.speedType) then
        queueStateUntilStanding(zombie, state)
        RandomZeds.debug("Zombie state deferred: speed type not yet applied")
        return
    end
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

local function rollZombieState(config, period, crawlerAllowed)
    local speedType = getRandomSpeedType(config, crawlerAllowed)
    local state = {
        period = period,
        speedType = speedType,
        health = rollZombieHealth(config.health[speedType]),
        multiplier = rollSprinterMultiplier(config, speedType),
    }
    addRolledProfileState(state, config, speedType)
    return state
end

local function applyZombieType(zombie, config, period, crawlerAllowed)
    if RandomZeds.isExcluded(zombie) then return end

    if not config then
        period = lastEffectiveMode
        config = lastEffectiveConfig
        if not config then
            period, config = getEffectiveProfile()
        end
        if not config then
            RandomZeds.debug("Zombie type skipped: no active profile")
            return
        end
    end

    applyValidatedZombieState(zombie, rollZombieState(config, period, crawlerAllowed))
end

local function queueCrawlerReroll(zombie, config, period)
    if RandomZeds.isExcluded(zombie) then return end

    queuePendingState(zombie, rollZombieState(config, period, true))
end

local function applyPendingZombieState(zombie, modData)
    if not modData or RandomZeds.isExcluded(zombie) then return end

    local state = readPendingState(modData)
    local speedType = state.speedType
    if not speedType then return end
    state.period = state.period or getCurrentPeriod()
    state.multiplier = tonumber(state.multiplier) or 1.0
    state.health = tonumber(state.health) or zombie:getHealth()
    state.sight = tonumber(state.sight) or 2
    state.hearing = tonumber(state.hearing) or 2

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
    if not modData then return false end
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
            RandomZeds.applySprinterAnimationSpeed(zombie, state.multiplier)
        end
        RandomZeds.reconcileSprinterMotion(zombie)
        return false
    end

    if RandomZeds.dispatchZombieState(zombie, state) then
        RandomZeds.reconcileSprinterMotion(zombie)
        if state.baseSpeed ~= nil then
            modData[SPRINTER_BASE_SPEED_TAG] = state.baseSpeed
        end
        return true
    end

    RandomZeds.applyZombieSpeedType(zombie, "sprinter", state.multiplier)
    RandomZeds.reconcileSprinterMotion(zombie)
    if not RandomZeds.isZombieSpeedTypeApplied(zombie, "sprinter") then
        return false
    end

    RandomZeds.debug("Corrected sprinter speed")
    return true
end

local function verifyLoadedSprinter(zombie, now)
    if not isSprinterReadyForCheck(zombie) then return false end

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
    end
end

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

    for chunkKey in pairs(coverage.chunks) do
        changeProtectedChunkCount(chunkKey, -1)
    end
    playerProtectedChunks[player] = nil
end

local function updatePlayerProtectedChunks(player)
    if not player then return end
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
    local seenPlayers = {}
    local activePlayerCount = getNumActivePlayers()
    for playerIndex = 0, activePlayerCount - 1 do
        local player = getSpecificPlayer(playerIndex)
        if player then
            seenPlayers[player] = true
            updatePlayerProtectedChunks(player)
        end
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
    if not cell then return end
    local zombies = cell:getZombieList()
    if not zombies then return end

    local zombieCount = zombies:size()
    RandomZeds.debug("Reconciling cell zombies=" .. tostring(zombieCount)
        .. " period=" .. tostring(period))

    for zombieIndex = 0, zombieCount - 1 do
        local zombie = zombies:get(zombieIndex)
        if zombie and not RandomZeds.isExcluded(zombie) then
            local modData = zombie:getModData()
            if modData and not zombie:isDead() then
                local crawlerProtected = isCrawlerProtected(zombie)
                if crawlerProtected and (zombie:isCrawling() or modData[SPEED_TAG] == "crawler") then
                    RandomZeds.debug("Protected crawler queued for reroll")
                    queueCrawlerReroll(zombie, config, period)
                else
                    applyZombieType(zombie, config, period, not crawlerProtected)
                end
            end
        end
    end

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
        if modData and not RandomZeds.isExcluded(zombie)
                and not zombie:isDead() and modData[PENDING_SPEED_TAG] then
            if modData[PENDING_PERIOD_TAG] ~= lastEffectiveMode then
                if not isCrawlerProtected(zombie) then
                    local pendingPeriod = modData[PENDING_PERIOD_TAG]
                    applyZombieType(zombie)
                    if modData[PENDING_PERIOD_TAG] == pendingPeriod then
                        clearPendingReroll(modData)
                    end
                end
            elseif not isCrawlerProtected(zombie) then
                pending[#pending + 1] = zombie
            end
        end
    end)

    if #pending == 0 then return end
    RandomZeds.debug("Applying pending rerolls count=" .. tostring(#pending))
    for index = 1, #pending do
        local zombie = pending[index]
        applyPendingZombieState(zombie, zombie:getModData())
    end
end

local function isProtectedCrawlerPending(zombie)
    if not zombie:getSquare() or not isCrawlerProtected(zombie) then
        return false
    end
    local modData = zombie:getModData()
    return zombie:isCrawling() or modData[SPEED_TAG] == "crawler"
end

local function processPendingZombieCreates()
    local processed = 0
    local visited = 0
    local now = getTimestampMs()
    local deadline = now + INITIAL_STATE_BUDGET_MS
    for zombie in pairs(pendingZombieCreates) do
        if visited > 0 and getTimestampMs() >= deadline then break end
        visited = visited + 1
        local expiresAt = pendingZombieCreates[zombie]
        if not zombie:getCurrentSquare() or zombie:isDead()
                or RandomZeds.isExcluded(zombie) then
            pendingZombieCreates[zombie] = nil
        elseif isProtectedCrawlerPending(zombie) then
            pendingZombieCreates[zombie] = now + PENDING_STATE_TIMEOUT_MS
        elseif expiresAt and now >= expiresAt then
            pendingZombieCreates[zombie] = nil
        elseif zombie:getSquare() then
            applyZombieType(zombie, nil, nil, true)
            pendingZombieCreates[zombie] = nil
            processed = processed + 1
        end
    end
    if processed > 0 then
        RandomZeds.debug("Processed new zombies count=" .. tostring(processed))
    end
end

local function processPendingStandUps()
    local ready = {}
    local now = getTimestampMs()
    for zombie, expiresAt in pairs(pendingStandUps) do
        if not zombie:getCurrentSquare() or zombie:isDead()
                or RandomZeds.isExcluded(zombie) then
            pendingStandUps[zombie] = nil
        elseif expiresAt and now >= expiresAt then
            pendingStandUps[zombie] = nil
            local modData = zombie:getModData()
            if modData then clearPendingReroll(modData) end
            RandomZeds.debug("Cancelled stuck stand-up state")
        elseif not zombie:isCrawling()
                and zombie:getCurrentActionContextStateName() ~= "getup" then
            pendingStandUps[zombie] = nil
            ready[#ready + 1] = zombie
        end
    end

    if #ready == 0 then return end

    RandomZeds.debug("Processing stand-up states count=" .. tostring(#ready))
    for index = 1, #ready do
        local zombie = ready[index]
        applyPendingZombieState(zombie, zombie:getModData())
    end
end

local function processScheduledZombieWork()
    local now = getTimestampMs()
    if now < nextScheduledWorkAt then return end
    nextScheduledWorkAt = now + SCHEDULE_INTERVAL_MS

    if lastEffectiveMode ~= DISABLED_PERIOD then
        if hasPendingEntries(pendingZombieCreates) then
            processPendingZombieCreates()
        end
        if hasPendingEntries(pendingStandUps) then
            processPendingStandUps()
        end
        verifySprinterStates()
    end
    RandomZeds.refreshSprinterAnimationSpeeds()
end

local function applyEffectiveProfile(period, config, signature)
    RandomZeds.debug("Applying effective profile period=" .. tostring(period))
    if not config then
        discardPendingRerolls()
        lastEffectiveMode = period
        lastEffectiveSignature = signature
        lastEffectiveConfig = nil
        return
    end

    reconcileZombies(period, config)
    lastEffectiveMode = period
    lastEffectiveSignature = signature
    lastEffectiveConfig = config
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
    Events.OnTick.Add(processScheduledZombieWork)
    Events.EveryOneMinute.Add(updateEffectiveState)
    Events.EveryOneMinute.Add(refreshProtectedChunks)
    refreshProtectedChunks()
    updateEffectiveState()
    initialized = true
    RandomZeds.debug("Random Zeds server initialized")
end

Events.OnGameStart.Add(initialize)
