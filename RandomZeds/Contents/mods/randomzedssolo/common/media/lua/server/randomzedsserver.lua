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
local HEALTH_TAG = "RandomZedsHealth"
local SIGHT_TAG = "RandomZedsSight"
local HEARING_TAG = "RandomZedsHearing"
local PENDING_SPEED_TAG = "RandomZedsPendingSpeedType"
local PENDING_SPRINTER_MULTIPLIER_TAG = "RandomZedsPendingSprinterMultiplier"
local PENDING_HEALTH_TAG = "RandomZedsPendingHealth"
local PENDING_SIGHT_TAG = "RandomZedsPendingSight"
local PENDING_HEARING_TAG = "RandomZedsPendingHearing"
local PENDING_PERIOD_TAG = "RandomZedsPendingPeriod"
local PROTECTION_RADIUS = 50
local PROTECTION_RADIUS_SQUARED = PROTECTION_RADIUS * PROTECTION_RADIUS
local PROTECTED_CHUNK_RADIUS = math.ceil(PROTECTION_RADIUS / 8)
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
local pendingStandUps = {}
local pendingZombieCreates = {}
local protectedChunks = {}
local protectedChunkCounts = {}
local playerProtectedChunks = {}
local sprinterCheckCursor = { index = 0 }
local sprinterCheckCooldowns = setmetatable({}, { __mode = "k" })

local function readOption(optionPrefix, name)
    local fullName = optionPrefix .. "." .. name
    local option = getSandboxOptions():getOptionByName(fullName)
    if not option then
        RandomZeds.debug("Missing sandbox option " .. fullName)
        return nil
    end
    local optionValue = option:getValue()
    RandomZeds.debug("Read option " .. fullName .. "=" .. tostring(optionValue))
    return optionValue
end

local function normalizeChances(chances, order, fallback)
    local remaining = 100
    for _, chanceType in ipairs(order) do
        local chance = tonumber(chances[chanceType]) or 0
        chance = math.max(0, math.min(chance, remaining))
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

    config.sprinterSpeedMultiplier = tonumber(
        readOption(optionPrefix, "SprinterSpeedMultiplier")) or 1.0
    config.sprinterSpeedVariationDecrease = tonumber(
        readOption(optionPrefix, "SprinterSpeedVariationDecrease")) or 0
    config.sprinterSpeedVariationIncrease = tonumber(
        readOption(optionPrefix, "SprinterSpeedVariationIncrease")) or 0
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
    local signatureValues = {}

    for _, speedType in ipairs(SPEED_TYPES) do
        signatureValues[#signatureValues + 1] = config[speedType]
    end
    signatureValues[#signatureValues + 1] = config.sprinterSpeedMultiplier
    signatureValues[#signatureValues + 1] = config.sprinterSpeedVariationDecrease
    signatureValues[#signatureValues + 1] = config.sprinterSpeedVariationIncrease

    for _, speedType in ipairs(SPEED_TYPES) do
        local health = config.health[speedType]
        signatureValues[#signatureValues + 1] = health.fragile
        signatureValues[#signatureValues + 1] = health.normal
        signatureValues[#signatureValues + 1] = health.tough
        local sight = config.sight[speedType]
        signatureValues[#signatureValues + 1] = sight.eagle
        signatureValues[#signatureValues + 1] = sight.normal
        signatureValues[#signatureValues + 1] = sight.poor
        local hearing = config.hearing[speedType]
        signatureValues[#signatureValues + 1] = hearing.pinpoint
        signatureValues[#signatureValues + 1] = hearing.normal
        signatureValues[#signatureValues + 1] = hearing.poor
    end

    return table.concat(signatureValues, ":")
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

local function readSeasonStart(options, optionName, fallback)
    local option = options:getOptionByName(optionName)
    if not option then
        RandomZeds.debug("Missing sandbox option " .. optionName)
        return fallback
    end
    return tonumber(option:getValue()) or fallback
end

local function getSeasonPeriodSettings()
    local climate = getClimateManager()
    local season = climate and climate:getSeason()
    local seasonName = season and SEASON_OPTION_NAMES[season:getSeason()] or "Spring"
    local defaults = SEASON_DEFAULTS[seasonName] or SEASON_DEFAULTS.Spring
    local options = getSandboxOptions()
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

local function getRandomSpeedType(config, crawlerAllowed)
    local roll = ZombRandFloat(0, 100)
    local threshold = 0

    for _, speedType in ipairs(SPEED_TYPES) do
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
    for _, level in ipairs(order) do
        threshold = threshold + chances[level]
        if roll < threshold then return perceptionValues[level] end
    end
    return perceptionValues[order[#order]]
end

local function rollZombieSight(config, speedType)
    return rollPerception(config.sight[speedType], SIGHT_CHANCE_ORDER, SIGHT_VALUES)
end

local function rollZombieHearing(config, speedType)
    return rollPerception(config.hearing[speedType], HEARING_CHANCE_ORDER, HEARING_VALUES)
end

local function rollSprinterMultiplier(config, speedType)
    local multiplier = tonumber(config.sprinterSpeedMultiplier) or 1.0
    local decrease = tonumber(config.sprinterSpeedVariationDecrease) or 0
    local increase = tonumber(config.sprinterSpeedVariationIncrease) or 0
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

local function applyNativeStateSequence(zombie, callback)
    RandomZeds.beginStateApplication(zombie)
    local callbackSucceeded, callbackResult = pcall(callback)
    RandomZeds.finishStateApplication(zombie)
    if not callbackSucceeded then
        print("[Random Zeds] Native state sequence failed: " .. tostring(callbackResult))
        return false
    end
    return callbackResult ~= false
end

local function isSameZombieState(modData, state)
    return modData[PERIOD_TAG] == state.period
        and modData[SPEED_TAG] == state.speedType
        and tonumber(modData[SPRINTER_MULTIPLIER_TAG]) == tonumber(state.multiplier)
        and tonumber(modData[HEALTH_TAG]) == tonumber(state.health)
        and tonumber(modData[SIGHT_TAG]) == tonumber(state.sight)
        and tonumber(modData[HEARING_TAG]) == tonumber(state.hearing)
end

local function applySameZombieState(zombie, modData, state)
    local typeApplied = RandomZeds.isZombieSpeedTypeApplied(
        zombie, state.speedType, false)
    if typeApplied then
        if state.speedType == "sprinter" then
            RandomZeds.reconcileSprinterMotion(zombie)
        end
        zombie:setHealth(state.health)
        clearPendingReroll(modData)
        return true
    end

    if state.speedType ~= "sprinter" then return false end

    local corrected = applyNativeStateSequence(zombie, function()
        return RandomZeds.applyZombieSpeedType(
            zombie, state.speedType, state.multiplier)
    end)
    if not corrected or not RandomZeds.isZombieSpeedTypeApplied(
            zombie, state.speedType, false) then
        return true
    end

    RandomZeds.reconcileSprinterMotion(zombie)
    clearPendingReroll(modData)
    RandomZeds.debug("Corrected same-state sprinter speed")
    return true
end

local function persistZombieState(zombie, modData, state)
    zombie:setHealth(state.health)
    modData[PERIOD_TAG] = state.period
    modData[SPEED_TAG] = state.speedType
    modData[SPRINTER_MULTIPLIER_TAG] = state.multiplier
    modData[HEALTH_TAG] = state.health
    modData[SIGHT_TAG] = state.sight
    modData[HEARING_TAG] = state.hearing
    clearPendingReroll(modData)
end

local function applyFreshZombieState(zombie, modData, state)
    state.sight = tonumber(state.sight) or 2
    state.hearing = tonumber(state.hearing) or 2
    return applyNativeStateSequence(zombie, function()
        if not RandomZeds.applyZombieNativeStats(
                zombie, state.sight, state.hearing) then
            RandomZeds.debug("Native stats application failed; continuing with speed and health")
        end
        zombie:setVariable("RandomZedsSprinterSpeedScale", 0.8)
        if not RandomZeds.applyZombieSpeedType(
                zombie, state.speedType, state.multiplier) then
            return false
        end
        persistZombieState(zombie, modData, state)
        return true
    end)
end

local function queueStateUntilStanding(zombie, state)
    queuePendingState(zombie, state)
    pendingStandUps[zombie] = pendingStandUps[zombie]
        or getTimestampMs() + PENDING_STAND_UP_TIMEOUT_MS
end

local function queueZombieStateForRetry(zombie, state, message)
    queueStateUntilStanding(zombie, state)
    RandomZeds.debug(message)
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
        queueStateUntilStanding(zombie, state)
        if not gettingUp then
            RandomZeds.setCrawlerState(zombie, false)
        end
        RandomZeds.debug("Zombie state deferred: getting up or crawling")
        return
    end

    pendingStandUps[zombie] = nil
    state.multiplier = tonumber(state.multiplier) or 1.0
    if isSameZombieState(modData, state)
            and applySameZombieState(zombie, modData, state) then
        return
    end
    local applied = applyFreshZombieState(zombie, modData, state)
    if not applied then
        RandomZeds.debug("Zombie state failed: speed application failed")
        return
    end
    if not RandomZeds.isZombieSpeedTypeApplied(
            zombie, state.speedType, false) then
        queueZombieStateForRetry(
            zombie, state, "Zombie state deferred: speed type not yet applied")
        return
    end
    RandomZeds.debug("Zombie state applied")
end

local function applyZombieType(zombie, config, period, crawlerAllowed)
    if RandomZeds.isExcluded(zombie) then return end

    if not config then
        period, config = getEffectiveProfile()
        if not config then
            RandomZeds.debug("Zombie type skipped: no active profile")
            return
        end
    end

    local speedType = getRandomSpeedType(config, crawlerAllowed)
    local health = rollZombieHealth(config.health[speedType])
    local multiplier = rollSprinterMultiplier(config, speedType)
    local sight = rollZombieSight(config, speedType)
    local hearing = rollZombieHearing(config, speedType)
    RandomZeds.debug("Rolled zombie type speed=" .. speedType
        .. " multiplier=" .. tostring(multiplier) .. " health=" .. tostring(health)
        .. " sight=" .. tostring(sight)
        .. " hearing=" .. tostring(hearing))
    applyZombieState(zombie, {
        period = period,
        speedType = speedType,
        multiplier = multiplier,
        health = health,
        sight = sight,
        hearing = hearing,
    })
end

local function queueCrawlerReroll(zombie, config, period)
    if RandomZeds.isExcluded(zombie) then return end

    local speedType = getRandomSpeedType(config, true)
    RandomZeds.debug("Queueing crawler reroll period=" .. tostring(period)
        .. " speed=" .. tostring(speedType))
    queuePendingState(zombie, {
        period = period,
        speedType = speedType,
        multiplier = rollSprinterMultiplier(config, speedType),
        health = rollZombieHealth(config.health[speedType]),
        sight = rollZombieSight(config, speedType),
        hearing = rollZombieHearing(config, speedType),
    })
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

    RandomZeds.debug("Corrected sprinter speed")
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

local function getProtectionPlayers()
    local protectionPlayers = {}
    local activePlayerCount = getNumActivePlayers()
    for playerIndex = 0, activePlayerCount - 1 do
        local player = getSpecificPlayer(playerIndex)
        if player then protectionPlayers[#protectionPlayers + 1] = player end
    end
    return protectionPlayers
end

local function refreshProtectedChunks()
    local seenPlayers = {}
    local protectionPlayers = getProtectionPlayers()
    for _, player in ipairs(protectionPlayers) do
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

local function onPlayerCreated(playerIndex, player)
    local playerObject = player
    if not playerObject and type(playerIndex) ~= "number" then
        playerObject = playerIndex
    end
    updatePlayerProtectedChunks(playerObject)
end

local function onPlayerMove(player)
    updatePlayerProtectedChunks(player)
end

local function reconcileCell(cell, period, config, reapplyCurrentPeriod)
    local zombies = cell:getZombieList()
    if not zombies then
        RandomZeds.debug("Reconcile skipped: cell has no zombie list")
        return
    end

    RandomZeds.debug("Reconciling cell zombies=" .. tostring(zombies:size())
        .. " period=" .. tostring(period)
        .. " reapply=" .. tostring(reapplyCurrentPeriod))

    for zombieIndex = 0, zombies:size() - 1 do
        local zombie = zombies:get(zombieIndex)
        if zombie and not RandomZeds.isExcluded(zombie) then
            local modData = zombie:getModData()
            if not zombie:isDead()
                    and (reapplyCurrentPeriod or modData[PERIOD_TAG] ~= period) then
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

end

local function reconcileZombies(period, config, reapplyCurrentPeriod)
    RandomZeds.debug("Reconciling loaded zombies period=" .. tostring(period)
        .. " reapply=" .. tostring(reapplyCurrentPeriod))
    local cell = getCell()
    if cell then
        reconcileCell(cell, period, config, reapplyCurrentPeriod)
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
                end
            elseif not isCrawlerProtected(zombie) then
                pending[#pending + 1] = zombie
            end
        end
    end)

    if #pending == 0 then return end
    RandomZeds.debug("Applying pending rerolls count=" .. tostring(#pending))
    for _, zombie in ipairs(pending) do
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
    local now = getTimestampMs()
    for zombie in pairs(pendingZombieCreates) do
        local expiresAt = pendingZombieCreates[zombie]
        if RandomZeds.isExcluded(zombie)
                or zombie:isDead() then
            pendingZombieCreates[zombie] = nil
        elseif isProtectedCrawlerPending(zombie) then
            pendingZombieCreates[zombie] = now + PENDING_STATE_TIMEOUT_MS
        elseif expiresAt and now >= expiresAt then
            pendingZombieCreates[zombie] = nil
        elseif zombie:getSquare() then
            pendingZombieCreates[zombie] = nil
            applyZombieType(zombie, nil, nil, true)
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
    for _, zombie in ipairs(ready) do
        applyPendingZombieState(zombie, zombie:getModData())
    end
end

local function applyPendingStandUps()
    refreshProtectedChunks()
    if lastEffectiveMode ~= DISABLED_PERIOD then
        processPendingZombieCreates()
        processPendingStandUps()
    end
    verifySprinterStates()
end

local function applyEffectiveProfile(period, config, signature)
    RandomZeds.debug("Applying effective profile period=" .. tostring(period))
    if not config then
        discardPendingRerolls()
        lastEffectiveMode = period
        lastEffectiveSignature = signature
        return
    end

    reconcileZombies(period, config, true)
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

Events.OnGameStart.Add(initialize)
