local OPTION_PREFIX = "FasterActions."
local TITLE_BY_OPTION = {
    ["FasterActions.CraftingMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.BlacksmithingMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.BuildingMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.WoodcuttingMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.MechanicMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.WeldingMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.RippingMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.SawingMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.CarvingMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.KnappingMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.CleaningMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.TailoringMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.EquipMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.InventoryMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.OtherMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.SafehouseEnabled"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseCraftingMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseBlacksmithingMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseBuildingMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseWoodcuttingMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseMechanicMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseWeldingMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseRippingMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseSawingMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseCarvingMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseKnappingMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseCleaningMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseTailoringMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseEquipMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseInventoryMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseOtherMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.InstantHood"] = "FasterActions_QualityOfLife",
    ["FasterActions.InstantMap"] = "FasterActions_QualityOfLife",
    ["FasterActions.CorpseDraggingSpeedMultiplier"] = "FasterActions_QualityOfLife",
    ["FasterActions.Debug"] = "FasterActions_Advanced"
}

local function getTitle(setting)
    if not setting or type(setting.name) ~= "string" then return nil end
    return TITLE_BY_OPTION[setting.name]
end

local function getTitleForGroupStart(title, previousTitle)
    return title ~= previousTitle and title or nil
end

local function isFasterActionsPage(page)
    local settings = page and page.settings
    if not settings then return false end

    for index = 1, #settings do
        local setting = settings[index]
        if setting and type(setting.name) == "string"
                and setting.name:sub(1, #OPTION_PREFIX) == OPTION_PREFIX then
            return true
        end
    end
    return false
end

local function pageNeedsCustomization(page)
    local settings = page and page.settings
    if not settings then return false end

    local previousTitle
    for index = 1, #settings do
        local setting = settings[index]
        local title = getTitle(setting)
        if title and setting.title ~= getTitleForGroupStart(title, previousTitle) then
            return true
        end
        previousTitle = title
    end
    return false
end

local function copyPage(page)
    local pageCopy = copyTable(page)
    pageCopy.settings = table.newarray()
    local previousTitle
    local settings = page.settings
    for index = 1, #settings do
        local settingCopy = copyTable(settings[index])
        local title = getTitle(settingCopy)
        if title then
            settingCopy.title = getTitleForGroupStart(title, previousTitle)
        end
        previousTitle = title
        pageCopy.settings[#pageCopy.settings + 1] = settingCopy
    end
    return pageCopy
end

local function customizePage(page)
    if not page or not page.settings or not pageNeedsCustomization(page) then
        return page
    end
    return copyPage(page)
end

local function shiftPanelChildren(panel, y, amount)
    local children = panel:getChildrenInOrder()
    for index = 1, #children do
        local child = children[index]
        if child:getY() >= y then
            child:setY(child:getY() + amount)
        end
    end
end

local function trackFasterActionsHeader(panel, label)
    if not panel.fasterActionsHeaders then
        panel.fasterActionsHeaders = table.newarray()
    end
    panel.fasterActionsHeaders[#panel.fasterActionsHeaders + 1] = label
end

local function hasFasterActionsTitle(panel, setting)
    return setting and setting.title and panel.labels[setting.name] ~= nil
end

local function addFasterActionsTitle(panel, setting, titleHeight, titleAmount)
    local title = setting and setting.title
    local row = panel.labels[setting.name]
    local y = row:getY()
    shiftPanelChildren(panel, y, titleAmount)
    local label = ISLabel:new(
        0, 0, titleHeight, getText("Sandbox_Title_" .. title),
        1, 1, 1, 1, UIFont.Large)
    panel:addChild(label)
    trackFasterActionsHeader(panel, label)
    label:setX((panel:getWidth() - label:getWidth()) / 2)
    label:setY(y + 20)
end

local function addFasterActionsTitles(panel, page)
    if not panel or not page or not page.settings or not panel.labels then return end
    if not isFasterActionsPage(page) or panel.fasterActionsTitles then return end

    local titleHeight = getTextManager():getFontFromEnum(UIFont.Large):getLineHeight() + 6
    local titleAmount = titleHeight + 22
    local addedHeight = 0
    local settings = page.settings
    for index = 1, #settings do
        local setting = settings[index]
        if hasFasterActionsTitle(panel, setting) then
            addFasterActionsTitle(panel, setting, titleHeight, titleAmount)
            addedHeight = addedHeight + titleAmount
        end
    end

    if addedHeight > 0 then
        panel:setScrollHeight(panel:getScrollHeight() + addedHeight)
    end
    panel.fasterActionsTitles = true
end

local IN_GAME_SETTINGS_SPACING = 10

local function getSettingsColumnWidths(panel, settings)
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
    return labelWidth, controlWidth
end

local function centerSettingsRows(panel, settings, labelWidth, controlWidth)
    local contentWidth = labelWidth + IN_GAME_SETTINGS_SPACING + controlWidth
    local contentX = (panel:getWidth() - contentWidth) / 2
    for index = 1, #settings do
        local setting = settings[index]
        local label = setting and panel.labels[setting.name]
        local control = setting and panel.controls[setting.name]
        if label and control then
            label:setX(contentX + labelWidth - label:getWidth())
            control:setX(contentX + labelWidth + IN_GAME_SETTINGS_SPACING)
        end
    end
end

local function centerFasterActionsHeaders(panel)
    local headers = panel.fasterActionsHeaders
    if headers then
        for index = 1, #headers do
            local header = headers[index]
            header:setX((panel:getWidth() - header:getWidth()) / 2)
        end
    end
end

local function centerInGameSettings(panel, page)
    if not panel or not page or not page.settings
            or not panel.labels or not panel.controls then
        return
    end
    if not isFasterActionsPage(page) then return end

    local settings = page.settings
    local labelWidth, controlWidth = getSettingsColumnWidths(panel, settings)
    if labelWidth == 0 or controlWidth == 0 then return end
    centerSettingsRows(panel, settings, labelWidth, controlWidth)
    centerFasterActionsHeaders(panel)
end

local sandboxPanelHooked = false

local function installSandboxPanelHook()
    if sandboxPanelHooked or not SandboxOptionsScreen or not SandboxOptionsScreen.createPanel then
        return
    end

    local originalCreatePanel = SandboxOptionsScreen.createPanel
    SandboxOptionsScreen.createPanel = function(self, page)
        return originalCreatePanel(self, customizePage(page))
    end
    sandboxPanelHooked = true
end

local function replaceHostSettingsPage(pageEdit, pageEntry, customPage)
    local oldPanel = pageEntry.panel
    local wasCurrent = pageEdit.currentPanel == oldPanel
    if wasCurrent then pageEdit:removeChild(oldPanel) end

    pageEntry.page = customPage
    pageEntry.panel = pageEdit:createPanel({ name = "Sandbox" }, customPage)
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
            local customPage = customizePage(pageEntry.page)
            if customPage ~= pageEntry.page then
                replaceHostSettingsPage(pageEdit, pageEntry, customPage)
            end
        end
    end
end

local hostSettingsScreenHooked = false

local function installHostSettingsScreenHook()
    if hostSettingsScreenHooked or not ServerSettingsScreen or not ServerSettingsScreen.create then
        return
    end

    local originalCreate = ServerSettingsScreen.create
    ServerSettingsScreen.create = function(self)
        originalCreate(self)
        rebuildHostSettingsPages(self)
    end
    hostSettingsScreenHooked = true
end

local inGameSandboxPanelHooked = false

local function installInGameSandboxPanelHook()
    if inGameSandboxPanelHooked or not ISServerSandboxOptionsUI
            or not ISServerSandboxOptionsUI.createPanel then
        return
    end

    local originalCreatePanel = ISServerSandboxOptionsUI.createPanel
    ISServerSandboxOptionsUI.createPanel = function(self, page)
        local customPage = customizePage(page)
        local panel = originalCreatePanel(self, customPage)
        addFasterActionsTitles(panel, customPage)
        centerInGameSettings(panel, customPage)
        return panel
    end
    inGameSandboxPanelHooked = true
end

local inGameListboxHooked = false

local function installInGameListboxHook()
    if inGameListboxHooked or not ISServerSandboxOptionsUI
            or not ISServerSandboxOptionsUI.onMouseDownListbox then
        return
    end
    local originalOnMouseDownListbox = ISServerSandboxOptionsUI.onMouseDownListbox
    ISServerSandboxOptionsUI.onMouseDownListbox = function(self, item)
        originalOnMouseDownListbox(self, item)
        if item and item.page and item.panel then
            centerInGameSettings(item.panel, item.page)
        end
    end
    inGameListboxHooked = true
end

local function installInGameSandboxOptionsHook()
    installInGameSandboxPanelHook()
    installInGameListboxHook()
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
