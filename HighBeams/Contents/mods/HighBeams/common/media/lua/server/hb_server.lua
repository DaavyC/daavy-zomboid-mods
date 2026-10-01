local Beams = require "hb_shared"
local type = type

local function onClientCommand(module, command, player, args)
    if module ~= "HighBeams" or command ~= "selectMode" then return end
    if type(args) ~= "table" or type(args.high) ~= "boolean" or type(args.vehicle) ~= "number" then
        Beams.debugLog("Mode rejected", "invalid command arguments")
        return
    end
    local vehicle = player:getVehicle()
    if not vehicle or vehicle:getId() ~= args.vehicle or not vehicle:isDriver(player) then
        Beams.debugLog("Mode rejected", "sender is not the requested vehicle's driver", "vehicle", args.vehicle)
        return
    end
    if not Beams.anchor(vehicle) or not vehicle:hasHeadlights() then return end
    Beams.selectMode(vehicle, args)
end

Events.OnClientCommand.Add(onClientCommand)
Beams.debugLog("Server command handler installed")
