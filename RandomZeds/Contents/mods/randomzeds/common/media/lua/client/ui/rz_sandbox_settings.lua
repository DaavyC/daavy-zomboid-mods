local RandomZeds = require "rz_shared"

local TITLE_BY_OPTION = {
    ["RandomZeds.Rain"] = "RandomZeds_Weather",
    ["RandomZeds.CrawlerChance"] = "RandomZeds_SpeedTypeChance",
    ["RandomZeds.CrawlerFragileChance"] = "RandomZeds_Crawlers",
    ["RandomZeds.ShamblerFragileChance"] = "RandomZeds_Shamblers",
    ["RandomZeds.FastShamblerFragileChance"] = "RandomZeds_FastShamblers",
    ["RandomZeds.SprinterSpeedMultiplier"] = "RandomZeds_Sprinters",
    ["RandomZeds.SpringDayStart"] = "RandomZeds_Spring",
    ["RandomZeds.SummerDayStart"] = "RandomZeds_Summer",
    ["RandomZeds.AutumnDayStart"] = "RandomZeds_Autumn",
    ["RandomZeds.WinterDayStart"] = "RandomZeds_Winter",
    ["RandomZeds.Debug"] = "RandomZeds_Advanced",
}

local SUBTITLE_BY_OPTION = {
    ["RandomZeds.CrawlerFragileChance"] = "RandomZeds_Toughness",
    ["RandomZeds.CrawlerSightEagleChance"] = "RandomZeds_Sight",
    ["RandomZeds.CrawlerHearingPinpointChance"] = "RandomZeds_Hearing",
    ["RandomZeds.ShamblerFragileChance"] = "RandomZeds_Toughness",
    ["RandomZeds.ShamblerSightEagleChance"] = "RandomZeds_Sight",
    ["RandomZeds.ShamblerHearingPinpointChance"] = "RandomZeds_Hearing",
    ["RandomZeds.FastShamblerFragileChance"] = "RandomZeds_Toughness",
    ["RandomZeds.FastShamblerSightEagleChance"] = "RandomZeds_Sight",
    ["RandomZeds.FastShamblerHearingPinpointChance"] = "RandomZeds_Hearing",
    ["RandomZeds.SprinterFragileChance"] = "RandomZeds_Toughness",
    ["RandomZeds.SprinterSightEagleChance"] = "RandomZeds_Sight",
    ["RandomZeds.SprinterHearingPinpointChance"] = "RandomZeds_Hearing",
    ["RandomZeds.SprinterSpeedMultiplier"] = "RandomZeds_Speed",
    ["RandomZeds.CrawlerCognitionNavigateDoorsChance"] = "RandomZeds_Cognition",
    ["RandomZeds.CrawlerStrengthSuperhumanChance"] = "RandomZeds_Strength",
    ["RandomZeds.CrawlerMemoryLongChance"] = "RandomZeds_Memory",
    ["RandomZeds.ShamblerCognitionNavigateDoorsChance"] = "RandomZeds_Cognition",
    ["RandomZeds.ShamblerStrengthSuperhumanChance"] = "RandomZeds_Strength",
    ["RandomZeds.ShamblerMemoryLongChance"] = "RandomZeds_Memory",
    ["RandomZeds.FastShamblerCognitionNavigateDoorsChance"] = "RandomZeds_Cognition",
    ["RandomZeds.FastShamblerStrengthSuperhumanChance"] = "RandomZeds_Strength",
    ["RandomZeds.FastShamblerMemoryLongChance"] = "RandomZeds_Memory",
    ["RandomZeds.SprinterCognitionNavigateDoorsChance"] = "RandomZeds_Cognition",
    ["RandomZeds.SprinterStrengthSuperhumanChance"] = "RandomZeds_Strength",
    ["RandomZeds.SprinterMemoryLongChance"] = "RandomZeds_Memory",
}

local function normalizeSettingName(setting)
    if not setting or type(setting.name) ~= "string" then return nil end

    return setting.name
        :gsub("^RandomZedsNight", "RandomZeds")
        :gsub("^RandomZedsWeather", "RandomZeds")
        :gsub("^RandomZedsMain", "RandomZeds")
end

local function isSynapseFeatureOption(setting)
    local normalizedName = normalizeSettingName(setting)
    if not normalizedName then return false end
    return normalizedName:match("^RandomZeds%.[^%.]+Cognition") ~= nil
        or normalizedName:match("^RandomZeds%.[^%.]+Strength") ~= nil
        or normalizedName:match("^RandomZeds%.[^%.]+Memory") ~= nil
end

local function getTitle(setting)
    local normalizedName = normalizeSettingName(setting)
    return normalizedName and TITLE_BY_OPTION[normalizedName]
end

local function getSubtitle(setting)
    local normalizedName = normalizeSettingName(setting)
    return normalizedName and SUBTITLE_BY_OPTION[normalizedName]
end

local function isRandomZedsPage(page)
    local settings = page and page.settings
    if not settings then return false end
    for index = 1, #settings do
        local setting = settings[index]
        local normalizedName = normalizeSettingName(setting)
        if normalizedName and normalizedName:match("^RandomZeds%.") then
            return true
        end
    end
    return false
end

local function copyPage(page)
    local pageCopy = copyTable(page)
    pageCopy.settings = table.newarray()
    local synapseAvailable = RandomZeds.hasSynapseFeatureSupport()
    local settings = page.settings
    for index = 1, #settings do
        local setting = settings[index]
        if synapseAvailable or not isSynapseFeatureOption(setting) then
            pageCopy.settings[#pageCopy.settings + 1] = copyTable(setting)
        end
    end
    return pageCopy
end

local function customizePage(page, needsCustomization, customizeSetting)
    if not page or not page.settings then return page end

    local settings = page.settings
    for index = 1, #settings do
        local setting = settings[index]
        if needsCustomization(setting) then
            local customPage = copyPage(page)
            local customSettings = customPage.settings
            for customIndex = 1, #customSettings do
                customizeSetting(customSettings[customIndex])
            end
            return customPage
        end
    end

    return page
end

local function shiftPanelChildren(panel, y, amount)
    local children = panel:getChildrenInOrder()
    for index = 1, #children do
        local child = children[index]
        local childY = child:getY()
        if childY >= y then
            child:setY(childY + amount)
        end
    end
end

local function trackRandomZedsHeader(panel, label)
    if not panel.randomZedsHeaders then
        panel.randomZedsHeaders = table.newarray()
    end
    panel.randomZedsHeaders[#panel.randomZedsHeaders + 1] = label
end

local function addRandomZedsSubtitles(panel, page)
    if not panel or not page or not page.settings or not panel.labels then return panel end
    if not isRandomZedsPage(page) or panel.randomZedsSubtitles then return panel end

    local subtitleHeight = getTextManager():getFontFromEnum(UIFont.Medium):getLineHeight() + 4
    local subtitleSpacing = 8
    local subtitleAmount = subtitleHeight + subtitleSpacing
    local addedHeight = 0
    local settings = page.settings
    for index = 1, #settings do
        local setting = settings[index]
        local subtitle = setting and setting.randomZedsSubtitle
        local row = setting and panel.labels[setting.name]
        if subtitle and row then
            local y = row:getY()
            shiftPanelChildren(panel, y, subtitleAmount)
            local label = ISLabel:new(
                0, 0, subtitleHeight, getText("Sandbox_Title_" .. subtitle),
                1, 1, 1, 1, UIFont.Medium)
            panel:addChild(label)
            trackRandomZedsHeader(panel, label)
            if panel.titles then
                table.insert(panel.titles, label)
            end
            label:setX((panel:getWidth() - label:getWidth()) / 2)
            label:setY(y)
            addedHeight = addedHeight + subtitleAmount
        end
    end

    if addedHeight > 0 then
        panel:setScrollHeight(panel:getScrollHeight() + addedHeight)
    end
    panel.randomZedsSubtitles = true
    return panel
end

local function addRandomZedsTitle(panel, setting)
    local title = setting and setting.title
    local row = setting and panel.labels[setting.name]
    if not title or not row then return 0 end

    local titleHeight = getTextManager():getFontFromEnum(UIFont.Large):getLineHeight() + 6
    local titleAmount = titleHeight + 22
    local y = row:getY()
    shiftPanelChildren(panel, y, titleAmount)

    local label = ISLabel:new(
        0, 0, titleHeight, getText("Sandbox_Title_" .. title),
        1, 1, 1, 1, UIFont.Large)
    panel:addChild(label)
    trackRandomZedsHeader(panel, label)
    label:setX((panel:getWidth() - label:getWidth()) / 2)
    label:setY(y + 20)
    return titleAmount
end

local function addRandomZedsTitles(panel, page)
    if not panel or not page or not page.settings or not panel.labels then
        return panel
    end
    if not isRandomZedsPage(page) or panel.randomZedsTitles then return panel end

    local addedHeight = 0
    local settings = page.settings
    for index = 1, #settings do
        addedHeight = addedHeight + addRandomZedsTitle(panel, settings[index])
    end

    if addedHeight > 0 then
        panel:setScrollHeight(panel:getScrollHeight() + addedHeight)
    end
    panel.randomZedsTitles = true
    return panel
end

local IN_GAME_SETTINGS_SPACING = 10

local function centerInGameSettings(panel, page)
    if not panel or not page or not page.settings
            or not panel.labels or not panel.controls then
        return panel
    end
    if not isRandomZedsPage(page) then return panel end

    local settings = page.settings
    local labelWidth = 0
    local controlWidth = 0
    for index = 1, #settings do
        local setting = settings[index]
        local label = setting and panel.labels[setting.name]
        local control = setting and panel.controls[setting.name]
        if label and control then
            labelWidth = math.max(labelWidth, label:getWidth())
            controlWidth = math.max(controlWidth, control:getWidth())
        end
    end
    if labelWidth == 0 or controlWidth == 0 then return panel end

    local panelWidth = panel:getWidth()
    local contentWidth = labelWidth + IN_GAME_SETTINGS_SPACING + controlWidth
    local contentX = (panelWidth - contentWidth) / 2
    for index = 1, #settings do
        local setting = settings[index]
        local label = setting and panel.labels[setting.name]
        local control = setting and panel.controls[setting.name]
        if label and control then
            label:setX(contentX + labelWidth - label:getWidth())
            control:setX(contentX + labelWidth + IN_GAME_SETTINGS_SPACING)
        end
    end

    local headers = panel.randomZedsHeaders
    if headers then
        for index = 1, #headers do
            local header = headers[index]
            header:setX((panelWidth - header:getWidth()) / 2)
        end
    end

    return panel
end

local function sandboxSettingNeedsCustomization(setting)
    local title = getTitle(setting)
    return (title and setting.title ~= title)
        or setting.randomZedsSubtitle ~= getSubtitle(setting)
end

local function customizeTitleAndSubtitle(setting)
    local title = getTitle(setting)
    if title then setting.title = title end
    setting.randomZedsSubtitle = getSubtitle(setting)
end

local function createSandboxPage(page)
    return customizePage(
        page,
        sandboxSettingNeedsCustomization,
        customizeTitleAndSubtitle
    )
end

local sandboxPanelHooked = false

local function installSandboxPanelHook()
    if sandboxPanelHooked then return end
    if not SandboxOptionsScreen or not SandboxOptionsScreen.createPanel then
        return
    end

    local originalCreatePanel = SandboxOptionsScreen.createPanel
    SandboxOptionsScreen.createPanel = function(self, page)
        local customPage = createSandboxPage(page)
        return addRandomZedsSubtitles(
            originalCreatePanel(self, customPage), customPage)
    end

    sandboxPanelHooked = true
end

local function replaceHostSettingsPage(pageEdit, pageEntry, customPage)
    local oldPanel = pageEntry.panel
    local wasCurrent = pageEdit.currentPanel == oldPanel
    if wasCurrent then
        pageEdit:removeChild(oldPanel)
    end

    pageEntry.page = customPage
    pageEntry.panel = pageEdit:createPanel({ name = "Sandbox" }, customPage)
    addRandomZedsSubtitles(pageEntry.panel, customPage)

    if wasCurrent then
        pageEdit:addChild(pageEntry.panel)
        pageEdit.currentPanel = pageEntry.panel
        pageEdit:onPanelChange()
    end
end

local function rebuildHostSettingsPages(screen)
    screen = screen or (ServerSettingsScreen and ServerSettingsScreen.instance)
    local pageEdit = screen and screen.pageEdit
    if not pageEdit or not pageEdit.listbox then return end

    local settingsListItems = pageEdit.listbox.items
    for index = 1, #settingsListItems do
        local pageEntry = settingsListItems[index].item
        if pageEntry and pageEntry.page and not pageEntry.category then
            local page = pageEntry.page
            local customPage = createSandboxPage(page)
            if customPage ~= page then
                replaceHostSettingsPage(pageEdit, pageEntry, customPage)
            end
        end
    end
end

local hostSettingsScreenHooked = false

local function installHostSettingsScreenHook()
    if hostSettingsScreenHooked then return end
    if not ServerSettingsScreen or not ServerSettingsScreen.create then
        return
    end

    local originalCreate = ServerSettingsScreen.create
    ServerSettingsScreen.create = function(self)
        originalCreate(self)
        rebuildHostSettingsPages(self)
    end

    hostSettingsScreenHooked = true
end

local inGameSandboxOptionsHooked = false

local function installInGameSandboxOptionsHook()
    if inGameSandboxOptionsHooked then return end
    if not ISServerSandboxOptionsUI or not ISServerSandboxOptionsUI.createPanel then
        return
    end

    local originalCreatePanel = ISServerSandboxOptionsUI.createPanel
    ISServerSandboxOptionsUI.createPanel = function(self, page)
        local customPage = createSandboxPage(page)
        local panel = originalCreatePanel(self, customPage)
        addRandomZedsTitles(panel, customPage)
        addRandomZedsSubtitles(panel, customPage)
        return centerInGameSettings(panel, customPage)
    end

    local originalOnMouseDownListbox = ISServerSandboxOptionsUI.onMouseDownListbox
    if originalOnMouseDownListbox then
        ISServerSandboxOptionsUI.onMouseDownListbox = function(self, item)
            originalOnMouseDownListbox(self, item)
            if item and item.page and item.panel then
                centerInGameSettings(item.panel, item.page)
            end
        end
    end

    inGameSandboxOptionsHooked = true
end

local function initializeMenuSettings()
    installSandboxPanelHook()
    installHostSettingsScreenHook()
    installInGameSandboxOptionsHook()
    rebuildHostSettingsPages()
end

initializeMenuSettings()
Events.OnMainMenuEnter.Add(initializeMenuSettings)
Events.OnGameStart.Add(installInGameSandboxOptionsHook)

