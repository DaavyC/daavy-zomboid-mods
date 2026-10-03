if isClient() then return end

local M = require "ccc_shared"
local traitDefinition = M.traitDefinition

local function playerFromEvent(playerIndex, playerObject)
    if playerObject then return playerObject end
    return getSpecificPlayer(playerIndex)
end

local function professionDefinition(descriptor)
    local professionType = descriptor:getCharacterProfession()
    if not professionType then return end
    local profession = CharacterProfessionDefinition.getCharacterProfessionDefinition(professionType)
    if not profession then error("Missing profession definition: " .. tostring(professionType)) end
    return profession
end

local function removeTraits(traits, values)
    for index = 1, #values do
        traits:remove(values[index])
    end
end

local function appendList(target, values)
    for index = 1, #values do
        target[#target + 1] = values[index]
    end
end

local function traitKey(traitType)
    return M.definitionKey(traitDefinition(traitType))
end

local function appendTraits(target, traits)
    for i = 0, traits:size() - 1 do
        target[#target + 1] = traits:get(i)
    end
end

local function appendOriginalGrants(target, profession)
    local professionKey = M.professionKey(profession)
    local grants = M.originalProfessionGrants[professionKey]
    if not grants then error("Missing original grants for profession " .. professionKey) end
    for index = 1, #grants do
        local traitType = grants[index]
        if not M.traitBuyable(traitDefinition(traitType)) then
            target[#target + 1] = traitType
        end
    end
end

local function appendProfessionGrants(target, profession)
    if not profession then return end
    appendTraits(target, profession:getGrantedTraits())
    appendOriginalGrants(target, profession)
    appendList(target, M.professionGrantedTraits(profession))
end

local function appendGrantedRecipes(target, definition)
    if not definition then return end
    local recipes = definition:getGrantedRecipes()
    for i = 0, recipes:size() - 1 do
        target[recipes:get(i)] = true
    end
end

local function appendTraitRecipes(target, traitTypes)
    for index = 1, #traitTypes do
        appendGrantedRecipes(target, traitDefinition(traitTypes[index]))
    end
end

local function reconcileRecipes(playerObject, oldProfession, oldTraits, currentProfession)
    local knownRecipes = playerObject:getKnownRecipes()
    local oldRecipes = {}
    appendGrantedRecipes(oldRecipes, oldProfession)
    appendTraitRecipes(oldRecipes, oldTraits)

    for i = knownRecipes:size() - 1, 0, -1 do
        local recipe = knownRecipes:get(i)
        if oldRecipes[recipe] then
            knownRecipes:remove(recipe)
        end
    end

    local currentRecipes = {}
    appendGrantedRecipes(currentRecipes, currentProfession)
    local currentTraits = table.newarray()
    appendTraits(currentTraits, playerObject:getCharacterTraits():getKnownTraits())
    appendTraitRecipes(currentRecipes, currentTraits)

    for recipe in pairs(currentRecipes) do
        if not knownRecipes:contains(recipe) then
            knownRecipes:add(recipe)
        end
    end
end

local function removeDisabledTraits(playerObject, allowedTraits)
    local traits = playerObject:getCharacterTraits()
    local invalid = table.newarray()
    local knownTraits = traits:getKnownTraits()
    for i = 0, knownTraits:size() - 1 do
        local traitType = knownTraits:get(i)
        local definition = traitDefinition(traitType)
        if not allowedTraits[M.definitionKey(definition)] and not M.traitEnabled(definition) then
            invalid[#invalid + 1] = traitType
        end
    end
    removeTraits(traits, invalid)
end

local function allowedTraitKeys(grantedTraits)
    local allowedTraits = {}
    for index = 1, #grantedTraits do
        allowedTraits[traitKey(grantedTraits[index])] = true
    end
    return allowedTraits
end

local function replaceProfessionTraits(traits, oldProfession, currentProfession, currentGrants)
    local removedTraits = table.newarray()
    appendProfessionGrants(removedTraits, oldProfession)
    appendProfessionGrants(removedTraits, currentProfession)
    removeTraits(traits, removedTraits)
    for index = 1, #currentGrants do traits:add(currentGrants[index]) end
end

local function reconcileProfession(playerObject)
    local descriptor = playerObject:getDescriptor()

    local traits = playerObject:getCharacterTraits()
    local oldTraits = table.newarray()
    appendTraits(oldTraits, traits:getKnownTraits())
    local oldProfession = professionDefinition(descriptor)
    local current = oldProfession
    local fallback = M.fallbackProfession()
    if not fallback then error("No profession is available for character creation") end
    if not current or (not M.professionEnabled(current) and current ~= fallback) then
        descriptor:setCharacterProfession(fallback:getType())
        current = fallback
    end

    M.debugLog("Reconciling player profession", current)
    local currentGrants = M.professionGrantedTraits(current)
    removeDisabledTraits(playerObject, allowedTraitKeys(currentGrants))
    replaceProfessionTraits(traits, oldProfession, current, currentGrants)

    reconcileRecipes(playerObject, oldProfession, oldTraits, current)
end

local function markInitialLevelsApplied(playerObject, modData)
    modData.CharacterCreationCustomizerInitialLevels = true
    playerObject:transmitModData()
end

local function grantProfessionItems(playerObject)
    local profession = professionDefinition(playerObject:getDescriptor())
    if not profession then error("Player has no profession") end
    local inventory = playerObject:getInventory()
    local professionKey = M.professionKey(profession)
    local itemTypes = M.professionGrantedItems(profession)
    M.debugLog("Granting profession items", professionKey, #itemTypes)
    for index = 1, #itemTypes do
        local itemType = itemTypes[index]
        local addedItem = inventory:AddItem(itemType)
        if not addedItem then
            error("Failed to add item " .. itemType .. " for profession " .. professionKey)
        end
        M.debugLog("Granted profession item", professionKey, itemType)
    end
end

local function applyInitialLevels(playerObject)
    local xp
    local standardPerks = M.getStandardPerks()
    for index = 1, #standardPerks do
        local entry = standardPerks[index]
        local levelChange = M.standardValue(entry)
        if levelChange ~= 0 then
            local currentLevel = playerObject:getPerkLevel(entry.perk)
            local targetLevel = math.floor(M.clampSkillLevel(currentLevel + levelChange))
            if targetLevel ~= currentLevel then
                M.debugLog("Applying initial perk level", entry.key, currentLevel, targetLevel)
                playerObject:setPerkLevelDebug(entry.perk, targetLevel)
                xp = xp or playerObject:getXp()
                xp:setXPToLevel(entry.perk, targetLevel)
            end
        end
    end
end

local function applyToPlayer(playerIndex, playerObject)
    M.apply()
    local player = playerFromEvent(playerIndex, playerObject)
    if not player then
        M.debugLog("Skipping player setup because the player is unavailable", playerIndex)
        return
    end
    local modData = player:getModData()
    if modData.CharacterCreationCustomizerInitialLevels then
        M.debugLog("Skipping player setup because initial levels were already applied", playerIndex)
        return
    end
    if player:getHoursSurvived() > 0 then
        M.debugLog("Skipping character creation setup for an existing player", playerIndex)
        markInitialLevelsApplied(player, modData)
        return
    end
    M.debugLog("Applying character creation setup to player", playerIndex)
    reconcileProfession(player)
    grantProfessionItems(player)
    applyInitialLevels(player)
    markInitialLevelsApplied(player, modData)
    M.debugLog("Character creation setup applied to player", playerIndex)
end

Events.OnInitGlobalModData.Add(function()
    M.debugLog("Applying configuration during global mod data initialization")
    M.apply()
end)

Events.OnCreatePlayer.Add(applyToPlayer)
Events.OnNewGame.Add(function(playerObject)
    applyToPlayer(nil, playerObject)
end)

Events.OnClientCommand.Add(function(module, command, playerObject)
    if module == "CharacterCreationCustomizer" and command == "ApplyInitialLevels" then
        applyToPlayer(nil, playerObject)
    end
end)
