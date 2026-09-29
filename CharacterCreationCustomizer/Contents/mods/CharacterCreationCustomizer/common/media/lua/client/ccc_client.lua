local M = require "ccc_shared"
require "OptionScreens/CharacterCreationProfession"

local UI_BORDER_SPACING = 10
local SCROLL_BAR_WIDTH = 13
local CONFIGURATION_CHECK_INTERVAL = 30
local SKILL_LEVEL_COLOR = { r = 1.0, g = 0.75, b = 0.15 }
local SKILL_LEVEL_SEPARATOR_COLOR = { r = 0.55, g = 0.55, b = 0.55 }
local NEUTRAL_TEXT_COLOR = { r = 0.65, g = 0.65, b = 0.65 }
local XP_MULTIPLIER_COLORS = {
    [0] = NEUTRAL_TEXT_COLOR,
    [1] = { r = 0.31, g = 0.63, b = 0.86 },
    [2] = { r = 0.67, g = 0.42, b = 0.88 },
    [3] = { r = 0.91, g = 0.64, b = 0.23 },
}
local OTHER_SKILLS_POSITIVE_COLOR = { r = 0.20, g = 0.78, b = 0.80 }
local OTHER_SKILLS_NEGATIVE_COLOR = { r = 0.86, g = 0.35, b = 0.60 }
local SKILL_PERCENTAGES = {
    [0] = "+ 0%",
    [1] = "+ 75%",
    [2] = "+ 100%",
    [3] = "+ 125%",
}
local pacifistPerks

if rawget(M, "clientInstalled") then return end
rawset(M, "clientInstalled", true)
local installSandboxSettings = require "ui/ccc_sandbox_settings"

local traitItemStates = setmetatable({}, { __mode = "k" })

local function traitItemState(item)
    local state = traitItemStates[item]
    if not state then
        state = {}
        traitItemStates[item] = state
    end
    return state
end

local function qolEnabled(key)
    local qolValue = M.optionValue("QOL", key)
    if qolValue == nil then return true end
    return qolValue == true or qolValue == 1 or qolValue == "true"
end

local standardGroupRanks
local standardPerkIndex

local function indexStandardPerks()
    if standardPerkIndex ~= nil then return standardPerkIndex end

    local entriesByKey = {}
    local entriesByPerk = {}
    local standardPerks = M.getStandardPerks()
    for index = 1, #standardPerks do
        local entry = standardPerks[index]
        entriesByKey[entry.key] = entry
        entriesByPerk[entry.perk] = entry
        entriesByPerk[tostring(entry.perk)] = entry
    end
    standardPerkIndex = { byKey = entriesByKey, byPerk = entriesByPerk }
    return standardPerkIndex
end

local function standardEntry(key)
    return indexStandardPerks().byKey[key]
end

local function requiredStandardEntry(key)
    local entry = standardEntry(key)
    if not entry then error("Missing standard perk: " .. key) end
    return entry
end

local function standardGroupRank(group)
    if not standardGroupRanks then
        standardGroupRanks = {}
        local rank = 0
        local standardPerks = M.getStandardPerks()
        for index = 1, #standardPerks do
            local entry = standardPerks[index]
            if not standardGroupRanks[entry.group] then
                rank = rank + 1
                standardGroupRanks[entry.group] = rank
            end
        end
    end
    return standardGroupRanks[group] or 99
end

local function traitDefinitionByType(traitType)
    local trait = CharacterTraitDefinition.getCharacterTraitDefinition(traitType)
    if trait == nil then error("Missing trait definition: " .. tostring(traitType)) end
    return trait
end

local function populateNativeTraitList(self, list, positive)
    M.apply()
    list:clear()
    local expectedGroup = positive and "PositiveTraits" or "NegativeTraits"
    local traitList = CharacterTraitDefinition.getTraits()
    for i = 0, traitList:size() - 1 do
        local trait = traitList:get(i)
        local original = M.originalTrait(trait)
        local current = traitDefinitionByType(original:getType())
        local group = M.traitGroup(original)
        local selectable = not original:isFree() or M.traitBuyable(original)
        if M.traitEnabled(original) and selectable and group == expectedGroup and self:isTraitEnabled(current) and not self:isTraitExcluded(current) then
            list:addItem(current:getLabel(), current, current:getDescription())
        end
    end
end

function CharacterCreationProfession:populateTraitList(list)
    populateNativeTraitList(self, list, true)
end

function CharacterCreationProfession:populateBadTraitList(list)
    populateNativeTraitList(self, list, false)
end

local function traitKey(trait)
    return trait and M.definitionKey(trait)
end

local function findTrait(list, key)
    local items = list.items
    if not items then return end
    for index = 1, #items do
        local traitItem = items[index]
        if traitKey(traitItem.item) == key then
            return index, traitItem
        end
    end
end

local function selectedTrait(self, key)
    return findTrait(self.listboxTraitSelected, key)
end

local function addUniqueTrait(list, trait)
    if not findTrait(list, traitKey(trait)) then
        return list:addItem(trait:getLabel(), trait, trait:getDescription())
    end
end

local function removeTraitFromList(list, trait)
    local key = traitKey(trait)
    local items = list.items
    if not items then return end
    for index = #items, 1, -1 do
        if traitKey(items[index].item) == key then
            list:removeItemByIndex(index)
        end
    end
end

local function freeSources(self)
    self.characterCreationCustomizerFreeSources = self.characterCreationCustomizerFreeSources or {}
    return self.characterCreationCustomizerFreeSources
end

local function hasFreeSource(sources)
    if not sources then return false end
    for _ in pairs(sources) do return true end
    return false
end

local function isFreeTrait(self, trait)
    local key = traitKey(trait)
    local sources = key and freeSources(self)[key]
    return hasFreeSource(sources)
end

local function setFreeSource(self, trait, source, active)
    local key = traitKey(trait)
    if not key or not source then return end
    local sourcesByTrait = freeSources(self)
    local sources = sourcesByTrait[key]
    if active then
        sources = sources or {}
        sources[source] = true
        sourcesByTrait[key] = sources
    elseif sources then
        sources[source] = nil
        if not hasFreeSource(sources) then sourcesByTrait[key] = nil end
    end
end

local function refreshFreeTraitFlags(self)
    local items = self.listboxTraitSelected.items
    if not items then return end
    for index = 1, #items do
        local selectedItem = items[index]
        local free = isFreeTrait(self, selectedItem.item)
        traitItemState(selectedItem).freeTrait = free or nil
    end
end

local function updateMutuallyExclusiveTrait(self, traitType, isRemovingTrait)
    local exclusiveDefinition = CharacterTraitDefinition.getCharacterTraitDefinition(traitType)
    if not exclusiveDefinition or exclusiveDefinition:isFree() then return end

    local original = M.originalTrait(exclusiveDefinition)
    local group = M.traitGroup(original)
    if isRemovingTrait then
        if not M.traitEnabled(original) or self:isTraitExcluded(exclusiveDefinition) then return end
        if group == "PositiveTraits" then
            addUniqueTrait(self.listboxTrait, exclusiveDefinition)
        elseif group == "NegativeTraits" then
            addUniqueTrait(self.listboxBadTrait, exclusiveDefinition)
        end
        return
    end

    if group == "PositiveTraits" then
        removeTraitFromList(self.listboxTrait, exclusiveDefinition)
    elseif group == "NegativeTraits" then
        removeTraitFromList(self.listboxBadTrait, exclusiveDefinition)
    end
end

function CharacterCreationProfession:doTestForMutuallyExclusiveTraits(trait, isRemovingTrait)
    M.rememberTraits()
    local mutuallyExclusiveTraits = trait:getMutuallyExclusiveTraits()
    for i = 0, mutuallyExclusiveTraits:size() - 1 do
        updateMutuallyExclusiveTrait(self, mutuallyExclusiveTraits:get(i), isRemovingTrait)
    end
end

local function prepareGrantedTrait(self, trait, source)
    setFreeSource(self, trait, source, true)
    local _, item = selectedTrait(self, traitKey(trait))
    if not item then
        item = self.listboxTraitSelected:addItem(trait:getLabel(), trait, trait:getDescription())
    end
    if not item then error("Failed to add granted trait: " .. traitKey(trait)) end
    local state = traitItemState(item)
    state.manualTrait = state.manualTrait == true
    item.tooltip = trait:getDescription()
    removeTraitFromList(self.listboxTrait, trait)
    removeTraitFromList(self.listboxBadTrait, trait)
end

function CharacterCreationProfession:addTrait(trait)
    local original = M.originalTrait(trait)
    if M.traitGroup(original) and not M.traitEnabled(original) then return end
    local key = traitKey(trait)
    if selectedTrait(self, key) then return end

    local selectedItem = self.listboxTraitSelected:addItem(trait:getLabel(), trait, trait:getDescription())
    traitItemState(selectedItem).manualTrait = true
    if not isFreeTrait(self, trait) then self.pointToSpend = self.pointToSpend - trait:getCost() end
    removeTraitFromList(self.listboxTrait, trait)
    removeTraitFromList(self.listboxBadTrait, trait)

    local source = "trait:" .. key
    local grantedTraits = trait:getGrantedTraits()
    for i = 0, grantedTraits:size() - 1 do
        local grantedTrait = traitDefinitionByType(grantedTraits:get(i))
        prepareGrantedTrait(self, grantedTrait, source)
        self:doTestForMutuallyExclusiveTraits(grantedTrait, false)
    end

    refreshFreeTraitFlags(self)
    self:doTestForMutuallyExclusiveTraits(trait, false)
    self:repopulateTraitLists()
end

function CharacterCreationProfession:onSelectChosenTrait(item)
    local _, selected = selectedTrait(self, traitKey(item))
    local canRemove = selected and traitItemState(selected).manualTrait == true and not isFreeTrait(self, item)
    self.removeTraitBtn:setEnable(canRemove or false)
end

function CharacterCreationProfession:removeTrait(index)
    local selectedItem = self.listboxTraitSelected:getItem(index)
    if not selectedItem or isFreeTrait(self, selectedItem.item) then return end

    local trait = selectedItem.item
    local key = traitKey(trait)
    removeTraitFromList(self.listboxTraitSelected, trait)
    if traitItemState(selectedItem).manualTrait ~= false then self.pointToSpend = self.pointToSpend + trait:getCost() end

    local source = "trait:" .. key
    local grantedTraits = trait:getGrantedTraits()
    for i = 0, grantedTraits:size() - 1 do
        local grantedTrait = traitDefinitionByType(grantedTraits:get(i))
        setFreeSource(self, grantedTrait, source, false)
        local grantedKey = traitKey(grantedTrait)
        local _, grantedItem = selectedTrait(self, grantedKey)
        if grantedItem and not isFreeTrait(self, grantedTrait) and traitItemState(grantedItem).manualTrait ~= true then
            removeTraitFromList(self.listboxTraitSelected, grantedTrait)
            self:doTestForMutuallyExclusiveTraits(grantedTrait, true)
        end
    end

    refreshFreeTraitFlags(self)
    self:doTestForMutuallyExclusiveTraits(trait, true)
    self:repopulateTraitLists()
end

local nativeRandomizeTraits = CharacterCreationProfession.randomizeTraits
function CharacterCreationProfession:randomizeTraits()
    if #self.listboxTrait.items == 0 or #self.listboxBadTrait.items == 0 then
        self:resetBuild()
        return
    end
    return nativeRandomizeTraits(self)
end

local nativeDrawTraitMap = CharacterCreationProfession.drawTraitMap
local function prepareTraitMapProxy(traitState, traitRow, originalTrait)
    if traitState.proxyOriginal ~= originalTrait then
        traitState.proxyOriginal = originalTrait
        traitState.proxyItem = {
            getTexture = function() return originalTrait:getTexture() end,
            getCost = function() return 0 end,
            getLabel = function() return originalTrait:getLabel() end,
            getRightLabel = function() return "" end,
        }
        traitState.proxyEntry = {}
    end

    local proxyEntry = traitState.proxyEntry
    proxyEntry.index = traitRow.index
    proxyEntry.height = traitRow.height
    proxyEntry.itemindex = traitRow.itemindex
    proxyEntry.text = traitRow.text
    proxyEntry.item = traitState.proxyItem
end

local function drawTraitMap(listbox, y, item, alt)
    local traitState = traitItemStates[item]
    if not traitState or not traitState.freeTrait then
        return nativeDrawTraitMap(listbox, y, item, alt)
    end

    prepareTraitMapProxy(traitState, item, item.item)
    return nativeDrawTraitMap(listbox, y, traitState.proxyEntry, alt)
end
CharacterCreationProfession.drawTraitMap = drawTraitMap

local function professionPointDisplay(profession)
    local pointsDelta = M.professionCost(profession)
    if pointsDelta == 0 then
        return "0", NEUTRAL_TEXT_COLOR.r, NEUTRAL_TEXT_COLOR.g, NEUTRAL_TEXT_COLOR.b
    end

    local prefix = pointsDelta > 0 and "+" or "-"
    local color = pointsDelta > 0 and getCore():getGoodHighlitedColor() or getCore():getBadHighlitedColor()
    return prefix .. tostring(math.abs(pointsDelta)), color:getR(), color:getG(), color:getB()
end

local nativeDrawProfessionMap = CharacterCreationProfession.drawProfessionMap
local function drawProfessionMap(listbox, y, professionEntry, alt)
    local nextY = nativeDrawProfessionMap(listbox, y, professionEntry, alt)
    if not qolEnabled("ShowProfessionPoints_Enabled") then return nextY end

    local pointText, pointR, pointG, pointB = professionPointDisplay(professionEntry.item)
    local dy = (professionEntry.height - listbox.fontHgt) / 2
    local right = listbox.width - UI_BORDER_SPACING - SCROLL_BAR_WIDTH
    listbox:drawTextRight(pointText, right, y + dy,
        pointR, pointG, pointB, 0.9, UIFont.Small)
    return nextY
end
CharacterCreationProfession.drawProfessionMap = drawProfessionMap

local function grantedTraitDefinitions(traitTypes)
    local definitions = {}
    if not traitTypes then return definitions end
    for index = 1, #traitTypes do
        definitions[#definitions + 1] = traitDefinitionByType(traitTypes[index])
    end
    return definitions
end

local function removeGrantedProfessionTraits(self, traitTypes, professionKey)
    local source = professionKey and "profession:" .. professionKey
    if not source then return end
    local grantedDefinitions = grantedTraitDefinitions(traitTypes)
    for index = 1, #grantedDefinitions do
        local trait = grantedDefinitions[index]
        local key = traitKey(trait)
        setFreeSource(self, trait, source, false)
        local _, selectedItem = selectedTrait(self, key)
        if selectedItem and not isFreeTrait(self, trait) and traitItemState(selectedItem).manualTrait ~= true then
            removeTraitFromList(self.listboxTraitSelected, trait)
            self:doTestForMutuallyExclusiveTraits(trait, true)
        end
    end
    refreshFreeTraitFlags(self)
end

local function addGrantedProfessionTraits(self, profession, traitTypes)
    local source = "profession:" .. M.professionKey(profession)
    local grantedDefinitions = grantedTraitDefinitions(traitTypes)
    for index = 1, #grantedDefinitions do
        local trait = grantedDefinitions[index]
        prepareGrantedTrait(self, trait, source)
        self:doTestForMutuallyExclusiveTraits(trait, false)
    end
    refreshFreeTraitFlags(self)
    CharacterCreationMain.sort(self.listboxTraitSelected.items)
end

local function refreshSelectedTraitDefinitions(self)
    local items = self.listboxTraitSelected.items
    if not items then return end
    for index = 1, #items do
        local selectedItem = items[index]
        local definition = traitDefinitionByType(selectedItem.item:getType())
        selectedItem.item = definition
        selectedItem.text = definition:getLabel()
        selectedItem.tooltip = definition:getDescription()
    end
    refreshFreeTraitFlags(self)
end

local function removeDisabledSelectedTraits(self)
    local items = self.listboxTraitSelected.items
    if not items then return end
    for index = #items, 1, -1 do
        local selectedItem = items[index]
        if not isFreeTrait(self, selectedItem.item)
            and not M.traitEnabled(M.originalTrait(selectedItem.item)) then
            self:removeTrait(index)
        end
    end
end

local function removeUnbuyableSelectedTraits(self)
    local items = self.listboxTraitSelected.items
    if not items then return end
    for index = #items, 1, -1 do
        local selectedItem = items[index]
        local original = M.originalTrait(selectedItem.item)
        if traitItemState(selectedItem).manualTrait and not isFreeTrait(self, selectedItem.item)
            and original:isFree() and not M.traitBuyable(original) then
            self:removeTrait(index)
        end
    end
end

local function recalculatePointToSpend(self)
    local pointToSpend = 0.0
    local items = self.listboxTraitSelected.items
    if not items then
        self.pointToSpend = pointToSpend
        return
    end
    for index = 1, #items do
        local selectedItem = items[index]
        if traitItemState(selectedItem).manualTrait and not isFreeTrait(self, selectedItem.item) then
            pointToSpend = pointToSpend - selectedItem.item:getCost()
        end
    end
    self.pointToSpend = pointToSpend
end

local function removeConflictingProfessionTraits(self, grantedDefinitions)
    local selectedItems = self.listboxTraitSelected.items
    if not selectedItems then return end
    for index = #selectedItems, 1, -1 do
        local selected = selectedItems[index].item
        local selectedType = selected:getType()
        local shouldRemove = false
        for grantedIndex = 1, #grantedDefinitions do
            local grantedTrait = grantedDefinitions[grantedIndex]
            local mutuallyExclusiveTraits = grantedTrait:getMutuallyExclusiveTraits()
            if mutuallyExclusiveTraits:contains(selectedType) then
                shouldRemove = true
                break
            end
        end
        if shouldRemove and not isFreeTrait(self, selected) then self:removeTrait(index) end
    end
end

local function requireMainScreen()
    local mainScreen = MainScreen.instance
    if not mainScreen then error("Main screen is unavailable") end
    if not mainScreen.desc then error("Main screen description panel is unavailable") end
    return mainScreen
end

local function requireCreationMain()
    local creationMain = CharacterCreationMain.instance
    if not creationMain then error("Character creation main screen is unavailable") end
    return creationMain
end

local function applyProfessionSelection(self, profession)
    local mainScreen = requireMainScreen()
    self.profession = profession
    local professionItems = self.listboxProf.items
    if professionItems then
        for index = 1, #professionItems do
            local professionEntry = professionItems[index]
            if professionEntry.item == profession then
                self.listboxProf.selected = index
                break
            end
        end
    end

    local descriptionPanel = mainScreen.desc
    descriptionPanel:setProfessionSkills(profession)
    descriptionPanel:setCharacterProfession(profession:getType())
    self.cost = M.professionCost(profession)
    self:changeClothes()
end

function CharacterCreationProfession:onSelectProf(profession)
    if not profession then return end
    M.debugLog("Selecting profession", profession)
    requireMainScreen()
    requireCreationMain()
    freeSources(self)
    M.apply()
    local fallback = M.fallbackProfession()
    if not M.professionEnabled(profession) and profession ~= fallback then
        M.debugLog("Ignoring disabled profession", profession)
        return
    end

    local previousProfession = self.profession
    local previousKey = self.characterCreationCustomizerAppliedGrantedProfessionKey
    local previousGrants = self.characterCreationCustomizerAppliedGrantedTraits
    if previousProfession and not previousGrants then
        previousGrants = M.professionGrantedTraits(previousProfession)
    end
    local nextGrants = M.professionGrantedTraits(profession)
    removeGrantedProfessionTraits(self, previousGrants, previousKey or (previousProfession and M.professionKey(previousProfession)))

    removeConflictingProfessionTraits(self, grantedTraitDefinitions(nextGrants))

    applyProfessionSelection(self, profession)

    addGrantedProfessionTraits(self, profession, nextGrants)
    self.characterCreationCustomizerAppliedGrantedTraits = nextGrants
    self.characterCreationCustomizerAppliedGrantedProfessionKey = M.professionKey(profession)
    recalculatePointToSpend(self)
    self:repopulateTraitLists()
    self:checkXPBoost()
    CharacterCreationMain.sort(self.listboxTrait.items)
    CharacterCreationMain.invertSort(self.listboxBadTrait.items)
    CharacterCreationMain.sort(self.listboxTraitSelected.items)
    requireCreationMain():disableBtn()
    M.debugLog("Profession selection applied", profession)
end

function CharacterCreationProfession.populateProfessionList(_, list)
    M.apply()
    list:clear()
    local professionList = CharacterProfessionDefinition.getProfessions()
    local hasEnabledProfession = false
    for i = 0, professionList:size() - 1 do
        local profession = professionList:get(i)
        if M.professionEnabled(profession) then
            local newitem = list:addItem(profession:getUIName(), profession)
            newitem.tooltip = profession:getDescription()
            hasEnabledProfession = true
        end
    end

    if not hasEnabledProfession then
        local fallback = M.fallbackProfession()
        if not fallback then error("No profession is available for character creation") end
        local newitem = list:addItem(fallback:getUIName(), fallback)
        newitem.tooltip = fallback:getDescription()
    end

    list:sort(function(a, b)
        local aUnemployed = a.item:getType() == CharacterProfession.UNEMPLOYED
        local bUnemployed = b.item:getType() == CharacterProfession.UNEMPLOYED
        if aUnemployed or bUnemployed then return aUnemployed and not bUnemployed end
        return not string.sort(a.text, b.text)
    end)
end

local function addXpBoosts(levels, boosts)
    if not boosts then return end
    local boostTable = transformIntoKahluaTable(boosts)
    for perk, level in pairs(boostTable) do
        levels[perk] = (levels[perk] or 0) + level:intValue()
    end
end

local function professionWhiteBar()
    local professionScreen = CharacterCreationProfession.instance
    if not professionScreen then error("Character creation profession screen is unavailable") end
    if not professionScreen.whiteBar then error("Character creation profession white bar is unavailable") end
    return professionScreen.whiteBar
end

local function drawExtraBars(self, y, vanillaLevel, extraLevel, reducedLevel)
    extraLevel = extraLevel or 0
    reducedLevel = reducedLevel or 0
    if extraLevel == 0 and reducedLevel == 0 then return end
    local dy = (self.itemheight - self.fontHgt) / 2
    local textManager = getTextManager()
    local whiteBar = professionWhiteBar()
    local blitH = textManager:getFontHeight(UIFont.Small)
    local blitW = math.floor(blitH / (10/3))
    local blitGap = math.floor(blitW / 4)
    local multiplierText = qolEnabled("ShowXPMultiplier_Enabled") and "x1.00" or "+ 100%"
    local blitXOffset = textManager:MeasureStringX(UIFont.Small, multiplierText) + SCROLL_BAR_WIDTH
    local greenBlitsX = self.width - (blitXOffset + 12 * (blitW + blitGap))

    for i = 1, extraLevel do
        local position = vanillaLevel + i
        self:drawTextureScaled(whiteBar,
            greenBlitsX + (position * (blitW + blitGap)), y + dy, blitW, blitH, 1,
            0.15, 0.55, 0.9)
    end

    for i = 1, reducedLevel do
        local position = vanillaLevel - reducedLevel + i
        self:drawTextureScaled(whiteBar,
            greenBlitsX + (position * (blitW + blitGap)), y + dy, blitW, blitH, 1,
            0.9, 0.2, 0.2)
    end
end

local function clampXpLevel(level)
    return math.max(0, math.min(10, level or 0))
end

local function isPhysicalPerk(perk)
    return perk == Perks.Fitness or perk == Perks.Strength
end

local function xpMultiplierColor(level)
    return XP_MULTIPLIER_COLORS[math.min(3, clampXpLevel(level))]
end

local function perkKey(perk)
    local entriesByPerk = indexStandardPerks().byPerk
    local entry = entriesByPerk[perk] or entriesByPerk[tostring(perk)]
    return entry and entry.key or tostring(perk)
end

local function vanillaMultiplierValue(key, default)
    local values = SandboxVars and SandboxVars.MultiplierConfig
    local multiplierValue = values and values[key]
    if multiplierValue == nil then
        local optionName = "MultiplierConfig." .. key
        local option = getSandboxOptions():getOptionByName(optionName)
        if not option then error("Missing sandbox option: " .. optionName) end
        multiplierValue = option:asConfigOption():getValueAsObject()
    end
    return multiplierValue == nil and default or multiplierValue
end

local function configXpMultiplier(perk)
    local global = vanillaMultiplierValue("GlobalToggle", true)
    local key = (global == true or global == 1 or global == "true") and "Global" or perkKey(perk)
    local configuredMultiplier = vanillaMultiplierValue(key, 1)
    local multiplier = tonumber(configuredMultiplier)
    if multiplier == nil then error("Invalid XP multiplier for " .. key) end
    return multiplier
end

local function pointXpMultiplier(perk, level)
    level = clampXpLevel(level)
    local physical = isPhysicalPerk(perk)
    if level == 0 then return (physical or perk == Perks.Sprinting) and 1 or 0.25 end
    if level == 1 then return perk == Perks.Sprinting and 1.25 or 1 end
    if physical then return 1 end
    if level == 2 then return 1.33 end
    return 1.66
end

local function selectedTraitFlags(self)
    local flags = {}
    local listbox = self.listboxTraitSelected
    local items = listbox and listbox.items
    if not items then return flags end
    for index = 1, #items do
        flags[items[index].item:getType()] = true
    end
    return flags
end

local function isPacifistSkill(perk)
    if pacifistPerks == nil then
        pacifistPerks = {
            [Perks.SmallBlade] = true,
            [Perks.LongBlade] = true,
            [Perks.SmallBlunt] = true,
            [Perks.Spear] = true,
            [Perks.Blunt] = true,
            [Perks.Axe] = true,
            [Perks.Aiming] = true,
        }
    end
    return pacifistPerks[perk] == true
end

local function additionalXpMultiplier(perk, group, flags)
    local multiplier = 1.0
    local physical = isPhysicalPerk(perk)
    if flags[CharacterTrait.FAST_LEARNER] and not physical then
        multiplier = multiplier * 1.3
    end
    if flags[CharacterTrait.SLOW_LEARNER]
        and not physical and perk ~= Perks.Sprinting then
        multiplier = multiplier * 0.7
    end
    if flags[CharacterTrait.PACIFIST] and isPacifistSkill(perk) then
        multiplier = multiplier * 0.75
    end
    if flags[CharacterTrait.CRAFTY] and group == "Crafting" then
        multiplier = multiplier * 1.3
    end
    return multiplier
end

local function traitColorFlags(perk, group, flags)
    local physical = isPhysicalPerk(perk)
    return {
        fastLearner = flags[CharacterTrait.FAST_LEARNER]
            and not physical,
        slowLearner = flags[CharacterTrait.SLOW_LEARNER]
            and not physical and perk ~= Perks.Sprinting,
        crafty = flags[CharacterTrait.CRAFTY] and group == "Crafting",
        reluctantFighter = flags[CharacterTrait.PACIFIST] and isPacifistSkill(perk),
    }
end

local function itemXpMultiplier(skillData)
    return pointXpMultiplier(skillData.perk, skillData.level)
        * (skillData.additionalMultiplier or 1)
        * configXpMultiplier(skillData.perk)
end

local function effectiveMultiplierColor(baseMultiplier, multiplier)
    local color = XP_MULTIPLIER_COLORS[0]
    if multiplier > baseMultiplier + 0.001 then
        color = OTHER_SKILLS_POSITIVE_COLOR
    elseif multiplier < baseMultiplier - 0.001 then
        color = OTHER_SKILLS_NEGATIVE_COLOR
    end
    return color
end

local function mixColor(color, tint, amount)
    return {
        r = color.r + ((tint.r - color.r) * amount),
        g = color.g + ((tint.g - color.g) * amount),
        b = color.b + ((tint.b - color.b) * amount),
    }
end

local function traitTintedColor(color, flags)
    local tintedColor = color
    local good
    local bad
    if flags and (flags.fastLearner or flags.crafty) then
        local goodColor = getCore():getGoodHighlitedColor()
        good = { r = goodColor:getR(), g = goodColor:getG(), b = goodColor:getB() }
    end
    if flags and (flags.slowLearner or flags.reluctantFighter) then
        local badColor = getCore():getBadHighlitedColor()
        bad = { r = badColor:getR(), g = badColor:getG(), b = badColor:getB() }
    end
    if flags and flags.fastLearner then
        tintedColor = mixColor(tintedColor, good, 0.2)
    end
    if flags and flags.slowLearner then
        tintedColor = mixColor(tintedColor, bad, 0.2)
    end
    if flags and flags.crafty then
        tintedColor = mixColor(tintedColor, good, 0.2)
    end
    if flags and flags.reluctantFighter then
        tintedColor = mixColor(tintedColor, bad, 0.2)
    end
    return tintedColor
end

local function otherSkillsMultiplierColor(skillData)
    local baseMultiplier = pointXpMultiplier(skillData.perk, skillData.level)
    return traitTintedColor(
        effectiveMultiplierColor(baseMultiplier, itemXpMultiplier(skillData)),
        skillData.traitColorFlags)
end

local function skillPercentage(level)
    local clampedLevel = clampXpLevel(level)
    return SKILL_PERCENTAGES[clampedLevel] or SKILL_PERCENTAGES[3]
end

local function skillItem(skillSpec)
    local displayName = skillSpec.displayName
    local skillName = displayName or PerkFactory.getPerkName(skillSpec.perk)
    local skillData = {
        perk = skillSpec.perk,
        level = skillSpec.level,
        skillName = skillName,
        skillLevel = clampXpLevel(skillSpec.level + (skillSpec.extraLevel or 0) - (skillSpec.reducedLevel or 0)),
        showSkillLevel = displayName == nil,
        otherSkills = displayName ~= nil,
        additionalMultiplier = additionalXpMultiplier(skillSpec.perk, skillSpec.group, skillSpec.flags),
        traitColorFlags = traitColorFlags(skillSpec.perk, skillSpec.group, skillSpec.flags),
        percentage = skillPercentage(skillSpec.level),
        extraLevel = skillSpec.extraLevel,
        reducedLevel = skillSpec.reducedLevel,
    }
    return skillName, skillData
end

local function drawSkillLabel(self, y, skillEntry, dy, hc)
    local skillData = skillEntry.item
    if qolEnabled("ShowSkillLevels_Enabled") and skillData.showSkillLevel ~= false and skillData.skillName and skillData.skillLevel ~= nil then
        self:drawText(skillData.skillName, UI_BORDER_SPACING, y + dy, hc:getR(), hc:getG(), hc:getB(), 1, UIFont.Small)
        local textManager = getTextManager()
        local x = UI_BORDER_SPACING + textManager:MeasureStringX(UIFont.Small, skillData.skillName)
        local separator = " - "
        x = x - 2
        self:drawText(separator, x, y + dy, SKILL_LEVEL_SEPARATOR_COLOR.r, SKILL_LEVEL_SEPARATOR_COLOR.g, SKILL_LEVEL_SEPARATOR_COLOR.b, 1, UIFont.Small)
        x = x + textManager:MeasureStringX(UIFont.Small, separator)
        self:drawText(tostring(skillData.skillLevel), x, y + dy, SKILL_LEVEL_COLOR.r, SKILL_LEVEL_COLOR.g, SKILL_LEVEL_COLOR.b, 1, UIFont.Small)
        return
    end
    if skillData.otherSkillsVariant then
        local color = skillData.otherSkillsVariant == "Weapons"
            and getCore():getBadHighlitedColor()
            or getCore():getGoodHighlitedColor()
        self:drawText(skillEntry.text, UI_BORDER_SPACING, y + dy,
            color:getR(), color:getG(), color:getB(), 1, UIFont.Small)
        return
    end
    self:drawText(skillEntry.text, UI_BORDER_SPACING, y + dy, hc:getR(), hc:getG(), hc:getB(), 1, UIFont.Small)
end

local nativeDrawXpBoostMap = CharacterCreationProfession.drawXpBoostMap
local function drawXpBoostBorder(listbox, y)
    local yy = y + listbox.itemheight
    listbox:drawRectBorder(0, y, listbox:getWidth(), yy - y, 0.5, listbox.borderColor.r, listbox.borderColor.g, listbox.borderColor.b)
    return yy
end

local function drawVanillaXpBars(listbox, y, vanillaLevel, dy, greenBlitsX, blitW, blitGap, blitH, hc)
    if vanillaLevel == 0 then return end
    local whiteBar = professionWhiteBar()
    for i = 1, vanillaLevel do
        listbox:drawTextureScaled(whiteBar,
            greenBlitsX + (i * (blitW + blitGap)), y + dy, blitW, blitH, 1,
            hc:getR(), hc:getG(), hc:getB())
    end
end

local function drawXpMultiplier(listbox, y, skillData, showMultiplier, dy, hc)
    if not showMultiplier and isPhysicalPerk(skillData.perk) then return end

    local text = skillData.percentage
    local textR, textG, textB = hc:getR(), hc:getG(), hc:getB()
    if showMultiplier then
        text = string.format("x%.2f", itemXpMultiplier(skillData))
        local textColor = skillData.otherSkills
            and otherSkillsMultiplierColor(skillData)
            or traitTintedColor(xpMultiplierColor(skillData.level), skillData.traitColorFlags)
        textR, textG, textB = textColor.r, textColor.g, textColor.b
    end
    local right = listbox.width - UI_BORDER_SPACING - SCROLL_BAR_WIDTH
    listbox:drawTextRight(text, right, y + dy, textR, textG, textB, 1, UIFont.Small)
end

local function drawVisibleXpBoost(listbox, y, skillEntry, showMultiplier)
    local skillData = skillEntry.item
    local vanillaLevel = skillData.level or 0
    local dy = (listbox.itemheight - listbox.fontHgt) / 2
    local hc = getCore():getGoodHighlitedColor()
    local textManager = getTextManager()
    local blitH = textManager:getFontHeight(UIFont.Small)
    local blitW = math.floor(blitH / (10/3))
    local blitGap = math.floor(blitW / 4)
    local blitText = showMultiplier and "x1.00" or "+ 100%"
    local blitXOffset = textManager:MeasureStringX(UIFont.Small, blitText) + SCROLL_BAR_WIDTH
    local greenBlitsX = listbox.width - (blitXOffset + 12 * (blitW + blitGap))

    drawSkillLabel(listbox, y, skillEntry, dy, hc)
    drawVanillaXpBars(listbox, y, vanillaLevel, dy, greenBlitsX, blitW, blitGap, blitH, hc)
    drawExtraBars(listbox, y, vanillaLevel, skillData.extraLevel or 0, skillData.reducedLevel or 0)
    drawXpMultiplier(listbox, y, skillData, showMultiplier, dy, hc)
    return drawXpBoostBorder(listbox, y)
end

local function drawAdditionalXpBoost(listbox, y, skillEntry, alt)
    local skillData = skillEntry.item
    local extraLevel = skillData.extraLevel
    local vanillaLevel = skillData.level or 0
    if vanillaLevel > 0 then
        local drawHeight = nativeDrawXpBoostMap(listbox, y, skillEntry, alt)
        drawExtraBars(listbox, y, vanillaLevel, extraLevel, skillData.reducedLevel)
        return drawHeight
    end

    local dy = (listbox.itemheight - listbox.fontHgt) / 2
    local hc = getCore():getGoodHighlitedColor()
    drawSkillLabel(listbox, y, skillEntry, dy, hc)
    drawExtraBars(listbox, y, 0, extraLevel, skillData.reducedLevel)
    return drawXpBoostBorder(listbox, y)
end

local function drawXpBoostMap(listbox, y, skillEntry, alt)
    local skillData = skillEntry.item
    if skillData == nil then return nativeDrawXpBoostMap(listbox, y, skillEntry, alt) end

    local showMultiplier = qolEnabled("ShowXPMultiplier_Enabled")
    local showLevels = qolEnabled("ShowSkillLevels_Enabled")
    if showMultiplier or showLevels then return drawVisibleXpBoost(listbox, y, skillEntry, showMultiplier) end
    if skillData.extraLevel == nil then return nativeDrawXpBoostMap(listbox, y, skillEntry, alt) end
    return drawAdditionalXpBoost(listbox, y, skillEntry, alt)
end
CharacterCreationProfession.drawXpBoostMap = drawXpBoostMap

local function collectXpBoostLevels(self)
    local xpLevels = {}
    local listbox = self.listboxTraitSelected
    local items = listbox and listbox.items
    if items then
        for index = 1, #items do
            addXpBoosts(xpLevels, items[index].item:getXpBoosts())
        end
    end
    if self.profession then addXpBoosts(xpLevels, self.profession:getXpBoosts()) end
    xpLevels[Perks.Fitness] = (xpLevels[Perks.Fitness] or 0) + 5
    xpLevels[Perks.Strength] = (xpLevels[Perks.Strength] or 0) + 5
    return xpLevels
end

local function markOtherSkill(skillGroups, entry)
    skillGroups.hasOtherSkills = true
    skillGroups.hasCraftSkills = skillGroups.hasCraftSkills or entry.group == "Crafting"
    skillGroups.hasWeaponSkills = skillGroups.hasWeaponSkills or isPacifistSkill(entry.perk)
end

local function configuredSkill(state, entry)
    local levelChange = M.standardValue(entry)
    if levelChange == 0 then return end

    local vanillaLevel = state.xpLevels[entry.perk] or 0
    local level = clampXpLevel(vanillaLevel)
    local extraLevel = math.max(0, math.min(levelChange, 10 - level))
    local reducedLevel = math.max(0, math.min(-levelChange, level))
    if extraLevel == 0 and reducedLevel == 0 then return end

    local label, skill = skillItem({
        perk = entry.perk,
        level = level,
        group = entry.group,
        flags = state.traitFlags,
        extraLevel = extraLevel,
        reducedLevel = reducedLevel,
    })
    if skill.skillLevel > 0 or (skill.skillLevel == 0 and qolEnabled("ShowSkillLevels_Enabled")) then
        return "added", label, skill
    end
    return "other"
end

local function addConfiguredSkills(state)
    for index = 1, #state.standardPerks do
        local entry = state.standardPerks[index]
        local status, label, skill = configuredSkill(state, entry)
        if status then
            state.xpLevels[entry.perk] = nil
            if status == "added" then
                state.listbox:addItem(label, skill)
                state.addedPerks[entry.perk] = true
            else
                markOtherSkill(state.skillGroups, entry)
            end
        end
    end
end

local function addBaseSkills(state)
    for index = 1, #state.standardPerks do
        local entry = state.standardPerks[index]
        if not state.addedPerks[entry.perk] then
            local level = clampXpLevel(state.xpLevels[entry.perk] or 0)
            if level > 0 then
                local label, skill = skillItem({
                    perk = entry.perk,
                    level = level,
                    group = entry.group,
                    flags = state.traitFlags,
                })
                state.listbox:addItem(label, skill)
            else
                markOtherSkill(state.skillGroups, entry)
            end
        end
    end
end

local function addOtherSkillsGroup(state, entry, groupConfig)
    local label, skill = skillItem({
        perk = entry.perk,
        level = 0,
        group = groupConfig.group,
        flags = groupConfig.flags,
        displayName = getText(groupConfig.textKey),
    })
    skill.otherSkillsOrder = groupConfig.order
    skill.otherSkillsVariant = groupConfig.variant
    state.listbox:addItem(label, skill)
end

local function addCraftSkills(state)
    if not state.skillGroups.hasCraftSkills or not state.traitFlags[CharacterTrait.CRAFTY] then return end
    addOtherSkillsGroup(state, requiredStandardEntry("Woodwork"), {
        textKey = "Sandbox_CharacterCreationCustomizer_OtherSkillsCraft",
        group = "Crafting",
        flags = { [CharacterTrait.CRAFTY] = true },
        order = 1,
        variant = "Craft",
    })
end

local function addWeaponSkills(state)
    if not state.skillGroups.hasWeaponSkills or not state.traitFlags[CharacterTrait.PACIFIST] then return end
    addOtherSkillsGroup(state, requiredStandardEntry("Aiming"), {
        textKey = "Sandbox_CharacterCreationCustomizer_OtherSkillsWeapons",
        flags = {
            [CharacterTrait.PACIFIST] = true,
            [CharacterTrait.FAST_LEARNER] = state.traitFlags[CharacterTrait.FAST_LEARNER],
            [CharacterTrait.SLOW_LEARNER] = state.traitFlags[CharacterTrait.SLOW_LEARNER],
        },
        order = 2,
        variant = "Weapons",
    })
end

local function addGeneralSkills(state)
    if not state.skillGroups.hasOtherSkills then return end
    local entry = standardEntry("Maintenance") or state.standardPerks[1]
    if not entry then error("No standard perks available") end
    addOtherSkillsGroup(state, entry, {
        textKey = "Sandbox_CharacterCreationCustomizer_OtherSkills",
        flags = state.traitFlags,
        order = 3,
    })
end

local function addOtherSkills(state)
    if not qolEnabled("ShowSkillLevels_Enabled") and not qolEnabled("ShowXPMultiplier_Enabled") then return end
    addCraftSkills(state)
    addWeaponSkills(state)
    addGeneralSkills(state)
end

local function sortXpBoosts(state)
    state.listbox:sort(function(left, right)
        local leftIsOther = left.item and left.item.otherSkills
        local rightIsOther = right.item and right.item.otherSkills
        if leftIsOther ~= rightIsOther then return not leftIsOther end
        if leftIsOther and left.item.otherSkillsOrder ~= right.item.otherSkillsOrder then
            return left.item.otherSkillsOrder < right.item.otherSkillsOrder
        end
        return not string.sort(left.text, right.text)
    end)
end

function CharacterCreationProfession:checkXPBoost()
    self.listboxXpBoost:clear()
    local xpState = {
        listbox = self.listboxXpBoost,
        xpLevels = collectXpBoostLevels(self),
        standardPerks = M.getStandardPerks(),
        traitFlags = selectedTraitFlags(self),
        addedPerks = {},
        skillGroups = {
            hasOtherSkills = false,
            hasCraftSkills = false,
            hasWeaponSkills = false,
        },
    }
    addConfiguredSkills(xpState)
    addBaseSkills(xpState)
    addOtherSkills(xpState)
    sortXpBoosts(xpState)
end

local nativeCreate = CharacterCreationProfession.create
function CharacterCreationProfession:create()
    M.debugLog("Creating character creation screen")
    M.apply()
    local creationResult = nativeCreate(self)
    self:checkXPBoost()
    M.debugLog("Character creation screen created")
    return creationResult
end

local nativeSetVisible = CharacterCreationProfession.setVisible
local function refreshProfessionList(self)
    if not self.listboxProf then return end

    M.debugLog("Refreshing profession list")
    local selectedProfessionKey = self.profession and M.professionKey(self.profession)
    self:populateProfessionList(self.listboxProf)
    if not selectedProfessionKey then return end

    local professionItems = self.listboxProf.items
    if not professionItems then return end
    for index = 1, #professionItems do
        local professionEntry = professionItems[index]
        if M.professionKey(professionEntry.item) == selectedProfessionKey then
            self.listboxProf.selected = index
            self.profession = professionEntry.item
            return
        end
    end
end

local function clearAppliedProfession(self)
    local previousGrants = self.characterCreationCustomizerAppliedGrantedTraits
    local previousProfession = self.profession
    local previousKey = self.characterCreationCustomizerAppliedGrantedProfessionKey
    if not previousGrants and previousProfession then previousGrants = M.professionGrantedTraits(previousProfession) end

    removeGrantedProfessionTraits(self, previousGrants, previousKey or (previousProfession and M.professionKey(previousProfession)))
    self.characterCreationCustomizerAppliedGrantedTraits = nil
    self.characterCreationCustomizerAppliedGrantedProfessionKey = nil
end

local function selectFallbackProfession(self)
    local fallback = M.fallbackProfession()
    if not self.profession or M.professionEnabled(self.profession) or self.profession == fallback then return true end
    if not fallback then error("No profession is available for character creation") end
    self:onSelectProf(fallback)
    return false
end

local function applyCurrentProfession(self)
    if not self.profession then return end
    local grants = M.professionGrantedTraits(self.profession)
    addGrantedProfessionTraits(self, self.profession, grants)
    self.characterCreationCustomizerAppliedGrantedTraits = grants
    self.characterCreationCustomizerAppliedGrantedProfessionKey = M.professionKey(self.profession)
    self.cost = M.professionCost(self.profession)
end

local function reconcileLiveConfiguration(self)
    M.debugLog("Reconciling live character creation settings")
    refreshProfessionList(self)
    freeSources(self)
    clearAppliedProfession(self)
    refreshSelectedTraitDefinitions(self)
    removeDisabledSelectedTraits(self)

    if not selectFallbackProfession(self) then return end
    applyCurrentProfession(self)

    removeUnbuyableSelectedTraits(self)
    recalculatePointToSpend(self)
    self:repopulateTraitLists()
    self:checkXPBoost()
    M.debugLog("Live character creation settings reconciled")
end

local function customizerConfigSignature()
    local fingerprint = M.configurationFingerprint()
    if fingerprint ~= nil then return fingerprint end

    local values = { M.configurationSignature() }

    local professions = CharacterProfessionDefinition.getProfessions()
    for i = 0, professions:size() - 1 do
        local profession = professions:get(i)
        values[#values + 1] = "profession:" .. M.professionKey(profession) .. ":"
            .. tostring(M.professionEnabled(profession))
    end

    values[#values + 1] = "qol:levels:" .. tostring(M.optionValue("QOL", "ShowSkillLevels_Enabled"))
    values[#values + 1] = "qol:multiplier:" .. tostring(M.optionValue("QOL", "ShowXPMultiplier_Enabled"))
    values[#values + 1] = "qol:professionPoints:" .. tostring(M.optionValue("QOL", "ShowProfessionPoints_Enabled"))

    table.sort(values)
    return table.concat(values, "|")
end

function CharacterCreationProfession:setVisible(visible, joypadData)
    if visible then
        M.debugLog("Showing character creation screen")
        M.apply()
        reconcileLiveConfiguration(self)
        self.characterCreationCustomizerConfigSignature = customizerConfigSignature()
    end
    local visibilityResult = nativeSetVisible(self, visible, joypadData)
    if visible then
        self:checkXPBoost()
    end
    return visibilityResult
end

local nativeUpdate = CharacterCreationProfession.update

function CharacterCreationProfession:update()
    local updateResult = nativeUpdate(self)
    local checkCount = (self.characterCreationCustomizerConfigCheckCount or 0) + 1
    if checkCount < CONFIGURATION_CHECK_INTERVAL then
        self.characterCreationCustomizerConfigCheckCount = checkCount
        return updateResult
    end
    self.characterCreationCustomizerConfigCheckCount = 0
    local signature = customizerConfigSignature()
    if signature ~= self.characterCreationCustomizerConfigSignature then
        M.debugLog("Sandbox configuration changed during character creation")
        self.characterCreationCustomizerConfigSignature = signature
        M.apply()
        reconcileLiveConfiguration(self)
    end
    return updateResult
end

installSandboxSettings(standardEntry, standardGroupRank)
Events.OnInitWorld.Add(function()
    M.apply()
end)

if isClient() then
    Events.OnNewGame.Add(function(player)
        sendClientCommand(player, "CharacterCreationCustomizer", "ApplyInitialLevels", {})
    end)
end
