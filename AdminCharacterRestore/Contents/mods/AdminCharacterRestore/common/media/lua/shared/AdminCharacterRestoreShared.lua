AdminCharacterRestore = AdminCharacterRestore or {}

local ACR = AdminCharacterRestore

ACR.ID = "AdminCharacterRestore"
ACR.DATA_VERSION = 2

local SNAPSHOT_INTERVAL_OPTION = "AdminCharacterRestore.SnapshotIntervalHours"
local MAX_SNAPSHOTS_OPTION = "AdminCharacterRestore.MaxSnapshotsPerPlayer"
local DEBUG_OPTION = "AdminCharacterRestore.Debug"
local DEFAULT_SNAPSHOT_INTERVAL_HOURS = 2
local DEFAULT_MAX_SNAPSHOTS = 5
local MIN_SNAPSHOT_INTERVAL_HOURS = 1
local MAX_SNAPSHOT_INTERVAL_HOURS = 24
local MIN_SNAPSHOT_LIMIT = 1
local MAX_SNAPSHOT_LIMIT = 5

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
    return readSandboxOption(DEBUG_OPTION) == true
end

function ACR.debug(message)
    if ACR.isDebugEnabled() then print("[AdminCharacterRestore] debug=" .. tostring(message)) end
end

function ACR.nowMs()
    local ok, timestamp
    if type(getTimestampMs) == "function" then
        ok, timestamp = pcall(getTimestampMs)
    elseif type(getTimestamp) == "function" then
        ok, timestamp = pcall(getTimestamp)
        if ok and timestamp then timestamp = timestamp * 1000 end
    end

    if ok and tonumber(timestamp) then return math.floor(timestamp) end
    return math.floor(os.time() * 1000)
end

function ACR.worldHours()
    return getGameTime():getWorldAgeHours()
end

function ACR.worldDays()
    return ACR.worldHours() / 24
end

function ACR.resourceKey(resource)
    local ok, location = pcall(function () return ResourceLocation.of(resource) end)
    return ok and tostring(location) or tostring(resource)
end

function ACR.copyStringArray(values)
    local copy = {}
    if type(values) ~= "table" then return copy end

    for _, stringValue in ipairs(values) do
        if type(stringValue) == "string" and stringValue ~= "" then table.insert(copy, stringValue) end
    end
    return copy
end

function ACR.copyPageMap(pages)
    local copy = {}
    if type(pages) ~= "table" then return copy end

    for fullType, pagesRead in pairs(pages) do
        if type(fullType) == "string" then
            local number = tonumber(pagesRead)
            if number and number > 0 then copy[fullType] = number end
        end
    end
    return copy
end

function ACR.copyPerks(perks)
    local copy = {}
    if type(perks) ~= "table" then return copy end

    for perkName, saved in pairs(perks) do
        if type(perkName) == "string" and type(saved) == "table" then
            copy[perkName] = { level = tonumber(saved.level), xp = tonumber(saved.xp) }
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
    local ok, perk = pcall(function () return Perks.FromString(perkName) end)
    if not ok or not perk or perk == Perks.None or perk == Perks.MAX then return nil end
    return perk
end

local function normalizePerkLevel(player, perk, savedLevel)
    local targetLevel = math.max(0, math.min(10, math.floor(tonumber(savedLevel) or player:getPerkLevel(perk))))
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

function ACR.applyPerks(player, perks)
    for perkName, savedPerk in pairs(perks or {}) do
        if type(savedPerk) == "table" then
            local perk = resolvePerk(perkName)
            if perk then
                local targetLevel = math.max(
                    0, math.min(10, math.floor(tonumber(savedPerk.level) or player:getPerkLevel(perk)))
                )
                local targetXP = tonumber(savedPerk.xp)
                local xp = player:getXp()
                if targetXP then
                    xp:AddXP(perk, targetXP - xp:getXP(perk), false, false, true, false)
                else
                    xp:setXPToLevel(perk, targetLevel)
                end
                normalizePerkLevel(player, perk, targetLevel)
            end
        end
    end
end

function ACR.applyProfession(player, professionName)
    if type(professionName) ~= "string" then return end
    local ok, location = pcall(function () return ResourceLocation.of(professionName) end)
    if not ok then return end
    local profession = CharacterProfession.get(location)
    local definition = profession and CharacterProfessionDefinition.getCharacterProfessionDefinition(profession)
    if definition then player:getDescriptor():setCharacterProfession(definition:getType()) end
end

local function resolveTrait(traitName)
    if type(traitName) ~= "string" then return nil end
    local ok, location = pcall(function () return ResourceLocation.of(traitName) end)
    return ok and CharacterTrait.get(location) or nil
end

local function currentTraitKey(trait)
    local definition = CharacterTraitDefinition.getCharacterTraitDefinition(trait)
    return definition and tostring(definition:getType()) or nil
end

local function removeUnwantedTraits(player, wanted)
    local knownTraits = player:getCharacterTraits():getKnownTraits()
    for index = knownTraits:size() - 1, 0, -1 do
        local trait = knownTraits:get(index)
        if not wanted[currentTraitKey(trait)] then
            player:getCharacterTraits():remove(trait)
            player:modifyTraitXPBoost(trait, true)
        end
    end
end

local function addWantedTraits(player, traits)
    for _, traitName in ipairs(traits or {}) do
        local trait = resolveTrait(traitName)
        if trait and not player:hasTrait(trait) then
            player:getCharacterTraits():add(trait)
            player:modifyTraitXPBoost(trait, false)
        end
    end
end

function ACR.applyTraits(player, traits)
    local wanted = {}
    for _, traitName in ipairs(traits or {}) do
        wanted[ACR.resourceKey(traitName)] = true
    end
    removeUnwantedTraits(player, wanted)
    addWantedTraits(player, traits)
end

function ACR.applyRecipes(player, recipes)
    local knownRecipes = player:getKnownRecipes()
    for _, recipe in ipairs(recipes or {}) do
        if type(recipe) == "string" and not knownRecipes:contains(recipe) then
            local ok, learned = pcall(function () return player:learnRecipe(recipe) end)
            if not ok or not learned then knownRecipes:add(recipe) end
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

local function applyReadCollections(player, snapshot)
    local alreadyReadBooks = player:getAlreadyReadBook()
    for _, book in ipairs(snapshot.alreadyReadBooks or {}) do
        if not alreadyReadBooks:contains(book) then alreadyReadBooks:add(book) end
    end
    for _, media in ipairs(snapshot.readPrintMedia or {}) do
        player:addReadPrintMedia(media)
    end
    for _, lineID in ipairs(snapshot.knownMediaLines or {}) do
        if not player:isKnownMediaLine(lineID) then player:addKnownMediaLine(lineID) end
    end
end

function ACR.applyReadState(player, snapshot)
    local readPages = applyReadPages(player, snapshot.readPages)
    applyReadCollections(player, snapshot)
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
