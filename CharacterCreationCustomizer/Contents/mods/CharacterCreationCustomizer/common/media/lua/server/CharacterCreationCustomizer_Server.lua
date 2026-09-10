if isClient() then return end

local M = require "CharacterCreationCustomizer_Shared"

local function playerFromEvent(playerIndex, playerObject)
    if playerObject then return playerObject end
    return getSpecificPlayer(playerIndex)
end

local function professionDefinition(playerObject)
    local descriptor = playerObject:getDescriptor()
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

local function traitDefinition(traitType)
    local definition = CharacterTraitDefinition.getCharacterTraitDefinition(traitType)
    if definition == nil then error("Missing trait definition: " .. tostring(traitType)) end
    return definition
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
    appendList(target, grants)
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
    local currentTraits = {}
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
    local invalid = {}
    local knownTraits = traits:getKnownTraits()
    for i = 0, knownTraits:size() - 1 do
        local traitType = knownTraits:get(i)
        if not allowedTraits[traitKey(traitType)] then
            local definition = traitDefinition(traitType)
            if not M.traitEnabled(definition) then
                invalid[#invalid + 1] = traitType
            end
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
    local removedTraits = {}
    appendProfessionGrants(removedTraits, oldProfession)
    appendProfessionGrants(removedTraits, currentProfession)
    removeTraits(traits, removedTraits)
    for index = 1, #currentGrants do traits:add(currentGrants[index]) end
end

local function reconcileProfession(playerObject)
    local descriptor = playerObject:getDescriptor()

    local traits = playerObject:getCharacterTraits()
    local oldTraits = {}
    appendTraits(oldTraits, traits:getKnownTraits())
    local oldProfession = professionDefinition(playerObject)
    local current = oldProfession
    local fallback = M.fallbackProfession()
    if not fallback then error("No profession is available for character creation") end
    if not current then
        descriptor:setCharacterProfession(fallback:getType())
        current = fallback
    elseif not M.professionEnabled(current) and current ~= fallback then
        descriptor:setCharacterProfession(fallback:getType())
        current = fallback
    end

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
    local profession = professionDefinition(playerObject)
    if not profession then error("Player has no profession") end
    local inventory = playerObject:getInventory()
    local professionKey = M.professionKey(profession)
    local itemTypes = M.parseGrantedItems(M.professionValue(profession, "GrantedItems"), profession)
    for index = 1, #itemTypes do
        local itemType = itemTypes[index]
        local addedItem = inventory:AddItem(itemType)
        if not addedItem then
            error("Failed to add item " .. itemType .. " for profession " .. professionKey)
        end
    end
end

local function applyInitialLevels(playerObject, modData)
    local xp
    local standardPerks = M.getStandardPerks()
    for index = 1, #standardPerks do
        local entry = standardPerks[index]
        local levelChange = M.standardValue(entry)
        if levelChange ~= 0 then
            local currentLevel = playerObject:getPerkLevel(entry.perk)
            local targetLevel = math.floor(math.max(0, math.min(10, currentLevel + levelChange)))
            if targetLevel ~= currentLevel then
                playerObject:setPerkLevelDebug(entry.perk, targetLevel)
                xp = xp or playerObject:getXp()
                xp:setXPToLevel(entry.perk, targetLevel)
            end
        end
    end

    markInitialLevelsApplied(playerObject, modData)
end

local function applyToPlayer(playerIndex, playerObject)
    M.apply()
    local player = playerFromEvent(playerIndex, playerObject)
    if not player then return end
    local modData = player:getModData()
    if modData.CharacterCreationCustomizerInitialLevels then return end
    if player:getHoursSurvived() > 0 then
        markInitialLevelsApplied(player, modData)
        return
    end
    reconcileProfession(player)
    grantProfessionItems(player)
    applyInitialLevels(player, modData)
end

Events.OnInitGlobalModData.Add(function()
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
