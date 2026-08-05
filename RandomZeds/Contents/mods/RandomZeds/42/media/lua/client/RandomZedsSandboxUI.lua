local TITLE_BY_OPTION = {
    ["RandomZeds.Rain"] = "RandomZeds_Weather",
    ["RandomZeds.CrawlerChance"] = "RandomZeds_SpeedTypeChance",
    ["RandomZeds.CrawlerFragileChance"] = "RandomZeds_Crawlers",
    ["RandomZeds.ShamblerFragileChance"] = "RandomZeds_Shamblers",
    ["RandomZeds.FastShamblerFragileChance"] = "RandomZeds_FastShamblers",
    ["RandomZeds.SprinterSpeedMultiplier"] = "RandomZeds_Sprinters",
}

local function getTitle(setting)
    if not setting or not setting.name then return nil end

    local normalizedName = setting.name
        :gsub("^RandomZedsNight", "RandomZeds")
        :gsub("^RandomZedsWeather", "RandomZeds")
    return TITLE_BY_OPTION[normalizedName]
end

local function addTitles(page)
    if not page or not page.settings then return false end

    local changed = false
    for _, setting in ipairs(page.settings) do
        local title = getTitle(setting)
        if title and setting.title ~= title then
            setting.title = title
            changed = true
        end
    end

    return changed
end

local getterHooked = false
local adminPanelHooked = false

local function installGetterHook()
    if getterHooked or not ServerSettingsScreen then return end

    local original = ServerSettingsScreen.getSandboxSettingsTable
    if not original then return end

    ServerSettingsScreen.getSandboxSettingsTable = function()
        local pages = original()
        for _, page in ipairs(pages) do
            addTitles(page)
        end
        return pages
    end

    getterHooked = true
end

local function addAdminTitles(panel, page)
    if not panel or not page or page.customui then return end

    local content = panel.contents or panel
    local y = 11
    local titleHeight = getTextManager():getFontFromEnum(UIFont.Large):getLineHeight() + 6
    local titles = {}

    for _, setting in ipairs(page.settings) do
        local label = panel.labels and panel.labels[setting.name]
        local control = panel.controls and panel.controls[setting.name]
        if label and control then
            local title = getTitle(setting)
            if title then
                local titleLabel = ISLabel:new(0, 0, titleHeight,
                    getText("Sandbox_Title_" .. title), 1, 1, 1, 1, UIFont.Large)
                content:addChild(titleLabel)
                titleLabel:setX((panel:getWidth() - titleLabel:getWidth()) / 2)
                titleLabel:setY(y + 20)
                table.insert(titles, titleLabel)
                y = y + titleHeight + 22
            end

            label:setY(y)
            control:setY(y)
            y = y + math.max(label:getHeight(), control:getHeight()) + 10
        end
    end

    content:setScrollHeight(y + 1)
    panel.titles = titles
end

local function installAdminPanelHook()
    if adminPanelHooked or not ISServerSandboxOptionsUI then return end

    local original = ISServerSandboxOptionsUI.createPanel
    if not original then return end

    ISServerSandboxOptionsUI.createPanel = function(self, page)
        addTitles(page)
        local panel = original(self, page)
        addAdminTitles(panel, page)
        return panel
    end

    adminPanelHooked = true
end

local function rebuildSandboxOptionsPage()
    local screen = SandboxOptionsScreen and SandboxOptionsScreen.instance
    if not screen or not screen.listbox then return end

    for _, item in ipairs(screen.listbox.items) do
        local page = item.item and item.item.page
        if addTitles(page) then
            local oldPanel = item.item.panel
            local wasCurrent = screen.currentPanel == oldPanel
            if wasCurrent then
                screen:removeChild(oldPanel)
            end

            item.item.panel = screen:createPanel(page)
            if wasCurrent then
                screen:addChild(item.item.panel)
                screen.currentPanel = item.item.panel
                screen:onPanelChange()
            end
        end
    end
end

local function rebuildHostSettingsPage()
    local screen = ServerSettingsScreen and ServerSettingsScreen.instance
    local pageEdit = screen and screen.pageEdit
    if not pageEdit or not pageEdit.listbox then return end

    for _, item in ipairs(pageEdit.listbox.items) do
        local page = item.item and item.item.page
        if addTitles(page) then
            local oldPanel = item.item.panel
            local wasCurrent = pageEdit.currentPanel == oldPanel
            if wasCurrent then
                pageEdit:removeChild(oldPanel)
            end

            item.item.panel = pageEdit:createPanel({ name = "Sandbox" }, page)
            if wasCurrent then
                pageEdit:addChild(item.item.panel)
                pageEdit.currentPanel = item.item.panel
                pageEdit:onPanelChange()
            end
        end
    end
end

local function initialize()
    installGetterHook()
    installAdminPanelHook()
    rebuildSandboxOptionsPage()
    rebuildHostSettingsPage()
end

installGetterHook()
installAdminPanelHook()
Events.OnMainMenuEnter.Add(initialize)
Events.OnGameStart.Add(installAdminPanelHook)
