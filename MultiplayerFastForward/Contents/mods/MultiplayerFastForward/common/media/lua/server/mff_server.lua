if not isServer() then return end

local require = require
local Shared = require "mff_shared"
local TimedActions = require "mff_timed_actions"
local getOnlinePlayers = getOnlinePlayers
local sendServerCommand = sendServerCommand
local type = type
local newarray = table.newarray
local Events = Events
local state = Shared.new()
local gameTime
local zombieList
local serverOptions
local publishedRevision = -1
local reportedThreats = {}

local function preserveReportedThreats(generation)
    if generation == state.generation then return end
    for i = 1, #state.roster do
        local report = reportedThreats[state.roster[i]]
        if report and report.stateGeneration == generation then report.stateGeneration = state.generation end
    end
end

local function updateSettings()
    local generation = state.generation
    Shared.updateSettings(state)
    preserveReportedThreats(generation)
end

local function livingPlayers()
    local online = getOnlinePlayers()
    local onlineCount = online:size()
    local players = newarray()
    local roster = newarray()
    for i = 0, onlineCount - 1 do
        local player = online:get(i)
        if player:isAlive() then
            players[#players + 1] = player
            roster[#roster + 1] = player:getOnlineID()
        end
    end
    return players, roster, onlineCount
end

local function allAsleep(players)
    if #players == 0 or not serverOptions:getBoolean("SleepAllowed") then
        return false
    end
    for i = 1, #players do
        if not players[i]:isAsleep() then return false end
    end
    return true
end

local function playerPositions(players)
    local positions = newarray()
    for i = 1, #players do
        local player = players[i]
        positions[i] = { player = player, x = player:getX(), y = player:getY() }
    end
    return positions
end

local function zombieNearPlayers(players, radiusSquared)
    local positions = playerPositions(players)
    for j = 0, zombieList:size() - 1 do
        if Shared.findThreatenedPlayer(zombieList:get(j), positions, radiusSquared) then return true end
    end
    return false
end

local function clientThreatActive(players)
    for i = 1, #players do
        local report = reportedThreats[players[i]:getOnlineID()]
        if report and report.stateGeneration == state.generation then return true end
    end
    return false
end

local function updateProtection(players)
    local radiusSquared = Shared.protectionRadiusSquared()
    if radiusSquared and (clientThreatActive(players) or zombieNearPlayers(players, radiusSquared)) then
        Shared.detectZombieThreat(state)
    else
        Shared.clearZombieThreat(state)
    end
end

local function initializeWorld()
    local cell = getCell()
    if cell then
        gameTime = getGameTime()
        zombieList = cell:getZombieList()
        serverOptions = getServerOptions()
        Shared.debugLog("Multiplayer server initialized")
    end
end

local function cancelForMovement(players)
    for i = 1, #players do
        local player = players[i]
        if player:isPlayerMoving() then
            Shared.cancelAcceleration(state, player:getOnlineID())
            return
        end
    end
end

local function applyWorldSpeed()
    Shared.applySpeed(gameTime, state.speed, state.multipliers)
    TimedActions.update(Shared.multiplier(state.speed, state.multipliers), state.selections)
end

local function updateWorld()
    if not gameTime then initializeWorld() end
    if not gameTime then return end
    updateSettings()
    local players, roster, onlineCount = livingPlayers()
    Shared.replaceRoster(state, roster, onlineCount)
    if allAsleep(players) then
        Shared.enterSleepAcceleration(state)
    else
        Shared.leaveSleepAcceleration(state)
    end
    updateProtection(players)
    cancelForMovement(players)
    applyWorldSpeed()
end

local function publishState()
    if publishedRevision ~= state.revision then
        Shared.debugLog("Broadcasting server state", "revision", state.revision, "generation", state.generation,
            "speed", state.speed, "players", #state.roster)
        sendServerCommand("MultiplayerFastForward", "State", Shared.snapshot(state))
        publishedRevision = state.revision
    end
end

local function onTick()
    updateWorld()
    TimedActions.tick()
    publishState()
end

local function selectVote(player, arguments)
    if arguments.force ~= true then
        Shared.select(state, player:getOnlineID(), arguments.speed)
        return
    end
    if not state.adminForce or not player:isAccessLevel("admin") then
        Shared.debugLog("Forced vote rejected", "player", player:getOnlineID(), "reason", "admin force disabled or unauthorized")
        return
    end
    local generation = state.generation
    Shared.forceSelect(state, player:getOnlineID(), arguments.speed)
    preserveReportedThreats(generation)
end

local function receiveVote(player, arguments)
    if not player:isAlive() then
        Shared.debugLog("Vote rejected", "reason", "dead character")
        return
    end
    if type(arguments) ~= "table" then
        Shared.debugLog("Vote rejected", "reason", "invalid payload")
        return
    end
    if arguments.generation ~= state.generation then
        Shared.debugLog("Vote rejected", "reason", "stale generation", "received", arguments.generation, "current", state.generation)
        return
    end
    selectVote(player, arguments)
    cancelForMovement(livingPlayers())
    applyWorldSpeed()
    publishState()
end

local function acceptsZombieThreat(player, generation)
    return player:isAlive() and state.selections[player:getOnlineID()] ~= nil
        and (generation == state.generation
            or generation + 1 == state.generation and state.speed == 0 and state.zombieThreat)
        and not state.sleepAcceleration and Shared.protectionRadiusSquared() ~= nil
end

local function receiveZombieThreat(player, arguments)
    if type(arguments) ~= "table" or type(arguments.generation) ~= "number"
        or arguments.generation < 0 or arguments.generation % 1 ~= 0 then return end
    if acceptsZombieThreat(player, arguments.generation) then
        local playerId = player:getOnlineID()
        Shared.debugLog("Client zombie threat accepted", "player", playerId, "generation", state.generation)
        Shared.detectZombieThreat(state)
        reportedThreats[playerId] = { requestGeneration = arguments.generation, stateGeneration = state.generation }
    end
    updateWorld()
    if not gameTime then return end
    publishState()
    local snapshot = Shared.snapshot(state)
    snapshot.requestGeneration = arguments.generation
    sendServerCommand(player, "MultiplayerFastForward", "ZombieThreat", snapshot)
end

local function clearReportedThreat(player, arguments)
    local playerId = player:getOnlineID()
    local report = reportedThreats[playerId]
    if type(arguments) ~= "table" or not report or arguments.generation ~= report.requestGeneration then return end
    reportedThreats[playerId] = nil
    Shared.debugLog("Client zombie threat cleared", "player", playerId)
    updateWorld()
    publishState()
end

local function onClientCommand(module, command, player, arguments)
    if module ~= "MultiplayerFastForward" then return end
    if command == "ZombieThreat" then return receiveZombieThreat(player, arguments) end
    if command == "ZombieThreatCleared" then return clearReportedThreat(player, arguments) end
    updateWorld()
    if not gameTime then return end
    if command == "Vote" then receiveVote(player, arguments) end
    if command == "CancelAcceleration" and player:isAlive() and type(arguments) == "table"
        and arguments.generation == state.generation then
        Shared.cancelAcceleration(state, player:getOnlineID())
        applyWorldSpeed()
        publishState()
    end
    if command == "Vote" or command == "RequestState" or command == "CancelAcceleration" then
        Shared.debugLog("Sending server state", "command", command, "revision", state.revision)
        sendServerCommand(player, "MultiplayerFastForward", "State", Shared.snapshot(state))
    end
end

Events.OnTickEvenPaused.Add(onTick)
Events.OnClientCommand.Add(onClientCommand)
