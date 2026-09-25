package com.daavy.synapse;

import me.zed_0xff.zombie_buddy.Exposer;
import zombie.characters.IsoZombie;

@Exposer.LuaClass(name = "Synapse.API")
public final class SynapseApi {
    private static final int API_VERSION = 2;

    private SynapseApi() {
    }

    public static int getApiVersion() {
        return API_VERSION;
    }

    public static void applyZombieFeatures(
            IsoZombie zombie,
            int cognitionProfile,
            int strengthProfile,
            int memoryProfile) {
        RandomZeds.applyZombieFeatures(
                zombie, cognitionProfile, strengthProfile, memoryProfile);
    }

    public static void applyZombieSenses(IsoZombie zombie, int sight, int hearing) {
        RandomZeds.applyZombieSenses(zombie, sight, hearing);
    }
}
