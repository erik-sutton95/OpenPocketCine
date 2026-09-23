package com.opencapture.openpocketcine

import java.util.Random

/** Bounded, nonblocking local video loss. The instrumentation test is its only owner. */
internal class FeedStressFault(seed: Long, private val nowMs: () -> Long) {
    private val random = Random(seed)
    private var expires = 0L
    private var offered = 0
    private var profile = "loss"
    @Volatile var dropped = 0L
        private set

    @Synchronized fun arm(profile: String) {
        require(profile in PROFILES)
        this.profile = profile
        offered = 0
        expires = nowMs() + 8_000
    }

    @Synchronized fun disarm() { expires = 0 }

    @Synchronized fun admit(): Boolean {
        if (nowMs() >= expires) return true
        offered += 1
        val drop = when (profile) {
            "loss" -> random.nextInt(100) < 10
            "burst" -> offered % 40 < 8
            "combined" -> offered % 40 < 8 || random.nextInt(100) < 10
            else -> false
        }
        if (drop) dropped += 1
        return !drop
    }

    companion object { val PROFILES = setOf("loss", "burst", "combined") }
}
