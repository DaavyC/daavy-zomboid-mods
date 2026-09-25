local Config = {}

local RandomZeds = require "rz_shared"
local SPEED_TYPES = RandomZeds.SPEED_TYPES

local DAY_ID = "RandomZeds"
local NIGHT_ID = "RandomZedsNight"
local WEATHER_ID = "RandomZedsWeather"
local MAIN_ID = "RandomZedsMain"
local DAY_PERIOD = "Day"
local NIGHT_PERIOD = "Night"
local WEATHER_PERIOD = "Weather"
local DISABLED_PERIOD = "Disabled"

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

local function readOption(options, optionPrefix, name)
    local fullName = optionPrefix .. "." .. name
    local option = options and options:getOptionByName(fullName)
    if not option then
        return nil
    end
    return option:getValue()
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

local function readProfileChances(options, optionPrefix, prefix, profileName)
    local definition = PROFILE_DEFINITIONS[profileName]
    local chances = {}
    for index = 1, #definition.levels do
        local level = definition.levels[index]
        chances[level] = readOption(
            options,
            optionPrefix,
            prefix .. definition.optionSuffixes[level]
        )
    end
    return normalizeChances(chances, definition.levels, definition.remainder)
end

local function readProfileTables(options, optionPrefix, profileNames)
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
                options, optionPrefix, prefix, profileName)
        end
    end
    return profiles
end

local function readConfig(optionPrefix)
    local options = getSandboxOptions and getSandboxOptions()
    local config = normalizeChances({
        sprinter = readOption(options, optionPrefix, "SprinterChance"),
        fastShambler = readOption(options, optionPrefix, "FastShamblerChance"),
        shambler = readOption(options, optionPrefix, "ShamblerChance"),
        crawler = readOption(options, optionPrefix, "CrawlerChance"),
    }, SPEED_TYPES, "fastShambler")

    config.sprinterSpeedMultiplier = tonumber(
        readOption(options, optionPrefix, "SprinterSpeedMultiplier")) or 1.0
    config.sprinterSpeedVariationDecrease = tonumber(
        readOption(options, optionPrefix, "SprinterSpeedVariationDecrease")) or 0
    config.sprinterSpeedVariationIncrease = tonumber(
        readOption(options, optionPrefix, "SprinterSpeedVariationIncrease")) or 0
    config.featuresEnabled = RandomZeds.hasSynapseFeatureSupport()
    for index = 1, #ALL_PROFILE_NAMES do
        local profileName = ALL_PROFILE_NAMES[index]
        config[profileName] = {}
    end
    local profileNames = BASE_PROFILE_NAMES
    if config.featuresEnabled then
        profileNames = ALL_PROFILE_NAMES
    end
    local profileTables = readProfileTables(options, optionPrefix, profileNames)
    for index = 1, #profileNames do
        local profileName = profileNames[index]
        config[profileName] = profileTables[profileName]
    end

    return config
end

local function readWeatherSettings()
    local options = getSandboxOptions and getSandboxOptions()
    return {
        rain = readOption(options, WEATHER_ID, "Rain") == true,
        fog = readOption(options, WEATHER_ID, "Fog") == true,
        snow = readOption(options, WEATHER_ID, "Snow") == true,
    }
end

local function getConfigSignature(config)
    local values = table.newarray()

    for index = 1, #SPEED_TYPES do
        local speedType = SPEED_TYPES[index]
        values[#values + 1] = config[speedType]
    end
    values[#values + 1] = config.sprinterSpeedMultiplier
    values[#values + 1] = config.sprinterSpeedVariationDecrease
    values[#values + 1] = config.sprinterSpeedVariationIncrease

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
                values[#values + 1] = profile[levels[levelIndex]]
            end
        end
    end

    values[#values + 1] = config.featuresEnabled and "synapse" or "legacy"
    return table.concat(values, ":")
end

local function isWeatherActive(settings)
    if not settings.rain and not settings.fog and not settings.snow then
        return false
    end
    local climate = getClimateManager and getClimateManager()
    if not climate then return false end
    if settings.rain and climate:getPrecipitationIntensity() > 0 then
        return true
    end
    if settings.fog and climate:getFogIntensity() > 0 then
        return true
    end
    return settings.snow and climate:getSnowStrength() > 0 or false
end

local function readSeasonStart(options, optionName, fallback)
    local option = options and options:getOptionByName(optionName)
    if not option then
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
        options,
        seasonOptionPrefix .. "DayStart",
        defaults.dayStart
    )
    local nightStart = readSeasonStart(
        options,
        seasonOptionPrefix .. "NightStart",
        defaults.nightStart
    )
    return seasonName, defaults, dayStart, nightStart
end

local function getExclusivePeriod(dayEnabled, nightEnabled)
    if dayEnabled and not nightEnabled then
        return DAY_PERIOD
    end
    if not dayEnabled and nightEnabled then
        return NIGHT_PERIOD
    end
    if not dayEnabled and not nightEnabled then
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
    if period == DISABLED_PERIOD then
        return period, nil, period
    end
    return readProfile(period, getOptionPrefix(period), "")
end

Config.WEATHER_PERIOD = WEATHER_PERIOD
Config.DISABLED_PERIOD = DISABLED_PERIOD
Config.FEATURE_PROFILE_NAMES = FEATURE_PROFILE_NAMES
Config.PROFILE_DEFINITIONS = PROFILE_DEFINITIONS
Config.getCurrentPeriod = getCurrentPeriod
Config.getOptionPrefix = getOptionPrefix
Config.readProfile = readProfile
Config.getEffectiveProfile = getEffectiveProfile

return Config
