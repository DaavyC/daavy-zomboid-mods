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
}

local function normalizeSettingName(setting)
    if not setting or not setting.name then return nil end

    return setting.name
        :gsub("^RandomZedsNight", "RandomZeds")
        :gsub("^RandomZedsWeather", "RandomZeds")
        :gsub("^RandomZedsMain", "RandomZeds")
end

local function getTitle(setting)
    local normalizedName = normalizeSettingName(setting)
    return normalizedName and TITLE_BY_OPTION[normalizedName]
end

local function getSubtitle(setting)
    local normalizedName = normalizeSettingName(setting)
    return normalizedName and SUBTITLE_BY_OPTION[normalizedName]
end

local function getSoloName(setting)
    local normalizedName = normalizeSettingName(setting)
    local suffix = normalizedName and normalizedName:match("^RandomZeds%.(.+)$")
    return suffix and "RandomZeds_Solo_" .. suffix
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

local function copyPage(page)
    local pageCopy = copyTable(page)
    pageCopy.settings = {}
    for index, setting in ipairs(page.settings or {}) do
        pageCopy.settings[index] = copyTable(setting)
    end
    return pageCopy
end

local function shiftPanelChildren(panel, y, amount)
    for _, child in pairs(panel:getChildren()) do
        if child:getY() >= y then
            child:setY(child:getY() + amount)
        end
    end
end

local function addCenteredLabel(panel, height, labelText, font, y)
    local label = ISLabel:new(0, 0, height, labelText, 1, 1, 1, 1, font)
    panel:addChild(label)
    label:setX((panel:getWidth() - label:getWidth()) / 2)
    label:setY(y)
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
        local subtitle = setting.randomZedsSubtitle
        local row = panel.labels[setting.name]
        if subtitle and row then
            local y = row:getY()
            shiftPanelChildren(panel, y, subtitleAmount)
            addCenteredLabel(panel, subtitleHeight, getText("Sandbox_Title_" .. subtitle), UIFont.Medium, y)
            addedHeight = addedHeight + subtitleAmount
        end
    end

    if addedHeight > 0 then
        panel:setScrollHeight(panel:getScrollHeight() + addedHeight)
    end
    panel.randomZedsSubtitles = true
    return panel
end

local function createSandboxPage(page)
    if not page or not page.settings then return page end

    for _, setting in ipairs(page.settings) do
        local title = getTitle(setting)
        local subtitle = getSubtitle(setting)
        if (title and setting.title ~= title) or setting.randomZedsSubtitle ~= subtitle then
            local sandboxPage = copyPage(page)
            RandomZeds.debug("Customizing sandbox page")
            for _, sandboxSetting in ipairs(sandboxPage.settings) do
                local sandboxTitle = getTitle(sandboxSetting)
                if sandboxTitle then
                    sandboxSetting.title = sandboxTitle
                end
                sandboxSetting.randomZedsSubtitle = getSubtitle(sandboxSetting)
            end
            return sandboxPage
        end
    end

    return page
end

local soloSandboxPanelHooked = false

local function createSoloSandboxPage(page)
    if not page or not page.settings then return page end

    for _, setting in ipairs(page.settings) do
        if getSoloName(setting) then
            local soloPage = copyPage(page)
            RandomZeds.debug("Customizing solo sandbox page")
            for _, soloSetting in ipairs(soloPage.settings) do
                local soloName = getSoloName(soloSetting)
                if soloName then
                    soloSetting.translatedName = getText("Sandbox_" .. soloName)
                end
            end
            return soloPage
        end
    end

    return page
end

local function installSoloSandboxPanelHook()
    if soloSandboxPanelHooked then return end
    if not ISServerSandboxOptionsUI then
        RandomZeds.debug("Solo sandbox UI unavailable")
        return
    end

    local originalCreatePanel = ISServerSandboxOptionsUI.createPanel
    if not originalCreatePanel then
        RandomZeds.debug("Solo sandbox panel method unavailable")
        return
    end

    ISServerSandboxOptionsUI.createPanel = function(self, page)
        return originalCreatePanel(self, createSoloSandboxPage(page))
    end

    soloSandboxPanelHooked = true
    RandomZeds.debug("Solo sandbox UI hook installed")
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
        local customPage = createSandboxPage(page)
        return addRandomZedsSubtitles(
            originalCreatePanel(self, customPage),
            customPage
        )
    end

    sandboxPanelHooked = true
    RandomZeds.debug("Sandbox options UI hook installed")
end

local function initialize()
    RandomZeds.debug("Initializing Random Zeds sandbox UI")
    installSoloSandboxPanelHook()
    installSandboxPanelHook()
end

RandomZeds.debug("Installing Random Zeds sandbox UI events")
installSoloSandboxPanelHook()
installSandboxPanelHook()
Events.OnMainMenuEnter.Add(initialize)
Events.OnGameStart.Add(installSoloSandboxPanelHook)
