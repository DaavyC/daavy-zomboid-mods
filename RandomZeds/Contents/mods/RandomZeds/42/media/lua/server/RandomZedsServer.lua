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
local HEALTH_TAG = "RandomZedsHealth"
local REROLL_TAG = "RandomZedsReroll"
local PENDING_SPEED_TAG = "RandomZedsPendingSpeedType"
local PENDING_SPRINTER_MULTIPLIER_TAG = "RandomZedsPendingSprinterMultiplier"
local PENDING_HEALTH_TAG = "RandomZedsPendingHealth"
local PENDING_PERIOD_TAG = "RandomZedsPendingPeriod"
local PROTECTION_RADIUS_SQUARED = 50 * 50
local STATE_BATCH_SIZE = 16
local initialized = false
local lastEffectiveMode
local lastEffectiveSignature
local rerollRevision = 0
local queuedServerStates = {}

local function readChance(optionPrefix, name)
    local option = getSandboxOptions():getOptionByName(optionPrefix .. "." .. name)
    local value = tonumber(option and option:getValue()) or 0
    return math.max(0, math.min(100, math.floor(value)))
end

local function readBoolean(optionPrefix, name)
    local option = getSandboxOptions():getOptionByName(optionPrefix .. "." .. name)
    local value = option and option:getValue()
    return value == true or tostring(value):lower() == "true"
end

local function readSprinterMultiplier(optionPrefix)
    local option = getSandboxOptions():getOptionByName(optionPrefix .. ".SprinterSpeedMultiplier")
    local value = tonumber(option and option:getValue()) or 1.0
    return math.max(0.5, math.min(1.5, value))
end

local function readHealthChances(optionPrefix, prefix)
    local normal = readChance(optionPrefix, prefix .. "NormalChance")
    local tough = readChance(optionPrefix, prefix .. "ToughChance")
    local fragile = readChance(optionPrefix, prefix .. "FragileChance")
    local remaining = 100

    normal = math.min(normal, remaining)
    remaining = remaining - normal
    tough = math.min(tough, remaining)
    remaining = remaining - tough
    fragile = math.min(fragile, remaining)
    remaining = remaining - fragile

    normal = normal + remaining

    return {
        fragile = fragile,
        normal = normal,
        tough = tough,
    }
end

local function readConfig(optionPrefix)
    local sprinter = readChance(optionPrefix, "SprinterChance")
    local fastShambler = readChance(optionPrefix, "FastShamblerChance")
    local shambler = readChance(optionPrefix, "ShamblerChance")
    local crawler = readChance(optionPrefix, "CrawlerChance")
    local remaining = 100

    sprinter = math.min(sprinter, remaining)
    remaining = remaining - sprinter
    fastShambler = math.min(fastShambler, remaining)
    remaining = remaining - fastShambler
    shambler = math.min(shambler, remaining)
    remaining = remaining - shambler
    crawler = math.min(crawler, remaining)
    remaining = remaining - crawler

    fastShambler = fastShambler + remaining

    return {
        crawler = crawler,
        shambler = shambler,
        fastShambler = fastShambler,
        sprinter = sprinter,
        sprinterSpeedMultiplier = readSprinterMultiplier(optionPrefix),
        health = {
            crawler = readHealthChances(optionPrefix, "Crawler"),
            shambler = readHealthChances(optionPrefix, "Shambler"),
            fastShambler = readHealthChances(optionPrefix, "FastShambler"),
            sprinter = readHealthChances(optionPrefix, "Sprinter"),
        },
    }
end

local function readWeatherSettings()
    return {
        rain = readBoolean(WEATHER_ID, "Rain"),
        fog = readBoolean(WEATHER_ID, "Fog"),
        snow = readBoolean(WEATHER_ID, "Snow"),
    }
end

local function getConfigSignature(config)
    local values = {
        config.crawler,
        config.shambler,
        config.fastShambler,
        config.sprinter,
        config.sprinterSpeedMultiplier,
    }

    for _, speedType in ipairs({ "crawler", "shambler", "fastShambler", "sprinter" }) do
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
    if not getClimateManager then
        return false
    end

    local ok, active = pcall(function()
        local climate = getClimateManager()
        if not climate then return false end

        local rain = (tonumber(climate:getPrecipitationIntensity()) or 0) > 0
        local fog = (tonumber(climate:getFogIntensity()) or 0) > 0
        local snow = (tonumber(climate:getSnowStrength()) or 0) > 0
        return settings.rain and rain or settings.fog and fog or settings.snow and snow
    end)

    return ok and active == true
end

local function getCurrentPeriod()
    return getGameTime():isNight() and NIGHT_PERIOD or DAY_PERIOD
end

local function getOptionPrefix(period)
    return period == NIGHT_PERIOD and NIGHT_ID or DAY_ID
end

local function getEffectiveProfile()
    local weatherSettings = readWeatherSettings()
    if isWeatherActive(weatherSettings) then
        local config = readConfig(WEATHER_ID)
        local signature = WEATHER_PERIOD .. ":" .. getConfigSignature(config)
            .. ":" .. tostring(weatherSettings.rain)
            .. ":" .. tostring(weatherSettings.fog)
            .. ":" .. tostring(weatherSettings.snow)
        return WEATHER_PERIOD, config, signature
    end

    local period = getCurrentPeriod()
    local config = readConfig(getOptionPrefix(period))
    return period, config, period .. ":" .. getConfigSignature(config)
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
    if roll < config.sprinter then
        return "sprinter"
    elseif roll < config.sprinter + config.fastShambler then
        return "fastShambler"
    elseif roll < config.sprinter + config.fastShambler + config.shambler then
        return "shambler"
    elseif allowCrawler ~= false then
        return "crawler"
    else
        return "fastShambler"
    end
end

local function clearPendingReroll(modData)
    modData[PENDING_SPEED_TAG] = nil
    modData[PENDING_SPRINTER_MULTIPLIER_TAG] = nil
    modData[PENDING_HEALTH_TAG] = nil
    modData[PENDING_PERIOD_TAG] = nil
end

local function queueServerState(zombie, period, speedType, multiplier, health)
    if not isServer() then return end

    local onlineID = tonumber(zombie:getOnlineID())
    if not onlineID or onlineID < 0 then return end

    queuedServerStates[#queuedServerStates + 1] = {
        id = onlineID,
        period = period,
        speedType = speedType,
        multiplier = multiplier,
        health = health,
        reroll = rerollRevision,
    }
end

local function flushServerStates()
    if #queuedServerStates == 0 then return end

    for first = 1, #queuedServerStates, STATE_BATCH_SIZE do
        local states = {}
        local last = math.min(first + STATE_BATCH_SIZE - 1, #queuedServerStates)
        for index = first, last do
            states[#states + 1] = queuedServerStates[index]
        end
        pcall(function()
            sendServerCommand(COMMAND_MODULE, STATE_COMMAND, { states = states })
        end)
    end

    queuedServerStates = {}
end

local function applyZombieState(zombie, period, speedType, multiplier, health)
    local modData = zombie:getModData()
    zombie:setVariable("RandomZedsSprinterSpeedScale", 0.8)

    if speedType == "sprinter" then
        RandomZeds.setCrawlerState(zombie, false)
        zombie:doSprinter()
        RandomZeds.setZombieWalkType(zombie, speedType)
        RandomZeds.applySprinterSpeed(zombie, multiplier)
    elseif speedType == "fastShambler" then
        RandomZeds.setCrawlerState(zombie, false)
        zombie:doFastShambler()
        RandomZeds.setZombieWalkType(zombie, speedType)
    elseif speedType == "shambler" then
        RandomZeds.setCrawlerState(zombie, false)
        zombie:doShambler()
        RandomZeds.setZombieWalkType(zombie, speedType)
    else
        RandomZeds.setCrawlerState(zombie, true)
        zombie:doCrawlerSpeed(3)
        RandomZeds.setZombieWalkType(zombie, speedType)
    end

    zombie:setHealth(health)
    modData[PERIOD_TAG] = period
    modData[SPEED_TAG] = speedType
    modData[SPRINTER_MULTIPLIER_TAG] = multiplier
    modData[HEALTH_TAG] = health
    modData[REROLL_TAG] = rerollRevision
    clearPendingReroll(modData)
    zombie:update()
    zombie:transmitModData()
    queueServerState(zombie, period, speedType, multiplier, health)
end

local function applyZombieType(zombie, config, period, allowCrawler)
    if not config then
        period, config = getEffectiveProfile()
    end

    local speedType = getRandomSpeedType(config, allowCrawler)
    local health = rollZombieHealth(config.health[speedType])
    applyZombieState(zombie, period, speedType, config.sprinterSpeedMultiplier, health)
end

local function queueCrawlerReroll(zombie, config, period)
    local speedType = getRandomSpeedType(config, true)
    local modData = zombie:getModData()
    modData[PENDING_SPEED_TAG] = speedType
    modData[PENDING_SPRINTER_MULTIPLIER_TAG] = config.sprinterSpeedMultiplier
    modData[PENDING_HEALTH_TAG] = rollZombieHealth(config.health[speedType])
    modData[PENDING_PERIOD_TAG] = period
end

local function isPlayerNear(zombie, players)
    if not players then return false end

    local zombieX = zombie:getX()
    local zombieY = zombie:getY()
    for playerIndex = 0, players:size() - 1 do
        local player = players:get(playerIndex)
        if player then
            local dx = player:getX() - zombieX
            local dy = player:getY() - zombieY
            if dx * dx + dy * dy <= PROTECTION_RADIUS_SQUARED then
                return true
            end
        end
    end

    return false
end

local function reconcileCell(cell, period, config, force, players)
    local zombies = cell:getZombieList()
    if not zombies then return 0, 0 end

    local found = 0
    local rerolled = 0
    for zombieIndex = 0, zombies:size() - 1 do
        local zombie = zombies:get(zombieIndex)
        if zombie then
            found = found + 1
            local modData = zombie:getModData()
            if not zombie:isDead() and (force or modData[PERIOD_TAG] ~= period) then
                local playerNear = isPlayerNear(zombie, players)
                if playerNear and (zombie:isCrawling() or modData[SPEED_TAG] == "crawler") then
                    queueCrawlerReroll(zombie, config, period)
                else
                    applyZombieType(zombie, config, period, not playerNear)
                    rerolled = rerolled + 1
                end
            end
        end
    end

    flushServerStates()
    return found, rerolled
end

local function getLoadedCells(players)
    local cells = {}
    local seenCells = {}
    local function addCell(cell)
        if cell and not seenCells[cell] then
            seenCells[cell] = true
            cells[#cells + 1] = cell
        end
    end

    if players then
        for playerIndex = 0, players:size() - 1 do
            local player = players:get(playerIndex)
            addCell(player and player:getCell())
        end
    end

    addCell(getCell())
    return cells
end

local function reconcileZombies(period, config, force)
    local found = 0
    local rerolled = 0
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    for _, cell in ipairs(getLoadedCells(players)) do
        local cellFound, cellRerolled = reconcileCell(cell, period, config, force, players)
        found = found + cellFound
        rerolled = rerolled + cellRerolled
    end

    return players and players:size() or 0, found, rerolled
end

local function applyPendingRerolls()
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    local pending = {}
    for _, cell in ipairs(getLoadedCells(players)) do
        local zombies = cell:getZombieList()
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
    end

    if #pending == 0 then return 0 end
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
    return #pending
end

local function applyEffectiveProfile(period, config, signature)
    rerollRevision = rerollRevision + 1
    reconcileZombies(period, config, true)
    lastEffectiveMode = period
    lastEffectiveSignature = signature
end

local function updateEffectiveState(force)
    local period, config, signature = getEffectiveProfile()
    local changed = force or period ~= lastEffectiveMode or signature ~= lastEffectiveSignature
    if changed then
        applyEffectiveProfile(period, config, signature)
    end

    applyPendingRerolls()
    return changed
end

local function updateSettings()
    updateEffectiveState(false)
end

local function updatePeriod()
    updateEffectiveState(false)
end

local function onWeatherPeriodStart()
    updateEffectiveState(false)
end

local function onWeatherPeriodStage()
    updateEffectiveState(false)
end

local function onWeatherPeriodComplete()
    if lastEffectiveMode ~= WEATHER_PERIOD then
        updateEffectiveState(false)
        return
    end

    local period = getCurrentPeriod()
    local config = readConfig(getOptionPrefix(period))
    applyEffectiveProfile(period, config, period .. ":" .. getConfigSignature(config))
    applyPendingRerolls()
end

local function onZombieCreate(zombie)
    applyZombieType(zombie)
    flushServerStates()
end

local function initialize()
    if initialized then return end

    initialized = true
    Events.OnZombieCreate.Add(onZombieCreate)
    Events.OnWeatherPeriodStart.Add(onWeatherPeriodStart)
    Events.OnWeatherPeriodStage.Add(onWeatherPeriodStage)
    Events.OnWeatherPeriodComplete.Add(onWeatherPeriodComplete)
    Events.EveryOneMinute.Add(updateSettings)
    Events.EveryTenMinutes.Add(updatePeriod)
    updateEffectiveState(false)
end

Events.OnGameStart.Add(initialize)
Events.OnServerStarted.Add(initialize)
