package com.opencapture.openpocketcine.session

import java.util.Locale

/** Low-rate measurements of separate live stages. No camera content or identity. */
internal class LivePipelineCadence(private val nowNs: () -> Long = System::nanoTime) {
    enum class Stage { ACK, VIDEO, AU, SUBMIT, OUTPUT, PRESENT }
    private class Counter(var count: Int = 0, var last: Long? = null, var maxGap: Long = 0)
    private val counters = Stage.entries.associateWith { Counter() }
    private var started = nowNs()
    private var queued = 0
    private var queuePeak = 0
    private var queueDelayNs = 0L
    private var inputMisses = 0

    @Synchronized fun note(stage: Stage) {
        val now = nowNs()
        val c = counters.getValue(stage)
        c.maxGap = maxOf(c.maxGap, (now - (c.last ?: started)).coerceAtLeast(0))
        c.last = now
        c.count += 1
    }

    @Synchronized fun queued(): Long {
        queued += 1
        queuePeak = maxOf(queuePeak, queued)
        return nowNs()
    }

    @Synchronized fun dequeued(enqueuedAt: Long) {
        queued = (queued - 1).coerceAtLeast(0)
        queueDelayNs = maxOf(queueDelayNs, (nowNs() - enqueuedAt).coerceAtLeast(0))
    }

    @Synchronized fun inputMiss() { inputMisses += 1 }

    @Synchronized fun drain(): String? {
        val now = nowNs()
        val seconds = (now - started) / 1e9
        if (seconds < 1.0) return null
        val line = buildString {
            append(String.format(Locale.US, "feed: cadence window=%.2fs", seconds))
            for ((stage, c) in counters) {
                val age = c.last?.let { (now - it).coerceAtLeast(0) / 1e6 } ?: -1.0
                val gap = maxOf(c.maxGap, (now - (c.last ?: started)).coerceAtLeast(0))
                append(String.format(Locale.US, " %s=%.1f/s gap=%.1fms age=%.1fms",
                    stage.name.lowercase(Locale.US), c.count / seconds, gap / 1e6, age))
                c.count = 0
                c.maxGap = 0
            }
            append(String.format(Locale.US, " queue=%d peak=%d wait=%.1fms inputMiss=%d",
                queued, queuePeak, queueDelayNs / 1e6, inputMisses))
        }
        started = now
        queuePeak = queued
        queueDelayNs = 0
        inputMisses = 0
        return line
    }
}

/** New source images establish a recovered picture; repainting one does not. */
internal class PresentedFrameClock {
    private var sourceTime: Long? = null
    private var minimumSourceNs = Long.MIN_VALUE
    @Volatile var lastPresentedAt: Long? = null
        private set
    @Synchronized fun note(sourceNs: Long, nowMs: Long): Boolean {
        if (sourceNs < minimumSourceNs || sourceTime?.let { sourceNs <= it } == true) return false
        sourceTime = sourceNs
        lastPresentedAt = nowMs
        return true
    }
    @Synchronized fun beginProbe(sourceNowNs: Long, nowMs: Long): Long {
        beginEpoch(sourceNowNs)
        return nowMs
    }
    @Synchronized fun beginEpoch(minimumSourceNs: Long) { this.minimumSourceNs = minimumSourceNs }
    @Synchronized fun reset(minimumSourceNs: Long = Long.MIN_VALUE) {
        sourceTime = null
        lastPresentedAt = null
        this.minimumSourceNs = minimumSourceNs
    }
}
