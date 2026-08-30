CharacterCreationCustomizer = CharacterCreationCustomizer or {}

local M = CharacterCreationCustomizer
local DEBUG_OPTION_NAME = "CharacterCreationCustomizer.Debug"

M.standardPerkNames = {
    "Aiming", "Reloading",
    "Axe", "LongBlade", "Blunt", "Maintenance", "SmallBlade", "SmallBlunt", "Spear",
    "Blacksmith", "Woodwork", "Carving", "Cooking", "Electricity", "Glassmaking",
    "FlintKnapping", "Masonry", "Mechanics", "Pottery", "Tailoring", "MetalWelding",
    "Farming", "Husbandry", "Butchering",
    "Fitness", "Lightfoot", "Nimble", "Sprinting", "Sneak", "Strength",
    "Doctor", "Fishing", "PlantScavenging", "Tracking", "Trapping",
}

M.englishTraitLabels = {
    ["adrenaline junkie"] = "adrenalinejunkie",
    ["agoraphobic"] = "agoraphobic",
    ["all thumbs"] = "allthumbs",
    ["angler"] = "fishing",
    ["artisan"] = "artisan",
    ["athletic"] = "athletic",
    ["ax-pert"] = "axeman",
    ["baseball player"] = "baseballplayer",
    ["blacksmith knowledge"] = "blacksmith2",
    ["brave"] = "brave",
    ["brawler"] = "brawler",
    ["burglar"] = "burglar",
    ["bushcrafter"] = "wildernessknowledge",
    ["cat's eyes"] = "nightvision",
    ["claustrophobic"] = "claustrophobic",
    ["clumsy"] = "clumsy",
    ["conspicuous"] = "conspicuous",
    ["cowardly"] = "cowardly",
    ["crafty"] = "crafty",
    ["deaf"] = "deaf",
    ["desensitized"] = "desensitized",
    ["dextrous"] = "dextrous",
    ["disorganized"] = "disorganized",
    ["eagle eyed"] = "eagleeyed",
    ["emaciated"] = "emaciated",
    ["fast healer"] = "fasthealer",
    ["fast learner"] = "fastlearner",
    ["fast metabolism"] = "weightloss",
    ["fast reader"] = "fastreader",
    ["fear of blood"] = "hemophobic",
    ["first aider"] = "firstaid",
    ["fit"] = "fit",
    ["former scout"] = "formerscout",
    ["gardener"] = "gardener",
    ["graceful"] = "graceful",
    ["gymnast"] = "gymnast",
    ["handy"] = "handy",
    ["hard of hearing"] = "hardofhearing",
    ["hearty appetite"] = "heartyappetite",
    ["herbalist"] = "herbalist_prof",
    ["high thirst"] = "highthirst",
    ["high weight"] = "overweight",
    ["hiker"] = "hiker",
    ["hunter"] = "hunter",
    ["illiterate"] = "illiterate",
    ["inconspicuous"] = "inconspicuous",
    ["inventive"] = "inventive_prof",
    ["iron gut"] = "irongut",
    ["keen cook"] = "cook2",
    ["keen hearing"] = "keenhearing",
    ["light eater"] = "lighteater",
    ["low thirst"] = "lowthirst",
    ["low weight"] = "underweight",
    ["marksman"] = "marksman",
    ["mason"] = "mason",
    ["night owl"] = "nightowl",
    ["nutritionist"] = "nutritionist2",
    ["organized"] = "organized",
    ["outdoorsy"] = "outdoorsman",
    ["out of shape"] = "outofshape",
    ["prone to illness"] = "pronetoillness",
    ["puny"] = "weak",
    ["reluctant fighter"] = "pacifist",
    ["resilient"] = "resilient",
    ["restless sleeper"] = "insomniac",
    ["runner"] = "jogger",
    ["sewer"] = "tailor",
    ["short of breath"] = "asthmatic",
    ["short sighted"] = "shortsighted",
    ["sleepyhead"] = "needsmoresleep",
    ["slow healer"] = "slowhealer",
    ["slow learner"] = "slowlearner",
    ["slow metabolism"] = "weightgain",
    ["slow reader"] = "slowreader",
    ["smoker"] = "smoker",
    ["speed demon"] = "speeddemon",
    ["stout"] = "stout",
    ["strong"] = "strong",
    ["sunday driver"] = "sundaydriver",
    ["target shooter"] = "target_shooter",
    ["thick-skinned"] = "thickskinned",
    ["thin-skinned"] = "thinskinned",
    ["tinkerer"] = "tinkerer",
    ["unfit"] = "unfit",
    ["vehicle knowledge"] = "mechanics2",
    ["very high weight"] = "obese",
    ["very low weight"] = "veryunderweight",
    ["wakeful"] = "needslesssleep",
    ["weak"] = "feeble",
    ["weak stomach"] = "weakstomach",
    ["whittler"] = "whittler",
}

M.originalTraitDefinitions = M.originalTraitDefinitions or {}
M.originalTraitDefinitionsByShortKey = M.originalTraitDefinitionsByShortKey or {}
M.originalProfessionGrants = M.originalProfessionGrants or {}
M.invalidGrantWarnings = M.invalidGrantWarnings or {}
M.invalidItemWarnings = M.invalidItemWarnings or {}

function M.isDebugEnabled()
    local options = getSandboxOptions and getSandboxOptions()
    local option = options and options:getOptionByName(DEBUG_OPTION_NAME)
    return option and option:getValue() == true
end

function M.debug(message)
    if M.isDebugEnabled() then
        print("[Character Creation Customizer] " .. tostring(message))
    end
end

function M.definitionKey(definition)
    local traitType = definition and definition:getType()
    local name = traitType and traitType:getName()
    return name and tostring(name) or tostring(traitType)
end

function M.shortKeyFor(definition)
    return M.definitionKey(definition):gsub("^.*:", ""):gsub("%s+", ""):lower()
end

function M.professionKey(definition)
    local professionType = definition and definition:getType()
    local name = professionType and professionType:getName()
    return name and tostring(name):gsub("^.*:", "") or tostring(professionType)
end

function M.optionValue(section, key)
    local optionKey = section .. "_" .. key
    local optionName = "CharacterCreationCustomizer." .. optionKey
    local sandbox = SandboxVars and SandboxVars.CharacterCreationCustomizer
    if sandbox and sandbox[optionKey] ~= nil then
        return sandbox[optionKey]
    end
    if SandboxVars and SandboxVars[optionName] ~= nil then
        return SandboxVars[optionName]
    end

    if getSandboxOptions then
        local option = getSandboxOptions():getOptionByName(optionName)
        if option then
            if option:getType() == "string" then
                return option:getValueAsString()
            end
            return option:getValue()
        end
    end

    return nil
end

function M.rememberTraits()
    if not CharacterTraitDefinition then return end
    local definitions = CharacterTraitDefinition.getTraits()
    for i = 0, definitions:size() - 1 do
        local definition = definitions:get(i)
        local key = M.definitionKey(definition)
        local shortKey = M.shortKeyFor(definition)
        M.originalTraitDefinitions[key] = M.originalTraitDefinitions[key] or definition
        M.originalTraitDefinitionsByShortKey[shortKey] = M.originalTraitDefinitionsByShortKey[shortKey] or definition
    end
end

function M.rememberProfessions()
    if not CharacterProfessionDefinition then return end
    local professions = CharacterProfessionDefinition.getProfessions()
    for i = 0, professions:size() - 1 do
        local profession = professions:get(i)
        local key = M.professionKey(profession)
        if not M.originalProfessionGrants[key] then
            local grants = {}
            local grantedTraits = profession:getGrantedTraits()
            for j = 0, grantedTraits:size() - 1 do
                grants[#grants + 1] = grantedTraits:get(j)
            end
            M.originalProfessionGrants[key] = grants
        end
    end
end

function M.originalTrait(definition)
    return M.originalTraitDefinitions[M.definitionKey(definition)] or definition
end

function M.traitGroup(definition)
    local original = M.originalTrait(definition)
    local isFree = original:isFree()
    if isFree then
        if not M.traitBuyable(original) then return "NonBuyableTraits" end
        return M.traitCost(original) < 0 and "NegativeTraits" or "PositiveTraits"
    end
    local cost = original:getCost()
    if cost > 0 then return "PositiveTraits" end
    if cost < 0 then return "NegativeTraits" end
end

function M.traitValue(definition, suffix)
    local original = M.originalTrait(definition)
    local section = original:isFree() and "NonBuyableTraits" or "Traits"
    return M.optionValue(section, M.shortKeyFor(original) .. "_" .. suffix)
end
local function isDisabled(value)
    return value == true or value == 1 or value == "true"
end

function M.traitEnabled(definition)
    if M.originalTrait(definition):isFree() then return true end
    local disabledValue = M.traitValue(definition, "Disable")
    return not isDisabled(disabledValue)
end

function M.traitBuyable(definition)
    local original = M.originalTrait(definition)
    if not original:isFree() then return true end
    return isDisabled(M.traitValue(original, "Buyable"))
end

function M.traitCost(definition)
    local configuredCost = M.traitValue(definition, "Cost")
    return tonumber(configuredCost) or M.originalTrait(definition):getCost()
end

local function copyGrantedTraits(source, target)
    local grantedTraits = source:getGrantedTraits()
    for i = 0, grantedTraits:size() - 1 do
        target:addGrantedTrait(grantedTraits:get(i))
    end
end

local function preserveTranslatedText(translatedText)
    return (tostring(translatedText):gsub("%%", "%%%%"))
end

local function copyGrantedRecipes(source, target)
    local grantedRecipes = source:getGrantedRecipes()
    for i = 0, grantedRecipes:size() - 1 do
        target:addGrantedRecipe(grantedRecipes:get(i))
    end
end

local function copyXpBoosts(source, target)
    local xpBoosts = source:getXpBoosts()
    if not xpBoosts then return end
    for perk, level in pairs(transformIntoKahluaTable(xpBoosts)) do
        target:addXPBoost(perk, level:intValue())
    end
end

local function copyTraitRestrictions(source, target)
    local mutuallyExclusiveTraits = source:getMutuallyExclusiveTraits()
    for i = 0, mutuallyExclusiveTraits:size() - 1 do
        target:addMutuallyExclusive(mutuallyExclusiveTraits:get(i))
    end
end

local function copyTexture(source, target)
    local texture = source:getTexture()
    if texture then target:setTexture(texture) end
end

local function replaceTraitDefinition(definition, cost, isFree)
    local replacement = CharacterTraitDefinition.addCharacterTraitDefinition(
        definition:getType(),
        preserveTranslatedText(definition:getUIName()),
        cost,
        nil,
        isFree,
        definition:isDisabledInMultiplayer()
    )
    replacement:setDescription(definition:getDescription())

    copyGrantedTraits(definition, replacement)
    copyGrantedRecipes(definition, replacement)
    copyTraitRestrictions(definition, replacement)
    copyXpBoosts(definition, replacement)
    copyTexture(definition, replacement)
end

function M.applyTraitCosts()
    M.rememberTraits()
    for _, definition in pairs(M.originalTraitDefinitions) do
        if M.traitGroup(definition) then
            local cost = M.traitCost(definition)
            local current = CharacterTraitDefinition.getCharacterTraitDefinition(definition:getType())
            local isFree = definition:isFree() and not M.traitBuyable(definition)
            if current and (current:getCost() ~= cost or current:isFree() ~= isFree) then
                local replacementSucceeded, replacementError = pcall(replaceTraitDefinition, definition, cost, isFree)
                if not replacementSucceeded then
                    print("[Character Creation Customizer] " .. tostring(replacementError))
                end
            end
        end
    end
end

function M.normalizeLabel(label)
    return tostring(label):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

function M.resolveTraitLabel(value)
    M.rememberTraits()
    local normalized = M.normalizeLabel(value)
    if normalized == "" then return end

    local stableKey = normalized:gsub("%s+", "")
    for key, candidate in pairs(M.originalTraitDefinitions) do
        if tostring(key):gsub("%s+", ""):lower() == stableKey then
            return candidate
        end
    end

    local shortKey = stableKey:gsub("^.*:", "")
    local definition = M.originalTraitDefinitionsByShortKey[shortKey]
    if definition then return definition end
    local compactShortKey = shortKey:gsub("[_%-]", "")
    for candidateKey, candidate in pairs(M.originalTraitDefinitionsByShortKey) do
        if tostring(candidateKey):gsub("[_%-]", "") == compactShortKey then
            return candidate
        end
    end

    local alias = M.englishTraitLabels[normalized]
    definition = alias and M.originalTraitDefinitionsByShortKey[alias]
    if definition then return definition end

    for _, candidate in pairs(M.originalTraitDefinitions) do
        if M.normalizeLabel(candidate:getLabel()) == normalized then
            return candidate
        end
    end
end

local function warnOnce(warnings, warningKey, message)
    if warnings[warningKey] then return end
    warnings[warningKey] = true
    print("[Character Creation Customizer] " .. message)
end

function M.parseGrantedTraits(value, profession)
    local grantedTraits = {}
    local seen = {}
    if value == nil then
        return grantedTraits
    end

    for rawToken in (tostring(value) .. ","):gmatch("(.-),") do
        local token = rawToken:gsub("^%s+", ""):gsub("%s+$", "")
        if token ~= "" then
            local definition = M.resolveTraitLabel(token)
            if definition then
                local key = M.definitionKey(definition)
                if not seen[key] then
                    seen[key] = true
                    grantedTraits[#grantedTraits + 1] = definition:getType()
                end
            else
                local professionKey = profession and M.professionKey(profession) or "unknown"
                local warningKey = professionKey .. ":" .. M.normalizeLabel(token)
                warnOnce(M.invalidGrantWarnings, warningKey,
                    "Unknown trait '" .. token .. "' in profession " .. professionKey)
            end
        end
    end

    return grantedTraits
end

function M.professionValue(profession, suffix)
    return M.optionValue("Professions", M.professionKey(profession) .. "_" .. suffix)
end

function M.professionGrantedTraits(profession)
    M.rememberProfessions()
    local professionKey = M.professionKey(profession)
    local configured = M.professionValue(profession, "GrantedTraits")
    if configured == nil then
        return M.originalProfessionGrants[professionKey] or {}
    end
    if M.normalizeLabel(configured) == "" then return {} end
    local grants = M.parseGrantedTraits(configured, profession)
    if #grants == 0 then
        local warningKey = professionKey .. ":<no-valid-grants>"
        if not M.invalidGrantWarnings[warningKey] then
            M.invalidGrantWarnings[warningKey] = true
            print("[Character Creation Customizer] No valid granted traits for profession " .. professionKey)
        end
        return M.originalProfessionGrants[professionKey] or {}
    end
    return grants
end

function M.parseGrantedItems(value, profession)
    local grantedItems = {}
    if value == nil then return grantedItems end

    for rawToken in (tostring(value) .. ","):gmatch("(.-),") do
        local token = rawToken:gsub("^%s+", ""):gsub("%s+$", "")
        if token ~= "" then
            local itemDefinition = ScriptManager.instance:FindItem(token)
            if itemDefinition then
                grantedItems[#grantedItems + 1] = itemDefinition:getFullName()
            else
                local professionKey = profession and M.professionKey(profession) or "unknown"
                local warningKey = professionKey .. ":" .. M.normalizeLabel(token)
                warnOnce(M.invalidItemWarnings, warningKey,
                    "Unknown item '" .. token .. "' in profession " .. professionKey)
            end
        end
    end

    return grantedItems
end

function M.professionEnabled(profession)
    if profession and profession:getType() == CharacterProfession.UNEMPLOYED then
        return true
    end
    local disabledValue = M.professionValue(profession, "Disable")
    return not isDisabled(disabledValue)
end

function M.professionCost(profession)
    local configuredCost = M.professionValue(profession, "Cost")
    return tonumber(configuredCost) or profession:getCost()
end

function M.applyProfessionTraits()
    if not CharacterProfessionDefinition then return end
    local professions = CharacterProfessionDefinition.getProfessions()
    for i = 0, professions:size() - 1 do
        local profession = professions:get(i)
        local grants = M.professionGrantedTraits(profession)
        local texture = profession:getTexture()
        local replacement = CharacterProfessionDefinition.addCharacterProfessionDefinition(
            profession:getType(),
            preserveTranslatedText(profession:getUIName()),
            profession:getCost(),
            nil,
            texture and texture:getName()
        )
        replacement:setDescription(profession:getDescription())
        for _, grant in ipairs(grants) do
            replacement:addGrantedTrait(grant)
        end
        copyGrantedRecipes(profession, replacement)
        copyXpBoosts(profession, replacement)

    end
end

function M.getStandardPerks()
    if M.standardPerks then return M.standardPerks end
    M.standardPerks = {}
    for _, key in ipairs(M.standardPerkNames) do
        local perk = Perks[key]
        local definition = perk and PerkFactory.getPerk(perk)
        if definition and definition:getParent() ~= Perks.None then
            M.standardPerks[#M.standardPerks + 1] = {
                key = key,
                perk = perk,
                group = tostring(definition:getParent():getName()),
                order = #M.standardPerks,
            }
        end
    end

    return M.standardPerks
end

function M.standardValue(entry)
    local initialLevel = tonumber(M.optionValue("Standard", entry.key .. "_InitialLevel")) or 0
    return math.max(-10, math.min(10, initialLevel))
end

function M.fallbackProfession()
    local unemployed
    local professions = CharacterProfessionDefinition.getProfessions()
    for i = 0, professions:size() - 1 do
        local profession = professions:get(i)
        if profession:getType() == CharacterProfession.UNEMPLOYED then
            unemployed = profession
        elseif M.professionEnabled(profession) then
            return profession
        end
    end
    return unemployed
end

function M.configurationSignature()
    M.rememberTraits()
    M.rememberProfessions()
    local values = {}
    for key, definition in pairs(M.originalTraitDefinitions) do
        values[#values + 1] = "trait:" .. key .. ":"
            .. tostring(M.traitEnabled(definition)) .. ":"
            .. tostring(M.traitBuyable(definition)) .. ":"
            .. tostring(M.traitCost(definition))
    end

    if CharacterProfessionDefinition then
        local professions = CharacterProfessionDefinition.getProfessions()
        for i = 0, professions:size() - 1 do
            local profession = professions:get(i)
            values[#values + 1] = "profession:" .. M.professionKey(profession) .. ":"
                .. tostring(M.professionValue(profession, "GrantedTraits"))
        end
    end

    table.sort(values)
    return table.concat(values, "|")
end

function M.apply()
    local signatureOk, signature = pcall(M.configurationSignature)
    if not signatureOk then
        print("[Character Creation Customizer] " .. tostring(signature))
        return
    end
    if signature == M.appliedSignature then return end

    M.debug("Applying configuration")
    local applicationSucceeded, applicationError = pcall(function()
        M.applyTraitCosts()
        M.applyProfessionTraits()
    end)
    if applicationSucceeded then
        M.appliedSignature = signature
        M.debug("Configuration applied")
    else
        print("[Character Creation Customizer] " .. tostring(applicationError))
    end
end
