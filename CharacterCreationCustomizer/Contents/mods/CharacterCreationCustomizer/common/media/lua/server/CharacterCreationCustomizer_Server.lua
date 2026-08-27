if isClient() then return end

local M = CharacterCreationCustomizer

local function playerFromEvent(playerIndex, playerObject)
    if playerObject and playerObject.getPerkLevel then
        return playerObject
    end
    if getSpecificPlayer then
        return getSpecificPlayer(playerIndex)
    end
end

local function professionDefinition(playerObject)
    local descriptor = playerObject and playerObject:getDescriptor()
    local professionType = descriptor and descriptor:getCharacterProfession()
    return professionType and CharacterProfessionDefinition.getCharacterProfessionDefinition(professionType)
end

local function removeTraits(traits, values)
    for _, trait in ipairs(values) do
        traits:remove(trait)
    end
end

local function traitDefinition(traitType)
    return CharacterTraitDefinition
        and CharacterTraitDefinition.getCharacterTraitDefinition(traitType)
end

local function traitKey(traitType)
    local definition = traitDefinition(traitType)
    return definition and M.definitionKey(definition) or tostring(traitType)
end

local function appendTraits(target, traits)
    for i = 0, traits:size() - 1 do
        target[#target + 1] = traits:get(i)
    end
end

local function appendOriginalGrants(target, profession)
    local grants = M.originalProfessionGrants[M.professionKey(profession)] or {}
    for _, grant in ipairs(grants) do
        target[#target + 1] = grant
    end
end

local function appendProfessionGrants(target, profession)
    if not profession then return end
    appendTraits(target, profession:getGrantedTraits())
    appendOriginalGrants(target, profession)
    for _, grant in ipairs(M.professionGrantedTraits(profession)) do
        target[#target + 1] = grant
    end
end

local function appendGrantedRecipes(target, definition)
    local recipes = definition and definition:getGrantedRecipes()
    if not recipes then return end
    for i = 0, recipes:size() - 1 do
        target[recipes:get(i)] = true
    end
end

local function reconcileRecipes(playerObject, oldProfession, oldTraits, currentProfession)
    local knownRecipes = playerObject:getKnownRecipes()
    local oldRecipes = {}
    appendGrantedRecipes(oldRecipes, oldProfession)
    for _, traitType in ipairs(oldTraits) do
        appendGrantedRecipes(oldRecipes, traitDefinition(traitType))
    end

    for i = knownRecipes:size() - 1, 0, -1 do
        local recipe = knownRecipes:get(i)
        if oldRecipes[recipe] then
            knownRecipes:remove(recipe)
        end
    end

    local currentRecipes = {}
    appendGrantedRecipes(currentRecipes, currentProfession)
    local currentTraits = playerObject:getCharacterTraits():getKnownTraits()
    for i = 0, currentTraits:size() - 1 do
        appendGrantedRecipes(currentRecipes, traitDefinition(currentTraits:get(i)))
    end

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
            if definition and not M.traitEnabled(definition) then
                invalid[#invalid + 1] = traitType
            end
        end
    end
    removeTraits(traits, invalid)
end

local function allowedTraitKeys(grantedTraits)
    local allowedTraits = {}
    for _, traitType in ipairs(grantedTraits) do
        allowedTraits[traitKey(traitType)] = true
    end
    return allowedTraits
end

local function replaceProfessionTraits(traits, oldProfession, currentProfession, currentGrants)
    local removedTraits = {}
    appendProfessionGrants(removedTraits, oldProfession)
    appendProfessionGrants(removedTraits, currentProfession)
    removeTraits(traits, removedTraits)
    for _, grant in ipairs(currentGrants) do
        traits:add(grant)
    end
end

local function reconcileProfession(playerObject)
    local descriptor = playerObject and playerObject:getDescriptor()
    if not descriptor then return end

    local traits = playerObject:getCharacterTraits()
    local oldTraits = {}
    appendTraits(oldTraits, traits:getKnownTraits())
    local oldProfession = professionDefinition(playerObject)
    local current = oldProfession
    local fallback = M.fallbackProfession()
    if not current then
        if fallback then
            descriptor:setCharacterProfession(fallback:getType())
            current = fallback
        else
            return
        end
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
    if playerObject.transmitModData then
        playerObject:transmitModData()
    end
end

local function grantProfessionItems(playerObject)
    local profession = professionDefinition(playerObject)
    if not profession then return end
    local inventory = playerObject:getInventory()
    for _, itemType in ipairs(M.parseGrantedItems(M.professionValue(profession, "GrantedItems"), profession)) do
        inventory:AddItem(itemType)
    end
end

local function applyInitialLevels(playerObject, modData)
    for _, entry in ipairs(M.getStandardPerks()) do
        local levelChange = M.standardValue(entry)
        if levelChange ~= 0 then
            local currentLevel = playerObject:getPerkLevel(entry.perk)
            local targetLevel = math.max(0, math.min(10, currentLevel + levelChange))
            if targetLevel ~= currentLevel then
                playerObject:setPerkLevelDebug(entry.perk, targetLevel)
                playerObject:getXp():setXPToLevel(entry.perk, targetLevel)
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
    if player.getHoursSurvived and player:getHoursSurvived() > 0 then
        markInitialLevelsApplied(player, modData)
        return
    end
    reconcileProfession(player)
    grantProfessionItems(player)
    applyInitialLevels(player, modData)
end

if Events.OnInitGlobalModData then
    Events.OnInitGlobalModData.Add(function()
        M.apply()
    end)
end

Events.OnCreatePlayer.Add(applyToPlayer)
Events.OnNewGame.Add(function(playerObject)
    applyToPlayer(nil, playerObject)
end)

if Events.OnClientCommand then
    Events.OnClientCommand.Add(function(module, command, playerObject)
        if module == "CharacterCreationCustomizer" and command == "ApplyInitialLevels" then
            applyToPlayer(nil, playerObject)
        end
    end)
end
