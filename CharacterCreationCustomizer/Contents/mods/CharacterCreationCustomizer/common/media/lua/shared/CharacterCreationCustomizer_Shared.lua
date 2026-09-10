local existingCustomizer = rawget(_G, "CharacterCreationCustomizer")
if existingCustomizer then return existingCustomizer end

local M = {}
rawset(_G, "CharacterCreationCustomizer", M)
local DEBUG_OPTION_NAME = "CharacterCreationCustomizer.Debug"
local PROFESSION_OPTION_SUFFIXES = { "Disable", "Cost", "GrantedTraits", "GrantedItems" }
local standardPerks
local configurationFingerprintTable
local configurationFingerprintKeys = {}
local configurationFingerprintKeySet = {}
local configurationFingerprintValues = {}
local configurationFingerprintKeyCount
local configurationFingerprintValue

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
M.originalProfessionDefinitions = {}
M.originalProfessionGrants = {}

function M.isDebugEnabled()
    local option = getSandboxOptions():getOptionByName(DEBUG_OPTION_NAME)
    return option:asConfigOption():getValueAsObject() == true
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

local function optionalOptionMissing(options, section, key)
    if section == "NonBuyableTraits" then
        local base = key:match("^(.+)_Buyable$")
        local suffix = "Buyable"
        if not base then
            base = key:match("^(.+)_Cost$")
            suffix = "Cost"
        end
        if not base then return false end
        local counterpart = suffix == "Buyable" and "Cost" or "Buyable"
        return not options:getOptionByName("CharacterCreationCustomizer." .. section .. "_"
            .. base .. "_" .. counterpart)
    end
    if section == "Traits" then
        local base = key:match("^(.+)_Disable$")
        local suffix = "Disable"
        if not base then
            base = key:match("^(.+)_Cost$")
            suffix = "Cost"
        end
        if not base then return false end
        local counterpart = suffix == "Disable" and "Cost" or "Disable"
        return not options:getOptionByName("CharacterCreationCustomizer." .. section .. "_"
            .. base .. "_" .. counterpart)
    end
    if section == "Professions" then
        local base = key:match("^(.+)_Disable$")
            or key:match("^(.+)_Cost$")
            or key:match("^(.+)_GrantedTraits$")
            or key:match("^(.+)_GrantedItems$")
        if not base then return false end
        for index = 1, #PROFESSION_OPTION_SUFFIXES do
            local suffix = PROFESSION_OPTION_SUFFIXES[index]
            if options:getOptionByName("CharacterCreationCustomizer." .. section .. "_"
                .. base .. "_" .. suffix) then
                return false
            end
        end
        return true
    end
    return false
end

function M.optionValue(section, key)
    local optionKey = section .. "_" .. key
    local optionName = "CharacterCreationCustomizer." .. optionKey
    local sandbox = SandboxVars and SandboxVars.CharacterCreationCustomizer
    if sandbox and sandbox[optionKey] ~= nil then
        return sandbox[optionKey]
    end

    local options = getSandboxOptions()
    local option = options:getOptionByName(optionName)
    if not option then
        if optionalOptionMissing(options, section, key) then return end
        error("Missing sandbox option: " .. optionName)
    end
    return option:asConfigOption():getValueAsObject()
end

local function refreshConfigurationFingerprintKeys(sandbox)
    local keyCount = 0
    local changed = sandbox ~= configurationFingerprintTable
    for _ in pairs(sandbox) do
        keyCount = keyCount + 1
    end

    if not changed and keyCount == configurationFingerprintKeyCount then
        for key in pairs(sandbox) do
            if not configurationFingerprintKeySet[key] then
                changed = true
                break
            end
        end
    end
    if not changed and keyCount == configurationFingerprintKeyCount then return end

    configurationFingerprintTable = sandbox
    configurationFingerprintKeys = {}
    configurationFingerprintKeySet = {}
    configurationFingerprintValues = {}
    configurationFingerprintKeyCount = keyCount
    configurationFingerprintValue = nil
    for key in pairs(sandbox) do
        configurationFingerprintKeys[#configurationFingerprintKeys + 1] = key
        configurationFingerprintKeySet[key] = true
        configurationFingerprintValues[key] = sandbox[key]
    end
    table.sort(configurationFingerprintKeys)
end

function M.configurationFingerprint()
    local sandbox = SandboxVars and SandboxVars.CharacterCreationCustomizer
    if not sandbox then return end

    refreshConfigurationFingerprintKeys(sandbox)

    local changed = configurationFingerprintValue == nil
    for index = 1, #configurationFingerprintKeys do
        local key = configurationFingerprintKeys[index]
        local value = sandbox[key]
        if configurationFingerprintValues[key] ~= value then
            configurationFingerprintValues[key] = value
            changed = true
        end
    end
    if not changed then return configurationFingerprintValue end

    local values = {}
    for index = 1, #configurationFingerprintKeys do
        local key = configurationFingerprintKeys[index]
        values[index] = tostring(key) .. ":" .. tostring(configurationFingerprintValues[key])
    end
    configurationFingerprintValue = table.concat(values, "|")
    return configurationFingerprintValue
end

function M.rememberTraits()
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
    local professions = CharacterProfessionDefinition.getProfessions()
    for i = 0, professions:size() - 1 do
        local profession = professions:get(i)
        local key = M.professionKey(profession)
        M.originalProfessionDefinitions[key] = M.originalProfessionDefinitions[key] or profession
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
    local key = M.definitionKey(definition)
    local original = M.originalTraitDefinitions[key]
    if not original then error("Missing original trait definition: " .. key) end
    return original
end

function M.traitGroup(definition)
    local original = M.originalTrait(definition)
    if original:isFree() then
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
    local original = M.originalTrait(definition)
    if configuredCost == nil then return original:getCost() end
    local cost = tonumber(configuredCost)
    if cost == nil then error("Invalid trait cost for " .. M.definitionKey(original)) end
    return cost
end

local function preserveTranslatedText(translatedText)
    return (tostring(translatedText):gsub("%%", "%%%%"))
end

local function listValues(values)
    local result = {}
    for i = 0, values:size() - 1 do
        result[#result + 1] = values:get(i)
    end
    return result
end

local function forEachListToken(value, callback)
    if value == nil then return end
    for rawToken in (tostring(value) .. ","):gmatch("(.-),") do
        local token = rawToken:gsub("^%s+", ""):gsub("%s+$", "")
        if token ~= "" then callback(token) end
    end
end

local function xpBoostValues(definition)
    local result = {}
    for perk, level in pairs(transformIntoKahluaTable(definition:getXpBoosts())) do
        result[perk] = level:intValue()
    end
    return result
end

local function copyTraitDefinition(definition)
    return {
        type = definition:getType(),
        name = preserveTranslatedText(definition:getUIName()),
        description = definition:getDescription(),
        disabledInMultiplayer = definition:isDisabledInMultiplayer(),
        grantedTraits = listValues(definition:getGrantedTraits()),
        grantedRecipes = listValues(definition:getGrantedRecipes()),
        mutuallyExclusiveTraits = listValues(definition:getMutuallyExclusiveTraits()),
        xpBoosts = xpBoostValues(definition),
    }
end

local function applyDefinitionSnapshot(replacement, snapshot)
    if snapshot.description ~= nil then replacement:setDescription(snapshot.description) end
    for index = 1, #snapshot.grantedTraits do replacement:addGrantedTrait(snapshot.grantedTraits[index]) end
    for index = 1, #snapshot.grantedRecipes do replacement:addGrantedRecipe(snapshot.grantedRecipes[index]) end
    for index = 1, #(snapshot.mutuallyExclusiveTraits or {}) do
        replacement:addMutuallyExclusive(snapshot.mutuallyExclusiveTraits[index])
    end
    for perk, level in pairs(snapshot.xpBoosts) do replacement:addXPBoost(perk, level) end
end

local function applyTraitSnapshot(snapshot, cost, isFree)
    local description = snapshot.description or ""
    local replacement = CharacterTraitDefinition.addCharacterTraitDefinition(
        snapshot.type,
        snapshot.name,
        cost,
        preserveTranslatedText(description),
        isFree,
        snapshot.disabledInMultiplayer
    )
    applyDefinitionSnapshot(replacement, snapshot)
end

function M.applyTraitCosts()
    M.rememberTraits()
    for _, definition in pairs(M.originalTraitDefinitions) do
        if M.traitGroup(definition) then
            local cost = M.traitCost(definition)
            local current = CharacterTraitDefinition.getCharacterTraitDefinition(definition:getType())
            local isFree = definition:isFree() and not M.traitBuyable(definition)
            if not current then error("Missing current trait definition: " .. M.definitionKey(definition)) end
            if current:getCost() ~= cost or current:isFree() ~= isFree then
                applyTraitSnapshot(copyTraitDefinition(definition), cost, isFree)
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
    if definition ~= nil then return definition end
    local compactShortKey = shortKey:gsub("[_%-]", "")
    for candidateKey, candidate in pairs(M.originalTraitDefinitionsByShortKey) do
        if tostring(candidateKey):gsub("[_%-]", "") == compactShortKey then
            return candidate
        end
    end

    local alias = M.englishTraitLabels[normalized]
    definition = alias and M.originalTraitDefinitionsByShortKey[alias]
    if definition ~= nil then return definition end

    for _, candidate in pairs(M.originalTraitDefinitions) do
        if M.normalizeLabel(candidate:getLabel()) == normalized then
            return candidate
        end
    end
end

function M.parseGrantedTraits(value, profession)
    local grantedTraits = {}
    local seen = {}
    forEachListToken(value, function(token)
        local definition = M.resolveTraitLabel(token)
        if definition then
            local key = M.definitionKey(definition)
            if not seen[key] then
                seen[key] = true
                grantedTraits[#grantedTraits + 1] = definition:getType()
            end
        else
            local professionKey = profession and M.professionKey(profession) or "unknown"
            error("Unknown trait '" .. token .. "' in profession " .. professionKey)
        end
    end)

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
        local originalGrants = M.originalProfessionGrants[professionKey]
        if not originalGrants then error("Missing original grants for profession " .. professionKey) end
        return originalGrants
    end
    if M.normalizeLabel(configured) == "" then return {} end
    local grants = M.parseGrantedTraits(configured, profession)
    if #grants == 0 then error("No valid granted traits for profession " .. professionKey) end
    return grants
end

function M.parseGrantedItems(value, profession)
    local grantedItems = {}
    forEachListToken(value, function(token)
        local itemDefinition = ScriptManager.instance:FindItem(token)
        if itemDefinition == nil then
            local professionKey = profession and M.professionKey(profession) or "unknown"
            error("Unknown item '" .. token .. "' in profession " .. professionKey)
        end
        grantedItems[#grantedItems + 1] = itemDefinition:getFullName()
    end)

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
    M.rememberProfessions()
    local configuredCost = M.professionValue(profession, "Cost")
    local professionKey = M.professionKey(profession)
    local original = M.originalProfessionDefinitions[professionKey]
    if not original then error("Missing original profession definition: " .. professionKey) end
    if configuredCost == nil then return original:getCost() end
    local cost = tonumber(configuredCost)
    if cost == nil then error("Invalid profession cost for " .. professionKey) end
    return cost
end

local function sameGrantTypes(current, desired)
    if current:size() ~= #desired then return false end
    for index = 1, #desired do
        if current:get(index - 1) ~= desired[index] then return false end
    end
    return true
end

local function copyProfessionDefinition(definition, grantedTraits, cost)
    return {
        type = definition:getType(),
        name = preserveTranslatedText(definition:getUIName()),
        description = definition:getDescription(),
        texture = definition:getTexture(),
        grantedTraits = grantedTraits,
        grantedRecipes = listValues(definition:getGrantedRecipes()),
        xpBoosts = xpBoostValues(definition),
        cost = cost,
    }
end

local function applyProfessionSnapshot(snapshot)
    local description = snapshot.description or ""
    local replacement = CharacterProfessionDefinition.addCharacterProfessionDefinition(
        snapshot.type,
        snapshot.name,
        snapshot.cost,
        preserveTranslatedText(description),
        snapshot.texture and snapshot.texture:getName()
    )
    applyDefinitionSnapshot(replacement, snapshot)
end

function M.applyProfessionTraits()
    M.rememberProfessions()
    local professions = CharacterProfessionDefinition.getProfessions()
    for i = 0, professions:size() - 1 do
        local profession = professions:get(i)
        local professionKey = M.professionKey(profession)
        local original = M.originalProfessionDefinitions[professionKey]
        if not original then error("Missing original profession definition: " .. professionKey) end
        local grants = M.professionGrantedTraits(profession)
        local desiredCost = M.professionCost(profession)
        if profession:getCost() ~= desiredCost
            or not sameGrantTypes(profession:getGrantedTraits(), grants) then
            applyProfessionSnapshot(copyProfessionDefinition(original, grants, desiredCost))
        end
    end
end

function M.getStandardPerks()
    if standardPerks ~= nil then return standardPerks end
    standardPerks = {}
    for index = 1, #M.standardPerkNames do
        local key = M.standardPerkNames[index]
        local perk = Perks[key]
        if not perk then error("Missing perk enum: " .. key) end
        local definition = PerkFactory.getPerk(perk)
        if not definition then error("Missing perk definition: " .. key) end
        local parent = definition:getParent()
        if parent == Perks.None then error("Missing perk group: " .. key) end
        standardPerks[#standardPerks + 1] = {
            key = key,
            perk = perk,
            group = tostring(parent:getName()),
            order = #standardPerks,
        }
    end

    return standardPerks
end

function M.standardValue(entry)
    local configuredLevel = M.optionValue("Standard", entry.key .. "_InitialLevel")
    local initialLevel = configuredLevel == nil and 0 or tonumber(configuredLevel)
    if initialLevel == nil then error("Invalid initial level for " .. entry.key) end
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

    local professions = CharacterProfessionDefinition.getProfessions()
    for i = 0, professions:size() - 1 do
        local profession = professions:get(i)
        M.professionGrantedTraits(profession)
        M.parseGrantedItems(M.professionValue(profession, "GrantedItems"), profession)
        values[#values + 1] = "profession:" .. M.professionKey(profession) .. ":"
            .. tostring(M.professionValue(profession, "GrantedTraits")) .. ":"
            .. tostring(M.professionCost(profession))
    end

    local standardPerkEntries = M.getStandardPerks()
    for index = 1, #standardPerkEntries do
        local entry = standardPerkEntries[index]
        if not entry then error("Missing standard perk entry: " .. tostring(index)) end
        values[#values + 1] = "standard:" .. entry.key .. ":" .. tostring(M.standardValue(entry))
    end

    table.sort(values)
    return table.concat(values, "|")
end

function M.apply()
    local fingerprint = M.configurationFingerprint()
    if fingerprint ~= nil
        and fingerprint == M.appliedConfigurationFingerprint
        and M.appliedSignature ~= nil then
        return
    end

    local signature = M.configurationSignature()
    if signature == M.appliedSignature then
        M.appliedConfigurationFingerprint = fingerprint
        return
    end

    M.debug("Applying configuration")
    M.applyTraitCosts()
    M.applyProfessionTraits()
    M.appliedSignature = signature
    M.appliedConfigurationFingerprint = fingerprint
    M.debug("Configuration applied")
end

return M
