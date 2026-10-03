local ACR = {}

ACR.ID = "AdminCharacterRestore"
ACR.DATA_VERSION = 3

local SNAPSHOT_INTERVAL_OPTION = "AdminCharacterRestore.SnapshotIntervalHours"
local MAX_SNAPSHOTS_OPTION = "AdminCharacterRestore.MaxSnapshotsPerPlayer"
local DEFAULT_SNAPSHOT_INTERVAL_HOURS = 2
local DEFAULT_MAX_SNAPSHOTS = 5
local MIN_SNAPSHOT_INTERVAL_HOURS = 1
local MAX_SNAPSHOT_INTERVAL_HOURS = 24
local MIN_SNAPSHOT_LIMIT = 1
local MAX_SNAPSHOT_LIMIT = 5
local print = print

local function isResourceIdentifier(resourceName)
    if resourceName == "" then return false end
    local separator = resourceName:find(":", 1, true)
    return separator ~= 1 and separator ~= #resourceName
end

local function readSandboxOption(optionName)
    if type(getSandboxOptions) ~= "function" then return nil end
    local options = getSandboxOptions()
    local option = options and options:getOptionByName(optionName)
    return option and option:getValue() or nil
end

local function clampInteger(rawValue, minimum, maximum, fallbackValue)
    local numericValue = tonumber(rawValue)
    if not numericValue or numericValue ~= numericValue then numericValue = fallbackValue end
    local clampedValue = math.max(minimum, math.min(maximum, numericValue))
    return math.floor(clampedValue)
end

function ACR.getSnapshotIntervalHours()
    return clampInteger(
        readSandboxOption(SNAPSHOT_INTERVAL_OPTION), MIN_SNAPSHOT_INTERVAL_HOURS, MAX_SNAPSHOT_INTERVAL_HOURS,
        DEFAULT_SNAPSHOT_INTERVAL_HOURS
    )
end

function ACR.getMaxSnapshotsPerPlayer()
    return clampInteger(
        readSandboxOption(MAX_SNAPSHOTS_OPTION), MIN_SNAPSHOT_LIMIT, MAX_SNAPSHOT_LIMIT, DEFAULT_MAX_SNAPSHOTS
    )
end

function ACR.isDebugEnabled()
    local sandboxVars = SandboxVars
    local settings = sandboxVars and sandboxVars.AdminCharacterRestore
    return settings ~= nil and settings.Debug == true
end

function ACR.isAdmin(player)
    if not player then return false end
    if player:getAccessLevel() == "admin" then return true end
    local role = player:getRole()
    return role and role:getName() == "admin"
end

function ACR.debug(...)
    if not ACR.isDebugEnabled() then return end
    print("[AdminCharacterRestore][Debug]", ...)
end

function ACR.nowMs()
    if type(getTimestampMs) == "function" then
        return math.floor(getTimestampMs())
    end
    if type(getTimestamp) == "function" then return math.floor(getTimestamp() * 1000) end
    return math.floor(os.time() * 1000)
end

function ACR.worldHours()
    return getGameTime():getWorldAgeHours()
end

function ACR.worldDays()
    return ACR.worldHours() / 24
end

function ACR.resourceKey(resource)
    if resource == nil then return nil end
    local resourceName = tostring(resource)
    if not isResourceIdentifier(resourceName) then return resourceName end
    return tostring(ResourceLocation.of(resourceName))
end

function ACR.copyStringArray(values)
    local copy = {}
    if type(values) ~= "table" then return copy end

    for index = 1, #values do
        local stringValue = values[index]
        if type(stringValue) == "string" and stringValue ~= "" then
            copy[#copy + 1] = stringValue
        end
    end
    return copy
end

function ACR.copyPageMap(pages)
    local copy = {}
    if type(pages) ~= "table" then return copy end

    for fullType, pagesRead in pairs(pages) do
        if type(fullType) == "string" then
            local pageCount = tonumber(pagesRead)
            if pageCount and pageCount > 0 then copy[fullType] = pageCount end
        end
    end
    return copy
end

function ACR.copyPerks(perks)
    local copy = {}
    if type(perks) ~= "table" then return copy end

    for perkName, savedPerk in pairs(perks) do
        if type(perkName) == "string" and type(savedPerk) == "table" then
            copy[perkName] = { level = tonumber(savedPerk.level), xp = tonumber(savedPerk.xp) }
        end
    end
    return copy
end

function ACR.copyRestorePayload(snapshot)
    if type(snapshot) ~= "table" then return nil end

    return {
        id = tostring(snapshot.id or ""),
        profession = type(snapshot.profession) == "string" and ACR.resourceKey(snapshot.profession) or nil,
        perks = ACR.copyPerks(snapshot.perks),
        traits = ACR.copyStringArray(snapshot.traits),
        recipes = ACR.copyStringArray(snapshot.recipes),
        readPages = ACR.copyPageMap(snapshot.readPages),
        alreadyReadBooks = ACR.copyStringArray(snapshot.alreadyReadBooks),
        readPrintMedia = ACR.copyStringArray(snapshot.readPrintMedia),
        knownMediaLines = ACR.copyStringArray(snapshot.knownMediaLines),
        zombieKills = tonumber(snapshot.zombieKills),
        hoursSurvived = tonumber(snapshot.hoursSurvived),
        weight = tonumber(snapshot.weight)
    }
end

local function resolvePerk(perkName)
    if type(perkName) ~= "string" or not Perks or not Perks.FromString then return nil end
    local perk = Perks.FromString(perkName)
    if not perk or perk == Perks.None or perk == Perks.MAX then return nil end
    return perk
end

local function setPerkLevel(player, perk, targetLevel)
    for _ = 1, 12 do
        local currentLevel = player:getPerkLevel(perk)
        if currentLevel == targetLevel then return end
        if currentLevel < targetLevel then
            player:LevelPerk(perk)
        else
            player:LoseLevel(perk)
        end
    end
end

local function strengthXPModifier(nutrition)
    local proteins = nutrition:getProteins()
    if proteins > 50 and proteins < 300 then return 1.5 end
    if proteins < -300 then return 0.7 end
    return 1
end

local function restorePerkXP(player, xp, perk, targetXP)
    local nutrition = player:getNutrition()
    local modifier = perk == Perks.Strength and strengthXPModifier(nutrition) or 1
    for _ = 1, 2 do
        local amount = targetXP - xp:getXP(perk)
        if amount == 0 then return end
        if perk == Perks.Fitness and not nutrition:canAddFitnessXp() then
            setPerkLevel(player, perk, 0)
        end
        xp:AddXP(perk, amount / modifier, false, false, true, false)
    end
end

local function applySavedPerk(player, xp, perk, savedPerk)
    local targetLevel = math.max(
        0, math.min(10, math.floor(tonumber(savedPerk.level) or player:getPerkLevel(perk))))
    local targetXP = tonumber(savedPerk.xp)
    if targetXP then
        restorePerkXP(player, xp, perk, targetXP)
    else
        xp:setXPToLevel(perk, targetLevel)
    end
    setPerkLevel(player, perk, targetLevel)
    if perk == Perks.Fitness then
        player:getStats():set(CharacterStat.FITNESS, targetLevel / 5 - 1)
    end
end

function ACR.applyPerks(player, perks)
    local wasAsleep = player:isAsleep()
    if wasAsleep then player:setAsleep(false) end
    local xp
    for perkName, savedPerk in pairs(perks or {}) do
        if type(savedPerk) == "table" then
            local perk = resolvePerk(perkName)
            if perk then
                xp = xp or player:getXp()
                applySavedPerk(player, xp, perk, savedPerk)
            end
        end
    end
    if wasAsleep then player:setAsleep(true) end
end

function ACR.applyProfession(player, professionName)
    if type(professionName) ~= "string" or not isResourceIdentifier(professionName) then return end
    local location = ResourceLocation.of(professionName)
    local profession = CharacterProfession.get(location)
    local definition = profession and CharacterProfessionDefinition.getCharacterProfessionDefinition(profession)
    if not definition then return end
    local descriptor = player:getDescriptor()
    descriptor:setCharacterProfession(definition:getType())
    descriptor:setProfessionSkills(definition)
    local knownTraits = player:getCharacterTraits():getKnownTraits()
    for index = 0, knownTraits:size() - 1 do
        player:modifyTraitXPBoost(knownTraits:get(index), false)
    end
end

local function resolveTrait(traitName)
    if type(traitName) ~= "string" or not isResourceIdentifier(traitName) then return nil end
    return CharacterTrait.get(ResourceLocation.of(traitName))
end

local function currentTraitKey(trait)
    local definition = CharacterTraitDefinition.getCharacterTraitDefinition(trait)
    return definition and tostring(definition:getType()) or nil
end

local function removeUnwantedTraits(player, characterTraits, wanted)
    local knownTraits = characterTraits:getKnownTraits()
    for index = knownTraits:size() - 1, 0, -1 do
        local trait = knownTraits:get(index)
        if not wanted[currentTraitKey(trait)] then
            characterTraits:remove(trait)
            player:modifyTraitXPBoost(trait, true)
        end
    end
end

local function addWantedTraits(player, characterTraits, traits)
    for index = 1, #(traits or {}) do
        local traitName = traits[index]
        local trait = resolveTrait(traitName)
        if trait and not player:hasTrait(trait) then
            characterTraits:add(trait)
            player:modifyTraitXPBoost(trait, false)
        end
    end
end

function ACR.applyTraits(player, traits)
    local wanted = {}
    for index = 1, #(traits or {}) do
        local traitName = traits[index]
        local traitKey = ACR.resourceKey(traitName)
        if traitKey then wanted[traitKey] = true end
    end
    local characterTraits = player:getCharacterTraits()
    removeUnwantedTraits(player, characterTraits, wanted)
    addWantedTraits(player, characterTraits, traits)
end

function ACR.applyRecipes(player, recipes)
    local knownRecipes = player:getKnownRecipes()
    for index = 1, #(recipes or {}) do
        local recipe = recipes[index]
        if type(recipe) == "string" and not knownRecipes:contains(recipe) then
            local learned = player:learnRecipe(recipe)
            if not learned then knownRecipes:add(recipe) end
        end
    end
end

local function applyReadPages(player, savedReadPages)
    local mergedReadPages = {}
    for fullType, pagesRead in pairs(savedReadPages or {}) do
        if type(fullType) == "string" then
            local savedPages = tonumber(pagesRead)
            local currentPages = player:getAlreadyReadPages(fullType)
            if savedPages and savedPages > 0 then
                mergedReadPages[fullType] = math.max(currentPages, savedPages)
                if mergedReadPages[fullType] > currentPages then
                    player:setAlreadyReadPages(fullType, mergedReadPages[fullType])
                end
            end
        end
    end
    return mergedReadPages
end

local function applyReadBooks(player, books)
    local alreadyReadBooks = player:getAlreadyReadBook()
    for index = 1, #(books or {}) do
        local book = books[index]
        if not alreadyReadBooks:contains(book) then alreadyReadBooks:add(book) end
    end
end

local function applyReadPrintMedia(player, printMedia)
    for index = 1, #(printMedia or {}) do
        local media = printMedia[index]
        player:addReadPrintMedia(media)
    end
end

local function applyKnownMediaLines(player, mediaLines)
    for index = 1, #(mediaLines or {}) do
        local lineID = mediaLines[index]
        if not player:isKnownMediaLine(lineID) then player:addKnownMediaLine(lineID) end
    end
end

function ACR.applyReadState(player, snapshot)
    local readPages = applyReadPages(player, snapshot.readPages)
    applyReadBooks(player, snapshot.alreadyReadBooks)
    applyReadPrintMedia(player, snapshot.readPrintMedia)
    applyKnownMediaLines(player, snapshot.knownMediaLines)
    return readPages
end

function ACR.applyBasicStats(player, snapshot)
    if snapshot.zombieKills then player:setZombieKills(snapshot.zombieKills) end
    if snapshot.hoursSurvived then player:setHoursSurvived(snapshot.hoursSurvived) end
    if snapshot.weight then player:getNutrition():setWeight(snapshot.weight) end
end

function ACR.applyRestoreState(player, snapshot)
    if not player or type(snapshot) ~= "table" then return {} end
    ACR.applyProfession(player, snapshot.profession)
    ACR.applyTraits(player, snapshot.traits)
    ACR.applyPerks(player, snapshot.perks)
    ACR.applyRecipes(player, snapshot.recipes)
    local readPages = ACR.applyReadState(player, snapshot)
    ACR.applyBasicStats(player, snapshot)
    return readPages
end

return ACR
