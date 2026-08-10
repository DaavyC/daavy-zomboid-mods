local TITLE_BY_OPTION = {
    ["RandomZeds.Rain"] = "RandomZeds_Weather",
    ["RandomZeds.CrawlerChance"] = "RandomZeds_SpeedTypeChance",
    ["RandomZeds.CrawlerFragileChance"] = "RandomZeds_Crawlers",
    ["RandomZeds.ShamblerFragileChance"] = "RandomZeds_Shamblers",
    ["RandomZeds.FastShamblerFragileChance"] = "RandomZeds_FastShamblers",
    ["RandomZeds.SprinterSpeedMultiplier"] = "RandomZeds_Sprinters",
}

local function normalizeSettingName(setting)
    if not setting or not setting.name then return nil end

    return setting.name
        :gsub("^RandomZedsNight", "RandomZeds")
        :gsub("^RandomZedsWeather", "RandomZeds")
end

local function getTitle(setting)
    local normalizedName = normalizeSettingName(setting)
    return normalizedName and TITLE_BY_OPTION[normalizedName]
end

local function getAdminName(setting)
    local normalizedName = normalizeSettingName(setting)
    local suffix = normalizedName and normalizedName:match("^RandomZeds%.(.+)$")
    return suffix and "RandomZeds_Admin_" .. suffix
end

local function copyPage(page)
    local copy = copyTable(page)
    copy.settings = {}
    for index, setting in ipairs(page.settings or {}) do
        copy.settings[index] = copyTable(setting)
    end
    return copy
end

local adminPanelHooked = false

local function createHostPage(page)
    if not page or not page.settings then return page end

    for _, setting in ipairs(page.settings) do
        local title = getTitle(setting)
        if title and setting.title ~= title then
            local hostPage = copyPage(page)
            for _, hostSetting in ipairs(hostPage.settings) do
                local hostTitle = getTitle(hostSetting)
                if hostTitle then
                    hostSetting.title = hostTitle
                end
            end
            return hostPage
        end
    end

    return page
end

local function createAdminPage(page)
    if not page or not page.settings then return page end

    for _, setting in ipairs(page.settings) do
        if getAdminName(setting) then
            local adminPage = copyPage(page)
            for _, adminSetting in ipairs(adminPage.settings) do
                local adminName = getAdminName(adminSetting)
                if adminName then
                    adminSetting.translatedName = getText("Sandbox_" .. adminName)
                end
            end
            return adminPage
        end
    end

    return page
end

local function installAdminPanelHook()
    if adminPanelHooked then return end
    if not ISServerSandboxOptionsUI then return end

    local original = ISServerSandboxOptionsUI.createPanel
    if not original then return end

    ISServerSandboxOptionsUI.createPanel = function(self, page)
        return original(self, createAdminPage(page))
    end

    adminPanelHooked = true
end

local function rebuildHostSettingsPage()
    local screen = ServerSettingsScreen and ServerSettingsScreen.instance
    local pageEdit = screen and screen.pageEdit
    if not pageEdit or not pageEdit.listbox then return end

    for _, item in ipairs(pageEdit.listbox.items) do
        local itemData = item.item
        local page = itemData and itemData.page
        local hostPage = createHostPage(page)
        if hostPage ~= page then
            local oldPanel = itemData.panel
            local wasCurrent = pageEdit.currentPanel == oldPanel
            if wasCurrent then
                pageEdit:removeChild(oldPanel)
            end

            itemData.page = hostPage
            itemData.panel = pageEdit:createPanel({ name = "Sandbox" }, hostPage)
            if wasCurrent then
                pageEdit:addChild(itemData.panel)
                pageEdit.currentPanel = itemData.panel
                pageEdit:onPanelChange()
            end
        end
    end
end

local function initialize()
    installAdminPanelHook()
    rebuildHostSettingsPage()
end

installAdminPanelHook()
Events.OnMainMenuEnter.Add(initialize)
Events.OnGameStart.Add(installAdminPanelHook)
