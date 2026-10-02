local require = require
require "OptionScreens/ServerSettingsScreen"
require "ISUI/AdminPanel/ISServerSandboxOptionsUI"
require "ISUI/ISLabel"

local ServerSettingsScreen = ServerSettingsScreen
local ISServerSandboxOptionsUI = ISServerSandboxOptionsUI
local ISLabel = ISLabel
local getText = getText
local getTextManager = getTextManager
local isClient = isClient
local newarray = table.newarray
local LARGE_FONT = UIFont.Large
local protectionName = "MultiplayerFastForward.ZombieProtection"
local debugName = "MultiplayerFastForward.Debug"
local sections = newarray(
    { name = "MultiplayerFastForward.Speed1", translation = "Sandbox_Title_MultiplayerFastForward_Speeds" },
    { name = "MultiplayerFastForward.MinimumPlayers", translation = "Sandbox_Title_MultiplayerFastForward_Voting" },
    { name = protectionName, translation = "Sandbox_Title_MultiplayerFastForward_Protection" },
    { name = debugName, translation = "Sandbox_Title_MultiplayerFastForward_Advanced" }
)

local function isModPage(page)
    local settings = page.settings
    if not settings then return false end
    for i = 1, #settings do
        if settings[i].name == protectionName then return true end
    end
    return false
end

local function shiftRows(panel, startY, amount)
    local children = panel:getChildrenInOrder()
    for i = 1, #children do
        local child = children[i]
        local y = child:getY()
        if y >= startY then child:setY(y + amount) end
    end
end

local function addSectionTitle(panel, optionName, translation)
    local row = panel.labels[optionName]
    local height = getTextManager():getFontFromEnum(LARGE_FONT):getLineHeight() + 6
    local amount = height + 22
    local y = row:getY()
    shiftRows(panel, y, amount)
    local title = ISLabel:new(0, 0, height, getText(translation),
        1, 1, 1, 1, LARGE_FONT)
    panel:addChild(title)
    title:setX((panel:getWidth() - title:getWidth()) / 2)
    title:setY(y + 20)
    panel.mffSectionTitles[#panel.mffSectionTitles + 1] = title
    if panel.titles then panel.titles[#panel.titles + 1] = title end
    panel:setScrollHeight(panel:getScrollHeight() + amount)
end

local function addSectionTitles(panel)
    if panel.mffSectionTitles then return end
    panel.mffSectionTitles = newarray()
    for i = 1, #sections do
        local section = sections[i]
        if panel.labels[section.name] then addSectionTitle(panel, section.name, section.translation) end
    end
end

local function settingsWidths(panel, page)
    local labelWidth, controlWidth = 0, 0
    for i = 1, #page.settings do
        local name = page.settings[i].name
        local label, control = panel.labels[name], panel.controls[name]
        if label and control then
            local width = label:getWidth()
            if width > labelWidth then labelWidth = width end
            width = control:getWidth()
            if width > controlWidth then controlWidth = width end
        end
    end
    return labelWidth, controlWidth
end

local function centerSettings(panel, page)
    local labelWidth, controlWidth = settingsWidths(panel, page)
    local x = (panel:getWidth() - labelWidth - 10 - controlWidth) / 2
    for i = 1, #page.settings do
        local name = page.settings[i].name
        local label, control = panel.labels[name], panel.controls[name]
        if label and control then
            label:setX(x + labelWidth - label:getWidth())
            control:setX(x + labelWidth + 10)
        end
    end
    local titles = panel.mffSectionTitles
    for i = 1, #titles do
        local title = titles[i]
        title:setX((panel:getWidth() - title:getWidth()) / 2)
    end
end

local function styleHostSettings(screen)
    local pageEdit = screen.pageEdit
    if not pageEdit or not pageEdit.listbox then return end
    local entries = pageEdit.listbox.items
    for i = 1, #entries do
        local entry = entries[i].item
        if entry.page and not entry.category and isModPage(entry.page) then
            addSectionTitles(entry.panel)
        end
    end
end

local originalCreate = ServerSettingsScreen.create
function ServerSettingsScreen:create()
    originalCreate(self)
    styleHostSettings(self)
end

local originalCreatePanel = ISServerSandboxOptionsUI.createPanel
function ISServerSandboxOptionsUI:createPanel(page)
    local panel = originalCreatePanel(self, page)
    if isClient() and isModPage(page) then
        addSectionTitles(panel)
        centerSettings(panel, page)
    end
    return panel
end

local originalSelectPage = ISServerSandboxOptionsUI.onMouseDownListbox
function ISServerSandboxOptionsUI:onMouseDownListbox(entry)
    originalSelectPage(self, entry)
    if isClient() and entry.page and isModPage(entry.page) then
        centerSettings(entry.panel, entry.page)
    end
end

local function styleOpenHostSettings()
    local screen = ServerSettingsScreen.instance
    if screen then styleHostSettings(screen) end
end

styleOpenHostSettings()
Events.OnMainMenuEnter.Add(styleOpenHostSettings)
