RandomZeds = RandomZeds or {}

local SPEED_TYPE_IDS = {
    sprinter = 1,
    fastShambler = 2,
    shambler = 3,
    crawler = 3,
}
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"
local EXCLUDED_TAG = "RandomZedsExcluded"
local NATIVE_OPTION_NAMES = { "Sight", "Hearing" }
local DEBUG_OPTION_NAME = "RandomZedsMain.Debug"

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

    RandomZeds.debug("Processing loaded zombies: " .. tostring(zombies:size()))
    for zombieIndex = 0, zombies:size() - 1 do
        callback(zombies:get(zombieIndex))
    end
end

function RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
    local speedTypeId = SPEED_TYPE_IDS[speedType]
    local applied
    if speedType == "crawler" then
        applied = zombie:isCrawling()
            and not zombie:isCanWalk()
            and zombie:getSpeedType() == speedTypeId
    else
        applied = speedTypeId ~= nil
            and not zombie:isCrawling()
            and zombie:isCanWalk()
            and zombie:getSpeedType() == speedTypeId
    end

    RandomZeds.debug("Speed type check " .. tostring(speedType)
        .. " result=" .. tostring(applied))
    return applied
end

function RandomZeds.applySprinterSpeed(zombie, multiplier)
    RandomZeds.debug("Applying sprinter speed multiplier=" .. tostring(multiplier))
    zombie:doSprinter()
    multiplier = tonumber(multiplier) or 1.0
    local modData = zombie:getModData()
    local baseSpeed = tonumber(modData[SPRINTER_BASE_SPEED_TAG])
    if not baseSpeed or baseSpeed <= 0 then
        baseSpeed = tonumber(zombie:getSpeedMod()) or 1.0
        if baseSpeed <= 0 then baseSpeed = 1.0 end
    end
    modData[SPRINTER_BASE_SPEED_TAG] = baseSpeed
    zombie:setSpeedMod(baseSpeed * multiplier)
    zombie:setVariable("RandomZedsSprinterSpeedScale", 0.8 * multiplier)
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
