package com.opencapture.monitorui

/** Stable catalog order breaks equal usage scores; no brand or tool taxonomy is needed. */
object MonitorAssistUsage {
    fun <T> ranked(tools: List<T>, counts: Map<T, Int>): List<T> = tools.withIndex()
        .sortedWith(compareByDescending<IndexedValue<T>> { counts[it.value] ?: 0 }.thenBy { it.index })
        .map { it.value }

    fun <T> recording(tool: T, counts: Map<T, Int>): Map<T, Int> =
        counts + (tool to ((counts[tool] ?: 0).coerceAtMost(Int.MAX_VALUE - 1) + 1))
}
