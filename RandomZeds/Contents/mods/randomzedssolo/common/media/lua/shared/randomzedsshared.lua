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

function RandomZeds.forceVanillaPerceptionDefaults()
    RandomZeds.debug("Restoring vanilla perception defaults")
    local options = getSandboxOptions()
    local sight = options:getOptionByName("ZombieLore.Sight")
    local hearing = options:getOptionByName("ZombieLore.Hearing")
    if sight then sight:setValue(2) end
    if hearing then hearing:setValue(2) end
end

local function restoreNativeOptionValues(nativeOptions, previousNativeValues)
    for index, option in ipairs(nativeOptions) do
        local restored, restoreError = pcall(function()
            option:setValue(previousNativeValues[index])
        end)
        if not restored then
            print("[Random Zeds] Native option restore failed: " .. tostring(restoreError))
        end
    end
end

function RandomZeds.applyZombieNativeStats(zombie, sight, hearing)
    RandomZeds.debug("Applying native stats sight=" .. tostring(sight)
        .. " hearing=" .. tostring(hearing))
    local nativeStatValues = { tonumber(sight), tonumber(hearing) }
    if not nativeStatValues[1] and not nativeStatValues[2] then
        RandomZeds.debug("Native stats skipped: no values")
        return false
    end

    local options = getSandboxOptions()
    local nativeOptions = {}
    local previousNativeValues = {}
    for index, name in ipairs(NATIVE_OPTION_NAMES) do
        local option = options:getOptionByName("ZombieLore." .. name)
        if not option then
            RandomZeds.debug("Native stats failed: option missing " .. name)
            return false
        end
        nativeOptions[index] = option
        previousNativeValues[index] = option:getValue()
    end

    local statsApplied, statsError = pcall(function()
        for index, option in ipairs(nativeOptions) do
            if nativeStatValues[index] ~= nil then
                option:setValue(nativeStatValues[index])
            end
        end
        zombie:DoZombieStats()
    end)
    restoreNativeOptionValues(nativeOptions, previousNativeValues)
    if not statsApplied then
        print("[Random Zeds] Native stats application failed: " .. tostring(statsError))
    end
    RandomZeds.debug("Native stats result=" .. tostring(statsApplied)
        .. (statsError and " error=" .. tostring(statsError) or "")
        .. " using release-safe DoZombieStats")
    return statsApplied
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
    return zombie:getVariableBoolean(name) == true
end

function RandomZeds.isSprinterMotionExpected(zombie)
    if not zombie or zombie:isDead() or zombie:isCrawling()
            or zombie:getCurrentActionContextStateName() == "getup" then
        return false
    end

    return zombie:getTarget() ~= nil
        or getVariableBoolean(zombie, "bMoving")
        or getVariableBoolean(zombie, "bPathfind")
        or zombie:isMoving()
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
        or zombie:isMoving()
    if not getVariableBoolean(zombie, "bMoving") and movementIntent then
        zombie:setVariable("bMoving", true)
        changed = true
    end
    return changed
end

local function hasExpectedNativeSpeedType(zombie, speedType, speedTypeId)
    if speedType == "crawler" then
        return zombie:isCrawling()
            and not zombie:isCanWalk()
            and zombie:getSpeedType() == speedTypeId
    end
    return not zombie:isCrawling()
        and zombie:isCanWalk()
        and zombie:getSpeedType() == speedTypeId
end

local function hasExpectedSprinterSpeed(zombie, modData, includeMotionCheck)
    local baseSpeed = tonumber(modData[SPRINTER_BASE_SPEED_TAG])
    local multiplier = tonumber(modData[SPRINTER_MULTIPLIER_TAG])
    local speedMod = tonumber(zombie:getSpeedMod())
    local expectedSpeed = baseSpeed and multiplier
        and baseSpeed * multiplier
    local nativeSpeedMatches = expectedSpeed ~= nil
        and speedMod ~= nil
        and math.abs(speedMod - expectedSpeed) <= SPRINTER_SPEED_TOLERANCE
    if not nativeSpeedMatches then return false end

    local walkType = tostring(zombie:getWalkType() or "")
    if walkType:sub(1, 6) ~= "sprint" then return false end
    if includeMotionCheck and RandomZeds.isSprinterMotionExpected(zombie) then
        return zombie:isRunning() and getVariableBoolean(zombie, "bMoving")
    end
    return true
end

function RandomZeds.isZombieSpeedTypeApplied(zombie, speedType, includeMotionCheck)
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

    if applied then
        applied = hasExpectedNativeSpeedType(zombie, speedType, speedTypeId)
    end

    if applied and speedType == "sprinter" then
        applied = hasExpectedSprinterSpeed(zombie, modData, includeMotionCheck)
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
        if baseSpeed <= 0 then baseSpeed = 1.0 end
    end
    local expectedSpeed = baseSpeed * multiplier
    local nativeTypeValid = zombie:getSpeedType() == SPEED_TYPE_IDS.sprinter
        and not zombie:isCrawling()
        and zombie:isCanWalk()
        and tostring(zombie:getWalkType() or ""):sub(1, 6) == "sprint"
    if not nativeTypeValid then
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
