RandomZeds = RandomZeds or {}

local SPEED_TYPE_IDS = {
    sprinter = 1,
    fastShambler = 2,
    shambler = 3,
    crawler = 3,
}
local SPEED_TAG = "RandomZedsSpeedType"
local SPRINTER_MULTIPLIER_TAG = "RandomZedsSprinterMultiplier"
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local SPRINTER_SPEED_TOLERANCE = 0.005
local EXCLUDED_TAG = "RandomZedsExcluded"
local NATIVE_OPTION_NAMES = { "Sight", "Hearing" }
local DEBUG_OPTION_NAME = "RandomZedsMain.Debug"
local stateApplications = setmetatable({}, { __mode = "k" })

function RandomZeds.isExcluded(zombie)
    local modData = zombie and zombie:getModData()
    return modData and modData[EXCLUDED_TAG]
end

function RandomZeds.isDebugEnabled()
    local options = getSandboxOptions and getSandboxOptions()
    local option = options and options:getOptionByName(DEBUG_OPTION_NAME)
    return option and option:getValue() == true
end

function RandomZeds.debug(message)
    if RandomZeds.isDebugEnabled() then
        print("[Random Zeds] " .. tostring(message))
    end
end

function RandomZeds.beginStateApplication(zombie)
    if zombie then stateApplications[zombie] = true end
end

function RandomZeds.finishStateApplication(zombie)
    if zombie then stateApplications[zombie] = nil end
end

function RandomZeds.isStateApplicationInProgress(zombie)
    return zombie ~= nil and stateApplications[zombie] == true
end

function RandomZeds.isValidOnlineID(onlineID)
    onlineID = tonumber(onlineID)
    return onlineID ~= nil and onlineID ~= -1
end

function RandomZeds.forceVanillaPerceptionDefaults()
    RandomZeds.debug("Restoring vanilla perception defaults")
    local options = getSandboxOptions()
    local sight = options:getOptionByName("ZombieLore.Sight")
    local hearing = options:getOptionByName("ZombieLore.Hearing")
    if sight then sight:setValue(2) end
    if hearing then hearing:setValue(2) end
end

function RandomZeds.applyZombieNativeStats(zombie, sight, hearing)
    RandomZeds.debug("Applying native stats sight=" .. tostring(sight)
        .. " hearing=" .. tostring(hearing))
    local values = { tonumber(sight), tonumber(hearing) }
    if not values[1] and not values[2] then
        RandomZeds.debug("Native stats skipped: no values")
        return false
    end

    local options = getSandboxOptions()
    local nativeOptions = {}
    local previous = {}
    for index, name in ipairs(NATIVE_OPTION_NAMES) do
        local option = options:getOptionByName("ZombieLore." .. name)
        if not option then
            RandomZeds.debug("Native stats failed: option missing " .. name)
            return false
        end
        nativeOptions[index] = option
        previous[index] = option:getValue()
    end

    local applied, errorMessage = pcall(function()
        for index, option in ipairs(nativeOptions) do
            if values[index] ~= nil then option:setValue(values[index]) end
        end
        zombie:DoZombieStats()
    end)
    for index, option in ipairs(nativeOptions) do
        pcall(function() option:setValue(previous[index]) end)
    end
    RandomZeds.debug("Native stats result=" .. tostring(applied)
        .. (errorMessage and " error=" .. tostring(errorMessage) or "")
        .. " using release-safe DoZombieStats")
    return applied
end

function RandomZeds.forEachLoadedZombie(callback)
    local cell = getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then
        RandomZeds.debug("No loaded zombie list")
        return
    end

    for zombieIndex = 0, zombies:size() - 1 do
        callback(zombies:get(zombieIndex))
    end
end

function RandomZeds.forEachLoadedZombieWithinBudget(cursorState, budgetMs, callback)
    local cell = getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then
        cursorState.index = 0
        return 0
    end

    local count = zombies:size()
    if count <= 0 then
        cursorState.index = 0
        return 0
    end

    local index = tonumber(cursorState.index) or 0
    if index < 0 or index >= count then index = 0 end
    local startedAt = getTimestampMs()
    local budget = tonumber(budgetMs) or 1
    local processed = 0
    repeat
        callback(zombies:get(index))
        processed = processed + 1
        index = index + 1
        if index >= count then index = 0 end
    until processed >= count
        or (processed > 0 and getTimestampMs() - startedAt >= budget)

    cursorState.index = index
    return processed
end

local function getVariableBoolean(zombie, name)
    local ok, value = pcall(function() return zombie:getVariableBoolean(name) end)
    return ok and value == true
end

function RandomZeds.isSprinterMotionExpected(zombie)
    if not zombie or zombie:isDead() or zombie:isCrawling()
            or zombie:getCurrentActionContextStateName() == "getup" then
        return false
    end

    return zombie:getTarget() ~= nil
        or getVariableBoolean(zombie, "bMoving")
        or getVariableBoolean(zombie, "bPathfind")
        or getVariableBoolean(zombie, "bMovingNetwork")
        or zombie:isMoving()
end

function RandomZeds.isRemoteSprinterSpeedScaled(zombie, expectedSpeed)
    if not zombie or not expectedSpeed or not zombie.isRemoteZombie
            or not zombie:isRemoteZombie() then
        return false
    end

    local speedMod = tonumber(zombie:getSpeedMod())
    return speedMod ~= nil
        and speedMod >= 10
        and math.abs(speedMod / 1000 - expectedSpeed)
            <= SPRINTER_SPEED_TOLERANCE
end

local function callZombieMethod(zombie, methodName, ...)
    local method = zombie and zombie[methodName]
    if type(method) ~= "function" then return false end
    local argument = ...
    local hasArgument = select("#", ...) > 0
    local ok = pcall(function()
        if not hasArgument then
            method(zombie)
        else
            method(zombie, argument)
        end
    end)
    return ok
end

function RandomZeds.repairRemoteSprinterType(zombie)
    if not zombie or not zombie.isRemoteZombie or not zombie:isRemoteZombie() then
        return false
    end

    local changed = false
    local walkType = tostring(zombie:getWalkType() or "")
    if walkType:sub(1, 6) ~= "sprint" then
        if not callZombieMethod(zombie, "setWalkType", "sprint") then
            return false
        end
        changed = true
    end
    if zombie:getSpeedType() ~= SPEED_TYPE_IDS.sprinter then
        if not callZombieMethod(zombie, "setSpeedTypeFromWalkType") then
            return false
        end
        changed = true
    end
    if not zombie:isCanWalk() then
        if not callZombieMethod(zombie, "setCanWalk", true) then
            return false
        end
        changed = true
    end
    return changed
end

function RandomZeds.reconcileSprinterMotion(zombie)
    if not RandomZeds.isSprinterMotionExpected(zombie) then
        return false
    end

    local changed = false
    if not zombie:isRunning() then
        zombie:setRunning(true)
        changed = true
    end
    local movementIntent = zombie:getTarget() ~= nil
        or getVariableBoolean(zombie, "bPathfind")
        or getVariableBoolean(zombie, "bMovingNetwork")
        or zombie:isMoving()
    if not getVariableBoolean(zombie, "bMoving") and movementIntent then
        zombie:setVariable("bMoving", true)
        changed = true
    end
    return changed
end

function RandomZeds.isZombieSpeedTypeApplied(zombie, speedType, checkMotion)
    local speedTypeId = SPEED_TYPE_IDS[speedType]
    local applied = zombie ~= nil
        and speedTypeId ~= nil
        and not zombie:isDead()
        and zombie:getSquare() ~= nil

    local modData = applied and zombie:getModData() or nil
    if applied and speedType == "sprinter"
            and (not modData or modData[SPEED_TAG] ~= "sprinter") then
        applied = false
    end

    if applied and speedType == "crawler" then
        applied = zombie:isCrawling()
            and not zombie:isCanWalk()
            and zombie:getSpeedType() == speedTypeId
    elseif applied then
        applied = not zombie:isCrawling()
            and zombie:isCanWalk()
            and zombie:getSpeedType() == speedTypeId
    end

    if applied and speedType == "sprinter" then
        local baseSpeed = tonumber(modData[SPRINTER_BASE_SPEED_TAG])
        local multiplier = tonumber(modData[SPRINTER_MULTIPLIER_TAG])
        local speedMod = tonumber(zombie:getSpeedMod())
        local expectedSpeed = nil
        if baseSpeed and multiplier then
            expectedSpeed = baseSpeed * multiplier
        end
        local nativeSpeedMatches = expectedSpeed ~= nil
            and speedMod ~= nil
            and math.abs(speedMod - expectedSpeed) <= SPRINTER_SPEED_TOLERANCE
        local remoteSpeedIsScaled = RandomZeds.isRemoteSprinterSpeedScaled(
            zombie, expectedSpeed)
        applied = nativeSpeedMatches and not remoteSpeedIsScaled

        local walkType = tostring(zombie:getWalkType() or "")
        applied = applied and walkType:sub(1, 6) == "sprint"
        if applied and checkMotion and RandomZeds.isSprinterMotionExpected(zombie) then
            applied = zombie:isRunning()
                and getVariableBoolean(zombie, "bMoving")
        end
    end

    RandomZeds.debug("Speed type check " .. tostring(speedType)
        .. " result=" .. tostring(applied))
    return applied
end

function RandomZeds.applySprinterSpeed(zombie, multiplier)
    RandomZeds.debug("Applying sprinter speed multiplier=" .. tostring(multiplier))
    multiplier = tonumber(multiplier) or 1.0
    local modData = zombie:getModData()
    local baseSpeed = tonumber(modData[SPRINTER_BASE_SPEED_TAG])
    if not baseSpeed or baseSpeed <= 0 then
        baseSpeed = tonumber(zombie:getSpeedMod()) or 1.0
        if zombie.isRemoteZombie and zombie:isRemoteZombie()
                and baseSpeed >= 10 then
            baseSpeed = baseSpeed / 1000
        end
        if baseSpeed <= 0 then baseSpeed = 1.0 end
    end
    local expectedSpeed = baseSpeed * multiplier
    local remote = zombie.isRemoteZombie and zombie:isRemoteZombie()
    local nativeTypeValid = zombie:getSpeedType() == SPEED_TYPE_IDS.sprinter
        and not zombie:isCrawling()
        and zombie:isCanWalk()
        and tostring(zombie:getWalkType() or ""):sub(1, 6) == "sprint"
    if remote then
        RandomZeds.repairRemoteSprinterType(zombie)
    elseif not nativeTypeValid then
        zombie:doSprinter()
    end
    modData[SPEED_TAG] = "sprinter"
    modData[SPRINTER_MULTIPLIER_TAG] = multiplier
    modData[SPRINTER_BASE_SPEED_TAG] = baseSpeed
    zombie:setSpeedMod(expectedSpeed)
    zombie:setVariable("RandomZedsSprinterSpeedScale", 0.8 * multiplier)
    if not zombie:isDead() then
        zombie:setRunning(true)
    end
end

function RandomZeds.setCrawlerState(zombie, crawling)
    RandomZeds.debug("Setting crawler state crawling=" .. tostring(crawling))
    if zombie:isCrawling() ~= crawling then
        zombie:toggleCrawling()
    end
    zombie:setCanWalk(not crawling)
    if not crawling then
        zombie:setOnFloor(false)
        zombie:setFallOnFront(false)
    end
end

function RandomZeds.applyZombieSpeedType(zombie, speedType, multiplier)
    RandomZeds.debug("Applying speed type=" .. tostring(speedType) .. " multiplier=" .. tostring(multiplier))
    if speedType == "crawler" then
        RandomZeds.setCrawlerState(zombie, true)
        zombie:doCrawlerSpeed(3)
        return true
    end

    if speedType ~= "sprinter"
            and speedType ~= "fastShambler"
            and speedType ~= "shambler" then
        RandomZeds.debug("Speed type failed: unknown type " .. tostring(speedType))
        return false
    end

    RandomZeds.setCrawlerState(zombie, false)
    if speedType == "sprinter" then
        RandomZeds.applySprinterSpeed(zombie, multiplier)
    elseif speedType == "fastShambler" then
        zombie:doFastShambler()
    else
        zombie:doShambler()
    end
    return true
end
