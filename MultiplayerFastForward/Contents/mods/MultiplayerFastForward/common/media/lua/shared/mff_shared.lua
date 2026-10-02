if not isClient() and not isServer() then return end

local Shared = {}
local type = type
local print = print
local error = error
local newarray = table.newarray
Shared.PAUSE_MULTIPLIER = 1 / (365 * 24 * 60 * 60)
Shared.ACTION_TIMEOUT_MS = 30 * 60 * 1000
Shared.options = newarray(
    { speed = 0, icon = "Pause", binding = "PAUSE", label = "Pause" },
    { speed = 1, icon = "Play", binding = "NORMAL_SPEED", label = "1x" },
    { speed = 5, icon = "FFwd1", binding = "FAST_FORWARD_X1", label = "5x", setting = "Speed1" },
    { speed = 20, icon = "FFwd2", binding = "FAST_FORWARD_X2", label = "20x", setting = "Speed2" },
    { speed = 40, icon = "Wait", binding = "FAST_FORWARD_X3", label = "40x", setting = "Speed3" }
)
local validSpeeds = {}
for i = 1, #Shared.options do
    validSpeeds[Shared.options[i].speed] = true
end

function Shared.isDebugEnabled()
    local sandboxVars = SandboxVars
    local settings = sandboxVars and sandboxVars.MultiplayerFastForward
    return settings ~= nil and settings.Debug == true
end

function Shared.debugLog(...)
    if not Shared.isDebugEnabled() then return end
    print("[MultiplayerFastForward][Debug]", ...)
end

local function optionMultipliers(source)
    local multipliers = {}
    for i = 3, #Shared.options do
        local speed = Shared.options[i].speed
        multipliers[speed] = source and source[speed] or speed
    end
    return multipliers
end

function Shared.new()
    return {
        roster = newarray(),
        selections = {},
        speed = 1,
        revision = 0,
        generation = 0,
        zombieThreat = false,
        sleepAcceleration = false,
        multipliers = optionMultipliers(),
        minimumPlayers = 1,
        onlinePlayers = 0,
        adminForce = true,
    }
end

function Shared.isValidSpeed(speed)
    return type(speed) == "number" and validSpeeds[speed] == true
end

function Shared.isValidMultiplier(multiplier)
    return type(multiplier) == "number" and multiplier >= 2 and multiplier <= 100 and multiplier % 1 == 0
end

function Shared.isValidMinimumPlayers(minimum)
    return type(minimum) == "number" and minimum >= 1 and minimum <= 254 and minimum % 1 == 0
end

function Shared.multiplier(speed, multipliers)
    return speed > 1 and multipliers[speed] or speed
end

function Shared.selectionBlock(state, speed)
    if state.sleepAcceleration then return "sleep acceleration" end
    if speed <= 1 then return end
    if state.zombieThreat then return "zombie protection" end
    if state.onlinePlayers < state.minimumPlayers then return "minimum players" end
end

function Shared.canSelect(state, speed)
    return Shared.selectionBlock(state, speed) == nil
end

local function updateMultipliers(state, settings)
    for i = 3, #Shared.options do
        local option = Shared.options[i]
        local multiplier = settings[option.setting]
        if multiplier == nil then multiplier = option.speed end
        if not Shared.isValidMultiplier(multiplier) then
            error("[MultiplayerFastForward] Invalid sandbox multiplier: " .. option.setting)
        end
        if state.multipliers[option.speed] ~= multiplier then
            state.multipliers[option.speed] = multiplier
            state.revision = state.revision + 1
        end
    end
end

local function votingSettings(settings)
    local minimum = settings.MinimumPlayers
    if minimum == nil then minimum = 1 end
    if not Shared.isValidMinimumPlayers(minimum) then
        error("[MultiplayerFastForward] Invalid sandbox minimum player count")
    end
    local adminForce = settings.AdminForce
    if adminForce == nil then adminForce = true end
    if type(adminForce) ~= "boolean" then error("[MultiplayerFastForward] Invalid sandbox admin force setting") end
    return minimum, adminForce
end

function Shared.updateSettings(state)
    local sandboxVars = SandboxVars
    local settings = sandboxVars and sandboxVars.MultiplayerFastForward or {}
    local revision = state.revision
    local minimum, adminForce = votingSettings(settings)
    updateMultipliers(state, settings)
    if state.minimumPlayers ~= minimum or state.adminForce ~= adminForce then
        state.minimumPlayers, state.adminForce = minimum, adminForce
        state.revision = state.revision + 1
    end
    if state.revision ~= revision then Shared.clear(state, state.speed == 0 and 0 or 1) end
end

function Shared.protectionRadiusSquared()
    local sandboxVars = SandboxVars
    local settings = sandboxVars and sandboxVars.MultiplayerFastForward
    if settings and settings.ZombieProtection == false then return end
    local radius = settings and settings.ZombieRadius or 10
    return radius * radius
end

function Shared.findThreatenedPlayer(zombie, positions, radiusSquared)
    if not zombie:isAlive() then return end
    local x, y = zombie:getX(), zombie:getY()
    for i = 1, #positions do
        local position = positions[i]
        local dx, dy = x - position.x, y - position.y
        local distanceSquared = dx * dx + dy * dy
        if distanceSquared <= radiusSquared then return position.player, distanceSquared end
    end
end

function Shared.clear(state, speed)
    speed = speed or 1
    state.selections = {}
    for i = 1, #state.roster do
        state.selections[state.roster[i]] = speed
    end
    state.speed = speed
    state.revision = state.revision + 1
    state.generation = state.generation + 1
    Shared.debugLog("Votes cleared", "generation", state.generation, "players", #state.roster)
end

local function accelerationSelected(state)
    for i = 1, #state.roster do
        if state.selections[state.roster[i]] > 1 then return true end
    end
    return false
end

local function rosterChanged(state, roster)
    if #roster ~= #state.roster then return true end
    for i = 1, #roster do
        if state.selections[roster[i]] == nil then return true end
    end
    return false
end

function Shared.replaceRoster(state, roster, onlinePlayers)
    onlinePlayers = onlinePlayers or #roster
    if state.onlinePlayers ~= onlinePlayers then
        state.onlinePlayers = onlinePlayers
        state.revision = state.revision + 1
    end
    if rosterChanged(state, roster) then
        Shared.debugLog("Living player roster changed", "previous", #state.roster, "current", #roster)
        state.roster = newarray(roster)
        Shared.clear(state)
    end
    if not state.sleepAcceleration and state.onlinePlayers < state.minimumPlayers and accelerationSelected(state) then
        Shared.clear(state)
    end
end

local function unanimousSpeed(state)
    if #state.roster == 0 then
        return 1
    end
    local speed = state.selections[state.roster[1]]
    for i = 2, #state.roster do
        if state.selections[state.roster[i]] ~= speed then
            return 1
        end
    end
    return speed
end

function Shared.select(state, playerId, speed)
    if not Shared.isValidSpeed(speed) or state.selections[playerId] == nil then
        Shared.debugLog("Vote rejected", "player", playerId, "speed", speed, "reason", "invalid speed or unknown player")
        return
    end
    if not Shared.canSelect(state, speed) then
        Shared.debugLog("Vote rejected", "player", playerId, "speed", speed,
            "reason", Shared.selectionBlock(state, speed))
        return
    end
    if state.selections[playerId] ~= speed then
        state.selections[playerId] = speed
        state.speed = unanimousSpeed(state)
        state.revision = state.revision + 1
        Shared.debugLog("Vote accepted", "player", playerId, "speed", speed, "worldSpeed", state.speed, "revision", state.revision)
    else
        Shared.debugLog("Vote unchanged", "player", playerId, "speed", speed)
    end
end

function Shared.forceSelect(state, playerId, speed)
    if not state.adminForce or not Shared.isValidSpeed(speed) or state.selections[playerId] == nil
        or not Shared.canSelect(state, speed) then return end
    Shared.debugLog("Admin forced vote", "player", playerId, "speed", speed)
    Shared.clear(state, speed)
end

function Shared.cancelAcceleration(state, playerId)
    if state.sleepAcceleration or state.speed == 0 or state.selections[playerId] == nil then return end
    if accelerationSelected(state) then
        Shared.debugLog("Acceleration canceled by movement", "player", playerId)
        Shared.clear(state)
    end
end

function Shared.detectZombieThreat(state)
    if not state.zombieThreat then
        state.zombieThreat = true
        state.revision = state.revision + 1
        Shared.debugLog("Zombie threat detected", "worldSpeed", state.speed)
        if state.speed > 1 then
            Shared.clear(state, 0)
        end
    end
end

function Shared.clearZombieThreat(state)
    if state.zombieThreat then
        state.zombieThreat = false
        state.revision = state.revision + 1
        Shared.debugLog("Zombie threat cleared")
    end
end

function Shared.enterSleepAcceleration(state)
    if not state.sleepAcceleration then
        state.sleepAcceleration = true
        Shared.debugLog("Native sleep acceleration started")
        Shared.clear(state)
    end
end

function Shared.leaveSleepAcceleration(state)
    if state.sleepAcceleration then
        state.sleepAcceleration = false
        Shared.debugLog("Native sleep acceleration ended")
        Shared.clear(state)
    end
end

local function voteTotals(state)
    local counts = {}
    for i = 1, #Shared.options do
        counts[Shared.options[i].speed] = 0
    end
    local selections = {}
    for i = 1, #state.roster do
        local playerId = state.roster[i]
        local speed = state.selections[playerId]
        selections[playerId] = speed
        counts[speed] = counts[speed] + 1
    end
    return counts, selections
end

function Shared.snapshot(state)
    local counts, selections = voteTotals(state)
    return {
        speed = state.speed, revision = state.revision, generation = state.generation, counts = counts,
        selections = selections, total = #state.roster,
        zombieThreat = state.zombieThreat, sleepAcceleration = state.sleepAcceleration,
        multipliers = optionMultipliers(state.multipliers), onlinePlayers = state.onlinePlayers,
        minimumPlayers = state.minimumPlayers, adminForce = state.adminForce,
    }
end

function Shared.applySpeed(gameTime, speed, multipliers)
    local multiplier = speed == 0 and Shared.PAUSE_MULTIPLIER or multipliers and Shared.multiplier(speed, multipliers) or speed
    local difference = gameTime:getTrueMultiplier() - multiplier
    local tolerance = multiplier * 0.000001
    if difference < -tolerance or difference > tolerance then
        gameTime:setMultiplier(multiplier)
        Shared.debugLog("World multiplier applied", "speed", speed, "multiplier", multiplier)
    end
end

return Shared
