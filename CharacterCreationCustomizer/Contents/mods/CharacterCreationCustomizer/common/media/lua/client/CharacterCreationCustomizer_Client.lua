require "OptionScreens/CharacterCreationProfession"

local M = CharacterCreationCustomizer
local UI_BORDER_SPACING = 10
local SCROLL_BAR_WIDTH = 13
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

if M.clientInstalled then return end
M.clientInstalled = true

local groupOrder = {
    QOL = 1,
    PositiveTraits = 1,
    NegativeTraits = 2,
    NonBuyableTraits = 3,
    Professions = 1,
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

local settingTitles = {
    ["CharacterCreationCustomizer.Debug"] = "CharacterCreationCustomizer_Advanced",
}

local function trimTooltipText(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function automaticTooltip(setting)
    if not getSandboxOptions then return end
    local options = getSandboxOptions()
    local option = options and options:getOptionByName(setting.name)
    if not option then return end
    local optionType = option:getType()
    if optionType == "integer" or optionType == "double" then
        return "Min: " .. tostring(option:getMin()) .. " Max: " .. tostring(option:getMax()) .. " Default: " .. tostring(option:getDefaultValue())
    end
    local rawDefault = option:getDefaultValue()
    if rawDefault == nil then return end
    local defaultValue = tostring(rawDefault)
    if defaultValue == "" then return end
    return "Default: " .. defaultValue
end

local function composeTooltip(setting, description)
    local descriptionText = trimTooltipText(description)
    local automaticText = trimTooltipText(automaticTooltip(setting))
    if automaticText == "" then return descriptionText end
    if descriptionText == "" then return automaticText end
    return descriptionText .. "\n" .. automaticText
end

local function qolEnabled(key)
    local value = M.optionValue("QOL", key)
    if value == nil then return true end
    return value == true or value == 1 or value == "true"
end

local standardGroupRanks

local function standardEntry(key)
    for _, entry in ipairs(M.getStandardPerks()) do
        if entry.key == key then return entry end
    end
end

local function standardGroupRank(group)
    if not standardGroupRanks then
        standardGroupRanks = {}
        local rank = 0
        for _, entry in ipairs(M.getStandardPerks()) do
            if not standardGroupRanks[entry.group] then
                rank = rank + 1
                standardGroupRanks[entry.group] = rank
            end
        end
    end
    return standardGroupRanks[group] or 99
end

local function populateNativeTraitList(self, list, positive)
    M.apply()
    list:clear()
    local expectedGroup = positive and "PositiveTraits" or "NegativeTraits"
    local traitList = CharacterTraitDefinition.getTraits()
    for i = 0, traitList:size() - 1 do
        local trait = traitList:get(i)
        local original = M.originalTrait(trait)
        local current = CharacterTraitDefinition.getCharacterTraitDefinition(original:getType()) or trait
        local group = M.traitGroup(original)
        local selectable = not original:isFree() or M.traitBuyable(original)
        if M.traitEnabled(original) and selectable and group == expectedGroup and self:isTraitEnabled(current) and not self:isTraitExcluded(current) then
            list:addItem(current:getLabel(), current, current:getDescription())
        end
    end
end

CharacterCreationProfession.populateTraitList = function(self, list)
    populateNativeTraitList(self, list, true)
end

CharacterCreationProfession.populateBadTraitList = function(self, list)
    populateNativeTraitList(self, list, false)
end

local function traitKey(trait)
    return trait and M.definitionKey(trait)
end

local function findTrait(list, key)
    for index, item in ipairs(list.items or {}) do
        if traitKey(item.item) == key then
            return index, item
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
    for index = #(list.items or {}), 1, -1 do
        if traitKey(list.items[index].item) == key then
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
    for _, item in ipairs(self.listboxTraitSelected.items or {}) do
        local free = isFreeTrait(self, item.item)
        item.freeTrait = free or nil
    end
end

CharacterCreationProfession.doTestForMutuallyExclusiveTraits = function(self, trait, isRemovingTrait)
    M.rememberTraits()
    for i = 0, trait:getMutuallyExclusiveTraits():size() - 1 do
        local exclusiveTrait = trait:getMutuallyExclusiveTraits():get(i)
        local exclusiveDefinition = CharacterTraitDefinition.getCharacterTraitDefinition(exclusiveTrait)
        if exclusiveDefinition and not exclusiveDefinition:isFree() then
            local original = M.originalTrait(exclusiveDefinition)
            local group = M.traitGroup(original)
            local list = group == "PositiveTraits" and self.listboxTrait or group == "NegativeTraits" and self.listboxBadTrait
            if isRemovingTrait then
                if M.traitEnabled(original) and not self:isTraitExcluded(exclusiveDefinition) then
                    if list then addUniqueTrait(list, exclusiveDefinition) end
                end
            else
                if list then removeTraitFromList(list, exclusiveDefinition) end
            end
        end
    end
end

local function prepareGrantedTrait(self, trait, source)
    setFreeSource(self, trait, source, true)
    local _, item = selectedTrait(self, traitKey(trait))
    if not item then
        item = self.listboxTraitSelected:addItem(trait:getLabel(), trait, trait:getDescription())
    end
    if item then
        item.manualTrait = item.manualTrait == true
        item.tooltip = trait:getDescription()
    end
    removeTraitFromList(self.listboxTrait, trait)
    removeTraitFromList(self.listboxBadTrait, trait)
end

CharacterCreationProfession.addTrait = function(self, trait)
    local original = M.originalTrait(trait)
    if M.traitGroup(original) and not M.traitEnabled(original) then return end
    local key = traitKey(trait)
    if selectedTrait(self, key) then return end

    local item = self.listboxTraitSelected:addItem(trait:getLabel(), trait, trait:getDescription())
    item.manualTrait = true
    if not isFreeTrait(self, trait) then self.pointToSpend = self.pointToSpend - trait:getCost() end
    removeTraitFromList(self.listboxTrait, trait)
    removeTraitFromList(self.listboxBadTrait, trait)

    local source = "trait:" .. key
    for i = 0, trait:getGrantedTraits():size() - 1 do
        local grantedTrait = CharacterTraitDefinition.getCharacterTraitDefinition(trait:getGrantedTraits():get(i))
        if grantedTrait then
            prepareGrantedTrait(self, grantedTrait, source)
            self:doTestForMutuallyExclusiveTraits(grantedTrait, false)
        end
    end

    refreshFreeTraitFlags(self)
    self:doTestForMutuallyExclusiveTraits(trait, false)
    self:repopulateTraitLists()
end

CharacterCreationProfession.onSelectChosenTrait = function(self, item)
    local _, selected = selectedTrait(self, traitKey(item))
    local canRemove = selected and selected.manualTrait == true and not isFreeTrait(self, item)
    self.removeTraitBtn:setEnable(canRemove or false)
end

CharacterCreationProfession.removeTrait = function(self, index)
    local item = self.listboxTraitSelected:getItem(index)
    if not item or isFreeTrait(self, item.item) then return end

    local trait = item.item
    local key = traitKey(trait)
    removeTraitFromList(self.listboxTraitSelected, trait)
    if item.manualTrait ~= false then self.pointToSpend = self.pointToSpend + trait:getCost() end

    local source = "trait:" .. key
    for i = 0, trait:getGrantedTraits():size() - 1 do
        local grantedTrait = CharacterTraitDefinition.getCharacterTraitDefinition(trait:getGrantedTraits():get(i))
        if grantedTrait then
            setFreeSource(self, grantedTrait, source, false)
            local key = traitKey(grantedTrait)
            local _, grantedItem = selectedTrait(self, key)
            if grantedItem and not isFreeTrait(self, grantedTrait) and grantedItem.manualTrait ~= true then
                removeTraitFromList(self.listboxTraitSelected, grantedTrait)
                self:doTestForMutuallyExclusiveTraits(grantedTrait, true)
            end
        end
    end

    refreshFreeTraitFlags(self)
    self:doTestForMutuallyExclusiveTraits(trait, true)
    self:repopulateTraitLists()
end

local nativeRandomizeTraits = CharacterCreationProfession.randomizeTraits
CharacterCreationProfession.randomizeTraits = function(self)
    if #self.listboxTrait.items == 0 or #self.listboxBadTrait.items == 0 then
        self:resetBuild()
        return
    end
    return nativeRandomizeTraits(self)
end

local nativeDrawTraitMap = CharacterCreationProfession.drawTraitMap
CharacterCreationProfession.drawTraitMap = function(self, y, item, alt)
    local isFreeGrant = item.freeTrait
    if not isFreeGrant then
        return nativeDrawTraitMap(self, y, item, alt)
    end

    local original = item.item
    item.item = {
        getTexture = function() return original:getTexture() end,
        getCost = function() return 0 end,
        getLabel = function() return original:getLabel() end,
        getRightLabel = function() return "" end,
    }
    local result = nativeDrawTraitMap(self, y, item, alt)
    item.item = original
    return result
end

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
CharacterCreationProfession.drawProfessionMap = function(self, y, professionEntry, alt)
    local nextY = nativeDrawProfessionMap(self, y, professionEntry, alt)
    if not qolEnabled("ShowProfessionPoints_Enabled") then return nextY end

    local pointText, pointR, pointG, pointB = professionPointDisplay(professionEntry.item)
    local dy = (professionEntry.height - self.fontHgt) / 2
    local right = self.width - UI_BORDER_SPACING - SCROLL_BAR_WIDTH
    self:drawTextRight(pointText, right, y + dy,
        pointR, pointG, pointB, 0.9, UIFont.Small)
    return nextY
end

local function grantedTraitDefinitions(traitTypes)
    local definitions = {}
    for _, traitType in ipairs(traitTypes or {}) do
        local trait = CharacterTraitDefinition.getCharacterTraitDefinition(traitType)
        if trait then
            definitions[#definitions + 1] = trait
        end
    end
    return definitions
end

local function removeGrantedProfessionTraits(self, traitTypes, professionKey)
    local source = professionKey and "profession:" .. professionKey
    if not source then return end
    for _, trait in ipairs(grantedTraitDefinitions(traitTypes)) do
        local key = traitKey(trait)
        setFreeSource(self, trait, source, false)
        local _, item = selectedTrait(self, key)
        if item and not isFreeTrait(self, trait) and item.manualTrait ~= true then
            removeTraitFromList(self.listboxTraitSelected, trait)
            self:doTestForMutuallyExclusiveTraits(trait, true)
        end
    end
    refreshFreeTraitFlags(self)
end

local function addGrantedProfessionTraits(self, profession, traitTypes)
    local source = "profession:" .. M.professionKey(profession)
    for _, trait in ipairs(grantedTraitDefinitions(traitTypes)) do
        prepareGrantedTrait(self, trait, source)
        self:doTestForMutuallyExclusiveTraits(trait, false)
    end
    refreshFreeTraitFlags(self)
    CharacterCreationMain.sort(self.listboxTraitSelected.items)
end

local function refreshSelectedTraitDefinitions(self)
    for _, item in ipairs(self.listboxTraitSelected.items or {}) do
        local definition = CharacterTraitDefinition.getCharacterTraitDefinition(item.item:getType())
        if definition then
            item.item = definition
            item.text = definition:getLabel()
            item.tooltip = definition:getDescription()
        end
    end
    refreshFreeTraitFlags(self)
end

local function removeDisabledSelectedTraits(self)
    for index = #(self.listboxTraitSelected.items or {}), 1, -1 do
        local item = self.listboxTraitSelected.items[index]
        if not isFreeTrait(self, item.item)
            and not M.traitEnabled(M.originalTrait(item.item)) then
            self:removeTrait(index)
        end
    end
end

local function removeUnbuyableSelectedTraits(self)
    for index = #(self.listboxTraitSelected.items or {}), 1, -1 do
        local item = self.listboxTraitSelected.items[index]
        local original = M.originalTrait(item.item)
        if item.manualTrait and not isFreeTrait(self, item.item)
            and original:isFree() and not M.traitBuyable(original) then
            self:removeTrait(index)
        end
    end
end

local function recalculatePointToSpend(self)
    local pointToSpend = 0
    for _, item in ipairs(self.listboxTraitSelected.items or {}) do
        if item.manualTrait and not isFreeTrait(self, item.item) then
            pointToSpend = pointToSpend - item.item:getCost()
        end
    end
    self.pointToSpend = pointToSpend
end

local function removeConflictingProfessionTraits(self, grantedDefinitions)
    for index = #(self.listboxTraitSelected.items or {}), 1, -1 do
        local selected = self.listboxTraitSelected.items[index].item
        local shouldRemove = false
        for _, granted in ipairs(grantedDefinitions) do
            if granted:getMutuallyExclusiveTraits():contains(selected:getType()) then
                shouldRemove = true
                break
            end
        end
        if shouldRemove and not isFreeTrait(self, selected) then self:removeTrait(index) end
    end
end

local function applyProfessionSelection(self, profession)
    self.profession = profession
    for index, professionEntry in ipairs(self.listboxProf.items or {}) do
        if professionEntry.item == profession then
            self.listboxProf.selected = index
            break
        end
    end

    local descriptionPanel = MainScreen.instance.desc
    descriptionPanel:setProfessionSkills(profession)
    descriptionPanel:setCharacterProfession(profession:getType())
    self.cost = M.professionCost(profession)
    self:changeClothes()
end

CharacterCreationProfession.onSelectProf = function(self, profession)
    if not profession then return end
    freeSources(self)
    M.apply()
    local fallback = M.fallbackProfession()
    if not M.professionEnabled(profession) and profession ~= fallback then
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
    CharacterCreationMain.instance:disableBtn()
end

CharacterCreationProfession.populateProfessionList = function(self, list)
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
        if fallback then
            local newitem = list:addItem(fallback:getUIName(), fallback)
            newitem.tooltip = fallback:getDescription()
        end
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

local function drawExtraBars(self, y, vanillaLevel, extraLevel, reducedLevel)
    local dy = (self.itemheight - self.fontHgt) / 2
    reducedLevel = reducedLevel or 0
    local blitH = getTextManager():getFontHeight(UIFont.Small)
    local blitW = math.floor(blitH / (10/3))
    local blitGap = math.floor(blitW / 4)
    local multiplierText = qolEnabled("ShowXPMultiplier_Enabled") and "x1.00" or "+ 100%"
    local blitXOffset = getTextManager():MeasureStringX(UIFont.Small, multiplierText) + SCROLL_BAR_WIDTH
    local greenBlitsX = self.width - (blitXOffset + 12 * (blitW + blitGap))

    for i = 1, extraLevel do
        local position = vanillaLevel + i
        self:drawTextureScaled(CharacterCreationProfession.instance.whiteBar,
            greenBlitsX + (position * (blitW + blitGap)), y + dy, blitW, blitH, 1,
            0.15, 0.55, 0.9)
    end

    for i = 1, reducedLevel do
        local position = vanillaLevel - reducedLevel + i
        self:drawTextureScaled(CharacterCreationProfession.instance.whiteBar,
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
    for _, entry in ipairs(M.getStandardPerks()) do
        if entry.perk == perk or tostring(entry.perk) == tostring(perk) then
            return entry.key
        end
    end
    return tostring(perk)
end

local function vanillaMultiplierValue(key, default)
    local values = SandboxVars and SandboxVars.MultiplierConfig
    local value = values and values[key]
    if value == nil and SandboxVars then
        value = SandboxVars["MultiplierConfig." .. key]
    end
    if value == nil and getSandboxOptions then
        local options = getSandboxOptions()
        local option = options and options:getOptionByName("MultiplierConfig." .. key)
        value = option and option:getValue()
    end
    return value == nil and default or value
end

local function configXpMultiplier(perk)
    local global = vanillaMultiplierValue("GlobalToggle", true)
    local key = (global == true or global == 1 or global == "true") and "Global" or perkKey(perk)
    return tonumber(vanillaMultiplierValue(key, 1)) or 1
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
    for _, item in pairs(self.listboxTraitSelected and self.listboxTraitSelected.items or {}) do
        flags[item.item:getType()] = true
    end
    return flags
end

local function isPacifistSkill(perk)
    return perk == Perks.SmallBlade
        or perk == Perks.LongBlade
        or perk == Perks.SmallBlunt
        or perk == Perks.Spear
        or perk == Perks.Blunt
        or perk == Perks.Axe
        or perk == Perks.Aiming
end

local function additionalXpMultiplier(perk, group, flags)
    local multiplier = 1
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

local function itemXpMultiplier(item)
    return pointXpMultiplier(item.perk, item.level)
        * (item.additionalMultiplier or 1)
        * configXpMultiplier(item.perk)
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
    local result = color
    local good = getCore():getGoodHighlitedColor()
    local bad = getCore():getBadHighlitedColor()
    if flags and flags.fastLearner then
        result = mixColor(result, { r = good:getR(), g = good:getG(), b = good:getB() }, 0.2)
    end
    if flags and flags.slowLearner then
        result = mixColor(result, { r = bad:getR(), g = bad:getG(), b = bad:getB() }, 0.2)
    end
    if flags and flags.crafty then
        result = mixColor(result, { r = good:getR(), g = good:getG(), b = good:getB() }, 0.2)
    end
    if flags and flags.reluctantFighter then
        result = mixColor(result, { r = bad:getR(), g = bad:getG(), b = bad:getB() }, 0.2)
    end
    return result
end

local function otherSkillsMultiplierColor(item)
    local baseMultiplier = pointXpMultiplier(item.perk, item.level)
    return traitTintedColor(
        effectiveMultiplierColor(baseMultiplier, itemXpMultiplier(item)),
        item.traitColorFlags)
end

local function skillPercentage(level)
    level = clampXpLevel(level)
    if level == 0 then return "+ 0%" end
    if level == 1 then return "+ 75%" end
    if level == 2 then return "+ 100%" end
    return "+ 125%"
end

local function skillItem(perk, level, group, flags, extraLevel, reducedLevel, displayName)
    local skillName = displayName or PerkFactory.getPerkName(perk)
    local data = {
        perk = perk,
        level = level,
        skillName = skillName,
        skillLevel = clampXpLevel(level + (extraLevel or 0) - (reducedLevel or 0)),
        showSkillLevel = displayName == nil,
        otherSkills = displayName ~= nil,
        additionalMultiplier = additionalXpMultiplier(perk, group, flags),
        traitColorFlags = traitColorFlags(perk, group, flags),
        percentage = skillPercentage(level),
        extraLevel = extraLevel,
        reducedLevel = reducedLevel,
    }
    return skillName, data
end

local function drawSkillLabel(self, y, item, dy, hc)
    local data = item.item
    if qolEnabled("ShowSkillLevels_Enabled") and data.showSkillLevel ~= false and data.skillName and data.skillLevel ~= nil then
        self:drawText(data.skillName, UI_BORDER_SPACING, y + dy, hc:getR(), hc:getG(), hc:getB(), 1, UIFont.Small)
        local x = UI_BORDER_SPACING + getTextManager():MeasureStringX(UIFont.Small, data.skillName)
        local separator = " - "
        x = x - 2
        self:drawText(separator, x, y + dy, SKILL_LEVEL_SEPARATOR_COLOR.r, SKILL_LEVEL_SEPARATOR_COLOR.g, SKILL_LEVEL_SEPARATOR_COLOR.b, 1, UIFont.Small)
        x = x + getTextManager():MeasureStringX(UIFont.Small, separator)
        self:drawText(tostring(data.skillLevel), x, y + dy, SKILL_LEVEL_COLOR.r, SKILL_LEVEL_COLOR.g, SKILL_LEVEL_COLOR.b, 1, UIFont.Small)
        return
    end
    if data.otherSkillsVariant then
        local color = data.otherSkillsVariant == "Weapons"
            and getCore():getBadHighlitedColor()
            or getCore():getGoodHighlitedColor()
        self:drawText(item.text, UI_BORDER_SPACING, y + dy,
            color:getR(), color:getG(), color:getB(), 1, UIFont.Small)
        return
    end
    self:drawText(item.text, UI_BORDER_SPACING, y + dy, hc:getR(), hc:getG(), hc:getB(), 1, UIFont.Small)
end

local nativeDrawXpBoostMap = CharacterCreationProfession.drawXpBoostMap
CharacterCreationProfession.drawXpBoostMap = function(self, y, item, alt)
    local data = item.item
    local extraLevel = data and data.extraLevel
    local showMultiplier = qolEnabled("ShowXPMultiplier_Enabled")
    local showLevels = qolEnabled("ShowSkillLevels_Enabled")
    if data == nil then
        return nativeDrawXpBoostMap(self, y, item, alt)
    end

    if showMultiplier or showLevels then
        local vanillaLevel = data.level or 0
        local dy = (self.itemheight - self.fontHgt) / 2
        local hc = getCore():getGoodHighlitedColor()
        local blitH = getTextManager():getFontHeight(UIFont.Small)
        local blitW = math.floor(blitH / (10/3))
        local blitGap = math.floor(blitW / 4)
        local blitText = showMultiplier and "x1.00" or "+ 100%"
        local blitXOffset = getTextManager():MeasureStringX(UIFont.Small, blitText) + SCROLL_BAR_WIDTH
        local greenBlitsX = self.width - (blitXOffset + 12 * (blitW + blitGap))

        drawSkillLabel(self, y, item, dy, hc)
        for i = 1, vanillaLevel do
            self:drawTextureScaled(CharacterCreationProfession.instance.whiteBar,
                greenBlitsX + (i * (blitW + blitGap)), y + dy, blitW, blitH, 1,
                hc:getR(), hc:getG(), hc:getB())
        end
        drawExtraBars(self, y, vanillaLevel, extraLevel or 0, data.reducedLevel or 0)
        if showMultiplier or not isPhysicalPerk(data.perk) then
            local text = data.percentage
            local textR, textG, textB = hc:getR(), hc:getG(), hc:getB()
            if showMultiplier then
                text = string.format("x%.2f", itemXpMultiplier(data))
                local textColor = data.otherSkills
                    and otherSkillsMultiplierColor(data)
                    or traitTintedColor(xpMultiplierColor(data.level), data.traitColorFlags)
                textR, textG, textB = textColor.r, textColor.g, textColor.b
            end
            local right = self.width - UI_BORDER_SPACING - SCROLL_BAR_WIDTH
            self:drawTextRight(text, right, y + dy, textR, textG, textB, 1, UIFont.Small)
        end
        local yy = y + self.itemheight
        self:drawRectBorder(0, y, self:getWidth(), yy - y, 0.5, self.borderColor.r, self.borderColor.g, self.borderColor.b)
        return yy
    end

    if extraLevel == nil then
        return nativeDrawXpBoostMap(self, y, item, alt)
    end

    local vanillaLevel = data.level or 0
    if vanillaLevel > 0 then
        local result = nativeDrawXpBoostMap(self, y, item, alt)
        drawExtraBars(self, y, vanillaLevel, extraLevel, data.reducedLevel)
        return result
    end

    local dy = (self.itemheight - self.fontHgt) / 2
    local hc = getCore():getGoodHighlitedColor()
    drawSkillLabel(self, y, item, dy, hc)
    drawExtraBars(self, y, 0, extraLevel, data.reducedLevel)
    local yy = y + self.itemheight
    self:drawRectBorder(0, y, self:getWidth(), yy - y, 0.5, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    return yy
end

local function collectXpBoostLevels(self)
    local xpLevels = {}
    for _, selectedItem in pairs(self.listboxTraitSelected and self.listboxTraitSelected.items or {}) do
        addXpBoosts(xpLevels, selectedItem.item:getXpBoosts())
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

    local label, skill = skillItem(
        entry.perk, level, entry.group, state.traitFlags, extraLevel, reducedLevel)
    if skill.skillLevel > 0 or (skill.skillLevel == 0 and qolEnabled("ShowSkillLevels_Enabled")) then
        return "added", label, skill
    end
    return "other"
end

local function addConfiguredSkills(state)
    for _, entry in ipairs(state.standardPerks) do
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
    for _, entry in ipairs(state.standardPerks) do
        if not state.addedPerks[entry.perk] then
            local level = clampXpLevel(state.xpLevels[entry.perk] or 0)
            if level > 0 then
                local label, skill = skillItem(entry.perk, level, entry.group, state.traitFlags)
                state.listbox:addItem(label, skill)
            else
                markOtherSkill(state.skillGroups, entry)
            end
        end
    end
end

local function addOtherSkillsGroup(state, entry, groupConfig)
    if not entry then return end
    local label, skill = skillItem(
        entry.perk, 0, groupConfig.group, groupConfig.flags, nil, nil, getText(groupConfig.textKey))
    skill.otherSkillsOrder = groupConfig.order
    skill.otherSkillsVariant = groupConfig.variant
    state.listbox:addItem(label, skill)
end

local function addCraftSkills(state)
    if not state.skillGroups.hasCraftSkills or not state.traitFlags[CharacterTrait.CRAFTY] then return end
    addOtherSkillsGroup(state, standardEntry("Woodwork"), {
        textKey = "Sandbox_CharacterCreationCustomizer_OtherSkillsCraft",
        group = "Crafting",
        flags = { [CharacterTrait.CRAFTY] = true },
        order = 1,
        variant = "Craft",
    })
end

local function addWeaponSkills(state)
    if not state.skillGroups.hasWeaponSkills or not state.traitFlags[CharacterTrait.PACIFIST] then return end
    addOtherSkillsGroup(state, standardEntry("Aiming"), {
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
    addOtherSkillsGroup(state, standardEntry("Maintenance") or state.standardPerks[1], {
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

CharacterCreationProfession.checkXPBoost = function(self)
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
CharacterCreationProfession.create = function(self)
    M.apply()
    local result = nativeCreate(self)
    if self.listboxXpBoost then
        self:checkXPBoost()
    end
    return result
end

local nativeSetVisible = CharacterCreationProfession.setVisible
local function refreshProfessionList(self)
    if not self.listboxProf then return end

    M.debug("Refreshing profession list")
    local selectedProfessionKey = self.profession and M.professionKey(self.profession)
    self:populateProfessionList(self.listboxProf)
    if not selectedProfessionKey then return end

    for index, professionEntry in ipairs(self.listboxProf.items or {}) do
        if M.professionKey(professionEntry.item) == selectedProfessionKey then
            self.listboxProf.selected = index
            self.profession = professionEntry.item
            return
        end
    end
end

local function reconcileLiveConfiguration(self)
    refreshProfessionList(self)
    freeSources(self)
    local previousGrants = self.characterCreationCustomizerAppliedGrantedTraits
    local previousProfession = self.profession
    local previousKey = self.characterCreationCustomizerAppliedGrantedProfessionKey
    if not previousGrants and previousProfession then previousGrants = M.professionGrantedTraits(previousProfession) end

    removeGrantedProfessionTraits(self, previousGrants, previousKey or (previousProfession and M.professionKey(previousProfession)))
    self.characterCreationCustomizerAppliedGrantedTraits = nil
    self.characterCreationCustomizerAppliedGrantedProfessionKey = nil
    refreshSelectedTraitDefinitions(self)
    removeDisabledSelectedTraits(self)

    local fallback = M.fallbackProfession()
    if self.profession and not M.professionEnabled(self.profession)
        and self.profession ~= fallback and fallback then
        self:onSelectProf(fallback)
        return
    end

    if self.profession then
        local grants = M.professionGrantedTraits(self.profession)
        addGrantedProfessionTraits(self, self.profession, grants)
        self.characterCreationCustomizerAppliedGrantedTraits = grants
        self.characterCreationCustomizerAppliedGrantedProfessionKey = M.professionKey(self.profession)
        self.cost = M.professionCost(self.profession)
    end

    removeUnbuyableSelectedTraits(self)
    recalculatePointToSpend(self)
    self:repopulateTraitLists()
    self:checkXPBoost()
end

local function customizerConfigSignature()
    local values = { M.configurationSignature() }

    local professions = CharacterProfessionDefinition.getProfessions()
    for i = 0, professions:size() - 1 do
        local profession = professions:get(i)
        values[#values + 1] = "profession:" .. M.professionKey(profession) .. ":"
            .. tostring(M.professionEnabled(profession)) .. ":"
            .. tostring(M.professionCost(profession))
    end

    for _, entry in ipairs(M.getStandardPerks()) do
        values[#values + 1] = "standard:" .. entry.key .. ":" .. tostring(M.standardValue(entry))
    end

    values[#values + 1] = "qol:levels:" .. tostring(M.optionValue("QOL", "ShowSkillLevels_Enabled"))
    values[#values + 1] = "qol:multiplier:" .. tostring(M.optionValue("QOL", "ShowXPMultiplier_Enabled"))
    values[#values + 1] = "qol:professionPoints:" .. tostring(M.optionValue("QOL", "ShowProfessionPoints_Enabled"))

    table.sort(values)
    return table.concat(values, "|")
end

CharacterCreationProfession.setVisible = function(self, visible, joypadData)
    if visible then
        M.apply()
        if self.listboxTrait and self.listboxBadTrait and self.listboxTraitSelected then
            reconcileLiveConfiguration(self)
        else
            refreshProfessionList(self)
        end
        self.characterCreationCustomizerConfigSignature = customizerConfigSignature()
    end
    local result = nativeSetVisible(self, visible, joypadData)
    if visible and self.listboxXpBoost then
        self:checkXPBoost()
    end
    return result
end

local nativeUpdate = CharacterCreationProfession.update

CharacterCreationProfession.update = function(self)
    local result = nativeUpdate(self)
    if self.listboxTrait and self.listboxBadTrait and self.listboxTraitSelected then
        local signature = customizerConfigSignature()
        if signature ~= self.characterCreationCustomizerConfigSignature then
            self.characterCreationCustomizerConfigSignature = signature
            M.apply()
            reconcileLiveConfiguration(self)
        end
    end
    return result
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
    if section == "QOL" then return "QOL" end
    if section == "Standard" then
        local entry = standardEntry(key)
        return entry and entry.group
    end
    if section == "Professions" then return "Professions" end
    if section == "NonBuyableTraits" then return "NonBuyableTraits" end
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
    if group == "QOL" then
        return getText("Sandbox_Title_QOL")
    end
    if group == "PositiveTraits" or group == "NegativeTraits" or group == "NonBuyableTraits" or group == "Professions" then
        return getText("Sandbox_Title_" .. group)
    end
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
        local professions = {}
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
        for rank, profession in ipairs(professions) do
            professionRanks[M.professionKey(profession)] = rank
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
    for _, setting in ipairs(page.settings) do
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

local function settingsOrder(page)
    local order = {}
    for index, setting in ipairs(page.settings) do
        order[index] = setting
    end
    return order
end

local function settingsOrderChanged(settings, previousOrder)
    for index, setting in ipairs(settings) do
        if previousOrder[index] ~= setting then return true end
    end
    return false
end

local function updateSettingValue(changed, setting, property, value)
    if setting[property] == value then return changed end
    setting[property] = value
    return true
end

local function updateSettingMetadata(setting, previousGroup, previousKey)
    local group = settingGroup(setting)
    local section, key, part = settingParts(setting)
    local changed = false
    local tooltipKey = tooltipKeyFor(section, key, part)
    if tooltipKey then
        changed = updateSettingValue(changed, setting, "tooltip", composeTooltip(setting, getText(tooltipKey)))
    end

    local title = settingTitles[setting.name]
        or (group and group ~= previousGroup and group or nil)
    local subtitle = isSubtitleSetting(section, key, part) and key ~= previousKey and settingLabel(setting) or nil
    local standardTitle = section == "Standard" and title or nil
    local standardLabel = section == "Standard" and part == "InitialLevel" and settingLabel(setting) or nil

    if section == "Standard" or section == "Professions" then
        changed = updateSettingValue(changed, setting, "title", nil)
        if section == "Standard" then
            changed = updateSettingValue(changed, setting, "translatedName", standardLabel)
            subtitle = nil
        end
    else
        changed = updateSettingValue(changed, setting, "title", title)
    end
    changed = updateSettingValue(changed, setting, "standardTitle", standardTitle)
    changed = updateSettingValue(changed, setting, "subtitle", subtitle)

    return changed, group or previousGroup, key or previousKey
end

local function addTitles(page)
    if not page or not page.settings then return false end
    M.rememberTraits()

    if not hasCustomizerSettings(page) then return false end

    local oldOrder = settingsOrder(page)
    table.sort(page.settings, compareSettings)
    local changed = settingsOrderChanged(page.settings, oldOrder)

    local previousGroup
    local previousKey
    for _, setting in ipairs(page.settings) do
        local settingChanged
        settingChanged, previousGroup, previousKey = updateSettingMetadata(setting, previousGroup, previousKey)
        changed = settingChanged or changed
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
    for _, setting in ipairs(page.settings) do
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
    for _, child in pairs(panel:getChildren()) do
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

local function seedPanelSettings(page, states)
    if not page or not page.settings then return end
    local options = getSandboxOptions and getSandboxOptions()
    for _, setting in ipairs(page.settings) do
        local state = states[setting.name]
        if state then
            if state.text ~= nil then
                setting.text = state.text
            elseif state.selected ~= nil then
                setting.default = state.selected
            end
        elseif options then
            local option = options:getOptionByName(setting.name)
            if option then
                local optionType = option:getType()
                if optionType == "integer" or optionType == "double" then
                    setting.text = option:getValueAsString()
                elseif optionType == "string" or optionType == "text" then
                    setting.text = option:getValue()
                elseif optionType == "boolean" then
                    setting.default = option:getValue()
                end
            end
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

local function addCenteredLabel(panel, height, text, font, y)
    local label = ISLabel:new(0, 0, height, text, 1, 1, 1, 1, font)
    panel:addChild(label)
    label:setX((panel:getWidth() - label:getWidth()) / 2)
    label:setY(y)
    return label
end

local function addStandardTitles(panel, page)
    if not panel or not page or not page.settings or not panel.labels then return end

    local titleHeight = getTextManager():getFontFromEnum(UIFont.Large):getLineHeight() + 6
    local addedHeight = 0

    for _, setting in ipairs(page.settings) do
        if setting.standardTitle then
            local row = panel.labels[setting.name]
            if row then
                local y = row:getY()
                local amount = titleHeight + 22
                shiftPanelChildren(panel, y, amount)

                addCenteredLabel(panel, titleHeight, titleText(setting.standardTitle), UIFont.Large, y + 20)
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

    for _, setting in ipairs(page.settings) do
        local section, key, part = settingParts(setting)
        if key and isSubtitleSetting(section, key, part) and setting.subtitle then
            local row = panel.labels[setting.name]
            if row then
                local y = row:getY()
                local amount = subtitleHeight + subtitleSpacing
                shiftPanelChildren(panel, y, amount)

                addCenteredLabel(panel, subtitleHeight, setting.subtitle, UIFont.Medium, y)
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
local hostPanelHooked = false

local function withValidCustomizerIntegers(owner, category, options, callback)
    local restored = {}
    local controls = owner and owner.controls
    controls = category and controls and controls[category] or controls
    if controls and options then
        for i = 1, options:getNumOptions() do
            local option = options:getOptionByIndex(i - 1)
            local control = option and controls[option:getName()]
            if option and control and option:getType() == "integer"
                and option:getName():match("^CharacterCreationCustomizer%.") then
                local text = control.getText and control:getText()
                if text ~= nil and (text == "" or text == "-" or not option:isValidString(text)) then
                    restored[#restored + 1] = { control = control, text = text }
                    control:setText(option:getValueAsString())
                end
            end
        end
    end

    local ok, result = pcall(callback)
    for _, state in ipairs(restored) do
        state.control:setText(state.text)
    end
    if not ok then error(result) end
    return result
end

local function decorateSandboxPanel(panel, page)
    syncPanelTooltips(panel, page)
    addStandardTitles(panel, page)
    addSandboxSubtitles(panel, page)
    return panel
end

local function installSandboxPanelHook()
    if sandboxPanelHooked or not SandboxOptionsScreen then return end
    local original = SandboxOptionsScreen.createPanel
    if not original then return end

    local originalSettingsFromUI = SandboxOptionsScreen.settingsFromUI
    if originalSettingsFromUI then
        SandboxOptionsScreen.settingsFromUI = function(self, options)
            return withValidCustomizerIntegers(self, nil, options, function()
                return originalSettingsFromUI(self, options)
            end)
        end
    end

    SandboxOptionsScreen.createPanel = function(self, page)
        seedPanelSettings(page, {})
        addTitles(page)
        return decorateSandboxPanel(original(self, page), page)
    end

    sandboxPanelHooked = true
end

local function installHostPanelHook()
    if hostPanelHooked then return end
    local screen = ServerSettingsScreen and ServerSettingsScreen.instance
    local pageEdit = screen and screen.pageEdit
    if not pageEdit then return end
    local original = pageEdit.createPanel
    if not original then return end

    local originalSettingsFromUI = pageEdit.settingsFromUIAux
    if originalSettingsFromUI then
        pageEdit.settingsFromUIAux = function(self, category, options)
            return withValidCustomizerIntegers(self, category, options, function()
                return originalSettingsFromUI(self, category, options)
            end)
        end
    end

    pageEdit.createPanel = function(self, category, page)
        seedPanelSettings(page, {})
        addTitles(page)
        return decorateSandboxPanel(original(self, category, page), page)
    end

    hostPanelHooked = true
end

local function rebuildSettingsPanels(owner, listbox, createPanel)
    for _, item in ipairs(listbox.items) do
        local itemData = item.item
        local page = itemData and itemData.page
        local changed = addTitles(page)
        if changed or (hasCustomizerSettings(page) and itemData and itemData.panel and not itemData.panel.subtitles) then
            local oldPanel = itemData.panel
            local wasCurrent = owner.currentPanel == oldPanel
            local controlStates = saveControlStates(oldPanel)
            seedPanelSettings(page, controlStates)
            clearPanelTooltips(oldPanel)
            if wasCurrent then
                owner:removeChild(oldPanel)
            end

            itemData.panel = createPanel(page)
            replaceOwnerControls(owner, itemData.panel)
            restoreControlStates(itemData.panel, controlStates)
            if wasCurrent then
                owner:addChild(itemData.panel)
                owner.currentPanel = itemData.panel
                owner:onPanelChange()
            end
        end
    end
end

local function rebuildSandboxOptionsPage()
    local screen = SandboxOptionsScreen and SandboxOptionsScreen.instance
    if not screen or not screen.listbox then return end

    rebuildSettingsPanels(screen, screen.listbox, function(page)
        return screen:createPanel(page)
    end)
end

local function rebuildHostSettingsPage()
    local screen = ServerSettingsScreen and ServerSettingsScreen.instance
    local pageEdit = screen and screen.pageEdit
    if not pageEdit or not pageEdit.listbox then return end
    installHostPanelHook()

    rebuildSettingsPanels(pageEdit, pageEdit.listbox, function(page)
        return pageEdit:createPanel({ name = "Sandbox" }, page)
    end)
end

local function initialize()
    M.apply()
    installSandboxPanelHook()
    installHostPanelHook()
    rebuildSandboxOptionsPage()
    rebuildHostSettingsPage()
end

installSandboxPanelHook()
installHostPanelHook()
Events.OnMainMenuEnter.Add(initialize)
Events.OnInitWorld.Add(function()
    M.apply()
end)

if isClient() then
    Events.OnNewGame.Add(function(player)
        sendClientCommand(player, "CharacterCreationCustomizer", "ApplyInitialLevels", {})
    end)
end
