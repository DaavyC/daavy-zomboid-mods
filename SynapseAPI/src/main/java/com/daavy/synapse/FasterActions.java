package com.daavy.synapse;

import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.vm.KahluaTable;
import zombie.SandboxOptions;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;
import zombie.characters.IsoPlayer;
import zombie.core.BuildAction;
import zombie.core.Core;
import zombie.core.NetTimedAction;
import zombie.core.Transaction;
import zombie.debug.DebugLog;
import zombie.iso.areas.SafeHouse;
import zombie.network.GameServer;
import zombie.network.packets.ItemTransactionPacket;
import zombie.ui.UIManager;

import java.util.Map;
import java.util.WeakHashMap;

@Exposer.LuaClass(name = "Synapse.API.FasterActions")
public final class FasterActions {
    private static final float MIN_MULTIPLIER = 0.25F;
    private static final float MAX_MULTIPLIER = 10.0F;
    private static final float INSTANT_MULTIPLIER = -1.0F;
    private static final float MIN_DURATION_MS = 1.0F;
    private static final String LUA_MECHANIC_DURATION_MARKER = "FasterActionsMechanicDurationAdjusted";
    private static final String LUA_SAFEHOUSE_MARKER = "FasterActionsSafehouseActive";
    private static final String VISUAL_DURATION_MARKER = "FasterActionsVisualDuration";
    private static final String LOG_PREFIX = "[FasterActions]";
    private static final String[] INVENTORY_EXCLUDED_PATTERNS = { "Animal", "Hutch", "Recipe", "Plumb" };
    private static final String[] EQUIP_ACTION_PATTERNS = {
        "Equip",
        "Equipment",
        "Unequip",
        "Wear",
        "ClothingExtra",
        "AttachItem",
        "DetachItem"
    };
    private static final String[] INVENTORY_ACTION_PATTERNS = {
        "Inventory",
        "Transfer",
        "Grab",
        "Drop",
        "Pickup",
        "PickUp",
        "Container",
        "Water",
        "OpenCloseLid",
        "DumpContents",
        "Consolidate",
        "AddFluid",
        "DispenserBottle",
        "DeviceBattery",
        "DeviceMedia",
        "DestroyStuff",
        "EmptyRainBarrel"
    };
    private static final String[] MECHANIC_ACTION_TYPES = {
        "ISDeflateTire",
        "ISFixVehiclePartAction",
        "ISInflateTire",
        "ISInstallVehiclePart",
        "ISRepairEngine",
        "ISRepairLightbar",
        "ISTakeEngineParts",
        "ISUninstallVehiclePart"
    };
    private static final Map<LuaTimedActionNew, ProgressLogState> PROGRESS_LOG_STATE = new WeakHashMap<>();
    private static final Map<Transaction, Boolean> TRANSACTION_SAFEHOUSES = new WeakHashMap<>();
    private static final ThreadLocal<LuaTimedActionNew> CLIENT_ACTION_UPDATE = new ThreadLocal<>();

    private enum DurationCategory {
        INVENTORY("FasterActions.InventoryMultiplier", "FasterActions.SafehouseInventoryMultiplier"),
        EQUIP("FasterActions.EquipMultiplier", "FasterActions.SafehouseEquipMultiplier"),
        BUILDING("FasterActions.BuildingMultiplier", "FasterActions.SafehouseBuildingMultiplier"),
        MECHANIC("FasterActions.MechanicMultiplier", "FasterActions.SafehouseMechanicMultiplier");

        private final String optionName;
        private final String safehouseOptionName;

        DurationCategory(String optionName, String safehouseOptionName) {
            this.optionName = optionName;
            this.safehouseOptionName = safehouseOptionName;
        }
    }

    private FasterActions() {
    }

    private static final class ProgressLogState {
        private boolean progressBarDisabledLogged;
        private boolean noDurationLogged;
        private float maxTime = Float.NaN;
        private float progressDuration = Float.NaN;
        private int bucket = -1;

        private void log(LuaTimedActionNew action, float progress, String path, float progressDuration) {
            int progressBucket = Math.min(4, (int)(progress * 4.0F));
            if (Float.compare(maxTime, action.maxTime) == 0
                    && Float.compare(this.progressDuration, progressDuration) == 0
                    && bucket == progressBucket) {
                return;
            }
            debugLog(LOG_PREFIX + "[Progress] type=" + getLuaActionType(action) + " path=" + path
                    + " current=" + action.currentTime + " max=" + action.maxTime
                    + " duration=" + progressDuration + " value=" + progress + " bucket=" + progressBucket);
            maxTime = action.maxTime;
            this.progressDuration = progressDuration;
            bucket = progressBucket;
        }
    }

    private static final class ProgressDuration {
        private final float value;
        private final String source;

        private ProgressDuration(float value, String source) {
            this.value = value;
            this.source = source;
        }
    }

    private static float normalizeMultiplier(float multiplier) {
        if (!Float.isFinite(multiplier)) {
            return 1.0F;
        }
        if (multiplier == INSTANT_MULTIPLIER) {
            return multiplier;
        }
        if (multiplier > INSTANT_MULTIPLIER && multiplier < MIN_MULTIPLIER) {
            return MIN_MULTIPLIER;
        }
        if (multiplier < INSTANT_MULTIPLIER || multiplier > MAX_MULTIPLIER) {
            return 1.0F;
        }
        return multiplier;
    }

    private static float getSandboxMultiplier(DurationCategory category) {
        return getSandboxMultiplier(category.optionName);
    }

    private static float getSafehouseMultiplier(DurationCategory category) {
        return getSandboxMultiplier(category.safehouseOptionName);
    }

    private static float getSandboxMultiplier(String optionName) {
        SandboxOptions.SandboxOption option = SandboxOptions.instance.getOptionByName(optionName);
        if (option == null) {
            return 1.0F;
        }

        Object rawValue = option.asConfigOption().getValueAsObject();
        if (!(rawValue instanceof Number number)) {
            return 1.0F;
        }
        return normalizeMultiplier(number.floatValue());
    }

    private static float adjustDuration(float duration, float multiplier) {
        if (duration <= 0.0F) {
            return duration;
        }
        if (multiplier == INSTANT_MULTIPLIER) {
            return MIN_DURATION_MS;
        }
        return Math.max(MIN_DURATION_MS, duration / multiplier);
    }

    public static float adjustInventoryDuration(float duration) {
        return adjustInventoryDuration(duration, "Lua", null);
    }

    public static float adjustBuildingDuration(float duration) {
        return adjustBuildingDuration(duration, "Lua", null);
    }

    public static float adjustMechanicDuration(float duration) {
        return adjustMechanicDuration(duration, "Lua", null);
    }

    public static float adjustTransactionDuration(float duration) {
        return adjustInventoryDuration(duration, "Transaction", "ItemTransaction");
    }

    public static float adjustTransactionDuration(Transaction transaction, float duration) {
        return Boolean.TRUE.equals(TRANSACTION_SAFEHOUSES.get(transaction))
                ? adjustSafehouseCategoryDuration(DurationCategory.INVENTORY, duration,
                    "Transaction", "ItemTransaction")
                : adjustCategoryDuration(DurationCategory.INVENTORY, duration,
                    "Transaction", "ItemTransaction");
    }

    public static void captureTransactionSafehouse(Transaction transaction, IsoPlayer player) {
        TRANSACTION_SAFEHOUSES.put(transaction, isInSafehouse(player));
    }

    public static float adjustBuildActionDuration(float duration) {
        return adjustBuildingDuration(duration, "BuildAction", "BuildAction");
    }

    public static float adjustBuildActionDuration(BuildAction action, float duration) {
        IsoPlayer player = getBuildActionPlayer(action);
        return isInSafehouse(player)
                ? adjustSafehouseCategoryDuration(DurationCategory.BUILDING, duration,
                    "BuildAction", "BuildAction")
                : adjustCategoryDuration(DurationCategory.BUILDING, duration,
                    "BuildAction", "BuildAction");
    }

    private static float adjustInventoryDuration(float duration, String source, String actionType) {
        return adjustCategoryDuration(DurationCategory.INVENTORY, duration, source, actionType);
    }

    private static float adjustBuildingDuration(float duration, String source, String actionType) {
        return adjustCategoryDuration(DurationCategory.BUILDING, duration, source, actionType);
    }

    private static float adjustMechanicDuration(float duration, String source, String actionType) {
        return adjustCategoryDuration(DurationCategory.MECHANIC, duration, source, actionType);
    }

    private static float adjustCategoryDuration(DurationCategory category, float duration,
            String source, String actionType) {
        float multiplier = getSandboxMultiplier(category);
        float adjusted = adjustDuration(duration, multiplier);
        logDuration(source, actionType, duration, adjusted, multiplier);
        return adjusted;
    }

    private static float adjustSafehouseCategoryDuration(DurationCategory category, float duration,
            String source, String actionType) {
        float multiplier = getSafehouseMultiplier(category);
        float adjusted = adjustDuration(duration, multiplier);
        logDuration("Safehouse/" + source, actionType, duration, adjusted, multiplier);
        return adjusted;
    }

    public static float adjustNetTimedActionDuration(NetTimedAction action, float duration) {
        String actionType = action.type;
        DurationCategory category = getNetTimedActionCategory(action);
        if (category != null) {
            if (isActionInSafehouse(action)) {
                return adjustSafehouseCategoryDuration(category, duration, "NetTimedAction", actionType);
            }
            return adjustCategoryDuration(category, duration, "NetTimedAction", actionType);
        }
        debugLog(LOG_PREFIX + "[NetTimedAction] type=" + actionType
                + " input=" + duration + " output=" + duration + " path=unchanged");
        return duration;
    }

    public static long adjustInventoryAnimationEventDelay(NetTimedAction action, long delay) {
        if (isServerInventoryAction(action)) {
            return adjustInventoryEventDelay(action, delay);
        }
        debugLog(LOG_PREFIX + "[Animation] type=" + action.type
                + " input=" + delay + " output=" + delay + " path=unchanged");
        return delay;
    }

    private static void logDuration(String source, String actionType, float input, float output,
            float multiplier) {
        debugLog(LOG_PREFIX + "[Duration] source=" + source + " type=" + actionType
                + " multiplier=" + multiplier + " input=" + input + " output=" + output);
    }

    private static void debugLog(String message) {
        if (Core.getInstance().getDebug()) {
            DebugLog.log(message);
        }
    }

    private static boolean isInventoryActionType(String actionType) {
        return hasText(actionType)
                && !containsAny(actionType, INVENTORY_EXCLUDED_PATTERNS)
                && !isEquipActionType(actionType)
                && containsAny(actionType, INVENTORY_ACTION_PATTERNS);
    }

    private static boolean isEquipActionType(String actionType) {
        return hasText(actionType) && containsAny(actionType, EQUIP_ACTION_PATTERNS);
    }

    private static boolean isItemTransactionAction(String actionType) {
        return "ISInventoryTransferAction".equals(actionType) || "ISGrabItemAction".equals(actionType);
    }

    private static boolean isMechanicActionType(String actionType) {
        return hasText(actionType) && equalsAny(actionType, MECHANIC_ACTION_TYPES);
    }

    private static boolean hasText(String value) {
        return value != null && !value.isEmpty();
    }

    private static boolean containsAny(String actionType, String[] patterns) {
        for (String pattern : patterns) {
            if (actionType.contains(pattern)) {
                return true;
            }
        }
        return false;
    }

    private static boolean equalsAny(String actionType, String[] actionTypes) {
        for (String candidate : actionTypes) {
            if (candidate.equals(actionType)) {
                return true;
            }
        }
        return false;
    }

    private static boolean hasLuaAdjustedMechanicDuration(NetTimedAction action) {
        KahluaTable luaAction = action.action;
        return luaAction != null && Boolean.TRUE.equals(luaAction.rawget(LUA_MECHANIC_DURATION_MARKER));
    }

    private static boolean isServerInventoryAction(NetTimedAction action) {
        return GameServer.server && isInventoryActionType(action.type)
                && !isItemTransactionAction(action.type);
    }

    private static boolean isServerEquipAction(NetTimedAction action) {
        return GameServer.server && isEquipActionType(action.type);
    }

    private static DurationCategory getNetTimedActionCategory(NetTimedAction action) {
        if (isServerEquipAction(action)) {
            return DurationCategory.EQUIP;
        }
        if (isServerInventoryAction(action)) {
            return DurationCategory.INVENTORY;
        }
        if (GameServer.server && isMechanicActionType(action.type)
                && !hasLuaAdjustedMechanicDuration(action)) {
            return DurationCategory.MECHANIC;
        }
        return null;
    }

    private static long adjustInventoryEventDelay(NetTimedAction action, long delay) {
        if (delay <= 0L) {
            return delay;
        }
        DurationCategory category = getNetTimedActionCategory(action);
        if (category != DurationCategory.INVENTORY && category != DurationCategory.EQUIP) {
            debugLog(LOG_PREFIX + "[Animation] type=" + action.type
                    + " input=" + delay + " output=" + delay + " path=unchanged");
            return delay;
        }
        float adjustedDelay = isActionInSafehouse(action)
                ? adjustSafehouseCategoryDuration(category, delay, "AnimEvent", action.type)
                : adjustCategoryDuration(category, delay, "AnimEvent", action.type);
        long result = Math.max(1L, Math.round(adjustedDelay));
        debugLog(LOG_PREFIX + "[Animation] type=" + action.type
                + " input=" + delay + " output=" + result + " path="
                + (category == DurationCategory.EQUIP ? "equip" : "inventory"));
        return result;
    }

    private static boolean isInSafehouse(IsoPlayer player) {
        return player != null && player.getCurrentSquare() != null
                && SafeHouse.getSafeHouse(player.getCurrentSquare()) != null;
    }

    private static IsoPlayer getActionPlayer(NetTimedAction action) {
        if (action == null || action.action == null) {
            return null;
        }

        Object rawPlayer = action.action.rawget("character");
        return rawPlayer instanceof IsoPlayer player ? player : null;
    }

    private static boolean isActionInSafehouse(NetTimedAction action) {
        if (action == null || action.action == null) {
            return false;
        }

        Object marker = action.action.rawget(LUA_SAFEHOUSE_MARKER);
        if (marker instanceof Boolean safehouse) {
            return safehouse;
        }
        return isInSafehouse(getActionPlayer(action));
    }

    private static IsoPlayer getBuildActionPlayer(BuildAction action) {
        if (action == null || action.item == null) {
            return null;
        }

        Object rawPlayer = action.item.rawget("player");
        return rawPlayer instanceof IsoPlayer player ? player : null;
    }

    private static ProgressLogState getProgressLogState(LuaTimedActionNew action) {
        return PROGRESS_LOG_STATE.computeIfAbsent(action, ignored -> new ProgressLogState());
    }

    private static String getLuaActionType(LuaTimedActionNew action) {
        KahluaTable table = action.getTable();
        Object type = table == null ? null : table.rawget("Type");
        return type == null ? "<unknown>" : String.valueOf(type);
    }

    private static boolean isProgressBarVisible(LuaTimedActionNew action) {
        return (Core.getInstance().isOptionProgressBar() || action.forceProgressBar)
                && action.useProgressBar;
    }

    private static void logDisabledProgress(ProgressLogState state, String actionType) {
        if (!state.progressBarDisabledLogged) {
            debugLog(LOG_PREFIX + "[Progress] type=" + actionType + " skipped=disabled");
            state.progressBarDisabledLogged = true;
        }
    }

    private static void logMissingProgressDuration(ProgressLogState state,
            String actionType, float maxTime, String source) {
        if (!state.noDurationLogged) {
            debugLog(LOG_PREFIX + "[Progress] type=" + actionType
                    + " skipped=maxTime=" + maxTime + " source=" + source);
            state.noDurationLogged = true;
        }
    }

    private static void updateProgressBar(LuaTimedActionNew action, IsoPlayer player,
            ProgressLogState state, String actionType) {
        ProgressDuration duration = getProgressDuration(action);

        if (duration.value <= 0.0F) {
            logMissingProgressDuration(state, actionType, action.maxTime, duration.source);
            return;
        }

        state.noDurationLogged = false;
        float progress = getProgress(action.currentTime, duration.value);
        UIManager.getProgressBar(player.getIndex()).setValue(progress);
        state.log(action, progress, duration.source, duration.value);
    }

    private static ProgressDuration getProgressDuration(LuaTimedActionNew action) {
        float visualDuration = getVisualProgressDuration(action);
        if (visualDuration > 0.0F) {
            return new ProgressDuration(visualDuration, "updated-visual");
        }
        return new ProgressDuration(action.maxTime, "updated-local");
    }

    private static float getProgress(float currentTime, float duration) {
        return Math.max(0.0F, Math.min(currentTime / duration, 1.0F));
    }

    public static void beginClientActionUpdate(LuaTimedActionNew action) {
        CLIENT_ACTION_UPDATE.remove();
        if (action.chr instanceof IsoPlayer player && player.isLocalPlayer()) {
            CLIENT_ACTION_UPDATE.set(action);
        }
    }

    public static float adjustInventoryItemProgress(float progress) {
        LuaTimedActionNew action = CLIENT_ACTION_UPDATE.get();
        if (action == null || Float.compare(progress, action.delta) != 0) {
            return progress;
        }
        ProgressDuration duration = getProgressDuration(action);
        return duration.value > 0.0F
                ? getProgress(action.currentTime, duration.value)
                : progress;
    }

    public static void finishClientActionUpdate(LuaTimedActionNew action) {
        CLIENT_ACTION_UPDATE.remove();
        refreshClientProgressBar(action);
    }

    private static void refreshClientActionProgress(LuaTimedActionNew action) {
        if (!(action.chr instanceof IsoPlayer player) || !player.isLocalPlayer()) {
            return;
        }
        if (action.isForceComplete()) {
            action.delta = 1.0F;
            return;
        }
        ProgressDuration duration = getProgressDuration(action);
        if (duration.value > 0.0F) {
            action.delta = getProgress(action.currentTime, duration.value);
        }
    }

    private static float getVisualProgressDuration(LuaTimedActionNew action) {
        KahluaTable actionTable = action.getTable();
        if (actionTable == null) {
            return 0.0F;
        }

        Object rawDuration = actionTable.rawget(VISUAL_DURATION_MARKER);
        if (!(rawDuration instanceof Number duration)) {
            return 0.0F;
        }
        float progressDuration = duration.floatValue();
        return Float.isFinite(progressDuration) && progressDuration > 0.0F
                ? progressDuration
                : 0.0F;
    }

    private static boolean updateCompletedProgress(LuaTimedActionNew action, IsoPlayer player,
            ProgressLogState state) {
        if (!action.isForceComplete()) {
            return false;
        }
        action.delta = 1.0F;
        UIManager.getProgressBar(player.getIndex()).setValue(1.0F);
        state.log(action, 1.0F, "force-complete", action.maxTime);
        return true;
    }

    public static void refreshClientProgressBar(LuaTimedActionNew action) {
        if (!(action.chr instanceof IsoPlayer player) || !player.isLocalPlayer()) {
            return;
        }

        refreshClientActionProgress(action);
        refreshLocalPlayerProgressBar(action, player);
    }

    private static void refreshLocalPlayerProgressBar(LuaTimedActionNew action, IsoPlayer player) {
        ProgressLogState state = getProgressLogState(action);
        String actionType = getLuaActionType(action);
        if (!isProgressBarVisible(action)) {
            logDisabledProgress(state, actionType);
            return;
        }

        if (updateCompletedProgress(action, player, state)) {
            return;
        }

        updateProgressBar(action, player, state, actionType);
    }

    @Patch(className = "zombie.core.Transaction", methodName = "getDuration")
    public static class TransactionDurationPatch {
        @Patch.OnExit
        public static void exit(@Patch.This Transaction transaction,
                @Patch.Return(readOnly = false) float duration) {
            if (GameServer.server) {
                duration = FasterActions.adjustTransactionDuration(transaction, duration);
            }
        }
    }

    @Patch(className = "zombie.core.TransactionManager", methodName = "isConsistent")
    public static class TransactionPlayerPatch {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(value = 5) ItemTransactionPacket transaction,
            @Patch.Argument(value = 6) IsoPlayer player) {
            if (GameServer.server && transaction != null && player != null) {
                FasterActions.captureTransactionSafehouse(transaction, player);
            }
        }
    }

    @Patch(className = "zombie.core.NetTimedAction", methodName = "getDuration")
    public static class NetTimedActionDurationPatch {
        @Patch.OnExit
        public static void exit(@Patch.This NetTimedAction action, @Patch.Return(readOnly = false) float duration) {
            duration = FasterActions.adjustNetTimedActionDuration(action, duration);
        }
    }

    @Patch(className = "zombie.inventory.InventoryItem", methodName = "setJobDelta")
    public static class InventoryItemProgressPatch {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(value = 0, readOnly = false) float progress) {
            progress = FasterActions.adjustInventoryItemProgress(progress);
        }
    }

    @Patch(className = "zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName = "update")
    public static class ClientProgressBarPatch {
        @Patch.OnEnter
        public static void enter(@Patch.This LuaTimedActionNew action) {
            FasterActions.beginClientActionUpdate(action);
        }

        @Patch.OnExit
        public static void exit(@Patch.This LuaTimedActionNew action) {
            FasterActions.finishClientActionUpdate(action);
        }
    }

    @Patch(className = "zombie.core.BuildAction", methodName = "getDuration")
    public static class BuildActionDurationPatch {
        @Patch.OnExit
        public static void exit(@Patch.This BuildAction action,
                @Patch.Return(readOnly = false) float duration) {
            if (GameServer.server) {
                duration = FasterActions.adjustBuildActionDuration(action, duration);
            }
        }
    }

    @Patch(className = "zombie.network.server.AnimEventEmulator", methodName = "create")
    public static class InventoryAnimationEventPatch {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) NetTimedAction action,
                @Patch.Argument(value = 1, readOnly = false) long delay) {
            delay = FasterActions.adjustInventoryAnimationEventDelay(action, delay);
        }
    }
}
