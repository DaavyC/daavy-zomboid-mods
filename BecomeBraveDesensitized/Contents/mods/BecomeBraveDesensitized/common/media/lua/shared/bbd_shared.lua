local Rules = {}
local CharacterTrait = CharacterTrait
local CharacterProfession = CharacterProfession
local newarray = table.newarray
local print = print
local ZombRand = ZombRand
local floor = math.floor
local max = math.max

Rules.ID = "BecomeBraveDesensitized"

function Rules.isDebugEnabled()
    local options = SandboxVars and SandboxVars[Rules.ID]
    return options ~= nil and options.Debug == true
end

function Rules.debugLog(...)
    if not Rules.isDebugEnabled() then return end
    print("[BecomeBraveDesensitized][Debug]", ...)
end
Rules.fears = newarray(
    { trait = CharacterTrait.COWARDLY, option = "CowardlyExtraKills", blocksBrave = true },
    { trait = CharacterTrait.AGORAPHOBIC, option = "AgoraphobicExtraKills", blocksBrave = true },
    { trait = CharacterTrait.CLAUSTROPHOBIC, option = "ClaustrophobicExtraKills", blocksBrave = true },
    { trait = CharacterTrait.HEMOPHOBIC, option = "FearOfBloodExtraKills", blocksBrave = true }
)
Rules.penalties = newarray(Rules.fears)
Rules.penalties[#Rules.penalties + 1] = { trait = CharacterTrait.PACIFIST, option = "ReluctantFighterExtraKills" }
local benefits = newarray(
    { trait = CharacterTrait.HUNTER, option = "HunterKillReduction" },
    { trait = CharacterTrait.TARGET_SHOOTER, option = "TargetShooterKillReduction" },
    { trait = CharacterTrait.BRAVE, option = "BraveKillReduction", desensitizedOnly = true }
)
local professionOptions = {
    [CharacterProfession.DOCTOR] = "DoctorKillReduction",
    [CharacterProfession.LUMBERJACK] = "LumberjackKillReduction",
    [CharacterProfession.NURSE] = "NurseKillReduction",
    [CharacterProfession.PARK_RANGER] = "ParkRangerKillReduction",
    [CharacterProfession.POLICE_OFFICER] = "PoliceOfficerKillReduction",
    [CharacterProfession.SECURITY_GUARD] = "SecurityGuardKillReduction",
}
Rules.synchronizedTraits = newarray(
    CharacterTrait.BRAVE, CharacterTrait.DESENSITIZED, CharacterTrait.ADRENALINE_JUNKIE
)
for index = 1, #Rules.fears do
    local synchronizedTraits = Rules.synchronizedTraits
    synchronizedTraits[#synchronizedTraits + 1] = Rules.fears[index].trait
end

local function extraRequirement(traits, options)
    local extraKills = 0
    local hasFear = false
    local penalties = Rules.penalties
    for index = 1, #penalties do
        local penalty = penalties[index]
        if traits:get(penalty.trait) then
            hasFear = hasFear or penalty.blocksBrave == true
            local extra = options[penalty.option]
            if extra > 0 then extraKills = extraKills + extra end
        end
    end
    return extraKills, hasFear and options.BraveBlock ~= false
end

local function traitReductions(traits, options)
    local braveReduction, desensitizedReduction = 0, 0
    for index = 1, #benefits do
        local benefit = benefits[index]
        if traits:get(benefit.trait) then
            local reduction = options[benefit.option]
            desensitizedReduction = desensitizedReduction + reduction
            if not benefit.desensitizedOnly then braveReduction = braveReduction + reduction end
        end
    end
    return braveReduction, desensitizedReduction
end

local function adjustedRequirement(base, adjustment)
    if base < 0 then return -1 end
    return max(0, base + adjustment)
end

local function requirements(player, traits, options)
    local extraKills, blocksBrave = extraRequirement(traits, options)
    local braveReduction, desensitizedReduction = traitReductions(traits, options)
    local professionOption = professionOptions[player:getDescriptor():getCharacterProfession()]
    local professionReduction = professionOption and options[professionOption] or 0
    local braveAdjustment = extraKills - braveReduction - professionReduction
    local desensitizedAdjustment = extraKills - desensitizedReduction - professionReduction
    return {
        braveMinimum = adjustedRequirement(options.BraveMinKills, braveAdjustment),
        braveTarget = adjustedRequirement(options.BraveKills, braveAdjustment),
        desensitizedMinimum = adjustedRequirement(options.DesensitizedMinKills, desensitizedAdjustment),
        desensitizedTarget = adjustedRequirement(options.DesensitizedKills, desensitizedAdjustment),
        blocksBrave = blocksBrave,
    }
end

function Rules.reward(player, kills)
    local traits = player:getCharacterTraits()
    if traits:get(CharacterTrait.DESENSITIZED) then return end
    local options = SandboxVars[Rules.ID]
    local limits = requirements(player, traits, options)
    if limits.desensitizedTarget >= 0 and kills >= limits.desensitizedTarget then
        return CharacterTrait.DESENSITIZED
    end
    if limits.braveTarget >= 0 and kills >= limits.braveTarget and not limits.blocksBrave and not traits:get(CharacterTrait.BRAVE) then
        return CharacterTrait.BRAVE
    end
end

function Rules.chance(minimum, maximum, kills)
    if minimum < 0 or maximum < 0 or minimum >= maximum or kills <= minimum then return 0 end
    if kills >= maximum then return 0.1 end
    local position = (kills - minimum) / (maximum - minimum)
    return 0.1 * position * position
end

local function earlyChances(player, kills)
    local options = SandboxVars[Rules.ID]
    local traits = player:getCharacterTraits()
    local limits = requirements(player, traits, options)
    local desensitizedChance = Rules.chance(limits.desensitizedMinimum, limits.desensitizedTarget, kills)
    local braveChance = 0
    if not limits.blocksBrave and not traits:get(CharacterTrait.BRAVE) then
        braveChance = Rules.chance(limits.braveMinimum, limits.braveTarget, kills)
    end
    return braveChance, desensitizedChance
end

local function trackProgress(player, kills, options)
    local modData = player:getModData()
    local progress = modData[Rules.ID]
    if not options.EarlyTraits then
        if progress and progress.active then
            progress.active = false
            progress.revision = progress.revision + 1
        end
        return
    end
    if not progress or not progress.active or progress.hour ~= nil then
        modData[Rules.ID] = {
            active = true, kills = progress and progress.active and progress.kills or kills,
            revision = progress and progress.revision + 1 or 1
        }
    end
end

local function rollRewards(player, kills, attempts)
    local braveChance, desensitizedChance = earlyChances(player, kills)
    if braveChance == 0 and desensitizedChance == 0 then return end
    for index = 1, attempts do
        local roll = ZombRand(1000000) / 1000000
        Rules.debugLog("Early trait attempt", kills, "roll", roll, "chances", braveChance, desensitizedChance)
        if roll < desensitizedChance then
            Rules.grant(player, CharacterTrait.DESENSITIZED)
            return
        elseif roll < braveChance then
            Rules.grant(player, CharacterTrait.BRAVE)
            return
        end
    end
end

local function attemptReward(player, kills, options)
    local progress = player:getModData()[Rules.ID]
    local interval = options.KillsPerAttempt
    local attempts = floor((kills - progress.kills) / interval)
    if attempts <= 0 then return end
    progress.kills = progress.kills + attempts * interval
    progress.revision = progress.revision + 1
    rollRewards(player, kills, attempts)
end

function Rules.check(player, kills)
    if player:getCharacterTraits():get(CharacterTrait.DESENSITIZED) then return end
    local options = SandboxVars[Rules.ID]
    trackProgress(player, kills, options)
    local reward = Rules.reward(player, kills)
    if reward then
        Rules.grant(player, reward)
        return
    end
    if not options.EarlyTraits then return end
    attemptReward(player, kills, options)
end

function Rules.grant(player, reward)
    local traits = player:getCharacterTraits()
    local fears = Rules.fears
    for index = 1, #fears do traits:remove(fears[index].trait) end
    if reward == CharacterTrait.DESENSITIZED then
        traits:remove(CharacterTrait.BRAVE)
        traits:remove(CharacterTrait.ADRENALINE_JUNKIE)
    end
    traits:add(reward)
    Rules.debugLog("Granted", reward, "to", player:getUsername())
end

function Rules.snapshot(player)
    local traits = player:getCharacterTraits()
    local synchronizedTraits = Rules.synchronizedTraits
    local snapshot = { playerId = player:getOnlineID(), username = player:getUsername(), traits = {} }
    for index = 1, #synchronizedTraits do
        snapshot.traits[index] = traits:get(synchronizedTraits[index])
    end
    return snapshot
end

function Rules.applySnapshot(player, snapshot)
    local traits = player:getCharacterTraits()
    local synchronizedTraits = Rules.synchronizedTraits
    for index = 1, #synchronizedTraits do
        local trait = synchronizedTraits[index]
        local enabled = snapshot.traits[index]
        if traits:get(trait) ~= enabled then traits:set(trait, enabled) end
    end
end

return Rules
