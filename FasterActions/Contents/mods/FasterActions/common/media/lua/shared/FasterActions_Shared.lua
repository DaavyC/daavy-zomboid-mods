local MIN_MULTIPLIER = 0.25
local MAX_MULTIPLIER = 10.0
local INSTANT_MULTIPLIER = -1.0
local INSTANT_DURATION = 0.01
local OPTION_PREFIX = "FasterActions."
local SAFEHOUSE_OPTION_PREFIX = OPTION_PREFIX .. "Safehouse"
local SAFEHOUSE_ENABLED_OPTION = OPTION_PREFIX .. "SafehouseEnabled"
local CORPSE_DRAGGING_SPEED_OPTION = OPTION_PREFIX .. "CorpseDraggingSpeedMultiplier"
local CORPSE_DRAGGING_SPEED_08_VARIABLE = "FasterActionsCorpseSpeed08"
local CORPSE_DRAGGING_SPEED_12_VARIABLE = "FasterActionsCorpseSpeed12"
local CORPSE_DRAGGING_SPEED_161_VARIABLE = "FasterActionsCorpseSpeed161"
local CORPSE_DRAGGING_SPEED_VARIABLE = "FasterActionsCorpseDragSpeed"
local CORPSE_DRAGGING_MIN_MULTIPLIER = 0.25
local CORPSE_DRAGGING_MAX_MULTIPLIER = 10.0
local CORPSE_DRAGGING_SPEED_TOLERANCE = 0.005
local initializedCorpseDraggingPlayers = setmetatable({}, { __mode = "k" })
local activeCorpseDraggingTargets = setmetatable({}, { __mode = "k" })
local SERVER_MECHANIC_DURATION_MARKER = "FasterActionsMechanicDurationAdjusted"
local SAFEHOUSE_ACTION_MARKER = "FasterActionsSafehouseActive"
local ADJUSTED_DURATION_INPUT_MARKER = "FasterActionsAdjustedDurationInput"
local ADJUSTED_DURATION_OUTPUT_MARKER = "FasterActionsAdjustedDurationOutput"
local ADJUSTED_DURATION_SAFEHOUSE_MARKER = "FasterActionsAdjustedDurationSafehouse"
local VISUAL_DURATION_MARKER = "FasterActionsVisualDuration"
local INSTANT_HOOD_OPTION = OPTION_PREFIX .. "InstantHood"
local INSTANT_MAP_OPTION = OPTION_PREFIX .. "InstantMap"
local TAILORING_RECIPE_PATTERNS = { "Clothing", "Trousers", "Tailor", "Sew" }
local RIPPING_ACTION_SCRIPTS = { RipClothing = true, CutClothing = true }
local SAWING_ACTION_SCRIPTS = {
    SawLogs = true,
    SawSmallItemMetal = true,
    SawOffShotgun = true,
    UseBandsaw = true
}
local MECHANIC_ACTION_TYPES = {
    ISConfigHeadlight = true,
    ISDeflateTire = true,
    ISFixVehiclePartAction = true,
    ISInflateTire = true,
    ISInstallVehiclePart = true,
    ISRepairEngine = true,
    ISRepairLightbar = true,
    ISTakeEngineParts = true,
    ISUninstallVehiclePart = true
}
local CLEANING_ACTION_TYPES = {
    ISWashVehicle = true
}
local BUILDING_ACTION_TYPES = {
    ISBuildAction = true,
    ISMultiStageBuild = true
}
local CRAFTING_ACTION_TYPES = {
    ISCraftAction = true,
    ISHandcraftAction = true
}
local EQUIP_ACTION_TYPES = {
    ISClothingExtraAction = true,
    ISEquipHeavyItem = true,
    ISEquipWeaponAction = true,
    ISUnequipAction = true,
    ISWearClothing = true,
    ISAttachItemHotbar = true,
    ISDetachItemHotbar = true
}
local EQUIP_ACTION_PATTERNS = {
    "Equip",
    "Equipment",
    "Unequip",
    "Wear",
    "ClothingExtra",
    "AttachItem",
    "DetachItem"
}

local function debugLog(message)
    if getCore():getDebug() then
        print("[FasterActions] " .. message)
    end
end

local function normalizeCorpseDraggingMultiplier(multiplier)
    if type(multiplier) ~= "number" or multiplier ~= multiplier then
        return 1.0
    end
    return math.max(CORPSE_DRAGGING_MIN_MULTIPLIER,
        math.min(CORPSE_DRAGGING_MAX_MULTIPLIER, multiplier))
end

local function getCorpseDraggingMultiplier()
    local option = getSandboxOptions():getOptionByName(CORPSE_DRAGGING_SPEED_OPTION)
    if not option then
        return 1.0
    end
    local multiplier = tonumber(option:asConfigOption():getValueAsObject())
    return normalizeCorpseDraggingMultiplier(multiplier)
end

local function setCorpseAnimationSpeed(character, variableName, speed)
    character:setVariable(variableName, speed)
end

local function setCorpseTargetAnimationSpeeds(target, multiplier)
    local speed08 = 0.8 * multiplier
    local speed161 = 1.61 * multiplier
    local currentSpeed08 = target:getVariableFloat(CORPSE_DRAGGING_SPEED_08_VARIABLE, -1.0)
    local currentSpeed161 = target:getVariableFloat(CORPSE_DRAGGING_SPEED_161_VARIABLE, -1.0)
    if math.abs(currentSpeed08 - speed08) <= CORPSE_DRAGGING_SPEED_TOLERANCE
            and math.abs(currentSpeed161 - speed161) <= CORPSE_DRAGGING_SPEED_TOLERANCE then
        return
    end
    setCorpseAnimationSpeed(target, CORPSE_DRAGGING_SPEED_08_VARIABLE, speed08)
    setCorpseAnimationSpeed(target, CORPSE_DRAGGING_SPEED_161_VARIABLE, speed161)
end

local function applyCorpseDraggingAnimationSpeeds(player, target, multiplier)
    setCorpseAnimationSpeed(player, CORPSE_DRAGGING_SPEED_08_VARIABLE, 0.8 * multiplier)
    setCorpseAnimationSpeed(player, CORPSE_DRAGGING_SPEED_12_VARIABLE, 1.2 * multiplier)
    local dragBaseSpeed = target:isSkeleton() and 1.2 or 0.8
    setCorpseAnimationSpeed(player, CORPSE_DRAGGING_SPEED_VARIABLE, dragBaseSpeed * multiplier)
    setCorpseTargetAnimationSpeeds(target, multiplier)
end

local function getCorpseDraggingTarget(player)
    if not player:isDraggingCorpse() then
        return nil
    end
    local target = player:getGrapplingTarget()
    if target == nil or not instanceof(target, "IsoZombie") then
        return nil
    end
    return target
end

local function setVanillaCorpseDraggingAnimationSpeeds(player)
    setCorpseAnimationSpeed(player, CORPSE_DRAGGING_SPEED_08_VARIABLE, 0.8)
    setCorpseAnimationSpeed(player, CORPSE_DRAGGING_SPEED_12_VARIABLE, 1.2)
    setCorpseAnimationSpeed(player, CORPSE_DRAGGING_SPEED_VARIABLE, 0.8)
end

local function initializeCorpseDraggingAnimationSpeeds(player)
    if initializedCorpseDraggingPlayers[player] then
        return
    end
    setVanillaCorpseDraggingAnimationSpeeds(player)
    initializedCorpseDraggingPlayers[player] = true
end

local function resetCorpseDraggingAnimationSpeeds(player)
    setVanillaCorpseDraggingAnimationSpeeds(player)
end

local function updateCorpseDraggingAnimationSpeeds(player)
    initializeCorpseDraggingAnimationSpeeds(player)
    local target = getCorpseDraggingTarget(player)
    if target == nil then
        if activeCorpseDraggingTargets[player] ~= nil then
            resetCorpseDraggingAnimationSpeeds(player)
        end
        activeCorpseDraggingTargets[player] = nil
        return
    end
    if activeCorpseDraggingTargets[player] == target then
        return
    end
    applyCorpseDraggingAnimationSpeeds(player, target, getCorpseDraggingMultiplier())
    activeCorpseDraggingTargets[player] = target
end

local function updateRemoteCorpseDraggingAnimationSpeeds(target)
    if not target:isReanimatedForGrappleOnly() or not target:isBeingGrappled() then
        return
    end
    local player = target:getGrappledBy()
    if player == nil or not instanceof(player, "IsoPlayer") then
        return
    end
    local playerSpeed = player:getVariableFloat(CORPSE_DRAGGING_SPEED_08_VARIABLE, 0.8)
    setCorpseTargetAnimationSpeeds(target, normalizeCorpseDraggingMultiplier(playerSpeed / 0.8))
end

local CATEGORY_PATTERNS = {
    { name = "Welding", patterns = { "Weld", "Welding" } },
    { name = "Crafting", patterns = { "Craft", "Recipe", "Research" } },
    {
        name = "Building",
        patterns = {
            "Build",
            "Barricade",
            "Dismantle",
            "Unbarricade",
            "Chop",
            "Dig",
            "Plumb",
            "RemoveGrass",
            "RemoveBush",
            "SmashWindow",
            "Bury",
            "FillGrave",
            "TakeBricks"
        }
    },
    {
        name = "Cleaning",
        patterns = {
            "CleanBlood",
            "CleanGraffiti",
            "WashClothing",
            "WashYourself",
            "WringClothing",
            "DryMyself",
            "ClothingDryer",
            "ClothingWasher",
            "ComboWasherDryer"
        }
    },
    { name = "Tailoring", patterns = { "Tailor", "Tailoring" } },
    { name = "Equip", patterns = EQUIP_ACTION_PATTERNS },
    {
        name = "Inventory",
        patterns = {
            "Inventory",
            "Transfer",
            "Grab",
            "Drop",
            "Pickup",
            "PickUp",
            "Item",
            "Container",
            "Water",
            "OpenCloseLid",
            "DumpContents",
            "Consolidate",
            "AddFluid",
            "DispenserBottle"
        }
    }
}

local INVENTORY_ACTION_TYPES = {
    ISInventoryTransferAction = true,
    ISGrabItemAction = true,
    ISGrabCorpseItem = true,
    ISDropVehicleItemAction = true,
    ISDropWorldItemAction = true,
    ISDropCorpseIntoContainer = true,
    ISOpenContainerTimedAction = true,
    ISOpenCloseLid = true,
    ISDumpContentsAction = true,
    ISConsolidateDrainable = true,
    ISAddFluidFromItemAction = true,
    ISAddTakeDispenserBottle = true,
    ISAttachItemHotbar = true,
    ISDetachItemHotbar = true,
    ISPickUpGroundCoverItem = true,
    ISDestroyStuffAction = true,
    ISDeviceBatteryAction = true,
    ISDeviceMediaAction = true,
    ISEmptyRainBarrelAction = true
}

local function matchesPattern(candidateText, pattern)
    return type(candidateText) == "string" and string.find(candidateText, pattern, 1, true) ~= nil
end

local function getActionType(action)
    return action and action.Type
end

local function isListedAction(action, actionTypes)
    local actionType = getActionType(action)
    return type(actionType) == "string" and actionTypes[actionType] == true
end

local function isWeldingAction(action)
    local actionType = action and action.Type
    if actionType == "ISRemoveBurntVehicle" then
        return true
    end
    if actionType == "ISBarricadeAction" then
        return action.isMetal or action.isMetalBar or false
    end
    if actionType == "ISUnbarricadeAction" then
        if not action.item then
            return false
        end
        local barricade = action.item:getBarricadeForCharacter(action.character)
        return barricade ~= nil and (barricade:isMetal() or barricade:isMetalBar())
    end
    if actionType == "ISBuildAction" then
        return action.item ~= nil and action.item.firstItem == "BlowTorch"
    end
    if actionType == "ISMultiStageBuild" then
        if not action.stage then
            return false
        end
        local stageItems = action.stage:getItemsLua()
        return stageItems ~= nil and (stageItems["Base.BlowTorch"] ~= nil or stageItems["BlowTorch"] ~= nil)
    end
    return false
end

local function getActionScriptName(action)
    if not action or action.Type ~= "ISHandcraftAction" then
        return nil
    end
    local actionScript = action.actionScript
    return actionScript and actionScript:getName()
end

local function isRippingAction(action)
    local actionScriptName = getActionScriptName(action)
    local actionType = getActionType(action)
    return RIPPING_ACTION_SCRIPTS[actionScriptName] == true
        or actionType == "ISCraftAction" and action.recipe ~= nil
        and matchesPattern(action.recipe:getOriginalname(), "Rip")
end

local function isSawingAction(action)
    local actionScriptName = getActionScriptName(action)
    local actionType = getActionType(action)
    return SAWING_ACTION_SCRIPTS[actionScriptName] == true
        or actionType == "ISCraftAction" and action.recipe ~= nil
        and matchesPattern(action.recipe:getOriginalname(), "Saw")
end

local function getCraftRecipeCategory(action)
    local craftRecipe = action and action.craftRecipe
    return craftRecipe and craftRecipe:getCategory()
end

local function isRecipeCategoryAction(action, category)
    return getCraftRecipeCategory(action) == category
end

local function isTailoringAction(action)
    local actionType = getActionType(action)
    if actionType == "ISRemovePatch" or actionType == "ISRepairClothing" then
        return true
    end

    local recipeName
    if actionType == "ISCraftAction" and action.recipe then
        recipeName = action.recipe:getOriginalname()
    elseif actionType == "ISHandcraftAction" and action.craftRecipe then
        recipeName = action.craftRecipe:getName()
    else
        return false
    end

    for _, pattern in ipairs(TAILORING_RECIPE_PATTERNS) do
        if matchesPattern(recipeName, pattern) then
            return true
        end
    end

    return false
end

local function isInventoryAction(action)
    return isListedAction(action, INVENTORY_ACTION_TYPES)
end

local function isEquipAction(action)
    if isListedAction(action, EQUIP_ACTION_TYPES) then
        return true
    end

    local actionType = getActionType(action)
    for _, pattern in ipairs(EQUIP_ACTION_PATTERNS) do
        if matchesPattern(actionType, pattern) then
            return true
        end
    end

    return false
end

local function isMechanicAction(action)
    return isListedAction(action, MECHANIC_ACTION_TYPES)
end

local function isCleaningAction(action)
    return isListedAction(action, CLEANING_ACTION_TYPES)
end

local function isBuildingAction(action)
    return isListedAction(action, BUILDING_ACTION_TYPES)
end

local function isCraftingAction(action)
    return isListedAction(action, CRAFTING_ACTION_TYPES)
end

local CATEGORY_CHECKS = {
    { name = "Equip", matches = isEquipAction },
    { name = "Inventory", matches = isInventoryAction },
    { name = "Mechanic", matches = isMechanicAction },
    { name = "Cleaning", matches = isCleaningAction },
    { name = "Welding", matches = isWeldingAction },
    { name = "Ripping", matches = isRippingAction },
    { name = "Sawing", matches = isSawingAction },
    { name = "Carving", matches = function(action) return isRecipeCategoryAction(action, "Carving") end },
    { name = "Knapping", matches = function(action) return isRecipeCategoryAction(action, "Knapping") end },
    { name = "Tailoring", matches = isTailoringAction },
    { name = "Building", matches = isBuildingAction },
    { name = "Crafting", matches = isCraftingAction }
}

local function isFeatureEnabled(optionName)
    local option = getSandboxOptions():getOptionByName(optionName)
    return option ~= nil and option:asConfigOption():getValueAsObject() == true
end

local function isInstantHoodAction(action)
    if not action then
        return false
    end
    if action.Type == "ISOpenMechanicsUIAction" then
        return action.usedHood ~= nil and isFeatureEnabled(INSTANT_HOOD_OPTION)
    end
    if action.Type ~= "ISOpenVehicleDoor" or not action.part then
        return false
    end
    return action.part:getId() == "EngineDoor" and isFeatureEnabled(INSTANT_HOOD_OPTION)
end

local function isInstantMapAction(action)
    return action ~= nil and action.Type == "ISReadWorldMap" and isFeatureEnabled(INSTANT_MAP_OPTION)
end

local function getCategory(action)
    for _, category in ipairs(CATEGORY_CHECKS) do
        if category.matches(action) then
            return category.name
        end
    end

    local actionType = getActionType(action)
    if type(actionType) ~= "string" then
        return "Other"
    end

    for _, category in ipairs(CATEGORY_PATTERNS) do
        for _, pattern in ipairs(category.patterns) do
            if matchesPattern(actionType, pattern) then
                return category.name
            end
        end
    end

    return "Other"
end

local function normalizeMultiplier(multiplier)
    if type(multiplier) ~= "number" then
        return 1.0
    end
    if multiplier == INSTANT_MULTIPLIER then
        return multiplier
    end
    if multiplier > INSTANT_MULTIPLIER and multiplier < MIN_MULTIPLIER then
        return MIN_MULTIPLIER
    end
    if multiplier < INSTANT_MULTIPLIER or multiplier > MAX_MULTIPLIER then
        return 1.0
    end
    return multiplier
end

local function isCharacterInSafehouse(character)
    local square = character and character:getCurrentSquare()
    return square ~= nil and SafeHouse.getSafeHouse(square) ~= nil
end

local function isActionInSafehouse(action)
    if not action then
        return false
    end

    local captured = action[SAFEHOUSE_ACTION_MARKER]
    if captured ~= nil then
        return captured == true
    end

    return isCharacterInSafehouse(action.character)
end

local function captureSafehouseState(action)
    if not action then
        return
    end

    local active = isCharacterInSafehouse(action.character)
    local cachedState = action[ADJUSTED_DURATION_SAFEHOUSE_MARKER]
    local cachedInput = action[ADJUSTED_DURATION_INPUT_MARKER]
    local cachedOutput = action[ADJUSTED_DURATION_OUTPUT_MARKER]
    if cachedState ~= nil and cachedState ~= active and action.maxTime == cachedOutput then
        action.maxTime = cachedInput
        action[ADJUSTED_DURATION_INPUT_MARKER] = nil
        action[ADJUSTED_DURATION_OUTPUT_MARKER] = nil
        action[ADJUSTED_DURATION_SAFEHOUSE_MARKER] = nil
        action[VISUAL_DURATION_MARKER] = nil
    end

    action[SAFEHOUSE_ACTION_MARKER] = active
end

local function getCategoryMultiplier(category, action)
    local useSafehouseSettings = isActionInSafehouse(action) and isFeatureEnabled(SAFEHOUSE_ENABLED_OPTION)
    local optionPrefix = useSafehouseSettings and SAFEHOUSE_OPTION_PREFIX or OPTION_PREFIX
    local option = getSandboxOptions():getOptionByName(optionPrefix .. category .. "Multiplier")
    if not option then
        return 1.0
    end

    return normalizeMultiplier(tonumber(option:asConfigOption():getValueAsObject()))
end

local function isNativeRemoteAction(action)
    local actionMetatable = action and getmetatable(action)
    return actionMetatable ~= nil and rawget(actionMetatable, "complete") ~= nil
end

local function isInventoryAnimationAction(action)
    local actionType = getActionType(action)
    if actionType == "ISAttachItemHotbar" or actionType == "ISDetachItemHotbar" then
        return true
    end
    return (actionType == "ISEquipWeaponAction" or actionType == "ISUnequipAction") and action.fromHotbar == true
end

local function scaleDurationByMultiplier(actionTime, multiplier)
    if multiplier == INSTANT_MULTIPLIER then
        return INSTANT_DURATION
    end
    if actionTime <= 1 then
        return actionTime
    end
    return math.max(1, actionTime / multiplier)
end

local function getVisualDuration(action, actionTime, multiplier)
    if isInstantHoodAction(action) or isInstantMapAction(action) then
        return INSTANT_DURATION
    end
    return scaleDurationByMultiplier(actionTime, multiplier)
end

local function getAppliedDuration(action, actionTime, category, visualDuration)
    if isClient() and isNativeRemoteAction(action) and not isInventoryAnimationAction(action) then
        return -1
    end
    if isServer() and category == "Mechanic" and isNativeRemoteAction(action) then
        action[SERVER_MECHANIC_DURATION_MARKER] = true
    end
    if (isServer() or isClient()) and (category == "Inventory" or category == "Equip") then
        return actionTime
    end
    return visualDuration
end

local function scaleActionDuration(action, actionTime, category, multiplier)
    if type(actionTime) ~= "number" then
        return actionTime
    end

    local visualDuration = getVisualDuration(action, actionTime, multiplier)
    action[VISUAL_DURATION_MARKER] = visualDuration
    return getAppliedDuration(action, actionTime, category, visualDuration)
end

local function getCachedAdjustedDuration(action, maxTime)
    if not action then
        return nil
    end

    local cachedInput = action[ADJUSTED_DURATION_INPUT_MARKER]
    local cachedDuration = action[ADJUSTED_DURATION_OUTPUT_MARKER]
    local cachedState = action[ADJUSTED_DURATION_SAFEHOUSE_MARKER]
    if cachedState == nil or cachedState ~= isActionInSafehouse(action) then
        return nil
    end
    if cachedInput == maxTime then
        return cachedDuration
    end
    if cachedDuration == maxTime then
        return maxTime
    end
    return nil
end

local function isFinalDurationAdjustment(action, maxTime)
    if maxTime == -1 then
        return false
    end

    local currentMaxTime = action and action.maxTime
    return type(currentMaxTime) ~= "number" or currentMaxTime == maxTime
end

local function installInstantHoodHook()
    require "Vehicles/TimedActions/ISOpenVehicleDoor"

    ISOpenVehicleDoor.FasterActionsOriginalStart = ISOpenVehicleDoor.start
    function ISOpenVehicleDoor:start()
        self:FasterActionsOriginalStart()
        if isInstantHoodAction(self) then
            self.action:setTime(0)
        end
    end
end

local function installAdjustMaxTimeHook()
    require "TimedActions/ISBaseTimedAction"

    ISBaseTimedAction.FasterActionsOriginalBegin = ISBaseTimedAction.begin
    function ISBaseTimedAction:begin()
        captureSafehouseState(self)
        return self:FasterActionsOriginalBegin()
    end

    ISBaseTimedAction.FasterActionsOriginalAdjustMaxTime = ISBaseTimedAction.adjustMaxTime
    function ISBaseTimedAction:adjustMaxTime(maxTime)
        local actionType = getActionType(self) or "<unknown>"
        local cachedDuration = getCachedAdjustedDuration(self, maxTime)
        if cachedDuration ~= nil then
            debugLog("[LuaDuration] type=" .. tostring(actionType) .. " path=cache input="
                .. tostring(maxTime) .. " output=" .. tostring(cachedDuration))
            return cachedDuration
        end

        local adjustedMaxTime = self:FasterActionsOriginalAdjustMaxTime(maxTime)
        if not isFinalDurationAdjustment(self, maxTime) then
            debugLog("[LuaDuration] type=" .. tostring(actionType) .. " path=intermediate input="
                .. tostring(maxTime) .. " output=" .. tostring(adjustedMaxTime))
            return adjustedMaxTime
        end

        local category = getCategory(self)
        local multiplier = getCategoryMultiplier(category, self)
        local scaledDuration = scaleActionDuration(self, adjustedMaxTime, category, multiplier)
        debugLog("[LuaDuration] type=" .. tostring(actionType) .. " category=" .. category
            .. " multiplier=" .. tostring(multiplier) .. " input=" .. tostring(maxTime)
            .. " vanilla=" .. tostring(adjustedMaxTime) .. " output=" .. tostring(scaledDuration))
        self[ADJUSTED_DURATION_INPUT_MARKER] = maxTime
        self[ADJUSTED_DURATION_OUTPUT_MARKER] = scaledDuration
        self[ADJUSTED_DURATION_SAFEHOUSE_MARKER] = isActionInSafehouse(self)
        return scaledDuration
    end
end

installInstantHoodHook()
installAdjustMaxTimeHook()
addVariableToSyncList(CORPSE_DRAGGING_SPEED_08_VARIABLE)
addVariableToSyncList(CORPSE_DRAGGING_SPEED_12_VARIABLE)
addVariableToSyncList(CORPSE_DRAGGING_SPEED_VARIABLE)
Events.OnPlayerUpdate.Add(updateCorpseDraggingAnimationSpeeds)
Events.OnZombieUpdate.Add(updateRemoteCorpseDraggingAnimationSpeeds)
