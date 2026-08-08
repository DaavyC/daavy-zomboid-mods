RandomZeds = RandomZeds or {}

local SPEED_TYPE_IDS = {
    sprinter = 1,
    fastShambler = 2,
    shambler = 3,
    crawler = 3,
}
local SPRINTER_BASE_SPEED_TAG = "RandomZedsSprinterBaseSpeed"

function RandomZeds.isZombieSpeedTypeApplied(zombie, speedType)
    if speedType == "crawler" then
        return zombie:isCrawling()
            and not zombie:isCanWalk()
            and zombie:getSpeedType() == SPEED_TYPE_IDS.crawler
    end

    return SPEED_TYPE_IDS[speedType] ~= nil
        and not zombie:isCrawling()
        and zombie:isCanWalk()
        and zombie:getSpeedType() == SPEED_TYPE_IDS[speedType]
end

function RandomZeds.applySprinterSpeed(zombie, multiplier)
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
    if speedType == "sprinter" then
        RandomZeds.setCrawlerState(zombie, false)
    elseif speedType == "fastShambler" then
        RandomZeds.setCrawlerState(zombie, false)
        zombie:doFastShambler()
    elseif speedType == "shambler" then
        RandomZeds.setCrawlerState(zombie, false)
        zombie:doShambler()
    elseif speedType == "crawler" then
        RandomZeds.setCrawlerState(zombie, true)
        zombie:doCrawlerSpeed(3)
    else
        return false
    end

    if speedType == "sprinter" then
        RandomZeds.applySprinterSpeed(zombie, multiplier)
    end
    return true
end
