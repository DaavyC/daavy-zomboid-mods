package com.daavy.synapse;

import java.util.Objects;

import me.zed_0xff.zombie_buddy.Exposer;
import zombie.characters.IsoZombie;

@Exposer.LuaClass(name = "Synapse.API.RandomZeds")
public final class RandomZeds {
    private RandomZeds() {
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
        zombie.cognition = cognition;
        zombie.strength = strength;
        zombie.memory = memory;
    }

    public static void applyZombieSenses(IsoZombie zombie, int sight, int hearing) {
        Objects.requireNonNull(zombie, "zombie");
        int validatedSight = requireProfile(sight, "sight", 3);
        int validatedHearing = requireProfile(hearing, "hearing", 3);
        zombie.sight = validatedSight;
        zombie.hearing = validatedHearing;
    }

    private static int mapStrengthProfile(int profile) {
        return switch (requireProfile(profile, "strength", 3)) {
            case 1 -> 5;
            case 2 -> 3;
            case 3 -> 1;
            default -> throw new IllegalStateException("Unknown strength profile");
        };
    }

    private static int mapCognitionProfile(int profile) {
        return switch (requireProfile(profile, "cognition", 3)) {
            case 1 -> 1;
            case 2, 3 -> -1;
            default -> throw new IllegalStateException("Unknown cognition profile");
        };
    }

    private static int mapMemoryProfile(int profile) {
        return switch (requireProfile(profile, "memory", 4)) {
            case 1 -> 1250;
            case 2 -> 800;
            case 3 -> 500;
            case 4 -> 25;
            default -> throw new IllegalStateException("Unknown memory profile");
        };
    }

    private static int requireProfile(int profile, String name, int maximum) {
        if (profile < 1 || profile > maximum) {
            throw new IllegalArgumentException("Unknown " + name + " profile");
        }
        return profile;
    }
}
