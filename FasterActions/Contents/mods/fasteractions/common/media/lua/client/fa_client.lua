require "ui/fa_sandbox_settings"
require "TimedActions/ISBaseTimedAction"

local ISBaseTimedAction = ISBaseTimedAction
local UIManager = UIManager
local getNumActivePlayers = getNumActivePlayers
local getSpecificPlayer = getSpecificPlayer
local isClient = isClient
local instanceof = instanceof
local min = math.min
local max = math.max
local core = getCore()
local VISUAL_DURATION_MARKER = "FasterActionsVisualDuration"
local ANIMATION_PROGRESS_MARKER = "FasterActionsAnimationProgress"
local REMOTE_PROGRESS_MARKER = "FasterActionsRemoteProgress"

local function getProgressDuration(action, nativeAction)
    local client = isClient()
    if client and action[REMOTE_PROGRESS_MARKER] then
        local duration = action[VISUAL_DURATION_MARKER]
        if duration and duration > 0 then
            return duration
        end
    end
    local duration = nativeAction:getTime()
    if duration == -1 and not client and action[ANIMATION_PROGRESS_MARKER] then
        return action[VISUAL_DURATION_MARKER]
    end
    return duration
end

local function getActionProgress(action)
    local nativeAction = action.action
    if nativeAction:isForceComplete() then
        return 1
    end
    local duration = getProgressDuration(action, nativeAction)
    if not duration or duration <= 0 then
        return nil
    end
    local progress = nativeAction:getCurrentTime() / duration
    return max(0, min(progress, 1))
end

local originalGetJobDelta = ISBaseTimedAction.getJobDelta
function ISBaseTimedAction:getJobDelta()
    local progress = getActionProgress(self)
    if progress ~= nil then
        return progress
    end
    return originalGetJobDelta(self)
end

local function installInventoryProgressHook()
    require "TimedActions/ISInventoryTransferAction"
    local ISInventoryTransferAction = ISInventoryTransferAction
    local originalUpdate = ISInventoryTransferAction.update
    function ISInventoryTransferAction:update()
        originalUpdate(self)
        if not self.action:isForceComplete() then
            self.item:setJobDelta(self:getJobDelta())
        end
    end
end

local function installProgressBarDefaults()
    require "Foraging/ISForageAction"
    require "TimedActions/ISFitnessAction"
    ISForageAction.useProgressBar = false
    ISFitnessAction.useProgressBar = false
end

local function getCurrentAction(player)
    local actions = player:getCharacterActions()
    if actions:isEmpty() then
        return nil
    end
    local nativeAction = actions:get(0)
    if not instanceof(nativeAction, "LuaTimedActionNew") or not nativeAction:isStarted() then
        return nil
    end
    return nativeAction:getTable()
end

local function refreshPlayerProgressBar(player)
    local action = getCurrentAction(player)
    if not action then
        return
    end
    if action.useProgressBar == false or not (core:isOptionProgressBar() or action.forceProgressBar) then
        return
    end
    local progress = getActionProgress(action)
    if progress ~= nil then
        UIManager.trySetProgressBarValue(player:getPlayerNum(), progress)
    end
end

local function refreshProgressBars()
    for playerIndex = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerIndex)
        if player and player:isLocalPlayer() then
            refreshPlayerProgressBar(player)
        end
    end
end

Events.OnGameStart.Add(installInventoryProgressHook)
Events.OnGameStart.Add(installProgressBarDefaults)
Events.OnTick.Add(refreshProgressBars)
