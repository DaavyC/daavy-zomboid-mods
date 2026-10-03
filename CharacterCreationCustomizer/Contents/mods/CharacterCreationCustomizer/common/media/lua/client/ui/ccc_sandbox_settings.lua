local M = require "ccc_shared"

local standardEntry
local standardGroupRank
local SETTING_METADATA_KEYS = table.newarray("tooltip", "title", "translatedName", "standardTitle", "subtitle")

local groupOrder = {
    QOL = 1,
    Advanced = 2,
    PositiveTraits = 1,
    NegativeTraits = 2,
    NonBuyableTraits = 3,
    Professions = 1,
}

local fixedSettingGroups = {
    QOL = "QOL",
    Advanced = "Advanced",
    Professions = "Professions",
    NonBuyableTraits = "NonBuyableTraits",
}

local sandboxTitleKeys = {
    QOL = "Sandbox_Title_QOL",
    Advanced = "Sandbox_Title_Advanced",
    PositiveTraits = "Sandbox_Title_PositiveTraits",
    NegativeTraits = "Sandbox_Title_NegativeTraits",
    NonBuyableTraits = "Sandbox_Title_NonBuyableTraits",
    Professions = "Sandbox_Title_Professions",
}

local partOrder = {
    InitialLevel = 1,
    Disable = 1,
    Buyable = 1,
    Cost = 2,
    GrantedTraits = 3,
    GrantedItems = 4,
}

local settingTooltipKeys = {
    QOL = {
        ShowSkillLevels_Enabled = "Sandbox_CharacterCreationCustomizer_QOL_ShowSkillLevels_tooltip",
        ShowXPMultiplier_Enabled = "Sandbox_CharacterCreationCustomizer_QOL_ShowXPMultiplier_tooltip",
        ShowProfessionPoints_Enabled = "Sandbox_CharacterCreationCustomizer_QOL_ShowProfessionPoints_tooltip",
    },
    Advanced = {
        Debug_Enabled = "Sandbox_CharacterCreationCustomizer_Debug_tooltip",
    },
    Standard = {
        InitialLevel = "Sandbox_CharacterCreationCustomizer_InitialLevel_tooltip",
    },
    Traits = {
        Disable = "Sandbox_CharacterCreationCustomizer_TraitDisable_tooltip",
        Cost = "Sandbox_CharacterCreationCustomizer_TraitCost_tooltip",
    },
    NonBuyableTraits = {
        Buyable = "Sandbox_CharacterCreationCustomizer_TraitBuyable_tooltip",
        Cost = "Sandbox_CharacterCreationCustomizer_TraitCost_tooltip",
    },
    Professions = {
        Disable = "Sandbox_CharacterCreationCustomizer_ProfessionDisable_tooltip",
        Cost = "Sandbox_CharacterCreationCustomizer_ProfessionCost_tooltip",
        GrantedTraits = "Sandbox_CharacterCreationCustomizer_GrantedTraits_tooltip",
        GrantedItems = "Sandbox_CharacterCreationCustomizer_GrantedItems_tooltip",
    },
}

local function trimTooltipText(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function automaticTooltip(setting)
    local option = getSandboxOptions():getOptionByName(setting.name)
    if not option then error("Missing sandbox option: " .. setting.name) end
    return (option:getTooltip() or ""):gsub("\\n", "\n")
end

local function tooltipRemainder(automaticText, descriptionText)
    if automaticText == descriptionText then return "" end
    if automaticText:sub(1, #descriptionText) ~= descriptionText then return automaticText end
    if automaticText:sub(#descriptionText + 1, #descriptionText + 1) ~= "\n" then return automaticText end
    return trimTooltipText(automaticText:sub(#descriptionText + 2))
end

local function composeTooltip(setting, description)
    local descriptionText = trimTooltipText(description)
    local automaticText = trimTooltipText(automaticTooltip(setting))
    if automaticText == "" then return descriptionText end
    if descriptionText == "" then return automaticText end
    local automaticRemainder = tooltipRemainder(automaticText, descriptionText)
    if automaticRemainder == "" then return descriptionText end
    return descriptionText .. "\n" .. automaticRemainder
end

local function settingParts(setting)
    if not setting or not setting.name then return end
    return setting.name:match("^CharacterCreationCustomizer%.([^_]+)_(.+)_(%w+)$")
end

local function tooltipKeyFor(section, key, part)
    local entries = settingTooltipKeys[section]
    return entries and (entries[key .. "_" .. part] or entries[part])
end

local function settingGroup(setting)
    local section, key = settingParts(setting)
    local fixedGroup = rawget(fixedSettingGroups, section)
    if fixedGroup then return fixedGroup end
    if section == "Standard" then
        local entry = standardEntry(key)
        return entry and entry.group
    end
    if section == "Traits" then
        M.rememberTraits()
        local definition = M.originalTraitDefinitionsByShortKey[key]
        return definition and M.traitGroup(definition)
    end
end

local function settingRank(setting)
    local _, key = settingParts(setting)
    local entry = standardEntry(key)
    return entry and entry.order or 100000
end

local function titleText(group)
    local titleKey = rawget(sandboxTitleKeys, group)
    if titleKey then return getText(titleKey) end
    group = tostring(group):gsub("^Perks%.", "")
    if group == "Farming" then
        group = "FarmingCategory"
    end
    local title = getText("IGUI_perks_" .. group)
    if title == "IGUI_perks_" .. group then
        title = group
    end
    return title
end

local function isSubtitleSetting(section, key, part)
    return part == "InitialLevel"
        or part == "Disable"
        or part == "Buyable"
        or (section == "Professions" and key == "unemployed" and part == "Cost")
end

local professionRanks

local function professionRank(key)
    if not professionRanks then
        professionRanks = {}
        local professions = table.newarray()
        local definitionList = CharacterProfessionDefinition.getProfessions()
        for i = 0, definitionList:size() - 1 do
            professions[#professions + 1] = definitionList:get(i)
        end
        table.sort(professions, function(a, b)
            local aUnemployed = a:getType() == CharacterProfession.UNEMPLOYED
            local bUnemployed = b:getType() == CharacterProfession.UNEMPLOYED
            if aUnemployed or bUnemployed then return aUnemployed and not bUnemployed end
            return not string.sort(a:getUIName(), b:getUIName())
        end)
        for rank = 1, #professions do
            professionRanks[M.professionKey(professions[rank])] = rank
        end
    end
    return professionRanks[key] or 100000
end

local function settingLabel(setting)
    local section, key = settingParts(setting)
    if section == "Standard" then
        local entry = standardEntry(key)
        if entry then return PerkFactory.getPerkName(entry.perk) end
    elseif section == "Traits" or section == "NonBuyableTraits" then
        M.rememberTraits()
        local definition = M.originalTraitDefinitionsByShortKey[key]
        return definition and definition:getLabel() or key
    elseif section == "Professions" then
        local professions = CharacterProfessionDefinition.getProfessions()
        for i = 0, professions:size() - 1 do
            local profession = professions:get(i)
            if M.professionKey(profession) == key then
                return profession:getUIName()
            end
        end
    end
    return key
end

local function hasCustomizerSettings(page)
    if not page or not page.settings then return false end
    for index = 1, #page.settings do
        local setting = page.settings[index]
        if settingParts(setting) then return true end
    end
    return false
end

local function settingSortRank(section, group)
    if section == "Standard" then return standardGroupRank(group) end
    return group and groupOrder[group] or 99
end

local function settingOrderKey(setting)
    local section, key, part = settingParts(setting)
    local group = settingGroup(setting)
    return section, key, part, settingSortRank(section, group)
end

local function compareSettings(left, right)
    local leftSection, leftKey, leftPart, leftRank = settingOrderKey(left)
    local rightSection, rightKey, rightPart, rightRank = settingOrderKey(right)
    if leftRank ~= rightRank then return leftRank < rightRank end

    if leftSection == "Standard" and rightSection == "Standard" then
        local leftOrder = settingRank(left)
        local rightOrder = settingRank(right)
        if leftOrder ~= rightOrder then return leftOrder < rightOrder end
    end
    if leftSection == "Professions" and rightSection == "Professions" then
        local leftOrder = professionRank(leftKey)
        local rightOrder = professionRank(rightKey)
        if leftOrder ~= rightOrder then return leftOrder < rightOrder end
    end
    if leftKey ~= rightKey then return tostring(leftKey) < tostring(rightKey) end
    return (partOrder[leftPart] or 99) < (partOrder[rightPart] or 99)
end

local function settingsOrderChanged(settings, previousOrder)
    for index = 1, #settings do
        if previousOrder[index] ~= settings[index] then return true end
    end
    return false
end

local function settingMetadata(setting, previousGroup, previousKey)
    local group = settingGroup(setting)
    local section, key, part = settingParts(setting)
    local isStandard = section == "Standard"
    local tooltipKey = tooltipKeyFor(section, key, part)
    local title = group and group ~= previousGroup and group or nil
    local subtitle = not isStandard and isSubtitleSetting(section, key, part) and key ~= previousKey and settingLabel(setting) or nil
    local translatedName = setting.translatedName
    if isStandard then
        translatedName = part == "InitialLevel" and settingLabel(setting) or nil
    end
    return {
        tooltip = tooltipKey and composeTooltip(setting, getText(tooltipKey)) or setting.tooltip,
        title = not isStandard and section ~= "Professions" and title or nil,
        translatedName = translatedName,
        standardTitle = isStandard and title or nil,
        subtitle = subtitle,
    }, group or previousGroup, key or previousKey
end

local function addTitles(page)
    if not page or not page.settings then return false end
    if not hasCustomizerSettings(page) then return false end
    M.rememberTraits()

    local oldOrder = table.newarray(page.settings)
    table.sort(page.settings, compareSettings)
    local changed = settingsOrderChanged(page.settings, oldOrder)

    local previousGroup
    local previousKey
    for index = 1, #page.settings do
        local setting = page.settings[index]
        local metadata
        metadata, previousGroup, previousKey = settingMetadata(setting, previousGroup, previousKey)
        for propertyIndex = 1, #SETTING_METADATA_KEYS do
            local property = SETTING_METADATA_KEYS[propertyIndex]
            if setting[property] ~= metadata[property] then
                setting[property] = metadata[property]
                changed = true
            end
        end
    end

    return changed
end

local function syncControlTooltip(control, tooltip)
    if not control then return end
    if control.isCombobox then
        control.tooltip = { defaultTooltip = tooltip }
    else
        control.tooltip = tooltip
    end
    if control.entry then
        control.entry.tooltip = tooltip
    end
    if control.combo then
        control.combo.tooltip = { defaultTooltip = tooltip }
    end
end

local function syncPanelTooltips(panel, page)
    if not panel or not page or not page.settings then return end
    for index = 1, #page.settings do
        local setting = page.settings[index]
        local section, key, part = settingParts(setting)
        local tooltipKey = tooltipKeyFor(section, key, part)
        if tooltipKey then
            local tooltip = setting.tooltip or composeTooltip(setting, getText(tooltipKey))
            local label = panel.labels and panel.labels[setting.name]
            local control = panel.controls and panel.controls[setting.name]
            if label then
                label.tooltip = tooltip
            end
            syncControlTooltip(control, tooltip)
        end
    end
end

local function clearPanelTooltips(panel)
    if not panel or not panel.getChildren then return end
    for _, child in pairs(panel:getChildren()) do
        if child.tooltipUI then
            child.tooltipUI:setVisible(false)
            child.tooltipUI:removeFromUIManager()
            child.tooltipUI = nil
        end
        clearPanelTooltips(child)
    end
end

local function shiftPanelChildren(panel, y, amount)
    local children = panel:getChildrenInOrder()
    for index = 1, #children do
        local child = children[index]
        local childY = child:getY()
        if childY >= y then
            child:setY(childY + amount)
        end
    end
end

local function saveControlStates(panel)
    local states = {}
    for name, control in pairs(panel and panel.controls or {}) do
        if control.isTickBox then
            states[name] = { selected = control.selected[1] }
        elseif control.isCombobox or control.Type == "ISSpinBox" then
            states[name] = { selected = control.selected }
        elseif control.Type == "SandboxAdvancedControl" then
            states[name] = {
                text = control:getText(),
                advanced = control.entry:isVisible(),
            }
        elseif control.getText then
            states[name] = { text = control:getText() }
        end
    end
    return states
end

local function restoreControlStates(panel, states)
    if not panel or not panel.controls then return end
    for name, state in pairs(states) do
        local control = panel.controls[name]
        if control then
            if control.isTickBox then
                control.selected[1] = state.selected
            elseif control.isCombobox or control.Type == "ISSpinBox" then
                control.selected = state.selected
            elseif control.Type == "SandboxAdvancedControl" then
                control:advancedCheckboxChanged(state.advanced)
                control:setText(state.text)
            elseif state.text ~= nil and control.setText then
                control:setText(state.text)
            end
        end
    end
end

local function seedSettingState(setting, state)
    if state.text ~= nil then
        setting.text = state.text
    elseif state.selected ~= nil then
        setting.default = state.selected
    end
end

local function seedConfiguredSetting(setting, configOption)
    local optionType = configOption:getType()
    if optionType == "integer" or optionType == "double" then
        setting.text = configOption:getValueAsString()
    elseif optionType == "string" or optionType == "text" then
        setting.text = configOption:getValueAsObject()
    elseif optionType == "boolean" then
        setting.default = configOption:getValueAsObject()
    end
end

local function seedPanelSettings(page, states)
    if not page or not page.settings then return end
    local options = getSandboxOptions()
    for index = 1, #page.settings do
        local setting = page.settings[index]
        local state = states[setting.name]
        if state then
            seedSettingState(setting, state)
        else
            local option = options:getOptionByName(setting.name)
            if not option then error("Missing sandbox option: " .. setting.name) end
            seedConfiguredSetting(setting, option:asConfigOption())
        end
    end
end

local function replaceOwnerControls(owner, panel)
    if not owner or not owner.controls or not panel or not panel.controls then return end
    local target = panel.category and owner.controls[panel.category] or owner.controls
    if not target then return end
    for name, control in pairs(panel.controls) do
        target[name] = control
    end
end

local function addCenteredLabel(panel, labelSpec)
    local label = ISLabel:new(0, 0, labelSpec.height, labelSpec.text, 1, 1, 1, 1, labelSpec.font)
    panel:addChild(label)
    label:setX((panel:getWidth() - label:getWidth()) / 2)
    label:setY(labelSpec.y)
    local headers = panel.characterCreationCustomizerHeaders
    if not headers then
        headers = table.newarray()
        panel.characterCreationCustomizerHeaders = headers
    end
    headers[#headers + 1] = label
    return label
end

local function addSandboxTitles(panel, page, titleProperty)
    if not panel or not page or not page.settings or not panel.labels then return end

    local titleHeight = getTextManager():getFontFromEnum(UIFont.Large):getLineHeight() + 6
    local addedHeight = 0

    for index = 1, #page.settings do
        local setting = page.settings[index]
        if setting[titleProperty] then
            local row = panel.labels[setting.name]
            if row then
                local y = row:getY()
                local amount = titleHeight + 22
                shiftPanelChildren(panel, y, amount)

                addCenteredLabel(panel, {
                    height = titleHeight, text = titleText(setting[titleProperty]), font = UIFont.Large, y = y + 20,
                })
                addedHeight = addedHeight + amount
            end
        end
    end

    if addedHeight > 0 then
        panel:setScrollHeight(panel:getScrollHeight() + addedHeight)
    end
end

local function addSandboxSubtitles(panel, page)
    if not panel or not page or not page.settings or not panel.labels then return end

    local subtitleHeight = getTextManager():getFontFromEnum(UIFont.Medium):getLineHeight() + 4
    local subtitleSpacing = 8
    local addedHeight = 0

    for index = 1, #page.settings do
        local setting = page.settings[index]
        local section, key, part = settingParts(setting)
        if key and isSubtitleSetting(section, key, part) and setting.subtitle then
            local row = panel.labels[setting.name]
            if row then
                local y = row:getY()
                local amount = subtitleHeight + subtitleSpacing
                shiftPanelChildren(panel, y, amount)

                addCenteredLabel(panel, {
                    height = subtitleHeight, text = setting.subtitle, font = UIFont.Medium, y = y,
                })
                addedHeight = addedHeight + amount
            end
        end
    end

    if addedHeight > 0 then
        panel:setScrollHeight(panel:getScrollHeight() + addedHeight)
    end
    panel.subtitles = true
end

local sandboxPanelHooked = false
local hookedHostPageEdit
local rebuiltSandboxScreen
local rebuiltSandboxListbox
local rebuiltSandboxFingerprint
local rebuiltHostPageEdit
local rebuiltHostListbox
local rebuiltHostFingerprint

local function invalidCustomizerInteger(optionName, option, control)
    if not control or not optionName:match("^CharacterCreationCustomizer%.") then return false end
    local configOption = option:asConfigOption()
    if configOption:getType() ~= "integer" then return false end
    local text = control.getText and control:getText()
    return text ~= nil and (text == "" or text == "-" or not configOption:isValidString(text))
end

local function filteredSettingsOptions(owner, category, options)
    local controls = owner and owner.controls
    controls = category and controls and controls[category] or controls
    local validOptions = table.newarray()
    local optionCount = options:getNumOptions()
    for index = 0, optionCount - 1 do
        local option = options:getOptionByIndex(index)
        local optionName = option:getName()
        local control = controls and controls[optionName]
        if not invalidCustomizerInteger(optionName, option, control) then
            validOptions[#validOptions + 1] = option
        end
    end
    return {
        getNumOptions = function()
            return #validOptions
        end,
        getOptionByIndex = function(_, index)
            return validOptions[index + 1]
        end,
    }
end

local function decorateSettingsPanel(panel, page)
    syncPanelTooltips(panel, page)
    addSandboxTitles(panel, page, "standardTitle")
    addSandboxSubtitles(panel, page)
    return panel
end

local function copyCustomizerPage(page)
    local copiedPage = copyTable(page)
    copiedPage.settings = table.newarray()
    for index = 1, #page.settings do
        copiedPage.settings[index] = copyTable(page.settings[index])
    end
    return copiedPage
end

local function createInGameSandboxPage(page)
    if not hasCustomizerSettings(page) then return page end

    local customPage = copyCustomizerPage(page)
    addTitles(customPage)
    for index = 1, #customPage.settings do
        local setting = customPage.settings[index]
        setting.inGameTitle = setting.standardTitle or setting.title
        setting.title = nil
    end
    return customPage
end

local IN_GAME_SETTINGS_SPACING = 10

local function inGameSettingsWidths(panel, page)
    local labelWidth = 0
    local controlWidth = 0
    for index = 1, #page.settings do
        local setting = page.settings[index]
        local label = panel.labels[setting.name]
        local control = panel.controls[setting.name]
        if label and control then
            labelWidth = math.max(labelWidth, label:getWidth())
            controlWidth = math.max(controlWidth, control:getWidth())
        end
    end
    return { label = labelWidth, control = controlWidth }
end

local function centerInGameSettingRows(panel, page, widths)
    local panelWidth = panel:getWidth()
    local contentWidth = widths.label + IN_GAME_SETTINGS_SPACING + widths.control
    local contentX = (panelWidth - contentWidth) / 2
    for index = 1, #page.settings do
        local setting = page.settings[index]
        local label = panel.labels[setting.name]
        local control = panel.controls[setting.name]
        if label and control then
            label:setX(contentX + widths.label - label:getWidth())
            control:setX(contentX + widths.label + IN_GAME_SETTINGS_SPACING)
        end
    end
end

local function centerInGameHeaders(panel, panelWidth)
    local headers = panel.characterCreationCustomizerHeaders
    if not headers then return end
    for index = 1, #headers do
        local header = headers[index]
        header:setX((panelWidth - header:getWidth()) / 2)
    end
end

local function centerInGameSettings(panel, page)
    if not panel or not page or not page.settings
            or not panel.labels or not panel.controls then
        return panel
    end
    if not hasCustomizerSettings(page) then return panel end

    local widths = inGameSettingsWidths(panel, page)
    if widths.label == 0 or widths.control == 0 then return panel end

    local panelWidth = panel:getWidth()
    centerInGameSettingRows(panel, page, widths)
    centerInGameHeaders(panel, panelWidth)
    return panel
end

local inGameSandboxOptionsHooked = false

local function hookInGameSandboxPanelCreation()
    local originalCreatePanel = ISServerSandboxOptionsUI.createPanel
    ISServerSandboxOptionsUI.createPanel = function(self, page)
        local customPage = createInGameSandboxPage(page)
        local panel = originalCreatePanel(self, customPage)
        if hasCustomizerSettings(customPage) then
            addSandboxTitles(panel, customPage, "inGameTitle")
            addSandboxSubtitles(panel, customPage)
            centerInGameSettings(panel, customPage)
        end
        return panel
    end
end

local function hookInGameSandboxPanelSelection()
    local originalOnMouseDownListbox = ISServerSandboxOptionsUI.onMouseDownListbox
    if originalOnMouseDownListbox then
        ISServerSandboxOptionsUI.onMouseDownListbox = function(self, item)
            originalOnMouseDownListbox(self, item)
            if item and item.page and item.panel then
                centerInGameSettings(item.panel, item.page)
            end
        end
    end
end

local function installInGameSandboxOptionsHook()
    if inGameSandboxOptionsHooked then return end
    if not ISServerSandboxOptionsUI or not ISServerSandboxOptionsUI.createPanel then return end

    hookInGameSandboxPanelCreation()
    hookInGameSandboxPanelSelection()
    inGameSandboxOptionsHooked = true
end

local function installSandboxPanelHook()
    if sandboxPanelHooked or not SandboxOptionsScreen then return end
    local originalCreatePanel = SandboxOptionsScreen.createPanel
    local originalSettingsFromUI = SandboxOptionsScreen.settingsFromUI

    function SandboxOptionsScreen:settingsFromUI(options)
        return originalSettingsFromUI(self, filteredSettingsOptions(self, nil, options))
    end

    function SandboxOptionsScreen:createPanel(page)
        seedPanelSettings(page, {})
        addTitles(page)
        return decorateSettingsPanel(originalCreatePanel(self, page), page)
    end

    sandboxPanelHooked = true
end

local function installHostPanelHook()
    local screen = ServerSettingsScreen and ServerSettingsScreen.instance
    local pageEdit = screen and screen.pageEdit
    if not pageEdit or pageEdit == hookedHostPageEdit then return end
    local pageEditMethods = getmetatable(pageEdit).__index
    local originalCreatePanel = pageEditMethods.createPanel
    if not originalCreatePanel then return end
    local originalSettingsFromUI = pageEditMethods.settingsFromUIAux

    if originalSettingsFromUI then
        rawset(pageEdit, "settingsFromUIAux", function(owner, category, options)
            return originalSettingsFromUI(owner, category, filteredSettingsOptions(owner, category, options))
        end)
    end

    rawset(pageEdit, "createPanel", function(owner, category, page)
        seedPanelSettings(page, {})
        addTitles(page)
        return decorateSettingsPanel(originalCreatePanel(owner, category, page), page)
    end)

    hookedHostPageEdit = pageEdit
end

local function showSettingsPanel(owner, panel)
    owner:addChild(panel)
    owner.currentPanel = panel
    owner:onPanelChange()
end

local function rebuildSettingsPanel(owner, itemData, createPanel)
    local oldPanel = itemData.panel
    local wasCurrent = owner.currentPanel == oldPanel
    local controlStates = saveControlStates(oldPanel)
    seedPanelSettings(itemData.page, controlStates)
    clearPanelTooltips(oldPanel)
    if wasCurrent then owner:removeChild(oldPanel) end

    itemData.panel = createPanel(itemData.page)
    replaceOwnerControls(owner, itemData.panel)
    restoreControlStates(itemData.panel, controlStates)
    if wasCurrent then showSettingsPanel(owner, itemData.panel) end
end

local function rebuildSettingsPanels(owner, listbox, createPanel)
    for index = 1, #listbox.items do
        local itemData = listbox.items[index].item
        local page = itemData and itemData.page
        local changed = addTitles(page)
        if changed or (hasCustomizerSettings(page) and itemData and itemData.panel and not itemData.panel.subtitles) then
            rebuildSettingsPanel(owner, itemData, createPanel)
        end
    end
end

local function rebuildSandboxOptionsPage()
    local screen = SandboxOptionsScreen and SandboxOptionsScreen.instance
    if not screen or not screen.listbox then return end
    local fingerprint = M.configurationFingerprint()
    if screen == rebuiltSandboxScreen
        and screen.listbox == rebuiltSandboxListbox
        and fingerprint ~= nil
        and fingerprint == rebuiltSandboxFingerprint then
        return
    end

    rebuildSettingsPanels(screen, screen.listbox, function(page)
        return screen:createPanel(page)
    end)
    rebuiltSandboxScreen = screen
    rebuiltSandboxListbox = screen.listbox
    rebuiltSandboxFingerprint = fingerprint
end

local function rebuildHostSettingsPage()
    local screen = ServerSettingsScreen and ServerSettingsScreen.instance
    local pageEdit = screen and screen.pageEdit
    local listbox = pageEdit and rawget(pageEdit, "listbox")
    if not pageEdit or not listbox then return end
    local fingerprint = M.configurationFingerprint()
    if pageEdit == rebuiltHostPageEdit
        and listbox == rebuiltHostListbox
        and fingerprint ~= nil
        and fingerprint == rebuiltHostFingerprint then
        return
    end
    installHostPanelHook()
    local createPanel = rawget(pageEdit, "createPanel")

    rebuildSettingsPanels(pageEdit, listbox, function(page)
        return createPanel(pageEdit, { name = "Sandbox" }, page)
    end)
    rebuiltHostPageEdit = pageEdit
    rebuiltHostListbox = listbox
    rebuiltHostFingerprint = fingerprint
end

local function initialize()
    installSandboxPanelHook()
    installHostPanelHook()
    installInGameSandboxOptionsHook()
    rebuildSandboxOptionsPage()
    rebuildHostSettingsPage()
end

local function installSandboxSettings(lookupStandardEntry, lookupStandardGroupRank)
    standardEntry = lookupStandardEntry
    standardGroupRank = lookupStandardGroupRank
    installSandboxPanelHook()
    installHostPanelHook()
    installInGameSandboxOptionsHook()
    Events.OnMainMenuEnter.Add(initialize)
    Events.OnGameStart.Add(installInGameSandboxOptionsHook)
end

return installSandboxSettings
