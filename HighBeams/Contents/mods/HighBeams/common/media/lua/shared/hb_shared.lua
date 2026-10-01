local Beams = {}
local frontIds = table.newarray("HeadlightLeft", "HeadlightRight")
local tonumber = tonumber
local type = type
local abs = math.abs
local print = print
local getSandboxOptions = getSandboxOptions

function Beams.debugLog(...)
    local option = getSandboxOptions():getOptionByName("HighBeams.Debug")
    if option and option:getValue() == true then print("[HighBeams][Debug]", ...) end
end

function Beams.anchor(vehicle)
    return vehicle:getPartById(frontIds[1]) or vehicle:getPartById(frontIds[2])
end

function Beams.isHigh(vehicle)
    local anchor = Beams.anchor(vehicle)
    return anchor ~= nil and anchor:getModData().HighBeams == true
end

local function captureBaseline(part)
    local conditionFactor = 0.5 + part:getCondition() / 200
    local params = part:getTable("headlight") or {}
    local xOffset = tonumber(params.xOffset) or 0.5
    if part:getId() == frontIds[2] then xOffset = -xOffset end
    return {
        distance = part:getLightDistance() / conditionFactor,
        intensity = part:getLightIntensity() / conditionFactor,
        xOffset = xOffset,
        yOffset = tonumber(params.yOffset) or 2,
        dot = tonumber(params.dot) or 0.75,
        focusing = part:getLight():getFocusing(),
    }
end

function Beams.selectMode(vehicle, selection)
    for index = 1, #frontIds do
        local part = vehicle:getPartById(frontIds[index])
        if part and part:getLight() then
            local partData = part:getModData()
            if not partData.HighBeamsBase then partData.HighBeamsBase = captureBaseline(part) end
            vehicle:transmitPartModData(part)
        end
    end
    local anchor = Beams.anchor(vehicle)
    anchor:getModData().HighBeams = selection.high
    vehicle:transmitPartModData(anchor)
    if selection.high then vehicle:setHeadlightsOn(true) end
    Beams.debugLog("Mode saved", "vehicle", vehicle:getId(), "high", selection.high)
end

local function multiplier(option, fallback, maximum)
    if type(option) ~= "number" or option ~= option then return fallback end
    if option < 1 then return 1 end
    if option > maximum then return maximum end
    return option
end

function Beams.settings()
    local options = getSandboxOptions()
    local distance = options:getOptionByName("HighBeams.DistanceMultiplier")
    local brightness = options:getOptionByName("HighBeams.BrightnessMultiplier")
    local debug = options:getOptionByName("HighBeams.Debug")
    return {
        distance = multiplier(distance and distance:getValue(), 2, 10),
        brightness = multiplier(brightness and brightness:getValue(), 1.5, 5),
        debug = debug ~= nil and debug:getValue() == true,
    }
end

local function applyPart(part, distanceMultiplier, brightnessMultiplier)
    local baseline = part:getModData().HighBeamsBase
    if not baseline or not part:getLight() then return end
    local conditionFactor = 0.5 + part:getCondition() / 200
    local distance = baseline.distance * distanceMultiplier
    local intensity = baseline.intensity * brightnessMultiplier
    if abs(part:getLightDistance() - distance * conditionFactor) < 0.0001 + distance * 0.000001
        and abs(part:getLightIntensity() - intensity * conditionFactor) < 0.0001 then return end
    part:createSpotLight(baseline.xOffset, baseline.yOffset, distance, intensity, baseline.dot, baseline.focusing)
    Beams.debugLog("Headlight updated", "vehicle", part:getVehicle():getId(), "part", part:getId(),
        "distance", distance, "intensity", intensity)
end

function Beams.apply(vehicle, settings)
    local anchor = Beams.anchor(vehicle)
    if not anchor then return end
    local partData = anchor:getModData()
    if partData.HighBeams == nil then return end
    local distanceMultiplier, brightnessMultiplier = 1, 1
    if partData.HighBeams == true then
        distanceMultiplier, brightnessMultiplier = settings.distance, settings.brightness
    end
    for index = 1, #frontIds do
        local part = vehicle:getPartById(frontIds[index])
        if part then applyPart(part, distanceMultiplier, brightnessMultiplier) end
    end
end

return Beams
