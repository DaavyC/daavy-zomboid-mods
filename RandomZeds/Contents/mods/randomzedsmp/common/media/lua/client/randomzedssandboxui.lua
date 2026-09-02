local RandomZeds = require "randomzedsshared"

local TITLE_BY_OPTION = {
    ["RandomZeds.Debug"] = "RandomZeds_Advanced",
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
    for _, setting in ipairs(page and page.settings or {}) do
        local normalizedName = normalizeSettingName(setting)
        if normalizedName and normalizedName:match("^RandomZeds%.") then
            return true
        end
    end
    return false
end

local function getAdminName(setting)
    local normalizedName = normalizeSettingName(setting)
    local suffix = normalizedName and normalizedName:match("^RandomZeds%.(.+)$")
    return suffix and "RandomZeds_Admin_" .. suffix
end

local function copyPage(page)
    local pageCopy = copyTable(page)
    pageCopy.settings = {}
    local synapseAvailable = RandomZeds.hasSynapseFeatureSupport()
    for _, setting in ipairs(page.settings or {}) do
        if synapseAvailable or not isSynapseFeatureOption(setting) then
            pageCopy.settings[#pageCopy.settings + 1] = copyTable(setting)
        end
    end
    return pageCopy
end

local function customizePage(page, needsCustomization, customizeSetting, message)
    if not page or not page.settings then return page end

    for _, setting in ipairs(page.settings) do
        if needsCustomization(setting) then
            local customPage = copyPage(page)
            RandomZeds.debug(message)
            for _, customSetting in ipairs(customPage.settings) do
                customizeSetting(customSetting)
            end
            return customPage
        end
    end

    return page
end

local function shiftPanelChildren(panel, y, amount)
    for _, child in pairs(panel:getChildren()) do
        if child:getY() >= y then
            child:setY(child:getY() + amount)
        end
    end
end

local function addRandomZedsSubtitles(panel, page)
    if not panel or not page or not page.settings or not panel.labels then return panel end
    if not isRandomZedsPage(page) or panel.randomZedsSubtitles then return panel end

    RandomZeds.debug("Adding Random Zeds subtitles to sandbox page")

    local subtitleHeight = getTextManager():getFontFromEnum(UIFont.Medium):getLineHeight() + 4
    local subtitleSpacing = 8
    local subtitleAmount = subtitleHeight + subtitleSpacing
    local addedHeight = 0
    for _, setting in ipairs(page.settings) do
        local subtitle = setting and setting.randomZedsSubtitle
        local row = setting and panel.labels[setting.name]
        if subtitle and row then
            local y = row:getY()
            shiftPanelChildren(panel, y, subtitleAmount)
            local label = ISLabel:new(
                0, 0, subtitleHeight, getText("Sandbox_Title_" .. subtitle),
                1, 1, 1, 1, UIFont.Medium)
            panel:addChild(label)
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

local adminPanelHooked = false

local function hostPageNeedsCustomization(setting)
    local title = getTitle(setting)
    return (title and setting.title ~= title)
        or setting.randomZedsSubtitle ~= getSubtitle(setting)
end

local function customizeHostSetting(setting)
    local title = getTitle(setting)
    if title then setting.title = title end
    setting.randomZedsSubtitle = getSubtitle(setting)
end

local function createHostPage(page)
    return customizePage(
        page,
        hostPageNeedsCustomization,
        customizeHostSetting,
        "Customizing host sandbox page"
    )
end

local function adminPageNeedsCustomization(setting)
    return getAdminName(setting) ~= nil
end

local function customizeAdminSetting(setting)
    local adminName = getAdminName(setting)
    if adminName then
        setting.translatedName = getText("Sandbox_" .. adminName)
    end
end

local function createAdminPage(page)
    return customizePage(
        page,
        adminPageNeedsCustomization,
        customizeAdminSetting,
        "Customizing admin sandbox page"
    )
end

local function installAdminPanelHook()
    if adminPanelHooked then return end
    if not ISServerSandboxOptionsUI then
        RandomZeds.debug("Admin sandbox UI unavailable")
        return
    end

    local originalCreatePanel = ISServerSandboxOptionsUI.createPanel
    if not originalCreatePanel then
        RandomZeds.debug("Admin sandbox panel method unavailable")
        return
    end

    ISServerSandboxOptionsUI.createPanel = function(self, page)
        return originalCreatePanel(self, createAdminPage(page))
    end

    adminPanelHooked = true
    RandomZeds.debug("Admin sandbox UI hook installed")
end

local function rebuildHostSettingsPage()
    local screen = ServerSettingsScreen and ServerSettingsScreen.instance
    local pageEdit = screen and screen.pageEdit
    if not pageEdit or not pageEdit.listbox then
        RandomZeds.debug("Host sandbox page unavailable for rebuild")
        return
    end
    local rebuilt = 0
    for _, listEntry in ipairs(pageEdit.listbox.items) do
        local pageEntry = listEntry.item
        if pageEntry and not pageEntry.category then
            local page = pageEntry.page
            local hostPage = createHostPage(page)
            if hostPage ~= page then
                local oldPanel = pageEntry.panel
                local wasCurrent = pageEdit.currentPanel == oldPanel
                if wasCurrent then
                    pageEdit:removeChild(oldPanel)
                end

                pageEntry.page = hostPage
                pageEntry.panel = pageEdit:createPanel({ name = "Sandbox" }, hostPage)
                addRandomZedsSubtitles(pageEntry.panel, hostPage)
                if wasCurrent then
                    pageEdit:addChild(pageEntry.panel)
                    pageEdit.currentPanel = pageEntry.panel
                    pageEdit:onPanelChange()
                end
                rebuilt = rebuilt + 1
            end
        end
    end
    if rebuilt > 0 then
        RandomZeds.debug("Rebuilt host sandbox pages count=" .. tostring(rebuilt))
    end
end

local sandboxPanelHooked = false

local function installSandboxPanelHook()
    if sandboxPanelHooked then return end
    if not SandboxOptionsScreen or not SandboxOptionsScreen.createPanel then
        RandomZeds.debug("Sandbox options UI unavailable")
        return
    end

    local originalCreatePanel = SandboxOptionsScreen.createPanel
    SandboxOptionsScreen.createPanel = function(self, page)
        local customPage = createHostPage(page)
        return addRandomZedsSubtitles(
            originalCreatePanel(self, customPage), customPage)
    end

    sandboxPanelHooked = true
    RandomZeds.debug("Sandbox options UI hook installed")
end

local function initialize()
    RandomZeds.debug("Initializing Random Zeds sandbox UI")
    installAdminPanelHook()
    installSandboxPanelHook()
    rebuildHostSettingsPage()
end

RandomZeds.debug("Installing Random Zeds sandbox UI events")
installAdminPanelHook()
installSandboxPanelHook()
Events.OnMainMenuEnter.Add(initialize)
Events.OnGameStart.Add(installAdminPanelHook)
