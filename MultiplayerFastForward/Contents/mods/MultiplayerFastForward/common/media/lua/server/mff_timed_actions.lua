if not isServer() then return end

local require = require
require "TimedActions/ISBaseTimedAction"
local Shared = require "mff_shared"
local ISBaseTimedAction = ISBaseTimedAction
local getServerTimeMills = GameTime.getServerTimeMills
local newarray = table.newarray
local actions = newarray()
local actionLookup = {}
local methodHooks = {}
local EVENTS_PER_TICK = 128
local BACKLOG_DELAY_MS = 1000
local nextActionIndex = 1
local speed = 1
local timestamp = getServerTimeMills()
local elapsed = 0
local unpausedElapsed = 0
local TimedActions = {}

local function advanceClock()
    local now = getServerTimeMills()
    elapsed = elapsed + (now - timestamp) * speed
    if speed ~= 0 then unpausedElapsed = unpausedElapsed + now - timestamp end
    timestamp = now
end

local function actionProgress(nativeAction, original)
    local record = actionLookup[nativeAction]
    if not record then return original(nativeAction) end
    if record.completing then return 1 end
    if record.duration == 0 then return speed == 0 and 0 or 1 end
    local delta = getServerTimeMills() - timestamp
    if record.duration < 0 then
        local activeTime = unpausedElapsed + (speed ~= 0 and delta or 0) - record.startedUnpaused
        return activeTime / Shared.ACTION_TIMEOUT_MS
    end
    local actionElapsed = elapsed + delta * speed - record.startedAt
    return actionElapsed < record.duration and actionElapsed / record.duration or 1
end

local function forceCompleteAction(nativeAction, original)
    local record = actionLookup[nativeAction]
    if record then record.completing = true end
    original(nativeAction)
end

local function hookNativeMethods(record)
    local methods = getmetatable(record.native).__index
    local originals = methodHooks[methods]
    if not originals then
        originals = { progress = methods.getProgress, complete = methods.forceComplete }
        methodHooks[methods] = originals
        methods.getProgress = function(nativeAction) return actionProgress(nativeAction, originals.progress) end
        methods.forceComplete = function(nativeAction) forceCompleteAction(nativeAction, originals.complete) end
    end
    record.nativeComplete = originals.complete
end

local function nextAnimationIndex(record)
    local animations = record.animations
    local deadline = record.duration >= 0 and record.startedAt + record.duration or elapsed
    local nextIndex
    for i = 1, #animations do
        local due = animations[i].nextTime
        if due <= deadline and (not nextIndex or due < animations[nextIndex].nextTime) then
            nextIndex = i
        end
    end
    return nextIndex
end

local function setNativeDelay(record, delay)
    local duration = timestamp - record.startedTimestamp + delay
    duration = duration - duration % 1
    if record.currentDuration ~= duration then
        record.currentDuration = duration
        record.native:setDuration(duration)
    end
end

local function updateInfiniteAction(record, worldSpeed)
    local remaining = Shared.ACTION_TIMEOUT_MS - (unpausedElapsed - record.startedUnpaused)
    if worldSpeed == 0 and remaining < BACKLOG_DELAY_MS then remaining = BACKLOG_DELAY_MS end
    setNativeDelay(record, remaining)
end

local function updateAction(record, worldSpeed)
    if record.completing then return end
    if record.duration < 0 then return updateInfiniteAction(record, worldSpeed) end
    local remaining = record.duration - (elapsed - record.startedAt)
    local pending = nextAnimationIndex(record)
    if remaining <= 0 and not pending and worldSpeed ~= 0 then
        record.completing = true
        record.nativeComplete(record.native)
        return
    end
    local multiplier = worldSpeed == 0 and Shared.PAUSE_MULTIPLIER or worldSpeed
    local delay = remaining / multiplier
    if (pending or worldSpeed == 0) and delay < BACKLOG_DELAY_MS then delay = BACKLOG_DELAY_MS end
    setNativeDelay(record, delay)
end

local function startAction(record, action)
    advanceClock()
    record.native = action.netAction
    record.playerId = action.character:getOnlineID()
    record.startedAt = elapsed
    record.startedTimestamp = timestamp
    record.startedUnpaused = unpausedElapsed
    record.currentDuration = record.duration
    record.active = true
    record.completing = false
    record.animations = newarray()
    actionLookup[record.native] = record
    hookNativeMethods(record)
    updateAction(record, speed)
    actions[#actions + 1] = record
end

local function wrapTiming(action, record)
    local adjustMaxTime, serverStart = action.adjustMaxTime, action.serverStart
    action.adjustMaxTime = function(self, duration)
        local adjusted = adjustMaxTime(self, duration)
        if not record.active then record.duration = adjusted == -1 and -1 or adjusted * 20 end
        return adjusted
    end
    action.serverStart = function(self)
        startAction(record, self)
        if serverStart then return serverStart(self) end
    end
end

local function wrapCompletion(action, record)
    local serverStop, complete = action.serverStop, action.complete
    action.serverStop = function(self)
        record.active = false
        if serverStop then return serverStop(self) end
    end
    action.complete = function(self)
        record.active = false
        return complete(self)
    end
end

local originalNew = ISBaseTimedAction.new
function ISBaseTimedAction:new(character)
    local action = originalNew(self, character)
    if action.complete then
        local record = {}
        wrapTiming(action, record)
        wrapCompletion(action, record)
    end
    return action
end

local function dispatchAnimation(record, index)
    local animations = record.animations
    local animation = animations[index]
    if animation.repeating then
        animation.nextTime = animation.duration > 0 and animation.nextTime + animation.duration or elapsed + 1
    else
        for i = index, #animations - 1 do animations[i] = animations[i + 1] end
        animations[#animations] = nil
    end
    record.native:animEvent(animation.event, animation.parameter)
end

local function updateAnimations()
    local budget, idle = EVENTS_PER_TICK, 0
    while speed ~= 0 and budget > 0 and idle < #actions do
        if nextActionIndex > #actions then nextActionIndex = 1 end
        local record = actions[nextActionIndex]
        nextActionIndex = nextActionIndex + 1
        local index = record.active and not record.completing and nextAnimationIndex(record)
        if index and record.animations[index].nextTime <= elapsed then
            budget, idle = budget - 1, 0
            dispatchAnimation(record, index)
        else
            idle = idle + 1
        end
    end
end

local function updateActions(worldSpeed, playerVotes)
    local index = 1
    while index <= #actions do
        local record = actions[index]
        if playerVotes[record.playerId] == nil then record.active = false end
        if record.active then
            updateAction(record, worldSpeed)
            index = index + 1
        else
            actionLookup[record.native] = nil
            actions[index] = actions[#actions]
            actions[#actions] = nil
        end
    end
end

local function addAnimation(record, animation)
    advanceClock()
    animation.nextTime = elapsed + animation.duration
    local animations = record.animations
    animations[#animations + 1] = animation
    updateAction(record, speed)
end

local originalEmulate = emulateAnimEvent
function emulateAnimEvent(nativeAction, duration, event, parameter)
    local record = actionLookup[nativeAction]
    if not record then return originalEmulate(nativeAction, duration, event, parameter) end
    addAnimation(record, { duration = duration, event = event, parameter = parameter, repeating = true })
end

local originalEmulateOnce = emulateAnimEventOnce
function emulateAnimEventOnce(nativeAction, duration, event, parameter)
    local record = actionLookup[nativeAction]
    if not record then return originalEmulateOnce(nativeAction, duration, event, parameter) end
    addAnimation(record, { duration = duration, event = event, parameter = parameter })
end

function TimedActions.update(worldSpeed, playerVotes)
    advanceClock()
    speed = worldSpeed
    updateActions(worldSpeed, playerVotes)
end

function TimedActions.tick()
    advanceClock()
    if speed ~= 0 then updateAnimations() end
    advanceClock()
    for i = 1, #actions do
        local record = actions[i]
        if record.active then updateAction(record, speed) end
    end
end

return TimedActions
