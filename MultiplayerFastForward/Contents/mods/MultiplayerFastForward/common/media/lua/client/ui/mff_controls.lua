if not isClient() then return end

local require = require
require "ISUI/ISPanel"
require "ISUI/ISButton"

local ISPanel = ISPanel
local SpeedButton = ISButton:derive("MultiplayerFastForwardSpeedButton")
SpeedButton.BORDER = 3
local BUTTON_BORDER = SpeedButton.BORDER
local Shared = require "mff_shared"
local getSpecificPlayer = getSpecificPlayer
local getTexture = getTexture
local getText = getText
local getTextManager = getTextManager
local tostring = tostring
local newarray = table.newarray
local isGamePaused = isGamePaused
local SMALL_FONT = UIFont.Small
local blockMessages = {
    ["sleep acceleration"] = "UI_MFF_SleepBlocked",
    ["zombie protection"] = "UI_MFF_ZombieBlocked",
    ["minimum players"] = "UI_MFF_MinimumPlayers",
}
local Controls = ISPanel:derive("MultiplayerFastForwardControls")
local PauseOverlay = ISPanel:derive("MultiplayerFastForwardPauseOverlay")
Controls.PauseOverlay = PauseOverlay

function PauseOverlay:new(client)
    local panel = ISPanel.new(self, 0, 0, 0, 0)
    panel.client = client
    panel.core = getCore()
    panel.background = false
    panel:setWantMouseEvents(true)
    panel:setVisible(false)
    local textManager = getTextManager()
    panel.text = getText("IGUI_GamePaused")
    panel.fontHeight = textManager:getFontHeight(SMALL_FONT)
    panel.boxWidth = textManager:MeasureStringX(SMALL_FONT, panel.text) + 32
    return panel
end

function PauseOverlay:update()
    self:setVisible(self.client.isPaused())
    self:setWidth(self.core:getScreenWidth())
    self:setHeight(self.core:getScreenHeight())
end

function PauseOverlay:render()
    if not self.client.isPaused() or isGamePaused() then return end
    local height = math.ceil(self.fontHeight * 1.5)
    local centerX, centerY = self.width / 2, self.height / 6
    self:drawRect(centerX - self.boxWidth / 2, centerY - height / 2, self.boxWidth, height, 0.75, 0, 0, 0)
    self:drawTextCentre(self.text, centerX, centerY - self.fontHeight / 2, 1, 1, 1, 1, SMALL_FONT)
end

local function consumePauseInput() return true end
PauseOverlay.onMouseDown = consumePauseInput
PauseOverlay.onMouseUp = consumePauseInput
PauseOverlay.onRightMouseDown = consumePauseInput
PauseOverlay.onRightMouseUp = consumePauseInput
PauseOverlay.onMouseMove = consumePauseInput
PauseOverlay.onMouseWheel = consumePauseInput

function SpeedButton:prerender()
    self:updateTooltip()
end

function SpeedButton:render()
    local border = self.BORDER
    local y = self.enable and self.pressed and 1 or 0
    local highlighted = self.enable and (self.active or self.mouseOver or self.joypadFocused)
    local texture = highlighted and self.onTexture or self.offTexture
    local alpha = highlighted and 1 or 0.85
    local tint = self.enable and 1 or 0.25
    self:drawRect(0, y, self.width, self.height, 0.75, 0, 0, 0)
    self:drawTextureScaled(texture, border, border + y, self.width - border * 2, self.height - border * 2, alpha, tint, tint, tint)
end

function Controls:new(playerIndex, client)
    local panel = ISPanel.new(self, 0, 0, 100, 42)
    panel.playerIndex = playerIndex
    panel.client = client
    panel.buttons = newarray()
    panel.background = false
    return panel
end

function Controls:addSpeedButton(option, x)
    local off = getTexture("media/ui/speedControls/" .. option.icon .. "_Off.png")
    local on = getTexture("media/ui/speedControls/" .. option.icon .. "_On.png")
    local button = SpeedButton:new(x, 0, off:getWidth() + BUTTON_BORDER * 2, off:getHeight() + BUTTON_BORDER * 2, "", self, self.castVote)
    button:initialise()
    button.option = option
    button.offTexture, button.onTexture = off, on
    button:setEnable(false)
    self:addChild(button)
    self.buttons[#self.buttons + 1] = button
end

function Controls:createChildren()
    local x = 0
    for i = 1, #Shared.options do
        self:addSpeedButton(Shared.options[i], x)
        x = x + self.buttons[i]:getWidth() + 2
    end
    self:setWidth(x - 2)
    self.countY = self.buttons[1]:getHeight() + 3
    self.countHeight = getTextManager():getFontHeight(SMALL_FONT)
    self:setHeight(self.countY + self.countHeight + 2)
end

function Controls:castVote(button)
    self.client.vote(self.playerIndex, button.option.speed)
end

local function buttonTooltip(option, snapshot)
    if not snapshot then return option.label end
    local label = option.speed > 1 and tostring(Shared.multiplier(option.speed, snapshot.multipliers)) .. "x" or option.label
    local tooltip = getText("UI_MFF_Votes", label, snapshot.counts[option.speed], snapshot.total)
    local block = Shared.selectionBlock(snapshot, option.speed)
    if block then
        return tooltip .. "\n" .. getText(blockMessages[block], snapshot.onlinePlayers, snapshot.minimumPlayers)
    end
    if snapshot.adminForce then tooltip = tooltip .. "\n" .. getText("UI_MFF_AdminForce") end
    return tooltip
end

function Controls:updateButtons(snapshot)
    for i = 1, #self.buttons do
        local button = self.buttons[i]
        local speed = button.option.speed
        button:setEnable(snapshot ~= nil and Shared.canSelect(snapshot, speed))
        button.active = snapshot and snapshot.speed == speed or false
        button.tooltip = buttonTooltip(button.option, snapshot)
    end
end

function Controls:update()
    local player = getSpecificPlayer(self.playerIndex)
    self:setVisible(player ~= nil and player:isAlive())
    if not player then return end
    self:setX(getPlayerScreenLeft(self.playerIndex) + getPlayerScreenWidth(self.playerIndex) - self.width - 10)
    local clock = UIManager.getClock()
    local offset = clock and clock:getY() + clock:getHeight() + 10 or 50
    self:setY(getPlayerScreenTop(self.playerIndex) + offset)
    local snapshot = self.client.snapshot
    if self.snapshot ~= snapshot then
        self:updateButtons(snapshot)
        self.snapshot = snapshot
    end
end

function Controls:render()
    local snapshot = self.client.snapshot
    if not snapshot then return end
    for i = 1, #self.buttons do
        local button = self.buttons[i]
        local count = snapshot.counts[button.option.speed]
        if count > 0 then
            self:drawTextCentre(tostring(count), button:getX() + button:getWidth() / 2, self.countY, 1, 1, 1, 1, SMALL_FONT)
        end
    end
end

return Controls
