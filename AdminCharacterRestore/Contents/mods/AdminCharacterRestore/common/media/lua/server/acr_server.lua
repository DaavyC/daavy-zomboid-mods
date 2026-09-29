require "acr_shared"

if not isServer() then return end

local ACR = AdminCharacterRestore
local modData
local literatureTypes
local mediaLineIds

local function getUsername(player)
    return player and player:getUsername() or nil
end

local function getSteamID(player)
    if not player then return nil end
    local steamID = player:getSteamID()
    if steamID == nil then return nil end
    steamID = tostring(steamID)
    if steamID == "" or steamID == "nil" or steamID == "0" or steamID == "-1" then return nil end
    return steamID
end

local function getPlayerKey(username, steamID)
    if not username then return nil end
    return steamID and ("steam:" .. steamID) or ("user:" .. username)
end

local function normalizeTraits(traits)
    local normalizedTraits = {}
    if type(traits) == "table" then
        for index = 1, #traits do
            local traitName = traits[index]
            if type(traitName) == "string" then normalizedTraits[#normalizedTraits + 1] = ACR.resourceKey(traitName) end
        end
    end
    return normalizedTraits
end

local function normalizeSnapshot(snapshot)
    if type(snapshot) ~= "table" then return nil end
    local createdAt = tonumber(snapshot.createdAt) or tonumber(snapshot.id) or ACR.nowMs()
    local snapshotID = type(snapshot.id) == "string" or type(snapshot.id) == "number"
    snapshot.id = snapshotID and tostring(snapshot.id) or tostring(createdAt)
    snapshot.createdAt = createdAt
    snapshot.worldDays = tonumber(snapshot.worldDays) or 0
    if type(snapshot.profession) == "string" then snapshot.profession = ACR.resourceKey(snapshot.profession) end
    snapshot.perks = type(snapshot.perks) == "table" and snapshot.perks or {}
    snapshot.traits = normalizeTraits(snapshot.traits)
    snapshot.recipes = type(snapshot.recipes) == "table" and snapshot.recipes or {}
    snapshot.readPages = type(snapshot.readPages) == "table" and snapshot.readPages or {}
    snapshot.alreadyReadBooks = type(snapshot.alreadyReadBooks) == "table" and snapshot.alreadyReadBooks or {}
    snapshot.readPrintMedia = type(snapshot.readPrintMedia) == "table" and snapshot.readPrintMedia or {}
    snapshot.knownMediaLines = type(snapshot.knownMediaLines) == "table" and snapshot.knownMediaLines or {}
    return snapshot
end

local function snapshotIdentity(snapshot)
    if type(snapshot) ~= "table" then return nil end

    if snapshot.id ~= nil then
        local snapshotID = tostring(snapshot.id)
        if snapshotID ~= "" and snapshotID ~= "nil" then return "id:" .. snapshotID end
    end

    local createdAt = tonumber(snapshot.createdAt)
    if createdAt then return "created:" .. tostring(createdAt) end
    return snapshot
end

local function appendLegacySnapshot(restores, seen, snapshot)
    if type(snapshot) ~= "table" then return end
    local identity = snapshotIdentity(snapshot)
    if seen[identity] then return end
    seen[identity] = true
    table.insert(restores, snapshot)
end

local function appendLegacyRecordSnapshots(restores, seen, storedRecord)
    if type(storedRecord.snapshots) ~= "table" then return end
    for index = 1, #storedRecord.snapshots do
        local snapshot = storedRecord.snapshots[index]
        if type(snapshot) == "table" and (snapshot.released or (snapshot.released == nil and storedRecord.released)) then
            appendLegacySnapshot(restores, seen, snapshot)
        end
    end
end

local function appendLegacyReleasedSnapshots(restores, seen, storedRecord)
    if type(storedRecord.released) ~= "table" then return end
    if storedRecord.released.id or storedRecord.released.createdAt
        or storedRecord.released.perks or storedRecord.released.traits then
        appendLegacySnapshot(restores, seen, storedRecord.released)
        return
    end
    for index = 1, #storedRecord.released do
        appendLegacySnapshot(restores, seen, storedRecord.released[index])
    end
end

local function collectLegacyRestores(storedRecord)
    local restores = type(storedRecord.restores) == "table" and storedRecord.restores or {}
    local seen = {}
    for index = 1, #restores do
        local identity = snapshotIdentity(restores[index])
        if identity ~= nil then seen[identity] = true end
    end
    appendLegacyRecordSnapshots(restores, seen, storedRecord)
    appendLegacyReleasedSnapshots(restores, seen, storedRecord)
    return restores
end

local function normalizeRestores(restores)
    local normalizedRestores = {}
    local maxSnapshots = ACR.getMaxSnapshotsPerPlayer()
    for index = 1, #restores do
        local snapshot = restores[index]
        local normalized = normalizeSnapshot(snapshot)
        if normalized then table.insert(normalizedRestores, normalized) end
    end
    while #normalizedRestores > maxSnapshots do
        table.remove(normalizedRestores)
    end
    return normalizedRestores
end

local function normalizeRecordIdentity(storedRecord)
    if type(storedRecord.username) ~= "string" then storedRecord.username = nil end
    if storedRecord.steamID ~= nil then
        local steamType = type(storedRecord.steamID)
        storedRecord.steamID = (steamType == "string" or steamType == "number") and tostring(storedRecord.steamID)
            or nil
        if storedRecord.steamID == "" or storedRecord.steamID == "nil"
            or storedRecord.steamID == "0" or storedRecord.steamID == "-1" then
            storedRecord.steamID = nil
        end
    end
    storedRecord.lastSnapshotId = tonumber(storedRecord.lastSnapshotId)
    storedRecord.latestWorldHour = tonumber(storedRecord.latestWorldHour)
end

local function migrateRecord(storedRecord)
    if type(storedRecord) ~= "table" then return { restores = {} } end

    normalizeRecordIdentity(storedRecord)
    storedRecord.restores = normalizeRestores(collectLegacyRestores(storedRecord))
    if storedRecord.latestSnapshot then
        storedRecord.latestSnapshot = normalizeSnapshot(storedRecord.latestSnapshot)
    end
    if storedRecord.snapshots ~= nil then storedRecord.snapshots = nil end
    if storedRecord.released ~= nil then storedRecord.released = nil end
    return storedRecord
end

local function migrateModData()
    modData.schemaVersion = ACR.DATA_VERSION
    modData.players = type(modData.players) == "table" and modData.players or {}
    modData.lastSnapshotId = tonumber(modData.lastSnapshotId) or 0

    for key, storedRecord in pairs(modData.players) do
        local record = migrateRecord(storedRecord)
        local greatest = tonumber(record.lastSnapshotId) or 0
        greatest = math.max(greatest, tonumber(record.latestSnapshot and record.latestSnapshot.id) or 0)
        for index = 1, #record.restores do
            local snapshot = record.restores[index]
            greatest = math.max(greatest, tonumber(snapshot.id) or 0)
        end
        record.lastSnapshotId = greatest
        modData.lastSnapshotId = math.max(modData.lastSnapshotId, greatest)
        modData.players[key] = record
    end
    ACR.debug("ModData migrated", modData.schemaVersion)
end

local function ensureModData()
    if modData then return modData end
    modData = ModData.getOrCreate(ACR.ID)
    migrateModData()
    return modData
end

local function findExistingRecord(players, key, steamID, username)
    if players[key] then return key, players[key] end

    for storedKey, storedRecord in pairs(players) do
        if type(storedRecord) == "table" then
            if steamID and tostring(storedRecord.steamID) == steamID then return storedKey, storedRecord end
            if username and storedRecord.username == username and (not steamID or not storedRecord.steamID) then
                return storedKey, storedRecord
            end
        end
    end
    return nil, nil
end

local function ensurePlayerRecord(player)
    local username = getUsername(player)
    local steamID = getSteamID(player)
    local key = getPlayerKey(username, steamID)
    if not username or not key then return nil end

    local players = ensureModData().players
    local storedKey, record = findExistingRecord(players, key, steamID, username)
    record = record or { restores = {} }
    record = migrateRecord(record)
    steamID = steamID or (record.steamID and tostring(record.steamID))
    local recordKey = steamID and ("steam:" .. steamID) or key
    record.username = username
    record.steamID = steamID
    players[recordKey] = record
    if storedKey and storedKey ~= recordKey then players[storedKey] = nil end
    return record
end

local function trimRestores(record)
    local maxSnapshots = ACR.getMaxSnapshotsPerPlayer()
    ACR.debug("Trimming restores", record.username, #record.restores, maxSnapshots)
    while #record.restores > maxSnapshots do
        table.remove(record.restores)
    end
end

local function nextSnapshotId(record, timestamp)
    local greatest = math.max(tonumber(modData.lastSnapshotId) or 0, tonumber(record.lastSnapshotId) or 0)
    greatest = math.max(greatest, tonumber(record.latestSnapshot and record.latestSnapshot.id) or 0)
    for index = 1, #record.restores do
        local storedSnapshot = record.restores[index]
        greatest = math.max(greatest, tonumber(storedSnapshot.id) or 0)
    end

    local nextID = math.max(timestamp, greatest + 1)
    record.lastSnapshotId = nextID
    modData.lastSnapshotId = nextID
    return tostring(nextID)
end

local function characterName(player)
    local descriptor = player and player:getDescriptor()
    if not descriptor then return getUsername(player) or "Unknown" end

    local name = ((descriptor:getForename() or "") .. " " .. (descriptor:getSurname() or ""))
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or getUsername(player) or "Unknown"
end

local function restoreName(player)
    return string.format("%s - %s", characterName(player), os.date("%d/%m/%Y | %H:%M"))
end

local function buildLiteratureIndex()
    if literatureTypes then return end
    literatureTypes = table.newarray()
    local items = getScriptManager():getAllItems()
    local literatureCount = 0
    for index = 0, items:size() - 1 do
        local scriptItem = items:get(index)
        if scriptItem:isItemType(ItemType.LITERATURE) then
            literatureCount = literatureCount + 1
            literatureTypes[literatureCount] = scriptItem:getFullName()
        end
    end
end

local function buildMediaIndex()
    if mediaLineIds then return end
    mediaLineIds = table.newarray()
    local seen = {}
    for _, media in pairs(RecMedia or {}) do
        local lines = media.lines or {}
        for index = 1, #lines do
            local line = lines[index]
            local lineID = line.text
            if lineID and not seen[lineID] then
                seen[lineID] = true
                mediaLineIds[#mediaLineIds + 1] = lineID
            end
        end
    end
end

local function captureReadPages(player)
    buildLiteratureIndex()
    local pages = {}
    for index = 1, #literatureTypes do
        local fullType = literatureTypes[index]
        local pagesRead = player:getAlreadyReadPages(fullType)
        if pagesRead > 0 then pages[fullType] = pagesRead end
    end
    return pages
end

local function captureKnownMediaLines(player)
    buildMediaIndex()
    local knownLines = {}
    for index = 1, #mediaLineIds do
        local lineID = mediaLineIds[index]
        if player:isKnownMediaLine(lineID) then knownLines[#knownLines + 1] = lineID end
    end
    return knownLines
end

local function copyJavaList(javaValues)
    local strings = {}
    local size = javaValues:size()
    for index = 0, size - 1 do
        local javaValue = javaValues:get(index)
        if javaValue then strings[#strings + 1] = tostring(javaValue) end
    end
    return strings
end

local function copyJavaSet(javaValues)
    return copyJavaList(ArrayList.new(javaValues))
end

local function capturePerks(player)
    local perks = {}
    local xp = player:getXp()
    local maxPerkIndex = Perks.getMaxIndex()
    for index = 0, maxPerkIndex - 1 do
        local perkType = Perks.fromIndex(index)
        local perk = perkType and PerkFactory.getPerk(perkType)
        if perk and perk:getParent() ~= Perks.None then
            perks[tostring(perkType)] = { level = player:getPerkLevel(perkType), xp = xp:getXP(perkType) }
        end
    end
    return perks
end

local function captureTraits(player)
    local traits = {}
    local knownTraits = player:getCharacterTraits():getKnownTraits()
    for index = 0, knownTraits:size() - 1 do
        traits[#traits + 1] = tostring(knownTraits:get(index))
    end
    return traits
end

local function captureRecipes(player)
    return copyJavaList(player:getKnownRecipes())
end

local function getProfession(player)
    local descriptor = player:getDescriptor()
    local profession = descriptor:getCharacterProfession()
    return profession and tostring(profession) or nil
end

local function captureRestorableState(player)
    return {
        profession = getProfession(player),
        perks = capturePerks(player),
        traits = captureTraits(player),
        recipes = captureRecipes(player),
        readPages = captureReadPages(player),
        alreadyReadBooks = copyJavaList(player:getAlreadyReadBook()),
        readPrintMedia = copyJavaSet(player:getReadPrintMedia()),
        knownMediaLines = captureKnownMediaLines(player),
        zombieKills = player:getZombieKills(),
        hoursSurvived = player:getHoursSurvived(),
        weight = player:getNutrition():getWeight()
    }
end

local function captureSnapshot(player, record)
    local timestamp = ACR.nowMs()
    local snapshot = captureRestorableState(player)
    snapshot.id = nextSnapshotId(record, timestamp)
    snapshot.username = getUsername(player)
    snapshot.steamID = record.steamID
    snapshot.createdAt = timestamp
    snapshot.worldDays = ACR.worldDays()
    return snapshot
end

local function saveLatestSnapshot(player, record)
    record = record or ensurePlayerRecord(player)
    if not record then return end

    record.latestSnapshot = captureSnapshot(player, record)
    record.latestWorldHour = ACR.worldHours()
    ACR.debug("Saved latest snapshot", record.username, record.latestSnapshot.id)
end

local function releaseLatestSnapshot(player)
    local record = ensurePlayerRecord(player)
    local latest = record and record.latestSnapshot
    if not latest then
        ACR.debug("Snapshot release denied: latest snapshot missing")
        return
    end

    latest.releasedAt = ACR.nowMs()
    latest.restoreName = restoreName(player)
    table.insert(record.restores, 1, latest)
    trimRestores(record)
    record.latestSnapshot = nil
    record.latestWorldHour = nil
    ACR.debug("Released snapshot", record.username, latest.id)
end

local function isSnapshotDue(record, worldHour, intervalHours)
    return not record.latestWorldHour or worldHour - record.latestWorldHour >= intervalHours
end

local function capturePlayerIfDue(player, worldHour, intervalHours)
    if not player or player:isDead() then return end
    local record = ensurePlayerRecord(player)
    if not record then return end

    if isSnapshotDue(record, worldHour, intervalHours) then
        ACR.debug("Snapshot due", record.username)
        saveLatestSnapshot(player, record)
    else
        ACR.debug("Snapshot not due", record.username)
    end
end

local function captureLatestDue()
    local players = getOnlinePlayers()
    if not players then return end

    local worldHour = ACR.worldHours()
    local intervalHours = ACR.getSnapshotIntervalHours()
    ACR.debug("Scheduler check", worldHour, intervalHours)
    for index = 0, players:size() - 1 do
        capturePlayerIfDue(players:get(index), worldHour, intervalHours)
    end
end

local function appendRecordSnapshots(output, playerKey, record)
    trimRestores(record)
    for index = 1, #record.restores do
        local storedSnapshot = record.restores[index]
        output[#output + 1] = {
            playerKey = playerKey,
            snapshotId = tostring(storedSnapshot.id),
            username = record.username,
            restoreName = type(storedSnapshot.restoreName) == "string" and storedSnapshot.restoreName or nil,
            worldDays = storedSnapshot.worldDays
        }
    end
end

local function listUsers(players)
    local users, seen = {}, {}
    for _, record in pairs(players) do
        if record.username and #record.restores > 0 and not seen[record.username] then
            seen[record.username] = true
            table.insert(users, record.username)
        end
    end
    table.sort(users)
    return users
end

local function listPayload()
    local players = ensureModData().players
    local snapshots = {}
    for playerKey, record in pairs(players) do
        appendRecordSnapshots(snapshots, playerKey, record)
    end
    table.sort(snapshots, function (left, right)
        return (tonumber(left.snapshotId) or 0) > (tonumber(right.snapshotId) or 0)
    end)
    return { snapshots = snapshots, users = listUsers(players) }
end

local function findSnapshot(playerKey, snapshotID)
    local record = ensureModData().players[playerKey]
    if not record then return nil, nil end
    for index = 1, #record.restores do
        local storedSnapshot = record.restores[index]
        if tostring(storedSnapshot.id) == snapshotID then return record, storedSnapshot end
    end
    return record, nil
end

local function findOnlineTarget(record)
    local players = getOnlinePlayers()
    if not players then return nil end
    local usernameMatch
    local usernameMismatch = false
    local recordUsername = record.username

    for index = 0, players:size() - 1 do
        local player = players:get(index)
        local playerSteamID = getSteamID(player)
        if record.steamID and playerSteamID then
            if playerSteamID == tostring(record.steamID) then return player end
            if getUsername(player) == recordUsername then usernameMismatch = true end
        elseif getUsername(player) == recordUsername then
            usernameMatch = player
        end
    end
    return usernameMismatch and nil or usernameMatch
end

local function bookMultiplierKey(level)
    if level == 1 then
        return "maxMultiplier1"
    elseif level == 3 then
        return "maxMultiplier2"
    elseif level == 5 then
        return "maxMultiplier3"
    elseif level == 7 then
        return "maxMultiplier4"
    elseif level == 9 then
        return "maxMultiplier5"
    end
end

local function bookMultiplier(scriptItem)
    if not SkillBook or not scriptItem:isItemType(ItemType.LITERATURE) then return nil end
    local book = SkillBook[scriptItem:getSkillTrained()]
    if not book then return nil end
    local level = scriptItem:getLevelSkillTrained()
    local multiplierKey = bookMultiplierKey(level)
    local maxMultiplier = multiplierKey and book[multiplierKey]
    if not maxMultiplier then return nil end
    return book.perk, maxMultiplier, level, scriptItem:getMaxLevelTrained(), scriptItem:getNumberOfPages()
end

local function applyBookMultipliers(player, readPages)
    buildLiteratureIndex()
    local scriptManager = getScriptManager()
    local xp
    for index = 1, #literatureTypes do
        local fullType = literatureTypes[index]
        local pagesRead = tonumber(readPages and readPages[fullType])
        if pagesRead and pagesRead > 0 then
            local scriptItem = scriptManager:getItem(fullType)
            if scriptItem then
                local perk, maxMultiplier, minLevel, maxLevel, pageCount = bookMultiplier(scriptItem)
                if perk and pageCount and pageCount > 0 then
                    xp = xp or player:getXp()
                    local multiplier = math.floor(math.min(1, pagesRead / pageCount) * 10) * (maxMultiplier / 10)
                    if multiplier > xp:getMultiplier(perk) then
                        addXpMultiplier(player, perk, multiplier, minLevel, maxLevel)
                    end
                end
            end
        end
    end
end

local function applySnapshotOnServer(player, snapshot)
    local readPages = ACR.applyRestoreState(player, snapshot)
    applyBookMultipliers(player, readPages)
    sendSyncPlayerFields(player, 7)
    syncPlayerStats(player, -1)
end

local function validRestoreRequest(args)
    if type(args) ~= "table" then return nil, nil end
    local playerKey = type(args.playerKey) == "string" and args.playerKey or nil
    local snapshotID = type(args.snapshotId) == "string" and args.snapshotId or nil
    if not playerKey or not snapshotID or #playerKey == 0 or #snapshotID == 0 then return nil, nil end
    if #playerKey > 128 or #snapshotID > 128 then return nil, nil end
    local hasSteamPrefix = playerKey:sub(1, 6) == "steam:" and #playerKey > 6
    local hasUsernamePrefix = playerKey:sub(1, 5) == "user:" and #playerKey > 5
    if not hasSteamPrefix and not hasUsernamePrefix then return nil, nil end
    return playerKey, snapshotID
end

local function isAdmin(player)
    if not player then return false end
    if player:getAccessLevel() == "admin" then return true end
    local role = player:getRole()
    return role and role:getName() == "admin"
end

local function findLiveTarget(record)
    local target = findOnlineTarget(record)
    return target and not target:isDead() and target or nil
end

local function sendRestore(target, snapshot)
    ACR.debug("Applying restore on server", snapshot.id)
    applySnapshotOnServer(target, snapshot)
    sendServerCommand(target, ACR.ID, "ApplySnapshot", { snapshot = snapshot })
end

local function runSelfCommand(command, requester)
    if command == "ReleaseLatest" then
        if requester:isDead() then
            releaseLatestSnapshot(requester)
        else
            ACR.debug("Snapshot release denied: requester is alive")
        end
        return true
    end

    if command == "RefreshLatest" then
        local record = not requester:isDead() and ensurePlayerRecord(requester)
        if record and not record.latestSnapshot then
            saveLatestSnapshot(requester, record)
        end
        return true
    end
    return false
end

local function resolveRestoreSource(args)
    local playerKey, snapshotID = validRestoreRequest(args)
    if not playerKey then
        ACR.debug("Restore denied: invalid request")
        return nil, nil
    end

    local record, snapshot = findSnapshot(playerKey, snapshotID)
    if not snapshot then
        ACR.debug("Restore denied: snapshot missing", playerKey, snapshotID)
        return nil, nil
    end
    return record, snapshot
end

local function restoreSnapshotFromCommand(args)
    local record, snapshot = resolveRestoreSource(args)
    if not snapshot then return end

    local target = findLiveTarget(record)
    if not target then
        ACR.debug("Restore denied: target unavailable", record.username, snapshot.id)
        return
    end

    local restoreSnapshot = ACR.copyRestorePayload(snapshot)
    if not restoreSnapshot then
        ACR.debug("Restore denied: invalid snapshot", record.username, snapshot.id)
        return
    end

    sendRestore(target, restoreSnapshot)
end

local function validateCommandArgs(args)
    if args ~= nil and type(args) ~= "table" then return nil end
    return args or {}
end

local function sendSnapshotList(requester)
    local payload = listPayload()
    sendServerCommand(requester, ACR.ID, "Snapshots", payload)
    ACR.debug("Sent snapshot list", #payload.snapshots, #payload.users)
end

local function onClientCommand(module, command, requester, args)
    if module ~= ACR.ID or type(command) ~= "string" or not requester then return end
    ACR.debug("Received command", command)
    local commandArgs = validateCommandArgs(args)
    if not commandArgs then
        ACR.debug("Rejected command: invalid arguments", command)
        return
    end
    if runSelfCommand(command, requester) then return end
    if not isAdmin(requester) then
        ACR.debug("Rejected admin command: requester is not an admin", command)
        return
    end
    if command == "ListSnapshots" then
        sendSnapshotList(requester)
    elseif command == "RestoreSnapshot" then
        restoreSnapshotFromCommand(commandArgs)
    end
end

Events.OnInitGlobalModData.Add(ensureModData)
Events.EveryTenMinutes.Add(captureLatestDue)
Events.OnClientCommand.Add(onClientCommand)
