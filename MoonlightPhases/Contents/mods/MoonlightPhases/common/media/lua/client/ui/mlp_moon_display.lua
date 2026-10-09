require "ISUI/ISPanel"
require "ISUI/ISToolTip"

local moonlight = require "mlp_shared"
local phaseNames = moonlight.phases
local MoonDisplay = ISPanel:derive("MLPMoonDisplay")
local UIManager = UIManager
local getTimestampMs = getTimestampMs
local getText = getText
local getTexture = getTexture
local display

local function updateReveal()
    if not display then return end
    local settings = SandboxVars.MoonlightPhases
    if not settings.InterfaceEnabled then return end
    local hours = settings.RevealHours
    display.revealHours = hours
    display.revealed = hours < 0 or moonlight.beforeDawn or display.time:getTimeOfDay() >= display.climate:getSeason():getDusk() - hours
end

local function prepareDisplay()
    if not display then return end
    local settings = SandboxVars.MoonlightPhases
    if settings.InterfaceEnabled and (settings.RevealHours ~= display.revealHours or not display.interfaceEnabled) then
        updateReveal()
    end
    display.interfaceEnabled = settings.InterfaceEnabled
    local visible = settings.InterfaceEnabled and display.revealed and display.clock:isVisible()
    if visible == display.shown then return end
    display.shown = visible
    if visible then
        display.nextUpdate = 0
        display:update()
    else
        display.tooltip:setVisible(false)
        display.hovered = false
    end
    display:setVisible(visible)
end

local function updatePhase(self)
    local phase = moonlight.phase
    local weather = moonlight.weather
    if phase == self.phase and weather == self.weather then return end
    self.phase = phase
    self.weather = weather
    self.tooltip:setName(getText("Sandbox_MoonlightPhases_" .. (weather or phaseNames[phase + 1])))
    self.tooltip:setDescription(getText(weather and "UI_MoonlightPhases_Weather" or "UI_MoonlightPhases_Tonight"))
end

local function positionDisplay(self)
    local size = self.clock:getHeight()
    local x = self.clock:getX() - size - 4
    local y = self.clock:getY()
    if size == self.width and x == self.x and y == self.y then return end
    if size ~= self.width then
        self:setWidth(size)
        self:setHeight(size)
        self.iconOffset = size * 0.18
        self.iconSize = size * 0.64
    end
    if x ~= self.x then self:setX(x) end
    if y ~= self.y then self:setY(y) end
    self.tooltip:setX(x)
    self.tooltip:setY(y + size + 8)
end

MoonDisplay.update = function(self)
    if not self.shown then return end
    local now = getTimestampMs()
    if now < self.nextUpdate then return end
    self.nextUpdate = now + 250
    positionDisplay(self)
    updatePhase(self)
end

MoonDisplay.prerender = function(self)
    if not self.shown then return end
    local size = self.width
    self:drawTextureScaled(self.frame, 0, 0, size, size, 1, 1, 1, 1)
    local icon = moonlight.weather and self.clouds or self.moons[self.phase + 1]
    self:drawTextureScaled(icon, self.iconOffset, self.iconOffset, self.iconSize, self.iconSize, 1, 0.55, 1, 1)
    local hovered = self:isMouseOver()
    if hovered ~= self.hovered then
        self.hovered = hovered
        self.tooltip:setVisible(hovered)
    end
end

local function initialiseDisplay(self, clock)
    self:initialise()
    self:setWantMouseEvents(false)
    self.clock = clock
    self.climate = getClimateManager()
    self.time = getGameTime()
    self.frame = getTexture("media/ui/MoonlightPhases/Dial.png")
    self.clouds = getTexture("media/ui/MoonlightPhases/Clouds.png")
    self.moons = table.newarray()
    for phase = 1, 8 do self.moons[phase] = getTexture("media/ui/queue/moonN" .. phase .. ".png") end
    self.tooltip = ISToolTip:new()
    self.tooltip:initialise()
    self.tooltip.followMouse = false
    self.tooltip:addToUIManager()
    self.tooltip:setVisible(false)
end

local function createDisplay()
    if display then
        display:removeFromUIManager()
        display.tooltip:removeFromUIManager()
    end
    local clock = UIManager.getClock()
    if not clock then
        display = nil
        return
    end
    display = MoonDisplay:new(0, 0, 1, 1)
    initialiseDisplay(display, clock)
    display.shown = false
    display.revealed = false
    display.nextUpdate = 0
    display:setVisible(false)
    display:addToUIManager()
    prepareDisplay()
end

Events.OnGameStart.Add(createDisplay)
Events.OnClimateTick.Add(updateReveal)
Events.OnPreUIDraw.Add(prepareDisplay)
