local require = require
require "OptionScreens/ServerSettingsScreen"

local ServerSettingsScreen = ServerSettingsScreen
local getSandboxSettingsTable = ServerSettingsScreen.getSandboxSettingsTable
local isClient = isClient
local isServer = isServer
local newarray = table.newarray
local optionPrefix = "MultiplayerFastForward."

function ServerSettingsScreen.getSandboxSettingsTable()
    local pages = getSandboxSettingsTable()
    if isClient() or isServer() then return pages end
    local visiblePages = newarray()
    for i = 1, #pages do
        local page = pages[i]
        local firstSetting = page.settings and page.settings[1]
        if not firstSetting or firstSetting.name:sub(1, #optionPrefix) ~= optionPrefix then
            visiblePages[#visiblePages + 1] = page
        end
    end
    return visiblePages
end

if not isClient() then return end

local Shared = require "mff_shared"
local Controls = require "ui/mff_controls"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"
require "ISUI/ISContextMenu"
require "Vehicles/ISUI/ISVehicleMenu"
local getSpecificPlayer = getSpecificPlayer
local getNumActivePlayers = getNumActivePlayers
local sendClientCommand = sendClientCommand
local isShiftKeyDown = isShiftKeyDown
local MainScreen = MainScreen
local KeybindId = KeybindId
local type = type
local error = error
local ISBaseTimedAction = ISBaseTimedAction
local getServerTimeMills = GameTime.getServerTimeMills
local ISTimedActionQueue = ISTimedActionQueue
local ISContextMenu = ISContextMenu
local ISChat = ISChat
local ISVehicleMenu = ISVehicleMenu
local Events = Events
local client = {}
local panels = newarray()
local pauseOverlay
local gameTime
local vehicleSet
local zombieList
local core
local requestTicks = 0

local blockedPlayers = newarray()
local originals = {}
local frozenVehicles = newarray()
local vehicleOriginals = {}
local canceledGeneration
local protectionGeneration
local protectionPending = false
local protectionActive = false
local protectionRadiusSquared
local protectedPositions = newarray()
local reportedThreat
local timeoutTimestamp = getServerTimeMills()
local unpausedElapsed = 0

local function paused()
    local snapshot = client.snapshot
    return snapshot ~= nil and (snapshot.speed == 0 or snapshot.speed > 1 and protectionPending
        and protectionGeneration == snapshot.generation)
end

client.isPaused = paused

local function updateActionClock()
    local now = getServerTimeMills()
    if not paused() then unpausedElapsed = unpausedElapsed + now - timeoutTimestamp end
    timeoutTimestamp = now
end

local originalUsingTimeout = ISBaseTimedAction.isUsingTimeout
function ISBaseTimedAction:isUsingTimeout()
    return originalUsingTimeout(self) and (not isClient() or not self.complete)
end

local clientUsingTimeout = ISBaseTimedAction.isUsingTimeout
local originalNew = ISBaseTimedAction.new
function ISBaseTimedAction:new(character)
    local action = originalNew(self, character)
    if action.complete then
        local start = action.start
        action.start = function(self)
            if isClient() and self.isUsingTimeout == clientUsingTimeout and originalUsingTimeout(self) then
                updateActionClock()
                self.mffTimeoutStart = unpausedElapsed
            end
            return start(self)
        end
    end
    return action
end

local function updateActionTimeout(player)
    local queue = ISTimedActionQueue.queues[player]
    local action = queue and queue.queue[1]
    if action and action.mffTimeoutStart and unpausedElapsed - action.mffTimeoutStart > Shared.ACTION_TIMEOUT_MS then
        action.mffTimeoutStart = nil
        action.action:forceStop()
    end
end

local nativeIsGamePaused = isGamePaused
function isGamePaused()
    return paused() or nativeIsGamePaused()
end

local function pauseAwareKey(callback)
    return function(key)
        if not paused() then return callback(key) end
    end
end

local vehicleKeyEvents = newarray("OnKeyPressed", "OnKeyStartPressed")
local vehicleKeyMethods = newarray("onKeyPressed", "onKeyStartPressed")
for i = 1, #vehicleKeyEvents do
    local event = Events[vehicleKeyEvents[i]]
    local method = vehicleKeyMethods[i]
    local callback = ISVehicleMenu[method]
    event.Remove(callback)
    ISVehicleMenu[method] = pauseAwareKey(callback)
    event.Add(ISVehicleMenu[method])
end

local originalAddAction = ISTimedActionQueue.add
function ISTimedActionQueue.add(action)
    if paused() then return end
    return originalAddAction(action)
end

local originalAddAfter = ISTimedActionQueue.addAfter
function ISTimedActionQueue.addAfter(previousAction, action)
    if paused() then return end
    return originalAddAfter(previousAction, action)
end

local originalContextMouseUp = ISContextMenu.onMouseUp
function ISContextMenu:onMouseUp(x, y)
    if paused() then return true end
    return originalContextMouseUp(self, x, y)
end

local originalContextJoypad = ISContextMenu.onJoypadDown
function ISContextMenu:onJoypadDown(button)
    if paused() then return end
    return originalContextJoypad(self, button)
end

local function blockCharacters()
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and player:isAlive() then
            if originals[player] == nil then
                originals[player] = player:isBlockMovement()
                blockedPlayers[#blockedPlayers + 1] = player
                Shared.debugLog("Character movement blocked", "localPlayer", i)
            end
            player:setBlockMovement(true)
        end
    end
end

local function restoreCharacters()
    if #blockedPlayers > 0 then Shared.debugLog("Character movement restored", "players", #blockedPlayers) end
    for i = 1, #blockedPlayers do
        local player = blockedPlayers[i]
        player:setBlockMovement(originals[player])
    end
    blockedPlayers = newarray()
    originals = {}
end

local function freezeVehicles()
    local iterator = vehicleSet:iterator()
    while iterator:hasNext() do
        local vehicle = iterator:next()
        if vehicleOriginals[vehicle] == nil then
            vehicleOriginals[vehicle] = { active = vehicle:isPhysicsActive(), localSimulation = vehicle:isLocalPhysicSim() }
            frozenVehicles[#frozenVehicles + 1] = vehicle
        end
    end
    for i = 1, #frozenVehicles do
        local vehicle = frozenVehicles[i]
        if not vehicle:isRemovedFromWorld() and vehicle:isPhysicsActive() then vehicle:setPhysicsActive(false) end
    end
end

local function restoreVehicles()
    if #frozenVehicles > 0 then Shared.debugLog("Vehicle physics restored", "vehicles", #frozenVehicles) end
    for i = 1, #frozenVehicles do
        local vehicle = frozenVehicles[i]
        local original = vehicleOriginals[vehicle]
        local localSimulation = vehicle:isLocalPhysicSim()
        original.resumeActive = localSimulation ~= original.localSimulation and localSimulation
            or localSimulation == original.localSimulation and original.active
        if not vehicle:isRemovedFromWorld() and original.resumeActive then vehicle:setPhysicsActive(true) end
    end
    for i = 1, #frozenVehicles do
        local vehicle = frozenVehicles[i]
        if not vehicle:isRemovedFromWorld() and not vehicleOriginals[vehicle].resumeActive then vehicle:setPhysicsActive(false) end
    end
    frozenVehicles = newarray()
    vehicleOriginals = {}
end

local function applyWorldSpeed(snapshot)
    if not gameTime then return end
    local speed = snapshot.speed
    if paused() then
        speed = 0
    elseif speed > 1 and canceledGeneration == snapshot.generation then
        speed = 1
    end
    Shared.applySpeed(gameTime, speed, snapshot.multipliers)
end

local function blockPauseInput()
    if not gameTime then return end
    blockCharacters()
    freezeVehicles()
    if not pauseOverlay then return end
    pauseOverlay:addToUIManager()
    for i = 1, 4 do
        if panels[i] then panels[i]:addToUIManager() end
    end
    if ISChat and ISChat.instance then ISChat.instance:addToUIManager() end
    if MainScreen.instance and MainScreen.instance:getIsVisible() then MainScreen.instance:addToUIManager() end
end

local function applyClientState()
    applyWorldSpeed(client.snapshot)
    if paused() then
        blockPauseInput()
    elseif #blockedPlayers > 0 or #frozenVehicles > 0 then
        restoreCharacters()
        restoreVehicles()
    end
end

local function updateProtectedPositions()
    protectedPositions = newarray()
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and player:isAlive() then
            protectedPositions[#protectedPositions + 1] = { player = player, x = player:getX(), y = player:getY() }
        end
    end
end

local function updateLocalProtection()
    local snapshot = client.snapshot
    protectionActive = false
    if not snapshot or snapshot.speed <= 1 or snapshot.sleepAcceleration then
        protectionGeneration, protectionPending = nil, false
        return
    end
    protectionRadiusSquared = Shared.protectionRadiusSquared()
    if not protectionRadiusSquared then
        protectionGeneration, protectionPending = nil, false
        return
    end
    if protectionGeneration == snapshot.generation then return end
    updateProtectedPositions()
    protectionActive = #protectedPositions > 0
end

local function requestZombiePause(zombie, player, distanceSquared)
    updateActionClock()
    protectionGeneration = client.snapshot.generation
    protectionPending, protectionActive = true, false
    reportedThreat = { player = player, zombie = zombie, generation = protectionGeneration }
    applyClientState()
    if pauseOverlay then pauseOverlay:update() end
    Shared.debugLog("Requesting zombie protection pause", "player", player:getOnlineID(), "generation", protectionGeneration,
        "distanceSquared", distanceSquared, "radiusSquared", protectionRadiusSquared)
    sendClientCommand(player, "MultiplayerFastForward", "ZombieThreat", { generation = protectionGeneration })
end

local function findLoadedThreat(positions, radiusSquared)
    for i = 0, zombieList:size() - 1 do
        local zombie = zombieList:get(i)
        local player, distanceSquared = Shared.findThreatenedPlayer(zombie, positions, radiusSquared)
        if player then return zombie, player, distanceSquared end
    end
end

local function detectLocalZombie(zombie)
    if not protectionActive then return end
    local player, distanceSquared = Shared.findThreatenedPlayer(zombie, protectedPositions, protectionRadiusSquared)
    if player then requestZombiePause(zombie, player, distanceSquared) end
end

local function checkLoadedZombies()
    local zombie, player, distanceSquared = findLoadedThreat(protectedPositions, protectionRadiusSquared)
    if zombie then requestZombiePause(zombie, player, distanceSquared) end
end

local function updateReportedThreat()
    if not reportedThreat then return end
    local radiusSquared = Shared.protectionRadiusSquared()
    updateProtectedPositions()
    if radiusSquared then
        if zombieList:contains(reportedThreat.zombie)
            and Shared.findThreatenedPlayer(reportedThreat.zombie, protectedPositions, radiusSquared) then return end
        local zombie = findLoadedThreat(protectedPositions, radiusSquared)
        if zombie then
            reportedThreat.zombie = zombie
            return
        end
    end
    local report = reportedThreat
    reportedThreat = nil
    sendClientCommand(report.player, "MultiplayerFastForward", "ZombieThreatCleared", { generation = report.generation })
end

local function cancelForMovement(player)
    local snapshot = client.snapshot
    if not gameTime or not snapshot or paused() or snapshot.sleepAcceleration or canceledGeneration == snapshot.generation then return end
    if not player:isLocalPlayer() or not player:isAlive() or not (player:pressedMovement(false) or player:isPlayerMoving()) then return end
    if protectionActive then
        updateLocalProtection()
        checkLoadedZombies()
        if paused() then return end
    end
    for i = 1, #Shared.options do
        local speed = Shared.options[i].speed
        if speed > 1 and snapshot.counts[speed] > 0 then
            canceledGeneration = snapshot.generation
            Shared.applySpeed(gameTime, 1)
            Shared.debugLog("Requesting acceleration reset", "player", player:getOnlineID(), "generation", snapshot.generation)
            sendClientCommand(player, "MultiplayerFastForward", "CancelAcceleration", { generation = snapshot.generation })
            return
        end
    end
end

local function nonnegativeInteger(number)
    return type(number) == "number" and number >= 0 and number % 1 == 0
end

local function validCounts(snapshot)
    if type(snapshot.counts) ~= "table" or type(snapshot.selections) ~= "table" then return false end
    local total = 0
    for i = 1, #Shared.options do
        local count = snapshot.counts[Shared.options[i].speed]
        if not nonnegativeInteger(count) then return false end
        total = total + count
    end
    return total == snapshot.total
end

local function validSettings(snapshot)
    if type(snapshot.multipliers) ~= "table" or type(snapshot.adminForce) ~= "boolean"
        or not nonnegativeInteger(snapshot.onlinePlayers) or snapshot.onlinePlayers < snapshot.total
        or not Shared.isValidMinimumPlayers(snapshot.minimumPlayers) then
        return false
    end
    for i = 3, #Shared.options do
        if not Shared.isValidMultiplier(snapshot.multipliers[Shared.options[i].speed]) then return false end
    end
    return true
end

local function validSnapshot(snapshot)
    return type(snapshot) == "table" and Shared.isValidSpeed(snapshot.speed)
        and nonnegativeInteger(snapshot.revision) and nonnegativeInteger(snapshot.generation)
        and nonnegativeInteger(snapshot.total) and validCounts(snapshot)
        and type(snapshot.sleepAcceleration) == "boolean" and type(snapshot.zombieThreat) == "boolean"
        and validSettings(snapshot)
end

function client.vote(playerIndex, speed)
    local player = getSpecificPlayer(playerIndex)
    local snapshot = client.snapshot
    if not player or not player:isAlive() or not snapshot or not Shared.isValidSpeed(speed) then return end
    if not Shared.canSelect(snapshot, speed) then return end
    local force = snapshot.adminForce and isShiftKeyDown() and player:isAccessLevel("admin")
    local playerId = player:getOnlineID()
    if not force and speed == 0 and snapshot.selections[playerId] == 0 then speed = 1 end
    if speed > 1 and (player:pressedMovement(false) or player:isPlayerMoving()) then return end
    Shared.debugLog("Sending vote", "player", playerId, "speed", speed, "generation", snapshot.generation)
    sendClientCommand(player, "MultiplayerFastForward", "Vote", { speed = speed, generation = snapshot.generation, force = force })
end

local function requestState()
    local player = getSpecificPlayer(0)
    if player then
        Shared.debugLog("Requesting server state")
        sendClientCommand(player, "MultiplayerFastForward", "RequestState", {})
    end
end

local function createControls(playerIndex)
    local slot = playerIndex + 1
    if panels[slot] then panels[slot]:removeFromUIManager() end
    local panel = Controls:new(playerIndex, client)
    panel:initialise()
    panel:addToUIManager()
    panels[slot] = panel
    Shared.debugLog("Speed controls created", "localPlayer", playerIndex)
    requestState()
end

local function onGameStart()
    gameTime, core = getGameTime(), getCore()
    local cell = getCell()
    vehicleSet, zombieList = cell:getVehicles(), cell:getZombieList()
    pauseOverlay = Controls.PauseOverlay:new(client)
    pauseOverlay:initialise()
    pauseOverlay:addToUIManager()
    Shared.debugLog("Multiplayer client initialized")
    for i = 0, getNumActivePlayers() - 1 do
        if getSpecificPlayer(i) then createControls(i) end
    end
end

local function onServerCommand(module, command, snapshot)
    if module ~= "MultiplayerFastForward" or command ~= "State" and command ~= "ZombieThreat" then return end
    if not validSnapshot(snapshot) then error("[MultiplayerFastForward] Invalid server state") end
    if command == "ZombieThreat" and not nonnegativeInteger(snapshot.requestGeneration) then
        error("[MultiplayerFastForward] Invalid zombie protection response")
    end
    if client.snapshot and snapshot.revision < client.snapshot.revision then
        Shared.debugLog("Discarded older server state", "received", snapshot.revision, "current", client.snapshot.revision)
        return
    end
    updateActionClock()
    if command == "ZombieThreat" and snapshot.requestGeneration == protectionGeneration then protectionPending = false end
    client.snapshot = snapshot
    Shared.debugLog("Received server state", "revision", snapshot.revision, "generation", snapshot.generation,
        "speed", snapshot.speed, "players", snapshot.total)
    updateLocalProtection()
    if gameTime and protectionActive then checkLoadedZombies() end
    if pauseOverlay then pauseOverlay:update() end
    applyClientState()
end

local function requestMissingState()
    requestTicks = requestTicks + 1
    if requestTicks >= 60 then
        requestTicks = 0
        requestState()
    end
end

local function onTick()
    if not gameTime then return end
    updateActionClock()
    if client.snapshot then
        updateLocalProtection()
        updateReportedThreat()
        applyClientState()
    else
        requestMissingState()
    end
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player then
            updateActionTimeout(player)
            cancelForMovement(player)
        end
    end
end

local function onKeyPressed(key)
    if not core or core:isDoingTextEntry() then return end
    if MainScreen.instance and MainScreen.instance:getIsVisible() then return end
    for i = 1, #Shared.options do
        local option = Shared.options[i]
        if core:isKey(KeybindId[option.binding], key) then
            client.vote(0, option.speed)
            return
        end
    end
end

local function onMainMenu()
    Shared.debugLog("Multiplayer client cleanup")
    restoreCharacters()
    restoreVehicles()
    if gameTime then Shared.applySpeed(gameTime, 1) end
    for i = 1, 4 do
        if panels[i] then panels[i]:removeFromUIManager() end
    end
    panels = newarray()
    if pauseOverlay then pauseOverlay:removeFromUIManager() end
    pauseOverlay = nil
    client.snapshot = nil
    gameTime, core, vehicleSet, zombieList = nil, nil, nil, nil
    canceledGeneration = nil
    protectionGeneration, protectionRadiusSquared = nil, nil
    protectionPending, protectionActive = false, false
    protectedPositions = newarray()
    reportedThreat = nil
    requestTicks, timeoutTimestamp, unpausedElapsed = 0, getServerTimeMills(), 0
end

Events.OnGameStart.Add(onGameStart)
Events.OnCreatePlayer.Add(createControls)
Events.OnServerCommand.Add(onServerCommand)
Events.OnTickEvenPaused.Add(onTick)
Events.OnPlayerUpdate.Add(cancelForMovement)
Events.OnZombieUpdate.Add(detectLocalZombie)
Events.OnKeyPressed.Add(onKeyPressed)
Events.OnMainMenuEnter.Add(onMainMenu)
Events.OnDisconnect.Add(onMainMenu)
