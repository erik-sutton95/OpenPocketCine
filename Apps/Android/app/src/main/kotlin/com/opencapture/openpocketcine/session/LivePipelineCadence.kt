package com.opencapture.openpocketcine.session

import java.util.Locale

/** Beyond this a transit sample is a stall, not transit. */
private const val TRANSIT_SANITY_LIMIT_NS = 2_000_000_000L

/** Low-rate measurements of separate live stages. No camera content or identity. */
internal class LivePipelineCadence(private val nowNs: () -> Long = System::nanoTime) {
    enum class Stage { ACK, VIDEO, AU, SUBMIT, OUTPUT, PRESENT }

    /**
     * How long one picture took between two stages. The [Stage] counters give
     * rates and gaps, which say whether the pipeline flows — not how far behind
     * the glass it runs. A leg follows a single frame.
     */
    enum class Leg { DECODE, PRESENT }

    private class Counter(var count: Int = 0, var last: Long? = null, var maxGap: Long = 0)

    /** Mean and max together: max alone is one hiccup, mean alone hides it. */
    private class Transit(var count: Int = 0, var totalNs: Long = 0, var maxNs: Long = 0) {
        fun note(ns: Long) {
            // A negative sample means the clocks disagree and a multi-second one
            // is a stall, which the gap counters already report. Neither is transit.
            if (ns < 0 || ns > TRANSIT_SANITY_LIMIT_NS) return
            count += 1
            totalNs += ns
            maxNs = maxOf(maxNs, ns)
        }

        fun meanMs(): Double = if (count == 0) -1.0 else totalNs.toDouble() / count / 1e6

        fun maxMs(): Double = if (count == 0) -1.0 else maxNs / 1e6

        fun reset() {
            count = 0
            totalNs = 0
            maxNs = 0
        }
    }

    private val counters = Stage.entries.associateWith { Counter() }
    private val transits = Leg.entries.associateWith { Transit() }
    private var started = nowNs()
    private var queued = 0
    private var queuePeak = 0
    private var queueDelayNs = 0L
    private var inputMisses = 0

    /**
     * Stamps of decoded pictures not yet reported presented, oldest first.
     *
     * A count cannot answer this. With one picture in flight at every boundary
     * the count reads one window after window, while the picture behind it is a
     * different one each time — a healthy pipeline that a count calls stalled.
     * The stamp says which picture is waiting, so "still that one" and "a new
     * one" stop looking alike.
     */
    private val pendingStamps = LinkedHashSet<Long>()

    /** [pendingStamps] as the previous window closed. */
    private var pendingAtLastClose = emptySet<Long>()

    /**
     * Counts a stage with no picture to name.
     *
     * OUTPUT and PRESENT do not come through here: they carry the decoder's
     * stamp, via [noteOutput] and [notePresented], because the drop count needs
     * to know *which* picture is waiting.
     */
    @Synchronized fun note(stage: Stage) {
        val now = nowNs()
        val c = counters.getValue(stage)
        c.maxGap = maxOf(c.maxGap, (now - (c.last ?: started)).coerceAtLeast(0))
        c.last = now
        c.count += 1
    }

    /**
     * A decoded picture left the codec, stamped as it was released for display.
     *
     * [stampNs] is the value handed to `releaseOutputBuffer`; every present path
     * gives that same stamp back to [notePresented], which is what lets a drop
     * name a picture rather than a shortfall.
     */
    @Synchronized fun noteOutput(stampNs: Long) {
        note(Stage.OUTPUT)
        pendingStamps.add(stampNs)
    }

    /** The picture released with [stampNs] reached a present. */
    @Synchronized fun notePresented(stampNs: Long) {
        note(Stage.PRESENT)
        pendingStamps.remove(stampNs)
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

    @Synchronized fun noteTransit(leg: Leg, ns: Long) { transits.getValue(leg).note(ns) }

    data class Window(
        val seconds: Double,
        val hz: Map<Stage, Double>,
        val ageMs: Map<Stage, Double>,
        val gapMs: Map<Stage, Double>,
        val queue: Int,
        val peak: Int,
        val waitMs: Double,
        val inputMiss: Int,
        val transitMeanMs: Map<Leg, Double>,
        val transitMaxMs: Map<Leg, Double>,
        /**
         * Pictures the decoder released that never reached the glass — the
         * renderer takes the newest buffer and lets older ones go. Delay and
         * drops feel alike and are fixed differently.
         *
         * Pictures are tracked by the stamp they were released with, and one is
         * only called dropped once that stamp has survived a whole window — so
         * this reports the pictures lost during the *previous* window. A picture
         * decoded near a boundary is normally presented a few milliseconds
         * later; counting per window called every one of those a drop, and
         * counting the backlog instead called a pipeline with one picture always
         * in flight a drop too, since the tally never noticed the picture
         * waiting had changed.
         */
        val dropped: Int,
    )

    /** The LIVE keepalive closes windows even when Media suppresses publication. */
    fun takeKeepaliveWindow(live: Boolean, isBrowsingMedia: Boolean): Window? {
        if (!live) return null
        val window = takeWindow()
        return if (isBrowsingMedia) null else window
    }

    @Synchronized fun takeWindow(): Window? {
        val now = nowNs()
        val seconds = (now - started) / 1e9
        if (seconds < 1.0) return null
        val hz = linkedMapOf<Stage, Double>()
        val ageMs = linkedMapOf<Stage, Double>()
        val gapMs = linkedMapOf<Stage, Double>()
        val counts = linkedMapOf<Stage, Int>()
        for ((stage, c) in counters) {
            hz[stage] = c.count / seconds
            ageMs[stage] = c.last?.let { (now - it).coerceAtLeast(0) / 1e6 } ?: -1.0
            val gap = maxOf(c.maxGap, (now - (c.last ?: started)).coerceAtLeast(0))
            gapMs[stage] = gap / 1e6
            counts[stage] = c.count
            c.count = 0
            c.maxGap = 0
        }
        val transitMeanMs = linkedMapOf<Leg, Double>()
        val transitMaxMs = linkedMapOf<Leg, Double>()
        for ((leg, t) in transits) {
            transitMeanMs[leg] = t.meanMs()
            transitMaxMs[leg] = t.maxMs()
            t.reset()
        }
        // A picture counts as dropped once it has outlived a whole window: the
        // same stamp was waiting at the previous close and is waiting still. One
        // in flight across the boundary is not that, however steady the backlog
        // looks, because the stamp waiting now is not the stamp from before.
        // Reporting forgets it, so a picture is announced once and a standing
        // shortfall does not repeat every second.
        val dropped = pendingStamps.count { it in pendingAtLastClose }
        pendingStamps.removeAll(pendingAtLastClose)
        pendingAtLastClose = pendingStamps.toSet()
        val window =
            Window(
                seconds = seconds,
                hz = hz,
                ageMs = ageMs,
                gapMs = gapMs,
                queue = queued,
                peak = queuePeak,
                waitMs = queueDelayNs / 1e6,
                inputMiss = inputMisses,
                transitMeanMs = transitMeanMs,
                transitMaxMs = transitMaxMs,
                dropped = dropped,
            )
        started = now
        queuePeak = queued
        queueDelayNs = 0
        inputMisses = 0
        return window
    }

    @Synchronized fun drain(): String? {
        val window = takeWindow() ?: return null
        return format(window)
    }

    fun format(window: Window): String = buildString {
        append(String.format(Locale.US, "feed: cadence window=%.2fs", window.seconds))
        for (stage in Stage.entries) {
            val hz = window.hz[stage] ?: 0.0
            val gap = window.gapMs[stage] ?: 0.0
            val age = window.ageMs[stage] ?: -1.0
            append(
                String.format(
                    Locale.US,
                    " %s=%.1f/s gap=%.1fms age=%.1fms",
                    stage.name.lowercase(Locale.US),
                    hz,
                    gap,
                    age,
                ),
            )
        }
        append(
            String.format(
                Locale.US,
                " queue=%d peak=%d wait=%.1fms inputMiss=%d",
                window.queue,
                window.peak,
                window.waitMs,
                window.inputMiss,
            ),
        )
        // mean/max per leg; -1 means the leg took no sample this window.
        for (leg in Leg.entries) {
            append(
                String.format(
                    Locale.US,
                    " %sMs=%.1f/%.1f",
                    leg.name.lowercase(Locale.US),
                    window.transitMeanMs[leg] ?: -1.0,
                    window.transitMaxMs[leg] ?: -1.0,
                ),
            )
        }
        append(String.format(Locale.US, " drop=%d", window.dropped))
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
