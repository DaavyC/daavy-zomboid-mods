require "AdminCharacterRestoreShared"

local ACR = AdminCharacterRestore

local TITLE_BY_OPTION = {
    ["AdminCharacterRestore.SnapshotIntervalHours"] = "AdminCharacterRestore_Snapshots",
    ["AdminCharacterRestore.Debug"] = "AdminCharacterRestore_Advanced"
}

local function copyPage(page)
    local copy = copyTable(page)
    copy.settings = {}
    for index, setting in ipairs(page.settings or {}) do
        copy.settings[index] = copyTable(setting)
    end
    return copy
end

local function createHostPage(page)
    if not page or not page.settings then return page end

    for _, setting in ipairs(page.settings) do
        if TITLE_BY_OPTION[setting.name] then
            local hostPage = copyPage(page)
            ACR.debug("Customizing Admin Character Restore sandbox page")
            for _, hostSetting in ipairs(hostPage.settings) do
                hostSetting.title = TITLE_BY_OPTION[hostSetting.name]
            end
            return hostPage
        end
    end

    return page
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
            if wasCurrent then pageEdit:removeChild(oldPanel) end

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

local sandboxPanelHooked = false

local function installSandboxPanelHook()
    if sandboxPanelHooked or not SandboxOptionsScreen or not SandboxOptionsScreen.createPanel then return end

    local original = SandboxOptionsScreen.createPanel
    SandboxOptionsScreen.createPanel = function (self, page)
        return original(self, createHostPage(page))
    end
    sandboxPanelHooked = true
    ACR.debug("Sandbox options title hook installed")
end

local function initialize()
    installSandboxPanelHook()
    rebuildHostSettingsPage()
end

installSandboxPanelHook()
Events.OnMainMenuEnter.Add(initialize)
