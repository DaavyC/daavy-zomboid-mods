if not isServer() then return end

local Rules = require "bbd_shared"
local sendServerCommand = sendServerCommand
local sendSyncPlayerFields = sendSyncPlayerFields
local getOnlinePlayers = getOnlinePlayers
local type = type
local error = error
local floor = math.floor
local CharacterTrait = CharacterTrait

local function checkReward(player, kills)
    local traits = player:getCharacterTraits()
    local brave = traits:get(CharacterTrait.BRAVE)
    local desensitized = traits:get(CharacterTrait.DESENSITIZED)
    Rules.check(player, kills)
    if brave ~= traits:get(CharacterTrait.BRAVE) or desensitized ~= traits:get(CharacterTrait.DESENSITIZED) then
        sendSyncPlayerFields(player, 2)
        sendServerCommand(Rules.ID, "Traits", Rules.snapshot(player))
    end
end

local function sendProgress(player)
    local progress = player:getModData()[Rules.ID]
    if not progress then return end
    sendServerCommand(player, Rules.ID, "Progress", {
        playerId = player:getOnlineID(), username = player:getUsername(), progress = progress
    })
end

local function validateReport(report)
    if type(report) ~= "table" then error("[BecomeBraveDesensitized] Missing kill report") end
    local kills = report.kills
    if type(kills) ~= "number" or kills ~= kills or kills < 0 or kills > 2147483647 or kills ~= floor(kills) then
        error("[BecomeBraveDesensitized] Invalid zombie kill count: " .. tostring(kills))
    end
    if type(report.sync) ~= "boolean" then error("[BecomeBraveDesensitized] Invalid sync request") end
end

local function sendRoster(requester)
    local players = getOnlinePlayers()
    for index = 0, players:size() - 1 do
        local player = players:get(index)
        if not player:isDead() then
            sendServerCommand(requester, Rules.ID, "Traits", Rules.snapshot(player))
        end
    end
    sendServerCommand(requester, Rules.ID, "Ready", {
        playerId = requester:getOnlineID(), username = requester:getUsername()
    })
end

local function onClientCommand(module, command, player, report)
    if module ~= Rules.ID or command ~= "Check" then return end
    validateReport(report)
    if not player or player:isDead() then return end
    if Rules.isDebugEnabled() then
        Rules.debugLog("Checking zombie kills", report.kills, "for", player:getUsername())
    end
    local modData = player:getModData()
    local progress = modData[Rules.ID]
    local revision = progress and progress.revision
    checkReward(player, report.kills)
    progress = modData[Rules.ID]
    if report.sync or (progress and progress.revision ~= revision) then sendProgress(player) end
    if report.sync then sendRoster(player) end
end

Events.OnClientCommand.Add(onClientCommand)
