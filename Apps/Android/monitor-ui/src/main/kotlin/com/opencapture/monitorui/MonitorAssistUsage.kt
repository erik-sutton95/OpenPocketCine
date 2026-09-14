package com.opencapture.monitorui

import kotlin.math.pow

/** Frecency ranking for collapsed View Assist favorites (36-hour half-life). */
data class MonitorToolUsageState(
    val scores: Map<String, Double> = emptyMap(),
    val counts: Map<String, Int> = emptyMap(),
    val lastUsed: Map<String, Double> = emptyMap(),
    val clock: Double = 0.0,
) {
    fun decayed(now: Double): MonitorToolUsageState {
        if (!now.isFinite()) return this
        if (clock <= 0.0) return copy(clock = now)
        if (now <= clock) return this
        val factor = 0.5.pow((now - clock) / HALF_LIFE)
        if (factor >= 1.0) return copy(clock = now)
        return copy(scores = scores.mapValues { it.value * factor }, clock = now)
    }

    fun recording(id: String, now: Double): MonitorToolUsageState {
        val decayed = decayed(now)
        val previous = decayed.counts[id] ?: 0
        return decayed.copy(
            scores = decayed.scores + (id to (decayed.scores[id] ?: 0.0) + 1.0),
            counts = decayed.counts + (id to if (previous == Int.MAX_VALUE) previous else previous + 1),
            lastUsed = decayed.lastUsed + (id to now),
        )
    }

    fun ranked(catalog: List<String>, seed: Map<String, Int> = emptyMap(), now: Double): List<String> {
        val snap = decayed(now)
        val unique = catalog.withIndex().distinctBy { it.value }
        if (snap.counts.isEmpty()) {
            return unique.sortedWith(
                compareByDescending<IndexedValue<String>> { seed[it.value] ?: 0 }.thenBy { it.index },
            ).map { it.value }
        }
        return unique.sortedWith(
            compareByDescending<IndexedValue<String>> { snap.scores[it.value] ?: 0.0 }
                .thenByDescending { snap.lastUsed[it.value] ?: 0.0 }
                .thenBy { it.index },
        ).map { it.value }
    }

    companion object {
        const val HALF_LIFE = 36.0 * 3600.0
    }
}

object MonitorAssistUsage {
    fun <T> ranked(
        tools: List<T>,
        idOf: (T) -> String,
        usage: MonitorToolUsageState,
        seed: Map<String, Int>,
        now: Double = System.currentTimeMillis() / 1000.0,
    ): List<T> {
        val byId = tools.associateBy(idOf)
        return usage.ranked(tools.map(idOf), seed, now).mapNotNull { byId[it] }
    }
}
