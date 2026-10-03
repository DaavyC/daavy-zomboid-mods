local M = require "ccc_shared"
require "OptionScreens/CharacterCreationProfession"
local core = getCore()

local UI_BORDER_SPACING = 10
local SCROLL_BAR_WIDTH = 13
local CONFIGURATION_CHECK_INTERVAL = 30
local NEUTRAL_TEXT_COLOR = { r = 0.65, g = 0.65, b = 0.65 }

if rawget(M, "clientInstalled") then return end
rawset(M, "clientInstalled", true)
local installSandboxSettings = require "ui/ccc_sandbox_settings"
local installSkillDisplay = require "ui/ccc_skill_display"

local traitItemStates = setmetatable({}, { __mode = "k" })

local function traitItemState(item)
    local state = traitItemStates[item]
    if not state then
        state = {}
        traitItemStates[item] = state
    end
    return state
end

local qolEnabled = M.qolEnabled
local traitDefinitionByType = M.traitDefinition
local standardPerkIndex

local function indexStandardPerks()
    if standardPerkIndex ~= nil then return standardPerkIndex end

    local entriesByKey = {}
    local entriesByPerk = {}
    local groupRanks = {}
    local groupRank = 0
    local standardPerks = M.getStandardPerks()
    for index = 1, #standardPerks do
        local entry = standardPerks[index]
        entriesByKey[entry.key] = entry
        entriesByPerk[entry.perk] = entry
        entriesByPerk[tostring(entry.perk)] = entry
        if not groupRanks[entry.group] then
            groupRank = groupRank + 1
            groupRanks[entry.group] = groupRank
        end
    end
    standardPerkIndex = { byKey = entriesByKey, byPerk = entriesByPerk, groupRanks = groupRanks }
    return standardPerkIndex
end

local function standardEntry(key)
    return indexStandardPerks().byKey[key]
end

local function standardGroupRank(group)
    return indexStandardPerks().groupRanks[group] or 99
end

local function populateNativeTraitList(self, list, expectedGroup)
    M.apply()
    list:clear()
    local traitList = CharacterTraitDefinition.getTraits()
    for i = 0, traitList:size() - 1 do
        local trait = traitList:get(i)
        local original = M.originalTrait(trait)
        local current = traitDefinitionByType(original:getType())
        local group = M.traitGroup(original)
        local selectable = M.traitBuyable(original)
        if M.traitEnabled(original) and selectable and group == expectedGroup and self:isTraitEnabled(current) and not self:isTraitExcluded(current) then
            list:addItem(current:getLabel(), current, current:getDescription())
        end
    end
end

function CharacterCreationProfession:populateTraitList(list)
    populateNativeTraitList(self, list, "PositiveTraits")
end

function CharacterCreationProfession:populateBadTraitList(list)
    populateNativeTraitList(self, list, "NegativeTraits")
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
    return sources ~= nil and next(sources) ~= nil
end

local function isFreeTrait(self, trait)
    local key = traitKey(trait)
    local sources = key and freeSources(self)[key]
    return hasFreeSource(sources)
end

local function grantFreeSource(self, trait, source)
    local key = traitKey(trait)
    if not key or not source then return end
    local sourcesByTrait = freeSources(self)
    local sources = sourcesByTrait[key] or {}
    sources[source] = true
    sourcesByTrait[key] = sources
end

local function releaseFreeSource(self, trait, source)
    local key = traitKey(trait)
    if not key or not source then return end
    local sourcesByTrait = freeSources(self)
    local sources = sourcesByTrait[key]
    if not sources then return end
    sources[source] = nil
    if not hasFreeSource(sources) then sourcesByTrait[key] = nil end
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

local function grantTrait(self, trait, source)
    grantFreeSource(self, trait, source)
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
    self:doTestForMutuallyExclusiveTraits(trait, false)
end

local function releaseGrantedTrait(self, trait, source)
    releaseFreeSource(self, trait, source)
    local _, selectedItem = selectedTrait(self, traitKey(trait))
    if selectedItem and not isFreeTrait(self, trait) and traitItemState(selectedItem).manualTrait ~= true then
        removeTraitFromList(self.listboxTraitSelected, trait)
        self:doTestForMutuallyExclusiveTraits(trait, true)
    end
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
        grantTrait(self, grantedTrait, source)
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
        releaseGrantedTrait(self, grantedTrait, source)
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
    local color = pointsDelta > 0 and core:getGoodHighlitedColor() or core:getBadHighlitedColor()
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
    local definitions = table.newarray()
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
        releaseGrantedTrait(self, grantedDefinitions[index], source)
    end
    refreshFreeTraitFlags(self)
end

local function addGrantedProfessionTraits(self, profession, traitTypes)
    local source = "profession:" .. M.professionKey(profession)
    local grantedDefinitions = grantedTraitDefinitions(traitTypes)
    for index = 1, #grantedDefinitions do
        grantTrait(self, grantedDefinitions[index], source)
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

local function applyProfessionSelection(self, profession, mainScreen)
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
    local mainScreen = requireMainScreen()
    local creationMain = requireCreationMain()
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

    applyProfessionSelection(self, profession, mainScreen)

    addGrantedProfessionTraits(self, profession, nextGrants)
    self.characterCreationCustomizerAppliedGrantedTraits = nextGrants
    self.characterCreationCustomizerAppliedGrantedProfessionKey = M.professionKey(profession)
    recalculatePointToSpend(self)
    self:repopulateTraitLists()
    self:checkXPBoost()
    CharacterCreationMain.sort(self.listboxTrait.items)
    CharacterCreationMain.invertSort(self.listboxBadTrait.items)
    CharacterCreationMain.sort(self.listboxTraitSelected.items)
    creationMain:disableBtn()
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

local xpConfigSignature = installSkillDisplay(indexStandardPerks, qolEnabled)

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
    removeConflictingProfessionTraits(self, grantedTraitDefinitions(grants))
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
    local multiplierSignature = xpConfigSignature()
    if fingerprint ~= nil then return fingerprint .. "|xp:" .. multiplierSignature end

    local values = table.newarray(M.configurationSignature(), multiplierSignature)

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
