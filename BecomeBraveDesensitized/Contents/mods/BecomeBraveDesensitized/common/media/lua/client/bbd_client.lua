if isServer() then return end

local Rules = require "bbd_shared"
local multiplayer = isClient()
local getTimestampMs = getTimestampMs
local getSpecificPlayer = getSpecificPlayer
local getNumActivePlayers = getNumActivePlayers
local getPlayerByOnlineID = getPlayerByOnlineID
local sendClientCommand = sendClientCommand
local Events = Events
local type = type
local error = error
local floor = math.floor
local huge = math.huge
local reports = {}
local pending = {}

local function reportKills(index, player)
    if player:getOnlineID() < 0 then return end
    local report = reports[index]
    if not report or report.player ~= player then
        report = { player = player, ready = false }
        reports[index] = report
    end
    local kills = player:getZombieKills()
    sendClientCommand(player, Rules.ID, "Check", { kills = kills, sync = not report.ready })
    Rules.debugLog("Reported zombie kills", kills, "for local player", index)
end

local function checkPlayer(index, player)
    if not player or player:isDead() then return end
    if multiplayer then
        reportKills(index, player)
    else
        Rules.check(player, player:getZombieKills())
    end
end

local function validateIdentity(snapshot)
    if type(snapshot) ~= "table" then error("[BecomeBraveDesensitized] Missing player snapshot") end
    local playerId = snapshot.playerId
    if type(playerId) ~= "number" or playerId ~= playerId or playerId < 0 or playerId > 32767 or playerId ~= floor(playerId) then
        error("[BecomeBraveDesensitized] Invalid player ID: " .. tostring(playerId))
    end
    if type(snapshot.username) ~= "string" then error("[BecomeBraveDesensitized] Missing player username") end
end

local function validateTraits(snapshot)
    local enabledTraits = snapshot.traits
    local synchronizedTraits = Rules.synchronizedTraits
    if type(enabledTraits) ~= "table" or #enabledTraits ~= #synchronizedTraits then
        error("[BecomeBraveDesensitized] Invalid trait snapshot")
    end
    for index = 1, #synchronizedTraits do
        if type(enabledTraits[index]) ~= "boolean" then
            error("[BecomeBraveDesensitized] Invalid trait flag at index " .. index)
        end
    end
end

local function applyPending(now)
    for playerId, queued in pairs(pending) do
        local player = getPlayerByOnlineID(playerId)
        if player then
            local snapshot = queued.snapshot
            if player:getUsername() == snapshot.username then Rules.applySnapshot(player, snapshot) end
            Rules.debugLog("Received trait snapshot for", snapshot.username)
            pending[playerId] = nil
        elseif now >= queued.expires then
            pending[playerId] = nil
        end
    end
end

local function acknowledge(snapshot)
    for index = 0, getNumActivePlayers() - 1 do
        local report = reports[index]
        if report then
            local player = report.player
            if player:getOnlineID() == snapshot.playerId and player:getUsername() == snapshot.username then
                report.ready = true
            end
        end
    end
end

local function applyProgress(snapshot)
    local progress = snapshot.progress
    if type(progress) ~= "table" or type(progress.active) ~= "boolean"
        or type(progress.kills) ~= "number" or progress.kills < 0 or progress.kills > 2147483647 or progress.kills ~= floor(progress.kills)
        or type(progress.revision) ~= "number" or progress.revision < 1 or progress.revision == huge or progress.revision ~= floor(progress.revision) then
        error("[BecomeBraveDesensitized] Invalid early trait progress")
    end
    for index = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(index)
        if player and player:getOnlineID() == snapshot.playerId and player:getUsername() == snapshot.username then
            local modData = player:getModData()
            local previous = modData[Rules.ID]
            if not previous or progress.revision >= previous.revision then modData[Rules.ID] = progress end
        end
    end
end

local function onServerCommand(module, command, snapshot)
    if module ~= Rules.ID or (command ~= "Traits" and command ~= "Ready" and command ~= "Progress") then return end
    validateIdentity(snapshot)
    if command == "Traits" then
        validateTraits(snapshot)
        local now = getTimestampMs()
        pending[snapshot.playerId] = { snapshot = snapshot, expires = now + 30000 }
        applyPending(now)
    elseif command == "Progress" then
        applyProgress(snapshot)
    else
        acknowledge(snapshot)
    end
end

Events.OnCreatePlayer.Add(function(index, player)
    checkPlayer(index, player)
end)

Events.EveryOneMinute.Add(function()
    for index = 0, getNumActivePlayers() - 1 do
        checkPlayer(index, getSpecificPlayer(index))
    end
    if multiplayer then applyPending(getTimestampMs()) end
end)

if multiplayer then
    Events.OnTick.Add(function(tick)
        if tick % 30 == 0 then applyPending(getTimestampMs()) end
    end)
    Events.OnServerCommand.Add(onServerCommand)
end
