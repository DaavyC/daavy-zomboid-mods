require "acr_shared"

local ACR = AdminCharacterRestore

local TITLE_BY_OPTION = {
    ["AdminCharacterRestore.SnapshotIntervalHours"] = "AdminCharacterRestore_Snapshots",
    ["AdminCharacterRestore.Debug"] = "AdminCharacterRestore_Advanced"
}

local function shiftPanelChildren(panel, y, amount)
    local children = panel:getChildrenInOrder()
    for index = 1, #children do
        local child = children[index]
        if child:getY() >= y then child:setY(child:getY() + amount) end
    end
end

local function addSandboxPageTitle(panel, setting, titleHeight, titleAmount)
    local title = setting and setting.title
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

local function copyPage(page)
    local copy = copyTable(page)
    copy.settings = table.newarray()
    for index = 1, #(page.settings or {}) do
        local setting = page.settings[index]
        copy.settings[index] = copyTable(setting)
    end
    return copy
end

local function createHostPage(page)
    if not page or not page.settings then return page end

    for index = 1, #page.settings do
        local setting = page.settings[index]
        if TITLE_BY_OPTION[setting.name] then
            local hostPage = copyPage(page)
            ACR.debug("Customizing Admin Character Restore sandbox page")
            for settingIndex = 1, #hostPage.settings do
                local hostSetting = hostPage.settings[settingIndex]
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

    for index = 1, #pageEdit.listbox.items do
        local item = pageEdit.listbox.items[index]
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

local inGameSandboxPanelHooked = false

local function installInGameSandboxPanelHook()
    if inGameSandboxPanelHooked or not ISServerSandboxOptionsUI
            or not ISServerSandboxOptionsUI.createPanel then return end

    local original = ISServerSandboxOptionsUI.createPanel
    ISServerSandboxOptionsUI.createPanel = function (self, page)
        local hostPage = createHostPage(page)
        local panel = original(self, hostPage)
        addSandboxPageTitles(panel, hostPage)
        return panel
    end
    inGameSandboxPanelHooked = true
    ACR.debug("In-game sandbox panel title hook installed")
end

local function initialize()
    installSandboxPanelHook()
    installInGameSandboxPanelHook()
    rebuildHostSettingsPage()
end

installSandboxPanelHook()
installInGameSandboxPanelHook()
Events.OnMainMenuEnter.Add(initialize)
Events.OnGameStart.Add(installInGameSandboxPanelHook)
