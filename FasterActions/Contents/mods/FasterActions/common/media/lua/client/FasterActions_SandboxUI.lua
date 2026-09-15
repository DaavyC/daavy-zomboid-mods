local TITLE_BY_OPTION = {
    ["FasterActions.CraftingMultiplier"] = "FasterActions_ActionCategories",
    ["FasterActions.BuildingMultiplier"] = "FasterActions_ActionCategories",
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
    ["FasterActions.SafehouseCraftingMultiplier"] = "FasterActions_Safehouse",
    ["FasterActions.SafehouseBuildingMultiplier"] = "FasterActions_Safehouse",
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
    ["FasterActions.InstantMap"] = "FasterActions_QualityOfLife"
}

local function getTitle(setting)
    return setting and TITLE_BY_OPTION[setting.name]
end

local function getTitleForGroupStart(title, previousTitle)
    if title == previousTitle then
        return nil
    end
    return title
end

local function pageNeedsCustomization(page)
    local previousTitle
    for _, setting in ipairs(page and page.settings or {}) do
        local title = getTitle(setting)
        if title then
            local expectedTitle = getTitleForGroupStart(title, previousTitle)
            if setting.title ~= expectedTitle then
                return true
            end
        end
        previousTitle = title
    end
    return false
end

local function customizePage(page)
    if not pageNeedsCustomization(page) then
        return page
    end

    local customPage = copyTable(page)
    customPage.settings = {}
    local previousTitle
    for _, setting in ipairs(page.settings or {}) do
        local customSetting = copyTable(setting)
        local title = getTitle(customSetting)
        if title then
            customSetting.title = getTitleForGroupStart(title, previousTitle)
        end
        previousTitle = title
        customPage.settings[#customPage.settings + 1] = customSetting
    end
    return customPage
end

local adminPanelHooked = false

local function installAdminPanelHook()
    if adminPanelHooked or not ISServerSandboxOptionsUI then
        return
    end

    local originalCreatePanel = ISServerSandboxOptionsUI.createPanel
    if not originalCreatePanel then
        return
    end

    ISServerSandboxOptionsUI.createPanel = function(self, page)
        return originalCreatePanel(self, customizePage(page))
    end
    adminPanelHooked = true
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

local function rebuildHostPage(pageEdit, pageEntry)
    local page = pageEntry.page
    local customPage = customizePage(page)
    if customPage == page then
        return
    end

    local oldPanel = pageEntry.panel
    local wasCurrent = pageEdit.currentPanel == oldPanel
    if wasCurrent then
        pageEdit:removeChild(oldPanel)
    end

    pageEntry.page = customPage
    pageEntry.panel = pageEdit:createPanel({ name = "Sandbox" }, customPage)
    if wasCurrent then
        pageEdit:addChild(pageEntry.panel)
        pageEdit.currentPanel = pageEntry.panel
        pageEdit:onPanelChange()
    end
end

local function rebuildHostSettingsPages()
    local screen = ServerSettingsScreen and ServerSettingsScreen.instance
    local pageEdit = screen and screen.pageEdit
    if not pageEdit or not pageEdit.listbox then return end

    for _, listEntry in ipairs(pageEdit.listbox.items) do
        local pageEntry = listEntry.item
        if pageEntry and not pageEntry.category then
            rebuildHostPage(pageEdit, pageEntry)
        end
    end
end

local function initialize()
    installAdminPanelHook()
    installSandboxPanelHook()
    rebuildHostSettingsPages()
end

installAdminPanelHook()
installSandboxPanelHook()
Events.OnMainMenuEnter.Add(initialize)
Events.OnGameStart.Add(installAdminPanelHook)
