local sectionTitles = {
    ["MoonlightPhases.NewMoon"] = "MoonlightPhases_MoonPhases",
    ["MoonlightPhases.WeatherEnabled"] = "MoonlightPhases_Weather",
    ["MoonlightPhases.InterfaceEnabled"] = "MoonlightPhases_Interface",
    ["MoonlightPhases.Debug"] = "MoonlightPhases_Advanced",
}
local pairs = pairs
local max = math.max
local getText = getText
local getTextManager = getTextManager
local isClient = isClient
local menuHooked = false
local hostHooked = false
local inGameHooked = false

local function isMoonlightPage(page)
    if not page or not page.settings then return false end
    for index = 1, #page.settings do
        if page.settings[index].name:match("^MoonlightPhases%.") then return true end
    end
    return false
end

local function shallowCopy(source)
    local copied = {}
    for key, entry in pairs(source) do copied[key] = entry end
    return copied
end

local function menuPage(page)
    if not isMoonlightPage(page) or page.moonlightPhasesStyled then return page end
    local styled = shallowCopy(page)
    styled.settings = table.newarray()
    for index = 1, #page.settings do
        local setting = shallowCopy(page.settings[index])
        setting.title = sectionTitles[setting.name]
        styled.settings[index] = setting
    end
    styled.moonlightPhasesStyled = true
    return styled
end

local function inGamePage(page)
    if not isMoonlightPage(page) then return page end
    local styled = shallowCopy(menuPage(page))
    styled.settings = table.newarray()
    for index = 1, #page.settings do
        local setting = shallowCopy(page.settings[index])
        setting.title = nil
        styled.settings[index] = setting
    end
    return styled
end

local function shiftRows(panel, y, amount)
    local children = panel:getChildrenInOrder()
    for index = 1, #children do
        local child = children[index]
        local childY = child:getY()
        if childY >= y then child:setY(childY + amount) end
    end
end

local function insertSectionTitle(panel, setting)
    local title = sectionTitles[setting.name]
    if not title then return end
    local height = getTextManager():getFontFromEnum(UIFont.Large):getLineHeight() + 6
    local y = panel.labels[setting.name]:getY()
    shiftRows(panel, y, height + 22)
    local label = ISLabel:new(0, 0, height, getText("Sandbox_Title_" .. title), 1, 1, 1, 1, UIFont.Large)
    panel:addChild(label)
    panel.moonlightPhasesHeaders[#panel.moonlightPhasesHeaders + 1] = label
    label:setX((panel:getWidth() - label:getWidth()) / 2)
    label:setY(y + 20)
    panel:setScrollHeight(panel:getScrollHeight() + height + 22)
end

local function insertSectionTitles(panel, page)
    if not isMoonlightPage(page) or panel.moonlightPhasesHeaders then return end
    panel.moonlightPhasesHeaders = table.newarray()
    for index = 1, #page.settings do
        insertSectionTitle(panel, page.settings[index])
    end
end

local function columnWidths(panel, page)
    local labelWidth, controlWidth = 0, 0
    for index = 1, #page.settings do
        local name = page.settings[index].name
        labelWidth = max(labelWidth, panel.labels[name]:getWidth())
        controlWidth = max(controlWidth, panel.controls[name]:getWidth())
    end
    return labelWidth, controlWidth
end

local function centerInGamePanel(panel, page)
    if not isMoonlightPage(page) then return end
    local labelWidth, controlWidth = columnWidths(panel, page)
    local panelWidth = panel:getWidth()
    local x = (panelWidth - labelWidth - 10 - controlWidth) / 2
    for index = 1, #page.settings do
        local name = page.settings[index].name
        local label = panel.labels[name]
        label:setX(x + labelWidth - label:getWidth())
        panel.controls[name]:setX(x + labelWidth + 10)
    end
    local headers = panel.moonlightPhasesHeaders
    for index = 1, #headers do
        local header = headers[index]
        header:setX((panelWidth - header:getWidth()) / 2)
    end
end

local function installMenuHook()
    if menuHooked or not SandboxOptionsScreen then return end
    local originalCreatePanel = SandboxOptionsScreen.createPanel
    SandboxOptionsScreen.createPanel = function(self, page)
        return originalCreatePanel(self, menuPage(page))
    end
    menuHooked = true
end

local function replaceHostPanel(editor, entry, page)
    local wasCurrent = editor.currentPanel == entry.panel
    if wasCurrent then editor:removeChild(entry.panel) end
    entry.page = page
    entry.panel = editor:createPanel({ name = "Sandbox" }, page)
    if wasCurrent then
        editor:addChild(entry.panel)
        editor.currentPanel = entry.panel
        editor:onPanelChange()
    end
end

local function styleHostPages(screen)
    local editor = screen and screen.pageEdit
    if not editor or not editor.listbox then return end
    local entries = editor.listbox.items
    for index = 1, #entries do
        local entry = entries[index].item
        if entry.page and not entry.category then
            local styled = menuPage(entry.page)
            if styled ~= entry.page then replaceHostPanel(editor, entry, styled) end
        end
    end
end

local function installHostHook()
    if hostHooked or not ServerSettingsScreen then return end
    local originalCreate = ServerSettingsScreen.create
    ServerSettingsScreen.create = function(self)
        originalCreate(self)
        styleHostPages(self)
    end
    hostHooked = true
    styleHostPages(ServerSettingsScreen.instance)
end

local function installInGameSelectionHook()
    local originalSelect = ISServerSandboxOptionsUI.onMouseDownListbox
    ISServerSandboxOptionsUI.onMouseDownListbox = function(self, entry)
        originalSelect(self, entry)
        if entry.page and entry.panel then centerInGamePanel(entry.panel, entry.page) end
    end
end

local function installInGameApplyHook()
    local originalSettingsFromUI = ISServerSandboxOptionsUI.settingsFromUI
    ISServerSandboxOptionsUI.settingsFromUI = function(self, options)
        originalSettingsFromUI(self, options)
        if isClient() then return end
        for index = 0, options:getNumOptions() - 1 do
            local option = options:getOptionByIndex(index)
            if option:getTableName() == "MoonlightPhases" then option:toTable(SandboxVars) end
        end
    end
end

local function installInGameHook()
    if inGameHooked or not ISServerSandboxOptionsUI then return end
    local originalCreatePanel = ISServerSandboxOptionsUI.createPanel
    ISServerSandboxOptionsUI.createPanel = function(self, page)
        local styled = inGamePage(page)
        local panel = originalCreatePanel(self, styled)
        insertSectionTitles(panel, styled)
        centerInGamePanel(panel, styled)
        return panel
    end
    installInGameSelectionHook()
    installInGameApplyHook()
    inGameHooked = true
end

local function initializeSettings()
    installMenuHook()
    installHostHook()
    installInGameHook()
end

initializeSettings()
Events.OnMainMenuEnter.Add(initializeSettings)
Events.OnGameStart.Add(initializeSettings)
