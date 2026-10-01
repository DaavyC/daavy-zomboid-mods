local titles = {
    ["HighBeams.DistanceMultiplier"] = "HighBeams_Headlights",
    ["HighBeams.Debug"] = "HighBeams_Advanced",
}
local pairs = pairs
local max = math.max
local getText = getText
local getTextManager = getTextManager
local menuHooked = false
local hostHooked = false
local adminHooked = false

local function isBeamPage(page)
    if not page or not page.settings then return false end
    for index = 1, #page.settings do
        if page.settings[index].name:match("^HighBeams%.") then return true end
    end
    return false
end

local function copyTable(source)
    local copy = {}
    for key, entry in pairs(source) do copy[key] = entry end
    return copy
end

local function preparePage(page)
    if not isBeamPage(page) or page.highBeamsStyled then return page end
    local styled = copyTable(page)
    styled.settings = table.newarray()
    for index = 1, #page.settings do
        local setting = copyTable(page.settings[index])
        setting.title = nil
        styled.settings[index] = setting
    end
    styled.highBeamsStyled = true
    return styled
end

local function shiftRows(panel, y, amount)
    local children = panel:getChildrenInOrder()
    for index = 1, #children do
        local child = children[index]
        if child:getY() >= y then child:setY(child:getY() + amount) end
    end
end

local function addTitle(panel, setting)
    local title = titles[setting.name]
    local row = panel.labels[setting.name]
    if not title or not row then return 0 end
    local height = getTextManager():getFontFromEnum(UIFont.Large):getLineHeight() + 6
    local y = row:getY()
    shiftRows(panel, y, height + 22)
    local label = ISLabel:new(0, 0, height, getText("Sandbox_Title_" .. title), 1, 1, 1, 1, UIFont.Large)
    panel:addChild(label)
    panel.highBeamsHeaders[#panel.highBeamsHeaders + 1] = label
    if panel.titles then panel.titles[#panel.titles + 1] = label end
    label:setX((panel:getWidth() - label:getWidth()) / 2)
    label:setY(y + 20)
    return height + 22
end

local function decoratePanel(panel, page)
    if not isBeamPage(page) or panel.highBeamsHeaders then return panel end
    panel.highBeamsHeaders = table.newarray()
    local addedHeight = 0
    for index = 1, #page.settings do addedHeight = addedHeight + addTitle(panel, page.settings[index]) end
    panel:setScrollHeight(panel:getScrollHeight() + addedHeight)
    return panel
end

local function columnWidths(panel, page)
    local labelWidth, controlWidth = 0, 0
    for index = 1, #page.settings do
        local name = page.settings[index].name
        local label, control = panel.labels[name], panel.controls[name]
        if label and control then
            labelWidth = max(labelWidth, label:getWidth())
            controlWidth = max(controlWidth, control:getWidth())
        end
    end
    return labelWidth, controlWidth
end

local function centerHeaders(panel)
    local headers = panel.highBeamsHeaders
    for index = 1, #headers do
        local header = headers[index]
        header:setX((panel:getWidth() - header:getWidth()) / 2)
    end
end

local function centerPanel(panel, page)
    if not isBeamPage(page) then return panel end
    local labelWidth, controlWidth = columnWidths(panel, page)
    local x = (panel:getWidth() - labelWidth - 10 - controlWidth) / 2
    for index = 1, #page.settings do
        local name = page.settings[index].name
        local label, control = panel.labels[name], panel.controls[name]
        if label and control then
            label:setX(x + labelWidth - label:getWidth())
            control:setX(x + labelWidth + 10)
        end
    end
    centerHeaders(panel)
    return panel
end

local function installMenuHook()
    if menuHooked or not SandboxOptionsScreen then return end
    local original = SandboxOptionsScreen.createPanel
    SandboxOptionsScreen.createPanel = function(self, page)
        local styled = preparePage(page)
        return decoratePanel(original(self, styled), styled)
    end
    menuHooked = true
end

local function replaceHostPanel(editor, entry, page)
    local wasCurrent = editor.currentPanel == entry.panel
    if wasCurrent then editor:removeChild(entry.panel) end
    entry.page = page
    entry.panel = decoratePanel(editor:createPanel({ name = "Sandbox" }, page), page)
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
        if entry.page and not entry.category then
            local styled = preparePage(entry.page)
            if styled ~= entry.page then replaceHostPanel(editor, entry, styled) end
        end
    end
end

local function installHostHook()
    if hostHooked or not ServerSettingsScreen then return end
    local original = ServerSettingsScreen.create
    ServerSettingsScreen.create = function(self)
        original(self)
        rebuildHostPages(self)
    end
    hostHooked = true
    rebuildHostPages(ServerSettingsScreen.instance)
end

local function installAdminHook()
    if adminHooked or not ISServerSandboxOptionsUI then return end
    local original = ISServerSandboxOptionsUI.createPanel
    ISServerSandboxOptionsUI.createPanel = function(self, page)
        local styled = preparePage(page)
        return centerPanel(decoratePanel(original(self, styled), styled), styled)
    end
    local originalSelect = ISServerSandboxOptionsUI.onMouseDownListbox
    ISServerSandboxOptionsUI.onMouseDownListbox = function(self, entry)
        originalSelect(self, entry)
        if entry.page and entry.panel then centerPanel(entry.panel, entry.page) end
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
