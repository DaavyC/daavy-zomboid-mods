require "ISUI/ISRadialMenu"
local Beams = require "hb_shared"
local getCell = getCell
local sendClientCommand = sendClientCommand
local getText = getText
local getTexture = getTexture
local select = select
local cell
local ticks = 0
local radialHooked = false
local lastSettings

local function selectMode(player)
    local vehicle = player:getVehicle()
    if not vehicle or not vehicle:isDriver(player) then return end
    local selection = {
        vehicle = vehicle:getId(),
        high = not vehicle:getHeadlightsOn() or not Beams.isHigh(vehicle),
    }
    Beams.debugLog("Mode requested", "vehicle", selection.vehicle, "high", selection.high)
    sendClientCommand(player, "HighBeams", "selectMode", selection)
end

local function addBeamSlice(menu, player)
    local vehicle = player and player:getVehicle()
    if not vehicle or not vehicle:isDriver(player) or not Beams.anchor(vehicle) then return end
    local label = "UI_HighBeams_Enable"
    local icon = "media/ui/HighBeams/high_beams_inactive.png"
    if vehicle:getHeadlightsOn() and Beams.isHigh(vehicle) then
        label = "UI_HighBeams_Disable"
        icon = "media/ui/HighBeams/high_beams_active.png"
    end
    menu:addSlice(getText(label), getTexture(icon), selectMode, player)
    Beams.debugLog("Radial option added", "vehicle", vehicle:getId(), "label", label)
end

local function installRadialHook()
    if radialHooked then return end
    local originalAddSlice = ISRadialMenu.addSlice
    ISRadialMenu.addSlice = function(menu, text, texture, ...)
        originalAddSlice(menu, text, texture, ...)
        if text == getText("ContextMenu_VehicleHeadlightsOn")
            or text == getText("ContextMenu_VehicleHeadlightsOff") then
            addBeamSlice(menu, select(2, ...))
        end
    end
    radialHooked = true
    Beams.debugLog("Radial hook installed")
end

local function applyLoadedVehicles(settings)
    if not cell then return end
    local iterator = cell:getVehicles():iterator()
    while iterator:hasNext() do Beams.apply(iterator:next(), settings) end
end

local function refreshSettings()
    local settings = Beams.settings()
    if not lastSettings or settings.distance ~= lastSettings.distance
        or settings.brightness ~= lastSettings.brightness or settings.debug ~= lastSettings.debug then
        Beams.debugLog("Sandbox settings updated", "distance", settings.distance,
            "brightness", settings.brightness, "debug", settings.debug)
        lastSettings = settings
    end
    applyLoadedVehicles(settings)
end

local function onTick()
    ticks = ticks + 1
    if ticks < 15 then return end
    ticks = 0
    refreshSettings()
end

local function onGameStart()
    installRadialHook()
    cell = getCell()
    lastSettings = nil
    Beams.debugLog("Client started")
    refreshSettings()
end

Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
