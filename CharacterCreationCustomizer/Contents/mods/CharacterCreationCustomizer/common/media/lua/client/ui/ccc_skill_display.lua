local M = require "ccc_shared"
local core = getCore()
local textManager = getTextManager()
local clampXpLevel = M.clampSkillLevel
local isEnabled = M.isEnabled

local indexStandardPerks
local qolEnabled

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
local SKILL_PERCENTAGES = {
    [0] = "+ 0%",
    [1] = "+ 75%",
    [2] = "+ 100%",
    [3] = "+ 125%",
}
local pacifistPerks
local OTHER_SKILL_GROUPS = table.newarray(
    { textKey = "Sandbox_CharacterCreationCustomizer_OtherSkillsCraft", variant = "Craft" },
    { textKey = "Sandbox_CharacterCreationCustomizer_OtherSkillsWeapons", variant = "Weapons" },
    { textKey = "Sandbox_CharacterCreationCustomizer_OtherSkills" }
)

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

local function xpBarLayout(listbox, multiplierText)
    local blitH = textManager:getFontHeight(UIFont.Small)
    local blitW = math.floor(blitH / (10/3))
    local blitGap = math.floor(blitW / 4)
    local blitXOffset = textManager:MeasureStringX(UIFont.Small, multiplierText) + SCROLL_BAR_WIDTH
    return {
        x = listbox.width - (blitXOffset + 12 * (blitW + blitGap)),
        height = blitH,
        width = blitW,
        step = blitW + blitGap,
    }
end

local function drawExtraBars(listbox, y, skillData, layout)
    local extraLevel = skillData.extraLevel or 0
    local reducedLevel = skillData.reducedLevel or 0
    if extraLevel == 0 and reducedLevel == 0 then return end
    local vanillaLevel = skillData.level or 0
    local barY = y + (listbox.itemheight - listbox.fontHgt) / 2
    local whiteBar = professionWhiteBar()
    layout = layout or xpBarLayout(listbox, qolEnabled("ShowXPMultiplier_Enabled") and "x1.00" or "+ 100%")
    for i = 1, extraLevel do
        local position = vanillaLevel + i
        listbox:drawTextureScaled(whiteBar,
            layout.x + position * layout.step, barY, layout.width, layout.height, 1,
            0.15, 0.55, 0.9)
    end

    for i = 1, reducedLevel do
        local position = vanillaLevel - reducedLevel + i
        listbox:drawTextureScaled(whiteBar,
            layout.x + position * layout.step, barY, layout.width, layout.height, 1,
            0.9, 0.2, 0.2)
    end
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
    local globalToggle = vanillaMultiplierValue("GlobalToggle", true)
    local key = isEnabled(globalToggle) and "Global" or perkKey(perk)
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

local function additionalXpMultiplier(effects)
    local multiplier = 1.0
    if effects.fastLearner then
        multiplier = multiplier * 1.3
    end
    if effects.slowLearner then
        multiplier = multiplier * 0.7
    end
    if effects.reluctantFighter then
        multiplier = multiplier * 0.75
    end
    if effects.crafty then
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
        local goodColor = core:getGoodHighlitedColor()
        good = { r = goodColor:getR(), g = goodColor:getG(), b = goodColor:getB() }
    end
    if flags and (flags.slowLearner or flags.reluctantFighter) then
        local badColor = core:getBadHighlitedColor()
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
    local effects = traitColorFlags(skillSpec.perk, skillSpec.group, skillSpec.flags)
    local skillData = {
        perk = skillSpec.perk,
        level = skillSpec.level,
        skillName = skillName,
        skillLevel = clampXpLevel(skillSpec.level + (skillSpec.extraLevel or 0) - (skillSpec.reducedLevel or 0)),
        showSkillLevel = displayName == nil,
        otherSkills = displayName ~= nil,
        additionalMultiplier = additionalXpMultiplier(effects),
        traitColorFlags = effects,
        percentage = skillPercentage(skillSpec.level),
        extraLevel = skillSpec.extraLevel,
        reducedLevel = skillSpec.reducedLevel,
    }
    return skillName, skillData
end

local function drawSkillLevelLabel(listbox, skillData, context)
    local hc = context.color
    listbox:drawText(skillData.skillName, UI_BORDER_SPACING, context.y, hc:getR(), hc:getG(), hc:getB(), 1, UIFont.Small)
    local x = UI_BORDER_SPACING + textManager:MeasureStringX(UIFont.Small, skillData.skillName) - 2
    local separator = " - "
    listbox:drawText(separator, x, context.y, SKILL_LEVEL_SEPARATOR_COLOR.r, SKILL_LEVEL_SEPARATOR_COLOR.g, SKILL_LEVEL_SEPARATOR_COLOR.b, 1, UIFont.Small)
    x = x + textManager:MeasureStringX(UIFont.Small, separator)
    listbox:drawText(tostring(skillData.skillLevel), x, context.y, SKILL_LEVEL_COLOR.r, SKILL_LEVEL_COLOR.g, SKILL_LEVEL_COLOR.b, 1, UIFont.Small)
end

local function drawSkillLabel(self, skillEntry, context)
    local skillData = skillEntry.item
    if qolEnabled("ShowSkillLevels_Enabled") and skillData.showSkillLevel ~= false and skillData.skillName and skillData.skillLevel ~= nil then
        drawSkillLevelLabel(self, skillData, context)
        return
    end
    if skillData.otherSkillsVariant then
        local color = skillData.otherSkillsVariant == "Weapons"
            and core:getBadHighlitedColor()
            or core:getGoodHighlitedColor()
        self:drawText(skillEntry.text, UI_BORDER_SPACING, context.y,
            color:getR(), color:getG(), color:getB(), 1, UIFont.Small)
        return
    end
    local hc = context.color
    self:drawText(skillEntry.text, UI_BORDER_SPACING, context.y, hc:getR(), hc:getG(), hc:getB(), 1, UIFont.Small)
end

local nativeDrawXpBoostMap
local function drawXpBoostBorder(listbox, y)
    local yy = y + listbox.itemheight
    listbox:drawRectBorder(0, y, listbox:getWidth(), yy - y, 0.5, listbox.borderColor.r, listbox.borderColor.g, listbox.borderColor.b)
    return yy
end

local function drawVanillaXpBars(listbox, vanillaLevel, context)
    if vanillaLevel == 0 then return end
    local whiteBar = professionWhiteBar()
    local layout = context.bars
    local hc = context.color
    for i = 1, vanillaLevel do
        listbox:drawTextureScaled(whiteBar,
            layout.x + i * layout.step, context.y, layout.width, layout.height, 1,
            hc:getR(), hc:getG(), hc:getB())
    end
end

local function drawXpMultiplier(listbox, skillData, context)
    if not context.showMultiplier and isPhysicalPerk(skillData.perk) then return end

    local text = skillData.percentage
    local hc = context.color
    local textR, textG, textB = hc:getR(), hc:getG(), hc:getB()
    if context.showMultiplier then
        text = string.format("x%.2f", itemXpMultiplier(skillData))
        local textColor = skillData.otherSkills
            and otherSkillsMultiplierColor(skillData)
            or traitTintedColor(xpMultiplierColor(skillData.level), skillData.traitColorFlags)
        textR, textG, textB = textColor.r, textColor.g, textColor.b
    end
    local right = listbox.width - UI_BORDER_SPACING - SCROLL_BAR_WIDTH
    listbox:drawTextRight(text, right, context.y, textR, textG, textB, 1, UIFont.Small)
end

local function drawVisibleXpBoost(listbox, y, skillEntry, context)
    local skillData = skillEntry.item
    local vanillaLevel = skillData.level or 0
    context.y = y + (listbox.itemheight - listbox.fontHgt) / 2
    context.color = core:getGoodHighlitedColor()
    context.bars = xpBarLayout(listbox, context.showMultiplier and "x1.00" or "+ 100%")
    drawSkillLabel(listbox, skillEntry, context)
    drawVanillaXpBars(listbox, vanillaLevel, context)
    drawExtraBars(listbox, y, skillData, context.bars)
    drawXpMultiplier(listbox, skillData, context)
    return drawXpBoostBorder(listbox, y)
end

local function drawAdditionalXpBoost(listbox, y, skillEntry, alt)
    local skillData = skillEntry.item
    local vanillaLevel = skillData.level or 0
    if vanillaLevel > 0 then
        local drawHeight = nativeDrawXpBoostMap(listbox, y, skillEntry, alt)
        drawExtraBars(listbox, y, skillData)
        return drawHeight
    end

    local context = {
        y = y + (listbox.itemheight - listbox.fontHgt) / 2,
        color = core:getGoodHighlitedColor(),
    }
    drawSkillLabel(listbox, skillEntry, context)
    drawExtraBars(listbox, y, skillData)
    return drawXpBoostBorder(listbox, y)
end

local function drawXpBoostMap(listbox, y, skillEntry, alt)
    local skillData = skillEntry.item
    if skillData == nil then return nativeDrawXpBoostMap(listbox, y, skillEntry, alt) end

    local showMultiplier = qolEnabled("ShowXPMultiplier_Enabled")
    local showLevels = qolEnabled("ShowSkillLevels_Enabled")
    if showMultiplier or showLevels then
        return drawVisibleXpBoost(listbox, y, skillEntry, { showMultiplier = showMultiplier })
    end
    if skillData.extraLevel == nil then return nativeDrawXpBoostMap(listbox, y, skillEntry, alt) end
    return drawAdditionalXpBoost(listbox, y, skillEntry, alt)
end

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

local function collectOtherSkill(state, entry)
    local groupIndex = 3
    if state.traitFlags[CharacterTrait.CRAFTY] and entry.group == "Crafting" then
        groupIndex = 1
    elseif state.traitFlags[CharacterTrait.PACIFIST] and isPacifistSkill(entry.perk) then
        groupIndex = 2
    end
    local entries = state.otherSkillEntries[groupIndex]
    entries[#entries + 1] = entry
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
    if skill.skillLevel > 0 or state.showLevels or state.showMultiplier then
        return "added", label, skill
    end
    return "other"
end

local function addConfiguredSkills(state)
    for index = 1, #state.standardPerks do
        local entry = state.standardPerks[index]
        local status, label, skill = configuredSkill(state, entry)
        if status then
            state.addedPerks[entry.perk] = true
            if status == "added" then
                state.listbox:addItem(label, skill)
            else
                collectOtherSkill(state, entry)
            end
        end
    end
end

local function addBaseSkill(state, entry, level)
    local label, skill = skillItem({
        perk = entry.perk,
        level = level,
        group = entry.group,
        flags = state.traitFlags,
    })
    state.listbox:addItem(label, skill)
end

local function addBaseSkills(state)
    for index = 1, #state.standardPerks do
        local entry = state.standardPerks[index]
        if not state.addedPerks[entry.perk] then
            local level = clampXpLevel(state.xpLevels[entry.perk] or 0)
            if level > 0 or (state.showMultiplier and (isPhysicalPerk(entry.perk) or entry.perk == Perks.Sprinting)) then
                addBaseSkill(state, entry, level)
            else
                collectOtherSkill(state, entry)
            end
        end
    end
end

local function addOtherSkillsGroup(state, entries, groupIndex)
    local entry = entries[1]
    local groupConfig = OTHER_SKILL_GROUPS[groupIndex]
    local label, skill = skillItem({
        perk = entry.perk,
        level = 0,
        group = entry.group,
        flags = state.traitFlags,
        displayName = getText(groupConfig.textKey),
    })
    skill.otherSkillsOrder = groupIndex
    skill.otherSkillsVariant = groupConfig.variant
    state.listbox:addItem(label, skill)
end

local function groupHasSingleMultiplier(entries)
    local multiplier = configXpMultiplier(entries[1].perk)
    for index = 2, #entries do
        if configXpMultiplier(entries[index].perk) ~= multiplier then return false end
    end
    return true
end

local function addOtherSkills(state)
    if not state.showLevels and not state.showMultiplier then return end
    for groupIndex = 1, #state.otherSkillEntries do
        local entries = state.otherSkillEntries[groupIndex]
        if #entries > 0 then
            if not state.showMultiplier or groupHasSingleMultiplier(entries) then
                addOtherSkillsGroup(state, entries, groupIndex)
            else
                for index = 1, #entries do
                    addBaseSkill(state, entries[index], 0)
                end
            end
        end
    end
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

local function checkXPBoost(self)
    self.listboxXpBoost:clear()
    local xpState = {
        listbox = self.listboxXpBoost,
        xpLevels = collectXpBoostLevels(self),
        standardPerks = M.getStandardPerks(),
        traitFlags = selectedTraitFlags(self),
        addedPerks = {},
        otherSkillEntries = table.newarray(table.newarray(), table.newarray(), table.newarray()),
        showLevels = qolEnabled("ShowSkillLevels_Enabled"),
        showMultiplier = qolEnabled("ShowXPMultiplier_Enabled"),
    }
    addConfiguredSkills(xpState)
    addBaseSkills(xpState)
    addOtherSkills(xpState)
    sortXpBoosts(xpState)
end

local function xpConfigSignature()
    if not qolEnabled("ShowXPMultiplier_Enabled") then return "" end
    local entries = M.getStandardPerks()
    local multipliers = table.newarray()
    for index = 1, #entries do
        multipliers[index] = tostring(configXpMultiplier(entries[index].perk))
    end
    return table.concat(multipliers, "|")
end

local function installSkillDisplay(lookupStandardPerkIndex, isQolEnabled)
    indexStandardPerks = lookupStandardPerkIndex
    qolEnabled = isQolEnabled
    nativeDrawXpBoostMap = CharacterCreationProfession.drawXpBoostMap
    CharacterCreationProfession.drawXpBoostMap = drawXpBoostMap
    CharacterCreationProfession.checkXPBoost = checkXPBoost
    return xpConfigSignature
end

return installSkillDisplay
