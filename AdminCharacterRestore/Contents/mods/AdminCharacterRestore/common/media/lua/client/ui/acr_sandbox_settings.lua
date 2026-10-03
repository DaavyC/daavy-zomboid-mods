local ACR = require "acr_shared"

local TITLE_BY_OPTION = {
    ["AdminCharacterRestore.SnapshotIntervalHours"] = "AdminCharacterRestore_Snapshots",
    ["AdminCharacterRestore.Debug"] = "AdminCharacterRestore_Advanced"
}
local IN_GAME_SETTINGS_SPACING = 10
local sandboxPanelHooked = false
local hostSettingsScreenHooked = false
local inGameSandboxPanelHooked = false

local function shiftPanelChildren(panel, y, amount)
    local children = panel:getChildrenInOrder()
    for index = 1, #children do
        local child = children[index]
        local childY = child:getY()
        if childY >= y then child:setY(childY + amount) end
    end
end

local function addSandboxPageTitle(panel, setting, titleHeight, titleAmount)
    local title = setting and setting.acrTitle
    local row = setting and panel.labels[setting.name]
    if not title or not row then return 0 end

    local y = row:getY()
    shiftPanelChildren(panel, y, titleAmount)
    local titleLabel = ISLabel:new(
        0, 0, titleHeight, getText("Sandbox_Title_" .. title), 1, 1, 1, 1, UIFont.Large
    )
    panel:addChild(titleLabel)
    titleLabel:setX((panel:getWidth() - titleLabel:getWidth()) / 2)
    titleLabel:setY(y + 20)
    if not panel.adminCharacterRestoreHeaders then
        panel.adminCharacterRestoreHeaders = table.newarray()
    end
    panel.adminCharacterRestoreHeaders[#panel.adminCharacterRestoreHeaders + 1] = titleLabel
    return titleAmount
end

local function addSandboxPageTitles(panel, page)
    if not panel or not page or not page.settings or not panel.labels then return end
    if panel.adminCharacterRestoreTitles then return end

    local titleHeight = getTextManager():getFontFromEnum(UIFont.Large):getLineHeight() + 6
    local titleAmount = titleHeight + 22
    local addedHeight = 0
    for index = 1, #page.settings do
        addedHeight = addedHeight + addSandboxPageTitle(panel, page.settings[index], titleHeight, titleAmount)
    end
    if addedHeight > 0 then panel:setScrollHeight(panel:getScrollHeight() + addedHeight) end
    panel.adminCharacterRestoreTitles = true
end

local function copySettingsPage(page)
    local copy = copyTable(page)
    copy.settings = table.newarray()
    for index = 1, #(page.settings or {}) do
        local setting = page.settings[index]
        copy.settings[index] = copyTable(setting)
    end
    return copy
end

local function needsHostTitles(page)
    for index = 1, #page.settings do
        local setting = page.settings[index]
        local title = TITLE_BY_OPTION[setting.name]
        if title and (setting.title ~= title or setting.acrTitle ~= title) then
            return true
        end
    end
    return false
end

local function applyHostTitles(page)
    for index = 1, #page.settings do
        local setting = page.settings[index]
        local title = TITLE_BY_OPTION[setting.name]
        if title then
            setting.title = title
            setting.acrTitle = title
        end
    end
end

local function createHostPage(page)
    if not page or not page.settings or not needsHostTitles(page) then return page end
    local hostPage = copySettingsPage(page)
    ACR.debug("Customizing Admin Character Restore sandbox page")
    applyHostTitles(hostPage)
    return hostPage
end

local function hasNativeTitles(page)
    for index = 1, #page.settings do
        local setting = page.settings[index]
        if TITLE_BY_OPTION[setting.name] and setting.title ~= nil then
            return true
        end
    end
    return false
end

local function createInGamePage(page)
    if not page or not page.settings then return page end
    local customPage = createHostPage(page)
    if customPage == page and hasNativeTitles(customPage) then customPage = copySettingsPage(page) end
    for index = 1, #customPage.settings do
        local setting = customPage.settings[index]
        if TITLE_BY_OPTION[setting.name] then setting.title = nil end
    end
    return customPage
end

local function isAdminCharacterRestorePage(page)
    if not page or not page.settings then return false end

    for index = 1, #page.settings do
        if TITLE_BY_OPTION[page.settings[index].name] then return true end
    end

    return false
end

local function getInGameSettingsWidths(panel, page)
    local labelWidth = 0
    local controlWidth = 0
    for index = 1, #page.settings do
        local setting = page.settings[index]
        local label = panel.labels[setting.name]
        local control = panel.controls[setting.name]
        if label and control then
            local currentLabelWidth = label:getWidth()
            local currentControlWidth = control:getWidth()
            labelWidth = math.max(labelWidth, currentLabelWidth)
            controlWidth = math.max(controlWidth, currentControlWidth)
        end
    end

    return labelWidth, controlWidth
end

local function alignInGameSetting(panel, setting, labelWidth, contentX)
    local label = panel.labels[setting.name]
    local control = panel.controls[setting.name]
    if not label or not control then return end
    label:setX(contentX + labelWidth - label:getWidth())
    control:setX(contentX + labelWidth + IN_GAME_SETTINGS_SPACING)
end

local function centerInGameSettings(panel, page)
    if not panel or not page or not page.settings
            or not panel.labels or not panel.controls
            or not isAdminCharacterRestorePage(page) then return end

    local labelWidth, controlWidth = getInGameSettingsWidths(panel, page)
    if labelWidth == 0 or controlWidth == 0 then return end

    local contentWidth = labelWidth + IN_GAME_SETTINGS_SPACING + controlWidth
    local contentX = (panel:getWidth() - contentWidth) / 2
    for index = 1, #page.settings do
        alignInGameSetting(panel, page.settings[index], labelWidth, contentX)
    end
end

local function centerSandboxPageTitles(panel)
    local headers = panel and panel.adminCharacterRestoreHeaders
    if not headers then return end

    local panelWidth = panel:getWidth()
    for index = 1, #headers do
        local header = headers[index]
        header:setX((panelWidth - header:getWidth()) / 2)
    end
end

local function replaceHostPanel(pageEdit, pageEntry, hostPage)
    local oldPanel = pageEntry.panel
    local wasCurrent = pageEdit.currentPanel == oldPanel
    if wasCurrent then pageEdit:removeChild(oldPanel) end
    pageEntry.page = hostPage
    pageEntry.panel = pageEdit:createPanel({ name = "Sandbox" }, hostPage)
    if wasCurrent then
        pageEdit:addChild(pageEntry.panel)
        pageEdit.currentPanel = pageEntry.panel
        pageEdit:onPanelChange()
    end
end

local function rebuildHostSettingsPage(screen)
    screen = screen or (ServerSettingsScreen and ServerSettingsScreen.instance)
    local pageEdit = screen and screen.pageEdit
    if not pageEdit or not pageEdit.listbox then return end

    for index = 1, #pageEdit.listbox.items do
        local listItem = pageEdit.listbox.items[index]
        local pageEntry = listItem.item
        local page = pageEntry and pageEntry.page
        local hostPage = createHostPage(page)
        if hostPage ~= page then
            replaceHostPanel(pageEdit, pageEntry, hostPage)
        end
    end
end

local function installSandboxPanelHook()
    if sandboxPanelHooked or not SandboxOptionsScreen or not SandboxOptionsScreen.createPanel then return end

    local originalCreatePanel = SandboxOptionsScreen.createPanel
    SandboxOptionsScreen.createPanel = function (self, page)
        return originalCreatePanel(self, createHostPage(page))
    end
    sandboxPanelHooked = true
    ACR.debug("Sandbox options title hook installed")
end

local function installHostSettingsScreenHook()
    if hostSettingsScreenHooked or not ServerSettingsScreen
            or not ServerSettingsScreen.create then return end

    local originalCreateScreen = ServerSettingsScreen.create
    ServerSettingsScreen.create = function (self)
        originalCreateScreen(self)
        rebuildHostSettingsPage(self)
    end
    hostSettingsScreenHooked = true
end

local function installInGameSandboxListboxHook()
    local originalSelectPage = ISServerSandboxOptionsUI.onMouseDownListbox
    if not originalSelectPage then return end

    ISServerSandboxOptionsUI.onMouseDownListbox = function (self, pageEntry)
        originalSelectPage(self, pageEntry)
        if pageEntry and pageEntry.page and pageEntry.panel then
            centerInGameSettings(pageEntry.panel, pageEntry.page)
            centerSandboxPageTitles(pageEntry.panel)
        end
    end
end

local function installInGameSandboxPanelHook()
    if inGameSandboxPanelHooked or not ISServerSandboxOptionsUI
            or not ISServerSandboxOptionsUI.createPanel then return end

    local originalCreatePanel = ISServerSandboxOptionsUI.createPanel
    ISServerSandboxOptionsUI.createPanel = function (self, page)
        local inGamePage = createInGamePage(page)
        local panel = originalCreatePanel(self, inGamePage)
        addSandboxPageTitles(panel, inGamePage)
        centerInGameSettings(panel, inGamePage)
        return panel
    end
    installInGameSandboxListboxHook()
    inGameSandboxPanelHooked = true
    ACR.debug("In-game sandbox panel title hook installed")
end

local function installSandboxHooks()
    installSandboxPanelHook()
    installHostSettingsScreenHook()
    installInGameSandboxPanelHook()
end

local function onMainMenuEnter()
    installSandboxHooks()
    rebuildHostSettingsPage()
end

installSandboxHooks()
Events.OnMainMenuEnter.Add(onMainMenuEnter)
Events.OnGameStart.Add(installInGameSandboxPanelHook)
