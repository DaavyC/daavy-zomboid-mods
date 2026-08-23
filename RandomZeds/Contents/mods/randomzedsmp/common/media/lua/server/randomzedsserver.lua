if not isServer() then return end

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
local REROLL_TAG = "RandomZedsReroll"
local PENDING_SPEED_TAG = "RandomZedsPendingSpeedType"
local PENDING_SPRINTER_MULTIPLIER_TAG = "RandomZedsPendingSprinterMultiplier"
local PENDING_HEALTH_TAG = "RandomZedsPendingHealth"
local PENDING_SIGHT_TAG = "RandomZedsPendingSight"
local PENDING_HEARING_TAG = "RandomZedsPendingHearing"
local PENDING_PERIOD_TAG = "RandomZedsPendingPeriod"
local PROTECTION_RADIUS = 50
local PROTECTION_RADIUS_SQUARED = PROTECTION_RADIUS * PROTECTION_RADIUS
local PROTECTED_CHUNK_RADIUS = math.ceil(PROTECTION_RADIUS / 8)
local STATE_BATCH_SIZE = 16
local SPRINTER_RECONCILE_BUDGET_MS = 4
local SPRINTER_CHECK_COOLDOWN_MS = 1000
local PENDING_STATE_TIMEOUT_MS = 60000
local PENDING_STAND_UP_TIMEOUT_MS = 30000
local MIN_SPRINTER_MULTIPLIER = 0.5
local MAX_SPRINTER_MULTIPLIER = 1.5
local SPEED_TYPES = { "sprinter", "fastShambler", "shambler", "crawler" }
local HEALTH_CHANCE_ORDER = { "normal", "tough", "fragile" }
local SIGHT_CHANCE_ORDER = { "eagle", "normal", "poor" }
local HEARING_CHANCE_ORDER = { "pinpoint", "normal", "poor" }
local SIGHT_VALUES = { eagle = 1, normal = 2, poor = 3 }
local HEARING_VALUES = { pinpoint = 1, normal = 2, poor = 3 }
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
        RandomZeds.debug("Missing sandbox option " .. fullName)
        return nil
    end
    local value = option:getValue()
    RandomZeds.debug("Read option " .. fullName .. "=" .. tostring(value))
    return value
end

local function normalizeChances(chances, order, fallback)
    local remaining = 100
    for _, chanceType in ipairs(order) do
        local chance = math.min(chances[chanceType], remaining)
        chances[chanceType] = chance
        remaining = remaining - chance
    end

    chances[fallback] = chances[fallback] + remaining
    return chances
end

local function readHealthChances(optionPrefix, prefix)
    return normalizeChances({
        normal = readOption(optionPrefix, prefix .. "NormalChance"),
        tough = readOption(optionPrefix, prefix .. "ToughChance"),
        fragile = readOption(optionPrefix, prefix .. "FragileChance"),
    }, HEALTH_CHANCE_ORDER, "normal")
end

local function readSightChances(optionPrefix, prefix)
    return normalizeChances({
        eagle = readOption(optionPrefix, prefix .. "SightEagleChance"),
        normal = readOption(optionPrefix, prefix .. "SightNormalChance"),
        poor = readOption(optionPrefix, prefix .. "SightPoorChance"),
    }, SIGHT_CHANCE_ORDER, "normal")
end

local function readHearingChances(optionPrefix, prefix)
    return normalizeChances({
        pinpoint = readOption(optionPrefix, prefix .. "HearingPinpointChance"),
        normal = readOption(optionPrefix, prefix .. "HearingNormalChance"),
        poor = readOption(optionPrefix, prefix .. "HearingPoorChance"),
    }, HEARING_CHANCE_ORDER, "normal")
end

local function readConfig(optionPrefix)
    RandomZeds.debug("Reading profile config " .. optionPrefix)
    local config = normalizeChances({
        sprinter = readOption(optionPrefix, "SprinterChance"),
        fastShambler = readOption(optionPrefix, "FastShamblerChance"),
        shambler = readOption(optionPrefix, "ShamblerChance"),
        crawler = readOption(optionPrefix, "CrawlerChance"),
    }, SPEED_TYPES, "fastShambler")

    config.sprinterSpeedMultiplier = readOption(optionPrefix, "SprinterSpeedMultiplier")
    config.sprinterSpeedVariationDecrease = readOption(optionPrefix, "SprinterSpeedVariationDecrease")
    config.sprinterSpeedVariationIncrease = readOption(optionPrefix, "SprinterSpeedVariationIncrease")
    config.health = {}
    config.sight = {}
    config.hearing = {}
    for _, speedType in ipairs(SPEED_TYPES) do
        local prefix = speedType:gsub("^%l", string.upper)
        config.health[speedType] = readHealthChances(optionPrefix, prefix)
        config.sight[speedType] = readSightChances(optionPrefix, prefix)
        config.hearing[speedType] = readHearingChances(optionPrefix, prefix)
    end

    RandomZeds.debug("Profile config loaded " .. optionPrefix)
    return config
end

local function readWeatherSettings()
    local settings = {
        rain = readOption(WEATHER_ID, "Rain"),
        fog = readOption(WEATHER_ID, "Fog"),
        snow = readOption(WEATHER_ID, "Snow"),
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
    end

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
    local active = settings.rain and rain or settings.fog and fog or settings.snow and snow
    RandomZeds.debug("Weather activity rain=" .. tostring(rain) .. " fog=" .. tostring(fog)
        .. " snow=" .. tostring(snow) .. " active=" .. tostring(active))
    return active
end

local function getCurrentPeriod()
    local climate = getClimateManager()
    local season = climate and climate:getSeason()
    local seasonName = season and SEASON_OPTION_NAMES[season:getSeason()] or "Spring"
    local defaults = SEASON_DEFAULTS[seasonName] or SEASON_DEFAULTS.Spring
    local options = getSandboxOptions()
    local seasonOptionPrefix = MAIN_ID .. "." .. seasonName
    local dayStart = tonumber(options:getOptionByName(
        seasonOptionPrefix .. "DayStart"
    ):getValue()) or defaults.dayStart
    local nightStart = tonumber(options:getOptionByName(
        seasonOptionPrefix .. "NightStart"
    ):getValue()) or defaults.nightStart
    local dayEnabled = dayStart >= 0
    local nightEnabled = nightStart >= 0
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

    if not dayEnabled then dayStart = defaults.dayStart end
    if not nightEnabled then nightStart = defaults.nightStart end
    if dayStart >= nightStart then
        dayStart = defaults.dayStart
        nightStart = defaults.nightStart
    end

    local timeOfDay = getGameTime():getTimeOfDay()
    local isDay = timeOfDay >= dayStart and timeOfDay < nightStart
    local period = isDay and DAY_PERIOD or NIGHT_PERIOD
    RandomZeds.debug("Current period=" .. period .. " season=" .. seasonName
        .. " time=" .. tostring(timeOfDay))
    return period
end

local function getOptionPrefix(period)
    return period == NIGHT_PERIOD and NIGHT_ID or DAY_ID
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
    return readProfile(period, getOptionPrefix(period))
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

    return "crawler"
end

local function rollPerception(chances, order, values)
    local roll = ZombRandFloat(0, 100)
    local threshold = 0
    for _, level in ipairs(order) do
        threshold = threshold + chances[level]
        if roll < threshold then return values[level] end
    end
    return values[order[#order]]
end

local function rollZombieSight(config, speedType)
    return rollPerception(config.sight[speedType], SIGHT_CHANCE_ORDER, SIGHT_VALUES)
end

local function rollZombieHearing(config, speedType)
    return rollPerception(config.hearing[speedType], HEARING_CHANCE_ORDER, HEARING_VALUES)
end

local function rollSprinterMultiplier(config, speedType)
    local multiplier = config.sprinterSpeedMultiplier
    local decrease = config.sprinterSpeedVariationDecrease
    local increase = config.sprinterSpeedVariationIncrease
    if speedType ~= "sprinter" or (decrease <= 0 and increase <= 0) then
        return multiplier
    end

    return ZombRandFloat(
        math.max(MIN_SPRINTER_MULTIPLIER, multiplier - decrease),
        math.min(MAX_SPRINTER_MULTIPLIER, multiplier + increase)
    )
end

local function clearPendingReroll(modData)
    local hadPending = modData[PENDING_SPEED_TAG] ~= nil
    modData[PENDING_SPEED_TAG] = nil
    modData[PENDING_SPRINTER_MULTIPLIER_TAG] = nil
    modData[PENDING_HEALTH_TAG] = nil
    modData[PENDING_SIGHT_TAG] = nil
    modData[PENDING_HEARING_TAG] = nil
    modData[PENDING_PERIOD_TAG] = nil
    return hadPending
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
        if zombie and not RandomZeds.isExcluded(zombie)
                and clearPendingReroll(zombie:getModData()) then
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
    modData[PENDING_SPEED_TAG] = state.speedType
    modData[PENDING_SPRINTER_MULTIPLIER_TAG] = state.multiplier
    modData[PENDING_HEALTH_TAG] = state.health
    modData[PENDING_SIGHT_TAG] = state.sight
    modData[PENDING_HEARING_TAG] = state.hearing
    modData[PENDING_PERIOD_TAG] = state.period
end

local function queueIdentifiedServerState(zombie, state, onlineID)
    if RandomZeds.isExcluded(zombie) then return end

    RandomZeds.debug("Queueing synchronized state id=" .. tostring(onlineID)
        .. " speed=" .. tostring(state.speedType))
    state.id = onlineID
    zombie:transmitModData()
    queuedServerStates[#queuedServerStates + 1] = state
end

local function queueServerState(zombie, state)
    if RandomZeds.isExcluded(zombie) then return end

    local onlineID = tonumber(zombie:getOnlineID())
    local synchronizedState = {
        period = state.period,
        speedType = state.speedType,
        multiplier = state.multiplier,
        baseSpeed = tonumber(zombie:getModData()[SPRINTER_BASE_SPEED_TAG]),
        health = state.health,
        sight = state.sight,
        hearing = state.hearing,
        reroll = tonumber(state.reroll) or rerollRevision,
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
    state.readyTick = serverTick + 1
    state.expiresAt = getTimestampMs() + PENDING_STATE_TIMEOUT_MS
    pendingStateConfirmations[zombie] = state
end

local function processPendingStateConfirmations()
    local now = getTimestampMs()
    for zombie, state in pairs(pendingStateConfirmations) do
        if RandomZeds.isExcluded(zombie) or zombie:isDead()
                or state.expiresAt and now >= state.expiresAt then
            pendingStateConfirmations[zombie] = nil
        elseif serverTick >= state.readyTick and zombie:getSquare()
                and zombie:getCurrentActionContextStateName() ~= "getup"
                and not zombie:isCrawling() then
            if RandomZeds.isZombieSpeedTypeApplied(
                    zombie, state.speedType, false) then
                if state.speedType == "sprinter" then
                    RandomZeds.reconcileSprinterMotion(zombie)
                end
                pendingStateConfirmations[zombie] = nil
                queueServerState(zombie, state)
            end
        end
    end
end

local function applyNativeStateSequence(zombie, callback)
    RandomZeds.beginStateApplication(zombie)
    local ok, result = pcall(callback)
    RandomZeds.finishStateApplication(zombie)
    if not ok then
        RandomZeds.debug("Native state sequence failed: " .. tostring(result))
        return false
    end
    return result ~= false
end

local function deferBlockedZombieState(zombie, state, gettingUp)
    queuePendingState(zombie, state)
    if not gettingUp then
        RandomZeds.setCrawlerState(zombie, false)
    end
    pendingStandUps[zombie] = pendingStandUps[zombie]
        or getTimestampMs() + PENDING_STAND_UP_TIMEOUT_MS
    RandomZeds.debug("Zombie state deferred: getting up or crawling")
end

local function isSameZombieState(modData, state)
    return modData[PERIOD_TAG] == state.period
        and modData[SPEED_TAG] == state.speedType
        and tonumber(modData[SPRINTER_MULTIPLIER_TAG])
            == tonumber(state.multiplier)
        and tonumber(modData[HEALTH_TAG]) == tonumber(state.health)
        and tonumber(modData[SIGHT_TAG]) == tonumber(state.sight)
        and tonumber(modData[HEARING_TAG]) == tonumber(state.hearing)
end

local function repairSameStateSprinter(zombie, state, modData)
    local corrected = applyNativeStateSequence(zombie, function()
        return RandomZeds.applyZombieSpeedType(
            zombie, state.speedType, state.multiplier)
    end)
    if not corrected
            or not RandomZeds.isZombieSpeedTypeApplied(
                zombie, state.speedType, false) then
        return
    end

    RandomZeds.reconcileSprinterMotion(zombie)
    clearPendingReroll(modData)
    state.reroll = modData[REROLL_TAG]
    deferStateConfirmation(zombie, state)
    RandomZeds.debug("Corrected same-state sprinter speed")
end

local function writeAppliedZombieState(zombie, modData, state)
    zombie:setHealth(state.health)
    modData[PERIOD_TAG] = state.period
    modData[SPEED_TAG] = state.speedType
    modData[SPRINTER_MULTIPLIER_TAG] = state.multiplier
    modData[HEALTH_TAG] = state.health
    modData[SIGHT_TAG] = state.sight
    modData[HEARING_TAG] = state.hearing
    modData[REROLL_TAG] = rerollRevision
    clearPendingReroll(modData)
end

local function applyFreshZombieState(zombie, modData, state)
    local applied = applyNativeStateSequence(zombie, function()
        if not RandomZeds.applyZombieNativeStats(
                zombie, state.sight, state.hearing) then
            RandomZeds.debug("Native stats application failed; continuing with speed and health")
        end
        zombie:setVariable("RandomZedsSprinterSpeedScale", 0.8)
        if not RandomZeds.applyZombieSpeedType(
                zombie, state.speedType, state.multiplier) then
            return false
        end
        writeAppliedZombieState(zombie, modData, state)
        return true
    end)
    if not applied then
        RandomZeds.debug("Zombie state failed: speed application failed")
        return false
    end
    return true
end

local function deferUnappliedZombieState(zombie, state)
    queuePendingState(zombie, state)
    pendingStandUps[zombie] = pendingStandUps[zombie]
        or getTimestampMs() + PENDING_STAND_UP_TIMEOUT_MS
    RandomZeds.debug("Zombie state deferred: speed type not yet applied")
end

local function applyZombieState(zombie, state)
    if RandomZeds.isExcluded(zombie) then return end

    RandomZeds.debug("Applying zombie state period=" .. tostring(state.period)
        .. " speed=" .. tostring(state.speedType)
        .. " health=" .. tostring(state.health)
        .. " sight=" .. tostring(state.sight)
        .. " hearing=" .. tostring(state.hearing))
    local modData = zombie:getModData()
    local gettingUp = zombie:getCurrentActionContextStateName() == "getup"

    if gettingUp or (state.speedType ~= "crawler" and zombie:isCrawling()) then
        deferBlockedZombieState(zombie, state, gettingUp)
        return
    end

    pendingStandUps[zombie] = nil
    state.multiplier = tonumber(state.multiplier) or 1.0
    if isSameZombieState(modData, state) then
        local typeApplied = RandomZeds.isZombieSpeedTypeApplied(
            zombie, state.speedType, false)
        if typeApplied then
            if state.speedType == "sprinter" then
                RandomZeds.reconcileSprinterMotion(zombie)
            end
            zombie:setHealth(state.health)
            clearPendingReroll(modData)
            return
        end
        if state.speedType == "sprinter" then
            repairSameStateSprinter(zombie, state, modData)
            return
        end
    end
    state.sight = tonumber(state.sight) or 2
    state.hearing = tonumber(state.hearing) or 2
    if not applyFreshZombieState(zombie, modData, state) then return end
    if not RandomZeds.isZombieSpeedTypeApplied(zombie, state.speedType, false) then
        deferUnappliedZombieState(zombie, state)
        return
    end
    deferStateConfirmation(zombie, state)
    RandomZeds.debug("Zombie state applied and synchronized")
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
    local health = rollZombieHealth(config.health[speedType])
    local multiplier = rollSprinterMultiplier(config, speedType)
    local sight = rollZombieSight(config, speedType)
    local hearing = rollZombieHearing(config, speedType)
    local state = {
        period = period,
        speedType = speedType,
        health = health,
        multiplier = multiplier,
        sight = sight,
        hearing = hearing,
    }
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
    local multiplier = rollSprinterMultiplier(config, speedType)
    local health = rollZombieHealth(config.health[speedType])
    local sight = rollZombieSight(config, speedType)
    local hearing = rollZombieHearing(config, speedType)
    local state = {
        period = period,
        speedType = speedType,
        multiplier = multiplier,
        health = health,
        sight = sight,
        hearing = hearing,
    }
    RandomZeds.debug("Queueing crawler reroll period=" .. tostring(period)
        .. " speed=" .. tostring(speedType))
    queuePendingState(zombie, state)
end

local function applyPendingZombieState(zombie, modData)
    if RandomZeds.isExcluded(zombie) then return end

    local speedType = modData[PENDING_SPEED_TAG]
    if not speedType then return end

    RandomZeds.debug("Applying pending zombie state speed=" .. tostring(speedType))

    applyZombieState(zombie, {
        period = modData[PENDING_PERIOD_TAG] or getCurrentPeriod(),
        speedType = speedType,
        multiplier = tonumber(modData[PENDING_SPRINTER_MULTIPLIER_TAG]) or 1.0,
        health = tonumber(modData[PENDING_HEALTH_TAG]) or zombie:getHealth(),
        sight = tonumber(modData[PENDING_SIGHT_TAG]) or 2,
        hearing = tonumber(modData[PENDING_HEARING_TAG]) or 2,
    })
end

local function isSprinterReadyForCheck(zombie)
    if not zombie or RandomZeds.isExcluded(zombie)
            or RandomZeds.isStateApplicationInProgress(zombie)
            or zombie:isDead() or not zombie:getSquare()
            or zombie:isCrawling()
            or zombie:getCurrentActionContextStateName() == "getup" then
        return false
    end

    local modData = zombie:getModData()
    return modData and modData[SPEED_TAG] == "sprinter"
        and not modData[PENDING_SPEED_TAG]
end

local function correctSprinterState(zombie)
    local modData = zombie:getModData()
    local multiplier = tonumber(modData[SPRINTER_MULTIPLIER_TAG]) or 1.0
    local period = modData[PERIOD_TAG] or lastEffectiveMode
    if not period or period == DISABLED_PERIOD then return false end

    local typeApplied = RandomZeds.isZombieSpeedTypeApplied(
        zombie, "sprinter", false)
    if typeApplied then
        RandomZeds.reconcileSprinterMotion(zombie)
        return false
    end
    modData[SPRINTER_MULTIPLIER_TAG] = multiplier
    local applied = applyNativeStateSequence(zombie, function()
        return RandomZeds.applyZombieSpeedType(zombie, "sprinter", multiplier)
    end)
    if not applied then
        return false
    end
    RandomZeds.reconcileSprinterMotion(zombie)
    if not RandomZeds.isZombieSpeedTypeApplied(zombie, "sprinter", false) then
        return false
    end

    deferStateConfirmation(zombie, {
        period = period,
        speedType = "sprinter",
        multiplier = multiplier,
        health = tonumber(modData[HEALTH_TAG]) or zombie:getHealth(),
        sight = tonumber(modData[SIGHT_TAG]) or 2,
        hearing = tonumber(modData[HEARING_TAG]) or 2,
        reroll = modData[REROLL_TAG],
    })
    RandomZeds.debug("Corrected sprinter speed and queued synchronized state")
    return true
end

local function verifyLoadedSprinter(zombie, now)
    if not isSprinterReadyForCheck(zombie) then return false end

    local cooldownAt = sprinterCheckCooldowns[zombie] or 0
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

    local count = (protectedChunkCounts[chunkKey] or 0) + delta
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
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    local seenPlayers = {}
    if players then
        for playerIndex = 0, players:size() - 1 do
            local player = players:get(playerIndex)
            if player then
                seenPlayers[player] = true
                updatePlayerProtectedChunks(player)
            end
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

local function onPlayerCreated(playerIndex, player)
    updatePlayerProtectedChunks(player or playerIndex)
end

local function onPlayerMove(player)
    updatePlayerProtectedChunks(player)
end

local function reconcileCell(cell, period, config)
    local zombies = cell:getZombieList()
    if not zombies then
        RandomZeds.debug("Reconcile skipped: cell has no zombie list")
        return
    end

    RandomZeds.debug("Reconciling cell zombies=" .. tostring(zombies:size())
        .. " period=" .. tostring(period))

    for zombieIndex = 0, zombies:size() - 1 do
        local zombie = zombies:get(zombieIndex)
        if zombie and not RandomZeds.isExcluded(zombie) then
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
    local cell = getCell()
    if cell then
        reconcileCell(cell, period, config)
    end
end

local function applyPendingRerolls()
    if lastEffectiveMode == DISABLED_PERIOD then
        RandomZeds.debug("Pending rerolls skipped: profile disabled")
        return
    end

    local pending = {}
    RandomZeds.forEachLoadedZombie(function(zombie)
        local modData = zombie and zombie:getModData()
        if zombie and not RandomZeds.isExcluded(zombie)
                and not zombie:isDead() and modData and modData[PENDING_SPEED_TAG] then
            if modData[PENDING_PERIOD_TAG] ~= lastEffectiveMode then
                if not isCrawlerProtected(zombie) then
                    clearPendingReroll(modData)
                    applyZombieType(zombie)
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
                or zombie:isDead() or expiresAt and now >= expiresAt then
            pendingZombieCreates[zombie] = nil
        elseif zombie:getSquare() then
            pendingZombieCreates[zombie] = nil
            applyZombieType(zombie)
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
        local onlineID = tonumber(zombie:getOnlineID())
        if RandomZeds.isExcluded(zombie)
                or zombie:isDead() or state.expiresAt and now >= state.expiresAt then
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
        elseif expiresAt and now >= expiresAt then
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
    local _, config, signature = readProfile(period, getOptionPrefix(period))
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
    initialized = true
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
    RandomZeds.debug("Random Zeds server initialized")
end

Events.OnServerStarted.Add(initialize)
