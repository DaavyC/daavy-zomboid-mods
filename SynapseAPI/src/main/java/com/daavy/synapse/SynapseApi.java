package com.daavy.synapse;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

import me.zed_0xff.zombie_buddy.Exposer;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoZombie;
import zombie.core.skinnedmodel.advancedanimation.AnimLayer;
import zombie.core.skinnedmodel.advancedanimation.AnimNode;
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;

@Exposer.LuaClass(name = "Synapse.API")
public final class SynapseApi {
    private static final int API_VERSION = 1;
    private static final String SPEED_TYPE_SPRINTER = "sprinter";
    private static final String SPEED_TYPE_FAST_SHAMBLER = "fastShambler";
    private static final String SPEED_TYPE_SHAMBLER = "shambler";
    private static final String SPEED_TYPE_CRAWLER = "crawler";
    private static final int SPRINTER_SPEED_TYPE = 1;
    private static final int FAST_SHAMBLER_SPEED_TYPE = 2;
    private static final int SHAMBLER_SPEED_TYPE = 3;
    private static final int CRAWLER_SPEED_TYPE = 3;
    private static final String SPRINTER_WALK_PREFIX = "sprint";
    private static final String SHAMBLER_WALK_PREFIX = "slow";
    private static final String CRAWLER_WALK_VARIANT = "ZombieWalk";
    private static final float HEALTH_MINIMUM = 0.5F;
    private static final float HEALTH_MAXIMUM = 3.8F;

    private SynapseApi() {
    }

    public static int getApiVersion() {
        return API_VERSION;
    }

    public static void applyAnimationSpeed(
            IsoZombie zombie,
            String variable,
            float speedScale) {
        Objects.requireNonNull(zombie, "zombie");
        Objects.requireNonNull(variable, "variable");
        AdvancedAnimator animator = requireAnimator(zombie);
        validateAnimationSpeed(variable, speedScale);
        applyAnimationSpeed(zombie, animator, variable, speedScale);
    }

    private static AdvancedAnimator requireAnimator(IsoZombie zombie) {
        AdvancedAnimator animator = zombie.getAdvancedAnimator();
        if (animator == null) {
            throw new IllegalStateException("Zombie animator is required");
        }
        return animator;
    }

    private static void applyAnimationSpeed(
            IsoZombie zombie,
            AdvancedAnimator animator,
            String variable,
            float speedScale) {
        List<AnimNode> updatedNodes = findActiveSpeedNodes(animator, variable);
        zombie.setVariable(variable, speedScale);
        animator.updateSpeedScale(variable, speedScale);
        restoreSpeedScaleVariables(updatedNodes, variable);
    }

    private static void validateAnimationSpeed(String variable, float speedScale) {
        if (variable.isBlank()) {
            throw new IllegalArgumentException("Animation variable must not be blank");
        }
        if (!Float.isFinite(speedScale) || speedScale <= 0.0F) {
            throw new IllegalArgumentException(
                    "Animation speed must be positive and finite");
        }
    }

    private static List<AnimNode> findActiveSpeedNodes(
            AdvancedAnimator animator, String variable) {
        AnimLayer rootLayer = animator.getRootLayer();
        if (rootLayer == null) {
            return List.of();
        }

        List<AnimNode> matchingNodes = new ArrayList<>();
        for (LiveAnimNode liveNode : rootLayer.getLiveAnimNodes()) {
            AnimNode sourceNode = liveNode.getSourceNode();
            if (liveNode.isActive() && sourceNode != null
                    && variable.equals(sourceNode.speedScaleVariable)) {
                matchingNodes.add(sourceNode);
            }
        }
        return matchingNodes;
    }

    private static void restoreSpeedScaleVariables(
            List<AnimNode> nodes, String variable) {
        for (AnimNode node : nodes) {
            node.speedScale = variable;
        }
    }

    public static void applyZombieFeatures(
            IsoZombie zombie,
            int cognitionProfile,
            int strengthProfile,
            int memoryProfile) {
        Objects.requireNonNull(zombie, "zombie");
        int cognition = mapCognitionProfile(cognitionProfile);
        int strength = mapStrengthProfile(strengthProfile);
        int memory = mapMemoryProfile(memoryProfile);

        applyFeatureValues(zombie, cognition, strength, memory);
    }

    public static void applyZombieState(IsoZombie zombie, KahluaTable table) {
        Objects.requireNonNull(zombie, "zombie");
        ZombieState state = ZombieState.parse(table);
        validateApplicationDependencies(zombie, state);
        applyMovement(zombie, state);
        applyAttributes(zombie, state);
        applyAnimation(zombie, state);
    }

    private static void validateApplicationDependencies(
            IsoZombie zombie, ZombieState state) {
        if (state.animationVariable() != null) {
            requireAnimator(zombie);
        }
        if (SPEED_TYPE_SPRINTER.equals(state.speedType())
                && zombie.isRemoteZombie()
                && zombie.getWalkType() == null) {
            throw new IllegalStateException("Zombie walk type is required");
        }
    }

    private static void applyMovement(IsoZombie zombie, ZombieState state) {
        String speedType = state.speedType();
        if (SPEED_TYPE_CRAWLER.equals(speedType)) {
            applyCrawlerMovement(zombie);
            return;
        }
        boolean wasCrawling = zombie.isCrawling();
        applyStandingMovement(zombie);
        applyStandingSpeedType(zombie, state, wasCrawling);
    }

    private static void applyStandingSpeedType(
            IsoZombie zombie,
            ZombieState state,
            boolean wasCrawling) {
        String speedType = state.speedType();
        switch (speedType) {
            case SPEED_TYPE_SPRINTER -> applySprinterMovement(zombie, state);
            case SPEED_TYPE_FAST_SHAMBLER -> {
                if (wasCrawling || !hasStandingSpeedType(zombie, FAST_SHAMBLER_SPEED_TYPE)) {
                    zombie.doFastShambler();
                }
            }
            case SPEED_TYPE_SHAMBLER -> {
                if (wasCrawling || !hasStandingSpeedType(zombie, SHAMBLER_SPEED_TYPE)) {
                    zombie.doShambler();
                }
            }
        }
    }

    private static void applyCrawlerMovement(IsoZombie zombie) {
        boolean crawlerMovementReady = zombie.isCrawling()
                && !zombie.isCanWalk()
                && zombie.getSpeedType() == CRAWLER_SPEED_TYPE;
        zombie.setCrawler(true);
        zombie.setCanWalk(false);
        zombie.setOnFloor(true);
        zombie.walkVariant = CRAWLER_WALK_VARIANT;
        if (!crawlerMovementReady) {
            zombie.doCrawlerSpeed(CRAWLER_SPEED_TYPE);
        }
    }

    private static void applyStandingMovement(IsoZombie zombie) {
        if (zombie.isCrawling()) {
            zombie.setCrawler(false);
            zombie.setKnockedDown(false);
            zombie.setStaggerBack(false);
            zombie.setFallOnFront(false);
            zombie.setOnFloor(false);
        }
        zombie.setCanWalk(true);
    }

    private static void applySprinterMovement(IsoZombie zombie, ZombieState state) {
        if (zombie.isRemoteZombie()) {
            repairRemoteSprinterType(zombie);
        } else if (!hasSprinterMovement(zombie)) {
            zombie.doSprinter();
        }
        zombie.setSpeedMod(state.speedMod());
        if (!zombie.isDead()) {
            zombie.setRunning(true);
        }
    }

    private static boolean hasSprinterMovement(IsoZombie zombie) {
        String walkType = zombie.getWalkType();
        return !zombie.isCrawling()
                && zombie.isCanWalk()
                && zombie.getSpeedType() == SPRINTER_SPEED_TYPE
                && isSprinterWalkType(walkType);
    }

    private static boolean hasStandingSpeedType(IsoZombie zombie, int speedType) {
        String walkType = zombie.getWalkType();
        if (zombie.isCrawling() || !zombie.isCanWalk()
                || zombie.getSpeedType() != speedType) {
            return false;
        }
        if (speedType == SHAMBLER_SPEED_TYPE) {
            return isShamblerWalkType(walkType);
        }
        return !isShamblerWalkType(walkType) && !isSprinterWalkType(walkType);
    }

    private static void repairRemoteSprinterType(IsoZombie zombie) {
        String walkType = zombie.getWalkType();
        if (walkType == null) {
            throw new IllegalStateException("Zombie walk type is required");
        }
        if (!isSprinterWalkType(walkType)) {
            zombie.setWalkType(SPRINTER_WALK_PREFIX);
        }
        if (zombie.getSpeedType() != SPRINTER_SPEED_TYPE) {
            zombie.setSpeedTypeFromWalkType();
        }
        if (!zombie.isCanWalk()) {
            zombie.setCanWalk(true);
        }
    }

    private static boolean isSprinterWalkType(String walkType) {
        return walkType != null && walkType.startsWith(SPRINTER_WALK_PREFIX);
    }

    private static boolean isShamblerWalkType(String walkType) {
        return walkType != null && walkType.startsWith(SHAMBLER_WALK_PREFIX);
    }

    private static void applyAttributes(IsoZombie zombie, ZombieState state) {
        zombie.setHealth(state.health());
        zombie.sight = state.sight();
        zombie.hearing = state.hearing();
        if (state.cognition() != null) {
            applyFeatureValues(
                    zombie,
                    state.cognition(),
                    state.strength(),
                    state.memory());
        }
    }

    private static void applyAnimation(IsoZombie zombie, ZombieState state) {
        if (state.animationVariable() != null) {
            applyAnimationSpeed(
                    zombie,
                    requireAnimator(zombie),
                    state.animationVariable(),
                    state.animationSpeedScale());
        }
    }

    private static void applyFeatureValues(
            IsoZombie zombie,
            int cognition,
            int strength,
            int memory) {
        zombie.cognition = cognition;
        zombie.strength = strength;
        zombie.memory = memory;
    }

    private static int mapStrengthProfile(int strengthProfile) {
        return switch (strengthProfile) {
            case 1 -> 5;
            case 2 -> 3;
            case 3 -> 1;
            default -> throw new IllegalArgumentException("Unknown strength profile");
        };
    }

    private static int mapCognitionProfile(int cognitionProfile) {
        return switch (cognitionProfile) {
            case 1 -> 1;
            case 2, 3 -> -1;
            default -> throw new IllegalArgumentException("Unknown cognition profile");
        };
    }

    private static int mapMemoryProfile(int memoryProfile) {
        return switch (memoryProfile) {
            case 1 -> 1250;
            case 2 -> 800;
            case 3 -> 500;
            case 4 -> 25;
            default -> throw new IllegalArgumentException("Unknown memory profile");
        };
    }

    private record ZombieState(
            String speedType,
            Float speedMod,
            String animationVariable,
            Float animationSpeedScale,
            float health,
            int sight,
            int hearing,
            Integer cognition,
            Integer strength,
            Integer memory) {
        private static ZombieState parse(KahluaTable table) {
            Objects.requireNonNull(table, "state");
            String speedType = requireSpeedType(table.rawget("speedType"));
            MotionState motion = parseMotion(table, speedType);
            FeatureState features = parseFeatures(table);
            return new ZombieState(
                    speedType,
                    motion.speedMod(),
                    motion.animationVariable(),
                    motion.animationSpeedScale(),
                    requireHealth(table.rawget("health")),
                    requireInteger(table.rawget("sight"), "sight", 1, 3),
                    requireInteger(table.rawget("hearing"), "hearing", 1, 3),
                    features.cognition(),
                    features.strength(),
                    features.memory());
        }

        private static MotionState parseMotion(KahluaTable table, String speedType) {
            return new MotionState(
                    optionalSprinterNumber(table, speedType, "speedMod"),
                    optionalSprinterVariable(table, speedType),
                    optionalSprinterNumber(table, speedType, "animationSpeedScale"));
        }

        private static FeatureState parseFeatures(KahluaTable table) {
            Integer cognition = optionalInteger(table.rawget("cognition"), "cognition", 1, 3);
            Integer strength = optionalInteger(table.rawget("strength"), "strength", 1, 3);
            Integer memory = optionalInteger(table.rawget("memory"), "memory", 1, 4);
            validateFeatureGroup(cognition, strength, memory);
            return new FeatureState(
                    cognition == null ? null : mapCognitionProfile(cognition),
                    strength == null ? null : mapStrengthProfile(strength),
                    memory == null ? null : mapMemoryProfile(memory));
        }

        private static String requireSpeedType(Object rawSpeedType) {
            if (!(rawSpeedType instanceof String speedType)) {
                throw new IllegalArgumentException("speedType is required");
            }
            return switch (speedType) {
                case SPEED_TYPE_SPRINTER,
                        SPEED_TYPE_FAST_SHAMBLER,
                        SPEED_TYPE_SHAMBLER,
                        SPEED_TYPE_CRAWLER -> speedType;
                default -> throw new IllegalArgumentException("Unknown speed type");
            };
        }

        private static Float optionalSprinterNumber(
                KahluaTable table,
                String speedType,
                String fieldName) {
            Object rawNumber = table.rawget(fieldName);
            if (!SPEED_TYPE_SPRINTER.equals(speedType)) {
                rejectNonSprinterField(rawNumber, fieldName);
                return null;
            }
            return requirePositiveNumber(rawNumber, fieldName);
        }

        private static String optionalSprinterVariable(KahluaTable table, String speedType) {
            Object rawVariable = table.rawget("animationVariable");
            if (!SPEED_TYPE_SPRINTER.equals(speedType)) {
                rejectNonSprinterField(rawVariable, "animationVariable");
                return null;
            }
            if (!(rawVariable instanceof String variable) || variable.isBlank()) {
                throw new IllegalArgumentException("animationVariable is required");
            }
            return variable;
        }

        private static void rejectNonSprinterField(Object rawValue, String fieldName) {
            if (rawValue != null) {
                throw new IllegalArgumentException(
                        fieldName + " is only valid for sprinters");
            }
        }

        private static float requireHealth(Object rawHealth) {
            float health = requireFiniteNumber(rawHealth, "health");
            if (health < HEALTH_MINIMUM || health > HEALTH_MAXIMUM) {
                throw new IllegalArgumentException("Health is out of range");
            }
            return health;
        }

        private static Float requirePositiveNumber(Object rawNumber, String name) {
            float number = requireFiniteNumber(rawNumber, name);
            if (number <= 0.0F) {
                throw new IllegalArgumentException(name + " must be positive");
            }
            return number;
        }

        private static float requireFiniteNumber(Object rawNumber, String name) {
            if (!(rawNumber instanceof Number number)) {
                throw new IllegalArgumentException(name + " is required");
            }
            float numericValue = number.floatValue();
            if (!Float.isFinite(numericValue)) {
                throw new IllegalArgumentException(name + " must be finite");
            }
            return numericValue;
        }

        private static Integer optionalInteger(
                Object rawNumber,
                String name,
                int minimum,
                int maximum) {
            if (rawNumber == null) {
                return null;
            }
            return requireInteger(rawNumber, name, minimum, maximum);
        }

        private static int requireInteger(
                Object rawNumber,
                String name,
                int minimum,
                int maximum) {
            if (!(rawNumber instanceof Number number)) {
                throw new IllegalArgumentException(name + " is required");
            }
            double numericValue = number.doubleValue();
            if (!Double.isFinite(numericValue)
                    || numericValue != Math.rint(numericValue)) {
                throw new IllegalArgumentException(name + " must be an integer");
            }
            int integerValue = (int) numericValue;
            if (integerValue < minimum || integerValue > maximum) {
                throw new IllegalArgumentException(name + " is out of range");
            }
            return integerValue;
        }

        private static void validateFeatureGroup(
                Integer cognition,
                Integer strength,
                Integer memory) {
            boolean anyProfile = cognition != null || strength != null || memory != null;
            boolean allProfiles = cognition != null && strength != null && memory != null;
            if (anyProfile && !allProfiles) {
                throw new IllegalArgumentException(
                        "Cognition, strength and memory are required together");
            }
        }

        private record MotionState(
                Float speedMod,
                String animationVariable,
                Float animationSpeedScale) {
        }

        private record FeatureState(
                Integer cognition,
                Integer strength,
                Integer memory) {
        }
    }
}
