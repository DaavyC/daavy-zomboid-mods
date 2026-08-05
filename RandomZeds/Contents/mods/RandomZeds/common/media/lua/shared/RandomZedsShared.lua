RandomZeds = RandomZeds or {}

function RandomZeds.applySprinterSpeed(zombie, multiplier)
    zombie:setVariable("RandomZedsSprinterSpeedScale", 0.8 * multiplier)
    if multiplier == 1 then return end

    local speedMod = tonumber(zombie:getSpeedMod()) or 1.0
    if speedMod <= 0 then speedMod = 1.0 end

    zombie:setSpeedMod(speedMod * multiplier)
    local spriteDef = zombie:getSpriteDef()
    if spriteDef then
        spriteDef:setFrameSpeedPerFrame(0.24 * speedMod * multiplier)
    end
end

function RandomZeds.setCrawlerState(zombie, crawling)
    if zombie:isCrawling() ~= crawling then
        zombie:toggleCrawling()
    end

    zombie:setCrawler(crawling)
    zombie:setCanWalk(not crawling)

    if not crawling then
        zombie:setOnFloor(false)
        zombie:setFallOnFront(false)
    end
end

function RandomZeds.setZombieWalkType(zombie, speedType)
    local walkType = speedType == "sprinter" and "sprint1"
        or speedType == "shambler" and "slow1"
        or "1"

    zombie:setWalkType(walkType)
    zombie:setSpeedTypeFromWalkType()
end
