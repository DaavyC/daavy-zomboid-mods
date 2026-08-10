if isClient() then return end

local DAY_ID = "RandomZeds"
local NIGHT_ID = "RandomZedsNight"
local WEATHER_ID = "RandomZedsWeather"
local DAY_PERIOD = "Day"
local NIGHT_PERIOD = "Night"
local WEATHER_PERIOD = "Weather"
local COMMAND_MODULE = "RandomZeds"
local STATE_COMMAND = "ZombieState"
local PERIOD_TAG = "RandomZedsPeriod"
local SPEED_TAG = "RandomZedsSpeedType"
local SPRINTER_MULTIPLIER_TAG = "RandomZedsSprinterMultiplier"
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local HEALTH_TAG = "RandomZedsHealth"
local REROLL_TAG = "RandomZedsReroll"
local PENDING_SPEED_TAG = "RandomZedsPendingSpeedType"
local PENDING_SPRINTER_MULTIPLIER_TAG = "RandomZedsPendingSprinterMultiplier"
local PENDING_HEALTH_TAG = "RandomZedsPendingHealth"
local PENDING_PERIOD_TAG = "RandomZedsPendingPeriod"
local PROTECTION_RADIUS_SQUARED = 50 * 50
local STATE_BATCH_SIZE = 16
local MIN_SPRINTER_MULTIPLIER = 0.5
local MAX_SPRINTER_MULTIPLIER = 1.5
local SPEED_TYPES = { "sprinter", "fastShambler", "shambler", "crawler" }
local HEALTH_CHANCE_ORDER = { "normal", "tough", "fragile" }
local initialized = false
local lastEffectiveMode
local lastEffectiveSignature
local rerollRevision = 0
local queuedServerStates = {}
local pendingServerStates = {}
local pendingStandUps = {}
local pendingZombieCreates = {}

local function readChance(optionPrefix, name)
    return getSandboxOptions():getOptionByName(optionPrefix .. "." .. name):getValue()
end

local function readBoolean(optionPrefix, name)
    return getSandboxOptions():getOptionByName(optionPrefix .. "." .. name):getValue()
end

local function readSprinterMultiplier(optionPrefix)
    return getSandboxOptions():getOptionByName(
        optionPrefix .. ".SprinterSpeedMultiplier"
    ):getValue()
end

local function readSprinterVariation(optionPrefix)
    return getSandboxOptions():getOptionByName(
        optionPrefix .. ".SprinterSpeedVariation"
    ):getValue()
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
        normal = readChance(optionPrefix, prefix .. "NormalChance"),
        tough = readChance(optionPrefix, prefix .. "ToughChance"),
        fragile = readChance(optionPrefix, prefix .. "FragileChance"),
    }, HEALTH_CHANCE_ORDER, "normal")
end

local function readConfig(optionPrefix)
    local config = normalizeChances({
        sprinter = readChance(optionPrefix, "SprinterChance"),
        fastShambler = readChance(optionPrefix, "FastShamblerChance"),
        shambler = readChance(optionPrefix, "ShamblerChance"),
        crawler = readChance(optionPrefix, "CrawlerChance"),
    }, SPEED_TYPES, "fastShambler")

    config.sprinterSpeedMultiplier = readSprinterMultiplier(optionPrefix)
    config.sprinterSpeedVariation = readSprinterVariation(optionPrefix)
    config.health = {}
    for _, speedType in ipairs(SPEED_TYPES) do
        config.health[speedType] = readHealthChances(
            optionPrefix,
            speedType:gsub("^%l", string.upper)
        )
    end

    return config
end

local function readWeatherSettings()
    return {
        rain = readBoolean(WEATHER_ID, "Rain"),
        fog = readBoolean(WEATHER_ID, "Fog"),
        snow = readBoolean(WEATHER_ID, "Snow"),
    }
end

local function getConfigSignature(config)
    local values = {}

    for _, speedType in ipairs(SPEED_TYPES) do
        values[#values + 1] = config[speedType]
    end
    values[#values + 1] = config.sprinterSpeedMultiplier
    values[#values + 1] = config.sprinterSpeedVariation

    for _, speedType in ipairs(SPEED_TYPES) do
        local health = config.health[speedType]
        values[#values + 1] = health.fragile
        values[#values + 1] = health.normal
        values[#values + 1] = health.tough
    end

    return table.concat(values, ":")
end

local function isWeatherActive(settings)
    if not settings.rain and not settings.fog and not settings.snow then
        return false
    end
    local climate = getClimateManager()
    local rain = climate:getPrecipitationIntensity() > 0
    local fog = climate:getFogIntensity() > 0
    local snow = climate:getSnowStrength() > 0
    return settings.rain and rain or settings.fog and fog or settings.snow and snow
end

local function getCurrentPeriod()
    return getGameTime():isNight() and NIGHT_PERIOD or DAY_PERIOD
end

local function getOptionPrefix(period)
    return period == NIGHT_PERIOD and NIGHT_ID or DAY_ID
end

local function readProfile(period, optionPrefix, signatureSuffix)
    local config = readConfig(optionPrefix)
    local signature = period .. ":" .. getConfigSignature(config)
        .. (signatureSuffix or "")
    return period, config, signature
end

local function getEffectiveProfile()
    local weatherSettings = readWeatherSettings()
    if isWeatherActive(weatherSettings) then
        return readProfile(
            WEATHER_PERIOD,
            WEATHER_ID,
            ":" .. tostring(weatherSettings.rain)
                .. ":" .. tostring(weatherSettings.fog)
                .. ":" .. tostring(weatherSettings.snow)
        )
    end

    local period = getCurrentPeriod()
    return readProfile(period, getOptionPrefix(period))
end

local function rollZombieHealth(chances)
    local roll = ZombRand(100)
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
    local roll = ZombRand(100)
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

local function rollSprinterMultiplier(config, speedType)
    local multiplier = config.sprinterSpeedMultiplier
    local variation = config.sprinterSpeedVariation
    if speedType ~= "sprinter" or variation <= 0 then
        return multiplier
    end

    return ZombRandFloat(
        math.max(MIN_SPRINTER_MULTIPLIER, multiplier - variation),
        math.min(MAX_SPRINTER_MULTIPLIER, multiplier + variation)
    )
end

local function clearPendingReroll(modData)
    modData[PENDING_SPEED_TAG] = nil
    modData[PENDING_SPRINTER_MULTIPLIER_TAG] = nil
    modData[PENDING_HEALTH_TAG] = nil
    modData[PENDING_PERIOD_TAG] = nil
end

local function queuePendingState(zombie, period, speedType, multiplier, health)
    local modData = zombie:getModData()
    modData[PENDING_SPEED_TAG] = speedType
    modData[PENDING_SPRINTER_MULTIPLIER_TAG] = multiplier
    modData[PENDING_HEALTH_TAG] = health
    modData[PENDING_PERIOD_TAG] = period
end

local function queueIdentifiedServerState(zombie, state, onlineID)
    state.id = onlineID
    zombie:transmitModData()
    queuedServerStates[#queuedServerStates + 1] = state
end

local function queueServerState(zombie, period, speedType, multiplier, health)
    if not isServer() then return end

    local onlineID = tonumber(zombie:getOnlineID())
    local state = {
        period = period,
        speedType = speedType,
        multiplier = multiplier,
        baseSpeed = tonumber(zombie:getModData()[SPRINTER_BASE_SPEED_TAG]),
        health = health,
        reroll = rerollRevision,
    }

    if not onlineID or onlineID < 0 then
        pendingServerStates[zombie] = state
        return
    end

    pendingServerStates[zombie] = nil
    queueIdentifiedServerState(zombie, state, onlineID)
end

local function flushServerStates()
    if #queuedServerStates == 0 then return end

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

local function applyZombieState(zombie, period, speedType, multiplier, health)
    local modData = zombie:getModData()
    local gettingUp = zombie:getCurrentActionContextStateName() == "getup"

    if gettingUp or (speedType ~= "crawler" and zombie:isCrawling()) then
        queuePendingState(zombie, period, speedType, multiplier, health)
        if not gettingUp then
            RandomZeds.setCrawlerState(zombie, false)
        end
        pendingStandUps[zombie] = true
        return
    end

    pendingStandUps[zombie] = nil
    zombie:setVariable("RandomZedsSprinterSpeedScale", 0.8)

    if not RandomZeds.applyZombieSpeedType(zombie, speedType, multiplier) then
        return
    end
    if not RandomZeds.isZombieSpeedTypeApplied(zombie, speedType) then
        queuePendingState(zombie, period, speedType, multiplier, health)
        pendingStandUps[zombie] = true
        return
    end
    zombie:setHealth(health)
    modData[PERIOD_TAG] = period
    modData[SPEED_TAG] = speedType
    modData[SPRINTER_MULTIPLIER_TAG] = multiplier
    modData[HEALTH_TAG] = health
    modData[REROLL_TAG] = rerollRevision
    clearPendingReroll(modData)
    queueServerState(zombie, period, speedType, multiplier, health)
end

local function applyZombieType(zombie, config, period, allowCrawler)
    if not config then
        period, config = getEffectiveProfile()
    end

    local speedType = getRandomSpeedType(config, allowCrawler)
    local health = rollZombieHealth(config.health[speedType])
    local multiplier = rollSprinterMultiplier(config, speedType)
    applyZombieState(zombie, period, speedType, multiplier, health)
end

local function queueCrawlerReroll(zombie, config, period)
    local speedType = getRandomSpeedType(config, true)
    queuePendingState(
        zombie,
        period,
        speedType,
        rollSprinterMultiplier(config, speedType),
        rollZombieHealth(config.health[speedType])
    )
end

local function isPlayerNear(zombie, players)
    if not players then return false end

    for playerIndex = 0, players:size() - 1 do
        local player = players:get(playerIndex)
        if player and zombie:DistToSquared(player:getX(), player:getY())
                <= PROTECTION_RADIUS_SQUARED then
            return true
        end
    end

    return false
end

local function reconcileCell(cell, period, config, force, players)
    local zombies = cell:getZombieList()
    if not zombies then return end

    for zombieIndex = 0, zombies:size() - 1 do
        local zombie = zombies:get(zombieIndex)
        if zombie then
            local modData = zombie:getModData()
            if not zombie:isDead() and (force or modData[PERIOD_TAG] ~= period) then
                local playerNear = isPlayerNear(zombie, players)
                if playerNear and (zombie:isCrawling() or modData[SPEED_TAG] == "crawler") then
                    queueCrawlerReroll(zombie, config, period)
                else
                    applyZombieType(zombie, config, period, not playerNear)
                end
            end
        end
    end

    flushServerStates()
end

local function reconcileZombies(period, config, force)
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    local cell = getCell()
    if cell then
        reconcileCell(cell, period, config, force, players)
    end
end

local function applyPendingRerolls()
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    local pending = {}
    local cell = getCell()
    local zombies = cell and cell:getZombieList()
    if zombies then
        for zombieIndex = 0, zombies:size() - 1 do
            local zombie = zombies:get(zombieIndex)
            local modData = zombie and zombie:getModData()
            if zombie and not zombie:isDead() and modData and modData[PENDING_SPEED_TAG]
                    and not isPlayerNear(zombie, players) then
                pending[#pending + 1] = zombie
            end
        end
    end

    if #pending == 0 then return end
    rerollRevision = rerollRevision + 1
    for _, zombie in ipairs(pending) do
        local modData = zombie:getModData()
        applyZombieState(
            zombie,
            modData[PENDING_PERIOD_TAG] or getCurrentPeriod(),
            modData[PENDING_SPEED_TAG],
            tonumber(modData[PENDING_SPRINTER_MULTIPLIER_TAG]) or 1.0,
            tonumber(modData[PENDING_HEALTH_TAG]) or zombie:getHealth()
        )
    end
    flushServerStates()
end

local function processPendingZombieCreates()
    for zombie in pairs(pendingZombieCreates) do
        pendingZombieCreates[zombie] = nil
        if not zombie:isDead() and zombie:getSquare() then
            applyZombieType(zombie)
        end
    end
end

local function processPendingServerStates()
    for zombie, state in pairs(pendingServerStates) do
        local onlineID = tonumber(zombie:getOnlineID())
        if zombie:isDead() or not zombie:getSquare() then
            pendingServerStates[zombie] = nil
        elseif onlineID and onlineID >= 0 then
            pendingServerStates[zombie] = nil
            queueIdentifiedServerState(zombie, state, onlineID)
        end
    end
end

local function processPendingStandUps()
    local ready = {}
    for zombie in pairs(pendingStandUps) do
        if zombie:isDead() or not zombie:getSquare() then
            pendingStandUps[zombie] = nil
        elseif not zombie:isCrawling()
                and zombie:getCurrentActionContextStateName() ~= "getup" then
            pendingStandUps[zombie] = nil
            ready[#ready + 1] = zombie
        end
    end

    if #ready > 0 then
        rerollRevision = rerollRevision + 1
        for _, zombie in ipairs(ready) do
            local modData = zombie:getModData()
            local speedType = modData[PENDING_SPEED_TAG]
            if speedType then
                applyZombieState(
                    zombie,
                    modData[PENDING_PERIOD_TAG] or getCurrentPeriod(),
                    speedType,
                    tonumber(modData[PENDING_SPRINTER_MULTIPLIER_TAG]) or 1.0,
                    tonumber(modData[PENDING_HEALTH_TAG]) or zombie:getHealth()
                )
            end
        end
    end
end

local function applyPendingStandUps()
    processPendingZombieCreates()
    processPendingServerStates()
    processPendingStandUps()
    flushServerStates()
end

local function applyEffectiveProfile(period, config, signature)
    rerollRevision = rerollRevision + 1
    reconcileZombies(period, config, true)
    lastEffectiveMode = period
    lastEffectiveSignature = signature
end

local function updateEffectiveState()
    local period, config, signature = getEffectiveProfile()
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

    local period = getCurrentPeriod()
    local _, config, signature = readProfile(period, getOptionPrefix(period))
    applyEffectiveProfile(period, config, signature)
    applyPendingRerolls()
end

local function onZombieCreate(zombie)
    pendingZombieCreates[zombie] = true
end

local function initialize()
    if initialized then return end

    initialized = true
    Events.OnZombieCreate.Add(onZombieCreate)
    Events.OnWeatherPeriodStart.Add(updateEffectiveState)
    Events.OnWeatherPeriodStage.Add(updateEffectiveState)
    Events.OnWeatherPeriodComplete.Add(onWeatherPeriodComplete)
    Events.OnTick.Add(applyPendingStandUps)
    Events.EveryOneMinute.Add(updateEffectiveState)
    updateEffectiveState()
end

Events.OnGameStart.Add(initialize)
Events.OnServerStarted.Add(initialize)
