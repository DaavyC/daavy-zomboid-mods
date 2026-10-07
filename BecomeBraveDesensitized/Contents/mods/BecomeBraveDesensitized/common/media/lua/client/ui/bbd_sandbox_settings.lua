local Rules = require "bbd_shared"
local getText = getText
local getTextManager = getTextManager
local ISLabel = ISLabel
local UIFont = UIFont
local Events = Events
local max = math.max
local copyTable = copyTable
local newarray = table.newarray
local titles = {
    [Rules.ID .. ".BraveKills"] = Rules.ID .. "_Progression",
    [Rules.ID .. ".BraveBlock"] = Rules.ID .. "_Penalties",
    [Rules.ID .. ".HunterKillReduction"] = Rules.ID .. "_Benefits",
    [Rules.ID .. ".EarlyTraits"] = Rules.ID .. "_Chance",
    [Rules.ID .. ".Debug"] = Rules.ID .. "_Advanced",
}
local minimumOptions = newarray(Rules.ID .. ".BraveMinKills", Rules.ID .. ".DesensitizedMinKills")
local menuHooked = false
local hostHooked = false
local adminHooked = false

local function isModPage(page)
    if not page or not page.settings then return false end
    local settings = page.settings
    local prefix = Rules.ID .. "."
    for index = 1, #settings do
        if settings[index].name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function preparePage(page)
    if not isModPage(page) or page.bbdStyled then return page end
    local styled = copyTable(page)
    local settings = page.settings
    styled.settings = newarray()
    for index = 1, #settings do
        local setting = copyTable(settings[index])
        setting.title = titles[setting.name]
        styled.settings[index] = setting
    end
    styled.bbdStyled = true
    return styled
end

local function prepareAdminPage(page)
    local styled = preparePage(page)
    if not isModPage(styled) then return styled end
    local adminPage = copyTable(styled)
    adminPage.settings = newarray()
    local settings = styled.settings
    for index = 1, #settings do
        local setting = copyTable(settings[index])
        setting.title = nil
        adminPage.settings[index] = setting
    end
    return adminPage
end

local function shiftRows(panel, y, amount)
    local children = panel:getChildrenInOrder()
    for index = 1, #children do
        local child = children[index]
        local childY = child:getY()
        if childY >= y then child:setY(childY + amount) end
    end
end

local function addTitle(panel, setting)
    local title = titles[setting.name]
    local row = panel.labels[setting.name]
    if not title or not row then return end
    local height = getTextManager():getFontFromEnum(UIFont.Large):getLineHeight() + 6
    local y = row:getY()
    shiftRows(panel, y, height + 22)
    local label = ISLabel:new(0, 0, height, getText("Sandbox_Title_" .. title), 1, 1, 1, 1, UIFont.Large)
    panel:addChild(label)
    panel.bbdHeaders[#panel.bbdHeaders + 1] = label
    label:setX((panel:getWidth() - label:getWidth()) / 2)
    label:setY(y + 20)
    panel:setScrollHeight(panel:getScrollHeight() + height + 22)
end

local function addTitles(panel, page)
    if not isModPage(page) or panel.bbdHeaders then return end
    panel.bbdHeaders = newarray()
    local settings = page.settings
    for index = 1, #settings do addTitle(panel, settings[index]) end
end

local function columnWidths(panel, page)
    local labelWidth, controlWidth = 0, 0
    local settings = page.settings
    for index = 1, #settings do
        local name = settings[index].name
        local label, control = panel.labels[name], panel.controls[name]
        if label and control then
            labelWidth = max(labelWidth, label:getWidth())
            controlWidth = max(controlWidth, control:getWidth())
        end
    end
    return labelWidth, controlWidth
end

local function centerHeaders(panel)
    local panelWidth = panel:getWidth()
    local headers = panel.bbdHeaders
    for index = 1, #headers do
        local header = headers[index]
        header:setX((panelWidth - header:getWidth()) / 2)
    end
end

local function centerPanel(panel, page)
    if not isModPage(page) then return end
    local labelWidth, controlWidth = columnWidths(panel, page)
    local panelWidth = panel:getWidth()
    local x = (panelWidth - labelWidth - 10 - controlWidth) / 2
    local settings = page.settings
    for index = 1, #settings do
        local name = settings[index].name
        local label, control = panel.labels[name], panel.controls[name]
        if label and control then
            label:setX(x + labelWidth - label:getWidth())
            control:setX(x + labelWidth + 10)
        end
    end
    centerHeaders(panel)
end

local function updateMinimumControls(panel)
    local toggle = panel.controls[Rules.ID .. ".EarlyTraits"]
    local enabled = toggle:isSelected(1)
    if panel.bbdEarlyTraitsEnabled == enabled then return end
    panel.bbdEarlyTraitsEnabled = enabled
    local color = enabled and 1 or 0.6
    for index = 1, #minimumOptions do
        local name = minimumOptions[index]
        panel.controls[name]:setEditable(enabled)
        panel.labels[name]:setColor(color, color, color)
    end
end

local function attachEarlyTraitControls(panel, page)
    if not isModPage(page) or panel.bbdEarlyTraitsHooked then return end
    local original = panel.prerender
    panel.prerender = function(self)
        updateMinimumControls(self)
        original(self)
    end
    panel.bbdEarlyTraitsHooked = true
    updateMinimumControls(panel)
end

local function installMenuHook()
    if menuHooked or not SandboxOptionsScreen or not SandboxOptionsScreen.createPanel then return end
    local original = SandboxOptionsScreen.createPanel
    SandboxOptionsScreen.createPanel = function(self, page)
        local styled = preparePage(page)
        local panel = original(self, styled)
        attachEarlyTraitControls(panel, styled)
        return panel
    end
    menuHooked = true
end

local function replaceHostPanel(editor, entry, page)
    local wasCurrent = editor.currentPanel == entry.panel
    if wasCurrent then editor:removeChild(entry.panel) end
    entry.page = page
    entry.panel = editor:createPanel({ name = "Sandbox" }, page)
    attachEarlyTraitControls(entry.panel, page)
    if wasCurrent then
        editor:addChild(entry.panel)
        editor.currentPanel = entry.panel
        editor:onPanelChange()
    end
end

local function rebuildHostPages(screen)
    local editor = screen and screen.pageEdit
    if not editor or not editor.listbox then return end
    local entries = editor.listbox.items
    for index = 1, #entries do
        local entry = entries[index].item
        if entry and entry.page and not entry.category then
            local styled = preparePage(entry.page)
            if styled ~= entry.page then replaceHostPanel(editor, entry, styled) end
        end
    end
end

local function installHostHook()
    if hostHooked or not ServerSettingsScreen or not ServerSettingsScreen.create then return end
    local original = ServerSettingsScreen.create
    ServerSettingsScreen.create = function(self)
        original(self)
        rebuildHostPages(self)
    end
    hostHooked = true
    rebuildHostPages(ServerSettingsScreen.instance)
end

local function installAdminHook()
    if adminHooked or not ISServerSandboxOptionsUI or not ISServerSandboxOptionsUI.createPanel then return end
    local original = ISServerSandboxOptionsUI.createPanel
    ISServerSandboxOptionsUI.createPanel = function(self, page)
        local styled = prepareAdminPage(page)
        local panel = original(self, styled)
        addTitles(panel, styled)
        attachEarlyTraitControls(panel, styled)
        centerPanel(panel, styled)
        return panel
    end
    local originalSelect = ISServerSandboxOptionsUI.onMouseDownListbox
    ISServerSandboxOptionsUI.onMouseDownListbox = function(self, entry)
        originalSelect(self, entry)
        if entry and entry.page and entry.panel then centerPanel(entry.panel, entry.page) end
    end
    adminHooked = true
end

local function initializeSettings()
    installMenuHook()
    installHostHook()
    installAdminHook()
end

initializeSettings()
Events.OnMainMenuEnter.Add(initializeSettings)
Events.OnGameStart.Add(initializeSettings)
