package com.opencapture.openpocketcine.session

import kotlin.math.ceil

/** Zoom visits each saved amount even when the angular path rounds B. */
internal data class GimbalZoomPath(val legs: List<Leg>) {
    data class Leg(val from: Double, val to: Double, val duration: Double)

    constructor(program: GimbalProgram) : this(if (program.a != null && program.b != null) {
        listOfNotNull(Leg(program.a.zoom, program.b.zoom, program.durationAB),
            program.c?.let { Leg(program.b.zoom, it.zoom, program.durationBC) })
    } else emptyList())

    val duration: Double get() = legs.sumOf { it.duration }
    val end: Double get() = legs.lastOrNull()?.to ?: 1.0

    fun position(time: Double, lookAhead: Double = 0.05): Double {
        var remaining = time.coerceAtLeast(0.0)
        for (leg in legs) {
            if (remaining < leg.duration - 1e-9) {
                val fraction = minOf(1.0, (remaining + lookAhead) / leg.duration)
                return leg.from + (leg.to - leg.from) * fraction
            }
            remaining -= leg.duration
        }
        return end
    }

    fun nativeDemand(time: Double): NativeProgramZoomDemand {
        var remaining = time.coerceAtLeast(0.0)
        for (leg in legs) {
            if (remaining < leg.duration - 1e-9) {
                return NativeProgramZoom.demand(leg.from, leg.to, leg.duration, remaining)
            }
            remaining = maxOf(0.0, remaining - leg.duration)
        }
        return NativeProgramZoomDemand(NativeProgramZoomCommand.Track(end), end)
    }

    fun remaining(time: Double, zoom: Double, quantized: Boolean): GimbalZoomPath {
        val next = legs.toMutableList()
        var consumed = time.coerceAtLeast(0.0)
        while (next.size > 1 && consumed >= next.first().duration - 1e-9) consumed -= next.removeAt(0).duration
        if (next.isEmpty()) return this
        val remaining = maxOf(0.0, next.first().duration - consumed)
        next[0] = next.first().copy(from = zoom,
            duration = if (quantized) maxOf(0.1, ceil((remaining - 1e-9) * 10) / 10) else remaining)
        val total = next.sumOf { it.duration }
        if (total < 0.1) next[0] = next.first().copy(duration = next.first().duration + 0.1 - total)
        return GimbalZoomPath(next)
    }
}
