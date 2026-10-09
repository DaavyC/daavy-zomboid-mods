local phaseOptions = table.newarray(
    "NewMoon", "WaxingCrescent", "FirstQuarter", "WaxingGibbous",
    "FullMoon", "WaningGibbous", "ThirdQuarter", "WaningCrescent"
)
local moonlight = { phases = phaseOptions }
local ClimateMoon = ClimateMoon
local getClimateManager = getClimateManager
local getGameTime = getGameTime
local getSandboxOptions = getSandboxOptions
local sendServerCommand = sendServerCommand
local sendClientCommand = sendClientCommand
local print = print
local client = isClient()
local server = isServer()
local rainStages = {
    [1] = "WeatherLightRain", [2] = "WeatherHeavyRain",
    [5] = "WeatherLightRain", [6] = "WeatherLightRain",
}
local stageOverrides = {
    [3] = "WeatherHeavyRain", [4] = "Moon", [7] = "WeatherBlizzard",
    [8] = "WeatherHeavyRain", [9] = "Moon", [11] = "WeatherHeavyRain",
}
local weatherOptions = {
    WeatherSnow = true, WeatherCloudsFog = true, WeatherLightRain = true,
    WeatherBlizzard = true, WeatherHeavyRain = true,
}
local moon
local climate
local time
local season
local phaseDate
local weatherPeriod
local nightDarkness
local lastPhase
local lastDebug
local lastSource
local serverSource = "Moon"

local function configuredDarkness(settings, optionName)
    local darkness = settings[optionName]
    if type(darkness) ~= "number" or darkness % 1 ~= 0 or darkness < 1 or darkness > 4 then
        error("[MoonlightPhases] Invalid MoonlightPhases." .. optionName .. ": " .. tostring(darkness))
    end
    return darkness
end

local function periodCategory()
    if not weatherPeriod then
        weatherPeriod = climate:getWeatherPeriod()
    end
    if not weatherPeriod:isRunning() then return nil, -1 end
    local stage = weatherPeriod:getCurrentStageID()
    local category = stageOverrides[stage]
    if category then return category, stage end
    if weatherPeriod:isBlizzard() then return "WeatherBlizzard", stage end
    if weatherPeriod:isThunderStorm() or weatherPeriod:isTropicalStorm() then
        return "WeatherHeavyRain", stage
    end
    return nil, stage
end

local function weatherCategory()
    local category, stage = periodCategory()
    if category then return category end
    local precipitation = climate:getPrecipitationIntensity()
    local rain = rainStages[stage]
    if (precipitation > 0 or rain) and climate:getPrecipitationIsSnow() then return "WeatherSnow" end
    if rain then return rain end
    if precipitation >= 0.5 then return "WeatherHeavyRain" end
    if precipitation > 0 then return "WeatherLightRain" end
    if climate:getFogIntensity() > 0 or climate:getCloudIntensity() >= 0.5 then return "WeatherCloudsFog" end
    return "Moon"
end

local function updateMoon()
    moonlight.beforeDawn = time:getTimeOfDay() < season:getDawn()
    local day = moonlight.beforeDawn and climate:getPreviousDay() or climate:getCurrentDay()
    local date = day:getDateValue()
    if date == phaseDate then return end
    moon:updatePhase(day:getYear(), day:getMonth(), day:getDay())
    moonlight.phase = moon:getCurrentMoonPhase()
    phaseDate = date
end

local function lightingFor(settings, phase, source)
    local darkness = configuredDarkness(settings, phaseOptions[phase + 1])
    if source ~= "Moon" then
        local weatherDarkness = configuredDarkness(settings, source)
        if weatherDarkness < darkness then return weatherDarkness, source end
    end
    return darkness
end

local function applyLighting(settings, phase, source)
    local previousDarkness = nightDarkness:getValue()
    local previousWeather = moonlight.weather
    local darkness, weather = lightingFor(settings, phase, source)
    if previousDarkness ~= darkness then nightDarkness:setValue(darkness) end
    SandboxVars.NightDarkness = darkness
    moonlight.weather = weather
    if settings.Debug and (phase ~= lastPhase or source ~= lastSource or weather ~= previousWeather or darkness ~= previousDarkness or not lastDebug) then
        print("[MoonlightPhases][Debug]", moon:getPhaseName(), "Weather", source, "Source", weather or "Moon", "NightDarkness", previousDarkness, "->", darkness)
    end
    lastPhase = phase
    lastDebug = settings.Debug
end

local function updateLighting()
    if not moon then
        moon = ClimateMoon.new()
        climate = getClimateManager()
        time = getGameTime()
        season = climate:getSeason()
        nightDarkness = getSandboxOptions():getOptionByName("NightDarkness")
    end
    updateMoon()
    local settings = SandboxVars.MoonlightPhases
    local phase = moonlight.phase
    local source = "Moon"
    if settings.WeatherEnabled then source = client and serverSource or weatherCategory() end
    applyLighting(settings, phase, source)
    if server and source ~= lastSource then
        sendServerCommand("MoonlightPhases", "Weather", { source = source })
    end
    lastSource = source
end

local function receiveWeather(module, command, arguments)
    if module ~= "MoonlightPhases" or command ~= "Weather" then return end
    if type(arguments) ~= "table" or (arguments.source ~= "Moon" and not weatherOptions[arguments.source]) then
        error("[MoonlightPhases] Invalid weather source from server")
    end
    serverSource = arguments.source
    updateLighting()
end

local function requestWeather()
    if SandboxVars.MoonlightPhases.WeatherEnabled then sendClientCommand("MoonlightPhases", "Weather", {}) end
end

local function sendWeather(module, command, player)
    if module ~= "MoonlightPhases" or command ~= "Weather" then return end
    sendServerCommand(player, "MoonlightPhases", "Weather", { source = lastSource or "Moon" })
end

Events.OnClimateTick.Add(updateLighting)
Events.OnGameStart.Add(updateLighting)
if client then
    Events.OnServerCommand.Add(receiveWeather)
    Events.OnGameStart.Add(requestWeather)
elseif server then
    Events.OnClientCommand.Add(sendWeather)
end
return moonlight
