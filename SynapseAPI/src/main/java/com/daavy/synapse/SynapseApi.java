package com.daavy.synapse;

import me.zed_0xff.zombie_buddy.Exposer;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoZombie;

@Exposer.LuaClass(name = "Synapse.API")
public final class SynapseApi {
    private static final int API_VERSION = 1;

    private SynapseApi() {
    }

    public static int getApiVersion() {
        return API_VERSION;
    }

    public static void applyAnimationSpeed(
            IsoZombie zombie,
            String variable,
            float speedScale) {
        RandomZeds.applyAnimationSpeed(zombie, variable, speedScale);
    }

    public static void applyZombieFeatures(
            IsoZombie zombie,
            int cognitionProfile,
            int strengthProfile,
            int memoryProfile) {
        RandomZeds.applyZombieFeatures(
                zombie, cognitionProfile, strengthProfile, memoryProfile);
    }

    public static void applyZombieState(IsoZombie zombie, KahluaTable table) {
        RandomZeds.applyZombieState(zombie, table);
    }
}
